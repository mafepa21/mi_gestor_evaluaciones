import SwiftUI
import MiGestorKit

struct AppleAISettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject var bridge: KmpBridge
    
    var body: some View {
        Form {
            Section("Integración con Apple Intelligence") {
                Toggle("Asistente de Informes Inteligentes", isOn: $settings.appleAIReportsEnabled)
                Toggle("Radar de Alumnado Integrado", isOn: $settings.appleAIRadarEnabled)
            }
            
            Section("Historial de Consultas de IA") {
                AppleAIHistoryPanel(bridge: bridge)
            }
        }
        .navigationTitle("IA Apple")
    }
}
