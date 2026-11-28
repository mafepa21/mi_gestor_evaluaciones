import Foundation
import MiGestorKit

// «Alumnos invisibles» (ticket 2026-11-27): alumnado de un grupo sin ningún registro
// del docente en 14 días lectivos. La cuenta la hace KMP (`UnseenStudentsUseCase`);
// aquí se traduce a Swift, se pasan los días no lectivos y se guarda «Visto».

/// Alumno sin mirar, listo para pintar.
struct UnseenStudentRow: Identifiable, Equatable, Sendable {
    let studentId: Int64
    let classId: Int64
    let name: String
    let hasSupportMeasure: Bool
    /// `nil` si no hay ningún registro.
    let daysSinceLast: Int?
    /// «Nota en Hockey, 10 nov» o «Sin registros desde que empezó el curso».
    let lastDescription: String
    var id: Int64 { studentId }

    /// «17 días sin registro» / «Ningún registro».
    var daysText: String {
        guard let daysSinceLast else { return "Ningún registro" }
        return daysSinceLast == 1 ? "1 día sin registro" : "\(daysSinceLast) días sin registro"
    }
}

/// Alumno marcado «Visto» en este aparato: no sale hasta `until`.
struct SeenStudentRow: Identifiable, Equatable, Sendable {
    let studentId: Int64
    let name: String
    let until: Date
    var id: Int64 { studentId }
}

/// Resumen de un grupo para «Hoy» › Atención.
struct UnseenGroupSummary: Identifiable, Equatable, Sendable {
    let classId: Int64
    let className: String
    let count: Int
    let previewNames: [String]
    var id: Int64 { classId }

    var title: String {
        "\(className): \(count) sin mirar en 2 semanas"
    }

    /// «Ana López, Pablo García y 2 más».
    var detail: String {
        let shown = previewNames.prefix(2)
        let rest = count - shown.count
        let names = shown.joined(separator: ", ")
        return rest > 0 ? "\(names) y \(rest) más" : names
    }
}

/// Lo que «Hoy» pinta los viernes. Compartido para no observar `KmpBridge` entero.
@MainActor
final class UnseenStudentsStore: ObservableObject {
    static let shared = UnseenStudentsStore()

    @Published private(set) var summaries: [UnseenGroupSummary] = []
    /// Sube con cada cambio (observación guardada, «Visto»): las listas se recargan.
    @Published private(set) var version = 0
    private(set) var loadedDay: Date?
    /// Hay un cálculo del resumen de «Hoy» en marcha (evita calcularlo dos veces a la vez).
    var isRefreshingSummaries = false

    /// Resultado por grupo, válido mientras no cambien el día ni `version`.
    struct CachedReport {
        let day: Date
        let version: Int
        let unseen: [UnseenStudentRow]
        let seen: [SeenStudentRow]
        let total: Int
    }
    var cache: [Int64: CachedReport] = [:]

    /// Publica el resumen solo si nada cambió mientras se calculaba (`version`).
    func publish(_ summaries: [UnseenGroupSummary], day: Date, computedAt version: Int) {
        guard version == self.version else { return }
        if self.summaries != summaries { self.summaries = summaries }
        loadedDay = day
    }

    func clearSummaries(day: Date) {
        if !summaries.isEmpty { summaries = [] }
        loadedDay = day
    }

    func markNotLoaded() { loadedDay = nil }

    func bump() {
        version += 1
        loadedDay = nil
        cache.removeAll()
    }
}

/// «Visto» guardado solo en este aparato (`UserDefaults`), 7 días.
enum UnseenSeenStore {
    static let days = 7
    private static let key = "attention.seen.v1"

    private static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private static func save(_ value: [String: Double]) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func entryKey(classId: Int64, studentId: Int64) -> String { "\(classId)|\(studentId)" }

    /// Alumnos «Vistos» todavía vigentes en el grupo, con su fecha de vuelta.
    static func active(classId: Int64, now: Date = Date()) -> [Int64: Date] {
        var result: [Int64: Date] = [:]
        var all = load()
        var changed = false
        for (entry, until) in all {
            let untilDate = Date(timeIntervalSince1970: until)
            if untilDate <= now { all[entry] = nil; changed = true; continue }
            let parts = entry.split(separator: "|")
            guard parts.count == 2, Int64(parts[0]) == classId, let studentId = Int64(parts[1]) else { continue }
            result[studentId] = untilDate
        }
        if changed { save(all) }
        return result
    }

    static func markSeen(classId: Int64, studentId: Int64, now: Date = Date()) {
        var all = load()
        let until = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        all[entryKey(classId: classId, studentId: studentId)] = until.timeIntervalSince1970
        save(all)
    }

