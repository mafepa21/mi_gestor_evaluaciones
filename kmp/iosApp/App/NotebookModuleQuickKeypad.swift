import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    var keypadAdvanceMode: NotebookKeypadAdvanceMode {
        get { NotebookKeypadAdvanceMode(rawValue: keypadAdvanceModeRaw) ?? .immediate }
        nonmutating set { keypadAdvanceModeRaw = newValue.rawValue }
    }

    var keypadDirection: NotebookKeypadDirection {
        get { NotebookKeypadDirection(rawValue: keypadDirectionRaw) ?? .down }
        nonmutating set { keypadDirectionRaw = newValue.rawValue }
    }

    var keypadAdvanceModeBinding: Binding<NotebookKeypadAdvanceMode> {
        Binding(
            get: { keypadAdvanceMode },
            set: { keypadAdvanceMode = $0 }
        )
    }

    var keypadDirectionBinding: Binding<NotebookKeypadDirection> {
        Binding(
            get: { keypadDirection },
            set: { keypadDirection = $0 }
        )
    }

    // MARK: - Quick Keypad Actions

    func applyKeypadGrade(_ value: String, data: NotebookUiStateData, rows: [NotebookTableRow], advance: Bool = true) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        guard isToolbarEditableCellColumn(selected.column) else {
            showToast("Esta columna se edita desde su acción específica", style: .warning)
            return
        }

        keypadAdvanceTask?.cancel()
        keypadAdvanceTask = nil

        let previousValue = displayValue(for: selected.row, column: selected.column)
        if previousValue != value {
            recordCellUndo(
                studentId: selected.selection.studentId,
                column: selected.column,
                previousValue: previousValue,
                previousDisplayLabel: nil
            )
            bridge.saveColumnGrade(studentId: selected.selection.studentId, column: selected.column, value: value)
            reloadNotebookRow(selected.selection.studentId)
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        guard advance else { return }

        let currentStudentId = selected.selection.studentId
        let currentColumn = selected.column

        switch keypadAdvanceMode {
        case .immediate:
            advanceKeypadCell(from: currentStudentId, column: currentColumn, rows: rows, data: data)
        case .withDelay:
            keypadAdvanceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                advanceKeypadCell(from: currentStudentId, column: currentColumn, rows: rows, data: data)
            }
        case .manual:
            break
        }
    }

    func applyKeypadDelta(_ delta: Double, data: NotebookUiStateData, rows: [NotebookTableRow]) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        let raw = displayValue(for: selected.row, column: selected.column)
        let current = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        let nextValue = max(0.0, min(10.0, current + delta))
        let formatted = formatKeypadNumber(nextValue)
        applyKeypadGrade(formatted, data: data, rows: rows)
    }

    func applyKeypadDecimalFraction(_ fraction: String, data: NotebookUiStateData, rows: [NotebookTableRow]) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        let raw = displayValue(for: selected.row, column: selected.column)
        let clean = raw.replacingOccurrences(of: ",", with: ".")
        let currentVal = Double(clean) ?? 0.0
        let intPart = Int(currentVal)
        if intPart >= 10 {
            applyKeypadGrade("10", data: data, rows: rows)
            return
        }
        let fracPart = fraction.hasPrefix(".") ? String(fraction.dropFirst()) : fraction
        let combined = "\(intPart).\(fracPart)"
        if let doubleVal = Double(combined) {
            let clamped = min(10.0, max(0.0, doubleVal))
            applyKeypadGrade(formatKeypadNumber(clamped), data: data, rows: rows)
        } else {
            applyKeypadGrade(combined, data: data, rows: rows)
        }
    }

    func applyKeypadBackspace(data: NotebookUiStateData, rows: [NotebookTableRow]) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        var current = displayValue(for: selected.row, column: selected.column)
        guard !current.isEmpty else { return }
        current.removeLast()
        if current.hasSuffix(".") || current.hasSuffix(",") {
            current.removeLast()
        }
        applyKeypadGrade(current, data: data, rows: rows, advance: false)
    }

    func applyKeypadClear(data: NotebookUiStateData, rows: [NotebookTableRow]) {
        applyKeypadGrade("", data: data, rows: rows, advance: false)
    }

    func advanceKeypadCell(
        from studentId: Int64,
        column: NotebookColumnDefinition,
        rows: [NotebookTableRow],
        data: NotebookUiStateData
    ) {
        let renderModel = gridLayoutModel.renderModel(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset,
            isCompact: isCompact
        )
        navigateCell(
            from: studentId,
            column: column,
            direction: keypadDirection.navigationDirection,
            rows: rows,
            segments: renderModel.scrollableSegments
        )
    }

    func navigateKeypadCell(
        direction: NotebookNavigationDirection,
        data: NotebookUiStateData,
        rows: [NotebookTableRow]
    ) {
        keypadAdvanceTask?.cancel()
        keypadAdvanceTask = nil

        guard let selected = selectedNotebookCell(data: data) else {
            startKeypadAtFirstStudent(data: data, rows: rows)
            return
        }

        let renderModel = gridLayoutModel.renderModel(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset,
            isCompact: isCompact
        )
        navigateCell(
            from: selected.selection.studentId,
            column: selected.column,
            direction: direction,
            rows: rows,
            segments: renderModel.scrollableSegments
        )
    }

    func startKeypadAtFirstStudent(data: NotebookUiStateData, rows: [NotebookTableRow]) {
        guard let firstRow = rows.first else { return }
        let renderModel = gridLayoutModel.renderModel(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset,
            isCompact: isCompact
        )
        let navigableColumns = renderModel.scrollableSegments.compactMap { segment -> NotebookColumnDefinition? in
            guard case .column(let candidate) = segment else { return nil }
            return candidate
        }
        guard let targetColumn = navigableColumns.first(where: { isToolbarEditableCellColumn($0) }) ?? navigableColumns.first else { return }

        withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
            inspectorSelection = NotebookInspectorSelection(studentId: firstRow.student.id, columnId: targetColumn.id)
            focusedCellId = nil
            activeChoiceCellId = nil
        }
    }

    private func formatKeypadNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(rounded))
        } else if (rounded * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f", rounded)
        } else {
            return String(format: "%.2f", rounded)
        }
    }

    // MARK: - Dock View Builder

    @ViewBuilder
    func quickKeypadDock(data: NotebookUiStateData, rows: [NotebookTableRow]) -> some View {
        let selected = selectedNotebookCell(data: data)
        let hasSelection = selected != nil
        let student = selected?.row.student
        let column = selected?.column
        let studentName = student.map { "\($0.firstName) \($0.lastName)" }
        let initials = student.map { String($0.firstName.prefix(1)) + String($0.lastName.prefix(1)) }
        let currentIndex = selected.flatMap { item in rows.firstIndex(where: { $0.student.id == item.selection.studentId }) }
        let studentIndex = currentIndex.map { $0 + 1 }
        let totalStudents = rows.count
        let colTitle = column?.title
        let colIcon = column.map { columnSystemIcon(for: $0) }
        let categoryTint = column?.categoryId.flatMap { id in
            data.sheet.columnCategories.first(where: { $0.id == id }).map { tint(for: $0) }
        }
        let currentValue = selected.map { displayValue(for: $0.row, column: $0.column) } ?? ""
        let isEditable = column.map { isToolbarEditableCellColumn($0) } ?? false

        let canNavigatePrevious = (currentIndex ?? 0) > 0
        let canNavigateNext = (currentIndex ?? 0) < rows.count - 1

        NotebookQuickKeypadDock(
            studentName: studentName,
            studentInitials: initials,
            studentIndex: studentIndex,
            totalStudents: totalStudents,
            columnTitle: colTitle,
            columnSystemIcon: colIcon,
            categoryTint: categoryTint,
            currentValue: currentValue,
            isEditable: isEditable,
            hasActiveSelection: hasSelection,
            advanceMode: keypadAdvanceModeBinding,
            direction: keypadDirectionBinding,
            canNavigatePrevious: canNavigatePrevious,
            canNavigateNext: canNavigateNext,
            onApplyGrade: { grade in
                applyKeypadGrade(grade, data: data, rows: rows)
            },
            onApplyModifier: { delta in
                applyKeypadDelta(delta, data: data, rows: rows)
            },
            onApplyDecimalFraction: { fraction in
                applyKeypadDecimalFraction(fraction, data: data, rows: rows)
            },
            onClear: {
                applyKeypadClear(data: data, rows: rows)
            },
            onBackspace: {
                applyKeypadBackspace(data: data, rows: rows)
            },
            onNavigate: { direction in
                navigateKeypadCell(direction: direction, data: data, rows: rows)
            },
            onStartAtFirstStudent: {
                startKeypadAtFirstStudent(data: data, rows: rows)
            },
            onOpenStamps: {
                openCellStampPickerForSelection(data: data, rows: rows)
            },
            onClose: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    isQuickKeypadPresented = false
                }
            }
        )
    }
}
