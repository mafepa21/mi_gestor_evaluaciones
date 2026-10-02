import SwiftUI
import AppKit

struct MacBackupInspectorView: View {
    @ObservedObject var store: MacBackupStore
    @State private var restoreCandidate: MacBackupRecord?
    @State private var showRestoreConfirmation = false
    @State private var backupToExport: AppleBackupDescriptor?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                if let backup = store.selectedBackup {
                    MacPremiumInspectorHeader(
                        title: "Detalle del backup",
                        subtitle: backup.displayName
                    ) {
                        MacStatusPill(
                            label: backup.verificationState.rawValue,
                            isActive: backup.verificationState == .verified,
                            tint: tint(for: backup.verificationState)
                        )
                    }

                    MacPremiumInspectorSection(title: "Metadatos") {
                        inspectorRow("Fecha", backup.createdAt.macBackupDateText)
                        inspectorRow("Ruta", backup.path)
                        inspectorRow("Tamaño", backup.sizeBytes.macBackupFileSizeText)
                        inspectorRow("Checksum", backup.manifest?.checksumSHA256 ?? backup.checksumSHA256 ?? "--", isMonospaced: true)
                        inspectorRow("Versión de esquema", backup.manifest?.appVersion ?? "--")
                        inspectorRow("Estado de verificación", backup.verificationState.rawValue)
                    }

                    MacPremiumInspectorActionGroup {
                        Button {
                            requestRestore(backup)
                        } label: {
                            Label("Restaurar esta copia", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!backup.isRestorable)

                        Button {
                            Task { await store.verifySelectedBackup() }
                        } label: {
                            Label("Verificar integridad", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.openSelectedInFinder()
                        } label: {
                            Label("Ver en Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.copySelectedPathToPasteboard()
                        } label: {
                            Label("Copiar ruta", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            backupToExport = backup.descriptor
                        } label: {
                            Label("Exportar backup", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ContentUnavailableView(
                        "Sin selección",
                        systemImage: "externaldrive",
                        description: Text("Selecciona una copia del historial para ver sus detalles.")
                    )
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
        .background(MacAppStyle.pageBackground)
        .sheet(item: $backupToExport) { backup in
            EncryptedBackupExportSheet(
                backup: backup,
                onExport: { destinationURL, password in
                    try await store.exportEncryptedBackup(backup, to: destinationURL, password: password)
                },
                onFinished: { await store.loadBackups() }
            )
        }
        .confirmationDialog(
            "Restaurar backup",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restaurar esta copia", role: .destructive) {
                Task { await store.restoreSelectedBackup() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se creará primero una copia de emergencia y después se reemplazará la base de datos actual por \(restoreCandidate?.displayName ?? "la copia seleccionada"). La aplicación se cerrará al terminar; tendrás que volver a abrirla para completar la restauración.")
        }
    }

    private func inspectorRow(_ label: String, _ value: String, isMonospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(for state: MacBackupRecord.VerificationState) -> Color {
        switch state {
        case .verified:
            return MacAppStyle.successTint
        case .checksumMismatch:
            return MacAppStyle.dangerTint
        case .missingFile:
            return MacAppStyle.warningTint
        }
    }

    private func requestRestore(_ backup: MacBackupRecord?) {
        guard let backup else { return }
        restoreCandidate = backup
        store.selectedBackupID = backup.id
        showRestoreConfirmation = true
    }
}
