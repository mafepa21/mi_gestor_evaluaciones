import SwiftUI

struct StudentImportSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    let preview: AppleStudentImportPreview

    @State private var selectedRows: Set<Int>
    @State private var selectedClassId: Int64?
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(preview: AppleStudentImportPreview) {
        self.preview = preview
        _selectedRows = State(initialValue: Set(preview.students.map(\.rowNumber)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                Divider()
                studentsList
            }
            .navigationTitle("Importar alumnado")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importando..." : "Importar") {
                        Task { await confirmImport() }
                    }
                    .disabled(selectedRows.isEmpty || isImporting)
                }
            }
        }
        .alert("No se pudo importar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(selectedRows.count) de \(preview.students.count) alumnos", systemImage: "person.3.fill")
                    .font(.headline)

                Spacer()

                Button(selectedRows.count == preview.students.count ? "Deseleccionar" : "Seleccionar todos") {
                    if selectedRows.count == preview.students.count {
                        selectedRows.removeAll()
                    } else {
                        selectedRows = Set(preview.students.map(\.rowNumber))
                    }
                }
            }

            if let className = preview.className, !className.isEmpty {
                Text("Clase detectada: \(className)")
                    .foregroundStyle(.secondary)
            }

            if let course = preview.course, !course.isEmpty {
                Text("Curso detectado: \(course)")
                    .foregroundStyle(.secondary)
            }

            Picker("Clase destino", selection: $selectedClassId) {
                Text("No asignar").tag(Optional<Int64>.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(schoolClass.name).tag(Optional(schoolClass.id))
                }
            }
        }
        .padding()
    }

    private var studentsList: some View {
        List(preview.students) { student in
            Toggle(isOn: Binding(
                get: { selectedRows.contains(student.rowNumber) },
                set: { isSelected in
                    if isSelected {
                        selectedRows.insert(student.rowNumber)
                    } else {
                        selectedRows.remove(student.rowNumber)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.fullName)
                        .font(.body.weight(.medium))
                    Text("Nombre: \(student.firstName) - Apellidos: \(student.lastName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func confirmImport() async {
        isImporting = true
        defer { isImporting = false }

        do {
            try await bridge.confirmStudentImport(
                selectedRows: Array(selectedRows),
                targetClassId: selectedClassId
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
