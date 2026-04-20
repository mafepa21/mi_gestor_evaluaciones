import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    let onOpenSync: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                Text("Ajustes")
                    .font(MacAppStyle.pageTitle)
                    .padding(.bottom, 4)

                systemSection
                commandCenterQuickSection
                shellSection
                featuresSection
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Sistema")
            VStack(spacing: 0) {
                settingsRow("Plataforma", value: session.bootstrap.platformName)
                Divider().padding(.leading, 16)
                settingsRow("Base de datos", value: URL(fileURLWithPath: session.bootstrap.databasePath).lastPathComponent)
                Divider().padding(.leading, 16)
                settingsRow("Estado del bridge", value: session.bridge.status)
            }
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    private var commandCenterQuickSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Sincronización LAN")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commandCenter.statusMessage)
                        .font(.callout)
                        .lineLimit(2)
                    Text("Gestiona la sincronización completa en el módulo Sync LAN.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Ir a Sync") {
                    onOpenSync()
                }
                .buttonStyle(.bordered)
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    private var shellSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Shell")
            Toggle("Mostrar inspector por defecto", isOn: $session.inspectorVisible)
                .toggleStyle(.switch)
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Módulos disponibles")
            VStack(spacing: 0) {
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
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
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
