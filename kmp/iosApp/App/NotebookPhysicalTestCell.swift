import SwiftUI
import MiGestorKit

/// Celda única de una prueba física: `marca | nota`. Al tocarla se abre el
/// cronómetro (pruebas de tiempo) o el teclado (distancia y repeticiones).
struct NotebookPhysicalTestCell: View {
    let pair: NotebookPhysicalColumnPair
    let student: Student
    let markText: String
    let scoreText: String
    let width: CGFloat
    let tint: Color
    let isSelected: Bool
    let onSelect: () -> Void
    let makeRoster: () -> [NotebookPhysicalRosterEntry]
    let previewScore: @MainActor (Student, Double) async -> Double?
    let onSave: @MainActor (Student, String) async -> NotebookPhysicalMarkSaveOutcome
    let onGroupTimer: (() -> Void)?
    var diagnose: (@MainActor (Student, Double) async -> PhysicalScoreGap?)?
    var setSex: (@MainActor (Student, StudentSex) async -> Bool)?

    @State private var isCapturePresented = false
    @State private var roster: [NotebookPhysicalRosterEntry] = []

    private var mark: String {
        let trimmed = markText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return "" }
        guard pair.kind == .time,
              let seconds = NotebookPhysicalMark.value(from: trimmed, kind: .time) else { return trimmed }
        return NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: seconds))
    }

    private var score: String {
        let trimmed = scoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return "" }
        if let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return NotebookPhysicalMark.decimalText(value)
        }
        return trimmed
    }

    private var emptySymbol: String {
        pair.kind == .time ? "stopwatch" : "keyboard"
    }

    var body: some View {
        Button {
            onSelect()
            roster = makeRoster()
            isCapturePresented = true
        } label: {
            content
                .frame(width: max(0, width - 8))
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(student.fullName), \(pair.testName)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(pair.kind == .time ? "Abre el cronómetro" : "Abre el teclado")
        .popover(isPresented: $isCapturePresented, arrowEdge: .bottom) {
            NotebookPhysicalCapturePanel(
                pair: pair,
                roster: roster,
                startIndex: roster.firstIndex { $0.student.id == student.id } ?? 0,
                tint: tint,
                previewScore: previewScore,
                onSave: onSave,
                onGroupTimer: onGroupTimer,
                diagnose: diagnose,
                setSex: setSex
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if mark.isEmpty {
            Image(systemName: emptySymbol)
                .font(.body)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 8) {
                Text(mark)
                    .notebookFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 18)
                if score.isEmpty {
                    Text("sin nota")
                        .notebookFont(size: 12, weight: .medium)
                        .foregroundStyle(NotebookStyle.warningTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(score)
                        .notebookFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .monospacedDigit()
        }
    }

    private var accessibilityValue: String {
        guard !mark.isEmpty else { return "Sin marca" }
        let spokenMark = pair.kind == .time ? NotebookPhysicalMark.spokenTime(mark) : "\(mark) \(pair.unitLabel)"
        return score.isEmpty ? "\(spokenMark), sin nota" : "\(spokenMark), nota \(score)"
    }
}
