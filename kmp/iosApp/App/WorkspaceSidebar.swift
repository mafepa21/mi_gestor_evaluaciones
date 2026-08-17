import SwiftUI
import MiGestorKit

extension AppWorkspaceShell {
    @ViewBuilder
    var workspaceSidebar: some View {
        let enabledProfiles = TeacherSubjectProfile.decodeSet(UserDefaults.standard.string(forKey: "teacher.enabledSubjectProfiles.v1") ?? TeacherSubjectProfile.general.rawValue)

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clase activa")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Label(activeClassLabel, systemImage: "rectangle.3.group")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
            }

            ForEach(WorkspaceSidebarSection.allCases) { section in
                let features = features(for: section, enabledProfiles: enabledProfiles)
                if !features.isEmpty {
                    Section(section.rawValue) {
                        ForEach(features) { feature in
                            Button {
                                open(module: feature.module)
                            } label: {
                                WorkspaceSidebarFeatureRow(
                                    feature: feature,
                                    isActive: activeModule == feature.module
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MiGestor")
    }

    private func features(
        for section: WorkspaceSidebarSection,
        enabledProfiles: Set<TeacherSubjectProfile>
    ) -> [IOSFeatureDescriptor] {
        let available = IOSFeatureRegistry.all(enabledProfiles: enabledProfiles)
        return section.modules.compactMap { module in
            available.first { $0.module == module }
        }
    }
}

private enum WorkspaceSidebarSection: String, CaseIterable, Identifiable {
    case today = "Hoy"
    case evaluation = "Evaluación"
    case planning = "Planificación"
    case system = "Sistema"

    var id: String { rawValue }

    var modules: [AppWorkspaceModule] {
        switch self {
        case .today:
            return [.dashboard]
        case .evaluation:
            return [.notebook, .attendance, .evaluationHub, .rubrics, .webSubmissions, .peTests, .peRubrics]
        case .planning:
            return [.planner, .diary, .situations, .meetings, .students, .peSessions]
        case .system:
            return [.reports, .library, .peIncidents, .peMaterial, .peTournaments, .settings, .backups]
        }
    }
}

private struct WorkspaceSidebarFeatureRow: View {
    let feature: IOSFeatureDescriptor
    let isActive: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                Text(feature.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: feature.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .foregroundStyle(isActive ? Color.accentColor : .primary)
        .padding(.vertical, 4)
    }
}
