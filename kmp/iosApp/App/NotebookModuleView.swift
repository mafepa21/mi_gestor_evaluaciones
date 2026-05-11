import SwiftUI
import PhotosUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

struct NotebookModuleView: View {
    #if os(macOS)
    let notebookGridRowHeight: CGFloat = 64
    #else
    let notebookGridRowHeight: CGFloat = 72
    #endif
    let notebookGridHeaderHeight: CGFloat = 68
    let notebookGridFolderLaneHeight: CGFloat = 64

    @EnvironmentObject var layoutState: WorkspaceLayoutState
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let macToolbarActions: NotebookMacToolbarActions?
    @StateObject var inspectorState: NotebookMacInspectorState
    let macPresentation: NotebookMacPresentation
    @State var addColumnContext: NotebookAddColumnContext? = nil
    @State var searchText = ""
    @State var selectedGroupId: Int64? = nil
    @State var viewPreset: NotebookViewPreset = .all
    @State var surfaceMode: NotebookSurfaceMode = .grid
    @State var todayAttendanceByStudentId: [Int64: String] = [:]
    @State var incidentCountByStudentId: [Int64: Int] = [:]
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
    @State var expandedEmptyCategoryIds: Set<String> = []
    @State var notebookAISheetRequest: NotebookAISheetRequest? = nil
    @State var notebookSummarySheetRequest: NotebookSummarySheetRequest? = nil
    @State var isAverageConfigurationPresented = false
    @State var averageExplanationRow: NotebookTableRow? = nil
    @State var currentSelectionAuditEvents: [NotebookCellAuditEvent] = []
    @State var auditObservationTask: Task<Void, Never>? = nil
    @State var riskLevelCache: [Int64: RiskLevel] = [:]
    @State var riskComputationKey: String?
    @State var isPrecomputingRiskLevels = false
    @AppStorage("notebook.fixedZoneWidth") var fixedZoneWidthStored = 460.0
    @State var isDraggingFixedZoneDivider = false
    @State var fixedZoneDragStartWidth: CGFloat = 0
    @State var fixedZoneLiveWidth: CGFloat? = nil
    @State var columnWidths: [String: CGFloat] = [:]
    @State var formulaEditRequest: NotebookFormulaEditRequest? = nil
    @State var formulaDraft = ""
    @State var formulaAIPrompt = ""
    @State var formulaAIMessage: String? = nil
    @State var isFormulaAIGenerating = false
    @State var activeChoiceCellId: String? = nil
    @AppStorage("notebook.navigationDirection") var navigationDirectionRaw = NotebookNavigationDirection.down.rawValue
    @FocusState var focusedCellId: String?
    let formulaAIService = AppleFoundationFormulaService()

    init(
        bridge: KmpBridge,
        selectedClassId: Binding<Int64?>,
        selectedStudentId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void,
        macPresentation: NotebookMacPresentation = .full,
        macInspectorState: NotebookMacInspectorState? = nil,
        macToolbarActions: NotebookMacToolbarActions? = nil
    ) {
        self._bridge = ObservedObject(wrappedValue: bridge)
        self._selectedClassId = selectedClassId
        self._selectedStudentId = selectedStudentId
        self.onOpenModule = onOpenModule
        self.macToolbarActions = macToolbarActions
        self.macPresentation = macPresentation
        self._inspectorState = StateObject(wrappedValue: macInspectorState ?? NotebookMacInspectorState())
    }

