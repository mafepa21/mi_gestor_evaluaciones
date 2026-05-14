import SwiftUI
import MiGestorKit

struct NotebookFormulaEditorSheet: View {
    let column: NotebookColumnDefinition
    let referenceColumns: [NotebookColumnDefinition]
    let allColumns: [NotebookColumnDefinition]
    let rows: [NotebookRow]
    @Binding var formula: String
    @Binding var aiPrompt: String
    @Binding var aiMessage: String?
    let isAIGenerating: Bool
    let onGenerateAI: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    private var validation: NotebookFormulaEditorValidationResult {
        NotebookFormulaEditorValidator.validate(
            formula: formula,
            targetColumn: column,
            availableColumns: allColumns,
            formulaColumns: allColumns.filter { $0.type == .calculated },
            previewRow: rows.first
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 660, height: 640)
        .background(EvaluationBackdrop())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fórmula de columna")
                    .font(.title3.bold())
                Text(column.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cerrar") { onCancel() }
                .buttonStyle(.borderless)
        }
        .padding(22)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edita la fórmula una vez y se aplicará a todas las celdas de esta columna calculada.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                NotebookFormulaKeyboard(
                    formula: $formula,
                    availableColumns: referenceColumns
                )

                validationPanel

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Ayuda con Apple Intelligence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)

