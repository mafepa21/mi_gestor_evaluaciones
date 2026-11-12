import Foundation

/// Kit de clase: la sesión del Planner convertida en apoyo para dar la clase
/// (guion corto en inglés, regla que corrige, preguntas de comprobación y tarjetas).
/// Las tareas salen siempre del plan; Apple Intelligence solo añade el apoyo de aula.
struct PlannerClassKitInput: Equatable {
    struct Task: Equatable, Identifiable {
        let id: String
        let title: String
        let phase: String
        let minutes: Int?
        let detail: String
        let clil: String?
        /// Solo las tareas del momento principal llevan tarjeta para imprimir.
        let isMainMoment: Bool
    }

    let title: String
    let meta: String
    let objective: String
    let setup: [String]
    let tasks: [Task]
    /// Frases CLIL del plan: la IA las reutiliza si encajan.
    let clilCues: [String]

    /// Texto máximo de cada tarea que se pasa al modelo del dispositivo (ventana corta).
    static let maxDetailLength = 1_200

    init(title: String, meta: String, objective: String, setup: [String], blocks: [PlannerSessionReviewBlock], clilCues: [String]) {
        self.title = title
        self.meta = meta
        self.objective = objective
        self.setup = setup
        self.clilCues = clilCues
        self.tasks = blocks.flatMap(\.steps)
            .filter { !$0.isCollection }
            .map { step in
                let moment = NarrativeSessionActivityCompactor.moment(for: step.phase.isEmpty ? step.title : step.phase)
                return Task(
                    id: step.activityKey,
                    title: step.title,
                    phase: step.phase,
                    minutes: step.minutes,
                    detail: Self.shortened(step.detail),
                    clil: step.clil,
                    isMainMoment: step.isMain || moment == .main
                )
            }
    }

    init(projection: PlannerSessionDetailProjection, title: String, meta: String) {
        self.init(
            title: title,
            meta: meta,
            objective: projection.reviewObjective,
            setup: projection.setupAll,
            blocks: projection.guideBlocks,
            clilCues: projection.clilChunks?.teacherCues ?? []
        )
    }

    static func shortened(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxDetailLength else { return trimmed }
        let cut = trimmed.prefix(maxDetailLength)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}

/// Lo que Apple Intelligence añade a la sesión entera.
struct PlannerClassKitHeaderDraft: Equatable {
    let boardWords: [String]
    let sessionCue: String
    let cueGesture: String
    let closingQuestion: String
    let closingSentence: String
}

/// Lo que Apple Intelligence añade a una tarea.
struct PlannerClassKitCoaching: Equatable {
    struct Check: Equatable {
        let question: String
        let answer: String
    }

    let show: String
    let say: [String]
    let rule: [String]
    let checks: [Check]
    let cue: String
    let card: PlannerClassKitCard?
}

struct PlannerClassKitCard: Equatable {
    let title: String
    let steps: [String]
    let points: String
    let swap: String
    let cue: String
}

struct PlannerClassKit: Equatable {
    struct Task: Equatable, Identifiable {
        let source: PlannerClassKitInput.Task
        var coaching: PlannerClassKitCoaching?
        var id: String { source.id }
    }

    let input: PlannerClassKitInput
    var header: PlannerClassKitHeaderDraft?
    var tasks: [Task]

    init(input: PlannerClassKitInput) {
        self.input = input
        self.header = nil
        self.tasks = input.tasks.map { Task(source: $0, coaching: nil) }
    }

    var cards: [PlannerClassKitCard] {
        tasks.filter(\.source.isMainMoment).compactMap { $0.coaching?.card }
    }

    /// Hay apoyo de IA en alguna parte del kit.
    var hasCoaching: Bool {
        header != nil || tasks.contains { $0.coaching != nil }
    }
}

/// Normaliza lo que devuelve el modelo: recorta listas y quita vacíos y repeticiones.
enum PlannerClassKitNormalizer {
    static let sayLimit = 3
    static let ruleLimit = 3
    static let checkLimit = 3
    static let boardWordLimit = 3
    static let cardStepLimit = 3

    static func header(boardWords: [String], sessionCue: String, cueGesture: String, closingQuestion: String, closingSentence: String) -> PlannerClassKitHeaderDraft {
        PlannerClassKitHeaderDraft(
            boardWords: list(boardWords.flatMap { $0.split(separator: "·").map(String.init) }, limit: boardWordLimit).map { $0.uppercased() },
            sessionCue: clean(sessionCue),
            cueGesture: clean(cueGesture),
            closingQuestion: clean(closingQuestion),
            closingSentence: clean(closingSentence)
        )
    }

