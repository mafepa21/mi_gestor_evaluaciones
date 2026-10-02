import Foundation
import ZIPFoundation

// MARK: - Errors

enum EducamosSMXlsxWriterError: LocalizedError {
    case cannotCopyTemplate
    case cannotOpenArchive
    case sheetNotFound(String)
    case cannotReadSheetXML
    case cannotWriteSheetXML

    var errorDescription: String? {
        switch self {
        case .cannotCopyTemplate:
            return "No se ha podido copiar la plantilla de Educamos."
        case .cannotOpenArchive:
            return "No se ha podido abrir el archivo xlsx para escritura."
        case .sheetNotFound(let name):
            return "No se ha encontrado la hoja '\(name)' en el archivo."
        case .cannotReadSheetXML:
            return "No se ha podido leer el XML de la hoja de cálculo."
        case .cannotWriteSheetXML:
            return "No se ha podido escribir los cambios en la hoja de cálculo."
        }
    }
}

// MARK: - Cell value to write

/// Valor a escribir en una celda del xlsx.
enum EducamosSMCellValue {
    case integer(Int)       // Nota entera 0-10
    case decimal(Double)    // Nota decimal (ej. 9.38)
    case numeric(Int)       // Compatibilidad retroactiva
    case text(String)       // Comentario de texto

    var xmlFragment: String {
        switch self {
        case .integer(let value), .numeric(let value):
            return "<v>\(value)</v>"
        case .decimal(let value):
            let formatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
            let clean: String
            if formatted.hasSuffix(".00") {
                clean = String(formatted.dropLast(3))
            } else if formatted.hasSuffix("0") && formatted.contains(".") {
                clean = String(formatted.dropLast(1))
            } else {
                clean = formatted
            }
            return "<v>\(clean)</v>"
        case .text(let value):
            let escaped = value.xmlEscaped
            return "<is><t>\(escaped)</t></is>"
        }
    }

    /// Atributo de tipo para la celda. Numéricos no necesitan tipo; texto usa `t="inlineStr"`.
    var typeAttribute: String? {
        switch self {
        case .integer, .decimal, .numeric: return nil
        case .text: return "inlineStr"
        }
    }
}

// MARK: - Writer

/// Modifica un `.xlsx` de Educamos SM rellenando celdas de calificaciones.
///
/// Estrategia: copia el archivo original, abre el ZIP, localiza el XML de la hoja
/// principal, inyecta valores en las celdas especificadas, y devuelve la URL del
/// archivo modificado.
enum EducamosSMXlsxWriter {

    /// Estructura que define una celda a rellenar.
    struct CellWrite {
        let cellReference: String   // "M13", "O13"
        let value: EducamosSMCellValue
    }

