import Foundation

enum ScheduleExcelImportError: LocalizedError {
    case missingWeekdayHeader
    case missingTimeRows
    case emptySchedule

    var errorDescription: String? {
        switch self {
        case .missingWeekdayHeader:
            return "No se encontró la cabecera Horas, Lunes, Martes, Miércoles, Jueves y Viernes."
        case .missingTimeRows:
            return "No se encontraron franjas con formato De HH:mm a HH:mm."
        case .emptySchedule:
            return "El horario no contiene clases ni huecos detectables."
        }
    }
}

struct ScheduleExcelImportService {
    func preview(from url: URL) throws -> ScheduleImportPreview {
        let rows = try AppleSpreadsheetReader.readRows(from: url)
        return try preview(rows: rows, sourceName: url.lastPathComponent)
    }

    func preview(rows: [[String]], sourceName: String = "Horario") throws -> ScheduleImportPreview {
        guard let header = findHeader(in: rows) else {
            throw ScheduleExcelImportError.missingWeekdayHeader
        }

        let legend = parseLegend(in: rows)
        let legendByCode = Dictionary(uniqueKeysWithValues: legend.map { ($0.code.uppercased(), $0.name) })
        var slots: [ImportedScheduleSlot] = []
        var foundTimeRows = false

        for row in rows.dropFirst(header.rowIndex + 1) {
            let timeText = value(at: header.timeColumn, in: row)
            guard let interval = parseInterval(timeText) else { continue }
            foundTimeRows = true

            for (weekday, columnIndex) in header.weekdayColumns {
                let raw = value(at: columnIndex, in: row)
                slots.append(contentsOf: parseCell(
                    raw,
                    weekday: weekday,
                    startMinute: interval.start,
                    endMinute: interval.end,
                    legendByCode: legendByCode
                ))
            }
        }

        guard foundTimeRows else {
            throw ScheduleExcelImportError.missingTimeRows
        }
        guard !slots.isEmpty else {
            throw ScheduleExcelImportError.emptySchedule
        }

        let conflicts = detectConflicts(in: slots)
        let warnings = buildWarnings(for: slots)
        return ScheduleImportPreview(
            sourceName: sourceName,
            slots: slots.sorted { lhs, rhs in
                (lhs.weekday, lhs.startMinute, lhs.endMinute, lhs.rawText) < (rhs.weekday, rhs.startMinute, rhs.endMinute, rhs.rawText)
            },
            subjectLegend: legend,
            conflicts: conflicts,
            warnings: warnings
        )
    }

    private func findHeader(in rows: [[String]]) -> Header? {
        for (rowIndex, row) in rows.enumerated() {
            let normalized = row.map(normalize)
            guard let timeColumn = normalized.firstIndex(of: "horas") else { continue }

            var weekdayColumns: [(weekday: Int, column: Int)] = []
            for (index, value) in normalized.enumerated() {
                switch value {
                case "lunes":
                    weekdayColumns.append((1, index))
                case "martes":
                    weekdayColumns.append((2, index))
                case "miercoles":
                    weekdayColumns.append((3, index))
                case "jueves":
                    weekdayColumns.append((4, index))
                case "viernes":
                    weekdayColumns.append((5, index))
                default:
                    break
                }
            }

            if weekdayColumns.count >= 5 {
                return Header(rowIndex: rowIndex, timeColumn: timeColumn, weekdayColumns: weekdayColumns)
            }
        }
        return nil
    }

    private func parseLegend(in rows: [[String]]) -> [ImportedSubjectLegend] {
        guard let legendStart = rows.firstIndex(where: { row in
            row.contains { normalize($0).contains("materias") }
        }) else {
            return [
                ImportedSubjectLegend(code: "EFI", name: "Educación Física"),
                ImportedSubjectLegend(code: "TUT", name: "Tutoría")
            ]
        }

        var result: [ImportedSubjectLegend] = []
        for row in rows.dropFirst(legendStart + 1) {
            let line = row
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            result.append(ImportedSubjectLegend(code: parts[0].uppercased(), name: normalizedSubjectName(parts[1])))
        }

        if result.isEmpty {
            result = [
                ImportedSubjectLegend(code: "EFI", name: "Educación Física"),
                ImportedSubjectLegend(code: "TUT", name: "Tutoría")
            ]
        }
        return result
    }

