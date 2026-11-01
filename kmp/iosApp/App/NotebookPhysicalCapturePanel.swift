import SwiftUI
import MiGestorKit

struct NotebookPhysicalRosterEntry: Identifiable {
    let student: Student
    let markText: String

    var id: Int64 { student.id }
}

/// Ventana que se abre al tocar una celda de prueba física: cronómetro para las
/// pruebas de tiempo y teclado para distancia o repeticiones. Guarda la marca y
/// la nota de cada alumno y pasa al siguiente sin cerrarse.
struct NotebookPhysicalCapturePanel: View {
    let pair: NotebookPhysicalColumnPair
    let roster: [NotebookPhysicalRosterEntry]
    let tint: Color
    let previewScore: @MainActor (Student, Double) async -> Double?
    let onSave: @MainActor (Student, String) async -> NotebookPhysicalMarkSaveOutcome
    let onGroupTimer: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var draft = ""
    @State private var stopwatchStart: TimeInterval?
    @State private var accumulated: TimeInterval = 0
    @State private var undoAccumulated: TimeInterval?
    @State private var undoTask: Task<Void, Never>?
    @State private var isTypingTime = false
    @State private var preview: Double?
    @State private var isSaving = false
    @State private var savedMessage: String?
    /// Marcas guardadas con la ventana abierta: el listado recibido no se refresca.
    @State private var savedMarks: [Int64: String] = [:]
    @FocusState private var isPanelFocused: Bool

    init(
        pair: NotebookPhysicalColumnPair,
        roster: [NotebookPhysicalRosterEntry],
        startIndex: Int,
        tint: Color,
        previewScore: @escaping @MainActor (Student, Double) async -> Double?,
        onSave: @escaping @MainActor (Student, String) async -> NotebookPhysicalMarkSaveOutcome,
        onGroupTimer: (() -> Void)? = nil
    ) {
        self.pair = pair
        self.roster = roster
        self.tint = tint
        self.previewScore = previewScore
        self.onSave = onSave
        self.onGroupTimer = onGroupTimer
        _index = State(initialValue: min(max(0, startIndex), max(0, roster.count - 1)))
    }

    private var entry: NotebookPhysicalRosterEntry? {
        roster.indices.contains(index) ? roster[index] : nil
    }

    private var isRunning: Bool { stopwatchStart != nil }

    private var currentValue: Double? {
        if pair.kind == .time && !isTypingTime {
            return accumulated > 0 ? accumulated : nil
        }
        return NotebookPhysicalMark.value(from: draft, kind: pair.kind)
    }

    private var canSave: Bool { !isRunning && !isSaving && currentValue != nil }

