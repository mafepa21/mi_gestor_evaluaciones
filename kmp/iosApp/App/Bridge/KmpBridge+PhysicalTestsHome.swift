import Foundation
import MiGestorKit

/// Todo lo que pinta la pantalla «Pruebas físicas»: pruebas, baterías y, por
/// grupo, qué pruebas están en su cuaderno.
struct PhysicalTestsHomeSnapshot {
    var definitions: [PhysicalTestDefinition] = []
    var scalesByTest: [String: [PhysicalTestScale]] = [:]
    var batteries: [PhysicalTestBattery] = []
    var groups: [PhysicalGroupSummary] = []

    func scales(for definitionId: String) -> [PhysicalTestScale] {
        scalesByTest[definitionId] ?? []
    }

    func groups(using definitionId: String) -> [(group: PhysicalGroupSummary, entry: PhysicalGroupTestEntry)] {
        groups.flatMap { group in
            group.entries.filter { $0.definition.id == definitionId }.map { (group, $0) }
        }
    }
}

struct PhysicalGroupSummary: Identifiable {
    let schoolClass: SchoolClass
    let students: [Student]
    let entries: [PhysicalGroupTestEntry]
    let missing: PhysicalTestNotebookPlacement.MissingData

    var id: Int64 { schoolClass.id }
}

struct PhysicalGroupTestEntry: Identifiable {
    let assignment: PhysicalTestAssignment
    let definition: PhysicalTestDefinition
    let rawColumnId: String?
    let scoreColumnId: String?
    let tabTitle: String?
    let markedCount: Int
    let scoredCount: Int
    let hasScale: Bool
    let scoreCountsTowardAverage: Bool
    let scoreWeight: Double

    var id: String { "\(assignment.id)|\(definition.id)" }
    var termLabel: String { assignment.termLabel ?? "Sin evaluación" }
    var columnIds: [String] { [rawColumnId, scoreColumnId].compactMap { $0 } }
}

struct PhysicalAddToNotebookOutcome {
    var added: [String] = []
    var alreadyThere: [String] = []
}

@MainActor
extension KmpBridge {
    func loadPhysicalTestsHome() async throws -> PhysicalTestsHomeSnapshot {
        let repository = container.physicalTestsRepository
        let definitions = try await repository.listDefinitions()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var scalesByTest: [String: [PhysicalTestScale]] = [:]
        for definition in definitions {
            scalesByTest[definition.id] = try await repository.listScalesForTest(testId: definition.id)
        }
        let allBatteries = try await repository.listBatteries()
        let definitionsById = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let batteriesById = Dictionary(allBatteries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var groups: [PhysicalGroupSummary] = []
        for schoolClass in classes.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let students = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            let assignments = try await repository.listAssignmentsForClass(classId: schoolClass.id)
            var entries: [PhysicalGroupTestEntry] = []
            var usedScales: [PhysicalTestScale] = []
            if !assignments.isEmpty {
                let columns = try await container.notebookConfigRepository.listColumns(classId: schoolClass.id)
                let columnsById = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let tabs = try await container.notebookConfigRepository.listTabs(classId: schoolClass.id)
                let tabTitles = Dictionary(tabs.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
                let grades = try await container.gradesRepository.listGradesForClass(classId: schoolClass.id)
                var filledByColumn: [String: Int] = [:]
                for grade in grades where grade.value != nil {
                    filledByColumn[grade.columnId, default: 0] += 1
                }
                var seenColumns = Set<String>()
                for assignment in assignments {
                    let links = try await repository.listNotebookLinksForAssignment(assignmentId: assignment.id)
                    let testIds = batteriesById[assignment.batteryId]?.testIds ?? links.map(\.testId)
                    for testId in testIds {
                        guard let definition = definitionsById[testId],
                              let link = links.first(where: { $0.testId == testId }) else { continue }
                        // Solo cuenta lo que sigue en el cuaderno, y una vez (asignaciones viejas repetidas).
                        let liveIds = [link.rawColumnId, link.scoreColumnId].compactMap { $0 }.filter { columnsById[$0] != nil }
                        guard !liveIds.isEmpty, seenColumns.isDisjoint(with: liveIds) else { continue }
                        seenColumns.formUnion(liveIds)
                        let score = link.scoreColumnId.flatMap { columnsById[$0] }
                        let raw = link.rawColumnId.flatMap { columnsById[$0] }
                        let scales = scalesByTest[testId] ?? []
                        usedScales.append(contentsOf: scales)
                        entries.append(PhysicalGroupTestEntry(
                            assignment: assignment,
                            definition: definition,
                            rawColumnId: raw?.id,
                            scoreColumnId: score?.id,
                            tabTitle: (score ?? raw)?.tabIds.first.flatMap { tabTitles[$0] },
                            markedCount: raw.map { filledByColumn[$0.id] ?? 0 } ?? 0,
                            scoredCount: score.map { filledByColumn[$0.id] ?? 0 } ?? 0,
                            hasScale: !scales.isEmpty,
                            scoreCountsTowardAverage: score?.countsTowardAverage ?? false,
                            scoreWeight: score?.weight ?? 0
                        ))
                    }
                }
            }
            groups.append(PhysicalGroupSummary(
                schoolClass: schoolClass,
                students: students,
                entries: entries.sorted {
                    if $0.termLabel != $1.termLabel { return $0.termLabel < $1.termLabel }
                    return $0.definition.name.localizedCaseInsensitiveCompare($1.definition.name) == .orderedAscending
                },
                missing: PhysicalTestNotebookPlacement.missingData(students: students, scales: usedScales)
            ))
        }

        return PhysicalTestsHomeSnapshot(
            definitions: definitions,
            scalesByTest: scalesByTest,
            batteries: allBatteries.filter(PhysicalTestNotebookPlacement.isUserBattery)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            groups: groups
        )
    }

    /// Añade pruebas al cuaderno de un grupo. Lo que ya estaba (misma prueba,
    /// grupo y evaluación con su columna viva) no se duplica.
    func addPhysicalTestsToNotebook(
        classId: Int64,
        definitions: [PhysicalTestDefinition],
        termLabel: String?,
        notebookTab: String,
        countsTowardAverage: Bool,
        existing: [PhysicalGroupTestEntry]
    ) async throws -> PhysicalAddToNotebookOutcome {
        var outcome = PhysicalAddToNotebookOutcome()
        for definition in definitions {
            if existing.contains(where: { $0.definition.id == definition.id && $0.assignment.termLabel == termLabel }) {
                outcome.alreadyThere.append(definition.name)
                continue
            }
            let measurement = PhysicalTestMeasurement(kind: definition.measurementKind)
            let draft = PhysicalTestSetupDraft(
                existingDefinitionId: definition.id,
                name: definition.name,
                unit: definition.unit,
                measurement: measurement,
                capacity: PhysicalTestCapacity(capacity: definition.capacity),
                higherIsBetter: definition.higherIsBetter,
                attempts: Int(definition.attempts),
                resultMode: .best,
                scaleGroups: [],
                classId: classId,
                notebookTab: notebookTab,
                date: Date(),
                termLabel: termLabel,
                countsTowardAverage: countsTowardAverage
            )
            _ = try await savePhysicalTestSetup(draft)
            outcome.added.append(definition.name)
        }
        if notebookViewModel.currentClassId?.int64Value == classId {
            notebookViewModel.selectClass(classId: classId, force: true)
        }
        return outcome
    }

    /// Quita la prueba del cuaderno del grupo: borra sus columnas (y sus marcas).
    func removePhysicalTestFromNotebook(_ entry: PhysicalGroupTestEntry) async throws {
        for columnId in entry.columnIds {
            try await deleteColumnAwaitingSuccess(id: columnId, evaluationId: nil)
        }
    }

    func createPhysicalTest(from template: PhysicalTestTemplate) async throws -> String {
        let id = "pe_catalog_\(template.id)"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        try await savePhysicalDefinition(PhysicalTestDefinition(
            id: id,
            name: template.name,
            capacity: template.capacity.kitCapacity,
            measurementKind: template.measurement.kitKind,
            unit: template.unit,
            higherIsBetter: template.direction == .higherIsBetter,
            protocol: template.protocolText,
            material: "",
            attempts: Int32(template.attempts),
            resultMode: template.resultMode.kitMode,
            trace: AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: localDeviceId, syncVersion: 1)
        ))
        return id
    }

