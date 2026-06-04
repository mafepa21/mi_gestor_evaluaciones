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

struct NotebookEditableTableCell: View {
    let bridge: KmpBridge
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
    var onGenerateSummary: (() -> Void)? = nil
    let onNavigate: (NotebookNavigationDirection) -> Void
    let onCellSaved: () -> Void
    let onAttendanceSaved: () -> Void

    private var persistedCell: PersistedNotebookCell? {
        item.row.persistedCells.first(where: { $0.columnId == column.id })
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(editableCellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.85) : editableCellBorder,
                            lineWidth: isSelected ? 1.4 : 0.6
                        )
                )

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

    private var editableCellFill: Color {
        if column.isLocked {
            return NotebookStyle.surfaceMuted.opacity(0.45)
        }
        if column.type == .calculated {
            #if os(macOS)
            return Color.accentColor.opacity(isSelected ? 0.08 : 0.02)
            #else
            return Color.accentColor.opacity(isSelected ? 0.10 : 0.04)
            #endif
        }
        if hasColumnColor {
            return tint.opacity(isSelected ? 0.22 : 0.10)
        }
        if hasPendingDraft {
            return NotebookStyle.warningTint.opacity(0.10)
        }
        return isSelected ? tint.opacity(0.14) : NotebookStyle.surfaceSoft.opacity(column.categoryId == nil ? 0.12 : 0.22)
    }

    private var editableCellBorder: Color {
        if column.isLocked {
            return NotebookStyle.softBorder.opacity(0.55)
        }
        if column.type == .calculated {
            return Color.accentColor.opacity(isSelected ? 0.40 : 0.15)
        }
        if saveFeedback == .saving {
            return NotebookStyle.warningTint.opacity(0.70)
        }
        if saveFeedback == .saved {
            return NotebookStyle.successTint.opacity(0.70)
        }
        if hasPendingDraft {
            return NotebookStyle.warningTint.opacity(0.55)
        }
        if hasColumnColor {
            return tint.opacity(0.28)
        }
        return (categoryTint ?? tint).opacity(column.categoryId == nil ? 0.05 : 0.12)
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

        switch saveFeedback {
        case .saving:
            badges.append(NotebookCellStateBadge(id: "saving", systemImage: "arrow.triangle.2.circlepath", label: "Guardando", tint: NotebookStyle.warningTint))
        case .saved:
            badges.append(NotebookCellStateBadge(id: "saved", systemImage: "checkmark.circle.fill", label: "Sincronizado", tint: NotebookStyle.successTint))
        case .idle:
            if hasPendingDraft {
                badges.append(NotebookCellStateBadge(id: "pending", systemImage: "circle.dotted", label: "Pendiente de guardar", tint: NotebookStyle.warningTint))
            }
        }

        if formulaDisplay?.isError == true {
            badges.append(NotebookCellStateBadge(id: "error", systemImage: "exclamationmark.triangle.fill", label: "Error", tint: NotebookStyle.warningTint))
        }

        return badges
    }

    private var hasPendingDraft: Bool {
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
        } else {
            switch column.type {
            case .numeric:
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
                                .foregroundStyle(numericDraft.isEmpty ? .tertiary : .primary)
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
                        .textFieldStyle(RoundedBorderTextFieldStyle())
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
            case .calculated:
                Button {
                    onSelect()
                    onOpenFormula()
                } label: {
                    HStack(spacing: 5) {
                        Text(formulaDisplay?.text ?? bridge.numericGradeOnTenText(studentId: item.student.id, columnId: column.id))
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
                            .textFieldStyle(RoundedBorderTextFieldStyle())
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

    private var isAttendanceColumn: Bool {
        column.type == .attendance || column.categoryKind == .attendance
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
            checkDraft = bridge.cellCheck(studentId: item.student.id, columnId: column.id)
            originalCheckDraft = checkDraft
        case .attendance:
            let textValue = cell?.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayValue = cell?.displayValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = textValue.isEmpty ? displayValue : textValue
            let canonical = NotebookAttendanceStatus.canonical(raw)
            if !raw.isEmpty, canonical.isEmpty {
                let bridgeValue = bridge.cellText(studentId: item.student.id, columnId: column.id)
                textDraft = NotebookAttendanceStatus.canonical(bridgeValue)
            } else {
                textDraft = canonical
            }
            originalTextDraft = textDraft
        case .ordinal, .text, .icon:
            textDraft = cell?.textValue ?? cell?.displayValue ?? ""
            originalTextDraft = textDraft
        case .numeric:
            numericDraft = bridge.numericGradeText(studentId: item.student.id, columnId: column.id).trimmingCharacters(in: .whitespacesAndNewlines)
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
                bridge.flushPendingColumnGradeSave(studentId: item.student.id, columnId: column.id)
                bridge.saveColumnGrade(studentId: item.student.id, column: column, value: numericDraft)
            } else {
                bridge.saveColumnGradeDebounced(studentId: item.student.id, column: column, value: numericDraft)
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
                bridge.flushPendingColumnGradeSave(studentId: item.student.id, columnId: column.id)
                bridge.saveColumnGrade(studentId: item.student.id, column: column, value: textDraft)
            } else {
                bridge.saveColumnGradeDebounced(studentId: item.student.id, column: column, value: textDraft)
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
        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: option)
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
        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: nextValue)
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
        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: canonicalStatus)
        markSaveInProgress()
        onCellSaved()
        onNavigate(navigationDirection)

        guard let classId else { return }
        let attendanceDate = column.dateEpochMs
            .map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000.0) } ?? Date()

        Task {
            try? await bridge.saveAttendance(
                studentId: item.student.id,
                classId: classId,
                on: attendanceDate,
                status: canonicalStatus
            )
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
        let value = bridge.rubricGradeOnTenText(studentId: item.student.id, column: column).trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct NotebookCellStateBadge: Identifiable {
    let id: String
    let systemImage: String
    let label: String
    let tint: Color
}
