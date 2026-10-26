//
//  KmpBridge+PhysicalTestSetup.swift
//  MiGestorKMP
//
//  Guardado del asistente «Nueva prueba» (Test → Baremo → Cuaderno).
//

import Foundation
import MiGestorKit

/// Lo que el asistente ha reunido antes de pulsar «Guardar y añadir».
struct PhysicalTestSetupDraft {
    /// Prueba ya guardada que se reutiliza; `nil` crea una nueva.
    var existingDefinitionId: String?
    var name: String
    var unit: String
    var measurement: PhysicalTestMeasurement
    var capacity: PhysicalTestCapacity
    var higherIsBetter: Bool
    var attempts: Int
    var resultMode: PhysicalTestResultMode
    var scaleGroups: [PhysicalScaleSpreadsheetImport.Group]
    /// Grupo donde se añaden las columnas; `nil` guarda solo la prueba y su baremo.
    var classId: Int64?
    /// Id de una pestaña existente o título de una pestaña nueva.
    var notebookTab: String?
    var date: Date
}

struct PhysicalTestSetupOutcome {
    var definitionId: String
    var classId: Int64?
    var notebookTabId: String?
    var createdColumns: Int
}

@MainActor
extension KmpBridge {
    func listNotebookTabsForClass(classId: Int64) async throws -> [NotebookTab] {
        try await container.notebookConfigRepository.listTabs(classId: classId)
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    /// Guarda la prueba, sus baremos y, si hay grupo, la asignación, la
    /// categoría y las columnas «Marca» y «Nota» del cuaderno.
    ///
    /// Los ids son estables por prueba y grupo: repetir el asistente con la
    /// misma prueba sobrescribe en lugar de duplicar.
    func savePhysicalTestSetup(_ draft: PhysicalTestSetupDraft) async throws -> PhysicalTestSetupOutcome {
        defer { triggerAutoSyncSoon() }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw NSError(domain: "KmpBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "La prueba necesita un nombre."])
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = physicalSetupTrace(classId: draft.classId, epochMs: nowMs)
        let definitionId = draft.existingDefinitionId ?? "pe_custom_\(physicalSetupSlug(name))_\(nowMs)"
        let kitMeasurement = physicalSetupMeasurement(draft.measurement)

        if draft.existingDefinitionId == nil {
            try await container.physicalTestsRepository.saveDefinition(
                definition: PhysicalTestDefinition(
                    id: definitionId,
                    name: name,
                    capacity: physicalSetupCapacity(draft.capacity),
                    measurementKind: kitMeasurement,
                    unit: draft.unit,
                    higherIsBetter: draft.higherIsBetter,
                    protocol: "",
                    material: "",
                    attempts: Int32(max(1, draft.attempts)),
                    resultMode: physicalSetupResultMode(draft.resultMode),
                    trace: trace
                )
            )
        }

        // Sin batería: así el baremo vale para cualquier asignación de la prueba
        // (ver `resolveScale`, que cae a baremos sin batería por curso o edad).
        for group in draft.scaleGroups {
            let scaleId = "pe_wizard_scale_\(definitionId)_\(group.key)"
            try await container.physicalTestsRepository.saveScale(
                scale: PhysicalTestScale(
                    id: scaleId,
                    testId: definitionId,
                    name: "\(name) · \(group.title)",
                    course: group.course.map { KotlinInt(value: Int32($0)) },
                    ageFrom: group.ageFrom.map { KotlinInt(value: Int32($0)) },
                    ageTo: group.ageTo.map { KotlinInt(value: Int32($0)) },
                    sex: group.sex,
                    batteryId: nil,
                    direction: draft.higherIsBetter ? .higherIsBetter : .lowerIsBetter,
                    ranges: group.ranges.enumerated().map { index, range in
                        MiGestorKit.PhysicalTestScaleRange(
                            id: "\(scaleId)_range_\(index + 1)",
                            scaleId: scaleId,
                            minValue: range.minValue.map { KotlinDouble(value: $0) },
                            maxValue: range.maxValue.map { KotlinDouble(value: $0) },
                            score: range.score,
                            label: nil,
                            sortOrder: Int32(index)
                        )
                    },
                    scoringMode: .step,
                    scoreRoundTo: nil,
                    trace: trace
                )
            )
        }

        guard let classId = draft.classId else {
            return PhysicalTestSetupOutcome(definitionId: definitionId, classId: nil, notebookTabId: nil, createdColumns: 0)
        }

        var hasScale = !draft.scaleGroups.isEmpty
        if !hasScale {
            hasScale = !(try await container.physicalTestsRepository.listScalesForTest(testId: definitionId)).isEmpty
        }
        let dateMs = Int64(draft.date.timeIntervalSince1970 * 1000)
        let course = classes.first(where: { $0.id == classId }).map { KotlinInt(value: $0.course) }
        let batteryId = "pe_wizard_battery_\(definitionId)"
        let assignmentId = "pe_wizard_assignment_\(definitionId)_\(classId)"

        try await container.physicalTestsRepository.saveBattery(
            battery: PhysicalTestBattery(
                id: batteryId,
                name: name,
                description: "Creada con el asistente de pruebas físicas",
                defaultCourse: course,
                defaultAgeFrom: nil,
                defaultAgeTo: nil,
                testIds: [definitionId],
                trace: trace
            )
        )
        try await container.physicalTestsRepository.assignBatteryToClass(
            assignment: PhysicalTestAssignment(
                id: assignmentId,
                batteryId: batteryId,
                classId: classId,
                course: course,
                ageFrom: nil,
                ageTo: nil,
                termLabel: nil,
                dateEpochMs: dateMs,
                rawColumnMode: true,
                scoreColumnMode: hasScale,
                trace: trace
            )
        )

        let tabId = try await resolveNotebookTargetTabId(classId: classId, preferredTabId: draft.notebookTab)
        let categories = try await container.notebookRepository.listColumnCategories(classId: classId, tabId: tabId)
        if !categories.contains(where: { $0.id == assignmentId }) {
            try await container.notebookRepository.saveColumnCategory(
                classId: classId,
                category: NotebookColumnCategory(
                    id: assignmentId,
                    classId: classId,
                    tabId: tabId,
                    name: name,
                    order: (categories.map(\.order).max() ?? -1) + 1,
                    isCollapsed: false,
                    trace: trace
                )
            )
        }

        // El listado de pruebas del grupo sale de sus evaluaciones.
        let code = "EF_\(definitionId.uppercased())"
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        if !evaluations.contains(where: { $0.code == code }) {
            _ = try await createPhysicalTest(
                classId: classId,
                code: code,
                name: name,
                kind: draft.measurement.rawValue,
                weight: 1,
                description: nil
            )
        }

        let existingLink = try await container.physicalTestsRepository
            .listNotebookLinksForAssignment(assignmentId: assignmentId)
            .first { $0.testId == definitionId }
        let existingColumns = try await container.notebookConfigRepository.listColumns(classId: classId)
        func existingColumnId(_ title: String) -> String? {
            existingColumns.first { $0.title == title && $0.categoryId == assignmentId }?.id
        }
        var createdColumns = 0

        let rawTitle = "\(name) · \(draft.measurement == .level ? "Nivel" : "Marca")"
        let rawColumnId: String
        if let id = existingLink?.rawColumnId ?? existingColumnId(rawTitle) {
            rawColumnId = id
        } else {
            rawColumnId = try await createNotebookPhysicalColumnForClass(
                classId: classId,
                name: rawTitle,
                categoryId: assignmentId,
                inputKind: draft.measurement.inputKind,
                unitOrSituation: "Dato bruto · \(draft.unit)",
                scaleKind: draft.measurement.scaleKind,
                iconName: "stopwatch.fill",
                weight: 0,
                countsTowardAverage: false,
                dateEpochMs: dateMs,
                targetTabId: tabId
            )
            createdColumns += 1
        }

        var scoreColumnId: String?
        if hasScale {
            let scoreTitle = "\(name) · Nota"
            if let id = existingLink?.scoreColumnId ?? existingColumnId(scoreTitle) {
                scoreColumnId = id
            } else {
                scoreColumnId = try await createNotebookPhysicalColumnForClass(
                    classId: classId,
                    name: scoreTitle,
                    categoryId: assignmentId,
                    inputKind: .numeric010,
                    unitOrSituation: "Nota baremada",
                    scaleKind: .tenPoint,
                    iconName: "chart.bar.fill",
                    weight: 10,
                    countsTowardAverage: true,
                    dateEpochMs: dateMs,
                    targetTabId: tabId
                )
                createdColumns += 1
            }
        }

        if existingLink?.rawColumnId != rawColumnId || existingLink?.scoreColumnId != scoreColumnId {
            try await container.physicalTestsRepository.saveNotebookLink(
                link: PhysicalTestNotebookLink(
                    assignmentId: assignmentId,
                    testId: definitionId,
                    rawColumnId: rawColumnId,
                    scoreColumnId: scoreColumnId,
                    trace: trace
                )
            )
        }

        return PhysicalTestSetupOutcome(
            definitionId: definitionId,
            classId: classId,
            notebookTabId: tabId,
            createdColumns: createdColumns
        )
    }

    private func physicalSetupTrace(classId: Int64?, epochMs: Int64) -> AuditTrace {
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: epochMs)
        return AuditTrace(
            authorUserId: nil,
            createdAt: now,
            updatedAt: now,
            associatedGroupId: classId.map { KotlinLong(value: $0) },
            deviceId: localDeviceId,
            syncVersion: 0
        )
    }

    private func physicalSetupSlug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
        let slug = folded.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return String(slug.split(separator: "_").joined(separator: "_").prefix(32))
    }

    private func physicalSetupCapacity(_ capacity: PhysicalTestCapacity) -> PhysicalCapacity {
        switch capacity {
        case .resistance: return .resistance
        case .strength: return .strength
        case .speed: return .speed
        case .flexibility: return .flexibility
        }
    }

    private func physicalSetupMeasurement(_ measurement: PhysicalTestMeasurement) -> PhysicalMeasurementKind {
        switch measurement {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .level
        }
    }

    private func physicalSetupResultMode(_ mode: PhysicalTestResultMode) -> MiGestorKit.PhysicalResultMode {
        switch mode {
        case .best: return .best
        case .average: return .average
        case .last: return .last
        }
    }
}
