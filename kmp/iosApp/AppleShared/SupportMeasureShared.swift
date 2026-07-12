import Foundation

// Modelo y lógica puros de las medidas de respuesta educativa Nivel III/IV
// (Decreto 104/2018 + Orden 20/2019, Comunidad Valenciana), compartidos entre
// la ficha de alumno de iOS/iPadOS y la de macOS. El docente de aula registra
// y consulta aquí; nunca redacta el informe sociopsicopedagógico ni el PAP en
// sí — solo referencia el documento oficial y sus propias observaciones.

enum SupportMeasureLevelUI: String, CaseIterable, Identifiable {
    case iii = "III"
    case iv = "IV"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iii: return "Nivel III"
        case .iv: return "Nivel IV"
        }
    }

    var shortLabel: String { rawValue }
}

enum SupportMeasureTypeUI: String, CaseIterable, Identifiable {
    case refuerzo = "REFUERZO"
    case enriquecimiento = "ENRIQUECIMIENTO"
    case adaptacionAcceso = "ADAPTACION_ACCESO"
    case apoyoPt = "APOYO_PT"
    case apoyoAl = "APOYO_AL"
    case acis = "ACIS"
    case exencion = "EXENCION"
    case flexibilizacion = "FLEXIBILIZACION"
    case permanenciaExtraordinaria = "PERMANENCIA_EXTRAORDINARIA"
    case escolarizacionEspecifica = "ESCOLARIZACION_ESPECIFICA"

    var id: String { rawValue }

    /// Nivel al que pertenece típicamente esta medida (Orden 20/2019).
    var level: SupportMeasureLevelUI {
        switch self {
        case .refuerzo, .enriquecimiento, .adaptacionAcceso, .apoyoPt, .apoyoAl:
            return .iii
        case .acis, .exencion, .flexibilizacion, .permanenciaExtraordinaria, .escolarizacionEspecifica:
            return .iv
        }
    }

    var displayName: String {
        switch self {
        case .refuerzo: return "Refuerzo"
        case .enriquecimiento: return "Enriquecimiento"
        case .adaptacionAcceso: return "Adaptación de acceso"
        case .apoyoPt: return "Apoyo PT"
        case .apoyoAl: return "Apoyo AL"
        case .acis: return "ACIS"
        case .exencion: return "Exención"
        case .flexibilizacion: return "Flexibilización"
        case .permanenciaExtraordinaria: return "Permanencia extraordinaria"
        case .escolarizacionEspecifica: return "Escolarización específica"
        }
    }

    static func types(for level: SupportMeasureLevelUI) -> [SupportMeasureTypeUI] {
        allCases.filter { $0.level == level }
    }
}

enum SupportMeasureIntensityUI: String, CaseIterable, Identifiable {
    case baja = "BAJA"
    case media = "MEDIA"
    case alta = "ALTA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baja: return "Baja"
        case .media: return "Media"
        case .alta: return "Alta"
        }
    }
}

struct SupportMeasureRow: Identifiable {
    let id: Int64
    let studentId: Int64
    let level: SupportMeasureLevelUI
    let measureType: SupportMeasureTypeUI
    let startDateIso: String
    let endDateIso: String?
    let responsible: String?
    let intensity: SupportMeasureIntensityUI?
    let followUpNotes: String
    let documentRef: String?
    let reviewDueIso: String?
    let isActive: Bool

    /// Revisión anual vencida o próxima (30 días), lógica determinista sin IA.
    var reviewStatus: SupportMeasureReviewStatus {
        guard isActive, let reviewDueIso, let dueDate = AppDateTimeSupport.isoDateFormatter.date(from: reviewDueIso) else {
            return .none
        }
        let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        if daysUntilDue < 0 { return .overdue }
        if daysUntilDue <= 30 { return .dueSoon }
        return .none
    }
}

enum SupportMeasureReviewStatus {
    case none
    case dueSoon
    case overdue
}

struct SupportMeasureDraft {
    var studentId: Int64
    var level: SupportMeasureLevelUI
    var measureType: SupportMeasureTypeUI
    var startDateIso: String
    var responsible: String = ""
    var intensity: SupportMeasureIntensityUI?
    var followUpNotes: String = ""
    var documentRef: String = ""
    var reviewDueIso: String?
}
