import Foundation
import MiGestorKit

public struct NotebookWorkGroupImportPreview: Identifiable {
    public let id = UUID()
    public let sourceName: String
    public let groups: [ImportedNotebookGroup]
    public let warnings: [String]

    public var totalMatchedStudents: Int {
        groups.reduce(0) { $0 + $1.members.filter { $0.matchedStudentId != nil }.count }
    }

    public var totalUnmatchedStudents: Int {
        groups.reduce(0) { $0 + $1.members.filter { $0.matchedStudentId == nil }.count }
    }
}

public struct ImportedNotebookGroup: Identifiable {
    public let id = UUID()
    public var name: String
    public var members: [ImportedNotebookGroupMember]
}

public struct ImportedNotebookGroupMember: Identifiable {
    public let id = UUID()
    public let rawName: String
    public var matchedStudentId: Int64?
    public var matchedStudentName: String?
}

public enum NotebookWorkGroupImportError: LocalizedError {
    case emptySpreadsheet
    case noGroupsFound
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .emptySpreadsheet:
            return "La hoja de cálculo está vacía o no contiene datos válidos."
        case .noGroupsFound:
            return "No se han detectado columnas ni registros de grupos reconocibles."
        case .unreadableFile:
            return "No se ha podido leer el archivo seleccionado."
        }
    }
}

public struct NotebookWorkGroupImportService {
    public init() {}

    /// Parsea la matriz de filas leídas de un Excel/CSV y empareja los alumnos con la lista de `Student` dada.
    public func preview(
        rows: [[String]],
        sourceName: String,
        classStudents: [Student]
    ) throws -> NotebookWorkGroupImportPreview {
        guard !rows.isEmpty else {
            throw NotebookWorkGroupImportError.emptySpreadsheet
        }

        // Limpiar filas vacías
        let cleanRows = rows
            .map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { row in row.contains(where: { !$0.isEmpty }) }

        guard !cleanRows.isEmpty else {
            throw NotebookWorkGroupImportError.emptySpreadsheet
        }

        // Heurística de detección de formato:
        // Formato B prioritario si la cabecera indica explícitamente tabla Alumno / Grupo:
        if let tablePreview = parseTwoColumnList(rows: cleanRows, sourceName: sourceName, classStudents: classStudents) {
            return tablePreview
        }

        // Formato A (Matricial por columnas, ej: Generador_de_grupos.xlsx):
        // Fila 1 (o primera fila no vacía) contiene los encabezados de grupo (Grupo 1, Grupo 2, ...)
        // Filas subsiguientes contienen alumnos debajo de cada columna.
        if let matrixPreview = parseColumnMatrix(rows: cleanRows, sourceName: sourceName, classStudents: classStudents) {
            return matrixPreview
        }

        throw NotebookWorkGroupImportError.noGroupsFound
    }

    // MARK: - Parser Matricial (Generador_de_grupos.xlsx)

