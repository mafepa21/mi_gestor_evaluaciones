import SwiftUI
import AppKit
import MiGestorKit

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    @ObservedObject var backupStore: MacBackupStore
    let onOpenSync: () -> Void
    /// Necesarios desde que "Cursos y grupos" vive dentro de Ajustes.
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @StateObject private var settings = AppSettingsStore()
    @ObservedObject private var settingsNavigation = SettingsNavigationStore.shared
    @State private var selectedRoute: SettingsRoute = .general
    @State private var scheduleSelectedClassId: Int64?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedRoute) {
                Section("Ajustes") {
                    settingsRow("General", systemImage: "slider.horizontal.3", route: .general)
                    settingsRow("Cursos y grupos", systemImage: "person.2.fill", route: .courses)
                    settingsRow("Horario docente", systemImage: "calendar.badge.clock", route: .schedule)
                    settingsRow("Evaluación", systemImage: "chart.bar.doc.horizontal", route: .evaluation)
                    settingsRow("Cuaderno", systemImage: "text.book.closed", route: .notebook)
                    settingsRow("Datos y Seguridad", systemImage: "lock.shield", route: .dataSecurity)
                    settingsRow("Gestión de datos", systemImage: "trash", route: .dataManagement)
                    settingsRow("Sincronización", systemImage: "arrow.triangle.2.circlepath", route: .sync)
                    settingsRow("IA Apple", systemImage: "sparkles", route: .appleAI)
                    settingsRow("Apariencia", systemImage: "paintpalette", route: .appearance)
                    settingsRow("Diagnóstico Avanzado", systemImage: "waveform.path.ecg", route: .diagnostics)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 224)

            Divider()

            // "Horario docente" y "Cursos y grupos" gestionan su propio scroll
            // (el primero es el asistente progresivo con cabecera y pie fijos);
            // envolverlos en el ScrollView genérico de Ajustes anidaría dos
            // scrolls y, en el asistente, perdería el pie fijo.
            if selectedRoute == .schedule {
                TeacherScheduleWizard(
                    bridge: session.bridge,
                    selectedClassId: $scheduleSelectedClassId
                )
                .background(Color(NSColor.windowBackgroundColor))
            } else if selectedRoute == .courses {
                CoursesWorkspaceView(
                    selectedClassId: $selectedClassId,
                    onOpenModule: onOpenModule,
                    onCreateStudent: { classId in
                        selectedClassId = classId
                        onOpenModule(.students, classId, nil)
                    }
                )
                .environmentObject(session.bridge)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                // `detailViewForRoute` puede navegar con `NavigationLink` (p.ej.
                // Datos y Seguridad → Zona de Riesgo). Sin un `NavigationStack`
                // propio aquí, ese push se resuelve contra un contexto de
                // navegación implícito ligado a la ventana en vez de a esta
                // vista: al cambiar de `selectedRoute` (o de sección en la
                // barra lateral principal) el push queda huérfano y sigue
                // tapando el panel de detalle aunque el resto de la app haya
                // navegado a otro sitio. `.id(selectedRoute)` fuerza además a
                // resetear el push al cambiar de sección de Ajustes sin salir
                // de Ajustes.
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            detailViewForRoute(selectedRoute)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .id(selectedRoute)
            }
        }
        .task { consumePendingSection() }
        .appOnChange(of: settingsNavigation.pendingSection) { _ in
            consumePendingSection()
        }
    }

    /// Alguien ha pedido "abre Ajustes por esta sección" desde fuera (menú del
    /// Cuaderno, lista de primeros pasos).
    private func consumePendingSection() {
        guard let request = settingsNavigation.consume() else { return }
        switch request {
        case .general: selectedRoute = .general
        case .courses: selectedRoute = .courses
        case .schedule: selectedRoute = .schedule
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
        case .courses, .schedule:
            // Se resuelven arriba, fuera del ScrollView genérico.
            EmptyView()
        case .evaluation:
            EvaluationSettingsView(settings: settings)
        case .notebook:
            NotebookSettingsView(settings: settings)
        case .dataSecurity:
            DataSecuritySettingsView(settings: settings)
                .environmentObject(session.bridge)
        case .dataManagement:
            DataManagementSettingsView()
                .environmentObject(session.bridge)
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
