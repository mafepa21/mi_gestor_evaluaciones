import CoreXLSX
import Foundation

// MARK: - Models

/// Metadata del centro y evaluación extraída de la cabecera del xlsx de Educamos SM.
struct EducamosSMMetadata {
    let modelo: String              // "CuadernoCompetenciasItems"
    let colegioId: Int
    let calendarioEscolarId: String // UUID
    let claseMateriaId: String      // UUID
    let evaluacionId: String        // UUID
    let ficheroId: String           // UUID
    let materia: String             // "Educación física"
    let evaluacion: String          // "PRIMERA EVALUACIÓN"
    let cursoEscolar: String        // "2026-2027"
    let colegio: String             // Nombre completo del colegio
}

/// Un elemento/columna del cuaderno de Educamos SM.
struct EducamosSMElement {
    let columnIndex: Int            // Índice de columna en el Excel (0-based, G=6, H=7...)
    let columnLetter: String        // "G", "H", "I"... para referencia de celdas
    let shortName: String           // "mo", "Hab", "Hand"...
    let uuid: String?               // UUID del elemento (nil para Nota/Rec/Comentarios)
    let tipoColumna: Int            // 14=Elemento, 15=Categoría, 1=Nota, 2=Rec, 20=Comentarios

    var isNotaFinal: Bool { tipoColumna == 1 }
    var isRecuperacion: Bool { tipoColumna == 2 }
    var isComentarios: Bool { tipoColumna == 20 }
    var isElemento: Bool { tipoColumna == 14 || tipoColumna == 15 }
}

/// Un alumno en la plantilla de Educamos SM.
struct EducamosSMStudent {
    let rowIndex: Int               // Fila en el Excel (1-based: 13, 14, 15...)
    let personaId: String           // UUID del alumno en Educamos
    let orderNumber: Int            // Número de orden (1, 2, 3...)
    let clase: String               // "1BACB"
}

/// Plantilla completa parseada de Educamos SM.
struct EducamosSMTemplate {
    let metadata: EducamosSMMetadata
    let elements: [EducamosSMElement]
    let students: [EducamosSMStudent]
    let mainSheetName: String       // Nombre de la hoja principal
    let mainSheetIndex: Int         // Índice de la hoja en el workbook (0-based)
    let sourceURL: URL

    /// Columna de Nota final (TipoColumna=1)
    var notaFinalElement: EducamosSMElement? {
        elements.first(where: \.isNotaFinal)
    }

    /// Columna de Comentarios del profesor (TipoColumna=20)
    var comentariosElement: EducamosSMElement? {
        elements.first(where: \.isComentarios)
    }
}

// MARK: - Errors

enum EducamosSMTemplateError: LocalizedError {
    case unreadableFile
    case invalidFormat(String)
    case noMainSheet
    case noStudents

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "No se ha podido leer el archivo de Educamos."
        case .invalidFormat(let detail):
            return "El archivo no tiene el formato esperado de Educamos SM: \(detail)"
        case .noMainSheet:
            return "No se ha encontrado la hoja principal con datos de alumnos."
        case .noStudents:
            return "No se han encontrado alumnos en el archivo."
        }
    }
}

// MARK: - Service

/// Parsea un `.xlsx` exportado de Educamos SM y extrae su estructura.
enum EducamosSMTemplateService {

    /// Parsea la plantilla de Educamos SM y devuelve un modelo estructurado.
    static func parse(from url: URL) throws -> EducamosSMTemplate {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Leer todas las hojas como texto plano (reutilizando AppleSpreadsheetReader)
        let allSheets = try AppleSpreadsheetReader.readAllXLSXSheets(from: url)

        // Encontrar la hoja principal: la que tiene "ClaseMateriaId" o "PersonaId" en alguna fila
        guard let (mainSheetIndex, mainSheet) = findMainSheet(in: allSheets) else {
            throw EducamosSMTemplateError.noMainSheet
        }

        // Parsear metadata de las filas de cabecera
        let metadata = try parseMetadata(from: mainSheet.rows)

        // Parsear tipos de columna y UUIDs de elementos
        let elements = parseElements(from: mainSheet.rows)

        // Parsear alumnos
        let students = parseStudents(from: mainSheet.rows, claseMateriaId: metadata.claseMateriaId)

        guard !students.isEmpty else {
            throw EducamosSMTemplateError.noStudents
        }

        return EducamosSMTemplate(
            metadata: metadata,
            elements: elements,
            students: students,
            mainSheetName: mainSheet.name,
            mainSheetIndex: mainSheetIndex,
            sourceURL: url
        )
    }

    // MARK: - Private helpers

    private static func findMainSheet(
        in sheets: [(name: String, rows: [[String]])]
    ) -> (Int, (name: String, rows: [[String]]))? {
        for (index, sheet) in sheets.enumerated() {
            for row in sheet.rows {
                if row.contains("ClaseMateriaId") || row.contains("PersonaId") {
                    return (index, sheet)
                }
            }
        }
        // Fallback: buscar la hoja con más filas que no sea "Export Summary" ni "Leyenda"
        let candidates = sheets.enumerated().filter { (_, sheet) in
            !sheet.name.lowercased().contains("export") &&
            !sheet.name.lowercased().contains("leyenda") &&
            !sheet.name.lowercased().contains("descripci")
        }
        return candidates.max(by: { $0.1.rows.count < $1.1.rows.count })
    }

