import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func isNotebookAICommentColumn(_ column: NotebookColumnDefinition) -> Bool {
        bridge.isNotebookAICommentColumn(column)
    }

    func headerLaneItems(data: NotebookUiStateData, segments: [NotebookDisplaySegment]) -> [NotebookHeaderLaneItem] {
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
                } + CGFloat(max(categoryColumns.count - 1, 0) * 8)
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

    func fixedSegmentsForCurrentView() -> [NotebookFixedColumn] {
        [.name, .average]
    }

    func columnMatchesCurrentView(_ column: NotebookColumnDefinition) -> Bool {
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

    func columnMatchesActiveTab(_ column: NotebookColumnDefinition, data: NotebookUiStateData) -> Bool {
        guard let activeTabId = activeNotebookTabId(data: data) else { return true }
        return column.tabIds.contains(activeTabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty)
    }

    func isColumnHidden(_ column: NotebookColumnDefinition) -> Bool {
        !column.isVisibleInGrid
    }

    func isColumnRestorableHidden(_ column: NotebookColumnDefinition) -> Bool {
        column.canBeShownWithShowAll
    }

    func isColumnArchived(_ column: NotebookColumnDefinition) -> Bool {
        column.isArchived
    }

    func toggleColumnVisibility(_ column: NotebookColumnDefinition) {
        setNotebookColumnHidden(column, isHidden: !isColumnHidden(column))
    }

    func copyNotebookColumn(
        _ column: NotebookColumnDefinition,
        title: String? = nil,
        isHidden: Bool? = nil,
        visibility: NotebookColumnVisibility? = nil,
        order: Int32? = nil,
        widthDp: Double? = nil,
        weight: Double? = nil,
        countsTowardAverage: Bool? = nil,
        isLocked: Bool? = nil,
        colorHex: String? = nil,
        formula: String? = nil,
        updatesFormula: Bool = false
    ) -> NotebookColumnDefinition {
        NotebookColumnDefinition(
            id: column.id,
            title: title?.isEmpty == false ? title! : column.title,
            type: column.type,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            evaluationId: column.evaluationId,
            rubricId: column.rubricId,
            formula: updatesFormula ? formula : column.formula,
            weight: weight ?? column.weight,
            dateEpochMs: column.dateEpochMs,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds,
            scaleKind: column.scaleKind,
            tabIds: column.tabIds,
            sessions: column.sessions,
            sharedAcrossTabs: column.sharedAcrossTabs,
            colorHex: colorHex ?? column.colorHex,
            iconName: column.iconName,
            order: order ?? column.order,
            widthDp: widthDp ?? column.widthDp,
            categoryId: column.categoryId,
            ordinalLevels: column.ordinalLevels,
            availableIcons: column.availableIcons,
            countsTowardAverage: countsTowardAverage ?? column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: isHidden ?? column.isHidden,
            visibility: visibility ?? column.visibility,
            isLocked: isLocked ?? column.isLocked,
            isTemplate: column.isTemplate,
            emptyCellPolicy: column.emptyCellPolicy,
            trace: column.trace
        )
    }

    func setNotebookColumnHidden(_ column: NotebookColumnDefinition, isHidden: Bool) {
        setNotebookColumnVisibility(column, visibility: isHidden ? .hidden : .visible)
    }

    func setNotebookColumnVisibility(_ column: NotebookColumnDefinition, visibility: NotebookColumnVisibility) {
        if column.isArchived && visibility == .hidden {
            showToast("La columna archivada debe restaurarse antes de ocultarse", style: .warning)
            return
        }
        if visibility == .archived && !column.canBeArchived {
            showToast("Esta columna no se puede archivar", style: .warning)
            return
        }
        let updated = copyNotebookColumn(
            column,
            isHidden: visibility != .visible,
            visibility: visibility
        )

        bridge.saveColumn(column: updated)
        switch visibility {
        case .visible:
            showToast("Columna visible")
        case .hidden:
            showToast("Columna ocultada")
        case .archived:
            showToast("Columna archivada")
        default:
            showToast("Visibilidad actualizada")
        }
        scheduleToolbarStateSyncIfLoaded()
    }

    func showAllManagedColumns(data: NotebookUiStateData) {
        let columns = managedColumns(data: data).filter(isColumnRestorableHidden)
        guard !columns.isEmpty else {
            showToast("No hay columnas ocultas para mostrar", style: .warning)
            return
        }
        // TODO(backend-batch): replace per-column saves with a single batch visibility mutation.
        columns.forEach { column in
            bridge.saveColumn(column: copyNotebookColumn(
                column,
                isHidden: false,
                visibility: .visible
            ))
        }
        showToast(columns.count == 1 ? "Columna visible" : "Columnas ocultas visibles")
        scheduleToolbarStateSyncIfLoaded()
    }

    func saveAverageConfiguration(_ updates: [NotebookAverageColumnUpdate]) {
        guard !updates.isEmpty else { return }
        // TODO(backend-batch): persist average column configuration in one backend batch instead of many saves.
        updates.forEach { update in
            bridge.saveColumn(column: copyNotebookColumn(
                update.column,
                weight: update.isIncluded ? update.weight : 0,
                countsTowardAverage: update.isIncluded
            ))
        }
        showToast("Media actualizada")
        scheduleToolbarStateSyncIfLoaded()
    }

    func reorderManagedColumns(_ reorderedColumns: [NotebookColumnDefinition]) {
        // TODO(backend-batch): persist reordered columns in one backend batch instead of many saves.
        reorderedColumns.enumerated().forEach { index, column in
            let nextOrder = Int32(index)
            if column.order != nextOrder {
                bridge.saveColumn(column: copyNotebookColumn(column, order: nextOrder))
            }
        }
        showToast("Columnas reordenadas")
        scheduleToolbarStateSyncIfLoaded()
    }

}
