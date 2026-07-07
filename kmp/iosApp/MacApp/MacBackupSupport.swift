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
        case checksumMismatch = "Checksum distinto"
        case missingFile = "Archivo perdido"
    }

    let id: UUID
    let descriptor: AppleBackupDescriptor

    var databaseURL: URL { descriptor.url.appendingPathComponent("database.sqlite") }
    var manifestURL: URL? { descriptor.url.appendingPathComponent("manifest.json") }
    var manifest: BackupManifest? {
        BackupManifest(
            id: self.id,
            createdAt: descriptor.manifest.createdAt,
            appVersion: descriptor.manifest.appVersion,
            databaseFileName: "database.sqlite",
            databaseSizeBytes: descriptor.manifest.databaseSizeBytes,
            checksumSHA256: descriptor.manifest.checksumSHA256,
            sourceDatabasePath: "",
            note: descriptor.manifest.note
        )
    }
    
    var createdAt: Date { descriptor.manifest.createdAt }
    var sizeBytes: Int64 { descriptor.sizeBytes }
    var checksumSHA256: String? { descriptor.manifest.checksumSHA256 }
    
    var verificationState: VerificationState {
        if descriptor.isVerified {
            if descriptor.verificationError != nil {
                return .checksumMismatch
            } else {
                return .verified
            }
        } else {
            return .verified
        }
    }

    var displayName: String { descriptor.displayName }
    var path: String { descriptor.url.path }
    var isRestorable: Bool { descriptor.isVerified && descriptor.verificationError == nil }
    
    init(descriptor: AppleBackupDescriptor) {
        self.descriptor = descriptor
        self.id = Self.stableID(for: descriptor.url)
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
}

@MainActor
final class MacBackupStore: ObservableObject {
    @Published private(set) var backups: [MacBackupRecord] = []
    @Published var selectedBackupID: MacBackupRecord.ID?
    @Published private(set) var operationState: MacPremiumOperationStateKind = .idle
    @Published private(set) var lastMessage = "Copias listas."
    @Published var errorMessage: String?
    @Published private(set) var isCreatingBackup = false

    private let service = AppleBackupService.shared

    init(bridge: KmpBridge) {
        // Bridged directly to the shared service
    }

    var backupDirectoryURL: URL { service.backupsDirectoryURL }

    var selectedBackup: MacBackupRecord? {
        guard let selectedBackupID else { return backups.first }
        return backups.first { $0.id == selectedBackupID } ?? backups.first
    }

    var latestBackup: MacBackupRecord? { backups.first }
    var protectedStatus: String {
        if backups.isEmpty { return "Desprotegido" }
        let newest = backups[0].createdAt
        let daysAgo = Calendar.current.dateComponents([.day], from: newest, to: Date()).day ?? 0
        if daysAgo > 7 {
            return "Desactualizado"
        }
        return "Protegido"
    }
    var retentionSummary: String { "10 copias" }
    var extraCopiesCount: Int { max(0, backups.count - 10) }

    func loadBackups() async {
        operationState = .loading("Escaneando")
        await service.scanBackups()
        
        self.backups = service.backups.map { MacBackupRecord(descriptor: $0) }
        
        if selectedBackupID == nil || !backups.contains(where: { $0.id == selectedBackupID }) {
            selectedBackupID = backups.first?.id
        }
        
        lastMessage = backups.isEmpty ? "Todavía no hay copias locales." : "\(backups.count) copias encontradas."
        operationState = .idle
    }

    func createBackup(note: String? = nil) async {
        guard !isCreatingBackup else { return }
        isCreatingBackup = true
        errorMessage = nil
        operationState = .saving("Creando copia")
        defer { isCreatingBackup = false }

        do {
            _ = try await service.createBackup(note: note)
            lastMessage = "Copia de seguridad creada con éxito."
            operationState = .saved("Creada")
            await loadBackups()
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
        
        let verified = await service.verifyBackup(backup.descriptor)
        if let err = verified.verificationError {
            lastMessage = "Error de integridad: \(err)"
            operationState = .failed("Corrupta")
        } else {
            lastMessage = "Copia 100% válida y verificada."
            operationState = .saved("Verificada")
        }
        await loadBackups()
    }

    func restoreSelectedBackup() async {
        guard let backup = selectedBackup else { return }
        operationState = .saving("Restaurando")
        
        do {
            try await service.restoreBackup(backup.descriptor)
            lastMessage = "Copia restaurada con éxito. Reiniciando..."
            operationState = .saved("Restaurada")
            await loadBackups()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            lastMessage = message
            operationState = .failed("Error restaurando")
        }
    }

    func openBackupDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: service.backupsDirectoryURL.path)
    }

    func openSelectedInFinder() {
        guard let selectedBackup else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: selectedBackup.descriptor.url.path)
    }

    func copySelectedPathToPasteboard() {
        guard let selectedBackup else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedBackup.descriptor.url.path, forType: .string)
        lastMessage = "Ruta copiada al portapapeles."
    }

    func exportSelectedBackup() {
        guard let selectedBackup else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = selectedBackup.descriptor.url.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        
        operationState = .saving("Exportando")
        Task {
            do {
                try await service.exportBackup(selectedBackup.descriptor, to: targetURL)
                lastMessage = "Backup exportado con éxito a \(targetURL.path)"
                operationState = .saved("Exportado")
            } catch {
                lastMessage = error.localizedDescription
                operationState = .failed("Error exportando")
            }
        }
    }

    func deleteBackupsBeyondRetention() async {
        // Enforced automatically on create, but we scan to reload
        await loadBackups()
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
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let macBackupRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .full
        return formatter
    }()
}

extension Int64 {
    var macBackupFileSizeText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