    var body: some View {
        VStack(spacing: 24) {
            header
            valueDisplay
            if pair.kind == .time && !isTypingTime {
                stopwatchControls
            } else {
                keypad
            }
            footer
        }
        .padding(24)
        .frame(width: 360)
        .focusable()
        .focusEffectDisabled()
        .focused($isPanelFocused)
        .onKeyPress(phases: .down, action: handleKey)
        .onAppear {
            loadEntry()
            isPanelFocused = true
        }
        .onChange(of: index) { _, _ in loadEntry() }
        .onDisappear {
            undoTask?.cancel()
        }
        .task(id: previewKey) { await refreshPreview() }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 8) {
            navigationButton(systemImage: "chevron.left", label: "Alumno anterior", delta: -1)
            VStack(spacing: 4) {
                Text(entry.map { $0.student.fullName } ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(pair.testName) · \(index + 1) de \(roster.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            navigationButton(systemImage: "chevron.right", label: "Alumno siguiente", delta: 1)
        }
    }

    private func navigationButton(systemImage: String, label: String, delta: Int) -> some View {
        Button {
            move(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .disabled(isRunning || roster.count < 2)
        .accessibilityLabel(label)
    }

    // MARK: Marca y nota

    private var valueDisplay: some View {
        VStack(spacing: 8) {
            if pair.kind == .time && !isTypingTime {
                TimelineView(.animation(minimumInterval: 0.05, paused: !isRunning)) { _ in
                    Text(NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: liveElapsed())))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .accessibilityLabel("Tiempo")
                .accessibilityValue(NotebookPhysicalMark.spokenTime(NotebookPhysicalMark.timeText(seconds: accumulated)))
                .accessibilityAddTraits(.updatesFrequently)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(draft.isEmpty ? "0" : draft)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(draft.isEmpty ? .secondary : .primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(pair.unitLabel)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Marca")
                .accessibilityValue(draft.isEmpty ? "vacía" : "\(draft) \(pair.unitLabel)")
            }
            scoreChip
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var scoreChip: some View {
        let label: String = {
            if isRunning { return "Corriendo…" }
            guard currentValue != nil else { return pair.kind == .time ? "Pulsa Iniciar cuando salga" : "Escribe la marca" }
            return preview.map { "Nota \(NotebookPhysicalMark.decimalText($0))" } ?? "Sin baremo para este alumno"
        }()
        HStack(spacing: 8) {
            if !isRunning, currentValue != nil {
                Image(systemName: preview == nil ? "exclamationmark.triangle" : "chart.bar.fill")
            }
            Text(label)
        }
        .font(.headline)
        .foregroundStyle(preview == nil || currentValue == nil || isRunning ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 16)
        .frame(minHeight: 32)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Cronómetro

    private var stopwatchControls: some View {
        Button(action: toggleStopwatch) {
            Text(isRunning ? "Parar" : (accumulated > 0 ? "Seguir" : "Iniciar"))
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRunning ? .red : .green)
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityHint(isRunning ? "Para el cronómetro" : "Pone en marcha el cronómetro")
    }

    // MARK: Teclado

    private var keypadKeys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", pair.kind == .repetitions ? "" : ",", "0", "delete.left"]
    }

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(keypadKeys.enumerated()), id: \.offset) { _, key in
                if key.isEmpty {
                    Color.clear.frame(height: 56)
                } else {
                    Button {
                        press(key)
                    } label: {
                        Group {
                            if key == "delete.left" {
                                Image(systemName: key)
                            } else {
                                Text(key)
                            }
                        }
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "delete.left" ? "Borrar" : (key == "," ? "Coma decimal" : key))
                }
            }
        }
    }

    // MARK: Pie

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                Task { await save(advance: true) }
            } label: {
                Text("Guardar y siguiente")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)

            HStack {
                if pair.kind == .time {
                    Button(isTypingTime ? "Usar cronómetro" : "Escribir el tiempo") {
                        switchTimeInput()
                    }
                    .disabled(isRunning)
                }
                if let onGroupTimer, pair.kind == .time {
                    Button("Cronometrar al grupo") {
                        dismiss()
                        onGroupTimer()
                    }
                    .disabled(isRunning)
                }
                Spacer(minLength: 8)
                if pair.kind == .time && !isTypingTime {
                    Button(undoAccumulated == nil ? "Reiniciar" : "Deshacer", role: undoAccumulated == nil ? .destructive : nil) {
                        resetOrUndo()
                    }
                    .disabled(isRunning || (accumulated == 0 && undoAccumulated == nil))
                }
            }
            .font(.subheadline)
            .frame(minHeight: 44)

            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Lógica

    private var previewKey: String {
        "\(entry?.student.id ?? 0)|\(currentValue.map { String($0) } ?? "")|\(isRunning)"
    }

    private func refreshPreview() async {
        guard !isRunning, let student = entry?.student, let value = currentValue else {
            preview = nil
            return
        }
        let resolved = await previewScore(student, value)
        guard !Task.isCancelled else { return }
        preview = resolved
    }

    private func liveElapsed() -> TimeInterval {
        guard let stopwatchStart else { return accumulated }
        return accumulated + max(0, ProcessInfo.processInfo.systemUptime - stopwatchStart)
    }

    private func loadEntry() {
        stopwatchStart = nil
        undoAccumulated = nil
        let existing = (entry.flatMap { savedMarks[$0.student.id] } ?? entry?.markText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = NotebookPhysicalMark.value(from: existing, kind: pair.kind)
        switch pair.kind {
        case .time:
            accumulated = value ?? 0
            draft = value.map { NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: $0)) } ?? ""
        case .distance, .repetitions:
            accumulated = 0
            draft = value.map(NotebookPhysicalMark.decimalText) ?? ""
        }
    }

    private func move(by delta: Int) {
        guard !roster.isEmpty, !isRunning else { return }
        index = (index + delta + roster.count) % roster.count
        AppleInteractionFeedback.play(.selection)
    }

    private func toggleStopwatch() {
        if let stopwatchStart {
            accumulated += max(0, ProcessInfo.processInfo.systemUptime - stopwatchStart)
            self.stopwatchStart = nil
            AppleInteractionFeedback.play(.lightImpact)
            AccessibilityNotification.Announcement(
                NotebookPhysicalMark.spokenTime(NotebookPhysicalMark.timeText(seconds: accumulated))
            ).post()
        } else {
            undoAccumulated = nil
            stopwatchStart = ProcessInfo.processInfo.systemUptime
            AppleInteractionFeedback.play(.lightImpact)
        }
    }

    private func resetOrUndo() {
        undoTask?.cancel()
        if let previous = undoAccumulated {
            accumulated = previous
            undoAccumulated = nil
            return
        }
        undoAccumulated = accumulated
        accumulated = 0
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            undoAccumulated = nil
        }
    }

