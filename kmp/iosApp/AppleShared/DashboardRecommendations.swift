import Foundation

/// Traduce una alerta de riesgo del dashboard en una recomendación accionable —el
/// "qué hacer"— derivada de su tipo. No hay esquema nuevo: se calcula en la capa
/// de presentación a partir de la clave estable `AlertItem.type` (con respaldo por
/// palabras clave del título/detalle, como hace `riskIcon`).
enum DashboardRecommendations {

    /// Recomendación para una alerta, o `nil` si no hay una acción clara que sugerir.
    static func action(type: String, title: String = "", detail: String = "") -> String? {
        switch type {
        case "faltas_acumuladas":
            return "Contacta con la familia y acuerda un seguimiento de asistencia."
        case "incidencias_recientes":
            return "Revisa en Asistencia cuándo se concentran las incidencias y habla con el alumnado implicado."
        case "incidencias_fisicas":
            return "Registra el parte, avisa a la familia si procede y revisa la seguridad de la actividad."
        case "familias_sin_comunicar":
            return "Registra una tutoría con la familia esta semana."
        case "sin_evaluar":
            return "Programa una evaluación breve para tener evidencia del alumnado aún sin calificar."
        case "instrumentos_pendientes":
            return "Completa los instrumentos pendientes antes del siguiente corte de evaluación."
        case "prueba_rubrica_activa":
            return "Cierra la rúbrica o prueba que sigue abierta en el grupo."
        case "exentos_adaptacion":
            return "Comprueba que las adaptaciones estén registradas como medidas de apoyo."
        default:
            return fallbackAction(haystack: "\(type) \(title) \(detail)".lowercased())
        }
    }

    private static func fallbackAction(haystack: String) -> String? {
        if haystack.contains("asistencia") || haystack.contains("falta") || haystack.contains("attendance") {
            return "Revisa la asistencia del alumno y contacta con la familia si el patrón se mantiene."
        }
        if haystack.contains("lesion") || haystack.contains("lesión") || haystack.contains("injur") {
            return "Confirma el estado del alumno lesionado y ajusta la actividad prevista."
        }
        if haystack.contains("evalua") || haystack.contains("nota") || haystack.contains("rendi") {
            return "Revisa las evidencias recientes y acuerda una intervención breve con el alumno."
        }
        if haystack.contains("familia") || haystack.contains("tutor") {
            return "Registra una tutoría con la familia y deja constancia del acuerdo."
        }
        return "Revisa las evidencias recientes y acuerda una intervención breve."
    }
}
