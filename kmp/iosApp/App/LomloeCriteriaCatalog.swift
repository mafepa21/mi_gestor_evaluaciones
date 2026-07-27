import Foundation

/// Catálogo oficial de Criterios de Evaluación LOMLOE (Educación Física en Secundaria y Bachillerato)
/// para asociar el código (ej. "CE 2.1") con su descripción literal según la legislación educativa.
struct LomloeCriterionDefinition: Identifiable, Hashable, Codable {
    var id: String { code }
    let code: String
    let title: String
    let officialDescription: String
}

enum LomloeCriteriaCatalog {
    /// Lista completa de Criterios de Evaluación LOMLOE de Educación Física (Leyes Echeverría / Real Decreto 217/2022 y 243/2022).
    static let allCriteria: [LomloeCriterionDefinition] = [
        .init(
            code: "CE 1.1",
            title: "Estilo de vida activo y salud",
            officialDescription: "Analizar y valorar los factores que intervienen en la práctica de la actividad física y su impacto sobre la salud integral, adoptando un estilo de vida activo y saludable."
        ),
        .init(
            code: "CE 1.2",
            title: "Planificación del entrenamiento personal",
            officialDescription: "Planificar, desarrollar y evaluar un programa de actividad física orientado al mantenimiento o mejora de las capacidades físicas y la salud, adaptado a las necesidades individuales."
        ),
        .init(
            code: "CE 1.3",
            title: "Prevención de lesiones y primeros auxilios",
            officialDescription: "Aplicar pautas de prevención de lesiones, ergonomía postural y medidas básicas de primeros auxilios ante situaciones de emergencia en la práctica deportiva o cotidiana."
        ),
        .init(
            code: "CE 1.4",
            title: "Hábitos saludables y autorregulación",
            officialDescription: "Reflexionar sobre las conductas de riesgo asociadas a la salud y consolidar hábitos posturales, alimentarios y de descanso que potencien el bienestar propio y colectivo."
        ),
        .init(
            code: "CE 2.1",
            title: "Toma de decisiones, técnica y táctica motriz",
            officialDescription: "Desarrollar proyectos motores o situaciones de juego aplicando principios de técnica, táctica y toma de decisiones adecuadas al contexto y a los requerimientos de la tarea."
        ),
        .init(
            code: "CE 2.2",
            title: "Ejecución y autorregulación de acciones motrices",
            officialDescription: "Diseñar, ejecutar y autorregular producciones motrices individuales, de oposición o colectivas, adaptando la ejecución a los condicionantes cambiantes de la actividad."
        ),
        .init(
            code: "CE 2.3",
            title: "Análisis y retroalimentación motriz",
            officialDescription: "Analizar y evaluar la propia ejecución motriz y la del alumnado participante, utilizando indicadores de calidad y ofreciendo retroalimentación constructiva."
        ),
        .init(
            code: "CE 3.1",
            title: "Gestión emocional y resiliencia",
            officialDescription: "Identificar, gestionar y autorregular las emociones, pensamientos y comportamientos ante el éxito, el fracaso o la dificultad en situaciones motrices, favoreciendo la resiliencia."
        ),
        .init(
            code: "CE 3.2",
            title: "Juego limpio y resolución pacífica de conflictos",
            officialDescription: "Mostrar y promover actitudes de juego limpio, respeto a las reglas, deportividad, cooperación y resolución pacífica de conflictos en entornos motrices y deportivos."
        ),
        .init(
            code: "CE 4.1",
            title: "Actividad física sostenible en el entorno",
            officialDescription: "Practicar y promover actividades físicas y recreativas en el medio natural y urbano de forma responsable, respetuosa y sostenible con el medio ambiente."
        ),
        .init(
            code: "CE 4.2",
            title: "Organización de actividades en la naturaleza",
            officialDescription: "Organizar, planificar y participar activamente en desplazamientos o actividades en la naturaleza con criterios de seguridad, autonomía y minimización del impacto ambiental."
        ),
        .init(
            code: "CE 5.1",
            title: "Inclusión, perspectiva de género y diversidad",
            officialDescription: "Promover la inclusión activa, la perspectiva de género y la aceptación de la diversidad en las actividades motrices y colectivas, rechazando cualquier discriminación."
        ),
        .init(
            code: "CE 5.2",
            title: "Análisis crítico del fenómeno deportivo",
            officialDescription: "Analizar críticamente las manifestaciones socioculturales del deporte (medios de comunicación, igualdad, profesionalización y consumo) y su impacto en la sociedad actual."
        ),
        .init(
            code: "CE 6.1",
            title: "Expresión corporal y creación artística",
            officialDescription: "Proponer, diseñar y llevar a cabo composiciones y producciones con intencionalidad artística o expresiva a través del cuerpo, la música y el movimiento."
        ),
        .init(
            code: "CE 6.2",
            title: "Patrimonio cultural motriz y juegos tradicionales",
            officialDescription: "Valorar, transmitir y practicar juegos tradicionales, deportes populares y manifestaciones motrices pertenecientes al patrimonio cultural propio y de otros entornos."
        )
    ]

