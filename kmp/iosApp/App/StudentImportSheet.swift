import SwiftUI

struct StudentImportSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let preview: AppleStudentImportPreview

    @State private var selectedRows: Set<Int>
    @State private var selectedClassId: Int64?
    @State private var omitDuplicates = true
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(preview: AppleStudentImportPreview) {
        self.preview = preview
        _selectedRows = State(initialValue: Set(preview.students.filter { $0.duplicateStatus == .new }.map(\.rowNumber)))
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            ScrollView {
                summaryHeader
                studentsList
            }
            .background(appSecondarySystemBackgroundColor().opacity(0.35))

            Divider()
            footer
        }
        .background(appPageBackground(for: colorScheme))
        .alert("No se pudo importar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Importar alumnado")
                    .font(.title2.weight(.bold))
                Text("Revisa duplicados, clase destino y filas antes de confirmar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                importMetric("Seleccionados", "\(selectedRows.count)")
                importMetric("Detectados", "\(preview.students.count)")
                importMetric("Duplicados", "\(preview.students.filter { $0.duplicateStatus != .new }.count)")

                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    if let className = preview.className, !className.isEmpty {
                        Label("Clase detectada: \(className)", systemImage: "rectangle.3.group")
                            .foregroundStyle(.secondary)
                    }

                    if let course = preview.course, !course.isEmpty {
                        Label("Curso detectado: \(course)", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(selectedRows.count == preview.students.count ? "Deseleccionar" : "Seleccionar todos") {
                    if selectedRows.count == preview.students.count {
                        selectedRows.removeAll()
                    } else {
                        selectedRows = Set(preview.students.map(\.rowNumber))
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 16) {
                Toggle("Omitir duplicados", isOn: $omitDuplicates)
                    .toggleStyle(.switch)

                Picker("Clase destino", selection: $selectedClassId) {
                    Text("No asignar").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .frame(maxWidth: 280)
            }
        }
        .padding(20)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        }
        .padding(24)
    }

    private var studentsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(preview.students) { student in
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(student.fullName)
                            .font(.body.weight(.medium))
                        HStack(spacing: 8) {
                            Text("Fila \(student.rowNumber)")
                                .foregroundStyle(.secondary)
                            Text("\(student.firstName) \(student.lastName)")
                                .foregroundStyle(.secondary)
                            Text(student.duplicateStatus.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(duplicateTint(for: student.duplicateStatus))
                            if let detail = student.duplicateDetail {
                                Text(detail)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
                .disabled(omitDuplicates && student.duplicateStatus != .new)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NotebookStyle.softBorder.opacity(0.8), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(selectedRows.isEmpty ? "Selecciona al menos una fila para importar." : "\(selectedRows.count) filas listas para importar.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                Task { await confirmImport() }
            } label: {
                Label(isImporting ? "Importando..." : "Importar", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedRows.isEmpty || isImporting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private func importMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
        }
        .frame(minWidth: 112, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @MainActor
    private func confirmImport() async {
        isImporting = true
        defer { isImporting = false }

        do {
            try await bridge.confirmStudentImport(
                selectedRows: Array(selectedRows),
                targetClassId: selectedClassId,
                omitDuplicates: omitDuplicates
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicateTint(for status: AppleStudentDuplicateStatus) -> Color {
        switch status {
        case .new:
            return .green
        case .possibleDuplicate:
            return .orange
        case .alreadyExists:
            return .red
        }
    }
}
