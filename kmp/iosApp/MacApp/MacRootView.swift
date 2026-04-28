import SwiftUI
import AppKit

struct MacRootView: View {
    @ObservedObject var session: MacAppSessionController
    @StateObject private var commandCenter = MacCommandCenterCoordinator()
    @StateObject private var layoutState = WorkspaceLayoutState()
    @StateObject private var notebookInspectorState = NotebookMacInspectorState()
    @StateObject private var notebookToolbarActions = NotebookMacToolbarActions()
    @StateObject private var physicalTestsToolbarActions = MacPhysicalTestsToolbarActions()
    @State private var selectedClassId: Int64? = nil
    @State private var selectedStudentId: Int64? = nil
    @State private var attendanceToolbarActions: MacAttendanceToolbarActions? = nil
    @State private var dashboardToolbarActions: MacDashboardToolbarActions? = nil
    @State private var studentsReloadToken = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isNotebookInspectorColumnVisible = true

    var body: some View {
        Group {
            switch session.bootstrapState {
            case .idle, .loading:
                ProgressView("Preparando shell macOS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MacAppStyle.pageBackground)
            case .failed(let message):
                ContentUnavailableView(
                    "No se pudo iniciar la shell Mac",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
            case .ready:
                navigationSplit
            }
        }
        .task {
            session.start()
            commandCenter.startIfNeeded()
        }
    }

    @ViewBuilder
    private var navigationSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            macSidebar
        } content: {
            featureContent(for: session.selectedFeature)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
        } detail: {
            featureInspectorColumn(for: session.selectedFeature)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            macToolbar
        }
        .onChange(of: session.selectedFeature) { newFeature in
            columnVisibility = .all
            if newFeature == .notebook {
                isNotebookInspectorColumnVisible = true
            }
        }
    }

