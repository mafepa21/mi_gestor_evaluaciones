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

/// Grupo del catálogo docente de medidas Nivel III (documento propio de codificación ITACA).
/// No aplica a Nivel IV, que usa su propia lista cerrada de la Orden 20/2019.
enum SupportMeasureCatalogGroup: String, CaseIterable, Identifiable {
    case aprendizaje = "Aprendizaje"
    case participacion = "Participación"
    case acceso = "Acceso"
    case flexibilizacion = "Flexibilización"

    var id: String { rawValue }
}

enum SupportMeasureTypeUI: String, CaseIterable, Identifiable {
    // Nivel IV: apoyos especializados extraordinarios (Orden 20/2019).
    case acis = "ACIS"
    case exencion = "EXENCION"
    case flexibilizacion = "FLEXIBILIZACION"
    case permanenciaExtraordinaria = "PERMANENCIA_EXTRAORDINARIA"
    case escolarizacionEspecifica = "ESCOLARIZACION_ESPECIFICA"

    // Nivel III - Aprendizaje.
    case aprFormatoExamen = "APR_FORMATO_EXAMEN"
    case aprRevisionExamen = "APR_REVISION_EXAMEN"
    case aprOrtografiaCV = "APR_ORTOGRAFIA_CV"
    case aprReducirCopiaEnunciados = "APR_REDUCIR_COPIA_ENUNCIADOS"
    case aprLibretaCompartida = "APR_LIBRETA_COMPARTIDA"
    case aprLibretaExclusiva = "APR_LIBRETA_EXCLUSIVA"
    case aprFotocopiasUnaCara = "APR_FOTOCOPIAS_UNA_CARA"
    case aprSupervisionAgenda = "APR_SUPERVISION_AGENDA"
    case aprUbicacionAula = "APR_UBICACION_AULA"
    case aprCuadernosCaligrafia = "APR_CUADERNOS_CALIGRAFIA"
    case aprActividadesTic = "APR_ACTIVIDADES_TIC"

    // Nivel III - Participación.
    case partSupervisionExposicion = "PART_SUPERVISION_EXPOSICION"
    case partAvisoLecturaVozAlta = "PART_AVISO_LECTURA_VOZ_ALTA"
    case partTutoriasPersonalizadas = "PART_TUTORIAS_PERSONALIZADAS"

    // Nivel III - Flexibilización.
    case flexPlanRepeticion = "FLEX_PLAN_REPETICION"

    // Nivel III - Acceso.
    case accDesplazamientoAutonomo = "ACC_DESPLAZAMIENTO_AUTONOMO"
    case accBanoAyudaFamilia = "ACC_BANO_AYUDA_FAMILIA"
    case accMesaAdaptada = "ACC_MESA_ADAPTADA"

    var id: String { rawValue }

    /// Nivel al que pertenece esta medida.
    var level: SupportMeasureLevelUI {
        switch self {
        case .acis, .exencion, .flexibilizacion, .permanenciaExtraordinaria, .escolarizacionEspecifica:
            return .iv
        default:
            return .iii
        }
    }

    /// Grupo del catálogo Nivel III. `nil` para las medidas de Nivel IV.
    var catalogGroup: SupportMeasureCatalogGroup? {
        switch self {
        case .aprFormatoExamen, .aprRevisionExamen, .aprOrtografiaCV, .aprReducirCopiaEnunciados,
             .aprLibretaCompartida, .aprLibretaExclusiva, .aprFotocopiasUnaCara, .aprSupervisionAgenda,
             .aprUbicacionAula, .aprCuadernosCaligrafia, .aprActividadesTic:
            return .aprendizaje
        case .partSupervisionExposicion, .partAvisoLecturaVozAlta, .partTutoriasPersonalizadas:
            return .participacion
        case .flexPlanRepeticion:
            return .flexibilizacion
        case .accDesplazamientoAutonomo, .accBanoAyudaFamilia, .accMesaAdaptada:
            return .acceso
        default:
            return nil
        }
    }

    /// Etiqueta corta para listas y badges.
    var displayName: String {
        switch self {
        case .acis: return "ACIS"
        case .exencion: return "Exención"
        case .flexibilizacion: return "Flexibilización"
        case .permanenciaExtraordinaria: return "Permanencia extraordinaria"
        case .escolarizacionEspecifica: return "Escolarización específica"
        case .aprFormatoExamen: return "Tipo/tamaño letra y menos preguntas"
        case .aprRevisionExamen: return "Revisión del examen antes de entregar"
        case .aprOrtografiaCV: return "Adaptar corrección ortográfica (Cast./Val.)"
        case .aprReducirCopiaEnunciados: return "Reducir copia de enunciados"
        case .aprLibretaCompartida: return "Libreta compartida entre materias"
        case .aprLibretaExclusiva: return "Libreta exclusiva por materia"
        case .aprFotocopiasUnaCara: return "Fotocopias a una cara"
        case .aprSupervisionAgenda: return "Supervisión de la agenda"
        case .aprUbicacionAula: return "Ubicación en primeras filas"
        case .aprCuadernosCaligrafia: return "Cuadernos de caligrafía"
        case .aprActividadesTic: return "Actividades TIC complementarias"
        case .partSupervisionExposicion: return "Supervisión previa de trabajo expuesto"
        case .partAvisoLecturaVozAlta: return "Aviso previo para leer en voz alta"
        case .partTutoriasPersonalizadas: return "Tutorías personalizadas"
        case .flexPlanRepeticion: return "Plan específico de permanencia"
        case .accDesplazamientoAutonomo: return "Desplazamiento autónomo (ascensor/rampa)"
        case .accBanoAyudaFamilia: return "Acceso al baño con ayuda de la familia"
        case .accMesaAdaptada: return "Mesa adecuada en altura y movilidad"
        }
    }

