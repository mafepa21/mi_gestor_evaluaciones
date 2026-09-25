import Foundation
import SwiftUI
import MiGestorKit
import Combine

extension KmpBridge {
    @MainActor
    func launchFirstBulkRubricEvaluationForClass(classId: Int64) async -> Bool {
        do {
            let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
            guard let column = columns.first(where: { $0.rubricId != nil && $0.evaluationId != nil }),
                  let rubricId = column.rubricId?.int64Value,
                  let evaluationId = column.evaluationId?.int64Value else {
                status = "No hay una rúbrica vinculada al cuaderno de esta clase."
                return false
            }
            startBulkRubricEvaluation(
                classId: classId,
                evaluationId: evaluationId,
                rubricId: rubricId,
                columnId: column.id,
                tabId: column.tabIds.first
            )
            return true
        } catch {
            status = "No se pudo abrir la rúbrica rápida: \(error.localizedDescription)"
            return false
        }
    }


    func refreshRubrics() async throws {
        let rubrics = try await container.rubricsRepository.listRubrics()
        self.rubrics = rubrics
    }

    func refreshRubricClassLinks() async throws {
        if classes.isEmpty {
            try await refreshClasses()
        }

        let currentClasses = self.classes
        var links: [Int64: Set<Int64>] = [:]
        for schoolClass in currentClasses {
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            for evaluation in evaluations {
                if let rubricId = evaluation.rubricId?.int64Value {
                    var classSet = links[rubricId] ?? Set<Int64>()
                    classSet.insert(schoolClass.id)
                    links[rubricId] = classSet
                }
            }
        }
        self.rubricClassLinks = links
    }

    private func refreshRubricBuilderTeachingUnits(for classId: Int64?) async throws {
        rubricBuilderTeachingUnits = try await plannerTeachingUnits(for: classId)
    }


    func loadRubricUsage(rubricId: Int64) async throws -> RubricUsageSnapshot {
        if classes.isEmpty {
            try await refreshClasses()
        }

        var usages: [RubricUsageSnapshot.EvaluationUsage] = []
        for schoolClass in classes {
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            let matching = evaluations.filter { $0.rubricId?.int64Value == rubricId }
            usages.append(contentsOf: matching.map { evaluation in
                RubricUsageSnapshot.EvaluationUsage(
                    classId: schoolClass.id,
                    className: schoolClass.name,
                    evaluationId: evaluation.id,
                    evaluationName: evaluation.name,
                    evaluationType: evaluation.type,
                    weight: evaluation.weight
                )
            })
        }

        let classNames = Array(Set(usages.map(\.className))).sorted()
        return RubricUsageSnapshot(
            rubricId: rubricId,
            classCount: classNames.count,
            evaluationCount: usages.count,
            linkedClassNames: classNames,
            evaluationUsages: usages.sorted { lhs, rhs in
                if lhs.className == rhs.className {
                    return lhs.evaluationName.localizedCaseInsensitiveCompare(rhs.evaluationName) == .orderedAscending
                }
                return lhs.className.localizedCaseInsensitiveCompare(rhs.className) == .orderedAscending
            }
        )
    }


    @MainActor
    func startRubricEvaluationCoordinator(
        columnId: String,
        rubricId: Int64,
        classId: Int64,
        evaluationId: Int64,
        studentIds: [Int64],
        currentStudentId: Int64
    ) {
        rubricEvaluationCoordinator.start(
            columnId: columnId,
            rubricId: rubricId,
            classId: classId,
            evaluationId: evaluationId,
            studentIds: studentIds,
            currentStudentId: currentStudentId
        )
        isNotebookRubricAutoAdvanceActive = true
    }

    @MainActor
    func openRubricEvaluationFromNotebook(studentId: Int64, columnId: String, rubricId: Int64, evaluationId: Int64) {
        closeBulkRubricEvaluation()
        isNotebookRubricAutoAdvanceActive = true
        rubricEvaluationViewModel.loadForNotebookCell(studentId: studentId, columnId: columnId, rubricId: rubricId, evaluationId: evaluationId)
    }


