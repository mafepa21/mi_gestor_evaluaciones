import Foundation
import MiGestorKit

// Lesiones con fecha (migración 51). La lógica vive en KMP (`StudentInjuryUseCase`);
// aquí solo se traduce a tipos Swift, se encola para Sync LAN y se avisa a las vistas.
// `students.is_injured` sigue existiendo como marca derivada: los usos antiguos
// (`student.isInjured`) no cambian.

/// Papel en clase del alumno lesionado. `rawValue` = nombre guardado en KMP.
enum InjuryRoleUI: String, CaseIterable, Identifiable, Sendable {
    case none = "NONE"
    case referee = "REFEREE"
    case timekeeper = "TIMEKEEPER"
    case equipmentHelper = "EQUIPMENT_HELPER"
    case theorySheet = "THEORY_SHEET"
    case other = "OTHER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Sin papel"
        case .referee: return "Árbitro"
        case .timekeeper: return "Cronometrador"
        case .equipmentHelper: return "Ayudante de material"
        case .theorySheet: return "Ficha teórica"
        case .other: return "Otro"
        }
    }

    init(storage: String) {
        self = InjuryRoleUI(rawValue: storage) ?? .none
    }
}

/// Lesión lista para pintar. Las fechas son días de calendario (a mediodía local).
struct StudentInjurySnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let studentId: Int64
    var startsOn: Date
    var endsOn: Date?
    var role: InjuryRoleUI
    var note: String
    var proofDelivered: Bool
}

/// Alumno que vuelve hoy de una lesión (su «hasta» fue ayer). Para «Hoy» › Atención.
struct InjuryReturnNotice: Identifiable, Equatable, Sendable {
    let injury: StudentInjurySnapshot
    let studentName: String
    var id: String { injury.id }
    var studentId: Int64 { injury.studentId }
}

/// Lesiones activas hoy y alumnos que vuelven hoy. Compartido por Asistencia, ficha,
/// Cuaderno y «Hoy» sin que ninguna vista observe `KmpBridge` entero.
@MainActor
final class StudentInjuryStore: ObservableObject {
    static let shared = StudentInjuryStore()

    @Published private(set) var activeByStudent: [Int64: StudentInjurySnapshot] = [:]
    @Published private(set) var returningToday: [InjuryReturnNotice] = []
    /// Sube en cada publicación: las vistas que leen lesiones no activas (historial,
    /// programadas) se recargan con él.
    @Published private(set) var version = 0
    /// Día al que corresponden los datos: si cambia el día, hay que recalcular.
    private(set) var loadedDay: Date?
    /// Las lesiones se reencolan para Sync LAN una sola vez por arranque.
    var didRequeueThisLaunch = false

    func publish(active: [Int64: StudentInjurySnapshot], returning: [InjuryReturnNotice], day: Date) {
        if activeByStudent != active { activeByStudent = active }
        if returningToday != returning { returningToday = returning }
        loadedDay = day
        version += 1
    }
}

enum StudentInjuryText {
    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    static func shortDate(_ date: Date) -> String { dayMonth.string(from: date) }

    /// «Lesionado hasta el 12 dic · Árbitro» / «Lesionado sin fecha de fin».
    static func badge(_ injury: StudentInjurySnapshot, today: Date = Date()) -> String {
        var text: String
        if let endsOn = injury.endsOn {
            text = Calendar.current.isDate(endsOn, inSameDayAs: today)
                ? "Lesionado · último día hoy"
                : "Lesionado hasta el \(shortDate(endsOn))"
        } else {
            text = "Lesionado sin fecha de fin"
        }
        if injury.role != .none { text += " · \(injury.role.title)" }
        return text
    }
}

extension KmpBridge {
    // MARK: - Lectura

    /// Lesiones del alumno (sin las borradas), la más reciente primero.
    func injuries(forStudentId studentId: Int64) async throws -> [StudentInjurySnapshot] {
        try await container.studentInjuries.listForStudent(studentId: studentId).map(injurySnapshot)
    }

    /// Recalcula la marca de hoy y publica activas y «vuelven hoy». Llamar al abrir la
    /// app, al volver a primer plano y tras sincronizar. Si alguna marca cambió,
    /// refresca el alumnado para que los usos de `isInjured` lo vean.
    func refreshInjuries() async {
        do {
            // Primera carga de este arranque: se reencolan todas las lesiones (son pocas).
            // Si el otro aparato aún no tenía la migración 51 y las ignoró, se ponen al día.
            if !StudentInjuryStore.shared.didRequeueThisLaunch {
                StudentInjuryStore.shared.didRequeueThisLaunch = true
                for injury in try await container.studentInjuryRepository.listAll() {
                    enqueueInjury(injury)
                }
            }
            let changed = try await container.studentInjuries.reconcileFlags()
            try await publishInjuries()
            // `count` y no `isEmpty`: el Set de Kotlin llega como NSSet; no se itera.
            if changed.count > 0 {
                try await refreshStudentsDirectory()
            }
        } catch {
            // Sin datos de lesiones las pantallas siguen con `isInjured`: no se bloquea nada.
        }
    }

