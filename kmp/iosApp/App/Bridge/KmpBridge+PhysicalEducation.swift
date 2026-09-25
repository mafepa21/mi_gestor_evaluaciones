//
//  KmpBridge+PhysicalEducation.swift
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
    func loadPhysicalTests(classId: Int64) async throws -> [PhysicalTestSnapshot] {
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)

        let physicalEvaluations = evaluations.filter { evaluation in
            let normalized = "\(evaluation.type) \(evaluation.name) \(evaluation.description_ ?? "")".lowercased()
            return normalized.contains("physical")
                || normalized.contains("física")
                || normalized.contains("fisica")
                || normalized.contains("prueba")
                || normalized.contains("test")
        }

        return physicalEvaluations.map { evaluation in
            let evaluationGrades = grades.filter { $0.evaluationId?.int64Value == evaluation.id }
            let gradesByStudent = Dictionary(
                evaluationGrades.map { ($0.studentId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let results = students.map { student in
                let grade = gradesByStudent[student.id]
                return PhysicalTestSnapshot.StudentResult(
                    id: student.id,
                    student: student,
                    gradeId: grade?.id,
                    value: grade?.value?.doubleValue
                )
            }
            let numericValues = results.compactMap(\.value)
            let average = numericValues.isEmpty ? 0 : numericValues.reduce(0, +) / Double(numericValues.count)
            return PhysicalTestSnapshot(
                evaluation: evaluation,
                results: results,
                average: average,
                best: numericValues.max(),
                recordedCount: numericValues.count
            )
        }
        .sorted { lhs, rhs in
            lhs.evaluation.name.localizedCaseInsensitiveCompare(rhs.evaluation.name) == .orderedAscending
        }
    }

    func listPhysicalDefinitions() async throws -> [PhysicalTestDefinition] {
        try await container.physicalTestsRepository.listDefinitions()
    }

    func savePhysicalDefinition(_ definition: PhysicalTestDefinition) async throws {
        try await container.physicalTestsRepository.saveDefinition(definition: definition)
    }

    func listPhysicalBatteries() async throws -> [PhysicalTestBattery] {
        try await container.physicalTestsRepository.listBatteries()
    }

    func savePhysicalBattery(_ battery: PhysicalTestBattery) async throws {
        try await container.physicalTestsRepository.saveBattery(battery: battery)
    }

    func assignPhysicalBatteryToClass(_ assignment: PhysicalTestAssignment) async throws {
        try await container.physicalTestsRepository.assignBatteryToClass(assignment: assignment)
    }

    func listPhysicalAssignmentsForClass(classId: Int64) async throws -> [PhysicalTestAssignment] {
        try await container.physicalTestsRepository.listAssignmentsForClass(classId: classId)
    }

    func listPhysicalScalesForTest(testId: String) async throws -> [PhysicalTestScale] {
        try await container.physicalTestsRepository.listScalesForTest(testId: testId)
    }

    func savePhysicalScale(_ scale: PhysicalTestScale) async throws {
        try await container.physicalTestsRepository.saveScale(scale: scale)
    }

    func resolvePhysicalScale(
        testId: String,
        course: Int?,
        age: Int?,
        sex: String?,
        batteryId: String?
    ) async throws -> PhysicalTestScale? {
        try await container.physicalTestsRepository.resolveScale(
            testId: testId,
            course: course.map { KotlinInt(value: Int32($0)) },
            age: age.map { KotlinInt(value: Int32($0)) },
            sex: sex,
            batteryId: batteryId
        )
    }

    func savePhysicalNotebookLink(_ link: PhysicalTestNotebookLink) async throws {
        try await container.physicalTestsRepository.saveNotebookLink(link: link)
    }

    func listPhysicalNotebookLinksForAssignment(assignmentId: String) async throws -> [PhysicalTestNotebookLink] {
        try await container.physicalTestsRepository.listNotebookLinksForAssignment(assignmentId: assignmentId)
    }

    /// Resuelve la nota de referencia de una marca física del cuaderno sin crear
    /// una segunda columna evaluable. Esto permite que los manifiestos
    /// diagnósticos (`recordScore=false`) sigan guardando solo el dato bruto,
    /// pero ofrezcan al docente la orientación del baremo al capturarlo.
    func resolvePhysicalNotebookScore(
        classId: Int64,
        student: Student,
        columnId: String,
        rawValue: Double
    ) async -> Double? {
        guard rawValue.isFinite else { return nil }

        do {
            let assignments = try await container.physicalTestsRepository.listAssignmentsForClass(classId: classId)
            for assignment in assignments {
                let links = try await container.physicalTestsRepository.listNotebookLinksForAssignment(assignmentId: assignment.id)
                guard let link = links.first(where: { $0.rawColumnId == columnId }) else { continue }

                let scale = try await container.physicalTestsRepository.resolveScale(
                    testId: link.testId,
                    course: assignment.course,
                    age: physicalScaleAge(for: student).map { KotlinInt(value: Int32($0)) },
                    sex: physicalScaleSex(for: student),
                    batteryId: assignment.batteryId
                )
                guard let scale else { return nil }
                let score = scale.scoreFor(rawValue: rawValue)
                return score?.doubleValue
            }
        } catch {
            return nil
        }
        return nil
    }

    func savePhysicalResult(_ result: PhysicalTestResult, attempts: [PhysicalTestAttempt]) async throws {
        try await container.physicalTestsRepository.saveResult(result: result, attempts: attempts)
    }

    func listPhysicalResultsForAssignment(assignmentId: String) async throws -> [PhysicalTestResult] {
        try await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignmentId)
    }

    func listPhysicalResultsForStudent(studentId: Int64, testId: String) async throws -> [PhysicalTestResult] {
        try await container.physicalTestsRepository.listResultsForStudent(studentId: studentId, testId: testId)
    }

    private func physicalScaleSex(for student: Student) -> String? {
        switch student.sex {
        case .male: return "MALE"
        case .female: return "FEMALE"
        default: return nil
        }
    }

    private func physicalScaleAge(for student: Student) -> Int? {
        guard let birthDate = student.birthDate else { return nil }
        let now = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let year = now.year, let month = now.month, let day = now.day else { return nil }
        var age = year - Int(birthDate.year)
        if month < Int(birthDate.monthNumber) ||
            (month == Int(birthDate.monthNumber) && day < Int(birthDate.dayOfMonth)) {
            age -= 1
        }
        return age >= 0 ? age : nil
    }

    func createNotebookPhysicalColumnForClass(
        classId: Int64,
        name: String,
        categoryId: String?,
        inputKind: NotebookCellInputKind,
        unitOrSituation: String?,
        scaleKind: NotebookScaleKind,
        iconName: String,
        weight: Double,
        countsTowardAverage: Bool,
        dateEpochMs: Int64,
        targetTabId: String? = nil
    ) async throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NSError(domain: "KmpBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "El nombre de la columna no puede estar vacío."])
        }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let columnId = "COL_PE_\(nowMillis)_\(abs(normalized.hashValue))"
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMillis)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let tabIds = targetTabId.map { [$0] } ?? selectedNotebookTabId.map { [$0] } ?? tabs.first.map { [$0.id] } ?? []
        let column = NotebookColumnDefinition(
            id: columnId,
            title: normalized,
            type: .numeric,
            categoryKind: .physicalEducation,
            instrumentKind: .physicalTest,
            inputKind: inputKind,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: weight,
            dateEpochMs: KotlinLong(value: dateEpochMs),
            unitOrSituation: unitOrSituation,
            competencyCriteriaIds: [],
            scaleKind: scaleKind,
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "F97316",
            iconName: iconName,
            order: -1,
            widthDp: 120,
            categoryId: categoryId,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: countsTowardAverage,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        scheduleNotebookSnapshotSync(forClassId: classId)
        return columnId
    }

    func saveNotebookPhysicalValue(
        classId: Int64,
        studentId: Int64,
        columnId: String,
        value: Double
    ) async throws {
        try await container.notebookRepository.upsertGrade(
            classId: classId,
            studentId: studentId,
            columnId: columnId,
            evaluationId: nil,
            numericValue: value,
            rubricSelections: nil,
            evidence: nil,
            createdAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            deviceId: localDeviceId,
            syncVersion: 1
        )
        scheduleGradeSnapshotSync(forClassId: classId)
    }

    func loadPESessions(weekNumber: Int, year: Int, classId: Int64?) async throws -> [PESessionSnapshot] {
        let sessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(
            summaries.map { ($0.planningSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var snapshots: [PESessionSnapshot] = []
        for session in sessions.sorted(by: {
            if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
            return $0.dayOfWeek < $1.dayOfWeek
        }) {
            let aggregate = try? await plannerJournal(for: session)
            let journal = aggregate?.journal
            snapshots.append(
                PESessionSnapshot(
                    id: session.id,
                    session: session,
                    summary: summariesById[session.id],
                    materialToPrepareText: journal?.materialToPrepareText ?? "",
                    materialUsedText: journal?.materialUsedText ?? "",
                    injuriesText: journal?.injuriesText ?? "",
                    unequippedStudentsText: journal?.unequippedStudentsText ?? "",
                    intensityScore: Int(journal?.intensityScore ?? 0),
                    stationObservationsText: journal?.stationObservationsText ?? "",
                    physicalIncidentsText: journal?.physicalIncidentsText ?? ""
                )
            )
        }
        return snapshots
    }


    func createEvaluation(classId: Int64, code: String, name: String, type: String, weight: Double) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveEvaluation.invoke(
            id: nil,
            classId: classId,
            code: code,
            name: name,
            type: type,
            weight: weight,
            formula: nil,
            rubricId: nil,
            description: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(classId)-\(code)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": NSNull(),
                "classId": classId,
                "code": code,
                "name": name,
                "type": type,
                "weight": weight,
                "formula": NSNull(),
                "rubricId": NSNull(),
                "description": NSNull()
            ]
        )
    }

    @discardableResult
    func createPhysicalTest(
        classId: Int64,
        code: String,
        name: String,
        kind: String,
        weight: Double,
        description: String?
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let evaluationId = try await container.saveEvaluation.invoke(
            id: nil,
            classId: classId,
            code: code,
            name: name,
            type: "Prueba física · \(kind)",
            weight: weight,
            formula: nil,
            rubricId: nil,
            description: description,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(classId)-\(code)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": NSNull(),
                "classId": classId,
                "code": code,
                "name": name,
                "type": "Prueba física · \(kind)",
                "weight": weight,
                "formula": NSNull(),
                "rubricId": NSNull(),
                "description": description ?? NSNull()
            ]
        )
        return evaluationId.int64Value
    }

    func updatePhysicalTest(
        evaluationId: Int64,
        classId: Int64,
        code: String,
        name: String,
        kind: String,
        weight: Double,
        description: String?,
        formula: String? = nil,
        rubricId: Int64? = nil
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveEvaluation.invoke(
            id: KotlinLong(value: evaluationId),
            classId: classId,
            code: code,
            name: name,
            type: "Prueba física · \(kind)",
            weight: weight,
            formula: formula,
            rubricId: kotlinLong(rubricId),
            description: description,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(evaluationId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": evaluationId,
                "classId": classId,
                "code": code,
                "name": name,
                "type": "Prueba física · \(kind)",
                "weight": weight,
                "formula": formula ?? NSNull(),
                "rubricId": rubricId ?? NSNull(),
                "description": description ?? NSNull()
            ]
        )
    }

    func deletePhysicalTest(evaluationId: Int64) async throws {
        try await container.evaluationsRepository.deleteEvaluation(evaluationId: evaluationId)
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(evaluationId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": evaluationId],
            op: "delete"
        )
    }

    func saveGrade(studentId: Int64, evaluationId: Int64, value: Double?, classId: Int64) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try await container.recordGrade.invoke(
            id: nil,
            classId: classId,
            studentId: studentId,
            evaluationId: evaluationId,
            value: value.map { KotlinDouble(value: $0) },
            evidence: nil,
            evidencePath: nil,
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "grade",
            id: "\(classId)-\(studentId)-\(evaluationId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "classId": classId,
                "studentId": studentId,
                "evaluationId": evaluationId,
                "value": value ?? NSNull()
            ]
        )
    }

    func createPESession(
        classId: Int64,
        title: String,
        dayOfWeek: Int,
        period: Int,
        weekNumber: Int,
        year: Int,
        objectives: String,
        activities: String,
        evaluation: String = "",
        status: SessionStatus = .planned,
        scheduledSpace: String = "",
        usedSpace: String = "",
        materialToPrepare: String = "",
        materialUsed: String = "",
        injuries: String = "",
        unequippedStudents: String = "",
        intensityScore: Int = 0,
        stationObservations: String = "",
        physicalIncidents: String = ""
    ) async throws -> Int64 {
        let resolvedClass: SchoolClass?
        if let cachedClass = classes.first(where: { $0.id == classId }) {
            resolvedClass = cachedClass
        } else {
            resolvedClass = try await container.classesRepository.listClasses().first { $0.id == classId }
        }

        guard let schoolClass = resolvedClass else {
            throw NSError(domain: "KmpBridge", code: -3001, userInfo: [NSLocalizedDescriptionKey: "No se encontró el grupo para crear la sesión EF"])
        }

        let sessionId = try await plannerUpsertSession(
            id: 0,
            teachingUnitId: 0,
            teachingUnitName: title,
            teachingUnitColor: "#1E88E5",
            groupId: classId,
            groupName: schoolClass.name,
            dayOfWeek: dayOfWeek,
            period: period,
            weekNumber: weekNumber,
            year: year,
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            status: status
        )

        try await savePESessionOperationalData(
            sessionId: sessionId,
            scheduledSpace: scheduledSpace,
            usedSpace: usedSpace,
            materialToPrepare: materialToPrepare,
            materialUsed: materialUsed,
            injuries: injuries,
            unequippedStudents: unequippedStudents,
            intensityScore: intensityScore,
            stationObservations: stationObservations,
            physicalIncidents: physicalIncidents,
            journalStatus: .draft
        )
        try await refreshPlanning()
        return sessionId
    }

    func savePESessionOperationalData(
        sessionId: Int64,
        scheduledSpace: String,
        usedSpace: String,
        materialToPrepare: String,
        materialUsed: String,
        injuries: String,
        unequippedStudents: String,
        intensityScore: Int,
        stationObservations: String,
        physicalIncidents: String,
        journalStatus: SessionJournalStatus
    ) async throws {
        guard let session = try await container.plannerRepository.listAllSessions().first(where: { $0.id == sessionId }) else {
            throw NSError(domain: "KmpBridge", code: -3002, userInfo: [NSLocalizedDescriptionKey: "No se encontró la sesión EF"])
        }

        let aggregate = try await container.sessionJournalRepository.getOrCreateJournal(session: session)
        let current = aggregate.journal
        let updatedJournal = SessionJournal(
            id: current.id,
            planningSessionId: current.planningSessionId,
            teacherName: current.teacherName,
            scheduledSpace: scheduledSpace.isEmpty ? current.scheduledSpace : scheduledSpace,
            usedSpace: usedSpace.isEmpty ? current.usedSpace : usedSpace,
            unitLabel: current.unitLabel,
            objectivePlanned: current.objectivePlanned,
            plannedText: current.plannedText,
            actualText: current.actualText,
            attainmentText: current.attainmentText,
            adaptationsText: current.adaptationsText,
            incidentsText: current.incidentsText,
            groupObservations: current.groupObservations,
            climateScore: current.climateScore,
            participationScore: current.participationScore,
            usefulTimeScore: current.usefulTimeScore,
            perceivedDifficultyScore: current.perceivedDifficultyScore,
            pedagogicalDecision: current.pedagogicalDecision,
            pendingTasksText: current.pendingTasksText,
            materialToPrepareText: materialToPrepare,
            studentsToReviewText: current.studentsToReviewText,
            familyCommunicationText: current.familyCommunicationText,
            nextStepText: current.nextStepText,
            weatherText: current.weatherText,
            materialUsedText: materialUsed,
            physicalIncidentsText: physicalIncidents,
            injuriesText: injuries,
            unequippedStudentsText: unequippedStudents,
            intensityScore: Int32(max(0, min(intensityScore, 5))),
            warmupMinutes: current.warmupMinutes,
            mainPartMinutes: current.mainPartMinutes,
            cooldownMinutes: current.cooldownMinutes,
            stationObservationsText: stationObservations,
            incidentTags: current.incidentTags,
            status: journalStatus
        )
        let updatedAggregate = SessionJournalAggregate(
            journal: updatedJournal,
            individualNotes: aggregate.individualNotes,
            actions: aggregate.actions,
            media: aggregate.media,
            links: aggregate.links
        )
        _ = try await container.sessionJournalRepository.saveJournalAggregate(aggregate: updatedAggregate)
        if let stored = try await container.sessionJournalRepository.getJournalForSession(planningSessionId: session.id) {
            enqueueSavedJournal(stored)
        } else {
            enqueueSavedJournal(updatedAggregate)
        }
    }


}
