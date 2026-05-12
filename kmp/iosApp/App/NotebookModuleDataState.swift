import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func openInspectorForSelection(_ data: NotebookUiStateData) {
        if inspectorSelection != nil { return }
        if let firstColumn = managedColumns(data: data).first,
           let firstRow = filteredRows(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: firstRow.student.id, columnId: firstColumn.id)
        }
    }

    func openInspectorForStudent(_ studentId: Int64, data: NotebookUiStateData) {
        if let existingSelection = inspectorSelection,
           existingSelection.studentId == studentId,
           !existingSelection.columnId.isEmpty {
            inspectorSelection = existingSelection
        } else if let firstColumn = managedColumns(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: firstColumn.id)
        }
        isInspectorPresented = true
    }

    func evaluationTitle(for column: NotebookColumnDefinition) -> String {
        guard let evaluationId = column.evaluationId?.int64Value else { return "Sin evaluación asociada" }
        if let schoolClass = currentClass,
           let evaluation = bridge.evaluationsInClass.first(where: { $0.id == evaluationId }),
           !bridge.evaluationsInClass.isEmpty {
            return "\(evaluation.name) · \(schoolClass.name)"
        }
        return "Evaluación #\(evaluationId)"
    }

    func rubricTitle(for column: NotebookColumnDefinition) -> String {
        guard let rubricId = column.rubricId?.int64Value else { return "Sin rúbrica asociada" }
        return bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? "Rúbrica #\(rubricId)"
    }

    func filteredRows(data: NotebookUiStateData) -> [NotebookTableRow] {
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

    func notebookRowView(
        item: NotebookTableRow,
        data: NotebookUiStateData,
        segments: [NotebookDisplaySegment],
        rowIndex: Int,
        allRows: [NotebookTableRow],
        navigableSegments: [NotebookDisplaySegment]
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if segments.isEmpty {
                emptyNotebookCellPlaceholder(width: 180)
            } else {
                ForEach(segments, id: \.id) { segment in
                    rowCell(
                        for: segment,
                        item: item,
                        data: data,
                        rowIndex: rowIndex,
                        allRows: allRows,
                        navigableSegments: navigableSegments
                    )
                    .frame(width: segmentWidth(segment), height: notebookGridRowHeight, alignment: .center)
                }
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

    func emptyNotebookCellPlaceholder(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(NotebookStyle.surfaceSoft.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NotebookStyle.softBorder.opacity(0.65), lineWidth: 0.8)
            )
            .frame(width: width, height: 44)
            .frame(height: notebookGridRowHeight, alignment: .center)
    }

    func groupedRows(data: NotebookUiStateData) -> [NotebookWorkGroup] {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroups
            .filter { activeTabId == nil || $0.tabId == activeTabId }
            .sorted { $0.order < $1.order }
    }

    func groupId(for studentId: Int64, in data: NotebookUiStateData) -> Int64? {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroupMembers
            .first(where: { $0.studentId == studentId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .groupId
    }

    func groupName(for groupId: Int64, in data: NotebookUiStateData) -> String? {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroups
            .first(where: { $0.id == groupId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .name
    }

    func memberCount(_ groupId: Int64, in data: NotebookUiStateData) -> Int {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroupMembers
            .filter { $0.groupId == groupId && (activeTabId == nil || $0.tabId == activeTabId) }
            .count
    }

    func columns(in category: NotebookColumnCategory, data: NotebookUiStateData, includeHidden: Bool = false) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { $0.categoryId == category.id }
            .filter { includeHidden || $0.isVisibleInGrid }
            .filter { columnMatchesActiveTab($0, data: data) }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }
    }

    func managedColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { columnMatchesActiveTab($0, data: data) }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func relevantCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        visibleCategories(data: data)
            .filter { !columns(in: $0, data: data, includeHidden: true).isEmpty }
    }

    func visibleCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.columnCategories
            .filter { activeTabId == nil || $0.tabId == activeTabId }
            .sorted { $0.order < $1.order }
    }

    func displaySegments(data: NotebookUiStateData) -> [NotebookDisplaySegment] {
        var segments = fixedSegmentsForCurrentView().map(NotebookDisplaySegment.fixed)
        let rows = filteredRows(data: data)
        let categoriesById = Dictionary(
            data.sheet.columnCategories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedColumns = data.sheet.columns
            .filter(\.isVisibleInGrid)
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
            let categoryColumns = columns(in: category, data: data)
            let isEmptyCategory = completedCollapsedCategoryCount(categoryColumns, rows: rows) == 0
            let isCollapsed = isCategoryCollapsed(category) || (isEmptyCategory && !expandedEmptyCategoryIds.contains(category.id))
            if isCollapsed {
                if emittedCollapsedCategories.insert(category.id).inserted {
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

    func notebookSourceColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        managedColumns(data: data)
    }

    func visibleNotebookSourceColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        displaySegments(data: data).compactMap { segment in
            guard case .column(let column) = segment else { return nil }
            return column
        }
    }

    func notebookEvidenceSourceColumns(_ columns: [NotebookColumnDefinition]) -> [NotebookColumnDefinition] {
        columns.filter { !isNotebookIndividualSummaryColumn($0) }
    }

    func selectedNotebookAIStudentIds(in data: NotebookUiStateData) -> [Int64] {
        if let selectedStudentId {
            return [selectedStudentId]
        }
        if let inspectorSelection {
            return [inspectorSelection.studentId]
        }
        return filteredRows(data: data).map(\.student.id)
    }

}