    /// Publica sin recalcular marcas (tras guardar, el caso de uso ya lo hizo).
    func publishInjuries() async throws {
        let active = try await container.studentInjuries.activeToday()
        let returning = try await container.studentInjuries.returningToday()
        var byStudent: [Int64: StudentInjurySnapshot] = [:]
        for injury in active {
            byStudent[injury.studentId] = injurySnapshot(injury)
        }
        // Solo alumnos que existen: una lesión huérfana no debe salir sin nombre.
        var notices: [InjuryReturnNotice] = []
        for injury in returning {
            guard let student = try await container.studentsRepository.getStudent(studentId: injury.studentId) else { continue }
            notices.append(InjuryReturnNotice(injury: injurySnapshot(injury), studentName: student.fullName))
        }
        StudentInjuryStore.shared.publish(
            active: byStudent.filter { key, _ in allStudents.isEmpty || allStudents.contains { $0.id == key } },
            returning: notices,
            day: Calendar.current.startOfDay(for: Date())
        )
    }

    /// Si el día cambió desde la última carga (app abierta de un día para otro).
    func refreshInjuriesIfDayChanged() async {
        let today = Calendar.current.startOfDay(for: Date())
        guard StudentInjuryStore.shared.loadedDay != today else { return }
        await refreshInjuries()
    }

    // MARK: - Escritura

    /// Crea o edita. Devuelve la lesión guardada. Lanza si las fechas o la nota no valen.
    @discardableResult
    func saveInjury(
        id: String?,
        studentId: Int64,
        startsOn: Date,
        endsOn: Date?,
        role: InjuryRoleUI,
        note: String,
        proofDelivered: Bool
    ) async throws -> StudentInjurySnapshot {
        let draft = StudentInjuryDraft(
            id: id,
            studentId: studentId,
            startsOn: injuryLocalDate(startsOn),
            endsOn: endsOn.map(injuryLocalDate),
            role: InjuryRole.companion.fromStorage(value: role.rawValue),
            note: note,
            proofDelivered: proofDelivered
        )
        let saved = try await container.studentInjuries.save(draft: draft, nowEpochMs: injuryNowMs(), deviceId: localDeviceId)
        try await afterInjuryChange([saved])
        return injurySnapshot(saved)
    }

    /// «Ha vuelto»: termina ayer (o se borra si empezó hoy).
    func markInjuryReturned(id: String) async throws {
        guard let updated = try await container.studentInjuries.markReturned(
            injuryId: id, nowEpochMs: injuryNowMs(), deviceId: localDeviceId
        ) else { return }
        try await afterInjuryChange([updated])
    }

    /// Borrado lógico de una lesión puesta por error.
    func deleteInjury(id: String) async throws {
        guard let deleted = try await container.studentInjuries.delete(
            injuryId: id, nowEpochMs: injuryNowMs(), deviceId: localDeviceId
        ) else { return }
        try await afterInjuryChange([deleted])
    }

    /// Interruptores rápidos de siempre: marcar crea una lesión desde hoy sin fecha
    /// de fin; quitar marca «ha vuelto» en las activas.
    func setStudentInjured(studentId: Int64, injured: Bool) async throws {
        let changed = try await container.studentInjuries.setInjured(
            studentId: studentId, injured: injured, nowEpochMs: injuryNowMs(), deviceId: localDeviceId
        )
        try await afterInjuryChange(changed)
    }

    private func afterInjuryChange(_ injuries: [StudentInjury]) async throws {
        for injury in injuries {
            enqueueInjury(injury)
        }
        try await publishInjuries()
        try await refreshStudentsDirectory()
        try await refreshDashboard()
    }

    private func enqueueInjury(_ injury: StudentInjury) {
        let json = SchoolRecordsSync.companion.injuryPayload(injury: injury)
        guard let data = json.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        enqueueLocalChange(
            entity: SchoolRecordsSync.companion.STUDENT_INJURIES,
            id: injury.id,
            updatedAtEpochMs: injury.trace.updatedAt.toEpochMilliseconds(),
            payload: payload
        )
    }

    // MARK: - Conversión

    private func injurySnapshot(_ injury: StudentInjury) -> StudentInjurySnapshot {
        StudentInjurySnapshot(
            id: injury.id,
            studentId: injury.studentId,
            startsOn: injuryDate(injury.startsOn),
            endsOn: injury.endsOn.map(injuryDate),
            role: InjuryRoleUI(storage: injury.role.name),
            note: injury.note,
            proofDelivered: injury.proofDelivered
        )
    }

    private func injuryLocalDate(_ date: Date) -> LocalDate {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return LocalDate(
            year: Int32(parts.year ?? 2026),
            monthNumber: Int32(parts.month ?? 1),
            dayOfMonth: Int32(parts.day ?? 1)
        )
    }

    private func injuryDate(_ date: LocalDate) -> Date {
        let parts = DateComponents(year: Int(date.year), month: Int(date.monthNumber), day: Int(date.dayOfMonth), hour: 12)
        return Calendar.current.date(from: parts) ?? Date()
    }

    private func injuryNowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