    private func switchTimeInput() {
        if isTypingTime {
            accumulated = NotebookPhysicalMark.value(from: draft, kind: .time) ?? accumulated
        } else {
            draft = accumulated > 0 ? NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: accumulated)) : ""
        }
        isTypingTime.toggle()
    }

    private func press(_ key: String) {
        switch key {
        case "delete.left":
            if !draft.isEmpty { draft.removeLast() }
        case ",":
            guard pair.kind != .repetitions, !draft.contains(",") else { return }
            draft = draft.isEmpty ? "0," : draft + ","
        default:
            guard draft.count < 8 else { return }
            draft += key
        }
        savedMessage = nil
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            dismiss()
            return .handled
        }
        guard pair.kind != .time || isTypingTime else { return .ignored }
        let character = press.characters
        if press.key == .delete {
            self.press("delete.left")
            return .handled
        }
        if character == "," || character == "." {
            self.press(",")
            return .handled
        }
        if character == ":" && pair.kind == .time {
            if !draft.contains(":") { draft += ":" }
            return .handled
        }
        if character.count == 1, character.first?.isNumber == true {
            self.press(character)
            return .handled
        }
        return .ignored
    }

    private func save(advance: Bool) async {
        guard canSave, let student = entry?.student else { return }
        let text: String
        if pair.kind == .time && !isTypingTime {
            text = NotebookPhysicalMark.timeText(seconds: accumulated)
        } else {
            text = draft
        }
        isSaving = true
        let outcome = await onSave(student, text)
        isSaving = false
        let name = student.fullName
        switch outcome {
        case .scored(let score):
            savedMarks[student.id] = text
            savedMessage = "\(name): nota \(NotebookPhysicalMark.decimalText(score))"
            AppleInteractionFeedback.play(.success)
        case .noScale:
            savedMarks[student.id] = text
            savedMessage = "\(name): marca guardada, sin baremo"
            AppleInteractionFeedback.play(.warning)
        case .cleared:
            savedMarks[student.id] = ""
            savedMessage = "\(name): marca borrada"
            AppleInteractionFeedback.play(.success)
        case .invalid:
            savedMessage = nil
            AppleInteractionFeedback.play(.error)
            AccessibilityNotification.Announcement("La marca no es válida").post()
            return
        }
        if let savedMessage {
            AccessibilityNotification.Announcement(savedMessage).post()
        }
        if advance, roster.count > 1, index < roster.count - 1 {
            index += 1
        } else if advance {
            dismiss()
        }
    }
}
