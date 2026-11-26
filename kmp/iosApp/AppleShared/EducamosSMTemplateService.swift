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
    let fullName: String?           // Nombre descriptivo en Educamos ("Competencia motriz", "Balonmano"...)
    let uuid: String?               // UUID del elemento (nil para Nota/Rec/Comentarios)
    let tipoColumna: Int            // 14=Elemento, 15=Categoría, 1=Nota, 2=Rec, 20=Comentarios
    let parentSAColumnLetter: String? // Letra de la categoría SA (tipo 15) a la que pertenece este instrumento

    init(
        columnIndex: Int,
        columnLetter: String,
        shortName: String,
        fullName: String? = nil,
        uuid: String?,
        tipoColumna: Int,
        parentSAColumnLetter: String? = nil
    ) {
        self.columnIndex = columnIndex
        self.columnLetter = columnLetter
        self.shortName = shortName
        self.fullName = fullName
        self.uuid = uuid
        self.tipoColumna = tipoColumna
        self.parentSAColumnLetter = parentSAColumnLetter
    }

    var isNotaFinal: Bool { tipoColumna == 1 }
    var isRecuperacion: Bool { tipoColumna == 2 }
    var isComentarios: Bool { tipoColumna == 20 }
    var isInstrumento: Bool { tipoColumna == 14 }
    var isCategoriaSA: Bool { tipoColumna == 15 }
    var isElemento: Bool { tipoColumna == 14 || tipoColumna == 15 }

    /// Título legible para mostrar en la interfaz sin jerga interna del Excel.
    var displayTitle: String {
        if isNotaFinal { return "Nota final" }
        if isComentarios { return "Comentarios" }
        if let cleanFull = cleanedFullName {
            return cleanFull
        }
        return shortName
    }

    /// Código abreviado de Educamos cuando existe además un nombre descriptivo distinto.
    var secondaryCode: String? {
        guard !isNotaFinal, !isComentarios, let cleanFull = cleanedFullName else { return nil }
        let normShort = Self.comparableKey(shortName)
        let normFull = Self.comparableKey(cleanFull)
        return normShort == normFull ? nil : shortName
    }

    private var cleanedFullName: String? {
        guard let raw = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func comparableKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
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
    private(set) var rowNumbers: [Int] = []
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
            rowNumbers.append(rowIndex)
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

/// Extrae comentarios de celda (`xl/comments*.xml`), donde Educamos SM guarda la descripción
/// completa de cada elemento y categoría en la fila de cabecera (p. ej. `G12` -> «Competencia motriz»).
private final class CommentsXMLParser: NSObject, XMLParserDelegate {
    private(set) var commentsByCellRef: [String: String] = [:]
    private var authors: [String] = []
    private var insideAuthor = false
    private var insideComment = false
    private var insideTextRun = false
    private var currentAuthor = ""
    private var currentRef = ""
    private var currentCommentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "author":
            insideAuthor = true
            currentAuthor = ""
        case "comment":
            insideComment = true
            currentRef = (attributeDict["ref"] ?? "").uppercased()
            currentCommentText = ""
        case "t":
            if insideComment {
                insideTextRun = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideAuthor {
            currentAuthor += string
        } else if insideComment && insideTextRun {
            currentCommentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "author":
            insideAuthor = false
            let trimmed = currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                authors.append(trimmed)
            }
        case "t":
            insideTextRun = false
        case "comment":
            insideComment = false
            let cleaned = cleanCommentBody(currentCommentText)
            if !currentRef.isEmpty, !cleaned.isEmpty {
                commentsByCellRef[currentRef] = cleaned
            }
        default:
            break
        }
    }

    private func cleanCommentBody(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for author in authors where !author.isEmpty {
            if text.hasPrefix("\(author):") {
                text = String(text.dropFirst(author.count + 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
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

        // 3. Parsear hojas: localizar la principal y conservar las auxiliares (p. ej. descripciones)
        var mainSheetPath: String?
        var mainRows: [[String]] = []
        var mainRowNumbers: [Int] = []
        var auxiliarySheetRows: [[[String]]] = []

        for entry in sheetEntries {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            let parser = EducamosSMXMLParser(sharedStrings: sharedStrings)
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            xmlParser.parse()

            let isMain = parser.rows.contains { row in
                row.contains("ClaseMateriaId") || row.contains("PersonaId")
            }
            if isMain && mainSheetPath == nil {
                mainSheetPath = entry.path
                mainRows = parser.rows
                mainRowNumbers = parser.rowNumbers
            } else {
                auxiliarySheetRows.append(parser.rows)
            }
        }

        guard let sheetPath = mainSheetPath, !mainRows.isEmpty else {
            throw EducamosSMTemplateError.noMainSheet
        }

        // 4. Extraer comentarios de cabecera (xl/comments*.xml) con descripciones por celda
        var commentsByCellRef: [String: String] = [:]
        let commentEntries = archive.filter { $0.path.hasPrefix("xl/comments") && $0.path.hasSuffix(".xml") }
        for entry in commentEntries {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            let parser = CommentsXMLParser()
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            xmlParser.parse()
            for (ref, text) in parser.commentsByCellRef {
                commentsByCellRef[ref] = text
            }
        }

        let metadata = try parseMetadata(from: mainRows)
        let elements = parseElements(
            from: mainRows,
            rowNumbers: mainRowNumbers,
            auxiliarySheets: auxiliarySheetRows,
            commentsByCellRef: commentsByCellRef
        )
        let students = parseStudents(
            from: mainRows,
            rowNumbers: mainRowNumbers,
            claseMateriaId: metadata.claseMateriaId
        )

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

    private static let localizedStudentHeaderLabels: Set<String> = [
        "alumnos", "alumnes", "alumnado", "alumnat", "students", "ikasleak"
    ]

    private static let localizedClassHeaderLabels: Set<String> = [
        "clase", "classe", "class", "grupo", "grup", "taldea"
    ]

    /// Localiza la fila de cabecera del alumnado usando la clave técnica `PersonaId`
    /// (independiente del idioma del centro) con respaldo por etiquetas localizadas.
    private static func findHeaderRowIndex(in rows: [[String]]) -> Int? {
        if let technicalIdx = rows.firstIndex(where: { row in
            row.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "PersonaId" }
        }) {
            return technicalIdx
        }
        return rows.firstIndex(where: { row in
            row.contains { cell in
                let normalized = cell
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return localizedStudentHeaderLabels.contains(normalized)
            }
        })
    }

    private static func parseElements(
        from rows: [[String]],
        rowNumbers: [Int],
        auxiliarySheets: [[[String]]],
        commentsByCellRef: [String: String]
    ) -> [EducamosSMElement] {
        guard let tipoColumnaRowIndex = rows.firstIndex(where: { $0.contains("TipoColumna") }),
              let headerRowIndex = findHeaderRowIndex(in: rows)
        else { return [] }

        let tipoColumnaRow = rows[tipoColumnaRowIndex]
        let headerRow = rows[headerRowIndex]
        let headerExcelRow = headerRowIndex < rowNumbers.count ? rowNumbers[headerRowIndex] : (headerRowIndex + 1)

        let uuidRowIndex = tipoColumnaRowIndex + 1
        let uuidRow = uuidRowIndex < rows.count ? rows[uuidRowIndex] : []

        let claseIdx = headerRow.firstIndex(where: { cell in
            let normalized = cell
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return localizedClassHeaderLabels.contains(normalized)
        }) ?? tipoColumnaRow.firstIndex(of: "TipoColumna")
        guard let claseIdx else { return [] }
        let startColIndex = claseIdx + 1

        struct DraftElement {
            let columnIndex: Int
            let columnLetter: String
            let shortName: String
            let uuid: String?
            let tipoColumna: Int
        }

        var drafts: [DraftElement] = []
        for colIdx in startColIndex..<headerRow.count {
            let name = headerRow[colIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let tipoStr = colIdx < tipoColumnaRow.count ? tipoColumnaRow[colIdx] : ""
            let tipo = Int(tipoStr) ?? 0

            let uuid = colIdx < uuidRow.count ? uuidRow[colIdx] : ""
            let uuidValue = uuid.trimmingCharacters(in: .whitespacesAndNewlines)

            drafts.append(DraftElement(
                columnIndex: colIdx,
                columnLetter: spreadsheetColumnLetter(for: colIdx),
                shortName: name,
                uuid: uuidValue.isEmpty ? nil : uuidValue,
                tipoColumna: tipo
            ))
        }

        // Extraer mapa shortName -> descripción desde la hoja «Descripción elementos y categor»
        let knownShortNames = Set(drafts.map(\.shortName))
        var descriptionByShortName: [String: String] = [:]
        for sheetRows in auxiliarySheets {
            for row in sheetRows {
                let nonEmpty = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                guard nonEmpty.count >= 2 else { continue }
                if knownShortNames.contains(nonEmpty[0]), descriptionByShortName[nonEmpty[0]] == nil {
                    descriptionByShortName[nonEmpty[0]] = nonEmpty[1]
                }
            }
        }

        // En Educamos SM los instrumentos (tipo 14) preceden inmediatamente a la categoría/SA (tipo 15)
        // que agrupa su bloque (p. ej. [AUT, CM, TG] -> Beis; [Seg, C.M., T-T, A.H] -> Hock).
        var parentSAByLetter: [String: String] = [:]
        var pendingInstrumentLetters: [String] = []
        for draft in drafts {
            if draft.tipoColumna == 14 {
                pendingInstrumentLetters.append(draft.columnLetter)
            } else if draft.tipoColumna == 15 {
                for letter in pendingInstrumentLetters {
                    parentSAByLetter[letter] = draft.columnLetter
                }
                pendingInstrumentLetters.removeAll()
            } else {
                pendingInstrumentLetters.removeAll()
            }
        }

        return drafts.map { draft in
            let exactCellRef = "\(draft.columnLetter)\(headerExcelRow)"
            let commentDescription = commentsByCellRef[exactCellRef]
            let resolvedFullName = commentDescription ?? descriptionByShortName[draft.shortName]

            return EducamosSMElement(
                columnIndex: draft.columnIndex,
                columnLetter: draft.columnLetter,
                shortName: draft.shortName,
                fullName: resolvedFullName,
                uuid: draft.uuid,
                tipoColumna: draft.tipoColumna,
                parentSAColumnLetter: parentSAByLetter[draft.columnLetter]
            )
        }
    }

    private static func parseStudents(
        from rows: [[String]],
        rowNumbers: [Int],
        claseMateriaId: String
    ) -> [EducamosSMStudent] {
        guard let headerRowIndex = findHeaderRowIndex(in: rows) else {
            return []
        }

        let headerRow = rows[headerRowIndex]
        let personaIdColIndex = headerRow.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "PersonaId"
        }) ?? 1
        let claseColIndex = headerRow.firstIndex(where: { cell in
            let normalized = cell
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return localizedClassHeaderLabels.contains(normalized)
        }) ?? 5

        let dataStartIndex = headerRowIndex + 1
        var students: [EducamosSMStudent] = []

        for rowIdx in dataStartIndex..<rows.count {
            let row = rows[rowIdx]
            guard row.count > personaIdColIndex else { continue }

            let personaId = row[personaIdColIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard personaId.contains("-") else { continue }

            var orderNumber = 0
            var rawName = ""
            var clase = ""

            // Buscar orden y nombre entre PersonaId y la columna de Clase
            let nameSearchStart = personaIdColIndex + 1
            let nameSearchEnd = min(claseColIndex - 1, row.count - 1)
            if nameSearchStart <= nameSearchEnd {
                for colIdx in nameSearchStart...nameSearchEnd {
                    let val = row[colIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let num = Int(val), orderNumber == 0 {
                        orderNumber = num
                    } else if !val.isEmpty && !val.contains("-") && rawName.isEmpty {
                        rawName = val
                    }
                }
            }

            if orderNumber == 0 {
                orderNumber = students.count + 1
            }

            if row.count > claseColIndex {
                clase = row[claseColIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let excelRowNumber = rowIdx < rowNumbers.count ? rowNumbers[rowIdx] : (rowIdx + 1)

            students.append(EducamosSMStudent(
                rowIndex: excelRowNumber,
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
