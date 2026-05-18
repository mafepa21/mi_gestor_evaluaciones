import AppKit
import CryptoKit
import Foundation
import MiGestorKit
import SwiftUI

struct BackupManifest: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let appVersion: String
    let databaseFileName: String
    let databaseSizeBytes: Int64
    let checksumSHA256: String
    let sourceDatabasePath: String
    let note: String?
}

struct MacBackupRecord: Identifiable, Hashable {
    enum VerificationState: String, Hashable {
        case verified = "Verificada"
        case missingManifest = "Sin manifest"
        case checksumMismatch = "Checksum distinto"
        case missingFile = "Archivo perdido"
        case unreadable = "No legible"
    }

    let id: UUID
    let databaseURL: URL
    let manifestURL: URL?
    let manifest: BackupManifest?
    let createdAt: Date
    let sizeBytes: Int64
    let checksumSHA256: String?
    let verificationState: VerificationState

    var displayName: String { databaseURL.lastPathComponent }
    var path: String { databaseURL.path }
    var isRestorable: Bool { verificationState == .verified }
}

@MainActor
final class MacBackupStore: ObservableObject {
    @Published private(set) var backups: [MacBackupRecord] = []
    @Published var selectedBackupID: MacBackupRecord.ID?
    @Published private(set) var operationState: MacPremiumOperationStateKind = .idle
    @Published private(set) var backupDirectoryURL: URL
    @Published private(set) var lastMessage = "Backups listos."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCreatingBackup = false

    private let bridge: KmpBridge
    private let backupService: MacBackupService
    private let fileManager: FileManager
    private let retentionLimit = 10
    private let manifestFileName = "backup_manifest.json"

    init(bridge: KmpBridge, fileManager: FileManager = .default) {
        self.bridge = bridge
        self.fileManager = fileManager
        self.backupService = MacBackupService(fileManager: fileManager)
        self.backupDirectoryURL = Self.defaultBackupDirectoryURL(fileManager: fileManager)
    }

    var selectedBackup: MacBackupRecord? {
        guard let selectedBackupID else { return backups.first }
        return backups.first { $0.id == selectedBackupID } ?? backups.first
    }

    var latestBackup: MacBackupRecord? { backups.first }
    var protectedStatus: String { latestBackup == nil ? "Pendiente" : "Protegido" }
    var retentionSummary: String { "\(retentionLimit) copias" }
    var extraCopiesCount: Int { max(0, backups.count - retentionLimit) }

    func loadBackups() async {
        operationState = .loading("Escaneando")
        do {
            try ensureBackupDirectory()
            let records = try scanBackupDirectory()
            backups = records
            if selectedBackupID == nil || !records.contains(where: { $0.id == selectedBackupID }) {
                selectedBackupID = records.first?.id
            }
            lastMessage = records.isEmpty ? "Todavía no hay copias locales." : "\(records.count) copias encontradas."
            operationState = .idle
        } catch {
            lastMessage = error.localizedDescription
            operationState = .failed("No se pudo escanear")
        }
    }

    func createBackup(note: String? = nil) async {
        guard !isCreatingBackup else { return }
        isCreatingBackup = true
        errorMessage = nil
        operationState = .saving("Creando backup")
        defer { isCreatingBackup = false }

        do {
            let backup = try await backupService.createBackup(note: note)
            backupDirectoryURL = backup.databaseURL.deletingLastPathComponent().deletingLastPathComponent()
            lastMessage = "Backup creado en \(backup.databaseURL.path)"
            operationState = .saved("Backup creado")
            await loadBackups()
            selectedBackupID = backup.id
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            lastMessage = message
            operationState = .failed("Error creando")
        }
    }

    func verifySelectedBackup() async {
        guard let backup = selectedBackup else { return }
        operationState = .loading("Verificando")
        do {
            _ = try validateForRestore(backup)
            lastMessage = "Integridad verificada para \(backup.displayName)."
            operationState = .saved("Verificada")
            await loadBackups()
        } catch {
            lastMessage = error.localizedDescription
            operationState = .failed("Verificación fallida")
        }
    }

    func restoreSelectedBackup() async {
        guard let backup = selectedBackup else { return }
        operationState = .saving("Restaurando")
        do {
            _ = try validateForRestore(backup)
            _ = try await backupService.createBackup(note: "Copia de emergencia antes de restaurar \(backup.displayName)")
            let restored = try await bridge.restoreLocalBackup(from: backup.databaseURL.path)
            guard restored else { throw MacBackupError.restoreRejected }
            lastMessage = "Backup restaurado desde \(backup.databaseURL.path)"
            operationState = .saved("Restaurado")
            await loadBackups()
        } catch {
            lastMessage = error.localizedDescription
            operationState = .failed("Error restaurando")
        }
    }

