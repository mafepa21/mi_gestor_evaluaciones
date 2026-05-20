import SwiftUI
import MiGestorKit

struct SettingsWorkspaceView: View {
    @StateObject private var settings = AppSettingsStore()
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            List {
                Section("Ajustes generales") {
                    NavigationLink(destination: GeneralSettingsView(settings: settings)) {
                        SettingsRow(title: "General", subtitle: "Curso escolar, nombre del centro", systemImage: "slider.horizontal.3")
                    }
                    
                    NavigationLink(destination: EvaluationSettingsView(settings: settings)) {
                        SettingsRow(title: "Evaluación", subtitle: "Escalas y redondeos de medias", systemImage: "chart.bar.doc.horizontal")
                    }
                    
                    NavigationLink(destination: NotebookSettingsView(settings: settings)) {
                        SettingsRow(title: "Cuaderno", subtitle: "Densidad de filas y visualización", systemImage: "text.book.closed")
                    }
                }
                
                Section("Mantenimiento y sincronización") {
                    NavigationLink(destination: DataSecuritySettingsView(settings: settings)) {
                        SettingsRow(title: "Datos y seguridad", subtitle: "Copias de seguridad, restaurar, borrar", systemImage: "lock.shield")
                    }
                    
                    NavigationLink(destination: SyncSettingsView(settings: settings).environmentObject(bridge)) {
                        SettingsRow(title: "Sincronización", subtitle: "Auto-sync, enlazar con Mac", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                
                Section("Inteligencia y apariencia") {
                    NavigationLink(destination: AppleAISettingsView(settings: settings).environmentObject(bridge)) {
                        SettingsRow(title: "IA Apple", subtitle: "Informes y radar inteligente", systemImage: "sparkles")
                    }
                    
                    NavigationLink(destination: AppearanceSettingsView(settings: settings)) {
                        SettingsRow(title: "Apariencia", subtitle: "Tema de color, accesibilidad", systemImage: "paintpalette")
                    }
                }
                
                Section("Avanzado") {
                    NavigationLink(destination: SettingsDiagnosticsView()) {
                        SettingsRow(title: "Diagnóstico avanzado", subtitle: "Esquema, logs SQLite, uso de disco", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