                    TextField("Ej: media del examen y la rúbrica, o corrige esta fórmula", text: $aiPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    HStack {
                        Button {
                            onGenerateAI()
                        } label: {
                            Label(isAIGenerating ? "Pensando..." : "Generar / corregir fórmula", systemImage: "apple.intelligence")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAIGenerating || aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let aiMessage {
                            Text(aiMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var validationPanel: some View {
        NotebookSurface(cornerRadius: 12, fill: NotebookStyle.surface, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(validation.isValid ? NotebookStyle.successTint : NotebookStyle.warningTint)
                    Text(validation.isValid ? "Fórmula válida" : "Revisa la fórmula")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(validation.referenceSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if validation.errors.isEmpty {
                    Text(validation.previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(validation.errors, id: \.id) { error in
                            Label(error.message, systemImage: "xmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancelar") { onCancel() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Guardar fórmula") { onSave() }
                .buttonStyle(.borderedProminent)
                .disabled(!validation.isValid)
        }
        .padding(18)
    }
}

struct NotebookFormulaEditorValidationResult {
    let errors: [NotebookFormulaEditorValidationError]
    let referencedColumnIds: [String]
    let previewValue: Double?
    let hasPreviewRow: Bool

    var isValid: Bool { errors.isEmpty }

    var referenceSummary: String {
        referencedColumnIds.isEmpty ? "Sin referencias" : "\(referencedColumnIds.count) referencia(s)"
    }

    var previewText: String {
        guard hasPreviewRow else {
            return "No hay datos suficientes para previsualizar, pero la fórmula es válida."
        }
        guard let previewValue else {
            return "No hay datos suficientes para previsualizar, pero la fórmula es válida."
        }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: previewValue)) ?? String(format: "%.2f", previewValue)
        return "Preview con el primer alumno: \(value)"
    }
}

struct NotebookFormulaEditorValidationError: Identifiable {
    let id = UUID()
    let message: String
}

enum NotebookFormulaEditorValidator {
    static func validate(
        formula: String,
        targetColumn: NotebookColumnDefinition,
        availableColumns: [NotebookColumnDefinition],
        formulaColumns: [NotebookColumnDefinition],
        previewRow: NotebookRow?
    ) -> NotebookFormulaEditorValidationResult {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "=" }
        let expression = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            return .init(errors: [.init(message: "La fórmula no puede estar vacía.")], referencedColumnIds: [], previewValue: nil, hasPreviewRow: previewRow != nil)
        }

        var errors: [NotebookFormulaEditorValidationError] = []
        let referencedIds = referencedColumnIds(in: expression)
        let availableIds = Set(availableColumns.map(\.id))

        referencedIds.filter { !availableIds.contains($0) }.forEach { missingId in
            errors.append(.init(message: missingColumnMessage(for: missingId, availableColumns: availableColumns)))
        }

        unsupportedFunctions(in: expression).forEach {
            errors.append(.init(message: "Función no soportada: \($0)."))
        }

        if referencedIds.contains(targetColumn.id) || hasCircularReference(targetColumnId: targetColumn.id, directReferences: referencedIds, formulaColumns: formulaColumns) {
            errors.append(.init(message: "La fórmula crea una referencia circular."))
        }

        let variables = previewRow.map { variablesForPreview(row: $0, columns: availableColumns) } ?? [:]
        let previewValue: Double?
        if errors.isEmpty {
            do {
                previewValue = try NotebookFormulaEditorEvaluator.evaluate(expression, variables: variables)
            } catch NotebookFormulaEditorEvaluatorError.divisionByZero {
                errors.append(.init(message: "División por cero."))
                previewValue = nil
            } catch {
                if previewRow == nil || variables.isEmpty {
                    previewValue = nil
                } else {
                    errors.append(.init(message: error.localizedDescription))
                    previewValue = nil
                }
            }
        } else {
            previewValue = nil
        }

        return .init(
            errors: errors,
            referencedColumnIds: referencedIds,
            previewValue: previewValue,
            hasPreviewRow: previewRow != nil
        )
    }

    private static func referencedColumnIds(in formula: String) -> [String] {
        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(formula.startIndex..<formula.endIndex, in: formula)
        var seen = Set<String>()
        return regex.matches(in: formula, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: formula) else { return nil }
            let id = String(formula[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { return nil }
            seen.insert(id)
            return id
        }
    }

    private static func unsupportedFunctions(in formula: String) -> [String] {
        let stripped = formula.replacingOccurrences(of: #"\[[^\]]+]"#, with: "1", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#) else { return [] }
        let allowed: Set<String> = ["SUMA", "PROMEDIO", "MIN", "MAX", "REDONDEAR", "SI"]
        let range = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
        var seen = Set<String>()
        return regex.matches(in: stripped, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: stripped) else { return nil }
            let name = String(stripped[tokenRange])
            guard !allowed.contains(name.uppercased()), !seen.contains(name.uppercased()) else { return nil }
            seen.insert(name.uppercased())
            return name
        }
    }

    private static func hasCircularReference(targetColumnId: String, directReferences: [String], formulaColumns: [NotebookColumnDefinition]) -> Bool {
        let graph = Dictionary(uniqueKeysWithValues: formulaColumns.map { column in
            (column.id, referencedColumnIds(in: column.formula ?? ""))
        })

        func visitsTarget(_ columnId: String, seen: Set<String>) -> Bool {
            if columnId == targetColumnId { return true }
            if seen.contains(columnId) { return false }
            return graph[columnId, default: []].contains { visitsTarget($0, seen: seen.union([columnId])) }
        }

        return directReferences.contains { visitsTarget($0, seen: []) }
    }

    private static func variablesForPreview(row: NotebookRow, columns: [NotebookColumnDefinition]) -> [String: Double] {
        var variables: [String: Double] = [:]
        for column in columns {
            let value = numericValue(for: row, column: column) ?? 0
            variables[column.id] = value
            variables[NotebookFormulaEditorEvaluator.safeIdentifier(for: column.id)] = value
        }
        return variables
    }

    private static func numericValue(for row: NotebookRow, column: NotebookColumnDefinition) -> Double? {
        if let value = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
            return value
        }
        if let evaluationId = column.evaluationId?.int64Value,
           let value = row.cells.first(where: { $0.evaluationId == evaluationId })?.value?.doubleValue {
            return value
        }
        if column.type == .check,
           let value = row.persistedCells.first(where: { $0.columnId == column.id })?.boolValue?.boolValue {
            return value ? checkPositiveValue(for: column) : 0
        }
        return nil
    }

    private static func checkPositiveValue(for column: NotebookColumnDefinition) -> Double {
        column.weight > 0 ? column.weight : 1
    }

    private static func missingColumnMessage(for reference: String, availableColumns: [NotebookColumnDefinition]) -> String {
        if let column = availableColumns.first(where: { normalize($0.title) == normalize(reference) }) {
            return "La columna [\(reference)] no existe. Usa [\(column.id)] para “\(column.title)”."
        }
        return "La columna [\(reference)] no existe. Inserta la referencia desde la lista de columnas."
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum NotebookFormulaEditorEvaluatorError: LocalizedError {
    case incompleteExpression
    case unexpectedToken(String)
    case unbalancedParentheses
    case unknownVariable(String)
    case unknownFunction(String)
    case invalidArguments(String)
    case divisionByZero

    var errorDescription: String? {
        switch self {
        case .incompleteExpression:
            return "Fórmula incompleta"
        case .unexpectedToken(let token):
            return "Token inesperado: \(token)"
        case .unbalancedParentheses:
            return "Paréntesis desbalanceados"
        case .unknownVariable(let name):
            return "Columna no encontrada: \(name)"
        case .unknownFunction(let name):
            return "Función no soportada: \(name)"
        case .invalidArguments(let message):
            return message
        case .divisionByZero:
            return "División por cero"
        }
    }
}

private enum NotebookFormulaEditorEvaluator {
    static func safeIdentifier(for raw: String) -> String {
        let mapped = raw.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        let identifier = String(mapped)
        if identifier.first?.isNumber == true {
            return "_\(identifier)"
        }
        return identifier
    }

    static func evaluate(_ expression: String, variables: [String: Double]) throws -> Double {
        let normalized = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "=" })
        var parser = Parser(tokens: tokenize(String(normalized)), variables: variables)
        return try parser.parseExpression()
    }

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character.isWhitespace {
                flush()
            } else if character == "[" {
                flush()
                let nextIndex = input.index(after: index)
                if let end = input[nextIndex...].firstIndex(of: "]") {
                    tokens.append(safeIdentifier(for: String(input[nextIndex..<end])))
                    index = end
                } else {
                    tokens.append(String(character))
                }
            } else if "+-*/(),<>".contains(character) {
                flush()
                let nextIndex = input.index(after: index)
                if nextIndex < input.endIndex {
                    let pair = "\(character)\(input[nextIndex])"
                    if ["<=", ">=", "==", "!=", "<>"].contains(pair) {
                        tokens.append(pair)
                        index = nextIndex
                    } else {
                        tokens.append(String(character))
                    }
                } else {
                    tokens.append(String(character))
                }
            } else {
                current.append(character)
            }
            index = input.index(after: index)
        }
        flush()
        return tokens
    }

    private struct Parser {
        let tokens: [String]
        let variables: [String: Double]
        var position = 0

        mutating func parseExpression() throws -> Double {
            let result = try parseComparison()
            if !isAtEnd {
                throw NotebookFormulaEditorEvaluatorError.unexpectedToken(peek)
            }
            return result
        }

        private mutating func parseComparison() throws -> Double {
            var left = try parseAddSub()
            while match("<", ">", "<=", ">=", "==", "!=", "<>") {
                let op = previous
                let right = try parseAddSub()
                switch op {
                case "<": left = left < right ? 1 : 0
                case ">": left = left > right ? 1 : 0
                case "<=": left = left <= right ? 1 : 0
                case ">=": left = left >= right ? 1 : 0
                case "==": left = left == right ? 1 : 0
                case "!=", "<>": left = left != right ? 1 : 0
                default: throw NotebookFormulaEditorEvaluatorError.unexpectedToken(op)
                }
            }
            return left
        }

        private mutating func parseAddSub() throws -> Double {
            var left = try parseMulDiv()
            while match("+", "-") {
                let op = previous
                let right = try parseMulDiv()
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        private mutating func parseMulDiv() throws -> Double {
            var left = try parseUnary()
            while match("*", "/") {
                let op = previous
                let right = try parseUnary()
                if op == "/" {
                    guard right != 0 else { throw NotebookFormulaEditorEvaluatorError.divisionByZero }
                    left /= right
                } else {
                    left *= right
                }
            }
            return left
        }

        private mutating func parseUnary() throws -> Double {
            if match("-") { return try -parseUnary() }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            if match("(") {
                let value = try parseComparison()
                guard match(")") else { throw NotebookFormulaEditorEvaluatorError.unbalancedParentheses }
                return value
            }

            guard !isAtEnd else { throw NotebookFormulaEditorEvaluatorError.incompleteExpression }
            let token = advance()
            if let number = Double(token.replacingOccurrences(of: ",", with: ".")) {
                return number
            }
            if match("(") {
                var args: [Double] = []
                if !check(")") {
                    repeat {
                        args.append(try parseComparison())
                    } while match(",")
                }
                guard match(")") else { throw NotebookFormulaEditorEvaluatorError.unbalancedParentheses }
                return try evaluateFunction(token, args: args)
            }
            if let value = variables[token] ?? variables[NotebookFormulaEditorEvaluator.safeIdentifier(for: token)] {
                return value
            }
            throw NotebookFormulaEditorEvaluatorError.unknownVariable(token)
        }

        private func evaluateFunction(_ rawName: String, args: [Double]) throws -> Double {
            let name = rawName.uppercased()
            switch name {
            case "SUMA":
                return args.reduce(0, +)
            case "PROMEDIO":
                guard !args.isEmpty else { throw NotebookFormulaEditorEvaluatorError.invalidArguments("\(rawName) requiere al menos 1 argumento") }
                return args.reduce(0, +) / Double(args.count)
            case "MIN":
                guard let value = args.min() else { throw NotebookFormulaEditorEvaluatorError.invalidArguments("MIN requiere al menos 1 argumento") }
                return value
            case "MAX":
                guard let value = args.max() else { throw NotebookFormulaEditorEvaluatorError.invalidArguments("MAX requiere al menos 1 argumento") }
                return value
            case "REDONDEAR":
                guard args.count == 1 || args.count == 2 else { throw NotebookFormulaEditorEvaluatorError.invalidArguments("\(rawName) requiere 1 o 2 argumentos") }
                let digits = args.count == 2 ? Int(args[1]) : 0
                let factor = pow(10.0, Double(digits))
                return (args[0] * factor).rounded() / factor
            case "SI":
                guard args.count == 3 else { throw NotebookFormulaEditorEvaluatorError.invalidArguments("\(rawName) requiere 3 argumentos") }
                return args[0] != 0 ? args[1] : args[2]
            default:
                throw NotebookFormulaEditorEvaluatorError.unknownFunction(rawName)
            }
        }

        private mutating func match(_ expected: String...) -> Bool {
            guard !isAtEnd, expected.contains(peek) else { return false }
            position += 1
            return true
        }

        private func check(_ expected: String) -> Bool {
            !isAtEnd && peek == expected
        }

        private mutating func advance() -> String {
            let token = peek
            position += 1
            return token
        }

        private var previous: String { tokens[position - 1] }
        private var peek: String { tokens[position] }
        private var isAtEnd: Bool { position >= tokens.count }
    }
}
