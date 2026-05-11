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

            ForEach(AppWorkspaceSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(AppWorkspaceModule.allCases.filter { $0.section == section }) { module in
                        Button {
                            open(module: module)
                        } label: {
                            Label(module.title, systemImage: module.systemImage)
                                .foregroundStyle(activeModule == module ? Color.accentColor : .primary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workspace")
    }

}
