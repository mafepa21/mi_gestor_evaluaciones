import SwiftUI
import MiGestorKit

private struct NotebookInspectorSelection: Identifiable, Hashable {
    let studentId: Int64
    let columnId: String

    var id: String { "\(studentId)|\(columnId)" }
}

private struct NotebookTableRow: Identifiable {
    let student: Student
    let row: NotebookRow
    let groupName: String

    var id: Int64 { student.id }
}

private enum NotebookFixedColumn: String, Identifiable, CaseIterable {
    case photo
    case name
    case group
    case followUp
    case attendance
    case average

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Foto"
        case .name: return "Nombre"
        case .group: return "Grupo"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .average: return "Media"
        }
    }

    var subtitle: String {
        switch self {
        case .photo: return "Alumno"
        case .name: return "Alumno"
        case .group: return "Contexto"
        case .followUp: return "Estado"
        case .attendance: return "Resumen"
        case .average: return "Promedio"
        }
    }

    var width: CGFloat {
        switch self {
        case .photo: return 82
        case .name: return 180
        case .group: return 110
        case .followUp: return 120
        case .attendance: return 120
        case .average: return 110
        }
    }
}

private enum NotebookDisplaySegment: Identifiable {
    case fixed(NotebookFixedColumn)
    case column(NotebookColumnDefinition)
    case collapsedCategory(NotebookColumnCategory, [NotebookColumnDefinition])

    var id: String {
        switch self {
        case .fixed(let fixed):
            return "fixed_\(fixed.rawValue)"
        case .column(let column):
            return "column_\(column.id)"
        case .collapsedCategory(let category, _):
            return "collapsed_\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .fixed(let fixed):
            return fixed.title
        case .column(let column):
            return column.title
        case .collapsedCategory(let category, _):
            return category.name
        }
    }
}

private enum NotebookViewPreset: String, CaseIterable, Identifiable {
    case all
    case evaluation
    case followUp
    case attendance
    case extras
    case physicalEducation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Vista completa"
        case .evaluation: return "Vista evaluación"
        case .followUp: return "Vista seguimiento"
        case .attendance: return "Vista asistencia"
        case .extras: return "Vista extras"
        case .physicalEducation: return "Vista EF"
        }
    }
}

struct NotebookModuleView: View {
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State private var showAddColumnSheet = false
    @State private var searchText = ""
    @State private var selectedGroupId: Int64? = nil
    @State private var inspectorSelection: NotebookInspectorSelection? = nil
    @State private var inspectorNoteDraft = ""
    @State private var viewPreset: NotebookViewPreset = .all
    @State private var isInspectorPresented = false

    var body: some View {
        Group {
            if let data = bridge.notebookState as? NotebookUiStateData {
                centerPanel(data: data)
                    .sheet(isPresented: $showAddColumnSheet) {
                        AddColumnSheet(bridge: bridge)
                    }
                    .onAppear {
                        syncToolbarState(data: data)
                    }
                    .onChange(of: toolbarStateKey(data: data)) { _ in
                        syncToolbarState(data: data)
                    }
            } else if bridge.notebookState is NotebookUiStateLoading {
                NotebookStateCard(
                    systemImage: "tablecells",
                    title: "Cargando cuaderno",
                    message: "Estamos preparando el cuaderno iPad."
                ) {
                    ProgressView()
                }
            } else if let error = bridge.notebookState as? NotebookUiStateError {
                NotebookStateCard(
                    systemImage: "exclamationmark.triangle",
                    title: "No se pudo cargar el cuaderno",
                    message: error.message,
                    tint: NotebookStyle.warningTint
                )
            } else {
                NotebookStateCard(
                    systemImage: "tablecells",
                    title: "Sin datos del cuaderno",
                    message: "Selecciona una clase para empezar."
                )
            }
        }
        .background(EvaluationBackdrop())
        .task {
            if let selectedClassId,
               bridge.notebookViewModel.currentClassId?.int64Value != selectedClassId {
                bridge.selectClass(id: selectedClassId)
            } else if selectedClassId == nil,
                      let notebookClassId = bridge.notebookViewModel.currentClassId?.int64Value {
                self.selectedClassId = notebookClassId
            }
        }
        .onChange(of: selectedClassId) { newValue in
            guard let newValue else { return }
            guard bridge.notebookViewModel.currentClassId?.int64Value != newValue else { return }
            selectNotebookClass(newValue)
        }
        .onChange(of: inspectorSelection) { _ in
            syncInspectorDraft()
            if inspectorSelection == nil {
                isInspectorPresented = false
            }
        }
        .onChange(of: isInspectorPresented) { _ in
            if let data = bridge.notebookState as? NotebookUiStateData {
                syncToolbarState(data: data)
            }
        }
        .onDisappear {
            layoutState.clearNotebookToolbar()
        }
    }

