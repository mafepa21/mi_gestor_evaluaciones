import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

private enum NotebookCellKeyboardKind {
    case numeric010
    case time
    case distance
    case repetitions
    case quickSelector
    case rubric
    case check
    case readOnlyFormula
    case text
}

struct NotebookCellDisplaySnapshot: Equatable {
    let numericText: String
    let text: String
    let checkValue: Bool
    let calculatedText: String
    let rubricText: String
    let stampIcon: String?
    let hasNote: Bool
    let attachmentCount: Int

    init(
        numericText: String = "",
        text: String = "",
        checkValue: Bool = false,
        calculatedText: String = "",
        rubricText: String = "",
        stampIcon: String? = nil,
        hasNote: Bool = false,
        attachmentCount: Int = 0
    ) {
        self.numericText = numericText
        self.text = text
        self.checkValue = checkValue
        self.calculatedText = calculatedText
        self.rubricText = rubricText
        self.stampIcon = stampIcon
        self.hasNote = hasNote
        self.attachmentCount = attachmentCount
    }
}

struct NotebookCellActions {
    let flushPendingColumnGradeSave: @MainActor (_ studentId: Int64, _ columnId: String) -> Void
    let saveColumnGrade: @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void
    let saveColumnGradeDebounced: @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void
    let resolvePhysicalScore: (@MainActor (_ student: Student, _ classId: Int64, _ columnId: String, _ rawValue: Double) async -> Double?)?
    let saveAttendance: @MainActor (_ studentId: Int64, _ classId: Int64, _ date: Date, _ status: String) async -> Bool

    init(
        flushPendingColumnGradeSave: @escaping @MainActor (_ studentId: Int64, _ columnId: String) -> Void,
        saveColumnGrade: @escaping @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void,
        saveColumnGradeDebounced: @escaping @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void,
        resolvePhysicalScore: (@MainActor (_ student: Student, _ classId: Int64, _ columnId: String, _ rawValue: Double) async -> Double?)? = nil,
        saveAttendance: @escaping @MainActor (_ studentId: Int64, _ classId: Int64, _ date: Date, _ status: String) async -> Bool
    ) {
        self.flushPendingColumnGradeSave = flushPendingColumnGradeSave
        self.saveColumnGrade = saveColumnGrade
        self.saveColumnGradeDebounced = saveColumnGradeDebounced
        self.resolvePhysicalScore = resolvePhysicalScore
        self.saveAttendance = saveAttendance
    }
}

@MainActor
struct NotebookEditableTableCell: View {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let actions: NotebookCellActions
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    var focusedCellId: FocusState<String?>.Binding
    /// Calculado en el padre: evita que cada celda lea el FocusState y se invalide con cada cambio de foco.
    let isFocused: Bool
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onOpenStructuredInstrument: () -> Void
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    var body: some View {
        cellContent
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column.title), \(item.student.fullName)")
            .accessibilityValue(accessibilityCellValue)
            .accessibilityHint(accessibilityCellHint)
    }

    private var accessibilityCellValue: String {
        if column.type == .check {
            return displaySnapshot.checkValue ? "Marcado" : "Sin marcar"
        }
        if column.inputKind.isStructuredInstrument {
            let raw = displaySnapshot.text.isEmpty
                ? (item.lookup.cellsByColumnId[column.id]?.displayValue ?? item.lookup.cellsByColumnId[column.id]?.textValue ?? "")
                : displaySnapshot.text
            return NotebookStructuredValueLabel.accessibilityValue(for: raw)
        }
        if column.type == .rubric {
            return NotebookRubricValueLabel.accessibilityValue(for: displaySnapshot.rubricText)
        }
        let value = [
            displaySnapshot.numericText,
            displaySnapshot.calculatedText,
            displaySnapshot.rubricText,
            displaySnapshot.text
        ].first(where: { !$0.isEmpty })
        return value ?? "Vacío"
    }

    private var accessibilityCellHint: String {
        switch column.type {
        case .calculated:
            return "Calculado automáticamente, no editable"
        case .check:
            return "Toca dos veces para marcar o desmarcar"
        default:
            return "Toca dos veces para editar"
        }
    }

    @ViewBuilder
    private var cellContent: some View {
        if column.inputKind.isStructuredInstrument {
            NotebookReadOnlyCell(
                displaySnapshot: displaySnapshot,
                item: item,
                column: column,
                width: width,
                tint: tint,
                categoryTint: categoryTint,
                hasColumnColor: hasColumnColor,
                formulaDisplay: formulaDisplay,
                isSelected: isSelected,
                reloadToken: reloadToken,
                onSelect: onSelect,
                onOpenStructuredInstrument: onOpenStructuredInstrument
            )
            .equatable()
        } else if column.type == .attendance || column.categoryKind == .attendance {
            NotebookAttendanceCell(
                displaySnapshot: displaySnapshot,
                actions: actions,
                item: item,
                column: column,
                classId: classId,
                width: width,
                tint: tint,
                categoryTint: categoryTint,
                hasColumnColor: hasColumnColor,
                focusedCellId: focusedCellId,
                isFocused: isFocused,
                activeChoiceCellId: $activeChoiceCellId,
                navigationDirection: navigationDirection,
                formulaDisplay: formulaDisplay,
                isSelected: isSelected,
                isAttendanceQuickMode: isAttendanceQuickMode,
                reloadToken: reloadToken,
                onSelect: onSelect,
                onPrepareUndo: onPrepareUndo,
                onOpenFormula: onOpenFormula,
                onOpenRubricIndividual: onOpenRubricIndividual,
                onOpenRubricBulk: onOpenRubricBulk,
                onOpenStructuredInstrument: onOpenStructuredInstrument,
                onGenerateSummary: onGenerateSummary,
                onNavigate: onNavigate,
                onCellSaved: onCellSaved,
                onAttendanceSaved: onAttendanceSaved
            )
            .equatable()
        } else {
            switch column.type {
            case .numeric:
                NotebookNumericCell(
                    displaySnapshot: displaySnapshot,
                    actions: actions,
                    item: item,
                    column: column,
                    classId: classId,
                    width: width,
                    tint: tint,
                    categoryTint: categoryTint,
                    hasColumnColor: hasColumnColor,
                    focusedCellId: focusedCellId,
                    isFocused: isFocused,
                    activeChoiceCellId: $activeChoiceCellId,
                    navigationDirection: navigationDirection,
                    formulaDisplay: formulaDisplay,
                    isSelected: isSelected,
                    isAttendanceQuickMode: isAttendanceQuickMode,
                    reloadToken: reloadToken,
                    onSelect: onSelect,
                    onPrepareUndo: onPrepareUndo,
                    onOpenFormula: onOpenFormula,
                    onOpenRubricIndividual: onOpenRubricIndividual,
                    onOpenRubricBulk: onOpenRubricBulk,
                    onOpenStructuredInstrument: onOpenStructuredInstrument,
                    onGenerateSummary: onGenerateSummary,
                    onNavigate: onNavigate,
                    onCellSaved: onCellSaved,
                    onAttendanceSaved: onAttendanceSaved
                )
                .equatable()
            case .check:
                NotebookCheckCell(
                    displaySnapshot: displaySnapshot,
                    actions: actions,
                    item: item,
                    column: column,
                    classId: classId,
                    width: width,
                    tint: tint,
                    categoryTint: categoryTint,
                    hasColumnColor: hasColumnColor,
                    focusedCellId: focusedCellId,
                    isFocused: isFocused,
                    activeChoiceCellId: $activeChoiceCellId,
                    navigationDirection: navigationDirection,
                    formulaDisplay: formulaDisplay,
                    isSelected: isSelected,
                    isAttendanceQuickMode: isAttendanceQuickMode,
                    reloadToken: reloadToken,
                    onSelect: onSelect,
                    onPrepareUndo: onPrepareUndo,
                    onOpenFormula: onOpenFormula,
                    onOpenRubricIndividual: onOpenRubricIndividual,
                    onOpenRubricBulk: onOpenRubricBulk,
                    onOpenStructuredInstrument: onOpenStructuredInstrument,
                    onGenerateSummary: onGenerateSummary,
                    onNavigate: onNavigate,
                    onCellSaved: onCellSaved,
                    onAttendanceSaved: onAttendanceSaved
                )
                .equatable()
            case .rubric:
                NotebookRubricCell(
                    displaySnapshot: displaySnapshot,
                    item: item,
                    column: column,
                    width: width,
                    tint: tint,
                    categoryTint: categoryTint,
                    hasColumnColor: hasColumnColor,
                    formulaDisplay: formulaDisplay,
                    isSelected: isSelected,
                    reloadToken: reloadToken,
                    onSelect: onSelect,
                    onOpenRubricIndividual: onOpenRubricIndividual,
                    onOpenRubricBulk: onOpenRubricBulk
                )
                .equatable()
            case .calculated:
                NotebookFormulaCell(
                    displaySnapshot: displaySnapshot,
                    item: item,
                    column: column,
                    width: width,
                    tint: tint,
                    categoryTint: categoryTint,
                    hasColumnColor: hasColumnColor,
                    formulaDisplay: formulaDisplay,
                    isSelected: isSelected,
                    reloadToken: reloadToken,
                    onSelect: onSelect,
                    onOpenFormula: onOpenFormula
                )
                .equatable()
            default:
                NotebookTextCell(
                    displaySnapshot: displaySnapshot,
                    actions: actions,
                    item: item,
                    column: column,
                    classId: classId,
                    width: width,
                    tint: tint,
                    categoryTint: categoryTint,
                    hasColumnColor: hasColumnColor,
                    focusedCellId: focusedCellId,
                    isFocused: isFocused,
                    activeChoiceCellId: $activeChoiceCellId,
                    navigationDirection: navigationDirection,
                    formulaDisplay: formulaDisplay,
                    isSelected: isSelected,
                    isAttendanceQuickMode: isAttendanceQuickMode,
                    reloadToken: reloadToken,
                    onSelect: onSelect,
                    onPrepareUndo: onPrepareUndo,
                    onOpenFormula: onOpenFormula,
                    onOpenRubricIndividual: onOpenRubricIndividual,
                    onOpenRubricBulk: onOpenRubricBulk,
                    onOpenStructuredInstrument: onOpenStructuredInstrument,
                    onGenerateSummary: onGenerateSummary,
                    onNavigate: onNavigate,
                    onCellSaved: onCellSaved,
                    onAttendanceSaved: onAttendanceSaved
                )
                .equatable()
            }
        }
    }
}