    func openBackupDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([backupDirectoryURL])
    }

    func openSelectedInFinder() {
        guard let selectedBackup else {
            openBackupDirectory()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([selectedBackup.databaseURL])
    }

    func copySelectedPathToPasteboard() {
        guard let selectedBackup else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedBackup.path, forType: .string)
        lastMessage = "Ruta copiada."
        operationState = .saved("Ruta copiada")
    }

    func exportSelectedBackup() {
        guard let selectedBackup else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = selectedBackup.databaseURL.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: selectedBackup.databaseURL, to: targetURL)
            lastMessage = "Backup exportado a \(targetURL.path)"
            operationState = .saved("Exportado")
        } catch {
            lastMessage = error.localizedDescription
            operationState = .failed("No exportado")
        }
    }

    func deleteBackupsBeyondRetention() async {
        let stale = Array(backups.dropFirst(retentionLimit))
        guard !stale.isEmpty else { return }
        operationState = .saving("Limpiando")
        do {
            for backup in stale {
                let container = backup.databaseURL.deletingLastPathComponent()
                if backup.manifestURL?.lastPathComponent == manifestFileName {
                    try fileManager.removeItem(at: container)
                } else {
                    if let manifestURL = backup.manifestURL {
                        try? fileManager.removeItem(at: manifestURL)
                    }
                    try fileManager.removeItem(at: backup.databaseURL)
                }
            }
            lastMessage = "\(stale.count) copias antiguas eliminadas."
            operationState = .saved("Retención aplicada")
            await loadBackups()
        } catch {
            lastMessage = error.localizedDescription
            operationState = .failed("No se pudo limpiar")
        }
    }

    private func scanBackupDirectory() throws -> [MacBackupRecord] {
        guard let enumerator = fileManager.enumerator(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [MacBackupRecord] = []
        for case let url as URL in enumerator {
            guard Self.isDatabaseBackup(url) else { continue }
            records.append(try record(for: url))
        }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private func record(for databaseURL: URL) throws -> MacBackupRecord {
        let manifestURL = manifestURL(for: databaseURL)
        let manifest = manifestURL.flatMap { try? readManifest(from: $0) }
        let fileExists = fileManager.fileExists(atPath: databaseURL.path)
        let size = (try? Self.fileSize(databaseURL, fileManager: fileManager)) ?? manifest?.databaseSizeBytes ?? 0
        let checksum = fileExists ? try? Self.sha256Hex(for: databaseURL) : nil
        let state: MacBackupRecord.VerificationState
        if !fileExists {
            state = .missingFile
        } else if let manifest {
            state = checksum == manifest.checksumSHA256 && size == manifest.databaseSizeBytes ? .verified : .checksumMismatch
        } else {
            state = .missingManifest
        }

        return MacBackupRecord(
            id: manifest?.id ?? Self.stableID(for: databaseURL),
            databaseURL: databaseURL,
            manifestURL: manifestURL,
            manifest: manifest,
            createdAt: manifest?.createdAt ?? Self.creationDate(for: databaseURL, fileManager: fileManager),
            sizeBytes: size,
            checksumSHA256: checksum,
            verificationState: state
        )
    }

    private func validateForRestore(_ backup: MacBackupRecord) throws -> BackupManifest? {
        guard fileManager.fileExists(atPath: backup.databaseURL.path) else { throw MacBackupError.missingFile }
        guard let manifest = backup.manifest else {
            throw MacBackupError.missingManifest
        }
        let checksum = try Self.sha256Hex(for: backup.databaseURL)
        let size = try Self.fileSize(backup.databaseURL, fileManager: fileManager)
        guard checksum == manifest.checksumSHA256, size == manifest.databaseSizeBytes else {
            throw MacBackupError.integrityFailed
        }
        return manifest
    }

    private func ensureBackupDirectory() throws {
        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
    }

    private func manifestURL(for databaseURL: URL) -> URL? {
        let packageManifestURL = databaseURL.deletingLastPathComponent().appendingPathComponent(manifestFileName)
        if fileManager.fileExists(atPath: packageManifestURL.path) {
            return packageManifestURL
        }
        let sidecarURL = databaseURL.deletingPathExtension().appendingPathExtension("backup_manifest.json")
        if fileManager.fileExists(atPath: sidecarURL.path) {
            return sidecarURL
        }
        return nil
    }

    private func readManifest(from url: URL) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupManifest.self, from: Data(contentsOf: url))
    }

    nonisolated fileprivate static func writeManifest(_ manifest: BackupManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private static func isDatabaseBackup(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".sqlite") || name.hasSuffix(".db")
    }

    nonisolated fileprivate static func fileSize(_ url: URL, fileManager: FileManager) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func creationDate(for url: URL, fileManager: FileManager) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.creationDate] as? Date)
            ?? (attributes?[.modificationDate] as? Date)
            ?? Date.distantPast
    }

    nonisolated fileprivate static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func stableID(for url: URL) -> UUID {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    nonisolated fileprivate static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }

    private static func defaultBackupDirectoryURL(fileManager: FileManager) -> URL {
        defaultAppSupportDirectoryURL(fileManager: fileManager).appendingPathComponent("backups", isDirectory: true)
    }

    private static func defaultAppSupportDirectoryURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("MiGestor", isDirectory: true)
    }
}