    static func unmark(classId: Int64, studentId: Int64) {
        var all = load()
        all[entryKey(classId: classId, studentId: studentId)] = nil
        save(all)
    }
}

enum UnseenText {
    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static let iso: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func shortDate(_ date: Date) -> String { dayMonth.string(from: date) }

    static func isoDay(_ date: Date) -> String { iso.string(from: date) }

    static func date(fromIso value: String) -> Date? { value.isEmpty ? nil : iso.date(from: value) }

    /// Nombre del tipo de registro (por su `name` de Kotlin).
    static func kindTitle(_ kindName: String?) -> String {
        switch kindName {
        case "GRADE": return "Nota"
        case "CELL_ENTRY": return "Comentario o sello"
        case "RUBRIC": return "Rúbrica"
        case "PHYSICAL_TEST": return "Prueba física"
        case "OBSERVATION": return "Observación"
        case "INCIDENT": return "Incidencia"
        case "ATTENDANCE_NOTE": return "Nota de asistencia"
        case "TERM_NOTE": return "Tu valoración"
        case "JOURNAL_NOTE": return "Nota del diario"
        case "FAMILY_MEETING": return "Reunión con la familia"
        default: return "Registro"
        }
    }

    /// «Nota en Hockey, 10 nov» / «Incidencia: Sin material, 3 nov».
    static func lastDescription(kindName: String?, label: String, dateIso: String) -> String {
        guard kindName != nil else { return "Sin registros desde que empezó el curso" }
        var text = kindTitle(kindName)
        if !label.isEmpty {
            text += kindName == "INCIDENT" ? ": \(label)" : " en \(label)"
        }
        if let date = date(fromIso: dateIso) { text += ", \(shortDate(date))" }
        return text
    }
}

extension KmpBridge {
    // MARK: - Lista de un grupo

    /// Alumnado sin mirar del grupo (sin los «Vistos») y los «Vistos» vigentes.
    /// Se guarda en caché por grupo hasta que cambie el día o algo (`bump()`).
    /// `globalEvents`: eventos no lectivos generales ya leídos (para no pedirlos por grupo).
    func unseenStudents(
        classId: Int64,
        globalEvents: [CalendarEvent]? = nil
    ) async throws -> (unseen: [UnseenStudentRow], seen: [SeenStudentRow], total: Int) {
        let store = UnseenStudentsStore.shared
        let today = Calendar.current.startOfDay(for: Date())
        let version = store.version
        if let cached = store.cache[classId], cached.day == today, cached.version == version {
            return (cached.unseen, cached.seen, cached.total)
        }
        let seenMap = UnseenSeenStore.active(classId: classId)
        let nonTeaching = try await nonTeachingDaysIso(classId: classId, globalEvents: globalEvents)
        // El cálculo sin «Vistos» sirve para listar también los ocultos con su nombre.
        let report = try await container.unseenStudents.unseenForClass(
            classId: classId,
            nonTeachingDaysIso: nonTeaching,
            hiddenStudentIds: []
        )
        var unseen: [UnseenStudentRow] = []
        var seen: [SeenStudentRow] = []
        for student in report.unseen {
            if let until = seenMap[student.studentId] {
                seen.append(SeenStudentRow(studentId: student.studentId, name: student.name, until: until))
                continue
            }
            unseen.append(row(student, classId: classId))
        }
        let sortedSeen = seen.sorted { $0.until < $1.until }
        let total = Int(report.totalStudents)
        if store.version == version {
            store.cache[classId] = .init(day: today, version: version, unseen: unseen, seen: sortedSeen, total: total)
        }
        return (unseen, sortedSeen, total)
    }

    /// Último registro del alumno en el grupo (ficha y Alumnado).
    func lastContactLine(classId: Int64, studentId: Int64) async throws -> (text: String, isOverdue: Bool) {
        let nonTeaching = try await nonTeachingDaysIso(classId: classId)
        let summary = try await container.unseenStudents.lastContact(
            classId: classId, studentId: studentId, nonTeachingDaysIso: nonTeaching
        )
        let kind = summary.kind?.name
        // «nota en Hockey»: solo la primera letra en minúscula (el nombre de la columna se respeta).
        let full = UnseenText.lastDescription(kindName: kind, label: summary.label, dateIso: "")
        let detail = full.prefix(1).lowercased() + full.dropFirst()
        let text: String
        if summary.daysSince < 0 {
            text = "Ningún registro todavía"
        } else if summary.daysSince == 0 {
            text = "Último registro: hoy (\(detail))"
        } else if summary.isOverdue {
            text = "\(summary.daysSince) días sin registro (último: \(detail))"
        } else {
            text = "Último registro: hace \(summary.daysSince) días (\(detail))"
        }
        return (text, summary.isOverdue)
    }

