import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func exportText(data: NotebookUiStateData) -> String {
        let segments = displaySegments(data: data)
        let header = segments.map(exportHeaderTitle(for:)).joined(separator: "\t")
        let columnLettersById = exportColumnLettersById(segments: segments)

        let body = filteredRows(data: data).enumerated().map { rowIndex, item in
            segments.map {
                exportValue(
                    for: $0,
                    item: item,
                    spreadsheetRowIndex: rowIndex + 2,
                    columnLettersById: columnLettersById
                )
            }
            .joined(separator: "\t")
        }

        return ([header] + body).joined(separator: "\n")
    }

    func exportColumnLettersById(segments: [NotebookDisplaySegment]) -> [String: String] {
        var result: [String: String] = [:]
        for (index, segment) in segments.enumerated() {
            if case .column(let column) = segment {
                result[column.id] = spreadsheetColumnName(for: index + 1)
            }
        }
        return result
    }

    func spreadsheetColumnName(for oneBasedIndex: Int) -> String {
        var index = max(oneBasedIndex, 1)
        var result = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            index = (index - 1) / 26
        }
        return result
    }

    func exportHeaderTitle(for segment: NotebookDisplaySegment) -> String {
        switch segment {
        case .fixed(let fixed):
            return fixed.title
        case .column(let column):
            return column.title
        case .collapsedCategory(let category, _):
            return category.name
        }
    }

    func exportValue(
        for segment: NotebookDisplaySegment,
        item: NotebookTableRow,
        spreadsheetRowIndex: Int,
        columnLettersById: [String: String]
    ) -> String {
        switch segment {
        case .fixed(let fixed):
            switch fixed {
            case .photo:
                return initials(for: item.student)
            case .name:
                return "\(item.student.firstName) \(item.student.lastName)"
            case .group:
                return item.groupName
            case .followUp:
                return item.student.isInjured ? "Atención" : "Normal"
            case .attendance:
                return attendanceSummary(for: item)
            case .average:
                return averageText(for: item)
            }
        case .column(let column):
            if column.type == .calculated,
               let formula = column.formula?.trimmingCharacters(in: .whitespacesAndNewlines),
               !formula.isEmpty {
                return NotebookFormulaDisplay.spreadsheetFormula(
                    formula,
                    rowIndex: spreadsheetRowIndex,
                    columnLettersById: columnLettersById
                )
            }
            return displayValue(for: item, column: column)
        case .collapsedCategory(_, let columns):
            return "\(filledCellCount(item, columns: columns))/\(columns.count)"
        }
    }

    func formulaDisplay(
        for item: NotebookTableRow,
        column: NotebookColumnDefinition,
        data: NotebookUiStateData
    ) -> NotebookFormulaCellDisplay? {
        guard column.type == .calculated else { return nil }
        return NotebookFormulaDisplay.display(
            formula: column.formula,
            item: item,
            data: data,
            numericText: { studentId, columnId in
                bridge.numericGradeText(studentId: studentId, columnId: columnId)
            },
            rubricText: { studentId, column in
                bridge.rubricGradeText(studentId: studentId, column: column)
            }
        )
    }

    func categoryTitle(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> String {
        if let categoryId = column.categoryId,
           let category = data.sheet.columnCategories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        switch column.categoryKind {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .custom: return "Sin categoría"
        default: return "Sin categoría"
        }
    }

    func columnHeaderSubtitle(
        for column: NotebookColumnDefinition,
        data: NotebookUiStateData,
        rows: [NotebookTableRow]
    ) -> String {
        var parts = [categoryTitle(for: column, data: data)]
        if let epochMs = column.dateEpochMs?.int64Value {
            let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000.0)
            parts.append(date.formatted(.dateTime.day().month(.abbreviated)))
        }
        if let average = columnAverageText(for: column, rows: rows) {
            parts.append(average)
        }
        return parts.joined(separator: " · ")
    }

    func columnAverageText(for column: NotebookColumnDefinition, rows: [NotebookTableRow]) -> String? {
        guard column.type == .numeric || column.type == .rubric else { return nil }
        let values = rows.compactMap { item -> Double? in
            let raw = column.type == .rubric
                ? bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
                : bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
            return NotebookFormulaDisplay.parseNumber(raw)
        }
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return String(format: "x̄ %.1f", average)
    }

    func tint(for category: NotebookColumnCategory) -> Color {
        tint(forName: category.name)
    }

    func tint(for column: NotebookColumnDefinition) -> Color {
        if let colorHex = column.colorHex {
            return Color(hex: colorHex)
        }
        switch column.categoryKind {
        case .evaluation: return NotebookStyle.primaryTint
        case .followUp: return NotebookStyle.successTint
        case .attendance: return NotebookStyle.warningTint
        case .extras: return .pink
        case .physicalEducation: return .orange
        case .custom: return .secondary
        default: return .secondary
        }
    }

    func tint(forName name: String) -> Color {
        if name.localizedCaseInsensitiveContains("evalu") { return NotebookStyle.primaryTint }
        if name.localizedCaseInsensitiveContains("segu") { return NotebookStyle.successTint }
        if name.localizedCaseInsensitiveContains("asist") { return NotebookStyle.warningTint }
        if name.localizedCaseInsensitiveContains("extra") { return .pink }
        if name.localizedCaseInsensitiveContains("ef") { return .orange }
        return .secondary
    }

    func studentAvatar(for student: Student) -> some View {
        ZStack {
            Circle()
                .fill(NotebookStyle.primaryTint.opacity(0.15))
            Text(initials(for: student))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NotebookStyle.primaryTint)
        }
        .frame(width: 36, height: 36)
    }

    func initials(for student: Student) -> String {
        String(student.firstName.prefix(1)) + String(student.lastName.prefix(1))
    }

    func followUpBadge(for student: Student) -> some View {
        Text(student.isInjured ? "Atención" : "Normal")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(student.isInjured ? .orange : NotebookStyle.successTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill((student.isInjured ? Color.orange : NotebookStyle.successTint).opacity(0.12))
            )
    }

    func attendanceSummary(for item: NotebookTableRow) -> String {
        if let status = todayAttendanceByStudentId[item.student.id], !status.isEmpty {
            return status
        }
        let attendanceColumns = item.row.persistedCells.filter { $0.columnId.localizedCaseInsensitiveContains("attendance") || $0.columnId.localizedCaseInsensitiveContains("asist") }
        if attendanceColumns.isEmpty { return "Sin datos" }
        let present = attendanceColumns.filter { ($0.textValue ?? "").localizedCaseInsensitiveContains("pres") }.count
        return "\(present)/\(attendanceColumns.count)"
    }

    func averageText(for item: NotebookTableRow) -> String {
        guard let weightedAverage = item.row.weightedAverage else { return "Sin media" }
        return IosFormatting.decimal(from: weightedAverage)
    }

    enum AverageCellState {
        case complete
        case pending
        case insufficient
    }

    func averageState(for item: NotebookTableRow) -> AverageCellState {
        guard let explanation = item.row.averageExplanation,
              explanation.average != nil,
              !explanation.included.isEmpty else {
            return .insufficient
        }
        return explanation.excluded.contains { $0.reason == .empty } ? .pending : .complete
    }

    func averageBadge(for item: NotebookTableRow) -> some View {
        let state = averageState(for: item)
        let tint: Color = {
            switch state {
            case .complete: return NotebookStyle.successTint
            case .pending: return NotebookStyle.warningTint
            case .insufficient: return .secondary
            }
        }()
        let icon: String = {
            switch state {
            case .complete: return "checkmark.circle.fill"
            case .pending: return "clock.fill"
            case .insufficient: return "dash.circle"
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(averageText(for: item))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(state == .insufficient ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(state == .insufficient ? 0.08 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(state == .insufficient ? 0.12 : 0.22), lineWidth: 1)
        )
        .help(averageHelpText(for: state))
    }

    func averageHelpText(for state: AverageCellState) -> String {
        switch state {
        case .complete: return "Media completa"
        case .pending: return "Media con pendientes"
        case .insufficient: return "Sin datos suficientes"
        }
    }

    func filledCellCount(_ item: NotebookTableRow, columns: [NotebookColumnDefinition]) -> Int {
        columns.filter { !displayValue(for: item, column: $0).isEmpty }.count
    }

    func displayValue(for item: NotebookTableRow, column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric, .calculated:
            return bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        case .rubric:
            return bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
        case .check:
            return bridge.cellCheck(studentId: item.student.id, columnId: column.id) ? "Sí" : ""
        default:
            return bridge.cellText(studentId: item.student.id, columnId: column.id)
        }
    }

    func evidenceLabel(for persistedCell: PersistedNotebookCell?) -> String {
        let count = persistedCell?.annotation?.attachmentUris.count ?? 0
        let icon = persistedCell?.annotation?.icon ?? persistedCell?.iconValue ?? ""
        if count == 0 && icon.isEmpty { return "Sin evidencia" }
        if count == 0 { return "Icono \(icon)" }
        return icon.isEmpty ? "\(count) archivo(s)" : "\(count) archivo(s) · \(icon)"
    }

    func formattedDate(_ epochMs: Int64?) -> String {
        guard let epochMs else { return "Sin fecha" }
        return Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000).formatted(date: .abbreviated, time: .omitted)
    }

}
