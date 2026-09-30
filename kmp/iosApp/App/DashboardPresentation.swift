import SwiftUI
import MiGestorKit

// MARK: - Modelo de presentación del Dashboard
//
// Todo lo que las vistas necesitan sale de aquí, calculado UNA vez por
// snapshot (ver `DashboardPresentationCache`) y no en cada `body`. Las vistas
// de las tres franjas (AHORA, ATENCIÓN, CONTEXTO) y el modo Clase solo pintan.

/// Elemento del que el inspector enseña detalle.
enum DashboardInspectorSelection: Hashable {
    case session(Int64)
    case alert(String)
    case pe(String)
    /// Fila de Atención sin alerta detrás (asistencia de hoy sin pasar, solo Mac).
    case attendance(classId: Int64)
}

// MARK: - Atención

/// Urgencia de una fila: rojo = riesgo, naranja = alerta, azul = pendiente.
/// El orden de los casos es el orden de la lista.
enum DashboardAttentionKind: Int, CaseIterable, Identifiable, Hashable {
    case risk
    case alert
    case pending

    var id: Int { rawValue }

    var filterTitle: String {
        switch self {
        case .risk: return "Riesgo"
        case .alert: return "Alertas"
        case .pending: return "Pendientes"
        }
    }

    var accessibilityName: String {
        switch self {
        case .risk: return "Riesgo"
        case .alert: return "Alerta"
        case .pending: return "Pendiente"
        }
    }

    var systemImage: String {
        switch self {
        case .risk: return "chart.line.downtrend.xyaxis"
        case .alert: return "exclamationmark.triangle"
        case .pending: return "clock"
        }
    }

    var tint: Color {
        switch self {
        case .risk: return DashboardStyle.Tint.risk
        case .alert: return DashboardStyle.Tint.alert
        case .pending: return DashboardStyle.Tint.pending
        }
    }
}

enum DashboardAttentionRoute {
    case module(AppWorkspaceModule, classId: Int64?, studentId: Int64?)
    /// Sin destino propio: la acción abre el detalle en el inspector.
    case inspector
}

struct DashboardAttentionAction {
    let title: String
    let route: DashboardAttentionRoute
}

struct DashboardAttentionItem: Identifiable {
    /// Estable entre repintados: sale del id del origen, nunca de `UUID()`.
    let id: String
    let kind: DashboardAttentionKind
    let title: String
    let detail: String
    let classId: Int64?
    let studentId: Int64?
    let inspector: DashboardInspectorSelection
    let action: DashboardAttentionAction

    var accessibilitySummary: String {
        detail.isEmpty
            ? "\(kind.accessibilityName): \(title)"
            : "\(kind.accessibilityName): \(title). \(detail)"
    }
}

/// Lo que la franja Atención pinta para un filtro concreto.
struct DashboardAttentionSlice {
    let rows: [DashboardAttentionItem]
    /// Filas que cumplen el filtro (antes de recortar a 5).
    let filteredCount: Int
}

// MARK: - Agenda, grupos, EF

struct DashboardAgendaRow: Identifiable {
    let id: Int64
    let timeLabel: String
    let title: String
    let detail: String
    let isCurrent: Bool
}

struct DashboardPERow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let severity: String
}

// MARK: - Ahora

/// Reloj de una franja "HH:mm" -> "HH:mm". Puro: la vista le pasa la fecha
/// (`TimelineView`) y no hay temporizador escondido.
struct DashboardSessionClock: Equatable {
    let startMinutes: Int
    let endMinutes: Int

    init?(start: String?, end: String?) {
        guard let start, let end,
              let s = Self.minutes(from: start),
              let e = Self.minutes(from: end),
              e > s else { return nil }
        startMinutes = s
        endMinutes = e
    }

    struct State: Equatable {
        let remaining: Int
        let elapsed: Int
        let total: Int
        let minutesToStart: Int
        let progress: Double
        var hasStarted: Bool { minutesToStart == 0 }
    }