    /// Texto completo de la medida, para detalle/ayuda (documento propio de codificación).
    var fullDescription: String {
        switch self {
        case .acis: return "Adaptación Curricular Individual Significativa."
        case .exencion: return "Exención de materia o parte del currículo."
        case .flexibilizacion: return "Flexibilización de la escolarización."
        case .permanenciaExtraordinaria: return "Prórroga de permanencia extraordinaria en la etapa."
        case .escolarizacionEspecifica: return "Determinación de modalidad de escolarización específica."
        case .aprFormatoExamen: return "Tipo y tamaño letra adecuado en exámenes y documentos. Enunciados cortos en exámenes, y preguntas separadas (pocas por hoja)."
        case .aprRevisionExamen: return "Revisión del examen antes de la entrega para verificar preguntas no respondidas."
        case .aprOrtografiaCV: return "Modificación de criterios de corrección y calificación para faltas de ortografía en Castellano y Valenciano."
        case .aprReducirCopiaEnunciados: return "Reducir la copia de enunciados de ejercicios."
        case .aprLibretaCompartida: return "Trabajo en una libreta (que puede ser compartida con otras asignaturas)."
        case .aprLibretaExclusiva: return "Trabajo en una libreta independiente para cada asignatura."
        case .aprFotocopiasUnaCara: return "Entrega de materiales fotocopiados a una cara para que se peguen en las hojas de la libreta."
        case .aprSupervisionAgenda: return "Supervisión de la agenda. Tareas pendientes y exámenes."
        case .aprUbicacionAula: return "Ubicación en las primeras filas del aula, si es posible, para permitir contacto directo con el docente."
        case .aprCuadernosCaligrafia: return "Realización de cuadernos de caligrafía para conseguir una grafía legible."
        case .aprActividadesTic: return "Propuesta de actividades TIC que complementan lo trabajado en clase."
        case .partSupervisionExposicion: return "Supervisión previa del trabajo que vaya a ser expuesto en público (revisión de faltas de ortografía)."
        case .partAvisoLecturaVozAlta: return "Si tiene que leer en voz alta, se le avisará con antelación para que se lo prepare."
        case .partTutoriasPersonalizadas: return "Tutorías personalizadas."
        case .flexPlanRepeticion: return "Permanencia un año más en el mismo curso."
        case .accDesplazamientoAutonomo: return "Facilitar el desplazamiento autónomo (ascensor y rampa)."
        case .accBanoAyudaFamilia: return "Facilitar el acceso al baño con ayuda de la familia."
        case .accMesaAdaptada: return "Mesa adecuada en altura y movilidad."
        }
    }

    /// Código de referencia ITACA del documento de codificación propio.
    var itacaCode: String {
        switch self {
        case .acis, .exencion, .flexibilizacion, .permanenciaExtraordinaria, .escolarizacionEspecifica:
            return ""
        case .aprFormatoExamen, .aprRevisionExamen, .aprOrtografiaCV: return "1.5 Pruebas e instrumentos de evaluación"
        case .aprReducirCopiaEnunciados: return "1.3 Actividades"
        case .aprLibretaCompartida, .aprLibretaExclusiva, .aprFotocopiasUnaCara, .aprSupervisionAgenda: return "1.4 Materiales didácticos"
        case .aprUbicacionAula, .aprCuadernosCaligrafia, .aprActividadesTic: return "2.10 Otros"
        case .partSupervisionExposicion, .partAvisoLecturaVozAlta: return "11. Otros"
        case .partTutoriasPersonalizadas: return "1. Tutorías personalizadas"
        case .flexPlanRepeticion: return "Permanencia un año más en el mismo curso"
        case .accDesplazamientoAutonomo: return "1.1.1 Medidas desplazamiento autónomo"
        case .accBanoAyudaFamilia: return "1.1.3 Adecuación de baños"
        case .accMesaAdaptada: return "1.1.4 Adecuación del mobiliario"
        }
    }

    static func types(for level: SupportMeasureLevelUI) -> [SupportMeasureTypeUI] {
        allCases.filter { $0.level == level }
    }

    /// Medidas Nivel III agrupadas por categoría, en el orden del catálogo docente.
    static func catalog(for group: SupportMeasureCatalogGroup) -> [SupportMeasureTypeUI] {
        allCases.filter { $0.catalogGroup == group }
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
