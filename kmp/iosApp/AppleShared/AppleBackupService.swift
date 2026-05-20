import Foundation
import CryptoKit
import SQLite3
#if os(iOS)
import UIKit
#endif

@MainActor
public final class AppleBackupService: ObservableObject {
    @Published public var backups: [AppleBackupDescriptor] = []
    @Published public var operationState: AppleBackupOperationState = .idle
    @Published public var lastError: String? = nil
    @Published public var needsRestart: Bool = false
    @Published public var latestEmergencyBackupUrl: URL? = nil

    private let fileManager: FileManager
    public let backupsDirectoryURL: URL
    public let databaseURL: URL
    public let attachmentsURL: URL
    private let retentionLimit = 10

    public static let shared = AppleBackupService()

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let dbPath = AppleBridgeBootstrap.current().databasePath
        self.databaseURL = URL(fileURLWithPath: dbPath)
        
        let appDataURL = self.databaseURL.deletingLastPathComponent()
        self.backupsDirectoryURL = appDataURL.appendingPathComponent("backups", isDirectory: true)
        
        // Attachments directory matches standard location used by NotebookEvidence
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? appDataURL
        self.attachmentsURL = docDir.appendingPathComponent("NotebookEvidence", isDirectory: true)

        try? ensureDirectoriesExist()
    }

    private func ensureDirectoriesExist() throws {
        if !fileManager.fileExists(atPath: backupsDirectoryURL.path) {
            try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    public func scanBackups() async {
        operationState = .scanning
        defer { operationState = .idle }

        do {
            try ensureDirectoriesExist()
            let urls = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            let backupUrls = urls.filter { $0.pathExtension == "migestorbackup" }
            
            var loadedDescriptors: [AppleBackupDescriptor] = []
            for url in backupUrls {
                if let descriptor = try? loadBackupDescriptor(at: url) {
                    loadedDescriptors.append(descriptor)
                }
            }
            
            // Sort: newest first
            self.backups = loadedDescriptors.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        } catch {
            self.lastError = "Error escaneando copias de seguridad: \(error.localizedDescription)"
        }
    }

    public func createBackup(note: String? = nil) async throws -> AppleBackupDescriptor {
        operationState = .creating
        defer { operationState = .idle }

        do {
            try ensureDirectoriesExist()
            
            // Format package path
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let randomSuffix = String(UUID().uuidString.prefix(6))
            let packageName = "backup_\(timestamp)_\(randomSuffix).migestorbackup"
            let packageURL = backupsDirectoryURL.appendingPathComponent(packageName, isDirectory: true)
            
            // Create backup package directory
            try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
            
            // 1. Copy database
            let destinationDBURL = packageURL.appendingPathComponent("database.sqlite")
            if fileManager.fileExists(atPath: destinationDBURL.path) {
                try fileManager.removeItem(at: destinationDBURL)
            }
            try fileManager.copyItem(at: databaseURL, to: destinationDBURL)
            
            // Copy WAL/SHM sidecars if present
            for suffix in ["-wal", "-shm"] {
                let sourceSidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                let destinationSidecar = URL(fileURLWithPath: destinationDBURL.path + suffix)
                if fileManager.fileExists(atPath: sourceSidecar.path) {
                    if fileManager.fileExists(atPath: destinationSidecar.path) {
                        try fileManager.removeItem(at: destinationSidecar)
                    }
                    try fileManager.copyItem(at: sourceSidecar, to: destinationSidecar)
                }
            }
            
            // 2. Copy attachments
            let destinationAttachmentsURL = packageURL.appendingPathComponent("attachments", isDirectory: true)
            try fileManager.createDirectory(at: destinationAttachmentsURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: attachmentsURL.path) {
                try copyDirectoryContents(from: attachmentsURL, to: destinationAttachmentsURL)
            }
            
            // 3. Compute stats
            let classCount = countRows(in: databaseURL.path, table: "classes")
            let studentCount = countRows(in: databaseURL.path, table: "students")
            let notebookColumnCount = countRows(in: databaseURL.path, table: "notebook_columns")
            let rubricCount = countRows(in: databaseURL.path, table: "rubrics")
            let attendanceRecordCount = countRows(in: databaseURL.path, table: "attendance")
            
            let summary = AppleBackupSummary(
                classCount: classCount,
                studentCount: studentCount,
                notebookColumnCount: notebookColumnCount,
                rubricCount: rubricCount,
                attendanceRecordCount: attendanceRecordCount
            )
            
            // 4. Compute schema and database size
            let dbSize = try getFileSize(destinationDBURL)
            let dbChecksum = try calculateSHA256(for: destinationDBURL)
            let schemaVersion = getSchemaVersion(of: databaseURL.path)
            
            // 5. Gather App Metadata
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            let platform = AppleBridgeBootstrap.current().platformName
            
            #if os(macOS)
            let deviceName = Host.current().localizedName ?? "Mac"
            #else
            let deviceName = UIDevice.current.name
            #endif
            
            let manifest = AppleBackupManifest(
                appVersion: appVersion,
                buildNumber: buildNumber,
                platform: platform,
                deviceName: deviceName,
                databaseSizeBytes: dbSize,
                checksumSHA256: dbChecksum,
                schemaVersion: schemaVersion,
                summary: summary,
                note: note
            )
            
            // 6. Write manifest.json
            let manifestURL = packageURL.appendingPathComponent("manifest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)
            
            // 7. Write checksums.json
            var checksumMap: [String: String] = [:]
            checksumMap["database.sqlite"] = dbChecksum
            checksumMap["manifest.json"] = try calculateSHA256(for: manifestURL)
            
            // Add sidecars to checksum if they exist
            for suffix in ["-wal", "-shm"] {
                let sidecarURL = destinationDBURL.deletingLastPathComponent().appendingPathComponent("database.sqlite" + suffix)
                if fileManager.fileExists(atPath: sidecarURL.path) {
                    checksumMap["database.sqlite" + suffix] = try calculateSHA256(for: sidecarURL)
                }
            }
            
            // Add attachment files to checksum map
            let attachmentFiles = try getRelativeFiles(in: destinationAttachmentsURL)
            for relativePath in attachmentFiles {
                let fileURL = destinationAttachmentsURL.appendingPathComponent(relativePath)
                checksumMap["attachments/\(relativePath)"] = try calculateSHA256(for: fileURL)
            }
            
            let checksumsData = try encoder.encode(checksumMap)
            try checksumsData.write(to: packageURL.appendingPathComponent("checksums.json"), options: .atomic)
            
            let descriptor = AppleBackupDescriptor(
                url: packageURL,
                manifest: manifest,
                sizeBytes: try getDirectorySize(packageURL),
                isVerified: true
            )
            
            // 8. Enforce retention policy
            try applyRetentionPolicy()
            
            // 9. Re-scan and refresh
            await scanBackups()
            
            return descriptor
        } catch {
            self.lastError = "No se pudo crear la copia de seguridad: \(error.localizedDescription)"
            throw error
        }
    }

    public func verifyBackup(_ descriptor: AppleBackupDescriptor) async -> AppleBackupDescriptor {
        operationState = .verifying
        defer { operationState = .idle }

        var verifiedDescriptor = descriptor
        do {
            let packageURL = descriptor.url
            let manifestURL = packageURL.appendingPathComponent("manifest.json")
            let checksumsURL = packageURL.appendingPathComponent("checksums.json")
            
            guard fileManager.fileExists(atPath: manifestURL.path),
                  fileManager.fileExists(atPath: checksumsURL.path) else {
                throw NSError(domain: "AppleBackupService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Archivos esenciales de metadatos (manifest.json o checksums.json) perdidos."])
            }
            
            let checksumsData = try Data(contentsOf: checksumsURL)
            let checksumMap = try JSONDecoder().decode([String: String].self, from: checksumsData)
            
            for (relPath, expectedChecksum) in checksumMap {
                let fileURL = packageURL.appendingPathComponent(relPath)
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    throw NSError(domain: "AppleBackupService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Falta el archivo: \(relPath)"])
                }
                
                let currentChecksum = try calculateSHA256(for: fileURL)
                if currentChecksum != expectedChecksum {
                    throw NSError(domain: "AppleBackupService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Fallo de suma de comprobación (checksum mismatch) en \(relPath)."])
                }
            }
            
            verifiedDescriptor.isVerified = true
            verifiedDescriptor.verificationError = nil
        } catch {
            verifiedDescriptor.isVerified = false
            verifiedDescriptor.verificationError = error.localizedDescription
        }

        // Update list inline if present
        if let idx = backups.firstIndex(where: { $0.url == descriptor.url }) {
            backups[idx] = verifiedDescriptor
        }
        
        return verifiedDescriptor
    }

    public func restoreBackup(_ descriptor: AppleBackupDescriptor) async throws {
        operationState = .restoring
        defer { operationState = .idle }

        do {
            // 1. Verify before restoring
            let verified = await verifyBackup(descriptor)
            guard verified.isVerified else {
                throw NSError(domain: "AppleBackupService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No se puede restaurar una copia corrupta o sin validar: \(verified.verificationError ?? "Error desconocido")"])
            }
            
            // 2. Create Emergency Backup
            let emergencyNote = "Copia de seguridad de emergencia previa a restauración de \(descriptor.displayName) (\(descriptor.manifest.createdAt.formattedDateText))"
            let emergencyCopy = try await createBackup(note: emergencyNote)
            self.latestEmergencyBackupUrl = emergencyCopy.url
            
            // 3. Overwrite the database
            let packageURL = descriptor.url
            let sourceDB = packageURL.appendingPathComponent("database.sqlite")
            
            // Delete active WAL and SHM journal sidecars so they don't apply to the restored database
            for suffix in ["-wal", "-shm"] {
                let activeSidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                if fileManager.fileExists(atPath: activeSidecar.path) {
                    try fileManager.removeItem(at: activeSidecar)
                }
            }
            
            // Replace main database file
            if fileManager.fileExists(atPath: databaseURL.path) {
                try fileManager.removeItem(at: databaseURL)
            }
            try fileManager.copyItem(at: sourceDB, to: databaseURL)
            
            // Restore sidecars from package if they exist
            for suffix in ["-wal", "-shm"] {
                let packageSidecar = packageURL.appendingPathComponent("database.sqlite" + suffix)
                let activeSidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                if fileManager.fileExists(atPath: packageSidecar.path) {
                    try fileManager.copyItem(at: packageSidecar, to: activeSidecar)
                }
            }
            
            // 4. Restore attachments
            if fileManager.fileExists(atPath: attachmentsURL.path) {
                try fileManager.removeItem(at: attachmentsURL)
            }
            try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            
            let packageAttachments = packageURL.appendingPathComponent("attachments", isDirectory: true)
            if fileManager.fileExists(atPath: packageAttachments.path) {
                try copyDirectoryContents(from: packageAttachments, to: attachmentsURL)
            }
            
            // 5. Trigger restart requirements flag
            self.needsRestart = true
        } catch {
            self.lastError = "Error restaurando copia: \(error.localizedDescription)"
            throw error
        }
    }

    public func deleteBackup(_ descriptor: AppleBackupDescriptor) async throws {
        do {
            if fileManager.fileExists(atPath: descriptor.url.path) {
                try fileManager.removeItem(at: descriptor.url)
            }
            await scanBackups()
        } catch {
            self.lastError = "No se pudo eliminar la copia: \(error.localizedDescription)"
            throw error
        }
    }

    public func exportBackup(_ descriptor: AppleBackupDescriptor, to destinationURL: URL) async throws {
        operationState = .exporting
        defer { operationState = .idle }
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: descriptor.url, to: destinationURL)
        } catch {
            self.lastError = "Error exportando copia: \(error.localizedDescription)"
            throw error
        }
    }

    public func getCurrentDatabaseSummary() -> AppleBackupSummary {
        let classCount = countRows(in: databaseURL.path, table: "classes")
        let studentCount = countRows(in: databaseURL.path, table: "students")
        let notebookColumnCount = countRows(in: databaseURL.path, table: "notebook_columns")
        let rubricCount = countRows(in: databaseURL.path, table: "rubrics")
        let attendanceRecordCount = countRows(in: databaseURL.path, table: "attendance")
        
        return AppleBackupSummary(
            classCount: classCount,
            studentCount: studentCount,
            notebookColumnCount: notebookColumnCount,
            rubricCount: rubricCount,
            attendanceRecordCount: attendanceRecordCount
        )
    }

    // MARK: - Retention Policy

    private func applyRetentionPolicy() throws {
        let urls = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let backupUrls = urls.filter { $0.pathExtension == "migestorbackup" }
        
        var loadedDescriptors: [(URL, Date)] = []
        for url in backupUrls {
            let manifestURL = url.appendingPathComponent("manifest.json")
            if let manifestData = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(AppleBackupManifest.self, from: manifestData) {
                loadedDescriptors.append((url, manifest.createdAt))
            } else {
                // If corrupted manifest or unreadable, still include it for sorting using file attributes
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let date = (attributes?[.creationDate] as? Date) ?? Date.distantPast
                loadedDescriptors.append((url, date))
            }
        }
        
        // Sort: newest first
        let sorted = loadedDescriptors.sorted { $0.1 > $1.1 }
        if sorted.count > retentionLimit {
            let toDelete = sorted.suffix(sorted.count - retentionLimit)
            for (url, _) in toDelete {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Private Helpers

    private func loadBackupDescriptor(at url: URL) throws -> AppleBackupDescriptor {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw NSError(domain: "AppleBackupService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing manifest"])
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AppleBackupManifest.self, from: manifestData)
        let totalSize = try getDirectorySize(url)
        
        return AppleBackupDescriptor(
            url: url,
            manifest: manifest,
            sizeBytes: totalSize,
            isVerified: false
        )
    }

    private func getDirectorySize(_ url: URL) throws -> Int64 {
        var size: Int64 = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            size += (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        return size
    }

    private func getFileSize(_ url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func calculateSHA256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 65536), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
        for item in contents {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destItem.path) {
                try fileManager.removeItem(at: destItem)
            }
            try fileManager.copyItem(at: item, to: destItem)
        }
    }

    private func getRelativeFiles(in rootURL: URL) throws -> [String] {
        var files: [String] = []
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            files.append(relativePath)
        }
        return files
    }

    private func countRows(in dbPath: String, table: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_close(db) }
        
        var statement: OpaquePointer?
        let query = "SELECT COUNT(*) FROM \(table);"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        return 0
    }

    private func getSchemaVersion(of dbPath: String) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }
        
        var statement: OpaquePointer?
        let query = "PRAGMA user_version;"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        return nil
    }
}

// MARK: - Date Formatting Helpers
extension Date {
    fileprivate var formattedDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
