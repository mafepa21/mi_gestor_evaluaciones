import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController

    var body: some View {
        Form {
            Section("Bootstrap Apple") {
                LabeledContent("Plataforma", value: session.bootstrap.platformName)
                LabeledContent("Base de datos", value: session.bootstrap.databasePath)
                LabeledContent("Estado", value: session.bridge.status)
            }

            Section("Shell") {
                Toggle("Mostrar inspector por defecto", isOn: $session.inspectorVisible)
            }

            Section("Cobertura v1") {
                ForEach(MacFeatureRegistry.all) { feature in
                    HStack {
                        Label(feature.title, systemImage: feature.systemImage)
                        Spacer()
                        Text(feature.source.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}
