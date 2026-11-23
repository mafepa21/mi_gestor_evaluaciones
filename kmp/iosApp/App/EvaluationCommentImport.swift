import Foundation
import CoreXLSX

// Importación de comentarios de evaluación desde Excel.
//
// Regla del docente: la primera fila con comentario va al primer alumno del Cuaderno,
// la segunda al segundo, y así con todos. Las filas vacías cuentan: un alumno sin comentario
// no desplaza a los siguientes. Si el archivo es una plantilla de Educamos, se usan sus filas
// de alumnado y su columna de comentarios (TipoColumna=20), en el mismo orden.
// Este archivo no toca KMP ni la base de datos.

/// Celdas de una hoja, por número de fila (1-based) e índice de columna (0-based).
struct EvaluationCommentTable: Equatable {
    var cellsByRow: [Int: [Int: String]]

    init(cellsByRow: [Int: [Int: String]]) {
        self.cellsByRow = cellsByRow
    }

    /// Filas seguidas desde la fila 1. Para pruebas y CSV.
    init(rows: [[String]]) {
        var cells: [Int: [Int: String]] = [:]
        for (rowOffset, row) in rows.enumerated() {
            var rowCells: [Int: String] = [:]
            for (column, value) in row.enumerated() where !value.isEmpty {
                rowCells[column] = value
            }
            if !rowCells.isEmpty { cells[rowOffset + 1] = rowCells }
        }
        self.cellsByRow = cells
    }

    func value(row: Int, column: Int) -> String {
        (cellsByRow[row]?[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var columnIndexes: [Int] {
        Array(Set(cellsByRow.values.flatMap(\.keys))).sorted()
    }

    /// Filas con texto en una columna, de arriba abajo.
    func filledRows(in column: Int) -> [Int] {
        cellsByRow.keys.sorted().filter { !value(row: $0, column: column).isEmpty }
    }
}

/// Dónde están el alumnado y los comentarios en una plantilla de Educamos.
struct EvaluationCommentEducamosLayout: Equatable {
    let studentRows: [Int]
    let commentsColumn: Int
    /// Nombre de cada alumno en el Excel, para comprobar el orden en la revisión.
    var studentNames: [String] = []
}

struct EvaluationCommentColumnOption: Identifiable, Hashable {
    let index: Int
    let letter: String
    let title: String
    let filledCount: Int
    var id: Int { index }

    var label: String { title.isEmpty ? letter : "\(letter) · \(title)" }
}

struct EvaluationCommentStudent: Equatable {
    let id: Int64
    let displayName: String
    let existingComment: String
}

struct EvaluationCommentPlan: Equatable {
    struct Entry: Equatable, Identifiable {
        let position: Int
        let student: EvaluationCommentStudent
        /// `nil` cuando su fila está vacía: el alumno se queda como está.
        let newComment: String?
        /// Nombre que trae el Excel en esa fila (solo plantillas de Educamos).
        var sourceName: String? = nil

        var id: Int64 { student.id }
        var changes: Bool { newComment != nil && newComment != student.existingComment }
        var replacesExisting: Bool { changes && !student.existingComment.isEmpty }
    }

    let entries: [Entry]
    /// Comentarios con texto en el archivo, dentro del tramo leído.
    let sourceCount: Int
    /// Comentarios que sobran porque hay menos alumnos que filas.
    let extraCount: Int
    /// Emparejado por código «Alumno NN» del informe anónimo, no por orden.
    var matchedByCode = false
    /// Códigos del archivo que no corresponden a ningún alumno del grupo.
    var unknownCodes: [String] = []

    var importCount: Int { entries.filter(\.changes).count }
    var replaceCount: Int { entries.filter(\.replacesExisting).count }
    var emptyCount: Int { entries.filter { $0.newComment == nil }.count }
    var countsDiffer: Bool { !matchedByCode && sourceCount != entries.count }
}

enum EvaluationCommentImportError: LocalizedError {
    case unreadableFile
    case noTextColumns

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "No se pudo leer el archivo. Debe ser un .xlsx."
        case .noTextColumns:
            return "El archivo no tiene ninguna columna con texto."
        }
    }
}

enum EvaluationCommentImport {
    static let maxTitleLength = 40
    private static let headerKeywords = ["comentario", "observacion", "texto", "valoracion", "evaluacion", "alumno", "nombre"]

