import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Genera el apoyo de aula del kit de clase con el modelo del dispositivo.
/// Una sesión de modelo nueva por llamada: el contexto del modelo local es corto y
/// acumular tareas en la misma conversación lo desbordaría.
@MainActor
final class AppleFoundationClassKitService {
    var isAvailable: Bool {
        AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available
    }

    /// `nil` si la IA no está disponible o falla: el kit sigue sin ese apoyo.
    func generateHeader(for input: PlannerClassKitInput) async -> PlannerClassKitHeaderDraft? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await LanguageModelSession(instructions: Self.instructions).respond(
                    to: Self.headerPrompt(for: input),
                    generating: GeneratedClassKitHeader.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.3)
                )
                let content = response.content
                return PlannerClassKitNormalizer.header(
                    boardWords: content.boardWords,
                    sessionCue: content.sessionCue,
                    cueGesture: content.cueGesture,
                    closingQuestion: content.closingQuestion,
                    closingSentence: content.closingSentence
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
            }
        }
        #endif
        return nil
    }

    func generateCoaching(for task: PlannerClassKitInput.Task, in input: PlannerClassKitInput) async -> PlannerClassKitCoaching? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await LanguageModelSession(instructions: Self.instructions).respond(
                    to: Self.taskPrompt(for: task, in: input),
                    generating: GeneratedClassKitTask.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.3)
                )
                let content = response.content
                let card = task.isMainMoment
                    ? PlannerClassKitCard(
                        title: content.cardTitle,
                        steps: content.cardSteps,
                        points: content.cardPoints,
                        swap: content.cardSwap,
                        cue: content.oneCue
                    )
                    : nil
                return PlannerClassKitNormalizer.coaching(
                    show: content.show,
                    say: content.say,
                    rule: content.scoringRule,
                    checks: content.checks.map { ($0.question, $0.expectedAnswer) },
                    cue: content.oneCue,
                    card: card
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
            }
        }
        #endif
        return nil
    }

    // MARK: Prompts

    static let instructions = """
    Eres un docente experto de Educación Física en un programa bilingüe (CLIL) de secundaria.
    Conviertes tareas ya diseñadas en apoyo para darlas en clase. No inventes tareas nuevas ni cambies su organización.
    Las explicaciones para el docente van en español de España. Lo que se dice al alumnado y las tarjetas van en inglés A2: frases cortas, imperativas, de menos de 10 palabras.
    Nunca uses la pregunta "Do you understand?".
    """

    static func headerPrompt(for input: PlannerClassKitInput) -> String {
        var lines = ["Sesión: \(input.title)"]
        if !input.objective.isEmpty { lines.append("Objetivo: \(input.objective)") }
        lines.append("Tareas:")
        lines += input.tasks.map { "- \($0.title)" }
        lines.append("""
        Devuelve:
        - boardWords: 3 palabras clave en inglés para la pizarra.
        - sessionCue: una sola corrección en inglés para toda la sesión (2-4 palabras).
        - cueGesture: el gesto que acompaña a esa corrección, en español.
        - closingQuestion: una pregunta de cierre en inglés, muy corta.
        - closingSentence: una frase en inglés para completar, con el hueco como ______ y la respuesta entre paréntesis.
        """)
        return lines.joined(separator: "\n")
    }

    static func taskPrompt(for task: PlannerClassKitInput.Task, in input: PlannerClassKitInput) -> String {
        var lines = ["Sesión: \(input.title)", "Tarea: \(task.title)"]
        if let minutes = task.minutes { lines.append("Duración: \(minutes) min") }
        if !task.detail.isEmpty { lines.append("Descripción del plan: \(task.detail)") }
        if let clil = task.clil, !clil.isEmpty { lines.append("Consigna CLIL del plan: \(clil)") }
        if !input.clilCues.isEmpty {
            lines.append("Frases del plan que puedes reutilizar: \(input.clilCues.prefix(4).joined(separator: " / "))")
        }
        lines.append("""
        Devuelve:
        - show: cómo hace el docente la demostración en silencio (español, 1-2 frases).
        - say: exactamente 3 frases en inglés que explican la tarea.
        - scoringRule: 1-3 reglas en español de puntuación o diana que obligan a ejecutar bien.
        - checks: 2-3 preguntas en inglés para comprobar que lo han entendido, con la respuesta esperada.
        - oneCue: una sola corrección en inglés (2-4 palabras).
        - cardTitle, cardSteps (3 pasos), cardPoints, cardSwap: tarjeta para imprimir, en inglés.
        """)
        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedClassKitHeader {
    let boardWords: [String]
    let sessionCue: String
    let cueGesture: String
    let closingQuestion: String
    let closingSentence: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedClassKitCheck {
    let question: String
    let expectedAnswer: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedClassKitTask {
    let show: String
    let say: [String]
    let scoringRule: [String]
    let checks: [GeneratedClassKitCheck]
    let oneCue: String
    let cardTitle: String
    let cardSteps: [String]
    let cardPoints: String
    let cardSwap: String
}
#endif