    var navigationDirection: NotebookNavigationDirection {
        get { NotebookNavigationDirection(rawValue: navigationDirectionRaw) ?? .down }
        nonmutating set { navigationDirectionRaw = newValue.rawValue }
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

    var isMacInspectorOnly: Bool {
        macPresentation == .inspector
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

    var isInspectorPresentedBinding: Binding<Bool> {
        Binding(
            get: { isInspectorPresented },
            set: { isInspectorPresented = $0 }
        )
    }

    var body: some View {
        notebookLifecycleCleanup(
            notebookObservationModifiers(
                notebookSheetAndTaskModifiers(notebookContentWithDialogs)
            )
        )
    }

    var notebookContentWithDialogs: some View {
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
        .sheet(item: $pendingDeletionImpact, onDismiss: {
            deletionConfirmationText = ""
            pendingDeleteColumn = nil
            pendingDeleteCategory = nil
        }) { impact in
            NotebookDeletionImpactSheet(
                impact: impact,
                confirmationText: $deletionConfirmationText,
                onPreserveCategory: {
                    preserveCategoryFromImpact(impact)
                },
                onDelete: {
                    performDestructiveDeletion(impact)
                },
                onCancel: {
                    pendingDeletionImpact = nil
                }
            )
            .frame(minWidth: 520, minHeight: 460)
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

    func notebookSheetAndTaskModifiers<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $isOrganizationMenuPresented) {
                if let data = bridge.notebookState as? NotebookUiStateData {
                    NotebookColumnOrganizerSheet(
                        columns: managedColumns(data: data),
                        onSetVisibility: { column, visibility in
                            setNotebookColumnVisibility(column, visibility: visibility)
                        },
                        onRename: { column in
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                presentRenameColumn(column)
                            }
                        },
                        onDelete: { column in
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                presentDeleteColumnImpact(column)
                            }
                        },
                        onAddColumn: {
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                addColumnContext = NotebookAddColumnContext(
                                    categoryId: nil,
                                    startsCreatingCategory: false
                                )
                            }
                        },
                        onOpenHiddenColumns: {
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                isHiddenColumnsSheetPresented = true
                            }
                        },
                        onShowAll: {
                            showAllManagedColumns(data: data)
                        },
                        onReorder: { reorderedColumns in
                            reorderManagedColumns(reorderedColumns)
                        }
                    )
                    .frame(minWidth: 520, minHeight: 620)
                } else {
                    NotebookContentUnavailableView(
                        "Sin datos del cuaderno",
                        systemImage: "rectangle.3.group",
                        description: "Carga una clase para organizar sus columnas."
                    )
                    .frame(minWidth: 420, minHeight: 260)
                }
            }
            .sheet(isPresented: $isHiddenColumnsSheetPresented) {
                if let data = bridge.notebookState as? NotebookUiStateData {
                    NotebookHiddenColumnsSheet(
                        columns: managedColumns(data: data),
                        onShowColumn: { column in
                            setNotebookColumnVisibility(column, visibility: .visible)
                        },
                        onShowAll: {
                            showAllManagedColumns(data: data)
                        }
                    )
                    .frame(minWidth: 420, minHeight: 360)
                } else {
                    NotebookContentUnavailableView(
                        "Sin datos del cuaderno",
                        systemImage: "eye.slash",
                        description: "Carga una clase para revisar columnas ocultas."
                    )
                    .frame(minWidth: 420, minHeight: 260)
                }
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

    func notebookObservationModifiers<Content: View>(_ content: Content) -> some View {
        notebookToolbarObservationModifiers(
            notebookSelectionObservationModifiers(content)
        )
    }

    func notebookSelectionObservationModifiers<Content: View>(_ content: Content) -> some View {
        content
            .appOnChange(of: selectedClassId) { newValue in
                Task { @MainActor in
                    undoStack.removeAll()
                    guard let newValue else { return }
                    guard bridge.notebookViewModel.currentClassId?.int64Value != newValue else { return }
                    selectNotebookClass(newValue)
                }
            }
            .appOnChange(of: bridge.selectedNotebookTabId) { _ in
                Task { @MainActor in
                    undoStack.removeAll()
                    restoreSeatPositions()
                    await refreshNotebookSignals()
                }
            }
            .appOnChange(of: inspectorSelection) { newValue in
                Task { @MainActor in
                    syncInspectorDraft()
                    auditObservationTask?.cancel()
                    currentSelectionAuditEvents = []

                    if let selection = newValue {
                        auditObservationTask = Task { @MainActor in
                            let sequence = bridge.notebookViewModel.observeCellAudit(
                                studentId: selection.studentId,
                                columnId: selection.columnId
                            ).asAsyncSequence(type: NSArray.self)

                            for await events in sequence {
                                if Task.isCancelled { break }
                                currentSelectionAuditEvents = (events as? [NotebookCellAuditEvent]) ?? []
                            }
                        }
                    }

                    if newValue == nil {
                        isInspectorPresented = false
                    }
                }
            }
            .appOnChange(of: selectedAttachmentPhoto) { newValue in
                guard let newValue else { return }
                Task { await importSelectedAttachment(from: newValue) }
            }
    }

    func notebookToolbarObservationModifiers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: isInspectorPresented) { _ in
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: surfaceMode) { _ in
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: undoStack.count) { _ in
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: isAttendanceQuickMode) { _ in
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: searchText) { _ in
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: selectedGroupId) { _ in
                scheduleToolbarStateSyncIfLoaded()
                Task { @MainActor in
                    riskComputationKey = nil
                }
            }
            .appOnChange(of: inspectorSelection) { _ in
                scheduleToolbarStateSyncIfLoaded()
            }
            .appOnChange(of: bridge.notebookState is NotebookUiStateData) { _ in
                Task { @MainActor in
                    restoreSeatPositions()
                    riskComputationKey = nil
                }
                scheduleToolbarStateSyncIfLoaded()
            }
    }

    func notebookLifecycleCleanup<Content: View>(_ content: Content) -> some View {
        content
            .onDisappear {
                if !isMacInspectorOnly {
                    layoutState.clearNotebookToolbar()
                    macToolbarActions?.clear()
                }
            }
    }

    func centerPanel(data: NotebookUiStateData) -> some View {
        let rows = filteredRows(data: data)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NotebookTopBar(
                    bridge: bridge,
                    searchText: $searchText,
                    surfaceMode: $surfaceMode,
                    navigationDirection: navigationDirection,
                    isInspectorPresented: isInspectorPresented,
                    isAttendanceQuickMode: isAttendanceQuickMode,
                    canMarkAllPresent: !rows.isEmpty,
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
                    exportText: exportText(data: data),
                    showsInlineActions: macPresentation != .content
                )
                Divider()
                NotebookTabStrip(
                    tabs: orderedNotebookTabs(data: data),
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
                spreadsheetContent(data: data, rows: rows)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if macPresentation == .full && isInspectorPresented {
                Divider().opacity(0.16)
                inspectorPanel(data: data, rows: rows)
                    .frame(width: 360)
                    .background(NotebookStyle.surfaceMuted)
            }
        }
        .background(EvaluationBackdrop())
        .onAppear {
            if !isMacInspectorOnly {
                scheduleToolbarStateSync(data: data)
            }
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
        let fixedSegments = visibleFixedSegments(in: segments)
        let leadingFixedSegments = fixedSegments.filter { !isTrailingFixedSegment($0) }
        let trailingFixedSegments = fixedSegments.filter(isTrailingFixedSegment)
        let scrollableSegments = segments.filter { !isFixedSegment($0) }
        let laneItems = headerLaneItems(data: data, segments: scrollableSegments)
        let hasFolders = laneItems.contains {
            if case .folder = $0 { return true }
            return false
        }

        NotebookGridContent(
            rows: rows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedZoneWidth,
            trailingFixedColumnWidth: trailingFixedSegments.isEmpty ? 0 : defaultFixedWidth(for: .average) + 32,
            topAccessoryHeight: hasFolders ? notebookGridFolderLaneHeight : 0,
            headerHeight: notebookGridHeaderHeight,
            rowHeight: notebookGridRowHeight,
            rowInvalidationKey: gridRowInvalidationKey(data: data),
            fixedSegments: leadingFixedSegments,
            trailingFixedSegments: trailingFixedSegments,
            scrollableSegments: scrollableSegments
        ) {
            NotebookStateCard(
                systemImage: "person.3.sequence",
                title: "Sin alumnos visibles",
                message: "Ajusta la búsqueda o el filtro de grupo para ver filas del cuaderno."
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
                if hasFolders {
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
                    .padding(.top, 10)
                    .padding(.bottom, 8)
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

    func isFixedSegment(_ segment: NotebookDisplaySegment) -> Bool {
        if case .fixed = segment {
            return true
        }
        return false
    }

    func isTrailingFixedSegment(_ segment: NotebookDisplaySegment) -> Bool {
        if case .fixed(.average) = segment {
            return true
        }
        return false
    }

    func visibleFixedSegments(in segments: [NotebookDisplaySegment]) -> [NotebookDisplaySegment] {
        let allowedColumns = visibleFixedColumns
        return segments.filter { segment in
            guard case .fixed(let fixed) = segment else { return false }
            return allowedColumns.contains(fixed)
        }
    }

    var fixedZoneWidth: CGFloat {
        min(maxFixedZoneWidth, max(minFixedZoneWidth, fixedZoneLiveWidth ?? CGFloat(fixedZoneWidthStored)))
    }

    var minFixedZoneWidth: CGFloat { 220 }
    var maxFixedZoneWidth: CGFloat { 700 }

    var visibleFixedColumns: [NotebookFixedColumn] {
        var columns: [NotebookFixedColumn] = [.photo, .name]
        if fixedZoneWidth > 290 { columns.append(.followUp) }
        if fixedZoneWidth > 400 { columns.append(.attendance) }
        if fixedZoneWidth > 490 { columns.append(.group) }
        return columns
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
        }
        DispatchQueue.main.async {
            fixedZoneWidthStored = Double(snappedWidth)
            fixedZoneLiveWidth = nil
        }
    }

    func segmentWidth(_ segment: NotebookDisplaySegment) -> CGFloat {
        switch segment {
        case .fixed(let fixed):
            return resolvedFixedWidth(for: fixed)
        case .column(let column):
            return resolvedColumnWidth(for: column)
        case .collapsedCategory:
            return 150
        }
    }

    func resolvedFixedWidth(for fixed: NotebookFixedColumn) -> CGFloat {
        let visibleColumns = visibleFixedColumns
        let trailingColumns = visibleColumns.filter { $0 != .photo && $0 != .name }
        let trailingWidth = trailingColumns.reduce(CGFloat.zero) { partial, column in
            partial + defaultFixedWidth(for: column)
        }
        let spacing = CGFloat(max(visibleColumns.count - 1, 0)) * 8
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

    func defaultFixedWidth(for fixed: NotebookFixedColumn) -> CGFloat {
        switch fixed {
        case .photo: return 52
        case .name: return 180
        case .group: return 90
        case .followUp: return 100
        case .attendance: return 90
        case .average: return 90
        }
    }

    func resolvedColumnWidth(for column: NotebookColumnDefinition) -> CGFloat {
        columnWidths[column.id] ?? CGFloat(max(column.widthDp, 140))
    }

    func notebookLoadedContent(data: NotebookUiStateData) -> some View {
        Group {
            switch macPresentation {
            case .full, .content:
                centerPanel(data: data)
            case .inspector:
                inspectorPanel(data: data, rows: filteredRows(data: data))
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430, maxHeight: .infinity)
                    .background(NotebookStyle.surfaceMuted)
            }
        }
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
            .navigationTitle("Cuaderno")
            .notebookNavigationSubtitle(notebookNavigationSubtitle(data: data))
            .notebookKeyboardNavigation {
                navigateFromFocused(direction: navigationDirection, data: data)
            }
            .onAppear {
                if !isMacInspectorOnly {
                    ensureActiveNotebookTab(data: data)
                    scheduleToolbarStateSync(data: data)
                }
            }
            .appOnChange(of: notebookTabsStateKey(data: data)) { _ in
                if !isMacInspectorOnly {
                    ensureActiveNotebookTab(data: data)
                }
            }
            .appOnChange(of: toolbarStateKey(data: data)) { _ in
                if !isMacInspectorOnly {
                    scheduleToolbarStateSync(data: data)
                }
            }
    }

    @ViewBuilder
    func addColumnSheetPresentation(for context: NotebookAddColumnContext) -> some View {
        let content = AddColumnSheet(
            bridge: bridge,
            initialCategoryId: context.categoryId,
            startsCreatingCategory: context.startsCreatingCategory
        )

        #if os(macOS)
        content
            .frame(minWidth: 520, idealWidth: 560, maxWidth: 640, minHeight: 560, idealHeight: 620)
        #else
        content
            .presentationDetents([.large])
        #endif
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
            "\(isInspectorPresented)",
            "\(isAttendanceQuickMode)",
            "\(cellReloadRevision)",
            activeChoiceCellId ?? "none",
            focusedCellId ?? "none",
            todayAttendanceByStudentId
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ","),
            incidentCountByStudentId
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ","),
            riskLevelCache
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ","),
            "\(data.sheet.columns.count)"
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
