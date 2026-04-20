import SwiftUI
import AppKit

struct MacRootView: View {
    @ObservedObject var session: MacAppSessionController
    @StateObject private var commandCenter = MacCommandCenterCoordinator()
    @State private var selectedClassId: Int64? = nil
    @State private var selectedStudentId: Int64? = nil

    var body: some View {
        Group {
            switch session.bootstrapState {
            case .idle, .loading:
                ProgressView("Preparando shell macOS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MacAppStyle.pageBackground)
            case .failed(let message):
                ContentUnavailableView(
                    "No se pudo iniciar la shell Mac",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
            case .ready:
                NavigationSplitView {
                    macSidebar
                } detail: {
                    featureDetail(for: session.selectedFeature)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MacAppStyle.pageBackground)
                }
                .toolbar {
                    macToolbar
                }
            }
        }
        .task {
            session.start()
        }
        .sheet(
            isPresented: Binding(
                get: { session.bridge.showingBulkRubricEvaluation },
                set: { session.bridge.showingBulkRubricEvaluation = $0 }
            )
        ) {
            RubricBulkEvaluationSheet(bridge: session.bridge)
                .frame(minWidth: 1200, minHeight: 820)
        }
    }

    private var macSidebar: some View {
        List(MacFeatureRegistry.all, selection: $session.selectedFeature) { feature in
            HStack(spacing: 10) {
                Image(systemName: feature.systemImage)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(iconTint(for: feature.feature))
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(.callout.weight(.medium))
                    Text(feature.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
            .tag(feature.feature)
        }
        .listStyle(.sidebar)
        .navigationTitle("MiGestor")
        .navigationSubtitle(session.bridge.statsText)
    }

    @ViewBuilder
    private func featureDetail(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .dashboard:
            MacDashboardView(bridge: session.bridge, bootstrap: session.bootstrap)
        case .notebook:
            NotebookModuleView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: { _, _, _ in }
            )
        case .students:
            MacStudentsView(bridge: session.bridge, selectedClassId: $selectedClassId)
        case .rubrics:
            MacRubricsView(bridge: session.bridge)
        case .reports:
            MacReportsView(bridge: session.bridge)
        case .planner:
            MacPlannerView(bridge: session.bridge)
        case .sync:
            MacSyncView(bridge: session.bridge, commandCenter: commandCenter)
        case .backups:
            MacBackupsView(bridge: session.bridge)
        case .settings:
            MacSettingsView(
                session: session,
                commandCenter: commandCenter,
                onOpenSync: { session.selectedFeature = .sync }
            )
        }
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await session.bridge.pullMissingSyncChanges() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sincronizar con desktop")

            if session.selectedFeature == .notebook {
                Button {
                    session.bridge.showingAddColumn = true
                } label: {
                    Label("Columna", systemImage: "plus.rectangle")
                }
                .help("Nueva columna")
            }

            Button {
                Task { await session.bridge.refreshDashboard(mode: .office) }
            } label: {
                Label("Refrescar", systemImage: "arrow.clockwise")
            }
            .help("Refrescar datos")
        }

        ToolbarItem {
            MacStatusPill(
                label: session.bridge.syncPendingChanges > 0
                    ? "\(session.bridge.syncPendingChanges) pendientes"
                    : "Sincronizado",
                isActive: session.bridge.syncPendingChanges > 0,
                tint: session.bridge.syncPendingChanges > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint
            )
        }
    }

    private func iconTint(for feature: MacFeatureDescriptor.Feature) -> Color {
        switch feature {
        case .dashboard: return .accentColor
        case .notebook: return .purple
        case .planner: return .orange
        case .students: return .blue
        case .rubrics: return .teal
        case .sync: return .green
        case .backups: return .gray
        case .reports: return .indigo
        case .settings: return .secondary
        }
    }
}

private struct MacBackupsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var backupMessage = "Todavía no se ha creado ningún backup."

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Text("Backups locales")
                .font(MacAppStyle.pageTitle)

            Text(backupMessage)
                .foregroundStyle(.secondary)

            HStack {
                Button("Crear backup") {
                    Task {
                        do {
                            let result = try await bridge.createLocalBackup()
                            backupMessage = "Backup creado en \(result.path)"
                        } catch {
                            backupMessage = "Error creando backup: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        if panel.runModal() == .OK, let path = panel.url?.path {
                            do {
                                let restored = try await bridge.restoreLocalBackup(from: path)
                                backupMessage = restored
                                    ? "Backup restaurado desde \(path)"
                                    : "No se pudo restaurar el backup."
                            } catch {
                                backupMessage = "Error restaurando backup: \(error.localizedDescription)"
                            }
                        }
                    }
                } label: {
                    Text("Restaurar backup")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(MacAppStyle.pagePadding)
    }
}
