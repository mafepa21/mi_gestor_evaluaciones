import SwiftUI

struct NotebookDeletionImpactSheet: View {
    let impact: NotebookDeletionImpactDraft
    @Binding var confirmationText: String
    let onPreserveCategory: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var destructiveEnabled: Bool {
        !impact.hasLockedColumns && (!impact.requiresStrongConfirmation || confirmationText == "ELIMINAR")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    impactRow("Columnas afectadas", value: impact.affectedColumnCount, systemImage: "rectangle.3.group")
                    impactRow("Notas afectadas", value: impact.affectedGradeCount, systemImage: "number")
                    impactRow("Fórmulas relacionadas", value: impact.affectedFormulaColumnCount, systemImage: "function")
                    impactRow("Columnas usadas en media", value: impact.affectedAverageColumnCount, systemImage: "percent")
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if impact.hasLockedColumns {
                    Label("Hay columnas bloqueadas. La eliminación destructiva está desactivada.", systemImage: "lock.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NotebookStyle.warningTint)
                }

                if impact.requiresStrongConfirmation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Escribe ELIMINAR para confirmar el borrado de notas.")
                            .font(.callout.weight(.semibold))
                        TextField("ELIMINAR", text: $confirmationText)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    if impact.kind == .category {
                        Button {
                            onPreserveCategory()
                        } label: {
                            Label("Eliminar solo la categoría y conservar columnas", systemImage: "folder.badge.minus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(destructiveTitle, systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!destructiveEnabled)

                    Button("Cancelar", role: .cancel) {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .navigationTitle("Borrado seguro")
            .appInlineNavigationBarTitleDisplayMode()
        }
    }

    private var title: String {
        switch impact.kind {
        case .column:
            return "Eliminar columna \"\(impact.targetName)\""
        case .category:
            return "Eliminar categoría \"\(impact.targetName)\""
        case .columns:
            return "Eliminar \(impact.affectedColumnCount) columnas"
        }
    }

    private var subtitle: String {
        switch impact.kind {
        case .column:
            return "Esta acción eliminará la columna y sus notas de esta clase."
        case .category:
            return "La opción recomendada conserva las columnas y solo elimina la categoría."
        case .columns:
            return "Esta acción eliminará de forma permanente las columnas seleccionadas y sus notas de esta clase."
        }
    }

    private var destructiveTitle: String {
        switch impact.kind {
        case .column:
            return "Eliminar columna"
        case .category:
            return "Eliminar categoría y columnas"
        case .columns:
            return "Eliminar columnas"
        }
    }

    private func impactRow(_ label: String, value: Int, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            Text(label)
            Spacer()
            Text("\(value)")
                .font(.headline.monospacedDigit())
        }
    }
}

