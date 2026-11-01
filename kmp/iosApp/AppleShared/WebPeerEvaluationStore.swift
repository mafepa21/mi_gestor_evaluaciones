import Foundation

/// Combina varias respuestas al mismo ítem en una sola celda del Cuaderno.
///
/// Notas y escalas: media. Sí/No: mayoría. Texto y elección: todas, una por línea.
enum WebAnswerCombiner {
    struct Combined: Equatable {
        let text: String
        let bool: Bool?
        let number: Double?
    }

    static func combine(_ answers: [WebResolvedAnswer]) -> Combined? {
        guard let type = answers.first?.type else { return nil }
        switch type {
        case .scale1To4, .number:
            let numbers = answers.compactMap(\.numberValue)
            guard !numbers.isEmpty else { return Combined(text: "", bool: nil, number: nil) }
            let media = numbers.reduce(0.0, +) / Double(numbers.count)
            let text = media.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(media))
                : String(format: "%.2f", media)
            return Combined(text: text, bool: nil, number: media)
        case .check:
            let bools = answers.compactMap(\.boolValue)
            guard !bools.isEmpty else { return Combined(text: "", bool: nil, number: nil) }
            let majority = bools.filter { $0 }.count > bools.count / 2
            return Combined(text: majority ? "Sí" : "No", bool: majority, number: nil)
        case .text, .choice:
            let texts = answers
                .compactMap { $0.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Combined(text: texts.joined(separator: "\n"), bool: nil, number: nil)
        }
    }
}

/// Coevaluaciones recibidas, guardadas una a una en este Mac.
///
/// Con el buzón llegan poco a poco: para que la media de un alumno incluya todas
/// las recibidas, y no solo las de la última recogida, se guarda cada evaluación
/// por separado y la celda se recalcula con todas. Si un evaluador reenvía, cuenta
/// solo su última versión.
///
/// Vive junto a la hoja privada de enlaces (`EntregasWeb/<formulario>/`) y, como
/// ella, no viaja por Sync LAN: relaciona alias con alumnos.
struct WebPeerEvaluationStore {
    struct Evaluation: Codable, Equatable {
        let evaluatorAlias: String
        let targetStudentId: Int64
        let clientSubmittedAt: String
        let answers: [WebResolvedAnswer]
    }

    let fileURL: URL
    private(set) var evaluations: [String: Evaluation] = [:]

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: Evaluation].self, from: data) {
            evaluations = stored
        }
    }

    static func forForm(_ formInstanceId: String) -> WebPeerEvaluationStore? {
        WebSubmissionPrivateLinksStore.folderURL(for: formInstanceId).map {
            WebPeerEvaluationStore(fileURL: $0.appendingPathComponent("coevaluaciones.json"))
        }
    }

    private static func key(evaluator: String, target: Int64) -> String { "\(evaluator)|\(target)" }

    /// Añade o sustituye la evaluación de `evaluatorAlias` a `targetStudentId`.
    /// Una versión más antigua que la guardada no la pisa.
    mutating func record(evaluatorAlias: String, targetStudentId: Int64, clientSubmittedAt: String, answers: [WebResolvedAnswer]) {
        let clave = Self.key(evaluator: evaluatorAlias, target: targetStudentId)
        if let previa = evaluations[clave], previa.clientSubmittedAt > clientSubmittedAt { return }
        evaluations[clave] = Evaluation(
            evaluatorAlias: evaluatorAlias,
            targetStudentId: targetStudentId,
            clientSubmittedAt: clientSubmittedAt,
            answers: answers
        )
    }

    func evaluations(for targetStudentId: Int64) -> [Evaluation] {
        evaluations.values
            .filter { $0.targetStudentId == targetStudentId }
            .sorted { $0.evaluatorAlias < $1.evaluatorAlias }
    }

    func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(evaluations).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