    func state(at date: Date, calendar: Calendar = .current) -> State {
        let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let total = endMinutes - startMinutes
        let elapsed = min(max(now - startMinutes, 0), total)
        return State(
            remaining: max(endMinutes - now, 0),
            elapsed: elapsed,
            total: total,
            minutesToStart: max(startMinutes - now, 0),
            progress: Double(elapsed) / Double(total)
        )
    }

    private static func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return h * 60 + m
    }
}

struct DashboardNowModel {
    enum Phase {
        /// Clase en curso.
        case live
        /// Hay una próxima clase (hoy u otro día).
        case upcoming(today: Bool)
        /// Sin horario o fuera de curso: no hay grupo al que apuntar.
        case none(noSchedule: Bool)
    }

    let phase: Phase
    let title: String
    let subtitle: String
    let timeRange: String?
    let dayLabel: String?
    let clock: DashboardSessionClock?
    let classId: Int64?
    let primary: DashboardNowAction
    let primaryTitle: String
    /// Grupos del menú "Más": cada grupo se separa con un divisor.
    let menuGroups: [[DashboardNowAction]]
    /// Sin sesión planificada en la franja en curso: el menú ofrece crearla.
    let offersCreateSession: Bool
    let hasSessionJournal: Bool

    var isLive: Bool { if case .live = phase { return true } else { return false } }
}

/// Qué se enseña en AHORA cuando no hay clase a la que apuntar.
struct DashboardNowEmpty {
    let title: String
    let detail: String
    let buttonTitle: String
}

// MARK: - Modo Clase

struct DashboardClassroomFacts {
    let attendanceValue: String
    let attendanceDetail: String
    let pendingCount: Int
    let pendingDetail: String
    let alertStudentsCount: Int
    let alertDetail: String
}

// MARK: - Sincronización

enum DashboardSyncPill: Equatable {
    case synced
    case syncing
    case pending(Int)
    case offline
    case notPaired

    var title: String {
        switch self {
        case .synced: return "Sincronizado"
        case .syncing: return "Sincronizando…"
        case .pending(let n): return n == 1 ? "1 cambio pendiente" : "\(n) cambios pendientes"
        case .offline: return "Sin conexión"
        case .notPaired: return "Sin sincronizar"
        }
    }

    var tint: Color {
        switch self {
        case .synced: return DashboardStyle.Tint.success
        case .syncing: return DashboardStyle.accent
        case .pending, .offline, .notPaired: return DashboardStyle.Tint.alert
        }
    }

    static func make(message: String, pendingChanges: Int, pairedHost: String?) -> DashboardSyncPill {
        let lower = message.lowercased()
        if lower.hasPrefix("sincronizando") { return .syncing }
        if lower.contains("fallido") || lower.hasPrefix("error") || lower.contains("sin conexión") {
            return .offline
        }
        if pairedHost == nil { return .notPaired }
        if pendingChanges > 0 { return .pending(pendingChanges) }
        return .synced
    }
}

// MARK: - Modelo completo

struct DashboardPresentation {
    let queue: [DashboardAttentionItem]
    let now: DashboardNowModel?
    let nowEmpty: DashboardNowEmpty
    let agenda: [DashboardAgendaRow]
    let groups: [DashboardGroupRow]
    let peRows: [DashboardPERow]
    let hasSessionsToday: Bool
    let generatedAt: Date

    /// Total sin filtrar: el ÚNICO contador de atención de la pantalla.
    var totalAttention: Int { queue.count }

    /// Filtrado en local sobre el snapshot, sin volver a llamar a KMP.
    func attention(hidden: Set<DashboardAttentionKind>, showAll: Bool, limit: Int = 5) -> DashboardAttentionSlice {
        let filtered = hidden.isEmpty ? queue : queue.filter { !hidden.contains($0.kind) }
        return DashboardAttentionSlice(
            rows: showAll ? filtered : Array(filtered.prefix(limit)),
            filteredCount: filtered.count
        )
    }

