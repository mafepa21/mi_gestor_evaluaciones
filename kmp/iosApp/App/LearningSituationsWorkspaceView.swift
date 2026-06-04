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
        HStack(spacing: 0) {
            masterColumn
                .frame(minWidth: 300, idealWidth: 330, maxWidth: 360)
            Divider().opacity(0.2)
            detailColumn
        }
        .background(appPageBackground(for: colorScheme))
        .task { await reload() }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.docx], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                importDraft = try LearningSituationDocumentImportService().preview(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $importDraft) { draft in
            LearningSituationImportPreviewSheet(draft: draft, classes: bridge.classes) { accepted in
                Task { await confirmImport(accepted) }
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
        VStack(spacing: 16) {
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
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Importar situación de aprendizaje")
                }
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar situación", text: $searchText).textFieldStyle(.plain)
            }
            .padding(10)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            if isSelectionMode {
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
        .padding(16)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let situation = selectedSituation {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(situation.subjectLabel.uppercased())
                            .font(.caption.bold())
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
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
            WorkspaceEmptyState(
                title: "Situaciones de aprendizaje",
                subtitle: "Importa un documento Word y asócialo a tus grupos para programar sesiones y preparar evaluación."
            )
        }
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
                Button("Importar nueva versión") {
                    importTargetId = situation.id
                    isImporterPresented = true
                }
                Button("Duplicar y reasignar") {
                    duplicateSituation = situation
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

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documento fuente").font(.headline)
            ForEach(versions, id: \.id) { version in
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
                .padding(12)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
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
                    Label(resource.label.isEmpty ? resource.resourceId : resource.label, systemImage: icon(for: resource.kind))
                        .font(.subheadline)
                }
            }
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
                        Text(criterion.evidence).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
            if !draft.knowledge.isEmpty {
                DisclosureGroup("Saberes básicos") {
                    ForEach(draft.knowledge, id: \.self) {
                        Text($0).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !draft.methodology.isEmpty {
                DisclosureGroup("Metodología") {
                    ForEach(draft.methodology, id: \.self) {
                        Text($0).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !draft.inclusionMeasures.isEmpty {
                DisclosureGroup("Medidas DUA") {
                    ForEach(draft.inclusionMeasures, id: \.self) {
                        Text($0).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            Text(situation.title).font(.headline).lineLimit(2)
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
        .frame(minWidth: 480, minHeight: 460)
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
        .frame(minWidth: 540, minHeight: 560)
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
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Grupo", selection: $classId) {
                    Text("Selecciona grupo").tag(nil as Int64?)
                    ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Desde", selection: $startDate, displayedComponents: .date)
                Section("Secuenciación detallada (opcional)") {
                    Button {
                        isSequenceImporterPresented = true
                    } label: {
                        Label(sequenceDraft == nil ? "Adjuntar secuenciación DOCX" : "Sustituir documento adjunto", systemImage: "doc.badge.plus")
                    }
                    if let draft = sequenceDraft {
                        Label("\(draft.sourceFileName) · \(draft.plans.count) sesiones reconocidas", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(draft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        ForEach(draft.plans.indices, id: \.self) { index in
                            sessionPlanEditor(index: index)
                        }
                        Button("Quitar secuenciación", role: .destructive) { sequenceDraft = nil }
                            .font(.caption)
                    }
                }
                Button("Previsualizar \(situation.sessionCount) sesiones") { Task { await makePreview() } }
                if slots.isEmpty {
                    Text("Selecciona grupo y fecha para distribuir sesiones sobre su horario existente.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Sesiones a crear o sustituir") {
                        ForEach($slots) { $slot in
                            Toggle(slot.label, isOn: $slot.isSelected)
                        }
                        Text("Si ya existe una sesión en una franja seleccionada, se sustituirá por esta situación.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Programar sesiones")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Programar") { Task { await save() } }
                        .disabled(!canProgram)
                }
            }
            .alert("No se puede programar", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("Cerrar", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
        .frame(minWidth: 560, minHeight: 620)
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
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var canProgram: Bool {
        let selectedCount = slots.filter(\.isSelected).count
        guard selectedCount > 0 else { return false }
        guard let sequenceDraft else { return true }
        return sequenceDraft.plans.count == selectedCount
            && !sequenceDraft.plans.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @ViewBuilder
    private func sessionPlanEditor(index: Int) -> some View {
        if let plan = sequenceDraft?.plans[index] {
            DisclosureGroup("Sesión \(plan.sessionNumber) · \(plan.title)") {
                TextField("Título", text: sequenceTextBinding(index: index, keyPath: \.title))
                TextField("Objetivo", text: sequenceTextBinding(index: index, keyPath: \.objective), axis: .vertical)
                    .lineLimit(2...4)
                TextField("Material", text: sequenceTextBinding(index: index, keyPath: \.material), axis: .vertical)
                Text(plan.criteria.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(plan.sessionType) · \(plan.effectiveMinutes) minutos útiles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
            let template = allScheduleSlots.filter { $0.schoolClassId == classId }
            guard !template.isEmpty else {
                errorMessage = "El grupo no tiene franjas horarias configuradas."
                return
            }
            var candidates: [LearningSituationScheduledSlot] = []
            var date = startDate
            let calendar = Calendar.current
            while candidates.count < max(situation.sessionCount, 1) {
                let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
                for slot in template.filter({ Int($0.dayOfWeek) == weekday }).sorted(by: { $0.startTime < $1.startTime }) {
                    candidates.append(LearningSituationScheduledSlot(
                        date: date, period: plannerPeriod(for: slot, allScheduleSlots: allScheduleSlots),
                        teacherScheduleSlotId: slot.id, startTime: slot.startTime, endTime: slot.endTime
                    ))
                    if candidates.count == max(situation.sessionCount, 1) { break }
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
        do {
            try await bridge.programLearningSituationSessions(
                situation: situation, classId: classId, groupName: schoolClass.name,
                scheduledSlots: slots.filter(\.isSelected),
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
    @State private var showingRubricImporter = false
    @State private var showingRubricBuilder = false
    @State private var rubricImportPreview: AppleRubricImportPreview?
    @State private var errorMessage = ""

    private var selectedProposals: [LearningSituationEvaluationDraft] {
        proposals.filter(\.isSelected)
    }

    private var canSave: Bool {
        classId != nil &&
        !selectedProposals.isEmpty &&
        selectedProposals.allSatisfy { $0.rubricId != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Grupo", selection: $classId) {
                    ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                Section("Instrumentos propuestos") {
                    ForEach($proposals) { $proposal in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $proposal.isSelected) {
                                VStack(alignment: .leading) {
                                    Text(proposal.title)
                                    Text(proposal.weightPercent.map { "\(Int($0))%" } ?? "Sin ponderación")
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
                Text(canSave ? "Se crearán evaluaciones y columnas de rúbrica vinculadas." : "Cada instrumento seleccionado necesita una rúbrica antes de crear las columnas.")
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
                isPresented: $showingRubricImporter,
                allowedContentTypes: [.xlsx, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleRubricImportFile(result) }
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
                .frame(minWidth: 1200, minHeight: 820)
            }
            .alert("No se puede crear", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
                Button("Cerrar", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
        .frame(minWidth: 620, minHeight: 560)
        .onAppear {
            classId = initialClassId ?? bridge.classes.first?.id
            proposals = (try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data(situation.payloadJson.utf8)))?.evaluationItems ?? []
            Task {
                try? await bridge.refreshRubrics()
                try? await bridge.refreshRubricClassLinks()
            }
        }
        .appOnChange(of: classId) { newValue in
            if let newValue {
                bridge.selectClass(id: newValue)
                bridge.selectRubricClass(newValue)
            }
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
        }
        bridge.updateRubricName(proposal.title)
        showingRubricBuilder = true
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
            try await bridge.materializeLearningSituationEvaluations(situation: situation, classId: classId, proposals: proposals)
            dismiss()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                HStack(spacing: 12) {
                    previewMetric(title: "Niveles", value: "\(preview.levelCount)", icon: "slider.horizontal.below.square")
                    previewMetric(title: "Criterios", value: "\(preview.criterionCount)", icon: "list.bullet.rectangle")
                    previewMetric(title: "Advertencias", value: "\(preview.warnings.count)", icon: "exclamationmark.triangle")
                }

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
        .frame(width: 600, height: 430)
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
