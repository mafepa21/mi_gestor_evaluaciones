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
    @State private var scheduleSelectedClassId: Int64?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedRoute) {
                Section("Ajustes") {
                    settingsRow("General", systemImage: "slider.horizontal.3", route: .general)
                    settingsRow("Horario docente", systemImage: "calendar.badge.clock", route: .schedule)
                    settingsRow("Evaluación", systemImage: "chart.bar.doc.horizontal", route: .evaluation)
                    settingsRow("Cuaderno", systemImage: "text.book.closed", route: .notebook)
                    settingsRow("Datos y Seguridad", systemImage: "lock.shield", route: .dataSecurity)
                    settingsRow("Sincronización", systemImage: "arrow.triangle.2.circlepath", route: .sync)
                    settingsRow("IA Apple", systemImage: "sparkles", route: .appleAI)
                    settingsRow("Apariencia", systemImage: "paintpalette", route: .appearance)
                    settingsRow("Diagnóstico Avanzado", systemImage: "waveform.path.ecg", route: .diagnostics)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 224)

            Divider()

            // "Horario docente" gestiona su propio scroll y su cabecera/pie
            // fijos (es el asistente progresivo); envolverlo en el ScrollView
            // genérico de Ajustes anidaría dos scrolls y perdería el pie fijo.
            if selectedRoute == .schedule {
                TeacherScheduleWizard(
                    bridge: session.bridge,
                    selectedClassId: $scheduleSelectedClassId
                )
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        detailViewForRoute(selectedRoute)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    @ViewBuilder
    private func settingsRow(
        _ title: String,
        systemImage: String,
        route: SettingsRoute
    ) -> some View {
        Label(title, systemImage: systemImage)
            .tag(route)
    }

    @ViewBuilder
    private func detailViewForRoute(_ route: SettingsRoute) -> some View {
        switch route {
        case .general:
            GeneralSettingsView(settings: settings)
        case .schedule:
            EmptyView()
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
