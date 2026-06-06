import SwiftUI
import MiGestorKit

final class NotebookGridLayoutModel: ObservableObject {
    private enum Metrics {
        static let fixedZoneHorizontalPadding: CGFloat = 32
        static let collapsedCategoryWidth: CGFloat = 168
        static let minimumColumnWidth: CGFloat = 80
        static let maximumColumnWidth: CGFloat = 400
        static let defaultColumnWidth: CGFloat = 140
    }

    @Published private(set) var collapsedCategoryIds: Set<String> = []
    @Published private(set) var columnWidths: [String: CGFloat] = [:]

    private var storageClassKey = "no-class"
    private var renderCache: NotebookGridRenderModel?
    private var rowsCache: NotebookVisibleRowsCache?

    func configure(classId: Int64?) {
        let nextKey = classId.map(String.init) ?? "no-class"
        guard nextKey != storageClassKey || collapsedCategoryIds.isEmpty else { return }
        storageClassKey = nextKey
        collapsedCategoryIds = Self.loadCollapsedCategoryIds(storageKey: collapsedCategoryStorageKey)
    }

    func isCategoryCollapsed(_ category: NotebookColumnCategory) -> Bool {
        category.isCollapsed || collapsedCategoryIds.contains(category.id)
    }

    func setCategoryCollapsed(_ category: NotebookColumnCategory, collapsed: Bool) {
        if collapsed {
            collapsedCategoryIds.insert(category.id)
        } else {
            collapsedCategoryIds.remove(category.id)
        }
        UserDefaults.standard.set(
            collapsedCategoryIds.sorted().joined(separator: ","),
            forKey: collapsedCategoryStorageKey
        )
        renderCache = nil
    }

    func renderModel(
        data: NotebookUiStateData,
        activeTabId: String?,
        viewPreset: NotebookViewPreset,
        isCompact: Bool
    ) -> NotebookGridRenderModel {
        let key = NotebookGridRenderModel.Key(
            classId: data.sheet.classId,
            activeTabId: activeTabId,
            viewPreset: viewPreset.rawValue,
            isCompact: isCompact,
            columnsVersion: Self.version(data.sheet.columns.map { "\($0.id):\($0.order):\($0.visibility):\($0.isPinned):\($0.categoryId ?? ""):\($0.widthDp)" }),
            categoriesVersion: Self.version(data.sheet.columnCategories.map { "\($0.id):\($0.tabId):\($0.order):\($0.isCollapsed)" }),
            collapsedCategoriesVersion: Self.version(Array(collapsedCategoryIds)),
            fixedMode: UserDefaults.standard.string(forKey: "notebook.groupByWorkGroupMode") ?? "none"
        )
        if let renderCache, renderCache.key == key {
            NotebookGridPerformanceDebug.event("renderModel hit")
            return renderCache
        }

        let segments = NotebookGridPerformanceDebug.measure("renderModel build") {
            displaySegments(data: data, activeTabId: activeTabId, viewPreset: viewPreset)
        }
        let fixedSegments = visibleFixedSegments(in: segments)
        let leadingFixedSegments = fixedSegments.filter { !isTrailingFixedSegment($0) }
        let trailingFixedSegments = fixedSegments.filter(isTrailingFixedSegment)
        let scrollableSegments = segments.filter { !isFixedSegment($0) }
        let laneItems = headerLaneItems(data: data, activeTabId: activeTabId, segments: scrollableSegments)
        let model = NotebookGridRenderModel(
            key: key,
            fixedSegments: leadingFixedSegments,
            trailingFixedSegments: trailingFixedSegments,
            scrollableSegments: scrollableSegments,
            laneItems: laneItems,
            hasGroupedHeaders: !isCompact && laneItems.contains {
                if case .folder = $0 { return true }
                return false
            }
        )
        renderCache = model
        return model
    }

