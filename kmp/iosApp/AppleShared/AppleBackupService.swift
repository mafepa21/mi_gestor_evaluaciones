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
    var automaticBackupTask: Task<Void, Never>?

    /// Bases de datos que el arranque puso en cuarentena porque no pudo abrirlas
    /// (ver `createAppleDriver` en AppleDriver.kt). Cuando esto ocurre la app se abre
    /// vacía y, hasta 2026-07, no se avisaba de ninguna forma: el usuario veía sus datos
    /// desaparecer sin saber que seguían en disco y eran recuperables.
    @Published public var quarantinedDatabases: [AppleQuarantinedDatabase] = []

    private let fileManager: FileManager
    public let backupsDirectoryURL: URL
    public let databaseURL: URL
    public let attachmentsURL: URL
    public let learningSituationsURL: URL
    /// Retención (ver `retentionVictims`): copias normales recientes, una por semana
    /// de las anteriores y un cupo propio para las de emergencia previas a restaurar.
    nonisolated public static let recentRetentionCount = 7
    nonisolated public static let weeklyRetentionCount = 4
    nonisolated public static let emergencyRetentionCount = 2
    /// Regla antigua (las 5 más recientes de cualquier tipo). Se sigue respetando para
    /// que el cambio de regla no borre ninguna copia que antes se conservaba.
    nonisolated static let legacyRetentionCount = 5
    nonisolated static let emergencyNotePrefix = "Copia de seguridad de emergencia"
    private let libretaStorage = LibretaStorage.standard

    public static let shared = AppleBackupService()

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let dbPath = AppleBridgeBootstrap.databasePath
        self.databaseURL = URL(fileURLWithPath: dbPath)
        
        let appDataURL = self.databaseURL.deletingLastPathComponent()
        self.backupsDirectoryURL = appDataURL.appendingPathComponent("backups", isDirectory: true)
        
        // Attachments directory matches standard location used by NotebookEvidence
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? appDataURL
        self.attachmentsURL = docDir.appendingPathComponent("NotebookEvidence", isDirectory: true)
        self.learningSituationsURL = docDir.appendingPathComponent("LearningSituations", isDirectory: true)

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

        scanQuarantinedDatabases()
    }

    /// Busca bases de datos apartadas por el arranque (`<nombre>.backup_<epoch>`) y las
    /// publica para que la UI pueda avisar. Sin esto la pérdida es completamente silenciosa.
    public func scanQuarantinedDatabases() {
        let appDataURL = databaseURL.deletingLastPathComponent()
        let dbName = databaseURL.lastPathComponent

        guard let urls = try? fileManager.contentsOfDirectory(
            at: appDataURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            quarantinedDatabases = []
            return
        }

        let prefix = dbName + ".backup_"
        let found: [AppleQuarantinedDatabase] = urls.compactMap { url in
            let name = url.lastPathComponent
            // Los sidecars acompañan al .db en cuarentena; no son entradas propias.
            guard name.hasPrefix(prefix), !name.hasSuffix("-wal"), !name.hasSuffix("-shm") else {
                return nil
            }

            let epochText = String(name.dropFirst(prefix.count))
            let quarantinedAt = TimeInterval(epochText).map(Date.init(timeIntervalSince1970:))
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            let size = (try? getFileSize(url)) ?? 0

            var summary: AppleBackupSummary? = nil
            if size > 0 {
                summary = AppleBackupSummary(
                    classCount: countRows(in: url.path, table: "classes"),
                    studentCount: countRows(in: url.path, table: "students"),
                    notebookColumnCount: countRows(in: url.path, table: "notebook_columns"),
                    rubricCount: countRows(in: url.path, table: "rubrics"),
                    attendanceRecordCount: countRows(in: url.path, table: "attendance")
                )
            }

            return AppleQuarantinedDatabase(
                url: url,
                quarantinedAt: quarantinedAt,
                sizeBytes: size,
                summary: summary
            )
        }

        quarantinedDatabases = found.sorted { $0.quarantinedAt > $1.quarantinedAt }
    }

    public func createBackup(note: String? = nil) async throws -> AppleBackupDescriptor {
        try await createBackup(note: note, protecting: [])
    }

    /// `protecting`: copias que la retención no puede borrar (p. ej. la que se está restaurando).
    private func createBackup(note: String?, protecting protectedURLs: Set<URL>) async throws -> AppleBackupDescriptor {
        let perfStart = DispatchTime.now()
        defer { PerfLog.finish("Copia de seguridad", start: perfStart) }
        operationState = .creating
        defer { operationState = .idle }

        do {
            try ensureDirectoriesExist()

            // Una base de datos ausente, vacía o sin cabecera SQLite no produce una copia:
            // produce un paquete que PARECE válido (manifiesto correcto, adjuntos copiados)
            // con database.sqlite de 0 bytes. Es exactamente lo que ocurrió en macOS mientras
            // databasePath apuntaba a un fichero fantasma, y dejó al usuario sin copias
            // utilizables durante meses sin un solo aviso. Fallar aquí es obligatorio.
            try validateUsableDatabase(at: databaseURL, context: "la base de datos activa")

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
            try AppleSQLiteBackupValidator.validateDatabase(at: destinationDBURL)
            
            // 2. Copy attachments
            let destinationAttachmentsURL = packageURL.appendingPathComponent("attachments", isDirectory: true)
            try fileManager.createDirectory(at: destinationAttachmentsURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: attachmentsURL.path) {
                try copyDirectoryContents(from: attachmentsURL, to: destinationAttachmentsURL)
            }

            let destinationLearningSituationsURL = packageURL.appendingPathComponent("learning-situations", isDirectory: true)
            try fileManager.createDirectory(at: destinationLearningSituationsURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: learningSituationsURL.path) {
                try copyDirectoryContents(from: learningSituationsURL, to: destinationLearningSituationsURL)
            }
            
            // 2b. Libreta (solo iPad): base SwiftData + dibujos e imágenes.
            var libretaCount: Int? = nil
            if LibretaStorage.isSupportedOnThisPlatform,
               try LibretaBackupPackager.package(from: libretaStorage, into: packageURL, fileManager: fileManager) {
                libretaCount = LibretaBackupPackager.notebookCount(in: LibretaBackupPackager.databaseURL(in: packageURL)) ?? 0
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
                attendanceRecordCount: attendanceRecordCount,
                libretaCount: libretaCount
            )
            
            // 4. Compute schema and database size
            let dbSize = try getFileSize(destinationDBURL)
            guard dbSize > 0 else {
                try? fileManager.removeItem(at: packageURL)
                throw NSError(
                    domain: "AppleBackupService",
                    code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "La copia resultante estaba vacía y se ha descartado. No se ha guardado nada."]
                )
            }
            let dbChecksum = try calculateSHA256(for: destinationDBURL)
            let schemaVersion = getSchemaVersion(of: databaseURL.path)
            
            // 5. Gather App Metadata
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            let platform = AppleBridgeBootstrap.platformName
            
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
            let situationFiles = try getRelativeFiles(in: destinationLearningSituationsURL)
            for relativePath in situationFiles {
                let fileURL = destinationLearningSituationsURL.appendingPathComponent(relativePath)
                checksumMap["learning-situations/\(relativePath)"] = try calculateSHA256(for: fileURL)
            }
            let libretaFolderURL = LibretaBackupPackager.folderURL(in: packageURL)
            for relativePath in try LibretaBackupPackager.regularFileRelativePaths(in: libretaFolderURL, fileManager: fileManager) {
                let fileURL = libretaFolderURL.appendingPathComponent(relativePath)
                checksumMap["\(LibretaBackupPackager.folderName)/\(relativePath)"] = try calculateSHA256(for: fileURL)
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
            try applyRetentionPolicy(protecting: protectedURLs)
            
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
            guard let expectedDatabaseChecksum = checksumMap["database.sqlite"],
                  expectedDatabaseChecksum == descriptor.manifest.checksumSHA256 else {
                throw NSError(
                    domain: "AppleBackupService",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "El checksum principal de la base no coincide con el manifiesto."]
                )
            }
            
            for (relPath, expectedChecksum) in checksumMap {
                let fileURL = try validatedPackageFileURL(relativePath: relPath, packageURL: packageURL)
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    throw NSError(domain: "AppleBackupService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Falta el archivo: \(relPath)"])
                }
                
                let currentChecksum = try calculateSHA256(for: fileURL)
                if currentChecksum != expectedChecksum {
                    throw NSError(domain: "AppleBackupService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Fallo de suma de comprobación (checksum mismatch) en \(relPath)."])
                }
            }
            let databaseURL = packageURL.appendingPathComponent("database.sqlite")
            try validateUsableDatabase(at: databaseURL, context: "la base incluida en la copia")
            try AppleSQLiteBackupValidator.validateDatabase(at: databaseURL)
            if checksumMap[LibretaBackupPackager.databaseChecksumKey] != nil {
                try AppleSQLiteBackupValidator.validateDatabase(at: LibretaBackupPackager.databaseURL(in: packageURL))
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
            
            // 2. La verificación por checksum NO basta: el hash de un fichero vacío es
            // perfectamente válido y coincide con su manifiesto. Restaurar una de esas
            // copias borraría los datos actuales y los sustituiría por nada.
            let packageURL = descriptor.url
            let sourceDB = packageURL.appendingPathComponent("database.sqlite")
            try ensureSchemaCompatible(descriptor.manifest)
            try validateUsableDatabase(at: sourceDB, context: "la copia seleccionada")
            try AppleSQLiteBackupValidator.validateDatabase(at: sourceDB)

            // 3. Create Emergency Backup
            // Best-effort: si la base activa no es utilizable (vacía o corrupta) no hay nada
            // que proteger, y ese es precisamente el caso en el que el usuario más necesita
            // restaurar. No lo bloqueamos por no poder hacer una copia de la nada.
            let emergencyNote = "\(AppleBackupDescriptor.emergencyNotePrefix) previa a restauración de \(descriptor.displayName) (\(descriptor.manifest.createdAt.formattedDateText))"
            do {
                // La copia elegida queda protegida: si fuese la más antigua, la retención
                // la borraría justo antes de leerla para restaurar.
                let emergencyCopy = try await createBackup(
                    note: emergencyNote,
                    protecting: [packageURL.standardizedFileURL]
                )
                self.latestEmergencyBackupUrl = emergencyCopy.url
            } catch {
                // Sin red de seguridad no se sustituyen unas libretas que existen:
                // a diferencia de la base principal, aquí sí hay algo que proteger.
                let packageBringsLibreta = (try? loadChecksumKeys(in: packageURL))?
                    .contains(LibretaBackupPackager.databaseChecksumKey) == true
                if LibretaStorage.isSupportedOnThisPlatform,
                   packageBringsLibreta,
                   fileManager.fileExists(atPath: libretaStorage.storeURL.path) {
                    throw NSError(
                        domain: "AppleBackupService",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "No se pudo hacer la copia de emergencia de tus libretas, así que no se ha restaurado nada. \(error.localizedDescription)"]
                    )
                }
                self.latestEmergencyBackupUrl = nil
                print("[AppleBackupService] Sin copia de emergencia previa a restaurar: \(error.localizedDescription)")
            }

            // 4. Preparar el conjunto completo sin tocar todavía datos activos. La
            // instantánea SQLite integra cualquier WAL del paquete y vuelve a validarse.
            let transactionID = UUID().uuidString
            let stagedDatabaseURL = databaseURL
                .deletingLastPathComponent()
                .appendingPathComponent("restore-\(transactionID).sqlite")
            let stagedAttachmentsURL = attachmentsURL
                .deletingLastPathComponent()
                .appendingPathComponent(".restore-\(transactionID)-attachments", isDirectory: true)
            let stagedLearningSituationsURL = learningSituationsURL
                .deletingLastPathComponent()
                .appendingPathComponent(".restore-\(transactionID)-learning-situations", isDirectory: true)
            let stagedURLs = [stagedDatabaseURL, stagedAttachmentsURL, stagedLearningSituationsURL]
            var libretaStagedURLs: [URL] = []
            defer {
                (stagedURLs + libretaStagedURLs).forEach { url in
                    if fileManager.fileExists(atPath: url.path) {
                        try? fileManager.removeItem(at: url)
                    }
                }
            }

            try AppleSQLiteBackupValidator.materializeSnapshot(from: sourceDB, to: stagedDatabaseURL)
            let packageAttachments = packageURL.appendingPathComponent("attachments", isDirectory: true)
            let packageLearningSituations = packageURL.appendingPathComponent("learning-situations", isDirectory: true)
            try stageDirectory(from: packageAttachments, to: stagedAttachmentsURL)
            try stageDirectory(from: packageLearningSituations, to: stagedLearningSituationsURL)

            // Libreta (solo iPad): si la copia no la trae, las libretas actuales no se tocan.
            var libretaOperations: [AppleBackupRestoreOperation] = []
            if LibretaStorage.isSupportedOnThisPlatform {
                let checksumKeys = Set(try loadChecksumKeys(in: packageURL))
                if let staged = try LibretaBackupPackager.stageRestore(
                    from: packageURL,
                    checksumKeys: checksumKeys,
                    to: libretaStorage,
                    transactionID: transactionID,
                    fileManager: fileManager
                ) {
                    libretaOperations = staged.operations
                    libretaStagedURLs = staged.stagedURLs
                }
            }

            // 5. Instalar base + dos árboles como una sola transacción de filesystem.
            // Si cualquier paso falla, el helper revierte en orden inverso.
            let activeWalURL = URL(fileURLWithPath: databaseURL.path + "-wal")
            let activeShmURL = URL(fileURLWithPath: databaseURL.path + "-shm")
            try AppleBackupRestoreTransaction(fileManager: fileManager).commit([
                .replace(stagedURL: stagedDatabaseURL, destinationURL: databaseURL),
                .remove(destinationURL: activeWalURL),
                .remove(destinationURL: activeShmURL),
                .replace(stagedURL: stagedAttachmentsURL, destinationURL: attachmentsURL),
                .replace(stagedURL: stagedLearningSituationsURL, destinationURL: learningSituationsURL),
            ] + libretaOperations)
            
            // 6. Trigger restart requirements flag
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

    /// Exporta una copia portable cifrada. El ZIP intermedio y la salida parcial viven en
    /// staging y se eliminan incluso si la operación falla; nunca se carga el paquete entero
    /// en memoria.
    public func exportEncryptedBackup(
        _ descriptor: AppleBackupDescriptor,
        to destinationURL: URL,
        password: String
    ) async throws {
        operationState = .exporting
        defer { operationState = .idle }

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("migestor-encrypted-export-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryRoot.appendingPathComponent("backup.zip")
        let stagedDestination = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).migestorbackupx")
        defer {
            if fileManager.fileExists(atPath: temporaryRoot.path) { try? fileManager.removeItem(at: temporaryRoot) }
            if fileManager.fileExists(atPath: stagedDestination.path) { try? fileManager.removeItem(at: stagedDestination) }
        }

        do {
            let verified = await verifyBackup(descriptor)
            guard verified.isRestorable else {
                throw NSError(
                    domain: "AppleBackupService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "No se puede exportar una copia que no supera la validación de integridad."]
                )
            }
            operationState = .exporting
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) {
                try AppleBackupPackageArchive.createArchive(packageURL: descriptor.url, archiveURL: archiveURL)
                try AppleEncryptedBackupContainer.encrypt(
                    plaintextURL: archiveURL,
                    destinationURL: stagedDestination,
                    password: password
                )
            }.value
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagedDestination)
            } else {
                try fileManager.moveItem(at: stagedDestination, to: destinationURL)
            }
        } catch {
            self.lastError = "Error exportando copia cifrada: \(error.localizedDescription)"
            throw error
        }
    }

    /// Incorpora al historial una copia externa. Las copias antiguas en directorio siguen
    /// siendo legibles; las nuevas se descifran y descomprimen en staging antes de pasar por
    /// checksum, cabecera SQLite, integrity_check y foreign_key_check.
    public func importPortableBackup(from sourceURL: URL, password: String?) async throws -> AppleBackupDescriptor {
        operationState = .importing
        defer { operationState = .idle }

        let importID = UUID().uuidString
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("migestor-encrypted-import-\(importID)", isDirectory: true)
        let decryptedArchiveURL = temporaryRoot.appendingPathComponent("backup.zip")
        let legacyArchiveURL = temporaryRoot.appendingPathComponent("legacy.zip")
        let stagedPackageURL = backupsDirectoryURL
            .appendingPathComponent(".import-\(importID).migestorbackup", isDirectory: true)
        var finalPackageURL: URL?
        defer {
            if fileManager.fileExists(atPath: temporaryRoot.path) { try? fileManager.removeItem(at: temporaryRoot) }
            if fileManager.fileExists(atPath: stagedPackageURL.path) { try? fileManager.removeItem(at: stagedPackageURL) }
        }

        do {
            try ensureDirectoriesExist()
            let format = try ApplePortableBackupFormat.detect(at: sourceURL)
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            switch format {
            case .legacyPackage:
                try await Task.detached(priority: .userInitiated) {
                    try AppleBackupPackageArchive.createArchive(packageURL: sourceURL, archiveURL: legacyArchiveURL)
                    try AppleBackupPackageArchive.extractArchive(
                        archiveURL: legacyArchiveURL,
                        destinationURL: stagedPackageURL
                    )
                }.value
            case .encryptedV1:
                guard let password else { throw AppleEncryptedBackupError.passwordRequired }
                try await Task.detached(priority: .userInitiated) {
                    try AppleEncryptedBackupContainer.decrypt(
                        encryptedURL: sourceURL,
                        destinationURL: decryptedArchiveURL,
                        password: password
                    )
                    try AppleBackupPackageArchive.extractArchive(
                        archiveURL: decryptedArchiveURL,
                        destinationURL: stagedPackageURL
                    )
                }.value
            }

            let stagedDescriptor = try loadBackupDescriptor(at: stagedPackageURL)
            try ensureSchemaCompatible(stagedDescriptor.manifest)
            let verified = await verifyBackup(stagedDescriptor)
            operationState = .importing
            guard verified.isRestorable else {
                throw NSError(
                    domain: "AppleBackupService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "La copia importada no supera la validación: \(verified.verificationError ?? "error desconocido")."]
                )
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: stagedDescriptor.manifest.createdAt)
            let finalURL = backupsDirectoryURL.appendingPathComponent(
                "imported_\(timestamp)_\(String(importID.prefix(6))).migestorbackup",
                isDirectory: true
            )
            try fileManager.moveItem(at: stagedPackageURL, to: finalURL)
            finalPackageURL = finalURL
            await scanBackups()
            guard let imported = backups.first(where: { $0.url == finalURL }) else {
                throw NSError(
                    domain: "AppleBackupService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "La copia se validó pero no pudo añadirse al historial."]
                )
            }
            let verifiedImport = await verifyBackup(imported)
            operationState = .importing
            guard verifiedImport.isRestorable else {
                throw NSError(
                    domain: "AppleBackupService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "La copia se importó pero no conservó su validación de integridad."]
                )
            }
            return verifiedImport
        } catch {
            if let finalPackageURL, fileManager.fileExists(atPath: finalPackageURL.path) {
                try? fileManager.removeItem(at: finalPackageURL)
                await scanBackups()
            }
            self.lastError = "Error importando copia: \(error.localizedDescription)"
            throw error
        }
    }

    public func getCurrentDatabaseSummary() -> AppleBackupSummary {
        let classCount = countRows(in: databaseURL.path, table: "classes")
        let studentCount = countRows(in: databaseURL.path, table: "students")
        let notebookColumnCount = countRows(in: databaseURL.path, table: "notebook_columns")
        let rubricCount = countRows(in: databaseURL.path, table: "rubrics")
        let attendanceRecordCount = countRows(in: databaseURL.path, table: "attendance")
        let libretaCount: Int? = LibretaStorage.isSupportedOnThisPlatform
            ? LibretaBackupPackager.notebookCount(in: libretaStorage.storeURL)
            : nil
        
        return AppleBackupSummary(
            classCount: classCount,
            studentCount: studentCount,
            notebookColumnCount: notebookColumnCount,
            rubricCount: rubricCount,
            attendanceRecordCount: attendanceRecordCount,
            libretaCount: libretaCount
        )
    }

    // MARK: - Retention Policy

    private func applyRetentionPolicy(protecting protectedURLs: Set<URL> = []) throws {
        let urls = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let backupUrls = urls.filter { $0.pathExtension == "migestorbackup" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [RetentionEntry] = []
        for url in backupUrls {
            let manifestURL = url.appendingPathComponent("manifest.json")
            if let manifestData = try? Data(contentsOf: manifestURL),
               let manifest = try? decoder.decode(AppleBackupManifest.self, from: manifestData) {
                entries.append(RetentionEntry(url: url, createdAt: manifest.createdAt, note: manifest.note))
            } else {
                // Manifiesto ilegible: se ordena por la fecha de la carpeta.
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let date = (attributes?[.creationDate] as? Date) ?? Date.distantPast
                entries.append(RetentionEntry(url: url, createdAt: date, note: nil))
            }
        }

        for url in Self.retentionVictims(entries: entries, protecting: protectedURLs) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Aplica la retención ahora (botón «Aplicar retención» del Mac).
    public func applyRetentionNow() async {
        do {
            try applyRetentionPolicy()
        } catch {
            lastError = "No se pudo aplicar la retención: \(error.localizedDescription)"
        }
        await scanBackups()
    }

    /// Copias de la lista actual que la retención borraría.
    public var backupsBeyondRetentionCount: Int {
        let entries = backups.map {
            RetentionEntry(url: $0.url, createdAt: $0.manifest.createdAt, note: $0.manifest.note)
        }
        return Self.retentionVictims(entries: entries, protecting: []).count
    }

    struct RetentionEntry {
        let url: URL
        let createdAt: Date
        let isEmergency: Bool

        init(url: URL, createdAt: Date, note: String?) {
            self.url = url
            self.createdAt = createdAt
            self.isEmergency = note?.hasPrefix(AppleBackupService.emergencyNotePrefix) == true
        }
    }

    /// Copias a borrar. Se conservan:
    /// - las `recentRetentionCount` copias normales más recientes;
    /// - de las normales más antiguas, la más reciente de cada semana aún no
    ///   representada, hasta `weeklyRetentionCount` semanas;
    /// - las `emergencyRetentionCount` copias de emergencia más recientes, en cupo
    ///   aparte, para que restaurar varias veces no eche a las copias normales;
    /// - las `legacyRetentionCount` más recientes de cualquier tipo (regla anterior);
    /// - y nunca se borra una copia protegida (p. ej. la que se está restaurando).
    nonisolated static func retentionVictims(
        entries: [RetentionEntry],
        protecting protectedURLs: Set<URL>,
        calendar: Calendar = .current
    ) -> [URL] {
        func key(_ url: URL) -> String { url.standardizedFileURL.path }
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        var kept = Set(protectedURLs.map(key))

        sorted.prefix(legacyRetentionCount).forEach { kept.insert(key($0.url)) }
        sorted.filter(\.isEmergency).prefix(emergencyRetentionCount).forEach { kept.insert(key($0.url)) }

        let normals = sorted.filter { !$0.isEmergency }
        let recent = normals.prefix(recentRetentionCount)
        recent.forEach { kept.insert(key($0.url)) }

        func week(_ date: Date) -> Date? { calendar.dateInterval(of: .weekOfYear, for: date)?.start }
        var coveredWeeks = Set(recent.compactMap { week($0.createdAt) })
        var weeklyKept = 0
        for entry in normals.dropFirst(recentRetentionCount) where weeklyKept < weeklyRetentionCount {
            guard let entryWeek = week(entry.createdAt), !coveredWeeks.contains(entryWeek) else { continue }
            coveredWeeks.insert(entryWeek)
            kept.insert(key(entry.url))
            weeklyKept += 1
        }

        return sorted.map(\.url).filter { !kept.contains(key($0)) }
    }

    // MARK: - Schema Compatibility

    /// Una copia de una versión de datos más nueva no se puede abrir con esta app.
    nonisolated static func isSchemaCompatible(backupSchemaVersion: Int?, currentSchemaVersion: Int?) -> Bool {
        guard let backupSchemaVersion, let currentSchemaVersion else { return true }
        return backupSchemaVersion <= currentSchemaVersion
    }

    private func ensureSchemaCompatible(_ manifest: AppleBackupManifest) throws {
        guard Self.isSchemaCompatible(
            backupSchemaVersion: manifest.schemaVersion,
            currentSchemaVersion: getSchemaVersion(of: databaseURL.path)
        ) else {
            throw NSError(
                domain: "AppleBackupService",
                code: 426,
                userInfo: [NSLocalizedDescriptionKey: "Esta copia es de una versión más nueva de la app. Actualiza la app para restaurarla."]
            )
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

    /// Comprueba que la ruta es una base de datos SQLite real y no vacía.
    ///
    /// Un fichero de 0 bytes supera cualquier verificación por checksum (el hash del vacío
    /// es válido y estable), así que el checksum por sí solo no protege de copiar o
    /// restaurar la nada. Se valida tamaño y la cabecera mágica de SQLite.
    private func validateUsableDatabase(at url: URL, context: String) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "AppleBackupService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No se encontró \(context) en \(url.path)."]
            )
        }

        let size = (try? getFileSize(url)) ?? 0
        guard size > 0 else {
            throw NSError(
                domain: "AppleBackupService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "\(context.prefix(1).uppercased())\(context.dropFirst()) está vacía (0 bytes). Operación cancelada para no destruir datos."]
            )
        }

        // Cabecera SQLite: los 16 primeros bytes son "SQLite format 3" + NUL.
        let expectedHeader = Array("SQLite format 3\u{0}".utf8)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw NSError(
                domain: "AppleBackupService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo leer \(context) para validarla."]
            )
        }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: expectedHeader.count)) ?? Data()
        guard Array(header) == expectedHeader else {
            throw NSError(
                domain: "AppleBackupService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "\(context.prefix(1).uppercased())\(context.dropFirst()) no es una base de datos SQLite válida. Operación cancelada."]
            )
        }
    }

    private func loadChecksumKeys(in packageURL: URL) throws -> [String] {
        let data = try Data(contentsOf: packageURL.appendingPathComponent("checksums.json"))
        return Array(try JSONDecoder().decode([String: String].self, from: data).keys)
    }

    private func validatedPackageFileURL(relativePath: String, packageURL: URL) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw NSError(
                domain: "AppleBackupService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "La copia contiene una ruta no segura: \(relativePath)"]
            )
        }
        let rootURL = packageURL.resolvingSymlinksInPath().standardizedFileURL
        let root = rootURL.path + "/"
        let unresolvedCandidate = packageURL.appendingPathComponent(relativePath).standardizedFileURL
        let candidate = unresolvedCandidate.resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root) else {
            throw NSError(
                domain: "AppleBackupService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "La copia intenta acceder fuera de su paquete."]
            )
        }
        var componentURL = packageURL
        for component in relativePath.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            try rejectSymbolicLink(at: componentURL, description: relativePath)
        }
        return candidate
    }

    private func stageDirectory(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: source.path) {
            try rejectSymbolicLink(at: source, description: source.lastPathComponent)
            let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: nil)
            while let itemURL = enumerator?.nextObject() as? URL {
                try rejectSymbolicLink(at: itemURL, description: itemURL.lastPathComponent)
            }
            try copyDirectoryContents(from: source, to: destination)
        }
    }

    private func rejectSymbolicLink(at url: URL, description: String) throws {
        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw NSError(
                domain: "AppleBackupService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "La copia contiene un enlace simbólico no admitido: \(description)"]
            )
        }
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

