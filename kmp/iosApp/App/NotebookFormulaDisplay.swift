import Foundation
import MiGestorKit

enum NotebookFormulaDisplay {
    static func display(
        formula: String?,
        item: NotebookTableRow,
        data: NotebookUiStateData,
        numericText: (Int64, String) -> String,
        rubricText: (Int64, NotebookColumnDefinition) -> String
    ) -> NotebookFormulaCellDisplay? {
        let formula = formula?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !formula.isEmpty else {
            return NotebookFormulaCellDisplay(text: "Sin fórmula", isError: true)
        }

        do {
            let variables = variables(
                for: item,
                data: data,
                numericText: numericText,
                rubricText: rubricText
            )
            let value = try NotebookFormulaEvaluator.evaluate(formula, variables: variables)
            return NotebookFormulaCellDisplay(text: formatResult(value), isError: false)
        } catch {
            return NotebookFormulaCellDisplay(text: error.localizedDescription, isError: true)
        }
    }

    static func variables(
        for item: NotebookTableRow,
        data: NotebookUiStateData,
        numericText: (Int64, String) -> String,
        rubricText: (Int64, NotebookColumnDefinition) -> String
    ) -> [String: Double] {
        var variables: [String: Double] = [:]
        for column in data.sheet.columns where column.type != .calculated {
            let raw = column.type == .rubric
                ? rubricText(item.student.id, column)
                : numericText(item.student.id, column.id)
            let value = parseNumber(raw) ?? 0
            variables[column.id] = value
            variables[NotebookFormulaEvaluator.safeIdentifier(for: column.id)] = value
        }
        return variables
    }

    static func parseNumber(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    static func formatResult(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func spreadsheetFormula(
        _ formula: String,
        rowIndex: Int,
        columnLettersById: [String: String]
    ) -> String {
        var output = formula.hasPrefix("=") ? formula : "=\(formula)"
        for (columnId, letter) in columnLettersById {
            output = output.replacingOccurrences(of: "[\(columnId)]", with: "\(letter)\(rowIndex)")
        }
        return output
    }
}