    private var macSidebar: some View {
        List(MacFeatureRegistry.all, selection: $session.selectedFeature) { feature in
            HStack(spacing: 10) {
                Image(systemName: feature.systemImage)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(iconTint(for: feature.feature))
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(.callout.weight(.medium))
                    Text(feature.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
            .tag(feature.feature)
            .contextMenu {
                sidebarContextMenu(for: feature.feature)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MiGestor")
        .navigationSubtitle(session.bridge.statsText)
    }

    @ViewBuilder
    private func featureContent(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .dashboard:
            MacDashboardView(
                bridge: session.bridge,
                bootstrap: session.bootstrap,
                onToolbarActionsChange: setDashboardToolbarActions
            )
        case .notebook:
            NotebookModuleView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                macPresentation: .content,
                macInspectorState: notebookInspectorState,
                macToolbarActions: notebookToolbarActions
            )
            .environmentObject(layoutState)
        case .attendance:
            MacAttendanceView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                onToolbarActionsChange: setAttendanceToolbarActions
            )
        case .students:
            MacStudentsView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                presentation: .content,
                reloadToken: studentsReloadToken
            )
        case .rubrics:
            MacRubricsView(bridge: session.bridge)
        case .physicalTests:
            MacPhysicalTestsView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                toolbarActions: physicalTestsToolbarActions
            )
        case .reports:
            MacReportsView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId
            )
        case .planner:
            MacPlannerView(bridge: session.bridge)
        case .sync:
            MacSyncView(bridge: session.bridge, commandCenter: commandCenter)
        case .backups:
            MacBackupsView(bridge: session.bridge)
        case .settings:
            MacSettingsView(session: session)
        }
    }

    @ViewBuilder
    private func featureInspector(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .notebook:
            NotebookModuleView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                macPresentation: .inspector,
                macInspectorState: notebookInspectorState
            )
            .environmentObject(layoutState)
        case .students:
            MacStudentsView(
                bridge: session.bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                presentation: .inspector,
                reloadToken: studentsReloadToken
            )
        default:
            MacModuleInspectorPlaceholder(feature: MacFeatureRegistry.descriptor(for: feature))
        }
    }

    @ViewBuilder
    private func featureInspectorColumn(for feature: MacFeatureDescriptor.Feature) -> some View {
        if feature == .notebook && !isNotebookInspectorColumnVisible {
            Color.clear
                .frame(minWidth: 0, idealWidth: 0, maxWidth: 0, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 1)
                .background(MacAppStyle.pageBackground)
        } else {
            featureInspector(for: feature)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
        }
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await session.bridge.pullMissingSyncChanges() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sincronizar con desktop")

            if session.selectedFeature == .notebook {
                Button {
                    notebookToolbarActions.markAllPresent()
                } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
                .disabled(!notebookToolbarActions.canMarkAllPresent)
                .help("Marcar como presentes los alumnos filtrados")

                Button {
                    notebookToolbarActions.toggleAttendanceQuickMode()
                } label: {
                    Label("Pase rápido", systemImage: notebookToolbarActions.isAttendanceQuickMode ? "figure.walk.circle.fill" : "figure.walk.circle")
                }
                .help("Activar pase rápido de asistencia")

                Button {
                    notebookToolbarActions.undo()
                } label: {
                    Label("Deshacer", systemImage: "arrow.uturn.backward")
                }
                .disabled(!notebookToolbarActions.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Deshacer último cambio del cuaderno")

                Button {
                    toggleNotebookInspectorColumn()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .disabled(!isNotebookInspectorColumnVisible && !notebookToolbarActions.canToggleInspector)
                .help(notebookToolbarActions.isInspectorPresented ? "Ocultar inspector" : "Mostrar inspector")

                Menu {
                    Button("Organizar columnas…") {
                        notebookToolbarActions.openOrganizationMenu()
                    }
                    .disabled(!notebookToolbarActions.organizationMenuAvailable)

                    Divider()

                    Button("Generar síntesis…") {
                        notebookToolbarActions.generateSummary()
                    }

                    if let exportText = notebookToolbarActions.exportText {
                        Divider()
                        ShareLink(item: exportText) {
                            Label("Exportar…", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("Más", systemImage: "ellipsis.circle")
                }
                .help("Más opciones del cuaderno")

                Button {
                    notebookToolbarActions.addColumn()
                } label: {
                    Label("Columna", systemImage: "plus.rectangle")
                }
                .disabled(!notebookToolbarActions.addColumnAvailable)
                .help("Nueva columna")
            }

            if session.selectedFeature == .dashboard, let dashboardToolbarActions {
                Picker(
                    "Modo",
                    selection: Binding(
                        get: { dashboardToolbarActions.modeRawValue },
                        set: { dashboardToolbarActions.setMode($0) }
                    )
                ) {
                    Text("Clase").tag("classroom")
                    Text("Despacho").tag("office")
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .help("Modo operativo del dashboard")

                Button {
                    dashboardToolbarActions.passList()
                } label: {
                    Label("Pasar lista", systemImage: "checkmark.circle")
                }
                .disabled(!dashboardToolbarActions.canRunActions)
                .keyboardShortcut("l", modifiers: [.command])
                .help("Pasar lista para la clase activa")

                Button {
                    dashboardToolbarActions.observation()
                } label: {
                    Label("Observación", systemImage: "note.text.badge.plus")
                }
                .disabled(!dashboardToolbarActions.canRunActions)
                .help("Registrar una observación rápida")
            }

            if session.selectedFeature == .attendance, let attendanceToolbarActions {
                Button {
                    attendanceToolbarActions.markAllPresent()
                } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
                .help("Marcar como presentes los alumnos filtrados")

                Button {
                    attendanceToolbarActions.repeatPattern()
                } label: {
                    Label("Repetir patrón", systemImage: "repeat")
                }
                .help("Repetir el último patrón de asistencia")

                if attendanceToolbarActions.canCloseSelection {
                    Button {
                        attendanceToolbarActions.clearSelection()
                    } label: {
                        Label("Cerrar ficha", systemImage: "sidebar.right")
                    }
                    .help("Cerrar el inspector del alumno")
                }
            }

            if session.selectedFeature == .physicalTests {
                Button {
                    physicalTestsToolbarActions.newBattery()
                } label: {
                    Label("Batería", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(!physicalTestsToolbarActions.canUseClassActions)
                .help("Nueva batería de condición física")

                Button {
                    physicalTestsToolbarActions.capture()
                } label: {
                    Label("Captura", systemImage: "square.and.pencil")
                }
                .disabled(!physicalTestsToolbarActions.canUseClassActions)
                .help("Abrir captura de marcas")

                Button {
                    physicalTestsToolbarActions.createColumns()
                } label: {
                    Label("Cuaderno", systemImage: "tablecells")
                }
                .disabled(!physicalTestsToolbarActions.canUseClassActions)
                .help("Crear columnas de marca y nota en el cuaderno")
            }

            Button {
                if session.selectedFeature == .dashboard, let dashboardToolbarActions {
                    dashboardToolbarActions.refresh()
                } else if session.selectedFeature == .notebook {
                    notebookToolbarActions.refresh()
                } else if session.selectedFeature == .attendance, let attendanceToolbarActions {
                    attendanceToolbarActions.refresh()
                } else if session.selectedFeature == .physicalTests {
                    physicalTestsToolbarActions.refresh()
                } else {
                    Task { await session.bridge.refreshDashboard(mode: .office) }
                }
            } label: {
                Label("Refrescar", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refrescar datos")
        }

        ToolbarItem {
            MacStatusPill(
                label: session.bridge.syncPendingChanges > 0
                    ? "\(session.bridge.syncPendingChanges) pendientes"
                    : "Sincronizado",
                isActive: session.bridge.syncPendingChanges > 0,
                tint: session.bridge.syncPendingChanges > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint
            )
        }
    }

    private func iconTint(for feature: MacFeatureDescriptor.Feature) -> Color {
        switch feature {
        case .dashboard: return .accentColor
        case .notebook: return .purple
        case .attendance: return .green
        case .planner: return .orange
        case .students: return .blue
        case .rubrics: return .teal
        case .physicalTests: return .orange
        case .sync: return .green
        case .backups: return .gray
        case .reports: return .indigo
        case .settings: return .secondary
        }
    }

    private func setDashboardToolbarActions(_ actions: MacDashboardToolbarActions?) {
        DispatchQueue.main.async {
            guard session.selectedFeature == .dashboard else { return }
            dashboardToolbarActions = actions
        }
    }

    private func setAttendanceToolbarActions(_ actions: MacAttendanceToolbarActions?) {
        DispatchQueue.main.async {
            guard session.selectedFeature == .attendance else { return }
            attendanceToolbarActions = actions
        }
    }

    private func toggleNotebookInspectorColumn() {
        guard session.selectedFeature == .notebook else { return }

        if isNotebookInspectorColumnVisible {
            isNotebookInspectorColumnVisible = false
            notebookInspectorState.isPresented = false
            notebookToolbarActions.isInspectorPresented = false
            columnVisibility = .all
            return
        }

        isNotebookInspectorColumnVisible = true
        columnVisibility = .all

        if notebookInspectorState.selection == nil {
            notebookToolbarActions.toggleInspector()
        } else {
            notebookInspectorState.isPresented = true
            notebookToolbarActions.isInspectorPresented = true
        }
    }

    @ViewBuilder
    private func sidebarContextMenu(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .notebook:
            if layoutState.notebookAddColumnAvailable {
                Button {
                    session.selectedFeature = .notebook
                    layoutState.showNotebookAddColumn()
                } label: {
                    Label("Nueva columna", systemImage: "plus.rectangle")
                }
            }
            if layoutState.notebookOrganizationMenuAvailable {
                Button {
                    session.selectedFeature = .notebook
                    layoutState.openNotebookOrganizationMenu()
                } label: {
                    Label("Abrir organización", systemImage: "folder.badge.gearshape")
                }
            }
        case .students:
            Button {
                session.selectedFeature = .students
                studentsReloadToken += 1
            } label: {
                Label("Recargar alumnado", systemImage: "arrow.clockwise")
            }
        case .attendance:
            if let attendanceToolbarActions {
                Button {
                    session.selectedFeature = .attendance
                    attendanceToolbarActions.markAllPresent()
                } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
            }
        default:
            EmptyView()
        }
    }

    private func open(module: AppWorkspaceModule, classId: Int64?, studentId: Int64?) {
        if let classId {
            selectedClassId = classId
        }
        if let studentId {
            selectedStudentId = studentId
        }

        switch module {
        case .notebook:
            session.selectedFeature = .notebook
        case .students:
            session.selectedFeature = .students
        case .reports:
            session.selectedFeature = .reports
        case .attendance:
            session.selectedFeature = .attendance
        case .peTests:
            session.selectedFeature = .physicalTests
        default:
            session.bridge.status = "El módulo \(module.title) todavía no está disponible en la shell Mac."
        }
    }
}

private struct MacModuleInspectorPlaceholder: View {
    let feature: MacFeatureDescriptor

    var body: some View {
        ContentUnavailableView(
            "\(feature.title)",
            systemImage: feature.systemImage,
            description: Text("Este módulo no tiene inspector contextual independiente en la shell Mac.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppStyle.cardBackground)
    }
}

private struct MacBackupsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var backupMessage = "Todavía no se ha creado ningún backup."

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Text("Backups locales")
                .font(MacAppStyle.pageTitle)

            Text(backupMessage)
                .foregroundStyle(.secondary)

            HStack {
                Button("Crear backup") {
                    Task {
                        do {
                            let result = try await bridge.createLocalBackup()
                            backupMessage = "Backup creado en \(result.path)"
                        } catch {
                            backupMessage = "Error creando backup: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        if panel.runModal() == .OK, let path = panel.url?.path {
                            do {
                                let restored = try await bridge.restoreLocalBackup(from: path)
                                backupMessage = restored
                                    ? "Backup restaurado desde \(path)"
                                    : "No se pudo restaurar el backup."
                            } catch {
                                backupMessage = "Error restaurando backup: \(error.localizedDescription)"
                            }
                        }
                    }
                } label: {
                    Text("Restaurar backup")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(MacAppStyle.pagePadding)
    }
}
