import SwiftUI
import MiGestorKit

/// «Valoración rápida» de un alumno en un trimestre: fichas de Fortaleza, A mejorar y
/// Orientación, y texto libre. Guarda en «Tu valoración» (privada; la usa la IA para redactar).
struct QuickTermNoteSheet: View {
    let bridge: KmpBridge
    let classId: Int64
    let studentId: Int64
    let studentName: String
    let termLabel: String
    let chips: [QuickNoteGroup: [QuickNoteChip]]

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [QuickNoteGroup: [String]] = [:]
    @State private var freeText = ""
    @State private var originalNote = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isDiscardConfirmationPresented = false
    @State private var custom: [QuickNoteGroup: [QuickNotePhrase]] = [:]
    @State private var phraseEditor: PhraseEditor?

    private struct PhraseEditor: Identifiable {
        let id = UUID()
        let group: QuickNoteGroup
        let phrase: QuickNotePhrase?
    }

    private var composed: String { QuickNoteComposer.compose(selected: selected, freeText: freeText) }
    private var hasChanges: Bool { composed != originalNote.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var firstName: String {
        studentName.components(separatedBy: ", ").last ?? studentName
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label {
                            Text(errorMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }
                }
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Cargando valoración…")
                        Spacer()
                    }
                } else {
                    ForEach(QuickNoteGroup.allCases) { group in
                        Section(group.rawValue) {
                            LearningSituationFlowLayout(spacing: 8) {
                                ForEach(chipList(for: group)) { chip in
                                    chipToggle(chip)
                                }
                                Button {
                                    phraseEditor = PhraseEditor(group: group, phrase: nil)
                                } label: {
                                    Label("Nueva ficha", systemImage: "plus")
                                        .font(.subheadline)
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .accessibilityLabel("Nueva ficha de \(group.rawValue)")
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    Section {
                        TextField("Algo más (opcional)", text: $freeText, axis: .vertical)
                            .lineLimit(2...6)
                            .accessibilityLabel("Valoración libre de \(firstName)")
                    } header: {
                        Text("Tu valoración (privada)")
                    } footer: {
                        Text(composed.isEmpty
                             ? "Elige fichas o escribe. Puedes dictar con el micrófono del teclado."
                             : "Se guardará: \(composed)")
                            .lineLimit(6)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Valoración · \(firstName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        if hasChanges { isDiscardConfirmationPresented = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("Guardar")
                            .opacity(isSaving ? 0 : 1)
                            .overlay { if isSaving { ProgressView().controlSize(.small) } }
                    }
                    .disabled(!hasChanges || isSaving || isLoading)
                    .accessibilityLabel(isSaving ? "Guardando" : "Guardar valoración")
                }
            }
            .confirmationDialog("¿Descartar los cambios?", isPresented: $isDiscardConfirmationPresented, titleVisibility: .visible) {
                Button("Descartar cambios", role: .destructive) { dismiss() }
                Button("Seguir editando", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .sheet(item: $phraseEditor) { editor in
            QuickNotePhraseSheet(
                title: editor.phrase == nil ? "Nueva ficha" : "Editar ficha",
                initialGroup: editor.group,
                initialText: editor.phrase?.text ?? ""
            ) { group, text in
                if let saved = try? await bridge.saveQuickNotePhrase(id: editor.phrase?.id, group: group, text: text) {
                    custom = await bridge.quickNotePhrases()
                    var items = selected[group] ?? []
                    if let old = editor.phrase?.text { items.removeAll { $0 == old } }
                    if !items.contains(saved.text) { items.append(saved.text) }
                    selected[group] = items
                }
            }
            #if os(macOS)
            .frame(width: 420, height: 260)
            #else
            .presentationDetents([.medium])
            #endif
        }
        .task { await load() }
    }

    /// Fichas del grupo más las frases propias que ya estaban guardadas.
    private func chipList(for group: QuickNoteGroup) -> [QuickNoteChip] {
        var list = chips[group] ?? []
        // Fichas propias del docente, justo después de las que salen de lo registrado.
        let firstFixed = list.firstIndex { $0.source == nil } ?? list.count
        let own = (custom[group] ?? []).filter { phrase in !list.contains { $0.text == phrase.text } }
            .map { QuickNoteChip(group: group, text: $0.text, source: nil, phraseId: $0.id) }
        list.insert(contentsOf: own, at: firstFixed)
        for text in selected[group] ?? [] where !list.contains(where: { $0.text == text }) {
            list.append(QuickNoteChip(group: group, text: text, source: nil))
        }
        return list
    }

    private func isSelected(_ chip: QuickNoteChip) -> Bool {
        (selected[chip.group] ?? []).contains(chip.text)
    }

    private func chipToggle(_ chip: QuickNoteChip) -> some View {
        Toggle(isOn: Binding(
            get: { isSelected(chip) },
            set: { isOn in
                var items = selected[chip.group] ?? []
                if isOn { if !items.contains(chip.text) { items.append(chip.text) } } else { items.removeAll { $0 == chip.text } }
                selected[chip.group] = items
            }
        )) {
            HStack(spacing: 4) {
                if isSelected(chip) {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
                Text(chip.text)
                if let source = chip.source {
                    Text("· \(source)")
                        .foregroundStyle(isSelected(chip) ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
        }
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        .contextMenu {
            if let phrase = ownPhrase(chip) {
                Button { phraseEditor = PhraseEditor(group: chip.group, phrase: phrase) } label: { Label("Editar", systemImage: "pencil") }
                Button(role: .destructive) { Task { await deletePhrase(phrase) } } label: { Label("Borrar", systemImage: "trash") }
            }
        }
        .accessibilityActions {
            if let phrase = ownPhrase(chip) {
                Button("Editar ficha") { phraseEditor = PhraseEditor(group: chip.group, phrase: phrase) }
                Button("Borrar ficha") { Task { await deletePhrase(phrase) } }
            }
        }
        .accessibilityLabel(chip.source.map { "\(chip.text), de \($0)" } ?? chip.text)
        .accessibilityAddTraits(isSelected(chip) ? .isSelected : [])
    }

    private func ownPhrase(_ chip: QuickNoteChip) -> QuickNotePhrase? {
        guard let id = chip.phraseId else { return nil }
        return custom[chip.group]?.first { $0.id == id }
    }

    @MainActor
    private func deletePhrase(_ phrase: QuickNotePhrase) async {
        try? await bridge.deleteQuickNotePhrase(phrase)
        custom = await bridge.quickNotePhrases()
    }

    @MainActor
    private func load() async {
        guard isLoading else { return }
        custom = await bridge.quickNotePhrases()
        let note = (try? await bridge.teacherTermNote(studentId: studentId, classId: classId, termLabel: termLabel)) ?? ""
        let parts = QuickNoteComposer.decompose(note)
        selected = parts.selected
        freeText = parts.freeText
        originalNote = QuickNoteComposer.compose(selected: parts.selected, freeText: parts.freeText)
        isLoading = false
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await bridge.saveTeacherTermNote(studentId: studentId, classId: classId, termLabel: termLabel, text: composed)
            AccessibilityNotification.Announcement("Valoración guardada").post()
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
            AccessibilityNotification.Announcement(errorMessage ?? "").post()
        }
    }
}