// MARK: - Copias automáticas

/// Hasta 2026-10 la frecuencia elegida en Ajustes se guardaba pero nadie la leía:
/// la app nunca hacía copias por su cuenta. Las únicas copias "automáticas" eran
/// las de emergencia previas a restaurar.
extension AppleBackupService {
    nonisolated static let automaticBackupNote = "Copia automática"
    nonisolated static let backupFrequencyDefaultsKey = "settings.backupFrequency"
    nonisolated static let lastAutomaticAttemptDefaultsKey = "backup.automatic.lastAttemptAt"
    /// Tras un intento fallido no se reintenta en este tiempo, para no repetir el
    /// mismo error en cada cambio de ventana.
    nonisolated static let automaticRetryInterval: TimeInterval = 60 * 60
    /// Margen tras volver a la app antes de copiar, para no competir con la carga inicial.
    nonisolated static let automaticActivationDelay: Duration = .seconds(45)

    /// ¿Toca una copia automática? Regla pura, sin disco, para poder probarla.
    nonisolated static func isAutomaticBackupDue(
        frequency: BackupFrequency,
        lastBackupAt: Date?,
        lastAttemptAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if frequency == .manual { return false }
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < automaticRetryInterval {
            return false
        }
        guard let lastBackupAt else { return true }
        switch frequency {
        // Una copia con fecha futura (reloj cambiado, copia importada) no debe
        // bloquear las copias hasta que el tiempo real la alcance.
        case .daily:
            return !calendar.isDate(lastBackupAt, inSameDayAs: now)
        case .weekly:
            let elapsed = now.timeIntervalSince(lastBackupAt)
            return elapsed >= 7 * 86_400 || elapsed < -86_400
        case .manual:
            return false
        }
    }

