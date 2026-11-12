import Foundation
import MiGestorKit

/// Pareja de columnas de una prueba física en el Cuaderno: la marca (dato bruto)
/// y la nota baremada. En el grid se pinta una sola columna, la de nota, que
/// muestra `marca | nota`. La marca queda oculta y fuera de la media.
struct NotebookPhysicalColumnPair: Equatable {
    let raw: NotebookColumnDefinition
    let score: NotebookColumnDefinition

    var kind: NotebookPhysicalMarkKind { NotebookPhysicalMarkKind(inputKind: raw.inputKind) ?? .distance }

    /// Unidad de la marca sin el prefijo «Dato bruto · ».
    var unitLabel: String {
        let context = raw.unitOrSituation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unit = context.lowercased().hasPrefix("dato bruto")
            ? context.split(separator: "·", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            : context
        if !unit.isEmpty { return unit }
        switch kind {
        case .time: return "s"
        case .distance: return "m"
        case .repetitions: return "rep."
        }
    }

    /// Nombre de la prueba («Test del km» para «Test del km · Nota»).
    var testName: String { NotebookPhysicalColumns.testName(of: score.title) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.raw.id == rhs.raw.id && lhs.score.id == rhs.score.id
    }
}

enum NotebookPhysicalMarkKind: Equatable {
    case time
    case distance
    case repetitions

    init?(inputKind: NotebookCellInputKind) {
        switch inputKind {
        case .time: self = .time
        case .distance: self = .distance
        case .repetitions: self = .repetitions
        default: return nil
        }
    }
}

enum NotebookPhysicalColumns {
    private static let rawSuffixes = [" · Marca", " · Nivel"]
    private static let scoreSuffix = " · Nota"

    static func testName(of title: String) -> String {
        for suffix in rawSuffixes + [scoreSuffix] where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return title
    }

    static func isRawMeasure(_ column: NotebookColumnDefinition) -> Bool {
        column.instrumentKind == .physicalTest && NotebookPhysicalMarkKind(inputKind: column.inputKind) != nil
    }

    static func isScore(_ column: NotebookColumnDefinition) -> Bool {
        column.instrumentKind == .physicalTest &&
            column.inputKind == .numeric010 &&
            column.title.hasSuffix(scoreSuffix)
    }

    /// Las columnas de marca y nota se crean siempre en la misma categoría (la
    /// asignación) con el mismo nombre de prueba. Así se emparejan sin consultar
    /// la base de datos en cada pintado.
    static func pairs(in columns: [NotebookColumnDefinition]) -> [NotebookPhysicalColumnPair] {
        let raws = columns.filter(isRawMeasure)
        guard !raws.isEmpty else { return [] }
        return columns.filter(isScore).compactMap { score in
            let name = testName(of: score.title)
            guard let raw = raws.first(where: {
                $0.categoryId == score.categoryId && testName(of: $0.title) == name && $0.id != score.id
            }) else { return nil }
            return NotebookPhysicalColumnPair(raw: raw, score: score)
        }
    }

    static func pairsByScoreId(in columns: [NotebookColumnDefinition]) -> [String: NotebookPhysicalColumnPair] {
        Dictionary(pairs(in: columns).map { ($0.score.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Ajustes para que cada prueba física ocupe una sola columna visible:
    /// - la marca se oculta y sale de la media (peso 0);
    /// - si la marca contaba y la nota no (pesos invertidos), la nota pasa a contar;
    /// - la columna de evaluación con el mismo nombre que crea el alta de la prueba se oculta y sale de la media.
    /// Solo cambia visibilidad y peso: nunca toca notas. Vacío si ya está todo bien.
    static func repairPlan(for columns: [NotebookColumnDefinition]) -> [NotebookPhysicalColumnRepair] {
        var plan: [NotebookPhysicalColumnRepair] = []
        let pairs = pairs(in: columns)
        for pair in pairs {
            let raw = pair.raw
            if raw.visibility == .visible || raw.countsTowardAverage || raw.weight != 0 {
                plan.append(NotebookPhysicalColumnRepair(
                    column: raw,
                    visibility: raw.visibility == .visible ? .hidden : raw.visibility,
                    countsTowardAverage: false,
                    weight: 0
                ))
            }
            let score = pair.score
            if raw.countsTowardAverage && !score.countsTowardAverage {
                plan.append(NotebookPhysicalColumnRepair(
                    column: score,
                    visibility: score.visibility,
                    countsTowardAverage: true,
                    weight: score.weight > 0 ? score.weight : 10
                ))
            }
        }
        let testNames = Set(pairs.map(\.testName))
        for column in columns where column.evaluationId != nil &&
            column.instrumentKind != .physicalTest &&
            column.visibility == .visible &&
            testNames.contains(column.title) {
            plan.append(NotebookPhysicalColumnRepair(
                column: column,
                visibility: .hidden,
                countsTowardAverage: false,
                weight: 0
            ))
        }
        return plan
    }
}

struct NotebookPhysicalColumnRepair: Equatable {
    let column: NotebookColumnDefinition
    let visibility: NotebookColumnVisibility
    let countsTowardAverage: Bool
    let weight: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.column.id == rhs.column.id &&
            lhs.visibility == rhs.visibility &&
            lhs.countsTowardAverage == rhs.countsTowardAverage &&
            lhs.weight == rhs.weight
    }
}

/// Lectura y formato de marcas físicas. El tiempo se guarda como texto
/// `mm:ss,cc` (igual que el teclado de tiempo del Cuaderno) y se puntúa en segundos.
enum NotebookPhysicalMark {
    static func value(from text: String, kind: NotebookPhysicalMarkKind) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ",")
        guard !trimmed.isEmpty, trimmed != "—" else { return nil }
        if kind == .time, trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let minutes = Double(parts[0]) else { return nil }
            guard let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")), seconds < 60 else { return nil }
            return max(0, minutes * 60 + seconds)
        }
        guard let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")), number.isFinite, number >= 0 else {
            return nil
        }
        if kind == .repetitions, number.rounded() != number { return nil }
        return number
    }

    static func timeText(centiseconds: Int) -> String {
        let safe = max(0, centiseconds)
        return String(format: "%02d:%02d,%02d", safe / 6000, (safe / 100) % 60, safe % 100)
    }

    static func timeText(seconds: Double) -> String {
        timeText(centiseconds: Int((seconds * 100).rounded()))
    }

    /// Texto corto para la celda: «4:32,50» en vez de «04:32,50».
    static func compactTime(_ text: String) -> String {
        guard text.hasPrefix("0"), text.count > 1, text.dropFirst().first != ":" else { return text }
        return String(text.dropFirst())
    }

    /// Texto que se guarda en la celda de marca.
    static func storedText(from text: String, kind: NotebookPhysicalMarkKind) -> String? {
        guard let value = value(from: text, kind: kind) else { return nil }
        switch kind {
        case .time: return timeText(seconds: value)
        case .repetitions: return String(Int(value))
        case .distance: return decimalText(value)
        }
    }

    static func decimalText(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded.rounded() == rounded { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
    }

    /// Lectura para VoiceOver: «4 minutos 32 segundos».
    static func spokenTime(_ text: String) -> String {
        guard let seconds = value(from: text, kind: .time) else { return text }
        let minutes = Int(seconds) / 60
        let rest = seconds - Double(minutes * 60)
        let restText = decimalText(rest)
        return minutes > 0 ? "\(minutes) minutos \(restText) segundos" : "\(restText) segundos"
    }
}
