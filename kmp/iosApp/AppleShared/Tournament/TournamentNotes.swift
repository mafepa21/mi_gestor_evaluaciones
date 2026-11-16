import Foundation

/// Tipo de nota apuntada durante el torneo.
enum TournamentNoteKind: String, Codable, CaseIterable, Sendable {
    /// Dos equipos no se ponen de acuerdo con el resultado.
    case resultConflict
    /// Cualquier otra cosa de un partido.
    case match
    /// Algo de un alumno concreto (p. ej. juega muy bien y la rúbrica no lo recoge).
    case student

    var title: String {
        switch self {
        case .resultConflict: return "Conflicto por el resultado"
        case .match: return "Nota del partido"
        case .student: return "Nota del alumno"
        }
    }
}

/// Nota del docente durante el torneo. Viaja dentro del `config_json` del torneo (sin migración),
/// así que la sincronización la lleva con el resto del plan. Si además se copió a la ficha del
/// alumnado, `incidentIds` guarda las incidencias creadas.
struct TournamentNote: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var kind: TournamentNoteKind
    var text: String
    var createdAt: Date
    /// Ronda y pista del partido (notas de partido). `nil` en notas de alumno fuera de un partido.
    var roundNumber: Int?
    var venueNumber: Int?
    /// Nombres de los equipos implicados (como en el calendario).
    var teams: [String]
    /// Alumno de la nota (solo `.student`), como texto igual que `TournamentPlanTeam.studentIDs`.
    var studentID: String?
    var studentName: String?
    /// Incidencias creadas en la ficha del alumnado a partir de esta nota.
    var incidentIds: [Int64]

    init(
        id: UUID = UUID(),
        kind: TournamentNoteKind,
        text: String,
        createdAt: Date = Date(),
        roundNumber: Int? = nil,
        venueNumber: Int? = nil,
        teams: [String] = [],
        studentID: String? = nil,
        studentName: String? = nil,
        incidentIds: [Int64] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.roundNumber = roundNumber
        self.venueNumber = venueNumber
        self.teams = teams
        self.studentID = studentID
        self.studentName = studentName
        self.incidentIds = incidentIds
    }

    /// «Ronda 1 · Pista 2 · A contra B», con lo que se sepa.
    var contextLine: String {
        var parts: [String] = []
        if let roundNumber { parts.append("Ronda \(roundNumber)") }
        if let venueNumber { parts.append("Pista \(venueNumber)") }
        if !teams.isEmpty { parts.append(teams.joined(separator: " contra ")) }
        return parts.joined(separator: " · ")
    }

    /// Texto que se guarda en la ficha del alumno (detalle de la incidencia).
    var incidentDetail: String {
        let context = contextLine
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .student:
            return context.isEmpty ? body : "\(context): \(body)"
        case .resultConflict, .match:
            let head = context.isEmpty ? kind.title : "\(kind.title) (\(context))"
            return "\(head): \(body)"
        }
    }

    /// Gravedad de la incidencia: un conflicto pesa más que una observación.
    var incidentSeverity: String { kind == .resultConflict ? "medium" : "low" }
}

extension TournamentPlan {
    /// Notas del torneo, de la más antigua a la más reciente.
    var noteList: [TournamentNote] {
        (notes ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    mutating func addNote(_ note: TournamentNote) {
        var list = notes ?? []
        list.append(note)
        notes = list
    }

    mutating func setIncidentIds(_ ids: [Int64], forNote noteID: UUID) {
        guard var list = notes, let index = list.firstIndex(where: { $0.id == noteID }) else { return }
        list[index].incidentIds = ids
        notes = list
    }

    mutating func removeNote(id: UUID) {
        guard var list = notes else { return }
        list.removeAll { $0.id == id }
        notes = list.isEmpty ? nil : list
    }

    /// Notas de un partido concreto (misma ronda y pista).
    func notes(roundNumber: Int, venueNumber: Int) -> [TournamentNote] {
        noteList.filter { $0.roundNumber == roundNumber && $0.venueNumber == venueNumber && $0.kind != .student }
    }

    func hasResultConflict(roundNumber: Int, venueNumber: Int) -> Bool {
        notes(roundNumber: roundNumber, venueNumber: venueNumber).contains { $0.kind == .resultConflict }
    }

    /// Notas de un alumno en este torneo.
    func notes(studentID: String) -> [TournamentNote] {
        noteList.filter { $0.studentID == studentID }
    }

    /// Agrupadas por ronda (las que no tienen ronda, al final) para el apartado «Notas».
    var notesByRound: [(roundNumber: Int?, notes: [TournamentNote])] {
        let grouped = Dictionary(grouping: noteList, by: \.roundNumber)
        let numbered = grouped.keys.compactMap { $0 }.sorted().map { (roundNumber: Optional($0), notes: grouped[$0] ?? []) }
        let loose = grouped[nil].map { [(roundNumber: Int?.none, notes: $0)] } ?? []
        return numbered + loose
    }
}
