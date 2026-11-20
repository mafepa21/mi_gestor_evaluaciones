import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ApplePortableBackupImportSelection: Identifiable {
    let id = UUID()
    let url: URL
    let format: ApplePortableBackupFormat
}

extension UTType {
    static var miGestorEncryptedBackup: UTType {
        UTType(filenameExtension: "migestorbackupx") ?? .data
    }

    static var miGestorLegacyBackup: UTType {
        UTType(filenameExtension: "migestorbackup") ?? .folder
    }
}

struct EncryptedBackupExportSheet: View {
    let backup: AppleBackupDescriptor
    let portalSummary: WebPortalBackupVaultSummary
    let onExport: (URL, String, Bool) async throws -> Void
    var onFinished: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var includePortalKeys = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var exportedURL: URL?
    @State private var showingShareSheet = false
    #endif

    init(
        backup: AppleBackupDescriptor,
        portalSummary: WebPortalBackupVaultSummary = WebPortalBackupVault.currentSummary(),
        onExport: @escaping (URL, String, Bool) async throws -> Void,
        onFinished: (() async -> Void)? = nil
    ) {
        self.backup = backup
        self.portalSummary = portalSummary
        self.onExport = onExport
        self.onFinished = onFinished
    }

    private var passwordIsValid: Bool {
        password.count >= 12 && password == confirmation && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Copia portable protegida", systemImage: "lock.shield.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(IOSAppStyle.info)

                    Text("La contraseña cifra los datos antes de compartirlos. No se guarda ni se puede recuperar: consérvala en un lugar seguro.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        SecureField("Contraseña (mínimo 12 caracteres)", text: $password)
                            .textContentType(.newPassword)
                        SecureField("Repetir contraseña", text: $confirmation)
                            .textContentType(.newPassword)

                        if !confirmation.isEmpty && password != confirmation {
                            Label("Las contraseñas no coinciden.", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(IOSAppStyle.danger)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    if !portalSummary.isEmpty {
                        Toggle(isOn: $includePortalKeys) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Incluir llaves del portal del alumnado")
                                    .font(.callout.weight(.semibold))
                                Text("\(portalSummary.subtitle) · cifradas con esta misma contraseña")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(IOSAppStyle.danger)
                    }

                    Button(action: beginExport) {
                        HStack(spacing: 8) {
                            if isWorking { ProgressView().controlSize(.small) }
                            Label(isWorking ? "Protegiendo copia…" : "Crear copia cifrada", systemImage: "lock.doc.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!passwordIsValid)
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
            }
            .navigationTitle("Exportar copia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        #if os(iOS)
        .sheet(isPresented: $showingShareSheet, onDismiss: finishIOSExport) {
            if let exportedURL {
                ShareSheet(activityItems: [exportedURL])
            }
        }
        #endif
    }

    private func beginExport() {
        guard passwordIsValid else { return }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.miGestorEncryptedBackup]
        panel.nameFieldStringValue = backup.url.deletingPathExtension().lastPathComponent + ".migestorbackupx"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        performExport(to: destinationURL)
        #else
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(backup.url.deletingPathExtension().lastPathComponent + "-\(UUID().uuidString.prefix(6)).migestorbackupx")
        performExport(to: destinationURL)
        #endif
    }

    private func performExport(to destinationURL: URL) {
        isWorking = true
        errorMessage = nil
        let passwordForOperation = password
        let includeKeys = includePortalKeys && !portalSummary.isEmpty
        Task {
            defer {
                password = ""
                confirmation = ""
                isWorking = false
            }
            do {
                let hasSecurityScope = destinationURL.startAccessingSecurityScopedResource()
                defer { if hasSecurityScope { destinationURL.stopAccessingSecurityScopedResource() } }
                try await onExport(destinationURL, passwordForOperation, includeKeys)
                #if os(iOS)
                exportedURL = destinationURL
                showingShareSheet = true
                #else
                await onFinished?()
                dismiss()
                #endif
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    private func finishIOSExport() {
        if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
        exportedURL = nil
        Task { await onFinished?() }
        dismiss()
    }
    #endif
}

struct PortableBackupImportSheet: View {
    let selection: ApplePortableBackupImportSelection
    let onImport: (URL, String?) async throws -> WebPortalBackupVault?
    var onFinished: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var importedVault: WebPortalBackupVault?
    @State private var localPortalSummary: WebPortalBackupVaultSummary?

    private var isEncrypted: Bool { selection.format == .encryptedV1 }
    private var canImport: Bool { !isWorking && (!isEncrypted || !password.isEmpty) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let vault = importedVault {
                        portalVaultConfirmation(vault)
                    } else {
                        importForm
                    }
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
            }
            .navigationTitle(importedVault == nil ? "Importar copia" : "Llaves del portal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importedVault == nil ? "Cancelar" : "Omitir") {
                        finishWithoutPortalRestore()
                    }
                    .disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    @ViewBuilder
    private var importForm: some View {
        Label(
            isEncrypted ? "Copia cifrada" : "Copia compatible anterior",
            systemImage: isEncrypted ? "lock.doc.fill" : "clock.arrow.circlepath"
        )
        .font(.title3.weight(.semibold))
        .foregroundStyle(IOSAppStyle.info)

        Text(
            isEncrypted
                ? "Introduce la contraseña con la que se creó. Si no coincide o el archivo fue alterado, la importación se cancelará sin tocar tus datos."
                : "Esta copia no está cifrada. Se validará por completo antes de añadirse al historial."
        )
        .font(.body)
        .foregroundStyle(.secondary)

        if isEncrypted {
            SecureField("Contraseña de la copia", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
        }

        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(IOSAppStyle.danger)
        }

        Button(action: beginImport) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().controlSize(.small) }
                Label(isWorking ? "Validando copia…" : "Importar copia", systemImage: "square.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canImport)
    }

    @ViewBuilder
    private func portalVaultConfirmation(_ vault: WebPortalBackupVault) -> some View {
        let hasLocalKeys = (localPortalSummary?.isEmpty == false)
        Label("Copia importada con llaves del portal", systemImage: "key.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(IOSAppStyle.info)

        Text("Esta copia cifrada incluye las llaves del portal del alumnado (\(vault.summary.subtitle)). Si las restauras ahora en el Llavero de este equipo, podrás seguir publicando sin reinvitar a nadie.")
            .font(.body)
            .foregroundStyle(.secondary)

        if hasLocalKeys, let local = localPortalSummary {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Este equipo ya tiene llaves del portal guardadas (\(local.subtitle)). Si restauras las de la copia, las sustituirán.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }

        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(IOSAppStyle.danger)
        }

        HStack(spacing: 12) {
            if hasLocalKeys {
                Button("Restaurar llaves") { restorePortalKeys(vault) }
                    .controlSize(.large)
                Button("Omitir llaves") { finishWithoutPortalRestore() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                Button("Omitir llaves") { finishWithoutPortalRestore() }
                    .controlSize(.large)
                Button("Restaurar llaves") { restorePortalKeys(vault) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func beginImport() {
        guard canImport else { return }
        isWorking = true
        errorMessage = nil
        let passwordForOperation = isEncrypted ? password : nil
        Task {
            defer {
                password = ""
                isWorking = false
            }
            do {
                let hasSecurityScope = selection.url.startAccessingSecurityScopedResource()
                defer { if hasSecurityScope { selection.url.stopAccessingSecurityScopedResource() } }
                let vault = try await onImport(selection.url, passwordForOperation)
                if let vault, !vault.summary.isEmpty {
                    localPortalSummary = WebPortalBackupVault.currentSummary()
                    importedVault = vault
                } else {
                    await onFinished?()
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restorePortalKeys(_ vault: WebPortalBackupVault) {
        errorMessage = nil
        do {
            _ = try vault.restore()
            importedVault = nil
            Task {
                await onFinished?()
                dismiss()
            }
        } catch {
            errorMessage = "No se pudieron restaurar las llaves del portal: \(error.localizedDescription)"
        }
    }

    private func finishWithoutPortalRestore() {
        importedVault = nil
        Task {
            await onFinished?()
            dismiss()
        }
    }
}
