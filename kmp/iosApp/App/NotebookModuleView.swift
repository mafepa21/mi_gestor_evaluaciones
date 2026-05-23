import SwiftUI
import PhotosUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

enum NotebookToolbarMode {
    case inlineCompact
    case shellOwned
    case macWindowOwned
    case hidden
}

struct NotebookModuleView: View {
    #if os(macOS)
    let notebookGridRowHeight: CGFloat = 50
    #else
    var notebookGridRowHeight: CGFloat {
        isCompact ? 56 : 52
    }
    #endif
    let notebookGridHeaderHeight: CGFloat = 56
    let notebookGridFolderLaneHeight: CGFloat = 34

    @EnvironmentObject var layoutState: WorkspaceLayoutState
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let toolbarMode: NotebookToolbarMode
    let macToolbarActions: NotebookMacToolbarActions?
    @StateObject var inspectorState: NotebookMacInspectorState
    @StateObject var gridLayoutModel = NotebookGridLayoutModel()
    let macPresentation: NotebookMacPresentation
    @State var addColumnContext: NotebookAddColumnContext? = nil
    @State var searchText = ""
    @State var selectedGroupId: Int64? = nil
    @State var viewPreset: NotebookViewPreset = .all
    @State var surfaceMode: NotebookSurfaceMode = .grid
    @State var todayAttendanceByStudentId: [Int64: String] = [:]
    @State var incidentCountByStudentId: [Int64: Int] = [:]
    @State var localInjuryStatuses: [Int64: Bool] = [:]
    @State var seatPositions: [Int64: NotebookSeatPosition] = [:]
    @State var highlightedRandomStudentId: Int64? = nil
    @State var selectedAttachmentPhoto: PhotosPickerItem?
    @State var isCreateCategoryAlertPresented = false
    @State var categoryDraft = ""
    @State var editingCategoryId: String? = nil
    @State var isNotebookTabAlertPresented = false
    @State var notebookTabDraft = ""
    @State var editingNotebookTabId: String? = nil
    @State var pendingDeleteNotebookTab: NotebookTab? = nil
    @State var isRenameColumnAlertPresented = false
    @State var columnDraft = ""
    @State var editingColumnId: String? = nil
    @State var pendingDeleteColumn: NotebookColumnDefinition? = nil
    @State var pendingDeleteCategory: NotebookColumnCategory? = nil
    @State var pendingDeletionImpact: NotebookDeletionImpactDraft? = nil
    @State var deletionConfirmationText = ""
    @State var isOrganizationMenuPresented = false
    @State var isHiddenColumnsSheetPresented = false
    @State var toast: NotebookToast? = nil
    @State var isAttendanceQuickMode = false
    @State var isMarkAllPresentDialogPresented = false
    @State var undoStack: [NotebookCellUndoEntry] = []
    @State var cellReloadRevision = 0
    @State var highlightedCategoryId: String? = nil
    @State var highlightedColumnId: String? = nil
    @State var expandedEmptyCategoryIds: Set<String> = []
    @State var pendingRubricColumnId: String? = nil
    @State var pendingRubricStudentOrder: [Int64] = []
    @State var pendingRubricCurrentStudentId: Int64? = nil
    @State var notebookAISheetRequest: NotebookAISheetRequest? = nil
    @State var notebookSummarySheetRequest: NotebookSummarySheetRequest? = nil
    @State var isAverageConfigurationPresented = false
    @State var averageExplanationRow: NotebookTableRow? = nil
    @State var currentSelectionAuditEvents: [NotebookCellAuditEvent] = []
    @State var auditObservationTask: Task<Void, Never>? = nil
    @State var toolbarSyncTask: Task<Void, Never>? = nil
    @State var lastToolbarStateKey: String? = nil
    @State var riskLevelCache: [Int64: RiskLevel] = [:]
    @State var riskComputationKey: String?
    @State var isPrecomputingRiskLevels = false
    @AppStorage("notebook.fixedZoneWidth") var fixedZoneWidthStored = 460.0
    @State var isDraggingFixedZoneDivider = false
    @State var fixedZoneDragStartWidth: CGFloat = 0
    @State var fixedZoneLiveWidth: CGFloat? = nil
    @State var formulaEditRequest: NotebookFormulaEditRequest? = nil
    @State var formulaDraft = ""
    @State var formulaAIPrompt = ""
    @State var formulaAIMessage: String? = nil
    @State var isFormulaAIGenerating = false
    @State var activeChoiceCellId: String? = nil
    @State var organizationColumnSearchText = ""
    @State var focusMode: NotebookFocusMode = .normal
    @State private var contextualAIOrchestrator = AppleAIOrchestrator()
    @StateObject private var formulaAIServiceStore = AppleFoundationFormulaServiceStore()
    @AppStorage("notebook.navigationDirection") var navigationDirectionRaw = NotebookNavigationDirection.down.rawValue
    @FocusState var focusedCellId: String?

