import SwiftUI
import MiGestorKit

struct AppleAISettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    /// Referencia sin suscripción: esta vista solo llama acciones del bridge.
    @Environment(\.kmpBridgeReference) private var bridgeReference
    var bridge: KmpBridge { bridgeReference! }
    
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
