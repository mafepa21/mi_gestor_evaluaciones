import SwiftUI
import MiGestorKit

/// Cronómetro para varios alumnos a la vez: todos salen juntos y cada uno se
/// para al tocar su tarjeta cuando llega. Al guardar, cada tiempo va a su celda
/// con la nota del baremo.
struct NotebookPhysicalGroupTimerSheet: View {
    let pair: NotebookPhysicalColumnPair
    let groupLabel: String
    let roster: [NotebookPhysicalRosterEntry]
    let previewScore: @MainActor (Student, Double) async -> Double?
    let onSave: @MainActor (Student, String) async -> NotebookPhysicalMarkSaveOutcome
    let onFinished: (String) -> Void

    private enum Phase {
        case ready
        case running
        case finished
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .ready
    @State private var selectedIds: Set<Int64>
    @State private var startUptime: TimeInterval = 0
    @State private var stops: [Int64: TimeInterval] = [:]
    @State private var scores: [Int64: Double] = [:]
    @State private var noScaleIds: Set<Int64> = []
    @State private var lastStoppedId: Int64?
    @State private var isSaving = false
    @State private var isDiscardConfirmationPresented = false
    @State private var isRestartConfirmationPresented = false

    init(
        pair: NotebookPhysicalColumnPair,
        groupLabel: String,
        roster: [NotebookPhysicalRosterEntry],
        previewScore: @escaping @MainActor (Student, Double) async -> Double?,
        onSave: @escaping @MainActor (Student, String) async -> NotebookPhysicalMarkSaveOutcome,
        onFinished: @escaping (String) -> Void
    ) {
        self.pair = pair
        self.groupLabel = groupLabel
        self.roster = roster
        self.previewScore = previewScore
        self.onSave = onSave
        self.onFinished = onFinished
        _selectedIds = State(initialValue: Set(roster.map(\.student.id)))
    }

    private var runners: [NotebookPhysicalRosterEntry] {
        roster.filter { selectedIds.contains($0.student.id) }
    }

    private var stillRunningCount: Int {
        runners.filter { stops[$0.student.id] == nil }.count
    }

    private var stoppedCount: Int {
        runners.filter { stops[$0.student.id] != nil }.count
    }

