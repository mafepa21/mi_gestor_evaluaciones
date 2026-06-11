import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    var currentClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == bridge.notebookViewModel.currentClassId?.int64Value ?? 0 })
    }

    var notebookSupportRefreshKey: String {
        "\(selectedClassId ?? -1)|\(bridge.selectedNotebookTabId ?? "all")"
    }

    var semanticInspectorIcons: [String] {
        ["", "✅", "⭐", "⚠️", "🏠", "🧩", "📌", "💬"]
    }

    var saveBadge: (text: String, icon: String, color: Color) {
        if bridge.notebookSaveState == .saved {
            return ("Guardado", "checkmark.circle.fill", .secondary)
        } else if bridge.notebookSaveState == .saving {
            return ("Guardando…", "arrow.triangle.2.circlepath", .secondary)
        } else if bridge.notebookSaveState == .unsaved {
            return ("Sin guardar", "circle.dotted", Color.orange)
        }
        return ("Estado pendiente", "circle", .secondary)
    }

    var sortedClasses: [SchoolClass] {
        bridge.classes.sorted {
            if $0.course != $1.course { return $0.course < $1.course }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var activeClassLabel: String {
        guard let currentClass else { return "Seleccionar clase" }
        return classLabel(for: currentClass)
    }

    func classLabel(for schoolClass: SchoolClass) -> String {
        "\(schoolClass.name) · \(schoolClass.course)º"
    }

    func headerContextLine(in data: NotebookUiStateData) -> String {
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

    func orderedNotebookTabs(data: NotebookUiStateData) -> [NotebookTab] {
        let rootTabs = data.sheet.tabs.filter { $0.parentTabId == nil }
        let source = rootTabs.isEmpty ? data.sheet.tabs : rootTabs
        return source.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    func activeNotebookTabId(data: NotebookUiStateData) -> String? {
        let tabs = orderedNotebookTabs(data: data)
        if let selected = bridge.selectedNotebookTabId,
           tabs.contains(where: { $0.id == selected }) {
            return selected
        }
        return tabs.first?.id
    }

    func activeNotebookTab(data: NotebookUiStateData) -> NotebookTab? {
        guard let activeTabId = activeNotebookTabId(data: data) else { return nil }
        return data.sheet.tabs.first { $0.id == activeTabId }
    }

    func ensureActiveNotebookTab(data: NotebookUiStateData) {
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

    func scheduleActiveNotebookTabSync(data: NotebookUiStateData) {
        Task { @MainActor in
            await Task.yield()
            ensureActiveNotebookTab(data: data)
        }
    }

    func selectNotebookTab(_ tabId: String) {
        selectedGroupId = nil
        inspectorSelection = nil
        isInspectorPresented = false
        focusMode = .normal
        highlightedRandomStudentId = nil
        bridge.setSelectedNotebookTab(id: tabId)
    }

    func selectNotebookClass(_ classId: Int64) {
        guard bridge.notebookViewModel.currentClassId?.int64Value != classId else { return }
        selectedGroupId = nil
        isInspectorPresented = false
        inspectorSelection = nil
        inspectorNoteDraft = ""
        inspectorIconDraft = ""
        inspectorAttachmentUris = []
        focusMode = .normal
        highlightedRandomStudentId = nil
        searchText = ""
        selectedClassId = classId
        bridge.selectClass(id: classId)
    }

    func syncToolbarState(data: NotebookUiStateData) {
        let inspectorAvailable = inspectorSelection != nil || !managedColumns(data: data).isEmpty
        let canMarkAllPresent = !filteredRows(data: data).isEmpty

        layoutState.configureNotebookToolbar(
            inspectorAvailable: inspectorAvailable,
            isInspectorPresented: isInspectorPresented,
            addColumnAvailable: true,
            searchText: searchText,
            surfaceMode: surfaceMode.rawValue,
            selectedGroupId: selectedGroupId,
            availableGroups: groupedRows(data: data).map {
                NotebookToolbarGroupOption(id: $0.id, name: $0.name, studentCount: memberCount($0.id, in: data))
            },
            organizationMenuAvailable: true,
            canUndo: !undoStack.isEmpty,
            isAttendanceQuickMode: isAttendanceQuickMode,
            canMarkAllPresent: canMarkAllPresent,
            exportText: exportText(data: data),
            onToggleInspector: {
                if inspectorSelection == nil {
                    openInspectorForSelection(data)
                }
                if inspectorSelection != nil {
                    isInspectorPresented.toggle()
                    focusMode = isInspectorPresented ? .reviewing : .normal
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
            onMarkAllPresent: {
                requestMarkAllVisibleStudentsPresent(data: data)
            },
            onRefresh: {
                Task {
                    await refreshNotebookSignals()
                }
            },
            onGenerateSummary: {
                notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: nil)
            }
        )

        macToolbarActions?.configure(
            canMarkAllPresent: canMarkAllPresent,
            canUndo: !undoStack.isEmpty,
            canToggleInspector: inspectorAvailable,
            isAttendanceQuickMode: isAttendanceQuickMode,
            isInspectorPresented: isInspectorPresented,
            addColumnAvailable: true,
            organizationMenuAvailable: true,
            groupManagementAvailable: true,
            exportText: exportText(data: data),
            onMarkAllPresent: {
                requestMarkAllVisibleStudentsPresent(data: data)
            },
            onToggleAttendanceQuickMode: {
                isAttendanceQuickMode.toggle()
                if isAttendanceQuickMode {
                    activeChoiceCellId = nil
                    focusedCellId = nil
                }
            },
            onUndo: {
                undoLastCellChange()
            },
            onToggleInspector: {
                if inspectorSelection == nil {
                    openInspectorForSelection(data)
                }
                if inspectorSelection != nil {
                    isInspectorPresented.toggle()
                    focusMode = isInspectorPresented ? .reviewing : .normal
                }
            },
            onAddColumn: {
                addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
            },
            onOpenOrganizationMenu: {
                isOrganizationMenuPresented = true
            },
            onOpenGroupManagement: {
                isGroupManagementPresented = true
            },
            onOpenAdvancedMenu: {
                isOrganizationMenuPresented = true
            },
            onGenerateSummary: {
                notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: nil)
            },
            onRefresh: {
                Task { await refreshNotebookSignals() }
            }
        )
    }

    func syncToolbarStateIfLoaded() {
        guard !isMacInspectorOnly,
              let data = bridge.notebookState as? NotebookUiStateData else { return }
        syncToolbarState(data: data)
    }

    func scheduleToolbarStateSync(data: NotebookUiStateData) {
        guard !isMacInspectorOnly else { return }

        let nextKey = toolbarStateKey(data: data)
        guard lastToolbarStateKey != nextKey else { return }

        toolbarSyncTask?.cancel()
        toolbarSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            lastToolbarStateKey = nextKey
            syncToolbarState(data: data)
        }
    }

    func scheduleToolbarStateSyncIfLoaded() {
        guard !isMacInspectorOnly,
              let data = bridge.notebookState as? NotebookUiStateData else { return }
        scheduleToolbarStateSync(data: data)
    }

    func toolbarStateKey(data: NotebookUiStateData) -> String {
        let classKey = currentClass?.id ?? -1
        let groupKey = selectedGroupId ?? -1
        let inspectorKey = inspectorSelection?.id ?? "none"
        return "\(classKey)|\(groupKey)|\(surfaceMode.rawValue)|\(managedColumns(data: data).count)|\(filteredRows(data: data).count)|\(inspectorKey)|\(isInspectorPresented)|\(undoStack.count)|\(isAttendanceQuickMode)|\(bridge.notebookSaveState)"
    }

    var notebookRiskRefreshKey: String {
        guard let data = bridge.notebookState as? NotebookUiStateData else {
            return "empty|\(selectedClassId ?? -1)"
        }
        let rows = filteredRows(data: data)
        return "\(selectedClassId ?? -1)|\(selectedGroupId ?? -1)|\(bridge.selectedNotebookTabId ?? "all")|\(rows.map { String($0.student.id) }.joined(separator: ","))"
    }

    @MainActor
    func precomputeRiskLevelsForVisibleRows() async {
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
            } catch {
                nextCache[item.student.id] = .seguimientoNormal
            }
            await Task.yield()
        }
        riskLevelCache = nextCache
    }

}
