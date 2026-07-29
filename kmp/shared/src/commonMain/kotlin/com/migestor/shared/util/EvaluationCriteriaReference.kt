package com.migestor.shared.util

/**
 * Texto oficial de los 16 criterios de evaluacion LOMLOE de Educacion Fisica, 1r de Batxillerat
 * (Comunitat Valenciana), y el catalogo de que instrumento evalua que criterio. Fuente: la carpeta
 * de programaciones del docente (fuera de este repositorio), documentos
 * `05_competencias_y_criterios_oficiales_1bac.md` y `05_EVALUACION/instrumentos_evaluacion*.md` de
 * cada situacion de aprendizaje. Vive embebido aqui porque el dispositivo del docente no tiene
 * acceso a esa carpeta: es la unica forma de que la app muestre el enunciado real del criterio en
 * vez de solo su codigo ("CE 3.2") o una nota generica de importacion.
 *
 * Si el docente cambia de curso, etapa o materia estos textos dejan de aplicar: es un catalogo fijo
 * de 1r de Batxillerat - Educacion Fisica, no un mecanismo general de curriculo.
 */
object EvaluationCriteriaReference {

    /** "2.1" -> enunciado completo del criterio. */
    private val officialCriterionStatements: Map<String, String> = mapOf(
        "1.1" to "Diseñar y poner en práctica de manera autónoma un programa de actividad física para la mejora de la condición física y la salud, basado en criterios científicos y aprovechando responsablemente los recursos del entorno y las nuevas tecnologías.",
        "1.2" to "Incorporar propuestas para la gestión del esfuerzo en las actividades físicas, aplicando los principios y fases del entrenamiento.",
        "1.3" to "Consolidar hábitos de alimentación saludable atendiendo a un balance energético equilibrado, considerando los principios nutricionales desde el consumo responsable y sostenible.",
        "1.4" to "Analizar críticamente los componentes de un estilo de vida saludable, en el ámbito educativo y sociofamiliar, discriminando las conductas de riesgo para la salud física, mental y social.",
        "2.1" to "Resolver con eficacia y eficiencia motriz diferentes situaciones de juego y práctica deportiva utilizando los principios técnicos, tácticos y reglamentarios adecuados, aplicando pautas de seguridad e higiene personal y utilizando las estrategias apropiadas para la resolución de conflictos.",
        "2.2" to "Diseñar y participar en eventos recreativos y deportivos aplicando políticas sostenibles de gestión y uso de materiales e instalaciones.",
        "2.3" to "Investigar diferentes contextos de actividad física y de deportes atendiendo a los elementos inherentes a la justicia social, como la participación y la igualdad de oportunidades.",
        "3.1" to "Crear y ejecutar propuestas artístico-expresivas mostrando dominio de los elementos corporales y escénicos desde una perspectiva de género e inclusiva.",
        "3.2" to "Practicar diversas actividades motrices adoptando un comportamiento personal y social respetuoso y responsable, mostrando actitudes de empatía e inclusión ante la diversidad y autorregulando las emociones.",
        "3.3" to "Organizar y participar en partidas de Pilota Valenciana reconociendo sus valores intrínsecos.",
        "4.1" to "Organizar y practicar actividades fisicodeportivas inclusivas en el medio natural y urbano con seguridad y eco-responsabilidad, fomentando el ocio activo y estilos de vida sostenibles.",
        "4.2" to "Identificar y aplicar actuaciones saludables y sostenibles para la protección, conservación y mejora del entorno natural y urbano, estableciendo relaciones con entidades relacionadas con la educación ambiental y la sostenibilidad.",
        "4.3" to "Practicar y aplicar normas de seguridad y técnicas de primeros auxilios y supervivencia en contextos naturales y urbanos para controlar los riesgos intrínsecos de las actividades respecto a los equipamientos, el entorno y la actuación e interacción de los participantes.",
        "5.1" to "Participar en propuestas reales o simuladas relacionadas con la actividad física y la salud, el deporte, las actividades artístico-expresivas o la naturaleza, analizando las posibilidades del entorno más próximo y teniendo en cuenta la sostenibilidad.",
        "5.2" to "Detectar y curar contenidos con el uso de la tecnología como elemento facilitador para la creación de escenarios de práctica activa saludable.",
        "5.3" to "Colaborar en propuestas informativas de salidas académicas y laborales y en visitas a espacios relacionados con la actividad física, el deporte y el ocio activo.",
    )

