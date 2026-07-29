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
        .init(id: "courses",     title: "Cursos y grupos",  subtitle: "Curso escolar, asignaturas, grupos y archivado", systemImage: "person.2.fill",           tint: .cyan),
        .init(id: "schedule",    title: "Horario docente",  subtitle: "Franjas semanales, curso y evaluaciones",   systemImage: "calendar.badge.clock",         tint: .teal),
        .init(id: "appearance",  title: "Apariencia",        subtitle: "Tema de color y accesibilidad",            systemImage: "paintpalette.fill",            tint: .orange),
        .init(id: "evaluation",  title: "Evaluación",        subtitle: "Escalas, redondeos y cuaderno",            systemImage: "chart.bar.doc.horizontal.fill", tint: .indigo),
        .init(id: "datasec",     title: "Datos y seguridad", subtitle: "Copias de seguridad, restaurar, borrar",   systemImage: "lock.shield.fill",             tint: .green),
        .init(id: "datamgmt",    title: "Gestión de datos",  subtitle: "Borrado rápido de cursos, asignaturas, rúbricas y SA", systemImage: "trash.fill",       tint: .pink),
        .init(id: "synclan",     title: "Sync LAN",          subtitle: "Enlazar con Mac y sincronización local",   systemImage: "arrow.triangle.2.circlepath",  tint: .cyan),
        .init(id: "ai",          title: "IA Apple",          subtitle: "Informes y radar inteligente",             systemImage: "sparkles",                     tint: .purple),
        .init(id: "diagnostics", title: "Diagnóstico",       subtitle: "Esquema, logs SQLite y uso de disco",      systemImage: "waveform.path.ecg",            tint: .red),
    ]
}

// MARK: - Main View

struct SettingsWorkspaceView: View {
    @StateObject private var settings = AppSettingsStore()
    @ObservedObject private var settingsNavigation = SettingsNavigationStore.shared
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Necesarios desde que "Cursos y grupos" vive dentro de Ajustes: la
    /// pantalla de cursos sigue navegando al workspace diario (abrir cuaderno
    /// de un grupo, crear alumnado) igual que cuando estaba en la barra.
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var selectedSection: SettingsSectionDescriptor? = SettingsSectionDescriptor.all.first
    @State private var scheduleSelectedClassId: Int64?
    @State private var pushedSection: SettingsSectionDescriptor?

    var body: some View {
        Group {
            if sizeClass == .regular {
                ipadLayout
            } else {
                iphoneLayout
            }
        }
        .task { consumePendingSection() }
        .appOnChange(of: settingsNavigation.pendingSection) { _ in
            consumePendingSection()
        }
    }

    /// Alguien ha pedido "abre Ajustes por esta sección" desde fuera (menú del
    /// Cuaderno, lista de primeros pasos).
    private func consumePendingSection() {
        guard let request = settingsNavigation.consume() else { return }
        guard let match = SettingsSectionDescriptor.all.first(where: { $0.id == request.rawValue }) else { return }
        selectedSection = match
        if sizeClass != .regular {
            pushedSection = match
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
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
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
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                // Push gobernado por estado, no por `NavigationLink(destination:)`:
                // así una petición externa ("abre Cursos y grupos") también
                // navega en iPhone, no sólo en iPad.
                .navigationDestination(item: $pushedSection) { section in
                    settingsDetail(for: section)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
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
                // iPhone: push por estado (ver `iphoneLayout`)
                Button {
                    pushedSection = section
                } label: {
                    SettingsSidebarRow(section: section, isSelected: false)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .background(IOSAppStyle.pageBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("Ajustes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Detail router

    @ViewBuilder
    private func settingsDetail(for section: SettingsSectionDescriptor) -> some View {
        switch section.id {
        case "general":
            GeneralSettingsView(settings: settings)
        case "courses":
            CoursesWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: onOpenModule,
                onCreateStudent: { classId in
                    selectedClassId = classId
                    onOpenModule(.students, classId, nil)
                }
            )
            .environmentObject(bridge)
        case "schedule":
            TeacherScheduleWizard(
                bridge: bridge,
                selectedClassId: $scheduleSelectedClassId
            )
        case "appearance":
            AppearanceSettingsView(settings: settings)
        case "evaluation":
            EvaluationSettingsView(settings: settings)
        case "datasec":
            DataSecuritySettingsView(settings: settings)
                .environmentObject(bridge)
        case "datamgmt":
            DataManagementSettingsView()
                .environmentObject(bridge)
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
