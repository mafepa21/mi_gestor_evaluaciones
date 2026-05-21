import SwiftUI
import MiGestorKit

struct SyncSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject var bridge: KmpBridge
    
    var body: some View {
        ScrollView {
            VStack(spacing: IOSAppStyle.sectionSpacing) {
                IOSSectionCard(title: "Preferencia de Sincronización", systemImage: "arrow.triangle.2.circlepath") {
                    Toggle("Sincronizar automáticamente al inicio", isOn: $settings.syncAutoStart)
                        .font(IOSAppStyle.bodyText)
                }
                
                #if os(macOS)
                IOSSectionCard(title: "Sincronización de Red", systemImage: "wifi") {
                    Text("La sincronización y el emparejamiento se gestionan desde la sección dedicada 'Sincronizar' en la barra lateral de la aplicación principal.")
                        .font(IOSAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }
                #else
                SyncLanCard()
                #endif
            }
            .padding(IOSAppStyle.pagePadding)
        }
        .background(IOSAppStyle.pageBackground)
        .navigationTitle("Sincronización")
    }
}
