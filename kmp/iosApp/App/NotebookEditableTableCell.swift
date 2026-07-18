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

private enum NotebookCellSaveFeedback: Equatable {
    case idle
    case saving
    case saved
}

struct NotebookCellDisplaySnapshot: Equatable {
    let numericText: String
    let text: String
    let checkValue: Bool
    let calculatedText: String
    let rubricText: String

    init(
        numericText: String = "",
        text: String = "",
        checkValue: Bool = false,
        calculatedText: String = "",
        rubricText: String = ""
    ) {
        self.numericText = numericText
        self.text = text
        self.checkValue = checkValue
        self.calculatedText = calculatedText
        self.rubricText = rubricText
    }

}

struct NotebookCellActions {
    let flushPendingColumnGradeSave: @MainActor (_ studentId: Int64, _ columnId: String) -> Void
    let saveColumnGrade: @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void
    let saveColumnGradeDebounced: @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void
    let saveAttendance: @MainActor (_ studentId: Int64, _ classId: Int64, _ date: Date, _ status: String) async -> Void

    init(
        flushPendingColumnGradeSave: @escaping @MainActor (_ studentId: Int64, _ columnId: String) -> Void,
        saveColumnGrade: @escaping @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void,
        saveColumnGradeDebounced: @escaping @MainActor (_ studentId: Int64, _ column: NotebookColumnDefinition, _ value: String) -> Void,
        saveAttendance: @escaping @MainActor (_ studentId: Int64, _ classId: Int64, _ date: Date, _ status: String) async -> Void
    ) {
        self.flushPendingColumnGradeSave = flushPendingColumnGradeSave
        self.saveColumnGrade = saveColumnGrade
        self.saveColumnGradeDebounced = saveColumnGradeDebounced
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
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
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
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
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
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
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
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
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

    /// Ajuste transversal (color semántico + heat de nota), con toggle propio en
    /// el menú de acciones del cuaderno. Se lee aquí vía `@AppStorage` con la
    /// misma clave que `NotebookModuleView` en vez de enhebrarla por el init:
    /// patrón estándar de SwiftUI para un ajuste que cruza muchos tipos de celda.
    @AppStorage(NotebookGridStyle.semanticGradeColorDefaultsKey) private var semanticGradeColorEnabled = true

    private var persistedCell: PersistedNotebookCell? {
        item.row.persistedCells.first(where: { $0.columnId == column.id })
    }

    /// Banda de la nota (baja/media/alta) para colorear el número y, en modo
    /// heat, el fondo de la celda. `nil` si el toggle está apagado, la columna
    /// no es una nota 0–10 (p. ej. tiempo/distancia/repeticiones de pruebas
    /// físicas: un "6,5" ahí es un dato bruto, no una nota) o el valor no se
    /// puede interpretar como número.
    private var gradeBand: NotebookGradeBand? {
        guard semanticGradeColorEnabled, column.type == .numeric else { return nil }
        switch column.scaleKind {
        case .time, .distance, .repetitions:
            return nil
        default:
            break
        }
        guard let score = NotebookFormulaDisplay.parseNumber(numericDraft) else { return nil }
        return NotebookGradeBand(scoreOutOfTen: score)
    }

    @State private var numericDraft = ""
    @State private var textDraft = ""
    @State private var checkDraft = false
    @State private var originalNumericDraft = ""
    @State private var originalTextDraft = ""
    @State private var originalCheckDraft = false
    @State private var pendingCheckDraft: Bool?
    @State private var numericDragStartValue: Double?
    @State private var numericDragLastWholeValue: Int?
    @State private var isNumericDragging = false
    @State private var showTextPopover = false
    @State private var isNumericKeyboardPresented = false
    @State private var hasLoadedDrafts = false
    @State private var saveFeedback: NotebookCellSaveFeedback = .idle
    @State private var saveFeedbackTask: Task<Void, Never>?

    private var cellId: String {
        "\(item.student.id)|\(column.id)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                .fill(editableCellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                        .stroke(editableCellBorder, lineWidth: editableCellBorderWidth)
                )
                .shadow(
                    color: isSelected ? NotebookGridStyle.cellSelectionShadow : .clear,
                    radius: isSelected ? 4 : 0,
                    x: 0,
                    y: isSelected ? 1.5 : 0
                )
                .padding(2)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if let persistedCell, hasContextualSignal(in: persistedCell) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            if let icon = persistedCell.annotation?.icon ?? persistedCell.iconValue, !icon.isEmpty {
                                Text(icon)
                            }
                            let attachmentCount = persistedCell.annotation?.attachmentUris.count ?? 0
                            if attachmentCount > 0 {
                                Text("\(attachmentCount)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.14))
                        )
                    }
                    Spacer()
                }
                .padding(6)
            }

            cellStateOverlay
            saveFeedbackDot

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
        .frame(width: width, height: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear(perform: loadDrafts)
        .onDisappear {
            saveFeedbackTask?.cancel()
            saveFocusedDraftIfNeeded(requireFocusReleased: false)
        }
        .appOnChange(of: reloadToken) { _ in
            loadDraftsUnlessEditing()
        }
        .appOnChange(of: focusedCellId.wrappedValue) { newValue in
            if newValue == cellId {
                onSelect()
            } else {
                saveFocusedDraftIfNeeded()
            }
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
        if let gradeBand {
            // Modo heat (parte del mismo toggle que el color del número): tinte de
            // fondo suave por banda, para leer la clase entera como mapa de calor.
            return gradeBand.softFill
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
        let states = cellStateBadges
        if !states.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    ForEach(states, id: \.id) { state in
                        Image(systemName: state.systemImage)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(state.tint)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(NotebookStyle.surface.opacity(0.96))
                            )
                            .help(state.label)
                            .accessibilityLabel(state.label)
                    }
                }
            }
            .padding(5)
        }
    }

    /// Punto discreto de 6pt en la esquina inferior izquierda: única señal del
    /// ciclo de guardado transitorio (ámbar mientras guarda, verde con un rebote
    /// al confirmar). Esquina propia, distinta de la anotación (superior derecha)
    /// y de los badges persistentes (inferior derecha), para no competir con ellos.
    @ViewBuilder
    private var saveFeedbackDot: some View {
        if saveFeedback == .saving || saveFeedback == .saved {
            VStack {
                Spacer()
                HStack {
                    Group {
                        if #available(iOS 18.0, macOS 14.0, *) {
                            Image(systemName: "circle.fill")
                                .symbolEffect(.bounce, value: saveFeedback == .saved)
                        } else {
                            Image(systemName: "circle.fill")
                        }
                    }
                    .font(.system(size: 6))
                    .foregroundStyle(saveFeedback == .saving ? NotebookGridStyle.statePending : NotebookStyle.successTint)
                    .accessibilityHidden(true)

                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private var cellStateBadges: [NotebookCellStateBadge] {
        if column.isLocked {
            return [NotebookCellStateBadge(id: "locked", systemImage: "lock.fill", label: "Celda bloqueada", tint: .secondary)]
        }

        var badges: [NotebookCellStateBadge] = []
        if !column.countsTowardAverage {
            badges.append(NotebookCellStateBadge(id: "excluded", systemImage: "slash.circle", label: "No cuenta para media", tint: .secondary))
        }

        // El feedback transitorio de guardado (saving/saved) se muestra aparte,
        // como un punto discreto (`saveFeedbackDot`), no como badge.
        if saveFeedback == .idle, hasPendingDraft {
            badges.append(NotebookCellStateBadge(id: "pending", systemImage: "circle.dotted", label: "Pendiente de guardar", tint: NotebookStyle.warningTint))
        }

        if formulaDisplay?.isError == true {
            badges.append(NotebookCellStateBadge(id: "error", systemImage: "exclamationmark.triangle.fill", label: "Error", tint: NotebookStyle.warningTint))
        }

        return badges
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
                numericMacField
                #else
                if keyboardKind != .text {
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
                                .foregroundStyle(numericDraft.isEmpty ? AnyShapeStyle(.tertiary) : (gradeBand.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.primary)))
                                .lineLimit(1)
                            Image(systemName: "keyboard")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.plain)
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
                let rubricText = displayRubricText()
                Button {
                    onSelect()
                    onOpenRubricIndividual()
                } label: {
                    Text(rubricText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(rubricText == "—" ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
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
                            .foregroundStyle(textDraft.isEmpty ? .tertiary : .primary)
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
        TextField("", text: $numericDraft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(NotebookGridStyle.cellFont)
            .foregroundStyle(gradeBand.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.primary))
            .focused(focusedCellId, equals: cellId)
            .onSubmit { saveNumericAndNavigate(navigationDirection) }
            .onKeyPress(.upArrow) { saveNumericAndNavigate(.up); return .handled }
            .onKeyPress(.downArrow) { saveNumericAndNavigate(.down); return .handled }
            .onKeyPress(keys: [.tab]) { press in
                saveNumericAndNavigate(press.modifiers.contains(.shift) ? .left : .right)
                return .handled
            }
    }
    #endif

    private var isAttendanceColumn: Bool {
        column.type == .attendance || column.categoryKind == .attendance
    }

    private var isStructuredInstrument: Bool {
        column.inputKind.isStructuredInstrument
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
            HStack(spacing: 6) {
                Text(structuredDisplayText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(structuredDisplayText == "Pendiente" ? .tertiary : .primary)
                    .lineLimit(1)
                Image(systemName: "checklist")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir instrumento")
    }

    private var structuredDisplayText: String {
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
            textDraft = cell?.textValue ?? cell?.displayValue ?? ""
            originalTextDraft = textDraft
        case .numeric:
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
              !showTextPopover else { return }
        loadDrafts()
    }

    private func saveNumeric(selectsCell: Bool = true, immediate: Bool = false) {
        guard !column.isLocked else { return }
        if selectsCell {
            onSelect()
        }
        if originalNumericDraft != numericDraft {
            onPrepareUndo(originalNumericDraft, originalNumericDraft)
            originalNumericDraft = numericDraft
            if immediate {
                actions.flushPendingColumnGradeSave(item.student.id, column.id)
                actions.saveColumnGrade(item.student.id, column, numericDraft)
            } else {
                actions.saveColumnGradeDebounced(item.student.id, column, numericDraft)
            }
            markSaveInProgress()
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
            if immediate {
                actions.flushPendingColumnGradeSave(item.student.id, column.id)
                actions.saveColumnGrade(item.student.id, column, textDraft)
            } else {
                actions.saveColumnGradeDebounced(item.student.id, column, textDraft)
            }
            markSaveInProgress()
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
        markSaveInProgress()
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
        markSaveInProgress()
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
        markSaveInProgress()
        onCellSaved()
        onNavigate(navigationDirection)

        guard let classId else { return }
        let attendanceDate = column.dateEpochMs
            .map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000.0) } ?? Date()

        Task {
            await actions.saveAttendance(item.student.id, classId, attendanceDate, canonicalStatus)
            await MainActor.run {
                onAttendanceSaved()
            }
        }
    }

    private func saveQuickAttendanceValue() {
        let nextStatus = nextQuickAttendanceStatus(after: textDraft)
        saveAttendanceValue(nextStatus)
    }

    private func saveFocusedDraftIfNeeded(requireFocusReleased: Bool = true) {
        guard hasLoadedDrafts,
              activeChoiceCellId != cellId,
              !isNumericKeyboardPresented,
              !showTextPopover
        else { return }
        if requireFocusReleased && focusedCellId.wrappedValue == cellId {
            return
        }

        switch column.type {
        case .numeric:
            saveNumeric(selectsCell: false, immediate: true)
        case .text, .icon:
            saveText(selectsCell: false, immediate: true)
        default:
            break
        }
    }

    private func displayRubricText() -> String {
        let value = displaySnapshot.rubricText
        return value.isEmpty ? "—" : value
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

    private func markSaveInProgress() {
        saveFeedbackTask?.cancel()
        saveFeedback = .saving
        saveFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            saveFeedback = .saved
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            saveFeedback = .idle
        }
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
    let onSelect: () -> Void
    let onOpenFormula: () -> Void

    var body: some View {
        NotebookReadOnlyCellChrome(
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
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected &&
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
    let onSelect: () -> Void
    let onOpenRubricIndividual: () -> Void
    let onOpenRubricBulk: () -> Void

    private var rubricText: String {
        displaySnapshot.rubricText.isEmpty ? "—" : displaySnapshot.rubricText
    }

    var body: some View {
        NotebookReadOnlyCellChrome(
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
                Text(rubricText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(rubricText == "—" ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
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
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected
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
    let onSelect: () -> Void
    let onOpenStructuredInstrument: () -> Void

    private var persistedCell: PersistedNotebookCell? {
        item.row.persistedCells.first(where: { $0.columnId == column.id })
    }

    private var displayText: String {
        let value = (persistedCell?.displayValue ?? persistedCell?.textValue ?? displaySnapshot.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Pendiente" : value
    }

    var body: some View {
        NotebookReadOnlyCellChrome(
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
                HStack(spacing: 6) {
                    Text(displayText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(displayText == "Pendiente" ? .tertiary : .primary)
                        .lineLimit(1)
                    Image(systemName: "checklist")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir instrumento")
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displaySnapshot == rhs.displaySnapshot &&
            lhs.item.student.id == rhs.item.student.id &&
            lhs.column.cellEquatableKey == rhs.column.cellEquatableKey &&
            lhs.width == rhs.width &&
            lhs.isSelected == rhs.isSelected
    }
}

@MainActor
private struct NotebookReadOnlyCellChrome<Content: View>: View {
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
        item.row.persistedCells.first(where: { $0.columnId == column.id })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                .fill(cellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: NotebookGridStyle.Radius.cell, style: .continuous)
                        .stroke(cellBorder, lineWidth: isSelected ? NotebookGridStyle.cellSelectionRingWidth : 0.6)
                )
                .shadow(
                    color: isSelected ? NotebookGridStyle.cellSelectionShadow : .clear,
                    radius: isSelected ? 4 : 0,
                    x: 0,
                    y: isSelected ? 1.5 : 0
                )
                .padding(2)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if let persistedCell, hasContextualSignal(in: persistedCell) {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            if let icon = persistedCell.annotation?.icon ?? persistedCell.iconValue, !icon.isEmpty {
                                Text(icon)
                            }
                            let attachmentCount = persistedCell.annotation?.attachmentUris.count ?? 0
                            if attachmentCount > 0 {
                                Text("\(attachmentCount)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.14))
                        )
                    }
                    Spacer()
                }
                .padding(6)
            }

            cellStateOverlay
        }
        .frame(width: width, height: 44)
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
        let states = cellStateBadges
        if !states.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    ForEach(states, id: \.id) { state in
                        Image(systemName: state.systemImage)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(state.tint)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(NotebookStyle.surface.opacity(0.96))
                            )
                            .help(state.label)
                            .accessibilityLabel(state.label)
                    }
                }
            }
            .padding(5)
        }
    }

    private var cellStateBadges: [NotebookCellStateBadge] {
        if column.isLocked {
            return [NotebookCellStateBadge(id: "locked", systemImage: "lock.fill", label: "Celda bloqueada", tint: .secondary)]
        }

        var badges: [NotebookCellStateBadge] = []
        if !column.countsTowardAverage {
            badges.append(NotebookCellStateBadge(id: "excluded", systemImage: "slash.circle", label: "No cuenta para media", tint: .secondary))
        }
        if formulaDisplay?.isError == true {
            badges.append(NotebookCellStateBadge(id: "error", systemImage: "exclamationmark.triangle.fill", label: "Error", tint: NotebookStyle.warningTint))
        }
        return badges
    }

    private func hasContextualSignal(in cell: PersistedNotebookCell) -> Bool {
        !(cell.annotation?.note?.isEmpty ?? true) ||
            !((cell.annotation?.icon ?? cell.iconValue ?? "").isEmpty) ||
            !(cell.annotation?.attachmentUris.isEmpty ?? true)
    }
}

private struct NotebookCellColumnEquatableKey: Equatable {
    let id: String
    let type: String
    let inputKind: String
    let categoryKind: String
    let categoryId: String
    let colorHex: String
    let isLocked: Bool
    let countsTowardAverage: Bool
    let unitOrSituation: String
    let ordinalLevels: [String]
    let dateEpochMs: String
}

private extension NotebookColumnDefinition {
    var cellEquatableKey: NotebookCellColumnEquatableKey {
        NotebookCellColumnEquatableKey(
            id: id,
            type: String(describing: type),
            inputKind: String(describing: inputKind),
            categoryKind: String(describing: categoryKind),
            categoryId: String(describing: categoryId),
            colorHex: colorHex ?? "",
            isLocked: isLocked,
            countsTowardAverage: countsTowardAverage,
            unitOrSituation: unitOrSituation ?? "",
            ordinalLevels: ordinalLevels,
            dateEpochMs: String(describing: dateEpochMs)
        )
    }
}

private struct NotebookCellStateBadge: Identifiable {
    let id: String
    let systemImage: String
    let label: String
    let tint: Color
}
