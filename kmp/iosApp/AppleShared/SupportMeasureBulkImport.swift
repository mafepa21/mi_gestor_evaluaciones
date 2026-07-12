import Foundation
import MiGestorKit

// Importación masiva de medidas Nivel III desde una tabla Excel propia del docente
// (alumnos en filas, medidas del catálogo en columnas marcadas con "x"). Puramente
// lectura/interpretación: no persiste nada, solo produce un resultado revisable que
// la UI confirma antes de guardar via KmpBridge.

enum SupportMeasureBulkImportError: LocalizedError {
    case sheetNotFound
    case headerNotFound

    var errorDescription: String? {
        switch self {
        case .sheetNotFound:
            return "No se ha encontrado ninguna hoja con una columna 'Clase' en el archivo."
        case .headerNotFound:
            return "No se ha podido localizar la fila de cabecera (columna 'Clase')."
        }
    }
}

struct SupportMeasureImportRow: Identifiable {
    let id = UUID()
    let rowIndex: Int
    let rawName: String
    let claseValue: String
    var matchedStudent: Student?
    let measures: [SupportMeasureTypeUI]
    let notes: String
}

struct SupportMeasureBulkImportResult {
    var rows: [SupportMeasureImportRow]
    let claseValues: [String]
    let sheetName: String
    let hadUnrecognizedColumns: Bool
}

enum SupportMeasureBulkImport {
    /// Analiza el archivo y devuelve las filas detectadas, sin emparejar todavía con
    /// el alumnado real de la app (eso lo hace `match(rows:against:)` una vez se conoce
    /// la clase de destino seleccionada en la ficha).
    static func parse(url: URL) throws -> SupportMeasureBulkImportResult {
        let sheets = try AppleSpreadsheetReader.readAllXLSXSheets(from: url)

        guard let sheet = sheets.first(where: { sheet in
            sheet.rows.contains { row in
                row.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "clase" }
            }
        }) else {
            throw SupportMeasureBulkImportError.sheetNotFound
        }

        guard let headerRowIndex = sheet.rows.firstIndex(where: { row in
            row.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "clase" }
        }) else {
            throw SupportMeasureBulkImportError.headerNotFound
        }

        let headerRow = sheet.rows[headerRowIndex]
        let descriptionRow = headerRowIndex > 0 ? sheet.rows[headerRowIndex - 1] : []

        func effectiveHeader(at column: Int) -> String {
            let short = column < headerRow.count ? headerRow[column].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if !short.isEmpty { return short }
            return column < descriptionRow.count ? descriptionRow[column].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }

        let columnCount = max(headerRow.count, descriptionRow.count)

        var nameColumn: Int?
        var claseColumn: Int?
        var comentarioColumn: Int?
        var otrasColumn: Int?
        var aciColumn: Int?
        var diagnosticoColumn: Int?
        var measureColumns: [Int: SupportMeasureTypeUI] = [:]
        var recognizedColumns: Set<Int> = []
        var hadUnrecognizedColumns = false

        for column in 0..<columnCount {
            let short = column < headerRow.count ? headerRow[column].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let effective = effectiveHeader(at: column)
            let lower = effective.lowercased()

            if lower.hasPrefix("alumn") {
                nameColumn = column
                recognizedColumns.insert(column)
            } else if lower == "clase" {
                claseColumn = column
                recognizedColumns.insert(column)
            } else if lower == "comentario" {
                comentarioColumn = column
                recognizedColumns.insert(column)
            } else if lower.hasPrefix("otras") {
                otrasColumn = column
                recognizedColumns.insert(column)
            } else if lower.contains("acis") || lower.contains("pap-al") {
                aciColumn = column
                recognizedColumns.insert(column)
            } else if lower.contains("diagn") {
                diagnosticoColumn = column
                recognizedColumns.insert(column)
            } else if lower == "tutor" {
                recognizedColumns.insert(column)
            } else if !short.isEmpty, let measure = SupportMeasureTypeUI.fromCatalogCode(short) {
                measureColumns[column] = measure
                recognizedColumns.insert(column)
            }
        }

        guard let nameColumn else {
            throw SupportMeasureBulkImportError.headerNotFound
        }

        var rows: [SupportMeasureImportRow] = []
        var claseValuesSeen: [String] = []

        for rowIndex in (headerRowIndex + 1)..<sheet.rows.count {
            let row = sheet.rows[rowIndex]
            guard nameColumn < row.count else { continue }
            let rawName = row[nameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { continue }

            let clase = claseColumn.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil } ?? ""
            if !clase.isEmpty, !claseValuesSeen.contains(clase) {
                claseValuesSeen.append(clase)
            }

            var selectedMeasures: [SupportMeasureTypeUI] = []
            var noteParts: [String] = []

            for (column, measure) in measureColumns.sorted(by: { $0.key < $1.key }) {
                guard column < row.count else { continue }
                let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                selectedMeasures.append(measure)
                if value.lowercased() != "x" {
                    noteParts.append("\(measure.displayName): \(value)")
                }
            }

            if let otrasColumn, otrasColumn < row.count {
                let value = row[otrasColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    if value.uppercased() == "REPETICION", let measure = SupportMeasureTypeUI.fromCatalogCode("REPETICION") {
                        selectedMeasures.append(measure)
                    } else {
                        noteParts.append("Otras medidas: \(value)")
                    }
                }
            }

            if let comentarioColumn, comentarioColumn < row.count {
                let value = row[comentarioColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { noteParts.append("Comentario: \(value)") }
            }
            if let aciColumn, aciColumn < row.count {
                let value = row[aciColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { noteParts.append("ACI/ACIS/PAP-AL: \(value)") }
            }
            if let diagnosticoColumn, diagnosticoColumn < row.count {
                let value = row[diagnosticoColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { noteParts.append("Diagnóstico: \(value)") }
            }

            for (column, value) in row.enumerated() where column != nameColumn && !recognizedColumns.contains(column) {
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hadUnrecognizedColumns = true
                }
            }

            guard !selectedMeasures.isEmpty || !noteParts.isEmpty else { continue }

            rows.append(
                SupportMeasureImportRow(
                    rowIndex: rowIndex,
                    rawName: rawName,
                    claseValue: clase,
                    matchedStudent: nil,
                    measures: selectedMeasures,
                    notes: noteParts.joined(separator: "\n")
                )
            )
        }

        return SupportMeasureBulkImportResult(
            rows: rows,
            claseValues: claseValuesSeen.sorted(),
            sheetName: sheet.name,
            hadUnrecognizedColumns: hadUnrecognizedColumns
        )
    }

    /// Empareja cada fila con un alumno real del grupo seleccionado por nombre completo
    /// (y, si no hay coincidencia exacta, por nombre de pila si es único en el grupo).
    static func match(rows: [SupportMeasureImportRow], against roster: [Student]) -> [SupportMeasureImportRow] {
        rows.map { row in
            var row = row
            let normalized = row.rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if let exact = roster.first(where: { $0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
                row.matchedStudent = exact
                return row
            }

            let firstNameMatches = roster.filter { $0.firstName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
            if firstNameMatches.count == 1 {
                row.matchedStudent = firstNameMatches.first
            }
            return row
        }
    }
}
