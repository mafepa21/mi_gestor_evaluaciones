import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ajusta el guion de una sesión a lo que el docente cuenta que hizo, con el modelo del dispositivo.
/// Una sesión de modelo nueva por llamada (una por bloque y otra para lo añadido),
/// como el kit de clase: el contexto del modelo local es corto.
@MainActor
final class AppleFoundationActualEditService {
    var isAvailable: Bool {
        AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available
    }

    /// `nil` si la IA no está disponible o falla: el bloque se queda como en el plan.
    func adjust(_ block: PlannerActualEditInput.Block, note: String, in input: PlannerActualEditInput) async -> PlannerActualEditNormalizer.BlockResult? {
        guard isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await LanguageModelSession(instructions: Self.instructions).respond(
                    to: Self.blockPrompt(for: block, note: note, in: input),
                    generating: GeneratedActualBlock.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                let content = response.content
                return PlannerActualEditNormalizer.block(
                    planned: block,
                    wasSkipped: content.wasSkipped,
                    changed: content.changed,
                    detail: content.detail,
                    minutes: content.minutes,
                    changeNote: content.changeNote
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
            }
        }
        #endif
        return nil
    }

    /// Actividades que el docente hizo y no estaban en el plan. Vacío si no hay o si falla.
    func addedActivities(note: String, in input: PlannerActualEditInput) async -> [PlannerActualEdit.Added] {
        guard isAvailable else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await LanguageModelSession(instructions: Self.instructions).respond(
                    to: Self.additionsPrompt(note: note, in: input),
                    generating: GeneratedActualAdditions.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                let planned = Set(input.blocks.map { PlannerActualEditNormalizer.normalized($0.title) })
                return response.content.added
                    .compactMap { PlannerActualEditNormalizer.added(title: $0.title, minutes: $0.minutes, detail: $0.detail, afterTitle: $0.afterTitle) }
                    .filter { !planned.contains(PlannerActualEditNormalizer.normalized($0.title)) }
                    .prefix(3)
                    .map { $0 }
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
            }
        }
        #endif
        return []
    }

    // MARK: Prompts

    static let instructions = """
    Eres un asistente de un docente de secundaria. El docente cuenta qué cambió al dar una sesión que ya tenía planificada.
    Solo registras lo que el docente dice. No inventes cambios, materiales ni alumnado. Si la nota no habla de algo, ese algo no cambió.
    Escribe en español de España, en frases cortas y con el mismo estilo que el plan.
    """

    static func blockPrompt(for block: PlannerActualEditInput.Block, note: String, in input: PlannerActualEditInput) -> String {
        var lines = ["Sesión: \(input.title)", "Tareas del plan: \(input.blocks.map(\.title).joined(separator: " / "))"]
        lines.append("Nota del docente: \(note)")
        lines.append("Tarea que revisas: \(block.title)")
        if let minutes = block.minutes { lines.append("Duración en el plan: \(minutes) min") }
        if !block.detail.isEmpty { lines.append("Texto del plan: \(PlannerClassKitInput.shortened(block.detail))") }
        lines.append("""
        Devuelve:
        - wasSkipped: true solo si la nota dice que esta tarea no se hizo o se quitó.
        - changed: true solo si la nota cambia algo de esta tarea concreta.
        - detail: el texto de la tarea tal como se hizo. Si no cambia, copia el texto del plan.
        - minutes: los minutos que duró si la nota los cambia; 0 si no.
        - changeNote: qué cambió, en menos de 10 palabras. Vacío si no cambia.
        """)
        return lines.joined(separator: "\n")
    }

    static func additionsPrompt(note: String, in input: PlannerActualEditInput) -> String {
        """
        Sesión: \(input.title)
        Tareas del plan: \(input.blocks.map(\.title).joined(separator: " / "))
        Nota del docente: \(note)
        Devuelve en added solo las actividades que el docente hizo y que no son ninguna tarea del plan (máximo 3; lista vacía si no hay):
        - title: nombre corto.
        - minutes: minutos si la nota los dice; 0 si no.
        - detail: qué se hizo, en 1-2 frases.
        - afterTitle: el título exacto de la tarea del plan tras la que se hizo; vacío si no se sabe.
        """
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedActualBlock {
    let wasSkipped: Bool
    let changed: Bool
    let detail: String
    let minutes: Int
    let changeNote: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedActualActivity {
    let title: String
    let minutes: Int
    let detail: String
    let afterTitle: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedActualAdditions {
    let added: [GeneratedActualActivity]
}
#endif