private struct NotebookNumericCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let actions: NotebookCellActions
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    var focusedCellId: FocusState<String?>.Binding
    /// Calculado en el padre: evita que cada celda lea el FocusState y se invalide con cada cambio de foco.
    let isFocused: Bool
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onOpenStructuredInstrument: () -> Void
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    var body: some View { statefulCell }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isFocused == rhs.isFocused &&
            lhs.navigationDirection == rhs.navigationDirection &&
            lhs.reloadToken == rhs.reloadToken
    }
}

private struct NotebookTextCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let actions: NotebookCellActions
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    var focusedCellId: FocusState<String?>.Binding
    /// Calculado en el padre: evita que cada celda lea el FocusState y se invalide con cada cambio de foco.
    let isFocused: Bool
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onOpenStructuredInstrument: () -> Void
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    var body: some View { statefulCell }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isFocused == rhs.isFocused &&
            lhs.navigationDirection == rhs.navigationDirection &&
            lhs.reloadToken == rhs.reloadToken
    }
}

private struct NotebookCheckCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let actions: NotebookCellActions
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    var focusedCellId: FocusState<String?>.Binding
    /// Calculado en el padre: evita que cada celda lea el FocusState y se invalide con cada cambio de foco.
    let isFocused: Bool
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onOpenStructuredInstrument: () -> Void
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    var body: some View { statefulCell }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isFocused == rhs.isFocused &&
            lhs.navigationDirection == rhs.navigationDirection &&
            lhs.reloadToken == rhs.reloadToken
    }
}

private struct NotebookAttendanceCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let actions: NotebookCellActions
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    var focusedCellId: FocusState<String?>.Binding
    /// Calculado en el padre: evita que cada celda lea el FocusState y se invalide con cada cambio de foco.
    let isFocused: Bool
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onOpenStructuredInstrument: () -> Void
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    var body: some View { statefulCell }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isFocused == rhs.isFocused &&
            lhs.navigationDirection == rhs.navigationDirection &&
            lhs.isAttendanceQuickMode == rhs.isAttendanceQuickMode &&
            lhs.reloadToken == rhs.reloadToken
    }
}

extension NotebookNumericCell {
    private var statefulCell: some View {
        NotebookStatefulEditableTableCell(
            displaySnapshot: displaySnapshot,
            actions: actions,
            item: item,
            column: column,
            classId: classId,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            focusedCellId: focusedCellId,
            isFocused: isFocused,
            activeChoiceCellId: $activeChoiceCellId,
            navigationDirection: navigationDirection,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            isAttendanceQuickMode: isAttendanceQuickMode,
            reloadToken: reloadToken,
            onSelect: onSelect,
            onPrepareUndo: onPrepareUndo,
            onOpenFormula: onOpenFormula,
            onOpenRubricIndividual: onOpenRubricIndividual,
            onOpenRubricBulk: onOpenRubricBulk,
            onOpenStructuredInstrument: onOpenStructuredInstrument,
            onGenerateSummary: onGenerateSummary,
            onNavigate: onNavigate,
            onCellSaved: onCellSaved,
            onAttendanceSaved: onAttendanceSaved
        )
    }
}

extension NotebookTextCell {
    private var statefulCell: some View {
        NotebookStatefulEditableTableCell(
            displaySnapshot: displaySnapshot,
            actions: actions,
            item: item,
            column: column,
            classId: classId,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            focusedCellId: focusedCellId,
            isFocused: isFocused,
            activeChoiceCellId: $activeChoiceCellId,
            navigationDirection: navigationDirection,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            isAttendanceQuickMode: isAttendanceQuickMode,
            reloadToken: reloadToken,
            onSelect: onSelect,
            onPrepareUndo: onPrepareUndo,
            onOpenFormula: onOpenFormula,
            onOpenRubricIndividual: onOpenRubricIndividual,
            onOpenRubricBulk: onOpenRubricBulk,
            onOpenStructuredInstrument: onOpenStructuredInstrument,
            onGenerateSummary: onGenerateSummary,
            onNavigate: onNavigate,
            onCellSaved: onCellSaved,
            onAttendanceSaved: onAttendanceSaved
        )
    }
}

extension NotebookCheckCell {
    private var statefulCell: some View {
        NotebookStatefulEditableTableCell(
            displaySnapshot: displaySnapshot,
            actions: actions,
            item: item,
            column: column,
            classId: classId,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            focusedCellId: focusedCellId,
            isFocused: isFocused,
            activeChoiceCellId: $activeChoiceCellId,
            navigationDirection: navigationDirection,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            isAttendanceQuickMode: isAttendanceQuickMode,
            reloadToken: reloadToken,
            onSelect: onSelect,
            onPrepareUndo: onPrepareUndo,
            onOpenFormula: onOpenFormula,
            onOpenRubricIndividual: onOpenRubricIndividual,
            onOpenRubricBulk: onOpenRubricBulk,
            onOpenStructuredInstrument: onOpenStructuredInstrument,
            onGenerateSummary: onGenerateSummary,
            onNavigate: onNavigate,
            onCellSaved: onCellSaved,
            onAttendanceSaved: onAttendanceSaved
        )
    }
}

