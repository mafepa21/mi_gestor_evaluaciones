import Foundation
import ZIPFoundation

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
    var isInstrumento: Bool { tipoColumna == 14 }
    var isCategoriaSA: Bool { tipoColumna == 15 }
    var isElemento: Bool { tipoColumna == 14 || tipoColumna == 15 }
}

/// Un alumno en la plantilla de Educamos SM.
struct EducamosSMStudent {
    let rowIndex: Int               // Fila en el Excel (1-based: 13, 14, 15...)
    let personaId: String           // UUID del alumno en Educamos
    let orderNumber: Int            // Número de orden (1, 2, 3...)
    let rawName: String             // Nombre en Educamos ("Apellidos, Nombre" o alias)
    let clase: String               // "1BACB"
}

/// Plantilla completa parseada de Educamos SM.
struct EducamosSMTemplate {
    let metadata: EducamosSMMetadata
    let elements: [EducamosSMElement]
    let students: [EducamosSMStudent]
    let mainSheetPath: String       // Ruta dentro del zip: "xl/worksheets/sheet2.xml"
    let sourceURL: URL
    let originalFilename: String

    /// Columna de Nota final (TipoColumna=1)
    var notaFinalElement: EducamosSMElement? {
        elements.first(where: \.isNotaFinal)
    }

    /// Elementos correspondientes a instrumentos individuales (TipoColumna=14)
    var instrumentElements: [EducamosSMElement] {
        elements.filter(\.isInstrumento)
    }

    /// Elementos correspondientes a Situaciones de Aprendizaje / Categorías (TipoColumna=15)
    var categoriaElements: [EducamosSMElement] {
        elements.filter(\.isCategoriaSA)
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
            return "No se ha podido leer el archivo de Educamos. Asegúrate de seleccionar un archivo .xlsx válido."
        case .invalidFormat(let detail):
            return "El archivo no tiene el formato esperado de Educamos SM: \(detail)"
        case .noMainSheet:
            return "No se ha encontrado la hoja principal con datos de alumnos y materias."
        case .noStudents:
            return "No se han encontrado alumnos en el archivo."
        }
    }
}

// MARK: - XML Parsers (Foundation XMLParser)

private final class EducamosSMXMLParser: NSObject, XMLParserDelegate {
    private(set) var rows: [[String]] = []
    private var currentRow: [Int: String] = [:]
    private var currentCellColIndex: Int = 0
    private var currentCellRef: String = ""
    private var currentCellType: String = ""
    private var currentElement: String = ""
    private var currentText: String = ""
    private let sharedStrings: [String]
    private var rowIndex: Int = 0

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "row" {
            currentRow = [:]
            if let r = attributeDict["r"], let idx = Int(r) {
                rowIndex = idx
            } else {
                rowIndex += 1
            }
            currentCellColIndex = 0
        } else if elementName == "c" {
            currentCellRef = attributeDict["r"] ?? ""
            currentCellType = attributeDict["t"] ?? ""

            if !currentCellRef.isEmpty {
                currentCellColIndex = colIndex(from: currentCellRef)
            } else {
                currentCellColIndex += 1
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentCellType == "s", let sIndex = Int(text), sIndex >= 0 && sIndex < sharedStrings.count {
                currentRow[currentCellColIndex] = sharedStrings[sIndex]
            } else {
                currentRow[currentCellColIndex] = text
            }
        } else if elementName == "t" && currentElement == "t" {
            if currentCellType == "inlineStr" {
                currentRow[currentCellColIndex] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if elementName == "row" {
            guard let maxCol = currentRow.keys.max() else {
                rows.append([])
                return
            }
            let rowArray = (0...maxCol).map { currentRow[$0] ?? "" }
            rows.append(rowArray)
        }
    }

    private func colIndex(from cellRef: String) -> Int {
        var colLetters = ""
        for char in cellRef {
            if char.isLetter {
                colLetters.append(char)
            } else {
                break
            }
        }
        var index = 0
        for char in colLetters.uppercased() {
            guard let scalar = char.unicodeScalars.first, scalar.value >= 65 && scalar.value <= 90 else { continue }
            index = index * 26 + Int(scalar.value - 64)
        }
        return max(0, index - 1)
    }
}

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var currentString = ""
    private var insideSi = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "si" {
            insideSi = true
            currentString = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideSi {
            currentString += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "si" {
            insideSi = false
            strings.append(currentString)
        }
    }
}

// MARK: - Service

/// Parsea un `.xlsx` exportado de Educamos SM y extrae su estructura de forma robusta.
enum EducamosSMTemplateService {

    /// Parsea la plantilla de Educamos SM y devuelve un modelo estructurado.
    static func parse(from url: URL) throws -> EducamosSMTemplate {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw EducamosSMTemplateError.unreadableFile
        }

        // 1. Extraer sharedStrings.xml si existe
        var sharedStrings: [String] = []
        if let ssEntry = archive["xl/sharedStrings.xml"] {
            var data = Data()
            _ = try archive.extract(ssEntry) { data.append($0) }
            let parser = SharedStringsXMLParser()
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            xmlParser.parse()
            sharedStrings = parser.strings
        }

        // 2. Buscar todas las hojas en el ZIP
        let sheetEntries = archive.filter { $0.path.hasPrefix("xl/worksheets/sheet") && $0.path.hasSuffix(".xml") }
            .sorted { $0.path < $1.path }

        guard !sheetEntries.isEmpty else {
            throw EducamosSMTemplateError.noMainSheet
        }

        // 3. Parsear hojas hasta encontrar la principal
        var mainSheetPath: String?
        var mainRows: [[String]] = []

        for entry in sheetEntries {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            let parser = EducamosSMXMLParser(sharedStrings: sharedStrings)
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            xmlParser.parse()

            for row in parser.rows {
                if row.contains("ClaseMateriaId") || row.contains("PersonaId") {
                    mainSheetPath = entry.path
                    mainRows = parser.rows
                    break
                }
            }
            if mainSheetPath != nil { break }
        }

        guard let sheetPath = mainSheetPath, !mainRows.isEmpty else {
            throw EducamosSMTemplateError.noMainSheet
        }

        let metadata = try parseMetadata(from: mainRows)
        let elements = parseElements(from: mainRows)
        let students = parseStudents(from: mainRows, claseMateriaId: metadata.claseMateriaId)

        guard !students.isEmpty else {
            throw EducamosSMTemplateError.noStudents
        }

        return EducamosSMTemplate(
            metadata: metadata,
            elements: elements,
            students: students,
            mainSheetPath: sheetPath,
            sourceURL: url,
            originalFilename: url.lastPathComponent
        )
    }

    // MARK: - Private helpers

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
            guard row.count >= 2 else { continue }

            let personaId = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard personaId.contains("-") else { continue }

            var orderNumber = 0
            var rawName = ""
            var clase = ""

            // Buscar orden y nombre en columnas 2, 3, 4
            for colIdx in 2...min(4, row.count - 1) {
                let val = row[colIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                if let num = Int(val), orderNumber == 0 {
                    orderNumber = num
                } else if !val.isEmpty && !val.contains("-") && rawName.isEmpty {
                    rawName = val
                }
            }

            if orderNumber == 0 {
                orderNumber = students.count + 1
            }

            if row.count > 5 {
                clase = row[5].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            students.append(EducamosSMStudent(
                rowIndex: rowIdx + 1,
                personaId: personaId,
                orderNumber: orderNumber,
                rawName: rawName,
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
