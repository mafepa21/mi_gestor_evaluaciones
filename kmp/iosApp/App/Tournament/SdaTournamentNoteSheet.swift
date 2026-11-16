import SwiftUI

/// Qué se está anotando: un partido (ronda, pista, equipos) o un alumno.
struct SdaNoteTarget: Identifiable, Equatable {
    enum Subject: Equatable {
        case match
        case student(id: String, name: String)
    }

    let id = UUID()
    let subject: Subject
    let roundNumber: Int?
    let venueNumber: Int?
    let teams: [String]

    static func == (lhs: SdaNoteTarget, rhs: SdaNoteTarget) -> Bool { lhs.id == rhs.id }
}

/// Hoja corta para apuntar una nota en el modo directo. Partido: «Conflicto por el resultado» u
/// «Otra», y si se copia a la ficha de los alumnos de los dos equipos. Alumno: va siempre a su ficha.
/// En los dos casos queda también en el torneo (apartado «Notas»).
struct SdaTournamentNoteSheet: View {
    @ObservedObject var store: SdaTournamentStore
    let bridge: KmpBridge
    let target: SdaNoteTarget

    @Environment(\.dismiss) private var dismiss
    @State private var kind: TournamentNoteKind
    @State private var text = ""
    @State private var copyToFiles: Bool
    @State private var isSaving = false
    @State private var warning: String?
    @FocusState private var isEditorFocused: Bool

    init(store: SdaTournamentStore, bridge: KmpBridge, target: SdaNoteTarget) {
        self.store = store
        self.bridge = bridge
        self.target = target
        switch target.subject {
        case .match:
            _kind = State(initialValue: .resultConflict)
            _copyToFiles = State(initialValue: true)
        case .student:
            _kind = State(initialValue: .student)
            _copyToFiles = State(initialValue: true)
        }
    }

    private var isMatch: Bool { target.subject == .match }

    private var title: String {
        switch target.subject {
        case .match: return target.venueNumber.map { "Pista \($0)" } ?? "Partido"
        case .student(_, let name): return name
        }
    }

    private var context: String {
        TournamentNote(kind: kind, text: "", roundNumber: target.roundNumber, venueNumber: target.venueNumber, teams: target.teams).contextLine
    }

    private var matchStudentIds: [Int64] { store.studentIds(ofTeams: target.teams) }

    private var existingNotes: [TournamentNote] {
        switch target.subject {
        case .match:
            guard let round = target.roundNumber, let venue = target.venueNumber else { return [] }
            return store.plan.notes(roundNumber: round, venueNumber: venue)
        case .student(let id, _):
            return store.plan.notes(studentID: id)
        }
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if !context.isEmpty {
                    Section {
                        Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if isMatch {
                    Section {
                        Picker("Tipo", selection: $kind) {
                            Text("Conflicto por el resultado").tag(TournamentNoteKind.resultConflict)
                            Text("Otra").tag(TournamentNoteKind.match)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                Section {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($isEditorFocused)
                } header: {
                    Text("Qué ha pasado")
                }
                Section {
                    if isMatch {
                        Toggle(isOn: $copyToFiles) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Añadir a la ficha de los alumnos")
                                Text(matchStudentIds.isEmpty
                                     ? "Estos equipos no tienen alumnos asignados."
                                     : "\(sdaPlural(matchStudentIds.count, "alumno", "alumnos")) de los dos equipos.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(matchStudentIds.isEmpty)
                    } else {
                        Label("Se guarda en el torneo y en la ficha del alumno.", systemImage: "person.text.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let warning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(IOSAppStyle.warning)
                    }
                }
                if !existingNotes.isEmpty {
                    Section("Ya apuntado") {
                        ForEach(existingNotes) { note in
                            SdaTournamentNoteRow(note: note, showsContext: false)
                        }
                    }
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
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Guardar") { Task { await save() } }
                            .disabled(trimmedText.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(!trimmedText.isEmpty)
        }
        .onAppear { isEditorFocused = true }
    }

    private var placeholder: String {
        switch kind {
        case .resultConflict: return "Ej.: el equipo A dice 5-3 y el B dice 4-4."
        case .match: return "Ej.: partido muy igualado, buen juego limpio."
        case .student: return "Ej.: juega muy bien en la red, anima a su pareja."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let studentIds: [Int64]
        var note = TournamentNote(
            kind: kind,
            text: trimmedText,
            roundNumber: target.roundNumber,
            venueNumber: target.venueNumber,
            teams: target.teams
        )
        switch target.subject {
        case .match:
            studentIds = copyToFiles ? matchStudentIds : []
        case .student(let id, let name):
            note.studentID = id
            note.studentName = name
            studentIds = Int64(id).map { [$0] } ?? []
        }
        if let message = await store.addNote(note, copyingToStudentIds: studentIds, bridge: bridge) {
            // La nota ya está en el torneo: se avisa y se deja cerrar.
            warning = message
            text = ""
            return
        }
        dismiss()
    }
}

/// Una nota en lista: tipo, hora, contexto opcional y texto.
struct SdaTournamentNoteRow: View {
    let note: TournamentNote
    var showsContext = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(headline, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(note.kind == .resultConflict ? IOSAppStyle.warning : Color.primary)
                Spacer(minLength: 8)
                Text(note.createdAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsContext, !note.contextLine.isEmpty {
                Text(note.contextLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !note.incidentIds.isEmpty {
                Text("En la ficha de \(sdaPlural(note.incidentIds.count, "alumno", "alumnos"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if note.kind == .student, let name = note.studentName { return name }
        return note.kind.title
    }

    private var icon: String {
        switch note.kind {
        case .resultConflict: return "exclamationmark.bubble.fill"
        case .match: return "text.bubble"
        case .student: return "person.crop.circle"
        }
    }
}
