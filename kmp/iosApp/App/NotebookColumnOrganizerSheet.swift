import SwiftUI
import MiGestorKit

struct NotebookColumnOrganizerSheet: View {
    let columns: [NotebookColumnDefinition]
    let onSetVisibility: (NotebookColumnDefinition, NotebookColumnVisibility) -> Void
    let onRename: (NotebookColumnDefinition) -> Void
    let onDelete: (NotebookColumnDefinition) -> Void
    let onAddColumn: () -> Void
    let onOpenHiddenColumns: () -> Void
    let onShowAll: () -> Void
    let onReorder: ([NotebookColumnDefinition]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orderedColumnIds: [String] = []
    @State private var searchText = ""
    @State private var sectionFilter: SectionFilter = .all

    private enum SectionFilter: String, CaseIterable, Identifiable {
        case all = "Todas"
        case visible = "Visibles"
        case hidden = "Ocultas"
        case archived = "Archivadas"

        var id: String { rawValue }
    }

    private var orderedColumns: [NotebookColumnDefinition] {
        let columnById = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })
        let ids = orderedColumnIds.isEmpty ? defaultOrderedColumnIds : orderedColumnIds
        let ordered = ids.compactMap { columnById[$0] }
        let missing = columns
            .filter { !ids.contains($0.id) }
            .sorted { $0.order < $1.order }

        return ordered + missing
    }

    private var defaultOrderedColumnIds: [String] {
        columns.sorted { $0.order < $1.order }.map(\.id)
    }

    private var visibleColumns: [NotebookColumnDefinition] {
        filtered(orderedColumns.filter(\.isVisibleInGrid))
    }

    private var hiddenColumns: [NotebookColumnDefinition] {
        filtered(orderedColumns.filter(\.isTemporarilyHidden))
    }

    private var archivedColumns: [NotebookColumnDefinition] {
        filtered(orderedColumns.filter(\.isArchived))
    }

    private var visibleCount: Int {
        columns.filter(\.isVisibleInGrid).count
    }

    private var hiddenCount: Int {
        columns.filter(\.isTemporarilyHidden).count
    }

    private var archivedCount: Int {
        columns.filter(\.isArchived).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            controls

            Divider()

            if visibleColumns.isEmpty && hiddenColumns.isEmpty && archivedColumns.isEmpty {
                emptyState
            } else {
                List {
                    if sectionFilter == .all || sectionFilter == .visible {
                        columnSection("Visibles", columns: visibleColumns, emptyText: "No hay columnas visibles.", allowsMove: true)
                    }
                    if sectionFilter == .all || sectionFilter == .hidden {
                        columnSection("Ocultas", columns: hiddenColumns, emptyText: "No hay columnas ocultas.", allowsMove: true)
                    }
                    if sectionFilter == .all || sectionFilter == .archived {
                        columnSection("Archivadas", columns: archivedColumns, emptyText: "No hay columnas archivadas.", allowsMove: false)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            footer
        }
        .background(.regularMaterial)
        .onAppear {
            syncLocalStateWithColumns()
        }
        .appOnChange(of: columns.map(\.id)) { _ in
            syncLocalStateWithColumns()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("Organizar columnas")
                    .font(.title3.weight(.semibold))

                Text("\(visibleCount) visibles · \(hiddenCount) ocultas · \(archivedCount) archivadas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cerrar") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            TextField("Buscar columna...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Picker("Sección", selection: $sectionFilter) {
                ForEach(SectionFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            Button {
                onOpenHiddenColumns()
            } label: {
                Label("Ocultas", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered)
            .disabled(hiddenCount == 0)
            .fixedSize()

            Button {
                showAllColumns()
            } label: {
                Label("Mostrar todas", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .disabled(hiddenCount == 0)
            .fixedSize()

            Button {
                onAddColumn()
            } label: {
                Label("Nueva columna", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Sin columnas")
                .font(.headline)
            Text("No hay columnas que coincidan con el filtro actual.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    @ViewBuilder
    private func columnSection(
        _ title: String,
        columns: [NotebookColumnDefinition],
        emptyText: String,
        allowsMove: Bool
    ) -> some View {
        Section {
            if columns.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(columns, id: \.id) { column in
                    columnRow(column)
                }
                .onMove { source, destination in
                    guard allowsMove else { return }
                    moveColumns(from: source, to: destination, within: columns)
                }
            }
        } header: {
            Text(title)
        }
    }

    private func columnRow(_ column: NotebookColumnDefinition) -> some View {
        HStack(spacing: 10) {
            Image(systemName: columnIcon(for: column))
                .frame(width: 24)
                .foregroundStyle(column.isVisibleInGrid ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(column.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(column.isArchived ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(columnTypeLabel(for: column))
                    if column.isPinned {
                        Text("Fijada")
                    }
                    if column.isLocked {
                        Text("Bloqueada")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                if column.isVisibleInGrid {
                    Button("Ocultar") {
                        onSetVisibility(column, .hidden)
                    }
                    Button("Archivar") {
                        onSetVisibility(column, .archived)
                    }
                    Button("Renombrar") {
                        onRename(column)
                    }
                    deleteButton(for: column, title: "Eliminar")
                } else if column.isTemporarilyHidden {
                    Button("Mostrar") {
                        onSetVisibility(column, .visible)
                    }
                    Button("Archivar") {
                        onSetVisibility(column, .archived)
                    }
                    Button("Renombrar") {
                        onRename(column)
                    }
                    deleteButton(for: column, title: "Eliminar")
                } else {
                    Button("Restaurar") {
                        onSetVisibility(column, .visible)
                    }
                    deleteButton(for: column, title: "Eliminar definitivamente")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func deleteButton(for column: NotebookColumnDefinition, title: String) -> some View {
        Button(title, role: .destructive) {
            onDelete(column)
        }
        .disabled(!column.canBeDeleted)
    }

    private var footer: some View {
        HStack {
            Text("Ocultar limpia la rejilla. Archivar retira la columna del uso diario. Eliminar borra la columna tras confirmación.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func syncLocalStateWithColumns() {
        let currentIds = columns.map(\.id)
        if orderedColumnIds.isEmpty {
            orderedColumnIds = defaultOrderedColumnIds
        } else {
            orderedColumnIds = orderedColumnIds.filter { currentIds.contains($0) }
            let missingIds = defaultOrderedColumnIds.filter { !orderedColumnIds.contains($0) }
            orderedColumnIds.append(contentsOf: missingIds)
        }
    }

    private func filtered(_ columns: [NotebookColumnDefinition]) -> [NotebookColumnDefinition] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return columns }
        return columns.filter { $0.title.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private func showAllColumns() {
        onShowAll()
    }

    private func moveColumns(
        from source: IndexSet,
        to destination: Int,
        within sectionColumns: [NotebookColumnDefinition]
    ) {
        let sectionIds = sectionColumns.map(\.id)
        var reorderedSectionIds = sectionIds
        reorderedSectionIds.move(fromOffsets: source, toOffset: destination)

        var nextIds = orderedColumnIds.isEmpty ? defaultOrderedColumnIds : orderedColumnIds
        let positions = nextIds.indices.filter { sectionIds.contains(nextIds[$0]) }
        for (index, position) in positions.enumerated() where reorderedSectionIds.indices.contains(index) {
            nextIds[position] = reorderedSectionIds[index]
        }

        orderedColumnIds = nextIds
        onReorder(orderedColumns)
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