    private var configuredFrequency: BackupFrequency {
        let raw = UserDefaults.standard.string(forKey: Self.backupFrequencyDefaultsKey)
        return raw.flatMap(BackupFrequency.init(rawValue:)) ?? .weekly
    }

    /// Llamar desde el cambio de `scenePhase` de cada app.
    /// - `.active`: comprueba tras un margen (se cancela si la app sale antes).
    /// - `.background`: comprueba ya; en iOS pide tiempo extra al sistema.
    public func handleScenePhaseForAutomaticBackup(isActive: Bool) {
        automaticBackupTask?.cancel()
        if isActive {
            automaticBackupTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.automaticActivationDelay)
                guard !Task.isCancelled else { return }
                await self?.runAutomaticBackupIfDue()
            }
        } else {
            #if os(iOS)
            var taskID: UIBackgroundTaskIdentifier = .invalid
            taskID = UIApplication.shared.beginBackgroundTask(withName: "Copia automática") {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
            automaticBackupTask = Task { @MainActor [weak self] in
                await self?.runAutomaticBackupIfDue()
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            }
            #else
            automaticBackupTask = Task { @MainActor [weak self] in
                await self?.runAutomaticBackupIfDue()
            }
            #endif
        }
    }

    /// Hace la copia si toca. Silenciosa: si falla no muestra aviso, solo deja
    /// constancia y espera `automaticRetryInterval` antes de volver a probar.
    @discardableResult
    func runAutomaticBackupIfDue(now: Date = Date()) async -> Bool {
        guard operationState == .idle, !needsRestart else { return false }
        await scanBackups()
        let lastUsable = backups.first { !$0.hasEmptyDatabase && $0.verificationError == nil }
        let defaults = UserDefaults.standard
        let lastAttempt = defaults.object(forKey: Self.lastAutomaticAttemptDefaultsKey) as? Date
        guard Self.isAutomaticBackupDue(
            frequency: configuredFrequency,
            lastBackupAt: lastUsable?.manifest.createdAt,
            lastAttemptAt: lastAttempt,
            now: now
        ) else { return false }
        // Una instalación nueva o una base vacía no tiene nada que proteger.
        guard (try? validateUsableDatabase(at: databaseURL, context: "la base de datos activa")) != nil else {
            return false
        }
        guard operationState == .idle, !needsRestart else { return false }
        defaults.set(now, forKey: Self.lastAutomaticAttemptDefaultsKey)
        let previousError = lastError
        do {
            _ = try await createBackup(note: Self.automaticBackupNote)
            return true
        } catch {
            lastError = previousError
            print("[AppleBackupService] Copia automática fallida: \(error.localizedDescription)")
            return false
        }
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