    private func centerPanel(data: NotebookUiStateData) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerBar(data: data)
                spreadsheetContent(data: data)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isInspectorPresented {
                Divider().opacity(0.16)
                inspectorPanel(data: data)
                    .frame(width: 360)
                    .background(NotebookStyle.surfaceMuted)
            }
        }
        .background(EvaluationBackdrop())
    }

    private func headerBar(data: NotebookUiStateData) -> some View {
        NotebookSurface(cornerRadius: 0, fill: NotebookStyle.surfaceMuted, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cuaderno · \(activeClassLabel)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                        Text(selectedGroupId.flatMap { groupName(for: $0, in: data) } ?? "Grupo completo")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar alumno", text: $searchText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(NotebookStyle.surface)
                    )

                    Menu {
                        ForEach(sortedClasses, id: \.id) { schoolClass in
                            Button {
                                selectNotebookClass(schoolClass.id)
                            } label: {
                                HStack {
                                    Text(classLabel(for: schoolClass))
                                    if schoolClass.id == currentClass?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Curso", systemImage: "graduationcap")
                    }

                    Menu {
                        Button("Todo el grupo") { selectedGroupId = nil }
                        ForEach(groupedRows(data: data), id: \.id) { group in
                            Button(group.name) { selectedGroupId = group.id }
                        }
                    } label: {
                        Label("Filtro", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Menu {
                        ForEach(relevantCategories(data: data), id: \.id) { category in
                            Button(category.isCollapsed ? "Mostrar \(category.name)" : "Plegar \(category.name)") {
                                bridge.toggleColumnCategory(id: category.id, collapsed: !category.isCollapsed)
                            }
                        }
                        Divider()
                        ForEach(managedColumns(data: data), id: \.id) { column in
                            Button(column.isHidden ? "Mostrar \(column.title)" : "Ocultar \(column.title)") {
                                toggleColumnVisibility(column)
                            }
                        }
                    } label: {
                        Label("Columnas", systemImage: "square.grid.3x3.topleft.filled")
                    }

                    Menu {
                        ForEach(NotebookViewPreset.allCases) { preset in
                            Button {
                                viewPreset = preset
                            } label: {
                                HStack {
                                    Text(preset.title)
                                    if viewPreset == preset {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(viewPreset.title, systemImage: "sidebar.right")
                    }

                    ShareLink(item: exportText(data: data)) {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func spreadsheetContent(data: NotebookUiStateData) -> some View {
        let rows = filteredRows(data: data)
        let segments = displaySegments(data: data)

        if rows.isEmpty {
            NotebookStateCard(
                systemImage: "person.3.sequence",
                title: "Sin alumnos visibles",
                message: "Ajusta la búsqueda o el filtro de grupo para ver filas del cuaderno."
            )
        } else {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        ForEach(segments, id: \.id) { segment in
                            headerChip(for: segment, data: data)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(NotebookStyle.surface.opacity(0.92))

                    LazyVStack(spacing: 0) {
                        ForEach(rows) { item in
                            notebookRowView(item: item, data: data, segments: segments)
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func inspectorPanel(data: NotebookUiStateData) -> some View {
        Group {
            if let selection = inspectorSelection,
               let item = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }),
               let column = data.sheet.columns.first(where: { $0.id == selection.columnId }) {
                let persistedCell = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Inspector")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                        inspectorInfoRow("Alumno", value: "\(item.student.firstName) \(item.student.lastName)")
                        inspectorInfoRow("Columna", value: column.title)
                        inspectorInfoRow("Valor", value: displayValue(for: item, column: column))
                        inspectorInfoRow("Categoría", value: categoryTitle(for: column, data: data))
                        inspectorInfoRow("Peso", value: String(format: "%.1f", column.weight))
                        inspectorInfoRow("Cuenta para media", value: column.countsTowardAverage ? "Sí" : "No")
                        inspectorInfoRow("Tipo", value: "\(column.instrumentKind.name) · \(column.inputKind.name)")
                        inspectorInfoRow("Fecha", value: formattedDate(column.dateEpochMs?.int64Value))
                        inspectorInfoRow("Criterio asociado", value: column.competencyCriteriaIds.isEmpty ? "Sin criterio" : column.competencyCriteriaIds.map(String.init).joined(separator: ", "))
                        inspectorInfoRow("Evidencia", value: evidenceLabel(for: persistedCell))
                        inspectorInfoRow("Evaluación", value: evaluationTitle(for: column))
                        inspectorInfoRow("Rúbrica", value: rubricTitle(for: column))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Accesos rápidos")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))

                            HStack(spacing: 10) {
                                Button("Abrir alumno") {
                                    selectedStudentId = item.student.id
                                    isInspectorPresented = false
                                    inspectorSelection = nil
                                    onOpenModule(.students, currentClass?.id, item.student.id)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Ir a evaluación") {
                                    isInspectorPresented = false
                                    inspectorSelection = nil
                                    onOpenModule(.evaluationHub, currentClass?.id, item.student.id)
                                }
                                .buttonStyle(.bordered)
                                .disabled(column.evaluationId == nil)

                                Button("Ver rúbrica") {
                                    onOpenModule(
                                        column.categoryKind == .physicalEducation ? .peRubrics : .rubrics,
                                        currentClass?.id,
                                        item.student.id
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(column.rubricId == nil)
                            }

                            if column.categoryKind == .attendance {
                                Button("Abrir asistencia") {
                                    selectedStudentId = item.student.id
                                    isInspectorPresented = false
                                    inspectorSelection = nil
                                    onOpenModule(.attendance, currentClass?.id, item.student.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comentario")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            TextEditor(text: $inspectorNoteDraft)
                                .frame(minHeight: 140)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(NotebookStyle.surface)
                                )
                            Button("Guardar comentario") {
                                bridge.saveNotebookCellAnnotation(studentId: item.student.id, columnId: column.id, note: inspectorNoteDraft)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(24)
                }
                .background(EvaluationBackdrop())
            } else {
                NotebookStateCard(
                    systemImage: "sidebar.right",
                    title: "Inspector contextual",
                    message: "Selecciona una celda para ver alumno, columna, comentario, evidencia y peso."
                )
            }
        }
    }

    private var currentClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == bridge.notebookViewModel.currentClassId?.int64Value ?? 0 })
    }

    private var sortedClasses: [SchoolClass] {
        bridge.classes.sorted {
            if $0.course != $1.course { return $0.course < $1.course }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var activeClassLabel: String {
        guard let currentClass else { return "Seleccionar clase" }
        return classLabel(for: currentClass)
    }

    private func classLabel(for schoolClass: SchoolClass) -> String {
        "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private func selectNotebookClass(_ classId: Int64) {
        guard bridge.notebookViewModel.currentClassId?.int64Value != classId else { return }
        selectedGroupId = nil
        isInspectorPresented = false
        inspectorSelection = nil
        inspectorNoteDraft = ""
        searchText = ""
        selectedClassId = classId
        bridge.selectClass(id: classId)
    }

    private func syncToolbarState(data: NotebookUiStateData) {
        layoutState.configureNotebookToolbar(
            inspectorAvailable: inspectorSelection != nil || !managedColumns(data: data).isEmpty,
            isInspectorPresented: isInspectorPresented,
            addColumnAvailable: true,
            onToggleInspector: {
                if inspectorSelection == nil {
                    openInspectorForSelection(data)
                }
                if inspectorSelection != nil {
                    isInspectorPresented.toggle()
                }
            },
            onAddColumn: {
                showAddColumnSheet = true
            }
        )
    }

    private func toolbarStateKey(data: NotebookUiStateData) -> String {
        let classKey = currentClass?.id ?? -1
        let groupKey = selectedGroupId ?? -1
        let inspectorKey = inspectorSelection?.id ?? "none"
        return "\(classKey)|\(groupKey)|\(managedColumns(data: data).count)|\(filteredRows(data: data).count)|\(inspectorKey)|\(isInspectorPresented)"
    }

    private func openInspectorForSelection(_ data: NotebookUiStateData) {
        if inspectorSelection != nil { return }
        if let firstColumn = managedColumns(data: data).first,
           let firstRow = filteredRows(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: firstRow.student.id, columnId: firstColumn.id)
        }
    }

    private func openInspectorForStudent(_ studentId: Int64, data: NotebookUiStateData) {
        if let existingSelection = inspectorSelection,
           existingSelection.studentId == studentId,
           !existingSelection.columnId.isEmpty {
            inspectorSelection = existingSelection
        } else if let firstColumn = managedColumns(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: firstColumn.id)
        }
        isInspectorPresented = true
    }

    private func evaluationTitle(for column: NotebookColumnDefinition) -> String {
        guard let evaluationId = column.evaluationId?.int64Value else { return "Sin evaluación asociada" }
        if let schoolClass = currentClass,
           let evaluation = bridge.evaluationsInClass.first(where: { $0.id == evaluationId }),
           !bridge.evaluationsInClass.isEmpty {
            return "\(evaluation.name) · \(schoolClass.name)"
        }
        return "Evaluación #\(evaluationId)"
    }

    private func rubricTitle(for column: NotebookColumnDefinition) -> String {
        guard let rubricId = column.rubricId?.int64Value else { return "Sin rúbrica asociada" }
        return bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? "Rúbrica #\(rubricId)"
    }

    private func filteredRows(data: NotebookUiStateData) -> [NotebookTableRow] {
        let rows = data.sheet.groupedRowsFor(tabId: bridge.selectedNotebookTabId).flatMap { section in
            let groupName = section.group?.name ?? "Sin grupo"
            return section.rows.map { NotebookTableRow(student: $0.student, row: $0, groupName: groupName) }
        }

        return rows.filter { item in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || "\(item.student.firstName) \(item.student.lastName)".localizedCaseInsensitiveContains(searchText)
            let matchesGroup = selectedGroupId == nil || groupId(for: item.student.id, in: data) == selectedGroupId
            return matchesSearch && matchesGroup
        }
    }

    private func notebookRowView(item: NotebookTableRow, data: NotebookUiStateData, segments: [NotebookDisplaySegment]) -> some View {
        HStack(spacing: 12) {
            ForEach(segments, id: \.id) { segment in
                rowCell(for: segment, item: item, data: data)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func groupedRows(data: NotebookUiStateData) -> [NotebookWorkGroup] {
        data.sheet.workGroups.sorted { $0.order < $1.order }
    }

    private func groupId(for studentId: Int64, in data: NotebookUiStateData) -> Int64? {
        data.sheet.workGroupMembers.first(where: { $0.studentId == studentId })?.groupId
    }

    private func groupName(for groupId: Int64, in data: NotebookUiStateData) -> String? {
        data.sheet.workGroups.first(where: { $0.id == groupId })?.name
    }

    private func memberCount(_ groupId: Int64, in data: NotebookUiStateData) -> Int {
        data.sheet.workGroupMembers.filter { $0.groupId == groupId }.count
    }

    private func columns(in category: NotebookColumnCategory, data: NotebookUiStateData, includeHidden: Bool = false) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { $0.categoryId == category.id }
            .filter { includeHidden || !$0.isHidden }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }
    }

    private func managedColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        data.sheet.columns
            .filter { columnMatchesCurrentView($0) }
            .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func relevantCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        data.sheet.columnCategories
            .sorted { $0.order < $1.order }
            .filter { !columns(in: $0, data: data, includeHidden: true).isEmpty }
    }

    private func displaySegments(data: NotebookUiStateData) -> [NotebookDisplaySegment] {
        var segments = fixedSegmentsForCurrentView().map(NotebookDisplaySegment.fixed)
        let categoriesById = Dictionary(uniqueKeysWithValues: data.sheet.columnCategories.map { ($0.id, $0) })
        let orderedColumns = data.sheet.columns
            .filter { !$0.isHidden }
            .filter { columnMatchesCurrentView($0) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }

        var emittedCollapsedCategories = Set<String>()
        for column in orderedColumns {
            guard let categoryId = column.categoryId, let category = categoriesById[categoryId] else {
                segments.append(.column(column))
                continue
            }
            if category.isCollapsed {
                if emittedCollapsedCategories.insert(category.id).inserted {
                    let categoryColumns = columns(in: category, data: data)
                    if !categoryColumns.isEmpty {
                        segments.append(.collapsedCategory(category, categoryColumns))
                    }
                }
            } else {
                segments.append(.column(column))
            }
        }
        return segments
    }

    private func fixedSegmentsForCurrentView() -> [NotebookFixedColumn] {
        switch viewPreset {
        case .all:
            return [.photo, .name, .group, .followUp, .attendance, .average]
        case .evaluation:
            return [.photo, .name, .average]
        case .followUp:
            return [.photo, .name, .group, .followUp]
        case .attendance:
            return [.photo, .name, .group, .attendance]
        case .extras:
            return [.photo, .name]
        case .physicalEducation:
            return [.photo, .name]
        }
    }

    private func columnMatchesCurrentView(_ column: NotebookColumnDefinition) -> Bool {
        switch viewPreset {
        case .all:
            return true
        case .evaluation:
            return column.categoryKind == .evaluation
        case .followUp:
            return column.categoryKind == .followUp
        case .attendance:
            return column.categoryKind == .attendance
        case .extras:
            return column.categoryKind == .extras
        case .physicalEducation:
            return column.categoryKind == .physicalEducation
        }
    }

    private func toggleColumnVisibility(_ column: NotebookColumnDefinition) {
        bridge.saveColumn(column: NotebookColumnDefinition(
            id: column.id,
            title: column.title,
            type: column.type,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            evaluationId: column.evaluationId,
            rubricId: column.rubricId,
            formula: column.formula,
            weight: column.weight,
            dateEpochMs: column.dateEpochMs,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds,
            scaleKind: column.scaleKind,
            tabIds: column.tabIds,
            sessions: column.sessions,
            sharedAcrossTabs: column.sharedAcrossTabs,
            colorHex: column.colorHex,
            iconName: column.iconName,
            order: column.order,
            widthDp: column.widthDp,
            categoryId: column.categoryId,
            ordinalLevels: column.ordinalLevels,
            availableIcons: column.availableIcons,
            countsTowardAverage: column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: !column.isHidden,
            visibility: column.visibility,
            isLocked: column.isLocked,
            isTemplate: column.isTemplate,
            trace: column.trace
        ))
    }

    private func exportText(data: NotebookUiStateData) -> String {
        let segments = displaySegments(data: data)
        let header = segments.map(exportHeaderTitle(for:)).joined(separator: "\t")

        let body = filteredRows(data: data).map { item in
            segments.map { exportValue(for: $0, item: item) }.joined(separator: "\t")
        }

        return ([header] + body).joined(separator: "\n")
    }

    private func exportHeaderTitle(for segment: NotebookDisplaySegment) -> String {
        switch segment {
        case .fixed(let fixed):
            return fixed.title
        case .column(let column):
            return column.title
        case .collapsedCategory(let category, _):
            return category.name
        }
    }

    private func exportValue(for segment: NotebookDisplaySegment, item: NotebookTableRow) -> String {
        switch segment {
        case .fixed(let fixed):
            switch fixed {
            case .photo:
                return initials(for: item.student)
            case .name:
                return "\(item.student.firstName) \(item.student.lastName)"
            case .group:
                return item.groupName
            case .followUp:
                return item.student.isInjured ? "Atención" : "Normal"
            case .attendance:
                return attendanceSummary(for: item)
            case .average:
                return averageText(for: item)
            }
        case .column(let column):
            return displayValue(for: item, column: column)
        case .collapsedCategory(_, let columns):
            return "\(filledCellCount(item, columns: columns))/\(columns.count)"
        }
    }

    private func categoryTitle(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> String {
        if let categoryId = column.categoryId,
           let category = data.sheet.columnCategories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        switch column.categoryKind {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .custom: return "Sin categoría"
        default: return "Sin categoría"
        }
    }

    private func tint(for category: NotebookColumnCategory) -> Color {
        tint(forName: category.name)
    }

    private func tint(for column: NotebookColumnDefinition) -> Color {
        if let colorHex = column.colorHex {
            return Color(hex: colorHex)
        }
        switch column.categoryKind {
        case .evaluation: return NotebookStyle.primaryTint
        case .followUp: return NotebookStyle.successTint
        case .attendance: return NotebookStyle.warningTint
        case .extras: return .pink
        case .physicalEducation: return .orange
        case .custom: return .secondary
        default: return .secondary
        }
    }

    private func tint(forName name: String) -> Color {
        if name.localizedCaseInsensitiveContains("evalu") { return NotebookStyle.primaryTint }
        if name.localizedCaseInsensitiveContains("segu") { return NotebookStyle.successTint }
        if name.localizedCaseInsensitiveContains("asist") { return NotebookStyle.warningTint }
        if name.localizedCaseInsensitiveContains("extra") { return .pink }
        if name.localizedCaseInsensitiveContains("ef") { return .orange }
        return .secondary
    }

    private func studentAvatar(for student: Student) -> some View {
        ZStack {
            Circle()
                .fill(NotebookStyle.primaryTint.opacity(0.15))
            Text(initials(for: student))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NotebookStyle.primaryTint)
        }
        .frame(width: 36, height: 36)
    }

    private func initials(for student: Student) -> String {
        String(student.firstName.prefix(1)) + String(student.lastName.prefix(1))
    }

    private func followUpBadge(for student: Student) -> some View {
        Text(student.isInjured ? "Atención" : "Normal")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(student.isInjured ? .orange : NotebookStyle.successTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill((student.isInjured ? Color.orange : NotebookStyle.successTint).opacity(0.12))
            )
    }

    private func attendanceSummary(for item: NotebookTableRow) -> String {
        let attendanceColumns = item.row.persistedCells.filter { $0.columnId.localizedCaseInsensitiveContains("attendance") || $0.columnId.localizedCaseInsensitiveContains("asist") }
        if attendanceColumns.isEmpty { return "Sin datos" }
        let present = attendanceColumns.filter { ($0.textValue ?? "").localizedCaseInsensitiveContains("pres") }.count
        return "\(present)/\(attendanceColumns.count)"
    }

    private func averageText(for item: NotebookTableRow) -> String {
        guard let weightedAverage = item.row.weightedAverage else { return "Sin media" }
        return IosFormatting.decimal(from: weightedAverage)
    }

    private func filledCellCount(_ item: NotebookTableRow, columns: [NotebookColumnDefinition]) -> Int {
        columns.filter { !displayValue(for: item, column: $0).isEmpty }.count
    }

    private func displayValue(for item: NotebookTableRow, column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric, .calculated:
            return bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        case .rubric:
            return bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
        case .check:
            return bridge.cellCheck(studentId: item.student.id, columnId: column.id) ? "Sí" : ""
        default:
            return bridge.cellText(studentId: item.student.id, columnId: column.id)
        }
    }

    private func evidenceLabel(for persistedCell: PersistedNotebookCell?) -> String {
        let count = persistedCell?.annotation?.attachmentUris.count ?? 0
        return count == 0 ? "Sin evidencia" : "\(count) archivo(s)"
    }

    private func formattedDate(_ epochMs: Int64?) -> String {
        guard let epochMs else { return "Sin fecha" }
        return Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    private func syncInspectorDraft() {
        guard let selection = inspectorSelection,
              let data = bridge.notebookState as? NotebookUiStateData,
              let item = filteredRows(data: data).first(where: { $0.student.id == selection.studentId }) else {
            inspectorNoteDraft = ""
            return
        }
        inspectorNoteDraft = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })?.annotation?.note ?? ""
    }

    private func headerChip(title: String, subtitle: String, width: CGFloat, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private func headerChip(for segment: NotebookDisplaySegment, data: NotebookUiStateData) -> some View {
        switch segment {
        case .fixed(let fixed):
            return AnyView(
                headerChip(
                    title: fixed.title,
                    subtitle: fixed.subtitle,
                    width: fixed.width,
                    tint: tint(for: fixed)
                )
            )
        case .column(let column):
            return AnyView(
                headerChip(
                    title: column.title,
                    subtitle: categoryTitle(for: column, data: data),
                    width: CGFloat(max(column.widthDp, 120)),
                    tint: tint(for: column)
                )
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                headerChip(
                    title: category.name,
                    subtitle: "\(columns.count) columnas",
                    width: 150,
                    tint: tint(for: category)
                )
            )
        }
    }

    private func tint(for fixed: NotebookFixedColumn) -> Color {
        switch fixed {
        case .photo, .name, .group:
            return .secondary
        case .followUp:
            return NotebookStyle.successTint
        case .attendance:
            return NotebookStyle.warningTint
        case .average:
            return NotebookStyle.primaryTint
        }
    }

    private func rowCell(for segment: NotebookDisplaySegment, item: NotebookTableRow, data: NotebookUiStateData) -> some View {
        switch segment {
        case .fixed(let fixed):
            return AnyView(fixedRowCell(for: fixed, item: item, data: data))
        case .column(let column):
            return AnyView(
                NotebookEditableTableCell(
                    bridge: bridge,
                    item: item,
                    column: column,
                    isSelected: inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id),
                    onSelect: {
                        inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                    }
                )
                .frame(width: max(column.widthDp, 120))
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                Button {
                    bridge.toggleColumnCategory(id: category.id, collapsed: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("\(filledCellCount(item, columns: columns)) / \(columns.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(NotebookStyle.surfaceMuted)
                    )
                }
                .buttonStyle(.plain)
            )
        }
    }

    private func fixedRowCell(for fixed: NotebookFixedColumn, item: NotebookTableRow, data: NotebookUiStateData) -> some View {
        Group {
            switch fixed {
            case .photo:
                studentAvatar(for: item.student)
                    .frame(width: fixed.width, alignment: .center)
            case .name:
                Button {
                    openInspectorForStudent(item.student.id, data: data)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.student.firstName) \(item.student.lastName)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if item.student.isInjured {
                            Text("Seguimiento físico")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(width: fixed.width, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .group:
                Text(item.groupName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: fixed.width, alignment: .leading)
            case .followUp:
                followUpBadge(for: item.student)
                    .frame(width: fixed.width, alignment: .leading)
            case .attendance:
                Text(attendanceSummary(for: item))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: fixed.width, alignment: .leading)
            case .average:
                Text(averageText(for: item))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: fixed.width, alignment: .leading)
            }
        }
    }

    private func inspectorInfoRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "Sin valor" : value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }
}

private struct NotebookEditableTableCell: View {
    @ObservedObject var bridge: KmpBridge
    let item: NotebookTableRow
    let column: NotebookColumnDefinition
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var numericDraft = ""
    @State private var textDraft = ""
    @State private var checkDraft = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tint.opacity(0.14) : Color.clear)

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear(perform: loadDrafts)
    }

    private var tint: Color {
        if let colorHex = column.colorHex {
            return Color(hex: colorHex)
        }
        return NotebookStyle.primaryTint
    }

    @ViewBuilder
    private var content: some View {
        switch column.type {
        case .numeric:
            TextField("", text: $numericDraft)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .foregroundStyle(.primary)
                .onSubmit(saveNumeric)
        case .calculated:
            Text(bridge.numericGradeOnTenText(studentId: item.student.id, columnId: column.id))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        case .check:
            Toggle("", isOn: $checkDraft)
                .labelsHidden()
                .tint(tint)
                .onChange(of: checkDraft) { newValue in
                    onSelect()
                    bridge.saveColumnGrade(studentId: item.student.id, column: column, value: newValue ? "true" : "false")
                }
        case .ordinal:
            Menu {
                ForEach(ordinalOptions, id: \.self) { option in
                    Button(option) {
                        textDraft = option
                        onSelect()
                        bridge.saveColumnGrade(studentId: item.student.id, column: column, value: option)
                    }
                }
            } label: {
                Text(textDraft.isEmpty ? "Seleccionar" : textDraft)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        case .rubric:
            Button {
                onSelect()
                if let rubricId = column.rubricId?.int64Value, let evaluationId = column.evaluationId?.int64Value {
                    bridge.loadForNotebookCell(studentId: item.student.id, columnId: column.id, rubricId: rubricId, evaluationId: evaluationId)
                }
            } label: {
                Text(displayRubricText())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        default:
            TextField("", text: $textDraft)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.primary)
                .onSubmit(saveText)
        }
    }

    private var ordinalOptions: [String] {
        if !column.ordinalLevels.isEmpty { return column.ordinalLevels }
        switch column.inputKind {
        case .letterAbcd:
            return ["A", "B", "C", "D"]
        case .achievedPartialNotAchieved:
            return ["Logrado", "Parcial", "No logrado"]
        case .excellentGoodProgress:
            return ["Excelente", "Bien", "En proceso"]
        default:
            return ["A", "B", "C", "D"]
        }
    }

    private func loadDrafts() {
        numericDraft = bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        textDraft = bridge.cellText(studentId: item.student.id, columnId: column.id)
        checkDraft = bridge.cellCheck(studentId: item.student.id, columnId: column.id)
    }

    private func saveNumeric() {
        onSelect()
        bridge.saveColumnGradeDebounced(studentId: item.student.id, column: column, value: numericDraft)
    }

    private func saveText() {
        onSelect()
        bridge.saveColumnGradeDebounced(studentId: item.student.id, column: column, value: textDraft)
    }

    private func displayRubricText() -> String {
        let value = bridge.rubricGradeOnTenText(studentId: item.student.id, column: column).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Abrir rúbrica" : value
    }
}

private struct NotebookDynamicCellsRow: View {
    @ObservedObject var bridge: KmpBridge
    let item: NotebookTableRow
    let segments: [NotebookDisplaySegment]
    let inspectorSelection: NotebookInspectorSelection?
    let onSelect: (NotebookInspectorSelection) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .fixed:
                    EmptyView()
                case .column(let column):
                    NotebookEditableTableCell(
                        bridge: bridge,
                        item: item,
                        column: column,
                        isSelected: inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id),
                        onSelect: {
                            onSelect(NotebookInspectorSelection(studentId: item.student.id, columnId: column.id))
                        }
                    )
                    .frame(width: max(column.widthDp, 120))
                case .collapsedCategory(let category, let columns):
                    Button {
                        bridge.toggleColumnCategory(id: category.id, collapsed: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("\(columns.filter { !cellValue(for: $0).isEmpty }.count) / \(columns.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(NotebookStyle.surfaceMuted)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cellValue(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric, .calculated:
            return bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        case .rubric:
            return bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
        case .check:
            return bridge.cellCheck(studentId: item.student.id, columnId: column.id) ? "true" : ""
        default:
            return bridge.cellText(studentId: item.student.id, columnId: column.id)
        }
    }
}

private struct NotebookStateCard<Accessory: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = NotebookStyle.primaryTint
    @ViewBuilder var accessory: Accessory

    init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = NotebookStyle.primaryTint,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 28) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    accessory
                }
                .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
