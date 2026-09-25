//
//  KmpBridge+Notebook.swift
//  MiGestorKMP
//
//  Created for modularization of KmpBridge.
//

import Foundation
import Combine
import MiGestorKit
import SwiftUI

@MainActor
extension KmpBridge {
    func selectClass(id: Int64) {
        let restoredTabId = restoredSelectedNotebookTab(forClassId: id)
        selectedNotebookTabId = restoredTabId
        notebookViewModel.setSelectedTabId(tabId: restoredTabId)
        notebookViewModel.selectClass(classId: id, force: true)
    }

    var currentNotebookClassId: Int64? {
        notebookViewModel.currentClassId?.int64Value
    }

    func setSelectedNotebookTab(id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        selectedNotebookTabId = normalized
        notebookViewModel.setSelectedTabId(tabId: normalized)
        rememberSelectedNotebookTab(normalized, forClassId: notebookViewModel.currentClassId?.int64Value)
    }
    
    func saveColumnGrade(studentId: Int64, column: NotebookColumnDefinition, value: String) {
        let key = cellKey(studentId: studentId, columnId: column.id)
        if column.type == .numeric || column.type == .rubric || column.type == .calculated {
            optimisticGradeDrafts[key] = value
            if let evalId = column.evaluationId?.int64Value {
                optimisticGradeDrafts[cellKey(studentId: studentId, columnId: "eval_\(evalId)")] = value
            }
        } else {
            optimisticTextDrafts[key] = value
        }
        notebookViewModel.saveColumnGrade(studentId: studentId, column: column, value: value)
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func saveColumnGradeDebounced(
        studentId: Int64,
        column: NotebookColumnDefinition,
        value: String
    ) {
        let key = cellKey(studentId: studentId, columnId: column.id)
        if column.type == .numeric || column.type == .rubric || column.type == .calculated {
            optimisticGradeDrafts[key] = value
            if let evalId = column.evaluationId?.int64Value {
                optimisticGradeDrafts[cellKey(studentId: studentId, columnId: "eval_\(evalId)")] = value
            }
        } else {
            optimisticTextDrafts[key] = value
        }
        notebookViewModel.saveColumnGrade(studentId: studentId, column: column, value: value)
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func flushPendingColumnGradeSave(studentId: Int64, columnId: String? = nil) {
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func saveNotebook() {
        notebookViewModel.saveCurrentNotebook(completionHandler: { [weak self] saved, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.status = "Error al guardar cuaderno: \(error.localizedDescription)"
                    return
                }

                let didSave = saved?.boolValue ?? false
                self.status = didSave ? "Cuaderno guardado" : "No se pudo guardar el cuaderno"
                if didSave, let classId = self.notebookViewModel.currentClassId?.int64Value {
                    self.scheduleNotebookSnapshotSync(forClassId: classId)
                }
            }
        })
    }
    
    func addStudent(firstName: String, lastName: String, isInjured: Bool) {
        notebookViewModel.addStudent(firstName: firstName, lastName: lastName, isInjured: isInjured)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func deleteStudent(id: Int64) {
        let classId = notebookViewModel.currentClassId?.int64Value
        
        // Encolar borrado explícito
        enqueueLocalChange(
            entity: "student",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        
        notebookViewModel.deleteStudent(studentId: id)
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func saveColumn(column: NotebookColumnDefinition) {
        notebookViewModel.saveColumn(column: column)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveAverageConfiguration(updates: [NotebookAverageColumnConfig]) {
        notebookViewModel.saveAverageConfiguration(updates: updates)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func reorderNotebookColumn(columnId: String, targetColumnId: String) {
        notebookViewModel.reorderColumns(columnId: columnId, targetColumnId: targetColumnId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    
    func saveTab(tab: NotebookTab) {
        notebookViewModel.saveTab(tab: tab)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveTabFixedWidth(tabId: String, widthDp: Double) {
        notebookViewModel.saveTabFixedWidth(tabId: tabId, widthDp: widthDp)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveNotebookWorkGroup(name: String, learningSituationId: Int64? = nil, studentIds: [Int64] = [], tabId: String? = nil) {
        let situationKotlin = KotlinLong(value: learningSituationId ?? -1)
        let studentsKotlin = studentIds.map { KotlinLong(value: $0) }
        notebookViewModel.saveWorkGroup(name: name, groupId: nil, studentIds: studentsKotlin, learningSituationId: situationKotlin, tabId: tabId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func updateNotebookWorkGroup(groupId: Int64, name: String, learningSituationId: Int64? = nil, studentIds: [Int64] = [], tabId: String? = nil) {
        let situationKotlin = KotlinLong(value: learningSituationId ?? -1)
        let studentsKotlin = studentIds.map { KotlinLong(value: $0) }
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: studentsKotlin, learningSituationId: situationKotlin, tabId: tabId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func renameNotebookWorkGroup(groupId: Int64, name: String) {
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: [], learningSituationId: nil, tabId: nil)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteNotebookWorkGroup(groupId: Int64) {
        notebookViewModel.deleteWorkGroup(groupId: groupId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func assignStudentToNotebookGroup(groupName: String?, studentId: Int64) {
        notebookViewModel.assignStudentToWorkGroup(groupName: groupName, studentId: studentId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func assignStudentsToNotebookGroup(groupId: Int64?, studentIds: [Int64], tabId: String? = nil) {
        notebookViewModel.assignStudentsToWorkGroup(
            groupId: groupId.map { KotlinLong(value: $0) },
            studentIds: studentIds.map { KotlinLong(value: $0) },
            tabId: tabId
        )
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func importNotebookWorkGroups(
        classId: Int64,
        tabId: String,
        groups: [(name: String, studentIds: [Int64], learningSituationId: Int64?)],
        clearExisting: Bool = false
    ) async throws {
        let batchItems: [NotebookWorkGroupBatchItem] = groups.map { item in
            NotebookWorkGroupBatchItem(
                name: item.name,
                studentIds: item.studentIds.map { KotlinLong(value: $0) },
                learningSituationId: item.learningSituationId.map { KotlinLong(value: $0) }
            )
        }
        try await container.notebookRepository.replaceWorkGroups(
            classId: classId,
            tabId: tabId,
            groups: batchItems,
            clearExisting: clearExisting
        )
        await MainActor.run {
            self.notebookViewModel.selectClass(classId: classId, force: true)
            self.scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    @discardableResult
    func autoComposeNotebookWorkGroups(
        groupCount: Int32,
        strategy: String,
        mixSex: Bool,
        spreadInjured: Bool,
        learningSituationId: Int64? = nil,
        tabId: String? = nil,
        clearExisting: Bool = true
    ) -> [ComposedWorkGroup] {
        let situationKotlin = learningSituationId.map { KotlinLong(value: $0) }
        let composed = notebookViewModel.autoComposeWorkGroups(
            groupCount: groupCount,
            strategy: strategy,
            mixSex: mixSex,
            spreadInjured: spreadInjured,
            learningSituationId: situationKotlin,
            tabId: tabId,
            clearExisting: clearExisting
        )
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
        return composed
    }
    
    func createTab(title: String, parentTabId: String? = nil) -> String? {
        guard let classId = notebookViewModel.currentClassId?.int64Value else { return nil }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        let tabId = "tab_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: nil,
            deviceId: nil,
            syncVersion: 0
        )
        let tabs = (notebookState as? NotebookUiStateData)?.sheet.tabs ?? []
        let siblingCount = tabs.filter { $0.parentTabId == parentTabId }.count
        let order = Int32(siblingCount)
        let newTab = NotebookTab(id: tabId, title: normalizedTitle, description: nil, order: order, parentTabId: parentTabId, fixedColumnWidth: nil, trace: trace)
        notebookViewModel.saveTab(tab: newTab)
        notebookViewModel.selectClass(classId: classId, force: true)
        scheduleNotebookSnapshotSync(forClassId: classId)
        return tabId
    }
    
    func deleteTab(id: String) {
        let classId = notebookViewModel.currentClassId?.int64Value
        // Encolar borrado para sincronización antes de eliminar localmente
        enqueueLocalChange(
            entity: "notebook_tab",
            id: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        
        notebookViewModel.deleteTab(tabId: id)
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func confirmAndAdvance(studentIndex: Int32, column: NotebookColumnDefinition, value: String) {
        notebookViewModel.confirmAndAdvance(studentIndex: studentIndex, column: column, value: value)
    }

    func addColumn(
        name: String,
        type: String,
        weight: Double,
        formula: String?,
        rubricId: Int64?,
        categoryId: String? = nil,
        categoryKind: NotebookColumnCategoryKind = .custom,
        instrumentKind: NotebookInstrumentKind = .custom,
        inputKind: NotebookCellInputKind = .text,
        dateEpochMs: Int64? = nil,
        unitOrSituation: String? = nil,
        competencyCriteriaIds: [Int64] = [],
        scaleKind: NotebookScaleKind = .custom,
        iconName: String? = nil,
        countsTowardAverage: Bool = true,
        isPinned: Bool = false,
        isHidden: Bool = false,
        visibility: NotebookColumnVisibility = .visible,
        isLocked: Bool = false,
        isTemplate: Bool = false
    ) {
        let classId = notebookViewModel.currentClassId?.int64Value
        notebookViewModel.addColumn(
            name: name,
            type: type,
            weight: weight,
            formula: formula,
            rubricId: rubricId.map { KotlinLong(value: $0) },
            categoryId: categoryId,
            categoryKind: categoryKind,
            instrumentKind: instrumentKind,
            inputKind: inputKind,
            dateEpochMs: dateEpochMs.map { KotlinLong(value: $0) },
            unitOrSituation: unitOrSituation,
            competencyCriteriaIds: competencyCriteriaIds.map { KotlinLong(value: $0) },
            scaleKind: scaleKind,
            iconName: iconName,
            countsTowardAverage: countsTowardAverage,
            isPinned: isPinned,
            isHidden: isHidden,
            visibility: visibility,
            isLocked: isLocked,
            isTemplate: isTemplate
        )
        // iOS-specific safety refresh to reflect new columns immediately.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            refreshCurrentNotebook()
        }
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func addColumnWithOptionalCategory(
        name: String,
        type: String,
        weight: Double,
        formula: String?,
        rubricId: Int64?,
        categoryId: String? = nil,
        newCategoryName: String? = nil,
        categoryKind: NotebookColumnCategoryKind = .custom,
        instrumentKind: NotebookInstrumentKind = .custom,
        inputKind: NotebookCellInputKind = .text,
        dateEpochMs: Int64? = nil,
        unitOrSituation: String? = nil,
        competencyCriteriaIds: [Int64] = [],
        scaleKind: NotebookScaleKind = .custom,
        iconName: String? = nil,
        countsTowardAverage: Bool = true,
        isPinned: Bool = false,
        isHidden: Bool = false,
        visibility: NotebookColumnVisibility = .visible,
        isLocked: Bool = false,
        isTemplate: Bool = false
    ) async throws -> NotebookCreatedColumnResult {
        guard let classId = notebookViewModel.currentClassId?.int64Value else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No hay clase activa."])
        }

        let currentData = notebookState as? NotebookUiStateData
        let tabs = currentData?.sheet.tabs ?? []
        let selectedTab = selectedNotebookTabId ?? tabs.first?.id
        let resolvedTabIds = selectedTab.map { [$0] } ?? []
        let existingCategories = currentData?.sheet.columnCategories ?? []
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let finalCategory: NotebookColumnCategory?
        if let rawName = newCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let tabId = selectedTab ?? tabs.first?.id ?? "TAB_\(classId)"
            let nextOrder = (existingCategories.filter { $0.tabId == tabId }.map(\.order).max() ?? -1) + 1
            let category = NotebookColumnCategory(
                id: "cat_\(nowMs)",
                classId: classId,
                tabId: tabId,
                name: rawName,
                order: nextOrder,
                isCollapsed: false,
                trace: trace
            )
            try await container.notebookRepository.saveColumnCategory(classId: classId, category: category)
            finalCategory = category
        } else if let categoryId {
            finalCategory = existingCategories.first(where: { $0.id == categoryId })
        } else {
            finalCategory = nil
        }

        let columnType = notebookColumnType(from: type)
        let needsEvaluation = columnType == .numeric || columnType == .rubric
        let evaluationId: Int64?
        if needsEvaluation {
            let savedEvaluationId = try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: "COL_\(nowMs)",
                name: name,
                type: columnType == .rubric ? "Rúbrica" : "Evaluación",
                weight: weight,
                formula: nil,
                rubricId: rubricId.map { KotlinLong(value: $0) },
                description: nil,
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
            evaluationId = savedEvaluationId.int64Value
        } else {
            evaluationId = nil
        }
        let columnId = evaluationId.map { "eval_\($0)" } ?? "COL_\(nowMs)"
        let nextOrder = (currentData?.sheet.columns.map(\.order).max() ?? -1) + 1
        let column = NotebookColumnDefinition(
            id: columnId,
            title: name,
            type: columnType,
            categoryKind: categoryKind,
            instrumentKind: instrumentKind,
            inputKind: inputKind,
            evaluationId: evaluationId.map { KotlinLong(value: $0) },
            rubricId: rubricId.map { KotlinLong(value: $0) },
            formula: columnType == .calculated ? formula?.nilIfEmpty : nil,
            weight: weight,
            dateEpochMs: dateEpochMs.map { KotlinLong(value: $0) },
            unitOrSituation: unitOrSituation?.nilIfEmpty,
            competencyCriteriaIds: competencyCriteriaIds.map { KotlinLong(value: $0) },
            scaleKind: scaleKind,
            tabIds: resolvedTabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: iconName,
            order: nextOrder,
            widthDp: 132,
            categoryId: finalCategory?.id ?? categoryId,
            ordinalLevels: defaultOrdinalLevels(
                columnType: columnType,
                instrumentKind: instrumentKind,
                scaleKind: scaleKind
            ),
            availableIcons: [],
            countsTowardAverage: countsTowardAverage,
            isPinned: isPinned,
            isHidden: isHidden,
            visibility: visibility,
            isLocked: isLocked,
            isTemplate: isTemplate,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
        return NotebookCreatedColumnResult(column: column, category: finalCategory)
    }

    private func defaultOrdinalLevels(
        columnType: NotebookColumnType,
        instrumentKind: NotebookInstrumentKind,
        scaleKind: NotebookScaleKind
    ) -> [String] {
        guard columnType == .ordinal else { return [] }
        if instrumentKind == .participation, scaleKind == .achievement {
            return ["Excelente", "Bien", "En proceso", "No logrado"]
        }
        return []
    }

    func saveNotebookCellAnnotation(
        studentId: Int64,
        columnId: String,
        note: String,
        iconValue: String? = nil,
        attachmentUris: [String] = []
    ) {
        let key = cellKey(studentId: studentId, columnId: columnId)
        optimisticAnnotations[key] = OptimisticAnnotation(
            note: note.nilIfEmpty,
            icon: iconValue?.nilIfEmpty,
            attachmentUris: attachmentUris
        )
        lastNotebookAggregateSignature = nil
        notebookViewModel.saveCellAnnotation(
            studentId: studentId,
            columnId: columnId,
            note: note.nilIfEmpty,
            iconValue: iconValue?.nilIfEmpty,
            attachmentUris: attachmentUris
        )
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveColumnCategory(name: String, categoryId: String? = nil) {
        notebookViewModel.saveColumnCategory(name: name, categoryId: categoryId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteColumnCategory(id: String, preserveColumns: Bool = true) {
        enqueueLocalChange(
            entity: "notebook_column_category",
            id: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": id,
                "classId": notebookViewModel.currentClassId?.int64Value ?? 0,
                "preserveColumns": preserveColumns
            ],
            op: "delete"
        )

        if !preserveColumns, let data = notebookState as? NotebookUiStateData {
            let categoryColumns = data.sheet.columns.filter { $0.categoryId == id }
            for column in categoryColumns {
                enqueueLocalChange(
                    entity: "notebook_column",
                    id: column.id,
                    updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                    payload: ["id": column.id],
                    op: "delete"
                )
            }
        }

        notebookViewModel.deleteColumnCategory(categoryId: id, preserveColumns: preserveColumns)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func toggleColumnCategory(id: String, collapsed: Bool) {
        notebookViewModel.toggleColumnCategoryCollapsed(categoryId: id, isCollapsed: collapsed)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func assignColumn(_ columnId: String, toCategory categoryId: String?) {
        notebookViewModel.assignColumnToCategory(columnId: columnId, categoryId: categoryId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteColumn(id: String, evaluationId: Int64?) {
        let classId = notebookViewModel.currentClassId?.int64Value
        
        // Encolar borrado explícito
        enqueueLocalChange(
            entity: "notebook_column",
            id: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        
        if let evalId = evaluationId {
            notebookViewModel.deleteColumnByEvaluationId(columnId: evalId)
        } else {
            notebookViewModel.deleteColumnById(columnId: id)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self.refreshCurrentNotebook()
        }
        
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteColumns(idsAndEvalIds: [(id: String, evaluationId: Int64?)]) {
        let classId = notebookViewModel.currentClassId?.int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        
        for item in idsAndEvalIds {
            enqueueLocalChange(
                entity: "notebook_column",
                id: item.id,
                updatedAtEpochMs: nowMs,
                payload: ["id": item.id],
                op: "delete"
            )
            
            if let evalId = item.evaluationId {
                notebookViewModel.deleteColumnByEvaluationId(columnId: evalId)
            } else {
                notebookViewModel.deleteColumnById(columnId: item.id)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self.refreshCurrentNotebook()
        }
        
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func updateColumnWeight(columnId: Int64, newWeight: Double) {
        notebookViewModel.updateColumnWeight(columnId: columnId, newWeight: newWeight)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func loadForNotebookCell(studentId: Int64, columnId: String, rubricId: Int64, evaluationId: Int64) {
        rubricEvaluationViewModel.loadForNotebookCell(studentId: studentId, columnId: columnId, rubricId: rubricId, evaluationId: evaluationId)
    }

    /// Detecta si el `description` de una evaluación es en realidad un volcado del objeto Kotlin
    /// y, si lo es, recupera el texto original que quedó sepultado dentro.
    ///
    /// Durante un tiempo `enqueueNotebookSnapshot` envió por sync `evaluation.description` (el
    /// `description` de NSObject, o sea el `toString` del objeto) en vez del campo real del dominio
    /// `description_`. Cada vez que el bug se disparaba, el volcado anterior se leía como si fuera
    /// la descripción y se envolvía en uno nuevo, así que en las bases de datos ya sincronizadas
    /// hay valores anidados varios niveles:
    ///
    ///     Evaluation(id=35, …, description=Evaluation(id=35, …, description=<texto real>,
    ///                competencyLinks=[], trace=…), competencyLinks=[], trace=…)
    ///
    /// El texto real es siempre el `description=` más interno, es decir el último del volcado, y
    /// termina justo antes de `, competencyLinks=`. Si no se puede extraer con confianza (sigue
    /// pareciendo un volcado, está vacío o es `null`) se devuelve `nil` a propósito: la cascada de
    /// `criterionLabel` cae entonces al código o al nombre de la evaluación, que es preferible a
    /// enseñar basura.
    static func recoveredEvaluationDescription(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("Evaluation(id=") || trimmed.contains("description=Evaluation(") else {
            return trimmed
        }
        guard let markerRange = trimmed.range(of: "description=", options: .backwards) else {
            return nil
        }
        let afterMarker = trimmed[markerRange.upperBound...]
        guard let endRange = afterMarker.range(of: ", competencyLinks=") else {
            return nil
        }
        let inner = afterMarker[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty, inner != "null", !inner.hasPrefix("Evaluation(") else {
            return nil
        }
        return inner
    }

    /// Reescribe en base de datos el `description` de una evaluación cuyo valor guardado es un
    /// volcado del objeto. Se hace en cuanto se detecta, no solo al pintarlo, porque el dato
    /// corrupto ya está sincronizado entre dispositivos: si solo se limpiara en pantalla seguiría
    /// circulando y reapareciendo. Si el texto original no se puede recuperar se deja como está en
    /// vez de borrarlo, para no destruir lo poco que quede.
    @discardableResult
    private func repairCorruptedEvaluationDescription(_ evaluation: Evaluation) async -> String? {
        guard let stored = evaluation.description_,
              stored.hasPrefix("Evaluation(id=") || stored.contains("description=Evaluation(") else {
            return evaluation.description_
        }
        guard let recovered = KmpBridge.recoveredEvaluationDescription(from: stored) else {
            return nil
        }
        await saveEvaluationWithDescription(evaluation, description: recovered)
        return recovered
    }

    /// Recorre las evaluaciones de una clase y limpia las descripciones que quedaron convertidas en
    /// un volcado del objeto. Se engancha a la cadena de reparaciones que ya existe para el
    /// importador de instrumentos.
    func repairCorruptedEvaluationDescriptions(classId: Int64) async throws -> Bool {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        for evaluation in evaluations {
            guard let stored = evaluation.description_,
                  stored.hasPrefix("Evaluation(id=") || stored.contains("description=Evaluation(") else {
                continue
            }
            guard KmpBridge.recoveredEvaluationDescription(from: stored) != nil else { continue }
            await repairCorruptedEvaluationDescription(evaluation)
            didRepair = true
        }
        return didRepair
    }

    /// Recorre las evaluaciones de una clase creadas por el importador de instrumentos y sustituye
    /// la nota generica de importacion ("Instrumento importado desde...", ver
    /// materializeLearningSituationAssessmentInstruments) o una descripcion vacia por el enunciado
    /// oficial del criterio de evaluacion, buscado por el titulo del instrumento en
    /// EvaluationCriteriaReference. Sin esto, cualquier instrumento importado antes de este fix se
    /// queda enseñando la nota generica para siempre: el importador ya no la escribe, pero no
    /// reescribe lo que ya existe en la base de datos del docente.
    func repairAssessmentInstrumentCriterionDescriptions(classId: Int64) async throws -> Bool {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        for evaluation in evaluations {
            let stored = evaluation.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let looksGeneric = stored.isEmpty || stored.hasPrefix("Instrumento importado desde ")
            guard looksGeneric,
                  let statement = EvaluationCriteriaReference.shared.criterionStatement(instrumentTitle: evaluation.name),
                  statement != stored else { continue }
            await saveEvaluationWithDescription(evaluation, description: statement)
            didRepair = true
        }
        return didRepair
    }

    private func saveEvaluationWithDescription(_ evaluation: Evaluation, description: String) async {
        _ = try? await container.evaluationsRepository.saveEvaluation(
            id: KotlinLong(value: evaluation.id),
            classId: evaluation.classId,
            code: evaluation.code,
            name: evaluation.name,
            type: evaluation.type,
            weight: evaluation.weight,
            formula: evaluation.formula,
            rubricId: evaluation.rubricId,
            description: description,
            authorUserId: evaluation.trace.authorUserId,
            createdAtEpochMs: evaluation.trace.createdAt.toEpochMilliseconds(),
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            associatedGroupId: evaluation.trace.associatedGroupId,
            deviceId: localDeviceId,
            syncVersion: evaluation.trace.syncVersion
        )
    }

    func loadStructuredInstrumentEvaluation(
        classId: Int64,
        studentId: Int64,
        columnId: String
    ) async throws -> StructuredInstrumentEvaluationModel? {
        // La plantilla estructurada de una columna solo la crea el importador de instrumentos de
        // la situación de aprendizaje (`saveAssessmentInstrumentTemplateIfNeeded`) o llega por
        // SyncLAN desde el dispositivo donde se importó. Si no existe, se devuelve `nil` y la hoja
        // enseña su estado vacío: sintetizar una plantilla aquí escribiría en la base de datos del
        // docente sesiones e indicadores que él nunca ha definido, y esa invención luego se
        // sincroniza al resto de dispositivos como si fuera trabajo real suyo.
        guard let detail = try await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId) else {
            return nil
        }
        let columns = (try? await container.notebookConfigRepository.listColumns(classId: classId)) ?? []
        let column = columns.first(where: { $0.id == columnId })

        // Descripción del criterio de evaluación que se evalúa con el instrumento. Si la
        // `description` de la evaluación asociada está vacía o es la nota genérica de importación,
        // se busca el enunciado oficial en EvaluationCriteriaReference por el título del
        // instrumento y se persiste. `competencyCriteriaIds` guarda identificadores de fila, no
        // códigos curriculares, así que no sirve como etiqueta legible. Si no hay ningún texto
        // real, no se muestra nada en vez de repetir el título de la columna, que ya es el título
        // de la hoja.
        var criterionLabel: String? = nil
        var criterionStatements: [CriterionStatement] = []
        let targetEvalId = column?.evaluationId?.int64Value ?? detail.template_.evaluationId?.int64Value
        if let evalId = targetEvalId, evalId > 0,
           let evaluation = try? await container.evaluationsRepository.getEvaluation(evaluationId: evalId) {
            criterionStatements = EvaluationCriteriaReference.shared.criterionStatements(instrumentTitle: evaluation.name)
            // `description_` puede llevar arrastrando un volcado del objeto (ver
            // repairCorruptedEvaluationDescription) de cuando el sync mandaba `description` de
            // NSObject en vez del campo real; se repara aquí, no solo al pintarlo, para que deje de
            // circular entre dispositivos.
            var desc = await repairCorruptedEvaluationDescription(evaluation)
            let looksGeneric = (desc?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || (desc?.hasPrefix("Instrumento importado desde ") ?? false)
            if looksGeneric, let statement = EvaluationCriteriaReference.shared.criterionStatement(instrumentTitle: evaluation.name) {
                await saveEvaluationWithDescription(evaluation, description: statement)
                desc = statement
            }
            if let desc, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                criterionLabel = desc
            } else if !evaluation.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                criterionLabel = evaluation.code
            } else if !evaluation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                criterionLabel = evaluation.name
            }
        }
        if criterionLabel == nil,
           let unit = column?.unitOrSituation,
           !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            criterionLabel = unit
        }

        let responses = try await container.notebookInstrumentsRepository.listResponsesForCell(
            classId: classId,
            studentId: studentId,
            columnId: columnId
        )
        let responseByItemId = Dictionary(uniqueKeysWithValues: responses.map { ($0.itemId, $0) })
        let items = detail.items.map { item in
            let response = responseByItemId[item.id]
            return StructuredInstrumentEvaluationItem(
                id: item.id,
                key: item.key,
                title: item.title,
                type: item.type,
                options: item.options,
                helpText: item.helpText,
                textValue: response?.textValue ?? "",
                boolValue: response?.boolValue?.boolValue ?? false,
                numberValue: response?.numberValue.map { plainStructuredNumberString($0.doubleValue) } ?? ""
            )
        }
        return StructuredInstrumentEvaluationModel(
            id: "\(classId)-\(studentId)-\(columnId)",
            classId: classId,
            studentId: studentId,
            columnId: columnId,
            title: detail.template_.title,
            kind: detail.template_.kind,
            criterionLabel: criterionLabel,
            criterionStatements: criterionStatements,
            items: items
        )
    }

    @discardableResult
    func saveStructuredInstrumentEvaluation(_ model: StructuredInstrumentEvaluationModel) async throws -> NotebookInstrumentCellSummary {
        let responses = model.items.map { item in
            NotebookInstrumentResponse(
                classId: model.classId,
                studentId: model.studentId,
                columnId: model.columnId,
                itemId: item.id,
                textValue: structuredTextValue(for: item),
                boolValue: item.type == .check ? KotlinBoolean(value: item.boolValue) : nil,
                numberValue: structuredNumberValue(for: item).map { KotlinDouble(value: $0) },
                trace: AuditTrace(
                    authorUserId: nil,
                    createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                    updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)),
                    associatedGroupId: nil,
                    deviceId: localDeviceId,
                    syncVersion: 1
                )
            )
        }
        let summary = try await container.notebookInstrumentsRepository.saveResponses(
            classId: model.classId,
            studentId: model.studentId,
            columnId: model.columnId,
            responses: responses,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let key = cellKey(studentId: model.studentId, columnId: model.columnId)
        optimisticTextDrafts[key] = summary.displayValue
        invalidateNotebookCellValueIndexCache()
        lastNotebookAggregateSignature = nil
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: model.classId)
        return summary
    }

    private func structuredTextValue(for item: StructuredInstrumentEvaluationItem) -> String? {
        switch item.type {
        case .text, .choice:
            let value = item.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    /// `IosFormatting.decimal` fuerza siempre 2 decimales ("4.00"/"4,00" según locale), lo que
    /// no coincide con los tags planos "1".."4" de los selectores segmentados (.scale14) ni con
    /// lo que escribe una casilla numérica libre — el valor cargado no seleccionaba ningún nivel
    /// al reabrir el sheet, pareciendo que el guardado se había perdido aunque sí persistía.
    func plainStructuredNumberString(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    private func structuredNumberValue(for item: StructuredInstrumentEvaluationItem) -> Double? {
        switch item.type {
        case .number, .scale14:
            return Double(item.numberValue.replacingOccurrences(of: ",", with: "."))
        default:
            return nil
        }
    }



    private func sanitizePersistedCellText(_ text: String, columnType: NotebookColumnType?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard columnType != .icon else { return trimmed }

        // Si es un nombre crudo de símbolo SF (ej. "trophy.fill", "star.fill")
        if NotebookCellStampCatalog.item(for: trimmed) != nil || trimmed.hasSuffix(".fill") {
            return ""
        }

        // Si contiene un símbolo crudo concatenado (ej. "9 trophy.fill")
        for stamp in NotebookCellStampCatalog.allStamps {
            if trimmed.contains(stamp.symbol) {
                let cleaned = trimmed.replacingOccurrences(of: stamp.symbol, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned
            }
        }
        return trimmed
    }

    private func notebookCellValueIndex() -> NotebookCellValueIndex? {
        guard let data = notebookState as? NotebookUiStateData else { return nil }
        let stateIdentity = ObjectIdentifier(data)
        if cachedNotebookStateIdentity == stateIdentity, let cachedNotebookCellValueIndex {
            return cachedNotebookCellValueIndex
        }

        var index = NotebookCellValueIndex()

        let columnTypesById = Dictionary(
            data.sheet.columns.map { ($0.id, $0.type) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in data.sheet.rows {
            let studentId = row.student.id

            for persisted in row.persistedCells {
                let key = cellKey(studentId: studentId, columnId: persisted.columnId)
                let columnType = columnTypesById[persisted.columnId]

                if let display = persisted.displayValue, !display.isEmpty {
                    index.displayByKey[key] = sanitizePersistedCellText(display, columnType: columnType)
                }
                if columnType == .icon, let icon = persisted.iconValue, !icon.isEmpty {
                    index.textByKey[key] = icon
                } else if let text = persisted.textValue, !text.isEmpty {
                    index.textByKey[key] = sanitizePersistedCellText(text, columnType: columnType)
                } else if let ordinal = persisted.ordinalValue, !ordinal.isEmpty {
                    index.textByKey[key] = ordinal
                } else {
                    index.textByKey[key] = ""
                }
                index.checkByKey[key] = persisted.boolValue?.boolValue ?? false
            }

            for grade in row.persistedGrades {
                guard let value = grade.value else { continue }
                let formatted = IosFormatting.decimal(from: value.doubleValue)
                index.numericByKey[cellKey(studentId: studentId, columnId: grade.columnId)] = formatted
                if let evalId = grade.evaluationId?.int64Value {
                    index.numericByEvalKey[cellKey(studentId: studentId, columnId: "eval_\(evalId)")] = formatted
                }
            }

            for cell in row.cells {
                guard let value = cell.value else { continue }
                let evalId = cell.evaluationId
                let key = cellKey(studentId: studentId, columnId: "eval_\(evalId)")
                if index.numericByEvalKey[key] == nil {
                    index.numericByEvalKey[key] = IosFormatting.decimal(from: value.doubleValue)
                }
            }
        }

        for (key, value) in data.numericDrafts {
            guard let studentId = key.first?.int64Value, let columnId = key.second as String? else { continue }
            let rowKey = cellKey(studentId: studentId, columnId: columnId)
            index.numericDraftByKey[rowKey] = value
        }
        for (key, value) in data.textDrafts {
            guard let studentId = key.first?.int64Value, let columnId = key.second as String? else { continue }
            let rowKey = cellKey(studentId: studentId, columnId: columnId)
            index.textDraftByKey[rowKey] = value
        }
        for (key, value) in data.checkDrafts {
            guard let studentId = key.first?.int64Value, let columnId = key.second as String? else { continue }
            let rowKey = cellKey(studentId: studentId, columnId: columnId)
            index.checkDraftByKey[rowKey] = value.boolValue
        }

        for (key, value) in optimisticGradeDrafts {
            index.numericDraftByKey[key] = value
        }
        for (key, value) in optimisticTextDrafts {
            index.textDraftByKey[key] = value
            index.displayByKey[key] = value
            if let b = Bool(value) {
                index.checkDraftByKey[key] = b
            } else if value == "1" {
                index.checkDraftByKey[key] = true
            } else if value == "0" {
                index.checkDraftByKey[key] = false
            }
        }

        cachedNotebookStateIdentity = stateIdentity
        cachedNotebookCellValueIndex = index
        return index
    }

    func cellText(studentId: Int64, columnId: String) -> String {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticTextDrafts[key] {
            return opt
        }
        guard let index = notebookCellValueIndex() else { return "" }
        return index.textDraftByKey[key] ?? index.textByKey[key] ?? ""
    }

    func structuredCellDisplayText(studentId: Int64, columnId: String) -> String {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticTextDrafts[key] {
            return opt
        }
        guard let index = notebookCellValueIndex() else { return "" }
        return index.displayByKey[key] ?? index.textByKey[key] ?? ""
    }

    func cellAnnotation(studentId: Int64, columnId: String) -> (note: String?, icon: String?, attachmentUris: [String])? {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticAnnotations[key] {
            return (note: opt.note, icon: opt.icon, attachmentUris: opt.attachmentUris)
        }
        return nil
    }
    
    func numericGradeText(studentId: Int64, columnId: String) -> String {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticGradeDrafts[key] {
            return opt
        }
        guard let index = notebookCellValueIndex() else { return "" }
        if let draft = index.numericDraftByKey[key] {
            return draft
        }
        if let persisted = index.numericByKey[key] {
            return persisted
        }
        if let persistedEval = index.numericByEvalKey[key] {
            return persistedEval
        }
        return ""
    }

    func numericGradeText(studentId: Int64, column: NotebookColumnDefinition) -> String {
        let raw = numericGradeText(studentId: studentId, columnId: column.id)
        guard column.inputKind == .time else { return raw }
        guard let seconds = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) else {
            return raw
        }
        let centiseconds = max(0, Int((seconds * 100.0).rounded()))
        let minutes = centiseconds / 6000
        let remainingSeconds = (centiseconds / 100) % 60
        let fraction = centiseconds % 100
        return String(format: "%02d:%02d,%02d", minutes, remainingSeconds, fraction)
    }

    func numericGradeOnTenText(studentId: Int64, columnId: String) -> String {
        formatGradeOnTen(numericGradeText(studentId: studentId, columnId: columnId))
    }

    func rubricGradeText(studentId: Int64, column: NotebookColumnDefinition) -> String {
        guard let index = notebookCellValueIndex() else { return "" }
        let directKey = cellKey(studentId: studentId, columnId: column.id)
        if let directValue = index.numericDraftByKey[directKey], !directValue.isEmpty {
            return directValue
        }

        if let evaluationId = column.evaluationId?.int64Value {
            let evalKey = cellKey(studentId: studentId, columnId: "eval_\(evaluationId)")
            if let evalValue = index.numericDraftByKey[evalKey], !evalValue.isEmpty {
                return evalValue
            }
            if let persisted = index.numericByKey[directKey] {
                return persisted
            }
            if let persistedByEval = index.numericByEvalKey[evalKey] {
                return persistedByEval
            }
        } else if let persisted = index.numericByKey[directKey] {
            return persisted
        }

        return ""
    }

    func rubricGradeOnTenText(studentId: Int64, column: NotebookColumnDefinition) -> String {
        formatGradeOnTen(rubricGradeText(studentId: studentId, column: column))
    }

    func cellCheck(studentId: Int64, columnId: String) -> Bool {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let optText = optimisticTextDrafts[key] {
            if let b = Bool(optText) {
                return b
            }
            if optText == "1" { return true }
            if optText == "0" { return false }
        }
        guard let index = notebookCellValueIndex() else { return false }
        if let draft = index.checkDraftByKey[key] {
            return draft
        }
        if let persisted = index.checkByKey[key] {
            return persisted
        }
        return false
    }

    private func cellKey(studentId: Int64, columnId: String) -> String {
        "\(studentId)|\(columnId)"
    }

    private func formatGradeOnTen(_ rawValue: String) -> String {
        if let cached = gradeOnTenFormatCache[rawValue] {
            return cached
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            gradeOnTenFormatCache[rawValue] = ""
            return ""
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let numeric = Double(normalized) else {
            gradeOnTenFormatCache[rawValue] = trimmed
            return trimmed
        }
        let formatted = IosFormatting.scoreOutOfTen(from: numeric)
        gradeOnTenFormatCache[rawValue] = formatted
        return formatted
    }

}
