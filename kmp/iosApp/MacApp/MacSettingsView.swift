import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    let onOpenSync: () -> Void
    @State private var selectedScheduleClassId: Int64?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                Text("Ajustes")
                    .font(MacAppStyle.pageTitle)
                    .padding(.bottom, 4)

                generalSection
                syncSection
                agendaSection
                flagsAndShellSection
            }
            .padding(MacAppStyle.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacAppStyle.pageBackground)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "General")
            MacSettingsCard {
                VStack(spacing: 0) {
                    settingsRow("Plataforma", value: session.bootstrap.platformName)
                    Divider().padding(.leading, 16)
                    settingsRow("Base de datos", value: URL(fileURLWithPath: session.bootstrap.databasePath).lastPathComponent)
                    Divider().padding(.leading, 16)
                    settingsRow("Estado del bridge", value: session.bridge.status)
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Sync LAN")
            MacSettingsCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commandCenter.statusMessage)
                            .font(.callout)
                            .lineLimit(2)
                        Text("Emparejado, pull y observabilidad viven en el módulo Sync LAN.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ir a Sync") {
                        onOpenSync()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Agenda docente")
            MacTeacherScheduleSettingsPanel(
                bridge: session.bridge,
                selectedClassId: $selectedScheduleClassId
            )
        }
    }

    private var flagsAndShellSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Flags / IA / shell")
            MacSettingsCard {
                VStack(spacing: 0) {
                    Toggle("Mostrar inspector por defecto", isOn: $session.inspectorVisible)
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    Divider().padding(.leading, 16)

                    ForEach(Array(MacFeatureRegistry.all.enumerated()), id: \.element.id) { index, feature in
                        HStack(spacing: 10) {
                            Image(systemName: feature.systemImage)
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text(feature.title)
                                .font(.callout)
                            Spacer()
                            Text(feature.source.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if index < MacFeatureRegistry.all.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    private func settingsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct MacSettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}
