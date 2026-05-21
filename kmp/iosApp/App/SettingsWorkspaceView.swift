import SwiftUI
import MiGestorKit

// MARK: - Section Descriptor

struct SettingsSectionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension SettingsSectionDescriptor {
    static let all: [SettingsSectionDescriptor] = [
        .init(id: "general",     title: "General",          subtitle: "Curso escolar y nombre del centro",         systemImage: "slider.horizontal.3",         tint: .blue),
        .init(id: "appearance",  title: "Apariencia",        subtitle: "Tema de color y accesibilidad",            systemImage: "paintpalette.fill",            tint: .orange),
        .init(id: "evaluation",  title: "Evaluación",        subtitle: "Escalas, redondeos y cuaderno",            systemImage: "chart.bar.doc.horizontal.fill", tint: .indigo),
        .init(id: "datasec",     title: "Datos y seguridad", subtitle: "Copias de seguridad, restaurar, borrar",   systemImage: "lock.shield.fill",             tint: .green),
        .init(id: "synclan",     title: "Sync LAN",          subtitle: "Enlazar con Mac y sincronización local",   systemImage: "arrow.triangle.2.circlepath",  tint: .cyan),
        .init(id: "ai",          title: "IA Apple",          subtitle: "Informes y radar inteligente",             systemImage: "sparkles",                     tint: .purple),
        .init(id: "diagnostics", title: "Diagnóstico",       subtitle: "Esquema, logs SQLite y uso de disco",      systemImage: "waveform.path.ecg",            tint: .red),
    ]
}

// MARK: - Main View

struct SettingsWorkspaceView: View {
    @StateObject private var settings = AppSettingsStore()
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedSection: SettingsSectionDescriptor? = SettingsSectionDescriptor.all.first

    var body: some View {
        if sizeClass == .regular {
            ipadLayout
        } else {
            iphoneLayout
        }
    }

    // MARK: iPad — NavigationSplitView

    private var ipadLayout: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 320)
        } detail: {
            if let section = selectedSection {
                settingsDetail(for: section)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                settingsEmptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: iPhone — NavigationStack

    private var iphoneLayout: some View {
        NavigationStack {
            sidebarList
                .navigationTitle("Ajustes")
                .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Sidebar / List

    private var sidebarList: some View {
        List(SettingsSectionDescriptor.all, id: \.id, selection: $selectedSection) { section in
            if sizeClass == .regular {
                // iPad: NavigationSplitView selection
                SettingsSidebarRow(section: section, isSelected: selectedSection?.id == section.id)
                    .tag(section)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                // iPhone: NavigationLink
                NavigationLink(destination: settingsDetail(for: section)) {
                    SettingsSidebarRow(section: section, isSelected: false)
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .background(IOSAppStyle.pageBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Detail router

    @ViewBuilder
    private func settingsDetail(for section: SettingsSectionDescriptor) -> some View {
        switch section.id {
        case "general":
            GeneralSettingsView(settings: settings)
        case "appearance":
            AppearanceSettingsView(settings: settings)
        case "evaluation":
            EvaluationSettingsView(settings: settings)
        case "datasec":
            DataSecuritySettingsView(settings: settings)
        case "synclan":
            SyncSettingsView(settings: settings)
                .environmentObject(bridge)
        case "ai":
            AppleAISettingsView(settings: settings)
                .environmentObject(bridge)
        case "diagnostics":
            SettingsDiagnosticsView()
        default:
            settingsEmptyDetail
        }
    }

    private var settingsEmptyDetail: some View {
        IOSEmptyState(
            title: "Selecciona una sección",
            subtitle: "Elige una categoría de la barra lateral para ver sus opciones.",
            systemImage: "gearshape"
        )
        .background(IOSAppStyle.pageBackground)
    }
}

// MARK: - Sidebar Row

struct SettingsSidebarRow: View {
    let section: SettingsSectionDescriptor
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(section.tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: section.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(section.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? section.tint : .primary)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(isSelected ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous)
                .fill(isSelected
                      ? section.tint.opacity(colorScheme == .dark ? 0.14 : 0.08)
                      : IOSAppStyle.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous)
                        .stroke(isSelected ? section.tint.opacity(0.22) : IOSAppStyle.cardBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}
