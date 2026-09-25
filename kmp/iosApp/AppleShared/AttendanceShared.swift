import SwiftUI
import MiGestorKit

// Modelo y lógica puros del módulo de Asistencia, compartidos entre
// MacAttendanceView (macOS) y AttendanceWorkspaceView (iOS/iPadOS) para que
// ambas plataformas no puedan volver a divergir en silencio — cada una pinta
// estos datos con sus propios componentes nativos (toolbar, listas, tarjetas),
// pero calculan exactamente lo mismo.

enum AttendanceBoardMode: String, CaseIterable, Identifiable {
    case day = "Día"
    case matrix = "Matriz"
    case history = "Historial"
    case courses = "Cursos"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .day: return "person.crop.circle.badge.checkmark"
        case .matrix: return "tablecells"
        case .history: return "clock.arrow.circlepath"
        case .courses: return "square.grid.2x2"
        }
    }
}

enum AttendanceMatrixRange: String, CaseIterable, Identifiable {
    case month = "Mes actual"
    case quarter1 = "1er Trimestre"
    case quarter2 = "2º Trimestre"
    case quarter3 = "3er Trimestre"
    case fullYear = "Todo el curso"

    var id: String { rawValue }

    func dateRange(relativeTo date: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let schoolStartYear = month >= 8 ? year : year - 1

        switch self {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? date
            return (calendar.startOfDay(for: start), calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end)

        case .quarter1:
            var startComp = DateComponents(year: schoolStartYear, month: 9, day: 1)
            var endComp = DateComponents(year: schoolStartYear, month: 12, day: 22, hour: 23, minute: 59, second: 59)
            return (calendar.date(from: startComp) ?? date, calendar.date(from: endComp) ?? date)

        case .quarter2:
            var startComp = DateComponents(year: schoolStartYear + 1, month: 1, day: 7)
            var endComp = DateComponents(year: schoolStartYear + 1, month: 3, day: 31, hour: 23, minute: 59, second: 59)
            return (calendar.date(from: startComp) ?? date, calendar.date(from: endComp) ?? date)

        case .quarter3:
            var startComp = DateComponents(year: schoolStartYear + 1, month: 4, day: 1)
            var endComp = DateComponents(year: schoolStartYear + 1, month: 6, day: 30, hour: 23, minute: 59, second: 59)
            return (calendar.date(from: startComp) ?? date, calendar.date(from: endComp) ?? date)

        case .fullYear:
            var startComp = DateComponents(year: schoolStartYear, month: 9, day: 1)
            var endComp = DateComponents(year: schoolStartYear + 1, month: 6, day: 30, hour: 23, minute: 59, second: 59)
            return (calendar.date(from: startComp) ?? date, calendar.date(from: endComp) ?? date)
        }
    }
}

struct AttendanceMatrixStudentStats: Identifiable {
    let student: Student
    var id: Int64 { student.id }
    let presentCount: Int
    let absentCount: Int
    let lateCount: Int
    let justifiedCount: Int
    let noMaterialCount: Int
    let exemptCount: Int
    let totalSessions: Int

    var attendanceRate: Int {
        guard totalSessions > 0 else { return 100 }
        let attended = presentCount + lateCount + exemptCount
        return min(100, max(0, Int(round(Double(attended) / Double(totalSessions) * 100.0))))
    }

    var attendanceRateColor: Color {
        if attendanceRate >= 90 { return AppleDesignSystem.success }
        if attendanceRate >= 80 { return AppleDesignSystem.warning }
        return AppleDesignSystem.danger
    }
}

extension Student {
    var initials: String {
        let first = firstName.prefix(1)
        let last = lastName.prefix(1)
        let combined = "\(first)\(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "—" : combined.uppercased()
    }

    static func mock(
        id: Int64,
        firstName: String,
        lastName: String,
        isInjured: Bool = false
    ) -> Student {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
        return Student(
            id: id,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            isInjured: isInjured,
            sex: .unspecified,
            sexSource: .unknown,
            birthDate: nil,
            trace: trace
        )
    }
}

struct AttendanceStatusOption: Identifiable, Hashable {
    let id: String
    let label: String
    let shortLabel: String
    let color: Color

    static let all: [AttendanceStatusOption] = [
        .init(id: "PRESENTE", label: "Presente", shortLabel: "P", color: AppleDesignSystem.success),
        .init(id: "AUSENTE", label: "Ausente", shortLabel: "A", color: AppleDesignSystem.danger),
        .init(id: "TARDE", label: "Retraso", shortLabel: "R", color: AppleDesignSystem.warning),
        .init(id: "JUSTIFICADO", label: "Justificada", shortLabel: "J", color: .gray),
        .init(id: "SIN_MATERIAL", label: "Sin material", shortLabel: "M", color: .brown),
        .init(id: "EXENTO", label: "Exento", shortLabel: "E", color: .indigo)
    ]

    static func option(for status: String?) -> AttendanceStatusOption? {
        all.first { $0.id == status }
    }

    // Valor centralizado del filtro "sin filtrar" para que iOS y macOS no puedan
    // divergir usando literales "TODOS" distintos por accidente.
    static let allFilterId = "TODOS"
}

struct AttendanceEntryRow: Identifiable {
    let id: Int64
    let student: Student
    let isInjured: Bool
    let record: KmpBridge.AttendanceRecordSnapshot?
}

struct AttendanceAlert: Identifiable {
    let id: String
    let student: Student
    let message: String
    let systemImage: String
    let tint: Color
}

struct AttendanceHistorySelection: Identifiable {
    let studentId: Int64
    let date: Date
    let record: KmpBridge.AttendanceRecordSnapshot?

    var id: String {
        "\(studentId)|\(Int(date.stripTime.timeIntervalSince1970))"
    }
}

enum AttendanceLogic {
    static func isPresentStatus(_ status: String?) -> Bool {
        status?.uppercased().contains("PRESENT") == true
    }

    static func isAbsentStatus(_ status: String?) -> Bool {
        status?.uppercased().contains("AUS") == true
    }

    static func isLateStatus(_ status: String?) -> Bool {
        guard let status = status?.uppercased() else { return false }
        return status.contains("TARD") || status.contains("RETR")
    }

    /// Una fila "no resuelta" es la que necesita atención: lesión, sin
    /// registro, con incidencia o sin marcar como presente. Ambas plataformas
    /// usan esto para mostrar las excepciones antes que la lista de presentes.
    static func isRowUnresolved(_ row: AttendanceEntryRow) -> Bool {
        row.isInjured
            || row.record == nil
            || row.record?.hasIncident == true
            || !isPresentStatus(row.record?.status)
    }

    /// Orden de urgencia dentro del grupo de excepciones: ausencias primero,
    /// luego retrasos, luego lesión/incidencia, luego sin registro.
    static func exceptionPriority(_ row: AttendanceEntryRow) -> Int {
        if isAbsentStatus(row.record?.status) { return 0 }
        if isLateStatus(row.record?.status) { return 1 }
        if row.isInjured || row.record?.hasIncident == true { return 2 }
        if row.record == nil { return 4 }
        return 3
    }

    static func sessionLabel(for entry: KmpBridge.AttendanceSessionSnapshot) -> String {
        let unit = entry.session.teachingUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = unit.isEmpty ? "Sesión" : unit
        return "Periodo \(entry.session.period) · \(title)"
    }
}
