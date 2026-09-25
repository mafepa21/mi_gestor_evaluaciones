import SwiftUI
import MiGestorKit

/// Fila plana para el borrado en lote y swipe, desacoplada de los tipos KMP
/// concretos (`SchoolClass`, `Subject`, `RubricDetail`, `LearningSituation`,
/// `NotebookTab`, `NotebookColumnDefinition`, `PlanningSession`) para que
/// `CollapsibleBulkDeleteSection` no necesite genéricos ni protocolos extra.
struct DataManagementItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
}

struct NotebookTabItem: Identifiable {
    let id: String
    let classId: Int64
    let className: String
    let title: String
}

struct NotebookColumnItem: Identifiable {
    let id: String
    let classId: Int64
    let className: String
    let title: String
    let tabTitle: String?
    let evaluationId: Int64?
}

struct NotebookSummaryItem: Identifiable {
    let classId: Int64
    var id: String { String(classId) }
    let className: String
    let tabCount: Int
    let columnCount: Int
}

struct PlannerSessionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
}

/// Sección colapsable de Ajustes → Gestión de datos para un tipo de entidad:
/// header con badge de recuento, botón de expandir/colapsar, selección múltiple,
/// borrado en lote con confirmación y borrado individual por swipe.
struct CollapsibleBulkDeleteSection: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let items: [DataManagementItem]
    let emptyText: String
    let deleteWarning: String
    let onDeleteSelected: (Set<String>) async -> Void
    let onDeleteSingle: (String) async -> Void

    @State private var isExpanded: Bool = false
    @State private var isSelectionMode = false
    @State private var selectedIds = Set<String>()
    @State private var pendingSingleDelete: DataManagementItem?
    @State private var showingBatchDeleteAlert = false
    @State private var isBusy = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                if items.isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            row(for: item)
                            if item.id != items.last?.id {
                                Divider()
                                    .padding(.leading, isSelectionMode ? 32 : 0)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } label: {
            headerLabel
        }
        .alert("Eliminar \(selectedIds.count) elemento(s)", isPresented: $showingBatchDeleteAlert) {
            Button("Eliminar", role: .destructive) {
                Task {
                    isBusy = true
                    await onDeleteSelected(selectedIds)
                    selectedIds.removeAll()
                    isSelectionMode = false
                    isBusy = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(deleteWarning)
        }
        .alert(
            "Eliminar",
            isPresented: Binding(
                get: { pendingSingleDelete != nil },
                set: { if !$0 { pendingSingleDelete = nil } }
            ),
            presenting: pendingSingleDelete
        ) { item in
            Button("Eliminar", role: .destructive) {
                Task {
                    isBusy = true
                    await onDeleteSingle(item.id)
                    isBusy = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text("¿Eliminar «\(item.title)»? \(deleteWarning)")
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(items.isEmpty ? emptyText : "\(items.count) elemento\(items.count == 1 ? "" : "s")\(selectedIds.isEmpty ? "" : " · \(selectedIds.count) selec.")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isExpanded && !items.isEmpty {
                if isSelectionMode {
                    HStack(spacing: 8) {
                        Menu {
                            Button {
                                selectedIds = Set(items.map(\.id))
                            } label: {
                                Label("Seleccionar todo (\(items.count))", systemImage: "checkmark.circle")
                            }

                            Button {
                                selectedIds.removeAll()
                            } label: {
                                Label("Deseleccionar todo", systemImage: "circle")
                            }

                            Button {
                                selectedIds = Set(items.map(\.id)).subtracting(selectedIds)
                            } label: {
                                Label("Invertir selección", systemImage: "arrow.triangle.2.circlepath")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            showingBatchDeleteAlert = true
                        } label: {
                            Text("Eliminar (\(selectedIds.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .disabled(selectedIds.isEmpty || isBusy)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("Cancelar") {
                            withAnimation {
                                isSelectionMode = false
                                selectedIds.removeAll()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Seleccionar") {
                        withAnimation {
                            isSelectionMode = true
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func row(for item: DataManagementItem) -> some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selectedIds.contains(item.id) ? accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelectionMode else { return }
            if selectedIds.contains(item.id) {
                selectedIds.remove(item.id)
            } else {
                selectedIds.insert(item.id)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelectionMode {
                Button(role: .destructive) {
                    pendingSingleDelete = item
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            }
        }
    }
}

/// Sección especializada para Columnas del Cuaderno:
/// permite filtrar por curso y pestaña, buscar en tiempo real,
/// atajos de selección rápida (visibles, ninguna, invertir, por curso)
/// y borrado masivo seguro optimizado.
struct NotebookColumnsBulkDeleteSection: View {
    let columns: [NotebookColumnItem]
    let classes: [SchoolClass]
    let onDeleteSelected: (Set<String>) async -> Void
    let onDeleteSingle: (String) async -> Void

    @State private var isExpanded: Bool = false
    @State private var isSelectionMode = false
    @State private var selectedIds = Set<String>()
    @State private var selectedClassId: Int64? = nil
    @State private var selectedTabTitle: String? = nil
    @State private var searchText = ""
    @State private var showingBatchDeleteAlert = false
    @State private var pendingSingleDelete: NotebookColumnItem?
    @State private var isBusy = false

    private var classesWithColumns: [SchoolClass] {
        classes.filter { cls in columns.contains(where: { $0.classId == cls.id }) }
    }

    private var availableTabsForSelectedClass: [String] {
        guard let selectedClassId else { return [] }
        let tabs = columns.filter { $0.classId == selectedClassId }.compactMap(\.tabTitle)
        return Array(Set(tabs)).sorted()
    }

    private var selectedClassTitle: String {
        if let selectedClassId, let match = classes.first(where: { $0.id == selectedClassId }) {
            return match.name
        }
        return "Todos los cursos"
    }

    private var filteredColumns: [NotebookColumnItem] {
        columns.filter { col in
            if let selectedClassId, col.classId != selectedClassId {
                return false
            }
            if let selectedTabTitle, col.tabTitle != selectedTabTitle {
                return false
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let matchTitle = col.title.localizedCaseInsensitiveContains(query)
                let matchTab = col.tabTitle?.localizedCaseInsensitiveContains(query) ?? false
                let matchClass = col.className.localizedCaseInsensitiveContains(query)
                return matchTitle || matchTab || matchClass
            }
            return true
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 12) {
                if !columns.isEmpty {
                    filterAndSearchToolbar
                }

                if filteredColumns.isEmpty {
                    Text(columns.isEmpty ? "No hay columnas de evaluación creadas." : "Ninguna columna coincide con el filtro o búsqueda.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if selectedClassId == nil && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    groupedByCourseList
                } else {
                    flatFilteredList
                }
            }
            .padding(.top, 4)
        } label: {
            headerLabel
        }
        .alert("Eliminar \(selectedIds.count) columna(s)", isPresented: $showingBatchDeleteAlert) {
            Button("Eliminar", role: .destructive) {
                Task {
                    isBusy = true
                    await onDeleteSelected(selectedIds)
                    selectedIds.removeAll()
                    isSelectionMode = false
                    isBusy = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán las columnas de evaluación seleccionadas y todas las calificaciones registradas en ellas. Esta acción no se puede deshacer.")
        }
        .alert(
            "Eliminar columna",
            isPresented: Binding(
                get: { pendingSingleDelete != nil },
                set: { if !$0 { pendingSingleDelete = nil } }
            ),
            presenting: pendingSingleDelete
        ) { item in
            Button("Eliminar", role: .destructive) {
                Task {
                    isBusy = true
                    await onDeleteSingle(item.id)
                    isBusy = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text("¿Eliminar «\(item.title)» de \(item.className)? Se eliminarán las calificaciones registradas en ella. Esta acción no se puede deshacer.")
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Columnas del cuaderno")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                let countText = columns.isEmpty ? "No hay columnas de evaluación creadas." : "\(columns.count) elemento\(columns.count == 1 ? "" : "s")\(filteredColumns.count != columns.count ? " (\(filteredColumns.count) visibles)" : "")\(selectedIds.isEmpty ? "" : " · \(selectedIds.count) selec.")"
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isExpanded && !columns.isEmpty {
                if isSelectionMode {
                    HStack(spacing: 8) {
                        Button(role: .destructive) {
                            showingBatchDeleteAlert = true
                        } label: {
                            Text("Eliminar (\(selectedIds.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .disabled(selectedIds.isEmpty || isBusy)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("Cancelar") {
                            withAnimation {
                                isSelectionMode = false
                                selectedIds.removeAll()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Seleccionar") {
                        withAnimation {
                            isSelectionMode = true
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var filterAndSearchToolbar: some View {
        VStack(spacing: 8) {
            // Selectores de Curso y Pestaña
            HStack(spacing: 8) {
                Menu {
                    Button {
                        selectedClassId = nil
                        selectedTabTitle = nil
                    } label: {
                        HStack {
                            Text("Todos los cursos (\(columns.count))")
                            if selectedClassId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(classesWithColumns, id: \.id) { cls in
                        let count = columns.filter { $0.classId == cls.id }.count
                        Button {
                            selectedClassId = cls.id
                            selectedTabTitle = nil
                        } label: {
                            HStack {
                                Text("\(cls.name) (\(count))")
                                if selectedClassId == cls.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(selectedClassTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }

                if selectedClassId != nil, !availableTabsForSelectedClass.isEmpty {
                    Menu {
                        Button {
                            selectedTabTitle = nil
                        } label: {
                            HStack {
                                Text("Todas las pestañas")
                                if selectedTabTitle == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Divider()

                        ForEach(availableTabsForSelectedClass, id: \.self) { tab in
                            Button {
                                selectedTabTitle = tab
                            } label: {
                                HStack {
                                    Text(tab)
                                    if selectedTabTitle == tab {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .semibold))
                            Text(selectedTabTitle ?? "Todas las pestañas")
                                .font(.subheadline)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                }

                Spacer()
            }

            // Barra de búsqueda rápida
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("Buscar columna por nombre o pestaña...", text: $searchText)
                    .font(.subheadline)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Atajos de selección rápida (cuando está en modo selección)
            if isSelectionMode {
                HStack(spacing: 8) {
                    Button {
                        selectAllVisible()
                    } label: {
                        Text("Todas (\(filteredColumns.count))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)

                    Button {
                        deselectAllVisible()
                    } label: {
                        Text("Ninguna")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        invertSelectionVisible()
                    } label: {
                        Text("Invertir")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Menu {
                        ForEach(classesWithColumns, id: \.id) { cls in
                            let count = columns.filter { $0.classId == cls.id }.count
                            Button("Marcar \(cls.name) (\(count))") {
                                selectByClass(classId: cls.id)
                            }
                        }
                        Divider()
                        ForEach(classesWithColumns, id: \.id) { cls in
                            Button("Desmarcar \(cls.name)") {
                                deselectByClass(classId: cls.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                            Text("Por curso")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
        }
    }

    private var groupedByCourseList: some View {
        let grouped = Dictionary(grouping: filteredColumns, by: \.classId)
        let orderedClassIds = classes.map(\.id).filter { grouped[$0] != nil }

        return VStack(spacing: 12) {
            ForEach(orderedClassIds, id: \.self) { classId in
                let classCols = grouped[classId] ?? []
                let className = classCols.first?.className ?? "Curso"
                let allSelected = !classCols.isEmpty && classCols.allSatisfy { selectedIds.contains($0.id) }

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.teal)

                        Text(className)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("\(classCols.count)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())

                        Spacer()

                        if isSelectionMode {
                            Button(allSelected ? "Desmarcar grupo" : "Marcar grupo") {
                                if allSelected {
                                    deselectByClass(classId: classId)
                                } else {
                                    selectByClass(classId: classId)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.teal)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)

                    Divider()

                    ForEach(classCols) { col in
                        row(for: col, showClassName: false)
                        if col.id != classCols.last?.id {
                            Divider().padding(.leading, isSelectionMode ? 32 : 0)
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var flatFilteredList: some View {
        VStack(spacing: 0) {
            ForEach(filteredColumns) { col in
                row(for: col, showClassName: selectedClassId == nil)
                if col.id != filteredColumns.last?.id {
                    Divider().padding(.leading, isSelectionMode ? 32 : 0)
                }
            }
        }
    }

    private func row(for col: NotebookColumnItem, showClassName: Bool) -> some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: selectedIds.contains(col.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selectedIds.contains(col.id) ? Color.teal : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(col.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if showClassName {
                        Text(col.className)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let tab = col.tabTitle, !tab.isEmpty {
                        if showClassName {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(tab)
                        }
                        .font(.caption2)
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.teal.opacity(0.1))
                        .clipShape(Capsule())
                    }

                    if col.evaluationId != nil {
                        Text("Evaluación vinculada")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelectionMode else { return }
            if selectedIds.contains(col.id) {
                selectedIds.remove(col.id)
            } else {
                selectedIds.insert(col.id)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelectionMode {
                Button(role: .destructive) {
                    pendingSingleDelete = col
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            }
        }
    }

    private func selectAllVisible() {
        selectedIds.formUnion(filteredColumns.map(\.id))
    }

    private func deselectAllVisible() {
        selectedIds.subtract(filteredColumns.map(\.id))
    }

    private func invertSelectionVisible() {
        let visibleIds = Set(filteredColumns.map(\.id))
        let currentSelected = selectedIds.intersection(visibleIds)
        let currentUnselected = visibleIds.subtracting(currentSelected)
        selectedIds.subtract(visibleIds)
        selectedIds.formUnion(currentUnselected)
    }

    private func selectByClass(classId: Int64) {
        let ids = columns.filter { $0.classId == classId }.map(\.id)
        selectedIds.formUnion(ids)
    }

    private func deselectByClass(classId: Int64) {
        let ids = columns.filter { $0.classId == classId }.map(\.id)
        selectedIds.subtract(ids)
    }
}

/// Ajustes → Gestión de datos: borrado rápido y en lote organizado por áreas
/// (Estructura, Cuadernos, Planificación e Instrumentos) con secciones colapsables.
struct DataManagementSettingsView: View {
    @EnvironmentObject var bridge: KmpBridge

    @State private var learningSituations: [LearningSituation] = []
    @State private var notebookSummaries: [NotebookSummaryItem] = []
    @State private var notebookTabs: [NotebookTabItem] = []
    @State private var notebookColumns: [NotebookColumnItem] = []
    @State private var plannerSessions: [PlannerSessionItem] = []
    @State private var resultMessage: IdentifiableString?

    private var totalItemCount: Int {
        bridge.classes.count +
        bridge.subjects.count +
        notebookSummaries.map(\.columnCount).reduce(0, +) +
        notebookTabs.count +
        notebookColumns.count +
        plannerSessions.count +
        learningSituations.count +
        bridge.rubrics.count
    }

    var body: some View {
        Form {
            // Cabecera Informativa
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "trash.square.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gestión de Datos")
                            .font(.headline)
                        Text("Revisa y elimina elementos específicos creados en la aplicación. Toca sobre cada categoría para desplegar su contenido.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("\(totalItemCount) elemento(s) registrados en total.")
            }

            // 🏫 Estructura Escolar
            Section("Estructura Escolar") {
                CollapsibleBulkDeleteSection(
                    title: "Cursos",
                    systemImage: "person.3.fill",
                    accentColor: .blue,
                    items: bridge.classes.map { schoolClass in
                        DataManagementItem(
                            id: String(schoolClass.id),
                            title: schoolClass.name,
                            subtitle: subjectName(forSubjectId: schoolClass.subjectId?.int64Value)
                        )
                    },
                    emptyText: "No hay cursos creados.",
                    deleteWarning: "Se borrarán también su alumnado, asistencia, evaluaciones y notas asociadas. Esta acción no se puede deshacer.",
                    onDeleteSelected: { ids in await deleteClasses(ids) },
                    onDeleteSingle: { id in await deleteClasses([id]) }
                )

                CollapsibleBulkDeleteSection(
                    title: "Asignaturas",
                    systemImage: "books.vertical.fill",
                    accentColor: .indigo,
                    items: bridge.subjects.map { subject in
                        DataManagementItem(id: String(subject.id), title: subject.name, subtitle: subject.code)
                    },
                    emptyText: "No hay asignaturas creadas.",
                    deleteWarning: "Los cursos que la usan quedarán sin asignatura asignada. Esta acción no se puede deshacer.",
                    onDeleteSelected: { ids in await deleteSubjects(ids) },
                    onDeleteSingle: { id in await deleteSubjects([id]) }
                )
            }

            // 📓 Cuaderno de Evaluación
            Section("Cuaderno de Evaluación") {
                CollapsibleBulkDeleteSection(
                    title: "Cuadernos por curso (Resetear)",
                    systemImage: "square.grid.3x3.fill",
                    accentColor: .purple,
                    items: notebookSummaries.map { s in
                        DataManagementItem(
                            id: s.id,
                            title: s.className,
                            subtitle: "\(s.tabCount) pestaña(s) · \(s.columnCount) columna(s)"
                        )
                    },
                    emptyText: "No hay datos de cuadernos.",
                    deleteWarning: "Se vaciarán todas las pestañas, columnas y notas asociadas a este curso, manteniendo intacto el curso y la lista de alumnos.",
                    onDeleteSelected: { ids in await deleteNotebooks(ids) },
                    onDeleteSingle: { id in await deleteNotebooks([id]) }
                )

                CollapsibleBulkDeleteSection(
                    title: "Pestañas de cuaderno",
                    systemImage: "folder.fill",
                    accentColor: .cyan,
                    items: notebookTabs.map { tab in
                        DataManagementItem(
                            id: tab.id,
                            title: tab.title,
                            subtitle: "Curso: \(tab.className)"
                        )
                    },
                    emptyText: "No hay pestañas de cuaderno creadas.",
                    deleteWarning: "Se eliminará la pestaña seleccionada y su configuración en el cuaderno. Esta acción no se puede deshacer.",
                    onDeleteSelected: { ids in await deleteTabs(ids) },
                    onDeleteSingle: { id in await deleteTabs([id]) }
                )

                NotebookColumnsBulkDeleteSection(
                    columns: notebookColumns,
                    classes: bridge.classes,
                    onDeleteSelected: { ids in await deleteColumns(ids) },
                    onDeleteSingle: { id in await deleteColumns([id]) }
                )
            }

            // 📅 Planificación
            Section("Planificación") {
                CollapsibleBulkDeleteSection(
                    title: "Sesiones planificadas (Planner)",
                    systemImage: "calendar.badge.clock",
                    accentColor: .orange,
                    items: plannerSessions.map { s in
                        DataManagementItem(
                            id: s.id,
                            title: s.title,
                            subtitle: s.subtitle
                        )
                    },
                    emptyText: "No hay sesiones planificadas.",
                    deleteWarning: "Se eliminará la sesión del planificador y su diario asociado. Esta acción no se puede deshacer.",
                    onDeleteSelected: { ids in await deletePlannerSessions(ids) },
                    onDeleteSingle: { id in await deletePlannerSessions([id]) }
                )

                CollapsibleBulkDeleteSection(
                    title: "Situaciones de aprendizaje",
                    systemImage: "doc.text.fill",
                    accentColor: .mint,
                    items: learningSituations.map { situation in
                        DataManagementItem(id: String(situation.id), title: situation.title, subtitle: situationSubtitle(for: situation))
                    },
                    emptyText: "No hay situaciones de aprendizaje creadas.",
                    deleteWarning: "Esta acción no se puede deshacer.",
                    onDeleteSelected: { ids in await deleteSituations(ids) },
                    onDeleteSingle: { id in await deleteSituations([id]) }
                )
            }

            // 📝 Instrumentos
            Section("Instrumentos de Evaluación") {
                CollapsibleBulkDeleteSection(
                    title: "Rúbricas",
                    systemImage: "list.bullet.rectangle.fill",
                    accentColor: .pink,
                    items: bridge.rubrics.map { detail in
                        DataManagementItem(id: String(detail.rubric.id), title: detail.rubric.name, subtitle: rubricSubtitle(for: detail.rubric.id))
                    },
                    emptyText: "No hay rúbricas creadas.",
                    deleteWarning: "Las evaluaciones que la usan quedarán sin rúbrica asignada. Esta acción no se puede deshacer.",
                    onDeleteSelected: { ids in await deleteRubrics(ids) },
                    onDeleteSingle: { id in await deleteRubrics([id]) }
                )
            }
        }
        .navigationTitle("Gestión de datos")
        .task {
            await bridge.ensureClassesLoaded()
            try? await bridge.refreshRubrics()
            await reloadSituations()
            await reloadNotebookData()
            await reloadPlannerSessions()
        }
        .alert(item: $resultMessage) { message in
            Alert(title: Text("Aviso"), message: Text(message.value), dismissButton: .default(Text("OK")))
        }
    }

    private func subjectName(forSubjectId subjectId: Int64?) -> String {
        guard let subjectId, let subject = bridge.subjects.first(where: { $0.id == subjectId }) else {
            return "Sin asignatura"
        }
        return subject.name
    }

    private func rubricSubtitle(for rubricId: Int64) -> String {
        let linkedCount = bridge.rubricClassLinks[rubricId]?.count ?? 0
        return linkedCount == 0 ? "Sin vincular a ningún curso" : "Vinculada a \(linkedCount) curso(s)"
    }

    private func situationSubtitle(for situation: LearningSituation) -> String? {
        let parts = [situation.courseLabel, situation.subjectLabel].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func reloadSituations() async {
        learningSituations = (try? await bridge.learningSituations()) ?? []
    }

    private func reloadNotebookData() async {
        var summaries: [NotebookSummaryItem] = []
        var tabItems: [NotebookTabItem] = []
        var colItems: [NotebookColumnItem] = []

        for schoolClass in bridge.classes {
            let classId = schoolClass.id
            let className = schoolClass.name

            let tabs = (try? await bridge.fetchNotebookTabs(for: classId)) ?? []
            let columns = (try? await bridge.fetchNotebookColumns(for: classId)) ?? []

            summaries.append(NotebookSummaryItem(
                classId: classId,
                className: className,
                tabCount: tabs.count,
                columnCount: columns.count
            ))

            for tab in tabs {
                tabItems.append(NotebookTabItem(
                    id: tab.id,
                    classId: classId,
                    className: className,
                    title: tab.title
                ))
            }

            let tabMap = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.title) })
            for col in columns {
                let tabTitle = col.categoryId.flatMap { tabMap[$0] }
                colItems.append(NotebookColumnItem(
                    id: col.id,
                    classId: classId,
                    className: className,
                    title: col.title,
                    tabTitle: tabTitle,
                    evaluationId: col.evaluationId?.int64Value
                ))
            }
        }

        self.notebookSummaries = summaries
        self.notebookTabs = tabItems
        self.notebookColumns = colItems
    }

    private func reloadPlannerSessions() async {
        let sessions = (try? await bridge.plannerListAllSessions()) ?? []
        self.plannerSessions = sessions.map { session in
            let groupLabel = session.groupName
            let unitLabel = session.teachingUnitName
            let title = "\(groupLabel) · \(unitLabel)"

            var subParts: [String] = []
            if session.weekNumber > 0 {
                subParts.append("Semana \(session.weekNumber)")
            }
            if let startTime = session.startTime, !startTime.isEmpty {
                subParts.append(startTime)
            }
            let subtitle = subParts.isEmpty ? nil : subParts.joined(separator: " · ")

            return PlannerSessionItem(
                id: String(session.id),
                title: title,
                subtitle: subtitle
            )
        }
    }

    private func deleteClasses(_ ids: Set<String>) async {
        let numIds = Set(ids.compactMap { Int64($0) })
        var failed = 0
        for id in numIds {
            do {
                try await bridge.deleteClass(id: id)
            } catch {
                failed += 1
            }
        }
        await reloadNotebookData()
        await reloadPlannerSessions()
        reportResult(deleted: numIds.count - failed, failed: failed, entityPlural: "cursos")
    }

    private func deleteSubjects(_ ids: Set<String>) async {
        let numIds = Set(ids.compactMap { Int64($0) })
        var failed = 0
        for id in numIds {
            do {
                try await bridge.deleteSubject(id: id)
            } catch {
                failed += 1
            }
        }
        reportResult(deleted: ids.count - failed, failed: failed, entityPlural: "asignaturas")
    }

    private func deleteNotebooks(_ ids: Set<String>) async {
        let numIds = Set(ids.compactMap { Int64($0) })
        var failed = 0
        for classId in numIds {
            do {
                try await bridge.clearNotebookForClass(classId: classId)
            } catch {
                failed += 1
            }
        }
        await reloadNotebookData()
        reportResult(deleted: numIds.count - failed, failed: failed, entityPlural: "cuadernos de notas")
    }

    private func deleteTabs(_ ids: Set<String>) async {
        for id in ids {
            bridge.deleteTab(id: id)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        await reloadNotebookData()
    }

    private func deleteColumns(_ ids: Set<String>) async {
        let itemsToDelete = ids.compactMap { id -> (id: String, evaluationId: Int64?)? in
            guard let col = notebookColumns.first(where: { $0.id == id }) else { return nil }
            return (id: col.id, evaluationId: col.evaluationId)
        }
        bridge.deleteColumns(idsAndEvalIds: itemsToDelete)
        try? await Task.sleep(nanoseconds: 150_000_000)
        await reloadNotebookData()
    }

    private func deletePlannerSessions(_ ids: Set<String>) async {
        let numIds = Set(ids.compactMap { Int64($0) })
        var failed = 0
        for id in numIds {
            do {
                try await bridge.plannerDeleteSession(sessionId: id)
            } catch {
                failed += 1
            }
        }
        await reloadPlannerSessions()
        reportResult(deleted: numIds.count - failed, failed: failed, entityPlural: "sesiones planificadas")
    }

    private func deleteRubrics(_ ids: Set<String>) async {
        let numIds = Set(ids.compactMap { Int64($0) })
        for id in numIds {
            bridge.deleteRubric(id: id)
        }
        try? await bridge.refreshRubrics()
        let stillPresent = Set(bridge.rubrics.map(\.rubric.id)).intersection(numIds)
        reportResult(deleted: numIds.count - stillPresent.count, failed: stillPresent.count, entityPlural: "rúbricas")
    }

    private func deleteSituations(_ ids: Set<String>) async {
        let numIds = Set(ids.compactMap { Int64($0) })
        var failed = 0
        for id in numIds {
            do {
                try await bridge.deleteLearningSituation(id: id)
            } catch {
                failed += 1
            }
        }
        await reloadSituations()
        reportResult(deleted: numIds.count - failed, failed: failed, entityPlural: "situaciones de aprendizaje")
    }

    private func reportResult(deleted: Int, failed: Int, entityPlural: String) {
        guard failed > 0 else { return }
        let total = deleted + failed
        if total == 1 {
            resultMessage = IdentifiableString(value: "No se pudo eliminar de \(entityPlural). Inténtalo de nuevo.")
        } else {
            resultMessage = IdentifiableString(value: "Se eliminaron \(deleted) de \(total) \(entityPlural). \(failed) no se pudieron eliminar.")
        }
    }
}
