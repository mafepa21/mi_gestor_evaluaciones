import SwiftUI
import MiGestorKit

struct ClassroomCaptureBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let contextTitle: String
    let isCompactNotebookMode: Bool
    let onOpenAttendance: () -> Void
    let onOpenRubric: () -> Void
    let onQuickNote: () -> Void
    let onInjury: () -> Void
    let onObservation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(contextTitle, systemImage: "figure.run.circle.fill")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .frame(minWidth: 220, alignment: .leading)

            Spacer(minLength: 4)

            classroomAction("Asistencia", systemImage: "checklist.checked", action: onOpenAttendance)
            classroomAction("Rúbrica", systemImage: "checklist", action: onOpenRubric)
            classroomAction("Nota rápida", systemImage: "note.text.badge.plus", action: onQuickNote)
            classroomAction("Lesión", systemImage: "bandage", action: onInjury)
            classroomAction("Observación", systemImage: "eye", action: onObservation)

            if isCompactNotebookMode {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Cuaderno en modo compacto")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(appCardBackground(for: colorScheme).opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
    }

    private func classroomAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct ClassroomCaptureSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ClassroomCaptureSheet
    let students: [Student]
    @Binding var selectedStudentId: Int64?
    @Binding var noteText: String
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    private var selectedStudent: Student? {
        students.first(where: { $0.id == selectedStudentId })
    }

    private var title: String {
        switch kind {
        case .quickNote: return "Nota rápida"
        case .observation: return "Observación"
        case .injury: return selectedStudent?.isInjured == true ? "Retirar lesión" : "Marcar lesión"
        }
    }

    private var message: String {
        switch kind {
        case .quickNote:
            return "Se guardará en el diario de la sesión más reciente de la clase."
        case .observation:
            return "Se registrará como observación individual para seguimiento."
        case .injury:
            return "Actualiza el estado físico del alumno para Cuaderno, Asistencia y Rúbricas."
        }
    }

    private var requiresText: Bool {
        kind != .injury
    }

    private var canSave: Bool {
        selectedStudentId != nil && (!requiresText || !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Alumno", selection: Binding(
                    get: { selectedStudentId ?? students.first?.id ?? -1 },
                    set: { selectedStudentId = $0 > 0 ? $0 : nil }
                )) {
                    ForEach(students, id: \.id) { student in
                        Text(student.fullName).tag(student.id)
                    }
                }
                .pickerStyle(.menu)

                if requiresText {
                    TextField("Texto", text: $noteText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(5, reservesSpace: true)
                } else if let selectedStudent {
                    HStack {
                        Text("Estado actual")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedStudent.isInjured ? "Lesionado" : "Disponible")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(selectedStudent.isInjured ? .orange : .green)
                    }
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(kind == .injury ? "Actualizar" : "Guardar")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 360)
        #else
        .presentationDetents([.medium])
        #endif
    }
}
