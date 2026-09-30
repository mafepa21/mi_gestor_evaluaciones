import SwiftUI
import MiGestorKit

// MARK: - Capa de bloques compartida entre el Dashboard de iPad (DashboardView)
// y el de macOS (MacDashboardView).
//
// Antes de esto, macOS no tenía Resumen por grupo, Agenda docente, Educación
// Física ni Auditoría LOMLOE — esos bloques solo existían en iPad, duplicados
// a mano cada vez que se querían llevar a macOS. Este archivo los saca de
// DashboardView a funciones libres para que ambas plataformas rendericen
// exactamente la misma vista sobre el mismo `DashboardSnapshot` del backend,
// cada una con su propia forma de navegar (onOpenModule) y su propio
// `colorScheme`.
//
// El "Ahora" de macOS (franja horaria activa/próxima) y el System/Sistema de
// cada plataforma se quedan fuera a propósito: dependen de datos que no
// tienen equivalente en el otro lado (horario fijo del profesor en macOS,
// almacén de backups en macOS) y forzar una única vista ahí habría sido
// una regresión, no una unificación.

struct DashboardGroupRow: Identifiable {
    let id: Int64
    let groupName: String
    let attendancePct: Int
    let evaluationCompletedPct: Int
    let averageScore: Double
    let studentsInFollowUp: Int
}

// MARK: - Modo operativo (Clase / Despacho)

/// Lo que el usuario elige. `auto` es el valor por defecto: el modo se deduce
/// del horario, así que al entrar en el aula el dashboard ya está en Clase sin
/// tocar nada. Las otras dos opciones son una anulación manual.
enum DashboardModePreference: String, CaseIterable, Identifiable {
    case auto
    case classroom
    case office

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .classroom: return "Clase"
        case .office: return "Despacho"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .classroom: return "figure.run"
        case .office: return "tray.full"
        }
    }

    /// Con `auto`, hay clase en curso -> Clase; cualquier otra cosa ->
    /// Despacho. Si el horario no da contexto, se cae a Despacho en vez de
    /// dejar una pantalla vacía.
    func resolved(for context: DashboardSessionContext?) -> DashboardMode {
        switch self {
        case .classroom: return .classroom
        case .office: return .office
        case .auto:
            guard let context else { return .office }
            return context.status == .active ? .classroom : .office
        }
    }

    /// Etiqueta que explica qué ha decidido el automático, para que el usuario
    /// no tenga que adivinar por qué ve una cosa u otra.
    func resolvedHint(for context: DashboardSessionContext?) -> String? {
        guard self == .auto else { return nil }
        return resolved(for: context) == .classroom ? "Auto · Clase en curso" : "Auto · Despacho"
    }
}

// MARK: - Contexto "Ahora"

func dashboardContextStatusLabel(_ status: DashboardSessionContextStatus) -> String {
    switch status {
    case .active: return "En curso"
    case .nextToday: return "Hoy"
    case .nextOtherDay: return "Próxima"
    case .noSchedule: return "Sin horario"
    case .outsideSchoolYear: return "Fuera de curso"
    default: return "Sin horario"
    }
}

func dashboardContextStatusTint(_ status: DashboardSessionContextStatus) -> Color {
    switch status {
    case .active: return EvaluationDesign.success
    case .nextToday, .nextOtherDay: return EvaluationDesign.accent
    default: return IOSAppStyle.warning
    }
}

func dashboardContextDayLabel(_ day: Int?) -> String {
    switch day {
    case 1: return "Lunes"
    case 2: return "Martes"
    case 3: return "Miércoles"
    case 4: return "Jueves"
    case 5: return "Viernes"
    case 6: return "Sábado"
    case 7: return "Domingo"
    default: return "Día"
    }
}

// MARK: - Helpers de alerta/severidad compartidos

func dashboardFilterLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case "high": return "Alta"
    case "medium": return "Media"
    case "low": return "Baja"
    default: return raw.isEmpty ? "Sin clasificar" : raw
    }
}

func riskTint(_ raw: String) -> Color {
    switch raw.lowercased() {
    case "high": return .red
    case "medium": return .orange
    default: return .yellow
    }
}

/// Empareja una alerta con el `AgendaItem` ("recordatorio") que el backend
/// genera a partir de ella para transportar sus `navigationTargets` (rúbrica
/// + alumno pendientes de evaluar). El backend no enlaza ambos por id, así
/// que el emparejamiento se hace por contenido (mismo grupo, título y
/// detalle), suficiente porque el `AgendaItem` "recordatorio" siempre se
/// construye 1:1 desde la alerta.
func agendaNavigationTargets(for alert: AlertItem, snapshot: DashboardSnapshot) -> [AgendaNavigationTarget] {
    snapshot.agendaItems.first {
        $0.type == "recordatorio"
            && $0.title == alert.title
            && $0.subtitle == alert.detail
            && $0.classId?.int64Value == alert.classId?.int64Value
    }?.navigationTargets ?? []
}

/// Los `PEOperationalItem` del backend nunca llevan `classId` (se agregan a
/// nivel de todas las clases de EF), así que la navegación solo puede llevar
/// al módulo relevante, no a un grupo o alumno concretos.
func peDestination(for item: PEOperationalItem) -> AppWorkspaceModule? {
    switch item.type {
    case "incidencias_fisicas":
        return .peIncidents
    case "exentos_adaptacion":
        return .students
    case "prueba_rubrica_activa":
        return .peRubrics
    case "material_hoy":
        return .peMaterial
    default:
        return nil
    }
}

func trendBgColor(_ direction: String) -> Color {
    switch direction {
    case "UPWARD": return .green
    case "DOWNWARD": return .red
    case "STABLE": return .blue
    default: return .gray
    }
}

// MARK: - Tarjeta "Ahora"

/// Acciones que ofrece la tarjeta "Ahora". Se declaran aquí, sin destinos de
/// plataforma, para que iPad y Mac ofrezcan las mismas y cada uno las resuelva
/// con su propia navegación.
enum DashboardNowAction: String, Identifiable {
    case passList
    case openNotebook
    case evaluate
    case observation
    case quickEvaluation
    case openPlanner
    case openJournal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passList: return "Pasar lista"
        case .openNotebook: return "Abrir cuaderno"
        case .evaluate: return "Evaluar"
        case .observation: return "Nueva observación"
        case .quickEvaluation: return "Evaluación rápida"
        case .openPlanner: return "Abrir Planner"
        case .openJournal: return "Diario"
        }
    }

    var systemImage: String {
        switch self {
        case .passList: return "checkmark.circle"
        case .openNotebook: return "tablecells"
        case .evaluate: return "checklist.checked"
        case .observation: return "note.text.badge.plus"
        case .quickEvaluation: return "sparkles"
        case .openPlanner: return "calendar"
        case .openJournal: return "doc.text"
        }
    }
}

/// Estados en los que el horario no señala ninguna clase concreta.
func dashboardContextHasNoClass(_ status: DashboardSessionContextStatus) -> Bool {
    switch status {
    case .active, .nextToday, .nextOtherDay: return false
    default: return true
    }
}
