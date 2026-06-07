import SwiftUI
import MiGestorKit

extension AppWorkspaceShell {
    @ViewBuilder
    var workspaceSidebar: some View {
        let enabledProfiles = TeacherSubjectProfile.decodeSet(UserDefaults.standard.string(forKey: "teacher.enabledSubjectProfiles.v1") ?? TeacherSubjectProfile.general.rawValue)

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
                ForEach(IOSFeatureRegistry.secondary(enabledProfiles: enabledProfiles)) { feature in
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
