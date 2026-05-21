import SwiftUI
import MiGestorKit

extension AppWorkspaceShell {
    var workspaceSidebar: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MiGestor iPad")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text("App iPad-first para evaluación, seguimiento y trabajo en clase.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            }

            Section("Uso diario") {
                ForEach(IOSFeatureRegistry.daily) { feature in
                    Button {
                        open(module: feature.module)
                    } label: {
                        Label(feature.title, systemImage: feature.systemImage)
                            .foregroundStyle(activeModule == feature.module ? Color.accentColor : .primary)
                    }
                }
            }

            Section("Más herramientas") {
                ForEach(IOSFeatureRegistry.secondary) { feature in
                    Button {
                        open(module: feature.module)
                    } label: {
                        Label(feature.title, systemImage: feature.systemImage)
                            .foregroundStyle(activeModule == feature.module ? Color.accentColor : .primary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workspace")
    }

}
