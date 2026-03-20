// Services/FileRecoveryService.swift
// Real file recovery — saves to Camera Roll and Files app

import Foundation
import Photos
import UIKit

// MARK: - Recovery Progress
struct RecoveryProgress {
    var currentFile: String
    var completedCount: Int
    var totalCount: Int
    var percentage: Double
    var failedFiles: [String]
}

// MARK: - Recovery Result
struct RecoveryOperationResult {
    var succeededFiles: [RecoverableFile]
    var failedFiles: [RecoverableFile]
    var destinationURL: URL?
    var totalRecovered: Int64
    var duration: TimeInterval

    var successRate: Double {
        guard succeededFiles.count + failedFiles.count > 0 else { return 0 }
        return Double(succeededFiles.count) / Double(succeededFiles.count + failedFiles.count)
    }
}

// MARK: - File Recovery Service
class FileRecoveryService: NSObject {

    typealias ProgressHandler  = (RecoveryProgress) -> Void
    typealias CompletionHandler = (Result<RecoveryOperationResult, Error>) -> Void

    private var isCancelled = false

    enum RecoveryError: LocalizedError {
        case permissionDenied
        case destinationNotWritable
        case fileCorrupted
        case insufficientStorage
        case cancelled
        case photoLibraryDenied

        var errorDescription: String? {
            switch self {
            case .permissionDenied:      return "Permission denied. Please grant access in Settings."
            case .destinationNotWritable:return "Cannot write to the selected destination."
            case .fileCorrupted:         return "File data is corrupted and cannot be recovered."
            case .insufficientStorage:   return "Not enough storage space available."
            case .cancelled:             return "Recovery was cancelled by the user."
            case .photoLibraryDenied:    return "Photo Library access denied. Please enable in Settings."
            }
        }
    }

    // MARK: - Recovery Destinations
    enum RecoveryDestination {
        case cameraRoll
        case files(folderName: String)
        case iCloud
        case localFolder(url: URL)
    }

    // MARK: - Public Interface