    @MainActor
    func advanceRubricEvaluationToNextStudent(visibleStudentIds: [Int64]? = nil) -> RubricEvaluationAdvanceResult {
        guard let context = rubricEvaluationCoordinator.context else {
            closeRubricEvaluation()
            return .closed
        }

        refreshCurrentNotebook()
        if context.classId > 0 {
            scheduleNotebookSnapshotSync(forClassId: context.classId)
        }

        if let nextStudentId = rubricEvaluationCoordinator.advance(visibleStudentIds: visibleStudentIds),
           let nextContext = rubricEvaluationCoordinator.context {
            rubricEvaluationState = RubricEvaluationUiState.companion.default()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.openRubricEvaluationFromNotebook(
                    studentId: nextStudentId,
                    columnId: nextContext.columnId,
                    rubricId: nextContext.rubricId,
                    evaluationId: nextContext.evaluationId
                )
            }
            return .openedNext(
                studentId: nextStudentId,
                remainingCount: rubricEvaluationCoordinator.lastSummary?.remainingCount ?? 0
            )
        }

        let summary = rubricEvaluationCoordinator.lastSummary ?? RubricEvaluationAdvanceSummary(
            evaluatedCount: context.studentIds.count,
            remainingCount: 0
        )
        closeRubricEvaluation()
        return .completed(summary)
    }

    func openAgendaNavigationTarget(_ target: AgendaNavigationTarget) {
        guard let studentId = target.studentId?.int64Value,
              let classId = target.classId?.int64Value,
              let evaluationId = target.evaluationId?.int64Value,
              let rubricId = target.rubricId?.int64Value,
              let columnId = target.columnId?.nilIfEmpty else {
            status = "La agenda no pudo resolver la rúbrica seleccionada."
            return
        }

        if showingBulkRubricEvaluation {
            closeBulkRubricEvaluation()
        }
        closeRubricEvaluation()
        if notebookViewModel.currentClassId?.int64Value != classId {
            selectClass(id: classId)
        }
        rubricEvaluationViewModel.loadForNotebookCell(
            studentId: studentId,
            columnId: columnId,
            rubricId: rubricId,
            evaluationId: evaluationId
        )
    }

    func saveRubricEvaluation(
        manual: Bool = true,
        emitNotebookRefresh: Bool = true,
        onSuccess: @escaping () -> Void = {}
    ) {
        rubricEvaluationViewModel.save(manual: manual, emitNotebookRefresh: emitNotebookRefresh) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if emitNotebookRefresh {
                    self.lastNotebookAggregateSignature = nil
                    self.refreshCurrentNotebook()
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
                onSuccess()
            }
        }
    }
    
    func startBulkRubricEvaluation(column: NotebookColumnDefinition) {
        guard let classId = notebookViewModel.currentClassId?.int64Value,
              let evaluationId = column.evaluationId?.int64Value,
              let rubricId = column.rubricId?.int64Value else {
            return
        }
        // Evitamos que quede una evaluación individual abierta detrás del panel masivo.
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
        rubricBulkEvaluationViewModel.load(
            classId: classId,
            evaluationId: evaluationId,
            rubricId: rubricId,
            columnId: column.id,
            tabId: nil
        )
        showingBulkRubricEvaluation = true
    }

    func startBulkRubricEvaluation(
        classId: Int64,
        evaluationId: Int64,
        rubricId: Int64,
        columnId: String? = nil,
        tabId: String? = nil
    ) {
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
        rubricBulkEvaluationViewModel.load(
            classId: classId,
            evaluationId: evaluationId,
            rubricId: rubricId,
            columnId: columnId,
            tabId: tabId
        )
        showingBulkRubricEvaluation = true
    }

    @MainActor
    func launchBulkRubricEvaluationFromRubric(
        rubricId: Int64,
        preferredClassId: Int64? = nil
    ) async -> Bool {
        do {
            let usage = try await loadRubricUsage(rubricId: rubricId)
            let sortedUsages = usage.evaluationUsages.sorted { lhs, rhs in
                if let preferredClassId {
                    if lhs.classId == preferredClassId && rhs.classId != preferredClassId { return true }
                    if rhs.classId == preferredClassId && lhs.classId != preferredClassId { return false }
                }
                if lhs.className == rhs.className {
                    return lhs.evaluationName.localizedCaseInsensitiveCompare(rhs.evaluationName) == .orderedAscending
                }
                return lhs.className.localizedCaseInsensitiveCompare(rhs.className) == .orderedAscending
            }

            guard let target = sortedUsages.first else {
                status = "Esta rúbrica no está vinculada a ninguna evaluación."
                return false
            }

            return await launchBulkRubricEvaluationFromUsage(
                rubricId: rubricId,
                classId: target.classId,
                evaluationId: target.evaluationId
            )
        } catch {
            status = "Error abriendo evaluación masiva: \(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    func launchBulkRubricEvaluationFromUsage(
        rubricId: Int64,
        classId: Int64,
        evaluationId: Int64
    ) async -> Bool {
        do {
            let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
            let column = columns.first { $0.evaluationId?.int64Value == evaluationId }

            rubricEvaluationState = RubricEvaluationUiState.companion.default()
            rubricBulkEvaluationViewModel.load(
                classId: classId,
                evaluationId: evaluationId,
                rubricId: rubricId,
                columnId: column?.id,
                tabId: column?.tabIds.first
            )
            showingBulkRubricEvaluation = true

            if column == nil {
                status = "Abriendo evaluación masiva sin columna vinculada del cuaderno."
            }
            return true
        } catch {
            status = "Error abriendo evaluación masiva: \(error.localizedDescription)"
            return false
        }
    }
    
    func closeBulkRubricEvaluation() {
        showingBulkRubricEvaluation = false
        // Al cerrar la masiva, limpiamos cualquier overlay individual residual.
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
    }

    func closeRubricEvaluation() {
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
        isNotebookRubricAutoAdvanceActive = false
        rubricEvaluationCoordinator.reset()
    }

    func refreshCurrentNotebook() {
        guard let classId = notebookViewModel.currentClassId?.int64Value else { return }
        let preservedTab = selectedNotebookTabId ?? restoredSelectedNotebookTab(forClassId: classId)
        notebookViewModel.setSelectedTabId(tabId: preservedTab)
        notebookViewModel.selectClass(classId: classId, force: true)
    }

    func restoredSelectedNotebookTab(forClassId classId: Int64?) -> String? {
        guard let classId else { return nil }
        return selectedNotebookTabByClassId["\(classId)"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func rememberSelectedNotebookTab(_ tabId: String?, forClassId classId: Int64?) {
        guard let classId else { return }
        let key = "\(classId)"
        if let tabId = tabId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            selectedNotebookTabByClassId[key] = tabId
        } else {
            selectedNotebookTabByClassId.removeValue(forKey: key)
        }
        UserDefaults.standard.set(selectedNotebookTabByClassId, forKey: "notebook.selected.tab.by.class.v1")
    }
    
    func bulkSelectLevel(studentId: Int64, criterionId: Int64, levelId: Int64) {
        rubricBulkEvaluationViewModel.selectLevel(studentId: studentId, criterionId: criterionId, levelId: levelId)
    }
    
    func bulkSelectedLevelId(studentId: Int64, criterionId: Int64) -> Int64? {
        bulkAssessmentSnapshot()[studentId]?[criterionId]
    }
    
    func bulkScore(studentId: Int64) -> Double? {
        bulkScoreSnapshot()[studentId]
    }

    func bulkAssessmentSnapshot() -> [Int64: [Int64: Int64]] {
        guard let rawAssessments = bulkRubricEvaluationState?.assessments as NSDictionary? else {
            return [:]
        }

        var snapshot: [Int64: [Int64: Int64]] = [:]
        for (rawStudentId, rawStudentAssessments) in rawAssessments {
            guard let studentId = int64Value(rawStudentId),
                  let rawStudentAssessments = rawStudentAssessments as? NSDictionary else {
                continue
            }

            var selections: [Int64: Int64] = [:]
            for (rawCriterionId, rawLevelId) in rawStudentAssessments {
                guard let criterionId = int64Value(rawCriterionId),
                      let levelId = int64Value(rawLevelId) else {
                    continue
                }
                selections[criterionId] = levelId
            }
            snapshot[studentId] = selections
        }

        return snapshot
    }

    func bulkScoreSnapshot() -> [Int64: Double] {
        guard let rawScores = bulkRubricEvaluationState?.scores as NSDictionary? else {
            return [:]
        }

        var snapshot: [Int64: Double] = [:]
        for (rawStudentId, rawScore) in rawScores {
            guard let studentId = int64Value(rawStudentId),
                  let score = doubleValue(rawScore) else {
                continue
            }
            snapshot[studentId] = score
        }
        return snapshot
    }
    
    func bulkSaveAllAndClose() {
        rubricBulkEvaluationViewModel.saveAll()
        showingBulkRubricEvaluation = false
    }

    func bulkSaveAll() {
        rubricBulkEvaluationViewModel.saveAll()
    }

    func bulkCopyAssessment(studentId: Int64) {
        rubricBulkEvaluationViewModel.doCopyAssessment(studentId: studentId)
    }

    func bulkPasteAssessment(studentId: Int64) {
        rubricBulkEvaluationViewModel.pasteAssessment(studentId: studentId)
    }

    func duplicateNotebookStructure(to targetClassId: Int64) async throws {
        guard let sourceClassId = notebookViewModel.currentClassId?.int64Value else {
            throw NSError(
                domain: "KMP",
                code: -61,
                userInfo: [NSLocalizedDescriptionKey: "No hay curso origen seleccionado"]
            )
        }

        try await container.notebookRepository.duplicateConfigToClass(
            sourceClassId: sourceClassId,
            targetClassId: targetClassId
        )

        scheduleNotebookSnapshotSync(forClassId: targetClassId)
        try await refreshRubricClassLinks()
        status = "Estructura duplicada correctamente"
    }

    func createRubric(name: String, criterion: String, level: String, points: Int32) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCriterion = criterion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLevel = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "KMP", code: -12, userInfo: [NSLocalizedDescriptionKey: "La rúbrica no puede estar vacía"])
        }
        guard !trimmedCriterion.isEmpty else {
            throw NSError(domain: "KMP", code: -13, userInfo: [NSLocalizedDescriptionKey: "El criterio no puede estar vacío"])
        }
        guard !trimmedLevel.isEmpty else {
            throw NSError(domain: "KMP", code: -14, userInfo: [NSLocalizedDescriptionKey: "El nivel no puede estar vacío"])
        }
        guard points >= 0 else {
            throw NSError(domain: "KMP", code: -15, userInfo: [NSLocalizedDescriptionKey: "Los puntos deben ser un valor positivo"])
        }

        try await container.createRubricBundle(
            name: trimmedName,
            criterion: trimmedCriterion,
            level: trimmedLevel,
            points: points
        )

        try await refreshRubrics()
        try await refreshRubricClassLinks()
    }

    // Proxy Methods for RubricsViewModel
    func resetRubricBuilder() {
        editingRubricBuilderId = nil
        selectedRubricTeachingUnitId = nil
        rubricBuilderTeachingUnits = []
        rubricsViewModel.resetBuilder()
    }

    func importRubricDraft(tsv: String) async throws {
        guard let imported = appleImportFacade.previewRubricFromTsv(text: tsv) else {
            throw NSError(domain: "KmpBridge", code: -63, userInfo: [NSLocalizedDescriptionKey: "El archivo no tiene un formato de rúbrica válido."])
        }
        editingRubricBuilderId = nil
        selectedRubricTeachingUnitId = nil
        rubricBuilderTeachingUnits = []
        rubricsViewModel.loadImportedRubric(importedState: imported)
        rubricsUiState = rubricsViewModel.uiState.value as? RubricUiState
    }

    func loadRubricForEditing(_ rubric: RubricDetail) {
        editingRubricBuilderId = rubric.rubric.id
        rubricsViewModel.loadRubric(rubricDetail: rubric)
        let classId = rubric.rubric.classId?.int64Value
        let teachingUnitId = rubric.rubric.teachingUnitId?.int64Value
        if let classId {
            selectRubricClass(classId)
            Task { @MainActor in
                try? await refreshRubricBuilderTeachingUnits(for: classId)
                selectedRubricTeachingUnitId = teachingUnitId
            }
        } else {
            selectedRubricTeachingUnitId = teachingUnitId
            rubricBuilderTeachingUnits = []
        }
    }

    func deleteRubric(id: Int64) {
        enqueueLocalChange(
            entity: "rubric_bundle",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["rubricId": id],
            op: "delete"
        )
        rubricsViewModel.deleteRubric(rubricId: id)
        Task {
            try? await refreshRubrics()
            try? await refreshRubricClassLinks()
        }
    }

    func startAssignRubric(_ rubric: Rubric) {
        rubricsViewModel.startAssignRubricToClass(rubric: rubric)
    }

    func setRubricFilterClass(_ classId: Int64?) {
        let kotlinId = classId.map { KotlinLong(value: $0) }
        rubricsViewModel.setFilterClass(classId: kotlinId)
    }

    func onAssignClassSelected(_ classId: Int64) {
        rubricsViewModel.onAssignClassSelected(classId: classId)
    }

    func onAssignTabSelected(_ tabName: String) {
        rubricsViewModel.onAssignTabSelected(tabName: tabName)
    }

    func onToggleCreateNewTab(_ create: Bool) {
        rubricsViewModel.onToggleCreateNewTab(create: create)
    }

    func onNewTabNameChanged(_ name: String) {
        rubricsViewModel.onNewTabNameChanged(name: name)
    }

    func confirmAssignRubric() {
        rubricsViewModel.confirmAssignRubric()
        Task {
            try? await refreshRubricClassLinks()
            refreshCurrentNotebook()
        }
    }

    func dismissAssignRubricDialog() {
        rubricsViewModel.dismissAssignDialog()
    }

    func updateRubricName(_ name: String) {
        rubricsViewModel.updateRubricName(name: name)
    }

    func updateRubricInstructions(_ text: String) {
        rubricsViewModel.updateInstructions(text: text)
    }

    func selectRubricClass(_ classId: Int64?) {
        let kotlinId = classId.map { KotlinLong(value: $0) }
        rubricsViewModel.selectClass(classId: kotlinId)
        selectedRubricTeachingUnitId = nil
        Task { @MainActor in
            try? await refreshRubricBuilderTeachingUnits(for: classId)
        }
    }

    func selectRubricTeachingUnit(_ teachingUnitId: Int64?) {
        selectedRubricTeachingUnitId = teachingUnitId
    }

    func applyRubricPreset(_ preset: String) {
        rubricsViewModel.applyPresetLevels(preset: preset)
    }

    func addRubricLevel() {
        rubricsViewModel.addLevel()
    }

    func removeRubricLevel(at index: Int) {
        rubricsViewModel.removeLevel(index: Int32(index))
    }

    func updateRubricLevelName(at index: Int, name: String) {
        rubricsViewModel.updateLevelName(index: Int32(index), name: name)
    }

    func updateRubricLevelPoints(at index: Int, points: Int) {
        rubricsViewModel.updateLevelPoints(index: Int32(index), points: Int32(points))
    }

    func addRubricCriterion() {
        rubricsViewModel.addCriterion()
    }

    func removeRubricCriterion(at index: Int) {
        rubricsViewModel.removeCriterion(index: Int32(index))
    }

    func updateRubricCriterionDescription(at index: Int, description: String) {
        rubricsViewModel.updateCriterionDescription(index: Int32(index), description: description)
    }

    func updateRubricCriterionWeight(at index: Int, weight: Double) {
        rubricsViewModel.updateCriterionWeight(index: Int32(index), weight: weight)
    }

    func updateRubricLevelDescription(criterionIndex: Int, levelUid: String, description: String) {
        rubricsViewModel.updateLevelDescription(criterionIndex: Int32(criterionIndex), levelUid: levelUid, description: description)
    }

    // Audit debt: this mirrors RubricsViewModel save/edit logic in Swift. Keep changes minimal
    // here and move persistence orchestration back to KMP with dedicated tests in a later pass.
    @MainActor
    func saveRubricFromBuilderReturningId() async throws -> Int64 {
        guard let state = rubricsUiState else {
            throw NSError(domain: "KmpBridge", code: -71, userInfo: [NSLocalizedDescriptionKey: "No hay una rúbrica preparada para guardar."])
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let editingRubricId = editingRubricBuilderId
        let rubricId = try await container.rubricsRepository.saveRubric(
            id: editingRubricId.map { KotlinLong(value: $0) },
            name: state.rubricName,
            description: state.instructions.nilIfBlank,
            classId: state.selectedClassId,
            teachingUnitId: selectedRubricTeachingUnitId.map { KotlinLong(value: $0) },
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: editingRubricId == nil ? 1 : 2
        ).int64Value

        if let editingRubricId {
            let retainedCriterionIds = Set(state.criteria.compactMap { $0.id?.int64Value })
            let existingCriteria = try await container.rubricsRepository.listCriteriaByRubric(rubricId: editingRubricId)
            for existingCriterion in existingCriteria where !retainedCriterionIds.contains(existingCriterion.id) {
                try await container.rubricsRepository.deleteCriterion(criterionId: existingCriterion.id)
            }
        }

        let retainedLevelOrders = Set(state.levels.map { Int32($0.order) })
        for criterion in state.criteria {
            let existingLevelsByOrder: [Int32: RubricLevel]
            if let existingCriterionId = criterion.id?.int64Value {
                let existingLevels = try await container.rubricsRepository.listLevelsByCriterion(criterionId: existingCriterionId)
                for existingLevel in existingLevels where !retainedLevelOrders.contains(Int32(existingLevel.order)) {
                    try await container.rubricsRepository.deleteLevel(levelId: existingLevel.id)
                }
                existingLevelsByOrder = Dictionary(
                    existingLevels.map { (Int32($0.order), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                existingLevelsByOrder = [:]
            }

            let criterionId = try await container.rubricsRepository.saveCriterion(
                id: criterion.id,
                rubricId: rubricId,
                description: criterion.description_,
                weight: criterion.weight,
                order: Int32(criterion.order),
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId,
                syncVersion: criterion.id == nil ? 1 : 2
            ).int64Value

            for level in state.levels {
                let reusableLevelId = existingLevelsByOrder[Int32(level.order)]?.id
                _ = try await container.rubricsRepository.saveLevel(
                    id: reusableLevelId.map { KotlinLong(value: $0) },
                    criterionId: criterionId,
                    name: level.name,
                    points: Int32(level.points),
                    description: criterion.levelDescriptions[level.uid],
                    order: Int32(level.order),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: reusableLevelId == nil ? 1 : 2
                )
            }
        }

        enqueueLocalChange(
            entity: "rubric_bundle",
            id: "\(rubricId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "rubricId": rubricId,
                "editingRubricId": editingRubricId ?? NSNull(),
                "name": state.rubricName,
                "description": state.instructions.nilIfBlank ?? NSNull(),
                "classId": state.selectedClassId?.int64Value ?? NSNull(),
                "teachingUnitId": selectedRubricTeachingUnitId ?? NSNull(),
                "criteria": state.criteria.map { criterion in
                    [
                        "description": criterion.description_,
                        "weight": criterion.weight,
                        "order": Int(criterion.order),
                        "levels": state.levels.map { level in
                            [
                                "name": level.name,
                                "points": Int(level.points),
                                "description": criterion.levelDescriptions[level.uid] ?? "",
                                "order": Int(level.order)
                            ]
                        }
                    ]
                }
            ]
        )

        try? await refreshRubrics()
        try? await refreshRubricClassLinks()
        if let classId = state.selectedClassId?.int64Value {
            try? await refreshRubricBuilderTeachingUnits(for: classId)
        }
        editingRubricBuilderId = rubricId
        return rubricId
    }

    func saveRubricFromBuilder(onComplete: @escaping (Bool) -> Void) {
        Task { @MainActor in
            do {
                _ = try await saveRubricFromBuilderReturningId()
                onComplete(true)
            } catch {
                onComplete(false)
            }
        }
    }

}
