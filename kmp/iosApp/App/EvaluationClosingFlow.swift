import Foundation

// Lógica sin vistas de «Cerrar evaluación»: trimestre de la pestaña, estado de cada paso,
// recordatorios locales y fichas de «Valoración rápida». No toca KMP ni la base de datos.

/// Trimestre del recorrido. Los textos coinciden con los de Informes y con `TeacherTermNoteKeys`.
enum EvaluationClosingTerm: String, CaseIterable, Identifiable {
    case first = "1er Trimestre"
    case second = "2º Trimestre"
    case third = "3er Trimestre"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .first: return "1.º"
        case .second: return "2.º"
        case .third: return "3.º"
        }
    }

    /// «1.ª Eval», «2ª evaluación», «Tercer trimestre»… → trimestre. `nil` si no se reconoce.
    static func from(tabTitle: String?) -> EvaluationClosingTerm? {
        let folded = (tabTitle ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
        if let digit = folded.first(where: { "123".contains($0) }) {
            return [.first, .second, .third][Int(String(digit))! - 1]
        }
        if folded.contains("primer") { return .first }
        if folded.contains("segund") { return .second }
        if folded.contains("tercer") { return .third }
        return nil
    }

    /// Trimestre por la fecha (curso de septiembre a junio).
    static func current(at date: Date = Date(), calendar: Calendar = .current) -> EvaluationClosingTerm {
        switch calendar.component(.month, from: date) {
        case 9...12: return .first
        case 1...3: return .second
        default: return .third
        }
    }
}

/// Estado de un paso del recorrido, siempre con texto (nunca solo color).
enum EvaluationClosingStepState: Equatable {
    case done(String)
    case attention(String)
    case pending(String)

    var text: String {
        switch self {
        case .done(let text), .attention(let text), .pending(let text): return text
        }
    }

    var isDone: Bool {
        if case .done = self { return true }
        return false
    }
}

/// Recordatorios del cierre en este dispositivo: último archivo de Educamos y «Ya lo he subido».
/// No se sincronizan: la app no puede comprobar nada en Educamos.
struct EvaluationClosingRecord: Codable, Equatable {
    var exportDate: Date?
    var exportSummary: String?
    var exportFilePath: String?
    var uploadedDate: Date?

    var isUploaded: Bool { uploadedDate != nil }
}

enum EvaluationClosingStore {
    static func key(classId: Int64, tabId: String?) -> String {
        "evaluationClosing.\(classId).\(tabId ?? "sin-pestana")"
    }

    static func load(classId: Int64, tabId: String?, defaults: UserDefaults = .standard) -> EvaluationClosingRecord {
        guard let data = defaults.data(forKey: key(classId: classId, tabId: tabId)),
              let record = try? JSONDecoder().decode(EvaluationClosingRecord.self, from: data) else {
            return EvaluationClosingRecord()
        }
        return record
    }

    static func save(_ record: EvaluationClosingRecord, classId: Int64, tabId: String?, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key(classId: classId, tabId: tabId))
    }
}

enum EvaluationClosingSteps {
    static func notes(issueCount: Int, hasCountingColumns: Bool) -> EvaluationClosingStepState {
        guard hasCountingColumns else { return .pending("Sin columnas que cuenten") }
        if issueCount == 0 { return .done("Listo") }
        return .attention(issueCount == 1 ? "1 aviso" : "\(issueCount) avisos")
    }

    static func comments(withComment: Int, total: Int) -> EvaluationClosingStepState {
        guard total > 0 else { return .pending("Sin alumnado") }
        let missing = total - withComment
        if missing == 0 { return .done("Listo") }
        return .attention(missing == 1 ? "1 sin comentario" : "\(missing) sin comentario")
    }

    static func excel(_ record: EvaluationClosingRecord) -> EvaluationClosingStepState {
        record.exportDate == nil ? .pending("Pendiente") : .done("Generado")
    }

    static func upload(_ record: EvaluationClosingRecord) -> EvaluationClosingStepState {
        record.isUploaded ? .done("Subido") : .pending("Pendiente")
    }
}

// MARK: - Valoración rápida

enum QuickNoteGroup: String, CaseIterable, Identifiable {
    case strength = "Fortaleza"
    case improve = "A mejorar"
    case guidance = "Orientación"

    var id: String { rawValue }
}

struct QuickNoteChip: Identifiable, Hashable {
    let group: QuickNoteGroup
    let text: String
    /// De dónde sale («sello ×3», «rúbrica», «2 días sin material»). `nil` en las frases fijas.
    let source: String?
    /// Id de la ficha propia del docente; `nil` en las demás.
    var phraseId: String? = nil

    var id: String { "\(group.rawValue)|\(text)" }
}

