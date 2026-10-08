//
//  KmpBridge+Inclusion.swift
//  MiGestorKMP
//
//  Puente del seguimiento de plazos del Manual de Inclusión (migración 45).
//  La lógica (plantillas, fechas, estados de plazo) vive en KMP:
//  InclusionManual e InclusionTasksUseCase. Aquí solo se traduce a Swift.
//
//  Ojo con los nombres: la maqueta de AppleShared define tipos Swift
//  InclusionPhase/InclusionTask/InclusionDeadlineStatus. Los de Kotlin se
//  nombran siempre como MiGestorKit.X para no confundirlos.
//

import Foundation
import MiGestorKit

// MARK: - Snapshots

enum InclusionPhaseUI: String, CaseIterable, Identifiable, Hashable {
    case septiembre = "SEPTIEMBRE"
    case observar = "OBSERVAR"
    case evaluacionInicial = "EVALUACION_INICIAL"
    case noviembre = "NOVIEMBRE"
    case diciembre = "DICIEMBRE"

    var id: String { rawValue }

    var kotlin: MiGestorKit.InclusionPhase {
        switch self {
        case .septiembre: return .septiembre
        case .observar: return .observar
        case .evaluacionInicial: return .evaluacionInicial
        case .noviembre: return .noviembre
        case .diciembre: return .diciembre
        }
    }
}

enum InclusionDeadlineStatusUI: String, Hashable {
    case done = "DONE"
    case overdue = "OVERDUE"
    case soon = "SOON"
    case normal = "NORMAL"
}

struct InclusionTaskSnapshot: Identifiable, Hashable {
    let id: Int64
    let studentId: Int64
    let measureId: Int64?
    /// `nil` = tarea libre del docente.
    let templateKey: String?
    let title: String
    let phase: InclusionPhaseUI
    let due: Date
    /// Fecha del manual vigente (en tareas libres coincide con `due`).
    let manualDue: Date
    let isEdited: Bool
    let canReset: Bool
    let doneOn: Date?
    let status: InclusionDeadlineStatusUI
    let notes: String

    var isDone: Bool { doneOn != nil }
}

struct InclusionStudentSnapshot: Identifiable, Hashable {
    let id: Int64
    let name: String
    /// Nivel más alto entre sus medidas activas.
    let level: SupportMeasureLevelUI?
    let measuresSummary: String
    let tasks: [InclusionTaskSnapshot]
    let doneCount: Int
    let overdueCount: Int
}

struct InclusionBoardSnapshot: Hashable {
    let classId: Int64
    let schoolYear: String
    let initialEvaluationDate: Date
    let students: [InclusionStudentSnapshot]
    let overdueCount: Int
    let dueThisWeekCount: Int
}

/// Guarda contra respuestas tardías (trampa de Alumnado): si el docente cambia
/// de grupo mientras carga, la respuesta vieja se descarta.
/// Uso: `let ticket = gate.begin(classId:)`; al volver, `guard gate.isCurrent(ticket)`.
@MainActor
final class InclusionLoadGate {
    struct Ticket: Equatable {
        fileprivate let token: Int
        let classId: Int64
    }

    private var token = 0
    private(set) var currentClassId: Int64?

    init() {}

    func begin(classId: Int64) -> Ticket {
        token += 1
        currentClassId = classId
        return Ticket(token: token, classId: classId)
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.token == token && ticket.classId == currentClassId
    }
}

// MARK: - Funciones

@MainActor
extension KmpBridge {

    /// Curso escolar ("2026-2027") de una fecha: empieza el 1 de septiembre.
    func inclusionSchoolYear(for date: Date = Date()) -> String {
        MiGestorKit.InclusionManual.shared.schoolYearFor(date: inclusionLocalDate(date))
    }