extension NotebookAttendanceCell {
    private var statefulCell: some View {
        NotebookStatefulEditableTableCell(
            displaySnapshot: displaySnapshot,
            actions: actions,
            item: item,
            column: column,
            classId: classId,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            focusedCellId: focusedCellId,
            isFocused: isFocused,
            activeChoiceCellId: $activeChoiceCellId,
            navigationDirection: navigationDirection,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            isAttendanceQuickMode: isAttendanceQuickMode,
            reloadToken: reloadToken,
            onSelect: onSelect,
            onPrepareUndo: onPrepareUndo,
            onOpenFormula: onOpenFormula,
            onOpenRubricIndividual: onOpenRubricIndividual,
            onOpenRubricBulk: onOpenRubricBulk,
            onOpenStructuredInstrument: onOpenStructuredInstrument,
            onGenerateSummary: onGenerateSummary,
            onNavigate: onNavigate,
            onCellSaved: onCellSaved,
            onAttendanceSaved: onAttendanceSaved
        )
    }
}

@MainActor
private struct NotebookStatefulEditableTableCell: View {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let actions: NotebookCellActions
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let classId: Int64?
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    var focusedCellId: FocusState<String?>.Binding
    /// Calculado en el padre: evita que cada celda lea el FocusState y se invalide con cada cambio de foco.
    let isFocused: Bool
    @Binding var activeChoiceCellId: String?
    let navigationDirection: NotebookNavigationDirection
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let isAttendanceQuickMode: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onPrepareUndo: (String, String?) -> Void
    let onOpenFormula: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void
    let onOpenStructuredInstrument: () -> Void
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    private var persistedCell: PersistedNotebookCell? {
        item.lookup.cellsByColumnId[column.id]
    }

    @State private var numericDraft = ""
    @State private var textDraft = ""
    @State private var checkDraft = false
    @State private var originalNumericDraft = ""
    @State private var originalTextDraft = ""
    @State private var originalCheckDraft = false
    @State private var pendingCheckDraft: Bool?
    @State private var pendingNumericDraft: String?
    @State private var pendingTextDraft: String?
    @State private var numericDragStartValue: Double?
    @State private var numericDragLastWholeValue: Int?
    @State private var isNumericDragging = false
    @State private var showTextPopover = false
    @State private var isNumericKeyboardPresented = false
    @AppStorage("notebook.isQuickKeypadPresented") private var isQuickKeypadPresented = false
    @State private var hasLoadedDrafts = false
    @State private var physicalScore: Double?
    @State private var isResolvingPhysicalScore = false
    @State private var physicalScoreRequestID = UUID()
    @State private var physicalScoreTask: Task<Void, Never>?
    /// Clave alumno+columna+valor de la última resolución terminada o en curso (caché por celda).
    @State private var physicalScoreKey: String?
    @State private var lastExternalReloadTime: Date = .distantPast

    private var cellId: String {
        "\(item.student.id)|\(column.id)"
    }

    @State private var noticeToken = UUID()