    private func parseColumnMatrix(
        rows: [[String]],
        sourceName: String,
        classStudents: [Student]
    ) -> NotebookWorkGroupImportPreview? {
        guard let headerRow = rows.first else { return nil }

        // Identificar columnas que representan grupos.
        // Omitimos columnas como número de orden (ej: "1", "1.0", "Nº", "#", "N", "")
        var groupColumns: [(columnIndex: Int, groupName: String)] = []

        for (colIdx, cell) in headerRow.enumerated() {
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Si es un número o índice puro, lo ignoramos
            if isIndexOrOrderColumn(trimmed) {
                continue
            }

            // Aceptamos cualquier columna con título (ej: "Grupo 1", "Equipo A", "Color Rojo", etc.)
            groupColumns.append((columnIndex: colIdx, groupName: trimmed))
        }

        guard !groupColumns.isEmpty else { return nil }

        // Mapeo rápido de alumnos existentes para matching
        let lookup = StudentNameLookup(students: classStudents)
        var importedGroups: [ImportedNotebookGroup] = []
        var warnings: [String] = []

        for col in groupColumns {
            var members: [ImportedNotebookGroupMember] = []

            for rowIdx in 1..<rows.count {
                let row = rows[rowIdx]
                guard col.columnIndex < row.count else { continue }
                let cellVal = row[col.columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if cellVal.isEmpty { continue }

                // Descartar si es un valor puramente numérico no identificador
                if Double(cellVal) != nil && !cellVal.contains(" ") {
                    continue
                }

                let match = lookup.findStudent(for: cellVal)
                members.append(
                    ImportedNotebookGroupMember(
                        rawName: cellVal,
                        matchedStudentId: match?.id,
                        matchedStudentName: match.map { "\($0.firstName) \($0.lastName)" }
                    )
                )

                if match == nil {
                    warnings.append("En \(col.groupName): '\(cellVal)' no coincide con ningún alumno del cuaderno.")
                }
            }

            if !members.isEmpty {
                importedGroups.append(
                    ImportedNotebookGroup(
                        name: col.groupName,
                        members: members
                    )
                )
            }
        }

        guard !importedGroups.isEmpty else { return nil }

        return NotebookWorkGroupImportPreview(
            sourceName: sourceName,
            groups: importedGroups,
            warnings: warnings
        )
    }

    // MARK: - Parser Formato 2 Columnas (Grupo / Alumno)

    private func parseTwoColumnList(
        rows: [[String]],
        sourceName: String,
        classStudents: [Student]
    ) -> NotebookWorkGroupImportPreview? {
        guard rows.count >= 2 else { return nil }

        let firstRow = rows[0]
        guard firstRow.count >= 2 else { return nil }

        var groupColIdx: Int?
        var studentColIdx: Int?

        let col0 = firstRow[0].lowercased()
        let col1 = firstRow[1].lowercased()

        let isCol0Group = col0.contains("grupo") || col0.contains("equipo")
        let isCol1Group = col1.contains("grupo") || col1.contains("equipo")
        let isCol0Student = col0.contains("alumno") || col0.contains("estudiante") || col0.contains("nombre")
        let isCol1Student = col1.contains("alumno") || col1.contains("estudiante") || col1.contains("nombre")

        if isCol0Group && isCol1Student {
            groupColIdx = 0
            studentColIdx = 1
        } else if isCol1Group && isCol0Student {
            groupColIdx = 1
            studentColIdx = 0
        }

        guard let gIdx = groupColIdx, let sIdx = studentColIdx else { return nil }

        let lookup = StudentNameLookup(students: classStudents)
        var groupsMap: [String: [ImportedNotebookGroupMember]] = [:]
        var groupOrder: [String] = []
        var warnings: [String] = []

        for row in rows.dropFirst() {
            guard gIdx < row.count, sIdx < row.count else { continue }
            let groupName = row[gIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawStudent = row[sIdx].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !groupName.isEmpty, !rawStudent.isEmpty else { continue }

            if groupsMap[groupName] == nil {
                groupsMap[groupName] = []
                groupOrder.append(groupName)
            }

            let match = lookup.findStudent(for: rawStudent)
            groupsMap[groupName]?.append(
                ImportedNotebookGroupMember(
                    rawName: rawStudent,
                    matchedStudentId: match?.id,
                    matchedStudentName: match.map { "\($0.firstName) \($0.lastName)" }
                )
            )

            if match == nil {
                warnings.append("En \(groupName): '\(rawStudent)' no coincide con ningún alumno del cuaderno.")
            }
        }

        let importedGroups = groupOrder.compactMap { name -> ImportedNotebookGroup? in
            guard let members = groupsMap[name], !members.isEmpty else { return nil }
            return ImportedNotebookGroup(name: name, members: members)
        }

        guard !importedGroups.isEmpty else { return nil }

        return NotebookWorkGroupImportPreview(
            sourceName: sourceName,
            groups: importedGroups,
            warnings: warnings
        )
    }

    private func isIndexOrOrderColumn(_ text: String) -> Bool {
        if Double(text) != nil { return true }
        let lower = text.lowercased()
        return ["n", "nº", "no", "#", "num", "número", "orden", "pos", "pos."].contains(lower)
    }
}

// MARK: - Helper de Normalización y Búsqueda de Alumnos

public struct StudentNameLookup {
    private struct Entry {
        let student: Student
        let normalizedFullNameFirstLast: String
        let normalizedFullNameLastFirst: String
        let normalizedTokens: Set<String>
    }

    private let entries: [Entry]

    public init(students: [Student]) {
        self.entries = students.map { student in
            let fn = Self.normalize(student.firstName)
            let ln = Self.normalize(student.lastName)
            let firstLast = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
            let lastFirst = [ln, fn].filter { !$0.isEmpty }.joined(separator: " ")
            let tokens = Set(firstLast.components(separatedBy: " ").filter { !$0.isEmpty })

            return Entry(
                student: student,
                normalizedFullNameFirstLast: firstLast,
                normalizedFullNameLastFirst: lastFirst,
                normalizedTokens: tokens
            )
        }
    }

    public func findStudent(for rawString: String) -> Student? {
        let cleaned = Self.cleanRawStudentName(rawString)
        let normalized = Self.normalize(cleaned)
        guard !normalized.isEmpty else { return nil }

        // 1. Coincidencia exacta completa (Nombre Apellidos o Apellidos Nombre)
        if let exact = entries.first(where: {
            $0.normalizedFullNameFirstLast == normalized ||
            $0.normalizedFullNameLastFirst == normalized
        }) {
            return exact.student
        }

        // 2. Si contiene coma (Apellidos, Nombre)
        if rawString.contains(",") {
            let parts = rawString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 2 {
                let ln = Self.normalize(parts[0])
                let fn = Self.normalize(parts[1])
                let lf = [ln, fn].filter { !$0.isEmpty }.joined(separator: " ")
                let fl = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
                if let match = entries.first(where: {
                    $0.normalizedFullNameFirstLast == fl ||
                    $0.normalizedFullNameLastFirst == lf
                }) {
                    return match.student
                }
            }
        }

        // 3. Coincidencia por conjunto de tokens significativos
        let rawTokens = Set(normalized.components(separatedBy: " ").filter { !$0.isEmpty })
        if rawTokens.count >= 2 {
            // Si todos los tokens de raw están en el alumno o viceversa
            let candidates = entries.filter { entry in
                rawTokens.isSubset(of: entry.normalizedTokens) || entry.normalizedTokens.isSubset(of: rawTokens)
            }
            if candidates.count == 1 {
                return candidates.first?.student
            }
        }

        return nil
    }

    public static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func cleanRawStudentName(_ value: String) -> String {
        // Eliminar posibles prefijos numéricos como "1. ", "1 - ", etc.
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.range(of: #"^\d+[\.\-\)]\s*"#, options: .regularExpression) {
            text.removeSubrange(match)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
