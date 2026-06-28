import SwiftUI
import MiGestorKit

extension AppWorkspaceShell {
    @ViewBuilder
    var workspaceSidebar: some View {
        let enabledProfiles = TeacherSubjectProfile.decodeSet(UserDefaults.standard.string(forKey: "teacher.enabledSubjectProfiles.v1") ?? TeacherSubjectProfile.general.rawValue)

        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MiGestor iPad")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text("Evaluación, asistencia y decisiones de clase en una mesa de trabajo.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.3.group")
                            .font(.caption.weight(.bold))
                        Text(activeClassLabel)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.10), in: Capsule(style: .continuous))
                }
                .padding(.vertical, 16)
            }

            Section("Uso diario") {
                ForEach(primaryDailyFeatures) { feature in
                    Button {
                        open(module: feature.module)
                    } label: {
                        WorkspaceSidebarFeatureRow(
                            feature: feature,
                            isActive: activeModule == feature.module,
                            isPrimary: true
                        )
                    }
                }
            }

            Section("Trabajo lectivo") {
                ForEach(secondaryDailyFeatures) { feature in
                    Button {
                        open(module: feature.module)
                    } label: {
                        WorkspaceSidebarFeatureRow(
                            feature: feature,
                            isActive: activeModule == feature.module,
                            isPrimary: false
                        )
                    }
                }
            }

            Section("Más herramientas") {
                ForEach(IOSFeatureRegistry.secondary(enabledProfiles: enabledProfiles)) { feature in
                    Button {
                        open(module: feature.module)
                    } label: {
                        WorkspaceSidebarFeatureRow(
                            feature: feature,
                            isActive: activeModule == feature.module,
                            isPrimary: false
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MiGestor")
    }

    private var primaryDailyFeatures: [IOSFeatureDescriptor] {
        IOSFeatureRegistry.daily.filter { [.dashboard, .teacherRadar, .notebook, .attendance].contains($0.module) }
    }

    private var secondaryDailyFeatures: [IOSFeatureDescriptor] {
        IOSFeatureRegistry.daily.filter { ![.dashboard, .teacherRadar, .notebook, .attendance].contains($0.module) }
    }
}

private struct WorkspaceSidebarFeatureRow: View {
    let feature: IOSFeatureDescriptor
    let isActive: Bool
    let isPrimary: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(isPrimary ? .headline : .subheadline.weight(.semibold))
                Text(feature.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: feature.systemImage)
                .font(.system(size: isPrimary ? 17 : 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .foregroundStyle(isActive ? Color.accentColor : .primary)
        .padding(.vertical, isPrimary ? 6 : 4)
    }
}