    var formulaAIService: AppleFoundationFormulaService {
        formulaAIServiceStore.service
    }

    var formulaAIOrchestrator: AppleAIOrchestrator {
        formulaAIServiceStore.orchestrator
    }

    init(
        bridge: KmpBridge,
        selectedClassId: Binding<Int64?>,
        selectedStudentId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void,
        toolbarMode: NotebookToolbarMode = .inlineCompact,
        macPresentation: NotebookMacPresentation = .full,
        macInspectorState: NotebookMacInspectorState? = nil,
        macToolbarActions: NotebookMacToolbarActions? = nil
    ) {
        self._bridge = ObservedObject(wrappedValue: bridge)
        self._selectedClassId = selectedClassId
        self._selectedStudentId = selectedStudentId
        self.onOpenModule = onOpenModule
        self.toolbarMode = toolbarMode
        self.macToolbarActions = macToolbarActions
        self.macPresentation = macPresentation
        self._inspectorState = StateObject(wrappedValue: macInspectorState ?? NotebookMacInspectorState())
    }

    var navigationDirection: NotebookNavigationDirection {
        get { NotebookNavigationDirection(rawValue: navigationDirectionRaw) ?? .down }
        nonmutating set { navigationDirectionRaw = newValue.rawValue }
    }

    func isCategoryCollapsed(_ category: NotebookColumnCategory) -> Bool {
        gridLayoutModel.isCategoryCollapsed(category)
    }

    func setCategoryCollapsed(_ category: NotebookColumnCategory, collapsed: Bool) {
        withAnimation(.snappy(duration: 0.18)) {
            gridLayoutModel.setCategoryCollapsed(category, collapsed: collapsed)
            if !collapsed {
                expandedEmptyCategoryIds.insert(category.id)
            }
            bridge.toggleColumnCategory(id: category.id, collapsed: collapsed)
        }
    }

    var inspectorSelection: NotebookInspectorSelection? {
        get { inspectorState.selection }
        nonmutating set { inspectorState.selection = newValue }
    }

    var inspectorNoteDraft: String {
        get { inspectorState.noteDraft }
        nonmutating set { inspectorState.noteDraft = newValue }
    }

    var inspectorIconDraft: String {
        get { inspectorState.iconDraft }
        nonmutating set { inspectorState.iconDraft = newValue }
    }

    var inspectorAttachmentUris: [String] {
        get { inspectorState.attachmentUris }
        nonmutating set { inspectorState.attachmentUris = newValue }
    }

    var isInspectorPresented: Bool {
        get { inspectorState.isPresented }
        nonmutating set { inspectorState.isPresented = newValue }
    }

    func closeInspectorAndTransientState() {
        isInspectorPresented = false
        inspectorSelection = nil
        focusMode = .normal
        inspectorNoteDraft = ""
        inspectorIconDraft = ""
        inspectorAttachmentUris = []

        selectedAttachmentPhoto = nil
        averageExplanationRow = nil
        currentSelectionAuditEvents = []

        auditObservationTask?.cancel()
        auditObservationTask = nil
    }