    private static let criteriaByCode: [String: LomloeCriterionDefinition] = {
        var dict: [String: LomloeCriterionDefinition] = [:]
        for item in allCriteria {
            dict[item.code.uppercased()] = item
            // Soporte para variantes de formateo (ej. "CE2.1", "CE 2.1")
            let collapsedCode = item.code.replacingOccurrences(of: " ", with: "").uppercased()
            dict[collapsedCode] = item
        }
        return dict
    }()

    /// Busca la definición oficial de un criterio por su código (ej. "CE 2.1" o "CE2.1").
    static func lookup(code: String) -> LomloeCriterionDefinition? {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let exact = criteriaByCode[cleaned] { return exact }
        let collapsed = cleaned.replacingOccurrences(of: " ", with: "")
        return criteriaByCode[collapsed]
    }

    /// Extrae todos los códigos de un string arbitrario (ej. "CE 2.1 · CE 3.2" o "Rúbrica - CE 2.1 - 50%")
    /// y devuelve la lista de definiciones oficiales encontradas. Si un código no está en el catálogo oficial,
    /// genera una definición fallback conservando el código.
    static func resolveCriteria(from text: String?) -> [LomloeCriterionDefinition] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let pattern = #"(?:CE|Criterio|Criteri)\s*(\d+(?:\.\d+)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var foundCodes: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: text) {
                let codeNum = String(text[range])
                let fullCode = "CE \(codeNum)"
                if !foundCodes.contains(fullCode) {
                    foundCodes.append(fullCode)
                }
            }
        }

        // Si no se encontraron con regex de prefijo "CE", probar por división si es un label guardado tipo "CE 2.1 · CE 3.2"
        if foundCodes.isEmpty {
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "·,;/"))
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.uppercased().hasPrefix("CE") {
                    foundCodes.append(trimmed)
                }
            }
        }

        // Si sigue sin encontrarse un código explícito "CE X.X", realizar coincidencia semántica por palabras clave de EF
        if foundCodes.isEmpty {
            let lower = text.lowercased()
            if lower.contains("sostenib") || lower.contains("medio natural") || (lower.contains("organización") && lower.contains("torneo")) {
                foundCodes.append("CE 4.2")
            }
            if lower.contains("justicia social") || lower.contains("inclusión") || lower.contains("género") || lower.contains("diversidad") {
                if !foundCodes.contains("CE 5.1") { foundCodes.append("CE 5.1") }
            }
            if lower.contains("técnico") || lower.contains("táctica") || lower.contains("torneo") || lower.contains("fútbol") || lower.contains("baloncesto") || lower.contains("frisbee") {
                if !foundCodes.contains("CE 2.1") { foundCodes.append("CE 2.1") }
            }
            if lower.contains("fair play") || lower.contains("roles") || lower.contains("deportividad") || lower.contains("juego limpio") {
                if !foundCodes.contains("CE 3.2") { foundCodes.append("CE 3.2") }
            }
            if lower.contains("expresión") || lower.contains("danza") || lower.contains("acrosport") || lower.contains("artístic") {
                if !foundCodes.contains("CE 6.1") { foundCodes.append("CE 6.1") }
            }
            if lower.contains("salud") || lower.contains("calentamiento") || lower.contains("condición física") {
                if !foundCodes.contains("CE 1.1") { foundCodes.append("CE 1.1") }
            }
        }

        return foundCodes.map { rawCode -> LomloeCriterionDefinition in
            let normalizedCode = rawCode.replacingOccurrences(of: "CE", with: "CE ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if let official = lookup(code: normalizedCode) {
                return official
            }
            return LomloeCriterionDefinition(
                code: normalizedCode.uppercased(),
                title: "Criterio de Evaluación \(normalizedCode)",
                officialDescription: "Criterio de evaluación específico definido en el currículo de la Situación de Aprendizaje."
            )
        }
    }
}
