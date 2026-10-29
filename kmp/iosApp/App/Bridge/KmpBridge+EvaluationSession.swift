//
//  KmpBridge+EvaluationSession.swift
//  MiGestorKMP
//
//  Puente de la junta de evaluación (migración 47). Las reglas (total de
//  suspensas, resumen, congelado al cerrar) viven en KMP: EvaluationSessionUseCase.
//  Aquí solo se traduce a Swift y se ofrecen las mismas cuentas en local para
//  que la pantalla se recalcule al instante mientras el docente escribe.
//
//  Ojo con los nombres: `EvaluationKind` de Kotlin se escribe siempre como
//  MiGestorKit.EvaluationKind para no confundirlo con tipos Swift del proyecto.
//

import Foundation
import MiGestorKit

// MARK: - Tipos de interfaz

enum EvaluationKindUI: String, CaseIterable, Identifiable, Hashable {
    case initial = "INITIAL"
    case first = "FIRST"
    case second = "SECOND"
    case third = "THIRD"
    case final = "FINAL"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .initial: return "Evaluación inicial"
        case .first: return "1ª evaluación"
        case .second: return "2ª evaluación"
        case .third: return "3ª evaluación"
        case .final: return "Evaluación final"
        }
    }

    var shortTitle: String {
        switch self {
        case .initial: return "Inicial"
        case .first: return "1ª"
        case .second: return "2ª"
        case .third: return "3ª"
        case .final: return "Final"
        }
    }

    /// Valor Kotlin por nombre: no depende de cómo Swift renombre `FINAL`.
    var kotlin: MiGestorKit.EvaluationKind {
        MiGestorKit.EvaluationKind.entries.first { $0.name == rawValue } ?? .first
    }
}

struct JuntaSessionUI: Identifiable, Hashable {
    let id: String
    let classId: Int64
    let kind: EvaluationKindUI
    var label: String
    var dateIso: String
    var attendees: String
    var generalAgreements: String
    let isClosed: Bool
    let closedAtEpochMs: Int64?
    let plannerEvaluationPeriodId: Int64?
}

struct JuntaStudentRowUI: Identifiable, Hashable {
    let studentId: Int64
    let firstName: String
    let lastName: String
    let average: Double?
    let absencePercent: Double?
    let absenceCount: Int?
    let supportLevel: SupportMeasureLevelUI?
    let incidentCount: Int?
    var otherFailedCount: Int
    var agreement: String
    var isReviewed: Bool
    let isFrozen: Bool

    var id: Int64 { studentId }

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    /// Misma regla que el Cuaderno: Media menor que 5 sin redondear.
    var ownFailed: Bool? { average.map { $0 < JuntaRules.passThreshold } }

    var totalFailed: Int { otherFailedCount + (ownFailed == true ? 1 : 0) }

    // Claves de orden para las columnas de la tabla (valores comparables).
    var sortName: String { "\(lastName) \(firstName)".lowercased() }
    var sortAverage: Double { average ?? -1 }
    var sortAbsence: Double { absencePercent ?? -1 }
}

struct JuntaSummaryUI: Hashable {
    var studentCount: Int
    var passAllCount: Int
    var oneOrTwoFailedCount: Int
    var threeOrMoreFailedCount: Int
    var passedOwnSubjectCount: Int
    var reviewedCount: Int

    var pendingReviewCount: Int { studentCount - reviewedCount }
}

struct JuntaBoardUI: Hashable {
    var session: JuntaSessionUI
    var students: [JuntaStudentRowUI]
    var summary: JuntaSummaryUI
}

enum JuntaFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case failing = "Con suspensas"
    case unreviewed = "Sin revisar"

    var id: String { rawValue }

    func matches(_ row: JuntaStudentRowUI) -> Bool {
        switch self {
        case .all: return true
        case .failing: return row.totalFailed > 0
        case .unreviewed: return !row.isReviewed
        }
    }
}

// MARK: - Reglas locales (réplica de EvaluationSessionRules para recalcular al momento)

enum JuntaRules {
    static let passThreshold = 5.0
    static let maxOtherFailed = 15

