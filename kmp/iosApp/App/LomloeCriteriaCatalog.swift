import Foundation

struct LomloeCriterionDefinition: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let title: String
    let officialDescription: String
    let valencianDescription: String?

    init(code: String, title: String, officialDescription: String, valencianDescription: String? = nil) {
        self.code = code
        self.title = title
        self.officialDescription = officialDescription
        self.valencianDescription = valencianDescription
    }
}

/// Catálogo oficial de Criterios de Evaluación LOMLOE de Educación Física (1º Bachillerato/ESO),
/// extraído de la legislación educativa (Real Decreto 217/2022 y 243/2022).
enum LomloeCriteriaCatalog {
    static let allCriteria: [LomloeCriterionDefinition] = [
        // CE 1: Salud, condición física y estilo de vida
        .init(
            code: "CE 1.1",
            title: "Diseño y desarrollo autónomo de programa de condición física",
            officialDescription: "Diseñar y poner en práctica de manera autónoma un programa de actividad física para la mejora de la condición física y la salud, basado en criterios científicos, y aprovechando responsablemente los recursos del entorno y las nuevas tecnologías.",
            valencianDescription: "Dissenyar i posar en pràctica de manera autònoma un programa d'activitat física per a la millora de la condició física i la salut, basat en criteris científics, i aprofitant responsablement els recursos de l'entorn i les noves tecnologies."
        ),
        .init(
            code: "CE 1.2",
            title: "Gestión del esfuerzo y principios del entrenamiento",
            officialDescription: "Incorporar propuestas para la gestión del esfuerzo en las actividades físicas, aplicando los principios y fases del entrenamiento.",
            valencianDescription: "Incorporar propostes per a la gestió de l'esforç en les activitats físiques, aplicant els principis i fases de l'entrenament."
        ),
        .init(
            code: "CE 1.3",
            title: "Hábitos de alimentación saludable y consumo sostenible",
            officialDescription: "Consolidar hábitos de alimentación saludable atendiendo a un balance energético equilibrado considerando los principios nutricionales desde el consumo responsable y sostenible.",
            valencianDescription: "Consolidar hàbits d'alimentació saludable atenent a un balanç energètic equilibrat considerant els principis nutricionals des del consum responsable i sostenible."
        ),
        .init(
            code: "CE 1.4",
            title: "Análisis crítico de estilos de vida y conductas de riesgo",
            officialDescription: "Analizar críticamente los componentes que participan de un estilo de vida saludable, en el ámbito educativo y el ámbito sociofamiliar, discriminando las conductas de riesgo para la salud física, mental y social.",
            valencianDescription: "Analitzar críticament els components que participen d'un estil de vida saludable, a l'àmbit educatiu i l'àmbit sociofamiliar, discriminant les conductes de risc per a la salut física, mental i social."
        ),

        // CE 2: Resolución de situaciones deportivo-motrices
        .init(
            code: "CE 2.1",
            title: "Eficacia técnico-táctica, reglas y resolución de conflictos",
            officialDescription: "Resolver con eficacia y eficiencia motriz diferentes situaciones de juego y práctica deportiva utilizando los principios técnicos, tácticos y reglamentarios adecuados, aplicando pautas de seguridad e higiene personal y utilizando las estrategias apropiadas para la resolución de conflictos.",
            valencianDescription: "Resoldre amb eficàcia i eficiència motriu diferents situacions de joc i pràctica esportiva utilitzant els principis tècnics, tàctics i reglamentaris adients, aplicant pautes de seguretat i d’higiene personal i utilitzant les estratègies apropiades per a la resolució de conflictes."
        ),
        .init(
            code: "CE 2.2",
            title: "Gestión y organización sostenible de eventos deportivos",
            officialDescription: "Diseñar y participar en eventos recreativos y deportivos aplicando políticas sostenibles de gestión y uso de materiales e instalaciones.",
            valencianDescription: "Dissenyar i participar en esdeveniments recreatius i esportius aplicant polítiques sostenibles de gestió i ús de materials i instal·lacions."
        ),
        .init(
            code: "CE 2.3",
            title: "Justicia social, inclusión e igualdad de oportunidades",
            officialDescription: "Investigar diferentes contextos de actividad física y de deportes atendiendo a los elementos inherentes a la justicia social como la participación y la igualdad de oportunidades.",
            valencianDescription: "Investigar diferents contextos d’activitat física i d’esports atenent als elements inherents a la justícia social com la participació i la igualtat d’oportunitats."
        ),

        // CE 3: Expresión corporal y dimensión socioafectiva
        .init(
            code: "CE 3.1",
            title: "Creación y producción artístico-expresiva e inclusiva",
            officialDescription: "Crear y ejecutar propuestas artístico-expresivas mostrando dominio de los elementos corporales y escénicos desde una perspectiva de género e inclusiva.",
            valencianDescription: "Crear i executar propostes artisticoexpressives mostrant domini dels elements corporals i escènics des d’una perspectiva de gènere i inclusiva."
        ),
        .init(
            code: "CE 3.2",
            title: "Fair play, autorregulación emocional y empatía",
            officialDescription: "Practicar diversas actividades motrices adoptando un comportamiento personal y social respetuoso y responsable, mostrando actitudes de empatía e inclusión ante la diversidad y autorregulando las emociones.",
            valencianDescription: "Practicar diverses activitats motrius adoptant un comportament personal i social respectuós i responsable, mostrant actituds d’empatia i inclusió davant la diversitat i autoregulant les emocions."
        ),
        .init(
            code: "CE 3.3",
            title: "Patrimonio cultural motriz y Pilota Valenciana",
            officialDescription: "Organizar y participar en partidas de Pelota Valenciana reconociendo sus valores intrínsecos.",
            valencianDescription: "Organitzar i participar en partides de Pilota Valenciana reconeixent els seus valors intrínsecs."
        ),

        // CE 4: Medio natural, sostenibilidad y primeros auxilios
        .init(
            code: "CE 4.1",
            title: "Actividades en el medio natural y eco-responsabilidad",
            officialDescription: "Organizar y practicar actividades físico-deportivas inclusivas en el medio natural y urbano con seguridad y eco-responsabilidad fomentando el ocio activo y estilos de vida sostenibles.",
            valencianDescription: "Organitzar i practicar activitats fisicoesportives inclusives en el medi natural i urbà amb seguretat i eco-responsabilitat fomentant l’oci actiu i estils de vida sostenibles."
        ),
        .init(
            code: "CE 4.2",
            title: "Protección ambiental y sostenibilidad del entorno",
            officialDescription: "Identificar y aplicar actuaciones saludables y sostenibles para la protección, conservación y mejora del entorno natural y urbano, estableciendo relaciones con entidades relacionadas con la educación ambiental y la sostenibilidad.",
            valencianDescription: "Identificar i aplicar actuacions saludables i sostenibles per a la protecció, conservació i millora de l’entorn natural i urbà, establint relacions amb entitats relacionades amb l’educació ambiental i la sostenibilitat."
        ),
        .init(
            code: "CE 4.3",
            title: "Seguridad, primeros auxilios y gestión de riesgos",
            officialDescription: "Practicar y aplicar normas de seguridad y técnicas de primeros auxilios y supervivencia en contextos naturales y urbanos para controlar los riesgos intrínsecos de las actividades respecto a los equipamientos, el entorno y la actuación e interacción de los participantes.",
            valencianDescription: "Practicar i aplicar normes de seguretat i tècniques de primers auxilis i supervivència en contextos naturals i urbans per a controlar els riscos intrínsecs de les activitats respecte als equipaments, l’entorn i l’actuació i interacció dels participants."
        ),

        // CE 5: Orientación laboral, emprendimiento y tecnología
        .init(
            code: "CE 5.1",
            title: "Proyectos de actividad física y salud en el entorno",
            officialDescription: "Participar en propuestas reales o simuladas relacionadas con la actividad física y la salud, el deporte, las actividades artístico-expresivas o la naturaleza, analizando las posibilidades del entorno más próximo y teniendo en cuenta la sostenibilidad.",
            valencianDescription: "Participar en propostes reals o simulades relacionades amb l’activitat física i la salut, l’esport, les activitats artisticoexpressives o la natura, analitzant les possibilitats del entorn més pròxim i tenint en compte la sostenibilitat."
        ),
        .init(
            code: "CE 5.2",
            title: "Curación de contenidos digitales e innovación tecnológica",
            officialDescription: "Detectar y curar contenidos con el uso de la tecnología como elemento facilitador para la creación de escenarios de práctica activa saludable.",
            valencianDescription: "Detectar i curar continguts amb l’ús de la tecnologia com a element facilitador per a la creació d’escenaris de pràctica activa saludable."
        ),
        .init(
            code: "CE 5.3",
            title: "Orientación académica, laboral y salidas profesionales",
            officialDescription: "Colaborar en propuestas informativas de salidas académicas y laborales y en visitas a espacios relacionados con la actividad física, el deporte y el ocio activo.",
            valencianDescription: "Col·laborar en propostes informatives d’eixides acadèmiques i laborals i en visites a espais relacionats amb l'activitat física, l'esport i l'oci actiu."
        )
    ]

    private static let criteriaByCode: [String: LomloeCriterionDefinition] = {
        var dict: [String: LomloeCriterionDefinition] = [:]
        for item in allCriteria {
            dict[item.code.uppercased()] = item
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
    /// y devuelve la lista de definiciones oficiales encontradas. Si no hay código explícito,
    /// aplica resolución semántica por palabras clave del currículo de Educación Física.
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

        if foundCodes.isEmpty {
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "·,;/"))
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.uppercased().hasPrefix("CE") {
                    foundCodes.append(trimmed)
                }
            }
        }

        // Si no hay código explícito "CE X.X", resolver por palabras clave temáticas de EF 1º Bachillerato
        if foundCodes.isEmpty {
            let lower = text.lowercased()
            if lower.contains("sostenib") || lower.contains("medio natural") || lower.contains("organización") {
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
                if !foundCodes.contains("CE 3.1") { foundCodes.append("CE 3.1") }
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
                officialDescription: "Criterio de evaluación específico definido en la legislación LOMLOE."
            )
        }
    }
}