    // MARK: - Lectura

    /// Lee la hoja del archivo. Con plantilla de Educamos, lee su hoja principal.
    static func readTable(from url: URL, sheetPath: String? = nil) throws -> EvaluationCommentTable {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "csv" {
            return EvaluationCommentTable(rows: try AppleSpreadsheetReader.readRows(from: url))
        }
        guard let file = XLSXFile(filepath: url.path),
              let workbook = try? file.parseWorkbooks().first,
              let paths = try? file.parseWorksheetPathsAndNames(workbook: workbook),
              !paths.isEmpty else {
            throw EvaluationCommentImportError.unreadableFile
        }
        let sharedStrings = try? file.parseSharedStrings()
        let firstColumn = ColumnReference("A")!

        func table(at path: String) -> EvaluationCommentTable? {
            guard let worksheet = try? file.parseWorksheet(at: path) else { return nil }
            var cells: [Int: [Int: String]] = [:]
            for row in worksheet.data?.rows ?? [] {
                var rowCells: [Int: String] = [:]
                for cell in row.cells {
                    let text = cell.inlineString?.text
                        ?? sharedStrings.flatMap { cell.stringValue($0) }
                        ?? cell.value
                        ?? ""
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    rowCells[firstColumn.distance(to: cell.reference.column)] = text
                }
                if !rowCells.isEmpty { cells[Int(row.reference)] = rowCells }
            }
            return EvaluationCommentTable(cellsByRow: cells)
        }

        if let sheetPath, let sheet = table(at: normalizedSheetPath(sheetPath)) ?? table(at: sheetPath) {
            return sheet
        }
        for entry in paths {
            if let sheet = table(at: entry.path), !sheet.cellsByRow.isEmpty { return sheet }
        }
        throw EvaluationCommentImportError.noTextColumns
    }

    /// CoreXLSX trabaja con rutas absolutas dentro del zip («/xl/worksheets/sheet2.xml»).
    static func normalizedSheetPath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/" + path
    }

    // MARK: - Columnas

    static func columnOptions(
        table: EvaluationCommentTable,
        educamos: EvaluationCommentEducamosLayout?
    ) -> [EvaluationCommentColumnOption] {
        table.columnIndexes.compactMap { column in
            let rows = table.filledRows(in: column)
            let texts = rows.map { table.value(row: $0, column: column) }
            // La primera celda puede ser el título («Nota»): no basta para que la columna sea de texto.
            let body = texts.count > 1 ? Array(texts.dropFirst()) : texts
            guard body.contains(where: { !isNumeric($0) }) else { return nil }
            let title: String
            if let educamos, educamos.commentsColumn == column {
                title = "Comentarios (Educamos)"
            } else if let first = texts.first, first.count <= maxTitleLength {
                title = first
            } else {
                title = ""
            }
            return EvaluationCommentColumnOption(
                index: column,
                letter: columnLetter(for: column),
                title: title,
                filledCount: texts.count
            )
        }
    }

    /// Educamos: su columna de comentarios. Si no, la columna con más texto.
    static func suggestedColumn(table: EvaluationCommentTable, educamos: EvaluationCommentEducamosLayout?) -> Int? {
        if let educamos { return educamos.commentsColumn }
        let options = columnOptions(table: table, educamos: nil)
        return options.max { lhs, rhs in
            textWeight(table: table, column: lhs.index) < textWeight(table: table, column: rhs.index)
        }?.index
    }

    /// La primera celda con texto parece un título: corta, sin punto final y con una palabra
    /// típica de cabecera, o mucho más corta que el resto.
    static func looksLikeHeader(table: EvaluationCommentTable, column: Int) -> Bool {
        let texts = table.filledRows(in: column).map { table.value(row: $0, column: column) }
        guard texts.count >= 2, let first = texts.first, first.count <= maxTitleLength, !first.hasSuffix(".") else {
            return false
        }
        let folded = first.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
        if headerKeywords.contains(where: { folded.contains($0) }) { return true }
        let rest = texts.dropFirst()
        let averageRest = Double(rest.reduce(0) { $0 + $1.count }) / Double(rest.count)
        return averageRest >= Double(first.count) * 2
    }

    // MARK: - Códigos del informe anónimo