    func savePhysicalBattery(id: String?, name: String, testIds: [String]) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        try await savePhysicalBattery(PhysicalTestBattery(
            id: id ?? "pe_battery_\(PhysicalTestNotebookPlacement.slug(name))_\(nowMs)",
            name: name,
            description: "",
            defaultCourse: nil,
            defaultAgeFrom: nil,
            defaultAgeTo: nil,
            testIds: testIds,
            trace: AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: localDeviceId, syncVersion: 1)
        ))
    }
}

extension PhysicalTestMeasurement {
    init(kind: PhysicalMeasurementKind) {
        switch kind {
        case .time: self = .time
        case .repetitions: self = .repetitions
        case .level: self = .level
        default: self = .distance
        }
    }

    var kitKind: PhysicalMeasurementKind {
        switch self {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .level
        }
    }
}

extension PhysicalTestCapacity {
    init(capacity: PhysicalCapacity) {
        switch capacity {
        case .resistance: self = .resistance
        case .speed: self = .speed
        case .flexibility: self = .flexibility
        default: self = .strength
        }
    }

    var kitCapacity: PhysicalCapacity {
        switch self {
        case .resistance: return .resistance
        case .strength: return .strength
        case .speed: return .speed
        case .flexibility: return .flexibility
        }
    }
}

extension PhysicalTestResultMode {
    var kitMode: PhysicalResultMode {
        switch self {
        case .best: return .best
        case .average: return .average
        case .last: return .last
        }
    }
}

extension PhysicalTestDefinition {
    var measurementLabel: String {
        switch measurementKind {
        case .time: return "Tiempo"
        case .distance: return "Distancia"
        case .repetitions: return "Repeticiones"
        case .level: return "Nivel"
        default: return "Marca"
        }
    }

    var capacityLabel: String {
        switch capacity {
        case .resistance: return "Resistencia"
        case .strength: return "Fuerza"
        case .speed: return "Velocidad"
        case .flexibility: return "Movilidad"
        case .coordination: return "Coordinación"
        case .agility: return "Agilidad"
        default: return "Otra"
        }
    }

    var betterLabel: String {
        switch measurementKind {
        case .time: return higherIsBetter ? "Más tiempo" : "Menos tiempo"
        default: return higherIsBetter ? "Más es mejor" : "Menos es mejor"
        }
    }
}
