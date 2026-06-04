import Foundation

public struct AppleBackupManifest: Codable, Identifiable, Hashable {
    public var id: String { idString }
    private let idString: String
    public let createdAt: Date
    public let appVersion: String
    public let buildNumber: String
    public let platform: String
    public let deviceName: String
    public let databaseSizeBytes: Int64
    public let checksumSHA256: String
    public let schemaVersion: Int?
    public let summary: AppleBackupSummary
    public let note: String?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        appVersion: String,
        buildNumber: String,
        platform: String,
        deviceName: String,
        databaseSizeBytes: Int64,
        checksumSHA256: String,
        schemaVersion: Int? = nil,
        summary: AppleBackupSummary,
        note: String? = nil
    ) {
        self.idString = id
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.platform = platform
        self.deviceName = deviceName
        self.databaseSizeBytes = databaseSizeBytes
        self.checksumSHA256 = checksumSHA256
        self.schemaVersion = schemaVersion
        self.summary = summary
        self.note = note
    }
}

public struct AppleBackupSummary: Codable, Hashable {
    public let classCount: Int
    public let studentCount: Int
    public let notebookColumnCount: Int
    public let rubricCount: Int
    public let attendanceRecordCount: Int

    public init(
        classCount: Int,
        studentCount: Int,
        notebookColumnCount: Int,
        rubricCount: Int,
        attendanceRecordCount: Int
    ) {
        self.classCount = classCount
        self.studentCount = studentCount
        self.notebookColumnCount = notebookColumnCount
        self.rubricCount = rubricCount
        self.attendanceRecordCount = attendanceRecordCount
    }
}

public struct AppleBackupDescriptor: Identifiable, Hashable {
    public var id: String { manifest.id }
    public let url: URL
    public let manifest: AppleBackupManifest
    public let sizeBytes: Int64
    public var isVerified: Bool
    public var verificationError: String?

    public var displayName: String { url.lastPathComponent }

    public init(
        url: URL,
        manifest: AppleBackupManifest,
        sizeBytes: Int64,
        isVerified: Bool,
        verificationError: String? = nil
    ) {
        self.url = url
        self.manifest = manifest
        self.sizeBytes = sizeBytes
        self.isVerified = isVerified
        self.verificationError = verificationError
    }
}

extension AppleBackupDescriptor {
    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public enum AppleBackupOperationState: Equatable {
    case idle
    case scanning
    case creating
    case verifying
    case restoring
    case exporting
    case failed(String)
    case completed(String)
}