    /// Rellena celdas en el xlsx de Educamos y devuelve la URL del archivo generado.
    ///
    /// - Parameters:
    ///   - template: Plantilla parseada de Educamos SM
    ///   - cells: Lista de celdas a rellenar con sus valores
    /// - Returns: URL del archivo xlsx modificado, listo para compartir
    static func fillGrades(
        template: EducamosSMTemplate,
        cells: [CellWrite]
    ) throws -> URL {
        // 1. Copiar la plantilla a un directorio temporal conservando el nombre original
        let tempDir = FileManager.default.temporaryDirectory
        let outputFilename = template.originalFilename.isEmpty ? "Educamos_export.xlsx" : template.originalFilename
        let outputURL = tempDir.appendingPathComponent(outputFilename)

        // Limpiar si existe un archivo previo
        try? FileManager.default.removeItem(at: outputURL)

        // Acceso seguro al archivo fuente
        let didStartAccessing = template.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                template.sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: template.sourceURL, to: outputURL)
        } catch {
            throw EducamosSMXlsxWriterError.cannotCopyTemplate
        }

        // 2. Ruta del XML de la hoja principal dentro del ZIP
        let sheetXMLPath = template.mainSheetPath

        // 3. Modificar el XML dentro de un scope para asegurar flush del ZIP antes de retornar
        try modifySheetArchive(at: outputURL, sheetPath: sheetXMLPath, cells: cells)

        return outputURL
    }

    private static func modifySheetArchive(
        at fileURL: URL,
        sheetPath: String,
        cells: [CellWrite]
    ) throws {
        guard let archive = try? Archive(url: fileURL, accessMode: .update) else {
            throw EducamosSMXlsxWriterError.cannotOpenArchive
        }

        guard let sheetEntry = archive[sheetPath] else {
            throw EducamosSMXlsxWriterError.sheetNotFound(sheetPath)
        }

        var xmlData = Data()
        _ = try archive.extract(sheetEntry) { chunk in
            xmlData.append(chunk)
        }

        guard var xmlString = String(data: xmlData, encoding: .utf8) else {
            throw EducamosSMXlsxWriterError.cannotReadSheetXML
        }

        // Agrupar modificaciones por fila y por número de columna
        var writesByRow: [Int: [Int: ParsedWrite]] = [:]
        for cell in cells {
            if let parsed = parseCellReference(cell.cellReference) {
                let write = ParsedWrite(
                    cellReference: cell.cellReference,
                    colLetters: parsed.colLetters,
                    colNumber: parsed.colNumber,
                    rowNumber: parsed.rowNumber,
                    value: cell.value
                )
                writesByRow[parsed.rowNumber, default: [:]][parsed.colNumber] = write
            }
        }

        // Actualizar cada fila en el XML in-place
        // Ordenamos las filas de mayor a menor para que la sustitución de rangos no desplace los índices anteriores
        let sortedRowNumbers = writesByRow.keys.sorted(by: >)
        for rowNum in sortedRowNumbers {
            if let colWrites = writesByRow[rowNum] {
                xmlString = updateRowInPlace(xml: xmlString, rowNumber: rowNum, colWrites: colWrites)
            }
        }

        guard let modifiedData = xmlString.data(using: .utf8) else {
            throw EducamosSMXlsxWriterError.cannotWriteSheetXML
        }

        // Eliminar la entrada antigua y añadir la nueva con compresión deflate
        try archive.remove(sheetEntry)
        try archive.addEntry(
            with: sheetPath,
            type: .file,
            uncompressedSize: Int64(modifiedData.count),
            compressionMethod: .deflate,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, modifiedData.count)
                return modifiedData[start..<end]
            }
        )
    }

    // MARK: - Row & Cell parsing and in-place updates

    private struct ParsedWrite {
        let cellReference: String
        let colLetters: String
        let colNumber: Int      // 1-based (A=1, B=2, G=7, H=8, I=9, M=13)
        let rowNumber: Int
        let value: EducamosSMCellValue
    }

    private struct RawCell {
        let rawXML: String
        let colNumber: Int
        let hasExplicitR: Bool
        let styleAttribute: String?     // e.g. "s=\"70\""
    }

    /// Convierte una referencia de celda tipo "M13" en letras de columna, índice numérico de columna y número de fila.
    private static func parseCellReference(_ ref: String) -> (colLetters: String, colNumber: Int, rowNumber: Int)? {
        var letters = ""
        var digits = ""
        for ch in ref {
            if ch.isLetter {
                letters.append(ch)
            } else if ch.isNumber {
                digits.append(ch)
            }
        }
        guard !letters.isEmpty, let rowNum = Int(digits) else { return nil }
        var colNum = 0
        for ch in letters.uppercased() {
            guard let scalar = ch.unicodeScalars.first, scalar.value >= 65 && scalar.value <= 90 else { return nil }
            colNum = colNum * 26 + Int(scalar.value - 64)
        }
        return (letters.uppercased(), colNum, rowNum)
    }

    /// Actualiza una fila completa in-place dentro del XML de la hoja.
    private static func updateRowInPlace(
        xml: String,
        rowNumber: Int,
        colWrites: [Int: ParsedWrite]
    ) -> String {
        guard let bounds = findRowBounds(in: xml, rowNumber: rowNumber) else {
            return xml
        }

        // Si la fila era self-closing (<row r="14"... />)
        if bounds.isSelfClosing {
            // Expandir fila y crear celdas ordenadas
            let rowTagOpen = xml[bounds.openTagRange]
            var cleanOpen = String(rowTagOpen).trimmingCharacters(in: .whitespaces)
            if cleanOpen.hasSuffix("/>") {
                cleanOpen = String(cleanOpen.dropLast(2)) + ">"
            }
            var cellStrings: [String] = []
            for (_, write) in colWrites.sorted(by: { $0.key < $1.key }) {
                var attrs = ["r=\"\(write.cellReference)\""]
                if let t = write.value.typeAttribute { attrs.append("t=\"\(t)\"") }
                let attrStr = " " + attrs.joined(separator: " ")
                cellStrings.append("<c\(attrStr)>\(write.value.xmlFragment)</c>")
            }
            let replacement = cleanOpen + cellStrings.joined() + "</row>"
            var result = xml
            result.replaceSubrange(bounds.fullRowRange, with: replacement)
            return result
        }

        let rowContent = String(xml[bounds.contentRange])
        let existingCells = parseCells(from: rowContent, rowNumber: rowNumber)

        var newCellStrings: [String] = []
        var handledCols: Set<Int> = []

        for cell in existingCells {
            if let write = colWrites[cell.colNumber] {
                handledCols.insert(cell.colNumber)
                // Construir la nueva celda conservando el estilo y la convención de atributo 'r'
                var attrs: [String] = []
                if cell.hasExplicitR {
                    attrs.append("r=\"\(write.cellReference)\"")
                }
                if let s = cell.styleAttribute {
                    attrs.append(s)
                }
                if let t = write.value.typeAttribute {
                    attrs.append("t=\"\(t)\"")
                }
                let attrStr = attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")
                newCellStrings.append("<c\(attrStr)>\(write.value.xmlFragment)</c>")
            } else {
                newCellStrings.append(cell.rawXML)
            }
        }

        // Si alguna columna solicitada no existía en la fila (formato sparse), insertarla ordenada
        let unhandled = colWrites.filter { !handledCols.contains($0.key) }
            .sorted { $0.key < $1.key }
        if !unhandled.isEmpty {
            for (_, write) in unhandled {
                var attrs = ["r=\"\(write.cellReference)\""]
                if let t = write.value.typeAttribute {
                    attrs.append("t=\"\(t)\"")
                }
                let attrStr = " " + attrs.joined(separator: " ")
                newCellStrings.append("<c\(attrStr)>\(write.value.xmlFragment)</c>")
            }
        }

        let newRowContent = newCellStrings.joined()
        var result = xml
        result.replaceSubrange(bounds.contentRange, with: newRowContent)
        return result
    }

    private struct RowBounds {
        let fullRowRange: Range<String.Index>
        let openTagRange: Range<String.Index>
        let contentRange: Range<String.Index>
        let isSelfClosing: Bool
    }

    /// Localiza los límites de un `<row>` específico por su número de fila.
    private static func findRowBounds(in xml: String, rowNumber: Int) -> RowBounds? {
        let pattern = "r=\"\(rowNumber)\""
        var searchStart = xml.startIndex

        while searchStart < xml.endIndex {
            guard let rRange = xml[searchStart...].range(of: pattern) else { return nil }
            let beforeR = xml[..<rRange.lowerBound]

            if let rowStart = beforeR.range(of: "<row", options: .backwards) {
                // Verificar que no hay un '>' entre "<row" y "r=\"...\""
                let between = xml[rowStart.upperBound..<rRange.lowerBound]
                if !between.contains(">") {
                    guard let tagEnd = xml[rRange.upperBound...].range(of: ">") else { return nil }
                    let openTag = xml[rowStart.lowerBound..<tagEnd.upperBound]
                    let isSelfClosing = openTag.trimmingCharacters(in: .whitespaces).hasSuffix("/>")

                    if isSelfClosing {
                        return RowBounds(
                            fullRowRange: rowStart.lowerBound..<tagEnd.upperBound,
                            openTagRange: rowStart.lowerBound..<tagEnd.upperBound,
                            contentRange: tagEnd.lowerBound..<tagEnd.lowerBound,
                            isSelfClosing: true
                        )
                    }

                    guard let closeTag = xml[tagEnd.upperBound...].range(of: "</row>") else { return nil }
                    return RowBounds(
                        fullRowRange: rowStart.lowerBound..<closeTag.upperBound,
                        openTagRange: rowStart.lowerBound..<tagEnd.upperBound,
                        contentRange: tagEnd.upperBound..<closeTag.lowerBound,
                        isSelfClosing: false
                    )
                }
            }
            searchStart = rRange.upperBound
        }
        return nil
    }

    /// Parsea secuencialmente las celdas `<c>` dentro del contenido de una fila.
    private static func parseCells(from content: String, rowNumber: Int) -> [RawCell] {
        var cells: [RawCell] = []
        var idx = content.startIndex
        var currentCol = 0

        while idx < content.endIndex {
            guard let cStart = content[idx...].range(of: "<c")?.lowerBound else { break }
            guard let tagEnd = content[cStart...].range(of: ">") else { break }

            let cellRaw: String
            let preTagEnd = content[cStart..<tagEnd.lowerBound].trimmingCharacters(in: .whitespaces)
            let isSelfClosing = preTagEnd.hasSuffix("/")

            if isSelfClosing {
                cellRaw = String(content[cStart..<tagEnd.upperBound])
                idx = tagEnd.upperBound
            } else {
                guard let cClose = content[tagEnd.upperBound...].range(of: "</c>") else { break }
                cellRaw = String(content[cStart..<cClose.upperBound])
                idx = cClose.upperBound
            }

            // Determinar columna del cell
            var hasExplicitR = false
            if let rRange = cellRaw.range(of: "r=\"") {
                let afterQuote = cellRaw[rRange.upperBound...]
                if let endQuote = afterQuote.range(of: "\"") {
                    let ref = String(afterQuote[..<endQuote.lowerBound])
                    if let parsed = parseCellReference(ref) {
                        currentCol = parsed.colNumber
                        hasExplicitR = true
                    }
                }
            }
            if !hasExplicitR {
                currentCol += 1
            }

            // Extraer atributo de estilo s="..."
            var styleAttr: String? = nil
            if let sRange = cellRaw.range(of: "s=\"") {
                let afterQuote = cellRaw[sRange.upperBound...]
                if let endQuote = afterQuote.range(of: "\"") {
                    let sVal = String(afterQuote[..<endQuote.lowerBound])
                    styleAttr = "s=\"\(sVal)\""
                }
            }

            cells.append(RawCell(
                rawXML: cellRaw,
                colNumber: currentCol,
                hasExplicitR: hasExplicitR,
                styleAttribute: styleAttr
            ))
        }

        return cells
    }
}

// MARK: - String helpers

private extension String {
    /// Escapa caracteres especiales XML.
    var xmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
