import SwiftUI
import MiGestorKit

struct SyncSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject var bridge: KmpBridge
    
    var body: some View {
        Form {
            Section("Preferencia de Sincronización") {
                Toggle("Sincronizar automáticamente al inicio", isOn: $settings.syncAutoStart)
            }
            
            #if os(macOS)
            Section("Sincronización de Red") {
                Text("La sincronización y el emparejamiento se gestionan desde la sección dedicada 'Sincronizar' en la barra lateral de la aplicación principal.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            #else
            Section("Información de Enlace (iPad / iPhone)") {
                SyncLanCard()
            }
            #endif
        }
        .navigationTitle("Sincronización")
    }
}