    private var hasUnsavedTimes: Bool { stoppedCount > 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                controlBar
                instructionBar
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                        ForEach(roster) { entry in
                            tile(for: entry)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, 16)
            .background(Color.platformGroupedBackground)
            .navigationTitle(pair.testName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { requestCancel() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(pair.testName).font(.headline)
                        Text("\(groupLabel) · \(summary)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Guardando…" : "Guardar \(stoppedCount)") {
                        Task { await saveAll() }
                    }
                    .disabled(phase == .running || stoppedCount == 0 || isSaving)
                }
            }
            .confirmationDialog(
                "¿Descartar los tiempos?",
                isPresented: $isDiscardConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Descartar", role: .destructive) { dismiss() }
                Button("Seguir aquí", role: .cancel) {}
            } message: {
                Text("Hay \(stoppedCount) tiempos sin guardar.")
            }
            .confirmationDialog(
                "¿Repetir la salida?",
                isPresented: $isRestartConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Borrar tiempos y repetir", role: .destructive) { restart() }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(phase == .running || hasUnsavedTimes)
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
    }

    private var summary: String {
        switch phase {
        case .ready: return "\(runners.count) de \(roster.count) corren"
        case .running, .finished: return "\(stoppedCount) de \(runners.count) han llegado"
        }
    }

    // MARK: Reloj y botón principal

    private var controlBar: some View {
        HStack(spacing: 24) {
            TimelineView(.animation(minimumInterval: 0.05, paused: phase != .running)) { _ in
                Text(NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: clockSeconds())))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Tiempo de carrera")
            .accessibilityAddTraits(.updatesFrequently)

            switch phase {
            case .ready:
                Button { startAll() } label: {
                    Text("Iniciar los \(runners.count)")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 232, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(runners.isEmpty)
                .keyboardShortcut(.space, modifiers: [])
            case .running:
                Button { stopAll() } label: {
                    Text("Parar los \(stillRunningCount)")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 232, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            case .finished:
                Label("Terminado", systemImage: "flag.checkered")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 232, minHeight: 64)
            }
        }
        .padding(.horizontal, 24)
    }

    private var instructionBar: some View {
        HStack(spacing: 16) {
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if phase == .running, let lastStoppedId, let entry = roster.first(where: { $0.student.id == lastStoppedId }) {
                Button("Deshacer llegada de \(entry.student.firstName)") { undoLastStop() }
                    .buttonStyle(.bordered)
            }
            if phase == .finished {
                Button("Repetir la salida", role: .destructive) { isRestartConfirmationPresented = true }
                    .buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 24)
    }

    private var instruction: String {
        switch phase {
        case .ready: return "Elige quién corre y pulsa Iniciar. Todos salen a la vez."
        case .running: return "Toca la tarjeta de cada alumno cuando cruce la meta."
        case .finished: return "Revisa los tiempos y pulsa Guardar."
        }
    }

    // MARK: Tarjetas

    @ViewBuilder
    private func tile(for entry: NotebookPhysicalRosterEntry) -> some View {
        let id = entry.student.id
        let isRunner = selectedIds.contains(id)
        let stop = stops[id]
        Button {
            tapTile(entry)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.student.fullName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    tileSymbol(isRunner: isRunner, stop: stop)
                }
                tileValue(isRunner: isRunner, stop: stop, id: id)
                Text(tileCaption(entry: entry, isRunner: isRunner, stop: stop))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(stop != nil ? AnyShapeStyle(Color.green.opacity(0.14)) : AnyShapeStyle(Color.platformCardBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tileBorder(isRunner: isRunner, stop: stop), lineWidth: 2)
            )
            .opacity(isRunner ? 1 : (phase == .ready ? 0.6 : 0.4))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(phase != .ready && (!isRunner || stop != nil))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.student.fullName)
        .accessibilityValue(tileAccessibilityValue(isRunner: isRunner, stop: stop, id: id))
        .accessibilityHint(phase == .ready ? "Toca dos veces para cambiar si corre" : (phase == .running && isRunner && stop == nil ? "Toca dos veces para parar su tiempo" : ""))
    }

    @ViewBuilder
    private func tileSymbol(isRunner: Bool, stop: TimeInterval?) -> some View {
        switch phase {
        case .ready:
            Image(systemName: isRunner ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isRunner ? Color.accentColor : Color.secondary)
                .font(.title3)
        case .running, .finished:
            if !isRunner {
                EmptyView()
            } else if stop != nil {
                Image(systemName: "flag.checkered").foregroundStyle(.green).font(.title3)
            } else {
                Image(systemName: "figure.run").foregroundStyle(.red).font(.title3)
            }
        }
    }

    @ViewBuilder
    private func tileValue(isRunner: Bool, stop: TimeInterval?, id: Int64) -> some View {
        if phase == .ready || !isRunner {
            Text(isRunner ? "Preparado" : "No corre")
                .font(.body)
                .foregroundStyle(isRunner ? .primary : .secondary)
        } else if let stop {
            HStack(spacing: 8) {
                Text(NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: stop)))
                    .font(.title3.weight(.medium))
                Rectangle().fill(.separator).frame(width: 1, height: 20)
                if let score = scores[id] {
                    Text(NotebookPhysicalMark.decimalText(score)).font(.title2.weight(.semibold))
                } else if noScaleIds.contains(id) {
                    Text("sin baremo").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .monospacedDigit()
        } else {
            TimelineView(.animation(minimumInterval: 0.1, paused: phase != .running)) { _ in
                Text(NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: clockSeconds())))
                    .font(.title2.weight(.medium))
                    .monospacedDigit()
            }
        }
    }

    private func tileCaption(entry: NotebookPhysicalRosterEntry, isRunner: Bool, stop: TimeInterval?) -> String {
        switch phase {
        case .ready:
            let previous = entry.markText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRunner, !previous.isEmpty, previous != "—" {
                return "Ya tiene \(NotebookPhysicalMark.compactTime(previous)) · se sustituirá"
            }
            return isRunner ? "Toca para quitar" : "Toca para añadir"
        case .running:
            guard isRunner else { return "" }
            return stop == nil ? "Corriendo · toca al llegar" : "Llegó"
        case .finished:
            guard isRunner else { return "" }
            return stop == nil ? "Sin tiempo" : "Llegó"
        }
    }

