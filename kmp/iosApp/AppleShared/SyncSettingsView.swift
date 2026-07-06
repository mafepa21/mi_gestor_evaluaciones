import SwiftUI
import MiGestorKit

struct SyncSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject var bridge: KmpBridge

    var body: some View {
        #if os(macOS)
        // macOS: mantener comportamiento original (solo toggle + texto informativo)
        ScrollView {
            VStack(spacing: IOSAppStyle.sectionSpacing) {
                PremiumCard.section(title: "Preferencia de Sincronización", systemImage: "arrow.triangle.2.circlepath") {
                    Toggle("Sincronizar automáticamente al inicio", isOn: $settings.syncAutoStart)
                        .font(IOSAppStyle.bodyText)
                }

                PremiumCard.section(title: "Sincronización de Red", systemImage: "wifi") {
                    Text("La sincronización y el emparejamiento se gestionan desde la sección dedicada 'Sincronizar' en la barra lateral de la aplicación principal.")
                        .font(IOSAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(IOSAppStyle.pagePadding)
        }
        .background(IOSAppStyle.pageBackground)
        .navigationTitle("Sincronización")
        #else
        // iOS: nueva vista estructurada por secciones
        SyncLanView(settings: settings)
            .environmentObject(bridge)
        #endif
    }
}
