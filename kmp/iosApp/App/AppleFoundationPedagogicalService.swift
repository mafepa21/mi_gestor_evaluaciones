import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Inputs

struct RubricDraftInput: Hashable, Sendable {
    let title: String
    let criteriaOrTask: String
    let courseOrCycle: String?
    let levelCount: Int

    init(
        title: String,
        criteriaOrTask: String,
        courseOrCycle: String? = nil,
        levelCount: Int = 4
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.criteriaOrTask = criteriaOrTask.trimmingCharacters(in: .whitespacesAndNewlines)
        self.courseOrCycle = courseOrCycle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.levelCount = max(2, min(5, levelCount))
    }
}

struct DUAAdaptationInput: Hashable, Sendable {
    let activityTitle: String
    let activityDescription: String
    let studentNeeds: String
    let subjectArea: String?

    init(
        activityTitle: String,
        activityDescription: String,
        studentNeeds: String,
        subjectArea: String? = nil
    ) {
        self.activityTitle = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activityDescription = activityDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.studentNeeds = studentNeeds.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subjectArea = subjectArea?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PlannerSequenceInput: Hashable, Sendable {
    let unitTitle: String
    let sessionIndex: Int
    let totalSessions: Int
    let learningOutcomes: [String]
    let targetAudience: String?

    init(
        unitTitle: String,
        sessionIndex: Int,
        totalSessions: Int,
        learningOutcomes: [String] = [],
        targetAudience: String? = nil
    ) {
        self.unitTitle = unitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionIndex = max(1, sessionIndex)
        self.totalSessions = max(1, totalSessions)
        self.learningOutcomes = learningOutcomes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.targetAudience = targetAudience?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MetacognitionPromptsInput: Hashable, Sendable {
    let topicOrTask: String
    let studentLevel: String?
    let modality: String?

    init(
        topicOrTask: String,
        studentLevel: String? = nil,
        modality: String? = nil
    ) {
        self.topicOrTask = topicOrTask.trimmingCharacters(in: .whitespacesAndNewlines)
        self.studentLevel = studentLevel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modality = modality?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Output Models

struct AIRubricLevelDraft: Codable, Hashable, Sendable {
    let levelIndex: Int
    let levelName: String
    let descriptor: String
    let scoreSuggestion: Double
}

struct AIRubricCriterionDraft: Codable, Hashable, Sendable {
    let criterionTitle: String
    let description: String
    let weight: Double
    let levels: [AIRubricLevelDraft]
}

struct AIRubricDraft: Codable, Hashable, Sendable {
    let title: String
    let targetCourse: String?
    let criteria: [AIRubricCriterionDraft]
    let teacherTips: [String]
    let confidenceNote: String
    let appearsToBeRulesFallback: Bool

    init(
        title: String,
        targetCourse: String?,
        criteria: [AIRubricCriterionDraft],
        teacherTips: [String],
        confidenceNote: String,
        appearsToBeRulesFallback: Bool = false
    ) {
        self.title = AppleAIOutputNormalizer.nonEmpty(title, fallback: "Rúbrica de evaluación")
        self.targetCourse = targetCourse
        self.criteria = criteria
        self.teacherTips = AppleAIOutputNormalizer.compactLimited(teacherTips, limit: 3)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(confidenceNote, fallback: "Generado localmente.")
        self.appearsToBeRulesFallback = appearsToBeRulesFallback
    }
}

struct DUAAdaptationDraft: Codable, Hashable, Sendable {
    let studentContext: String
    let representationStrategies: [String]
    let actionAndExpressionStrategies: [String]
    let engagementStrategies: [String]
    let evaluationAlternative: String
    let confidenceNote: String
    let appearsToBeRulesFallback: Bool

    init(
        studentContext: String,
        representationStrategies: [String],
        actionAndExpressionStrategies: [String],
        engagementStrategies: [String],
        evaluationAlternative: String,
        confidenceNote: String,
        appearsToBeRulesFallback: Bool = false
    ) {
        self.studentContext = AppleAIOutputNormalizer.nonEmpty(studentContext, fallback: "Contexto de adaptación DUA")
        self.representationStrategies = AppleAIOutputNormalizer.compactLimited(representationStrategies, limit: 3)
        self.actionAndExpressionStrategies = AppleAIOutputNormalizer.compactLimited(actionAndExpressionStrategies, limit: 3)
        self.engagementStrategies = AppleAIOutputNormalizer.compactLimited(engagementStrategies, limit: 3)
        self.evaluationAlternative = AppleAIOutputNormalizer.nonEmpty(evaluationAlternative, fallback: "Ofrecer instrumento alternativo diversificado.")
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(confidenceNote, fallback: "Pautas DUA generadas localmente.")
        self.appearsToBeRulesFallback = appearsToBeRulesFallback
    }
}

struct PlannerSessionStepDraft: Codable, Hashable, Sendable {
    let phase: String
    let estimatedMinutes: Int
    let activityDescription: String
    let organizationTips: String
    let materialNeeds: [String]
}

struct PlannerSequenceDraft: Codable, Hashable, Sendable {
    let unitTitle: String
    let sessionNumber: Int
    let sessionFocus: String
    let steps: [PlannerSessionStepDraft]
    let evaluationStrategy: String
    let confidenceNote: String
    let appearsToBeRulesFallback: Bool

    init(
        unitTitle: String,
        sessionNumber: Int,
        sessionFocus: String,
        steps: [PlannerSessionStepDraft],
        evaluationStrategy: String,
        confidenceNote: String,
        appearsToBeRulesFallback: Bool = false
    ) {
        self.unitTitle = AppleAIOutputNormalizer.nonEmpty(unitTitle, fallback: "Unidad didáctica")
        self.sessionNumber = sessionNumber
        self.sessionFocus = AppleAIOutputNormalizer.nonEmpty(sessionFocus, fallback: "Objetivo de la sesión")
        self.steps = steps
        self.evaluationStrategy = AppleAIOutputNormalizer.nonEmpty(evaluationStrategy, fallback: "Observación directa y registro en cuaderno.")
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(confidenceNote, fallback: "Secuencia didáctica generada localmente.")
        self.appearsToBeRulesFallback = appearsToBeRulesFallback
    }
}

struct MetacognitionPromptsDraft: Codable, Hashable, Sendable {
    let contextTitle: String
    let selfEvaluationPrompts: [String]
    let peerEvaluationPrompts: [String]
    let exitTicketQuestion: String
    let confidenceNote: String
    let appearsToBeRulesFallback: Bool

    init(
        contextTitle: String,
        selfEvaluationPrompts: [String],
        peerEvaluationPrompts: [String],
        exitTicketQuestion: String,
        confidenceNote: String,
        appearsToBeRulesFallback: Bool = false
    ) {
        self.contextTitle = AppleAIOutputNormalizer.nonEmpty(contextTitle, fallback: "Autoevaluación")
        self.selfEvaluationPrompts = AppleAIOutputNormalizer.compactLimited(selfEvaluationPrompts, limit: 3)
        self.peerEvaluationPrompts = AppleAIOutputNormalizer.compactLimited(peerEvaluationPrompts, limit: 3)
        self.exitTicketQuestion = AppleAIOutputNormalizer.nonEmpty(exitTicketQuestion, fallback: "¿Qué es lo más importante que has aprendido hoy?")
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(confidenceNote, fallback: "Preguntas generadas localmente.")
        self.appearsToBeRulesFallback = appearsToBeRulesFallback
    }
}

// MARK: - Service Implementation

@MainActor
final class AppleFoundationPedagogicalService {
    #if canImport(FoundationModels)
    private var rubricSessionStorage: Any?
    private var duaSessionStorage: Any?
    private var plannerSessionStorage: Any?
    private var metacognitionSessionStorage: Any?
    #endif

    func prewarm() {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            _ = consumeRubricSession()
            _ = consumeDUASession()
            _ = consumePlannerSession()
            _ = consumeMetacognitionSession()
        }
        #endif
    }

    // MARK: 1. Generador de Rúbricas LOMLOE

    func generateRubricDraft(from input: RubricDraftInput) async throws -> AIRubricDraft {
        guard !input.title.isEmpty || !input.criteriaOrTask.isEmpty else {
            return fallbackRubricDraft(from: input, reason: "Título o criterio vacío.")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackRubricDraft(from: input, reason: "Resultado generado con reglas pedagógicas locales.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeRubricSession().respond(
                    to: rubricPrompt(from: input),
                    generating: GeneratedRubricDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                let criteria = response.content.criteria.map { c in
                    AIRubricCriterionDraft(
                        criterionTitle: c.criterionTitle,
                        description: c.description,
                        weight: c.weight,
                        levels: c.levels.map { l in
                            AIRubricLevelDraft(
                                levelIndex: l.levelIndex,
                                levelName: l.levelName,
                                descriptor: l.descriptor,
                                scoreSuggestion: l.scoreSuggestion
                            )
                        }
                    )
                }
                return AIRubricDraft(
                    title: response.content.title,
                    targetCourse: input.courseOrCycle,
                    criteria: criteria,
                    teacherTips: response.content.teacherTips,
                    confidenceNote: "Rúbrica estructurada con Apple Intelligence.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackRubricDraft(from: input, reason: "Resultado generado con reglas pedagógicas locales.")
            }
        }
        #endif

        return fallbackRubricDraft(from: input, reason: "Resultado generado con reglas pedagógicas locales.")
    }

    // MARK: 2. Asistente DUA y Adaptaciones

    func generateDUAAdaptation(from input: DUAAdaptationInput) async throws -> DUAAdaptationDraft {
        guard !input.studentNeeds.isEmpty else {
            return fallbackDUAAdaptation(from: input, reason: "Falta especificar la necesidad o perfil del alumno.")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackDUAAdaptation(from: input, reason: "Resultado generado con reglas DUA locales.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeDUASession().respond(
                    to: duaPrompt(from: input),
                    generating: GeneratedDUAAdaptationDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                return DUAAdaptationDraft(
                    studentContext: "\(input.studentNeeds) · \(input.activityTitle)",
                    representationStrategies: response.content.representationStrategies,
                    actionAndExpressionStrategies: response.content.actionAndExpressionStrategies,
                    engagementStrategies: response.content.engagementStrategies,
                    evaluationAlternative: response.content.evaluationAlternative,
                    confidenceNote: "Pautas DUA redactadas con Apple Intelligence.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackDUAAdaptation(from: input, reason: "Resultado generado con reglas DUA locales.")
            }
        }
        #endif

        return fallbackDUAAdaptation(from: input, reason: "Resultado generado con reglas DUA locales.")
    }

    // MARK: 3. Secuenciador para Planner

    func generatePlannerSequence(from input: PlannerSequenceInput) async throws -> PlannerSequenceDraft {
        guard !input.unitTitle.isEmpty else {
            return fallbackPlannerSequence(from: input, reason: "Título de unidad vacío.")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackPlannerSequence(from: input, reason: "Secuencia generada con plantilla didáctica local.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumePlannerSession().respond(
                    to: plannerPrompt(from: input),
                    generating: GeneratedPlannerSequenceDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.25)
                )
                let steps = response.content.steps.map { s in
                    PlannerSessionStepDraft(
                        phase: s.phase,
                        estimatedMinutes: s.estimatedMinutes,
                        activityDescription: s.activityDescription,
                        organizationTips: s.organizationTips,
                        materialNeeds: s.materialNeeds
                    )
                }
                return PlannerSequenceDraft(
                    unitTitle: input.unitTitle,
                    sessionNumber: input.sessionIndex,
                    sessionFocus: response.content.sessionFocus,
                    steps: steps,
                    evaluationStrategy: response.content.evaluationStrategy,
                    confidenceNote: "Secuencia didáctica generada con Apple Intelligence.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackPlannerSequence(from: input, reason: "Secuencia generada con plantilla didáctica local.")
            }
        }
        #endif

        return fallbackPlannerSequence(from: input, reason: "Secuencia generada con plantilla didáctica local.")
    }

    // MARK: 4. Metacognición y Coevaluación

    func generateMetacognitionPrompts(from input: MetacognitionPromptsInput) async throws -> MetacognitionPromptsDraft {
        guard !input.topicOrTask.isEmpty else {
            return fallbackMetacognitionPrompts(from: input, reason: "Tema o tarea no especificada.")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackMetacognitionPrompts(from: input, reason: "Preguntas generadas con plantilla local.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeMetacognitionSession().respond(
                    to: metacognitionPrompt(from: input),
                    generating: GeneratedMetacognitionPromptsDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                return MetacognitionPromptsDraft(
                    contextTitle: input.topicOrTask,
                    selfEvaluationPrompts: response.content.selfEvaluationPrompts,
                    peerEvaluationPrompts: response.content.peerEvaluationPrompts,
                    exitTicketQuestion: response.content.exitTicketQuestion,
                    confidenceNote: "Preguntas de autorreflexión con Apple Intelligence.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackMetacognitionPrompts(from: input, reason: "Preguntas generadas con plantilla local.")
            }
        }
        #endif

        return fallbackMetacognitionPrompts(from: input, reason: "Preguntas generadas con plantilla local.")
    }

    // MARK: - Sessions (Apple Intelligence)

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func consumeRubricSession() -> LanguageModelSession {
        if let session = rubricSessionStorage as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            instructions: """
            Eres un experto pedagógico en diseño curricular y evaluación formativa (LOMLOE).
            Tu tarea es generar rúbricas analíticas con niveles de logro graduales, observables y medibles.
            Evita adjetivos vacíos ("regular", "bien", "bastante"). Describe hechos y evidencias de ejecución.
            Devuelve un objeto estructurado. Tono profesional docente en español de España.
            """
        )
        rubricSessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeDUASession() -> LanguageModelSession {
        if let session = duaSessionStorage as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            instructions: """
            Eres un orientador y especialista en DUA (Diseño Universal para el Aprendizaje).
            Tu cometido es proponer ajustes pedagógicos prácticos y realistas en tres áreas:
            1. Formas de representación (cómo presentar la información).
            2. Formas de acción y expresión (cómo demuestra el alumno lo aprendido).
            3. Formas de implicación (cómo mantener la motivación y el interés).
            No emitas diagnósticos clínicos. Propón adaptaciones docentes revisables en español de España.
            """
        )
        duaSessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumePlannerSession() -> LanguageModelSession {
        if let session = plannerSessionStorage as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            instructions: """
            Eres un diseñador didáctico de sesiones de aula escolar.
            Estructura la sesión en 3 fases:
            1. Activación / Calentamiento (5-10 min).
            2. Desarrollo competencial / Parte principal (30-40 min).
            3. Vuelta a la calma / Reflexión / Coevaluación (5-10 min).
            Propón actividades concretas, organización del espacio y estrategia evaluativa formativa.
            """
        )
        plannerSessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeMetacognitionSession() -> LanguageModelSession {
        if let session = metacognitionSessionStorage as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            instructions: """
            Eres un especialista en metacognición y evaluación formativa entre iguales.
            Formula preguntas breves, directas y claras para que los alumnos piensen sobre su propio proceso
            o valoren respetuosamente el trabajo de sus compañeros.
            Redacta en un lenguaje accesible y cercano para el alumnado.
            """
        )
        metacognitionSessionStorage = session
        return session
    }
    #endif

    // MARK: - Prompts

    private func rubricPrompt(from input: RubricDraftInput) -> String {
        """
        Genera una rúbrica analítica LOMLOE.
        Título o tarea: \(input.title)
        Criterios / Evidencias deseadas: \(input.criteriaOrTask)
        \(input.courseOrCycle.map { "Curso / Nivel: \($0)" } ?? "")
        Número de niveles por criterio: \(input.levelCount) (desde 1: Insuficiente hasta \(input.levelCount): Sobresaliente)

        Reglas:
        - Cada nivel debe tener un descriptor observable y diferenciado.
        - Asigna pesos coherentes que sumen 100 o 1.0.
        - Añade 2 o 3 consejos docentes prácticos para su aplicación en el aula.
        """
    }

    private func duaPrompt(from input: DUAAdaptationInput) -> String {
        """
        Propón adaptaciones DUA para la siguiente situación de aula:
        Actividad: \(input.activityTitle)
        Descripción de la tarea: \(input.activityDescription)
        Perfil o necesidad del alumno: \(input.studentNeeds)
        \(input.subjectArea.map { "Materia / Ámbito: \($0)" } ?? "")

        Reglas:
        - Máximo 3 estrategias de representación.
        - Máximo 3 estrategias de acción y expresión.
        - Máximo 3 estrategias de implicación.
        - 1 alternativa o ajuste de evaluación formativa realizable en el aula ordinaria.
        """
    }

    private func plannerPrompt(from input: PlannerSequenceInput) -> String {
        """
        Secuencia una sesión lectiva para el planificador docente:
        Unidad didáctica: \(input.unitTitle)
        Sesión: \(input.sessionIndex) de \(input.totalSessions)
        \(input.learningOutcomes.isEmpty ? "" : "Criterios/Objetivos: \(input.learningOutcomes.joined(separator: ", "))")
        \(input.targetAudience.map { "Nivel del alumnado: \($0)" } ?? "")

        Reglas:
        - Estructura en 3 fases: Activación, Desarrollo competencial y Reflexión/Cierre.
        - Ajusta la duración total estimada a 50-60 minutos.
        - Especifica organización del alumnado (parejas, tríos, individual) y materiales necesarios.
        """
    }

    private func metacognitionPrompt(from input: MetacognitionPromptsInput) -> String {
        """
        Genera preguntas de autorreflexión y coevaluación para la sesión:
        Tarea / Contexto: \(input.topicOrTask)
        \(input.studentLevel.map { "Nivel escolar: \($0)" } ?? "")
        \(input.modality.map { "Modalidad: \($0)" } ?? "")

        Reglas:
        - 2 a 3 preguntas de autoevaluación claras y directas.
        - 2 a 3 preguntas de coevaluación constructiva entre iguales.
        - 1 pregunta de ticket de salida (cierre rápido en 1 minuto).
        """
    }

    // MARK: - Fallbacks deterministas

    private func fallbackRubricDraft(from input: RubricDraftInput, reason: String) -> AIRubricDraft {
        let taskName = input.title.isEmpty ? "Tarea evaluable" : input.title
        let criteria = [
            AIRubricCriterionDraft(
                criterionTitle: "Comprensión y aplicación",
                description: "Aplica los conceptos y procedimientos de la tarea \(taskName).",
                weight: 50.0,
                levels: [
                    AIRubricLevelDraft(levelIndex: 1, levelName: "Insuficiente", descriptor: "No muestra comprensión ni aplica los procedimientos básicos requeridos.", scoreSuggestion: 2.5),
                    AIRubricLevelDraft(levelIndex: 2, levelName: "Suficiente", descriptor: "Aplica los procedimientos básicos con ayuda docente o pautas guiadas.", scoreSuggestion: 5.5),
                    AIRubricLevelDraft(levelIndex: 3, levelName: "Notable", descriptor: "Aplica de forma autónoma los procedimientos con corrección en la mayoría de situaciones.", scoreSuggestion: 7.5),
                    AIRubricLevelDraft(levelIndex: 4, levelName: "Sobresaliente", descriptor: "Demuestra dominio completo, anticipación y justificación rigurosa de las decisiones.", scoreSuggestion: 9.5)
                ]
            ),
            AIRubricCriterionDraft(
                criterionTitle: "Autonomía y colaboración",
                description: "Participa de forma activa, respeta las normas y colabora eficazmente.",
                weight: 50.0,
                levels: [
                    AIRubricLevelDraft(levelIndex: 1, levelName: "Insuficiente", descriptor: "Muestra desinterés o dificultad persistente para trabajar con autonomía o respetar pautas.", scoreSuggestion: 2.5),
                    AIRubricLevelDraft(levelIndex: 2, levelName: "Suficiente", descriptor: "Cumple las pautas con recordatorios y colabora de forma básica en su grupo.", scoreSuggestion: 5.5),
                    AIRubricLevelDraft(levelIndex: 3, levelName: "Notable", descriptor: "Trabaja con autonomía, colabora activamente y apoya a sus compañeros.", scoreSuggestion: 7.5),
                    AIRubricLevelDraft(levelIndex: 4, levelName: "Sobresaliente", descriptor: "Ejerce liderazgo positivo, resuelve conflictos de forma constructiva y optimiza el trabajo.", scoreSuggestion: 9.5)
                ]
            )
        ]

        return AIRubricDraft(
            title: taskName,
            targetCourse: input.courseOrCycle,
            criteria: criteria,
            teacherTips: [
                "Compartir la rúbrica con los alumnos antes de iniciar la tarea.",
                "Usar los descriptores intermedios para orientar la mejora durante el proceso."
            ],
            confidenceNote: reason,
            appearsToBeRulesFallback: true
        )
    }

    private func fallbackDUAAdaptation(from input: DUAAdaptationInput, reason: String) -> DUAAdaptationDraft {
        DUAAdaptationDraft(
            studentContext: "\(input.studentNeeds) · \(input.activityTitle)",
            representationStrategies: [
                "Acompañar las instrucciones escritas con ejemplos visuales, esquemas o modelado previo.",
                "Fraccionar la explicación en pasos numerados con comprobación de comprensión intermedia."
            ],
            actionAndExpressionStrategies: [
                "Permitir diferentes formatos de respuesta (oral, esquema visual, grabación o plantilla guiada).",
                "Ofrecer tiempo adicional o pausas estructuradas si la tarea requiere alta concentración."
            ],
            engagementStrategies: [
                "Vincular el reto a intereses cotidianos del alumno y fijar una meta inicial sencilla y alcanzable.",
                "Asignar un rol claro dentro del grupo cooperativo que potencie sus fortalezas."
            ],
            evaluationAlternative: "Evaluar mediante rúbrica simplificada centrada en el proceso en lugar de penalizar el formato formal de entrega.",
            confidenceNote: reason,
            appearsToBeRulesFallback: true
        )
    }

    private func fallbackPlannerSequence(from input: PlannerSequenceInput, reason: String) -> PlannerSequenceDraft {
        PlannerSequenceDraft(
            unitTitle: input.unitTitle,
            sessionNumber: input.sessionIndex,
            sessionFocus: "Desarrollo competencial de la sesión \(input.sessionIndex)",
            steps: [
                PlannerSessionStepDraft(
                    phase: "Activación / Conexión inicial",
                    estimatedMinutes: 10,
                    activityDescription: "Recordatorio de la sesión anterior, presentación del reto del día y activación de conocimientos previos mediante preguntas breves.",
                    organizationTips: "Gran grupo en semicírculo.",
                    materialNeeds: ["Pizarra / soporte visual"]
                ),
                PlannerSessionStepDraft(
                    phase: "Desarrollo competencial",
                    estimatedMinutes: 35,
                    activityDescription: "Práctica guiada y autónoma de la tarea principal de la unidad '\(input.unitTitle)', aplicando las estrategias trabajadas.",
                    organizationTips: "Parejas o pequeños grupos cooperativos de 3-4 alumnos.",
                    materialNeeds: ["Fichas o material específico de la tarea"]
                ),
                PlannerSessionStepDraft(
                    phase: "Reflexión y cierre evaluativo",
                    estimatedMinutes: 10,
                    activityDescription: "Puesta en común de hallazgos, autoevaluación rápida con ticket de salida y recogida de materiales.",
                    organizationTips: "Gran grupo.",
                    materialNeeds: ["Cuaderno de clase o ticket de salida"]
                )
            ],
            evaluationStrategy: "Observación directa durante la fase de desarrollo y registro de evidencias formativas.",
            confidenceNote: reason,
            appearsToBeRulesFallback: true
        )
    }

    private func fallbackMetacognitionPrompts(from input: MetacognitionPromptsInput, reason: String) -> MetacognitionPromptsDraft {
        MetacognitionPromptsDraft(
            contextTitle: input.topicOrTask,
            selfEvaluationPrompts: [
                "¿Qué parte de la tarea me ha resultado más fácil y en cuál he necesitado más ayuda?",
                "¿Qué estrategia he utilizado hoy para resolver el reto planteado?"
            ],
            peerEvaluationPrompts: [
                "¿Qué aspecto positivo destacarías de la aportación de tu compañero al equipo?",
                "¿Qué sugerencia constructiva le harías para mejorar en la próxima sesión?"
            ],
            exitTicketQuestion: "Escribe en una sola frase lo más valioso que has aprendido hoy y cómo lo usarías en otra situación.",
            confidenceNote: reason,
            appearsToBeRulesFallback: true
        )
    }
}

// MARK: - Generable Types for Foundation Models

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedRubricLevelDraft {
    let levelIndex: Int
    let levelName: String
    let descriptor: String
    let scoreSuggestion: Double
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedRubricCriterionDraft {
    let criterionTitle: String
    let description: String
    let weight: Double
    let levels: [GeneratedRubricLevelDraft]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedRubricDraft {
    let title: String
    let criteria: [GeneratedRubricCriterionDraft]
    let teacherTips: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedDUAAdaptationDraft {
    let representationStrategies: [String]
    let actionAndExpressionStrategies: [String]
    let engagementStrategies: [String]
    let evaluationAlternative: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedPlannerSessionStepDraft {
    let phase: String
    let estimatedMinutes: Int
    let activityDescription: String
    let organizationTips: String
    let materialNeeds: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedPlannerSequenceDraft {
    let sessionFocus: String
    let steps: [GeneratedPlannerSessionStepDraft]
    let evaluationStrategy: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedMetacognitionPromptsDraft {
    let selfEvaluationPrompts: [String]
    let peerEvaluationPrompts: [String]
    let exitTicketQuestion: String
}
#endif
