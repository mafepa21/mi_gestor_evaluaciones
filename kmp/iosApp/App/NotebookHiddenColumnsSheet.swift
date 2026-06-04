import SwiftUI
import MiGestorKit

struct NotebookHiddenColumnsSheet: View {
    let columns: [NotebookColumnDefinition]
    let onShowColumn: (NotebookColumnDefinition) -> Void
    let onShowAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var hiddenColumns: [NotebookColumnDefinition] {
        columns
            .filter(\.isTemporarilyHidden)
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hiddenColumns.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(hiddenColumns, id: \.id) { column in
                                hiddenColumnRow(column)
                            }
                        } header: {
                            Text("\(hiddenColumns.count) columna(s) oculta(s)")
                        } footer: {
                            Text("Mostrar una columna la devuelve a la rejilla del cuaderno sin cambiar sus datos.")
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Columnas ocultas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }

                if !hiddenColumns.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Mostrar todas") {
                            onShowAll()
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Sin columnas ocultas")
                    .font(.headline)

                Text("Todas las columnas del cuaderno están visibles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hiddenColumnRow(_ column: NotebookColumnDefinition) -> some View {
        HStack(spacing: 16) {
            Image(systemName: columnIcon(for: column))
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(column.title)
                    .font(.headline)

                Text(columnTypeLabel(for: column))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Button {
                onShowColumn(column)
            } label: {
                Label("Mostrar", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }

    private func columnTypeLabel(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .calculated:
            return "Calculada"
        case .rubric:
            return "Rúbrica"
        case .check:
            return "Casilla"
        case .text:
            return "Texto"
        case .attendance:
            return "Asistencia"
        case .ordinal:
            return "Ordinal"
        case .numeric:
            return "Numérica"
        default:
            return String(describing: column.type)
        }
    }

    private func columnIcon(for column: NotebookColumnDefinition) -> String {
        if let icon = column.iconName, !icon.isEmpty {
            return icon
        }

        switch column.type {
        case .numeric:
            return "number"
        case .rubric:
            return "checklist"
        case .attendance:
            return "figure.walk.circle"
        case .calculated:
            return "function"
        case .text:
            return "text.alignleft"
        default:
            return "rectangle"
        }
    }
}
