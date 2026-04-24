import SwiftUI
import PhotosUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

private struct NotebookInspectorSelection: Identifiable, Hashable {
    let studentId: Int64
    let columnId: String

    var id: String { "\(studentId)|\(columnId)" }
}

private struct NotebookTableRow: Identifiable {
    let student: Student
    let row: NotebookRow
    let groupName: String

    var id: Int64 { student.id }
}

private enum NotebookFixedColumn: String, Identifiable, CaseIterable {
    case photo
    case name
    case group
    case followUp
    case attendance
    case average

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Foto"
        case .name: return "Nombre"
        case .group: return "Grupo"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .average: return "Media"
        }
    }

    var subtitle: String {
        switch self {
        case .photo: return "Alumno"
        case .name: return "Alumno"
        case .group: return "Contexto"
        case .followUp: return "Estado"
        case .attendance: return "Resumen"
        case .average: return "Promedio"
        }
    }

    var width: CGFloat {
        switch self {
        case .photo: return 82
        case .name: return 180
        case .group: return 110
        case .followUp: return 120
        case .attendance: return 120
        case .average: return 110
        }
    }
}

private enum NotebookDisplaySegment: Identifiable {
    case fixed(NotebookFixedColumn)
    case column(NotebookColumnDefinition)
    case collapsedCategory(NotebookColumnCategory, [NotebookColumnDefinition])

    var id: String {
        switch self {
        case .fixed(let fixed):
            return "fixed_\(fixed.rawValue)"
        case .column(let column):
            return "column_\(column.id)"
        case .collapsedCategory(let category, _):
            return "collapsed_\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .fixed(let fixed):
            return fixed.title
        case .column(let column):
            return column.title
        case .collapsedCategory(let category, _):
            return category.name
        }
    }
}

private enum NotebookViewPreset: String, CaseIterable, Identifiable {
    case all
    case evaluation
    case followUp
    case attendance
    case extras
    case physicalEducation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Vista completa"
        case .evaluation: return "Vista evaluación"
        case .followUp: return "Vista seguimiento"
        case .attendance: return "Vista asistencia"
        case .extras: return "Vista extras"
        case .physicalEducation: return "Vista EF"
        }
    }
}

enum NotebookSurfaceMode: String, CaseIterable, Identifiable {
    case grid
    case seatingPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Rejilla"
        case .seatingPlan: return "Plano"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "tablecells"
        case .seatingPlan: return "square.grid.3x3.square"
        }
    }
}

private struct NotebookSeatPosition: Codable {
    var x: Double
    var y: Double
}

private struct NotebookAddColumnContext: Identifiable {
    let categoryId: String?
    let startsCreatingCategory: Bool

    var id: String {
        "\(categoryId ?? "none")|\(startsCreatingCategory)"
    }
}

enum NotebookToastStyle: Equatable {
    case success
    case warning

    var tint: Color {
        switch self {
        case .success: return NotebookStyle.successTint
        case .warning: return NotebookStyle.warningTint
        }
    }
}

private struct NotebookToast: Identifiable {
    let id = UUID()
    let message: String
    let style: NotebookToastStyle
}

private enum NotebookHeaderLaneItem: Identifiable {
    case spacer(id: String, width: CGFloat)
    case folder(NotebookColumnCategory, [NotebookColumnDefinition], CGFloat)

    var id: String {
        switch self {
        case .spacer(let id, _): return id
        case .folder(let category, _, _): return "folder_\(category.id)"
        }
    }
}

private enum NotebookAIFlowMode {
    case createColumn
    case selection
}

private enum NotebookAIColumnScope: String, CaseIterable, Identifiable {
    case visibleColumns
    case evaluableColumns
    case allManagedColumns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visibleColumns: return "Columnas visibles"
        case .evaluableColumns: return "Solo evaluables"
        case .allManagedColumns: return "Todas las gestionadas"
        }
    }
}

private struct NotebookAISheetRequest: Identifiable {
    let mode: NotebookAIFlowMode
    let studentIds: [Int64]
    let targetColumnId: String?

    var id: String {
        let modeLabel = mode == .createColumn ? "create" : "selection"
        return "\(modeLabel)|\(studentIds.map(String.init).joined(separator: ","))|\(targetColumnId ?? "none")"
    }
}

private struct NotebookSummarySheetRequest: Identifiable {
    let targetColumnId: String?

    var id: String { targetColumnId ?? "summary" }
}

enum NotebookNavigationDirection: String, CaseIterable, Identifiable {
    case up
    case down
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return "Arriba"
        case .down: return "Abajo"
        case .left: return "Izquierda"
        case .right: return "Derecha"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}

private struct NotebookFormulaEditRequest: Identifiable {
    let columnId: String

    var id: String { columnId }
}

private struct NotebookFormulaCellDisplay {
    let text: String
    let isError: Bool
}

private struct NotebookCellUndoEntry {
    let studentId: Int64
    let column: NotebookColumnDefinition
    let previousValue: String
    let previousDisplayLabel: String?
}

struct NotebookModuleView: View {
    private let notebookGridRowHeight: CGFloat = 72
    private let notebookGridHeaderHeight: CGFloat = 68

    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State private var addColumnContext: NotebookAddColumnContext? = nil
    @State private var searchText = ""
    @State private var selectedGroupId: Int64? = nil
    @State private var inspectorSelection: NotebookInspectorSelection? = nil
    @State private var inspectorNoteDraft = ""
    @State private var inspectorIconDraft = ""
    @State private var inspectorAttachmentUris: [String] = []
    @State private var viewPreset: NotebookViewPreset = .all
    @State private var surfaceMode: NotebookSurfaceMode = .grid
    @State private var isInspectorPresented = false
    @State private var todayAttendanceByStudentId: [Int64: String] = [:]
    @State private var incidentCountByStudentId: [Int64: Int] = [:]
    @State private var seatPositions: [Int64: NotebookSeatPosition] = [:]
    @State private var highlightedRandomStudentId: Int64? = nil
    @State private var selectedAttachmentPhoto: PhotosPickerItem?
    @State private var isCreateCategoryAlertPresented = false
    @State private var categoryDraft = ""
    @State private var editingCategoryId: String? = nil
    @State private var isNotebookTabAlertPresented = false
    @State private var notebookTabDraft = ""
    @State private var editingNotebookTabId: String? = nil
    @State private var pendingDeleteNotebookTab: NotebookTab? = nil
    @State private var isRenameColumnAlertPresented = false
    @State private var columnDraft = ""
    @State private var editingColumnId: String? = nil
    @State private var pendingDeleteColumn: NotebookColumnDefinition? = nil
    @State private var pendingDeleteCategory: NotebookColumnCategory? = nil
    @State private var isOrganizationMenuPresented = false
    @State private var toast: NotebookToast? = nil
    @State private var isAttendanceQuickMode = false
    @State private var isMarkAllPresentDialogPresented = false
    @State private var undoStack: [NotebookCellUndoEntry] = []
    @State private var cellReloadRevision = 0
    @State private var highlightedCategoryId: String? = nil
    @State private var notebookAISheetRequest: NotebookAISheetRequest? = nil
    @State private var notebookSummarySheetRequest: NotebookSummarySheetRequest? = nil
    @State private var riskLevelCache: [Int64: RiskLevel] = [:]
    @State private var riskComputationKey: String?
    @State private var isPrecomputingRiskLevels = false
    @AppStorage("notebook.fixedZoneWidth") private var fixedZoneWidthStored = 460.0
    @State private var isDraggingFixedZoneDivider = false
    @State private var fixedZoneDragStartWidth: CGFloat = 0
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var formulaEditRequest: NotebookFormulaEditRequest? = nil
    @State private var formulaDraft = ""
    @State private var formulaAIPrompt = ""
    @State private var formulaAIMessage: String? = nil
    @State private var isFormulaAIGenerating = false
    @State private var activeChoiceCellId: String? = nil
    @AppStorage("notebook.navigationDirection") private var navigationDirectionRaw = NotebookNavigationDirection.down.rawValue
    @FocusState private var focusedCellId: String?
    private let formulaAIService = AppleFoundationFormulaService()

    private var navigationDirection: NotebookNavigationDirection {
        get { NotebookNavigationDirection(rawValue: navigationDirectionRaw) ?? .down }
        nonmutating set { navigationDirectionRaw = newValue.rawValue }
    }

    var body: some View {
        notebookLifecycleCleanup(
            notebookObservationModifiers(
                notebookSheetAndTaskModifiers(notebookContentWithDialogs)
            )
        )
    }

