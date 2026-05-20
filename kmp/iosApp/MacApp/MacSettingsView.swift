import SwiftUI
import AppKit
import MiGestorKit

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    @ObservedObject var backupStore: MacBackupStore
    let onOpenSync: () -> Void

    @StateObject private var settings = AppSettingsStore()
    @State private var selectedRoute: SettingsRoute = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedRoute) {
                Section("Ajustes") {
                    NavigationLink(value: SettingsRoute.general) {
                        Label("General", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(value: SettingsRoute.evaluation) {
                        Label("Evaluación", systemImage: "chart.bar.doc.horizontal")
                    }
                    NavigationLink(value: SettingsRoute.notebook) {
                        Label("Cuaderno", systemImage: "text.book.closed")
                    }
                    NavigationLink(value: SettingsRoute.dataSecurity) {
                        Label("Datos y Seguridad", systemImage: "lock.shield")
                    }
                    NavigationLink(value: SettingsRoute.sync) {
                        Label("Sincronización", systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink(value: SettingsRoute.appleAI) {
                        Label("IA Apple", systemImage: "sparkles")
                    }
                    NavigationLink(value: SettingsRoute.appearance) {
                        Label("Apariencia", systemImage: "paintpalette")
                    }
                    NavigationLink(value: SettingsRoute.diagnostics) {
                        Label("Diagnóstico Avanzado", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Ajustes")
            .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailViewForRoute(selectedRoute)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailViewForRoute(_ route: SettingsRoute) -> some View {
        switch route {
        case .general:
            GeneralSettingsView(settings: settings)
        case .evaluation:
            EvaluationSettingsView(settings: settings)
        case .notebook:
            NotebookSettingsView(settings: settings)
        case .dataSecurity:
            DataSecuritySettingsView(settings: settings)
        case .sync:
            SyncSettingsView(settings: settings)
                .environmentObject(session.bridge)
        case .appleAI:
            AppleAISettingsView(settings: settings)
                .environmentObject(session.bridge)
        case .appearance:
            AppearanceSettingsView(settings: settings)
        case .diagnostics:
            SettingsDiagnosticsView()
        }
    }
}
