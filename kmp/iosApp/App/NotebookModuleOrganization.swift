import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func notebookOrganizationSheet(data: NotebookUiStateData?) -> some View {
        NavigationStack {
            List {
                Section("Organización") {
                    Button {
                        isOrganizationMenuPresented = false
                        presentCreateCategory()
                    } label: {
                        Label("Nueva categoría", systemImage: "folder.badge.plus")
                    }

                    Button {
                        isOrganizationMenuPresented = false
                        isGroupManagementPresented = true
                    } label: {
                        Label("Gestionar grupos de trabajo", systemImage: "person.2.badge.gearshape")
                    }

                    if let data {
                        TextField("Buscar columna", text: $organizationColumnSearchText)
                            .textFieldStyle(.roundedBorder)

                        ForEach(filteredOrganizationColumns(data: data), id: \.id) { column in
                            Button {
                                if column.isArchived {
                                    setNotebookColumnVisibility(column, visibility: .visible)
                                } else {
                                    toggleColumnVisibility(column)
                                }
                            } label: {
                                HStack {
                                    Label(column.title, systemImage: column.isArchived ? "archivebox" : (isColumnHidden(column) ? "eye.slash" : "eye"))
                                    Spacer()
                                    Text(column.isArchived ? "Archivada" : (column.isTemporarilyHidden ? "Oculta" : "Visible"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onMove { source, destination in
                            moveOrganizationColumns(data: data, from: source, to: destination)
                        }
                    }
                }

                if let data {
                    Section("Pestañas (Temas)") {
                        Button {
                            isOrganizationMenuPresented = false
                            presentCreateNotebookTab()
                        } label: {
                            Label("Nueva pestaña", systemImage: "plus.rectangle.on.rectangle")
                        }

                        ForEach(orderedNotebookTabs(data: data), id: \.id) { tab in
                            HStack {
                                Text(tab.title)
                                Spacer()
                                Button {
                                    isOrganizationMenuPresented = false
                                    presentRenameNotebookTab(tab)
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    isOrganizationMenuPresented = false
                                    pendingDeleteNotebookTab = tab
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Vista") {
                    Toggle("Vista compacta", isOn: $isCompactViewActive)

                    Picker("Agrupar por", selection: $groupByWorkGroupMode) {
                        Text("No agrupar").tag("none")
                        Text("Grupos generales").tag("general")
                        ForEach(classSituations, id: \.id) { situation in
                            Text("Situación: \(situation.title)").tag("situation_\(situation.id)")
                        }
                    }
                    .pickerStyle(.menu)

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
                        .disabled(data.sheet.rows.isEmpty || data.sheet.columns.filter(isNotebookIndividualSummaryColumn).isEmpty)

                        ShareLink(item: exportText(data: data)) {
                            Label("Exportar cuaderno", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Organización")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        isOrganizationMenuPresented = false
                    }
                }
            }
        }
    }

    func filteredOrganizationColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        let columns = managedColumns(data: data)
        let query = organizationColumnSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return columns }
        return columns.filter { column in
            column.title.localizedCaseInsensitiveContains(query)
                || column.id.localizedCaseInsensitiveContains(query)
        }
    }

    func moveOrganizationColumns(data: NotebookUiStateData, from source: IndexSet, to destination: Int) {
        let managed = managedColumns(data: data)
        let filtered = filteredOrganizationColumns(data: data)
        guard !filtered.isEmpty else { return }

        if organizationColumnSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var reordered = managed
            reordered.move(fromOffsets: source, toOffset: destination)
            reorderManagedColumns(reordered)
            return
        }

        let filteredIds = Set(filtered.map(\.id))
        let managedFilteredIndices = managed.indices.filter { filteredIds.contains(managed[$0].id) }
        var reorderedFiltered = filtered
        reorderedFiltered.move(fromOffsets: source, toOffset: destination)

        var merged = managed
        for (index, column) in zip(managedFilteredIndices, reorderedFiltered) {
            merged[index] = column
        }
        reorderManagedColumns(merged)
    }

    func presentCreateCategory() {
        editingCategoryId = nil
        categoryDraft = defaultCategoryDraft()
        isCreateCategoryAlertPresented = true
    }

    func openAddColumn(in category: NotebookColumnCategory) {
        highlightedCategoryId = category.id
        addColumnContext = NotebookAddColumnContext(categoryId: category.id, startsCreatingCategory: false)
    }

    func presentCreateNotebookTab() {
        editingNotebookTabId = nil
        notebookTabDraft = defaultNotebookTabDraft()
        isNotebookTabAlertPresented = true
    }

    func presentRenameNotebookTab(_ tab: NotebookTab) {
        editingNotebookTabId = tab.id
        notebookTabDraft = tab.title
        isNotebookTabAlertPresented = true
    }

    func presentRenameColumn(_ column: NotebookColumnDefinition) {
        editingColumnId = column.id
        columnDraft = column.title
        isRenameColumnAlertPresented = true
    }

    func defaultNotebookTabDraft() -> String {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return "Nuevo tema" }
        let nextIndex = orderedNotebookTabs(data: data).count + 1
        return "Tema \(nextIndex)"
    }

    func resetNotebookTabDraft() {
        editingNotebookTabId = nil
        notebookTabDraft = ""
    }

    func saveNotebookTabDraft() {
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
                fixedColumnWidth: tab.fixedColumnWidth,
                trace: tab.trace
            ))
            showToast("Pestaña renombrada")
        } else if let createdId = bridge.createTab(title: draft) {
            selectNotebookTab(createdId)
            showToast("Pestaña creada")
        }

        resetNotebookTabDraft()
    }

    func deleteNotebookTab(_ tab: NotebookTab) {
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

    func saveCategoryFromDraft() {
        let draft = categoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        bridge.saveColumnCategory(name: draft, categoryId: editingCategoryId)
        highlightedCategoryId = editingCategoryId
        showToast(editingCategoryId == nil ? "Categoría creada" : "Categoría renombrada")
        editingCategoryId = nil
        categoryDraft = ""
    }

    func saveColumnRename() {
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

    func saveColumnMutation(
        _ column: NotebookColumnDefinition,
        title: String? = nil,
        countsTowardAverage: Bool? = nil,
        weight: Double? = nil,
        isLocked: Bool? = nil,
        colorHex: String? = nil,
        widthDp: Double? = nil,
        formula: String? = nil,
        updatesFormula: Bool = false
    ) {
        bridge.saveColumn(column: copyNotebookColumn(
            column,
            title: title,
            widthDp: widthDp,
            weight: weight,
            countsTowardAverage: countsTowardAverage,
            isLocked: isLocked,
            colorHex: colorHex,
            formula: formula,
            updatesFormula: updatesFormula
        ))
    }

    func deleteColumn(_ column: NotebookColumnDefinition) {
        guard column.canBeDeleted else {
            showToast("Esta columna está bloqueada y no se puede eliminar", style: .warning)
            pendingDeleteColumn = nil
            return
        }
        bridge.deleteColumn(id: column.id, evaluationId: column.evaluationId?.int64Value)
        showToast("Columna eliminada", style: .warning)
        pendingDeleteColumn = nil
    }

    func presentDeleteColumnImpact(_ column: NotebookColumnDefinition) {
        guard let data = bridge.notebookState as? NotebookUiStateData else {
            pendingDeleteColumn = column
            return
        }
        pendingDeleteColumn = column
        pendingDeleteCategory = nil
        deletionConfirmationText = ""
        pendingDeletionImpact = deletionImpact(
            kind: .column,
            targetId: column.id,
            targetName: column.title,
            columns: [column],
            data: data
        )
    }

    func presentDeleteColumnsImpact(_ columns: [NotebookColumnDefinition]) {
        guard let data = bridge.notebookState as? NotebookUiStateData else {
            return
        }
        pendingDeleteColumn = nil
        pendingDeleteCategory = nil
        deletionConfirmationText = ""
        
        let columnIds = Set(columns.map(\.id))
        let gradeCount = data.sheet.rows.reduce(0) { total, row in
            total + row.persistedGrades.filter { grade in
                columnIds.contains(grade.columnId) && grade.value != nil
            }.count
        }
        let formulaCount = data.sheet.columns
            .filter { $0.type == .calculated && !columnIds.contains($0.id) }
            .filter { column in
                let formula = column.formula ?? ""
                return columnIds.contains(where: { id in
                    formula.contains("[\(id)]")
                })
            }
            .count
        let averageCount = columns.filter(\.countsTowardAverage).count

        pendingDeletionImpact = NotebookDeletionImpactDraft(
            kind: .columns,
            targetId: "bulk_delete",
            targetName: "\(columns.count) columnas",
            affectedColumns: columns,
            affectedGradeCount: gradeCount,
            affectedFormulaColumnCount: formulaCount,
            affectedAverageColumnCount: averageCount,
            hasLockedColumns: columns.contains { $0.isLocked }
        )
    }

    func presentDeleteCategoryImpact(_ category: NotebookColumnCategory) {
        guard let data = bridge.notebookState as? NotebookUiStateData else {
            pendingDeleteCategory = category
            return
        }
        pendingDeleteCategory = category
        pendingDeleteColumn = nil
        deletionConfirmationText = ""
        pendingDeletionImpact = deletionImpact(
            kind: .category,
            targetId: category.id,
            targetName: category.name,
            columns: columns(in: category, data: data, includeHidden: true),
            data: data
        )
    }

    func preserveCategoryFromImpact(_ impact: NotebookDeletionImpactDraft) {
        guard impact.kind == .category else { return }
        bridge.deleteColumnCategory(id: impact.targetId, preserveColumns: true)
        showToast("Categoría eliminada; las columnas se han conservado")
        pendingDeletionImpact = nil
        pendingDeleteCategory = nil
        deletionConfirmationText = ""
    }

    func performDestructiveDeletion(_ impact: NotebookDeletionImpactDraft) {
        guard !impact.hasLockedColumns else {
            showToast("Hay columnas bloqueadas. No se puede eliminar destructivamente.", style: .warning)
            return
        }
        if impact.requiresStrongConfirmation && deletionConfirmationText != "ELIMINAR" {
            showToast("Escribe ELIMINAR para confirmar", style: .warning)
            return
        }

        switch impact.kind {
        case .column:
            if let column = impact.affectedColumns.first {
                deleteColumn(column)
            }
        case .category:
            bridge.deleteColumnCategory(id: impact.targetId, preserveColumns: false)
            showToast("Categoría y columnas eliminadas", style: .warning)
            pendingDeleteCategory = nil
        case .columns:
            let idsAndEvalIds = impact.affectedColumns.map { ($0.id, $0.evaluationId?.int64Value) }
            bridge.deleteColumns(idsAndEvalIds: idsAndEvalIds)
            showToast("\(impact.affectedColumns.count) columnas eliminadas", style: .warning)
        }

        pendingDeletionImpact = nil
        deletionConfirmationText = ""
    }

    func deletionImpact(
        kind: NotebookDeletionKind,
        targetId: String,
        targetName: String,
        columns: [NotebookColumnDefinition],
        data: NotebookUiStateData
    ) -> NotebookDeletionImpactDraft {
        let columnIds = Set(columns.map(\.id))
        let gradeCount = data.sheet.rows.reduce(0) { total, row in
            total + row.persistedGrades.filter { grade in
                columnIds.contains(grade.columnId) && grade.value != nil
            }.count
        }
        let formulaCount = data.sheet.columns
            .filter { $0.type == .calculated && !columnIds.contains($0.id) }
            .filter { column in
                let formula = column.formula ?? ""
                return columnIds.contains(where: { id in
                    formula.contains("[\(id)]")
                })
            }
            .count
        let averageCount = columns.filter(\.countsTowardAverage).count

        return NotebookDeletionImpactDraft(
            kind: kind,
            targetId: targetId,
            targetName: targetName,
            affectedColumns: columns,
            affectedGradeCount: gradeCount,
            affectedFormulaColumnCount: formulaCount,
            affectedAverageColumnCount: averageCount,
            hasLockedColumns: columns.contains { $0.isLocked }
        )
    }

    func showToast(_ message: String, style: NotebookToastStyle = .success) {
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

    func notebookToastView(_ toast: NotebookToast) -> some View {
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

    func defaultCategoryDraft() -> String {
        switch viewPreset {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .all: return "Nueva categoría"
        }
    }

    func completedCollapsedCategoryCount(_ columns: [NotebookColumnDefinition], rows: [NotebookTableRow]) -> Int {
        columns.filter(\.isVisibleInGrid).filter { column in
            rows.contains { row in
                !displayValue(for: row, column: column)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }
        }.count
    }

    func visibleColumnCount(_ columns: [NotebookColumnDefinition]) -> Int {
        columns.filter(\.isVisibleInGrid).count
    }

    func collapsedCategoryProgressText(columns: [NotebookColumnDefinition], rows: [NotebookTableRow]) -> String {
        "\(completedCollapsedCategoryCount(columns, rows: rows)) / \(visibleColumnCount(columns)) con datos"
    }

    var columnColorOptions: [(label: String, hex: String)] {
        [
            ("Azul", "#4A90D9"),
            ("Verde", "#2E9B6F"),
            ("Ámbar", "#D28C1D"),
            ("Coral", "#D95C5C"),
            ("Violeta", "#7B6FF1"),
            ("Grafito", "#6B7280"),
        ]
    }

    func fixedRowCell(for fixed: NotebookFixedColumn, item: NotebookTableRow, data: NotebookUiStateData) -> some View {
        Group {
            switch fixed {
            case .photo:
                studentAvatar(for: item.student)
                    .frame(width: resolvedFixedWidth(for: fixed), alignment: .center)
            case .name:
                NotebookAttendanceSwipeCell(
                    onPresent: { Task { await markAttendance(for: item.student.id, status: NotebookAttendanceStatus.present) } },
                    onAbsent: { Task { await markAttendance(for: item.student.id, status: NotebookAttendanceStatus.absent) } },
                    onLate: { Task { await markAttendance(for: item.student.id, status: NotebookAttendanceStatus.late) } },
                    onMissingMaterial: { Task { await markAttendance(for: item.student.id, status: "SIN_MATERIAL") } },
                    onJustified: { Task { await markAttendance(for: item.student.id, status: "JUSTIFICADO") } },
                    onInjury: { Task { await toggleStudentInjuryStatus(item.student) } }
                ) {
                    Button {
                        openInspectorForStudent(item.student.id, data: data)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("\(item.student.firstName) \(item.student.lastName)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                    .layoutPriority(1)
                                riskBadge(for: item.student.id)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            let isInjured = isStudentInjured(item.student)
                            if isInjured {
                                Text("Seguimiento físico")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                Task { await toggleStudentInjuryStatus(item.student) }
                            } label: {
                                Label(
                                    isStudentInjured(item.student) ? "Quitar lesión" : "Marcar lesión",
                                    systemImage: isStudentInjured(item.student) ? "heart.slash" : "bandage"
                                )
                            }

                            Button {
                                openInspectorForStudent(item.student.id, data: data)
                            } label: {
                                Label("Abrir ficha", systemImage: "person.text.rectangle")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
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
                Button {
                    #if os(macOS)
                    inspectorSelection = NotebookInspectorSelection(
                        studentId: item.student.id,
                        columnId: NotebookInspectorSelection.averageColumnId
                    )
                    isInspectorPresented = true
                    focusMode = .reviewing
                    #else
                    averageExplanationRow = item
                    #endif
                } label: {
                    averageBadge(for: item)
                        .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .notebookAverageExplanation(item: mappedExplanationItemBinding)
            }
        }
    }

    @ViewBuilder
    func riskBadge(for studentId: Int64) -> some View {
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

}

private struct NotebookAttendanceSwipeCell<Content: View>: View {
    private enum Side {
        case primary
        case secondary
    }

    let onPresent: () -> Void
    let onAbsent: () -> Void
    let onLate: () -> Void
    let onMissingMaterial: () -> Void
    let onJustified: () -> Void
    let onInjury: () -> Void
    let content: Content

    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var revealedSide: Side?
    @GestureState private var translation: CGFloat = 0
    @State private var trackpadTranslation: CGFloat = 0

    private let revealWidth: CGFloat = 128
    private let commitThreshold: CGFloat = 164

    init(
        onPresent: @escaping () -> Void,
        onAbsent: @escaping () -> Void,
        onLate: @escaping () -> Void,
        onMissingMaterial: @escaping () -> Void,
        onJustified: @escaping () -> Void,
        onInjury: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onPresent = onPresent
        self.onAbsent = onAbsent
        self.onLate = onLate
        self.onMissingMaterial = onMissingMaterial
        self.onJustified = onJustified
        self.onInjury = onInjury
        self.content = content()
    }

    var body: some View {
        ZStack {
            actionLayer
            content.offset(x: offset)
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 14)
                .updating($translation) { value, state, _ in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    finishSwipe(translationWidth: value.translation.width)
                }
        )
        .macTrackpadSwipe { delta in
            trackpadTranslation = delta
        } onEnded: { delta in
            finishSwipe(translationWidth: delta)
            trackpadTranslation = 0
        }
    }

    private var settledOffset: CGFloat {
        switch revealedSide {
        case .primary: return revealWidth
        case .secondary: return -revealWidth
        case nil: return 0
        }
    }

    private var offset: CGFloat {
        let activeTranslation = trackpadTranslation != 0 ? trackpadTranslation : translation
        return min(max(settledOffset + activeTranslation, -commitThreshold - 8), commitThreshold + 8)
    }

    @ViewBuilder
    private var actionLayer: some View {
        HStack(spacing: 3) {
            if offset > 0 {
                compactAction("P", tint: .green, action: onPresent)
                compactAction("A", tint: .red, action: onAbsent)
                compactAction("R", tint: .orange, action: onLate)
            }
            Spacer(minLength: 0)
            if offset < 0 {
                compactAction("M", tint: .brown, action: onMissingMaterial)
                compactAction("J", tint: .gray, action: onJustified)
                compactAction("L", tint: .orange, action: onInjury)
            }
        }
        .padding(.horizontal, 4)
    }

    private func compactAction(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            close()
        } label: {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 32)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func finishSwipe(translationWidth: CGFloat) {
        let finalOffset = settledOffset + translationWidth
        if finalOffset >= commitThreshold {
            onPresent()
            close()
        } else if finalOffset <= -commitThreshold {
            onMissingMaterial()
            close()
        } else {
            withAnimation(uiFeatureFlags.interactionAnimation) {
                if let side = revealedSide {
                    if side == .primary && translationWidth < -34 {
                        revealedSide = nil
                    } else if side == .secondary && translationWidth > 34 {
                        revealedSide = nil
                    } else {
                        revealedSide = side
                    }
                } else {
                    if translationWidth > 34 {
                        revealedSide = .primary
                    } else if translationWidth < -34 {
                        revealedSide = .secondary
                    } else {
                        revealedSide = nil
                    }
                }
            }
        }
    }

    private func close() {
        withAnimation(uiFeatureFlags.interactionAnimation) {
            revealedSide = nil
        }
    }
}