    func visibleRows(
        data: NotebookUiStateData,
        activeTabId: String?,
        groupByWorkGroupMode: String,
        searchText: String,
        selectedGroupId: Int64?
    ) -> [NotebookTableRow] {
        let key = NotebookVisibleRowsCache.Key(
            classId: data.sheet.classId,
            activeTabId: activeTabId,
            groupByWorkGroupMode: groupByWorkGroupMode,
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedGroupId: selectedGroupId,
            rowsVersion: Self.version(data.sheet.rows.map { "\($0.student.id):\($0.student.firstName):\($0.student.lastName):\($0.weightedAverage ?? -1)" }),
            groupsVersion: Self.version(data.sheet.workGroups.map { "\($0.id):\($0.tabId):\($0.order):\($0.learningSituationId?.int64Value ?? -1)" }),
            membersVersion: Self.version(data.sheet.workGroupMembers.map { "\($0.tabId):\($0.groupId):\($0.studentId)" })
        )
        if let rowsCache, rowsCache.key == key {
            NotebookGridPerformanceDebug.event("visibleRows hit")
            return rowsCache.rows
        }

        let rows = NotebookGridPerformanceDebug.measure("visibleRows build") {
            buildVisibleRows(
                data: data,
                activeTabId: activeTabId,
                groupByWorkGroupMode: groupByWorkGroupMode,
                searchText: key.searchText,
                selectedGroupId: selectedGroupId
            )
        }
        rowsCache = NotebookVisibleRowsCache(key: key, rows: rows)
        return rows
    }

    func visibleCategories(
        data: NotebookUiStateData,
        activeTabId: String?
    ) -> [NotebookColumnCategory] {
        data.sheet.columnCategories
            .filter { activeTabId == nil || $0.tabId == activeTabId }
            .sorted { $0.order < $1.order }
    }