    /// `extraItems`: filas de Atención que no salen del snapshot (p. ej. la
    /// asistencia de hoy pendiente en Mac). Entran con la prioridad más alta de
    /// su urgencia.
    static func make(snapshot: DashboardSnapshot, extraItems: [DashboardAttentionItem] = []) -> DashboardPresentation {
        let queue = buildQueue(snapshot: snapshot, extraItems: extraItems)
        return DashboardPresentation(
            queue: queue,
            now: buildNow(snapshot: snapshot),
            nowEmpty: buildNowEmpty(snapshot: snapshot),
            agenda: buildAgenda(snapshot: snapshot),
            groups: snapshot.groupSummaries.map {
                DashboardGroupRow(
                    id: $0.classId,
                    groupName: $0.groupName,
                    attendancePct: Int($0.attendancePct),
                    evaluationCompletedPct: Int($0.evaluationCompletedPct),
                    averageScore: $0.averageScore,
                    studentsInFollowUp: Int($0.studentsInFollowUp)
                )
            },
            peRows: snapshot.peItems.map {
                DashboardPERow(id: $0.id, title: $0.title, detail: $0.detail, severity: $0.severity)
            },
            hasSessionsToday: !snapshot.todaySessions.isEmpty,
            generatedAt: Date()
        )
    }

    // MARK: Cola de atención

    /// Destino de la acción de cada tipo de fila:
    /// - alerta/pendiente con rúbrica pendiente -> "Evaluar": Rúbricas (clase y alumno).
    /// - alerta con alumno -> "Ver ficha": Alumnado; con solo clase -> "Abrir cuaderno".
    /// - EF `prueba_rubrica_activa` -> "Revisar": Rúbricas EF (o Rúbricas general sin perfil EF).
    /// - EF `incidencias_fisicas` -> Incidencias EF; `exentos_adaptacion` -> Alumnado;
    ///   `material_hoy` -> Material EF (sin perfil EF: Alumnado / Planner).
    /// - Sin destino conocido -> "Ver detalle": abre el inspector. Ninguna acción es un no-op.
    ///
    /// Unifica alertas de riesgo, pendientes y Educación Física en una sola
    /// lista ordenada por urgencia (riesgo, alerta, pendiente) y, dentro de
    /// cada una, por prioridad. Los "recordatorios" de la agenda se omiten a
    /// propósito: el backend los genera 1:1 desde cada alerta y contarlos
    /// duplicaría la fila.
    private static func buildQueue(snapshot: DashboardSnapshot, extraItems: [DashboardAttentionItem] = []) -> [DashboardAttentionItem] {
        var entries: [(item: DashboardAttentionItem, priority: Int, order: Int)] = []
        var order = 0
        for extra in extraItems {
            entries.append((extra, 4, -1))
        }

        for alert in snapshot.alerts {
            let kind: DashboardAttentionKind = isPending(alert)
                ? .pending
                : (alert.severity.lowercased() == "high" ? .risk : .alert)
            let studentId = alert.studentId?.int64Value
            let classId = alert.classId?.int64Value
            let targets = agendaNavigationTargets(for: alert, snapshot: snapshot)
            let action: DashboardAttentionAction
            if let target = targets.first {
                action = DashboardAttentionAction(
                    title: "Evaluar",
                    route: .module(.rubrics, classId: target.classId?.int64Value, studentId: target.studentId?.int64Value)
                )
            } else if let studentId {
                action = DashboardAttentionAction(
                    title: "Ver ficha",
                    route: .module(.students, classId: classId, studentId: studentId)
                )
            } else if let classId {
                action = DashboardAttentionAction(
                    title: "Abrir cuaderno",
                    route: .module(.notebook, classId: classId, studentId: nil)
                )
            } else {
                action = DashboardAttentionAction(title: "Ver detalle", route: .inspector)
            }
            entries.append((
                DashboardAttentionItem(
                    id: "alert-\(alert.id)",
                    kind: kind,
                    title: alert.count > 1 ? "\(alert.count) · \(alert.title)" : alert.title,
                    detail: alert.detail,
                    classId: classId,
                    studentId: studentId,
                    inspector: .alert(alert.id),
                    action: action
                ),
                priorityRank(alert.priority),
                order
            ))
            order += 1
        }

        for item in snapshot.peItems {
            let kind: DashboardAttentionKind = item.severity.lowercased() == "high" ? .risk : .alert
            let classId = item.classId?.int64Value
            let action: DashboardAttentionAction
            if let destination = peDestination(for: item) {
                action = DashboardAttentionAction(
                    title: "Revisar",
                    route: .module(destination, classId: classId, studentId: nil)
                )
            } else {
                action = DashboardAttentionAction(title: "Ver detalle", route: .inspector)
            }
            entries.append((
                DashboardAttentionItem(
                    id: "pe-\(item.id)",
                    kind: kind,
                    title: item.title,
                    detail: item.detail,
                    classId: classId,
                    studentId: nil,
                    inspector: .pe(item.id),
                    action: action
                ),
                priorityRank(item.severity),
                order
            ))
            order += 1
        }

        return entries
            .sorted {
                if $0.item.kind != $1.item.kind { return $0.item.kind.rawValue < $1.item.kind.rawValue }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.order < $1.order
            }
            .map(\.item)
    }

