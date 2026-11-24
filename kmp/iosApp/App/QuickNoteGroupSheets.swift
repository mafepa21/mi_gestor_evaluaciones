import SwiftUI
import MiGestorKit

// Valorar más rápido: por ficha para varios alumnos, copiar del trimestre anterior y
// fichas propias. Todo escribe en «Tu valoración» (privada; la usa la IA para redactar).

// MARK: - Valorar por ficha

struct QuickNoteGroupSheet: View {
    let bridge: KmpBridge
    let classId: Int64
    let termLabel: String
    let students: [(id: Int64, name: String)]
    /// Datos de cada alumno (sellos del trimestre), para «Marcar los que tienen el sello».
    let inputsByStudent: [Int64: BulletinBaseStudentInput]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var group: QuickNoteGroup = .strength
    @State private var chipText: String?
    @State private var custom: [QuickNoteGroup: [QuickNotePhrase]] = [:]
    @State private var notes: [Int64: String] = [:]
    @State private var marked: Set<Int64> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isNewPhrasePresented = false

    private var chips: [QuickNoteChip] {
        let customTexts = custom.mapValues { $0.map { (id: $0.id, text: $0.text) } }
        return QuickNoteCatalog.chips(for: nil, custom: customTexts)[group] ?? []
    }

    /// Alumnos que ya tienen la ficha elegida en su valoración.
    private var alreadyMarked: Set<Int64> {
        guard let chipText else { return [] }
        return Set(students.map(\.id).filter { id in
            (QuickNoteComposer.decompose(notes[id] ?? "").selected[group] ?? []).contains(chipText)
        })
    }

    private var hasChanges: Bool { chipText != nil && marked != alreadyMarked }

    /// Los que tienen un sello con ese mismo nombre salen primero.
    private func stampCount(_ studentId: Int64) -> Int {
        guard let chipText else { return 0 }
        return inputsByStudent[studentId]?.stamps.first { $0.title == chipText }?.count ?? 0
    }

