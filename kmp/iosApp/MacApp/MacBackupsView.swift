import SwiftUI
import AppKit

struct MacBackupsView: View {
    @ObservedObject var store: MacBackupStore

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            MacPremiumModuleHeader(
                title: "Backups",
                subtitle: store.lastMessage,
                state: store.operationState,
                primaryAction: MacPremiumHeaderAction(
                    title: "Crear backup ahora",
                    systemImage: "plus.circle.fill",
                    isDisabled: store.isCreatingBackup,
                    handler: { Task { await store.createBackup() } }
                ),
                secondaryActions: [
                    MacPremiumHeaderAction(
                        title: "Ver carpeta",
                        systemImage: "folder",
                        handler: store.openBackupDirectory
                    )
                ]
            )

            backupError
            retentionWarning
            
            backupHistory
                .frame(maxHeight: .infinity)
        }
        .padding(MacAppStyle.pagePadding)
        .task {
            await store.loadBackups()
        }
    }

    @ViewBuilder
    private var backupError: some View {
        if let errorMessage = store.errorMessage {
            HStack(spacing: 10) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MacAppStyle.dangerTint)
                    .textSelection(.enabled)
                Spacer(minLength: 12)
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.dangerTint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var retentionWarning: some View {
        if store.extraCopiesCount > 0 {
            HStack(spacing: 10) {
                Label("\(store.extraCopiesCount) copias superan la retención configurada.", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MacAppStyle.warningTint)
                Spacer()
                Button("Aplicar retención") {
                    Task { await store.deleteBackupsBeyondRetention() }
                }
                .buttonStyle(.bordered)
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.warningTint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    private var backupHistory: some View {
        MacPremiumTableContainer(
            title: "Historial de copias",
            subtitle: "Copias detectadas en \(store.backupDirectoryURL.path)",
            count: store.backups.count,
            isLoading: false
        ) {
            if store.backups.isEmpty {
                ContentUnavailableView(
                    "Sin backups",
                    systemImage: "externaldrive",
                    description: Text("Crea una copia para activar el historial verificable.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                Table(store.backups, selection: $store.selectedBackupID) {
                    TableColumn("Fecha") { backup in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.createdAt.macBackupDateText)
                                .font(.callout.weight(.medium))
                            Text(backup.createdAt.macBackupRelativeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 170, ideal: 210)

                    TableColumn("Tamaño") { backup in
                        Text(backup.sizeBytes.macBackupFileSizeText)
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Estado") { backup in
                        MacStatusPill(
                            label: backup.verificationState.rawValue,
                            isActive: backup.verificationState == .verified,
                            tint: tint(for: backup.verificationState)
                        )
                    }
                    .width(min: 130, ideal: 160)
                }
            }
        }
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
}
