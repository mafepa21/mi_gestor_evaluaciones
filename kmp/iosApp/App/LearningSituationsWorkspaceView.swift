import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

extension LearningSituation: @retroactive Identifiable {}

struct LearningSituationScheduledSlot: Identifiable {
    let id = UUID()
    let date: Date
    let period: Int
    let teacherScheduleSlotId: Int64?
    let startTime: String
    let endTime: String
    var isSelected = true

    var label: String {
        "\(date.formatted(date: .abbreviated, time: .omitted)) · \(startTime)-\(endTime)"
    }
}

struct LearningSituationScheduleTemplateDescriptor: Hashable {
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
}

enum LearningSituationScheduleProjection {
    static func uniqueTemplateIndices(
        for descriptors: [LearningSituationScheduleTemplateDescriptor]
    ) -> [Int] {
        var seen = Set<LearningSituationScheduleTemplateDescriptor>()
        return descriptors.indices.filter { seen.insert(descriptors[$0]).inserted }
    }

    static func hasDuplicateDestinations(_ slots: [LearningSituationScheduledSlot]) -> Bool {
        let calendar = Calendar(identifier: .iso8601)
        var seen = Set<ScheduledDestination>()
        for slot in slots {
            let destination = ScheduledDestination(
                date: calendar.startOfDay(for: slot.date),
                period: slot.period
            )
            if !seen.insert(destination).inserted {
                return true
            }
        }
        return false
    }

    private struct ScheduledDestination: Hashable {
        let date: Date
        let period: Int
    }
}

private struct LearningSituationBatchImportPresentation: Identifiable {
    let id = UUID()
    let drafts: [LearningSituationImportDraft]
    let failures: [LearningSituationDocumentImportFailure]
}