    // MARK: - «Hoy» los viernes

    /// Los viernes calcula un resumen por grupo para «Hoy» › Atención; el resto de
    /// días lo vacía. Una vez al día (o tras `UnseenStudentsStore.bump()`).
    func refreshUnseenSummariesIfNeeded() async {
        let today = Calendar.current.startOfDay(for: Date())
        let store = UnseenStudentsStore.shared
        guard store.loadedDay != today, !store.isRefreshingSummaries else { return }
        guard Calendar.current.component(.weekday, from: today) == 6 else {
            store.clearSummaries(day: today)
            return
        }
        store.isRefreshingSummaries = true
        defer { store.isRefreshingSummaries = false }
        let version = store.version
        guard let globalEvents = try? await plannerNonTeachingCalendarEvents(classId: nil) else { return }
        var summaries: [UnseenGroupSummary] = []
        var anyFailed = false
        for schoolClass in classes {
            if Task.isCancelled { return }
            do {
                let result = try await unseenStudents(classId: schoolClass.id, globalEvents: globalEvents)
                guard !result.unseen.isEmpty else { continue }
                // Vista previa por días sin registro, no por medida: el orden no delata a nadie.
                let preview = result.unseen
                    .sorted { ($0.daysSinceLast ?? Int.max) > ($1.daysSinceLast ?? Int.max) }
                    .map(\.name)
                summaries.append(UnseenGroupSummary(
                    classId: schoolClass.id,
                    className: schoolClass.name,
                    count: result.unseen.count,
                    previewNames: preview
                ))
            } catch {
                anyFailed = true
            }
        }
        // Si un grupo falló se enseña lo que hay, pero no se da el día por cargado.
        store.publish(summaries, day: today, computedAt: version)
        if anyFailed { store.markNotLoaded() }
    }

    /// Lanza el resumen sin hacer esperar a «Hoy».
    func scheduleUnseenSummariesRefresh() {
        Task { @MainActor [weak self] in await self?.refreshUnseenSummariesIfNeeded() }
    }

    // MARK: - Acciones

    /// Observación rápida: misma vía que «Nueva observación» de «Hoy» (incidencia
    /// con título «Observación»), así cuenta como registro.
    func saveQuickObservation(classId: Int64, studentId: Int64, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await createIncident(classId: classId, studentId: studentId, title: "Observación", detail: trimmed)
        afterUnseenChange()
    }

    func markStudentSeen(classId: Int64, studentId: Int64) {
        UnseenSeenStore.markSeen(classId: classId, studentId: studentId)
        afterUnseenChange()
    }

    func unmarkStudentSeen(classId: Int64, studentId: Int64) {
        UnseenSeenStore.unmark(classId: classId, studentId: studentId)
        afterUnseenChange()
    }

    /// Recarga listas y fichas y, si es viernes, el resumen de «Hoy».
    private func afterUnseenChange() {
        UnseenStudentsStore.shared.bump()
        scheduleUnseenSummariesRefresh()
    }

    // MARK: - Ayudas

    private func row(_ student: UnseenStudent, classId: Int64) -> UnseenStudentRow {
        let kind = student.lastKind?.name
        return UnseenStudentRow(
            studentId: student.studentId,
            classId: classId,
            name: student.name,
            hasSupportMeasure: student.hasSupportMeasure,
            daysSinceLast: student.daysSinceLast < 0 ? nil : Int(student.daysSinceLast),
            lastDescription: UnseenText.lastDescription(kindName: kind, label: student.lastLabel, dateIso: student.lastDateIso)
        )
    }

    /// Días no lectivos (globales y del grupo) de los últimos 120 días, en ISO.
    private func nonTeachingDaysIso(classId: Int64, globalEvents: [CalendarEvent]? = nil) async throws -> [String] {
        let global: [CalendarEvent]
        if let globalEvents { global = globalEvents } else { global = try await plannerNonTeachingCalendarEvents(classId: nil) }
        let events = global + (try await plannerNonTeachingCalendarEvents(classId: classId))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliest = calendar.date(byAdding: .day, value: -120, to: today) ?? today
        var days = Set<String>()
        for event in events {
            var cursor = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(event.startAt.toEpochMilliseconds()) / 1000))
            let end = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(event.endAt.toEpochMilliseconds()) / 1000))
            if end < earliest { continue }
            if cursor < earliest { cursor = earliest }
            while cursor <= end && cursor <= today {
                days.insert(UnseenText.isoDay(cursor))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return days.sorted()
    }
}