    /// Se re-registra al cambiar los datos de la celda para que los cierres no queden con valores viejos.
    private func registerNoticeHandlers() {
        NotebookCellNoticeRouter.shared.register(
            token: noticeToken,
            cellId: cellId,
            onBackground: { saveFocusedDraftIfNeeded(requireFocusReleased: false) },
            onKeyboardEdit: { applyKeyboardEditNotice($0) }
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                .fill(editableCellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                        .stroke(editableCellBorder, lineWidth: editableCellBorderWidth)
                .animation(isSelected ? .easeOut(duration: 0.15) : nil, value: isSelected)
                )
                .notebookCellSelectionShadow(isSelected)
                .padding(2)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            let hasSignal = (persistedCell != nil && hasContextualSignal(in: persistedCell!)) ||
                displaySnapshot.hasNote ||
                (displaySnapshot.stampIcon != nil && !displaySnapshot.stampIcon!.isEmpty) ||
                displaySnapshot.attachmentCount > 0

            if hasSignal {
                VStack {
                    HStack {
                        Spacer()
                        NotebookCellStampBadge(
                            iconValue: displaySnapshot.stampIcon ?? persistedCell?.annotation?.icon ?? persistedCell?.iconValue,
                            note: displaySnapshot.hasNote ? (persistedCell?.annotation?.note ?? " ") : persistedCell?.annotation?.note,
                            attachmentCount: max(displaySnapshot.attachmentCount, persistedCell?.annotation?.attachmentUris.count ?? 0),
                            fallbackTint: tint,
                            studentName: item.student.fullName
                        )
                    }
                    Spacer()
                }
                .padding(4)
            }

            cellStateOverlay

            if isNumericDragging {
                Text("Desliza para ajustar")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .frame(width: width) // la altura la fija la fila (notebookGridRowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear {
            registerNoticeHandlers()
            loadDrafts()
            if NotebookKeyboardEditBuffer.isCapturing(cellId) {
                numericDraft = NotebookKeyboardEditBuffer.text
            }
            refreshPhysicalScore()
        }
        .onDisappear {
            saveFocusedDraftIfNeeded(requireFocusReleased: false)
            NotebookCellNoticeRouter.shared.unregister(token: noticeToken)
            // La celda sale de la ventana virtualizada: no se deja una resolución colgada.
            if isResolvingPhysicalScore {
                physicalScoreTask?.cancel()
                physicalScoreTask = nil
                physicalScoreKey = nil
                isResolvingPhysicalScore = false
            }
        }
        .appOnChange(of: reloadToken) { _ in
            registerNoticeHandlers()
            lastExternalReloadTime = Date()
            loadDraftsUnlessEditing()
            refreshPhysicalScore()
        }
        .appOnChange(of: displaySnapshot) { _ in
            registerNoticeHandlers()
            loadDraftsUnlessEditing()
        }
        .appOnChange(of: isFocused) { newValue in
            if newValue {
                onSelect()
            } else {
                saveFocusedDraftIfNeeded()
            }
        }
        .appOnChange(of: cellId) { _ in registerNoticeHandlers() }
        .appOnChange(of: textDraft) { newText in
            guard focusedCellId.wrappedValue == cellId else { return }
            if originalTextDraft != newText {
                pendingTextDraft = newText
                actions.saveColumnGradeDebounced(item.student.id, column, newText)
            }
        }
        .appOnChange(of: numericDraft) { newNumeric in
            guard focusedCellId.wrappedValue == cellId else { return }
            #if os(macOS)
            // En el Mac la nota se guarda al confirmar (flecha, Return o salir).
            // Así Esc puede devolver el valor de antes de escribir.
            _ = newNumeric
            return
            #else
            let trimmed = newNumeric.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || (!trimmed.hasSuffix(",") && !trimmed.hasSuffix(".") && Double(trimmed.replacingOccurrences(of: ",", with: ".")) != nil) {
                if originalNumericDraft != trimmed {
                    pendingNumericDraft = trimmed
                    actions.saveColumnGradeDebounced(item.student.id, column, trimmed)
                }
            }
            #endif
        }
    }

    /// Fill del chip interior. Por defecto transparente: el fondo real de la celda
    /// (zebra, wash de color de columna, selección) ya lo pinta el Rectangle exterior
    /// en `NotebookModuleGridCells.rowCell`. Este chip solo aparece para estados que
    /// necesitan su propia señal (bloqueada, calculada, borrador pendiente, selección/edición).
    private var editableCellFill: Color {
        if isSelected {
            // Superficie opaca (no tinte de acento): tapa el wash de columna por
            // debajo para que la celda se eleve limpia con sombra + anillo.
            return NotebookGridStyle.cellSelectionSurface
        }
        if column.isLocked {
            return NotebookStyle.surfaceMuted.opacity(0.45)
        }
        if column.type == .calculated {
            return Color.accentColor.opacity(0.04)
        }
        if hasPendingDraft {
            return NotebookStyle.warningTint.opacity(0.10)
        }
        return .clear
    }

    private var editableCellBorder: Color {
        if isSelected {
            return NotebookGridStyle.cellSelectionRing
        }
        if column.isLocked {
            return NotebookGridStyle.gridLineStrong
        }
        if column.type == .calculated {
            return Color.accentColor.opacity(0.18)
        }
        if hasPendingDraft {
            return NotebookStyle.warningTint.opacity(0.45)
        }
        return .clear
    }

    private var editableCellBorderWidth: CGFloat {
        isSelected ? NotebookGridStyle.cellSelectionRingWidth : 0.6
    }

    @ViewBuilder
    private var cellStateOverlay: some View {
        if stateStripeColor != nil || column.isLocked {
            ZStack {
                if let stateStripeColor {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(stateStripeColor)
                            .frame(height: 3)
                    }
                }

                if column.isLocked {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(NotebookGridStyle.gridLineStrong)
                            .frame(width: 3)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stateStripeLabel)
        }
    }

    private var stateStripeColor: Color? {
        if column.isLocked { return NotebookGridStyle.gridLineStrong }
        if isSelected { return NotebookGridStyle.cellSelectionRing }
        if formulaDisplay?.isError == true { return NotebookGridStyle.stateError }
        if hasPendingDraft { return NotebookGridStyle.statePending }
        if !column.countsTowardAverage { return NotebookGridStyle.gridLineStrong }
        return nil
    }

    private var stateStripeLabel: String {
        if column.isLocked { return "Celda bloqueada" }
        if isSelected { return "Celda activa" }
        if formulaDisplay?.isError == true { return "Error en la fórmula" }
        if hasPendingDraft { return "Pendiente de guardar" }
        if !column.countsTowardAverage { return "No cuenta para la media" }
        return ""
    }

    private var hasPendingDraft: Bool {
        if isStructuredInstrument {
            return false
        }
        switch column.type {
        case .numeric:
            return originalNumericDraft != numericDraft
        case .text, .icon, .ordinal, .attendance:
            return originalTextDraft != textDraft
        case .check:
            return originalCheckDraft != checkDraft
        default:
            return false
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAttendanceColumn {
            if isAttendanceQuickMode {
                quickAttendanceButton
            } else {
                attendancePicker
            }
        } else if isStructuredInstrument {
            structuredInstrumentButton
        } else {
            switch column.type {
            case .numeric:
                #if os(macOS)
                if isPhysicalMeasurementColumn {
                    physicalMeasurementButton
                } else {
                    numericMacField
                }
                #else
                if keyboardKind != .text {
                    Button {
                        onSelect()
                        focusedCellId.wrappedValue = nil
                        activeChoiceCellId = nil
                        if !isQuickKeypadPresented {
                            isNumericKeyboardPresented = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(numericDraft.isEmpty ? "—" : numericDraft)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(numericDraft.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                                .lineLimit(1)
                            if let physicalScore {
                                Text("· \(IosFormatting.decimal(physicalScore))")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(tint)
                                    .lineLimit(1)
                            }
                            Image(systemName: "arrow.up.and.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Arrastra para ajustar en décimas")
                            Image(systemName: "keyboard")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(numericDragGesture)
                    .popover(isPresented: $isNumericKeyboardPresented, arrowEdge: .bottom) {
                        cellKeyboardPopover
                    }
                } else {
                    let field = TextField("", text: $numericDraft)
                        .textFieldStyle(.plain)
                        .font(NotebookGridStyle.cellFont)
                        .appKeyboardType(.decimalPad)
                        .focused(focusedCellId, equals: cellId)
                        .submitLabel(.next)
                        .foregroundStyle(.primary)
                        .onSubmit { saveNumericAndNavigate(navigationDirection) }
                        .simultaneousGesture(numericDragGesture)

                    #if canImport(UIKit)
                    field
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Button("Arriba") { saveNumericAndNavigate(.up) }
                                Button("Abajo") { saveNumericAndNavigate(.down) }
                                Spacer()
                                Button("Guardar y avanzar") {
                                    saveNumericAndNavigate(navigationDirection)
                                }
                            }
                        }
                    #else
                    field
                    #endif
                }
                #endif
            case .calculated:
                Button {
                    onSelect()
                    onOpenFormula()
                } label: {
                    HStack(spacing: 5) {
                        Text(displaySnapshot.calculatedText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .italic()
                            .monospacedDigit()
                            .foregroundStyle(formulaDisplay?.isError == true ? Color.orange : (isSelected ? Color.accentColor : Color.primary))
                            .lineLimit(1)
                        Image(systemName: formulaDisplay?.isError == true ? "exclamationmark.triangle.fill" : "function")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(formulaDisplay?.isError == true ? Color.orange : Color.accentColor.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .help(formulaDisplay?.isError == true ? (formulaDisplay?.text ?? "Error en la fórmula") : "Editar fórmula")
            case .check:
                checkButton
            case .ordinal:
                Button {
                    onSelect()
                    activeChoiceCellId = cellId
                } label: {
                    Text(textDraft.isEmpty ? "Seleccionar" : textDraft)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: choicePopoverBinding, arrowEdge: .bottom) {
                    choiceList(options: ordinalOptions) { option in
                        saveOrdinalValue(option)
                    }
                }
            case .rubric:
                Button {
                    onSelect()
                    onOpenRubricIndividual()
                } label: {
                    NotebookRubricValueLabel(rubricText: displaySnapshot.rubricText)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Evaluar alumno…") {
                        onSelect()
                        onOpenRubricIndividual()
                    }
                    Button("Evaluar grupo…") {
                        onSelect()
                        onOpenRubricBulk()
                    }
                }
            default:
                HStack(spacing: 6) {
                    if isNotebookIndividualSummaryColumn(column) {
                        Text(textDraft.isEmpty ? "Síntesis pendiente" : textDraft)
                            .font(.system(size: 13))
                            .foregroundStyle(textDraft.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    } else {
                        TextField("", text: $textDraft)
                            .textFieldStyle(.plain)
                            .focused(focusedCellId, equals: cellId)
                            .foregroundStyle(.primary)
                            .submitLabel(.next)
                            .onSubmit { saveTextAndNavigate() }
                    }

                    if isEmptySummaryCell {
                        Button {
                            onSelect()
                            onGenerateSummary?()
                        } label: {
                            Label("Generar", systemImage: "apple.intelligence")
                                .labelStyle(.iconOnly)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .help("Generar síntesis pedagógica")
                    }

                    if shouldOfferTextPopover {
                        Button {
                            showTextPopover = true
                        } label: {
                            Image(systemName: "text.alignleft")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showTextPopover, arrowEdge: .bottom) {
                            #if os(macOS)
                            VStack(spacing: 0) {
                                ScrollView {
                                    Text(textDraft)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: 320, alignment: .leading)
                                        .padding(14)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: 340, maxHeight: 260)

                                MacPopupActionBar(
                                    title: nil,
                                    onClose: { showTextPopover = false }
                                )
                            }
                            #else
                            ScrollView {
                                Text(textDraft)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: 320, alignment: .leading)
                                    .padding(14)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: 340, maxHeight: 260)
                            #endif
                        }
                    }
                }
            }
        }
    }

    #if os(macOS)
    private var numericMacField: some View {
        HStack(spacing: 6) {
            if isFocused {
                TextField("", text: $numericDraft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(NotebookGridStyle.cellFont)
                    .foregroundStyle(AnyShapeStyle(.primary))
                    .focused(focusedCellId, equals: cellId)
                    .onAppear {
                        focusedCellId.wrappedValue = cellId
                    }
                    .onKeyPress(.escape) {
                        cancelNumericEdit()
                        return .handled
                    }
                    .onKeyPress(.return) {
                        commitNumericAndMove(navigationDirection)
                        return .handled
                    }
                    .onKeyPress(.upArrow) { commitNumericAndMove(.up); return .handled }
                    .onKeyPress(.downArrow) { commitNumericAndMove(.down); return .handled }
                    .onKeyPress(.leftArrow) { commitNumericAndMove(.left); return .handled }
                    .onKeyPress(.rightArrow) { commitNumericAndMove(.right); return .handled }
                    .onKeyPress(keys: [.tab]) { press in
                        commitNumericAndMove(press.modifiers.contains(.shift) ? .left : .right)
                        return .handled
                    }
            } else {
                Text(numericDraft.isEmpty ? "—" : numericDraft)
                    .font(NotebookGridStyle.cellFont)
                    .monospacedDigit()
                    .foregroundStyle(numericDraft.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func cancelNumericEdit() {
        numericDraft = originalNumericDraft
        pendingNumericDraft = nil
        focusedCellId.wrappedValue = nil
        onSelect()
    }
    #endif

    private func commitNumericAndMove(_ direction: NotebookNavigationDirection) {
        trimIncompleteDecimalDraft()
        saveNumeric(selectsCell: false, immediate: true)
        NotebookKeyboardSession.requestMoveWithoutEditing()
        onNavigate(direction)
    }

    private func trimIncompleteDecimalDraft() {
        let trimmed = numericDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 1, trimmed.hasSuffix(",") || trimmed.hasSuffix(".") {
            numericDraft = String(trimmed.dropLast())
        }
    }

    private var physicalMeasurementButton: some View {
        Button {
            onSelect()
            focusedCellId.wrappedValue = nil
            activeChoiceCellId = nil
            isNumericKeyboardPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(numericDraft.isEmpty ? "—" : numericDraft)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numericDraft.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                if let physicalScore {
                    Text("· \(IosFormatting.decimal(physicalScore))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Image(systemName: keyboardKind == .time ? "stopwatch" : "keyboard")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
        #if !os(macOS)
        .simultaneousGesture(numericDragGesture)
        #endif
        .popover(isPresented: $isNumericKeyboardPresented, arrowEdge: .bottom) {
            cellKeyboardPopover
        }
    }

    private var isAttendanceColumn: Bool {
        column.type == .attendance || column.categoryKind == .attendance
    }

    private var isStructuredInstrument: Bool {
        column.inputKind.isStructuredInstrument
    }

    private var isPhysicalMeasurementColumn: Bool {
        column.instrumentKind == .physicalTest &&
            [.time, .distance, .repetitions].contains(column.inputKind)
    }

    private var isEmptySummaryCell: Bool {
        isNotebookIndividualSummaryColumn(column) &&
            textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var keyboardKind: NotebookCellKeyboardKind {
        switch column.inputKind {
        case .numeric010:
            return .numeric010
        case .time:
            return .time
        case .distance:
            return .distance
        case .repetitions:
            return .repetitions
        case .quickSelector:
            return .quickSelector
        case .rubric:
            return .rubric
        case .check:
            return .check
        case .calculated:
            return .readOnlyFormula
        default:
            return .text
        }
    }

    @ViewBuilder
    private var cellKeyboardPopover: some View {
        VStack(spacing: 8) {
            if isPhysicalMeasurementColumn {
                physicalScoreSummary
            }

            switch keyboardKind {
            case .numeric010:
                NotebookNumericCellKeyboard(
                    value: $numericDraft,
                    tint: tint,
                    onSave: { saveNumeric() },
                    onNavigate: { direction in
                        saveNumericAndNavigate(direction)
                        isNumericKeyboardPresented = false
                    }
                )
            case .time:
                NotebookTimeCellKeyboard(
                    value: $numericDraft,
                    tint: tint,
                    onSave: { saveNumeric() },
                    onNavigate: { direction in
                        saveNumericAndNavigate(direction)
                        isNumericKeyboardPresented = false
                    }
                )
            case .distance:
                NotebookDistanceCellKeyboard(
                    value: $numericDraft,
                    tint: tint,
                    unitLabel: column.unitOrSituation ?? "m",
                    onSave: { saveNumeric() },
                    onNavigate: { direction in
                        saveNumericAndNavigate(direction)
                        isNumericKeyboardPresented = false
                    }
                )
            case .repetitions:
                NotebookRepetitionCellKeyboard(
                    value: $numericDraft,
                    tint: tint,
                    onSave: { saveNumeric() },
                    onNavigate: { direction in
                        saveNumericAndNavigate(direction)
                        isNumericKeyboardPresented = false
                    }
                )
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var physicalScoreSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.caption.weight(.bold))
            if let physicalScore {
                Text("Nota de referencia: \(IosFormatting.decimal(physicalScore)) / 10")
                    .font(.caption.weight(.semibold))
            } else if isResolvingPhysicalScore {
                Text("Calculando baremo…")
                    .font(.caption.weight(.semibold))
            } else if !numericDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Sin baremo aplicable")
                    .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(physicalScore == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var checkButton: some View {
        Button {
            cycleCheckValue()
        } label: {
            Text(checkDraft ? "✓" : "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(checkDraft ? NotebookStyle.successTint : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(checkDraft ? NotebookStyle.successTint.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var structuredInstrumentButton: some View {
        Button {
            onSelect()
            onOpenStructuredInstrument()
        } label: {
            NotebookStructuredValueLabel(text: structuredDisplayText)
        }
        .buttonStyle(.plain)
        .help("Abrir instrumento")
    }

    private var structuredDisplayText: String {
        if column.type == .numeric {
            let num = numericDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !num.isEmpty { return num }
            let snapshotNum = displaySnapshot.numericText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snapshotNum.isEmpty { return snapshotNum }
        }
        let value = (persistedCell?.displayValue ?? persistedCell?.textValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Pendiente" : value
    }

    private var choicePopoverBinding: Binding<Bool> {
        Binding(
            get: { activeChoiceCellId == cellId },
            set: { isPresented in
                if isPresented {
                    activeChoiceCellId = cellId
                } else if activeChoiceCellId == cellId {
                    activeChoiceCellId = nil
                }
            }
        )
    }

    private func choiceList(options: [String], onChoose: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    onChoose(option)
                } label: {
                    HStack {
                        Text(option)
                        Spacer(minLength: 18)
                        if textDraft == option {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .frame(minWidth: 170, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
        .padding(8)
    }

    private var attendancePicker: some View {
        Button {
            onSelect()
            activeChoiceCellId = cellId
        } label: {
            attendanceChip(value: textDraft)
        }
        .buttonStyle(.plain)
        .popover(isPresented: choicePopoverBinding, arrowEdge: .bottom) {
            choiceList(options: attendanceOptions.map(\.label)) { label in
                if let option = attendanceOptions.first(where: { $0.label == label }) {
                    saveAttendanceValue(option.value)
                }
            }
        }
    }

    private var quickAttendanceButton: some View {
        Button {
            saveQuickAttendanceValue()
        } label: {
            HStack(spacing: 6) {
                attendanceChip(value: textDraft)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.plain)
        .help("Pase rápido")
    }

    private var numericDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if numericDragStartValue == nil {
                    numericDragStartValue = parseEditableNumber(numericDraft) ?? 0
                    numericDragLastWholeValue = Int((parseEditableNumber(numericDraft) ?? 0).rounded(.down))
                    isNumericDragging = true
                }
                guard let start = numericDragStartValue else { return }
                let delta = Double(-value.translation.height / 20.0)
                let adjusted = min(10.0, max(0.0, start + delta))
                let rounded = (adjusted * 10).rounded() / 10
                numericDraft = String(format: "%.1f", rounded)
                let wholeValue = Int(rounded.rounded(.down))
                if wholeValue != numericDragLastWholeValue {
                    numericDragLastWholeValue = wholeValue
                    AppleInteractionFeedback.play(wholeValue == 0 || wholeValue == 10 ? .warning : .selection)
                }
            }
            .onEnded { _ in
                numericDragStartValue = nil
                numericDragLastWholeValue = nil
                isNumericDragging = false
                saveNumeric()
                AppleInteractionFeedback.play(.success)
            }
    }

    private var attendanceOptions: [(label: String, value: String)] {
        [
            ("Presente", NotebookAttendanceStatus.present),
            ("Ausente", NotebookAttendanceStatus.absent),
            ("Retraso", NotebookAttendanceStatus.late),
            ("Justificada", NotebookAttendanceStatus.justified),
            ("Sin material", NotebookAttendanceStatus.noMaterial),
            ("Exento", NotebookAttendanceStatus.exempt),
            ("Sin pasar", "")
        ]
    }

    private func attendanceChip(value: String) -> some View {
        let display = attendanceDisplay(value)
        return Text(display.label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(display.color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(display.color.opacity(display.value.isEmpty ? 0.08 : 0.14))
            )
    }

    private func attendanceDisplay(_ value: String) -> (label: String, value: String, color: Color) {
        let normalized = NotebookAttendanceStatus.canonical(value)
        switch normalized {
        case NotebookAttendanceStatus.present:
            return ("Presente", normalized, .green)
        case NotebookAttendanceStatus.absent:
            return ("Ausente", normalized, .red)
        case NotebookAttendanceStatus.late:
            return ("Retraso", normalized, .orange)
        case NotebookAttendanceStatus.justified:
            return ("Justificada", normalized, .gray)
        case NotebookAttendanceStatus.noMaterial:
            return ("Sin material", normalized, .brown)
        case NotebookAttendanceStatus.exempt:
            return ("Exento", normalized, .indigo)
        default:
            return ("—", "", .secondary)
        }
    }

    private func nextQuickAttendanceStatus(after value: String) -> String {
        switch attendanceDisplay(value).value {
        case "":
            return NotebookAttendanceStatus.present
        case NotebookAttendanceStatus.present:
            return NotebookAttendanceStatus.absent
        case NotebookAttendanceStatus.absent:
            return NotebookAttendanceStatus.late
        default:
            return NotebookAttendanceStatus.present
        }
    }

    private func parseEditableNumber(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func physicalRawValue() -> Double? {
        if column.inputKind == .time {
            let normalized = numericDraft.replacingOccurrences(of: ".", with: ",")
            let minuteParts = normalized.split(separator: ":", omittingEmptySubsequences: false)
            if minuteParts.count == 2 {
                let minutes = Double(minuteParts[0]) ?? 0
                let secondParts = minuteParts[1].split(separator: ",", omittingEmptySubsequences: false)
                let seconds = Double(secondParts.first ?? "0") ?? 0
                let fractionText = String(secondParts.dropFirst().first ?? "0")
                let fraction = Double("0.\(fractionText)") ?? 0
                return max(0, minutes * 60 + seconds + fraction)
            }
        }
        return parseEditableNumber(numericDraft)
    }

    private func refreshPhysicalScore() {
        guard isPhysicalMeasurementColumn,
              let classId,
              let resolver = actions.resolvePhysicalScore,
              let rawValue = physicalRawValue()
        else {
            physicalScoreTask?.cancel()
            physicalScoreTask = nil
            physicalScoreKey = nil
            physicalScore = nil
            isResolvingPhysicalScore = false
            return
        }

        // Caché por alumno + columna + valor: si no cambió nada, no se vuelve a resolver.
        let key = "\(classId)|\(item.student.id)|\(column.id)|\(rawValue)|\(reloadToken)"
        if physicalScoreKey == key { return }
        physicalScoreKey = key
        physicalScoreTask?.cancel()

        let requestID = UUID()
        physicalScoreRequestID = requestID
        isResolvingPhysicalScore = true
        physicalScoreTask = Task { @MainActor in
            let resolved = await resolver(item.student, classId, column.id, rawValue)
            guard !Task.isCancelled, physicalScoreRequestID == requestID else { return }
            physicalScore = resolved
            isResolvingPhysicalScore = false
        }
    }

    private var ordinalOptions: [String] {
        if !column.ordinalLevels.isEmpty { return column.ordinalLevels }
        switch column.inputKind {
        case .letterAbcd:
            return ["A", "B", "C", "D"]
        case .achievedPartialNotAchieved:
            return ["Logrado", "Parcial", "No logrado"]
        case .excellentGoodProgress:
            return ["Excelente", "Bien", "En proceso"]
        default:
            return ["A", "B", "C", "D"]
        }
    }

    private func loadDrafts() {
        hasLoadedDrafts = false
        let cell = persistedCell
        switch column.type {
        case .check:
            if let pendingCheckDraft {
                let persistedBool = cell?.boolValue?.boolValue
                if persistedBool == pendingCheckDraft {
                    self.pendingCheckDraft = nil
                } else {
                    checkDraft = pendingCheckDraft
                    originalCheckDraft = pendingCheckDraft
                    hasLoadedDrafts = true
                    return
                }
            }
            checkDraft = displaySnapshot.checkValue
            originalCheckDraft = checkDraft
        case .attendance:
            let textValue = cell?.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayValue = cell?.displayValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = textValue.isEmpty ? displayValue : textValue
            let canonical = NotebookAttendanceStatus.canonical(raw)
            if !raw.isEmpty, canonical.isEmpty {
                textDraft = NotebookAttendanceStatus.canonical(displaySnapshot.text)
            } else {
                textDraft = canonical
            }
            originalTextDraft = textDraft
        case .ordinal, .text, .icon:
            let resolvedSnapshotText = !displaySnapshot.text.isEmpty ? displaySnapshot.text : (cell?.textValue ?? cell?.displayValue ?? "")
            if let pendingTextDraft {
                if resolvedSnapshotText == pendingTextDraft {
                    self.pendingTextDraft = nil
                } else {
                    textDraft = pendingTextDraft
                    originalTextDraft = pendingTextDraft
                    hasLoadedDrafts = true
                    return
                }
            }
            textDraft = resolvedSnapshotText
            originalTextDraft = textDraft
        case .numeric:
            if let pendingNumericDraft {
                if displaySnapshot.numericText == pendingNumericDraft {
                    self.pendingNumericDraft = nil
                } else {
                    numericDraft = pendingNumericDraft
                    originalNumericDraft = pendingNumericDraft
                    hasLoadedDrafts = true
                    return
                }
            }
            numericDraft = displaySnapshot.numericText
            originalNumericDraft = numericDraft
        default:
            break
        }
        hasLoadedDrafts = true
    }

    private func loadDraftsUnlessEditing() {
        guard focusedCellId.wrappedValue != cellId,
              activeChoiceCellId != cellId,
              !isNumericKeyboardPresented,
              !showTextPopover,
              !NotebookKeyboardEditBuffer.isCapturing(cellId) else { return }
        loadDrafts()
    }

    private func applyKeyboardEditNotice(_ note: Notification) {
        guard let id = note.userInfo?["cellId"] as? String, id == cellId else { return }
        guard let command = note.userInfo?["command"] as? String else { return }
        let text = note.userInfo?["text"] as? String
        switch command {
        case "set":
            numericDraft = text ?? ""
        case "cancel":
            numericDraft = originalNumericDraft
            pendingNumericDraft = nil
        case "sync":
            if let text {
                numericDraft = text
                originalNumericDraft = text
                pendingNumericDraft = text
            }
        default:
            break
        }
    }

    private func saveNumeric(selectsCell: Bool = true, immediate: Bool = false) {
        guard !column.isLocked else { return }
        if selectsCell {
            onSelect()
        }
        if originalNumericDraft != numericDraft {
            onPrepareUndo(originalNumericDraft, originalNumericDraft)
            originalNumericDraft = numericDraft
            pendingNumericDraft = numericDraft
            if immediate || column.inputKind == .time {
                actions.flushPendingColumnGradeSave(item.student.id, column.id)
                actions.saveColumnGrade(item.student.id, column, numericDraft)
            } else {
                actions.saveColumnGradeDebounced(item.student.id, column, numericDraft)
            }
            if isPhysicalMeasurementColumn {
                refreshPhysicalScore()
            }
            onCellSaved()
        }
    }

    private func saveNumericAndNavigate(_ direction: NotebookNavigationDirection) {
        saveNumeric()
        onNavigate(direction)
    }

    private func saveText(selectsCell: Bool = true, immediate: Bool = false) {
        guard !column.isLocked else { return }
        if selectsCell {
            onSelect()
        }
        if originalTextDraft != textDraft {
            onPrepareUndo(originalTextDraft, originalTextDraft)
            originalTextDraft = textDraft
            pendingTextDraft = textDraft
            if immediate {
                actions.flushPendingColumnGradeSave(item.student.id, column.id)
                actions.saveColumnGrade(item.student.id, column, textDraft)
            } else {
                actions.saveColumnGradeDebounced(item.student.id, column, textDraft)
            }
            onCellSaved()
        }
    }

    private func saveTextAndNavigate() {
        saveText()
        onNavigate(navigationDirection)
    }

    private func saveOrdinalValue(_ option: String) {
        guard !column.isLocked else { return }
        let previousValue = textDraft
        textDraft = option
        onSelect()
        activeChoiceCellId = nil
        if previousValue != option {
            onPrepareUndo(previousValue, previousValue)
            originalTextDraft = option
        }
        AppleInteractionFeedback.play(.selection)
        actions.saveColumnGrade(item.student.id, column, option)
        onCellSaved()
        onNavigate(navigationDirection)
    }

    private func cycleCheckValue() {
        guard !column.isLocked else { return }
        guard hasLoadedDrafts else { return }
        let previousValue = checkDraft ? "true" : "false"
        checkDraft.toggle()
        pendingCheckDraft = checkDraft
        let nextValue = checkDraft ? "true" : "false"
        onSelect()
        if previousValue != nextValue {
            onPrepareUndo(previousValue, previousValue == "true" ? "Sí" : "No")
            originalCheckDraft = checkDraft
        }
        AppleInteractionFeedback.play(.lightImpact)
        actions.saveColumnGrade(item.student.id, column, nextValue)
        onCellSaved()
        onNavigate(navigationDirection)
    }

    private func saveAttendanceValue(_ status: String) {
        guard !column.isLocked else { return }
        let canonicalStatus = NotebookAttendanceStatus.canonical(status)
        let previousValue = textDraft
        textDraft = canonicalStatus
        onSelect()
        activeChoiceCellId = nil
        if previousValue != canonicalStatus {
            onPrepareUndo(previousValue, attendanceDisplay(previousValue).label)
            originalTextDraft = canonicalStatus
        }
        AppleInteractionFeedback.play(.selection)
        actions.saveColumnGrade(item.student.id, column, canonicalStatus)
        onCellSaved()
        onNavigate(navigationDirection)

        guard let classId else { return }
        let attendanceDate = column.dateEpochMs
            .map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000.0) } ?? Date()

        Task {
            let saved = await actions.saveAttendance(item.student.id, classId, attendanceDate, canonicalStatus)
            await MainActor.run {
                if saved {
                    onAttendanceSaved()
                } else {
                    textDraft = previousValue
                    originalTextDraft = previousValue
                }
            }
        }
    }

    private func saveQuickAttendanceValue() {
        let nextStatus = nextQuickAttendanceStatus(after: textDraft)
        saveAttendanceValue(nextStatus)
    }

    private func saveFocusedDraftIfNeeded(requireFocusReleased: Bool = true) {
        guard hasLoadedDrafts, activeChoiceCellId != cellId else { return }
        // Al salir de la celda o ir a segundo plano, guardar ya aunque el teclado siga abierto.
        if requireFocusReleased {
            guard !isNumericKeyboardPresented,
                  !showTextPopover,
                  !NotebookKeyboardEditBuffer.isCapturing(cellId)
            else { return }
            guard focusedCellId.wrappedValue != cellId else { return }
        }

        switch column.type {
        case .numeric:
            #if os(macOS)
            trimIncompleteDecimalDraft()
            #endif
            if originalNumericDraft != numericDraft {
                saveNumeric(selectsCell: false, immediate: true)
            }
        case .text, .icon:
            if originalTextDraft != textDraft {
                saveText(selectsCell: false, immediate: true)
            }
        default:
            break
        }
    }

    private func hasContextualSignal(in cell: PersistedNotebookCell) -> Bool {
        !(cell.annotation?.note?.isEmpty ?? true) ||
            !((cell.annotation?.icon ?? cell.iconValue ?? "").isEmpty) ||
            !(cell.annotation?.attachmentUris.isEmpty ?? true)
    }

    private var shouldOfferTextPopover: Bool {
        !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && estimatedTextWidth > max(80, width - 56)
    }

    private var estimatedTextWidth: CGFloat {
        #if canImport(UIKit)
        return (textDraft as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13)]).width
        #else
        return CGFloat(textDraft.count) * 7
        #endif
    }

}

private struct NotebookFormulaCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onOpenFormula: () -> Void

    var body: some View {
        NotebookReadOnlyCellChrome(
            displaySnapshot: displaySnapshot,
            item: item,
            column: column,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            onSelect: onSelect
        ) {
            Button {
                onSelect()
                onOpenFormula()
            } label: {
                HStack(spacing: 5) {
                    Text(displaySnapshot.calculatedText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .italic()
                        .monospacedDigit()
                        .foregroundStyle(formulaDisplay?.isError == true ? Color.orange : (isSelected ? Color.accentColor : Color.primary))
                        .lineLimit(1)
                    Image(systemName: formulaDisplay?.isError == true ? "exclamationmark.triangle.fill" : "function")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(formulaDisplay?.isError == true ? Color.orange : Color.accentColor.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .help(formulaDisplay?.isError == true ? (formulaDisplay?.text ?? "Error en la fórmula") : "Editar fórmula")
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.reloadToken == rhs.reloadToken &&
            lhs.formulaDisplay?.text == rhs.formulaDisplay?.text &&
            lhs.formulaDisplay?.isError == rhs.formulaDisplay?.isError
    }
}

private struct NotebookRubricCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void

    var body: some View {
        NotebookReadOnlyCellChrome(
            displaySnapshot: displaySnapshot,
            item: item,
            column: column,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            onSelect: onSelect
        ) {
            Button {
                onSelect()
                onOpenRubricIndividual()
            } label: {
                NotebookRubricValueLabel(rubricText: displaySnapshot.rubricText)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Evaluar alumno…") {
                    onSelect()
                    onOpenRubricIndividual()
                }
                Button("Evaluar grupo…") {
                    onSelect()
                    onOpenRubricBulk()
                }
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.reloadToken == rhs.reloadToken
    }
}

private struct NotebookReadOnlyCell: View, Equatable {
    let displaySnapshot: NotebookCellDisplaySnapshot
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let reloadToken: Int
    let onSelect: () -> Void
    let onOpenStructuredInstrument: () -> Void

    private var persistedCell: PersistedNotebookCell? {
        item.lookup.cellsByColumnId[column.id]
    }

    private var displayText: String {
        let snapshotText = displaySnapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snapshotText.isEmpty {
            return snapshotText
        }
        let value = (persistedCell?.displayValue ?? persistedCell?.textValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Pendiente" : value
    }

    var body: some View {
        NotebookReadOnlyCellChrome(
            displaySnapshot: displaySnapshot,
            item: item,
            column: column,
            width: width,
            tint: tint,
            categoryTint: categoryTint,
            hasColumnColor: hasColumnColor,
            formulaDisplay: formulaDisplay,
            isSelected: isSelected,
            onSelect: onSelect
        ) {
            Button {
                onSelect()
                onOpenStructuredInstrument()
            } label: {
                NotebookStructuredValueLabel(text: displayText)
            }
            .buttonStyle(.plain)
            .help("Abrir instrumento")
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.hasSameCellAppearance(as: rhs.column) &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
            lhs.reloadToken == rhs.reloadToken &&
            lhs.displayText == rhs.displayText
    }
}

@MainActor
private struct NotebookReadOnlyCellChrome<Content: View>: View {
    let displaySnapshot: NotebookCellDisplaySnapshot?
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let width: CGFloat
    let tint: Color
    let categoryTint: Color?
    let hasColumnColor: Bool
    let formulaDisplay: NotebookFormulaCellDisplay?
    let isSelected: Bool
    let onSelect: () -> Void
    let content: Content

    init(
        displaySnapshot: NotebookCellDisplaySnapshot? = nil,
        item: NotebookTableRow,
        column: NotebookColumnDefinition,
        width: CGFloat,
        tint: Color,
        categoryTint: Color?,
        hasColumnColor: Bool,
        formulaDisplay: NotebookFormulaCellDisplay?,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.displaySnapshot = displaySnapshot
        self.item = item
        self.column = column
        self.width = width
        self.tint = tint
        self.categoryTint = categoryTint
        self.hasColumnColor = hasColumnColor
        self.formulaDisplay = formulaDisplay
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.content = content()
    }

    private var persistedCell: PersistedNotebookCell? {
        item.lookup.cellsByColumnId[column.id]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                .fill(cellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                        .stroke(cellBorder, lineWidth: isSelected ? NotebookGridStyle.cellSelectionRingWidth : 0.6)
                )
                .notebookCellSelectionShadow(isSelected)
                .padding(2)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            let hasSignal = (persistedCell != nil && hasContextualSignal(in: persistedCell!)) ||
                (displaySnapshot?.hasNote == true) ||
                (displaySnapshot?.stampIcon != nil && !(displaySnapshot?.stampIcon?.isEmpty ?? true)) ||
                (displaySnapshot?.attachmentCount ?? 0) > 0

            if hasSignal {
                VStack {
                    HStack {
                        Spacer()
                        NotebookCellStampBadge(
                            iconValue: displaySnapshot?.stampIcon ?? persistedCell?.annotation?.icon ?? persistedCell?.iconValue,
                            note: displaySnapshot?.hasNote == true ? (persistedCell?.annotation?.note ?? " ") : persistedCell?.annotation?.note,
                            attachmentCount: max(displaySnapshot?.attachmentCount ?? 0, persistedCell?.annotation?.attachmentUris.count ?? 0),
                            fallbackTint: tint,
                            studentName: item.student.fullName
                        )
                    }
                    Spacer()
                }
                .padding(4)
            }

            cellStateOverlay
        }
        .frame(width: width) // la altura la fija la fila (notebookGridRowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /// Fill del chip interior. Transparente por defecto: el fondo real de la celda
    /// (zebra, wash de color de columna, selección) ya lo pinta el Rectangle exterior
    /// en `NotebookModuleGridCells.rowCell`.
    private var cellFill: Color {
        if isSelected {
            return NotebookGridStyle.cellSelectionSurface
        }
        if column.isLocked {
            return NotebookStyle.surfaceMuted.opacity(0.45)
        }
        if column.type == .calculated {
            return Color.accentColor.opacity(0.04)
        }
        return .clear
    }

    private var cellBorder: Color {
        if isSelected {
            return NotebookGridStyle.cellSelectionRing
        }
        if column.isLocked {
            return NotebookGridStyle.gridLineStrong
        }
        if column.type == .calculated {
            return Color.accentColor.opacity(0.18)
        }
        return .clear
    }

    @ViewBuilder
    private var cellStateOverlay: some View {
        if stateStripeColor != nil || column.isLocked {
            ZStack {
                if let stateStripeColor {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(stateStripeColor)
                            .frame(height: 3)
                    }
                }

                if column.isLocked {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(NotebookGridStyle.gridLineStrong)
                            .frame(width: 3)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stateStripeLabel)
        }
    }

    private var stateStripeColor: Color? {
        if column.isLocked { return NotebookGridStyle.gridLineStrong }
        if isSelected { return NotebookGridStyle.cellSelectionRing }
        if formulaDisplay?.isError == true { return NotebookGridStyle.stateError }
        if !column.countsTowardAverage { return NotebookGridStyle.gridLineStrong }
        return nil
    }

    private var stateStripeLabel: String {
        if column.isLocked { return "Celda bloqueada" }
        if isSelected { return "Celda activa" }
        if formulaDisplay?.isError == true { return "Error en la fórmula" }
        if !column.countsTowardAverage { return "No cuenta para la media" }
        return ""
    }

    private func hasContextualSignal(in cell: PersistedNotebookCell) -> Bool {
        !(cell.annotation?.note?.isEmpty ?? true) ||
            !((cell.annotation?.icon ?? cell.iconValue ?? "").isEmpty) ||
            !(cell.annotation?.attachmentUris.isEmpty ?? true)
    }
}

private extension View {
    /// La sombra de selección solo existe en la celda seleccionada: `.shadow` con color `.clear`
    /// sigue costando en cada celda visible.
    @ViewBuilder
    func notebookCellSelectionShadow(_ isSelected: Bool) -> some View {
        if isSelected {
            shadow(color: NotebookGridStyle.cellSelectionShadow, radius: 4, x: 0, y: 1.5)
        } else {
            self
        }
    }
}

private extension NotebookColumnDefinition {
    /// Comparación directa de los campos que afectan al pintado de la celda: sin `String(describing:)`
    /// sobre enums Kotlin ni structs intermedios por cada comparación.
    func hasSameCellAppearance(as other: NotebookColumnDefinition) -> Bool {
        id == other.id &&
            type == other.type &&
            inputKind == other.inputKind &&
            categoryKind == other.categoryKind &&
            categoryId == other.categoryId &&
            colorHex == other.colorHex &&
            isLocked == other.isLocked &&
            countsTowardAverage == other.countsTowardAverage &&
            unitOrSituation == other.unitOrSituation &&
            ordinalLevels == other.ordinalLevels &&
            dateEpochMs?.int64Value == other.dateEpochMs?.int64Value
    }
}


// MARK: - Marcas de celda (rúbrica, instrumentos)

/// Marca de celda vacía. En macOS muestra un "+" tenue al pasar el ratón
/// (`@State` local, sin animación); en iOS es solo la marca.
private struct NotebookEmptyCellMark<Mark: View>: View {
    let helpText: String
    let mark: Mark
    #if os(macOS)
    @State private var isHovering = false
    #endif

    init(helpText: String, @ViewBuilder mark: () -> Mark) {
        self.helpText = helpText
        self.mark = mark()
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            if isHovering {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                mark
            }
            #else
            mark
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .help(helpText)
    }
}

/// Nota de rúbrica: solo el número, con barra vertical del color del nivel.
/// El nivel también va en `.help` y en el valor de accesibilidad (no depende
/// solo del color). Vacía: barra gris, sin "—".
private struct NotebookRubricValueLabel: View {
    let rubricText: String

    /// Devuelve el número tal como se muestra ("7,5") y su valor, o nil si no es numérico.
    static func parse(_ raw: String) -> (text: String, value: Double)? {
        let head = raw.components(separatedBy: "/").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let value = Double(head.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return (head, value)
    }

    private static func isEmpty(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Sin dato" || trimmed == "—"
    }

    static func accessibilityValue(for raw: String) -> String {
        if let parsed = parse(raw) {
            return "\(parsed.text), nivel \(NotebookGradeBand(scoreOutOfTen: parsed.value).levelName)"
        }
        return isEmpty(raw) ? "Pendiente" : raw
    }

    var body: some View {
        if let parsed = Self.parse(rubricText) {
            let band = NotebookGradeBand(scoreOutOfTen: parsed.value)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(band.color)
                    .frame(width: 3, height: 16)
                Text(parsed.text)
                    .font(NotebookGridStyle.cellFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .help("Nivel \(band.levelName)")
        } else if Self.isEmpty(rubricText) {
            NotebookEmptyCellMark(helpText: "Pendiente") {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(NotebookGridStyle.stateEmpty)
                    .frame(width: 3, height: 16)
            }
        } else {
            Text(rubricText)
                .font(NotebookGridStyle.cellFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
}

/// Estado de un instrumento estructurado (observación, checklist): vacío =
/// círculo hueco, parcial = "n/m" en dígitos monoespaciados, completo = marca verde.
private struct NotebookStructuredValueLabel: View {
    let text: String

    private static func progress(_ raw: String) -> (done: Int, total: Int)? {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let done = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let total = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              total > 0 else { return nil }
        return (done, total)
    }

    private static func isPending(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Pendiente"
    }

    static func accessibilityValue(for raw: String) -> String {
        if isPending(raw) { return "Pendiente" }
        if let p = progress(raw) { return "\(p.done) de \(p.total)" }
        return raw
    }

    var body: some View {
        if Self.isPending(text) {
            NotebookEmptyCellMark(helpText: "Pendiente") {
                Circle()
                    .strokeBorder(NotebookGridStyle.stateEmpty, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
            }
        } else if let p = Self.progress(text) {
            Group {
                if p.done >= p.total {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(NotebookStyle.successTint)
                } else {
                    Text("\(p.done)/\(p.total)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .help(p.done >= p.total ? "Completo" : "\(p.done) de \(p.total)")
        } else {
            Text(text)
                .font(NotebookGridStyle.cellFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
}
