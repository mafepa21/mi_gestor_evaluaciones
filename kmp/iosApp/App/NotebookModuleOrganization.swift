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

                    if let data {
                        ForEach(managedColumns(data: data), id: \.id) { column in
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
                    formula.contains("[\(id)]") || formula.contains(id)
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
                Button {
                    averageExplanationRow = item
                } label: {
                    averageBadge(for: item)
                        .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(item: $averageExplanationRow) { item in
                    NotebookAverageExplanationView(
                        studentName: "\(item.student.firstName) \(item.student.lastName)",
                        explanation: item.row.averageExplanation
                    )
                        .frame(width: 320)
                }
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
