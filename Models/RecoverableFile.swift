// Models/RecoverableFile.swift
// Data models for recoverable files

import Foundation
import UIKit
import Photos

// MARK: - File Type Enum
enum FileType: String, CaseIterable, Codable {
    case photo = "Photos"
    case video = "Videos"
    case audio = "Audio"
    case document = "Documents"
    case unknown = "Other"

    var icon: String {
        switch self {
        case .photo:     return "photo.fill"
        case .video:     return "video.fill"
        case .audio:     return "music.note"
        case .document:  return "doc.fill"
        case .unknown:   return "questionmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .photo:     return "#4ECDC4"
        case .video:     return "#FF6B6B"
        case .audio:     return "#A855F7"
        case .document:  return "#3B82F6"
        case .unknown:   return "#6B7280"
        }
    }

    var allowedExtensions: [String] {
        switch self {
        case .photo:     return ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff", "raw", "cr2", "nef"]
        case .video:     return ["mp4", "mov", "avi", "mkv", "m4v", "3gp", "wmv", "flv"]
        case .audio:     return ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff"]
        case .document:  return ["pdf", "doc", "docx", "txt", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "csv", "rtf", "zip", "rar"]
        case .unknown:   return []
        }
    }
}

// MARK: - Recovery Status
enum RecoveryStatus: String, Codable {
    case notStarted = "Not Started"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case partial = "Partial"
}

// MARK: - Scan Depth
enum ScanDepth: String, CaseIterable {
    case quick = "Quick Scan"
    case deep  = "Deep Scan"
    case full  = "Full Recovery Scan"

    var description: String {
        switch self {
        case .quick: return "Scans recently deleted files (~2 min)"
        case .deep:  return "Comprehensive scan of storage (~8 min)"
        case .full:  return "Maximum recovery depth (~20 min)"
        }
    }

    var estimatedDuration: TimeInterval {
        switch self {
        case .quick: return 120
        case .deep:  return 480
        case .full:  return 1200
        }
    }
}

// MARK: - Recoverable File Model
struct RecoverableFile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var fileType: FileType
    var size: Int64 // bytes
    var deletedDate: Date?
    var originalPath: String
    var thumbnailData: Data?
    var isSelected: Bool
    var recoveryChance: Double // 0.0 - 1.0
    var fragmentCount: Int
    var isRecovered: Bool
    var localIdentifier: String? // PHAsset identifier if available

    init(
        id: UUID = UUID(),
        name: String,
        fileType: FileType,
        size: Int64,
        deletedDate: Date? = nil,
        originalPath: String = "",
        thumbnailData: Data? = nil,
        isSelected: Bool = false,
        recoveryChance: Double = 1.0,
        fragmentCount: Int = 1,
        isRecovered: Bool = false,
        localIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fileType = fileType
        self.size = size
        self.deletedDate = deletedDate
        self.originalPath = originalPath
        self.thumbnailData = thumbnailData
        self.isSelected = isSelected
        self.recoveryChance = recoveryChance
        self.fragmentCount = fragmentCount
        self.isRecovered = isRecovered
        self.localIdentifier = localIdentifier
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var recoveryChanceLabel: String {
        switch recoveryChance {
        case 0.8...1.0: return "Excellent"
        case 0.5..<0.8: return "Good"
        case 0.2..<0.5: return "Fair"
        default:        return "Low"
        }
    }

    var recoveryChanceColor: String {
        switch recoveryChance {
        case 0.8...1.0: return "#10B981"
        case 0.5..<0.8: return "#F59E0B"
        case 0.2..<0.5: return "#FF6B6B"
        default:        return "#6B7280"
        }
    }

    var formattedDeletedDate: String {
        guard let date = deletedDate else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Scan Result
struct ScanResult {
    var scannedFiles: [RecoverableFile]
    var totalScanned: Int
    var recoverable: Int
    var duration: TimeInterval
    var scanDepth: ScanDepth
    var date: Date

    var recoverableByType: [FileType: [RecoverableFile]] {
        Dictionary(grouping: scannedFiles, by: { $0.fileType })
    }

    var totalRecoverableSize: Int64 {
        scannedFiles.reduce(0) { $0 + $1.size }
    }
}

// MARK: - Recovery Session
struct RecoverySession: Identifiable, Codable {
    let id: UUID
    var date: Date
    var recoveredFiles: [RecoverableFile]
    var destinationPath: String
    var status: RecoveryStatus

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var totalSize: Int64 {
        recoveredFiles.reduce(0) { $0 + $1.size }
    }
}