    private var notebookContentWithDialogs: some View {
        Group {
            if let data = bridge.notebookState as? NotebookUiStateData {
                notebookLoadedContent(data: data)
            } else if bridge.notebookState is NotebookUiStateLoading {
                NotebookStateCard(
                    systemImage: "tablecells",
                    title: "Cargando cuaderno",
                    message: "Estamos preparando el cuaderno iPad."
                ) {
                    ProgressView()
                }
            } else if let error = bridge.notebookState as? NotebookUiStateError {
                NotebookStateCard(
                    systemImage: "exclamationmark.triangle",
                    title: "No se pudo cargar el cuaderno",
                    message: error.message,
                    tint: NotebookStyle.warningTint
                )
            } else {
                NotebookStateCard(
                    systemImage: "tablecells",
                    title: "Sin datos del cuaderno",
                    message: "Selecciona una clase para empezar."
                )
            }
        }
        .background(EvaluationBackdrop())
        .overlay(alignment: .bottom) {
            if let toast {
                notebookToastView(toast)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(editingCategoryId == nil ? "Nueva categoría" : "Renombrar categoría", isPresented: $isCreateCategoryAlertPresented) {
            TextField("Nombre", text: $categoryDraft)
            Button("Cancelar", role: .cancel) {
                editingCategoryId = nil
                categoryDraft = ""
            }
            Button(editingCategoryId == nil ? "Crear" : "Guardar") {
                saveCategoryFromDraft()
            }
        } message: {
            Text("La categoría agrupa columnas relacionadas en el cuaderno.")
        }
        .alert(editingNotebookTabId == nil ? "Nueva pestaña" : "Renombrar pestaña", isPresented: $isNotebookTabAlertPresented) {
            TextField("Nombre", text: $notebookTabDraft)
            Button("Cancelar", role: .cancel) {
                resetNotebookTabDraft()
            }
            Button(editingNotebookTabId == nil ? "Crear" : "Guardar") {
                saveNotebookTabDraft()
            }
            .disabled(notebookTabDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Cada pestaña funciona como un cuaderno temático independiente dentro de la clase.")
        }
        .alert("Renombrar columna", isPresented: $isRenameColumnAlertPresented) {
            TextField("Título", text: $columnDraft)
            Button("Cancelar", role: .cancel) {
                editingColumnId = nil
                columnDraft = ""
            }
            Button("Guardar") {
                saveColumnRename()
            }
        }
        .confirmationDialog(
            "Eliminar columna",
            isPresented: Binding(
                get: { pendingDeleteColumn != nil },
                set: { if !$0 { pendingDeleteColumn = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let column = pendingDeleteColumn {
                Button("Eliminar columna", role: .destructive) {
                    deleteColumn(column)
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteColumn = nil
                }
            }
        } message: {
            if let column = pendingDeleteColumn {
                deleteColumnDialogMessage(for: column)
            }
        }
        .confirmationDialog(
            "Eliminar categoría",
            isPresented: isDeleteCategoryDialogPresented,
            titleVisibility: .visible
        ) {
            deleteCategoryDialogActions()
        } message: {
            deleteCategoryDialogMessageContent()
        }
        .confirmationDialog(
            "Eliminar pestaña",
            isPresented: Binding(
                get: { pendingDeleteNotebookTab != nil },
                set: { if !$0 { pendingDeleteNotebookTab = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tab = pendingDeleteNotebookTab {
                Button("Eliminar “\(tab.title)”", role: .destructive) {
                    deleteNotebookTab(tab)
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteNotebookTab = nil
                }
            }
        } message: {
            if let tab = pendingDeleteNotebookTab {
                Text("Se eliminará la pestaña “\(tab.title)” y las columnas que solo pertenezcan a ella.")
            }
        }
        .confirmationDialog(
            "Marcar todos como presentes",
            isPresented: $isMarkAllPresentDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Marcar alumnos visibles") {
                if let data = bridge.notebookState as? NotebookUiStateData {
                    markAllVisibleStudentsPresent(data: data)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            if let data = bridge.notebookState as? NotebookUiStateData {
                Text("Se marcarán como presentes \(filteredRows(data: data).count) alumnos visibles.")
            }
        }
    }

    private func notebookSheetAndTaskModifiers<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $isOrganizationMenuPresented) {
                notebookOrganizationSheet(data: bridge.notebookState as? NotebookUiStateData)
            }
            .task {
                if let selectedClassId,
                   bridge.notebookViewModel.currentClassId?.int64Value != selectedClassId {
                    bridge.selectClass(id: selectedClassId)
                } else if selectedClassId == nil,
                          let notebookClassId = bridge.notebookViewModel.currentClassId?.int64Value {
                    self.selectedClassId = notebookClassId
                }
            }
            .task(id: notebookSupportRefreshKey) {
                restoreSeatPositions()
                await refreshNotebookSignals()
            }
            .task(id: notebookRiskRefreshKey) {
                await precomputeRiskLevelsForVisibleRows()
            }
    }

    private func notebookObservationModifiers<Content: View>(_ content: Content) -> some View {
        notebookToolbarObservationModifiers(
            notebookSelectionObservationModifiers(content)
        )
    }

    private func notebookSelectionObservationModifiers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: selectedClassId) { newValue in
                undoStack.removeAll()
                guard let newValue else { return }
                guard bridge.notebookViewModel.currentClassId?.int64Value != newValue else { return }
                selectNotebookClass(newValue)
            }
            .onChange(of: bridge.selectedNotebookTabId) { _ in
                undoStack.removeAll()
                restoreSeatPositions()
                Task { await refreshNotebookSignals() }
            }
            .onChange(of: inspectorSelection) { _ in
                syncInspectorDraft()
                if inspectorSelection == nil {
                    isInspectorPresented = false
                }
            }
            .onChange(of: selectedAttachmentPhoto) { newValue in
                guard let newValue else { return }
                Task { await importSelectedAttachment(from: newValue) }
            }
    }

    private func notebookToolbarObservationModifiers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: isInspectorPresented) { _ in
                if let data = bridge.notebookState as? NotebookUiStateData {
                    syncToolbarState(data: data)
                }
            }
            .onChange(of: surfaceMode) { _ in
                if let data = bridge.notebookState as? NotebookUiStateData {
                    syncToolbarState(data: data)
                }
            }
            .onChange(of: selectedGroupId) { _ in
                if let data = bridge.notebookState as? NotebookUiStateData {
                    syncToolbarState(data: data)
                }
                riskComputationKey = nil
            }
            .onChange(of: bridge.notebookState is NotebookUiStateData) { _ in
                restoreSeatPositions()
                riskComputationKey = nil
            }
    }

    private func notebookLifecycleCleanup<Content: View>(_ content: Content) -> some View {
        content
            .onDisappear {
                layoutState.clearNotebookToolbar()
            }
    }

    private func centerPanel(data: NotebookUiStateData) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NotebookTopBar(
                    bridge: bridge,
                    searchText: $searchText,
                    surfaceMode: $surfaceMode,
                    navigationDirection: navigationDirection,
                    isInspectorPresented: isInspectorPresented,
                    isAttendanceQuickMode: isAttendanceQuickMode,
                    canMarkAllPresent: !filteredRows(data: data).isEmpty,
                    canUndo: !undoStack.isEmpty,
                    onSelectClass: selectNotebookClass,
                    onOpenOrganizationMenu: {
                        isOrganizationMenuPresented = true
                    },
                    onToggleInspector: {
                        if inspectorSelection == nil {
                            openInspectorForSelection(data)
                        }
                        if inspectorSelection != nil {
                            isInspectorPresented.toggle()
                        }
                    },
                    onOpenAdvancedMenu: {
                        isOrganizationMenuPresented = true
                    },
                    onOpenAddColumn: {
                        addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
                    },
                    onNavigationDirectionChange: { direction in
                        navigationDirection = direction
                    },
                    onToggleAttendanceQuickMode: {
                        isAttendanceQuickMode.toggle()
                        if isAttendanceQuickMode {
                            activeChoiceCellId = nil
                            focusedCellId = nil
                        }
                    },
                    onMarkAllPresent: {
                        requestMarkAllVisibleStudentsPresent(data: data)
                    },
                    onUndo: {
                        undoLastCellChange()
                    },
                    onGenerateSummaryFallback: {
                        notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: nil)
                    },
                    exportText: exportText(data: data)
                )
                Divider()
                notebookTabStrip(data: data)
                Divider()
                spreadsheetContent(data: data)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isInspectorPresented {
                Divider().opacity(0.16)
                inspectorPanel(data: data)
                    .frame(width: 360)
                    .background(NotebookStyle.surfaceMuted)
            }
        }
        .background(EvaluationBackdrop())
    }

    private func notebookTabStrip(data: NotebookUiStateData) -> some View {
        let tabs = orderedNotebookTabs(data: data)
        let activeTabId = activeNotebookTabId(data: data)

        return HStack(spacing: 10) {
            if tabs.isEmpty {
                Label("Organiza el cuaderno por temas", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button {
                    presentCreateNotebookTab()
                } label: {
                    Label("Crear primera pestaña", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.id) { tab in
                            notebookTabButton(tab: tab, isSelected: tab.id == activeTabId)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    presentCreateNotebookTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Nueva pestaña")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func notebookTabButton(tab: NotebookTab, isSelected: Bool) -> some View {
        Button {
            selectNotebookTab(tab.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.28) : NotebookStyle.softBorder.opacity(0.9), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Renombrar") {
                presentRenameNotebookTab(tab)
            }
            Button("Eliminar pestaña", role: .destructive) {
                pendingDeleteNotebookTab = tab
            }
        }
        .help("Abrir \(tab.title)")
    }

    @ViewBuilder
    private func deleteColumnDialogMessage(for column: NotebookColumnDefinition) -> some View {
        let message = "Se eliminará “\(column.title)” y su vínculo asociado si pertenece a una evaluación."
        Text(message)
    }

    @ViewBuilder
    private func deleteCategoryDialogMessage(for category: NotebookColumnCategory) -> some View {
        let notebookData = bridge.notebookState as? NotebookUiStateData
        Text(deleteCategoryMessage(for: category, data: notebookData))
    }

    private var isDeleteCategoryDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteCategory != nil },
            set: { if !$0 { pendingDeleteCategory = nil } }
        )
    }

    @ViewBuilder
    private func deleteCategoryDialogActions() -> some View {
        if let category = pendingDeleteCategory {
            Button("Eliminar solo la categoría", role: .destructive) {
                bridge.deleteColumnCategory(id: category.id, preserveColumns: true)
                showToast("Categoría eliminada; las columnas se han conservado")
                pendingDeleteCategory = nil
            }
            Button("Eliminar categoría y columnas", role: .destructive) {
                bridge.deleteColumnCategory(id: category.id, preserveColumns: false)
                showToast("Categoría y columnas eliminadas", style: .warning)
                pendingDeleteCategory = nil
            }
            Button("Cancelar", role: .cancel) {
                pendingDeleteCategory = nil
            }
        }
    }

    @ViewBuilder
    private func deleteCategoryDialogMessageContent() -> some View {
        if let category = pendingDeleteCategory {
            deleteCategoryDialogMessage(for: category)
        }
    }

    @ViewBuilder
    private func spreadsheetContent(data: NotebookUiStateData) -> some View {
        let rows = filteredRows(data: data)
        let segments = displaySegments(data: data)
        let fixedSegments = visibleFixedSegments(in: segments)
        let scrollableSegments = segments.filter { !isFixedSegment($0) }
        let laneItems = headerLaneItems(data: data, segments: scrollableSegments)
        let hasFolders = laneItems.contains {
            if case .folder = $0 { return true }
            return false
        }

        if rows.isEmpty {
            NotebookStateCard(
                systemImage: "person.3.sequence",
                title: "Sin alumnos visibles",
                message: "Ajusta la búsqueda o el filtro de grupo para ver filas del cuaderno."
            )
        } else if surfaceMode == .seatingPlan {
            seatingPlanContent(data: data, rows: rows)
        } else {
            NotebookDataGrid(
                fixedColumnWidth: fixedZoneWidth
            ) {
                Color.clear
                    .frame(height: hasFolders ? 64 : 0)
            } dividerHandle: {
                NotebookDividerHandle(isDragging: isDraggingFixedZoneDivider) { translationWidth in
                    if !isDraggingFixedZoneDivider {
                        isDraggingFixedZoneDivider = true
                        fixedZoneDragStartWidth = fixedZoneWidth
                    }
                    let newWidth = fixedZoneDragStartWidth + translationWidth
                    fixedZoneWidthStored = Double(min(maxFixedZoneWidth, max(minFixedZoneWidth, newWidth)))
                } onDragEnded: {
                    isDraggingFixedZoneDivider = false
                    snapFixedZoneWidth()
                }
            } scrollTopAccessory: {
                if hasFolders {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(laneItems, id: \.id) { item in
                            switch item {
                            case .spacer(_, let width):
                                Color.clear
                                    .frame(width: width, height: 1)
                            case .folder(let category, let columns, let width):
                                categoryFolderHeader(category: category, columns: columns, width: width)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
            } fixedHeader: {
                fixedHeaderRow(segments: fixedSegments, data: data)
            } scrollHeader: {
                headerRow(segments: scrollableSegments, data: data)
            } fixedRows: {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        notebookRowView(
                            item: item,
                            data: data,
                            segments: fixedSegments,
                            rowIndex: index,
                            allRows: rows,
                            navigableSegments: scrollableSegments
                        )
                        Divider()
                            .overlay(NotebookStyle.softBorder)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 16)
            } scrollRows: {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        notebookRowView(
                            item: item,
                            data: data,
                            segments: scrollableSegments,
                            rowIndex: index,
                            allRows: rows,
                            navigableSegments: scrollableSegments
                        )
                        Divider()
                            .overlay(NotebookStyle.softBorder)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func headerRow(segments: [NotebookDisplaySegment], data: NotebookUiStateData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(segments, id: \.id) { segment in
                headerChip(for: segment, data: data)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: notebookGridHeaderHeight, alignment: .topLeading)
        .background(
            NotebookStyle.surfaceSoft.opacity(0.9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NotebookStyle.softBorder)
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private func fixedHeaderRow(segments: [NotebookDisplaySegment], data: NotebookUiStateData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(segments, id: \.id) { segment in
                headerChip(for: segment, data: data)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: notebookGridHeaderHeight, alignment: .topLeading)
        .background(
            NotebookStyle.surfaceSoft.opacity(0.9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NotebookStyle.softBorder)
                        .frame(height: 1)
                }
        )
    }

    private func isFixedSegment(_ segment: NotebookDisplaySegment) -> Bool {
        if case .fixed = segment {
            return true
        }
        return false
    }

    private func visibleFixedSegments(in segments: [NotebookDisplaySegment]) -> [NotebookDisplaySegment] {
        let allowedColumns = visibleFixedColumns
        return segments.filter { segment in
            guard case .fixed(let fixed) = segment else { return false }
            return allowedColumns.contains(fixed)
        }
    }

    private var fixedZoneWidth: CGFloat {
        min(maxFixedZoneWidth, max(minFixedZoneWidth, CGFloat(fixedZoneWidthStored)))
    }

    private var minFixedZoneWidth: CGFloat { 220 }
    private var maxFixedZoneWidth: CGFloat { 700 }

    private var visibleFixedColumns: [NotebookFixedColumn] {
        var columns: [NotebookFixedColumn] = [.photo, .name]
        if fixedZoneWidth > 290 { columns.append(.followUp) }
        if fixedZoneWidth > 400 { columns.append(.attendance) }
        if fixedZoneWidth > 490 { columns.append(.average) }
        if fixedZoneWidth > 610 { columns.append(.group) }
        return columns
    }

    private func snapFixedZoneWidth() {
        let snapPoints: [CGFloat] = [220, 360, 460, 580]
        let current = fixedZoneWidth
        guard let nearest = snapPoints.min(by: { abs($0 - current) < abs($1 - current) }) else { return }
        if abs(nearest - current) < 30 {
            withAnimation(.spring(duration: 0.2, bounce: 0.15)) {
                fixedZoneWidthStored = Double(nearest)
            }
        }
    }

    private func segmentWidth(_ segment: NotebookDisplaySegment) -> CGFloat {
        switch segment {
        case .fixed(let fixed):
            return resolvedFixedWidth(for: fixed)
        case .column(let column):
            return resolvedColumnWidth(for: column)
        case .collapsedCategory:
            return 150
        }
    }

    private func resolvedFixedWidth(for fixed: NotebookFixedColumn) -> CGFloat {
        let visibleColumns = visibleFixedColumns
        let trailingColumns = visibleColumns.filter { $0 != .photo && $0 != .name }
        let trailingWidth = trailingColumns.reduce(CGFloat.zero) { partial, column in
            partial + defaultFixedWidth(for: column)
        }
        let spacing = CGFloat(max(visibleColumns.count - 1, 0)) * 12
        let horizontalPadding: CGFloat = 32

        switch fixed {
        case .photo:
            return 52
        case .name:
            return max(156, fixedZoneWidth - trailingWidth - spacing - horizontalPadding - 52)
        default:
            return defaultFixedWidth(for: fixed)
        }
    }

    private func defaultFixedWidth(for fixed: NotebookFixedColumn) -> CGFloat {
        switch fixed {
        case .photo: return 52
        case .name: return 180
        case .group: return 90
        case .followUp: return 100
        case .attendance: return 90
        case .average: return 90
        }
    }

    private func resolvedColumnWidth(for column: NotebookColumnDefinition) -> CGFloat {
        columnWidths[column.id] ?? CGFloat(max(column.widthDp, 140))
    }

    private func notebookLoadedContent(data: NotebookUiStateData) -> some View {
        centerPanel(data: data)
            .sheet(item: $addColumnContext) { context in
                addColumnSheetPresentation(for: context)
            }
            .sheet(item: $notebookAISheetRequest) { request in
                notebookAISheet(request: request, data: data)
            }
            .sheet(item: $notebookSummarySheetRequest) { request in
                NotebookSummaryGenerationSheet(
                    bridge: bridge,
                    initialTargetColumnId: request.targetColumnId
                ) { message, style in
                    showToast(message, style: style)
                }
            }
            .sheet(item: $formulaEditRequest) { request in
                formulaEditorSheet(request: request, data: data)
            }
            .sheet(isPresented: Binding(
                get: { bridge.showingBulkRubricEvaluation },
                set: { isPresented in
                    if !isPresented {
                        bridge.closeBulkRubricEvaluation()
                    }
                }
            )) {
                RubricBulkEvaluationSheet(bridge: bridge)
                    #if os(macOS)
                    .frame(width: 1180, height: 760)
                    #else
                    .presentationDetents([.large])
                    #endif
            }
            .navigationTitle("Cuaderno")
            .notebookNavigationSubtitle(notebookNavigationSubtitle(data: data))
            .notebookKeyboardNavigation {
                navigateFromFocused(direction: navigationDirection, data: data)
            }
            .onAppear {
                ensureActiveNotebookTab(data: data)
                syncToolbarState(data: data)
            }
            .onChange(of: notebookTabsStateKey(data: data)) { _ in
                ensureActiveNotebookTab(data: data)
            }
            .onChange(of: toolbarStateKey(data: data)) { _ in
                syncToolbarState(data: data)
            }
    }

    @ViewBuilder
    private func addColumnSheetPresentation(for context: NotebookAddColumnContext) -> some View {
        let content = AddColumnSheet(
            bridge: bridge,
            initialCategoryId: context.categoryId,
            startsCreatingCategory: context.startsCreatingCategory
        )

        #if os(macOS)
        content
            .frame(width: 560, height: 620)
        #else
        content
            .presentationDetents([.large])
        #endif
    }

    @ViewBuilder
    private func formulaEditorSheet(request: NotebookFormulaEditRequest, data: NotebookUiStateData) -> some View {
        if let column = data.sheet.columns.first(where: { $0.id == request.columnId }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fórmula de columna")
                            .font(.title3.bold())
                        Text(column.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cerrar") {
                        formulaEditRequest = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding(22)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Edita la fórmula una vez y se aplicará a todas las celdas de esta columna calculada.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NotebookFormulaKeyboard(
                        formula: $formulaDraft,
                        availableColumns: formulaReferenceColumns(for: column, data: data)
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ayuda con Apple Intelligence")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.3)

                        TextField("Ej: media del examen y la rúbrica, o corrige esta fórmula", text: $formulaAIPrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)

                        HStack {
                            Button {
                                generateFormulaWithAI(column: column, data: data)
                            } label: {
                                Label(isFormulaAIGenerating ? "Pensando…" : "Generar / corregir fórmula", systemImage: "apple.intelligence")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isFormulaAIGenerating || formulaAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if let formulaAIMessage {
                                Text(formulaAIMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(22)

                Spacer(minLength: 0)
                Divider()

                HStack {
                    Button("Cancelar") {
                        formulaEditRequest = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Guardar fórmula") {
                        saveFormula(column)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(18)
            }
            .frame(width: 620, height: 560)
        } else {
            Text("No se encontró la columna")
                .padding()
        }
    }

    private func formulaReferenceColumns(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        visibleNotebookSourceColumns(data: data)
            .filter { $0.id != column.id && $0.type != .calculated }
    }

    private func notebookNavigationSubtitle(data: NotebookUiStateData) -> String {
        let context = headerContextLine(in: data)
        let studentCount = filteredRows(data: data).count
        return "\(context) · \(studentCount) alumnos"
    }

    private func notebookTabsStateKey(data: NotebookUiStateData) -> String {
        data.sheet.tabs
            .sorted { $0.id < $1.id }
            .map { "\($0.id)|\($0.title)|\($0.order)|\($0.parentTabId ?? "")" }
            .joined(separator: "¬")
    }

    private func notebookAISheet(request: NotebookAISheetRequest, data: NotebookUiStateData) -> some View {
        NotebookAICommentSheet(
            bridge: bridge,
            data: data,
            managedColumns: notebookSourceColumns(data: data),
            visibleColumns: visibleNotebookSourceColumns(data: data),
            selectedStudentIds: request.studentIds,
            targetColumnId: request.targetColumnId,
            mode: request.mode
        ) { message, style in
            showToast(message, style: style)
        }
    }

    private func inspectorPanel(data: NotebookUiStateData) -> some View {
        Group {
            if let selection = inspectorSelection,
               let item = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }),
               let column = data.sheet.columns.first(where: { $0.id == selection.columnId }) {
                let persistedCell = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Inspector")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                        inspectorInfoRow("Alumno", value: "\(item.student.firstName) \(item.student.lastName)")
                        inspectorInfoRow("Columna", value: column.title)
                        inspectorInfoRow("Valor", value: displayValue(for: item, column: column))
                        inspectorInfoRow("Categoría", value: categoryTitle(for: column, data: data))
                        inspectorInfoRow("Peso", value: String(format: "%.1f", column.weight))
                        inspectorInfoRow("Cuenta para media", value: column.countsTowardAverage ? "Sí" : "No")
                        inspectorInfoRow("Tipo", value: "\(column.instrumentKind.name) · \(column.inputKind.name)")
                        inspectorInfoRow("Fecha", value: formattedDate(column.dateEpochMs?.int64Value))
                        inspectorInfoRow("Criterio asociado", value: column.competencyCriteriaIds.isEmpty ? "Sin criterio" : column.competencyCriteriaIds.map(String.init).joined(separator: ", "))
                        inspectorInfoRow("Evidencia", value: evidenceLabel(for: persistedCell))
                        inspectorInfoRow("Evaluación", value: evaluationTitle(for: column))
                        inspectorInfoRow("Rúbrica", value: rubricTitle(for: column))

                        if isNotebookAICommentColumn(column) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(isNotebookIndividualSummaryColumn(column) ? "Síntesis pedagógica" : "Comentario IA")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                inspectorInfoRow(
                                    "Origen",
                                    value: isNotebookIndividualSummaryColumn(column)
                                        ? "Columna de síntesis pedagógica editable"
                                        : "Columna de comentario IA editable"
                                )
                                inspectorInfoRow("Regeneración", value: "Disponible desde este inspector o por lote")
                                Button(isNotebookIndividualSummaryColumn(column) ? "Regenerar síntesis pedagógica" : "Regenerar comentario IA") {
                                    if isNotebookIndividualSummaryColumn(column) {
                                        notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: column.id)
                                    } else {
                                        notebookAISheetRequest = NotebookAISheetRequest(
                                            mode: .selection,
                                            studentIds: [item.student.id],
                                            targetColumnId: column.id
                                        )
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Accesos rápidos")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))

                            HStack(spacing: 10) {
                                Button("Abrir alumno") {
                                    selectedStudentId = item.student.id
                                    isInspectorPresented = false
                                    inspectorSelection = nil
                                    onOpenModule(.students, currentClass?.id, item.student.id)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Ir a evaluación") {
                                    isInspectorPresented = false
                                    inspectorSelection = nil
                                    onOpenModule(.evaluationHub, currentClass?.id, item.student.id)
                                }
                                .buttonStyle(.bordered)
                                .disabled(column.evaluationId == nil)

                                Button("Ver rúbrica") {
                                    onOpenModule(
                                        column.categoryKind == .physicalEducation ? .peRubrics : .rubrics,
                                        currentClass?.id,
                                        item.student.id
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(column.rubricId == nil)
                            }

                            if column.categoryKind == .attendance {
                                Button("Abrir asistencia") {
                                    selectedStudentId = item.student.id
                                    isInspectorPresented = false
                                    inspectorSelection = nil
                                    onOpenModule(.attendance, currentClass?.id, item.student.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comentario y evidencia")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            TextEditor(text: $inspectorNoteDraft)
                                .frame(minHeight: 140)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(NotebookStyle.surface)
                                )

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Icono semántico")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                FlexibleTagRow(items: semanticInspectorIcons, selected: inspectorIconDraft) { icon in
                                    inspectorIconDraft = icon == inspectorIconDraft ? "" : icon
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Adjuntos")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    PhotosPicker(selection: $selectedAttachmentPhoto, matching: .images) {
                                        Label("Añadir foto", systemImage: "photo.badge.plus")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if inspectorAttachmentUris.isEmpty {
                                    Text("Sin adjuntos todavía")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(inspectorAttachmentUris, id: \.self) { uri in
                                        HStack(spacing: 8) {
                                            Image(systemName: "paperclip")
                                                .foregroundStyle(NotebookStyle.primaryTint)
                                            Text(URL(fileURLWithPath: uri).lastPathComponent)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .lineLimit(1)
                                            Spacer()
                                            Button {
                                                inspectorAttachmentUris.removeAll { $0 == uri }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(NotebookStyle.surface)
                                        )
                                    }
                                }
                            }

                            Button("Guardar contexto") {
                                bridge.saveNotebookCellAnnotation(
                                    studentId: item.student.id,
                                    columnId: column.id,
                                    note: inspectorNoteDraft,
                                    iconValue: inspectorIconDraft,
                                    attachmentUris: inspectorAttachmentUris
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(24)
                }
                .background(EvaluationBackdrop())
            } else {
                NotebookStateCard(
                    systemImage: "sidebar.right",
                    title: "Inspector contextual",
                    message: "Selecciona una celda para ver alumno, columna, comentario, evidencia y peso."
                )
            }
        }
    }

    private func seatingPlanContent(data: NotebookUiStateData, rows: [NotebookTableRow]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Plano de clase")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    highlightedRandomStudentId = randomEligibleStudentId(from: rows)
                } label: {
                    Label("Alumno aleatorio", systemImage: "dice")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    seatPositions = defaultSeatPositions(for: rows)
                    persistSeatPositions()
                } label: {
                    Label("Reordenar", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(NotebookStyle.surface.opacity(0.92))

            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    NotebookStyle.surfaceMuted.opacity(0.96),
                                    NotebookStyle.surface.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        .padding(18)

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        let position = resolvedSeatPosition(for: item.student.id, index: index, total: rows.count)
                        NotebookSeatCard(
                            student: item.student,
                            averageText: averageText(for: item),
                            attendanceText: attendanceStatusText(for: item.student.id),
                            incidentCount: incidentCountByStudentId[item.student.id] ?? 0,
                            isHighlighted: highlightedRandomStudentId == item.student.id,
                            isSelected: inspectorSelection?.studentId == item.student.id,
                            onTap: {
                                openInspectorForStudent(item.student.id, data: data)
                            },
                            onMarkPresent: {
                                Task { await markAttendance(for: item.student.id, status: "Presente") }
                            },
                            onMarkAbsent: {
                                Task { await markAttendance(for: item.student.id, status: "Ausente") }
                            },
                            onMarkLate: {
                                Task { await markAttendance(for: item.student.id, status: "Retraso") }
                            },
                            onFollowUp: {
                                Task { await createFollowUp(for: item.student) }
                            }
                        )
                        .frame(width: 166, height: 138)
                        .position(
                            x: max(96, min(proxy.size.width - 96, CGFloat(position.x) * proxy.size.width)),
                            y: max(86, min(proxy.size.height - 86, CGFloat(position.y) * proxy.size.height))
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let clampedX = min(max(value.location.x / max(proxy.size.width, 1), 0.12), 0.88)
                                    let clampedY = min(max(value.location.y / max(proxy.size.height, 1), 0.12), 0.88)
                                    seatPositions[item.student.id] = NotebookSeatPosition(x: clampedX, y: clampedY)
                                }
                                .onEnded { _ in
                                    persistSeatPositions()
                                }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    private var currentClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == bridge.notebookViewModel.currentClassId?.int64Value ?? 0 })
    }

    private var notebookSupportRefreshKey: String {
        "\(selectedClassId ?? -1)|\(bridge.selectedNotebookTabId ?? "all")"
    }

    private var semanticInspectorIcons: [String] {
        ["", "✅", "⭐", "⚠️", "🏠", "🧩", "📌", "💬"]
    }

    private var sortedClasses: [SchoolClass] {
        bridge.classes.sorted {
            if $0.course != $1.course { return $0.course < $1.course }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var activeClassLabel: String {
        guard let currentClass else { return "Seleccionar clase" }
        return classLabel(for: currentClass)
    }

    private func classLabel(for schoolClass: SchoolClass) -> String {
        "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private func headerContextLine(in data: NotebookUiStateData) -> String {
        let classText = activeClassLabel
        let groupText = selectedGroupId.flatMap { groupName(for: $0, in: data) } ?? "Grupo completo"
        let tabText = activeNotebookTab(data: data)?.title
        return [classText, tabText, groupText]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    private func orderedNotebookTabs(data: NotebookUiStateData) -> [NotebookTab] {
        let rootTabs = data.sheet.tabs.filter { $0.parentTabId == nil }
        let source = rootTabs.isEmpty ? data.sheet.tabs : rootTabs
        return source.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    private func activeNotebookTabId(data: NotebookUiStateData) -> String? {
        let tabs = orderedNotebookTabs(data: data)
        if let selected = bridge.selectedNotebookTabId,
           tabs.contains(where: { $0.id == selected }) {
            return selected
        }
        return tabs.first?.id
    }

    private func activeNotebookTab(data: NotebookUiStateData) -> NotebookTab? {
        guard let activeTabId = activeNotebookTabId(data: data) else { return nil }
        return data.sheet.tabs.first { $0.id == activeTabId }
    }

    private func ensureActiveNotebookTab(data: NotebookUiStateData) {
        guard let activeTabId = activeNotebookTabId(data: data) else {
            if bridge.selectedNotebookTabId != nil {
                bridge.setSelectedNotebookTab(id: nil)
            }
            return
        }
        if bridge.selectedNotebookTabId != activeTabId {
            bridge.setSelectedNotebookTab(id: activeTabId)
        }
    }

    private func selectNotebookTab(_ tabId: String) {
        selectedGroupId = nil
        inspectorSelection = nil
        isInspectorPresented = false
        highlightedRandomStudentId = nil
        bridge.setSelectedNotebookTab(id: tabId)
    }

    private func selectNotebookClass(_ classId: Int64) {
        guard bridge.notebookViewModel.currentClassId?.int64Value != classId else { return }
        selectedGroupId = nil
        isInspectorPresented = false
        inspectorSelection = nil
        inspectorNoteDraft = ""
        inspectorIconDraft = ""
        inspectorAttachmentUris = []
        highlightedRandomStudentId = nil
        searchText = ""
        selectedClassId = classId
        bridge.selectClass(id: classId)
    }

    private func syncToolbarState(data: NotebookUiStateData) {
        layoutState.configureNotebookToolbar(
            inspectorAvailable: inspectorSelection != nil || !managedColumns(data: data).isEmpty,
            isInspectorPresented: isInspectorPresented,
            addColumnAvailable: true,
            searchText: searchText,
            surfaceMode: surfaceMode.rawValue,
            selectedGroupId: selectedGroupId,
            availableGroups: groupedRows(data: data).map {
                NotebookToolbarGroupOption(id: $0.id, name: $0.name, studentCount: memberCount($0.id, in: data))
            },
            organizationMenuAvailable: true,
            onToggleInspector: {
                if inspectorSelection == nil {
                    openInspectorForSelection(data)
                }
                if inspectorSelection != nil {
                    isInspectorPresented.toggle()
                }
            },
            onAddColumn: {
                addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
            },
            onSearchChange: { value in
                searchText = value
            },
            onSurfaceModeChange: { value in
                surfaceMode = NotebookSurfaceMode(rawValue: value) ?? .grid
            },
            onGroupFilterChange: { value in
                selectedGroupId = value
            },
            onOpenOrganizationMenu: {
                isOrganizationMenuPresented = true
            }
        )
    }

    private func toolbarStateKey(data: NotebookUiStateData) -> String {
        let classKey = currentClass?.id ?? -1
        let groupKey = selectedGroupId ?? -1
        let inspectorKey = inspectorSelection?.id ?? "none"
        return "\(classKey)|\(groupKey)|\(surfaceMode.rawValue)|\(managedColumns(data: data).count)|\(filteredRows(data: data).count)|\(inspectorKey)|\(isInspectorPresented)"
    }

    private var notebookRiskRefreshKey: String {
        guard let data = bridge.notebookState as? NotebookUiStateData else {
            return "empty|\(selectedClassId ?? -1)"
        }
        let rows = filteredRows(data: data)
        return "\(selectedClassId ?? -1)|\(selectedGroupId ?? -1)|\(bridge.selectedNotebookTabId ?? "all")|\(rows.map { String($0.student.id) }.joined(separator: ","))"
    }

    @MainActor
    private func precomputeRiskLevelsForVisibleRows() async {
        guard !isPrecomputingRiskLevels,
              let classId = selectedClassId,
              let data = bridge.notebookState as? NotebookUiStateData
        else { return }
        let rows = filteredRows(data: data)
        guard !rows.isEmpty else {
            riskLevelCache = [:]
            riskComputationKey = nil
            return
        }
        let key = notebookRiskRefreshKey
        guard riskComputationKey != key else { return }
        riskComputationKey = key
        isPrecomputingRiskLevels = true
        defer { isPrecomputingRiskLevels = false }

        var nextCache = riskLevelCache.filter { cached in
            rows.contains { $0.student.id == cached.key }
        }

        for item in rows where nextCache[item.student.id] == nil {
            if Task.isCancelled { return }
            do {
                let profile = try await bridge.loadStudentProfile(studentId: item.student.id, classId: classId)
                nextCache[item.student.id] = StudentRiskEvidenceBuilder.classify(profile: profile)
                riskLevelCache = nextCache
            } catch {
                nextCache[item.student.id] = .seguimientoNormal
            }
            await Task.yield()
        }
        riskLevelCache = nextCache
    }

    private func openInspectorForSelection(_ data: NotebookUiStateData) {
        if inspectorSelection != nil { return }
        if let firstColumn = managedColumns(data: data).first,
           let firstRow = filteredRows(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: firstRow.student.id, columnId: firstColumn.id)
        }
    }

    private func openInspectorForStudent(_ studentId: Int64, data: NotebookUiStateData) {
        if let existingSelection = inspectorSelection,
           existingSelection.studentId == studentId,
           !existingSelection.columnId.isEmpty {
            inspectorSelection = existingSelection
        } else if let firstColumn = managedColumns(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: firstColumn.id)
        }
        isInspectorPresented = true
    }

    private func evaluationTitle(for column: NotebookColumnDefinition) -> String {
        guard let evaluationId = column.evaluationId?.int64Value else { return "Sin evaluación asociada" }
        if let schoolClass = currentClass,
           let evaluation = bridge.evaluationsInClass.first(where: { $0.id == evaluationId }),
           !bridge.evaluationsInClass.isEmpty {
            return "\(evaluation.name) · \(schoolClass.name)"
        }
        return "Evaluación #\(evaluationId)"
    }

    private func rubricTitle(for column: NotebookColumnDefinition) -> String {
        guard let rubricId = column.rubricId?.int64Value else { return "Sin rúbrica asociada" }
        return bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? "Rúbrica #\(rubricId)"
    }

    private func filteredRows(data: NotebookUiStateData) -> [NotebookTableRow] {
        let rows = data.sheet.groupedRowsFor(tabId: activeNotebookTabId(data: data)).flatMap { section in
            let groupName = section.group?.name ?? "Sin grupo"
            return section.rows.map { NotebookTableRow(student: $0.student, row: $0, groupName: groupName) }
        }

        return rows.filter { item in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || "\(item.student.firstName) \(item.student.lastName)".localizedCaseInsensitiveContains(searchText)
            let matchesGroup = selectedGroupId == nil || groupId(for: item.student.id, in: data) == selectedGroupId
            return matchesSearch && matchesGroup
        }
    }

    private func notebookRowView(
        item: NotebookTableRow,
        data: NotebookUiStateData,
        segments: [NotebookDisplaySegment],
        rowIndex: Int,
        allRows: [NotebookTableRow],
        navigableSegments: [NotebookDisplaySegment]
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(segments, id: \.id) { segment in
                rowCell(
                    for: segment,
                    item: item,
                    data: data,
                    allRows: allRows,
                    navigableSegments: navigableSegments
                )
            }
        }
        .frame(height: notebookGridRowHeight, alignment: .center)
        .padding(.horizontal, 16)
        .background(
            (rowIndex.isMultiple(of: 2) ? NotebookStyle.surfaceSoft.opacity(0.38) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            inspectorSelection?.studentId == item.student.id ? NotebookStyle.primaryTint.opacity(0.18) : .clear,
                            lineWidth: 1
                        )
                )
        )
    }

    private func groupedRows(data: NotebookUiStateData) -> [NotebookWorkGroup] {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroups
            .filter { activeTabId == nil || $0.tabId == activeTabId }
            .sorted { $0.order < $1.order }
    }

    private func groupId(for studentId: Int64, in data: NotebookUiStateData) -> Int64? {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroupMembers
            .first(where: { $0.studentId == studentId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .groupId
    }

    private func groupName(for groupId: Int64, in data: NotebookUiStateData) -> String? {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroups
            .first(where: { $0.id == groupId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .name
    }

    private func memberCount(_ groupId: Int64, in data: NotebookUiStateData) -> Int {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroupMembers
            .filter { $0.groupId == groupId && (activeTabId == nil || $0.tabId == activeTabId) }
            .count
    }

    private func columns(in category: NotebookColumnCategory, data: NotebookUiStateData, includeHidden: Bool = false) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { $0.categoryId == category.id }
            .filter { includeHidden || !$0.isHidden }
            .filter { columnMatchesActiveTab($0, data: data) }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }
    }

    private func managedColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { columnMatchesActiveTab($0, data: data) }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func relevantCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        visibleCategories(data: data)
            .filter { !columns(in: $0, data: data, includeHidden: true).isEmpty }
    }

    private func visibleCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.columnCategories
            .filter { activeTabId == nil || $0.tabId == activeTabId }
            .sorted { $0.order < $1.order }
    }

    private func displaySegments(data: NotebookUiStateData) -> [NotebookDisplaySegment] {
        var segments = fixedSegmentsForCurrentView().map(NotebookDisplaySegment.fixed)
        let categoriesById = Dictionary(
            data.sheet.columnCategories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedColumns = data.sheet.columns
            .filter { !$0.isHidden }
            .filter { columnMatchesActiveTab($0, data: data) }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }

        var emittedCollapsedCategories = Set<String>()
        for column in orderedColumns {
            guard let categoryId = column.categoryId, let category = categoriesById[categoryId] else {
                segments.append(.column(column))
                continue
            }
            if category.isCollapsed {
                if emittedCollapsedCategories.insert(category.id).inserted {
                    let categoryColumns = columns(in: category, data: data)
                    if !categoryColumns.isEmpty {
                        segments.append(.collapsedCategory(category, categoryColumns))
                    }
                }
            } else {
                segments.append(.column(column))
            }
        }
        return segments
    }

    private func notebookSourceColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        managedColumns(data: data)
    }

    private func visibleNotebookSourceColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        displaySegments(data: data).compactMap { segment in
            guard case .column(let column) = segment else { return nil }
            return column
        }
    }

    private func selectedNotebookAIStudentIds(in data: NotebookUiStateData) -> [Int64] {
        if let selectedStudentId {
            return [selectedStudentId]
        }
        if let inspectorSelection {
            return [inspectorSelection.studentId]
        }
        return filteredRows(data: data).map(\.student.id)
    }

    private func cellFocusId(studentId: Int64, columnId: String) -> String {
        "\(studentId)|\(columnId)"
    }

    private func presentFormulaEditor(for column: NotebookColumnDefinition) {
        formulaDraft = column.formula ?? ""
        formulaAIPrompt = ""
        formulaAIMessage = nil
        isFormulaAIGenerating = false
        focusedCellId = nil
        activeChoiceCellId = nil
        formulaEditRequest = NotebookFormulaEditRequest(columnId: column.id)
    }

    private func saveFormula(_ column: NotebookColumnDefinition) {
        let trimmed = formulaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        saveColumnMutation(
            column,
            formula: trimmed.isEmpty ? nil : trimmed,
            updatesFormula: true
        )
        formulaEditRequest = nil
        showToast(trimmed.isEmpty ? "Fórmula eliminada" : "Fórmula actualizada")
    }

    private func generateFormulaWithAI(column: NotebookColumnDefinition, data: NotebookUiStateData) {
        let prompt = formulaAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isFormulaAIGenerating = true
        formulaAIMessage = nil
        let columns = formulaReferenceColumns(for: column, data: data)
        let currentFormula = formulaDraft
        Task {
            do {
                let formula = try await formulaAIService.generateFormula(
                    request: prompt,
                    currentFormula: currentFormula,
                    availableColumns: columns
                )
                await MainActor.run {
                    formulaDraft = formula
                    formulaAIMessage = "Propuesta insertada. Revísala antes de guardar."
                    isFormulaAIGenerating = false
                }
            } catch {
                await MainActor.run {
                    formulaAIMessage = error.localizedDescription
                    isFormulaAIGenerating = false
                }
            }
        }
    }

    private func openRubricIndividual(column: NotebookColumnDefinition, item: NotebookTableRow) {
        guard let rubricId = column.rubricId?.int64Value,
              let evaluationId = column.evaluationId?.int64Value else {
            showToast("Esta columna no tiene una rúbrica asociada", style: .warning)
            return
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            focusedCellId = nil
            activeChoiceCellId = nil
            inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
        }
        DispatchQueue.main.async {
            bridge.loadForNotebookCell(
                studentId: item.student.id,
                columnId: column.id,
                rubricId: rubricId,
                evaluationId: evaluationId
            )
        }
    }

    private func openRubricBulk(column: NotebookColumnDefinition, data: NotebookUiStateData) {
        guard let evaluationId = column.evaluationId?.int64Value,
              let rubricId = column.rubricId?.int64Value else {
            showToast("Esta columna no tiene una rúbrica asociada", style: .warning)
            return
        }
        focusedCellId = nil
        activeChoiceCellId = nil
        bridge.startBulkRubricEvaluation(
            classId: data.sheet.classId,
            evaluationId: evaluationId,
            rubricId: rubricId,
            columnId: column.id,
            tabId: activeNotebookTabId(data: data)
        )
    }

    private func navigateFromFocused(direction: NotebookNavigationDirection, data: NotebookUiStateData) {
        let currentCellId = focusedCellId ?? activeChoiceCellId
        guard let currentCellId else { return }
        let parts = currentCellId.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let studentId = Int64(parts[0]),
              let column = data.sheet.columns.first(where: { $0.id == parts[1] }) else {
            return
        }
        navigateCell(
            from: studentId,
            column: column,
            direction: direction,
            rows: filteredRows(data: data),
            segments: displaySegments(data: data).filter { !isFixedSegment($0) }
        )
    }

    private func navigateCell(
        from studentId: Int64,
        column: NotebookColumnDefinition,
        direction: NotebookNavigationDirection,
        rows: [NotebookTableRow],
        segments: [NotebookDisplaySegment]
    ) {
        let navigableColumns = segments.compactMap { segment -> NotebookColumnDefinition? in
            guard case .column(let candidate) = segment else { return nil }
            return candidate
        }

        guard !rows.isEmpty,
              !navigableColumns.isEmpty,
              let currentRowIndex = rows.firstIndex(where: { $0.student.id == studentId }),
              let currentColumnIndex = navigableColumns.firstIndex(where: { $0.id == column.id }) else {
            return
        }

        var nextRowIndex = currentRowIndex
        var nextColumnIndex = currentColumnIndex
        switch direction {
        case .up:
            nextRowIndex = max(currentRowIndex - 1, 0)
        case .down:
            nextRowIndex = min(currentRowIndex + 1, rows.count - 1)
        case .left:
            nextColumnIndex = max(currentColumnIndex - 1, 0)
        case .right:
            nextColumnIndex = min(currentColumnIndex + 1, navigableColumns.count - 1)
        }

        let nextStudentId = rows[nextRowIndex].student.id
        let nextColumn = navigableColumns[nextColumnIndex]
        let nextCellId = cellFocusId(studentId: nextStudentId, columnId: nextColumn.id)

        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            inspectorSelection = NotebookInspectorSelection(studentId: nextStudentId, columnId: nextColumn.id)
            focusedCellId = nil
            activeChoiceCellId = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                if nextColumn.type == .ordinal || nextColumn.type == .attendance || nextColumn.categoryKind == .attendance {
                    activeChoiceCellId = nextCellId
                } else if nextColumn.type != .calculated && nextColumn.type != .rubric && nextColumn.type != .check {
                    focusedCellId = nextCellId
                }
            }
        }
    }

    private func isNotebookAICommentColumn(_ column: NotebookColumnDefinition) -> Bool {
        bridge.isNotebookAICommentColumn(column)
    }

    private func headerLaneItems(data: NotebookUiStateData, segments: [NotebookDisplaySegment]) -> [NotebookHeaderLaneItem] {
        var items: [NotebookHeaderLaneItem] = []
        let categoriesById = Dictionary(
            visibleCategories(data: data).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var emittedCategoryIds = Set<String>()

        for segment in segments {
            switch segment {
            case .fixed(let fixed):
                items.append(.spacer(id: "fixed_\(fixed.id)", width: fixed.width))
            case .collapsedCategory(let category, _):
                items.append(.spacer(id: "collapsed_\(category.id)", width: 150))
            case .column(let column):
                guard let categoryId = column.categoryId,
                      let category = categoriesById[categoryId],
                      !category.isCollapsed else {
                    items.append(.spacer(id: "column_\(column.id)", width: CGFloat(max(column.widthDp, 120))))
                    continue
                }
                guard emittedCategoryIds.insert(category.id).inserted else { continue }
                let categoryColumns = columns(in: category, data: data)
                let totalWidth = categoryColumns.reduce(CGFloat(0)) { partial, column in
                    partial + CGFloat(max(column.widthDp, 120))
                } + CGFloat(max(categoryColumns.count - 1, 0) * 12)
                items.append(.folder(category, categoryColumns, totalWidth))
            }
        }

        let emptyCategories = visibleCategories(data: data)
            .filter { columns(in: $0, data: data, includeHidden: true).isEmpty }
        for category in emptyCategories where emittedCategoryIds.insert(category.id).inserted {
            items.append(.folder(category, [], 168))
        }
        return items
    }

    private func fixedSegmentsForCurrentView() -> [NotebookFixedColumn] {
        switch viewPreset {
        case .all:
            return [.photo, .name, .group, .followUp, .attendance, .average]
        case .evaluation:
            return [.photo, .name, .average]
        case .followUp:
            return [.photo, .name, .group, .followUp]
        case .attendance:
            return [.photo, .name, .group, .attendance]
        case .extras:
            return [.photo, .name]
        case .physicalEducation:
            return [.photo, .name]
        }
    }

    private func columnMatchesCurrentView(_ column: NotebookColumnDefinition) -> Bool {
        switch viewPreset {
        case .all:
            return true
        case .evaluation:
            return column.categoryKind == .evaluation
        case .followUp:
            return column.categoryKind == .followUp
        case .attendance:
            return column.categoryKind == .attendance
        case .extras:
            return column.categoryKind == .extras
        case .physicalEducation:
            return column.categoryKind == .physicalEducation
        }
    }

    private func columnMatchesActiveTab(_ column: NotebookColumnDefinition, data: NotebookUiStateData) -> Bool {
        guard let activeTabId = activeNotebookTabId(data: data) else { return false }
        return column.tabIds.contains(activeTabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty)
    }

    private func toggleColumnVisibility(_ column: NotebookColumnDefinition) {
        bridge.saveColumn(column: NotebookColumnDefinition(
            id: column.id,
            title: column.title,
            type: column.type,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            evaluationId: column.evaluationId,
            rubricId: column.rubricId,
            formula: column.formula,
            weight: column.weight,
            dateEpochMs: column.dateEpochMs,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds,
            scaleKind: column.scaleKind,
            tabIds: column.tabIds,
            sessions: column.sessions,
            sharedAcrossTabs: column.sharedAcrossTabs,
            colorHex: column.colorHex,
            iconName: column.iconName,
            order: column.order,
            widthDp: column.widthDp,
            categoryId: column.categoryId,
            ordinalLevels: column.ordinalLevels,
            availableIcons: column.availableIcons,
            countsTowardAverage: column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: !column.isHidden,
            visibility: column.visibility,
            isLocked: column.isLocked,
            isTemplate: column.isTemplate,
            trace: column.trace
        ))
    }

    private func exportText(data: NotebookUiStateData) -> String {
        let segments = displaySegments(data: data)
        let header = segments.map(exportHeaderTitle(for:)).joined(separator: "\t")
        let columnLettersById = exportColumnLettersById(segments: segments)

        let body = filteredRows(data: data).enumerated().map { rowIndex, item in
            segments.map {
                exportValue(
                    for: $0,
                    item: item,
                    spreadsheetRowIndex: rowIndex + 2,
                    columnLettersById: columnLettersById
                )
            }
            .joined(separator: "\t")
        }

        return ([header] + body).joined(separator: "\n")
    }

    private func exportColumnLettersById(segments: [NotebookDisplaySegment]) -> [String: String] {
        var result: [String: String] = [:]
        for (index, segment) in segments.enumerated() {
            if case .column(let column) = segment {
                result[column.id] = spreadsheetColumnName(for: index + 1)
            }
        }
        return result
    }

    private func spreadsheetColumnName(for oneBasedIndex: Int) -> String {
        var index = max(oneBasedIndex, 1)
        var result = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            index = (index - 1) / 26
        }
        return result
    }

    private func exportHeaderTitle(for segment: NotebookDisplaySegment) -> String {
        switch segment {
        case .fixed(let fixed):
            return fixed.title
        case .column(let column):
            return column.title
        case .collapsedCategory(let category, _):
            return category.name
        }
    }

    private func exportValue(
        for segment: NotebookDisplaySegment,
        item: NotebookTableRow,
        spreadsheetRowIndex: Int,
        columnLettersById: [String: String]
    ) -> String {
        switch segment {
        case .fixed(let fixed):
            switch fixed {
            case .photo:
                return initials(for: item.student)
            case .name:
                return "\(item.student.firstName) \(item.student.lastName)"
            case .group:
                return item.groupName
            case .followUp:
                return item.student.isInjured ? "Atención" : "Normal"
            case .attendance:
                return attendanceSummary(for: item)
            case .average:
                return averageText(for: item)
            }
        case .column(let column):
            if column.type == .calculated,
               let formula = column.formula?.trimmingCharacters(in: .whitespacesAndNewlines),
               !formula.isEmpty {
                return spreadsheetFormula(
                    formula,
                    rowIndex: spreadsheetRowIndex,
                    columnLettersById: columnLettersById
                )
            }
            return displayValue(for: item, column: column)
        case .collapsedCategory(_, let columns):
            return "\(filledCellCount(item, columns: columns))/\(columns.count)"
        }
    }

    private func formulaDisplay(
        for item: NotebookTableRow,
        column: NotebookColumnDefinition,
        data: NotebookUiStateData
    ) -> NotebookFormulaCellDisplay? {
        guard column.type == .calculated else { return nil }
        let formula = column.formula?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !formula.isEmpty else {
            return NotebookFormulaCellDisplay(text: "Sin fórmula", isError: true)
        }

        do {
            let variables = formulaVariables(for: item, data: data)
            let value = try NotebookFormulaEvaluator.evaluate(formula, variables: variables)
            return NotebookFormulaCellDisplay(text: formatFormulaResult(value), isError: false)
        } catch {
            return NotebookFormulaCellDisplay(text: error.localizedDescription, isError: true)
        }
    }

    private func formulaVariables(for item: NotebookTableRow, data: NotebookUiStateData) -> [String: Double] {
        var variables: [String: Double] = [:]
        for column in data.sheet.columns where column.type != .calculated {
            let raw: String
            if column.type == .rubric {
                raw = bridge.rubricGradeText(studentId: item.student.id, column: column)
            } else {
                raw = bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
            }
            let value = parseFormulaNumber(raw) ?? 0
            variables[column.id] = value
            variables[NotebookFormulaEvaluator.safeIdentifier(for: column.id)] = value
        }
        return variables
    }

    private func parseFormulaNumber(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatFormulaResult(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func spreadsheetFormula(
        _ formula: String,
        rowIndex: Int,
        columnLettersById: [String: String]
    ) -> String {
        var output = formula.hasPrefix("=") ? formula : "=\(formula)"
        for (columnId, letter) in columnLettersById {
            output = output.replacingOccurrences(of: "[\(columnId)]", with: "\(letter)\(rowIndex)")
        }
        return output
    }

    private func categoryTitle(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> String {
        if let categoryId = column.categoryId,
           let category = data.sheet.columnCategories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        switch column.categoryKind {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .custom: return "Sin categoría"
        default: return "Sin categoría"
        }
    }

    private func columnHeaderSubtitle(
        for column: NotebookColumnDefinition,
        data: NotebookUiStateData,
        rows: [NotebookTableRow]
    ) -> String {
        var parts = [categoryTitle(for: column, data: data)]
        if let epochMs = column.dateEpochMs?.int64Value {
            let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000.0)
            parts.append(date.formatted(.dateTime.day().month(.abbreviated)))
        }
        if let average = columnAverageText(for: column, rows: rows) {
            parts.append(average)
        }
        return parts.joined(separator: " · ")
    }

    private func columnAverageText(for column: NotebookColumnDefinition, rows: [NotebookTableRow]) -> String? {
        guard column.type == .numeric || column.type == .rubric else { return nil }
        let values = rows.compactMap { item -> Double? in
            let raw = column.type == .rubric
                ? bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
                : bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
            return parseFormulaNumber(raw)
        }
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return String(format: "x̄ %.1f", average)
    }

    private func tint(for category: NotebookColumnCategory) -> Color {
        tint(forName: category.name)
    }

    private func tint(for column: NotebookColumnDefinition) -> Color {
        if let colorHex = column.colorHex {
            return Color(hex: colorHex)
        }
        switch column.categoryKind {
        case .evaluation: return NotebookStyle.primaryTint
        case .followUp: return NotebookStyle.successTint
        case .attendance: return NotebookStyle.warningTint
        case .extras: return .pink
        case .physicalEducation: return .orange
        case .custom: return .secondary
        default: return .secondary
        }
    }

    private func tint(forName name: String) -> Color {
        if name.localizedCaseInsensitiveContains("evalu") { return NotebookStyle.primaryTint }
        if name.localizedCaseInsensitiveContains("segu") { return NotebookStyle.successTint }
        if name.localizedCaseInsensitiveContains("asist") { return NotebookStyle.warningTint }
        if name.localizedCaseInsensitiveContains("extra") { return .pink }
        if name.localizedCaseInsensitiveContains("ef") { return .orange }
        return .secondary
    }

    private func studentAvatar(for student: Student) -> some View {
        ZStack {
            Circle()
                .fill(NotebookStyle.primaryTint.opacity(0.15))
            Text(initials(for: student))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NotebookStyle.primaryTint)
        }
        .frame(width: 36, height: 36)
    }

    private func initials(for student: Student) -> String {
        String(student.firstName.prefix(1)) + String(student.lastName.prefix(1))
    }

    private func followUpBadge(for student: Student) -> some View {
        Text(student.isInjured ? "Atención" : "Normal")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(student.isInjured ? .orange : NotebookStyle.successTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill((student.isInjured ? Color.orange : NotebookStyle.successTint).opacity(0.12))
            )
    }

    private func attendanceSummary(for item: NotebookTableRow) -> String {
        if let status = todayAttendanceByStudentId[item.student.id], !status.isEmpty {
            return status
        }
        let attendanceColumns = item.row.persistedCells.filter { $0.columnId.localizedCaseInsensitiveContains("attendance") || $0.columnId.localizedCaseInsensitiveContains("asist") }
        if attendanceColumns.isEmpty { return "Sin datos" }
        let present = attendanceColumns.filter { ($0.textValue ?? "").localizedCaseInsensitiveContains("pres") }.count
        return "\(present)/\(attendanceColumns.count)"
    }

    private func averageText(for item: NotebookTableRow) -> String {
        guard let weightedAverage = item.row.weightedAverage else { return "Sin media" }
        return IosFormatting.decimal(from: weightedAverage)
    }

    private func filledCellCount(_ item: NotebookTableRow, columns: [NotebookColumnDefinition]) -> Int {
        columns.filter { !displayValue(for: item, column: $0).isEmpty }.count
    }

    private func displayValue(for item: NotebookTableRow, column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric, .calculated:
            return bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        case .rubric:
            return bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
        case .check:
            return bridge.cellCheck(studentId: item.student.id, columnId: column.id) ? "Sí" : ""
        default:
            return bridge.cellText(studentId: item.student.id, columnId: column.id)
        }
    }

    private func evidenceLabel(for persistedCell: PersistedNotebookCell?) -> String {
        let count = persistedCell?.annotation?.attachmentUris.count ?? 0
        let icon = persistedCell?.annotation?.icon ?? persistedCell?.iconValue ?? ""
        if count == 0 && icon.isEmpty { return "Sin evidencia" }
        if count == 0 { return "Icono \(icon)" }
        return icon.isEmpty ? "\(count) archivo(s)" : "\(count) archivo(s) · \(icon)"
    }

    private func formattedDate(_ epochMs: Int64?) -> String {
        guard let epochMs else { return "Sin fecha" }
        return Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    private func syncInspectorDraft() {
        guard let selection = inspectorSelection,
              let data = bridge.notebookState as? NotebookUiStateData,
              let item = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }) else {
            inspectorNoteDraft = ""
            inspectorIconDraft = ""
            inspectorAttachmentUris = []
            return
        }
        let persisted = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })
        inspectorNoteDraft = persisted?.annotation?.note ?? ""
        inspectorIconDraft = persisted?.annotation?.icon ?? persisted?.iconValue ?? ""
        inspectorAttachmentUris = persisted?.annotation?.attachmentUris ?? []
    }

    private func refreshNotebookSignals() async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        do {
            let attendance = try await bridge.attendanceRecords(for: classId, on: Date())
            await MainActor.run {
                todayAttendanceByStudentId = Dictionary(
                    attendance.map { ($0.studentId, $0.status) },
                    uniquingKeysWith: { _, latest in latest }
                )
            }
        } catch {
            await MainActor.run { todayAttendanceByStudentId = [:] }
        }

        do {
            let incidents = try await bridge.incidents(for: classId)
            let counts = Dictionary(grouping: incidents.compactMap { $0.studentId?.int64Value }, by: { $0 }).mapValues(\.count)
            await MainActor.run {
                incidentCountByStudentId = counts
            }
        } catch {
            await MainActor.run { incidentCountByStudentId = [:] }
        }
    }

    private func attendanceStatusText(for studentId: Int64) -> String {
        todayAttendanceByStudentId[studentId] ?? "Sin pasar"
    }

    private func markAttendance(for studentId: Int64, status: String) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        do {
            try await bridge.saveAttendance(studentId: studentId, classId: classId, on: Date(), status: status)
            await refreshNotebookSignals()
        } catch {
        }
    }

    private func requestMarkAllVisibleStudentsPresent(data: NotebookUiStateData) {
        let visibleRows = filteredRows(data: data)
        guard !visibleRows.isEmpty else { return }
        if visibleRows.count > 5 {
            isMarkAllPresentDialogPresented = true
        } else {
            markAllVisibleStudentsPresent(data: data)
        }
    }

    private func markAllVisibleStudentsPresent(data: NotebookUiStateData) {
        let visibleRows = filteredRows(data: data)
        guard !visibleRows.isEmpty else { return }
        Task {
            for row in visibleRows {
                await markAttendance(for: row.student.id, status: "PRESENTE")
            }
            await MainActor.run {
                showToast("\(visibleRows.count) alumnos marcados como presentes")
            }
        }
    }

    private func recordCellUndo(studentId: Int64, column: NotebookColumnDefinition, previousValue: String, previousDisplayLabel: String?) {
        undoStack.append(
            NotebookCellUndoEntry(
                studentId: studentId,
                column: column,
                previousValue: previousValue,
                previousDisplayLabel: previousDisplayLabel
            )
        )
        if undoStack.count > 10 {
            undoStack.removeFirst(undoStack.count - 10)
        }
    }

    private func undoLastCellChange() {
        guard let entry = undoStack.popLast() else {
            showToast("No hay cambios que deshacer", style: .warning)
            return
        }
        bridge.flushPendingColumnGradeSave(studentId: entry.studentId, columnId: entry.column.id)
        bridge.saveColumnGrade(studentId: entry.studentId, column: entry.column, value: entry.previousValue)
        cellReloadRevision += 1
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            inspectorSelection = NotebookInspectorSelection(studentId: entry.studentId, columnId: entry.column.id)
            focusedCellId = nil
            activeChoiceCellId = nil
        }
        let label = entry.previousDisplayLabel ?? entry.previousValue
        showToast(label.isEmpty ? "Cambio deshecho" : "Cambio deshecho: \(label)")
    }

    private func createFollowUp(for student: Student) async {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return }
        do {
            _ = try await bridge.createIncident(
                classId: classId,
                studentId: student.id,
                title: "Seguimiento desde plano",
                detail: "Marcado desde el plano de clase del cuaderno."
            )
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: classId,
                on: Date(),
                status: todayAttendanceByStudentId[student.id] ?? "Presente",
                note: "Seguimiento abierto desde el plano.",
                hasIncident: true
            )
            await refreshNotebookSignals()
        } catch {
        }
    }

    private func importSelectedAttachment(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value,
              let selection = inspectorSelection else { return }

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotebookEvidence", isDirectory: true)
            .appendingPathComponent("\(classId)", isDirectory: true)
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(selection.studentId)_\(selection.columnId)_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            await MainActor.run {
                inspectorAttachmentUris.append(url.path)
                selectedAttachmentPhoto = nil
            }
        } catch {
            await MainActor.run {
                selectedAttachmentPhoto = nil
            }
        }
    }

    private func defaultSeatPositions(for rows: [NotebookTableRow]) -> [Int64: NotebookSeatPosition] {
        guard !rows.isEmpty else { return [:] }
        let columns = max(3, Int(ceil(sqrt(Double(rows.count)))))
        let horizontalStep = 0.76 / Double(max(columns - 1, 1))
        let verticalRows = Int(ceil(Double(rows.count) / Double(columns)))
        let verticalStep = 0.68 / Double(max(verticalRows - 1, 1))
        return Dictionary(uniqueKeysWithValues: rows.enumerated().map { index, item in
            let row = index / columns
            let column = index % columns
            let x = 0.12 + Double(column) * horizontalStep
            let y = 0.16 + Double(row) * verticalStep
            return (item.student.id, NotebookSeatPosition(x: x, y: y))
        })
    }

    private func resolvedSeatPosition(for studentId: Int64, index: Int, total: Int) -> NotebookSeatPosition {
        if let existing = seatPositions[studentId] {
            return existing
        }
        let columns = max(3, Int(ceil(sqrt(Double(max(total, 1))))))
        let row = index / columns
        let column = index % columns
        let horizontalStep = 0.76 / Double(max(columns - 1, 1))
        let verticalRows = Int(ceil(Double(max(total, 1)) / Double(columns)))
        let verticalStep = 0.68 / Double(max(verticalRows - 1, 1))
        return NotebookSeatPosition(
            x: 0.12 + Double(column) * horizontalStep,
            y: 0.16 + Double(row) * verticalStep
        )
    }

    private func randomEligibleStudentId(from rows: [NotebookTableRow]) -> Int64? {
        let eligible = rows
            .map(\.student.id)
            .filter { !attendanceStatusText(for: $0).localizedCaseInsensitiveContains("aus") }
        return (eligible.isEmpty ? rows.map(\.student.id) : eligible).randomElement()
    }

    private func seatStorageKey() -> String? {
        guard let classId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value else { return nil }
        return "notebook.seating.\(classId).\(bridge.selectedNotebookTabId ?? "all")"
    }

    private func persistSeatPositions() {
        guard let key = seatStorageKey(),
              let encoded = try? JSONEncoder().encode(seatPositions) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    private func restoreSeatPositions() {
        guard let key = seatStorageKey() else {
            seatPositions = [:]
            return
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Int64: NotebookSeatPosition].self, from: data) {
            seatPositions = decoded
        } else if let data = bridge.notebookState as? NotebookUiStateData {
            seatPositions = defaultSeatPositions(for: filteredRows(data: data))
        } else {
            seatPositions = [:]
        }
    }

    private func headerChip(title: String, subtitle: String, width: CGFloat, tint: Color, folderStyle: Bool = false, isHighlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(folderStyle ? 0.8 : 0.5))
                    .frame(width: 6, height: 6)

                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: width)
        .frame(minHeight: 52, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(folderStyle ? NotebookStyle.surfaceSoft.opacity(0.55) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isHighlighted ? tint.opacity(0.32) : (folderStyle ? NotebookStyle.softBorder : Color.clear),
                            lineWidth: isHighlighted ? 1.5 : 1
                        )
                )
        )
    }

    private func headerChip(for segment: NotebookDisplaySegment, data: NotebookUiStateData) -> some View {
        let visibleRows = filteredRows(data: data)
        switch segment {
        case .fixed(let fixed):
            return AnyView(
                headerChip(
                    title: fixed.title,
                    subtitle: fixed.subtitle,
                    width: resolvedFixedWidth(for: fixed),
                    tint: tint(for: fixed)
                )
            )
        case .column(let column):
            return AnyView(
                NotebookResizableHeader(
                    width: resolvedColumnWidth(for: column),
                    minWidth: 80,
                    maxWidth: 400
                ) { newWidth in
                    columnWidths[column.id] = newWidth
                } content: {
                    headerChip(
                        title: column.title,
                        subtitle: columnHeaderSubtitle(for: column, data: data, rows: visibleRows),
                        width: resolvedColumnWidth(for: column),
                        tint: tint(for: column),
                        folderStyle: column.categoryId != nil,
                        isHighlighted: highlightedCategoryId == column.categoryId
                    )
                }
                .contextMenu {
                    columnContextMenu(column, data: data)
                }
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                headerChip(
                    title: category.name,
                    subtitle: "\(filledCollapsedCategoryCount(columns)) / \(columns.count) completas",
                    width: 150,
                    tint: tint(for: category),
                    folderStyle: true,
                    isHighlighted: highlightedCategoryId == category.id
                )
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
            )
        }
    }

    private func tint(for fixed: NotebookFixedColumn) -> Color {
        switch fixed {
        case .photo, .name, .group:
            return .secondary
        case .followUp:
            return NotebookStyle.successTint
        case .attendance:
            return NotebookStyle.warningTint
        case .average:
            return NotebookStyle.primaryTint
        }
    }

    private func rowCell(
        for segment: NotebookDisplaySegment,
        item: NotebookTableRow,
        data: NotebookUiStateData,
        allRows: [NotebookTableRow],
        navigableSegments: [NotebookDisplaySegment]
    ) -> some View {
        switch segment {
        case .fixed(let fixed):
            return AnyView(fixedRowCell(for: fixed, item: item, data: data))
        case .column(let column):
            return AnyView(
                NotebookEditableTableCell(
                    bridge: bridge,
                    item: item,
                    column: column,
                    classId: data.sheet.classId,
                    width: resolvedColumnWidth(for: column),
                    tint: tint(for: column),
                    categoryTint: column.categoryId.flatMap { id in
                        data.sheet.columnCategories.first(where: { $0.id == id }).map { tint(for: $0) }
                    },
                    focusedCellId: $focusedCellId,
                    activeChoiceCellId: $activeChoiceCellId,
                    navigationDirection: navigationDirection,
                    formulaDisplay: formulaDisplay(for: item, column: column, data: data),
                    isSelected: inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id),
                    isAttendanceQuickMode: isAttendanceQuickMode,
                    reloadToken: cellReloadRevision,
                    onSelect: {
                        inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                    },
                    onPrepareUndo: { previousValue, previousDisplayLabel in
                        recordCellUndo(
                            studentId: item.student.id,
                            column: column,
                            previousValue: previousValue,
                            previousDisplayLabel: previousDisplayLabel
                        )
                    },
                    onOpenFormula: {
                        presentFormulaEditor(for: column)
                    },
                    onOpenRubricIndividual: {
                        openRubricIndividual(column: column, item: item)
                    },
                    onOpenRubricBulk: {
                        openRubricBulk(column: column, data: data)
                    },
                    onNavigate: { direction in
                        navigateCell(
                            from: item.student.id,
                            column: column,
                            direction: direction,
                            rows: allRows,
                            segments: navigableSegments
                        )
                    },
                    onAttendanceSaved: {
                        Task { await refreshNotebookSignals() }
                    }
                )
                .frame(width: resolvedColumnWidth(for: column))
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                Button {
                    bridge.toggleColumnCategory(id: category.id, collapsed: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("\(filledCellCount(item, columns: columns)) / \(columns.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint(for: category).opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
            )
        }
    }

    private func categoryFolderHeader(category: NotebookColumnCategory, columns: [NotebookColumnDefinition], width: CGFloat) -> some View {
        let categoryTint = tint(for: category)
        let completed = filledCollapsedCategoryCount(columns)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: category.isCollapsed ? "folder.fill" : "folder.fill.badge.minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(categoryTint)
                    Text(category.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(columns.count)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(categoryTint)
                }

                Text(columns.isEmpty ? "Carpeta vacía lista para nuevas columnas" : "\(completed)/\(columns.count) completas")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(spacing: 6) {
                Button {
                    openAddColumn(in: category)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)

                Menu {
                    categoryContextMenu(category, data: bridge.notebookState as? NotebookUiStateData)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(categoryTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.030))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(categoryTint.opacity(highlightedCategoryId == category.id ? 0.48 : 0.20), lineWidth: highlightedCategoryId == category.id ? 1.5 : 1)
                )
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(categoryTint.opacity(0.72))
                        .frame(width: min(108, width * 0.48), height: 4)
                        .offset(x: 12, y: 8)
                }
        )
        .contextMenu {
            categoryContextMenu(category, data: bridge.notebookState as? NotebookUiStateData)
        }
    }

    @ViewBuilder
    private func columnContextMenu(_ column: NotebookColumnDefinition, data: NotebookUiStateData) -> some View {
        if isNotebookIndividualSummaryColumn(column) {
            Button(summaryActionTitle(for: column, data: data)) {
                notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: column.id)
            }
        }
        if column.type == .calculated {
            Button("Editar fórmula…") {
                presentFormulaEditor(for: column)
            }
        }
        if column.type == .rubric {
            Button("Evaluar alumno…") {
                let targetRow = inspectorSelection
                    .flatMap { selection in filteredRows(data: data).first { $0.student.id == selection.studentId } }
                    ?? filteredRows(data: data).first
                if let targetRow {
                    openRubricIndividual(column: column, item: targetRow)
                } else {
                    showToast("No hay alumnos disponibles para evaluar", style: .warning)
                }
            }
            Button("Evaluar grupo…") {
                openRubricBulk(column: column, data: data)
            }
        }
        Button("Renombrar") {
            editingColumnId = column.id
            columnDraft = column.title
            isRenameColumnAlertPresented = true
        }
        Menu("Mover a categoría") {
            Button("Sin categoría") {
                bridge.assignColumn(column.id, toCategory: nil)
                showToast("Columna movida fuera de la carpeta")
            }
            ForEach(visibleCategories(data: data), id: \.id) { category in
                Button(category.name) {
                    bridge.assignColumn(column.id, toCategory: category.id)
                    highlightedCategoryId = category.id
                    showToast("Columna movida a \(category.name)")
                }
            }
        }
        Menu("Cambiar color") {
            ForEach(columnColorOptions, id: \.hex) { option in
                Button(option.label) {
                    saveColumnMutation(column, colorHex: option.hex)
                    showToast("Color actualizado")
                }
            }
        }
        Button(column.isHidden ? "Mostrar" : "Ocultar") {
            toggleColumnVisibility(column)
            showToast(column.isHidden ? "Columna visible" : "Columna oculta")
        }
        Button("Eliminar columna", role: .destructive) {
            pendingDeleteColumn = column
        }
    }

    private func summaryActionTitle(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> String {
        let hasExistingText = filteredRows(data: data).contains { row in
            !bridge.cellText(studentId: row.student.id, columnId: column.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        return hasExistingText ? "Regenerar síntesis…" : "Generar síntesis…"
    }

    @ViewBuilder
    private func categoryContextMenu(_ category: NotebookColumnCategory, data: NotebookUiStateData?) -> some View {
        Button("Renombrar categoría") {
            editingCategoryId = category.id
            categoryDraft = category.name
            isCreateCategoryAlertPresented = true
        }
        Button(category.isCollapsed ? "Expandir" : "Colapsar") {
            bridge.toggleColumnCategory(id: category.id, collapsed: !category.isCollapsed)
        }
        Button("Nueva columna dentro") {
            openAddColumn(in: category)
        }
        if let data {
            Menu("Mover columnas a") {
                ForEach(visibleCategories(data: data).filter { $0.id != category.id }, id: \.id) { target in
                    Button(target.name) {
                        columns(in: category, data: data, includeHidden: true).forEach { column in
                            bridge.assignColumn(column.id, toCategory: target.id)
                        }
                        highlightedCategoryId = target.id
                        showToast("Columnas movidas a \(target.name)")
                    }
                }
                Button("Sin categoría") {
                    columns(in: category, data: data, includeHidden: true).forEach { column in
                        bridge.assignColumn(column.id, toCategory: nil)
                    }
                    showToast("Columnas liberadas de la carpeta")
                }
            }
        }
        Button("Eliminar categoría", role: .destructive) {
            pendingDeleteCategory = category
        }
    }

    private func notebookOrganizationSheet(data: NotebookUiStateData?) -> some View {
        NavigationStack {
            List {
                Section("Organización") {
                    Button {
                        isOrganizationMenuPresented = false
                        presentCreateCategory()
                    } label: {
                        Label("Nueva categoría", systemImage: "folder.badge.plus")
                    }

                    if let data {
                        ForEach(managedColumns(data: data), id: \.id) { column in
                            Button {
                                toggleColumnVisibility(column)
                            } label: {
                                HStack {
                                    Label(column.title, systemImage: column.isHidden ? "eye.slash" : "eye")
                                    Spacer()
                                    Text(column.isHidden ? "Oculta" : "Visible")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Vista") {
                    ForEach(NotebookViewPreset.allCases) { preset in
                        Button {
                            viewPreset = preset
                        } label: {
                            HStack {
                                Text(preset.title)
                                Spacer()
                                if viewPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(NotebookStyle.primaryTint)
                                }
                            }
                        }
                    }
                }

                if let data, !relevantCategories(data: data).isEmpty {
                    Section("Categorías") {
                        ForEach(relevantCategories(data: data), id: \.id) { category in
                            Button(category.isCollapsed ? "Mostrar \(category.name)" : "Plegar \(category.name)") {
                                bridge.toggleColumnCategory(id: category.id, collapsed: !category.isCollapsed)
                            }
                        }
                    }
                }

                if let data {
                    Section("IA y exportación") {
                        Button {
                            addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
                        } label: {
                            Label("Crear síntesis pedagógica", systemImage: "plus.bubble")
                        }

                        Button {
                            notebookSummarySheetRequest = NotebookSummarySheetRequest(
                                targetColumnId: inspectorSelection.flatMap { selection in
                                    data.sheet.columns.first(where: { $0.id == selection.columnId && isNotebookIndividualSummaryColumn($0) })?.id
                                }
                            )
                        } label: {
                            Label("Generar síntesis pedagógica", systemImage: "apple.intelligence")
                        }
                        .disabled(data.sheet.columns.filter(isNotebookIndividualSummaryColumn).isEmpty)

                        ShareLink(item: exportText(data: data)) {
                            Label("Exportar cuaderno", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Columnas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        isOrganizationMenuPresented = false
                    }
                }
            }
        }
    }

    private func presentCreateCategory() {
        editingCategoryId = nil
        categoryDraft = defaultCategoryDraft()
        isCreateCategoryAlertPresented = true
    }

    private func openAddColumn(in category: NotebookColumnCategory) {
        highlightedCategoryId = category.id
        addColumnContext = NotebookAddColumnContext(categoryId: category.id, startsCreatingCategory: false)
    }

    private func presentCreateNotebookTab() {
        editingNotebookTabId = nil
        notebookTabDraft = defaultNotebookTabDraft()
        isNotebookTabAlertPresented = true
    }

    private func presentRenameNotebookTab(_ tab: NotebookTab) {
        editingNotebookTabId = tab.id
        notebookTabDraft = tab.title
        isNotebookTabAlertPresented = true
    }

    private func defaultNotebookTabDraft() -> String {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return "Nuevo tema" }
        let nextIndex = orderedNotebookTabs(data: data).count + 1
        return "Tema \(nextIndex)"
    }

    private func resetNotebookTabDraft() {
        editingNotebookTabId = nil
        notebookTabDraft = ""
    }

    private func saveNotebookTabDraft() {
        let draft = notebookTabDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }

        if let editingNotebookTabId,
           let data = bridge.notebookState as? NotebookUiStateData,
           let tab = data.sheet.tabs.first(where: { $0.id == editingNotebookTabId }) {
            bridge.saveTab(tab: NotebookTab(
                id: tab.id,
                title: draft,
                description: tab.description,
                order: tab.order,
                parentTabId: tab.parentTabId,
                trace: tab.trace
            ))
            showToast("Pestaña renombrada")
        } else if let createdId = bridge.createTab(title: draft) {
            selectNotebookTab(createdId)
            showToast("Pestaña creada")
        }

        resetNotebookTabDraft()
    }

    private func deleteNotebookTab(_ tab: NotebookTab) {
        let nextTabId: String? = {
            guard let data = bridge.notebookState as? NotebookUiStateData else { return nil }
            let remainingTabs = orderedNotebookTabs(data: data).filter { $0.id != tab.id }
            if let selectedIndex = orderedNotebookTabs(data: data).firstIndex(where: { $0.id == tab.id }),
               remainingTabs.indices.contains(selectedIndex) {
                return remainingTabs[selectedIndex].id
            }
            return remainingTabs.last?.id
        }()

        bridge.deleteTab(id: tab.id)
        bridge.setSelectedNotebookTab(id: nextTabId)
        pendingDeleteNotebookTab = nil
        showToast("Pestaña eliminada", style: .warning)
    }

    private func saveCategoryFromDraft() {
        let draft = categoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        bridge.saveColumnCategory(name: draft, categoryId: editingCategoryId)
        highlightedCategoryId = editingCategoryId
        showToast(editingCategoryId == nil ? "Categoría creada" : "Categoría renombrada")
        editingCategoryId = nil
        categoryDraft = ""
    }

    private func saveColumnRename() {
        guard let editingColumnId,
              let data = bridge.notebookState as? NotebookUiStateData,
              let column = data.sheet.columns.first(where: { $0.id == editingColumnId }) else {
            self.editingColumnId = nil
            columnDraft = ""
            return
        }
        saveColumnMutation(column, title: columnDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        showToast("Columna renombrada")
        self.editingColumnId = nil
        columnDraft = ""
    }

    private func saveColumnMutation(
        _ column: NotebookColumnDefinition,
        title: String? = nil,
        colorHex: String? = nil,
        formula: String? = nil,
        updatesFormula: Bool = false
    ) {
        let nextTitle = (title?.isEmpty == false ? title! : column.title)
        bridge.saveColumn(column: NotebookColumnDefinition(
            id: column.id,
            title: nextTitle,
            type: column.type,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            evaluationId: column.evaluationId,
            rubricId: column.rubricId,
            formula: updatesFormula ? formula : column.formula,
            weight: column.weight,
            dateEpochMs: column.dateEpochMs,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds,
            scaleKind: column.scaleKind,
            tabIds: column.tabIds,
            sessions: column.sessions,
            sharedAcrossTabs: column.sharedAcrossTabs,
            colorHex: colorHex ?? column.colorHex,
            iconName: column.iconName,
            order: column.order,
            widthDp: column.widthDp,
            categoryId: column.categoryId,
            ordinalLevels: column.ordinalLevels,
            availableIcons: column.availableIcons,
            countsTowardAverage: column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: column.isHidden,
            visibility: column.visibility,
            isLocked: column.isLocked,
            isTemplate: column.isTemplate,
            trace: column.trace
        ))
    }

    private func deleteColumn(_ column: NotebookColumnDefinition) {
        bridge.deleteColumn(id: column.id, evaluationId: column.evaluationId?.int64Value)
        showToast("Columna eliminada", style: .warning)
        pendingDeleteColumn = nil
    }

    private func deleteCategoryMessage(for category: NotebookColumnCategory, data: NotebookUiStateData?) -> String {
        guard let data else { return "Puedes conservar las columnas o eliminarlas junto con la categoría." }
        let categoryColumns = columns(in: category, data: data, includeHidden: true)
        let hasProtectedColumns = categoryColumns.contains { $0.isLocked || $0.type == .rubric || $0.evaluationId != nil }
        if hasProtectedColumns {
            return "Esta carpeta contiene columnas bloqueadas o vinculadas a evaluación. La opción segura conserva las columnas fuera de la carpeta."
        }
        return "Puedes conservar las columnas o eliminarlas junto con la categoría."
    }

    private func showToast(_ message: String, style: NotebookToastStyle = .success) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            toast = NotebookToast(message: message, style: style)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast?.message == message {
                withAnimation(.easeOut(duration: 0.2)) {
                    toast = nil
                }
            }
        }
    }

    private func notebookToastView(_ toast: NotebookToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(NotebookStyle.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(toast.style.tint.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
    }

    private func defaultCategoryDraft() -> String {
        switch viewPreset {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .all: return "Nueva categoría"
        }
    }

    private func filledCollapsedCategoryCount(_ columns: [NotebookColumnDefinition]) -> Int {
        columns.reduce(0) { partial, column in
            partial + (column.isHidden ? 0 : 1)
        }
    }

    private var columnColorOptions: [(label: String, hex: String)] {
        [
            ("Azul", "#4A90D9"),
            ("Verde", "#2E9B6F"),
            ("Ámbar", "#D28C1D"),
            ("Coral", "#D95C5C"),
            ("Violeta", "#7B6FF1"),
            ("Grafito", "#6B7280"),
        ]
    }

    private func fixedRowCell(for fixed: NotebookFixedColumn, item: NotebookTableRow, data: NotebookUiStateData) -> some View {
        Group {
            switch fixed {
            case .photo:
                studentAvatar(for: item.student)
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .center)
            case .name:
                Button {
                    openInspectorForStudent(item.student.id, data: data)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(item.student.firstName) \(item.student.lastName)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            riskBadge(for: item.student.id)
                        }
                        if item.student.isInjured {
                            Text("Seguimiento físico")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .group:
                Text(item.groupName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
            case .followUp:
                followUpBadge(for: item.student)
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
            case .attendance:
                Text(attendanceSummary(for: item))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
            case .average:
                Text(averageText(for: item))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func riskBadge(for studentId: Int64) -> some View {
        switch riskLevelCache[studentId] {
        case .atencionPrioritaria:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .help("Atención prioritaria")
        case .atencionPuntual:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2.weight(.bold))
                .foregroundStyle(NotebookStyle.warningTint)
                .help("Atención puntual")
        case .seguimientoNormal, .none:
            EmptyView()
        }
    }

    private func inspectorInfoRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "Sin valor" : value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }
}

private struct NotebookNavigationSubtitleModifier: ViewModifier {
    let subtitle: String

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

private struct NotebookKeyboardNavigationModifier: ViewModifier {
    let onNext: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .focusable()
                .onKeyPress(.return) {
                    onNext()
                    return .handled
                }
                .onKeyPress(.tab) {
                    onNext()
                    return .handled
                }
        } else {
            content
        }
    }
}

private extension View {
    func notebookNavigationSubtitle(_ subtitle: String) -> some View {
        modifier(NotebookNavigationSubtitleModifier(subtitle: subtitle))
    }

    func notebookKeyboardNavigation(onNext: @escaping () -> Void) -> some View {
        modifier(NotebookKeyboardNavigationModifier(onNext: onNext))
    }
}

private enum NotebookFormulaError: LocalizedError {
    case incompleteExpression
    case unexpectedToken(String)
    case unbalancedParentheses
    case unknownVariable(String)
    case unknownFunction(String)
    case invalidArguments(String)
    case divisionByZero

    var errorDescription: String? {
        switch self {
        case .incompleteExpression:
            return "Fórmula incompleta"
        case .unexpectedToken(let token):
            return "Token inesperado: \(token)"
        case .unbalancedParentheses:
            return "Paréntesis desbalanceados"
        case .unknownVariable(let name):
            return "Columna no encontrada: \(name)"
        case .unknownFunction(let name):
            return "Función no soportada: \(name)"
        case .invalidArguments(let message):
            return message
        case .divisionByZero:
            return "División por cero"
        }
    }
}

private enum NotebookFormulaEvaluator {
    static func safeIdentifier(for raw: String) -> String {
        let mapped = raw.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        let identifier = String(mapped)
        if identifier.first?.isNumber == true {
            return "_\(identifier)"
        }
        return identifier
    }

    static func evaluate(_ expression: String, variables: [String: Double]) throws -> Double {
        let normalized = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "=" })
        var parser = Parser(tokens: tokenize(String(normalized)), variables: variables)
        return try parser.parseExpression()
    }

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character.isWhitespace {
                flush()
            } else if character == "[" {
                flush()
                let nextIndex = input.index(after: index)
                if let end = input[nextIndex...].firstIndex(of: "]") {
                    let columnId = String(input[nextIndex..<end])
                    tokens.append(columnId)
                    index = end
                } else {
                    tokens.append(String(character))
                }
            } else if "+-*/(),<>".contains(character) {
                flush()
                let nextIndex = input.index(after: index)
                if nextIndex < input.endIndex {
                    let pair = "\(character)\(input[nextIndex])"
                    if ["<=", ">=", "==", "!=", "<>"].contains(pair) {
                        tokens.append(pair)
                        index = nextIndex
                    } else {
                        tokens.append(String(character))
                    }
                } else {
                    tokens.append(String(character))
                }
            } else {
                current.append(character)
            }
            index = input.index(after: index)
        }
        flush()
        return tokens
    }

    private struct Parser {
        let tokens: [String]
        let variables: [String: Double]
        var position = 0

        mutating func parseExpression() throws -> Double {
            let result = try parseComparison()
            if !isAtEnd {
                throw NotebookFormulaError.unexpectedToken(peek)
            }
            return result
        }

        private mutating func parseComparison() throws -> Double {
            var left = try parseAddSub()
            while match("<", ">", "<=", ">=", "==", "!=", "<>") {
                let op = previous
                let right = try parseAddSub()
                switch op {
                case "<": left = left < right ? 1 : 0
                case ">": left = left > right ? 1 : 0
                case "<=": left = left <= right ? 1 : 0
                case ">=": left = left >= right ? 1 : 0
                case "==": left = left == right ? 1 : 0
                case "!=", "<>": left = left != right ? 1 : 0
                default: throw NotebookFormulaError.unexpectedToken(op)
                }
            }
            return left
        }

        private mutating func parseAddSub() throws -> Double {
            var left = try parseMulDiv()
            while match("+", "-") {
                let op = previous
                let right = try parseMulDiv()
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        private mutating func parseMulDiv() throws -> Double {
            var left = try parseUnary()
            while match("*", "/") {
                let op = previous
                let right = try parseUnary()
                if op == "/" {
                    guard right != 0 else { throw NotebookFormulaError.divisionByZero }
                    left /= right
                } else {
                    left *= right
                }
            }
            return left
        }

        private mutating func parseUnary() throws -> Double {
            if match("-") { return try -parseUnary() }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            if match("(") {
                let value = try parseComparison()
                guard match(")") else { throw NotebookFormulaError.unbalancedParentheses }
                return value
            }

            guard !isAtEnd else { throw NotebookFormulaError.incompleteExpression }
            let token = advance()
            if let number = Double(token.replacingOccurrences(of: ",", with: ".")) {
                return number
            }
            if match("(") {
                var args: [Double] = []
                if !check(")") {
                    repeat {
                        args.append(try parseComparison())
                    } while match(",")
                }
                guard match(")") else { throw NotebookFormulaError.unbalancedParentheses }
                return try evaluateFunction(token, args: args)
            }
            if let value = variables[token] ?? variables[NotebookFormulaEvaluator.safeIdentifier(for: token)] {
                return value
            }
            throw NotebookFormulaError.unknownVariable(token)
        }

        private func evaluateFunction(_ rawName: String, args: [Double]) throws -> Double {
            let name = rawName.uppercased()
            switch name {
            case "SUM", "SUMA":
                return args.reduce(0, +)
            case "AVG", "AVERAGE", "PROMEDIO":
                guard !args.isEmpty else { throw NotebookFormulaError.invalidArguments("\(rawName) requiere al menos 1 argumento") }
                return args.reduce(0, +) / Double(args.count)
            case "MIN":
                guard let value = args.min() else { throw NotebookFormulaError.invalidArguments("MIN requiere al menos 1 argumento") }
                return value
            case "MAX":
                guard let value = args.max() else { throw NotebookFormulaError.invalidArguments("MAX requiere al menos 1 argumento") }
                return value
            case "ROUND", "REDONDEAR":
                guard args.count == 1 || args.count == 2 else { throw NotebookFormulaError.invalidArguments("\(rawName) requiere 1 o 2 argumentos") }
                let digits = args.count == 2 ? Int(args[1]) : 0
                let factor = pow(10.0, Double(digits))
                return (args[0] * factor).rounded() / factor
            case "IF", "SI":
                guard args.count == 3 else { throw NotebookFormulaError.invalidArguments("\(rawName) requiere 3 argumentos") }
                return args[0] != 0 ? args[1] : args[2]
            default:
                throw NotebookFormulaError.unknownFunction(rawName)
            }
        }

        private mutating func match(_ expected: String...) -> Bool {
            guard !isAtEnd, expected.contains(peek) else { return false }
            position += 1
            return true
        }

        private func check(_ expected: String) -> Bool {
            !isAtEnd && peek == expected
        }

        private mutating func advance() -> String {
            let token = peek
            position += 1
            return token
        }

        private var previous: String { tokens[position - 1] }
        private var peek: String { tokens[position] }
        private var isAtEnd: Bool { position >= tokens.count }
    }
}

private struct NotebookEditableTableCell: View {
    @ObservedObject var bridge: KmpBridge
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    var focusedCellId: FocusState<String?>.Binding
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onAttendanceSaved: () -> Void

    @State private var numericDraft = ""
    @State private var textDraft = ""
    @State private var checkDraft = false
    @State private var originalNumericDraft = ""
    @State private var originalTextDraft = ""
    @State private var originalCheckDraft = false
    @State private var numericDragStartValue: Double?
    @State private var showTextPopover = false
    @State private var hasLoadedDrafts = false

    private var cellId: String {
        "\(item.student.id)|\(column.id)"
    }

    var body: some View {
        let persistedCell = item.row.persistedCells.first(where: { $0.columnId == column.id })
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tint.opacity(0.14) : NotebookStyle.surfaceSoft.opacity(column.categoryId == nil ? 0.16 : 0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ? tint.opacity(0.55) : (categoryTint ?? tint).opacity(column.categoryId == nil ? 0.05 : 0.12),
                            lineWidth: isSelected ? 1.5 : (column.categoryId == nil ? 0.8 : 1)
                        )
                )

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if let persistedCell, hasContextualSignal(in: persistedCell) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            if let icon = persistedCell.annotation?.icon ?? persistedCell.iconValue, !icon.isEmpty {
                                Text(icon)
                            }
                            let attachmentCount = persistedCell.annotation?.attachmentUris.count ?? 0
                            if attachmentCount > 0 {
                                Text("\(attachmentCount)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.14))
                        )
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear(perform: loadDrafts)
        .onChange(of: reloadToken) { _ in
            loadDrafts()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAttendanceColumn {
            if isAttendanceQuickMode {
                quickAttendanceButton
            } else {
                attendancePicker
            }
        } else {
            switch column.type {
            case .numeric:
                let field = TextField("", text: $numericDraft)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .appKeyboardType(.decimalPad)
                    .focused(focusedCellId, equals: cellId)
                    .submitLabel(.next)
                    .foregroundStyle(.primary)
                    .onSubmit { saveNumericAndNavigate(navigationDirection) }
                    .simultaneousGesture(numericDragGesture)

                #if canImport(UIKit)
                field
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Button("Arriba") { saveNumericAndNavigate(.up) }
                            Button("Abajo") { saveNumericAndNavigate(.down) }
                            Spacer()
                            Button("Guardar y avanzar") {
                                saveNumericAndNavigate(navigationDirection)
                            }
                        }
                    }
                #else
                field
                #endif
            case .calculated:
                Button {
                    onSelect()
                    onOpenFormula()
                } label: {
                    HStack(spacing: 6) {
                        Text(formulaDisplay?.text ?? bridge.numericGradeOnTenText(studentId: item.student.id, columnId: column.id))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(formulaDisplay?.isError == true ? .orange : .primary)
                            .lineLimit(1)
                        Image(systemName: formulaDisplay?.isError == true ? "exclamationmark.triangle.fill" : "function")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(formulaDisplay?.isError == true ? .orange : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(formulaDisplay?.isError == true ? (formulaDisplay?.text ?? "Error en la fórmula") : "Editar fórmula")
            case .check:
                Toggle("", isOn: $checkDraft)
                    .labelsHidden()
                    .tint(tint)
                    .onChange(of: checkDraft) { newValue in
                        guard hasLoadedDrafts else { return }
                        onSelect()
                        let previousValue = originalCheckDraft ? "true" : "false"
                        let nextValue = newValue ? "true" : "false"
                        if previousValue != nextValue {
                            onPrepareUndo(previousValue, originalCheckDraft ? "Sí" : "No")
                            originalCheckDraft = newValue
                        }
                        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: newValue ? "true" : "false")
                        onNavigate(navigationDirection)
                    }
            case .ordinal:
                Button {
                    onSelect()
                    activeChoiceCellId = cellId
                } label: {
                    Text(textDraft.isEmpty ? "Seleccionar" : textDraft)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: choicePopoverBinding, arrowEdge: .bottom) {
                    choiceList(options: ordinalOptions) { option in
                        saveOrdinalValue(option)
                    }
                }
            case .rubric:
                let rubricText = displayRubricText()
                Menu {
                    Button("Evaluar alumno…") {
                        onSelect()
                        onOpenRubricIndividual()
                    }
                    Button("Evaluar grupo…") {
                        onSelect()
                        onOpenRubricBulk()
                    }
                } label: {
                    Text(rubricText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(rubricText == "—" ? .tertiary : .primary)
                }
                .menuStyle(.borderlessButton)
            default:
                HStack(spacing: 6) {
                    TextField("", text: $textDraft)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused(focusedCellId, equals: cellId)
                        .foregroundStyle(.primary)
                        .submitLabel(.next)
                        .onSubmit { saveTextAndNavigate() }

                    if shouldOfferTextPopover {
                        Button {
                            showTextPopover = true
                        } label: {
                            Image(systemName: "text.alignleft")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showTextPopover, arrowEdge: .bottom) {
                            #if os(macOS)
                            VStack(spacing: 0) {
                                ScrollView {
                                    Text(textDraft)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: 320, alignment: .leading)
                                        .padding(14)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: 340, maxHeight: 260)

                                MacPopupActionBar(
                                    title: nil,
                                    onClose: { showTextPopover = false }
                                )
                            }
                            #else
                            ScrollView {
                                Text(textDraft)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: 320, alignment: .leading)
                                    .padding(14)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: 340, maxHeight: 260)
                            #endif
                        }
                    }
                }
            }
        }
    }

    private var isAttendanceColumn: Bool {
        column.type == .attendance || column.categoryKind == .attendance
    }

    private var choicePopoverBinding: Binding<Bool> {
        Binding(
            get: { activeChoiceCellId == cellId },
            set: { isPresented in
                if isPresented {
                    activeChoiceCellId = cellId
                } else if activeChoiceCellId == cellId {
                    activeChoiceCellId = nil
                }
            }
        )
    }

    private func choiceList(options: [String], onChoose: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    onChoose(option)
                } label: {
                    HStack {
                        Text(option)
                        Spacer(minLength: 18)
                        if textDraft == option {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .frame(minWidth: 170, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
        .padding(8)
    }

    private var attendancePicker: some View {
        Button {
            onSelect()
            activeChoiceCellId = cellId
        } label: {
            attendanceChip(value: textDraft)
        }
        .buttonStyle(.plain)
        .popover(isPresented: choicePopoverBinding, arrowEdge: .bottom) {
            choiceList(options: attendanceOptions.map(\.label)) { label in
                if let option = attendanceOptions.first(where: { $0.label == label }) {
                    saveAttendanceValue(option.value)
                }
            }
        }
    }

    private var quickAttendanceButton: some View {
        Button {
            saveQuickAttendanceValue()
        } label: {
            HStack(spacing: 6) {
                attendanceChip(value: textDraft)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.plain)
        .help("Pase rápido")
    }

    private var numericDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if numericDragStartValue == nil {
                    numericDragStartValue = parseEditableNumber(numericDraft) ?? 0
                }
                guard let start = numericDragStartValue else { return }
                let delta = Double(-value.translation.height / 20.0)
                let adjusted = min(10.0, max(0.0, start + delta))
                let rounded = (adjusted * 10).rounded() / 10
                numericDraft = String(format: "%.1f", rounded)
            }
            .onEnded { _ in
                numericDragStartValue = nil
                saveNumeric()
            }
    }

    private var attendanceOptions: [(label: String, value: String)] {
        [
            ("Presente", "PRESENTE"),
            ("Ausente", "AUSENTE"),
            ("Retraso", "TARDE"),
            ("Justificada", "JUSTIFICADO"),
            ("Sin material", "SIN_MATERIAL"),
            ("Exento", "EXENTO"),
            ("Sin pasar", "")
        ]
    }

    private func attendanceChip(value: String) -> some View {
        let display = attendanceDisplay(value)
        return Text(display.label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(display.color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(display.color.opacity(display.value.isEmpty ? 0.08 : 0.14))
            )
    }

    private func attendanceDisplay(_ value: String) -> (label: String, value: String, color: Color) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "PRESENTE", "PRESENT", "PRES":
            return ("Presente", normalized, .green)
        case "AUSENTE", "ABSENT", "AUS":
            return ("Ausente", normalized, .red)
        case "TARDE", "RETRASO", "LATE":
            return ("Retraso", normalized, .orange)
        case "JUSTIFICADO", "JUSTIFICADA", "JUSTIFIED":
            return ("Justificada", normalized, .gray)
        case "SIN_MATERIAL":
            return ("Sin material", normalized, .brown)
        case "EXENTO":
            return ("Exento", normalized, .indigo)
        default:
            return ("—", "", .secondary)
        }
    }

    private func nextQuickAttendanceStatus(after value: String) -> String {
        switch attendanceDisplay(value).value {
        case "":
            return "PRESENTE"
        case "PRESENTE", "PRESENT", "PRES":
            return "AUSENTE"
        case "AUSENTE", "ABSENT", "AUS":
            return "TARDE"
        default:
            return "PRESENTE"
        }
    }

    private func parseEditableNumber(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var ordinalOptions: [String] {
        if !column.ordinalLevels.isEmpty { return column.ordinalLevels }
        switch column.inputKind {
        case .letterAbcd:
            return ["A", "B", "C", "D"]
        case .achievedPartialNotAchieved:
            return ["Logrado", "Parcial", "No logrado"]
        case .excellentGoodProgress:
            return ["Excelente", "Bien", "En proceso"]
        default:
            return ["A", "B", "C", "D"]
        }
    }

    private func loadDrafts() {
        hasLoadedDrafts = false
        numericDraft = bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        textDraft = bridge.cellText(studentId: item.student.id, columnId: column.id)
        checkDraft = bridge.cellCheck(studentId: item.student.id, columnId: column.id)
        originalNumericDraft = numericDraft
        originalTextDraft = textDraft
        originalCheckDraft = checkDraft
        DispatchQueue.main.async {
            hasLoadedDrafts = true
        }
    }

    private func saveNumeric() {
        onSelect()
        if originalNumericDraft != numericDraft {
            onPrepareUndo(originalNumericDraft, originalNumericDraft)
            originalNumericDraft = numericDraft
        }
        bridge.saveColumnGradeDebounced(studentId: item.student.id, column: column, value: numericDraft)
    }

    private func saveNumericAndNavigate(_ direction: NotebookNavigationDirection) {
        saveNumeric()
        onNavigate(direction)
    }

    private func saveText() {
        onSelect()
        if originalTextDraft != textDraft {
            onPrepareUndo(originalTextDraft, originalTextDraft)
            originalTextDraft = textDraft
        }
        bridge.saveColumnGradeDebounced(studentId: item.student.id, column: column, value: textDraft)
    }

    private func saveTextAndNavigate() {
        saveText()
        onNavigate(navigationDirection)
    }

    private func saveOrdinalValue(_ option: String) {
        let previousValue = textDraft
        textDraft = option
        onSelect()
        activeChoiceCellId = nil
        if previousValue != option {
            onPrepareUndo(previousValue, previousValue)
            originalTextDraft = option
        }
        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: option)
        onNavigate(navigationDirection)
    }

    private func saveAttendanceValue(_ status: String) {
        let previousValue = textDraft
        textDraft = status
        onSelect()
        activeChoiceCellId = nil
        if previousValue != status {
            onPrepareUndo(previousValue, attendanceDisplay(previousValue).label)
            originalTextDraft = status
        }
        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: status)
        onNavigate(navigationDirection)

        guard let classId else { return }
        let attendanceDate = column.dateEpochMs
            .map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000.0) } ?? Date()

        Task {
            try? await bridge.saveAttendance(
                studentId: item.student.id,
                classId: classId,
                on: attendanceDate,
                status: status
            )
            await MainActor.run {
                onAttendanceSaved()
            }
        }
    }

    private func saveQuickAttendanceValue() {
        let nextStatus = nextQuickAttendanceStatus(after: textDraft)
        saveAttendanceValue(nextStatus)
    }

    private func displayRubricText() -> String {
        let value = bridge.rubricGradeOnTenText(studentId: item.student.id, column: column).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "—" : value
    }

    private func hasContextualSignal(in cell: PersistedNotebookCell) -> Bool {
        !(cell.annotation?.note?.isEmpty ?? true) ||
            !((cell.annotation?.icon ?? cell.iconValue ?? "").isEmpty) ||
            !(cell.annotation?.attachmentUris.isEmpty ?? true)
    }

    private var shouldOfferTextPopover: Bool {
        !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && estimatedTextWidth > max(80, width - 56)
    }

    private var estimatedTextWidth: CGFloat {
        #if canImport(UIKit)
        return (textDraft as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13)]).width
        #else
        return CGFloat(textDraft.count) * 7
        #endif
    }
}

private struct NotebookDynamicCellsRow: View {
    @ObservedObject var bridge: KmpBridge
    let item: NotebookTableRow
    let segments: [NotebookDisplaySegment]
    let inspectorSelection: NotebookInspectorSelection?
    let onSelect: (NotebookInspectorSelection) -> Void
    @FocusState private var focusedCellId: String?
    @State private var activeChoiceCellId: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .fixed:
                    EmptyView()
                case .column(let column):
                    NotebookEditableTableCell(
                        bridge: bridge,
                        item: item,
                        column: column,
                        classId: nil,
                        width: max(column.widthDp, 120),
                        tint: column.colorHex.map { Color(hex: $0) } ?? NotebookStyle.primaryTint,
                        categoryTint: nil,
                        focusedCellId: $focusedCellId,
                        activeChoiceCellId: $activeChoiceCellId,
                        navigationDirection: .down,
                        formulaDisplay: nil,
                        isSelected: inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id),
                        isAttendanceQuickMode: false,
                        reloadToken: 0,
                        onSelect: {
                            onSelect(NotebookInspectorSelection(studentId: item.student.id, columnId: column.id))
                        },
                        onPrepareUndo: { _, _ in },
                        onOpenFormula: {},
                        onOpenRubricIndividual: {},
                        onOpenRubricBulk: {},
                        onNavigate: { _ in },
                        onAttendanceSaved: {}
                    )
                    .frame(width: max(column.widthDp, 120))
                case .collapsedCategory(let category, let columns):
                    Button {
                        bridge.toggleColumnCategory(id: category.id, collapsed: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("\(columns.filter { !cellValue(for: $0).isEmpty }.count) / \(columns.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(NotebookStyle.surfaceMuted)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cellValue(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric, .calculated:
            return bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        case .rubric:
            return bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
        case .check:
            return bridge.cellCheck(studentId: item.student.id, columnId: column.id) ? "true" : ""
        default:
            return bridge.cellText(studentId: item.student.id, columnId: column.id)
        }
    }
}

private struct NotebookSeatCard: View {
    let student: Student
    let averageText: String
    let attendanceText: String
    let incidentCount: Int
    let isHighlighted: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onMarkPresent: () -> Void
    let onMarkAbsent: () -> Void
    let onMarkLate: () -> Void
    let onFollowUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(NotebookStyle.primaryTint.opacity(0.16))
                    Text(String(student.firstName.prefix(1)) + String(student.lastName.prefix(1)))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(student.fullName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text(attendanceText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Media \(averageText)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if incidentCount > 0 {
                    Text("\(incidentCount)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }

            HStack(spacing: 6) {
                quickAction("P", tint: NotebookStyle.successTint, action: onMarkPresent)
                quickAction("A", tint: .red, action: onMarkAbsent)
                quickAction("R", tint: NotebookStyle.warningTint, action: onMarkLate)
                quickAction("Seg", tint: .orange, action: onFollowUp)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isHighlighted ? NotebookStyle.primaryTint.opacity(0.18) : NotebookStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder((isSelected ? NotebookStyle.primaryTint : Color.white.opacity(0.10)), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private func quickAction(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct NotebookAICommentSheet: View {
    let bridge: KmpBridge
    let data: NotebookUiStateData
    let managedColumns: [NotebookColumnDefinition]
    let visibleColumns: [NotebookColumnDefinition]
    let selectedStudentIds: [Int64]
    let targetColumnId: String?
    let mode: NotebookAIFlowMode
    let onComplete: (String, NotebookToastStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var columnName = "Comentario IA"
    @State private var scope: NotebookAIColumnScope = .visibleColumns
    @State private var audience: AIReportAudience = .docente
    @State private var tone: AIReportTone = .claro
    @State private var onlyEmptyCells = true
    @State private var selectedExistingColumnId = ""
    @State private var isGenerating = false
    @State private var progressMessage: String?
    @State private var feedbackMessage: String?

    private let aiService = AppleFoundationContextualAIService()

    private var existingAIColumns: [NotebookColumnDefinition] {
        data.sheet.columns.filter(bridge.isNotebookAICommentColumn)
    }

    private var availability: AIContextualAvailabilityState {
        aiService.currentAvailability()
    }

    private var effectiveStudentIds: [Int64] {
        let ids = selectedStudentIds.isEmpty ? data.sheet.rows.map { $0.student.id } : selectedStudentIds
        return Array(Set(ids)).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    configCard
                    generationCard
                }
                .padding(24)
            }
            .background(EvaluationBackdrop())
            .navigationTitle(mode == .createColumn ? "Columna IA" : "Comentario IA")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                aiService.prewarm()
                if let targetColumnId {
                    selectedExistingColumnId = targetColumnId
                } else if let first = existingAIColumns.first {
                    selectedExistingColumnId = first.id
                }
            }
        }
    }

    private var configCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(mode == .createColumn ? "Crear columna persistida de comentario IA" : "Generar comentarios para selección")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Text(availability.message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(availability.isAvailable ? NotebookStyle.successTint : NotebookStyle.warningTint)

                if mode == .createColumn {
                    TextField("Nombre de columna", text: $columnName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } else if !existingAIColumns.isEmpty {
                    Picker("Columna destino", selection: $selectedExistingColumnId) {
                        ForEach(existingAIColumns, id: \.id) { column in
                            Text(column.title).tag(column.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker("Datos base", selection: $scope) {
                    ForEach(NotebookAIColumnScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Audiencia", selection: $audience) {
                    ForEach(AIReportAudience.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Tono", selection: $tone) {
                    ForEach(AIReportTone.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Rellenar solo celdas vacías", isOn: $onlyEmptyCells)

                Text("Los comentarios se guardarán como texto editable y no contarán para la media.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generationCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surface, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Generación")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Alumnado objetivo: \(effectiveStudentIds.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if let progressMessage {
                    Text(progressMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookStyle.warningTint)
                }

                HStack(spacing: 12) {
                    Button {
                        performGeneration()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(mode == .createColumn ? "Crear y generar" : "Generar comentarios", systemImage: "apple.intelligence")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || effectiveStudentIds.isEmpty || resolvedIncludedColumnIds().isEmpty)

                    if mode == .createColumn {
                        Button("Solo crear columna") {
                            if createColumnIfNeeded(forceNew: true) != nil {
                                onComplete("Columna IA creada. Puedes rellenarla manualmente o generar después.", .success)
                                dismiss()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func resolvedIncludedColumnIds() -> [String] {
        let columns: [NotebookColumnDefinition]
        switch scope {
        case .visibleColumns:
            columns = visibleColumns
        case .evaluableColumns:
            columns = managedColumns.filter { $0.countsTowardAverage || $0.categoryKind == .evaluation || $0.type == .rubric || $0.type == .numeric || $0.type == .calculated }
        case .allManagedColumns:
            columns = managedColumns
        }
        return columns.map(\.id)
    }

    private func createColumnIfNeeded(forceNew: Bool) -> String? {
        if !forceNew {
            if let targetColumnId, !targetColumnId.isEmpty {
                return targetColumnId
            }
            if !selectedExistingColumnId.isEmpty {
                return selectedExistingColumnId
            }
            if let existing = existingAIColumns.first {
                return existing.id
            }
        }
        return bridge.createNotebookAICommentColumn(name: columnName)
    }

    private func performGeneration() {
        let includedColumnIds = resolvedIncludedColumnIds()
        guard !includedColumnIds.isEmpty else {
            feedbackMessage = "Selecciona al menos una columna fuente con datos."
            return
        }

        isGenerating = true
        feedbackMessage = nil
        progressMessage = nil

        Task {
            var targetColumnId = createColumnIfNeeded(forceNew: mode == .createColumn)
            guard let resolvedColumnId = targetColumnId else {
                await MainActor.run {
                    feedbackMessage = "No se pudo crear o resolver la columna IA."
                    isGenerating = false
                }
                return
            }
            targetColumnId = resolvedColumnId

            if !availability.isAvailable {
                await MainActor.run {
                    onComplete("Columna IA creada, pero la generación local no está disponible en este dispositivo.", .warning)
                    isGenerating = false
                    dismiss()
                }
                return
            }

            let contexts = bridge.generateNotebookAICommentContexts(
                includedColumnIds: includedColumnIds,
                studentIds: effectiveStudentIds
            )

            if contexts.isEmpty {
                await MainActor.run {
                    feedbackMessage = "No hay suficiente contexto de cuaderno para generar comentarios."
                    isGenerating = false
                }
                return
            }

            var savedCount = 0
            var skippedCount = 0

            for (index, context) in contexts.enumerated() {
                await MainActor.run {
                    progressMessage = "Generando \(index + 1) de \(contexts.count): \(context.studentName)"
                }

                if onlyEmptyCells,
                   let targetColumnId,
                   !bridge.cellText(studentId: context.studentId, columnId: targetColumnId).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    skippedCount += 1
                    continue
                }

                do {
                    let draft = try await aiService.generateNotebookComment(
                        from: context,
                        audience: audience,
                        tone: tone
                    )
                    if let targetColumnId {
                        bridge.saveNotebookAIComment(studentId: context.studentId, columnId: targetColumnId, text: draft.commentText)
                        savedCount += 1
                    }
                } catch {
                    skippedCount += 1
                }
            }

            await MainActor.run {
                onComplete(
                    "Comentarios IA guardados: \(savedCount). Omitidos: \(skippedCount).",
                    savedCount > 0 ? .success : .warning
                )
                isGenerating = false
                dismiss()
            }
        }
    }
}

private struct FlexibleTagRow: View {
    let items: [String]
    let selected: String
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item.isEmpty ? "Sin icono" : item)
                        .font(.system(size: item.isEmpty ? 11 : 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected == item ? NotebookStyle.primaryTint.opacity(0.16) : NotebookStyle.surface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct NotebookStateCard<Accessory: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = NotebookStyle.primaryTint
    @ViewBuilder var accessory: Accessory

    init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = NotebookStyle.primaryTint,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 28) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    accessory
                }
                .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