    static func summary(of rows: [JuntaStudentRowUI]) -> JuntaSummaryUI {
        JuntaSummaryUI(
            studentCount: rows.count,
            passAllCount: rows.filter { $0.totalFailed == 0 }.count,
            oneOrTwoFailedCount: rows.filter { (1...2).contains($0.totalFailed) }.count,
            threeOrMoreFailedCount: rows.filter { $0.totalFailed >= 3 }.count,
            passedOwnSubjectCount: rows.filter { $0.ownFailed == false }.count,
            reviewedCount: rows.filter(\.isReviewed).count
        )
    }

    /// Alumno que sigue al indicado en la lista visible. `nil` si es el último.
    static func nextStudentId(after id: Int64?, in rows: [JuntaStudentRowUI]) -> Int64? {
        guard let id, let index = rows.firstIndex(where: { $0.studentId == id }) else { return rows.first?.studentId }
        let next = index + 1
        return next < rows.count ? rows[next].studentId : nil
    }
}

// MARK: - Formato

enum JuntaFormat {
    private static let oneDecimal = decimalFormatter(digits: 1)
    private static let twoDecimals = decimalFormatter(digits: 2)

    private static func decimalFormatter(digits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = false
        return formatter
    }

    /// Media sin color. Entre 4,95 y 5 (sin llegar) se enseñan dos decimales,
    /// truncados, para que un 4,96 nunca se lea «5,0» siendo suspensa.
    static func average(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value >= 4.95, value < JuntaRules.passThreshold {
            let truncated = (value * 100 + 1e-9).rounded(.down) / 100
            return twoDecimals.string(from: NSNumber(value: min(truncated, 4.99))) ?? "4,99"
        }
        return oneDecimal.string(from: NSNumber(value: value)) ?? "–"
    }

    static func absence(_ percent: Double?) -> String {
        guard let percent else { return "–" }
        return "\(Int(percent.rounded())) %"
    }

    static func suspensas(_ count: Int) -> String {
        count == 1 ? "1 suspensa" : "\(count) suspensas"
    }

    static func parseDate(_ iso: String) -> Date? {
        isoFormatter.date(from: iso)
    }

    static func isoDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// «15 de diciembre de 2026»
    static func longDate(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter.string(from: date)
    }