    private var orderedStudents: [(id: Int64, name: String)] {
        students.sorted { lhs, rhs in
            let l = stampCount(lhs.id), r = stampCount(rhs.id)
            return l == r ? lhs.name < rhs.name : l > r
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.primary) }
                }
                Section {
                    groupPicker
                    LearningSituationFlowLayout(spacing: 8) {
                        ForEach(chips) { chip in
                            Toggle(isOn: Binding(
                                get: { chipText == chip.text },
                                set: { isOn in selectChip(isOn ? chip.text : nil) }
                            )) {
                                HStack(spacing: 4) {
                                    if chipText == chip.text { Image(systemName: "checkmark").accessibilityHidden(true) }
                                    Text(chip.text)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 4)
                                .frame(minHeight: 44)
                            }
                            .toggleStyle(.button)
                            .buttonBorderShape(.capsule)
                            .accessibilityAddTraits(chipText == chip.text ? .isSelected : [])
                        }
                        Button {
                            isNewPhrasePresented = true
                        } label: {
                            Label("Nueva ficha", systemImage: "plus")
                                .font(.subheadline)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Elige una ficha")
                }

                if let chipText {
                    Section {
                        ForEach(orderedStudents, id: \.id) { student in
                            Toggle(isOn: Binding(
                                get: { marked.contains(student.id) },
                                set: { isOn in if isOn { marked.insert(student.id) } else { marked.remove(student.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.name)
                                    if stampCount(student.id) > 0 {
                                        Text("Sello «\(chipText)» ×\(stampCount(student.id))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    } header: {
                        Text("«\(chipText)» · \(marked.count) de \(students.count) alumnos")
                    } footer: {
                        Text("Se añade a «Tu valoración» de cada uno sin borrar lo que ya tenían. Desmarcar la quita.")
                    }
                    Section {
                        Button("Marcar a todos") { marked = Set(students.map(\.id)) }
                        Button("Marcar los que tienen el sello") {
                            marked.formUnion(students.map(\.id).filter { stampCount($0) > 0 })
                        }
                        .disabled(!students.contains { stampCount($0.id) > 0 })
                        Button("Quitar todos", role: .destructive) { marked = [] }
                    }
                } else if !isLoading {
                    Section {
                        Text("Elige una ficha y marca a los alumnos que la merecen.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Valorar por ficha")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("Guardar")
                            .opacity(isSaving ? 0 : 1)
                            .overlay { if isSaving { ProgressView().controlSize(.small) } }
                    }
                    .disabled(!hasChanges || isSaving)
                    .accessibilityLabel(isSaving ? "Guardando" : "Guardar la ficha en los alumnos marcados")
                }
            }
            .sheet(isPresented: $isNewPhrasePresented) {
                QuickNotePhraseSheet(initialGroup: group) { newGroup, text in
                    if let phrase = try? await bridge.saveQuickNotePhrase(group: newGroup, text: text) {
                        custom[newGroup, default: []].append(phrase)
                        group = newGroup
                        selectChip(phrase.text)
                    }
                }
                #if os(macOS)
                .frame(width: 420, height: 260)
                #else
                .presentationDetents([.medium])
                #endif
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task { await load() }
    }

    @ViewBuilder
    private var groupPicker: some View {
        let picker = Picker("Grupo", selection: $group) {
            ForEach(QuickNoteGroup.allCases) { Text($0.rawValue).tag($0) }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private func selectChip(_ text: String?) {
        chipText = text
        marked = alreadyMarked
    }

    @MainActor
    private func load() async {
        custom = await bridge.quickNotePhrases()
        notes = (try? await bridge.teacherTermNotes(classId: classId, termLabel: termLabel)) ?? [:]
        isLoading = false
    }

    @MainActor
    private func save() async {
        guard let chipText else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let changed = try await bridge.applyQuickNoteChip(
                classId: classId,
                termLabel: termLabel,
                group: group,
                text: chipText,
                selectedStudentIds: marked,
                allStudentIds: students.map(\.id)
            )
            notes = (try? await bridge.teacherTermNotes(classId: classId, termLabel: termLabel)) ?? notes
            errorMessage = nil
            AccessibilityNotification.Announcement("«\(chipText)» guardada en \(changed) alumnos").post()
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Ficha propia

struct QuickNotePhraseSheet: View {
    var title = "Nueva ficha"
    let initialGroup: QuickNoteGroup
    var initialText = ""
    let onSave: (QuickNoteGroup, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var group: QuickNoteGroup = .strength
    @State private var text = ""

    private var clean: String { QuickNoteCatalog.sanitize(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Texto", text: $text)
                    Picker("Grupo", selection: $group) {
                        ForEach(QuickNoteGroup.allCases) { Text($0.rawValue).tag($0) }
                    }
                } footer: {
                    Text("Sale en todos tus grupos, en el iPad y en el Mac. Sin comas ni puntos: se quitan solos.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(initialText.isEmpty ? "Añadir" : "Guardar") {
                        Task {
                            await onSave(group, clean)
                            dismiss()
                        }
                    }
                    .disabled(clean.isEmpty)
                }
            }
        }
        .onAppear {
            group = initialGroup
            text = initialText
        }
    }
}

// MARK: - Copiar del trimestre anterior

struct CopyPreviousTermSheet: View {
    let bridge: KmpBridge
    let classId: Int64
    let fromTerm: EvaluationClosingTerm
    let toTerm: EvaluationClosingTerm
    let studentIds: [Int64]

    @Environment(\.dismiss) private var dismiss
    @State private var replaceExisting = false
    @State private var sourceCount = 0
    @State private var targetFilled: Set<Int64> = []
    @State private var sourceFilled: Set<Int64> = []
    @State private var undo: [(studentId: Int64, previous: String)]?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var willCopy: Int {
        sourceFilled.filter { replaceExisting || !targetFilled.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                if let undo {
                    Section {
                        Label("Copiadas \(undo.count) valoraciones.", systemImage: "checkmark.circle.fill")
                        Button("Deshacer") { Task { await revert(undo) } }
                    }
                } else {
                    Section {
                        LabeledContent("Valoraciones en el \(fromTerm.rawValue)", value: "\(sourceCount)")
                        Toggle("Reemplazar si ya hay texto", isOn: $replaceExisting)
                    } footer: {
                        Text("Se copiarán \(willCopy) valoraciones al \(toTerm.rawValue). \(replaceExisting ? "" : "Los que ya tienen no se tocan. ")Podrás deshacerlo.")
                    }
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Copiar del \(fromTerm.rawValue)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(undo == nil ? "Cancelar" : "Hecho") { dismiss() }
                }
                if undo == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Copiar") { Task { await copy() } }
                            .disabled(willCopy == 0 || isWorking)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        let source = (try? await bridge.teacherTermNotes(classId: classId, termLabel: fromTerm.rawValue)) ?? [:]
        let target = (try? await bridge.teacherTermNotes(classId: classId, termLabel: toTerm.rawValue)) ?? [:]
        let ids = Set(studentIds)
        sourceFilled = Set(source.filter { ids.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys)
        targetFilled = Set(target.filter { ids.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys)
        sourceCount = sourceFilled.count
    }

    @MainActor
    private func copy() async {
        isWorking = true
        defer { isWorking = false }
        do {
            undo = try await bridge.copyTeacherTermNotes(
                classId: classId,
                fromTerm: fromTerm.rawValue,
                toTerm: toTerm.rawValue,
                studentIds: studentIds,
                replaceExisting: replaceExisting
            )
            AccessibilityNotification.Announcement("Copiadas \(undo?.count ?? 0) valoraciones").post()
        } catch {
            errorMessage = "No se pudo copiar: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func revert(_ previous: [(studentId: Int64, previous: String)]) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await bridge.restoreTeacherTermNotes(classId: classId, termLabel: toTerm.rawValue, previous: previous)
            AccessibilityNotification.Announcement("Copia deshecha").post()
            dismiss()
        } catch {
            errorMessage = "No se pudo deshacer: \(error.localizedDescription)"
        }
    }
}
