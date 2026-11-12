import SwiftUI

/// Hoja para cambiar los alumnos de cada equipo de un torneo ya configurado.
/// Solo toca integrantes: nombres, calendario y resultados se conservan.
struct SdaTournamentMembersSheet: View {
    let teams: [TournamentPlanTeam]
    let students: [(id: String, name: String)]
    let onSave: ([String: [String]]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: [String: [String]]
    @State private var errorText: String?

    init(
        teams: [TournamentPlanTeam],
        students: [(id: String, name: String)],
        onSave: @escaping ([String: [String]]) throws -> Void
    ) {
        self.teams = teams
        self.students = students
        self.onSave = onSave
        _draft = State(initialValue: Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.studentIDs) }))
    }

    private func name(_ id: String) -> String {
        students.first(where: { $0.id == id })?.name ?? SdaResolvedTeam.missingStudentName
    }

    private func team(of student: String) -> String? {
        draft.first(where: { $0.value.contains(student) })?.key
    }

    /// Alumnos del curso que no están en ningún equipo.
    private var unassigned: [(id: String, name: String)] {
        let used = Set(draft.values.flatMap { $0 })
        return students.filter { !used.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var hasChanges: Bool {
        teams.contains { Set(draft[$0.id] ?? []) != Set($0.studentIDs) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Mueve alumnos entre equipos. El calendario y los resultados no cambian.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(teams) { team in
                    Section {
                        let members = (draft[team.id] ?? []).sorted {
                            name($0).localizedStandardCompare(name($1)) == .orderedAscending
                        }
                        if members.isEmpty {
                            Text("Sin alumnos")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(members, id: \.self) { student in
                            memberRow(student, in: team.id)
                        }
                        addMenu(to: team.id)
                    } header: {
                        Text(team.name)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Editar integrantes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!hasChanges)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func memberRow(_ student: String, in teamId: String) -> some View {
        HStack {
            Text(name(student))
            Spacer(minLength: 8)
            Menu {
                ForEach(teams.filter { $0.id != teamId }) { other in
                    Button("Mover a \(other.name)") { move(student, to: other.id) }
                }
                Divider()
                Button("Quitar del equipo", role: .destructive) { remove(student) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Opciones de \(name(student))")
        }
    }

    private func addMenu(to teamId: String) -> some View {
        Menu {
            if unassigned.isEmpty {
                Text("Todos los alumnos tienen equipo")
            }
            ForEach(unassigned, id: \.id) { student in
                Button(student.name) { move(student.id, to: teamId) }
            }
            if !students.isEmpty {
                Menu("De otro equipo") {
                    ForEach(students.filter { team(of: $0.id).map { $0 != teamId } ?? false }, id: \.id) { student in
                        Button(student.name) { move(student.id, to: teamId) }
                    }
                }
            }
        } label: {
            Label("Añadir alumno", systemImage: "plus.circle")
        }
    }

    private func move(_ student: String, to teamId: String) {
        remove(student)
        draft[teamId, default: []].append(student)
        errorText = nil
    }

    private func remove(_ student: String) {
        for key in draft.keys { draft[key]?.removeAll { $0 == student } }
        errorText = nil
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch TournamentMembersError.emptyTeam(let teamName) {
            errorText = "«\(teamName)» se ha quedado sin alumnos. Añade al menos uno."
        } catch {
            errorText = "No se pudo guardar. Revisa que ningún alumno esté en dos equipos."
        }
    }
}