    private static func priorityRank(_ raw: String) -> Int {
        switch raw.lowercased() {
        case "critical", "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return 0
        }
    }

    static func isPending(_ alert: AlertItem) -> Bool {
        let haystack = "\(alert.type) \(alert.title) \(alert.detail)".lowercased()
        return haystack.contains("pending")
            || haystack.contains("pendiente")
            || haystack.contains("sin nota")
            || haystack.contains("sin cerrar")
            || haystack.contains("informe")
            || haystack.contains("missing")
    }

    // MARK: Ahora

    private static func buildNow(snapshot: DashboardSnapshot) -> DashboardNowModel? {
        guard let context = snapshot.currentContext, !dashboardContextHasNoClass(context.status) else {
            return nil
        }
        let isLive = context.status == .active
        let title = context.className.isEmpty ? (isLive ? "Clase actual" : "Próxima clase") : context.className
        let subtitleParts = [context.subjectLabel, context.unitLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let range: String? = {
            guard let start = context.startTime, let end = context.endTime else { return nil }
            return "\(start) a \(end)"
        }()
        let subtitle = (subtitleParts + [range].compactMap { $0 }).joined(separator: " · ")
        return DashboardNowModel(
            phase: isLive ? .live : .upcoming(today: context.status == .nextToday),
            title: title,
            subtitle: subtitle,
            timeRange: range,
            dayLabel: context.status == .nextOtherDay
                ? dashboardContextDayLabel(context.dayOfWeek?.intValue)
                : nil,
            clock: DashboardSessionClock(start: context.startTime, end: context.endTime),
            classId: context.classId?.int64Value,
            primary: isLive ? .passList : .openNotebook,
            primaryTitle: isLive ? "Pasar lista" : "Preparar cuaderno",
            menuGroups: isLive
                ? [[.observation, .quickEvaluation], [.evaluate, .openNotebook]]
                : [[.openPlanner]],
            offersCreateSession: isLive && !context.isFromPlannedSession,
            hasSessionJournal: isLive && context.sessionId != nil
        )
    }

    private static func buildNowEmpty(snapshot: DashboardSnapshot) -> DashboardNowEmpty {
        if snapshot.currentContext?.status == .outsideSchoolYear {
            return DashboardNowEmpty(
                title: "Hoy queda fuera del curso",
                detail: "El resto del Dashboard sigue disponible: el trabajo pendiente no desaparece.",
                buttonTitle: "Editar agenda docente"
            )
        }
        if snapshot.todaySessions.isEmpty {
            return DashboardNowEmpty(
                title: "Hoy no tienes sesiones",
                detail: "Disfruta del día o prepara la semana.",
                buttonTitle: "Ver horario"
            )
        }
        return DashboardNowEmpty(
            title: "Todavía no hay horario docente",
            detail: "Crea tus franjas para que el Dashboard sepa qué clase tienes en cada momento.",
            buttonTitle: "Configurar horario"
        )
    }

    // MARK: Agenda

    private static func buildAgenda(snapshot: DashboardSnapshot) -> [DashboardAgendaRow] {
        let context = snapshot.currentContext
        let liveClassId = context?.status == .active ? context?.classId?.int64Value : nil
        let liveStart = context?.startTime
        return snapshot.todaySessions.map { session in
            let isCurrent: Bool = {
                guard let liveClassId, session.classId?.int64Value == liveClassId else { return false }
                guard let liveStart else { return true }
                return session.timeLabel.hasPrefix(liveStart)
            }()
            return DashboardAgendaRow(
                id: session.id,
                timeLabel: session.timeLabel,
                title: session.groupName,
                detail: session.didacticUnit,
                isCurrent: isCurrent
            )
        }
    }

    // MARK: Modo Clase

    /// Las tres fichas del modo Clase. `snapshot` ya llega acotado al grupo en
    /// curso cuando se pidió en modo Clase; aun así se filtra por `classId`
    /// para no mezclar grupos durante un cambio de modo.
    static func classroomFacts(
        snapshot: DashboardSnapshot,
        studentNames: [Int64: String] = [:]
    ) -> DashboardClassroomFacts {
        let context = snapshot.currentContext
        let classId = context?.classId?.int64Value
        let queue = buildQueue(snapshot: snapshot).filter { item in
            guard let classId else { return true }
            return item.classId == classId
        }

        let attendanceValue: String
        let attendanceDetail: String
        if let classId, let summary = snapshot.groupSummaries.first(where: { $0.classId == classId }) {
            attendanceValue = "\(Int(summary.attendancePct)) %"
            attendanceDetail = "Media del grupo"
        } else {
            attendanceValue = "Sin datos"
            attendanceDetail = "Sin registro del grupo"
        }

        let pending = queue.filter { $0.kind == .pending }
        let flagged = queue.filter { $0.kind != .pending }
        let studentIds = flagged.compactMap(\.studentId)
        var seenStudents = Set<Int64>()
        let distinctStudents = studentIds.filter { seenStudents.insert($0).inserted }
        let alertCount = distinctStudents.isEmpty ? flagged.count : distinctStudents.count

        let names = distinctStudents.compactMap { studentNames[$0] }
        let alertDetail: String
        if names.isEmpty {
            alertDetail = alertCount == 0 ? "Sin alertas" : "En riesgo o con alerta"
        } else if names.count > 2 {
            alertDetail = "\(names.prefix(2).joined(separator: ", ")) y \(names.count - 2) más"
        } else {
            alertDetail = names.joined(separator: ", ")
        }

        return DashboardClassroomFacts(
            attendanceValue: attendanceValue,
            attendanceDetail: attendanceDetail,
            pendingCount: pending.count,
            pendingDetail: pending.first?.title ?? "Todo al día",
            alertStudentsCount: alertCount,
            alertDetail: alertDetail
        )
    }
}

/// Guarda el modelo del último snapshot. Es una clase (no `@Published`) para
/// poder consultarla desde `body` sin provocar otro repintado.
final class DashboardPresentationCache {
    private var key: String?
    private var cached: DashboardPresentation?

    func model(for snapshot: DashboardSnapshot, extraItems: [DashboardAttentionItem] = []) -> DashboardPresentation {
        let id = "\(ObjectIdentifier(snapshot).hashValue)|" + extraItems.map(\.id).joined(separator: ",")
        if key == id, let cached { return cached }
        let model = DashboardPresentation.make(snapshot: snapshot, extraItems: extraItems)
        key = id
        cached = model
        return model
    }
}

/// Reduce el texto del briefing (IA o radar) a una sola frase corta.
enum DashboardBriefing {
    static func oneSentence(_ text: String?, maxLength: Int = 160) -> String? {
        guard var value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let newline = value.firstIndex(of: "\n") {
            value = String(value[..<newline])
        }
        if let stop = value.range(of: ". ") {
            value = String(value[..<stop.lowerBound]) + "."
        }
        if value.count > maxLength {
            value = String(value.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return value
    }
}
