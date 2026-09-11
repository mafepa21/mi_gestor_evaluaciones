import SwiftUI
import MiGestorKit

struct AssignStudentToClassSheet: View {
    let student: Student
    let availableClasses: [SchoolClass]
    let onAssign: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassId: Int64?

    init(student: Student, availableClasses: [SchoolClass], onAssign: @escaping (Int64) -> Void) {
        self.student = student
        self.availableClasses = availableClasses
        self.onAssign = onAssign
        _selectedClassId = State(initialValue: availableClasses.first?.id)
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
                            Text("\(student.firstName) \(student.lastName)")
                                .font(.headline)
                            Text("Selecciona el curso o grupo al que deseas matricular a este alumno.")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Asignar") {
                        if let classId = selectedClassId {
                            onAssign(classId)
                            dismiss()
                        }
                    }
                    .disabled(selectedClassId == nil)
                }
            }
            #endif
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
                Text("\(student.firstName) \(student.lastName)")
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
            Button("Asignar a curso") {
                if let classId = selectedClassId {
                    onAssign(classId)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedClassId == nil)
        }
        .padding(16)
    }
    #endif
}
