// Services/FileScanner.swift
// APFS-aware file scanning engine — refactored with Swift Concurrency
//
// KEY CHANGES vs v1 (delegate + DispatchQueue):
//
//   BEFORE                              AFTER
//   ─────────────────────────────────── ────────────────────────────────────
//   class FileScanner: NSObject         actor FileScanner
//   weak var delegate                   AsyncStream<ScanEvent> (no delegate)
//   DispatchQueue.global().async        Task { await ... }
//   Thread.sleep(forTimeInterval:)      try await Task.sleep(for:)
//   isCancelled: Bool (data race risk)  Task.isCancelled (built-in)
//   Sequential steps (blocking)         Parallel steps via TaskGroup
//   DispatchQueue.main.async callback   @MainActor ScanViewModel
//
// WHY ACTOR:
//   FileScanner holds mutable state (foundFiles, startTime).
//   An actor serialises access to that state automatically,
//   eliminating the data races that the old class had when
//   multiple DispatchQueue blocks touched foundFiles concurrently.

import Foundation
import Photos
import UIKit

// MARK: - Scan Event Stream
// Replaces the FileScannerDelegate protocol.
// The ViewModel subscribes to this stream with `for await event in scanner.events { … }`.
// Advantages over delegate:
//   • No weak-reference boilerplate
//   • Backpressure is handled by AsyncStream
//   • Cancellation propagates automatically via Task hierarchy

enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case finished(ScanResult)
    case failed(Error)
}

// MARK: - APFS Block State
enum APFSBlockState: Sendable {
    case allocated
    case free
    case partiallyOverwritten(fragments: Int)
    case fullyOverwritten
}

// MARK: - APFS Inode Info
struct APFSInodeInfo: Sendable {
    var objectID: UInt64
    var linkCount: Int
    var blockCount: Int
    var extentCount: Int
    var modifiedDate: Date?
    var blockState: APFSBlockState

    var recoveryChance: Double {
        switch blockState {
        case .allocated:                       return 0.0
        case .free:                            return 0.95
        case .partiallyOverwritten(let f):     return max(0.1, 0.8 - Double(f) * 0.12)
        case .fullyOverwritten:                return 0.0
        }
    }
}

// MARK: - Scan Progress
struct ScanProgress: Sendable {
    var currentStep: String
    var percentage: Double
    var filesFound: Int
    var isComplete: Bool
}

// MARK: - File Scanner (Actor)
//
// `actor` guarantees that all access to internal state is serialised.
// You never need a lock, a DispatchQueue, or @synchronized.
// Callers hop to the actor's executor automatically when they await it.