    /// «15 de diciembre»
    static func dayMonth(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: date)
    }

    static func closedOn(_ epochMs: Int64?) -> String {
        guard let epochMs else { return "" }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: date)
    }

    /// «5 de 8 aprueban todo»
    static func headline(_ summary: JuntaSummaryUI) -> String {
        guard summary.studentCount > 0 else { return "Sin alumnado" }
        let verb = summary.passAllCount == 1 ? "aprueba todo" : "aprueban todo"
        return "\(summary.passAllCount) de \(summary.studentCount) \(verb)"
    }

    static func ownSubjectLine(_ summary: JuntaSummaryUI) -> String {
        "En mi materia aprueban \(summary.passedOwnSubjectCount) de \(summary.studentCount)."
    }

    /// Resumen leído de una vez por VoiceOver.
    static func summarySpeech(_ summary: JuntaSummaryUI) -> String {
        let one = summary.oneOrTwoFailedCount == 1 ? "1 con una o dos suspensas" : "\(summary.oneOrTwoFailedCount) con una o dos suspensas"
        let three = summary.threeOrMoreFailedCount == 1 ? "1 con tres o más" : "\(summary.threeOrMoreFailedCount) con tres o más"
        return "\(headline(summary)). \(one). \(three)."
    }

    /// «Luis Gil, media 4,2, faltas 12 %, medida nivel III, 3 suspensas en total, sin revisar»
    static func rowSpeech(_ row: JuntaStudentRowUI) -> String {
        var parts = [row.fullName]
        parts.append("media \(average(row.average))")
        parts.append("faltas \(absence(row.absencePercent))")
        if let level = row.supportLevel { parts.append("medida \(level.displayName.lowercased())") }
        parts.append("\(suspensas(row.totalFailed)) en total")
        parts.append(row.isReviewed ? "revisado" : "sin revisar")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Funciones

@MainActor
extension KmpBridge {

    func evaluationSessionList(classId: Int64, gate: InclusionLoadGate? = nil) async throws -> [JuntaSessionUI]? {
        let ticket = gate?.begin(classId: classId)
        let sessions = try await container.evaluationSessions.listSessions(classId: classId)
        if let gate, let ticket, !gate.isCurrent(ticket) { return nil }
        return sessions.compactMap(juntaSession(from:))
    }

    /// Crea la junta con sus asistentes en una sola operación de KMP.
    func createEvaluationSession(
        classId: Int64,
        kind: EvaluationKindUI,
        date: Date,
        attendees: String
    ) async throws -> JuntaSessionUI? {
        let created = try await container.evaluationSessions.createSession(
            classId: classId,
            kind: kind.kotlin,
            dateIso: JuntaFormat.isoDate(date),
            label: nil,
            attendees: attendees,
            plannerEvaluationPeriodId: nil,
            nowEpochMs: juntaNowMs()
        )
        return juntaSession(from: created)
    }

    /// Si `gate` llega y el grupo cambió mientras cargaba, devuelve `nil`.
    func loadEvaluationBoard(sessionId: String, classId: Int64, gate: InclusionLoadGate? = nil) async throws -> JuntaBoardUI? {
        let ticket = gate?.begin(classId: classId)
        let board = try await container.evaluationSessions.loadBoard(sessionId: sessionId, nowEpochMs: juntaNowMs())
        if let gate, let ticket, !gate.isCurrent(ticket) { return nil }
        return juntaBoard(from: board)
    }

    func saveEvaluationHeader(_ session: JuntaSessionUI) async throws {
        try await container.evaluationSessions.updateHeader(
            sessionId: session.id,
            label: session.label,
            dateIso: session.dateIso,
            attendees: session.attendees,
            generalAgreements: session.generalAgreements,
            plannerEvaluationPeriodId: session.plannerEvaluationPeriodId.map { KotlinLong(value: $0) },
            nowEpochMs: juntaNowMs()
        )
    }

    func saveEvaluationStudent(sessionId: String, row: JuntaStudentRowUI) async throws {
        try await container.evaluationSessions.updateStudent(
            sessionId: sessionId,
            studentId: row.studentId,
            otherFailedCount: Int32(row.otherFailedCount),
            agreement: row.agreement,
            isReviewed: row.isReviewed,
            nowEpochMs: juntaNowMs()
        )
    }

    func closeEvaluationSession(id: String) async throws -> JuntaBoardUI {
        juntaBoard(from: try await container.evaluationSessions.closeSession(sessionId: id, nowEpochMs: juntaNowMs()))!
    }

    func reopenEvaluationSession(id: String) async throws -> JuntaBoardUI {
        juntaBoard(from: try await container.evaluationSessions.reopenSession(sessionId: id, nowEpochMs: juntaNowMs()))!
    }

    func deleteEvaluationSession(id: String) async throws {
        try await container.evaluationSessions.deleteSession(sessionId: id)
    }

    // MARK: Conversión

    private func juntaSession(from session: MiGestorKit.EvaluationSession) -> JuntaSessionUI? {
        guard let kind = EvaluationKindUI(rawValue: session.kind.name) else { return nil }
        return JuntaSessionUI(
            id: session.id,
            classId: session.classId,
            kind: kind,
            label: session.label,
            dateIso: session.dateIso,
            attendees: session.attendees,
            generalAgreements: session.generalAgreements,
            isClosed: session.isClosed,
            closedAtEpochMs: session.closedAtEpochMs?.int64Value,
            plannerEvaluationPeriodId: session.plannerEvaluationPeriodId?.int64Value
        )
    }

    private func juntaBoard(from board: MiGestorKit.EvaluationSessionBoard) -> JuntaBoardUI? {
        guard let session = juntaSession(from: board.session) else { return nil }
        let rows = board.students.map { row in
            JuntaStudentRowUI(
                studentId: row.studentId,
                firstName: row.firstName,
                lastName: row.lastName,
                average: row.average?.doubleValue,
                absencePercent: row.absencePercent?.doubleValue,
                absenceCount: row.absenceCount.map { Int($0.int32Value) },
                supportLevel: row.supportLevel.flatMap { SupportMeasureLevelUI(rawValue: $0.name) },
                incidentCount: row.incidentCount.map { Int($0.int32Value) },
                otherFailedCount: Int(row.otherFailedCount),
                agreement: row.agreement,
                isReviewed: row.isReviewed,
                isFrozen: row.isFrozen
            )
        }
        .sorted { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
        return JuntaBoardUI(session: session, students: rows, summary: JuntaRules.summary(of: rows))
    }

    private func juntaNowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
