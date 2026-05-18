import SwiftUI
import AppKit

struct MacBackupsView: View {
    @ObservedObject var store: MacBackupStore
    @State private var restoreCandidate: MacBackupRecord?
    @State private var showRestoreConfirmation = false
    @State private var showRetentionConfirmation = false

    var body: some View {
        ScrollView {
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
                            title: "Restaurar",
                            systemImage: "arrow.counterclockwise",
                            isDisabled: store.selectedBackup == nil,
                            handler: { requestRestore(store.selectedBackup) }
                        ),
                        MacPremiumHeaderAction(
                            title: "Ver carpeta",
                            systemImage: "folder",
                            handler: store.openBackupDirectory
                        )
                    ]
                )

                backupHero
                backupActions
                backupError
                retentionWarning
                backupHistory
            }
            .padding(MacAppStyle.pagePadding)
        }
        .task {
            await store.loadBackups()
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
            Text("Se creará primero una copia de emergencia y después se reemplazará la base de datos actual por \(restoreCandidate?.displayName ?? "la copia seleccionada").")
        }
        .confirmationDialog(
            "Aplicar retención",
            isPresented: $showRetentionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar copias antiguas", role: .destructive) {
                Task { await store.deleteBackupsBeyondRetention() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se mantendrán las 10 copias más recientes y se borrarán las antiguas.")
        }
    }

    private var backupHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Protección de datos")
                        .font(.title2.weight(.semibold))
                    Text(store.latestBackup.map { "Última copia: \($0.createdAt.macBackupDateText)" } ?? "Última copia: sin copias")
                        .font(MacAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: store.latestBackup == nil ? "externaldrive.badge.questionmark" : "externaldrive.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(store.latestBackup == nil ? MacAppStyle.warningTint : MacAppStyle.successTint)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: MacAppStyle.cardSpacing) {
                MacMetricCard(label: "Estado", value: store.protectedStatus, tint: store.latestBackup == nil ? MacAppStyle.warningTint : MacAppStyle.successTint, systemImage: "shield")
                MacMetricCard(label: "Base de datos", value: store.latestBackup?.sizeBytes.macBackupFileSizeText ?? "--", systemImage: "internaldrive")
                MacMetricCard(label: "Retención", value: store.retentionSummary, systemImage: "clock.arrow.circlepath")
                MacMetricCard(label: "Historial", value: "\(store.backups.count)", systemImage: "list.bullet.rectangle")
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var backupActions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.createBackup() }
            } label: {
                Label("Crear backup ahora", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isCreatingBackup)

            Button {
                requestRestore(store.selectedBackup)
            } label: {
                Label("Restaurar", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.selectedBackup == nil)

            Button {
                store.openBackupDirectory()
            } label: {
                Label("Ver carpeta", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Spacer()
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
                    showRetentionConfirmation = true
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

                    TableColumn("Acciones") { backup in
                        HStack(spacing: 8) {
                            Button("Restaurar") {
                                store.selectedBackupID = backup.id
                                requestRestore(backup)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!backup.isRestorable)

                            Button("Ver") {
                                store.selectedBackupID = backup.id
                                store.openSelectedInFinder()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .width(min: 150, ideal: 180)
                }
                .frame(minHeight: 340)
            }
        }
    }

    private func tint(for state: MacBackupRecord.VerificationState) -> Color {
        switch state {
        case .verified:
            return MacAppStyle.successTint
        case .missingManifest:
            return MacAppStyle.warningTint
        case .checksumMismatch, .missingFile, .unreadable:
            return MacAppStyle.dangerTint
        }
    }

    private func requestRestore(_ backup: MacBackupRecord?) {
        guard let backup else { return }
        restoreCandidate = backup
        store.selectedBackupID = backup.id
        showRestoreConfirmation = true
    }
}

struct MacBackupInspectorView: View {
    @ObservedObject var store: MacBackupStore
    @State private var restoreCandidate: MacBackupRecord?
    @State private var showRestoreConfirmation = false

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
                            store.exportSelectedBackup()
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
            Text("Se creará primero una copia de emergencia y después se reemplazará la base de datos actual por \(restoreCandidate?.displayName ?? "la copia seleccionada").")
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
        case .missingManifest:
            return MacAppStyle.warningTint
        case .checksumMismatch, .missingFile, .unreadable:
            return MacAppStyle.dangerTint
        }
    }

    private func requestRestore(_ backup: MacBackupRecord?) {
        guard let backup else { return }
        restoreCandidate = backup
        store.selectedBackupID = backup.id
        showRestoreConfirmation = true
    }
}