    /**
     * Titulo del instrumento (tal como lo escribe el importador en `Evaluation.name`, ver
     * `materializeLearningSituationAssessmentInstruments` en KmpBridge.swift) -> codigos de
     * criterio ("2.1", no "CE 2.1"). Transcrito a mano de la cabecera "N\. <instrumento> - CE X.Y -
     * Z%" de cada `05_EVALUACION/instrumentos_evaluacion*.md` de las situaciones de aprendizaje de
     * 1r de Batxillerat - Educacion Fisica (SA1 a SA6). El instrumento transversal "Rejilla de
     * observación sistemática de fair play, roles e inclusión" es el mismo en las seis SA, siempre
     * CE 3.2, asi que aparece una sola vez.
     */
    private val instrumentCriterionCodesByTitle: Map<String, List<String>> = mapOf(
        "Rúbrica de diseño del plan" to listOf("1.1"),
        "Rejilla de observación sistemática de proceso" to listOf("1.2", "1.4"),
        "Quiz de hábitos y alimentación saludable" to listOf("1.3", "1.4"),
        "Rejilla de observación sistemática de fair play, roles e inclusión" to listOf("3.2"),
        "Rúbrica de progreso técnico" to listOf("2.1"),
        "Rejilla de observación sistemática de aplicación en juego" to listOf("2.1"),
        "Rúbrica de portafolio técnico" to listOf("2.1"),
        "Registro de observación docente" to listOf("2.1"),
        "Rúbrica técnico-táctica de Pilota Valenciana" to listOf("3.3"),
        "Rúbrica de organización del torneo" to listOf("3.3"),
        "Rúbrica de portafolio" to listOf("3.3"),
        "Quiz de fundamentos de RCP" to listOf("4.3"),
        "Rúbrica de aplicación de PAS/RICE y vendaje" to listOf("4.3"),
        "Rúbrica de RCP" to listOf("4.3"),
        "Rúbrica de valoración entre iguales" to listOf("4.3"),
        "Rúbrica de juego: técnica y táctica" to listOf("2.1"),
        "Rejilla de observación sistemática: arbitraje y organización del torneo" to listOf("2.1"),
        "Rúbrica de cierre individual y de equipo" to listOf("3.2"),
        "Rúbrica técnico-táctica de torneo" to listOf("2.1"),
        "Rúbrica de organización sostenible del torneo" to listOf("2.2"),
        "Rúbrica de justicia social y participación" to listOf("2.3"),
        "Rúbrica de ejecución técnica y creatividad" to listOf("3.1"),
        "Rúbrica de organización segura del evento" to listOf("4.1"),
        "Rúbrica de sostenibilidad y comunicación" to listOf("4.2"),
    )

    private val accentFold = mapOf(
        'á' to 'a', 'é' to 'e', 'í' to 'i', 'ó' to 'o', 'ú' to 'u', 'ü' to 'u', 'ñ' to 'n',
    )

    private fun normalizeTitle(value: String): String =
        value.trim().lowercase()
            .map { accentFold[it] ?: it }
            .joinToString("")
            .replace(Regex("\\s+"), " ")

    // Claves normalizadas una sola vez, no en cada busqueda: mismo criterio de normalizacion que
    // `normalizedAssessmentInstrumentTitle` en KmpBridge.swift (minusculas, sin tildes, espacios
    // colapsados), para que una tilde distinta entre el titulo importado y esta tabla no rompa el
    // emparejamiento. Debe declararse DESPUES de `accentFold`: los inicializadores de propiedades
    // de un `object` en Kotlin se ejecutan en orden de declaracion, y esta llama a `normalizeTitle`,
    // que lee `accentFold` (crash EXC_BAD_ACCESS visto en el Mac: se ejecutaba con `accentFold` aun
    // sin inicializar).
    private val instrumentCriterionCodesByNormalizedTitle: Map<String, List<String>> =
        instrumentCriterionCodesByTitle.mapKeys { (title, _) -> normalizeTitle(title) }

    /**
     * Enunciado oficial completo del/de los criterio(s) que evalua un instrumento, buscado por su
     * titulo (por ejemplo "Rejilla de observación sistemática de fair play, roles e inclusión" ->
     * el enunciado del criterio 3.2). Si el instrumento evalua dos criterios (p.ej. "CE 1.2 y
     * 1.4"), devuelve ambos enunciados con su codigo delante, uno por parrafo. `null` si el titulo
     * no esta en el catalogo (instrumento de otra materia/curso, o titulo editado a mano).
     */
    fun criterionStatement(instrumentTitle: String): String? {
        val codes = instrumentCriterionCodesByNormalizedTitle[normalizeTitle(instrumentTitle)]
            ?.takeIf { it.isNotEmpty() } ?: return null
        val statements = codes.mapNotNull { code ->
            officialCriterionStatements[code]?.let { statement ->
                if (codes.size > 1) "Criterio $code: $statement" else statement
            }
        }
        return statements.takeIf { it.isNotEmpty() }?.joinToString("\n\n")
    }
}
