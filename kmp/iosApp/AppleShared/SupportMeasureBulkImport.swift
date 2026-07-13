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

/// Resultado de emparejar el nombre crudo del Excel con el roster real de la clase.
/// Nunca se autoselecciona una fila para importar salvo `.exact`: asignar una medida
/// sensible (NEE) al alumno equivocado por una coincidencia parcial mal resuelta es un
/// error grave, así que `.suggested`/`.none` siempre requieren que el docente confirme
/// a mano en la pantalla de revisión, aunque solo haya un candidato sugerido.
enum SupportMeasureMatchStatus {
    case exact(Student)
    case suggested([Student])
    case none

    var confirmedStudent: Student? {
        if case .exact(let student) = self { return student }
        return nil
    }
}

struct SupportMeasureImportRow: Identifiable {
    let id = UUID()
    let rowIndex: Int
    let rawName: String
    let claseValue: String
    var matchStatus: SupportMeasureMatchStatus = .none
    var confirmedStudent: Student?
    /// `true` solo cuando el docente ha confirmado explícitamente el alumno (coincidencia
    /// exacta automática, o elección/confirmación manual en la UI). `confirmedStudent` puede
    /// estar precargado (p.ej. `.suggested`) sin que esto sea `true` todavía: la fila no debe
    /// importarse hasta que el docente lo confirme a mano.
    var isManuallyConfirmed = false
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

    /// Empareja cada fila con un alumno real del grupo. Soporta nombres de pila completos
    /// con apellidos abreviados (p.ej. "IVÁN CA SA" para "Iván Cabanillas Sánchez"): el
    /// nombre de pila debe coincidir palabra a palabra por completo, y cada fragmento de
    /// apellido debe ser prefijo (mínimo 2 letras) de la palabra correspondiente del
    /// apellido real, en orden. Nunca marca `.exact` salvo coincidencia exacta de nombre
    /// completo; cualquier otra coincidencia queda como `.suggested` para confirmar a mano.
    static func match(rows: [SupportMeasureImportRow], against roster: [Student]) -> [SupportMeasureImportRow] {
        rows.map { row in
            var row = row
            let rawTokens = normalizedTokens(row.rawName)
            guard !rawTokens.isEmpty else { return row }

            if let exact = roster.first(where: { normalizedTokens($0.fullName) == rawTokens }) {
                row.matchStatus = .exact(exact)
                row.confirmedStudent = exact
                row.isManuallyConfirmed = true
                return row
            }

            let candidates = roster.filter { candidate in
                matchesAbbreviated(rawTokens: rawTokens, candidate: candidate)
            }

            if !candidates.isEmpty {
                row.matchStatus = .suggested(candidates)
                // Precargado como punto de partida (el docente lo confirma o lo cambia en
                // el desplegable); no se equipara a `.exact`, la fila sigue marcada como
                // "sugerida" en la UI y `isManuallyConfirmed` queda en `false` hasta que el
                // docente la confirme explícitamente — no se importa solo por estar precargada.
                row.confirmedStudent = candidates.first
            }
            return row
        }
    }

    private static func matchesAbbreviated(rawTokens: [String], candidate: Student) -> Bool {
        let firstNameWords = normalizedTokens(candidate.firstName)
        guard !firstNameWords.isEmpty, rawTokens.count > firstNameWords.count else { return false }
        guard Array(rawTokens.prefix(firstNameWords.count)) == firstNameWords else { return false }

        let abbreviatedTokens = Array(rawTokens.suffix(from: firstNameWords.count))
        let lastNameWords = normalizedTokens(candidate.lastName)
        guard abbreviatedTokens.count <= lastNameWords.count else { return false }

        for (index, token) in abbreviatedTokens.enumerated() {
            guard token.count >= 2, lastNameWords[index].hasPrefix(token) else { return false }
        }
        return true
    }

    /// Mayúsculas, sin acentos/diacríticos, sin puntuación, separado en palabras.
    private static func normalizedTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.uppercased() }
            .filter { !$0.isEmpty }
    }
}