enum QuickNoteCatalog {
    static let fixed: [QuickNoteGroup: [String]] = [
        .strength: ["Actitud positiva", "Constancia", "Esfuerzo", "Participa activamente", "Respeta las normas"],
        .improve: ["Constancia en el trabajo", "Participación en clase", "Atención a las explicaciones", "Puntualidad", "Respeto de las normas"],
        .guidance: ["Mantener la constancia", "Practicar en casa unos minutos varios días", "Revisar la agenda del material", "Participar más en las actividades de grupo", "Preguntar las dudas en clase"]
    ]

    /// Sellos que suman como fortaleza o como aspecto a mejorar (por título del catálogo del Cuaderno).
    static let strengthStamps: Set<String> = ["Sobresaliente", "Logro destacado", "Objetivo cumplido", "Buen trabajo", "Idea creativa", "Gran energía", "Progresando", "Cooperación", "Superación"]
    static let improveStamps: Set<String> = ["Necesita refuerzo", "Prioritario", "Entrega pendiente", "No superado"]

    /// Fichas del alumno: primero lo que ya consta (sellos, rúbricas, material), luego las fijas.
    /// `custom`: fichas propias del docente (texto e id), que van justo después de lo registrado.
    static func chips(
        for input: BulletinBaseStudentInput?,
        custom: [QuickNoteGroup: [(id: String, text: String)]] = [:]
    ) -> [QuickNoteGroup: [QuickNoteChip]] {
        var result: [QuickNoteGroup: [QuickNoteChip]] = [:]
        func add(_ group: QuickNoteGroup, _ text: String, _ source: String?, phraseId: String? = nil) {
            let clean = sanitize(text)
            guard !clean.isEmpty, !(result[group] ?? []).contains(where: { $0.text == clean }) else { return }
            result[group, default: []].append(QuickNoteChip(group: group, text: clean, source: source, phraseId: phraseId))
        }

        if let input {
            for stamp in input.stamps.sorted(by: { $0.count > $1.count }) {
                let source = "sello ×\(stamp.count)"
                if strengthStamps.contains(stamp.title) { add(.strength, stamp.title, source) }
                if improveStamps.contains(stamp.title) { add(.improve, stamp.title, source) }
            }
            for level in input.criterionLevels {
                guard let ratio = level.ratio else { continue }
                let text = "\(level.criterion): \(level.level.lowercased())"
                if ratio >= 0.75 { add(.strength, text, "rúbrica") }
                if ratio <= 0.5 { add(.improve, text, "rúbrica") }
            }
            if input.attendance.noMaterial > 0 {
                let days = input.attendance.noMaterial
                add(.improve, "Traer el material de clase", days == 1 ? "1 día sin material" : "\(days) días sin material")
                add(.guidance, "Revisar la agenda del material", nil)
            }
        }
        for group in QuickNoteGroup.allCases {
            for phrase in custom[group] ?? [] { add(group, phrase.text, nil, phraseId: phrase.id) }
        }
        for group in QuickNoteGroup.allCases {
            for text in fixed[group] ?? [] { add(group, text, nil) }
        }
        return result
    }

    /// Las frases se separan con comas y los grupos con puntos: se quitan de cada frase.
    static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// «Fortaleza: A, B. A mejorar: C. Orientación: D.» en la primera línea y el texto libre debajo.
/// Así se puede volver a abrir y las fichas salen marcadas.
enum QuickNoteComposer {
    static func compose(selected: [QuickNoteGroup: [String]], freeText: String) -> String {
        let structured = QuickNoteGroup.allCases.compactMap { group -> String? in
            let items = selected[group] ?? []
            return items.isEmpty ? nil : "\(group.rawValue): \(items.joined(separator: ", "))."
        }.joined(separator: " ")
        let free = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [structured, free].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func decompose(_ note: String) -> (selected: [QuickNoteGroup: [String]], freeText: String) {
        var lines = note.components(separatedBy: "\n")
        guard let first = lines.first,
              QuickNoteGroup.allCases.contains(where: { first.hasPrefix("\($0.rawValue):") }) else {
            return ([:], note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lines.removeFirst()
        var selected: [QuickNoteGroup: [String]] = [:]
        let pattern = #"(Fortaleza|A mejorar|Orientación):\s*([^.]*)\."#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(first.startIndex..., in: first)
            for match in regex.matches(in: first, range: range) {
                guard let groupRange = Range(match.range(at: 1), in: first),
                      let itemsRange = Range(match.range(at: 2), in: first),
                      let group = QuickNoteGroup(rawValue: String(first[groupRange])) else { continue }
                selected[group] = first[itemsRange]
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        return (selected, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
