import SwiftUI
import AppKit
import MiGestorKit

struct MacStudentsView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var rows: [KmpBridge.MacStudentRowSnapshot] = []
    @State private var profile: KmpBridge.StudentProfileSnapshot?
    @State private var searchText = ""
    @State private var trackingFilter = "todos"
    @State private var workGroupFilter = "Todos"
    @State private var quickNoteText = ""
    @State private var isLoadingRows = false
    @State private var isSavingNote = false
    @State private var errorMessage: String?
    @FocusState private var isSearchFocused: Bool

    private var filteredRows: [KmpBridge.MacStudentRowSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            let matchesQuery = query.isEmpty ||
                row.student.fullName.localizedCaseInsensitiveContains(query) ||
                row.className.localizedCaseInsensitiveContains(query)
            let matchesTracking: Bool = {
                switch trackingFilter {
                case "seguimiento":
                    return row.isFollowUp
                case "lesionados":
                    return row.isInjured
                default:
                    return true
                }
            }()
            let matchesGroup = workGroupFilter == "Todos" || row.workGroupName == workGroupFilter
            return matchesQuery && matchesTracking && matchesGroup
        }
    }

    private var selectedRow: KmpBridge.MacStudentRowSnapshot? {
        guard let selectedStudentId else { return filteredRows.first }
        return rows.first(where: { $0.id == selectedStudentId }) ?? filteredRows.first
    }

    private var workGroupOptions: [String] {
        ["Todos"] + Array(Set(rows.map(\.workGroupName))).sorted()
    }

    var body: some View {
        HSplitView {
            studentsSidebar
                .frame(minWidth: 250, idealWidth: 270, maxWidth: 310)

            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                studentsHeader
                studentsTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(MacAppStyle.pagePadding)
            .frame(minWidth: 640)

            studentInspector
                .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)
        }
        .background(MacAppStyle.pageBackground)
        .task {
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId
            }
            await reloadRows()
        }
        .task(id: selectedClassId) {
            await bridge.selectStudentsClass(classId: selectedClassId)
            await reloadRows()
        }
        .onChange(of: selectedStudentId) { _, _ in
            Task { await reloadProfile() }
        }
        .onChange(of: filteredRows.map(\.id)) { _, visibleIds in
            guard !visibleIds.isEmpty else {
                selectedStudentId = nil
                return
            }
            if selectedStudentId == nil || !visibleIds.contains(selectedStudentId ?? -1) {
                selectedStudentId = visibleIds.first
            }
        }
        .onExitCommand {
            if !searchText.isEmpty {
                searchText = ""
            }
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)

            Button("") {
                openSelectedInNotebook()
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
        }
    }

    private var studentsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Filtros")
                    .font(.title3.weight(.semibold))
                Text("\(filteredRows.count) de \(rows.count) alumnos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Clase", selection: $selectedClassId) {
                    Text("Todas").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Busqueda")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nombre o clase", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Seguimiento")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Seguimiento", selection: $trackingFilter) {
                    Text("Todos").tag("todos")
                    Text("Seguimiento").tag("seguimiento")
                    Text("Lesionados").tag("lesionados")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Grupo de trabajo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Grupo de trabajo", selection: $workGroupFilter) {
                    ForEach(workGroupOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
        .background(MacAppStyle.cardBackground)
    }

    private var studentsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Alumnado")
                    .font(MacAppStyle.pageTitle)
                Text("Tabla densa con seguimiento, asistencia, media e incidencias.")
                    .font(MacAppStyle.bodyText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingRows {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await reloadRows() }
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var studentsTable: some View {
        if rows.isEmpty && !isLoadingRows {
            ContentUnavailableView(
                "Sin alumnado",
                systemImage: "person.3",
                description: Text("No hay alumnos disponibles para la clase seleccionada.")
            )
        } else if filteredRows.isEmpty {
            ContentUnavailableView(
                "Sin coincidencias",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Ajusta la busqueda o los filtros de seguimiento.")
            )
        } else {
            Table(filteredRows, selection: $selectedStudentId) {
                TableColumn("Nombre") { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.system(size: 13, weight: .semibold))
                        if row.student.email?.isEmpty == false {
                            Text(row.student.email ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Clase") { row in
                    Text(row.className)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Seguimiento") { row in
                    MacStatusPill(
                        label: row.followUpLabel,
                        isActive: row.isFollowUp,
                        tint: row.isInjured ? MacAppStyle.warningTint : (row.isFollowUp ? MacAppStyle.infoTint : MacAppStyle.successTint)
                    )
                }
                .width(min: 112, ideal: 130)
                TableColumn("Asistencia reciente") { row in
                    Text(row.recentAttendanceLabel)
                        .font(.system(size: 12, weight: .medium))
                }
                .width(min: 130, ideal: 150)
                TableColumn("Media") { row in
                    Text(row.averageText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 82)
                TableColumn("Incidencias") { row in
                    Text("\(row.incidentCount)")
                        .font(.system(size: 12, weight: row.incidentCount > 0 ? .bold : .regular))
                        .foregroundStyle(row.incidentCount > 0 ? .red : .secondary)
                        .monospacedDigit()
                }
                .width(min: 82, ideal: 96)
                TableColumn("Última observación") { row in
                    Text(row.lastObservationText)
                        .font(.system(size: 12))
                        .foregroundStyle(row.lastObservationText == "Sin observaciones" ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private var studentInspector: some View {
        if let selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ficha del alumno")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedRow.student.fullName)
                            .font(.title2.weight(.semibold))
                        Text(selectedRow.className)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        MacStatusPill(
                            label: selectedRow.followUpLabel,
                            isActive: selectedRow.isFollowUp,
                            tint: selectedRow.isInjured ? MacAppStyle.warningTint : MacAppStyle.infoTint
                        )
                        MacStatusPill(
                            label: selectedRow.workGroupName,
                            isActive: selectedRow.workGroupName != "Sin grupo",
                            tint: MacAppStyle.successTint
                        )
                    }

                    if let profile {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MacMetricCard(label: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                            MacMetricCard(label: "Media", value: IosFormatting.decimal(profile.averageScore), systemImage: "sum")
                            MacMetricCard(label: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble")
                            MacMetricCard(label: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                        }

                        inspectorSection("Notas rápidas") {
                            TextEditor(text: $quickNoteText)
                                .frame(minHeight: 86)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            HStack {
                                Button {
                                    Task { await saveQuickNote() }
                                } label: {
                                    Label(isSavingNote ? "Guardando…" : "Guardar nota", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNote)
                                Spacer()
                            }
                        }

                        inspectorSection("Historial de incidencias") {
                            if profile.incidents.isEmpty {
                                Text("Sin incidencias registradas.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(profile.incidents.prefix(5), id: \.id) { incident in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(incident.title)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(incident.severity.capitalized)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(incident.detail ?? "Sin detalle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }

                        inspectorSection("Accesos") {
                            VStack(spacing: 8) {
                                Button {
                                    openSelectedInNotebook()
                                } label: {
                                    Label("Abrir en cuaderno", systemImage: "tablecells")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    onOpenModule(.attendance, selectedClassId, selectedRow.id)
                                } label: {
                                    Label("Abrir asistencia", systemImage: "checklist.checked")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    onOpenModule(.reports, selectedClassId, selectedRow.id)
                                } label: {
                                    Label("Abrir informes", systemImage: "doc.text")
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ProgressView("Cargando ficha…")
                    }
                }
                .padding(MacAppStyle.pagePadding)
            }
            .background(MacAppStyle.cardBackground)
        } else {
            VStack {
                ContentUnavailableView(
                    "Selecciona un alumno",
                    systemImage: "person.3",
                    description: Text("La ficha reunira notas, incidencias y accesos cruzados.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(MacAppStyle.cardBackground)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            content()
        }
    }

    @MainActor
    private func reloadRows() async {
        isLoadingRows = true
        errorMessage = nil
        defer { isLoadingRows = false }
        do {
            rows = try await bridge.loadMacStudentRows(classId: selectedClassId)
            if let selectedStudentId, rows.contains(where: { $0.id == selectedStudentId }) {
                await reloadProfile()
            } else {
                selectedStudentId = filteredRows.first?.id
                await reloadProfile()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reloadProfile() async {
        guard let selectedStudentId else {
            profile = nil
            return
        }
        profile = try? await bridge.loadStudentProfile(studentId: selectedStudentId, classId: selectedClassId)
    }

    @MainActor
    private func saveQuickNote() async {
        guard let selectedStudentId else { return }
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            try await bridge.saveQuickStudentNote(studentId: selectedStudentId, classId: selectedClassId, note: quickNoteText)
            quickNoteText = ""
            await reloadRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSelectedInNotebook() {
        guard let selectedStudentId else { return }
        onOpenModule(.notebook, selectedClassId, selectedStudentId)
    }
}

struct MacRubricsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var selectedRubricId: Int64?
    @State private var selectedFilterClassId: Int64?
    @State private var usageSummary: KmpBridge.RubricUsageSnapshot?
    @State private var usageLoading = false
    @State private var bulkOptions: [KmpBridge.RubricUsageSnapshot.EvaluationUsage] = []
    @State private var bulkLaunchInFlight = false
    @State private var showingBuilder = false

    private var filteredRubrics: [RubricDetail] {
        bridge.rubrics.filter { rubric in
            guard let selectedFilterClassId else { return true }
            return rubric.rubric.classId?.int64Value == selectedFilterClassId
        }
    }

    private var selectedRubric: RubricDetail? {
        filteredRubrics.first(where: { $0.rubric.id == selectedRubricId }) ?? filteredRubrics.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rúbricas")
                        .font(MacAppStyle.pageTitle)
                    Text("Workspace Mac con banco, detalle e impacto evaluativo.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !bridge.classes.isEmpty {
                    Picker("Clase", selection: $selectedFilterClassId) {
                        Text("Todas").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .frame(width: 220)
                }
                Button {
                    bridge.resetRubricBuilder()
                    showingBuilder = true
                } label: {
                    Label("Nueva rúbrica", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if bridge.rubrics.isEmpty {
                ContentUnavailableView(
                    "Sin rúbricas",
                    systemImage: "checklist",
                    description: Text("Aún no hay rúbricas cargadas en el bridge.")
                )
            } else {
                HStack(alignment: .top, spacing: MacAppStyle.sectionSpacing) {
                    rubricsTable
                        .frame(minWidth: 430, idealWidth: 520, maxWidth: 620)
                    rubricDetailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(MacAppStyle.pagePadding)
        .task {
            if selectedRubricId == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            await reloadUsageSummary()
        }
        .onChange(of: selectedFilterClassId) { newValue in
            bridge.setRubricFilterClass(newValue)
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: bridge.rubrics.count) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: selectedRubricId) { _ in
            Task { await reloadUsageSummary() }
        }
        .confirmationDialog(
            "Elegir evaluación masiva",
            isPresented: Binding(
                get: { !bulkOptions.isEmpty },
                set: { if !$0 { bulkOptions = [] } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(bulkOptions, id: \.evaluationId) { usage in
                Button("\(usage.className) · \(usage.evaluationName)") {
                    openBulkEvaluation(for: usage)
                }
            }
            Button("Cancelar", role: .cancel) {
                bulkOptions = []
            }
        } message: {
            Text("Selecciona la clase y evaluación que quieres abrir.")
        }
        .sheet(isPresented: $showingBuilder) {
            RubricsBuilderScreen()
                .environmentObject(bridge)
                .frame(minWidth: 1200, minHeight: 820)
        }
        .sheet(
            isPresented: Binding(
                get: { bridge.rubricsUiState?.assignDialogState != nil },
                set: { visible in
                    if !visible {
                        bridge.dismissAssignRubricDialog()
                    }
                }
            )
        ) {
            AssignRubricToTabView()
                .environmentObject(bridge)
                .frame(minWidth: 640, minHeight: 520)
        }
        .sheet(
            isPresented: Binding(
                get: { bridge.showingBulkRubricEvaluation },
                set: { visible in
                    if !visible {
                        bridge.closeBulkRubricEvaluation()
                    }
                }
            )
        ) {
            RubricBulkEvaluationSheet(bridge: bridge)
                .environmentObject(bridge)
                .frame(minWidth: 1320, minHeight: 860)
        }
    }

    private var rubricsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nombre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Criterios")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Text("Uso")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.horizontal, MacAppStyle.innerPadding)
            .padding(.vertical, 10)
            .background(MacAppStyle.subtleFill)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRubrics, id: \.rubric.id) { rubric in
                        Button {
                            selectedRubricId = rubric.rubric.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rubric.rubric.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(className(for: rubric))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(rubric.criteria.count)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                MacStatusPill(
                                    label: usageLabel(for: rubric),
                                    isActive: usageCount(for: rubric) > 0,
                                    tint: usageCount(for: rubric) > 0 ? MacAppStyle.infoTint : .secondary
                                )
                                .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, MacAppStyle.innerPadding)
                            .padding(.vertical, 12)
                            .background(
                                selectedRubricId == rubric.rubric.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
            }
        }
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var rubricDetailPanel: some View {
        if let rubric = selectedRubric {
            ScrollView {
                VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rubric.rubric.name)
                            .font(.title2.weight(.semibold))
                        Text("\(className(for: rubric)) · \(formattedDate(for: rubric))")
                            .foregroundStyle(.secondary)
                        if let description = rubric.rubric.description_, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: MacAppStyle.cardSpacing) {
                        MacMetricCard(label: "Criterios", value: "\(rubric.criteria.count)", systemImage: "list.bullet.rectangle")
                        MacMetricCard(label: "Clases", value: "\(usageSummary?.classCount ?? 0)", systemImage: "rectangle.3.group")
                        MacMetricCard(label: "Evaluaciones", value: "\(usageSummary?.evaluationCount ?? 0)", systemImage: "chart.bar.doc.horizontal")
                        MacMetricCard(label: "Uso", value: usageLabel(for: rubric), systemImage: "checklist")
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await openBulkEvaluationFlow(for: rubric) }
                        } label: {
                            if bulkLaunchInFlight {
                                Label("Abriendo…", systemImage: "hourglass")
                            } else {
                                Label("Evaluación masiva", systemImage: "square.grid.3x3")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((usageSummary?.evaluationCount ?? 0) == 0 || bulkLaunchInFlight)

                        Button {
                            bridge.loadRubricForEditing(rubric)
                            showingBuilder = true
                        } label: {
                            Label("Abrir vista de edición", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            bridge.startAssignRubric(rubric.rubric)
                        } label: {
                            Label("Asignar a clase", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            bridge.deleteRubric(id: rubric.rubric.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Impacto evaluativo")
                            .font(MacAppStyle.sectionTitle)
                        if usageLoading {
                            ProgressView()
                        } else if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                            Text("Esta rúbrica está vinculada a \(usageSummary.evaluationCount) evaluación(es) en \(usageSummary.classCount) clase(s).")
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)

                            MacFlowLayout(spacing: 8) {
                                ForEach(usageSummary.linkedClassNames, id: \.self) { className in
                                    MacStatusPill(label: className, isActive: true, tint: MacAppStyle.infoTint)
                                }
                            }

                            VStack(spacing: 8) {
                                ForEach(usageSummary.evaluationUsages.prefix(6), id: \.evaluationId) { usage in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(usage.evaluationName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(usage.className) · \(usage.evaluationType) · Peso \(String(format: "%.1f", usage.weight))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(MacAppStyle.cardBackground)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                                            .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                                }
                            }
                        } else {
                            Text("Todavía no hay evaluaciones activas enlazadas a esta rúbrica.")
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Criterios y niveles")
                            .font(MacAppStyle.sectionTitle)
                        ForEach(rubric.criteria, id: \.criterion.id) { item in
                            MacRubricCriterionCard(item: item)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Selecciona una rúbrica",
                systemImage: "checklist",
                description: Text("El detalle mostrará criterios, niveles y acceso a evaluación masiva.")
            )
        }
    }

    @MainActor
    private func reloadUsageSummary() async {
        guard let rubricId = selectedRubric?.rubric.id else {
            usageSummary = nil
            return
        }
        usageLoading = true
        defer { usageLoading = false }
        usageSummary = try? await bridge.loadRubricUsage(rubricId: rubricId)
    }

    @MainActor
    private func openBulkEvaluationFlow(for rubric: RubricDetail) async {
        guard let usageSummary else { return }
        if usageSummary.evaluationUsages.count == 1 {
            bulkLaunchInFlight = true
            defer { bulkLaunchInFlight = false }
            _ = await bridge.launchBulkRubricEvaluationFromRubric(
                rubricId: rubric.rubric.id,
                preferredClassId: rubric.rubric.classId?.int64Value
            )
        } else {
            bulkOptions = usageSummary.evaluationUsages
        }
    }

    private func openBulkEvaluation(for usage: KmpBridge.RubricUsageSnapshot.EvaluationUsage) {
        bulkOptions = []
        Task { @MainActor in
            bulkLaunchInFlight = true
            defer { bulkLaunchInFlight = false }
            _ = await bridge.launchBulkRubricEvaluationFromUsage(
                rubricId: selectedRubric?.rubric.id ?? usageSummary?.rubricId ?? 0,
                classId: usage.classId,
                evaluationId: usage.evaluationId
            )
        }
    }

    private func usageCount(for rubric: RubricDetail) -> Int {
        if usageSummary?.rubricId == rubric.rubric.id {
            return usageSummary?.evaluationCount ?? 0
        }
        return (bridge.rubricClassLinks[rubric.rubric.id] ?? []).isEmpty ? 0 : 1
    }

    private func usageLabel(for rubric: RubricDetail) -> String {
        let count = usageCount(for: rubric)
        switch count {
        case 0: return "Sin uso"
        case 1: return "1 eval."
        default: return "\(count) evals."
        }
    }

    private func className(for rubric: RubricDetail) -> String {
        if let classId = rubric.rubric.classId?.int64Value,
           let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
            return schoolClass.name
        }
        return "Sin clase asociada"
    }

    private func formattedDate(for rubric: RubricDetail) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(rubric.rubric.trace.updatedAt.epochSeconds))
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct MacRubricCriterionCard: View {
    let item: RubricCriterionWithLevels

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.criterion.description_)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                MacStatusPill(
                    label: "Peso \(Int((item.criterion.weight * 100).rounded()))%",
                    isActive: true,
                    tint: MacAppStyle.infoTint
                )
            }

            VStack(spacing: 10) {
                ForEach(item.levels.sorted(by: { $0.order < $1.order }), id: \.id) { level in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(level.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(Int(level.points)) pts")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MacAppStyle.infoTint)
                        }

                        if let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 800
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: maxWidth,
            height: currentY + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct MacReportsView: View {
    private enum ReportTerm: String, CaseIterable, Identifiable {
        case first = "1er Trimestre"
        case second = "2º Trimestre"
        case third = "3er Trimestre"

        var id: String { rawValue }
    }

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case pdf = "PDF"
        case docx = "DOCX"

        var id: String { rawValue }
    }

    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    @State private var selectedReportKind: KmpBridge.ReportKind = .groupOverview
    @State private var selectedTerm: ReportTerm = .first
    @State private var selectedExportFormat: ExportFormat = .pdf
    @State private var includeFactLines = true
    @State private var includeRecommendations = true
    @State private var includeClassicAppendix = true
    @State private var reportContext: KmpBridge.ReportGenerationContext?
    @State private var preview: KmpBridge.ReportPreviewPayload?
    @State private var aiAvailability: AIReportAvailabilityState = .unavailable("Comprobando disponibilidad…")
    @State private var aiAudience: AIReportAudience = .docente
    @State private var aiTone: AIReportTone = .claro
    @State private var aiDraft: AIReportDraft?
    @State private var editableDraftText = ""
    @State private var feedbackMessage: String?
    @State private var isLoadingContext = false
    @State private var isGeneratingDraft = false
    @State private var isExporting = false

    private let aiReportService = AppleFoundationReportService()
    private let draftStore = MacReportDraftStore()

    private var selectedClass: SchoolClass? {
        guard let selectedClassId else { return nil }
        return bridge.classes.first(where: { $0.id == selectedClassId })
    }

    private var selectedStudent: Student? {
        guard let selectedStudentId else { return nil }
        return studentOptions.first(where: { $0.id == selectedStudentId })
    }

    private var studentOptions: [Student] {
        bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
    }

    private var requiresStudent: Bool {
        selectedReportKind.requiresStudentSelection
    }

    private var activeDraftKey: MacReportDraftKey? {
        guard let selectedClassId else { return nil }
        return MacReportDraftKey(
            classId: selectedClassId,
            reportKind: selectedReportKind.rawValue,
            period: selectedTerm.rawValue,
            studentId: selectedStudentId
        )
    }

    private var canGenerateAIDraft: Bool {
        guard !isGeneratingDraft, aiAvailability.isAvailable else { return false }
        guard let reportContext, reportContext.hasEnoughData else { return false }
        return !requiresStudent || selectedStudentId != nil
    }

    private var canExport: Bool {
        selectedClassId != nil &&
        (!requiresStudent || selectedStudentId != nil) &&
        !consolidatedReportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var consolidatedReportText: String {
        let edited = editableDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !edited.isEmpty {
            return edited
        }

        guard let context = reportContext else {
            return "Selecciona un grupo para preparar el informe."
        }

        var sections: [String] = [
            context.reportTitle,
            context.className,
            context.studentName.map { "Alumno/a: \($0)" } ?? "Ámbito: grupo completo",
            "Periodo: \(context.termLabel ?? selectedTerm.rawValue)",
            "",
            context.summary
        ]

        if includeFactLines, !context.factLines.isEmpty {
            sections += ["", "Hechos verificables", context.factLines.map { "- \($0)" }.joined(separator: "\n")]
        }

        if includeRecommendations, !context.recommendedActions.isEmpty {
            sections += ["", "Próximos pasos", context.recommendedActions.map { "- \($0)" }.joined(separator: "\n")]
        }

        if includeClassicAppendix {
            sections += ["", "Vista clásica", preview?.previewText ?? context.classicReportText]
        }

        return sections.joined(separator: "\n")
    }

    var body: some View {
        HSplitView {
            reportsSidebar
                .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)

            reportsCenter
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

            reportsExportPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        }
        .background(MacAppStyle.pageBackground)
        .task {
            aiAvailability = aiReportService.currentAvailability()
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
            }
            await refreshWorkspace()
        }
        .onChange(of: selectedClassId) { _, _ in
            selectedStudentId = nil
            Task { await refreshWorkspace() }
        }
        .onChange(of: selectedReportKind) { _, newValue in
            if newValue == .lomloeEvaluationComment {
                aiAudience = .familia
                aiTone = .formal
            }
            if !newValue.requiresStudentSelection {
                selectedStudentId = nil
            }
            Task { await reloadReport() }
        }
        .onChange(of: selectedTerm) { _, _ in
            Task { await reloadReport() }
        }
        .onChange(of: selectedStudentId) { _, _ in
            Task { await reloadReport() }
        }
    }

    private var reportsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Informes")
                        .font(.title2.weight(.semibold))
                    Text("Generador de salidas docentes")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                MacReportPanelCard(title: "Grupo") {
                    Picker("Grupo", selection: $selectedClassId) {
                        Text("Seleccionar grupo").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                MacReportPanelCard(title: "Tipo de informe") {
                    ForEach(KmpBridge.ReportKind.allCases) { kind in
                        reportKindButton(kind)
                    }
                }

                MacReportPanelCard(title: "Periodo") {
                    Picker("Periodo", selection: $selectedTerm) {
                        ForEach(ReportTerm.allCases) { term in
                            Text(term.rawValue).tag(term)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                MacReportPanelCard(title: "Alumnado") {
                    Picker("Alumno", selection: $selectedStudentId) {
                        Text(requiresStudent ? "Seleccionar alumno" : "Grupo completo").tag(Optional<Int64>.none)
                        ForEach(studentOptions, id: \.id) { student in
                            Text(student.fullName).tag(Optional(student.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Text(requiresStudent ? "Este informe necesita un alumno activo." : "Este informe se genera para el grupo completo.")
                        .font(.caption)
                        .foregroundStyle(requiresStudent && selectedStudentId == nil ? MacAppStyle.warningTint : .secondary)
                }

                MacReportPanelCard(title: "Filtros") {
                    Toggle("Incluir hechos verificables", isOn: $includeFactLines)
                    Toggle("Incluir próximos pasos", isOn: $includeRecommendations)
                    Toggle("Anexar vista clásica", isOn: $includeClassicAppendix)
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
        .background(MacAppStyle.cardBackground)
    }

    private var reportsCenter: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            reportsHeader

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if selectedClassId == nil {
                ContentUnavailableView(
                    "Selecciona un grupo",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Informes necesita un grupo para construir contexto, métricas y salidas docentes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requiresStudent && selectedStudentId == nil {
                ContentUnavailableView(
                    "Selecciona un alumno",
                    systemImage: "person.text.rectangle",
                    description: Text("Este tipo de informe es individual y necesita alumnado activo antes de generar preview o IA.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        metricsGrid
                        aiSummaryBlock
                        previewBlock
                    }
                    .padding(.bottom, MacAppStyle.pagePadding)
                }
            }
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var reportsHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedReportKind.title)
                    .font(MacAppStyle.pageTitle)
                Text(selectedClass?.name ?? "Selecciona un grupo para empezar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingContext {
                ProgressView()
                    .controlSize(.small)
            }
            MacStatusPill(
                label: aiAvailability.isAvailable ? "IA disponible" : "IA limitada",
                isActive: aiAvailability.isAvailable,
                tint: aiAvailability.isAvailable ? MacAppStyle.successTint : MacAppStyle.warningTint
            )
        }
    }

    @ViewBuilder
    private var metricsGrid: some View {
        if let reportContext {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                MacMetricCard(label: "Tipo", value: selectedReportKind.title, systemImage: selectedReportKind.systemImage)
                MacMetricCard(label: "Periodo", value: selectedTerm.rawValue, systemImage: "calendar")
                ForEach(reportContext.metrics) { metric in
                    MacMetricCard(label: metric.title, value: metric.value, systemImage: metric.systemImage)
                }
            }
        }
    }

    private var aiSummaryBlock: some View {
        MacReportPanelCard(title: "Bloque resumen IA") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reportContext?.summary ?? "Sin contexto cargado.")
                            .font(.headline)
                        Text(aiAvailability.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await generateAIDraft() }
                    } label: {
                        if isGeneratingDraft {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Generar borrador", systemImage: "apple.intelligence")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerateAIDraft)
                }

                HStack {
                    Picker("Audiencia", selection: $aiAudience) {
                        ForEach(AIReportAudience.allCases) { audience in
                            Text(audience.title).tag(audience)
                        }
                    }
                    Picker("Tono", selection: $aiTone) {
                        ForEach(AIReportTone.allCases) { tone in
                            Text(tone.title).tag(tone)
                        }
                    }
                }

                if let reportContext, !reportContext.factLines.isEmpty {
                    MacReportTextSection(title: "Hechos previos", lines: reportContext.factLines)
                }

                if let reportContext, let dataQualityNote = reportContext.dataQualityNote {
                    MacReportNotice(title: "Calidad de datos", message: dataQualityNote, tint: MacAppStyle.warningTint)
                }

                TextEditor(text: $editableDraftText)
                    .font(.system(size: 13))
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var previewBlock: some View {
        MacReportPanelCard(title: "Preview del informe") {
            VStack(alignment: .leading, spacing: 12) {
                Text(consolidatedReportText)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let reportContext {
                    if !reportContext.strengths.isEmpty {
                        MacReportTextSection(title: "Fortalezas detectadas", lines: reportContext.strengths)
                    }
                    if !reportContext.needsAttention.isEmpty {
                        MacReportTextSection(title: "Aspectos a vigilar", lines: reportContext.needsAttention)
                    }
                }
            }
        }
    }

    private var reportsExportPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Exportación")
                        .font(.title3.weight(.semibold))
                    Text("Salida final revisada")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                MacReportPanelCard(title: "Formato") {
                    Picker("Formato", selection: $selectedExportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                MacReportPanelCard(title: "Opciones") {
                    LabeledContent("Grupo") {
                        Text(selectedClass?.name ?? "Sin grupo")
                    }
                    LabeledContent("Destino") {
                        Text(selectedStudent?.fullName ?? "Grupo completo")
                    }
                    LabeledContent("Texto") {
                        Text("\(consolidatedReportText.count) caracteres")
                    }
                    LabeledContent("Borrador") {
                        Text(editableDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Preview" : "Editado")
                    }
                }

                MacReportPanelCard(title: "Acciones") {
                    VStack(spacing: 10) {
                        Button {
                            Task { await export(format: .pdf) }
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canExport || isExporting)

                        Button {
                            Task { await export(format: .docx) }
                        } label: {
                            Label("DOCX", systemImage: "doc.badge.gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canExport || isExporting)

                        Button {
                            copyReportText()
                        } label: {
                            Label("Copiar texto", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canExport)

                        Button {
                            saveDraft()
                        } label: {
                            Label("Guardar borrador", systemImage: "tray.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(activeDraftKey == nil || consolidatedReportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let reportContext {
                    MacReportPanelCard(title: "Métricas previas") {
                        ForEach(reportContext.metrics) { metric in
                            LabeledContent(metric.title) {
                                Text(metric.value)
                            }
                        }
                    }
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
        .background(MacAppStyle.cardBackground)
    }

    private func reportKindButton(_ kind: KmpBridge.ReportKind) -> some View {
        Button {
            selectedReportKind = kind
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(selectedReportKind == kind ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                    Text(kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(selectedReportKind == kind ? Color.accentColor.opacity(0.12) : MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func refreshWorkspace() async {
        guard let selectedClassId else {
            reportContext = nil
            preview = nil
            return
        }
        bridge.selectClass(id: selectedClassId)
        await bridge.selectStudentsClass(classId: selectedClassId)
        if requiresStudent, selectedStudentId == nil {
            selectedStudentId = bridge.studentsInClass.first?.id
        }
        await reloadReport()
    }

    @MainActor
    private func reloadReport() async {
        guard let selectedClassId else {
            reportContext = nil
            preview = nil
            return
        }
        if requiresStudent && selectedStudentId == nil {
            reportContext = nil
            preview = nil
            editableDraftText = ""
            aiDraft = nil
            return
        }

        isLoadingContext = true
        feedbackMessage = nil
        aiDraft = nil
        defer { isLoadingContext = false }

        do {
            let termLabel = selectedTerm.rawValue
            let context = try await bridge.buildReportGenerationContext(
                classId: selectedClassId,
                studentId: selectedStudentId,
                kind: selectedReportKind,
                termLabel: termLabel
            )
            reportContext = context
            preview = try await bridge.buildReportPreview(
                classId: selectedClassId,
                studentId: selectedStudentId,
                kind: selectedReportKind,
                termLabel: termLabel
            )
            loadSavedDraftForCurrentSelection()
            if !context.hasEnoughData {
                feedbackMessage = context.dataQualityNote ?? "Hay pocos datos para redactar conclusiones firmes."
            }
        } catch {
            reportContext = nil
            preview = nil
            editableDraftText = ""
            feedbackMessage = "No se pudo preparar el informe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generateAIDraft() async {
        guard let reportContext else { return }
        isGeneratingDraft = true
        feedbackMessage = nil
        defer { isGeneratingDraft = false }

        do {
            let draft = try await aiReportService.generateDraft(
                from: reportContext,
                audience: aiAudience,
                tone: aiTone
            )
            aiDraft = draft
            editableDraftText = draft.editableText(for: reportContext)
            feedbackMessage = "Borrador generado. Revísalo antes de exportar o compartir."
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func loadSavedDraftForCurrentSelection() {
        guard let key = activeDraftKey else {
            editableDraftText = ""
            return
        }
        editableDraftText = draftStore.load(key: key)?.text ?? ""
    }

    private func saveDraft() {
        guard let key = activeDraftKey else { return }
        draftStore.save(
            text: consolidatedReportText,
            key: key,
            title: reportContext?.reportTitle ?? selectedReportKind.title
        )
        editableDraftText = consolidatedReportText
        feedbackMessage = "Borrador guardado localmente para esta combinación de informe."
    }

    private func copyReportText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(consolidatedReportText, forType: .string)
        feedbackMessage = "Texto copiado al portapapeles."
    }

    @MainActor
    private func export(format: ExportFormat) async {
        guard canExport else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let title = reportContext?.reportTitle ?? selectedReportKind.title
            let fileName = MacReportExportService.safeFileName(
                title: title,
                className: selectedClass?.name ?? "Grupo",
                studentName: selectedStudent?.fullName
            )
            let url = try MacReportExportService.destinationURL(
                suggestedFileName: fileName,
                fileExtension: format == .pdf ? "pdf" : "docx"
            )
            switch format {
            case .pdf:
                try MacReportExportService.writePDF(text: consolidatedReportText, title: title, to: url)
            case .docx:
                try MacReportExportService.writeDOCX(text: consolidatedReportText, title: title, to: url)
            }
            feedbackMessage = "\(format.rawValue) exportado en \(url.lastPathComponent)."
        } catch MacReportExportError.cancelled {
            feedbackMessage = "Exportación cancelada."
        } catch {
            feedbackMessage = "No se pudo exportar: \(error.localizedDescription)"
        }
    }
}

private struct MacReportPanelCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            content()
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacReportTextSection: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text("• \(line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacReportNotice: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MacReportDraftKey: Codable, Hashable {
    let classId: Int64
    let reportKind: String
    let period: String
    let studentId: Int64?

    var storageId: String {
        [
            "\(classId)",
            reportKind,
            period,
            studentId.map(String.init) ?? "group"
        ]
        .joined(separator: "::")
    }
}

private struct MacReportDraftRecord: Codable {
    let key: MacReportDraftKey
    let title: String
    let text: String
    let updatedAt: Date
}

private final class MacReportDraftStore {
    private let defaults = UserDefaults.standard
    private let prefix = "mac.reports.draft."

    func load(key: MacReportDraftKey) -> MacReportDraftRecord? {
        guard let data = defaults.data(forKey: prefix + key.storageId) else { return nil }
        return try? JSONDecoder().decode(MacReportDraftRecord.self, from: data)
    }

    func save(text: String, key: MacReportDraftKey, title: String) {
        let record = MacReportDraftRecord(key: key, title: title, text: text, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: prefix + key.storageId)
    }
}

private enum MacReportExportError: LocalizedError {
    case cancelled
    case documentBuildFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Exportación cancelada."
        case .documentBuildFailed:
            return "No se pudo construir el documento."
        }
    }
}

private enum MacReportExportService {
    static func destinationURL(suggestedFileName: String, fileExtension: String) throws -> URL {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(suggestedFileName).\(fileExtension)"
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let url = panel.url else {
            throw MacReportExportError.cancelled
        }
        return url
    }

    static func safeFileName(title: String, className: String, studentName: String?) -> String {
        let raw = [title, className, studentName].compactMap { $0 }.joined(separator: " - ")
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func writePDF(text: String, title: String, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 54
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSMutableAttributedString(string: "\(title)\n\n", attributes: titleAttributes)
        attributed.append(NSAttributedString(string: text, attributes: bodyAttributes))

        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: pageRect.width - margin * 2, height: pageRect.height - margin * 2))
        textView.textStorage?.setAttributedString(attributed)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = CGSize(width: pageRect.width - margin * 2, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        guard let container = textView.textContainer else {
            throw MacReportExportError.documentBuildFailed
        }
        textView.layoutManager?.ensureLayout(for: container)
        let usedHeight = (textView.layoutManager?.usedRect(for: container).height ?? pageRect.height) + margin
        textView.frame = CGRect(x: 0, y: 0, width: pageRect.width - margin * 2, height: max(usedHeight, pageRect.height - margin * 2))
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        try pdfData.write(to: url, options: .atomic)
    }

    static func writeDOCX(text: String, title: String, to url: URL) throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        \(paragraphXML(title, style: "Title"))
        \(text.components(separatedBy: .newlines).map { paragraphXML($0) }.joined())
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
        </w:body></w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
        """
        let core = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(xmlEscape(title))</dc:title><dc:creator>MiGestor</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">\(ISO8601DateFormatter().string(from: Date()))</dcterms:created></cp:coreProperties>
        """
        let archive = try MacReportZipArchive(files: [
            "[Content_Types].xml": Data(contentTypes.utf8),
            "_rels/.rels": Data(rels.utf8),
            "docProps/core.xml": Data(core.utf8),
            "word/document.xml": Data(documentXML.utf8)
        ]).data()
        try archive.write(to: url, options: .atomic)
    }

    private static func paragraphXML(_ text: String, style: String? = nil) -> String {
        let styleXML = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        let runXML = text.isEmpty
            ? "<w:r><w:t></w:t></w:r>"
            : "<w:r><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
        return "<w:p>\(styleXML)\(runXML)</w:p>"
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct MacReportZipArchive {
    let files: [String: Data]

    func data() throws -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for name in files.keys.sorted() {
            guard let content = files[name], let nameData = name.data(using: .utf8) else { continue }
            let crc = MacReportCRC32.checksum(content)
            let size = UInt32(content.count)
            let nameSize = UInt16(nameData.count)

            var local = Data()
            local.appendUInt32(0x04034b50)
            local.appendUInt16(20)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(nameSize)
            local.appendUInt16(0)
            local.append(nameData)
            local.append(content)
            output.append(local)

            var central = Data()
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(nameSize)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)
            centralDirectory.append(central)

            offset += UInt32(local.count)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(files.count))
        output.appendUInt16(UInt16(files.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)
        return output
    }
}

private enum MacReportCRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ])
    }
}

struct MacPlannerView: View {
    @ObservedObject var bridge: KmpBridge
    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var activeSection: MacPlannerSection = .week
    @State private var selectedTableSessionId: Int64?
    @State private var showingScheduleSettings = false
    @State private var showingExportConfirmation = false
    @State private var transientMessage: String?
    @State private var isInspectorVisible = true
    @State private var inspectorWidth: CGFloat = 380

    var body: some View {
        GeometryReader { proxy in
            HSplitView {
                plannerSidebar
                    .frame(minWidth: 252, idealWidth: 272, maxWidth: 296)

                VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                    plannerHeader
                    if let transientMessage, !transientMessage.isEmpty {
                        MacPlannerBanner(message: transientMessage)
                    } else if !vm.bulkSummary.isEmpty {
                        MacPlannerBanner(message: vm.bulkSummary)
                    }
                    plannerCenterContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(MacAppStyle.pagePadding)
                .background(MacAppStyle.pageBackground)

                if shouldShowInspector(in: proxy.size.width) {
                    plannerInspector
                        .frame(minWidth: 320, idealWidth: inspectorWidth, maxWidth: 460)
                }
            }
        }
        .background(MacAppStyle.pageBackground)
        .task {
            await vm.bind(bridge: bridge)
        }
        .onChange(of: selectedTableSessionId) { newValue in
            guard let newValue,
                  let session = vm.filteredSessions.first(where: { $0.id == newValue }) ?? vm.sessions.first(where: { $0.id == newValue }) else { return }
            Task {
                await vm.select(session: session)
                isInspectorVisible = true
            }
        }
        .onChange(of: vm.selectedSession?.id) { newValue in
            selectedTableSessionId = newValue
        }
        .sheet(isPresented: $vm.showingComposer) {
            PlannerSessionComposerSheet(vm: vm)
                .frame(minWidth: 920, minHeight: 720)
        }
        .sheet(isPresented: $showingScheduleSettings, onDismiss: {
            Task { await vm.reloadAll() }
        }) {
            TeacherScheduleSettingsPanel(
                selectedClassId: Binding(
                    get: { vm.groupFilterId },
                    set: { vm.groupFilterId = $0 }
                )
            )
            .environmentObject(bridge)
            .frame(minWidth: 980, minHeight: 760)
        }
        .alert("Exportación copiada", isPresented: $showingExportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("El resumen actual de planificación se ha copiado al portapapeles.")
        }
    }

    private var plannerSidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Planificación")
                .font(MacAppStyle.pageTitle)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(MacPlannerSection.allCases) { section in
                    Button {
                        activeSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.callout.weight(activeSection == section ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(activeSection == section ? MacAppStyle.infoTint.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Filtros")
                    .font(MacAppStyle.sectionTitle)

                Picker("Grupo", selection: Binding(
                    get: { vm.groupFilterId },
                    set: { vm.groupFilterId = $0 }
                )) {
                    Text("Todos los grupos").tag(Optional<Int64>.none)
                    ForEach(vm.groups, id: \.id) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }

                TextField("Buscar sesión, unidad u objetivo", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: vm.searchText) { _ in
                        vm.applySearch()
                    }

                Picker("Estado", selection: $vm.sessionFilter) {
                    ForEach(PlannerSessionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Acciones")
                    .font(MacAppStyle.sectionTitle)

                Button("Nueva sesión") {
                    vm.openComposer()
                }
                .buttonStyle(.borderedProminent)

                Button("Copiar semana") {
                    Task { await copyFilteredWeek() }
                }
                .buttonStyle(.bordered)
                .disabled(displayedSessions.isEmpty)

                Button("Mover selección") {
                    Task { await moveFilteredSelection() }
                }
                .buttonStyle(.bordered)
                .disabled(displayedSessions.isEmpty)

                Button("Exportar") {
                    exportCurrentContext()
                }
                .buttonStyle(.bordered)

                Button("Configurar agenda") {
                    showingScheduleSettings = true
                }
                .buttonStyle(.bordered)
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(MacAppStyle.pagePadding)
        .background(MacAppStyle.cardBackground)
    }

    private var plannerHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeSection.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(vm.weekLabel) · \(vm.dateRangeLabel)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await vm.previousWeek() }
                } label: {
                    Image(systemName: "chevron.left")
                }

                Button {
                    Task { await vm.nextWeek() }
                } label: {
                    Image(systemName: "chevron.right")
                }

                Button(isInspectorVisible ? "Ocultar inspector" : "Mostrar inspector") {
                    isInspectorVisible.toggle()
                }
                .buttonStyle(.bordered)

                Button("Agenda") {
                    showingScheduleSettings = true
                }
                .buttonStyle(.bordered)

                Button("Nueva sesión") {
                    vm.openComposer()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var plannerCenterContent: some View {
        switch activeSection {
        case .week:
            MacPlannerWeekBoard(
                vm: vm,
                onSelectSession: { session in
                    Task {
                        await vm.select(session: session)
                        isInspectorVisible = true
                    }
                },
                onDoubleOpenSession: { session in
                    Task {
                        await vm.select(session: session)
                        isInspectorVisible = true
                    }
                }
            )
        case .sessions:
            MacPlannerSessionsTable(
                rows: displayedRows,
                selectedSessionId: $selectedTableSessionId
            )
        case .agenda:
            MacPlannerAgendaView(
                vm: vm,
                groupFilterId: vm.groupFilterId,
                onOpenSettings: { showingScheduleSettings = true }
            )
        }
    }

    private var plannerInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspector")
                        .font(MacAppStyle.sectionTitle)
                    Text(vm.selectedSession?.teachingUnitName ?? "Diario de sesión")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isInspectorVisible = false
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
            }
            .padding(MacAppStyle.innerPadding)

            Divider()

            PlannerJournalDetailPane(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MacAppStyle.cardBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MacAppStyle.cardBorder)
                .frame(width: 0.5)
        }
    }

    private var displayedSessions: [PlanningSession] {
        vm.filteredSessions
    }

    private var displayedRows: [MacPlannerSessionRow] {
        displayedSessions.map { session in
            MacPlannerSessionRow(
                session: session,
                dayLabel: vm.dayLabel(for: Int(session.dayOfWeek)),
                timeLabel: vm.timeLabel(for: Int(session.period)),
                sessionStatusLabel: session.status == .completed ? "Impartida" : "Planificada",
                diaryStatusLabel: diaryStatusLabel(for: session)
            )
        }
    }

    private func diaryStatusLabel(for session: PlanningSession) -> String {
        switch vm.summary(for: session.id)?.status {
        case .completed:
            return "Cerrado"
        case .draft:
            return "Borrador"
        case .empty, .none:
            return "Vacío"
        default:
            return "Vacío"
        }
    }

    private func shouldShowInspector(in totalWidth: CGFloat) -> Bool {
        isInspectorVisible && totalWidth >= 1180
    }

    private func copyFilteredWeek() async {
        guard !displayedSessions.isEmpty else { return }
        vm.selectedSessionIds = Set(displayedSessions.map(\.id))
        await vm.bulkCopyToNextWeek()
    }

    private func moveFilteredSelection() async {
        guard !displayedSessions.isEmpty else { return }
        vm.selectedSessionIds = Set(displayedSessions.map(\.id))
        await vm.bulkMoveOneDay()
    }

    private func exportCurrentContext() {
        let text: String
        if vm.selectedSession != nil {
            text = vm.exportText()
        } else {
            let sessionLines = displayedRows.map {
                "\($0.unit) · \($0.group) · \($0.day) · \($0.time) · \($0.sessionStatus) · \($0.diaryStatus)"
            }
            text = ([ "\(vm.weekLabel) · \(vm.dateRangeLabel)" ] + sessionLines).joined(separator: "\n")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        transientMessage = "Resumen exportado al portapapeles."
        showingExportConfirmation = true
    }
}

private enum MacPlannerSection: String, CaseIterable, Identifiable {
    case week
    case sessions
    case agenda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Semana"
        case .sessions: return "Sesiones"
        case .agenda: return "Agenda"
        }
    }

    var systemImage: String {
        switch self {
        case .week: return "calendar"
        case .sessions: return "tablecells"
        case .agenda: return "clock.badge.checkmark"
        }
    }
}

private struct MacPlannerSessionRow: Identifiable {
    let session: PlanningSession
    let dayLabel: String
    let timeLabel: String
    let sessionStatusLabel: String
    let diaryStatusLabel: String

    var id: Int64 { session.id }
    var unit: String { session.teachingUnitName }
    var group: String { session.groupName }
    var day: String { dayLabel }
    var time: String { timeLabel }
    var sessionStatus: String { sessionStatusLabel }
    var diaryStatus: String { diaryStatusLabel }
}

private struct MacPlannerBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MacAppStyle.successTint)
            Text(message)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.successTint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacPlannerSessionsTable: View {
    let rows: [MacPlannerSessionRow]
    @Binding var selectedSessionId: Int64?

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "Sin sesiones",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No hay sesiones que coincidan con los filtros actuales.")
            )
        } else {
            Table(rows, selection: $selectedSessionId) {
                TableColumn("Unidad") { row in
                    Text(row.unit)
                        .lineLimit(2)
                }
                .width(min: 180, ideal: 240)

                TableColumn("Grupo") { row in
                    Text(row.group)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Día") { row in
                    Text(row.day)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Franja") { row in
                    Text(row.time)
                }
                .width(min: 110, ideal: 120)

                TableColumn("Estado") { row in
                    Text(row.sessionStatus)
                }
                .width(min: 100, ideal: 110)

                TableColumn("Diario") { row in
                    Text(row.diaryStatus)
                }
                .width(min: 90, ideal: 100)
            }
        }
    }
}

private struct MacPlannerWeekBoard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onSelectSession: (PlanningSession) -> Void
    let onDoubleOpenSession: (PlanningSession) -> Void

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("Franja", width: 120)
                    ForEach(vm.visibleWeekdays, id: \.self) { day in
                        headerCell(vm.dayLabel(for: day), width: 250)
                    }
                }

                ForEach(vm.visibleSlots, id: \.period) { slot in
                    HStack(spacing: 0) {
                        VStack(spacing: 6) {
                            Text("P\(slot.period)")
                                .font(.caption.weight(.bold))
                            Text(slot.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120, height: 176)
                        .background(MacAppStyle.subtleFill)

                        ForEach(vm.visibleWeekdays, id: \.self) { day in
                            MacPlannerWeekCell(
                                entries: vm.entries(for: day, period: Int(slot.period)),
                                day: day,
                                period: Int(slot.period),
                                vm: vm,
                                onSelectSession: onSelectSession,
                                onDoubleOpenSession: onDoubleOpenSession
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .frame(width: width, height: 40)
            .background(MacAppStyle.subtleFill)
    }
}

private struct MacPlannerWeekCell: View {
    let entries: [PlannerWeekCellEntry]
    let day: Int
    let period: Int
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onSelectSession: (PlanningSession) -> Void
    let onDoubleOpenSession: (PlanningSession) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                    Text("Libre")
                        .font(.caption.weight(.bold))
                    Text("Doble clic para añadir sesión")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ForEach(entries.prefix(3)) { entry in
                    MacPlannerWeekEntryRow(
                        entry: entry,
                        vm: vm,
                        onSelectSession: onSelectSession,
                        onDoubleOpenSession: onDoubleOpenSession
                    )
                }

                if entries.count > 3 {
                    Text("+\(entries.count - 3) más")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 250, height: 176, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovering ? MacAppStyle.infoTint.opacity(0.08) : MacAppStyle.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovering ? MacAppStyle.infoTint.opacity(0.45) : MacAppStyle.cardBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            if entries.isEmpty {
                vm.openComposer(day: day, period: period)
            }
        }
    }
}

private struct MacPlannerWeekEntryRow: View {
    let entry: PlannerWeekCellEntry
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onSelectSession: (PlanningSession) -> Void
    let onDoubleOpenSession: (PlanningSession) -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(tint)
                    .frame(width: 8, height: 20)
                Text(entry.className)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if entry.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MacAppStyle.successTint)
                }
            }

            Text(entry.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(entry.preview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(entry.kind == .session ? 0.12 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .contextMenu {
            if let session = resolvedSession {
                Button("Abrir diario") {
                    onDoubleOpenSession(session)
                }
                Button("Editar") {
                    vm.openComposer(for: session)
                }
                Button("Duplicar próxima semana") {
                    Task {
                        vm.selectedSessionIds = [session.id]
                        await vm.bulkCopyToNextWeek()
                    }
                }
                Button("Marcar impartida") {
                    Task {
                        await vm.markCompleted(session)
                    }
                }
            }
        }
        .onTapGesture {
            if let session = resolvedSession {
                onSelectSession(session)
            }
        }
        .onTapGesture(count: 2) {
            if let session = resolvedSession {
                onDoubleOpenSession(session)
            } else {
                vm.openComposer(day: entry.dayOfWeek, period: entry.period)
                vm.composerDraft.groupId = entry.classId
            }
        }
    }

    private var resolvedSession: PlanningSession? {
        guard let sessionId = entry.sessionId else { return nil }
        return vm.sessions.first(where: { $0.id == sessionId })
    }
}

private struct MacPlannerAgendaView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let groupFilterId: Int64?
    let onOpenSettings: () -> Void

    private var filteredScheduleSlots: [TeacherScheduleSlot] {
        vm.effectiveScheduleSlots.filter { slot in
            guard let groupFilterId else { return true }
            return slot.schoolClassId == groupFilterId
        }
    }

    private var filteredForecastRows: [PlannerSessionForecast] {
        vm.forecastRows.filter { row in
            guard let groupFilterId else { return true }
            return row.schoolClassId?.int64Value == groupFilterId
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MacMetricCard(label: "Agenda", value: vm.scheduleName, tint: .blue, systemImage: "calendar")
                    MacMetricCard(label: "Curso", value: "\(vm.scheduleStartDate) - \(vm.scheduleEndDate)", tint: .indigo, systemImage: "clock")
                    MacMetricCard(label: "Franjas", value: "\(filteredScheduleSlots.count)", tint: .teal, systemImage: "square.grid.3x3")
                    MacMetricCard(label: "Evaluaciones", value: "\(vm.evaluationPeriods.count)", tint: .orange, systemImage: "chart.bar")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Días lectivos")
                            .font(MacAppStyle.sectionTitle)
                        Spacer()
                        Button("Abrir configuración", action: onOpenSettings)
                            .buttonStyle(.borderedProminent)
                    }

                    Text(vm.activeWeekdaySummary)
                        .font(MacAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Franjas persistentes")
                        .font(MacAppStyle.sectionTitle)

                    if filteredScheduleSlots.isEmpty {
                        Text("Todavía no hay franjas definidas para los filtros activos.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredScheduleSlots, id: \.id) { slot in
                            HStack(spacing: 12) {
                                Text(vm.dayLabel(for: Int(slot.dayOfWeek)))
                                    .font(.caption.weight(.bold))
                                    .frame(width: 48, alignment: .leading)
                                Text("\(slot.startTime)-\(slot.endTime)")
                                    .font(.callout)
                                    .monospacedDigit()
                                    .frame(width: 120, alignment: .leading)
                                Text(vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)")
                                    .frame(width: 180, alignment: .leading)
                                Text(slot.unitLabel ?? slot.subjectLabel)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            if slot.id != filteredScheduleSlots.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Forecast por evaluación")
                        .font(MacAppStyle.sectionTitle)

                    if filteredForecastRows.isEmpty {
                        Text("Todavía no hay previsiones calculadas para la agenda actual.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            MacPlannerForecastHeaderRow()
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                            ForEach(Array(filteredForecastRows.enumerated()), id: \.offset) { index, row in
                                MacPlannerForecastDataRow(row: row)

                                if index < filteredForecastRows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
            .padding(.bottom, 12)
        }
    }
}

private struct MacPlannerForecastHeaderRow: View {
    var body: some View {
        HStack {
            Text("Evaluación").frame(maxWidth: .infinity, alignment: .leading)
            Text("Grupo").frame(maxWidth: .infinity, alignment: .leading)
            Text("Sesiones").frame(width: 80, alignment: .trailing)
            Text("Completadas").frame(width: 100, alignment: .trailing)
            Text("Pendientes").frame(width: 90, alignment: .trailing)
        }
    }
}

private struct MacPlannerForecastDataRow: View {
    let row: PlannerSessionForecast

    var body: some View {
        HStack {
            Text(row.periodName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.className)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.expectedSessions)")
                .frame(width: 80, alignment: .trailing)
            Text("\(row.plannedSessions)")
                .frame(width: 100, alignment: .trailing)
            Text("\(row.remainingSessions)")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}