    func resetNotebookTransientStateForClassChange() {
        closeInspectorAndTransientState()

        selectedStudentId = nil
        selectedGroupId = nil
        highlightedRandomStudentId = nil
        activeChoiceCellId = nil
        focusedCellId = nil
        focusMode = .normal

        undoStack = []
        todayAttendanceByStudentId = [:]
        incidentCountByStudentId = [:]
        riskLevelCache = [:]
        riskComputationKey = nil
        isPrecomputingRiskLevels = false

        cellReloadRevision += 1
    }

    var isMacInspectorOnly: Bool {
        macPresentation == .inspector
    }

    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var shouldUseSideInspector: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular
        #else
        return true
        #endif
    }

    var inspectorSelectionBinding: Binding<NotebookInspectorSelection?> {
        Binding(
            get: { inspectorSelection },
            set: { inspectorSelection = $0 }
        )
    }

    var inspectorNoteDraftBinding: Binding<String> {
        Binding(
            get: { inspectorNoteDraft },
            set: { inspectorNoteDraft = $0 }
        )
    }

    var inspectorIconDraftBinding: Binding<String> {
        Binding(
            get: { inspectorIconDraft },
            set: { inspectorIconDraft = $0 }
        )
    }

    var inspectorAttachmentUrisBinding: Binding<[String]> {
        Binding(
            get: { inspectorAttachmentUris },
            set: { inspectorAttachmentUris = $0 }
        )
    }

    var mappedExplanationItemBinding: Binding<NotebookAverageExplanationItem?> {
        Binding(
            get: {
                guard let row = averageExplanationRow else { return nil }
                return NotebookAverageExplanationItem(
                    id: String(row.student.id),
                    studentName: "\(row.student.firstName) \(row.student.lastName)",
                    explanation: row.row.averageExplanation
                )
            },
            set: { newValue in
                if newValue == nil {
                    averageExplanationRow = nil
                }
            }
        )
    }

    var isInspectorPresentedBinding: Binding<Bool> {
        Binding(
            get: { isInspectorPresented },
            set: { isInspectorPresented = $0 }
        )
    }

    var body: some View {
        if isMacInspectorOnly {
            notebookLifecycleCleanup(notebookContentWithDialogs)
        } else {
            notebookLifecycleCleanup(
                notebookObservationModifiers(
                    notebookSheetAndTaskModifiers(notebookContentWithDialogs)
                )
            )
        }
    }


    func centerPanel(data: NotebookUiStateData) -> some View {
        let rows = filteredRows(data: data)
        let tabs = orderedNotebookTabs(data: data)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if toolbarMode == .inlineCompact {
                    NotebookCompactCommandBar(
                        bridge: bridge,
                        searchText: $searchText,
                        classTitle: activeClassLabel,
                        subtitle: tabs.count == 1 ? tabs.first?.title : nil,
                        selectedClassId: bridge.notebookViewModel.currentClassId?.int64Value,
                        classes: sortedClasses,
                        focusMode: focusMode,
                        isInspectorPresented: isInspectorPresented,
                        canUndo: !undoStack.isEmpty,
                        isAttendanceQuickMode: isAttendanceQuickMode,
                        showsAdvancedActions: focusMode == .normal,
                        onSelectClass: selectNotebookClass,
                        onAddColumn: {
                            addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
                        },
                        onOpenOrganization: {
                            isOrganizationMenuPresented = true
                        },
                        onToggleInspector: {
                            if isInspectorPresented {
                                closeInspectorAndTransientState()
                            } else {
                                if inspectorSelection == nil {
                                    openInspectorForSelection(data)
                                }
                                isInspectorPresented = inspectorSelection != nil
                                if isInspectorPresented {
                                    focusMode = .reviewing
                                }
                            }
                        },
                        onUndo: {
                            undoLastCellChange()
                        },
                        onToggleAttendanceQuickMode: {
                            isAttendanceQuickMode.toggle()
                            if isAttendanceQuickMode {
                                activeChoiceCellId = nil
                                focusedCellId = nil
                            }
                        },
                        secondaryActions: {
                            notebookCommandMenuContent(data: data, tabs: tabs, rows: rows)
                        }
                    )
                }
                if tabs.count > 1 && focusMode == .normal {
                    NotebookTabStrip(
                        tabs: tabs,
                        activeTabId: activeNotebookTabId(data: data),
                        onSelect: { tabId in
                            selectNotebookTab(tabId)
                        },
                        onCreateTab: {
                            presentCreateNotebookTab()
                        },
                        onRenameTab: { tab in
                            presentRenameNotebookTab(tab)
                        },
                        onDeleteTab: { tab in
                            pendingDeleteNotebookTab = tab
                        }
                    )
                    Divider()
                }
                spreadsheetContent(data: data, rows: rows)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if shouldUseSideInspector && macPresentation == .full && isInspectorPresented {
                Divider().opacity(0.16)
                inspectorPanel(data: data, rows: rows)
                    .frame(width: 360)
                    .background(NotebookStyle.surfaceMuted)
            }
        }
        .background(EvaluationBackdrop())
        .onAppear {
            gridLayoutModel.configure(classId: data.sheet.classId)
            if !isMacInspectorOnly {
                scheduleToolbarStateSync(data: data)
            }
        }
        .appOnChange(of: "\(data.sheet.classId)") { _ in
            gridLayoutModel.configure(classId: data.sheet.classId)
        }
        .appOnChange(of: toolbarStateKey(data: data)) { _ in
            if !isMacInspectorOnly {
                scheduleToolbarStateSync(data: data)
            }
        }
    }

    @ViewBuilder
    func spreadsheetContent(data: NotebookUiStateData, rows: [NotebookTableRow]) -> some View {
        let segments = displaySegments(data: data)
        let fixedSegments = gridLayoutModel.visibleFixedSegments(in: segments)
        let leadingFixedSegments = fixedSegments.filter { !gridLayoutModel.isTrailingFixedSegment($0) }
        let trailingFixedSegments = fixedSegments.filter(gridLayoutModel.isTrailingFixedSegment)
        let scrollableSegments = segments.filter { !gridLayoutModel.isFixedSegment($0) }
        let laneItems = gridLayoutModel.headerLaneItems(data: data, activeTabId: activeNotebookTabId(data: data), segments: scrollableSegments)
        let trailingPaddingCompensation = NotebookStyle.outerPadding * 2
        let hasFolders = laneItems.contains {
            if case .folder = $0 { return true }
            return false
        }
        let shouldShowFolderLane = hasFolders && !isCompact

        NotebookGridContent(
            rows: rows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedZoneWidth,
            trailingFixedColumnWidth: trailingFixedSegments.isEmpty ? 0 : defaultFixedWidth(for: .average) + trailingPaddingCompensation,
            topAccessoryHeight: shouldShowFolderLane ? notebookGridFolderLaneHeight : 0,
            headerHeight: notebookGridHeaderHeight,
            rowHeight: notebookGridRowHeight,
            rowInvalidationKey: gridRowInvalidationKey(data: data),
            fixedSegments: leadingFixedSegments,
            trailingFixedSegments: trailingFixedSegments,
            scrollableSegments: scrollableSegments
        ) {
            IOSEmptyState(
                title: "Sin alumnos visibles",
                subtitle: "Ajusta la búsqueda o el filtro de grupo para ver filas del cuaderno.",
                systemImage: "person.3.sequence"
            )
        } seatingContent: { rows in
            NotebookSeatingPlanView(
                rows: rows,
                averageText: { item in
                    averageText(for: item)
                },
                attendanceText: { studentId in
                    attendanceStatusText(for: studentId)
                },
                incidentCount: { studentId in
                    incidentCountByStudentId[studentId] ?? 0
                },
                selectedStudentId: inspectorSelection?.studentId,
                highlightedStudentId: highlightedRandomStudentId,
                seatPositions: $seatPositions,
                onHighlightRandomStudent: {
                    highlightedRandomStudentId = randomEligibleStudentId(from: rows)
                },
                onResetSeats: {
                    seatPositions = defaultSeatPositions(for: rows)
                    persistSeatPositions()
                },
                onPersistSeats: {
                    persistSeatPositions()
                },
                onOpenStudent: { studentId in
                    openInspectorForStudent(studentId, data: data)
                },
                onMarkPresent: { studentId in
                    Task { await markAttendance(for: studentId, status: NotebookAttendanceStatus.present) }
                },
                onMarkAbsent: { studentId in
                    Task { await markAttendance(for: studentId, status: NotebookAttendanceStatus.absent) }
                },
                onMarkLate: { studentId in
                    Task { await markAttendance(for: studentId, status: NotebookAttendanceStatus.late) }
                },
                onFollowUp: { student in
                    Task { await createFollowUp(for: student) }
                }
            )
        } topAccessory: {
            Group {
                if shouldShowFolderLane {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(laneItems, id: \.id) { item in
                            switch item {
                            case .spacer(_, let width):
                                Color.clear
                                    .frame(width: width, height: 1)
                            case .folder(let category, let columns, let width):
                                categoryFolderHeader(category: category, columns: columns, rows: rows, width: width)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                }
            }
        } dividerHandle: {
            NotebookDividerHandle(isDragging: isDraggingFixedZoneDivider) { translationWidth in
                if !isDraggingFixedZoneDivider {
                    isDraggingFixedZoneDivider = true
                    fixedZoneDragStartWidth = fixedZoneWidth
                }
                let newWidth = fixedZoneDragStartWidth + translationWidth
                fixedZoneLiveWidth = min(maxFixedZoneWidth, max(minFixedZoneWidth, newWidth))
            } onDragEnded: {
                isDraggingFixedZoneDivider = false
                snapFixedZoneWidth()
            }
        } header: { segments in
            headerRow(segments: segments, data: data)
        } rowContent: { index, item, segments in
            notebookRowView(
                item: item,
                data: data,
                segments: segments,
                rowIndex: index,
                allRows: rows,
                navigableSegments: scrollableSegments
            )
        }
    }

    @ViewBuilder
    func headerRow(segments: [NotebookDisplaySegment], data: NotebookUiStateData) -> some View {
        HStack(alignment: .top, spacing: 8) {
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

    var activeTabFixedWidth: CGFloat? {
        if let data = bridge.notebookState as? NotebookUiStateData,
           let tabId = activeNotebookTabId(data: data),
           let tab = data.sheet.tabs.first(where: { $0.id == tabId }),
           let width = tab.fixedColumnWidth?.doubleValue {
            return CGFloat(width)
        }
        return nil
    }

    var fixedZoneWidth: CGFloat {
        let stored = activeTabFixedWidth ?? CGFloat(fixedZoneWidthStored)
        return min(maxFixedZoneWidth, max(minFixedZoneWidth, fixedZoneLiveWidth ?? stored))
    }

    var minFixedZoneWidth: CGFloat { 220 }
    var maxFixedZoneWidth: CGFloat { 700 }

    var showsNotebookInlineActions: Bool {
        false
    }

    @ViewBuilder
    func notebookCommandMenuContent(data: NotebookUiStateData, tabs: [NotebookTab], rows: [NotebookTableRow]) -> some View {
        if !rows.isEmpty {
            Button {
                requestMarkAllVisibleStudentsPresent(data: data)
            } label: {
                Label("Marcar visibles presentes", systemImage: "checkmark.circle")
            }
        }

        Menu("Vista") {
            Button {
                surfaceMode = .grid
            } label: {
                Label("Grid", systemImage: surfaceMode == .grid ? "checkmark" : "tablecells")
            }

            Button {
                surfaceMode = .seatingPlan
            } label: {
                Label("Plano", systemImage: surfaceMode == .seatingPlan ? "checkmark" : "rectangle.3.group")
            }
            .disabled(focusMode != .normal)
        }

        Menu("Pestañas") {
            Button("Nueva pestaña") {
                presentCreateNotebookTab()
            }

            if let activeTab = activeNotebookTab(data: data) {
                Button("Renombrar \(activeTab.title)") {
                    presentRenameNotebookTab(activeTab)
                }
                Button("Eliminar \(activeTab.title)", role: .destructive) {
                    pendingDeleteNotebookTab = activeTab
                }
            }

            if tabs.count > 1 {
                Divider()
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        selectNotebookTab(tab.id)
                    } label: {
                        Label(tab.title, systemImage: tab.id == activeNotebookTabId(data: data) ? "checkmark" : "rectangle.on.rectangle")
                    }
                }
            }
        }

        if isCompact, !relevantCategories(data: data).isEmpty {
            Menu("Categorías") {
                Button("Nueva categoría") {
                    presentCreateCategory()
                }

                ForEach(relevantCategories(data: data), id: \.id) { category in
                    Button(isCategoryCollapsed(category) ? "Expandir \(category.name)" : "Colapsar \(category.name)") {
                        setCategoryCollapsed(category, collapsed: !isCategoryCollapsed(category))
                    }
                }
            }
        }

        if focusMode == .normal {
            Button {
                notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: nil)
            } label: {
                Label("Generar síntesis", systemImage: "apple.intelligence")
            }
            .disabled(data.sheet.rows.isEmpty || data.sheet.columns.filter(isNotebookIndividualSummaryColumn).isEmpty)
        }

        ShareLink(item: exportText(data: data)) {
            Label("Exportar cuaderno", systemImage: "square.and.arrow.up")
        }
    }

    func snapFixedZoneWidth() {
        let snapPoints: [CGFloat] = [220, 360, 460, 580]
        let current = fixedZoneWidth
        let snappedWidth: CGFloat
        if let nearest = snapPoints.min(by: { abs($0 - current) < abs($1 - current) }),
           abs(nearest - current) < 30 {
            snappedWidth = nearest
        } else {
            snappedWidth = current
        }
        withAnimation(.spring(duration: 0.2, bounce: 0.15)) {
            fixedZoneLiveWidth = snappedWidth
            if let data = bridge.notebookState as? NotebookUiStateData,
               let tabId = activeNotebookTabId(data: data) {
                bridge.saveTabFixedWidth(tabId: tabId, widthDp: Double(snappedWidth))
            } else {
                fixedZoneWidthStored = Double(snappedWidth)
            }
            fixedZoneLiveWidth = nil
        }
    }

    func segmentWidth(_ segment: NotebookDisplaySegment) -> CGFloat {
        gridLayoutModel.segmentWidth(segment, fixedZoneWidth: fixedZoneWidth)
    }

    func resolvedFixedWidth(for fixed: NotebookFixedColumn) -> CGFloat {
        gridLayoutModel.resolvedFixedWidth(for: fixed, fixedZoneWidth: fixedZoneWidth)
    }

    func defaultFixedWidth(for fixed: NotebookFixedColumn) -> CGFloat {
        gridLayoutModel.defaultFixedWidth(for: fixed)
    }

    func resolvedColumnWidth(for column: NotebookColumnDefinition) -> CGFloat {
        gridLayoutModel.resolvedColumnWidth(for: column)
    }

    @ViewBuilder
    func notebookLoadedContent(data: NotebookUiStateData) -> some View {
        let content = Group {
            switch macPresentation {
            case .full, .content:
                centerPanel(data: data)
            case .inspector:
                inspectorPanel(data: data, rows: filteredRows(data: data))
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430, maxHeight: .infinity)
                    .background(NotebookStyle.surfaceMuted)
            }
        }

        if isMacInspectorOnly {
            content
        } else {
            content
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
                .sheet(isPresented: $isAverageConfigurationPresented) {
                    NotebookAverageEditorSheet(
                        classTitle: activeClassLabel,
                        columns: data.sheet.columns,
                        rows: data.sheet.rows
                    ) { updates in
                        saveAverageConfiguration(updates)
                    }
                    #if os(macOS)
                    .frame(width: 560, height: 640)
                    #else
                    .presentationDetents([.large])
                    #endif
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
                .sheet(isPresented: Binding(
                    get: { isRubricEvaluationPresented },
                    set: { isPresented in
                        if !isPresented {
                            resetPendingRubricSequence()
                            bridge.closeRubricEvaluation()
                        }
                    }
                )) {
                    RubricEvaluationView()
                        .environmentObject(bridge)
                        #if os(macOS)
                        .frame(minWidth: 980, minHeight: 700)
                        #else
                        .presentationDetents([.large])
                        #endif
                }
                .sheet(isPresented: Binding(
                    get: { !shouldUseSideInspector && isInspectorPresented },
                    set: { isPresented in
                        if !isPresented {
                            closeInspectorAndTransientState()
                        }
                    }
                )) {
                    #if os(iOS)
                    inspectorPanel(data: data, rows: filteredRows(data: data))
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    #endif
                }
                .navigationTitle("Cuaderno")
                .notebookNavigationSubtitle(notebookNavigationSubtitle(data: data))
                .notebookKeyboardNavigation {
                    navigateFromFocused(direction: navigationDirection, data: data)
                }
                .onAppear {
                    scheduleActiveNotebookTabSync(data: data)
                    scheduleToolbarStateSync(data: data)
                }
                .appOnChange(of: "\(data.sheet.classId)") { _ in
                    resetNotebookTransientStateForClassChange()
                }
                .appOnChange(of: notebookTabsStateKey(data: data)) { _ in
                    scheduleActiveNotebookTabSync(data: data)
                }
                .appOnChange(of: toolbarStateKey(data: data)) { _ in
                    scheduleToolbarStateSync(data: data)
                }
                .appOnChange(of: bridge.rubricEvaluationState.isSaveSuccessful) { saved in
                    guard saved, bridge.isNotebookRubricAutoAdvanceActive else { return }
                    openNextRubricStudentIfPossible()
                }
        }
    }

    var isRubricEvaluationPresented: Bool {
        guard !bridge.showingBulkRubricEvaluation else { return false }
        return bridge.rubricEvaluationState.isLoading ||
            bridge.rubricEvaluationState.rubricDetail != nil ||
            bridge.rubricEvaluationState.error != nil
    }

    @ViewBuilder
    func addColumnSheetPresentation(for context: NotebookAddColumnContext) -> some View {
        let content = AddColumnSheet(
            bridge: bridge,
            initialCategoryId: context.categoryId,
            startsCreatingCategory: context.startsCreatingCategory,
            onCreatedColumn: { columnId in
                handleCreatedColumn(columnId)
            },
            onCreatedSummaryColumn: { columnId in
                handleCreatedSummaryColumn(columnId)
            }
        )

        #if os(macOS)
        content
            .frame(minWidth: 520, idealWidth: 560, maxWidth: 640, minHeight: 560, idealHeight: 620)
        #else
        content
            .presentationDetents([.large])
        #endif
    }

    func handleCreatedColumn(_ columnId: String) {
        highlightedColumnId = columnId
        if let data = bridge.notebookState as? NotebookUiStateData,
           let column = data.sheet.columns.first(where: { $0.id == columnId }) {
            highlightedCategoryId = column.categoryId
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if highlightedColumnId == columnId {
                highlightedColumnId = nil
            }
            if let data = bridge.notebookState as? NotebookUiStateData,
               highlightedCategoryId == data.sheet.columns.first(where: { $0.id == columnId })?.categoryId {
                highlightedCategoryId = nil
            }
        }
    }

    func handleCreatedSummaryColumn(_ columnId: String) {
        highlightedColumnId = columnId
        let availability = contextualAIOrchestrator.availability()
        if !availability.isAvailable {
            showToast("Columna creada. La generación IA no está disponible en este dispositivo.", style: .warning)
        }

        Task { @MainActor in
            var attempts = 0
            while attempts < 20 {
                if let data = bridge.notebookState as? NotebookUiStateData,
                   data.sheet.columns.contains(where: { $0.id == columnId }) {
                    await Task.yield()
                    notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: columnId)
                    return
                }

                attempts += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            showToast(
                "Columna creada, pero no se pudo abrir la generación automática. Usa “Generar síntesis…” desde el menú.",
                style: .warning
            )
        }
    }

    @ViewBuilder
    func formulaEditorSheet(request: NotebookFormulaEditRequest, data: NotebookUiStateData) -> some View {
        if let column = data.sheet.columns.first(where: { $0.id == request.columnId }) {
            NotebookFormulaEditorSheet(
                column: column,
                referenceColumns: formulaReferenceColumns(for: column, data: data),
                allColumns: data.sheet.columns,
                rows: data.sheet.rows,
                formula: $formulaDraft,
                aiPrompt: $formulaAIPrompt,
                aiMessage: $formulaAIMessage,
                isAIGenerating: isFormulaAIGenerating,
                onGenerateAI: { generateFormulaWithAI(column: column, data: data) },
                onCancel: { formulaEditRequest = nil },
                onSave: { saveFormula(column) }
            )
        } else {
            Text("No se encontró la columna")
                .padding()
        }
    }

    func formulaReferenceColumns(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        visibleNotebookSourceColumns(data: data)
            .filter { $0.id != column.id }
    }

    func notebookNavigationSubtitle(data: NotebookUiStateData) -> String {
        let context = headerContextLine(in: data)
        let studentCount = filteredRows(data: data).count
        return "\(context) · \(studentCount) alumnos"
    }

    func gridRowInvalidationKey(data: NotebookUiStateData) -> String {
        [
            inspectorSelection?.id ?? "none",
            "\(isAttendanceQuickMode)",
            "\(cellReloadRevision)",
            activeChoiceCellId ?? "none",
            focusedCellId ?? "none",
            "columns:\(data.sheet.columns.count)",
            "rows:\(data.sheet.rows.count)"
        ].joined(separator: "¬")
    }

    func notebookTabsStateKey(data: NotebookUiStateData) -> String {
        data.sheet.tabs
            .sorted { $0.id < $1.id }
            .map { "\($0.id)|\($0.title)|\($0.order)|\($0.parentTabId ?? "")" }
            .joined(separator: "¬")
    }

    func notebookAISheet(request: NotebookAISheetRequest, data: NotebookUiStateData) -> some View {
        NotebookAICommentSheet(
            bridge: bridge,
            data: data,
            managedColumns: notebookEvidenceSourceColumns(notebookSourceColumns(data: data)),
            visibleColumns: notebookEvidenceSourceColumns(visibleNotebookSourceColumns(data: data)),
            selectedStudentIds: request.studentIds,
            targetColumnId: request.targetColumnId,
            mode: request.mode
        ) { message, style in
            showToast(message, style: style)
        }
    }

    func inspectorPanel(data: NotebookUiStateData, rows: [NotebookTableRow]) -> some View {
        NotebookInspectorPanel(
            bridge: bridge,
            data: data,
            rows: rows,
            currentClassId: currentClass?.id,
            semanticIcons: semanticInspectorIcons,
            auditEvents: currentSelectionAuditEvents,
            inspectorSelection: inspectorSelectionBinding,
            isInspectorPresented: isInspectorPresentedBinding,
            inspectorNoteDraft: inspectorNoteDraftBinding,
            inspectorIconDraft: inspectorIconDraftBinding,
            inspectorAttachmentUris: inspectorAttachmentUrisBinding,
            selectedAttachmentPhoto: $selectedAttachmentPhoto,
            displayValue: { item, column in
                displayValue(for: item, column: column)
            },
            categoryTitle: { column, data in
                categoryTitle(for: column, data: data)
            },
            evidenceLabel: { persistedCell in
                evidenceLabel(for: persistedCell)
            },
            formattedDate: { epochMs in
                formattedDate(epochMs)
            },
            evaluationTitle: { column in
                evaluationTitle(for: column)
            },
            rubricTitle: { column in
                rubricTitle(for: column)
            },
            isSummaryColumn: { column in
                isNotebookIndividualSummaryColumn(column)
            },
            onOpenModule: onOpenModule,
            onSelectStudent: { studentId in
                selectedStudentId = studentId
            },
            onRegenerateSummary: { columnId in
                notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: columnId)
            },
            onRegenerateAI: { request in
                notebookAISheetRequest = request
            },
            onSaveContext: {
                cellReloadRevision += 1
            }
        )
    }

}