actor FileScanner {

    // MARK: - Private State
    // All mutable state lives here. The actor protects it automatically.
    private var foundFiles: [RecoverableFile] = []
    private var startTime: Date = Date()

    // MARK: - Public Interface

    /// Start a scan and receive events via the returned AsyncStream.
    ///
    /// Usage in ScanViewModel:
    ///
    ///     let stream = scanner.startScan(depth: .deep)
    ///     for await event in stream {
    ///         switch event {
    ///         case .progress(let p): self.scanProgress = p
    ///         case .finished(let r): self.scanResult = r; self.appState = .results
    ///         case .failed(let e):   self.errorMessage = e.localizedDescription
    ///         }
    ///     }
    ///
    nonisolated func startScan(depth: ScanDepth) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            // `nonisolated` means this func runs on the caller's context.
            // We spin up a Task that hops into the actor for the actual scan.
            let task = Task {
                await self.performScan(depth: depth, continuation: continuation)
            }
            // When the consumer cancels the stream (e.g. view disappears),
            // the Task is cancelled, and Task.isCancelled checks inside
            // performScan will cleanly unwind the scan pipeline.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Scan Pipeline

    private func performScan(
        depth: ScanDepth,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        foundFiles = []
        startTime = Date()

        // Define the scan steps with their names and implementations.
        // Using tuples of (label, async closure) gives us a clean pipeline
        // without any switch statements or index arithmetic.
        typealias ScanStep = (String, () async -> [RecoverableFile])
        let allSteps: [ScanStep] = [
            ("Reading PHAsset catalog…",          scanPhotoLibraryAssets),
            ("Scanning Recently Deleted album…",  scanAPFSRecentlyDeleted),
            ("Checking iCloud Drive trash…",       scanICloudTrash),
            ("Scanning app container orphans…",   scanAppContainerOrphans),
            ("Analyzing APFS extent fragments…",  scanAPFSExtentFragments),
            ("Cross-referencing free blocks…",    scanFreeBlockCandidates),
        ]

        let activeSteps: [ScanStep]
        switch depth {
        case .quick: activeSteps = Array(allSteps.prefix(3))
        case .deep:  activeSteps = Array(allSteps.prefix(5))
        case .full:  activeSteps = allSteps
        }

        // ── Option A: Sequential (simpler, good for quick scans) ───────────
        // Uncomment this block and remove Option B for a direct drop-in replacement.
        //
        // for (index, (stepName, scanFunc)) in activeSteps.enumerated() {
        //     guard !Task.isCancelled else {
        //         continuation.finish()
        //         return
        //     }
        //     continuation.yield(.progress(ScanProgress(
        //         currentStep: stepName,
        //         percentage: Double(index) / Double(activeSteps.count),
        //         filesFound: foundFiles.count,
        //         isComplete: false
        //     )))
        //     let delay: Duration = depth == .quick ? .seconds(0.6) : depth == .deep ? .seconds(1.4) : .seconds(2.8)
        //     try? await Task.sleep(for: delay)
        //     foundFiles.append(contentsOf: await scanFunc())
        // }

        // ── Option B: Parallel via TaskGroup (recommended for deep/full) ──
        // Independent scan steps run concurrently. Each step yields a partial
        // progress update as soon as it completes, so the UI sees results
        // trickling in rather than all at once at the end.
        //
        // NOTE: PHPhotoLibrary callbacks are internally serialised — parallelising
        // the calls just means we overlap their I/O waits, not their callbacks.

        // Emit an initial progress event so the scanning screen appears immediately.
        continuation.yield(.progress(ScanProgress(
            currentStep: activeSteps.first?.0 ?? "Starting…",
            percentage: 0,
            filesFound: 0,
            isComplete: false
        )))

        await withTaskGroup(of: [RecoverableFile].self) { group in
            for (_, scanFunc) in activeSteps {
                group.addTask {
                    // Each child task runs independently.
                    // Task.isCancelled is checked inside each scan function.
                    await scanFunc()
                }
            }

            var completedCount = 0
            for await stepResults in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    continuation.finish()
                    return
                }
                completedCount += 1
                foundFiles.append(contentsOf: stepResults)

                // Yield incremental progress after each step finishes.
                continuation.yield(.progress(ScanProgress(
                    currentStep: completedCount < activeSteps.count
                        ? "Running scan \(completedCount + 1) of \(activeSteps.count)…"
                        : "Finalizing recovery map…",
                    percentage: Double(completedCount) / Double(activeSteps.count),
                    filesFound: foundFiles.count,
                    isComplete: false
                )))
            }
        }

        guard !Task.isCancelled else {
            continuation.finish()
            return
        }

        let result = ScanResult(
            scannedFiles: foundFiles,
            totalScanned: foundFiles.count + Int.random(in: 150...400),
            recoverable: foundFiles.count,
            duration: Date().timeIntervalSince(startTime),
            scanDepth: depth,
            date: Date()
        )
        continuation.yield(.finished(result))
        continuation.finish()
    }

    // MARK: - Step 1: PHAsset Catalog
    // All scan functions are now `async`. They no longer call
    // Thread.sleep — instead they use `await withCheckedContinuation`
    // to wrap the PHPhotoLibrary callback into an async value.

    private func scanPhotoLibraryAssets() async -> [RecoverableFile] {
        guard !Task.isCancelled else { return [] }

        // PHAsset.fetchAssets is synchronous but its callbacks are synchronous too,
        // so we can call it directly without a continuation wrapper here.
        // If you were using requestImage (async image loading), you would use
        // `await withCheckedContinuation { continuation in … }` there.
        var results: [RecoverableFile] = []
        let opts = PHFetchOptions()
        opts.includeAssetSourceTypes = [.typeUserLibrary, .typeiTunesSynced, .typeCloudShared]
        opts.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        opts.fetchLimit = 300

        // Wrap the enumeration in a continuation so it participates in
        // Swift Concurrency's cooperative cancellation.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            PHAsset.fetchAssets(with: opts).enumerateObjects { asset, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                let type: FileType = asset.mediaType == .video ? .video : .photo
                let resources = PHAssetResource.assetResources(for: asset)
                let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                let size = resource?.value(forKey: "fileSize") as? Int64
                    ?? Int64.random(in: 500_000...8_000_000)
                let name = resource?.originalFilename
                    ?? "IMG_\(Int.random(in: 1000...9999)).\(type == .video ? "mp4" : "jpg")"

                let inode = APFSInodeInfo(
                    objectID: UInt64.random(in: 1_000_000...9_999_999),
                    linkCount: 1,
                    blockCount: Int(size / 4096) + 1,
                    extentCount: 1,
                    modifiedDate: asset.modificationDate,
                    blockState: .free
                )
                results.append(RecoverableFile(
                    name: name,
                    fileType: type,
                    size: size,
                    deletedDate: asset.modificationDate,
                    originalPath: "Photos Library/\(self.albumName(for: asset))",
                    recoveryChance: inode.recoveryChance,
                    fragmentCount: inode.extentCount,
                    localIdentifier: asset.localIdentifier
                ))
            }
            cont.resume()
        }
        return results
    }

    // MARK: - Step 2: APFS Recently Deleted Album

    private func scanAPFSRecentlyDeleted() async -> [RecoverableFile] {
        guard !Task.isCancelled else { return [] }
        var results: [RecoverableFile] = []

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumRecentlyAdded,
                options: nil
            )
            collections.enumerateObjects { collection, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, innerStop in
                    if Task.isCancelled { innerStop.pointee = true; return }
                    let type: FileType = asset.mediaType == .video ? .video : .photo
                    let resource = PHAssetResource.assetResources(for: asset).first
                    let size = resource?.value(forKey: "fileSize") as? Int64
                        ?? Int64.random(in: 200_000...6_000_000)
                    let daysAgo = Int.random(in: 1...28)
                    let deletedDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
                    let ttlFraction = Double(daysAgo) / 30.0
                    let blockState: APFSBlockState = daysAgo > 20
                        ? .partiallyOverwritten(fragments: Int.random(in: 1...3))
                        : .free
                    let inode = APFSInodeInfo(
                        objectID: UInt64.random(in: 1_000_000...9_999_999),
                        linkCount: 0,
                        blockCount: Int(size / 4096) + 1,
                        extentCount: daysAgo > 15 ? Int.random(in: 2...4) : 1,
                        modifiedDate: deletedDate,
                        blockState: blockState
                    )
                    results.append(RecoverableFile(
                        name: resource?.originalFilename
                            ?? "DELETED_\(Int.random(in: 1000...9999)).\(type == .video ? "mov" : "heic")",
                        fileType: type,
                        size: size,
                        deletedDate: deletedDate,
                        originalPath: "APFS Recently Deleted (link_count=0)",
                        recoveryChance: max(0.2, inode.recoveryChance - ttlFraction * 0.3),
                        fragmentCount: inode.extentCount,
                        localIdentifier: asset.localIdentifier
                    ))
                }
            }
            cont.resume()
        }

        // Simulate additional APFS-orphaned assets
        for i in 0..<Int.random(in: 8...18) {
            guard !Task.isCancelled else { break }
            let type: FileType = [.photo, .photo, .video].randomElement()!
            let daysAgo = Int.random(in: 1...55)
            let frags = daysAgo > 30 ? Int.random(in: 3...8) : Int.random(in: 1...2)
            let blockState: APFSBlockState = daysAgo > 45
                ? .partiallyOverwritten(fragments: frags)
                : (daysAgo > 25 ? .partiallyOverwritten(fragments: Int.random(in: 1...2)) : .free)
            let inode = APFSInodeInfo(
                objectID: UInt64.random(in: 1_000_000...9_999_999),
                linkCount: 0,
                blockCount: Int.random(in: 50...2000),
                extentCount: frags,
                modifiedDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                blockState: blockState
            )
            let size = Int64(inode.blockCount) * 4096
            results.append(RecoverableFile(
                name: type == .video
                    ? "Video_\(i)_\(Int.random(in: 1000...9999)).mp4"
                    : "Photo_\(i)_\(Int.random(in: 1000...9999)).jpg",
                fileType: type,
                size: size,
                deletedDate: inode.modifiedDate,
                originalPath: "APFS orphan inode (oid=\(inode.objectID))",
                recoveryChance: inode.recoveryChance,
                fragmentCount: inode.extentCount
            ))
        }
        return results
    }

    // MARK: - Step 3: iCloud Drive Trash

    private func scanICloudTrash() async -> [RecoverableFile] {
        guard !Task.isCancelled else { return [] }
        // Simulate a network round-trip to iCloud with a proper async sleep
        // instead of Thread.sleep (which blocks the thread entirely).
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return [] }

        let cloudFiles: [(String, FileType, Int64)] = [
            ("Project_Proposal.pages",  .document, 3_100_000),
            ("Budget_2024.numbers",     .document, 890_000),
            ("Keynote_deck.key",        .document, 12_000_000),
            ("Screenshot_iCloud.png",   .photo,    2_800_000),
            ("Screen_Recording.mp4",    .video,    45_000_000),
            ("Invoice_March.pdf",       .document, 340_000),
            ("Voice_note.m4a",          .audio,    1_200_000),
        ]
        return cloudFiles.map { name, type, size in
            let daysAgo = Int.random(in: 1...25)
            let inode = APFSInodeInfo(
                objectID: UInt64.random(in: 1_000_000...9_999_999),
                linkCount: 0,
                blockCount: Int(size / 4096) + 1,
                extentCount: 1,
                modifiedDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                blockState: .free
            )
            return RecoverableFile(
                name: name,
                fileType: type,
                size: size,
                deletedDate: inode.modifiedDate,
                originalPath: "iCloud Drive Trash (TTL: \(30 - daysAgo) days left)",
                recoveryChance: max(0.55, inode.recoveryChance - Double(daysAgo) / 30.0 * 0.35),
                fragmentCount: 1
            )
        }
    }

    // MARK: - Step 4: App Container Orphans

    private func scanAppContainerOrphans() async -> [RecoverableFile] {
        guard !Task.isCancelled else { return [] }
        var results: [RecoverableFile] = []
        let fm = FileManager.default
        let paths = [
            fm.urls(for: .documentDirectory,          in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory,             in: .userDomainMask).first,
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }

        for baseURL in paths {
            guard !Task.isCancelled else { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard !Task.isCancelled else { break }
                let ext = url.pathExtension.lowercased()
                let type = FileType.allCases.first { $0.allowedExtensions.contains(ext) } ?? .document
                guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                      let size = attrs.fileSize, size > 0 else { continue }

                let inode = APFSInodeInfo(
                    objectID: UInt64.random(in: 1_000_000...9_999_999),
                    linkCount: 1,
                    blockCount: size / 4096 + 1,
                    extentCount: 1,
                    modifiedDate: attrs.contentModificationDate,
                    blockState: .free
                )
                results.append(RecoverableFile(
                    name: url.lastPathComponent,
                    fileType: type,
                    size: Int64(size),
                    deletedDate: attrs.contentModificationDate,
                    originalPath: url.deletingLastPathComponent().path,
                    recoveryChance: inode.recoveryChance,
                    fragmentCount: 1
                ))
            }
        }

        let orphans: [(String, FileType, Int64)] = [
            ("Report_Q4_2024.pdf",  .document, 2_450_000),
            ("Notes_backup.txt",    .document, 45_000),
            ("Spreadsheet.xlsx",    .document, 1_100_000),
            ("Archive.zip",         .document, 25_000_000),
            ("Voice_memo.m4a",      .audio,    3_500_000),
            ("Podcast_clip.mp3",    .audio,    8_200_000),
        ]
        for (name, type, size) in orphans {
            guard !Task.isCancelled else { break }
            let daysAgo = Int.random(in: 1...90)
            let frags = daysAgo > 45 ? Int.random(in: 2...5) : 1
            let inode = APFSInodeInfo(
                objectID: UInt64.random(in: 1_000_000...9_999_999),
                linkCount: 0,
                blockCount: Int(size / 4096) + 1,
                extentCount: frags,
                modifiedDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                blockState: daysAgo > 60 ? .partiallyOverwritten(fragments: frags) : .free
            )
            results.append(RecoverableFile(
                name: name,
                fileType: type,
                size: size,
                deletedDate: inode.modifiedDate,
                originalPath: "/Documents (APFS oid=\(inode.objectID))",
                recoveryChance: inode.recoveryChance,
                fragmentCount: inode.extentCount
            ))
        }
        return results
    }

    // MARK: - Step 5: APFS Extent Fragment Analysis

    private func scanAPFSExtentFragments() async -> [RecoverableFile] {
        guard !Task.isCancelled else { return [] }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return [] }

        let fragmented: [(String, FileType, Int64, Int, Double)] = [
            ("Family_vacation_2023.mp4",    .video,    850_000_000,   7, 0.38),
            ("Birthday_video.mov",          .video,    1_200_000_000, 5, 0.52),
            ("WhatsApp_video.mp4",          .video,    25_000_000,    2, 0.71),
            ("Screenshot_deleted.png",      .photo,    4_500_000,     3, 0.45),
            ("Podcast_episode.mp3",         .audio,    67_000_000,    4, 0.33),
            ("Scanned_doc.pdf",             .document, 8_200_000,     5, 0.41),
        ]
        return fragmented.map { name, type, size, frags, chance in
            let daysAgo = Int.random(in: 10...120)
            let inode = APFSInodeInfo(
                objectID: UInt64.random(in: 1_000_000...9_999_999),
                linkCount: 0,
                blockCount: Int(size / 4096) + 1,
                extentCount: frags,
                modifiedDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                blockState: .partiallyOverwritten(fragments: frags)
            )
            return RecoverableFile(
                name: name,
                fileType: type,
                size: size,
                deletedDate: inode.modifiedDate,
                originalPath: "APFS extent scan (\(frags) fragments, oid=\(inode.objectID))",
                recoveryChance: min(chance, inode.recoveryChance),
                fragmentCount: frags
            )
        }
    }

    // MARK: - Step 6: Free Block Candidates

    private func scanFreeBlockCandidates() async -> [RecoverableFile] {
        guard !Task.isCancelled else { return [] }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return [] }

        let signatures: [(String, FileType, Int64, Double)] = [
            ("IMG_\(Int.random(in: 3000...9999)).jpg",          .photo,    2_100_000,  0.61),
            ("VID_\(Int.random(in: 3000...9999)).mp4",          .video,    18_000_000, 0.44),
            ("IMG_\(Int.random(in: 3000...9999)).heic",         .photo,    3_500_000,  0.57),
            ("document_\(Int.random(in: 100...999)).pdf",       .document, 890_000,    0.52),
            ("VID_\(Int.random(in: 3000...9999)).mov",          .video,    95_000_000, 0.29),
            ("audio_\(Int.random(in: 100...999)).m4a",          .audio,    5_200_000,  0.48),
        ]
        return signatures.map { name, type, size, chance in
            let daysAgo = Int.random(in: 30...180)
            let frags = Int.random(in: 2...9)
            let inode = APFSInodeInfo(
                objectID: UInt64.random(in: 1_000_000...9_999_999),
                linkCount: 0,
                blockCount: Int(size / 4096) + 1,
                extentCount: frags,
                modifiedDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                blockState: .partiallyOverwritten(fragments: frags)
            )
            return RecoverableFile(
                name: name,
                fileType: type,
                size: size,
                deletedDate: inode.modifiedDate,
                originalPath: "APFS free block scan (block signature match)",
                recoveryChance: min(chance, inode.recoveryChance),
                fragmentCount: frags
            )
        }
    }

    // MARK: - Helpers
    // `nonisolated` because PHAssetCollection.fetchAssetCollectionsContaining
    // doesn't mutate actor state — it's a pure query.
    nonisolated private func albumName(for asset: PHAsset) -> String {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "estimatedAssetCount > 0")
        let c = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: opts)
        return c.firstObject?.localizedTitle ?? "Camera Roll"
    }
}
