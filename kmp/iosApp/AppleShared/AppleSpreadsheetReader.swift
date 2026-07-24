import CoreXLSX
import Foundation

enum AppleSpreadsheetReaderError: LocalizedError {
    case unsupportedFormat
    case unreadableFile
    case emptyWorkbook

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Formato no compatible. Usa .xlsx o .csv."
        case .unreadableFile:
            return "No se ha podido leer el archivo."
        case .emptyWorkbook:
            return "El archivo no contiene datos legibles."
        }
    }
}

enum AppleSpreadsheetReader {
    static func readRows(from url: URL) throws -> [[String]] {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch url.pathExtension.lowercased() {
        case "csv":
            return try readCSV(url)
        case "xlsx":
            return try readXLSX(url)
        default:
            throw AppleSpreadsheetReaderError.unsupportedFormat
        }
    }

    private static func readCSV(_ url: URL) throws -> [[String]] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            throw AppleSpreadsheetReaderError.unreadableFile
        }

        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        let delimiter: Character = firstLine.contains(";") ? ";" : (firstLine.contains("\t") ? "\t" : ",")

        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { parseCSVLine(String($0), delimiter: delimiter) }
            .filter { !$0.isEffectivelyEmpty }

        guard !rows.isEmpty else {
            throw AppleSpreadsheetReaderError.emptyWorkbook
        }
        return rows
    }

    private static func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if insideQuotes, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        insideQuotes.toggle()
                        if next == delimiter {
                            result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    insideQuotes.toggle()
                }
            } else if char == delimiter && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(char)
            }
        }

        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private static func readXLSX(_ url: URL) throws -> [[String]] {
        guard let firstSheet = try readAllXLSXSheetsInternal(url).first else {
            throw AppleSpreadsheetReaderError.emptyWorkbook
        }
        return firstSheet.rows
    }

    /// Lee todas las hojas de un `.xlsx`, sin normalizar filas vacías (a diferencia de
    /// `readRows`, pensado para tablas de una sola hoja). Útil cuando el archivo real
    /// tiene varias hojas (p.ej. una de referencia/catálogo y otra con los datos) y hace
    /// falta decidir cuál usar según su contenido.
    static func readAllXLSXSheets(from url: URL) throws -> [(name: String, rows: [[String]])] {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try readAllXLSXSheetsInternal(url)
    }

    private static func readAllXLSXSheetsInternal(_ url: URL) throws -> [(name: String, rows: [[String]])] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw AppleSpreadsheetReaderError.unreadableFile
        }

        let sharedStrings = try file.parseSharedStrings()
        guard let workbook = try file.parseWorkbooks().first else {
            throw AppleSpreadsheetReaderError.emptyWorkbook
        }

        let worksheetPaths = try file.parseWorksheetPathsAndNames(workbook: workbook)
        guard !worksheetPaths.isEmpty else {
            throw AppleSpreadsheetReaderError.emptyWorkbook
        }

        let sheets: [(name: String, rows: [[String]])] = try worksheetPaths.map { entry in
            let worksheet = try file.parseWorksheet(at: entry.path)
            let rows: [[String]] = worksheet.data?.rows.map { row -> [String] in
                var valuesByColumn: [Int: String] = [:]
                let firstColumn = ColumnReference("A")!

                for cell in row.cells {
                    let columnIndex = firstColumn.distance(to: cell.reference.column)
                    if let sharedStrings {
                        valuesByColumn[columnIndex] = cell.stringValue(sharedStrings) ?? cell.value ?? ""
                    } else {
                        valuesByColumn[columnIndex] = cell.value ?? ""
                    }
                }

                guard let maxColumnIndex = valuesByColumn.keys.max() else { return [] }
                return (0...maxColumnIndex).map { valuesByColumn[$0] ?? "" }
            } ?? []
            return (name: entry.name ?? entry.path, rows: rows.filter { !$0.isEffectivelyEmpty })
        }

        guard sheets.contains(where: { !$0.rows.isEmpty }) else {
            throw AppleSpreadsheetReaderError.emptyWorkbook
        }
        return sheets
    }
}

extension Array where Element == String {
    var isEffectivelyEmpty: Bool {
        !contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
