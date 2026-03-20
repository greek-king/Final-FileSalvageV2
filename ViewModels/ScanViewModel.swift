// ViewModels/ScanViewModel.swift
// Core ViewModel — updated for Swift Concurrency (actor FileScanner + AsyncStream)
//
// CHANGES:
//   • Removed FileScannerDelegate conformance entirely
//   • startScan() creates a Task that iterates the AsyncStream
//   • scanTask is stored so cancelScan() can cancel it
//   • @MainActor on the class guarantees all @Published mutations stay on the main thread

import Foundation
import Photos

// MARK: - App State
enum AppState {
    case home, scanning, results, recovering, complete
}

// MARK: - Permission Status
struct PermissionStatus {
    var photos: PHAuthorizationStatus
    var allGranted: Bool { photos == .authorized }
    var photosGranted: Bool { photos == .authorized || photos == .limited }
}

// MARK: - ScanViewModel
// @MainActor replaces every DispatchQueue.main.async call.
// The compiler enforces that all @Published properties are only
// written from the main actor — no more runtime crashes from
// publishing on a background thread.
@MainActor
class ScanViewModel: ObservableObject {

    // MARK: - Published State
    @Published var appState: AppState = .home
    @Published var scanProgress: ScanProgress = ScanProgress(currentStep: "", percentage: 0, filesFound: 0, isComplete: false)
    @Published var scanResult: ScanResult?
    @Published var selectedFiles: Set<UUID> = []
    @Published var filterType: FileType? = nil
    @Published var sortOrder: SortOrder = .date
    @Published var recoveryProgress: RecoveryProgress?
    @Published var recoveryResult: RecoveryOperationResult?
    @Published var errorMessage: String?
    @Published var permissionStatus: PermissionStatus
    @Published var selectedDepth: ScanDepth = .deep
    @Published var isShowingPermissionAlert = false

    // MARK: - Services
    private let scanner = FileScanner()          // Now an actor
    private let recoveryService = FileRecoveryService()
    private var scanTask: Task<Void, Never>?     // Replaces isCancelled flag

    // MARK: - Sort Order
    enum SortOrder: String, CaseIterable {
        case date = "Date Deleted"
        case size = "File Size"
        case name = "Name"
        case type = "Type"
        case chance = "Recovery Chance"
    }

    // MARK: - Computed Properties

    var filteredFiles: [RecoverableFile] {
        var files = scanResult?.scannedFiles ?? []
        if let filterType { files = files.filter { $0.fileType == filterType } }
        switch sortOrder {
        case .date:   files.sort { ($0.deletedDate ?? .distantPast) > ($1.deletedDate ?? .distantPast) }
        case .size:   files.sort { $0.size > $1.size }
        case .name:   files.sort { $0.name < $1.name }
        case .type:   files.sort { $0.fileType.rawValue < $1.fileType.rawValue }
        case .chance: files.sort { $0.recoveryChance > $1.recoveryChance }
        }
        return files
    }

    var selectedCount: Int { selectedFiles.count }

    var selectedFilesArray: [RecoverableFile] {
        scanResult?.scannedFiles.filter { selectedFiles.contains($0.id) } ?? []
    }

    var selectedTotalSize: Int64 {
        selectedFilesArray.reduce(0) { $0 + $1.size }
    }

    var typeBreakdown: [(FileType, Int)] {
        guard let result = scanResult else { return [] }
        return FileType.allCases.compactMap { type in
            let count = result.scannedFiles.filter { $0.fileType == type }.count
            return count > 0 ? (type, count) : nil
        }.sorted { $0.1 > $1.1 }
    }

    // MARK: - Init
    init() {
        permissionStatus = PermissionStatus(photos: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    // MARK: - Permissions
    func requestPermissions() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            // Already on @MainActor — safe to assign directly
            self.permissionStatus.photos = status
        }
    }

    // MARK: - Scan Control

    func startScan() {
        guard permissionStatus.photosGranted else {
            isShowingPermissionAlert = true
            return
        }

        appState = .scanning
        selectedFiles = []
        scanResult = nil
        errorMessage = nil

        // Store the Task so we can cancel it from cancelScan().
        // The Task body iterates the AsyncStream — when the stream finishes
        // (or the Task is cancelled), the for-await loop exits automatically.
        scanTask = Task {
            let stream = await scanner.startScan(depth: selectedDepth)
            for await event in stream {
                // Already on @MainActor (Task inherits the actor context)
                switch event {
                case .progress(let progress):
                    self.scanProgress = progress

                case .finished(let result):
                    self.scanResult = result
                    self.appState = .results

                case .failed(let error):
                    self.errorMessage = error.localizedDescription
                    self.appState = .home
                }
            }
        }
    }

    func cancelScan() {
        // Cancels the Task, which cancels the actor's child TaskGroup,
        // which causes each scan step to check Task.isCancelled and return early.
        scanTask?.cancel()
        scanTask = nil
        appState = .home
    }

    // MARK: - Selection

    func toggleSelection(_ file: RecoverableFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }

    func selectAll()      { selectedFiles = Set(filteredFiles.map { $0.id }) }
    func deselectAll()    { selectedFiles = [] }
    func selectHighChance() {
        let high = scanResult?.scannedFiles.filter { $0.recoveryChance >= 0.8 } ?? []
        high.forEach { selectedFiles.insert($0.id) }
    }
    func selectByType(_ type: FileType) {
        (scanResult?.scannedFiles.filter { $0.fileType == type } ?? [])
            .forEach { selectedFiles.insert($0.id) }
    }

    // MARK: - Recovery
    func recoverSelected(to destination: FileRecoveryService.RecoveryDestination) {
        guard !selectedFiles.isEmpty else { return }
        let filesToRecover = selectedFilesArray

        guard recoveryService.hasEnoughSpace(for: filesToRecover) else {
            errorMessage = "Not enough storage space to recover selected files."
            return
        }

        appState = .recovering

        // FileRecoveryService still uses completion handlers — wrap in a Task
        // so we stay consistent with the async pattern throughout the ViewModel.
        Task {
            recoveryService.recoverFiles(
                filesToRecover,
                to: destination,
                progress: { [weak self] progress in
                    // @MainActor guarantees this is safe even though
                    // the closure may be called from a background queue.
                    Task { @MainActor [weak self] in
                        self?.recoveryProgress = progress
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        switch result {
                        case .success(let r): self?.recoveryResult = r; self?.appState = .complete
                        case .failure(let e): self?.errorMessage = e.localizedDescription; self?.appState = .results
                        }
                    }
                }
            )
        }
    }

    func resetToHome() {
        appState = .home
        scanResult = nil
        selectedFiles = []
        recoveryResult = nil
        recoveryProgress = nil
        errorMessage = nil
    }

    func rescan() {
        resetToHome()
        startScan()
    }
}

// MARK: - Recovery Store
class RecoveryStore: ObservableObject {
    @Published var sessions: [RecoverySession] = []

    func addSession(_ session: RecoverySession) {
        sessions.insert(session, at: 0)
        saveToUserDefaults()
    }

    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: "recovery_sessions")
        }
    }

    func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: "recovery_sessions"),
           let decoded = try? JSONDecoder().decode([RecoverySession].self, from: data) {
            sessions = decoded
        }
    }
}
