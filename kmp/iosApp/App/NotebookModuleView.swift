import SwiftUI
import PhotosUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum NotebookToolbarMode {
    case inlineCompact
    case shellOwned
    case macWindowOwned
    case macShellOwned
    case hidden
}

struct NotebookModuleView: View {
    @State var isCompactViewActive = false

    #if os(macOS)
    var notebookGridRowHeight: CGFloat {
        isCompactViewActive ? 38 : 50
    }
    #else
    var notebookGridRowHeight: CGFloat {
        isCompactViewActive ? 40 : (isCompact ? 56 : 52)
    }
    #endif
    let notebookGridHeaderHeight: CGFloat = 56
    let notebookGridFolderLaneHeight: CGFloat = 34

    @EnvironmentObject var layoutState: WorkspaceLayoutState
    @Environment(\.uiFeatureFlags) var uiFeatureFlags
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    let bridge: KmpBridge
    @ObservedObject var notebookStore: NotebookBridgeStore
    @ObservedObject var dashboardStore: DashboardBridgeStore
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
    @State var isSearchPresented = false
    @State var selectedGroupId: Int64? = nil
    @State var selectedColumnId: String? = nil
    @State var viewPreset: NotebookViewPreset = .all
    @State var surfaceMode: NotebookSurfaceMode = .grid
    @State var todayAttendanceByStudentId: [Int64: String] = [:]
    @State var incidentCountByStudentId: [Int64: Int] = [:]
    @State var activeSupportMeasureStudentIds: Set<Int64> = []
    @State var localInjuryStatuses: [Int64: Bool] = [:]
    @State var seatPositions: [Int64: NotebookSeatPosition] = [:]
    @State var highlightedRandomStudentId: Int64? = nil
    @State var seatingGradingColumnId: String? = nil
    @StateObject var voiceGradeDictationService = NotebookVoiceGradeDictationService()
    @State var selectedAttachmentPhoto: PhotosPickerItem?
    @State var isCreateCategoryAlertPresented = false
    @State var isGroupManagementPresented = false
    @State var classSituations: [LearningSituation] = []
    @AppStorage("notebook.groupByWorkGroupMode") var groupByWorkGroupMode = "none"
    var groupByWorkGroup: Bool {
        groupByWorkGroupMode != "none"
    }
    /// Color semántico de nota + heat de celda (rediseño radical del grid).
    /// Toggle propio en el menú de acciones; `NotebookStatefulEditableTableCell`
    /// lee la misma clave con su propio `@AppStorage` (ver `NotebookGridStyle`).
    @AppStorage(NotebookGridStyle.semanticGradeColorDefaultsKey) var semanticGradeColorEnabled = true
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
    @State var isFillColumnDialogPresented = false
    @State var pendingCopyTabStructureSource: NotebookTab? = nil
    @State var undoStack: [NotebookCellUndoEntry] = []
    @State var structuralGridRevision = 0
    @State var rowReloadRevisions: [Int64: Int] = [:]
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
    @AppStorage("notebook.fixedZoneWidth") var fixedZoneWidthStored = 240.0
    @State var isDraggingFixedZoneDivider = false
    @State var fixedZoneDragStartWidth: CGFloat = 0
    @State var fixedZoneLiveWidth: CGFloat? = nil
    @State var formulaEditRequest: NotebookFormulaEditRequest? = nil
    @State var structuredInstrumentRequest: StructuredInstrumentEvaluationRequest? = nil
    @State var formulaDraft = ""
    @State var formulaAIPrompt = ""
    @State var formulaAIMessage: String? = nil
    @State var isFormulaAIGenerating = false
    @State var activeChoiceCellId: String? = nil
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
        notebookStore: NotebookBridgeStore,
        dashboardStore: DashboardBridgeStore,
        selectedClassId: Binding<Int64?>,
        selectedStudentId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void,
        toolbarMode: NotebookToolbarMode = .inlineCompact,
        macPresentation: NotebookMacPresentation = .full,
        macInspectorState: NotebookMacInspectorState? = nil,
        macToolbarActions: NotebookMacToolbarActions? = nil
    ) {
        self.bridge = bridge
        self.notebookStore = notebookStore
        self.dashboardStore = dashboardStore
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
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
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
        selectedColumnId = nil
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
        selectedColumnId = nil
        highlightedRandomStudentId = nil
        activeChoiceCellId = nil
        focusedCellId = nil
        focusMode = .normal
        searchText = ""

        undoStack = []
        todayAttendanceByStudentId = [:]
        incidentCountByStudentId = [:]
        localInjuryStatuses = [:]
        seatPositions = [:]
        seatingGradingColumnId = nil
        activeSupportMeasureStudentIds = []
        riskLevelCache = [:]
        riskComputationKey = nil
        isPrecomputingRiskLevels = false

        formulaDraft = ""
        expandedEmptyCategoryIds = []
        pendingRubricColumnId = nil
        pendingRubricStudentOrder = []
        pendingRubricCurrentStudentId = nil

        rowReloadRevisions = [:]
        structuralGridRevision += 1
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
            get: { nil },
            set: { _ in }
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
                        isInspectorPresented: isInspectorPresented,
                        canUndo: !undoStack.isEmpty,
                        isAttendanceQuickMode: isAttendanceQuickMode,
                        showsAdvancedActions: focusMode == .normal,
                        selectionContext: toolbarSelectionContext(data: data),
                        onAddColumn: {
                            addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
                        },
                        onSearch: {
                            presentNotebookSearch()
                        },
                        onCopySelection: {
                            copySelectedCell(data: data)
                        },
                        onPasteSelection: {
                            pasteIntoSelectedCell(data: data)
                        },
                        onFillSelection: {
                            requestFillColumnFromSelectedCell(data: data)
                        },
                        onClearSelection: {
                            clearSelectedCell(data: data)
                        },
                        onCommentSelection: {
                            openCommentForSelectedCell(data: data)
                        },
                        isVoiceDictationActive: voiceGradeDictationService.isListening,
                        onToggleVoiceDictation: {
                            toggleVoiceGradeDictation(data: data)
                        },
                        onEditColumn: {
                            editSelectedColumn(data: data)
                        },
                        onHideColumn: {
                            hideSelectedColumn(data: data)
                        },
                        onDuplicateColumn: {
                            duplicateSelectedColumn(data: data)
                        },
                        onReorderColumn: {
                            isOrganizationMenuPresented = true
                        },
                        onToggleColumnAverage: {
                            toggleSelectedColumnAverage(data: data)
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
                        onOpenGroupManagement: {
                            isGroupManagementPresented = true
                        },
                        filters: {
                            notebookFilterMenuContent(data: data)
                        },
                        secondaryActions: {
                            notebookCommandMenuContent(data: data, tabs: tabs, rows: rows)
                        }
                    )
                }
                if !tabs.isEmpty && focusMode == .normal {
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
                }
                spreadsheetContent(data: data, rows: rows)
                    // Tarjeta elevada: el grid flota como superficie redondeada
                    // sobre el lienzo neutro del módulo (margen a los lados y
                    // abajo), en vez de ir a sangre completa. Es lo que da el aire
                    // premium; el clip + borde + sombra separan datos de lienzo.
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(NotebookGridStyle.gridLine, lineWidth: 1)
                    )
                    .shadow(color: NotebookGridStyle.gridSurfaceShadow, radius: 14, x: 0, y: 6)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if shouldUseSideInspector && macPresentation == .full && isInspectorPresented {
                Divider().opacity(0.16)
                inspectorPanel(data: data, rows: rows)
                    .frame(width: 360)
                    .background(.ultraThinMaterial)
            }
        }
        .background(NotebookCanvasBackground())
        .onAppear {
            gridLayoutModel.configure(classId: data.sheet.classId)
            loadClassLearningSituations(classId: data.sheet.classId)
            if !isMacInspectorOnly {
                scheduleToolbarStateSync(data: data)
            }
        }
        .appOnChange(of: "\(data.sheet.classId)") { newValue in
            resetNotebookTransientStateForClassChange()
            gridLayoutModel.configure(classId: data.sheet.classId)
            if let classId = Int64(newValue) {
                loadClassLearningSituations(classId: classId)
            }
            Task { await refreshNotebookSignals() }
        }
        .appOnChange(of: toolbarStateKey(data: data)) { _ in
            if !isMacInspectorOnly {
                scheduleToolbarStateSync(data: data)
            }
        }
    }

    @ViewBuilder
    func spreadsheetContent(data: NotebookUiStateData, rows: [NotebookTableRow]) -> some View {
        let renderModel = gridLayoutModel.renderModel(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset,
            isCompact: isCompact
        )
        let trailingPaddingCompensation = NotebookStyle.outerPadding * 2
        let shouldShowFolderLane = renderModel.hasGroupedHeaders

        NotebookGridContent(
            rows: rows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedZoneWidth,
            trailingFixedColumnWidth: renderModel.trailingFixedSegments.isEmpty ? 0 : defaultFixedWidth(for: .average) + trailingPaddingCompensation,
            isFixedColumnResizing: isDraggingFixedZoneDivider,
            topAccessoryHeight: shouldShowFolderLane ? notebookGridFolderLaneHeight : 0,
            headerHeight: notebookGridHeaderHeight,
            rowHeight: notebookGridRowHeight,
            structuralInvalidationKey: gridStructuralInvalidationKey(data: data),
            rowReloadRevisions: rowReloadRevisions,
            transientCellIds: transientGridCellIds,
            fixedSegments: renderModel.fixedSegments,
            trailingFixedSegments: renderModel.trailingFixedSegments,
            scrollableSegments: renderModel.scrollableSegments
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
                gradableColumns: gradableSeatingColumns(data: data),
                gradingColumnId: $seatingGradingColumnId,
                gradeText: { studentId in
                    guard let columnId = seatingGradingColumnId,
                          let column = data.sheet.columns.first(where: { $0.id == columnId }),
                          let row = rows.first(where: { $0.student.id == studentId }) else { return "—" }
                    let value = displayValue(for: row, column: column)
                    return value.isEmpty ? "—" : value
                },
                onAdjustGrade: { studentId, delta in
                    guard let columnId = seatingGradingColumnId,
                          let column = data.sheet.columns.first(where: { $0.id == columnId }) else { return }
                    adjustSeatingGrade(studentId: studentId, column: column, delta: delta, data: data)
                },
                onHighlightRandomStudent: {
                    highlightedRandomStudentId = randomEligibleStudentId(from: rows, data: data)
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
                        ForEach(renderModel.laneItems, id: \.id) { item in
                            switch item {
                            case .spacer(_, let width):
                                Color.clear
                                    .frame(width: width, height: 1)
                            case .folder(let category, _, let width):
                                categoryFolderHeader(category: category, data: data, width: width)
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
                    updateFixedZoneDragState(isDragging: true)
                    fixedZoneDragStartWidth = fixedZoneWidth
                }
                let newWidth = fixedZoneDragStartWidth + translationWidth
                updateFixedZoneLiveWidth(newWidth)
            } onDragEnded: {
                updateFixedZoneDragState(isDragging: false)
                snapFixedZoneWidth()
            } onResetWidth: {
                restoreRecommendedFixedZoneWidth()
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
                navigableSegments: renderModel.scrollableSegments
            )
        }
    }

    @ViewBuilder
    func headerRow(segments: [NotebookDisplaySegment], data: NotebookUiStateData) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(segments, id: \.id) { segment in
                headerChip(for: segment, data: data)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: notebookGridHeaderHeight, alignment: .topLeading)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotebookGridStyle.gridLineStrong)
                .frame(height: 1)
        }
    }

    var activeTabFixedWidth: CGFloat? {
        if let data = notebookStore.notebookState as? NotebookUiStateData,
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

    var minFixedZoneWidth: CGFloat {
        let visible = gridLayoutModel.visibleFixedColumns
        let photoWidth: CGFloat = visible.contains(.photo) ? 52 : 0
        let nameWidth: CGFloat = 156
        let trailingWidth = visible.filter { $0 != .photo && $0 != .name }.reduce(CGFloat.zero) { partial, col in
            partial + gridLayoutModel.defaultFixedWidth(for: col)
        }
        let spacing = CGFloat(max(visible.count - 1, 0)) * NotebookStyle.controlSpacing
        let calculated = nameWidth + photoWidth + trailingWidth + spacing + 32 // Padding horizontal (16 * 2)
        return max(220, calculated)
    }
    var maxFixedZoneWidth: CGFloat { 700 }
 
    func loadClassLearningSituations(classId: Int64) {
        Task {
            do {
                let situations = try await bridge.learningSituations()
                var filtered: [LearningSituation] = []
                for sit in situations {
                    let links = try await bridge.learningSituationClassLinks(id: sit.id)
                    if links.contains(where: { $0.classId == classId }) {
                        filtered.append(sit)
                    }
                }
                let finalFiltered = filtered
                await MainActor.run {
                    self.classSituations = finalFiltered
                }
            } catch {
                // ignore
            }
        }
    }

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

        Toggle(isOn: $semanticGradeColorEnabled) {
            Label("Colorear notas por banda", systemImage: "paintpalette")
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

                let otherTabs = tabs.filter { $0.id != activeNotebookTabId(data: data) }
                if !otherTabs.isEmpty {
                    Divider()
                    Menu("Copiar estructura desde…") {
                        ForEach(otherTabs, id: \.id) { tab in
                            Button(tab.title) {
                                requestCopyTabStructure(from: tab)
                            }
                        }
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

    @ViewBuilder
    func notebookFilterMenuContent(data: NotebookUiStateData) -> some View {
        let groups = groupedRows(data: data)
        if groups.isEmpty && classSituations.isEmpty {
            Button("Sin filtros disponibles") {}
                .disabled(true)
        } else {
            if !groups.isEmpty {
                Menu {
                    Button("Grupo completo") {
                        selectedGroupId = nil
                    }
                    ForEach(groups, id: \.id) { group in
                        Button {
                            selectedGroupId = group.id
                        } label: {
                            Label(
                                "\(group.name) (\(memberCount(group.id, in: data)) alumnos)",
                                systemImage: selectedGroupId == group.id ? "checkmark" : "person.2"
                            )
                        }
                    }
                } label: {
                    Label("Grupo", systemImage: "person.2")
                }
            }

            if !classSituations.isEmpty {
                Menu {
                    Button("Sin filtrar") {
                        groupByWorkGroupMode = "none"
                    }
                    ForEach(classSituations, id: \.id) { situation in
                        Button {
                            let targetMode = "situation_\(situation.id)"
                            groupByWorkGroupMode = groupByWorkGroupMode == targetMode ? "none" : targetMode
                        } label: {
                            Label(
                                situation.title,
                                systemImage: groupByWorkGroupMode == "situation_\(situation.id)" ? "checkmark" : "folder"
                            )
                        }
                    }
                } label: {
                    Label("Situación de aprendizaje", systemImage: "folder")
                }
            }
        }
    }

    func toolbarSelectionContext(data: NotebookUiStateData) -> NotebookToolbarSelectionContext {
        if selectedNotebookColumn(data: data) != nil {
            return .column
        }
        if selectedNotebookCell(data: data) != nil {
            return .cells
        }
        return .none
    }

    @ViewBuilder
    func nativeContextualToolbarActions(data: NotebookUiStateData) -> some View {
        switch toolbarSelectionContext(data: data) {
        case .none:
            Button {
                addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
            } label: {
                Label("Columna", systemImage: "plus")
            }
            .help("Añadir nueva columna de evaluación")

            Button {
                presentNotebookSearch()
            } label: {
                Label("Buscar", systemImage: "magnifyingglass")
            }
            .help("Buscar alumnado o columnas")

            Menu {
                notebookFilterMenuContent(data: data)
            } label: {
                Label("Filtros", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filtros del cuaderno")
        case .cells:
            Button {
                copySelectedCell(data: data)
            } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }

            Button {
                pasteIntoSelectedCell(data: data)
            } label: {
                Label("Pegar", systemImage: "clipboard")
            }

            Button {
                showToast("Selecciona un rango para rellenar varias celdas", style: .warning)
            } label: {
                Label("Rellenar", systemImage: "arrow.down.to.line")
            }

            Button {
                clearSelectedCell(data: data)
            } label: {
                Label("Borrar", systemImage: "eraser")
            }

            Button {
                openCommentForSelectedCell(data: data)
            } label: {
                Label("Comentario", systemImage: "text.bubble")
            }
        case .column:
            Button {
                editSelectedColumn(data: data)
            } label: {
                Label("Editar", systemImage: "pencil")
            }

            Button {
                hideSelectedColumn(data: data)
            } label: {
                Label("Ocultar", systemImage: "eye.slash")
            }

            Button {
                duplicateSelectedColumn(data: data)
            } label: {
                Label("Duplicar", systemImage: "plus.square.on.square")
            }

            Button {
                isOrganizationMenuPresented = true
            } label: {
                Label("Reordenar", systemImage: "arrow.up.arrow.down")
            }

            Button {
                toggleSelectedColumnAverage(data: data)
            } label: {
                Label("Media", systemImage: "percent")
            }
        }
    }

    func presentNotebookSearch() {
        if toolbarMode == .inlineCompact {
            isSearchPresented = true
        } else {
            NotificationCenter.default.post(name: .appleAppSearchRequested, object: nil)
        }
    }

    func selectedNotebookColumn(data: NotebookUiStateData) -> NotebookColumnDefinition? {
        guard let selectedColumnId else { return nil }
        return data.sheet.columns.first { $0.id == selectedColumnId }
    }

    func selectedNotebookCell(data: NotebookUiStateData) -> (selection: NotebookInspectorSelection, row: NotebookTableRow, column: NotebookColumnDefinition)? {
        guard let selection = inspectorSelection,
              !selection.isAverage,
              let row = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }),
              let column = data.sheet.columns.first(where: { $0.id == selection.columnId }) else {
            return nil
        }
        return (selection, row, column)
    }

    func copySelectedCell(data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        setClipboardText(displayValue(for: selected.row, column: selected.column))
        showToast("Celda copiada")
    }

    func pasteIntoSelectedCell(data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data),
              let rawClipboard = clipboardText() else { return }
        guard isToolbarEditableCellColumn(selected.column) else {
            showToast("Esta columna se edita desde su acción específica", style: .warning)
            return
        }

        let pastedValues = notebookClipboardColumnValues(from: rawClipboard)
        guard pastedValues.count > 1 else {
            let value = pastedValues.first ?? rawClipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            recordCellUndo(
                studentId: selected.selection.studentId,
                column: selected.column,
                previousValue: displayValue(for: selected.row, column: selected.column),
                previousDisplayLabel: nil
            )
            bridge.saveColumnGrade(studentId: selected.selection.studentId, column: selected.column, value: value)
            reloadNotebookRow(selected.selection.studentId)
            showToast("Celda pegada")
            return
        }

        // Pegado de varias filas (p. ej. una columna copiada de una hoja de cálculo):
        // se aplica desde la celda seleccionada hacia abajo, fila a fila.
        let rows = filteredRows(data: data)
        guard let startIndex = rows.firstIndex(where: { $0.student.id == selected.selection.studentId }) else { return }
        let targetRows = rows[startIndex...]

        var pastedCount = 0
        for (row, value) in zip(targetRows, pastedValues) {
            let previousValue = displayValue(for: row, column: selected.column)
            guard previousValue != value else { continue }
            recordCellUndo(
                studentId: row.student.id,
                column: selected.column,
                previousValue: previousValue,
                previousDisplayLabel: nil
            )
            bridge.saveColumnGrade(studentId: row.student.id, column: selected.column, value: value)
            reloadNotebookRow(row.student.id)
            pastedCount += 1
        }
        let skippedCount = max(0, pastedValues.count - targetRows.count)
        if skippedCount > 0 {
            showToast("Pegadas \(pastedCount) celdas (\(skippedCount) valores no cupieron en las filas visibles)", style: .warning)
        } else {
            showToast(pastedCount > 0 ? "Pegadas \(pastedCount) celdas" : "Sin cambios: los valores ya coincidían")
        }
    }

    private func notebookClipboardColumnValues(from rawClipboard: String) -> [String] {
        var lines = rawClipboard
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                let firstColumn = line.components(separatedBy: "\t").first ?? line
                return firstColumn.trimmingCharacters(in: .whitespaces)
            }
        // Las apps de hojas de cálculo suelen añadir una línea vacía final al copiar.
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    func clearSelectedCell(data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        guard isToolbarEditableCellColumn(selected.column) else {
            showToast("Esta columna se edita desde su acción específica", style: .warning)
            return
        }
        recordCellUndo(
            studentId: selected.selection.studentId,
            column: selected.column,
            previousValue: displayValue(for: selected.row, column: selected.column),
            previousDisplayLabel: nil
        )
        bridge.saveColumnGrade(studentId: selected.selection.studentId, column: selected.column, value: "")
        reloadNotebookRow(selected.selection.studentId)
        showToast("Celda borrada")
    }

    func openCommentForSelectedCell(data: NotebookUiStateData) {
        guard selectedNotebookCell(data: data) != nil else { return }
        isInspectorPresented = true
        focusMode = .reviewing
        syncInspectorDraft()
    }

    func editSelectedColumn(data: NotebookUiStateData) {
        guard let column = selectedNotebookColumn(data: data) else { return }
        editingColumnId = column.id
        columnDraft = column.title
        isRenameColumnAlertPresented = true
    }

    func hideSelectedColumn(data: NotebookUiStateData) {
        guard let column = selectedNotebookColumn(data: data) else { return }
        toggleColumnVisibility(column)
    }

    func duplicateSelectedColumn(data: NotebookUiStateData) {
        guard let column = selectedNotebookColumn(data: data) else { return }
        duplicateColumnStructure(column)
    }

    func toggleSelectedColumnAverage(data: NotebookUiStateData) {
        guard let column = selectedNotebookColumn(data: data) else { return }
        saveColumnMutation(
            column,
            countsTowardAverage: !column.countsTowardAverage,
            weight: column.countsTowardAverage ? 0 : max(column.weight, 1)
        )
        showToast(column.countsTowardAverage ? "Columna excluida de la media" : "Columna incluida en la media")
    }

    func isToolbarEditableCellColumn(_ column: NotebookColumnDefinition) -> Bool {
        column.type != .calculated && column.type != .rubric
    }

    func setClipboardText(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    func clipboardText() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
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
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            fixedZoneLiveWidth = snappedWidth
            if let data = notebookStore.notebookState as? NotebookUiStateData,
               let tabId = activeNotebookTabId(data: data) {
                bridge.saveTabFixedWidth(tabId: tabId, widthDp: Double(snappedWidth))
            } else {
                fixedZoneWidthStored = Double(snappedWidth)
            }
            fixedZoneLiveWidth = nil
        }
    }

    func restoreRecommendedFixedZoneWidth() {
        let recommendedWidth: CGFloat = 360
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            fixedZoneLiveWidth = recommendedWidth
            if let data = notebookStore.notebookState as? NotebookUiStateData,
               let tabId = activeNotebookTabId(data: data) {
                bridge.saveTabFixedWidth(tabId: tabId, widthDp: Double(recommendedWidth))
            } else {
                fixedZoneWidthStored = Double(recommendedWidth)
            }
            fixedZoneLiveWidth = nil
        }
        AppleInteractionFeedback.play(.lightImpact)
    }

    func updateFixedZoneDragState(isDragging: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            isDraggingFixedZoneDivider = isDragging
        }
    }

    func updateFixedZoneLiveWidth(_ proposedWidth: CGFloat) {
        let clamped = min(maxFixedZoneWidth, max(minFixedZoneWidth, proposedWidth))
        let quantized = (clamped / 2).rounded() * 2
        guard fixedZoneLiveWidth != quantized else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            fixedZoneLiveWidth = quantized
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
        let baseContent = Group {
            switch macPresentation {
            case .full, .content:
                centerPanel(data: data)
            case .inspector:
                inspectorPanel(data: data, rows: filteredRows(data: data))
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }

        let content = Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                baseContent
                    .sheet(item: $averageExplanationRow) { row in
                        NavigationStack {
                            CustomAverageExplanationPopoverView(
                                studentName: "\(row.student.firstName) \(row.student.lastName)",
                                explanation: row.row.averageExplanation,
                                columns: data.sheet.columns,
                                onClose: {
                                    averageExplanationRow = nil
                                }
                            )
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Hecho") {
                                        averageExplanationRow = nil
                                    }
                                }
                            }
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
            } else {
                baseContent
                    .popover(item: $averageExplanationRow) { row in
                        CustomAverageExplanationPopoverView(
                            studentName: "\(row.student.firstName) \(row.student.lastName)",
                            explanation: row.row.averageExplanation,
                            columns: data.sheet.columns,
                            onClose: {
                                averageExplanationRow = nil
                            }
                        )
                        .frame(width: 360, height: 500)
                    }
            }
            #else
            baseContent
                .popover(item: $averageExplanationRow) { row in
                    CustomAverageExplanationPopoverView(
                        studentName: "\(row.student.firstName) \(row.student.lastName)",
                        explanation: row.row.averageExplanation,
                        columns: data.sheet.columns,
                        onClose: {
                            averageExplanationRow = nil
                        }
                    )
                    .frame(width: 360, height: 500)
                }
            #endif
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
                .sheet(item: $structuredInstrumentRequest) { request in
                    StructuredInstrumentEvaluationSheet(
                        bridge: bridge,
                        request: request,
                        onSaved: {
                            reloadNotebookRow(request.studentId)
                            showToast("Instrumento guardado", style: .success)
                        },
                        onClose: {
                            structuredInstrumentRequest = nil
                        }
                    )
                    #if os(macOS)
                    .frame(minWidth: 680, minHeight: 620)
                    #else
                    .presentationDetents([.large])
                    #endif
                }
                .sheet(isPresented: $isGroupManagementPresented) {
                    NotebookGroupManagementSheet(bridge: bridge) { message, style in
                        showToast(message, style: style)
                    }
                    #if os(macOS)
                    .frame(minWidth: 550, minHeight: 480)
                    #endif
                }
                .appFullScreenCover(isPresented: Binding(
                    get: { notebookStore.showingBulkRubricEvaluation },
                    set: { isPresented in
                        if !isPresented {
                            bridge.closeBulkRubricEvaluation()
                        }
                    }
                )) {
                    RubricBulkEvaluationSheet(bridge: bridge)
                        #if os(macOS)
                        .frame(width: 1180, height: 760)
                        #endif
                }
                .appFullScreenCover(isPresented: Binding(
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
                        .frame(minWidth: 1180, minHeight: 700)
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
                .notebookKeyboardNavigation {
                    navigateFromFocused(direction: navigationDirection, data: data)
                }
                .onAppear {
                    scheduleActiveNotebookTabSync(data: data)
                    scheduleToolbarStateSync(data: data)
                    Task { await refreshNotebookSignals() }
                }
                .appOnChange(of: layoutState.notebookHiddenColumnsRequestID) { requestID in
                    guard requestID != nil else { return }
                    isOrganizationMenuPresented = false
                    isHiddenColumnsSheetPresented = true
                }

                .appOnChange(of: notebookTabsStateKey(data: data)) { _ in
                    scheduleActiveNotebookTabSync(data: data)
                }
                .appOnChange(of: toolbarStateKey(data: data)) { _ in
                    scheduleToolbarStateSync(data: data)
                }
                .appOnChange(of: notebookStore.rubricEvaluationState.isSaveSuccessful) { saved in
                    guard saved, notebookStore.isNotebookRubricAutoAdvanceActive else { return }
                    openNextRubricStudentIfPossible()
                }
                .appOnChange(of: voiceGradeDictationService.errorMessage) { message in
                    guard let message else { return }
                    showToast(message, style: .warning)
                }
                .toolbar {
                    if toolbarMode == .shellOwned || toolbarMode == .macWindowOwned {
                        ToolbarItemGroup(placement: .primaryAction) {
                            nativeContextualToolbarActions(data: data)
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                // 1. Deshacer cambio
                                Button {
                                    undoLastCellChange()
                                } label: {
                                    Label("Deshacer cambio", systemImage: "arrow.uturn.backward")
                                }
                                .disabled(undoStack.isEmpty)
                                .keyboardShortcut("z", modifiers: .command)

                                // 1b. Rellenar columna con la celda seleccionada
                                Button {
                                    requestFillColumnFromSelectedCell(data: data)
                                } label: {
                                    Label("Rellenar columna", systemImage: "arrow.down.to.line")
                                }
                                .disabled(selectedNotebookCell(data: data) == nil)
                                .keyboardShortcut("d", modifiers: .command)

                                // 1c. Ciclar pestañas del cuaderno
                                Button {
                                    cycleNotebookTab(forward: true, data: data)
                                } label: {
                                    Label("Siguiente pestaña", systemImage: "chevron.right")
                                }
                                .disabled(orderedNotebookTabs(data: data).count < 2)
                                .keyboardShortcut("]", modifiers: [.command, .shift])

                                Button {
                                    cycleNotebookTab(forward: false, data: data)
                                } label: {
                                    Label("Pestaña anterior", systemImage: "chevron.left")
                                }
                                .disabled(orderedNotebookTabs(data: data).count < 2)
                                .keyboardShortcut("[", modifiers: [.command, .shift])

                                // 2. Asistencia rápida
                                Button {
                                    isAttendanceQuickMode.toggle()
                                    if isAttendanceQuickMode {
                                        activeChoiceCellId = nil
                                        focusedCellId = nil
                                    }
                                } label: {
                                    Label(isAttendanceQuickMode ? "Salir de asistencia rápida" : "Asistencia rápida",
                                          systemImage: isAttendanceQuickMode ? "figure.walk.circle.fill" : "figure.walk.circle")
                                }

                                // 3. Generar síntesis IA
                                Button {
                                    notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: nil)
                                } label: {
                                    Label("Generar síntesis IA", systemImage: "apple.intelligence")
                                }
                                .disabled(data.sheet.rows.isEmpty || data.sheet.columns.filter(isNotebookIndividualSummaryColumn).isEmpty)

                                // 4. Mostrar/Ocultar inspector
                                Button {
                                    if inspectorSelection == nil {
                                        openInspectorForSelection(data)
                                    }
                                    if inspectorSelection != nil {
                                        isInspectorPresented.toggle()
                                        focusMode = isInspectorPresented ? .reviewing : .normal
                                    }
                                } label: {
                                    Label(isInspectorPresented ? "Ocultar inspector" : "Mostrar inspector",
                                          systemImage: isInspectorPresented ? "sidebar.right" : "sidebar.squares.right")
                                }
                                .disabled(inspectorSelection == nil && managedColumns(data: data).isEmpty)
                                .keyboardShortcut("i", modifiers: [.command])

                                Divider()

                                // 5. Reordenar columnas (Organizar columnas)
                                Button {
                                    isOrganizationMenuPresented = true
                                } label: {
                                    Label("Reordenar columnas", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                                }

                                // 6. Mostrar columnas ocultas
                                Button {
                                    isHiddenColumnsSheetPresented = true
                                } label: {
                                    Label("Mostrar columnas ocultas", systemImage: "eye.slash")
                                }

                                // 7. Exportar
                                ShareLink(item: exportText(data: data)) {
                                    Label("Exportar cuaderno", systemImage: "square.and.arrow.up")
                                }

                                // 9. Configuración de media
                                Button {
                                    isAverageConfigurationPresented = true
                                } label: {
                                    Label("Configuración de media", systemImage: "percent")
                                }

                                // 10. Filtros
                                let groups = groupedRows(data: data)
                                if !groups.isEmpty || !classSituations.isEmpty {
                                    Menu {
                                        if !groups.isEmpty {
                                            Menu {
                                                Button("Grupo completo") {
                                                    selectedGroupId = nil
                                                }
                                                ForEach(groups, id: \.id) { gp in
                                                    Button {
                                                        selectedGroupId = gp.id
                                                    } label: {
                                                        HStack {
                                                            Text("\(gp.name) (\(memberCount(gp.id, in: data)) alumnos)")
                                                            if selectedGroupId == gp.id {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                            } label: {
                                                Label("Filtrar grupo", systemImage: "person.2")
                                            }
                                        }

                                        if !classSituations.isEmpty {
                                            Menu {
                                                Button("Sin filtrar (Ver todas)") {
                                                    groupByWorkGroupMode = "none"
                                                }
                                                ForEach(classSituations, id: \.id) { situation in
                                                    Button {
                                                        let targetMode = "situation_\(situation.id)"
                                                        groupByWorkGroupMode = groupByWorkGroupMode == targetMode ? "none" : targetMode
                                                    } label: {
                                                        HStack {
                                                            Text(situation.title)
                                                            if groupByWorkGroupMode == "situation_\(situation.id)" {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                            } label: {
                                                Label("Situación de aprendizaje", systemImage: "folder")
                                            }
                                        }
                                    } label: {
                                        Label("Filtros", systemImage: "line.3.horizontal.decrease.circle")
                                    }
                                }
                            } label: {
                                Label("Acciones del cuaderno", systemImage: "ellipsis.circle")
                            }
                        }

                        // Barra de estado (.status)
                        ToolbarItem(placement: .status) {
                            HStack(spacing: 8) {
                                // Estado de guardado
                                HStack(spacing: 4) {
                                    if #available(iOS 18.0, macOS 14.0, *) {
                                        Image(systemName: saveBadge.icon)
                                            .symbolEffect(.rotate, isActive: notebookStore.notebookSplitSaveState.isSaving)
                                    } else {
                                        Image(systemName: saveBadge.icon)
                                    }
                                    Text(saveBadge.text)
                                }
                                .foregroundStyle(saveBadge.color)

                                if notebookStore.notebookSplitSaveState.state == .failed {
                                    Button {
                                        bridge.saveNotebook()
                                    } label: {
                                        Label("Reintentar", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityHint("Vuelve a intentar guardar los cambios pendientes")
                                }

                                Text("•")
                                    .foregroundStyle(.secondary)

                                // Sincronización LAN: no confundir ausencia de host con estado al día.
                                HStack(spacing: 4) {
                                    Image(systemName: notebookSyncStatusState.systemImage)
                                    Text(notebookSyncStatusText)
                                }
                                .foregroundStyle(notebookSyncStatusState.tint)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(notebookSyncStatusState.accessibilityLabel)

                                Text("•")
                                    .foregroundStyle(.secondary)

                                // Total alumnos
                                Text("\(filteredRows(data: data).count) alumnos")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                        }
                    }
                }
                .toolbarTitleMenu {
                    if toolbarMode == .shellOwned || toolbarMode == .macWindowOwned || toolbarMode == .macShellOwned || toolbarMode == .inlineCompact {
                        Section("Clase") {
                            ForEach(sortedClasses, id: \.id) { schoolClass in
                                Button {
                                    selectNotebookClass(schoolClass.id)
                                } label: {
                                    HStack {
                                        Text(classLabel(for: schoolClass))
                                        if selectedClassId == schoolClass.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        let tabs = orderedNotebookTabs(data: data)
                        if !tabs.isEmpty {
                            Section("Pestañas") {
                                Button {
                                    presentCreateNotebookTab()
                                } label: {
                                    Label("Nueva pestaña", systemImage: "plus.rectangle.on.rectangle")
                                }

                                ForEach(tabs, id: \.id) { tab in
                                    Button {
                                        selectNotebookTab(tab.id)
                                    } label: {
                                        HStack {
                                            Text(tab.title)
                                            if activeNotebookTabId(data: data) == tab.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        let groups = groupedRows(data: data)
                        if !groups.isEmpty {
                            Section("Grupo") {
                                Button {
                                    selectedGroupId = nil
                                } label: {
                                    HStack {
                                        Text("Grupo completo")
                                        if selectedGroupId == nil {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                ForEach(groups, id: \.id) { group in
                                    Button {
                                        selectedGroupId = group.id
                                    } label: {
                                        HStack {
                                            Text("\(group.name) (\(memberCount(group.id, in: data)) alumnos)")
                                            if selectedGroupId == group.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !classSituations.isEmpty {
                            Section("Situación de aprendizaje") {
                                Button {
                                    groupByWorkGroupMode = "none"
                                } label: {
                                    HStack {
                                        Text("Sin filtrar (Ver todas)")
                                        if groupByWorkGroupMode == "none" {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                ForEach(classSituations, id: \.id) { situation in
                                    Button {
                                        let targetMode = "situation_\(situation.id)"
                                        groupByWorkGroupMode = groupByWorkGroupMode == targetMode ? "none" : targetMode
                                    } label: {
                                        HStack {
                                            Text(situation.title)
                                            if groupByWorkGroupMode == "situation_\(situation.id)" {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Section("Vista") {
                            ForEach(NotebookSurfaceMode.allCases) { mode in
                                Button {
                                    surfaceMode = mode
                                } label: {
                                    HStack {
                                        Label(mode.title, systemImage: mode.systemImage)
                                        if surfaceMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        Section("Configuración") {
                            Button {
                                isAverageConfigurationPresented = true
                            } label: {
                                Label("Ver configuración del cuaderno", systemImage: "gearshape")
                            }
                        }
                    }
                }
                .toolbarRole(.editor)
                .notebookPresentedSearchable(if: toolbarMode == .inlineCompact, text: $searchText, isPresented: $isSearchPresented, prompt: "Buscar alumno")
                .avoidHidingContentDuringSearch()
        }
    }

    var isRubricEvaluationPresented: Bool {
        guard !notebookStore.showingBulkRubricEvaluation else { return false }
        return notebookStore.rubricEvaluationState.isLoading ||
            notebookStore.rubricEvaluationState.rubricDetail != nil ||
            notebookStore.rubricEvaluationState.error != nil
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
        // El presentador Mac es el único propietario de la geometría de la
        // hoja. Mantener aquí un tamaño único evita que AppKit mida el root con
        // un ancho y recorte después cabecera, catálogo y footer.
        content
            .frame(minWidth: 1_040, idealWidth: 1_200, maxWidth: 1_440, minHeight: 760, idealHeight: 860)
        #else
        content
            .presentationDetents([.large])
        #endif
    }

    func handleCreatedColumn(_ columnId: String) {
        highlightedColumnId = columnId
        if let data = notebookStore.notebookState as? NotebookUiStateData,
           let column = data.sheet.columns.first(where: { $0.id == columnId }) {
            highlightedCategoryId = column.categoryId
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if highlightedColumnId == columnId {
                highlightedColumnId = nil
            }
            if let data = notebookStore.notebookState as? NotebookUiStateData,
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
                if let data = notebookStore.notebookState as? NotebookUiStateData,
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
        if macPresentation == .full {
            let groupText = selectedGroupId.flatMap { groupName(for: $0, in: data) } ?? "Grupo completo"
            let tabText = activeNotebookTab(data: data)?.title
            let studentCount = filteredRows(data: data).count
            let studentSuffix = studentCount == 1 ? "alumno" : "alumnos"
            return [tabText, groupText, "\(studentCount) \(studentSuffix)"]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        let context = headerContextLine(in: data)
        let studentCount = filteredRows(data: data).count
        return "\(context) · \(studentCount) alumnos"
    }

    func gridStructuralInvalidationKey(data: NotebookUiStateData) -> String {
        [
            "\(isAttendanceQuickMode)",
            "\(structuralGridRevision)",
            "columns:\(data.sheet.columns.count)",
            "rows:\(data.sheet.rows.count)"
        ].joined(separator: "¬")
    }

    func reloadNotebookRow(_ studentId: Int64) {
        rowReloadRevisions[studentId, default: 0] += 1
    }

    var transientGridCellIds: Set<String> {
        var ids = Set<String>()
        if let selectionId = inspectorSelection?.id {
            ids.insert(selectionId)
        }
        if let focusedCellId {
            ids.insert(focusedCellId)
        }
        if let activeChoiceCellId {
            ids.insert(activeChoiceCellId)
        }
        return ids
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
                if let studentId = inspectorSelection?.studentId {
                    reloadNotebookRow(studentId)
                }
            }
        )
    }

}

struct CustomAverageExplanationPopoverView: View {
    let studentName: String
    let explanation: NotebookAverageExplanation?
    let columns: [NotebookColumnDefinition]
    let onClose: () -> Void

    private func formattedDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    enum AverageState {
        case complete
        case pending
        case insufficient
    }

    private var averageState: AverageState {
        guard let explanation = explanation,
              explanation.average != nil,
              !explanation.includedColumns.isEmpty else {
            return .insufficient
        }
        return explanation.pendingCells.isEmpty ? .complete : .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerCard

            if let explanation = explanation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryInfo(explanation)

                        if !explanation.weightedContributions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader(title: "Incluye", icon: "plus.circle.fill", color: NotebookStyle.successTint)
                                ForEach(explanation.weightedContributions, id: \.columnId) { c in
                                    contributionRow(c)
                                }
                            }
                        }

                        if !explanation.pendingCells.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader(title: "Pendientes", icon: "clock.fill", color: NotebookStyle.warningTint)
                                ForEach(explanation.pendingCells, id: \.columnId) { pending in
                                    pendingRow(pending)
                                }
                            }
                        }

                        if !explanation.excludedColumns.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader(title: "No incluye", icon: "minus.circle.fill", color: .secondary)
                                ForEach(explanation.excludedColumns, id: \.columnId) { e in
                                    exclusionRow(e)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay datos de cálculo disponibles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding()
            }
        }
        .padding(.vertical, 16)
    }

    private var headerCard: some View {
        let state = averageState
        let themeColor: Color = {
            switch state {
            case .complete: return NotebookStyle.successTint
            case .pending: return NotebookStyle.warningTint
            case .insufficient: return .secondary
            }
        }()
        let stateIcon: String = {
            switch state {
            case .complete: return "checkmark.seal.fill"
            case .pending: return "clock.badge.exclamationmark.fill"
            case .insufficient: return "exclamationmark.triangle.fill"
            }
        }()
        let stateTitle: String = {
            switch state {
            case .complete: return "Media consolidada"
            case .pending: return "Media provisional"
            case .insufficient: return "Datos insuficientes"
            }
        }()
        let stateDesc: String = {
            switch state {
            case .complete: return "Todos los instrumentos evaluables han sido calificados."
            case .pending: return "Faltan notas en una o más columnas del promedio."
            case .insufficient: return "No hay suficientes notas registradas para calcular."
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detalle de cálculo")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(studentName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    if let average = explanation?.average {
                        Text(formattedDecimal(average.doubleValue))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(themeColor)
                            .monospacedDigit()
                    } else {
                        Text("--")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: stateIcon)
                            .font(.system(size: 12, weight: .bold))
                        Text(stateTitle)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(themeColor)
                    .background(themeColor.opacity(0.12))
                    .clipShape(Capsule())
                }

                Text(stateDesc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themeColor.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(themeColor.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private func summaryInfo(_ explanation: NotebookAverageExplanation) -> some View {
        let totalWeight = explanation.includedColumns.reduce(0.0) { $0 + $1.weight }
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resumen del cálculo")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Peso acumulado de las notas: \(formattedDecimal(totalWeight))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    private func contributionRow(_ c: WeightedContribution) -> some View {
        HStack(spacing: 12) {
            let color: Color = {
                if let col = columns.first(where: { $0.id == c.columnId }),
                   let hex = col.colorHex,
                   !hex.isEmpty {
                    return Color(hex: hex)
                }
                return NotebookStyle.primaryTint
            }()

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Peso: \(formattedDecimal(c.weight))% · aporta \(formattedDecimal(c.weightedValue))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formattedDecimal(c.value))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(NotebookStyle.primaryTint)
                .monospacedDigit()
        }
        .padding(10)
        .background(NotebookStyle.surfaceSoft.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func pendingRow(_ pending: PendingCell) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(NotebookStyle.warningTint)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text("Celda vacía · peso previsto \(formattedDecimal(pending.expectedWeight))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                Text("Pendiente")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(NotebookStyle.warningTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(NotebookStyle.warningTint.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(10)
        .background(NotebookStyle.surfaceSoft.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func exclusionRow(_ e: ExcludedColumn) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(exclusionReasonText(e.reason))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer()

            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(10)
        .background(NotebookStyle.surfaceSoft.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func exclusionReasonText(_ reason: NotebookAverageExclusionReason) -> String {
        switch reason {
        case .empty: return "Pendiente"
        case .columnDoesNotCount: return "No cuenta para media"
        case .rawValueOnly: return "Marca bruta"
        case .lockedOrArchived: return "Bloqueado / Archivado"
        case .nonNumeric: return "Dato no numérico"
        default: return "Excluido"
        }
    }
}

private extension View {
    @ViewBuilder
    func notebookPresentedSearchable(if condition: Bool, text: Binding<String>, isPresented: Binding<Bool>, prompt: String) -> some View {
        if condition {
            if #available(iOS 17.0, macOS 14.0, *) {
                searchable(text: text, isPresented: isPresented, prompt: prompt)
            } else {
                searchable(text: text, prompt: prompt)
            }
        } else {
            self
        }
    }
}