    static func coaching(
        show: String,
        say: [String],
        rule: [String],
        checks: [(question: String, answer: String)],
        cue: String,
        card: PlannerClassKitCard?
    ) -> PlannerClassKitCoaching {
        let normalizedChecks = checks
            .map { PlannerClassKitCoaching.Check(question: clean($0.question), answer: clean($0.answer)) }
            .filter { !$0.question.isEmpty }
            // «Do you understand?» no comprueba nada.
            .filter { !$0.question.lowercased().contains("do you understand") }
        let normalizedCard = card.map {
            PlannerClassKitCard(
                title: clean($0.title).uppercased(),
                steps: list($0.steps, limit: cardStepLimit),
                points: clean($0.points),
                swap: clean($0.swap),
                cue: clean($0.cue).uppercased()
            )
        }
        return PlannerClassKitCoaching(
            show: clean(show),
            say: list(say, limit: sayLimit),
            rule: list(rule, limit: ruleLimit),
            checks: Array(normalizedChecks.prefix(checkLimit)),
            cue: clean(cue),
            card: normalizedCard.flatMap { $0.steps.isEmpty ? nil : $0 }
        )
    }

    static func list(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values.map(clean) where !value.isEmpty {
            guard seen.insert(value.lowercased()).inserted else { continue }
            result.append(value)
            if result.count == limit { break }
        }
        return result
    }

    /// Quita espacios, viñetas y numeración que el modelo suele añadir.
    static func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:[-•*]|\d+[.)])\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Parte fija del kit: no depende de la sesión ni pasa por la IA.
enum PlannerClassKitFixedContent {
    struct Phrase: Equatable {
        let phrase: String
        let gesture: String
        let meaning: String
    }

    static let howToUse: [String] = [
        "Muestra, di, practican, comprueba. Primero la demostración en silencio; después las 3 frases del guion, sin improvisar. Comprueba con las preguntas; nunca «Do you understand?».",
        "Una sola corrección por tarea. Siempre con las mismas palabras y el mismo gesto.",
        "La regla corrige: solo cuenta lo que cae en la zona o cumple la condición. Si cuenta, está bien hecho.",
        "Silbato: uno = «Freeze!», dos = «Rotate».",
        "Si un grupo se desvía: «Shadow, one minute». Gesto sin material un minuto y vuelven a la tarea.",
        "Para corregir a todos: «Freeze! Look at…». Un alumno lo hace bien, dices la corrección y «Go!»."
    ]

    static let phraseBank: [Phrase] = [
        Phrase(phrase: "Freeze!", gesture: "Brazos cruzados en alto", meaning: "Quietos y en silencio"),
        Phrase(phrase: "Equipment down.", gesture: "Mano abajo, palma al suelo", meaning: "Material al suelo"),
        Phrase(phrase: "Look at me. / Watch.", gesture: "Dos dedos a los ojos", meaning: "Mirar la demo"),
        Phrase(phrase: "Groups of two / three.", gesture: "Dedos", meaning: "Hacer parejas o tríos"),
        Phrase(phrase: "Go to your station.", gesture: "Señalar el espacio", meaning: "Ir a su zona"),
        Phrase(phrase: "Your turn.", gesture: "Palma hacia ellos", meaning: "Empiezan"),
        Phrase(phrase: "Swap roles.", gesture: "Índices girando", meaning: "Cambiar de rol"),
        Phrase(phrase: "Rotate. / Change station.", gesture: "Círculo con el dedo", meaning: "Cambiar de estación"),
        Phrase(phrase: "Two minutes left.", gesture: "Dos dedos", meaning: "Quedan 2 minutos"),
        Phrase(phrase: "Show me.", gesture: "Palmas arriba", meaning: "Me lo enseñan"),
        Phrase(phrase: "Again.", gesture: "Dedo hacia atrás", meaning: "Repetir"),
        Phrase(phrase: "Yes! That's it!", gesture: "Pulgar arriba", meaning: "Bien hecho"),
        Phrase(phrase: "Pick up the equipment.", gesture: "Gesto de recoger", meaning: "Recoger el material")
    ]
}
