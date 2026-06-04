import SwiftUI
import PhotosUI
import MiGestorKit

extension NotebookModuleView {
    var notebookContentWithDialogs: some View {
        Group {
            if let data = bridge.notebookState as? NotebookUiStateData {
                notebookLoadedContent(data: data)
            } else if bridge.notebookState is NotebookUiStateLoading {
                NotebookSkeletonGridView(rowCount: 14, columnCount: 7)
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

    @ViewBuilder
    func notebookSheetAndTaskModifiers<Content: View>(_ content: Content) -> some View {
        if isMacInspectorOnly {
            content
        } else {
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
                        onDeleteMultiple: { columns in
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                presentDeleteColumnsImpact(columns)
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
                        onCreateCategory: {
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                presentCreateCategory()
                            }
                        },
                        onCreateSummary: {
                            isOrganizationMenuPresented = false
                            UserDefaults.standard.set("individual_summary", forKey: "notebook.addColumn.lastBlueprintId")
                            DispatchQueue.main.async {
                                addColumnContext = NotebookAddColumnContext(
                                    categoryId: nil,
                                    startsCreatingCategory: false
                                )
                            }
                        },
                        onGenerateSummary: { columnId in
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: columnId)
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
                        },
                        onOpenGroupManagement: {
                            isOrganizationMenuPresented = false
                            DispatchQueue.main.async {
                                isGroupManagementPresented = true
                            }
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
                    startSelectionAuditObservationIfNeeded(for: newValue)

                    if newValue == nil {
                        isInspectorPresented = false
                        if focusedCellId == nil && activeChoiceCellId == nil {
                            focusMode = .normal
                        }
                    }
                }
            }
            .appOnChange(of: isInspectorPresented) { presented in
                Task { @MainActor in
                    if presented {
                        focusMode = .reviewing
                        startSelectionAuditObservationIfNeeded(for: inspectorSelection)
                    } else {
                        auditObservationTask?.cancel()
                        auditObservationTask = nil
                        currentSelectionAuditEvents = []
                        inspectorSelection = nil
                        if focusedCellId == nil && activeChoiceCellId == nil {
                            focusMode = .normal
                        }
                    }
                }
            }
            .appOnChange(of: focusedCellId) { newValue in
                if newValue != nil {
                    focusMode = .editing
                } else if activeChoiceCellId == nil && !isInspectorPresented {
                    focusMode = .normal
                }
            }
            .appOnChange(of: activeChoiceCellId) { newValue in
                if newValue != nil {
                    focusMode = .editing
                } else if focusedCellId == nil && !isInspectorPresented {
                    focusMode = .normal
                }
            }
            .appOnChange(of: selectedAttachmentPhoto) { newValue in
                guard let newValue else { return }
                Task { await importSelectedAttachment(from: newValue) }
            }
    }

    private func startSelectionAuditObservationIfNeeded(for selection: NotebookInspectorSelection?) {
        auditObservationTask?.cancel()
        auditObservationTask = nil
        guard isInspectorPresented, let selection else {
            currentSelectionAuditEvents = []
            return
        }

        currentSelectionAuditEvents = []
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
}
