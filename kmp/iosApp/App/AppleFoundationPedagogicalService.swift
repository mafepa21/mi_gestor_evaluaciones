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

struct RubricSelfAssessmentCriterionLevelInput: Hashable, Sendable, Codable {
    let levelId: Int64
    let position: Int
    let name: String
    let points: Int
    let descriptor: String
}

struct RubricSelfAssessmentCriterionInput: Hashable, Sendable, Codable {
    let criterionId: Int64
    let position: Int
    let title: String
    let weight: Double
    let levels: [RubricSelfAssessmentCriterionLevelInput]
}

struct RubricSelfAssessmentAnswerInput: Hashable, Sendable, Codable {
    let itemKey: String
    let questionTitle: String
    let helpText: String?
    let scaleValue: Int?
    let textResponse: String?
    let boolResponse: Bool?
}

struct RubricSelfAssessmentMappingInput: Hashable, Sendable {
    let rubricTitle: String
    let sourceInstrumentTitle: String
    let studentName: String
    let criteria: [RubricSelfAssessmentCriterionInput]
    let answers: [RubricSelfAssessmentAnswerInput]
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

struct RubricSelfAssessmentCriterionSuggestion: Codable, Hashable, Sendable, Identifiable {
    var id: Int64 { criterionId }
    let criterionId: Int64
    let suggestedLevelId: Int64
    let suggestedPosition: Int
    let rationale: String
    let evidenceExcerpt: String
    let confidence: String
}

struct RubricSelfAssessmentMappingDraft: Codable, Hashable, Sendable {
    let rubricTitle: String
    let sourceInstrumentTitle: String
    let studentName: String
    let suggestions: [RubricSelfAssessmentCriterionSuggestion]
    let confidenceNote: String
    let appearsToBeRulesFallback: Bool

