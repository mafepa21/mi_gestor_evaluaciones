import Foundation

enum ScheduleExcelImportError: LocalizedError {
    case missingWeekdayHeader
    case missingTimeRows
    case emptySchedule
    case tooManyFiles

    var errorDescription: String? {
        switch self {
        case .missingWeekdayHeader:
            return "No se encontró una cabecera de horario reconocible: Horas/Hores y Lunes-Viernes o Dilluns-Divendres."
        case .missingTimeRows:
            return "No se encontraron franjas con formato De HH:mm a HH:mm."
        case .emptySchedule:
            return "El horario no contiene clases ni huecos detectables."
        case .tooManyFiles:
            return "Puedes combinar un máximo de 3 archivos de horario."
        }
    }
}

struct ScheduleExcelImportService {
    func preview(from urls: [URL]) throws -> ScheduleImportPreview {
        guard urls.count <= 3 else {
            throw ScheduleExcelImportError.tooManyFiles
        }
        guard !urls.isEmpty else {
            throw ScheduleExcelImportError.emptySchedule
        }
        return combine(try urls.map(preview(from:)))
    }

    func preview(from url: URL) throws -> ScheduleImportPreview {
        let rows = try AppleSpreadsheetReader.readRows(from: url)
        return try preview(rows: rows, sourceName: url.lastPathComponent)
    }

    func combine(_ previews: [ScheduleImportPreview]) -> ScheduleImportPreview {
        guard previews.count > 1 else {
            return previews.first ?? ScheduleImportPreview(
                sourceName: "Horario",
                slots: [],
                subjectLegend: [],
                conflicts: [],
                warnings: []
            )
        }

        let slots = deduplicatedSlots(previews.flatMap(\.slots))
        let legend = mergedLegend(previews.flatMap(\.subjectLegend))
        let omittedCount = previews.reduce(0) { $0 + $1.slots.count } - slots.count
        var warnings = previews.flatMap(\.warnings)
        if omittedCount > 0 {
            warnings.append("\(omittedCount) bloque(s) idénticos entre archivos se han unificado.")
        }

        return ScheduleImportPreview(
            sourceName: "\(previews.count) archivos combinados",
            slots: slots.sorted { lhs, rhs in
                (lhs.weekday, lhs.startMinute, lhs.endMinute, lhs.rawText) < (rhs.weekday, rhs.startMinute, rhs.endMinute, rhs.rawText)
            },
            subjectLegend: legend,
            conflicts: Array(Set(previews.flatMap(\.conflicts) + detectConflicts(in: slots))).sorted(),
            warnings: Array(Set(warnings)).sorted()
        )
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
            let normalized = row.map(normalizeHeader)
            guard let timeColumn = normalized.firstIndex(where: isTimeHeader) else { continue }

            var weekdayColumns: [(weekday: Int, column: Int)] = []
            for (index, value) in normalized.enumerated() {
                if let weekday = weekdayNumber(forHeader: value) {
                    weekdayColumns.append((weekday, index))
                }
            }

            let requiredWeekdays = Set(1...5)
            let detectedWeekdays = Set(weekdayColumns.map(\.weekday))
            if requiredWeekdays.isSubset(of: detectedWeekdays) {
                let orderedWeekdayColumns = weekdayColumns
                    .filter { requiredWeekdays.contains($0.weekday) }
                    .sorted { lhs, rhs in lhs.weekday == rhs.weekday ? lhs.column < rhs.column : lhs.weekday < rhs.weekday }
                return Header(rowIndex: rowIndex, timeColumn: timeColumn, weekdayColumns: orderedWeekdayColumns)
            }
        }
        return nil
    }

    private func isTimeHeader(_ value: String) -> Bool {
        [
            "horari",
            "hora",
            "horas",
            "hores",
            "franja",
            "franjas",
            "franja horaria",
            "franges",
            "franges horaries"
        ].contains(value)
    }

    private func weekdayNumber(forHeader value: String) -> Int? {
        switch value {
        case "lunes", "lun", "l":
            return 1
        case "martes", "mar", "ma", "m":
            return 2
        case "miercoles", "mie", "mier", "mi", "x":
            return 3
        case "jueves", "jue", "ju", "j":
            return 4
        case "viernes", "vie", "vi", "v":
            return 5
        case "dilluns", "dill", "dil", "dll", "dl":
            return 1
        case "dimarts", "dim", "dt":
            return 2
        case "dimecres", "dime", "dc":
            return 3
        case "dijous", "dij", "dj":
            return 4
        case "divendres", "div", "dv":
            return 5
        case "dissabte", "sabado", "sab", "ds":
            return 6
        case "diumenge", "domingo", "dom", "dg":
            return 7
        default:
            if let firstToken = value.split(separator: " ").first {
                let firstTokenText = String(firstToken)
                if firstTokenText != value {
                    return weekdayNumber(forHeader: firstTokenText)
                }
            }
            return nil
        }
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
                    assignments: [],
                    subjectName: nil
                )
            ]
        }

        let parts = raw
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var assignments: [ImportedSlotAssignment] = []

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
            guard !subjectCode.isEmpty, !groupCode.isEmpty else { continue }
            assignments.append(ImportedSlotAssignment(subjectCode: subjectCode, groupCode: groupCode))
        }

        guard !assignments.isEmpty else {
            return [
                ImportedScheduleSlot(
                    weekday: weekday,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    rawText: raw,
                    kind: .teaching,
                    assignments: [],
                    subjectName: raw
                )
            ]
        }

        let subjectCodes = stableUnique(assignments.map(\.subjectCode))
        let kind: ImportedScheduleSlotKind = subjectCodes.contains { $0.hasPrefix("TUT") } ? .tutoring : .teaching
        let subjectName = resolveSubjectName(subjectCodes: subjectCodes, legendByCode: legendByCode, kind: kind)

        return [
            ImportedScheduleSlot(
                weekday: weekday,
                startMinute: startMinute,
                endMinute: endMinute,
                rawText: raw,
                kind: kind,
                assignments: assignments,
                subjectName: subjectName
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

    private func deduplicatedSlots(_ slots: [ImportedScheduleSlot]) -> [ImportedScheduleSlot] {
        var seen: Set<ScheduleImportSlotKey> = []
        return slots.filter { slot in
            seen.insert(ScheduleImportSlotKey(slot: slot)).inserted
        }
    }

    private func mergedLegend(_ entries: [ImportedSubjectLegend]) -> [ImportedSubjectLegend] {
        var seen: Set<String> = []
        return entries.filter { seen.insert($0.code.uppercased()).inserted }
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

    private func normalizeHeader(_ value: String) -> String {
        normalize(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

}

private struct ScheduleImportSlotKey: Hashable {
    let weekday: Int
    let startMinute: Int
    let endMinute: Int
    let kind: ImportedScheduleSlotKind
    let assignments: [String]
    let fallbackText: String

    init(slot: ImportedScheduleSlot) {
        weekday = slot.weekday
        startMinute = slot.startMinute
        endMinute = slot.endMinute
        kind = slot.kind
        assignments = slot.assignments
            .map { "\($0.subjectCode.uppercased()):\($0.groupCode.uppercased())" }
            .sorted()
        fallbackText = assignments.isEmpty
            ? slot.rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : ""
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
