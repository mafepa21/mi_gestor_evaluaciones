import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

struct LearningSituationPhysicalTestsImportSection: View {
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

struct LearningSituationEvaluationSheet: View {
    let situation: LearningSituation
    let bridge: KmpBridge
    let initialClassId: Int64?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassIds: Set<Int64> = []
    @State private var linkedClassIds: Set<Int64> = []
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
    @State private var targetTabTitle: String = "Evaluación"
    @State private var availableTabTitles: [String] = []
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
        guard !selectedClassIds.isEmpty else { return false }
        let hasTargetTab = !targetTabTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let physicalTestsImportDraft {
            return !physicalTestsImportDraft.testDefinitions.isEmpty && hasTargetTab
        }
        if instrumentImportDraft != nil {
            return !selectedImportedInstruments.isEmpty && hasTargetTab
        }
        return !selectedProposals.isEmpty &&
            selectedProposals.allSatisfy { $0.rubricId != nil } &&
            hasTargetTab
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
                Section("Grupos destino (\(selectedClassIds.count) seleccionados)") {
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Toggle(isOn: Binding(
                            get: { selectedClassIds.contains(schoolClass.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedClassIds.insert(schoolClass.id)
                                } else {
                                    selectedClassIds.remove(schoolClass.id)
                                }
                                Task { await loadTabTitles() }
                            }
                        )) {
                            HStack {
                                Text(schoolClass.name)
                                Spacer()
                                if linkedClassIds.contains(schoolClass.id) {
                                    Text("Asociado a SA")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(EvaluationDesign.accentSoft, in: Capsule())
                                        .foregroundStyle(EvaluationDesign.accent)
                                }
                            }
                        }
                    }
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
                }
                Section("Pestaña del cuaderno") {
                    if availableTabTitles.isEmpty {
                        Label("Se creará la pestaña \"\(targetTabTitle)\" en los \(selectedClassIds.count) grupos.", systemImage: "folder.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Pestaña destino", selection: $targetTabTitle) {
                            ForEach(availableTabTitles, id: \.self) { title in
                                Text(title).tag(title)
                            }
                        }
                        Text("Se añadirán las columnas en la pestaña \"\(targetTabTitle)\" en cada grupo (creándola si aún no existe).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        newTargetTabName = ""
                        isNewTargetTabAlertPresented = true
                    } label: {
                        Label("Crear pestaña nueva…", systemImage: "folder.badge.plus")
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
                    Button("Crear en \(selectedClassIds.count) grupo\(selectedClassIds.count == 1 ? "" : "s")") {
                        Task { await save() }
                    }
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
            proposals = (try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data(situation.payloadJson.utf8)))?.evaluationItems ?? []
            Task {
                do {
                    let links = try await bridge.learningSituationClassLinks(id: situation.id)
                    let linked = Set(links.map(\.classId))
                    linkedClassIds = linked
                    if !linked.isEmpty {
                        selectedClassIds = linked
                    } else if let initial = initialClassId {
                        selectedClassIds = [initial]
                    } else if let first = bridge.classes.first?.id {
                        selectedClassIds = [first]
                    }
                } catch {
                    errorMessage = LearningSituationScheduleLoad.linksFailure
                }
                try? await bridge.refreshRubrics()
                try? await bridge.refreshRubricClassLinks()
                await loadTabTitles()
            }
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
                if selectedClassIds.isEmpty { return true }
                let directClassId = rubric.rubric.classId?.int64Value
                if directClassId == nil { return true }
                if let direct = directClassId, selectedClassIds.contains(direct) { return true }
                if let links = bridge.rubricClassLinks[rubric.rubric.id], !links.isDisjoint(with: selectedClassIds) {
                    return true
                }
                return false
            }
            .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    private func startRubricBuilder(for proposal: LearningSituationEvaluationDraft) {
        activeProposalId = proposal.id
        bridge.resetRubricBuilder()
        if let firstClassId = selectedClassIds.first {
            bridge.selectRubricClass(firstClassId)
            Task {
                if let unitId = try? await bridge.ensureTeachingUnitForLearningSituation(situation: situation, classId: firstClassId) {
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
            if let firstClassId = selectedClassIds.first {
                bridge.selectRubricClass(firstClassId)
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
    private func loadTabTitles() async {
        var titlesSet = Set<String>()
        for id in selectedClassIds {
            if let tabs = try? await bridge.learningSituationNotebookTabs(for: id) {
                for tab in tabs {
                    titlesSet.insert(tab.title)
                }
            }
        }
        let titles = Array(titlesSet).sorted()
        availableTabTitles = titles
        if !titles.contains(targetTabTitle) {
            if let first = titles.first {
                targetTabTitle = first
            } else if targetTabTitle.isEmpty {
                targetTabTitle = "Evaluación"
            }
        }
    }

    @MainActor
    private func createInstrumentTargetTab() async {
        let name = newTargetTabName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !availableTabTitles.contains(name) {
            availableTabTitles.append(name)
        }
        targetTabTitle = name
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
        guard !selectedClassIds.isEmpty else { return }
        let target = targetTabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTabName = target.isEmpty ? "Evaluación" : target
        do {
            for classId in selectedClassIds {
                if let physicalTestsImportDraft {
                    try await bridge.materializeLearningSituationPhysicalTests(
                        situation: situation,
                        classId: classId,
                        draft: physicalTestsImportDraft,
                        targetTabId: resolvedTabName
                    )
                } else if let instrumentImportDraft {
                    try await bridge.materializeLearningSituationAssessmentInstruments(
                        situation: situation,
                        classId: classId,
                        draft: instrumentImportDraft,
                        targetTabId: resolvedTabName
                    )
                } else {
                    try await bridge.materializeLearningSituationEvaluations(
                        situation: situation,
                        classId: classId,
                        proposals: proposals,
                        targetTabId: resolvedTabName
                    )
                }
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

struct LearningSituationRubricImportPreviewSheet: View {
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
