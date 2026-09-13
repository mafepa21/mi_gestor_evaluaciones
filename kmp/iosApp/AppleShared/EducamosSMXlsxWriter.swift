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
    case numeric(Int)       // Nota entera 0-10
    case text(String)       // Comentario de texto

    var xmlFragment: String {
        switch self {
        case .numeric(let value):
            // Celda numérica: <v>7</v>
            return "<v>\(value)</v>"
        case .text(let value):
            // Celda con inline string: <is><t>texto</t></is>
            let escaped = value.xmlEscaped
            return "<is><t>\(escaped)</t></is>"
        }
    }

    /// Atributo de tipo para la celda. Numéricos no necesitan tipo; texto usa `t="inlineStr"`.
    var typeAttribute: String? {
        switch self {
        case .numeric: return nil
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

        // 2. Determinar la ruta del XML de la hoja principal dentro del ZIP
        //    Educamos usa sheet2.xml para la hoja principal (índice 1, 0-based)
        let sheetXMLPath = "xl/worksheets/sheet\(template.mainSheetIndex + 1).xml"

        // 3. Leer el XML de la hoja desde el ZIP
        guard let archive = Archive(url: outputURL, accessMode: .update) else {
            throw EducamosSMXlsxWriterError.cannotOpenArchive
        }

        guard let sheetEntry = archive[sheetXMLPath] else {
            throw EducamosSMXlsxWriterError.sheetNotFound(sheetXMLPath)
        }

        var xmlData = Data()
        _ = try archive.extract(sheetEntry) { chunk in
            xmlData.append(chunk)
        }

        guard var xmlString = String(data: xmlData, encoding: .utf8) else {
            throw EducamosSMXlsxWriterError.cannotReadSheetXML
        }

        // 4. Inyectar valores en las celdas
        for cell in cells {
            xmlString = injectCellValue(
                xml: xmlString,
                cellReference: cell.cellReference,
                value: cell.value
            )
        }

        // 5. Reemplazar la entrada en el ZIP
        guard let modifiedData = xmlString.data(using: .utf8) else {
            throw EducamosSMXlsxWriterError.cannotWriteSheetXML
        }

        // Eliminar la entrada antigua y añadir la nueva
        try archive.remove(sheetEntry)
        try archive.addEntry(
            with: sheetXMLPath,
            type: .file,
            uncompressedSize: Int64(modifiedData.count),
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, modifiedData.count)
                return modifiedData[start..<end]
            }
        )

        return outputURL
    }

    // MARK: - XML manipulation

    /// Inyecta un valor en una celda específica del XML del worksheet.
    ///
    /// El XML de OpenXML tiene celdas con formato:
    /// `<c r="M13" s="53"/>` (vacía, self-closing)
    /// `<c r="M13" s="53"></c>` (vacía, con closing tag)
    /// `<c r="M13" t="s" s="53"><v>42</v></c>` (con valor)
    ///
    /// Esta función busca la celda por su referencia y:
    /// - Si es self-closing (`/>`): la convierte a tag con contenido
    /// - Si tiene closing tag pero sin valor: inyecta el valor
    /// - Si ya tiene valor: lo reemplaza
    private static func injectCellValue(
        xml: String,
        cellReference: String,
        value: EducamosSMCellValue
    ) -> String {
        var result = xml

        // Patrón para encontrar la celda por su referencia
        // Buscar: <c r="M13" ... /> (self-closing) o <c r="M13" ...>...</c>
        let refPattern = "r=\"\(cellReference)\""

        // Buscar la posición de la celda en el XML
        guard let refRange = result.range(of: refPattern) else {
            // La celda no existe — no se puede añadir sin romper la estructura
            return result
        }

        // Encontrar el inicio del tag <c que contiene esta referencia
        let searchBackStart = result.startIndex
        let refStart = refRange.lowerBound
        guard let tagStart = result[searchBackStart..<refStart].range(of: "<c ", options: .backwards)?.lowerBound else {
            return result
        }

        // Determinar si el tag es self-closing o tiene closing tag
        let afterRef = refRange.upperBound
        let remainingFromTag = result[tagStart...]

        if let selfCloseRange = result[afterRef...].range(of: "/>") {
            // Verificar que el self-close pertenece a este tag (no hay otro < antes)
            let between = result[afterRef..<selfCloseRange.lowerBound]
            if !between.contains("<") {
                // Self-closing: <c r="M13" s="53"/>
                // Reemplazar con: <c r="M13" s="53" [t="inlineStr"]><v>7</v></c>
                //             o: <c r="M13" s="53" t="inlineStr"><is><t>texto</t></is></c>
                let endOfSelfClose = selfCloseRange.upperBound

                // Extraer los atributos existentes del tag
                let existingTag = String(result[tagStart..<selfCloseRange.lowerBound])

                // Construir el nuevo tag
                var newTag = existingTag
                // Eliminar atributo t="s" si existe (shared string reference)
                newTag = newTag.replacingOccurrences(
                    of: " t=\"s\"",
                    with: ""
                )
                // Añadir type attribute si es necesario
                if let typeAttr = value.typeAttribute {
                    newTag += " t=\"\(typeAttr)\""
                }
                newTag += ">\(value.xmlFragment)</c>"

                result.replaceSubrange(tagStart..<endOfSelfClose, with: newTag)
                return result
            }
        }

        // Tiene closing tag: <c r="M13" ...>...</c>
        if let closeRange = result[afterRef...].range(of: "</c>") {
            let between = result[afterRef..<closeRange.lowerBound]
            if !between.contains("</c>") {
                // Encontrar el fin del tag de apertura
                if let openTagEnd = result[afterRef...].range(of: ">") {
                    let openEnd = openTagEnd.upperBound

                    // Extraer el tag de apertura completo
                    var openTag = String(result[tagStart..<openEnd])
                    // Eliminar t="s" si existe
                    openTag = openTag.replacingOccurrences(of: " t=\"s\"", with: "")
                    // Añadir type attribute si necesario
                    if let typeAttr = value.typeAttribute {
                        if !openTag.contains("t=\"\(typeAttr)\"") {
                            openTag = openTag.replacingOccurrences(of: ">", with: " t=\"\(typeAttr)\">")
                        }
                    }

                    let newContent = openTag + value.xmlFragment + "</c>"
                    let endOfClose = closeRange.upperBound
                    result.replaceSubrange(tagStart..<endOfClose, with: newContent)
                }
            }
        }

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