    private static func parseMetadata(from rows: [[String]]) throws -> EducamosSMMetadata {
        func findRow(label: String) -> [String]? {
            rows.first { $0.contains(label) }
        }

        func value(in row: [String]?, afterLabel label: String) -> String {
            guard let row = row, let idx = row.firstIndex(of: label) else { return "" }
            let valueIdx = idx + 1
            return valueIdx < row.count ? row[valueIdx] : ""
        }

        let modeloRow = findRow(label: "Modelo")
        let colegioRow = findRow(label: "ColegioId")
        let calendarioRow = findRow(label: "CalendarioEscolarId")
        let materiaRow = findRow(label: "ClaseMateriaId")
        let evaluacionRow = findRow(label: "EvaluacionId")
        let ficheroRow = findRow(label: "FicheroId")

        let modelo = value(in: modeloRow, afterLabel: "Modelo")
        let colegioIdStr = value(in: colegioRow, afterLabel: "ColegioId")
        let colegioId = Int(colegioIdStr) ?? 0

        func descriptiveValue(in row: [String]?) -> String {
            guard let row = row, row.count > 4 else { return "" }
            for i in 3..<row.count {
                let v = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { return v }
            }
            return ""
        }

        return EducamosSMMetadata(
            modelo: modelo,
            colegioId: colegioId,
            calendarioEscolarId: value(in: calendarioRow, afterLabel: "CalendarioEscolarId"),
            claseMateriaId: value(in: materiaRow, afterLabel: "ClaseMateriaId"),
            evaluacionId: value(in: evaluacionRow, afterLabel: "EvaluacionId"),
            ficheroId: value(in: ficheroRow, afterLabel: "FicheroId"),
            materia: descriptiveValue(in: materiaRow),
            evaluacion: descriptiveValue(in: evaluacionRow),
            cursoEscolar: descriptiveValue(in: calendarioRow),
            colegio: descriptiveValue(in: colegioRow)
        )
    }

    private static func parseElements(from rows: [[String]]) -> [EducamosSMElement] {
        guard let tipoColumnaRowIndex = rows.firstIndex(where: { $0.contains("TipoColumna") }),
              let headerRowIndex = rows.firstIndex(where: { $0.contains("Alumnos") })
        else { return [] }

        let tipoColumnaRow = rows[tipoColumnaRowIndex]
        let headerRow = rows[headerRowIndex]

        let uuidRowIndex = tipoColumnaRowIndex + 1
        let uuidRow = uuidRowIndex < rows.count ? rows[uuidRowIndex] : []

        guard let claseIdx = headerRow.firstIndex(of: "Clase") else { return [] }
        let startColIndex = claseIdx + 1

        var elements: [EducamosSMElement] = []

        for colIdx in startColIndex..<headerRow.count {
            let name = headerRow[colIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let tipoStr = colIdx < tipoColumnaRow.count ? tipoColumnaRow[colIdx] : ""
            let tipo = Int(tipoStr) ?? 0

            let uuid = colIdx < uuidRow.count ? uuidRow[colIdx] : ""
            let uuidValue = uuid.trimmingCharacters(in: .whitespacesAndNewlines)

            elements.append(EducamosSMElement(
                columnIndex: colIdx,
                columnLetter: spreadsheetColumnLetter(for: colIdx),
                shortName: name,
                uuid: uuidValue.isEmpty ? nil : uuidValue,
                tipoColumna: tipo
            ))
        }

        return elements
    }

    private static func parseStudents(
        from rows: [[String]],
        claseMateriaId: String
    ) -> [EducamosSMStudent] {
        guard let headerRowIndex = rows.firstIndex(where: { $0.contains("Alumnos") }) else {
            return []
        }

        let dataStartIndex = headerRowIndex + 1
        var students: [EducamosSMStudent] = []

        for rowIdx in dataStartIndex..<rows.count {
            let row = rows[rowIdx]
            guard row.count >= 3 else { continue }

            let personaId = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let orderStr = row[2].trimmingCharacters(in: .whitespacesAndNewlines)

            guard personaId.contains("-"),
                  let orderNumber = Int(orderStr)
            else { continue }

            var clase = ""
            if row.count > 5 {
                clase = row[5].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            students.append(EducamosSMStudent(
                rowIndex: rowIdx + 1, // Convertir a 1-based (fila Excel)
                personaId: personaId,
                orderNumber: orderNumber,
                clase: clase
            ))
        }

        return students
    }

    /// Convierte un índice de columna 0-based a letra(s) de hoja de cálculo.
    private static func spreadsheetColumnLetter(for zeroBasedIndex: Int) -> String {
        var index = zeroBasedIndex + 1
        var result = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            index = (index - 1) / 26
        }
        return result
    }
}
