import SwiftUI
import MiGestorKit

/// Hoja «Lo que hice»: el docente cuenta qué cambió de la sesión, la IA ajusta el guion
/// bloque a bloque y el resultado se guarda en el diario. El plan no cambia.
struct PlannerSessionActualEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.kmpBridgeReference) private var bridgeReference

    let session: PlanningSession
    let input: PlannerActualEditInput
    var onSaved: () -> Void = {}

    @State private var note = ""
    @State private var edit: PlannerActualEdit
    @State private var phase: Phase = .writing
    @State private var expandedIds: Set<String> = []
    @State private var work: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isAIAvailable = true
    @State private var saveError: String?
    @State private var isReplaceConfirmationPresented = false
    @State private var isDiscardConfirmationPresented = false
    @FocusState private var isNoteFocused: Bool

    enum Phase: Equatable {
        case writing
        case working(done: Int)
        case review
        /// Sin Apple Intelligence o por «Editar a mano»: bloques editables.
        case manual
    }

    init(session: PlanningSession, input: PlannerActualEditInput, onSaved: @escaping () -> Void = {}) {
        self.session = session
        self.input = input
        self.onSaved = onSaved
        _edit = State(initialValue: PlannerActualEdit(input: input, status: .unchanged))
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isWorking: Bool { if case .working = phase { return true } else { return false } }
    private var isDirty: Bool { !trimmedNote.isEmpty || edit.hasChanges }
    private var canSave: Bool { (phase == .review || phase == .manual) && !isSaving }
    private var failedTitles: [String] { edit.blocks.filter { $0.status == .failed }.map(\.title) }

    var body: some View {
        NavigationStack {
            Group {
                if input.blocks.isEmpty {
                    ContentUnavailableView(
                        "Esta sesión no tiene guion",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Importa o escribe el guion de la sesión para poder registrar lo que hiciste.")
                    )
                } else {
                    ScrollView {
                        content
                            .frame(maxWidth: 820, alignment: .leading)
                            .padding(24)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Lo que hice")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isDirty ? "Cancelar" : "Cerrar") {
                        if isDirty { isDiscardConfirmationPresented = true } else { close() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase != .writing {
                        Button("Guardar") { Task { await save(replacing: false) } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 860, minHeight: 600, idealHeight: 900)
        #endif
        .interactiveDismissDisabled(isDirty)
        .onAppear {
            isAIAvailable = AppleFoundationActualEditService().isAvailable
            if !isAIAvailable { phase = .manual }
        }
        .onDisappear { work?.cancel() }
        .confirmationDialog("¿Reemplazar lo que escribiste?", isPresented: $isReplaceConfirmationPresented, titleVisibility: .visible) {
            Button("Reemplazar", role: .destructive) { Task { await save(replacing: true) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se perderá el texto que ya tienes en «Qué se ha hecho realmente» y en «Adaptaciones».")
        }
        .confirmationDialog("¿Descartar los cambios?", isPresented: $isDiscardConfirmationPresented, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { close() }
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("No se guardará nada en el diario.")
        }
    }

    // MARK: Contenido

    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
            switch phase {
            case .writing:
                writingSection
            case .working(let done):
                progressLine(done: done)
                blockList
            case .review, .manual:
                statusSection
                if phase == .review, edit.hasChanges { changesSummary }
                blockList
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(input.title)
                .font(.title3.weight(.semibold))
            if !input.meta.isEmpty {
                Text(input.meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var writingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $note)
                    .focused($isNoteFocused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 168)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Qué cambiaste")
                if note.isEmpty {
                    Text("Ej.: Cambié el calentamiento por pilla-pilla con balón. Quité el último juego. El partido final duró 10 minutos más.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            Label("El plan no cambia. Se guarda aparte, en el diario. Puedes dictar con el micrófono del teclado.", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Button { startAdjusting() } label: {
                    Text("Ajustar el guion").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(trimmedNote.isEmpty)
                Button("Editar a mano") { phase = .manual }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
        }
        .onAppear { isNoteFocused = true }
    }

    private func progressLine(done: Int) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Ajustando \(min(done + 1, input.blocks.count)) de \(input.blocks.count)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if phase == .manual {
                if isAIAvailable {
                    Label("Edita el guion a mano.", systemImage: "pencil")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    AppleAIStatusBadge(state: .unavailable, message: "La IA de Apple no está disponible en este dispositivo. Edita el guion a mano.")
                }
            } else {
                AppleAIStatusBadge(state: .available, message: "Ajustado con Apple Intelligence. Revísalo antes de guardar.")
            }
            if !failedTitles.isEmpty {
                Label("No se pudo ajustar \(failedTitles.map { "«\($0)»" }.joined(separator: ", ")). Se queda como en el plan.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var changesSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(edit.changeCount == 1 ? "1 cambio" : "\(edit.changeCount) cambios")
                    .font(.headline)
                Text("van a «Adaptaciones»")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(edit.blocks.filter(\.isChange)) { block in
                Text("• \(block.title): \(PlannerActualEdit.noteText(for: block)).")
                    .font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(edit.blocks) { block in
                blockCard(block)
            }
        }
    }

    // MARK: Bloque

    private func blockCard(_ block: PlannerActualEdit.Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(block.title).font(.headline)
                    Spacer(minLength: 8)
                    minutesLabel(block)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title).font(.headline)
                    minutesLabel(block)
                }
            }
            blockBody(block)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            if let tint = accent(for: block.status) {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous)
                    .fill(tint)
                    .frame(width: 4)
            }
        }
    }

    /// Cada pieza ocupa siempre el mismo hueco: el editor no pierde el foco cuando el bloque
    /// pasa de «Sin cambios» a «Cambiado» al escribir.
    @ViewBuilder
    private func blockBody(_ block: PlannerActualEdit.Block) -> some View {
        if block.status == .pending {
            Text(block.plannedDetail.isEmpty ? "Revisando…" : block.plannedDetail)
                .font(.callout)
                .lineLimit(2)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Revisando")
        }
        if showsPlanned(block) {
            plannedText(block)
        }
        if showsEditor(block) {
            detailEditor(block)
        }
        if let spec = actionSpec(for: block) {
            actionRow(block, status: spec.status, action: spec.action)
        }
    }

    private func showsPlanned(_ block: PlannerActualEdit.Block) -> Bool {
        switch block.status {
        case .skipped:
            return true
        case .changed:
            return !block.plannedDetail.isEmpty
                && PlannerActualEditNormalizer.normalized(block.detail) != PlannerActualEditNormalizer.normalized(block.plannedDetail)
        default:
            return false
        }
    }

    private func showsEditor(_ block: PlannerActualEdit.Block) -> Bool {
        switch block.status {
        case .pending, .skipped: return false
        case .changed, .added, .failed: return true
        case .unchanged: return phase == .manual || expandedIds.contains(block.id)
        }
    }

    private func actionSpec(for block: PlannerActualEdit.Block) -> (status: (String, String), action: (String, () -> Void))? {
        switch block.status {
        case .pending:
            return nil
        case .skipped:
            return (("No se hizo", "nosign"), ("Dejar como estaba", { edit.revert(block.id) }))
        case .changed:
            return (("Cambiado", "pencil"), ("Dejar como estaba", { edit.revert(block.id) }))
        case .added:
            return (("Añadido", "plus"), ("Quitar", { edit.revert(block.id) }))
        case .failed:
            return (("Como en el plan", "exclamationmark.triangle"), ("Reintentar", { retry(block.id) }))
        case .unchanged:
            if showsEditor(block) { return nil }
            return (("Sin cambios", "equal"), ("Editar", { expandedIds.insert(block.id) }))
        }
    }

    private func plannedText(_ block: PlannerActualEdit.Block) -> some View {
        Text(block.plannedDetail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .strikethrough(true, color: .secondary)
            .accessibilityLabel("Antes: \(block.plannedDetail)")
    }

    private func detailEditor(_ block: PlannerActualEdit.Block) -> some View {
        TextEditor(text: Binding(
            get: { edit.blocks.first { $0.id == block.id }?.detail ?? "" },
            set: {
                expandedIds.insert(block.id)
                edit.edit(block.id, detail: $0)
            }
        ))
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(4)
        .frame(minHeight: 72)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("\(block.title), ahora")
    }

    private func actionRow(_ block: PlannerActualEdit.Block, status: (String, String), action: (String, () -> Void)) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                statusLabel(status, block: block)
                Spacer(minLength: 8)
                actionButton(action)
            }
            VStack(alignment: .leading, spacing: 8) {
                statusLabel(status, block: block)
                actionButton(action)
            }
        }
    }

    private func statusLabel(_ status: (String, String), block: PlannerActualEdit.Block) -> some View {
        Label(status.0, systemImage: status.1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent(for: block.status) ?? .secondary)
    }

    private func actionButton(_ action: (String, () -> Void)) -> some View {
        Button(action.0, action: action.1)
            .frame(minHeight: 44)
            .disabled(isWorking)
    }

    @ViewBuilder
    private func minutesLabel(_ block: PlannerActualEdit.Block) -> some View {
        if block.status == .skipped {
            Text("0 min").font(.subheadline).foregroundStyle(.secondary)
        } else if let planned = block.plannedMinutes, let minutes = block.minutes, planned != minutes {
            Text("\(planned) → \(minutes) min").font(.subheadline).foregroundStyle(.secondary)
        } else if let minutes = block.minutes {
            Text("\(minutes) min").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func accent(for status: PlannerActualEdit.Status) -> Color? {
        switch status {
        case .changed, .skipped: return .accentColor
        case .added: return .green
        case .failed: return .orange
        case .pending, .unchanged: return nil
        }
    }

    // MARK: Acciones

    private func startAdjusting() {
        guard !trimmedNote.isEmpty else { return }
        isNoteFocused = false
        let note = trimmedNote
        edit = PlannerActualEdit(input: input)
        phase = .working(done: 0)
        work = Task { @MainActor in
            let service = AppleFoundationActualEditService()
            // En serie: el modelo del dispositivo atiende una petición cada vez.
            for (index, block) in input.blocks.enumerated() {
                if Task.isCancelled { return }
                if let result = await service.adjust(block, note: note, in: input) {
                    edit.apply(result, to: block.id)
                } else {
                    edit.markFailed(block.id)
                }
                phase = .working(done: index + 1)
            }
            if Task.isCancelled { return }
            edit.insert(await service.addedActivities(note: note, in: input))
            phase = .review
            AccessibilityNotification.Announcement(
                edit.hasChanges ? "Guion ajustado. \(edit.changeCount) cambios." : "Guion revisado. Sin cambios."
            ).post()
        }
    }

    private func retry(_ id: String) {
        guard let block = input.blocks.first(where: { $0.id == id }) else { return }
        let note = trimmedNote
        work = Task { @MainActor in
            let service = AppleFoundationActualEditService()
            if let result = await service.adjust(block, note: note, in: input) {
                edit.apply(result, to: id)
            }
        }
    }

    private func save(replacing: Bool) async {
        guard let bridge = bridgeReference else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let aggregate = try await bridge.plannerJournal(for: session)
            let current = aggregate.journal.actualText.trimmingCharacters(in: .whitespacesAndNewlines)
            let actual = edit.actualJournalText
            if !replacing, !current.isEmpty, current != actual.trimmingCharacters(in: .whitespacesAndNewlines) {
                isReplaceConfirmationPresented = true
                return
            }
            let journal = aggregate.journal.withActual(
                plannedText: edit.plannedJournalText,
                actualText: actual,
                adaptationsText: edit.adaptationsJournalText
            )
            _ = try await bridge.plannerSaveJournal(SessionJournalAggregate(
                journal: journal,
                individualNotes: aggregate.individualNotes,
                actions: aggregate.actions,
                media: aggregate.media,
                links: aggregate.links
            ))
            onSaved()
            close()
        } catch {
            saveError = "No se pudo guardar en el diario. Inténtalo de nuevo."
        }
    }

    private func close() {
        work?.cancel()
        dismiss()
    }
}