private struct LearningSituationPhysicalTestsImportSection: View {
    let isImporting: Bool
    let draft: PhysicalTestsImportDraft?
    let importAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        Section("Pruebas físicas") {
            Button(action: importAction) {
                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Validando manifiesto…")
                    }
                } else {
                    Label("Adjuntar manifiesto JSON", systemImage: "figure.run.circle")
                }
            }
            .disabled(isImporting)

            if let draft {
                Label("Manifiesto validado", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(verbatim: draft.assignmentTemplate.batteryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(draft.scoreIsDisabled
                    ? "Diagnóstico: se crearán columnas de marca sin nota, media ni ranking."
                    : "Se crearán las columnas configuradas en el manifiesto.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: removeAction) {
                    Label("Quitar manifiesto", systemImage: "trash")
                }
            } else {
                Text("Importa la batería, las escalas de referencia y las columnas de marca del JSON preparado para esta SA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LearningSituationsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var situations: [LearningSituation] = []
    @State private var selectedSituationId: Int64?
    @State private var searchText = ""
    @State private var subjectFilter = ""
    @State private var termFilter = ""
    @State private var classFilter: Int64?
    @State private var classIdsBySituation: [Int64: Set<Int64>] = [:]
    @State private var isImporterPresented = false
    @State private var importTargetId: Int64?
    @State private var importDraft: LearningSituationImportDraft?
    @State private var batchImport: LearningSituationBatchImportPresentation?
    @State private var versions: [LearningSituationVersion] = []
    @State private var classLinks: [LearningSituationClassLink] = []
    @State private var resources: [LearningSituationLinkedResource] = []
    @State private var scheduleSituation: LearningSituation?
    @State private var evaluationSituation: LearningSituation?
    @State private var duplicateSituation: LearningSituation?
    @State private var errorMessage = ""
    @State private var isSelectionMode = false
    @State private var selectedSituationIds = Set<Int64>()
    @State private var situationToDelete: LearningSituation?
    @State private var showingSingleDeleteAlert = false
    @State private var showingBatchDeleteAlert = false


    private var selectedSituation: LearningSituation? {
        situations.first(where: { $0.id == selectedSituationId })
    }

    private var selectedDraft: LearningSituationImportDraft? {
        selectedSituation.flatMap {
            try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data($0.payloadJson.utf8))
        }
    }

    private var availableSubjects: [String] {
        Array(Set(situations.map(\.subjectLabel).filter { !$0.isEmpty })).sorted()
    }

    private var availableTerms: [String] {
        Array(Set(situations.map(\.termLabel).filter { !$0.isEmpty })).sorted()
    }

    private var filteredSituations: [LearningSituation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return situations.filter { situation in
            let matchesText = query.isEmpty
                || situation.title.localizedCaseInsensitiveContains(query)
                || situation.subjectLabel.localizedCaseInsensitiveContains(query)
                || situation.termLabel.localizedCaseInsensitiveContains(query)
            let matchesSubject = subjectFilter.isEmpty || situation.subjectLabel == subjectFilter
            let matchesTerm = termFilter.isEmpty || situation.termLabel == termFilter
            let matchesClass = classFilter.map { classIdsBySituation[situation.id, default: []].contains($0) } ?? true
            return matchesText && matchesSubject && matchesTerm && matchesClass
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            masterColumn
                .frame(minWidth: 336, idealWidth: 360, maxWidth: 384)
            Color.clear.frame(width: 8)
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appPageBackground(for: colorScheme))
        .task { await reload() }
        .appOnChange(of: selectedSituationId) { _ in
            Task { await reloadDetail() }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.docx], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                handleDocumentSelection(urls)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $importDraft) { draft in
            LearningSituationImportPreviewSheet(draft: draft, classes: bridge.classes) { accepted in
                Task { await confirmImport(accepted) }
            }
        }
        .sheet(item: $batchImport) { batch in
            LearningSituationBatchImportPreviewSheet(
                drafts: batch.drafts,
                failures: batch.failures,
                classes: bridge.classes
            ) { accepted in
                Task {
                    await confirmImportBatch(accepted, initialFailures: batch.failures)
                }
            }
        }
        .sheet(item: $scheduleSituation) { situation in
            LearningSituationScheduleSheet(situation: situation, bridge: bridge, initialClassId: selectedClassId) {
                Task {
                    await reload()
                    scheduleSituation = nil
                }
            }
        }
        .sheet(item: $evaluationSituation) { situation in
            LearningSituationEvaluationSheet(situation: situation, bridge: bridge, initialClassId: selectedClassId) {
                Task {
                    await reload()
                    evaluationSituation = nil
                }
            }
        }
        .sheet(item: $duplicateSituation) { situation in
            LearningSituationDuplicateSheet(situation: situation, classes: bridge.classes) { classIds in
                Task { await duplicate(situation, classIds: classIds) }
            }
        }
        .alert("Situaciones", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("Cerrar", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Eliminar situación", isPresented: $showingSingleDeleteAlert, presenting: situationToDelete) { situation in
            Button("Eliminar", role: .destructive) {
                Task { await performDelete(situationId: situation.id) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { situation in
            Text("¿Estás seguro de que deseas eliminar la situación de aprendizaje \"\(situation.title)\"? Esta acción no se puede deshacer y borrará todos los datos relacionados.")
        }
        .alert("Eliminar situaciones", isPresented: $showingBatchDeleteAlert) {
            Button("Eliminar", role: .destructive) {
                Task { await performBatchDelete() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("¿Estás seguro de que deseas eliminar las \(selectedSituationIds.count) situaciones de aprendizaje seleccionadas? Esta acción no se puede deshacer y borrará todos los datos relacionados.")
        }
    }


    private var masterColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Situaciones")
                    .font(.title2.bold())
                Spacer()
                if isSelectionMode {
                    Button(role: .destructive) {
                        showingBatchDeleteAlert = true
                    } label: {
                        Text("Eliminar (\(selectedSituationIds.count))")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(selectedSituationIds.isEmpty)

                    Button("Cancelar") {
                        isSelectionMode = false
                        selectedSituationIds.removeAll()
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isSelectionMode = true
                        selectedSituationIds.removeAll()
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .help("Seleccionar múltiples")

                    Button {
                        importTargetId = nil
                        isImporterPresented = true
                    } label: {
                        Label("Importar", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Importar situación de aprendizaje")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar situación", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                WorkspaceCompactStat(title: "Situaciones", value: "\(filteredSituations.count)", tint: EvaluationDesign.accent)
                WorkspaceCompactStat(title: "Materias", value: "\(availableSubjects.count)", tint: IOSAppStyle.warning)
                WorkspaceCompactStat(title: "Trimestres", value: "\(availableTerms.count)", tint: EvaluationDesign.success)
            }

            situationFiltersMenu
            if isSelectionMode {
                Text("\(selectedSituationIds.count) seleccionadas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            }
            .padding(24)

            if filteredSituations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: situations.isEmpty ? "doc.badge.plus" : "line.3.horizontal.decrease.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(situations.isEmpty ? "Aún no hay situaciones" : "Ninguna coincide con los filtros")
                        .font(.headline)
                    if situations.isEmpty {
                        Button("Importar situación") {
                            importTargetId = nil
                            isImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Limpiar filtros", action: clearSituationFilters)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if isSelectionMode {
                List(filteredSituations, id: \.id, selection: $selectedSituationIds) { situation in
                    situationRow(for: situation)
                        .tag(situation.id)
                }
                .listStyle(.plain)
            } else {
                List(filteredSituations, id: \.id, selection: $selectedSituationId) { situation in
                    situationRow(for: situation)
                        .tag(situation.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                situationToDelete = situation
                                showingSingleDeleteAlert = true
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.plain)
            }

        }
        .background(appMutedCardBackground(for: colorScheme))
    }

    private var situationFiltersMenu: some View {
        Menu {
            Picker("Grupo", selection: $classFilter) {
                Text("Todos los grupos").tag(nil as Int64?)
                ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Materia", selection: $subjectFilter) {
                Text("Todas las materias").tag("")
                ForEach(availableSubjects, id: \.self) { Text($0).tag($0) }
            }
            Picker("Trimestre", selection: $termFilter) {
                Text("Todos los trimestres").tag("")
                ForEach(availableTerms, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Label("Filtrar", systemImage: "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let situation = selectedSituation {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(situation.subjectLabel.uppercased())
                                .font(.caption.bold())
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Spacer()
                            situationStatusBadge(situation.status)
                        }
                        Text(situation.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text([situation.courseLabel, situation.termLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                    actionRow(for: situation)
                    HStack(spacing: 12) {
                        situationMetric(title: "Sesiones", value: "\(situation.sessionCount)", icon: "calendar")
                        situationMetric(title: "Grupos", value: "\(classLinks.count)", icon: "person.3")
                        situationMetric(title: "Versiones", value: "\(versions.count)", icon: "doc.on.doc")
                    }
                    if !situation.challenge.isEmpty {
                        contentCard(title: "Reto", text: situation.challenge)
                    }
                    if !situation.finalProduct.isEmpty {
                        contentCard(title: "Producto final", text: situation.finalProduct)
                    }
                    if let draft = selectedDraft {
                        curriculumSection(draft)
                    }
                    documentSection
                    linkedSection
                }
                .padding(28)
            }
        } else {
            if situations.isEmpty {
                WorkspaceEmptyState(
                    title: "Situaciones de aprendizaje",
                    subtitle: "Importa un documento Word y asócialo a tus grupos para programar sesiones y preparar evaluación.",
                    systemImage: "doc.text.magnifyingglass",
                    actionTitle: "Importar situación"
                ) {
                    importTargetId = nil
                    isImporterPresented = true
                }
            } else if filteredSituations.isEmpty {
                WorkspaceEmptyState(
                    title: "Sin resultados",
                    subtitle: "No hay situaciones que coincidan con la búsqueda o los filtros activos.",
                    systemImage: "line.3.horizontal.decrease.circle",
                    actionTitle: "Limpiar filtros",
                    action: clearSituationFilters
                )
            } else {
                ContentUnavailableView(
                    "Selecciona una situación",
                    systemImage: "sidebar.left",
                    description: Text("El detalle y sus acciones aparecerán aquí.")
                )
            }
        }
    }

    private func clearSituationFilters() {
        searchText = ""
        subjectFilter = ""
        termFilter = ""
        classFilter = nil
    }

    private func actionRow(for situation: LearningSituation) -> some View {
        HStack(spacing: 10) {
            Button {
                scheduleSituation = situation
            } label: {
                Label("Programar sesiones", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            Button {
                evaluationSituation = situation
            } label: {
                Label("Preparar evaluación", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
            Menu {
                Button("Editar") {
                    if let decoded = draft(for: situation) {
                        importTargetId = situation.id
                        importDraft = decoded
                    }
                }
                Button("Importar nueva versión") {
                    importTargetId = situation.id
                    isImporterPresented = true
                }
                Button("Duplicar y reasignar") {
                    duplicateSituation = situation
                }
                Divider()
                Menu("Estado") {
                    ForEach(LearningSituationStatus.entries, id: \.self) { status in
                        Button {
                            Task { await updateStatus(situation, to: status) }
                        } label: {
                            HStack {
                                Text(situationStatusLabel(status))
                                if situation.status == status {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    situationToDelete = situation
                    showingSingleDeleteAlert = true
                } label: {
                    Label("Eliminar situación", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }

            .buttonStyle(.bordered)
        }
    }

    private func draft(for situation: LearningSituation) -> LearningSituationImportDraft? {
        guard var decoded = try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data(situation.payloadJson.utf8)) else {
            errorMessage = "No se pudo abrir esta situación para editarla."
            return nil
        }
        decoded.title = situation.title
        decoded.courseLabel = situation.courseLabel
        decoded.subjectLabel = situation.subjectLabel
        decoded.termLabel = situation.termLabel
        decoded.sessionCount = Int(situation.sessionCount)
        if let liveClassIds = classIdsBySituation[situation.id], !liveClassIds.isEmpty {
            decoded.selectedClassIds = liveClassIds
        }
        return decoded
    }

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documento fuente").font(.headline)
            ForEach(versions, id: \.id) { version in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Versión \(version.versionNumber) · \(version.originalFileName)")
                                .font(.subheadline.weight(.semibold))
                            Text(String(version.sha256.prefix(12)) + " · \(ByteCountFormatter.string(fromByteCount: version.sizeBytes, countStyle: .file))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let path = version.localPath {
                            ShareLink(item: URL(fileURLWithPath: path)) {
                                Label("Abrir", systemImage: "square.and.arrow.up")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    let warnings = decodeVersionWarnings(version.warningsJson)
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(warnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func decodeVersionWarnings(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    private var linkedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vínculos creados").font(.headline)
            if resources.isEmpty {
                Text("Todavía no se han creado sesiones ni instrumentos desde esta situación.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(resources, id: \.id) { resource in
                    Button {
                        onOpenModule(destination(for: resource.kind), resource.classId?.int64Value, nil)
                    } label: {
                        HStack {
                            Label(resource.label.isEmpty ? resource.resourceId : resource.label, systemImage: icon(for: resource.kind))
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func destination(for kind: LearningSituationResourceKind) -> AppWorkspaceModule {
        switch kind {
        case .teachingUnit, .planningSession: return .planner
        case .evaluation: return .evaluationHub
        case .rubric: return .rubrics
        case .notebookColumn: return .notebook
        default: return .notebook
        }
    }

    private func situationMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func contentCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func curriculumSection(_ draft: LearningSituationImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Desarrollo curricular").font(.headline)
            DisclosureGroup("Criterios y evidencias (\(draft.criteria.count))") {
                ForEach(draft.criteria) { criterion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(criterion.criterion).font(.subheadline.weight(.semibold))
                        if !criterion.evidence.isEmpty {
                            Text(criterion.evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
            if !draft.knowledge.isEmpty {
                DisclosureGroup("Saberes básicos") {
                    bulletList(draft.knowledge)
                }
            }
            if !draft.methodology.isEmpty {
                DisclosureGroup("Metodología") {
                    bulletList(draft.methodology)
                }
            }
            if !draft.inclusionMeasures.isEmpty {
                DisclosureGroup("Medidas DUA") {
                    bulletList(draft.inclusionMeasures)
                }
            }
            ForEach(draft.documentTables ?? []) { table in
                DisclosureGroup(table.title) {
                    documentTable(table)
                }
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Tabla del documento fuente (p.ej. secuenciación de sesiones o adaptaciones) que se
    /// mantiene como tabla real en vez de aplanarla en líneas sueltas.
    private func documentTable(_ table: LearningSituationTableDraft) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    @MainActor
    private func reload() async {
        do {
            situations = try await bridge.learningSituations()
            var updatedClassIds: [Int64: Set<Int64>] = [:]
            for situation in situations {
                let links = try await bridge.learningSituationClassLinks(id: situation.id)
                updatedClassIds[situation.id] = Set(links.map(\.classId))
            }
            classIdsBySituation = updatedClassIds
            if selectedSituationId == nil { selectedSituationId = situations.first?.id }
            await reloadDetail()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reloadDetail() async {
        guard let id = selectedSituationId else {
            versions = []; classLinks = []; resources = []; return
        }
        versions = (try? await bridge.learningSituationVersions(id: id)) ?? []
        classLinks = (try? await bridge.learningSituationClassLinks(id: id)) ?? []
        resources = (try? await bridge.learningSituationResources(id: id)) ?? []
    }

    private func handleDocumentSelection(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if urls.count == 1 {
            do {
                importDraft = try LearningSituationDocumentImportService().preview(from: urls[0])
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        // Una selección múltiple siempre crea situaciones nuevas. La importación de una versión
        // sigue siendo intencionadamente unitaria para no aplicar varios documentos sobre el
        // mismo registro por accidente.
        importTargetId = nil
        let batch = LearningSituationDocumentImportService().preview(from: urls)
        guard !batch.drafts.isEmpty else {
            errorMessage = batchFailureMessage(batch.failures)
            return
        }
        batchImport = LearningSituationBatchImportPresentation(
            drafts: batch.drafts,
            failures: batch.failures
        )
    }

    private func batchFailureMessage(_ failures: [LearningSituationDocumentImportFailure]) -> String {
        guard !failures.isEmpty else { return "No se ha podido leer ningún documento seleccionado." }
        let details = failures.map { "• \($0.fileName): \($0.message)" }.joined(separator: "\n")
        return "No se ha podido leer ningún documento seleccionado:\n\n\(details)"
    }

    @MainActor
    private func confirmImport(_ draft: LearningSituationImportDraft) async {
        do {
            let savedId = try await bridge.confirmLearningSituationImport(draft: draft, existingSituationId: importTargetId)
            importDraft = nil
            importTargetId = nil
            selectedSituationId = savedId
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmImportBatch(
        _ drafts: [LearningSituationImportDraft],
        initialFailures: [LearningSituationDocumentImportFailure]
    ) async {
        batchImport = nil
        importTargetId = nil

        var savedIds: [Int64] = []
        var failures = initialFailures
        for draft in drafts {
            do {
                let savedId = try await bridge.confirmLearningSituationImport(
                    draft: draft,
                    existingSituationId: nil
                )
                savedIds.append(savedId)
            } catch {
                failures.append(
                    LearningSituationDocumentImportFailure(
                        fileName: draft.sourceFileName,
                        message: error.localizedDescription
                    )
                )
            }
        }

        if let savedId = savedIds.last {
            selectedSituationId = savedId
        }
        await reload()

        guard !failures.isEmpty else { return }
        let importedSummary = savedIds.isEmpty
            ? "No se ha importado ninguna situación."
            : "Se han importado \(savedIds.count) situaciones."
        let details = failures.map { "• \($0.fileName): \($0.message)" }.joined(separator: "\n")
        errorMessage = "\(importedSummary)\n\nNo se pudieron gestionar estos documentos:\n\n\(details)"
    }

    @MainActor
    private func duplicate(_ situation: LearningSituation, classIds: [Int64]) async {
        do {
            selectedSituationId = try await bridge.duplicateLearningSituation(situation, classIds: classIds)
            duplicateSituation = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func situationRow(for situation: LearningSituation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                Text(situation.title).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                situationStatusBadge(situation.status)
            }
            Text([situation.courseLabel, situation.subjectLabel, situation.termLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if situation.sessionCount > 0 {
                Label("\(situation.sessionCount) sesiones", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private func performDelete(situationId: Int64) async {
        do {
            try await bridge.deleteLearningSituation(id: situationId)
            if selectedSituationId == situationId {
                selectedSituationId = nil
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performBatchDelete() async {
        do {
            for situationId in selectedSituationIds {
                try await bridge.deleteLearningSituation(id: situationId)
            }
            if let selectedId = selectedSituationId, selectedSituationIds.contains(selectedId) {
                selectedSituationId = nil
            }
            selectedSituationIds.removeAll()
            isSelectionMode = false
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    @MainActor
    private func updateStatus(_ situation: LearningSituation, to status: LearningSituationStatus) async {
        do {
            try await bridge.updateLearningSituationStatus(id: situation.id, status: status)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func situationStatusLabel(_ status: LearningSituationStatus) -> String {
        switch status {
        case .draft: return "Borrador"
        case .active: return "Activa"
        case .archived: return "Archivada"
        default: return "Sin estado"
        }
    }

    private func situationStatusTint(_ status: LearningSituationStatus) -> Color {
        switch status {
        case .draft: return .secondary
        case .active: return EvaluationDesign.success
        case .archived: return .orange
        default: return .secondary
        }
    }

    private func situationStatusBadge(_ status: LearningSituationStatus) -> some View {
        Text(situationStatusLabel(status).uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .foregroundStyle(situationStatusTint(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(situationStatusTint(status).opacity(0.12), in: Capsule())
    }

    private func icon(for kind: LearningSituationResourceKind) -> String {
        switch kind {
        case .teachingUnit: return "folder"
        case .planningSession: return "calendar"
        case .evaluation: return "checklist"
        case .rubric: return "list.clipboard"
        case .notebookColumn: return "tablecells"
        default: return "link"
        }
    }
}

private struct LearningSituationDuplicateSheet: View {
    let situation: LearningSituation
    let classes: [SchoolClass]
    let onConfirm: ([Int64]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassIds: Set<Int64> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva situación") {
                    Text(situation.title)
                    Text("Se conservará el documento de origen y podrás editar la copia después.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Asignar a grupos") {
                    ForEach(classes, id: \.id) { schoolClass in
                        Toggle(schoolClass.name, isOn: Binding(
                            get: { selectedClassIds.contains(schoolClass.id) },
                            set: { selected in
                                if selected { selectedClassIds.insert(schoolClass.id) }
                                else { selectedClassIds.remove(schoolClass.id) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Duplicar y reasignar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicar") { onConfirm(Array(selectedClassIds).sorted()) }
                        .disabled(selectedClassIds.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private struct LearningSituationImportPreviewSheet: View {
    @State var draft: LearningSituationImportDraft
    let classes: [SchoolClass]
    let onConfirm: (LearningSituationImportDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ficha importada") {
                    TextField("Título", text: $draft.title)
                    TextField("Curso", text: $draft.courseLabel)
                    TextField("Materia", text: $draft.subjectLabel)
                    TextField("Trimestre", text: $draft.termLabel)
                    Stepper("Sesiones: \(draft.sessionCount)", value: $draft.sessionCount, in: 0...60)
                }
                Section("Asociar a grupos") {
                    ForEach(classes, id: \.id) { schoolClass in
                        Toggle("\(schoolClass.name) · \(schoolClass.course)º", isOn: Binding(
                            get: { draft.selectedClassIds.contains(schoolClass.id) },
                            set: { isOn in
                                if isOn { draft.selectedClassIds.insert(schoolClass.id) }
                                else { draft.selectedClassIds.remove(schoolClass.id) }
                            }
                        ))
                    }
                }
                Section("Contenido reconocido") {
                    Text("\(draft.criteria.count) criterios · \(draft.evaluationItems.count) elementos de evaluación")
                    if !draft.challenge.isEmpty { Text(draft.challenge).font(.footnote).foregroundStyle(.secondary) }
                }
                if !draft.warnings.isEmpty {
                    Section("Revisión necesaria") {
                        ForEach(draft.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                    }
                }
            }
            .navigationTitle("Revisar importación")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { onConfirm(draft) }
                        .disabled(draft.selectedClassIds.isEmpty || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 560)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private struct LearningSituationBatchImportPreviewSheet: View {
    @State private var drafts: [LearningSituationImportDraft]
    let failures: [LearningSituationDocumentImportFailure]
    let classes: [SchoolClass]
    let onConfirm: ([LearningSituationImportDraft]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        drafts: [LearningSituationImportDraft],
        failures: [LearningSituationDocumentImportFailure],
        classes: [SchoolClass],
        onConfirm: @escaping ([LearningSituationImportDraft]) -> Void
    ) {
        _drafts = State(initialValue: drafts)
        self.failures = failures
        self.classes = classes
        self.onConfirm = onConfirm
    }

    private var readyCount: Int {
        drafts.filter(canImport).count
    }

    private var canConfirm: Bool {
        readyCount == drafts.count && !drafts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resumen") {
                    Label(
                        "\(drafts.count) documentos listos para revisar",
                        systemImage: "doc.on.doc"
                    )
                    if !failures.isEmpty {
                        Text("\(failures.count) documento(s) no se han podido leer y no bloquearán los demás.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !failures.isEmpty {
                    Section("Documentos con errores") {
                        ForEach(failures) { failure in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.fileName)
                                    .font(.subheadline.weight(.semibold))
                                Text(failure.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Situaciones detectadas") {
                    ForEach($drafts) { $draft in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Título", text: $draft.title)
                                TextField("Curso", text: $draft.courseLabel)
                                TextField("Materia", text: $draft.subjectLabel)
                                TextField("Trimestre", text: $draft.termLabel)
                                Stepper("Sesiones: \(draft.sessionCount)", value: $draft.sessionCount, in: 0...60)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Asociar a grupos")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(classes, id: \.id) { schoolClass in
                                        Toggle(
                                            "\(schoolClass.name) · \(schoolClass.course)º",
                                            isOn: classBinding(for: $draft, classId: schoolClass.id)
                                        )
                                    }
                                }

                                Text("\(draft.criteria.count) criterios · \(draft.evaluationItems.count) elementos de evaluación")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                if !draft.warnings.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(draft.warnings, id: \.self) { warning in
                                            Label(warning, systemImage: "exclamationmark.triangle")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: canImport(draft) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(canImport(draft) ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(draft.sourceFileName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(draft.title.isEmpty ? "Sin título" : draft.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar situaciones")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar \(readyCount)") {
                        onConfirm(drafts)
                        dismiss()
                    }
                    .disabled(!canConfirm)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func canImport(_ draft: LearningSituationImportDraft) -> Bool {
        !draft.selectedClassIds.isEmpty
            && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func classBinding(
        for draft: Binding<LearningSituationImportDraft>,
        classId: Int64
    ) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.selectedClassIds.contains(classId) },
            set: { isSelected in
                if isSelected {
                    draft.wrappedValue.selectedClassIds.insert(classId)
                } else {
                    draft.wrappedValue.selectedClassIds.remove(classId)
                }
            }
        )
    }
}

private struct LearningSituationScheduleSheet: View {
    let situation: LearningSituation
    let bridge: KmpBridge
    let initialClassId: Int64?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var classId: Int64?
    @State private var startDate = Date()
    @State private var slots: [LearningSituationScheduledSlot] = []
    @State private var isSequenceImporterPresented = false
    @State private var sequenceDraft: LearningSituationSessionSequenceImportDraft?
    @State private var expandedPlanNumbers: Set<Int> = []
    @State private var scheduleNotice = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scheduleHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        scheduleControlsCard
                        sequenceImportCard
                        slotsPreviewCard
                    }
                    .padding(24)
                }
                scheduleFooter
            }
            .background(EvaluationDesign.surface)
            .navigationTitle("Programar sesiones")
            .alert("No se puede programar", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("Cerrar", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 720)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { classId = initialClassId ?? bridge.classes.first?.id }
        .fileImporter(
            isPresented: $isSequenceImporterPresented,
            allowedContentTypes: [.docx],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    var draft = try LearningSituationSessionSequenceDocumentImportService().preview(from: url)
                    if situation.sessionCount > 0 && draft.plans.count != Int(situation.sessionCount) {
                        draft.warnings.append("La situación indica \(situation.sessionCount) sesiones y el documento contiene \(draft.plans.count).")
                    }
                    sequenceDraft = draft
                    expandedPlanNumbers = Set(draft.plans.prefix(3).map(\.sessionNumber))
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var selectedClassName: String {
        guard let classId, let schoolClass = bridge.classes.first(where: { $0.id == classId }) else { return "Sin grupo" }
        return schoolClass.name
    }

    private var targetSessionCount: Int {
        if let sequenceDraft, !sequenceDraft.plans.isEmpty { return sequenceDraft.plans.count }
        return max(Int(situation.sessionCount), 1)
    }

    private var validImportedSessionCount: Int {
        sequenceDraft?.plans.filter(planHasRequiredFields).count ?? 0
    }

    private var selectedSlotCount: Int {
        slots.filter(\.isSelected).count
    }

    private var statusText: String {
        if let sequenceDraft {
            return "\(sequenceDraft.plans.count) detectadas · \(validImportedSessionCount) listas · \(selectedSlotCount) franjas"
        }
        return "\(selectedSlotCount) franjas seleccionadas"
    }

    private var canProgram: Bool {
        let selectedCount = slots.filter(\.isSelected).count
        guard selectedCount > 0 else { return false }
        guard let sequenceDraft else { return true }
        return sequenceDraft.plans.count == selectedCount
            && !sequenceDraft.plans.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var scheduleHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.accent)
                    .frame(width: 40, height: 40)
                    .background(EvaluationDesign.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Programar sesiones")
                        .font(.title2.weight(.semibold))
                    Text(situation.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(selectedClassName)
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let draft = sequenceDraft {
                HStack(spacing: 8) {
                    metricChip(title: "Documento", value: draft.sourceFileName, systemImage: "doc.text")
                    metricChip(title: "Sesiones", value: "\(draft.plans.count)", systemImage: "number")
                    metricChip(title: "Listas", value: "\(validImportedSessionCount)", systemImage: "checkmark.seal")
                    if !draft.warnings.isEmpty {
                        metricChip(title: "Avisos", value: "\(draft.warnings.count)", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
        .padding(24)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var scheduleControlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Destino")
                .font(.headline)
            HStack(spacing: 16) {
                Picker("Grupo", selection: $classId) {
                    Text("Selecciona grupo").tag(nil as Int64?)
                    ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Desde", selection: $startDate, displayedComponents: .date)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private var sequenceImportCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Secuenciación detallada")
                        .font(.headline)
                    Text(sequenceDraft == nil ? "Adjunta un DOCX para completar títulos, objetivos, tiempos, criterios y desarrollo." : "Revisa lo detectado antes de programar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isSequenceImporterPresented = true
                } label: {
                    Label(sequenceDraft == nil ? "Adjuntar DOCX" : "Sustituir", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                if sequenceDraft != nil {
                    Button(role: .destructive) {
                        sequenceDraft = nil
                        expandedPlanNumbers.removeAll()
                    } label: {
                        Label("Quitar", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let draft = sequenceDraft {
                if !draft.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(draft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(EvaluationDesign.danger)
                        }
                    }
                    .padding(12)
                    .background(EvaluationDesign.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(draft.plans.indices, id: \.self) { index in
                        sessionPlanEditor(index: index)
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private var slotsPreviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Horario")
                        .font(.headline)
                    Text("Distribuye la situación sobre las franjas existentes del grupo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await makePreview() }
                } label: {
                    Label("Previsualizar \(targetSessionCount)", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .disabled(classId == nil)
            }
            if slots.isEmpty {
                Text("Selecciona grupo y fecha para distribuir sesiones sobre su horario existente.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !scheduleNotice.isEmpty {
                        Label(scheduleNotice, systemImage: "checkmark.shield")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(EvaluationDesign.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(EvaluationDesign.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    ForEach($slots) { $slot in
                        Toggle(slot.label, isOn: $slot.isSelected)
                            .padding(12)
                            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Si ya existe una sesión en una franja seleccionada, se sustituirá por esta situación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private var scheduleFooter: some View {
        HStack(spacing: 16) {
            Text(footerMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Programar") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canProgram)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var footerMessage: String {
        if slots.isEmpty { return "Previsualiza el horario antes de programar." }
        if let sequenceDraft, sequenceDraft.plans.count != selectedSlotCount {
            return "El documento contiene \(sequenceDraft.plans.count) sesiones y hay \(selectedSlotCount) franjas seleccionadas."
        }
        if let sequenceDraft, sequenceDraft.plans.contains(where: { !planHasRequiredFields($0) }) {
            return "Completa título y objetivo en todas las sesiones importadas."
        }
        return "Listo para programar \(selectedSlotCount) sesiones."
    }

    @ViewBuilder
    private func sessionPlanEditor(index: Int) -> some View {
        if let plan = sequenceDraft?.plans[index] {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedPlanNumbers.contains(plan.sessionNumber) },
                set: { isExpanded in
                    if isExpanded { expandedPlanNumbers.insert(plan.sessionNumber) }
                    else { expandedPlanNumbers.remove(plan.sessionNumber) }
                }
            )) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Título", text: sequenceTextBinding(index: index, keyPath: \.title))
                        .textFieldStyle(.roundedBorder)
                    TextField("Objetivo", text: sequenceTextBinding(index: index, keyPath: \.objective), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    TextField("Material", text: sequenceTextBinding(index: index, keyPath: \.material), axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                    if !plan.development.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Desarrollo detectado", systemImage: "list.bullet.rectangle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(plan.development) { section in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(section.title)
                                        .font(.caption.weight(.semibold))
                                    ForEach(section.lines.prefix(3), id: \.self) { line in
                                        Text(line)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    if !plan.adaptations.isEmpty {
                        Text(plan.adaptations.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.top, 12)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(plan.sessionNumber)")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .foregroundStyle(planHasRequiredFields(plan) ? EvaluationDesign.accent : EvaluationDesign.danger)
                        .frame(width: 32, height: 32)
                        .background((planHasRequiredFields(plan) ? EvaluationDesign.accent : EvaluationDesign.danger).opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.title.isEmpty ? "Sesión sin título" : plan.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            compactChip(plan.sessionType.isEmpty ? "Tipo pendiente" : plan.sessionType)
                            compactChip(plan.effectiveMinutes > 0 ? "\(plan.effectiveMinutes) min" : "Minutos pendientes")
                            if !plan.criteria.isEmpty {
                                compactChip(plan.criteria.joined(separator: ", "))
                            }
                        }
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
        }
    }

    private func planHasRequiredFields(_ plan: LearningSituationSessionPlanDraft) -> Bool {
        !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !plan.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func metricChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(EvaluationDesign.surfaceSoft, in: Capsule())
    }

    private func compactChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(EvaluationDesign.accentSoft, in: Capsule())
            .foregroundStyle(EvaluationDesign.accent)
    }

    private func sequenceTextBinding(index: Int, keyPath: WritableKeyPath<LearningSituationSessionPlanDraft, String>) -> Binding<String> {
        Binding(
            get: { sequenceDraft?.plans[index][keyPath: keyPath] ?? "" },
            set: { sequenceDraft?.plans[index][keyPath: keyPath] = $0 }
        )
    }

    @MainActor
    private func makePreview() async {
        guard let classId else { return }
        do {
            let schedule = try await bridge.plannerTeacherSchedule()
            let allScheduleSlots = try await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)
            let rawTemplate = allScheduleSlots.filter { $0.schoolClassId == classId }
            let descriptors = rawTemplate.map {
                LearningSituationScheduleTemplateDescriptor(
                    dayOfWeek: Int($0.dayOfWeek),
                    startTime: $0.startTime,
                    endTime: $0.endTime
                )
            }
            let uniqueIndices = LearningSituationScheduleProjection.uniqueTemplateIndices(for: descriptors)
            let template = uniqueIndices.map { rawTemplate[$0] }
            guard !template.isEmpty else {
                errorMessage = "El grupo no tiene franjas horarias configuradas."
                return
            }
            let ignoredDuplicates = rawTemplate.count - template.count
            scheduleNotice = ignoredDuplicates > 0
                ? "Se \(ignoredDuplicates == 1 ? "ha ignorado 1 franja duplicada" : "han ignorado \(ignoredDuplicates) franjas duplicadas") del horario para evitar sustituir sesiones."
                : ""
            var candidates: [LearningSituationScheduledSlot] = []
            var date = startDate
            let calendar = Calendar.current
            while candidates.count < targetSessionCount {
                let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
                for slot in template.filter({ Int($0.dayOfWeek) == weekday }).sorted(by: { $0.startTime < $1.startTime }) {
                    candidates.append(LearningSituationScheduledSlot(
                        date: date, period: plannerPeriod(for: slot, allScheduleSlots: allScheduleSlots),
                        teacherScheduleSlotId: slot.id, startTime: slot.startTime, endTime: slot.endTime
                    ))
                    if candidates.count == targetSessionCount { break }
                }
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            slots = candidates
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct SlotRange: Hashable {
        let startTime: String
        let endTime: String
    }

    private func plannerPeriod(for slot: TeacherScheduleSlot, allScheduleSlots: [TeacherScheduleSlot]) -> Int {
        let defaultSlots = bridge.plannerTimeSlots()
        if let exactDefault = defaultSlots.first(where: {
            $0.startTime == slot.startTime && $0.endTime == slot.endTime
        }) {
            return Int(exactDefault.period)
        }

        let defaultRanges = Set(defaultSlots.map { SlotRange(startTime: $0.startTime, endTime: $0.endTime) })
        let scheduleRanges = allScheduleSlots.map { SlotRange(startTime: $0.startTime, endTime: $0.endTime) }
        let weeklyRanges = bridge.plannerWeeklySlots(classId: nil).map {
            SlotRange(startTime: $0.startTime, endTime: $0.endTime)
        }
        let customRanges = Set(scheduleRanges + weeklyRanges)
            .filter { !defaultRanges.contains($0) }
            .sorted {
                $0.startTime == $1.startTime
                    ? $0.endTime < $1.endTime
                    : $0.startTime < $1.startTime
            }
        let range = SlotRange(startTime: slot.startTime, endTime: slot.endTime)
        let firstCustomPeriod = (defaultSlots.map { Int($0.period) }.max() ?? 0) + 1
        return firstCustomPeriod + (customRanges.firstIndex(of: range) ?? 0)
    }

    @MainActor
    private func save() async {
        guard let classId, let schoolClass = bridge.classes.first(where: { $0.id == classId }) else { return }
        guard canProgram else {
            errorMessage = "Las fichas detalladas deben corresponder a todas las sesiones seleccionadas y contener título y objetivo."
            return
        }
        let selectedSlots = slots.filter(\.isSelected)
        guard !LearningSituationScheduleProjection.hasDuplicateDestinations(selectedSlots) else {
            errorMessage = "Hay dos sesiones destinadas al mismo día y franja. Vuelve a previsualizar para distribuirlas sin sustituciones."
            return
        }
        do {
            try await bridge.programLearningSituationSessions(
                situation: situation, classId: classId, groupName: schoolClass.name,
                scheduledSlots: selectedSlots,
                sequenceDraft: sequenceDraft
            )
            dismiss()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LearningSituationEvaluationSheet: View {
    let situation: LearningSituation
    let bridge: KmpBridge
    let initialClassId: Int64?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var classId: Int64?
    @State private var proposals: [LearningSituationEvaluationDraft] = []
    @State private var activeProposalId: UUID?
    @State private var showingInstrumentImporter = false
    @State private var showingRubricImporter = false
    @State private var showingRubricBuilder = false
    @State private var instrumentImportDraft: LearningSituationAssessmentImportDraft?
    @State private var instrumentImportPreview: LearningSituationAssessmentImportDraft?
    @State private var showingPhysicalTestsImporter = false
    @State private var physicalTestsImportDraft: PhysicalTestsImportDraft?
    @State private var physicalTestsImportPreview: PhysicalTestsImportDraft?
    @State private var instrumentTargetTabs: [NotebookTab] = []
    @State private var selectedInstrumentTargetTabId: String?
    @State private var isNewTargetTabAlertPresented = false
    @State private var newTargetTabName = ""
    @State private var isImportingInstrumentDocument = false
    @State private var isImportingPhysicalTests = false
    @State private var rubricImportPreview: AppleRubricImportPreview?
    @State private var errorMessage = ""

    private var selectedProposals: [LearningSituationEvaluationDraft] {
        proposals.filter(\.isSelected)
    }

    private var canSave: Bool {
        if let physicalTestsImportDraft {
            let hasTargetTab = instrumentTargetTabs.isEmpty || selectedInstrumentTargetTabId != nil
            return classId != nil && !physicalTestsImportDraft.testDefinitions.isEmpty && hasTargetTab
        }
        if instrumentImportDraft != nil {
            let hasTargetTab = instrumentTargetTabs.isEmpty || selectedInstrumentTargetTabId != nil
            return classId != nil && !selectedImportedInstruments.isEmpty && hasTargetTab
        }
        return classId != nil &&
            !selectedProposals.isEmpty &&
            selectedProposals.allSatisfy { $0.rubricId != nil }
    }

    private var selectedImportedInstruments: [AssessmentInstrumentDraft] {
        instrumentImportDraft?.instruments.filter(\.isSelected) ?? []
    }

    private var selectedWeightTotal: Double {
        selectedImportedInstruments.compactMap(\.weightPercent).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Grupo", selection: $classId) {
                    ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                Section("Documento de instrumentos") {
                    Button {
                        showingInstrumentImporter = true
                    } label: {
                        if isImportingInstrumentDocument {
                            HStack(spacing: 8) {
                                ProgressView()
                                    #if os(macOS)
                                    .controlSize(.small)
                                    #endif
                                Text("Leyendo documento…")
                            }
                        } else {
                            Label("Adjuntar documento DOCX", systemImage: "doc.badge.plus")
                        }
                    }
                    .disabled(isImportingInstrumentDocument)
                    if let instrumentImportDraft {
                        Label("\(instrumentImportDraft.instruments.count) instrumentos detectados en \(instrumentImportDraft.sourceFileName)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                LearningSituationPhysicalTestsImportSection(
                    isImporting: isImportingPhysicalTests,
                    draft: physicalTestsImportDraft,
                    importAction: { showingPhysicalTestsImporter = true },
                    removeAction: { physicalTestsImportDraft = nil }
                )
                if physicalTestsImportDraft == nil && instrumentImportDraft == nil {
                    Section("Instrumentos propuestos") {
                        ForEach($proposals) { $proposal in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $proposal.isSelected) {
                                    VStack(alignment: .leading) {
                                        Text(proposal.title)
                                        Text(proposal.weightPercent.map { "\(Int($0))%" } ?? "Sin ponderacion")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }

                                HStack {
                                    rubricStatus(for: proposal)
                                    Spacer()
                                    rubricMenu(for: $proposal)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if physicalTestsImportDraft == nil {
                    Section("Instrumentos detectados") {
                        HStack {
                            Text("\(selectedImportedInstruments.count) seleccionados")
                            Spacer()
                            Text("\(Int(selectedWeightTotal.rounded()))% ponderado")
                                .fontWeight(.semibold)
                                .foregroundStyle(abs(selectedWeightTotal - 100) < 0.5 ? NotebookStyle.successTint : NotebookStyle.warningTint)
                        }
                        .font(.caption)
                        importedInstrumentRows
                    }
                    Section("Pestaña del cuaderno") {
                        if instrumentTargetTabs.isEmpty {
                            Label("Se creará la pestaña Evaluación si el grupo no tiene pestañas.", systemImage: "folder.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Añadir en", selection: $selectedInstrumentTargetTabId) {
                                Text("Selecciona pestaña")
                                    .tag(nil as String?)
                                ForEach(instrumentTargetTabs, id: \.id) { tab in
                                    Text(tab.title).tag(Optional(tab.id))
                                }
                            }
                        }
                        Button {
                            newTargetTabName = ""
                            isNewTargetTabAlertPresented = true
                        } label: {
                            Label("Crear pestaña nueva…", systemImage: "folder.badge.plus")
                        }
                    }
                } else {
                    Section("Pestaña del cuaderno") {
                        if instrumentTargetTabs.isEmpty {
                            Label("Se creará la pestaña Evaluación si el grupo no tiene pestañas.", systemImage: "folder.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Añadir en", selection: $selectedInstrumentTargetTabId) {
                                Text("Selecciona pestaña")
                                    .tag(nil as String?)
                                ForEach(instrumentTargetTabs, id: \.id) { tab in
                                    Text(tab.title).tag(Optional(tab.id))
                                }
                            }
                        }
                        Button {
                            newTargetTabName = ""
                            isNewTargetTabAlertPresented = true
                        } label: {
                            Label("Crear pestaña nueva…", systemImage: "folder.badge.plus")
                        }
                    }
                }
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(canSave ? .green : .secondary)
            }
            .navigationTitle("Preparar evaluación")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear seleccionadas") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showingInstrumentImporter,
                allowedContentTypes: [.docx],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleInstrumentImport(result) }
            }
            .fileImporter(
                isPresented: $showingPhysicalTestsImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                Task { await handlePhysicalTestsImport(result) }
            }
            .fileImporter(
                isPresented: $showingRubricImporter,
                allowedContentTypes: [.xlsx, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleRubricImportFile(result) }
            }
            .sheet(item: $instrumentImportPreview) { preview in
                LearningSituationAssessmentImportPreviewSheet(draft: preview) {
                    instrumentImportPreview = nil
                } confirm: { accepted in
                    physicalTestsImportDraft = nil
                    instrumentImportDraft = accepted
                    instrumentImportPreview = nil
                }
            }
            .sheet(item: $physicalTestsImportPreview) { preview in
                PhysicalTestsImportPreviewSheet(draft: preview) {
                    physicalTestsImportPreview = nil
                } confirm: { accepted in
                    instrumentImportDraft = nil
                    physicalTestsImportDraft = accepted
                    physicalTestsImportPreview = nil
                }
            }
            .sheet(item: $rubricImportPreview) { preview in
                LearningSituationRubricImportPreviewSheet(preview: preview) {
                    rubricImportPreview = nil
                } confirm: {
                    Task { await confirmRubricImport(preview) }
                }
            }
            .sheet(isPresented: $showingRubricBuilder) {
                RubricsBuilderScreen(onSaved: { rubricId in
                    attachRubric(rubricId)
                    showingRubricBuilder = false
                })
                .environmentObject(bridge)
#if os(macOS)
                .frame(minWidth: 1_120, idealWidth: 1_280, maxWidth: 1_600, minHeight: 720, idealHeight: 900)
#else
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            }
            .alert("No se puede crear", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("Cerrar", role: .cancel) {}
            } message: { Text(errorMessage) }
            .alert("Nueva pestaña", isPresented: $isNewTargetTabAlertPresented) {
                TextField("Nombre de la pestaña", text: $newTargetTabName)
                Button("Cancelar", role: .cancel) {}
                Button("Crear") { Task { await createInstrumentTargetTab() } }
            }
        }
#if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
        .onAppear {
            classId = initialClassId ?? bridge.classes.first?.id
            proposals = (try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data(situation.payloadJson.utf8)))?.evaluationItems ?? []
            Task {
                try? await bridge.refreshRubrics()
                try? await bridge.refreshRubricClassLinks()
                await loadNotebookTabsAndRepairImport()
            }
        }
        .appOnChange(of: classId) { newValue in
            if let newValue {
                bridge.selectClass(id: newValue)
                bridge.selectRubricClass(newValue)
            }
            Task { await loadNotebookTabsAndRepairImport() }
        }
    }

    private var statusMessage: String {
        if physicalTestsImportDraft != nil {
            return canSave
                ? "Se crearán la batería, las referencias, la asignación y las columnas de marca en el Cuaderno."
                : "Selecciona un grupo y una pestaña válida antes de importar las pruebas físicas."
        }
        if instrumentImportDraft != nil {
            return canSave
                ? "Se crearan evaluaciones, columnas y vinculos para los instrumentos seleccionados."
                : "Selecciona al menos un instrumento detectado antes de crear."
        }
        return canSave
            ? "Se crearan evaluaciones y columnas de rubrica vinculadas."
            : "Cada instrumento seleccionado necesita una rubrica antes de crear las columnas."
    }

    private var importedInstrumentRows: some View {
        ForEach(instrumentImportDraft?.instruments ?? [], id: \.id) { instrument in
            Toggle(isOn: Binding(
                get: {
                    instrumentImportDraft?.instruments.first(where: { $0.id == instrument.id })?.isSelected ?? false
                },
                set: { newValue in
                    guard let index = instrumentImportDraft?.instruments.firstIndex(where: { $0.id == instrument.id }) else { return }
                    instrumentImportDraft?.instruments[index].isSelected = newValue
                }
            )) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instrument.title)
                            .font(.body.weight(.semibold))
                        Text(importedInstrumentSubtitle(instrument))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let weight = instrument.weightPercent, weight > 0 {
                        Text("\(Int(weight.rounded()))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NotebookStyle.primaryTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NotebookStyle.primaryTint.opacity(0.12), in: Capsule())
                    } else {
                        Text("Auxiliar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func rubricStatus(for proposal: LearningSituationEvaluationDraft) -> some View {
        let rubric = proposal.rubricId.flatMap { rubricId in
            bridge.rubrics.first(where: { $0.rubric.id == rubricId })
        }
        return HStack(spacing: 8) {
            Image(systemName: rubric == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(rubric == nil ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(rubric?.rubric.name ?? "Sin rúbrica asociada")
                    .font(.caption.weight(.semibold))
                if let rubric {
                    Text("\(rubric.criteria.count) criterios")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rubricMenu(for proposal: Binding<LearningSituationEvaluationDraft>) -> some View {
        Menu {
            if availableRubrics.isEmpty {
                Text("No hay rúbricas disponibles")
            } else {
                ForEach(availableRubrics, id: \.rubric.id) { rubric in
                    Button {
                        proposal.wrappedValue.rubricId = rubric.rubric.id
                    } label: {
                        Label(rubric.rubric.name, systemImage: "checklist")
                    }
                }
            }

            Divider()

            Button {
                startRubricBuilder(for: proposal.wrappedValue)
            } label: {
                Label("Crear rúbrica", systemImage: "plus.square")
            }

            Button {
                activeProposalId = proposal.wrappedValue.id
                showingRubricImporter = true
            } label: {
                Label("Importar desde Excel", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label("Rúbrica", systemImage: "ellipsis.circle")
        }
    }

    private var availableRubrics: [RubricDetail] {
        bridge.rubrics
            .filter { rubric in
                guard let classId else { return true }
                let directClassId = rubric.rubric.classId?.int64Value
                return directClassId == nil || directClassId == classId || bridge.rubricClassLinks[rubric.rubric.id]?.contains(classId) == true
            }
            .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    private func startRubricBuilder(for proposal: LearningSituationEvaluationDraft) {
        activeProposalId = proposal.id
        bridge.resetRubricBuilder()
        if let classId {
            bridge.selectRubricClass(classId)
            Task {
                if let unitId = try? await bridge.ensureTeachingUnitForLearningSituation(situation: situation, classId: classId) {
                    bridge.selectRubricTeachingUnit(unitId)
                }
            }
        }
        bridge.updateRubricName(proposal.title)
        showingRubricBuilder = true
    }

    @MainActor
    private func handleInstrumentImport(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            isImportingInstrumentDocument = true
            defer { isImportingInstrumentDocument = false }

            // El acceso con alcance de seguridad y la lectura de bytes son rápidos (documento
            // pequeño) y se hacen aquí, en el hilo que ya tiene la autorización de
            // NSOpenPanel/.fileImporter, para no arriesgar una interacción rara entre
            // startAccessingSecurityScopedResource() y un contexto de tarea aislado.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)

            // El parseo XML en sí (CPU-bound, sin E/S) se despacha a una cola GCD normal
            // -deliberadamente NO Task.detached, que comparte el pool cooperativo de Swift
            // Concurrency con el resto de tareas estructuradas de la app- con un timeout
            // defensivo para que el spinner nunca quede colgado indefinidamente.
            let service = LearningSituationAssessmentInstrumentsImportService()
            instrumentImportPreview = try await withTimeout(seconds: 20) {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            continuation.resume(returning: try service.preview(from: url, data: data))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handlePhysicalTestsImport(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            isImportingPhysicalTests = true
            defer { isImportingPhysicalTests = false }

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let service = PhysicalTestsImportService()
            physicalTestsImportPreview = try await withTimeout(seconds: 20) {
                try service.preview(from: url, data: data)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LearningSituationImportError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    @MainActor
    private func handleRubricImportFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            rubricImportPreview = makeRubricImportPreview(from: rows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmRubricImport(_ preview: AppleRubricImportPreview) async {
        do {
            try await bridge.importRubricDraft(tsv: preview.tsv)
            if let classId {
                bridge.selectRubricClass(classId)
            }
            rubricImportPreview = nil
            showingRubricBuilder = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachRubric(_ rubricId: Int64) {
        guard let activeProposalId,
              let index = proposals.firstIndex(where: { $0.id == activeProposalId }) else { return }
        proposals[index].rubricId = rubricId
        proposals[index].isSelected = true
    }

    @MainActor
    private func loadNotebookTabsAndRepairImport() async {
        guard let classId else {
            instrumentTargetTabs = []
            selectedInstrumentTargetTabId = nil
            return
        }
        do {
            let tabs = try await bridge.learningSituationNotebookTabs(for: classId)
            instrumentTargetTabs = tabs
            if let selectedInstrumentTargetTabId,
               tabs.contains(where: { $0.id == selectedInstrumentTargetTabId }) {
                return
            }
            selectedInstrumentTargetTabId = tabs.first?.id
            try await bridge.repairLearningSituationAssessmentInstrumentImportIfNeeded(classId: classId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createInstrumentTargetTab() async {
        let name = newTargetTabName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let createdId = bridge.createTab(title: name) else { return }
        await loadNotebookTabsAndRepairImport()
        selectedInstrumentTargetTabId = createdId
        newTargetTabName = ""
    }

    private func makeRubricImportPreview(from rows: [[String]]) -> AppleRubricImportPreview {
        let tsv = rows.tsvText
        let nonEmptyRows = rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let header = nonEmptyRows.first ?? []
        let levels = header.dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let criteriaRows = nonEmptyRows.dropFirst().filter { row in
            row.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        var warnings: [String] = []
        if levels.isEmpty {
            warnings.append("No se han detectado niveles en la primera fila.")
        }
        if criteriaRows.isEmpty {
            warnings.append("No se han detectado criterios con descripción.")
        }
        return AppleRubricImportPreview(
            title: "Rúbrica importada",
            levelCount: levels.count,
            criterionCount: criteriaRows.count,
            warnings: warnings,
            tsv: tsv
        )
    }

    @MainActor
    private func save() async {
        guard let classId else { return }
        do {
            if let physicalTestsImportDraft {
                try await bridge.materializeLearningSituationPhysicalTests(
                    situation: situation,
                    classId: classId,
                    draft: physicalTestsImportDraft,
                    targetTabId: selectedInstrumentTargetTabId
                )
            } else if let instrumentImportDraft {
                try await bridge.materializeLearningSituationAssessmentInstruments(
                    situation: situation,
                    classId: classId,
                    draft: instrumentImportDraft,
                    targetTabId: selectedInstrumentTargetTabId
                )
            } else {
                try await bridge.materializeLearningSituationEvaluations(situation: situation, classId: classId, proposals: proposals)
            }
            dismiss()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importedInstrumentSubtitle(_ instrument: AssessmentInstrumentDraft?) -> String {
        guard let instrument else { return "" }
        var parts = [instrument.kind.label]
        if let criterion = instrument.criterionLabel, !criterion.isEmpty { parts.append(criterion) }
        let detailCount = instrument.rubric?.criteria.count ?? instrument.checklistItems.count + instrument.quizQuestions.count + instrument.observationFields.count
        if detailCount > 0 { parts.append("\(detailCount) items") }
        return parts.joined(separator: " · ")
    }
}

private struct LearningSituationAssessmentImportPreviewSheet: View {
    let draft: LearningSituationAssessmentImportDraft
    let cancel: () -> Void
    let confirm: (LearningSituationAssessmentImportDraft) -> Void
    @State private var editableDraft: LearningSituationAssessmentImportDraft
    @State private var selectedInstrumentId: UUID?

    init(
        draft: LearningSituationAssessmentImportDraft,
        cancel: @escaping () -> Void,
        confirm: @escaping (LearningSituationAssessmentImportDraft) -> Void
    ) {
        self.draft = draft
        self.cancel = cancel
        self.confirm = confirm
        _editableDraft = State(initialValue: draft)
        _selectedInstrumentId = State(initialValue: draft.instruments.first?.id)
    }

    private var selectedCount: Int {
        editableDraft.instruments.filter(\.isSelected).count
    }

    private var selectedInstruments: [AssessmentInstrumentDraft] {
        editableDraft.instruments.filter(\.isSelected)
    }

    private var averageCount: Int {
        selectedInstruments.filter(\.countsTowardAverage).count
    }

    private var auxiliaryCount: Int {
        selectedInstruments.count - averageCount
    }

    private var weightedTotal: Double {
        selectedInstruments
            .filter(\.countsTowardAverage)
            .compactMap(\.weightPercent)
            .reduce(0, +)
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if selectedCount == 0 {
            errors.append("Selecciona al menos un instrumento.")
        }
        for instrument in selectedInstruments {
            let title = instrument.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                errors.append("Hay un instrumento seleccionado sin título.")
            }
            if let weight = instrument.weightPercent, weight < 0 {
                errors.append("\(title.isEmpty ? "Instrumento" : title): el peso no puede ser negativo.")
            }
            if instrument.countsTowardAverage && (instrument.weightPercent ?? 0) <= 0 {
                errors.append("\(title): marca peso mayor que 0 o desactiva la media.")
            }
            if instrument.kind == .rubric && (instrument.rubric?.criteria.isEmpty ?? true) {
                errors.append("\(title): la rúbrica no tiene criterios.")
            }
            if instrument.kind.isStudentAuthored && (instrument.rubric?.criteria.isEmpty ?? true) {
                errors.append("\(title): la autoevaluación necesita una tabla de rúbrica con indicadores.")
            }
            if instrument.countsTowardAverage && instrument.scoreStrategy == .none {
                errors.append("\(title): elige una estrategia de puntuación.")
            }
            if instrument.countsTowardAverage &&
                instrument.scoreStrategy == .checklistProportional &&
                instrument.checklistItems.isEmpty {
                errors.append("\(title): la checklist proporcional necesita ítems para calcular la nota.")
            }
            if instrument.countsTowardAverage &&
                instrument.scoreStrategy == .observationScale1To4 &&
                !hasObservationScale1To4(instrument) {
                errors.append("\(title): la observación necesita escala 1-4.")
            }
        }
        return errors
    }

    private var canConfirm: Bool {
        validationErrors.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                ScrollView {
                    reviewContent(isWide: proxy.size.width >= 760)
                        .padding(24)
                }
                .background(appSecondarySystemBackgroundColor().opacity(0.35))
            }

            footer
        }
        .background(IOSAppStyle.pageBackground)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 620)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            ensureSelectedInstrument()
        }
    }

    private var selectedIndex: Int? {
        guard let selectedInstrumentId,
              let index = editableDraft.instruments.firstIndex(where: { $0.id == selectedInstrumentId }) else {
            return editableDraft.instruments.indices.first
        }
        return index
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Revisar instrumentos")
                    .font(.title2.weight(.bold))
                Text(draft.sourceFileName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar revisión de instrumentos")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func reviewContent(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            metricsStrip

            if isWide {
                HStack(alignment: .top, spacing: 24) {
                    instrumentList
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                    detailPanel
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    instrumentList
                    detailPanel
                }
            }

            gradingFormulaPanel

            diagnosticsPanel
        }
    }

    // D2: la fórmula de calificación final del documento ("Nota SA = Rúbrica... (40%) +
    // Rejilla... (35%) + ...") se parseaba (`gradingFormula`) pero no se mostraba en ningún
    // sitio; el docente no tenía forma de contrastarla con los instrumentos detectados salvo
    // leyendo el DOCX aparte. Se enseña junto al resumen de pesos de la hoja de revisión.
    @ViewBuilder
    private var gradingFormulaPanel: some View {
        if let gradingFormula = editableDraft.gradingFormula, !gradingFormula.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Fórmula de calificación del documento", systemImage: "function")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(gradingFormula)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var metricsStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                previewMetric("Detectados", value: "\(editableDraft.instruments.count)")
                previewMetric("Seleccionados", value: "\(selectedCount)")
                previewMetric("Computan", value: "\(averageCount)")
                previewMetric("Auxiliares", value: "\(auxiliaryCount)")
                previewMetric("Peso", value: "\(Int(weightedTotal.rounded()))%")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], alignment: .leading, spacing: 16) {
                previewMetric("Detectados", value: "\(editableDraft.instruments.count)")
                previewMetric("Seleccionados", value: "\(selectedCount)")
                previewMetric("Computan", value: "\(averageCount)")
                previewMetric("Auxiliares", value: "\(auxiliaryCount)")
                previewMetric("Peso", value: "\(Int(weightedTotal.rounded()))%")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var instrumentList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Instrumentos detectados")
                    .font(.headline)
                Spacer()
                Button(selectedCount == editableDraft.instruments.count ? "Deseleccionar" : "Seleccionar todos") {
                    let shouldSelectAll = selectedCount != editableDraft.instruments.count
                    for index in editableDraft.instruments.indices {
                        editableDraft.instruments[index].isSelected = shouldSelectAll
                    }
                    ensureSelectedInstrument()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                ForEach(Array(editableDraft.instruments.indices), id: \.self) { index in
                    instrumentRow(index: index)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Detalle")
                    .font(.headline)
                Spacer()
                if let selectedIndex {
                    Text(editableDraft.instruments[selectedIndex].isSelected ? "Incluido" : "Excluido")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(editableDraft.instruments[selectedIndex].isSelected ? NotebookStyle.successTint : .secondary)
                }
            }

            if let selectedIndex {
                editor(for: selectedIndex)
            } else {
                NotebookContentUnavailableView(
                    "Sin instrumentos",
                    systemImage: "doc.text",
                    description: "No se han detectado instrumentos editables en este DOCX."
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var diagnosticsPanel: some View {
        if !validationErrors.isEmpty || !editableDraft.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !validationErrors.isEmpty {
                    diagnosticsGroup(
                        title: "Revisión necesaria",
                        icon: "xmark.octagon.fill",
                        tint: NotebookStyle.warningTint,
                        items: validationErrors
                    )
                }

                if !editableDraft.warnings.isEmpty {
                    diagnosticsGroup(
                        title: "Avisos del documento",
                        icon: "exclamationmark.triangle.fill",
                        tint: NotebookStyle.warningTint,
                        items: editableDraft.warnings
                    )
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label(footerMessage, systemImage: canConfirm ? "checkmark.circle.fill" : "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canConfirm ? NotebookStyle.successTint : .secondary)
                .lineLimit(2)

            Spacer()

            Button("Cancelar", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                confirm(editableDraft)
            } label: {
                Label("Usar seleccionados", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConfirm)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var footerMessage: String {
        if canConfirm {
            return "\(selectedCount) instrumentos listos para crear en el cuaderno."
        }
        return validationErrors.first ?? "Revisa la selección antes de continuar."
    }

    private func previewMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func instrumentRow(index: Int) -> some View {
        let instrument = editableDraft.instruments[index]
        let isActive = instrument.id == selectedInstrumentId
        let itemCount = detailCount(for: instrument)

        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $editableDraft.instruments[index].isSelected)
                .labelsHidden()
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .accessibilityLabel("Incluir \(instrument.title.isEmpty ? "instrumento sin título" : instrument.title)")

            VStack(alignment: .leading, spacing: 8) {
                Text(instrument.title.isEmpty ? "Sin título" : instrument.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                instrumentTags(for: instrument, itemCount: itemCount)
            }

            Spacer(minLength: 8)

            Image(systemName: isActive ? "slider.horizontal.3" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? NotebookStyle.primaryTint : .secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(isActive ? NotebookStyle.primaryTint.opacity(0.10) : NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? NotebookStyle.primaryTint.opacity(0.45) : NotebookStyle.softBorder.opacity(0.75), lineWidth: 1)
        }
        .onTapGesture {
            selectedInstrumentId = instrument.id
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
    }

    private func editor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Incluir este instrumento", isOn: $editableDraft.instruments[index].isSelected)
                .toggleStyle(.switch)
                .tint(NotebookStyle.primaryTint)

            VStack(alignment: .leading, spacing: 8) {
                Text("Título")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Título", text: $editableDraft.instruments[index].title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                pickerField(title: "Tipo") {
                    Picker("Tipo", selection: kindBinding(for: index)) {
                        ForEach(AssessmentInstrumentKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Peso")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Peso %", text: weightBinding(for: index))
                        .textFieldStyle(.roundedBorder)
                        .appKeyboardType(.decimalPad)
                }
                .frame(maxWidth: 160)
            }

            Toggle("Cuenta para la media", isOn: $editableDraft.instruments[index].countsTowardAverage)
                .toggleStyle(.switch)
                .tint(NotebookStyle.primaryTint)

            HStack(spacing: 16) {
                pickerField(title: "Estrategia") {
                    Picker("Estrategia", selection: $editableDraft.instruments[index].scoreStrategy) {
                        ForEach(AssessmentInstrumentScoreStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.label).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)
                }

                pickerField(title: "Vacías") {
                    Picker("Vacías", selection: $editableDraft.instruments[index].emptyCellPolicy) {
                        ForEach(AssessmentInstrumentEmptyCellPolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let note = editableDraft.instruments[index].note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Anotaciones de contexto", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.top, 8)
            }

            if editableDraft.instruments[index].kind == .rubric,
               let rubric = editableDraft.instruments[index].rubric {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estructura de Rúbrica").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(rubric.criteria, id: \.title) { criterion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(criterion.title)
                                .font(.caption.weight(.bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(criterion.descriptors.enumerated()), id: \.offset) { levelIndex, desc in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(levelIndex < rubric.levels.count ? rubric.levels[levelIndex].label : "Nivel \(levelIndex + 1)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(NotebookStyle.primaryTint)
                                            Text(desc)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 120, alignment: .leading)
                                        .padding(6)
                                        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            
            if editableDraft.instruments[index].kind == .quizQuestions,
               !editableDraft.instruments[index].quizQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preguntas Detectadas (\(editableDraft.instruments[index].quizQuestions.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(editableDraft.instruments[index].quizQuestions.enumerated()), id: \.offset) { qIndex, question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(qIndex + 1). \(question.questionText)")
                                .font(.caption.weight(.semibold))
                            if !question.options.isEmpty {
                                Text("Opciones: " + question.options.joined(separator: " / "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Respuesta abierta / rellenar hueco")
                                    .font(.system(size: 10).italic())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if (editableDraft.instruments[index].kind == .checklist || editableDraft.instruments[index].kind == .submissionChecklist),
               !editableDraft.instruments[index].checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Items de Checklist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(editableDraft.instruments[index].checklistItems, id: \.title) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(.caption)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            Text(subtitle(for: editableDraft.instruments[index]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func pickerField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instrumentTag(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NotebookStyle.surfaceSoft, in: Capsule(style: .continuous))
    }

    private func instrumentTags(for instrument: AssessmentInstrumentDraft, itemCount: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
            instrumentTag(instrument.kind.label, icon: "rectangle.grid.1x2")
            instrumentTag(instrument.countsTowardAverage ? "Cuenta" : "Auxiliar", icon: instrument.countsTowardAverage ? "sum" : "paperclip")
            instrumentTag(instrument.weightPercent.map { "\(Int($0.rounded()))%" } ?? "Sin peso", icon: "percent")
            if itemCount > 0 {
                instrumentTag("\(itemCount) items", icon: "checklist")
            }
        }
    }

    private func diagnosticsGroup(title: String, icon: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ensureSelectedInstrument() {
        if let selectedInstrumentId,
           editableDraft.instruments.contains(where: { $0.id == selectedInstrumentId }) {
            return
        }
        selectedInstrumentId = editableDraft.instruments.first?.id
    }

    private func detailCount(for instrument: AssessmentInstrumentDraft) -> Int {
        if instrument.kind == .quizQuestions {
            return instrument.quizQuestions.count
        }
        return instrument.rubric?.criteria.count ?? instrument.checklistItems.count + instrument.observationFields.count
    }

    private func kindBinding(for index: Int) -> Binding<AssessmentInstrumentKind> {
        Binding {
            editableDraft.instruments[index].kind
        } set: { newKind in
            editableDraft.instruments[index].kind = newKind
            let strategy = defaultScoreStrategy(for: editableDraft.instruments[index])
            editableDraft.instruments[index].scoreStrategy = strategy
            editableDraft.instruments[index].countsTowardAverage = strategy != .none &&
                (editableDraft.instruments[index].weightPercent ?? 0) > 0
        }
    }

    private func weightBinding(for index: Int) -> Binding<String> {
        Binding {
            guard let weight = editableDraft.instruments[index].weightPercent else { return "" }
            if weight.rounded() == weight {
                return String(Int(weight))
            }
            return String(weight)
        } set: { newValue in
            let normalized = newValue.replacingOccurrences(of: ",", with: ".")
            editableDraft.instruments[index].weightPercent = Double(normalized)
            if (editableDraft.instruments[index].weightPercent ?? 0) <= 0 {
                editableDraft.instruments[index].countsTowardAverage = false
            }
        }
    }

    private func defaultScoreStrategy(for instrument: AssessmentInstrumentDraft) -> AssessmentInstrumentScoreStrategy {
        guard (instrument.weightPercent ?? 0) > 0 else { return .none }
        switch instrument.kind {
        case .rubric:
            return .rubric
        case .observationGrid:
            return hasObservationScale1To4(instrument) ? .observationScale1To4 : .none
        case .selfAssessment, .peerAssessment:
            // La rúbrica que rellena el alumnado se responde en escala 1-4 y su nota se deriva
            // igual que la de una rejilla de observación.
            return .observationScale1To4
        case .checklist, .submissionChecklist, .teacherObservation:
            return .none
        case .quizQuestions:
            return .quizPercentCorrect
        }
    }

    private func hasObservationScale1To4(_ instrument: AssessmentInstrumentDraft) -> Bool {
        // En un instrumento de autoevaluación/coevaluación los indicadores 1-4 no viven en
        // `observationFields` sino en la tabla de rúbrica (`rubric.criteria`), que es de donde
        // salen los ítems `rub_<n>` en escala 1-4. Sin este caso, la validación del import
        // bloqueaba con "la observación necesita escala 1-4" un instrumento que sí la tiene.
        if instrument.kind.isStudentAuthored {
            return !(instrument.rubric?.criteria.isEmpty ?? true)
        }
        return instrument.observationFields.contains { field in
            guard let scale = field.scaleLabel else { return false }
            return scale.contains("1") && scale.contains("4")
        }
    }

    private func subtitle(for instrument: AssessmentInstrumentDraft) -> String {
        var parts = [instrument.kind.label]
        if let criterion = instrument.criterionLabel, !criterion.isEmpty { parts.append(criterion) }
        if instrument.countsTowardAverage {
            parts.append("Cuenta")
        } else {
            parts.append("No cuenta")
        }
        parts.append(instrument.weightPercent.map { "\(Int($0.rounded()))%" } ?? "Auxiliar")
        parts.append(instrument.scoreStrategy.label)
        parts.append(instrument.emptyCellPolicy.label)
        let detailCount = instrument.rubric?.criteria.count ?? instrument.checklistItems.count + instrument.quizQuestions.count + instrument.observationFields.count
        if detailCount > 0 { parts.append("\(detailCount) items") }
        return parts.joined(separator: " · ")
    }
}

private struct LearningSituationRubricImportPreviewSheet: View {
    let preview: AppleRubricImportPreview
    let cancel: () -> Void
    let confirm: () -> Void

    private var canConfirm: Bool {
        preview.levelCount > 0 && preview.criterionCount > 0
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                rubricMetrics

                VStack(alignment: .leading, spacing: 12) {
                    Text("Validación")
                        .font(.headline)
                    if preview.warnings.isEmpty {
                        Label("Estructura lista para revisar en el editor.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(preview.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Importar rúbrica")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Abrir en editor", action: confirm)
                        .disabled(!canConfirm)
                }
            }
        }
        #if os(macOS)
        .frame(width: 600, height: 430)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var rubricMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                previewMetric(title: "Niveles", value: "\(preview.levelCount)", icon: "slider.horizontal.below.square")
                previewMetric(title: "Criterios", value: "\(preview.criterionCount)", icon: "list.bullet.rectangle")
                previewMetric(title: "Advertencias", value: "\(preview.warnings.count)", icon: "exclamationmark.triangle")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: 16)], alignment: .leading, spacing: 16) {
                previewMetric(title: "Niveles", value: "\(preview.levelCount)", icon: "slider.horizontal.below.square")
                previewMetric(title: "Criterios", value: "\(preview.criterionCount)", icon: "list.bullet.rectangle")
                previewMetric(title: "Advertencias", value: "\(preview.warnings.count)", icon: "exclamationmark.triangle")
            }
        }
    }

    private func previewMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