    private func tileBorder(isRunner: Bool, stop: TimeInterval?) -> Color {
        switch phase {
        case .ready: return isRunner ? .accentColor : .clear
        case .running: return isRunner && stop == nil ? .red : .clear
        case .finished: return .clear
        }
    }

    private func tileAccessibilityValue(isRunner: Bool, stop: TimeInterval?, id: Int64) -> String {
        if phase == .ready { return isRunner ? "Corre" : "No corre" }
        guard isRunner else { return "No corre" }
        guard let stop else { return "Corriendo" }
        let time = NotebookPhysicalMark.spokenTime(NotebookPhysicalMark.timeText(seconds: stop))
        if let score = scores[id] { return "Llegó, \(time), nota \(NotebookPhysicalMark.decimalText(score))" }
        return "Llegó, \(time)"
    }

    // MARK: Acciones

    private func clockSeconds() -> TimeInterval {
        switch phase {
        case .ready: return 0
        case .running: return max(0, ProcessInfo.processInfo.systemUptime - startUptime)
        case .finished: return stops.values.max() ?? 0
        }
    }

    private func tapTile(_ entry: NotebookPhysicalRosterEntry) {
        let id = entry.student.id
        switch phase {
        case .ready:
            if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
            AppleInteractionFeedback.play(.selection)
        case .running:
            guard selectedIds.contains(id), stops[id] == nil else { return }
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
            stops[id] = elapsed
            lastStoppedId = id
            AppleInteractionFeedback.play(.lightImpact)
            AccessibilityNotification.Announcement("\(entry.student.firstName), \(NotebookPhysicalMark.spokenTime(NotebookPhysicalMark.timeText(seconds: elapsed)))").post()
            Task { await resolveScore(for: entry.student, seconds: elapsed) }
            if stillRunningCount == 0 { finish() }
        case .finished:
            return
        }
    }

    private func startAll() {
        guard !runners.isEmpty else { return }
        stops = [:]
        scores = [:]
        noScaleIds = []
        lastStoppedId = nil
        startUptime = ProcessInfo.processInfo.systemUptime
        phase = .running
        AppleInteractionFeedback.play(.lightImpact)
    }

    private func stopAll() {
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
        for entry in runners where stops[entry.student.id] == nil {
            stops[entry.student.id] = elapsed
            Task { await resolveScore(for: entry.student, seconds: elapsed) }
        }
        finish()
    }

    private func finish() {
        phase = .finished
        lastStoppedId = nil
        AppleInteractionFeedback.play(.success)
    }

    private func undoLastStop() {
        guard let lastStoppedId else { return }
        stops[lastStoppedId] = nil
        scores[lastStoppedId] = nil
        noScaleIds.remove(lastStoppedId)
        self.lastStoppedId = nil
    }

    private func restart() {
        stops = [:]
        scores = [:]
        noScaleIds = []
        lastStoppedId = nil
        phase = .ready
    }

    private func resolveScore(for student: Student, seconds: TimeInterval) async {
        let rounded = (seconds * 100).rounded() / 100
        let score = await previewScore(student, rounded)
        guard stops[student.id] != nil else { return }
        if let score {
            scores[student.id] = score
        } else {
            noScaleIds.insert(student.id)
        }
    }

    private func requestCancel() {
        if phase == .running || hasUnsavedTimes {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private func saveAll() async {
        guard phase != .running, !isSaving else { return }
        isSaving = true
        var saved = 0
        var withoutScale = 0
        for entry in runners {
            guard let stop = stops[entry.student.id] else { continue }
            let outcome = await onSave(entry.student, NotebookPhysicalMark.timeText(seconds: stop))
            switch outcome {
            case .scored: saved += 1
            case .noScale: saved += 1; withoutScale += 1
            case .cleared, .invalid: break
            }
        }
        isSaving = false
        AppleInteractionFeedback.play(.success)
        let message = withoutScale > 0
            ? "\(saved) tiempos guardados · \(withoutScale) sin baremo"
            : "\(saved) tiempos guardados con su nota"
        onFinished(message)
        dismiss()
    }
}

private extension Color {
    static var platformGroupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var platformCardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
