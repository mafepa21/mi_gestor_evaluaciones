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
        // 1. Copiar la plantilla a un directorio temporal
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let outputFilename = "Educamos_\(template.metadata.materia)_\(timestamp).xlsx"
            .replacingOccurrences(of: " ", with: "_")
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
        guard let archive = Archive(url: fileURL, accessMode: .update) else {
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

        // Inyectar valores en las celdas
        for cell in cells {
            xmlString = injectCellValue(
                xml: xmlString,
                cellReference: cell.cellReference,
                value: cell.value
            )
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

    // MARK: - XML manipulation

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

    /// Inyecta un valor en una celda específica del XML del worksheet.
    ///
    /// Esta función busca la celda por su referencia:
    /// - Si ya existe y es self-closing (`/>`): la expande e inyecta el valor.
    /// - Si ya existe con closing tag (`</c>`): reemplaza su contenido interior.
    /// - Si no existe en la fila (formato sparse): la inserta en el orden alfabético correcto dentro de `<row>`.
    private static func injectCellValue(
        xml: String,
        cellReference: String,
        value: EducamosSMCellValue
    ) -> String {
        var result = xml

        let refPattern = "r=\"\(cellReference)\""

        // 1. La celda ya existe en el XML
        if let refRange = result.range(of: refPattern) {
            let searchBackStart = result.startIndex
            let refStart = refRange.lowerBound
            guard let tagStart = result[searchBackStart..<refStart].range(of: "<c ", options: .backwards)?.lowerBound else {
                return result
            }

            let afterRef = refRange.upperBound

            // A) Self-closing: <c r="M13" s="53"/>
            if let selfCloseRange = result[afterRef...].range(of: "/>") {
                let between = result[afterRef..<selfCloseRange.lowerBound]
                if !between.contains("<") {
                    let endOfSelfClose = selfCloseRange.upperBound
                    let existingTag = String(result[tagStart..<selfCloseRange.lowerBound])

                    var newTag = existingTag.replacingOccurrences(of: " t=\"s\"", with: "")
                    if let typeAttr = value.typeAttribute {
                        newTag += " t=\"\(typeAttr)\""
                    }
                    newTag += ">\(value.xmlFragment)</c>"

                    result.replaceSubrange(tagStart..<endOfSelfClose, with: newTag)
                    return result
                }
            }

            // B) Con closing tag: <c r="M13" ...>...</c>
            if let closeRange = result[afterRef...].range(of: "</c>") {
                let between = result[afterRef..<closeRange.lowerBound]
                if !between.contains("</c>") {
                    if let openTagEnd = result[afterRef...].range(of: ">") {
                        let openEnd = openTagEnd.upperBound
                        var openTag = String(result[tagStart..<openEnd])
                        openTag = openTag.replacingOccurrences(of: " t=\"s\"", with: "")
                        if let typeAttr = value.typeAttribute {
                            if !openTag.contains("t=\"\(typeAttr)\"") {
                                openTag = openTag.replacingOccurrences(of: ">", with: " t=\"\(typeAttr)\">")
                            }
                        }

                        let newContent = openTag + value.xmlFragment + "</c>"
                        let endOfClose = closeRange.upperBound
                        result.replaceSubrange(tagStart..<endOfClose, with: newContent)
                        return result
                    }
                }
            }

            return result
        }

        // 2. La celda no existe: inserción sparse ordenada dentro de <row>
        guard let parsed = parseCellReference(cellReference) else { return result }
        let rowPattern = "<row r=\"\(parsed.rowNumber)\""
        guard let rowRange = result.range(of: rowPattern) else { return result }

        let searchFrom = rowRange.lowerBound
        guard let rowTagClose = result[searchFrom...].range(of: ">") else { return result }

        // Si la fila completa era self-closing: <row r="14".../>
        let beforeRowTagClose = result.index(before: rowTagClose.lowerBound)
        if result[beforeRowTagClose] == "/" {
            var newCellTag = "<c r=\"\(cellReference)\""
            if let typeAttr = value.typeAttribute { newCellTag += " t=\"\(typeAttr)\"" }
            newCellTag += ">\(value.xmlFragment)</c>"
            let replacement = ">\(newCellTag)</row>"
            result.replaceSubrange(beforeRowTagClose...rowTagClose.lowerBound, with: replacement)
            return result
        }

        guard let endRowRange = result[rowTagClose.upperBound...].range(of: "</row>") else { return result }
        let rowContent = String(result[rowTagClose.upperBound..<endRowRange.lowerBound])

        var insertOffset = rowContent.count
        let regex = try? NSRegularExpression(pattern: "<c [^>]*r=\"([A-Za-z]+)\(parsed.rowNumber)\"")
        if let matches = regex?.matches(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent)) {
            for m in matches {
                if let r = Range(m.range(at: 1), in: rowContent) {
                    let colLetters = String(rowContent[r])
                    if let otherParsed = parseCellReference("\(colLetters)\(parsed.rowNumber)"),
                       otherParsed.colNumber > parsed.colNumber {
                        if let matchRange = Range(m.range, in: rowContent) {
                            insertOffset = rowContent.distance(from: rowContent.startIndex, to: matchRange.lowerBound)
                            break
                        }
                    }
                }
            }
        }

        var cellXML = "<c r=\"\(cellReference)\""
        if let typeAttr = value.typeAttribute { cellXML += " t=\"\(typeAttr)\"" }
        cellXML += ">\(value.xmlFragment)</c>"

        let insertIndex = result.index(rowTagClose.upperBound, offsetBy: insertOffset)
        result.insert(contentsOf: cellXML, at: insertIndex)
        return result
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