    /// Número de un código «Alumno 07» (también «alumno 7», «ALUMNO 007»).
    static func codeNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(of: #"^alumno\s+(\d{1,4})$"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let digits = trimmed[match].split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        return Int(digits)
    }

    /// Columna con códigos «Alumno NN»: al menos 2 y casi todas sus celdas (sin contar el título) lo son.
    static func codeColumn(table: EvaluationCommentTable) -> Int? {
        table.columnIndexes.first { column in
            let texts = table.filledRows(in: column).map { table.value(row: $0, column: column) }
            let codes = texts.filter { codeNumber($0) != nil }.count
            let body = codeNumber(texts.first ?? "") == nil ? texts.count - 1 : texts.count
            return codes >= 2 && Double(codes) >= Double(max(body, 1)) * 0.8
        }
    }

    /// Empareja por código: cada fila va al alumno que indica la clave, sin importar el orden.
    static func planByCode(
        table: EvaluationCommentTable,
        codeColumn: Int,
        commentColumn: Int,
        key: [Int: Int64],
        students: [EvaluationCommentStudent]
    ) -> EvaluationCommentPlan {
        var commentByStudent: [Int64: (code: String, text: String)] = [:]
        var unknown: [String] = []
        var sourceCount = 0
        for row in table.filledRows(in: codeColumn) {
            let codeText = table.value(row: row, column: codeColumn)
            guard let number = codeNumber(codeText) else { continue }
            let text = table.value(row: row, column: commentColumn)
            guard !text.isEmpty else { continue }
            sourceCount += 1
            guard let studentId = key[number], students.contains(where: { $0.id == studentId }) else {
                unknown.append(codeText)
                continue
            }
            commentByStudent[studentId] = (codeText, text)
        }
        let entries = students.enumerated().map { offset, student in
            EvaluationCommentPlan.Entry(
                position: offset + 1,
                student: student,
                newComment: commentByStudent[student.id]?.text,
                sourceName: commentByStudent[student.id]?.code
            )
        }
        return EvaluationCommentPlan(
            entries: entries,
            sourceCount: sourceCount,
            extraCount: 0,
            matchedByCode: true,
            unknownCodes: unknown
        )
    }

    // MARK: - Emparejamiento

    static func plan(
        table: EvaluationCommentTable,
        educamos: EvaluationCommentEducamosLayout?,
        column: Int,
        skipHeader: Bool,
        students: [EvaluationCommentStudent]
    ) -> EvaluationCommentPlan {
        let sourceRows: [Int]
        if let educamos {
            sourceRows = educamos.studentRows
        } else {
            let filled = table.filledRows(in: column)
            guard let first = filled.first, let last = filled.last else {
                return EvaluationCommentPlan(
                    entries: students.enumerated().map { .init(position: $0.offset + 1, student: $0.element, newComment: nil) },
                    sourceCount: 0,
                    extraCount: 0
                )
            }
            let start = skipHeader ? first + 1 : first
            sourceRows = start <= last ? Array(start...last) : []
        }

        let values = sourceRows.map { table.value(row: $0, column: column) }
        let entries = students.enumerated().map { offset, student in
            let text = offset < values.count ? values[offset] : ""
            let names = educamos?.studentNames ?? []
            return EvaluationCommentPlan.Entry(
                position: offset + 1,
                student: student,
                newComment: text.isEmpty ? nil : text,
                sourceName: offset < names.count ? names[offset].nilIfBlank : nil
            )
        }
        let extra = values.dropFirst(students.count).filter { !$0.isEmpty }.count
        return EvaluationCommentPlan(
            entries: entries,
            sourceCount: values.filter { !$0.isEmpty }.count,
            extraCount: extra
        )
    }

    // MARK: - Ayudas

    static func columnLetter(for zeroBasedIndex: Int) -> String {
        var index = zeroBasedIndex + 1
        var letters = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            index = (index - 1) / 26
        }
        return letters
    }

    private static func isNumeric(_ text: String) -> Bool {
        Double(text.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private static func textWeight(table: EvaluationCommentTable, column: Int) -> Int {
        table.filledRows(in: column)
            .map { table.value(row: $0, column: column) }
            .filter { !isNumeric($0) }
            .reduce(0) { $0 + $1.count }
    }
}