    func managedColumns(
        data: NotebookUiStateData,
        activeTabId: String?,
        viewPreset: NotebookViewPreset
    ) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { columnMatchesActiveTab($0, activeTabId: activeTabId) }
            .filter { columnMatchesViewPreset($0, viewPreset: viewPreset) }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func columns(
        in category: NotebookColumnCategory,
        data: NotebookUiStateData,
        activeTabId: String?,
        viewPreset: NotebookViewPreset,
        includeHidden: Bool = false
    ) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { $0.categoryId == category.id }
            .filter { includeHidden || $0.isVisibleInGrid }
            .filter { columnMatchesActiveTab($0, activeTabId: activeTabId) }
            .filter { columnMatchesViewPreset($0, viewPreset: viewPreset) }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }
    }

    func relevantCategories(
        data: NotebookUiStateData,
        activeTabId: String?,
        viewPreset: NotebookViewPreset
    ) -> [NotebookColumnCategory] {
        visibleCategories(data: data, activeTabId: activeTabId)
            .filter {
                !columns(
                    in: $0,
                    data: data,
                    activeTabId: activeTabId,
                    viewPreset: viewPreset,
                    includeHidden: true
                ).isEmpty
            }
    }

    func displaySegments(
        data: NotebookUiStateData,
        activeTabId: String?,
        viewPreset: NotebookViewPreset
    ) -> [NotebookDisplaySegment] {
        var segments = fixedSegmentsForCurrentView().map(NotebookDisplaySegment.fixed)
        let categories = visibleCategories(data: data, activeTabId: activeTabId)
        let visibleCategorizedIds = Set(categories.map(\.id))

        let uncategorizedColumns = data.sheet.columns
            .filter(\.isVisibleInGrid)
            .filter { columnMatchesActiveTab($0, activeTabId: activeTabId) }
            .filter { columnMatchesViewPreset($0, viewPreset: viewPreset) }
            .filter { column in
                guard let categoryId = column.categoryId else { return true }
                return !visibleCategorizedIds.contains(categoryId)
            }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }

        segments.append(contentsOf: uncategorizedColumns.map(NotebookDisplaySegment.column))

        for category in categories {
            let visibleCategoryColumns = columns(
                in: category,
                data: data,
                activeTabId: activeTabId,
                viewPreset: viewPreset
            )
            let allCategoryColumns = columns(
                in: category,
                data: data,
                activeTabId: activeTabId,
                viewPreset: viewPreset,
                includeHidden: true
            )

            if visibleCategoryColumns.isEmpty || isCategoryCollapsed(category) {
                segments.append(.collapsedCategory(category, allCategoryColumns))
            } else {
                segments.append(contentsOf: visibleCategoryColumns.map(NotebookDisplaySegment.column))
            }
        }
        return segments
    }

    func visibleFixedSegments(in segments: [NotebookDisplaySegment]) -> [NotebookDisplaySegment] {
        let allowedColumns = visibleFixedColumns
        return segments.filter { segment in
            guard case .fixed(let fixed) = segment else { return false }
            if fixed == .average {
                return true
            }
            return allowedColumns.contains(fixed)
        }
    }

    func headerLaneItems(data: NotebookUiStateData, activeTabId: String?, segments: [NotebookDisplaySegment]) -> [NotebookHeaderLaneItem] {
        var items: [NotebookHeaderLaneItem] = []
        let categoriesById = Dictionary(
            visibleCategories(data: data, activeTabId: activeTabId).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var index = 0
        while index < segments.count {
            let segment = segments[index]
            switch segment {
            case .fixed(let fixed):
                items.append(.spacer(id: "fixed_\(fixed.id)", width: defaultFixedWidth(for: fixed)))
                index += 1
            case .collapsedCategory:
                items.append(.spacer(id: segment.id, width: segmentWidth(segment)))
                index += 1
            case .column(let column):
                guard let categoryId = column.categoryId,
                      let category = categoriesById[categoryId],
                      !isCategoryCollapsed(category) else {
                    items.append(.spacer(id: segment.id, width: segmentWidth(segment)))
                    index += 1
                    continue
                }

                var runColumns: [NotebookColumnDefinition] = []
                var runWidth: CGFloat = 0
                var cursor = index

                while cursor < segments.count {
                    guard case .column(let runColumn) = segments[cursor],
                          runColumn.categoryId == categoryId else {
                        break
                    }

                    if !runColumns.isEmpty {
                        runWidth += 8
                    }
                    runColumns.append(runColumn)
                    runWidth += segmentWidth(.column(runColumn))
                    cursor += 1
                }

                items.append(.folder(category, runColumns, runWidth))
                index = cursor
            }
        }
        return items
    }

    func fixedSegmentsForCurrentView() -> [NotebookFixedColumn] {
        let mode = UserDefaults.standard.string(forKey: "notebook.groupByWorkGroupMode") ?? "none"
        if mode != "none" {
            return [.name, .group, .average]
        }
        return [.name, .average]
    }

    var visibleFixedColumns: [NotebookFixedColumn] {
        let mode = UserDefaults.standard.string(forKey: "notebook.groupByWorkGroupMode") ?? "none"
        if mode != "none" {
            return [.name, .group]
        }
        return [.name]
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

    func segmentWidth(_ segment: NotebookDisplaySegment, fixedZoneWidth: CGFloat) -> CGFloat {
        switch segment {
        case .fixed(let fixed):
            return resolvedFixedWidth(for: fixed, fixedZoneWidth: fixedZoneWidth)
        case .column(let column):
            return resolvedColumnWidth(for: column)
        case .collapsedCategory:
            return Metrics.collapsedCategoryWidth
        }
    }

    func segmentWidth(_ segment: NotebookDisplaySegment) -> CGFloat {
        switch segment {
        case .fixed(let fixed):
            return defaultFixedWidth(for: fixed)
        case .column(let column):
            return resolvedColumnWidth(for: column)
        case .collapsedCategory:
            return Metrics.collapsedCategoryWidth
        }
    }

    func resolvedFixedWidth(for fixed: NotebookFixedColumn, fixedZoneWidth: CGFloat) -> CGFloat {
        let visibleColumns = visibleFixedColumns
        let trailingColumns = visibleColumns.filter { $0 != .photo && $0 != .name }
        let trailingWidth = trailingColumns.reduce(CGFloat.zero) { partial, column in
            partial + defaultFixedWidth(for: column)
        }
        let spacing = CGFloat(max(visibleColumns.count - 1, 0)) * NotebookStyle.controlSpacing
        let photoWidth: CGFloat = visibleColumns.contains(.photo) ? 52 : 0

        switch fixed {
        case .photo:
            return 52
        case .name:
            let availableWidth = fixedZoneWidth - trailingWidth - spacing - Metrics.fixedZoneHorizontalPadding - photoWidth
            return max(CGFloat(156), availableWidth)
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
        case .average: return 110
        }
    }

    func resolvedColumnWidth(for column: NotebookColumnDefinition) -> CGFloat {
        columnWidths[column.id] ?? CGFloat(max(column.widthDp, Double(Metrics.defaultColumnWidth)))
    }

    func updateColumnWidth(_ column: NotebookColumnDefinition, width: CGFloat) -> CGFloat {
        let clampedWidth = min(Metrics.maximumColumnWidth, max(Metrics.minimumColumnWidth, width))
        columnWidths[column.id] = clampedWidth
        return clampedWidth
    }

    private func columnMatchesViewPreset(_ column: NotebookColumnDefinition, viewPreset: NotebookViewPreset) -> Bool {
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

    private func columnMatchesActiveTab(_ column: NotebookColumnDefinition, activeTabId: String?) -> Bool {
        guard let activeTabId else { return true }
        return column.tabIds.contains(activeTabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty)
    }

    private var collapsedCategoryStorageKey: String {
        "notebook.collapsed.categories.\(storageClassKey)"
    }

    private static func loadCollapsedCategoryIds(storageKey: String) -> Set<String> {
        Set(
            UserDefaults.standard
                .string(forKey: storageKey)?
                .split(separator: ",")
                .map(String.init) ?? []
        )
    }

    private static func version(_ parts: [String]) -> Int {
        parts.sorted().reduce(17) { partial, part in
            partial &* 31 &+ part.hashValue
        }
    }

    private func buildVisibleRows(
        data: NotebookUiStateData,
        activeTabId: String?,
        groupByWorkGroupMode: String,
        searchText: String,
        selectedGroupId: Int64?
    ) -> [NotebookTableRow] {
        let rows: [NotebookTableRow]
        if groupByWorkGroupMode != "none" {
            let activeGroups: [NotebookWorkGroup]

            if groupByWorkGroupMode == "general" {
                activeGroups = data.sheet.workGroups.filter {
                    ($0.tabId == activeTabId || activeTabId == nil) && $0.learningSituationId == nil
                }
            } else if groupByWorkGroupMode.hasPrefix("situation_"),
                      let sitId = Int64(groupByWorkGroupMode.dropFirst(10)) {
                activeGroups = data.sheet.workGroups.filter {
                    ($0.tabId == activeTabId || activeTabId == nil) && $0.learningSituationId?.int64Value == sitId
                }
            } else {
                activeGroups = data.sheet.workGroups.filter { $0.tabId == activeTabId || activeTabId == nil }
            }

            let sortedActiveGroups = activeGroups.sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }

            var resultRows: [NotebookTableRow] = []
            var groupedStudentIds = Set<Int64>()

            for group in sortedActiveGroups {
                let memberIds = Set(data.sheet.workGroupMembers
                    .filter { $0.groupId == group.id && ($0.tabId == activeTabId || activeTabId == nil) }
                    .map(\.studentId))

                let groupRows = data.sheet.rows.filter { memberIds.contains($0.student.id) }
                for row in groupRows {
                    groupedStudentIds.insert(row.student.id)
                    resultRows.append(NotebookTableRow(student: row.student, row: row, groupName: group.name))
                }
            }

            let ungroupedRows = data.sheet.rows.filter { !groupedStudentIds.contains($0.student.id) }
            let sortedUngrouped = ungroupedRows.sorted {
                let name1 = "\($0.student.lastName) \($0.student.firstName)"
                let name2 = "\($1.student.lastName) \($1.student.firstName)"
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
            rows = resultRows + sortedUngrouped.map { NotebookTableRow(student: $0.student, row: $0, groupName: "Sin grupo") }
        } else {
            rows = data.sheet.rows.map { row in
                let memberGroupId = data.sheet.workGroupMembers.first(where: {
                    $0.studentId == row.student.id && ($0.tabId == activeTabId || activeTabId == nil)
                })?.groupId
                let groupName = memberGroupId.flatMap { groupId in
                    data.sheet.workGroups.first(where: { $0.id == groupId })?.name
                } ?? "Sin grupo"
                return NotebookTableRow(student: row.student, row: row, groupName: groupName)
            }
            .sorted {
                let name1 = "\($0.student.lastName) \($0.student.firstName)"
                let name2 = "\($1.student.lastName) \($1.student.firstName)"
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        }

        return rows.filter { item in
            let matchesSearch = searchText.isEmpty || "\(item.student.firstName) \(item.student.lastName)".localizedCaseInsensitiveContains(searchText)
            let matchesGroup = selectedGroupId == nil || groupId(for: item.student.id, activeTabId: activeTabId, data: data) == selectedGroupId
            return matchesSearch && matchesGroup
        }
    }

    private func groupId(for studentId: Int64, activeTabId: String?, data: NotebookUiStateData) -> Int64? {
        data.sheet.workGroupMembers
            .first(where: { $0.studentId == studentId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .groupId
    }
}

enum NotebookGridPerformanceDebug {
    static var enabled = false

    static func measure<T>(_ label: String, work: () -> T) -> T {
        guard enabled else { return work() }
        let start = Date().timeIntervalSinceReferenceDate
        let value = work()
        let elapsed = (Date().timeIntervalSinceReferenceDate - start) * 1000
        print("NotebookPerf \(label) \(String(format: "%.1f", elapsed))ms")
        return value
    }

    static func event(_ label: String) {
        guard enabled else { return }
        print("NotebookPerf \(label)")
    }
}

struct NotebookGridRenderModel {
    struct Key: Equatable {
        let classId: Int64
        let activeTabId: String?
        let viewPreset: String
        let isCompact: Bool
        let columnsVersion: Int
        let categoriesVersion: Int
        let collapsedCategoriesVersion: Int
        let fixedMode: String
    }

    let key: Key
    let fixedSegments: [NotebookDisplaySegment]
    let trailingFixedSegments: [NotebookDisplaySegment]
    let scrollableSegments: [NotebookDisplaySegment]
    let laneItems: [NotebookHeaderLaneItem]
    let hasGroupedHeaders: Bool
}

private struct NotebookVisibleRowsCache {
    struct Key: Equatable {
        let classId: Int64
        let activeTabId: String?
        let groupByWorkGroupMode: String
        let searchText: String
        let selectedGroupId: Int64?
        let rowsVersion: Int
        let groupsVersion: Int
        let membersVersion: Int
    }

    let key: Key
    let rows: [NotebookTableRow]
}

extension NotebookModuleView {
    func isNotebookAICommentColumn(_ column: NotebookColumnDefinition) -> Bool {
        bridge.isNotebookAICommentColumn(column)
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

    func isFixedSegment(_ segment: NotebookDisplaySegment) -> Bool {
        gridLayoutModel.isFixedSegment(segment)
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

    func updateColumnWidth(_ column: NotebookColumnDefinition, width: CGFloat) {
        let clampedWidth = gridLayoutModel.updateColumnWidth(column, width: width)
        saveColumnMutation(column, widthDp: Double(clampedWidth))
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
        let configs = updates.map { update in
            NotebookAverageColumnConfig(
                columnId: update.column.id,
                countsTowardAverage: update.isIncluded,
                weight: update.isIncluded ? update.weight : 0,
                emptyCellPolicy: update.column.emptyCellPolicy
            )
        }
        bridge.saveAverageConfiguration(updates: configs)
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