    /// Crea las tareas del manual que falten y devuelve el tablero del grupo.
    /// Si `gate` llega y el grupo cambió mientras cargaba, devuelve `nil`.
    func loadInclusionBoard(
        classId: Int64,
        today: Date = Date(),
        gate: InclusionLoadGate? = nil
    ) async throws -> InclusionBoardSnapshot? {
        let ticket = gate?.begin(classId: classId)
        let schoolYear = inclusionSchoolYear(for: today)
        _ = try await container.inclusionTasks.generateForClass(
            classId: classId,
            schoolYear: schoolYear,
            nowEpochMs: inclusionNowMs()
        )
        if let gate, let ticket, !gate.isCurrent(ticket) { return nil }

        let board = try await container.inclusionTasks.loadBoard(
            classId: classId,
            schoolYear: schoolYear,
            today: inclusionLocalDate(today)
        )
        let roster = try await container.classesRepository.listStudentsInClass(classId: classId)
        let names = Dictionary(roster.map { ($0.id, "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces)) },
                               uniquingKeysWith: { first, _ in first })

        var students: [InclusionStudentSnapshot] = []
        for studentBoard in board.students {
            let studentId = studentBoard.studentId
            let measures = try await supportMeasures(for: studentId).filter(\.isActive)
            if let gate, let ticket, !gate.isCurrent(ticket) { return nil }
            let level: SupportMeasureLevelUI? = measures.contains { $0.level == .iv } ? .iv : (measures.isEmpty ? nil : .iii)
            students.append(InclusionStudentSnapshot(
                id: studentId,
                name: names[studentId] ?? "",
                level: level,
                measuresSummary: measures.map(\.measureType.displayName).joined(separator: " + "),
                tasks: studentBoard.items.compactMap(inclusionTaskSnapshot(from:)),
                doneCount: Int(studentBoard.doneCount),
                overdueCount: Int(studentBoard.overdueCount)
            ))
        }
        if let gate, let ticket, !gate.isCurrent(ticket) { return nil }

        return InclusionBoardSnapshot(
            classId: board.classId,
            schoolYear: board.schoolYear,
            initialEvaluationDate: inclusionDate(board.initialEvaluationDate),
            students: students.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            overdueCount: Int(board.summary.overdue),
            dueThisWeekCount: Int(board.summary.dueThisWeek)
        )
    }

    /// Marca o desmarca. Devuelve `true` si ha quedado hecha.
    @discardableResult
    func toggleInclusionTask(id: Int64, today: Date = Date()) async throws -> Bool {
        try await container.inclusionTasks.toggleDone(
            taskId: id,
            today: inclusionLocalDate(today),
            nowEpochMs: inclusionNowMs()
        ).boolValue
    }

    /// Fecha elegida por el docente. `classId` decide qué evaluación inicial se usa.
    func setInclusionTaskDue(id: Int64, classId: Int64, to date: Date) async throws {
        try await container.inclusionTasks.setDueDate(
            taskId: id,
            classId: classId,
            date: inclusionLocalDate(date),
            nowEpochMs: inclusionNowMs()
        )
    }

    /// Vuelve a la fecha del manual. Devuelve `false` en tareas libres.
    @discardableResult
    func resetInclusionTaskDue(id: Int64, classId: Int64) async throws -> Bool {
        try await container.inclusionTasks.resetDueDate(
            taskId: id,
            classId: classId,
            nowEpochMs: inclusionNowMs()
        ).boolValue
    }

    /// Guarda la evaluación inicial del grupo. Devuelve cuántas fechas se movieron.
    @discardableResult
    func setInclusionInitialEvaluation(classId: Int64, date: Date, today: Date = Date()) async throws -> Int {
        let moved = try await container.inclusionTasks.setInitialEvaluationDate(
            classId: classId,
            schoolYear: inclusionSchoolYear(for: today),
            date: inclusionLocalDate(date),
            nowEpochMs: inclusionNowMs()
        )
        return Int(moved.int32Value)
    }

    @discardableResult
    func addInclusionTask(
        studentId: Int64,
        title: String,
        phase: InclusionPhaseUI,
        due: Date,
        notes: String = "",
        today: Date = Date()
    ) async throws -> Int64 {
        try await container.inclusionTasks.addFreeTask(
            studentId: studentId,
            title: title,
            phase: phase.kotlin,
            due: inclusionLocalDate(due),
            schoolYear: inclusionSchoolYear(for: today),
            nowEpochMs: inclusionNowMs(),
            notes: notes
        ).int64Value
    }

    // MARK: Conversión

    private func inclusionTaskSnapshot(from item: MiGestorKit.InclusionTaskItem) -> InclusionTaskSnapshot? {
        let task = item.task
        guard
            let phase = InclusionPhaseUI(rawValue: task.phase.name),
            let status = InclusionDeadlineStatusUI(rawValue: item.status.name)
        else { return nil }
        return InclusionTaskSnapshot(
            id: task.id,
            studentId: task.studentId,
            measureId: task.measureId?.int64Value,
            templateKey: task.templateKey,
            title: task.title,
            phase: phase,
            due: inclusionDate(task.dueDate),
            manualDue: inclusionDate(item.manualDue),
            isEdited: item.isEdited,
            canReset: item.canReset,
            doneOn: task.doneAt.map(inclusionDate(_:)),
            status: status,
            notes: task.notes
        )
    }

    private static let inclusionCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private func inclusionLocalDate(_ date: Date) -> LocalDate {
        let parts = Self.inclusionCalendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(
            year: Int32(parts.year ?? 2026),
            monthNumber: Int32(parts.month ?? 1),
            dayOfMonth: Int32(parts.day ?? 1)
        )
    }

    private func inclusionDate(_ date: LocalDate) -> Date {
        let parts = DateComponents(year: Int(date.year), month: Int(date.monthNumber), day: Int(date.dayOfMonth), hour: 12)
        return Self.inclusionCalendar.date(from: parts) ?? Date()
    }

    private func inclusionNowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