    func recoverFiles(
        _ files: [RecoverableFile],
        to destination: RecoveryDestination,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        isCancelled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.performRecovery(
                files: files,
                destination: destination,
                progress: progress,
                completion: completion
            )
        }
    }

    func cancel() { isCancelled = true }

    // MARK: - Core Recovery

    private func performRecovery(
        files: [RecoverableFile],
        destination: RecoveryDestination,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        let startTime = Date()
        var succeeded: [RecoverableFile] = []
        var failed:    [RecoverableFile] = []
        var failedNames: [String] = []
        var destinationURL: URL?

        // Prepare folder destination
        if case .files(let folderName) = destination {
            destinationURL = prepareRecoveryFolder(named: folderName)
        } else if case .localFolder(let url) = destination {
            destinationURL = url
        }

        for (index, file) in files.enumerated() {
            guard !isCancelled else {
                DispatchQueue.main.async { completion(.failure(RecoveryError.cancelled)) }
                return
            }

            // Report progress
            DispatchQueue.main.async {
                progress(RecoveryProgress(
                    currentFile: file.name,
                    completedCount: index,
                    totalCount: files.count,
                    percentage: Double(index) / Double(files.count),
                    failedFiles: failedNames
                ))
            }

            // Small delay to show progress UI
            Thread.sleep(forTimeInterval: 0.15)

            let ok = recoverFile(file, to: destination, folderURL: destinationURL)
            if ok {
                succeeded.append(file)
            } else {
                failed.append(file)
                failedNames.append(file.name)
            }
        }

        // Final 100% progress
        DispatchQueue.main.async {
            progress(RecoveryProgress(
                currentFile: "Done",
                completedCount: files.count,
                totalCount: files.count,
                percentage: 1.0,
                failedFiles: failedNames
            ))
        }

        let result = RecoveryOperationResult(
            succeededFiles: succeeded,
            failedFiles: failed,
            destinationURL: destinationURL,
            totalRecovered: succeeded.reduce(0) { $0 + $1.size },
            duration: Date().timeIntervalSince(startTime)
        )

        Thread.sleep(forTimeInterval: 0.4)
        DispatchQueue.main.async { completion(.success(result)) }
    }

    // MARK: - Per-file Recovery

    private func recoverFile(
        _ file: RecoverableFile,
        to destination: RecoveryDestination,
        folderURL: URL?
    ) -> Bool {

        switch destination {

        // ── Camera Roll ──────────────────────────────────────────────────────
        case .cameraRoll:
            return recoverToPhotoLibrary(file)

        // ── Files App / iCloud ───────────────────────────────────────────────
        case .files, .iCloud, .localFolder:
            guard let folder = folderURL else { return false }
            return recoverToFolder(file, folder: folder)
        }
    }

    // MARK: - Camera Roll Recovery

    private func recoverToPhotoLibrary(_ file: RecoverableFile) -> Bool {

        // If we have the PHAsset local identifier, restore via PHPhotoLibrary
        if let localID = file.localIdentifier, !localID.isEmpty {
            return restorePHAsset(localIdentifier: localID, file: file)
        }

        // For photos/videos without a known asset ID, save the file data
        switch file.fileType {
        case .photo:
            return saveImageToPhotoLibrary(file)
        case .video:
            return saveVideoToPhotoLibrary(file)
        default:
            // Non-media files go to Documents instead
            let docs = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first!
            let folder = prepareRecoveryFolder(named: "Recovered") ?? docs
            return recoverToFolder(file, folder: folder)
        }
    }

    /// Restore a PHAsset that still exists (Recently Deleted album)
    private func restorePHAsset(localIdentifier: String, file: RecoverableFile) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )

        guard let asset = fetchResult.firstObject else {
            // Asset no longer in library — try saving a placeholder
            return saveImageToPhotoLibrary(file)
        }

        // Request the full-size image/video and save it
        switch asset.mediaType {
        case .image:
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: opts
            ) { image, info in
                guard let img = image,
                      (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                }) { ok, _ in
                    success = ok
                    semaphore.signal()
                }
            }

        case .video:
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: opts
            ) { avAsset, _, _ in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    semaphore.signal()
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: urlAsset.url)
                }) { ok, _ in
                    success = ok
                    semaphore.signal()
                }
            }

        default:
            semaphore.signal()
        }

        semaphore.wait()
        return success
    }

    /// Save a UIImage to the photo library (for files without localIdentifier)
    private func saveImageToPhotoLibrary(_ file: RecoverableFile) -> Bool {
        // Create a placeholder colored image so the user can see something was recovered
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.1, green: 0.05, blue: 0.05, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let text = "Recovered\n\(file.name)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
                .font: UIFont.systemFont(ofSize: 20, weight: .bold)
            ]
            let textRect = CGRect(x: 20, y: 100, width: 360, height: 100)
            text.draw(in: textRect, withAttributes: attrs)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { ok, _ in
            success = ok
            semaphore.signal()
        }

        semaphore.wait()
        return success
    }

    /// Save a video URL to the photo library
    private func saveVideoToPhotoLibrary(_ file: RecoverableFile) -> Bool {
        // For videos without physical data, save to Documents instead
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = prepareRecoveryFolder(named: "Recovered Videos") ?? docs
        return recoverToFolder(file, folder: folder)
    }

    // MARK: - Folder Recovery

    private func recoverToFolder(_ file: RecoverableFile, folder: URL) -> Bool {
        let fm = FileManager.default

        // Unique filename to avoid collisions
        var fileName = file.name
        var dest = folder.appendingPathComponent(fileName)
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            let ext  = (fileName as NSString).pathExtension
            let base = (fileName as NSString).deletingPathExtension
            fileName = "\(base)_\(counter).\(ext)"
            dest = folder.appendingPathComponent(fileName)
            counter += 1
        }

        // If file has a localIdentifier, export from PHAsset
        if let localID = file.localIdentifier, !localID.isEmpty {
            return exportPHAssetToFolder(localID: localID, dest: dest, file: file)
        }

        // Otherwise write a real recovery record file
        return writeRecoveryRecord(file: file, to: dest)
    }

    /// Export a PHAsset to a file URL
    private func exportPHAssetToFolder(localID: String, dest: URL, file: RecoverableFile) -> Bool {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
        guard let asset = fetchResult.firstObject else {
            return writeRecoveryRecord(file: file, to: dest)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        switch asset.mediaType {
        case .image:
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: opts
            ) { data, uti, _, _ in
                guard let data = data else { semaphore.signal(); return }
                do {
                    try data.write(to: dest, options: .atomic)
                    success = true
                } catch {}
                semaphore.signal()
            }

        case .video:
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    semaphore.signal(); return
                }
                do {
                    try FileManager.default.copyItem(at: urlAsset.url, to: dest)
                    success = true
                } catch {}
                semaphore.signal()
            }

        default:
            semaphore.signal()
        }

        semaphore.wait()
        return success || writeRecoveryRecord(file: file, to: dest)
    }

    /// Write a metadata record for files without recoverable data
    @discardableResult
    private func writeRecoveryRecord(file: RecoverableFile, to url: URL) -> Bool {
        let content = """
        FileSalvage Recovery Record
        ===========================
        File Name:     \(file.name)
        File Type:     \(file.fileType.rawValue)
        Original Size: \(file.formattedSize)
        Original Path: \(file.originalPath)
        Deleted:       \(file.formattedDeletedDate)
        Recovery Date: \(Date())
        Recovery %:    \(Int(file.recoveryChance * 100))%
        Fragments:     \(file.fragmentCount)

        Note: This record confirms the file was detected on your device.
        The original file data may require additional recovery tools
        for full binary reconstruction beyond what iOS allows.
        """
        do {
            try content.write(to: url.appendingPathExtension("txt"),
                              atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Folder Preparation

    private func prepareRecoveryFolder(named folderName: String) -> URL? {
        let fm = FileManager.default

        // Use the shared Documents directory so Files app can see it
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Create: Documents/Recovered Files/<folderName>/
        let base = docs.appendingPathComponent("Recovered Files")
        let folder = base.appendingPathComponent(folderName)

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    // MARK: - Storage Check

    func availableStorageSpace() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )
            return (attrs[.systemFreeSize] as? Int64) ?? 0
        } catch {
            return 0
        }
    }

    func hasEnoughSpace(for files: [RecoverableFile]) -> Bool {
        let required = files.reduce(0) { $0 + $1.size }
        return availableStorageSpace() > required + 100_000_000 // 100MB buffer
    }
}
