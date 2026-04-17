import SwiftUI
import AppKit

struct MacRootView: View {
    @ObservedObject var session: MacAppSessionController

    var body: some View {
        NavigationSplitView {
            List(MacFeatureRegistry.all, selection: $session.selectedFeature) { feature in
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.title)
                        Text(feature.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: feature.systemImage)
                }
                .tag(feature.feature)
            }
            .navigationTitle("MiGestor")
        } detail: {
            featureDetail(for: session.selectedFeature)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await session.bridge.pullMissingSyncChanges()
                    }
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                }

                Button {
                    Task {
                        await session.bridge.refreshDashboard(mode: .office)
                    }
                } label: {
                    Label("Refrescar", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private func featureDetail(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .dashboard:
            MacDashboardView(bridge: session.bridge, bootstrap: session.bootstrap)
        case .sync:
            MacSyncView(bridge: session.bridge)
        case .backups:
            MacBackupsView(bridge: session.bridge)
        case .settings:
            MacSettingsView(session: session)
        default:
            MacFeaturePlaceholderView(feature: MacFeatureRegistry.descriptor(for: feature), bridge: session.bridge)
        }
    }
}

private struct MacDashboardView: View {
    @ObservedObject var bridge: KmpBridge
    let bootstrap: AppleBridgeBootstrap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shell macOS operativo")
                        .font(.largeTitle.weight(.semibold))
                    Text("Base Apple compartida con KMP y paridad funcional guiada por iOS.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Estado") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Plataforma", value: bootstrap.platformName)
                        LabeledContent("Base de datos", value: bootstrap.databasePath)
                        LabeledContent("Bridge", value: bridge.status)
                        LabeledContent("Resumen", value: bridge.statsText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Clases") {
                    if bridge.classes.isEmpty {
                        Text("Todavía no hay clases cargadas.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            HStack {
                                Text(schoolClass.name)
                                Spacer()
                                Text("Curso \(schoolClass.course)")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct MacSyncView: View {
    @ObservedObject var bridge: KmpBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync LAN")
                .font(.title.bold())
            LabeledContent("Estado", value: bridge.syncStatusMessage)
            LabeledContent("Pendientes", value: String(bridge.syncPendingChanges))
            LabeledContent("Última sync", value: bridge.syncLastRunAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            LabeledContent("Host vinculado", value: bridge.pairedSyncHost ?? "Sin vincular")

            if bridge.discoveredSyncHosts.isEmpty {
                Text("No se han descubierto hosts todavía.")
                    .foregroundStyle(.secondary)
            } else {
                List(bridge.discoveredSyncHosts, id: \.self) { host in
                    Text(host)
                }
            }
        }
        .padding(24)
    }
}

private struct MacBackupsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var backupMessage = "Todavía no se ha creado ningún backup."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backups locales")
                .font(.title.bold())
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

                Button("Restaurar backup") {
                    Task {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        if panel.runModal() == .OK, let path = panel.url?.path {
                            do {
                                let restored = try await bridge.restoreLocalBackup(from: path)
                                backupMessage = restored ? "Backup restaurado desde \(path)" : "No se pudo restaurar el backup."
                            } catch {
                                backupMessage = "Error restaurando backup: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}

private struct MacFeaturePlaceholderView: View {
    let feature: MacFeatureDescriptor
    @ObservedObject var bridge: KmpBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(feature.title, systemImage: feature.systemImage)
                .font(.title.bold())
            Text(feature.subtitle)
                .foregroundStyle(.secondary)
            Divider()
            Text("Este vertical ya cuelga del bridge Apple/KMP compartido. La shell macOS está lista para ir incorporando las vistas nativas módulo a módulo sin depender de Compose Desktop.")
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Estado actual", value: bridge.status)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}
