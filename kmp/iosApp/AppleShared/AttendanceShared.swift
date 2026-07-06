import SwiftUI
import MiGestorKit

// Modelo y lógica puros del módulo de Asistencia, compartidos entre
// MacAttendanceView (macOS) y AttendanceWorkspaceView (iOS/iPadOS) para que
// ambas plataformas no puedan volver a divergir en silencio — cada una pinta
// estos datos con sus propios componentes nativos (toolbar, listas, tarjetas),
// pero calculan exactamente lo mismo.

enum AttendanceBoardMode: String, CaseIterable, Identifiable {
    case day = "Día"
    case history = "Historial"
    case courses = "Cursos"

    var id: String { rawValue }
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