struct MacBackupSnapshot: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let directoryURL: URL
    let databaseURL: URL
    let manifest: BackupManifest
    let verificationState: MacBackupRecord.VerificationState
}

final class MacBackupService {
    private let fileManager: FileManager
    private let manifestFileName = "backup_manifest.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createBackup(note: String?) async throws -> MacBackupSnapshot {
        let sourceDatabaseURL = try resolveDatabaseURL()
        try validateDatabaseExists(sourceDatabaseURL)

        let destinationDirectory = try makeBackupDirectory()
        let copiedDatabaseURL = destinationDirectory.appendingPathComponent(sourceDatabaseURL.lastPathComponent)
        try copySQLiteDatabaseBundle(from: sourceDatabaseURL, to: copiedDatabaseURL)

        let checksum = try MacBackupStore.sha256Hex(for: copiedDatabaseURL)
        let size = try MacBackupStore.fileSize(copiedDatabaseURL, fileManager: fileManager)
        let manifest = BackupManifest(
            id: UUID(),
            createdAt: Date(),
            appVersion: MacBackupStore.appVersion.isEmpty ? "unknown" : MacBackupStore.appVersion,
            databaseFileName: copiedDatabaseURL.lastPathComponent,
            databaseSizeBytes: size,
            checksumSHA256: checksum,
            sourceDatabasePath: sourceDatabaseURL.path,
            note: note
        )

        try MacBackupStore.writeManifest(manifest, to: destinationDirectory.appendingPathComponent(manifestFileName))
        return MacBackupSnapshot(
            id: manifest.id,
            createdAt: manifest.createdAt,
            directoryURL: destinationDirectory,
            databaseURL: copiedDatabaseURL,
            manifest: manifest,
            verificationState: .verified
        )
    }

    private func resolveDatabaseURL() throws -> URL {
        let candidates = [
            MacosDriverKt.getMacosAppDataPath(fileName: "desktop_mi_gestor_kmp.db"),
            MacosDriverKt.getMacosAppDataPath(fileName: "mi_gestor_kmp.db")
        ].map { URL(fileURLWithPath: $0) }

        if let existing = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return existing
        }

        throw MacBackupError.databasePathUnavailable(candidates.map(\.path).joined(separator: "\n"))
    }

    private func validateDatabaseExists(_ sourceDatabaseURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceDatabaseURL.path) else {
            throw MacBackupError.databaseNotFound(sourceDatabaseURL.path)
        }
    }

    private func makeBackupDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let rootURL = MacosDriverKt.getMacosAppDataPath(fileName: "backups")
        let directoryURL = URL(fileURLWithPath: rootURL, isDirectory: true)
            .appendingPathComponent("backup_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func copySQLiteDatabaseBundle(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItemSafely(from: sourceURL, to: destinationURL)

        for suffix in ["-wal", "-shm"] {
            let sourceSidecar = URL(fileURLWithPath: sourceURL.path + suffix)
            let destinationSidecar = URL(fileURLWithPath: destinationURL.path + suffix)
            if fileManager.fileExists(atPath: sourceSidecar.path) {
                try fileManager.copyItemSafely(from: sourceSidecar, to: destinationSidecar)
            }
        }
    }
}

enum MacBackupError: LocalizedError {
    case missingFile
    case missingManifest
    case integrityFailed
    case restoreRejected
    case databasePathUnavailable(String)
    case databaseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "La copia seleccionada ya no existe en disco."
        case .missingManifest:
            return "La copia no tiene manifest verificable. Crea un backup nuevo antes de restaurar esta copia."
        case .integrityFailed:
            return "La copia no coincide con su checksum o tamaño declarado."
        case .restoreRejected:
            return "El servicio de restauración rechazó la copia seleccionada."
        case .databasePathUnavailable(let candidates):
            return "No se encontró la base de datos local para crear el backup. Rutas comprobadas:\n\(candidates)"
        case .databaseNotFound(let path):
            return "No existe la base de datos local en \(path)."
        }
    }
}

extension FileManager {
    func copyItemSafely(from source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }

        try createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try copyItem(at: source, to: destination)
    }
}

extension Int64 {
    var macBackupFileSizeText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var macBackupDateText: String {
        Self.macBackupDateFormatter.string(from: self)
    }

    var macBackupRelativeText: String {
        Self.macBackupRelativeFormatter.localizedString(for: self, relativeTo: Date())
    }

    private static let macBackupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let macBackupRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
