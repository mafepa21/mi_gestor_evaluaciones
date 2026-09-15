import SwiftUI
import MiGestorKit

public struct NotebookGroupImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public let preview: NotebookWorkGroupImportPreview
    public let existingGroupNames: Set<String>
    public let onConfirm: ([ImportedNotebookGroup], Bool) -> Void

    @State private var selectedGroupIds: Set<UUID>
    @State private var clearExistingGroups: Bool = false
    @State private var isProcessing: Bool = false

    public init(
        preview: NotebookWorkGroupImportPreview,
        existingGroupNames: [String],
        onConfirm: @escaping ([ImportedNotebookGroup], Bool) -> Void
    ) {
        self.preview = preview
        self.existingGroupNames = Set(existingGroupNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.onConfirm = onConfirm
        _selectedGroupIds = State(initialValue: Set(preview.groups.map(\.id)))
    }

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    if !preview.warnings.isEmpty {
                        warningsCard
                    }
                    groupsGrid
                }
                .padding(24)
            }
            .background(appSecondarySystemBackgroundColor().opacity(0.35))

            Divider()
            sheetFooter
        }
        .background(appPageBackground(for: colorScheme))
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "person.2.badge.gearshape.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Importar grupos de trabajo")
                    .font(.title2.weight(.bold))
                Text("Revisa los grupos detectados y la asignación automática de alumnos.")
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

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                metricView("Archivo", preview.sourceName)
                metricView("Grupos", "\(selectedGroupIds.count)/\(preview.groups.count)")
                metricView("Asignados", "\(preview.totalMatchedStudents)")
                if preview.totalUnmatchedStudents > 0 {
                    metricView("Sin emparejar", "\(preview.totalUnmatchedStudents)", isWarning: true)
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                Toggle("Reemplazar grupos existentes en esta pestaña", isOn: $clearExistingGroups)
                    .toggleStyle(.switch)
                    .font(.subheadline)

                Spacer()

                Button(selectedGroupIds.count == preview.groups.count ? "Deseleccionar todos" : "Seleccionar todos") {
                    if selectedGroupIds.count == preview.groups.count {
                        selectedGroupIds.removeAll()
                    } else {
                        selectedGroupIds = Set(preview.groups.map(\.id))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(18)
        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        }
    }

    private func metricView(_ title: String, _ value: String, isWarning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(isWarning ? .orange : .primary)
                .lineLimit(1)
        }
        .frame(minWidth: 100, alignment: .leading)
        .padding(10)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Warnings Card

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Avisos de emparejamiento", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            ForEach(preview.warnings.prefix(5), id: \.self) { warning in
                Text("• \(warning)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if preview.warnings.count > 5 {
                Text("+ \(preview.warnings.count - 5) avisos más...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Groups Grid

    private var groupsGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(preview.groups) { group in
                let isSelected = selectedGroupIds.contains(group.id)
                let isAlreadyExisting = existingGroupNames.contains(group.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { isSelected },
                            set: { val in
                                if val { selectedGroupIds.insert(group.id) }
                                else { selectedGroupIds.remove(group.id) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Text(group.name)
                                    .font(.headline)

                                if isAlreadyExisting && !clearExistingGroups {
                                    Text("Ya existe (se añadirá sufijo)")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        Spacer()

                        Text("\(group.members.count) integrantes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Lista de integrantes
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.members) { member in
                            HStack(spacing: 8) {
                                if let matched = member.matchedStudentName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Text(matched)
                                        .font(.subheadline)
                                    if matched.lowercased() != member.rawName.lowercased() {
                                        Text("(\(member.rawName))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Image(systemName: "questionmark.circle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text(member.rawName)
                                        .font(.subheadline)
                                    Text("No encontrado")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.leading, 28)
                }
                .padding(14)
                .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? NotebookStyle.primaryTint.opacity(0.4) : NotebookStyle.softBorder, lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack(spacing: 16) {
            let count = selectedGroupIds.count
            Text(count == 0 ? "Selecciona al menos un grupo." : "\(count) grupo(s) seleccionados para importar.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                isProcessing = true
                let toImport = preview.groups.filter { selectedGroupIds.contains($0.id) }
                onConfirm(toImport, clearExistingGroups)
                dismiss()
            } label: {
                Label(isProcessing ? "Importando..." : "Importar grupos", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedGroupIds.isEmpty || isProcessing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}