    private func parseCell(
        _ text: String,
        weekday: Int,
        startMinute: Int,
        endMinute: Int,
        legendByCode: [String: String]
    ) -> [ImportedScheduleSlot] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return [
                ImportedScheduleSlot(
                    weekday: weekday,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    rawText: "",
                    kind: isBreak(startMinute: startMinute, endMinute: endMinute) ? .breakTime : .empty,
                    subjectCodes: [],
                    subjectName: nil,
                    groupCodes: []
                )
            ]
        }

        let parts = raw
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var subjectCodes: [String] = []
        var groupCodes: [String] = []

        for part in parts {
            let pieces = part
                .components(separatedBy: ":")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pieces.count >= 2 else { continue }
            let subjectCode = pieces[0].uppercased()
            let groupCode = pieces[1]
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
                .uppercased()
            if !subjectCode.isEmpty { subjectCodes.append(subjectCode) }
            if !groupCode.isEmpty { groupCodes.append(groupCode) }
        }

        guard !subjectCodes.isEmpty || !groupCodes.isEmpty else {
            return [
                ImportedScheduleSlot(
                    weekday: weekday,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    rawText: raw,
                    kind: .teaching,
                    subjectCodes: [],
                    subjectName: raw,
                    groupCodes: []
                )
            ]
        }

        let kind: ImportedScheduleSlotKind = subjectCodes.contains { $0.hasPrefix("TUT") } ? .tutoring : .teaching
        let subjectName = resolveSubjectName(subjectCodes: subjectCodes, legendByCode: legendByCode, kind: kind)

        return [
            ImportedScheduleSlot(
                weekday: weekday,
                startMinute: startMinute,
                endMinute: endMinute,
                rawText: raw,
                kind: kind,
                subjectCodes: stableUnique(subjectCodes),
                subjectName: subjectName,
                groupCodes: stableUnique(groupCodes)
            )
        ]
    }

    private func parseInterval(_ value: String) -> (start: Int, end: Int)? {
        let pattern = #"(?i)\b(?:de\s*)?(\d{1,2}):(\d{2})\s*a\s*(\d{1,2}):(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.numberOfRanges == 5 else { return nil }

        func int(at index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }

        guard let sh = int(at: 1), let sm = int(at: 2), let eh = int(at: 3), let em = int(at: 4) else { return nil }
        return (sh * 60 + sm, eh * 60 + em)
    }

    private func detectConflicts(in slots: [ImportedScheduleSlot]) -> [String] {
        let persistable = slots.filter { !$0.groupCodes.isEmpty && ($0.kind == .teaching || $0.kind == .tutoring) }
        var conflicts: [String] = []

        for lhsIndex in persistable.indices {
            for rhsIndex in persistable.indices where rhsIndex > lhsIndex {
                let lhs = persistable[lhsIndex]
                let rhs = persistable[rhsIndex]
                guard lhs.weekday == rhs.weekday, rangesOverlap(lhs, rhs) else { continue }
                let repeatedGroups = Set(lhs.groupCodes).intersection(rhs.groupCodes)
                guard !repeatedGroups.isEmpty else { continue }
                conflicts.append("\(weekdayLabel(lhs.weekday)) \(lhs.startTime)-\(lhs.endTime) se solapa para \(repeatedGroups.sorted().joined(separator: ", "))")
            }
        }

        return Array(Set(conflicts)).sorted()
    }

    private func buildWarnings(for slots: [ImportedScheduleSlot]) -> [String] {
        var warnings: [String] = []
        let withoutGroups = slots.filter { ($0.kind == .teaching || $0.kind == .tutoring) && $0.groupCodes.isEmpty }
        if !withoutGroups.isEmpty {
            warnings.append("\(withoutGroups.count) celda(s) lectivas no tienen grupo reconocible.")
        }
        if !slots.contains(where: { $0.kind == .teaching || $0.kind == .tutoring }) {
            warnings.append("No se detectaron clases lectivas en la hoja.")
        }
        return warnings
    }

    private func resolveSubjectName(subjectCodes: [String], legendByCode: [String: String], kind: ImportedScheduleSlotKind) -> String {
        for code in subjectCodes {
            if let exact = legendByCode[code] {
                return normalizedSubjectName(exact)
            }
            if code.hasPrefix("EFI") {
                return "Educación Física"
            }
            if code.hasPrefix("TUT") {
                return "Tutoría"
            }
        }
        return kind == .tutoring ? "Tutoría" : "Clase"
    }

    private func normalizedSubjectName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalize(trimmed).hasPrefix("tutoria") {
            return "Tutoría"
        }
        if normalize(trimmed).contains("educacion fisica") {
            return "Educación Física"
        }
        return trimmed
    }

    private func isBreak(startMinute: Int, endMinute: Int) -> Bool {
        startMinute == 11 * 60 && endMinute == 11 * 60 + 25
    }

    private func rangesOverlap(_ lhs: ImportedScheduleSlot, _ rhs: ImportedScheduleSlot) -> Bool {
        max(lhs.startMinute, rhs.startMinute) < min(lhs.endMinute, rhs.endMinute)
    }

    private func value(at index: Int, in row: [String]) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        ["", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"][safe: weekday] ?? "Día \(weekday)"
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private struct Header {
    let rowIndex: Int
    let timeColumn: Int
    let weekdayColumns: [(weekday: Int, column: Int)]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
