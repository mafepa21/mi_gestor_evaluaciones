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
                onNavigate: navigateFromDashboard,
                onToolbarActionsChange: setDashboardToolbarActions
            )
        case .notebook:
            MacNotebookView(
                bridge: session.bridge,
                layoutState: layoutState,
                toolbarActions: notebookToolbarActions,
                inspectorState: notebookInspectorState,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                presentation: .content,
                onToggleInspectorColumn: toggleNotebookInspectorColumn
            )
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
            MacSettingsView(session: session, commandCenter: commandCenter) {
                session.selectedFeature = .sync
            }
        }
    }

    @ViewBuilder
    private func featureInspector(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .notebook:
            MacNotebookView(
                bridge: session.bridge,
                layoutState: layoutState,
                toolbarActions: notebookToolbarActions,
                inspectorState: notebookInspectorState,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                presentation: .inspector,
                onToggleInspectorColumn: toggleNotebookInspectorColumn
            )
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

            }

            if session.selectedFeature == .dashboard, let dashboardToolbarActions {
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

            if session.selectedFeature != .notebook {
                Button {
                    if session.selectedFeature == .dashboard, let dashboardToolbarActions {
                        dashboardToolbarActions.refresh()
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

    private func navigateFromDashboard(_ destination: MacDashboardDestination) {
        switch destination {
        case .attendance(let classId):
            open(module: .attendance, classId: classId, studentId: nil)
        case .notebook(let classId):
            open(module: .notebook, classId: classId, studentId: nil)
        case .rubrics(let classId):
            if let classId {
                selectedClassId = classId
            }
            session.selectedFeature = .rubrics
        case .plannerAgenda:
            session.selectedFeature = .planner
        case .plannerSession(let sessionId):
            session.selectedFeature = .planner
            if let sessionId {
                session.bridge.status = "Abriendo Planner para la sesión \(sessionId)."
            }
        case .students(let classId):
            open(module: .students, classId: classId, studentId: nil)
        case .reports(let classId):
            open(module: .reports, classId: classId, studentId: nil)
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

private struct MacNotebookView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var toolbarActions: NotebookMacToolbarActions
    @ObservedObject var inspectorState: NotebookMacInspectorState
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?

    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let presentation: NotebookMacPresentation
    let onToggleInspectorColumn: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var isContentPresentation: Bool {
        presentation == .content || presentation == .full
    }

    @ViewBuilder
    var body: some View {
        let notebook = NotebookModuleView(
            bridge: bridge,
            selectedClassId: $selectedClassId,
            selectedStudentId: $selectedStudentId,
            onOpenModule: onOpenModule,
            macPresentation: presentation,
            macInspectorState: inspectorState,
            macToolbarActions: isContentPresentation ? toolbarActions : nil
        )
        .environmentObject(layoutState)

        if isContentPresentation {
            notebook
                .toolbar {
                notebookToolbar
                }
                .searchable(
                    text: Binding(
                        get: { searchText },
                        set: { newValue in
                            searchText = newValue
                            layoutState.setNotebookSearchText(newValue)
                        }
                    ),
                    placement: .toolbar,
                    prompt: "Buscar alumno..."
                )
                .searchFocused($isSearchFocused)
                .onAppear {
                    searchText = layoutState.notebookSearchText
                }
        } else {
            notebook
                .onAppear {
                    searchText = layoutState.notebookSearchText
                }
        }
    }

    @ToolbarContentBuilder
    private var notebookToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } label: {
                Label("Buscar", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)
            .help("Buscar en el cuaderno")

            Button {
                toolbarActions.addColumn()
            } label: {
                Label("Nueva columna", systemImage: "plus.rectangle")
            }
            .disabled(!toolbarActions.addColumnAvailable)
            .keyboardShortcut("n", modifiers: .command)
            .help("Nueva columna")

            Button {
                onToggleInspectorColumn()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .disabled(!toolbarActions.canToggleInspector && !inspectorState.isPresented)
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(toolbarActions.isInspectorPresented ? "Ocultar inspector" : "Mostrar inspector")

            Menu {
                Button {
                    layoutState.setNotebookSurfaceMode(NotebookSurfaceMode.grid.rawValue)
                } label: {
                    Label("Rejilla", systemImage: "tablecells")
                }
                .keyboardShortcut("1", modifiers: .command)

                Button {
                    layoutState.setNotebookSurfaceMode(NotebookSurfaceMode.seatingPlan.rawValue)
                } label: {
                    Label("Plano", systemImage: "square.grid.3x3.square")
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button {
                    toolbarActions.openOrganizationMenu()
                } label: {
                    Label("Organizar columnas", systemImage: "folder.badge.gearshape")
                }
                .disabled(!toolbarActions.organizationMenuAvailable)
            } label: {
                Label("Organizar columnas", systemImage: "rectangle.3.group")
            }
            .help("Organizar columnas y cambiar vista")

            Menu {
                Button {
                    layoutState.setNotebookGroupFilter(nil)
                } label: {
                    Label("Todos los grupos", systemImage: layoutState.notebookSelectedGroupId == nil ? "checkmark" : "line.3.horizontal.decrease.circle")
                }

                if !layoutState.notebookAvailableGroups.isEmpty {
                    Divider()
                }

                ForEach(layoutState.notebookAvailableGroups) { group in
                    Button {
                        layoutState.setNotebookGroupFilter(group.id)
                    } label: {
                        Label(
                            "\(group.name) (\(group.studentCount))",
                            systemImage: layoutState.notebookSelectedGroupId == group.id ? "checkmark" : "person.3"
                        )
                    }
                }
            } label: {
                Label("Filtros", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filtrar alumnado")

            if let exportText = toolbarActions.exportText {
                ShareLink(item: exportText) {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
                .help("Exportar cuaderno")
            } else {
                Button {
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
                .disabled(true)
                .help("Exportar cuaderno")
            }

            Button {
                toolbarActions.undo()
            } label: {
                Label("Deshacer", systemImage: "arrow.uturn.backward")
            }
            .disabled(!toolbarActions.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Deshacer ultimo cambio")

            Button {
                toolbarActions.refresh()
            } label: {
                Label("Refrescar", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refrescar datos")
        }
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
