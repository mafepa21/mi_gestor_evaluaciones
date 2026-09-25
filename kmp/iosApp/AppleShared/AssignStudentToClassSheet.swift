import SwiftUI
import MiGestorKit

/// Regla de cierre tras matricular: solo cierra si el bridge confirma el alta en el grupo.
enum StudentEnrollmentSaveGate {
    static let saveFailureMessage =
        "No se pudo matricular al alumno en el grupo. Sigue sin asignar."

    static func shouldDismiss(succeeded: Bool) -> Bool { succeeded }

    static func failureMessage(detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return saveFailureMessage }
        return "\(saveFailureMessage) \(trimmed)"
    }
}

struct AssignStudentToClassSheet: View {
    let students: [Student]
    let availableClasses: [SchoolClass]
    let onAssign: (Int64) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassId: Int64?
    @State private var errorMessage: String?
    @State private var isAssigning = false

    init(student: Student, availableClasses: [SchoolClass], onAssign: @escaping (Int64) async throws -> Void) {
        self.students = [student]
        self.availableClasses = availableClasses
        self.onAssign = onAssign
        _selectedClassId = State(initialValue: availableClasses.first?.id)
    }

    init(students: [Student], availableClasses: [SchoolClass], onAssign: @escaping (Int64) async throws -> Void) {
        self.students = students
        self.availableClasses = availableClasses
        self.onAssign = onAssign
        _selectedClassId = State(initialValue: availableClasses.first?.id)
    }

    private var targetTitle: String {
        if students.count == 1, let first = students.first {
            return "\(first.firstName) \(first.lastName)"
        } else {
            return "\(students.count) alumnos seleccionados"
        }
    }

    private var targetSubtitle: String {
        if students.count == 1 {
            return "Selecciona el curso o grupo al que deseas matricular a este alumno."
        } else {
            return "Selecciona el curso o grupo al que deseas matricular a los \(students.count) alumnos seleccionados."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(macOS)
                macHeader
                Divider()
                #endif

                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(targetTitle)
                                .font(.headline)
                            Text(targetSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Curso disponible") {
                        if availableClasses.isEmpty {
                            Text("No hay cursos creados. Crea un curso primero en la sección de Cursos.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Curso", selection: $selectedClassId) {
                                ForEach(availableClasses, id: \.id) { schoolClass in
                                    Text(schoolClass.name).tag(Optional(schoolClass.id))
                                }
                            }
                            #if os(iOS)
                            .pickerStyle(.inline)
                            .labelsHidden()
                            #endif
                        }
                    }
                }
                .formStyle(.grouped)

                #if os(macOS)
                Divider()
                macFooter
                #endif
            }
            .navigationTitle("Asignar a curso")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isAssigning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAssigning ? "Asignando…" : "Asignar") {
                        Task { await confirmAssign() }
                    }
                    .disabled(selectedClassId == nil || isAssigning)
                }
            }
            #endif
        }
        .alert("No se pudo matricular", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(macOS)
        .frame(width: 440, height: 320)
        #else
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }

    #if os(macOS)
    private var macHeader: some View {
        HStack {
            Image(systemName: "person.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asignar a curso")
                    .font(.headline)
                Text(targetTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var macFooter: some View {
        HStack {
            Spacer()
            Button("Cancelar") {
                dismiss()
            }
            .disabled(isAssigning)
            Button(isAssigning ? "Asignando…" : "Asignar a curso") {
                Task { await confirmAssign() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedClassId == nil || isAssigning)
        }
        .padding(16)
    }
    #endif

    @MainActor
    private func confirmAssign() async {
        guard let classId = selectedClassId, !isAssigning else { return }
        isAssigning = true
        defer { isAssigning = false }
        do {
            try await onAssign(classId)
            if StudentEnrollmentSaveGate.shouldDismiss(succeeded: true) {
                dismiss()
            }
        } catch {
            errorMessage = StudentEnrollmentSaveGate.failureMessage(detail: error.localizedDescription)
        }
    }
}