    init(
        rubricTitle: String,
        sourceInstrumentTitle: String,
        studentName: String,
        suggestions: [RubricSelfAssessmentCriterionSuggestion],
        confidenceNote: String,
        appearsToBeRulesFallback: Bool = false
    ) {
        self.rubricTitle = AppleAIOutputNormalizer.nonEmpty(rubricTitle, fallback: "Rúbrica")
        self.sourceInstrumentTitle = AppleAIOutputNormalizer.nonEmpty(sourceInstrumentTitle, fallback: "Autoevaluación")
        self.studentName = AppleAIOutputNormalizer.nonEmpty(studentName, fallback: "Alumno")
        self.suggestions = suggestions
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(confidenceNote, fallback: "Mapeo revisable generado localmente.")
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
    private var selfAssessmentMappingSessionStorage: Any?
    #endif

    func prewarm() {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            _ = consumeRubricSession()
            _ = consumeDUASession()
            _ = consumePlannerSession()
            _ = consumeMetacognitionSession()
            _ = consumeSelfAssessmentMappingSession()
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

    // MARK: 5. Mapeo universal de Autoevaluación a Rúbrica

    func generateRubricSelfAssessmentMapping(from input: RubricSelfAssessmentMappingInput) async throws -> RubricSelfAssessmentMappingDraft {
        guard !input.criteria.isEmpty, !input.answers.isEmpty else {
            return fallbackRubricSelfAssessmentMapping(from: input, reason: "Faltan criterios o respuestas en la autoevaluación.")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackRubricSelfAssessmentMapping(from: input, reason: "Sugerencias generadas con emparejamiento determinista local.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeSelfAssessmentMappingSession().respond(
                    to: selfAssessmentMappingPrompt(from: input),
                    generating: GeneratedRubricSelfAssessmentMappingDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.1)
                )
                let fallbackByCriterion = Dictionary(
                    uniqueKeysWithValues: fallbackRubricSelfAssessmentMapping(from: input, reason: "").suggestions.map { ($0.criterionId, $0) }
                )
                let suggestions: [RubricSelfAssessmentCriterionSuggestion] = input.criteria.compactMap { criterion in
                    guard !criterion.levels.isEmpty else { return nil }
                    let aiItem = response.content.suggestions.first { $0.criterionPosition == criterion.position }
                    if let aiItem {
                        let clampedPos = min(max(aiItem.suggestedLevelPosition, 1), criterion.levels.count)
                        let chosenLevel = criterion.levels.first(where: { $0.position == clampedPos }) ?? criterion.levels[clampedPos - 1]
                        return RubricSelfAssessmentCriterionSuggestion(
                            criterionId: criterion.criterionId,
                            suggestedLevelId: chosenLevel.levelId,
                            suggestedPosition: chosenLevel.position,
                            rationale: AppleAIOutputNormalizer.nonEmpty(aiItem.rationale, fallback: "Nivel \(chosenLevel.position) coherente con la autoevaluación."),
                            evidenceExcerpt: AppleAIOutputNormalizer.nonEmpty(aiItem.evidenceExcerpt, fallback: fallbackByCriterion[criterion.criterionId]?.evidenceExcerpt ?? ""),
                            confidence: AppleAIOutputNormalizer.nonEmpty(aiItem.confidence, fallback: "Alta")
                        )
                    }
                    return fallbackByCriterion[criterion.criterionId]
                }
                return RubricSelfAssessmentMappingDraft(
                    rubricTitle: input.rubricTitle,
                    sourceInstrumentTitle: input.sourceInstrumentTitle,
                    studentName: input.studentName,
                    suggestions: suggestions,
                    confidenceNote: "Niveles sugeridos con Apple Intelligence a partir de la autoevaluación del alumno.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackRubricSelfAssessmentMapping(from: input, reason: "Sugerencias generadas con emparejamiento determinista local.")
            }
        }
        #endif

        return fallbackRubricSelfAssessmentMapping(from: input, reason: "Sugerencias generadas con emparejamiento determinista local.")
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

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeSelfAssessmentMappingSession() -> LanguageModelSession {
        if let session = selfAssessmentMappingSessionStorage as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            instructions: """
            Eres un asistente docente experto en evaluación formativa por rúbricas.
            Tu tarea es triangular las respuestas de autoevaluación de un alumno (combinando sus escalas numéricas con sus respuestas a preguntas cortas o abiertas de reflexión)
            y sugerir para cada criterio de la rúbrica docente el nivel de logro más coherente con los descriptores de la rúbrica.
            REGLA CRÍTICA: NO te limites a copiar el número de la escala que el alumno se puso a sí mismo.
            Contrasta siempre la escala con las preguntas cortas de reflexión asociadas al criterio:
            - Si las preguntas cortas están en blanco o con respuestas superficiales de 1-2 palabras sin justificar lo que piden los niveles altos (identificar aciertos/errores, aportar datos/tiempos, proponer mejoras), baja el nivel sugerido respecto a la escala marcada.
            - Si el alumno aporta respuestas cortas detalladas (con datos, causas, funciones claras o propuestas de mejora), sube el nivel sugerido aunque haya sido modesto en la escala.
            No emitas juicios clínicos ni diagnósticos. Cita de forma concisa la combinación de escala y respuestas cortas en tu justificación.
            """
        )
        selfAssessmentMappingSessionStorage = session
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

    private func selfAssessmentMappingPrompt(from input: RubricSelfAssessmentMappingInput) -> String {
        let criteriaLines = input.criteria.map { criterion in
            let levelsText = criterion.levels.map { level in
                "  • Nivel \(level.position) (\(level.name), \(level.points) pt): \(level.descriptor)"
            }.joined(separator: "\n")
            return "Criterio \(criterion.position): \(criterion.title)\n\(levelsText)"
        }.joined(separator: "\n\n")

        let scaleItems = input.answers.filter { $0.itemKey.hasPrefix("rub_") || $0.scaleValue != nil }
        let reflectionItems = input.answers.filter { !$0.itemKey.hasPrefix("rub_") && $0.scaleValue == nil }

        let scaleLines = scaleItems.isEmpty
            ? "  (Ningún indicador de escala)"
            : scaleItems.map { ans in
                let valText = ans.scaleValue.map { "Nivel marcado: \($0)" } ?? "SIN MARCAR"
                return "- [\(ans.itemKey)] \(ans.questionTitle) -> \(valText)"
            }.joined(separator: "\n")

        let reflectionLines = reflectionItems.isEmpty
            ? "  (Ninguna pregunta corta de reflexión)"
            : reflectionItems.map { ans in
                let trimmed = ans.textResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty {
                    return "- [\(ans.itemKey)] \(ans.questionTitle) -> Respuesta corta: «\(trimmed)»"
                } else if let boolVal = ans.boolResponse {
                    return "- [\(ans.itemKey)] \(ans.questionTitle) -> Casilla: \(boolVal ? "Sí" : "No")"
                } else {
                    return "- [\(ans.itemKey)] \(ans.questionTitle) -> SIN RESPUESTA (en blanco)"
                }
            }.joined(separator: "\n")

        return """
        Mapea y triangula las respuestas de la autoevaluación del alumno a los niveles de la rúbrica docente.
        Rúbrica destino: \(input.rubricTitle)
        Instrumento origen: \(input.sourceInstrumentTitle)
        Alumno/a: \(input.studentName)

        CRITERIOS Y DESCRIPTORES DE LA RÚBRICA:
        \(criteriaLines)

        1) INDICADORES DE ESCALA MARCADOS POR EL ALUMNO:
        \(scaleLines)

        2) PREGUNTAS CORTAS / ABIERTAS DE REFLEXIÓN Y DATOS (EVIDENCIA CUALITATIVA/CUANTITATIVA):
        \(reflectionLines)

        Reglas de evaluación:
        - Devuelve una sugerencia por cada criterio de la rúbrica (criterionPosition 1 a \(input.criteria.count)).
        - NO copies directamente la escala 1-4 sin verificar las preguntas cortas de reflexión (sección 2).
        - Si el alumno se puntúa alto en la escala (ej. 3 o 4) pero dejó SIN RESPUESTA las preguntas cortas vinculadas a ese criterio o respondió con 1-2 palabras sin justificar lo que exige el descriptor (identificar acierto y error, aportar tiempos/datos de progreso, explicar causas o proponer mejoras), REBAJA suggestedLevelPosition en al menos 1 nivel (o limítalo a 2).
        - Si el alumno se puntúa bajo o medio en la escala pero en las preguntas cortas aporta evidencias concretas (datos/segundos, causas tácticas, rol del equipo, propuestas de mejora o ejemplos claros), SUBE suggestedLevelPosition al nivel cuyos descriptores queden demostrados por sus respuestas cortas.
        - En rationale explica en 1 frase breve cómo influyeron tanto la escala como las preguntas cortas (o su ausencia) en el nivel sugerido.
        - En evidenceExcerpt combina el valor de la escala con un extracto conciso de las respuestas cortas asociadas (o indica cuántas quedaron en blanco).
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

    func fallbackRubricSelfAssessmentMapping(
        from input: RubricSelfAssessmentMappingInput,
        reason: String
    ) -> RubricSelfAssessmentMappingDraft {
        let scaleAnswers = input.answers.filter { $0.itemKey.hasPrefix("rub_") || $0.scaleValue != nil }
        let reflectionQuestions = input.answers.filter { !$0.itemKey.hasPrefix("rub_") && $0.scaleValue == nil }

        let criterionTokenSets: [Set<String>] = input.criteria.map { criterion in
            Self.enrichedSemanticTokens(
                from: criterion.title + " " + criterion.levels.map(\.descriptor).joined(separator: " ")
            )
        }

        // Agrupar cada pregunta corta/abierta en el criterio de la rúbrica con mayor afinidad semántica
        var relatedReflectionsByCriterionIndex: [Int: [RubricSelfAssessmentAnswerInput]] = [:]
        if !input.criteria.isEmpty {
            for (qIdx, question) in reflectionQuestions.enumerated() {
                let qTokens = Self.enrichedSemanticTokens(
                    from: question.questionTitle + " " + (question.helpText ?? "") + " " + (question.textResponse ?? "")
                )
                var bestCriterionIndex = 0
                var bestOverlap = 0
                for (cIdx, cTokens) in criterionTokenSets.enumerated() {
                    let overlap = cTokens.intersection(qTokens).count
                    if overlap > bestOverlap {
                        bestOverlap = overlap
                        bestCriterionIndex = cIdx
                    }
                }
                if bestOverlap == 0 {
                    // Reparto proporcional cuando no hay solapamiento léxico directo
                    let proportionalIdx = Int(
                        (Double(qIdx) / Double(max(1, reflectionQuestions.count))) * Double(input.criteria.count)
                    )
                    bestCriterionIndex = min(max(proportionalIdx, 0), input.criteria.count - 1)
                }
                relatedReflectionsByCriterionIndex[bestCriterionIndex, default: []].append(question)
            }
        }

        let suggestions: [RubricSelfAssessmentCriterionSuggestion] = input.criteria.enumerated().compactMap { index, criterion in
            guard !criterion.levels.isEmpty else { return nil }
            let criterionTokens = criterionTokenSets[index]

            // 1. Buscar mejor respuesta de escala por similitud semántica de tokens o posición rub_<n>
            var bestScaleAnswer: RubricSelfAssessmentAnswerInput?
            var bestScaleScore = -1
            for answer in scaleAnswers {
                guard answer.scaleValue != nil else { continue }
                let answerTokens = Self.enrichedSemanticTokens(from: answer.questionTitle + " " + (answer.helpText ?? ""))
                let overlap = criterionTokens.intersection(answerTokens).count
                let positionalBonus = (answer.itemKey == "rub_\(index + 1)" || answer.itemKey == "rub_\(criterion.position)") ? 2 : 0
                let totalScore = overlap * 3 + positionalBonus
                if totalScore > bestScaleScore {
                    bestScaleScore = totalScore
                    bestScaleAnswer = answer
                }
            }
            if bestScaleAnswer == nil, scaleAnswers.indices.contains(index), scaleAnswers[index].scaleValue != nil {
                bestScaleAnswer = scaleAnswers[index]
            }

            // 2. Analizar las preguntas cortas / de reflexión vinculadas a este criterio
            let relatedQuestions = relatedReflectionsByCriterionIndex[index] ?? []
            let answeredReflections: [(question: RubricSelfAssessmentAnswerInput, text: String)] = relatedQuestions.compactMap { q in
                if let text = q.textResponse?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return (q, text)
                }
                if let boolVal = q.boolResponse {
                    return (q, boolVal ? "Sí" : "No")
                }
                return nil
            }

            let maxPosition = criterion.levels.count
            let scalePosition: Int? = bestScaleAnswer?.scaleValue.map { rawScale in
                if maxPosition == 4 {
                    return min(max(rawScale, 1), 4)
                } else {
                    let normalized = Double(min(max(rawScale, 1), 4) - 1) / 3.0
                    return min(max(Int(round(normalized * Double(maxPosition - 1))) + 1, 1), maxPosition)
                }
            }

            // 3. Evaluar nivel de evidencia aportado por las preguntas cortas (1..maxPosition)
            let openEvaluation = Self.evaluateOpenReflectionEvidence(
                answeredReflections: answeredReflections,
                totalRelatedCount: relatedQuestions.count,
                criterion: criterion
            )

            // 4. Combinar escala + preguntas cortas para que las respuestas breves influyan realmente en el resultado
            var resolvedPosition: Int
            var rationaleParts: [String] = []
            var excerptParts: [String] = []

            if let scaleAns = bestScaleAnswer, let rawScale = scaleAns.scaleValue, let sPos = scalePosition {
                excerptParts.append("\(scaleAns.questionTitle): \(rawScale)/4")

                if !relatedQuestions.isEmpty {
                    if answeredReflections.isEmpty {
                        // Marcó escala pero dejó en blanco las preguntas cortas de reflexión asociadas
                        if sPos >= 3 {
                            resolvedPosition = max(1, min(2, sPos - 1))
                            rationaleParts.append(
                                "Marcó \(rawScale)/4 en «\(scaleAns.questionTitle)», pero dejó sin responder las \(relatedQuestions.count) preguntas cortas asociadas (se ajusta a nivel \(resolvedPosition))"
                            )
                        } else {
                            resolvedPosition = sPos
                            rationaleParts.append(
                                "Marcó \(rawScale)/4 en «\(scaleAns.questionTitle)» (sin respuestas en las preguntas cortas asociadas)"
                            )
                        }
                        excerptParts.append("Preguntas cortas: 0/\(relatedQuestions.count) respondidas")
                    } else if let openPos = openEvaluation.suggestedLevel {
                        // Combinar escala (45%) + evidencia de preguntas cortas (55%)
                        let blended = Double(sPos) * 0.45 + Double(openPos) * 0.55
                        resolvedPosition = min(max(Int(round(blended)), 1), maxPosition)

                        if resolvedPosition > sPos {
                            rationaleParts.append(
                                "Subido de \(sPos) a \(resolvedPosition): marcó \(rawScale)/4 en escala y aportó evidencia sólida en \(answeredReflections.count)/\(relatedQuestions.count) preguntas cortas (\(openEvaluation.qualitySummary))"
                            )
                        } else if resolvedPosition < sPos {
                            rationaleParts.append(
                                "Ajustado de \(sPos) a \(resolvedPosition): marcó \(rawScale)/4 en escala, pero sus respuestas cortas (\(answeredReflections.count)/\(relatedQuestions.count)) son breves o incompletas para el descriptor superior"
                            )
                        } else {
                            rationaleParts.append(
                                "Nivel \(resolvedPosition) confirmado: marcó \(rawScale)/4 en escala y lo respaldó en \(answeredReflections.count)/\(relatedQuestions.count) preguntas cortas (\(openEvaluation.qualitySummary))"
                            )
                        }
                    } else {
                        resolvedPosition = sPos
                        rationaleParts.append("Marcó nivel \(rawScale) en «\(scaleAns.questionTitle)»")
                    }
                } else {
                    // Formulario sin preguntas cortas para este criterio
                    resolvedPosition = sPos
                    rationaleParts.append("Marcó nivel \(rawScale) en «\(scaleAns.questionTitle)»")
                }
            } else if let openPos = openEvaluation.suggestedLevel, !answeredReflections.isEmpty {
                resolvedPosition = openPos
                rationaleParts.append(
                    "Inferido de \(answeredReflections.count)/\(max(1, relatedQuestions.count)) preguntas cortas (\(openEvaluation.qualitySummary))"
                )
            } else {
                let anyPositiveBool = input.answers.contains { $0.boolResponse == true }
                resolvedPosition = anyPositiveBool ? max(1, maxPosition - 1) : 1
                rationaleParts.append("Sin escala ni respuestas cortas suficientes para este criterio")
            }

            if !answeredReflections.isEmpty {
                let snippets = answeredReflections.prefix(2).map { item -> String in
                    let clipped = item.text.count > 75 ? String(item.text.prefix(75)) + "…" : item.text
                    return "«\(clipped)»"
                }.joined(separator: " / ")
                excerptParts.append("Reflexión (\(answeredReflections.count)/\(relatedQuestions.count)): \(snippets)")
            }

            let chosenLevel = criterion.levels.first(where: { $0.position == resolvedPosition })
                ?? criterion.levels[min(max(resolvedPosition - 1, 0), criterion.levels.count - 1)]

            let rationale = rationaleParts.isEmpty
                ? "Nivel \(chosenLevel.position) (\(chosenLevel.name)) según autoevaluación."
                : rationaleParts.joined(separator: " ") + "."
            let excerpt = excerptParts.isEmpty
                ? "Respuesta registrada en \(input.sourceInstrumentTitle)"
                : excerptParts.joined(separator: " · ")

            let confidence: String = {
                if bestScaleAnswer != nil && !answeredReflections.isEmpty {
                    return "Alta"
                } else if bestScaleAnswer != nil || !answeredReflections.isEmpty {
                    return "Media"
                } else {
                    return "Baja"
                }
            }()

            return RubricSelfAssessmentCriterionSuggestion(
                criterionId: criterion.criterionId,
                suggestedLevelId: chosenLevel.levelId,
                suggestedPosition: chosenLevel.position,
                rationale: rationale,
                evidenceExcerpt: excerpt,
                confidence: confidence
            )
        }

        return RubricSelfAssessmentMappingDraft(
            rubricTitle: input.rubricTitle,
            sourceInstrumentTitle: input.sourceInstrumentTitle,
            studentName: input.studentName,
            suggestions: suggestions,
            confidenceNote: reason.isEmpty ? "Sugerencias generadas triangulando escala y preguntas cortas." : reason,
            appearsToBeRulesFallback: true
        )
    }

    private static func evaluateOpenReflectionEvidence(
        answeredReflections: [(question: RubricSelfAssessmentAnswerInput, text: String)],
        totalRelatedCount: Int,
        criterion: RubricSelfAssessmentCriterionInput
    ) -> (suggestedLevel: Int?, qualitySummary: String) {
        guard !answeredReflections.isEmpty else {
            return (nil, "sin respuestas cortas")
        }
        let maxPosition = criterion.levels.count
        let combinedText = answeredReflections.map(\.text).joined(separator: " ")
        let words = combinedText.split(whereSeparator: \.isWhitespace)
        let totalWords = words.count
        let avgWordsPerAnswered = Double(totalWords) / Double(answeredReflections.count)
        let completionRatio = totalRelatedCount > 0
            ? Double(answeredReflections.count) / Double(totalRelatedCount)
            : 1.0

        let folded = combinedText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()

        // Indicadores cualitativos y cuantitativos en las respuestas cortas
        let hasNumericData = combinedText.rangeOfCharacter(from: .decimalDigits) != nil
        let causalConnectors = ["porque", "para", "debido", "gracias", "cuando", "asi", "logre", "funciono", "pase", "espacio", "desmarque"]
        let improvementMarkers = ["mejorar", "proxima", "distinto", "cambiar", "solucion", "propuse", "consejo", "ayudar", "corregir", "acept"]
        let hasCausalAnalysis = causalConnectors.contains { folded.contains($0) }
        let hasImprovementProposal = improvementMarkers.contains { folded.contains($0) }

        // Solapamiento con los descriptores de los niveles superiores (3 y 4)
        let responseTokens = enrichedSemanticTokens(from: combinedText)
        var bestDescriptorPos = 2
        var bestOverlap = 0
        for level in criterion.levels {
            let descTokens = enrichedSemanticTokens(from: level.descriptor)
            let overlap = responseTokens.intersection(descTokens).count
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestDescriptorPos = level.position
            }
        }

        // Puntuación continua 1.0 .. 4.0 según completitud, profundidad y evidencias concretas
        var score4Scale = 1.6
        if completionRatio >= 0.85 {
            score4Scale += 0.75
        } else if completionRatio >= 0.5 {
            score4Scale += 0.35
        } else {
            score4Scale -= 0.25
        }

        if avgWordsPerAnswered >= 10 || totalWords >= 22 {
            score4Scale += 0.85
        } else if avgWordsPerAnswered >= 5 || totalWords >= 10 {
            score4Scale += 0.45
        } else if totalWords <= 3 && !hasNumericData {
            score4Scale -= 0.45
        }

        if hasNumericData {
            score4Scale += 0.45
        }
        if hasCausalAnalysis {
            score4Scale += 0.35
        }
        if hasImprovementProposal {
            score4Scale += 0.45
        }
        if bestOverlap >= 2 && bestDescriptorPos >= 3 {
            score4Scale += 0.3
        }

        let clamped4 = min(max(score4Scale, 1.0), 4.0)
        let mappedPos: Int
        if maxPosition == 4 {
            mappedPos = min(max(Int(round(clamped4)), 1), 4)
        } else {
            let normalized = (clamped4 - 1.0) / 3.0
            mappedPos = min(max(Int(round(normalized * Double(maxPosition - 1))) + 1, 1), maxPosition)
        }

        var traits: [String] = []
        if hasNumericData { traits.append("datos concretos") }
        if hasCausalAnalysis { traits.append("análisis causal") }
        if hasImprovementProposal { traits.append("propuesta de mejora") }
        if traits.isEmpty {
            traits.append(avgWordsPerAnswered >= 6 ? "explicación clara" : "respuesta breve")
        }

        return (mappedPos, traits.joined(separator: ", "))
    }

    private static func enrichedSemanticTokens(from text: String) -> Set<String> {
        var tokens = normalizedTokens(from: text)
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()

        // Expansión de familias temáticas frecuentes en autoevaluaciones y rúbricas
        if folded.contains("juego") || folded.contains("jugada") || folded.contains("tactic") || folded.contains("error") || folded.contains("acierto") || folded.contains("partido") {
            tokens.formUnion(["juego", "tactico", "actuacion", "error", "acierto"])
        }
        if folded.contains("equipo") || folded.contains("estrategia") || folded.contains("funcion") || folded.contains("plan") || folded.contains("atac") || folded.contains("defend") || folded.contains("superioridad") {
            tokens.formUnion(["equipo", "estrategia", "colectiva", "funcion"])
        }
        if folded.contains("progreso") || folded.contains("tiempo") || folded.contains("slalom") || folded.contains("sesion") || folded.contains("mejorado") || folded.contains("charla") || folded.contains("companero") || folded.contains("datos") {
            tokens.formUnion(["progreso", "datos", "analisis", "participa", "charla"])
        }
        if folded.contains("deporte") || folded.contains("valor") || folded.contains("desigualdad") || folded.contains("genero") || folded.contains("convivencia") {
            tokens.formUnion(["deporte", "valor", "desigualdad", "convivencia", "critica"])
        }
        return tokens
    }

    private static func normalizedTokens(from text: String) -> Set<String> {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let stopwords: Set<String> = [
            "el", "la", "los", "las", "de", "del", "en", "y", "o", "a", "con", "por", "para", "su", "sus",
            "un", "una", "al", "se", "no", "ni", "que", "es", "son", "como", "mas", "pero", "sobre", "entre"
        ]
        return Set(parts.filter { $0.count >= 3 && !stopwords.contains($0) })
    }
}

// MARK: - Generable Types for Foundation Models

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedRubricSelfAssessmentItemDraft {
    let criterionPosition: Int
    let suggestedLevelPosition: Int
    let rationale: String
    let evidenceExcerpt: String
    let confidence: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedRubricSelfAssessmentMappingDraft {
    let suggestions: [GeneratedRubricSelfAssessmentItemDraft]
}
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
