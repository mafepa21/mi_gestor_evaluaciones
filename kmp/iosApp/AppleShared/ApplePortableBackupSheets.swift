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
    let onExport: (URL, String) async throws -> Void
    var onFinished: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var exportedURL: URL?
    @State private var showingShareSheet = false
    #endif

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
        Task {
            defer {
                password = ""
                confirmation = ""
                isWorking = false
            }
            do {
                let hasSecurityScope = destinationURL.startAccessingSecurityScopedResource()
                defer { if hasSecurityScope { destinationURL.stopAccessingSecurityScopedResource() } }
                try await onExport(destinationURL, passwordForOperation)
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
    let onImport: (URL, String?) async throws -> Void
    var onFinished: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isEncrypted: Bool { selection.format == .encryptedV1 }
    private var canImport: Bool { !isWorking && (!isEncrypted || !password.isEmpty) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
            }
            .navigationTitle("Importar copia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
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
                try await onImport(selection.url, passwordForOperation)
                await onFinished?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
