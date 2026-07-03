import SwiftUI
import MiGestorKit

struct NotebookColumnOrganizerSheet: View {
    let columns: [NotebookColumnDefinition]
    let onSetVisibility: (NotebookColumnDefinition, NotebookColumnVisibility) -> Void
    let onRename: (NotebookColumnDefinition) -> Void
    let onDelete: (NotebookColumnDefinition) -> Void
    let onDeleteMultiple: ([NotebookColumnDefinition]) -> Void
    let onAddColumn: () -> Void
    let onCreateCategory: () -> Void
    let onCreateSummary: () -> Void
    let onGenerateSummary: (String?) -> Void
    let onShowAll: () -> Void
    let onReorder: ([NotebookColumnDefinition]) -> Void
    let onOpenGroupManagement: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("notebook.groupByWorkGroupMode") var groupByWorkGroupMode = "none"
    @State private var orderedColumnIds: [String] = []
    @State private var searchText = ""
    @State private var sectionFilter: SectionFilter = .all
    @State private var isSelectionMode = false
    @State private var selectedColumnIds = Set<String>()
    @State private var isHelpPopoverPresented = false

    private enum SectionFilter: Hashable, CaseIterable, Identifiable {
        case all
        case visible
        case hidden
        case archived

        var id: Self { self }
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

    private var summaryColumns: [NotebookColumnDefinition] {
        columns.filter(isNotebookIndividualSummaryColumn)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if !isSelectionMode {
                filterRow

                Divider()
            }

            if visibleColumns.isEmpty && hiddenColumns.isEmpty && archivedColumns.isEmpty {
                emptyState
            } else {
                List {
                    switch sectionFilter {
                    case .all:
                        if !visibleColumns.isEmpty {
                            columnSection("Visibles", columns: visibleColumns, emptyText: "No hay columnas visibles.", allowsMove: !isSelectionMode)
                        }
                        if !hiddenColumns.isEmpty {
                            columnSection("Ocultas", columns: hiddenColumns, emptyText: "No hay columnas ocultas.", allowsMove: !isSelectionMode)
                        }
                        if !archivedColumns.isEmpty {
                            columnSection("Archivadas", columns: archivedColumns, emptyText: "No hay columnas archivadas.", allowsMove: false)
                        }
                    case .visible:
                        columnSection("Visibles", columns: visibleColumns, emptyText: "No hay columnas visibles.", allowsMove: !isSelectionMode)
                    case .hidden:
                        columnSection("Ocultas", columns: hiddenColumns, emptyText: "No hay columnas ocultas.", allowsMove: !isSelectionMode)
                    case .archived:
                        columnSection("Archivadas", columns: archivedColumns, emptyText: "No hay columnas archivadas.", allowsMove: false)
                    }
                }
                .listStyle(.inset)
                .appEditMode(isSelectionMode: isSelectionMode)
            }

            Divider()

            if isSelectionMode {
                selectionActionBar
            } else {
                footer
            }
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
                Text(isSelectionMode ? "Seleccionar columnas" : "Organizar columnas")
                    .font(.title3.weight(.semibold))

                Text("\(visibleCount) visibles · \(hiddenCount) ocultas · \(archivedCount) archivadas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelectionMode {
                Button(selectedColumnIds.count == columns.count ? "Deseleccionar todo" : "Seleccionar todo") {
                    if selectedColumnIds.count == columns.count {
                        selectedColumnIds.removeAll()
                    } else {
                        selectedColumnIds = Set(columns.map(\.id))
                    }
                }
                .buttonStyle(.bordered)

                Button("Listo") {
                    isSelectionMode = false
                    selectedColumnIds.removeAll()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Seleccionar") {
                    isSelectionMode = true
                }
                .buttonStyle(.bordered)

                Button {
                    onAddColumn()
                } label: {
                    Label("Nueva columna", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar columna", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity)

            Picker("Sección", selection: $sectionFilter) {
                Text("Todas (\(columns.count))").tag(SectionFilter.all)
                Text("Visibles (\(visibleCount))").tag(SectionFilter.visible)
                Text("Ocultas (\(hiddenCount))").tag(SectionFilter.hidden)
                Text("Archivadas (\(archivedCount))").tag(SectionFilter.archived)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var selectionActionBar: some View {
        let selectedColumns = columns.filter { selectedColumnIds.contains($0.id) }
        let hasLocked = selectedColumns.contains { $0.isLocked }

        return VStack(spacing: 8) {
            if hasLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                    Text("La selección contiene columnas bloqueadas. Se mostrará una advertencia al continuar.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack {
                Text("\(selectedColumnIds.count) seleccionadas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    onDeleteMultiple(selectedColumns)
                } label: {
                    Label("Eliminar seleccionadas", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedColumnIds.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .padding(.top, hasLocked ? 4 : 12)
        }
        .background(.thinMaterial)
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
            if isSelectionMode {
                Image(systemName: selectedColumnIds.contains(column.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedColumnIds.contains(column.id) ? Color.accentColor : .secondary)
                    .padding(.trailing, 4)
            }

            Image(systemName: columnIcon(for: column))
                .frame(width: 24)
                .foregroundStyle(column.isVisibleInGrid ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(column.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(column.isArchived ? .secondary : .primary)

                    if column.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

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

            if !isSelectionMode {
                if column.isVisibleInGrid {
                    Button {
                        onSetVisibility(column, .hidden)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Ocultar columna")
                } else if column.isTemporarilyHidden {
                    Button {
                        onSetVisibility(column, .visible)
                    } label: {
                        Image(systemName: "eye.slash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Mostrar columna")
                }

                Menu {
                    if column.isVisibleInGrid || column.isTemporarilyHidden {
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
                .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                if selectedColumnIds.contains(column.id) {
                    selectedColumnIds.remove(column.id)
                } else {
                    selectedColumnIds.insert(column.id)
                }
            }
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
        HStack(spacing: 10) {
            Button {
                onCreateCategory()
            } label: {
                Label("Nueva categoría", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .fixedSize()

            Button {
                onShowAll()
            } label: {
                Label("Mostrar todas", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .disabled(hiddenCount == 0)
            .fixedSize()

            Spacer(minLength: 12)

            if let summaryColumn = summaryColumns.first {
                Button {
                    onGenerateSummary(summaryColumn.id)
                } label: {
                    Label("Síntesis pedagógica", systemImage: "apple.intelligence")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            } else {
                Button {
                    onCreateSummary()
                } label: {
                    Label("Síntesis pedagógica", systemImage: "plus.bubble")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }

            Menu {
                Toggle("Agrupar por grupos", isOn: Binding(
                    get: { groupByWorkGroupMode != "none" },
                    set: { newValue in
                        groupByWorkGroupMode = newValue ? "general" : "none"
                    }
                ))

                Divider()

                Button("Gestionar grupos") {
                    onOpenGroupManagement()
                }
            } label: {
                Label("Grupos", systemImage: "person.2")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                isHelpPopoverPresented = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isHelpPopoverPresented) {
                Text("Ocultar limpia la rejilla. Archivar retira la columna del uso diario. Eliminar borra la columna tras confirmación.")
                    .font(.callout)
                    .padding()
                    .frame(maxWidth: 260)
            }
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
