import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

/// Origen de lo que se va a crear en el Cuaderno. Un único selector sustituye a las tres
/// secciones excluyentes de antes.
enum LearningSituationEvaluationSource: String, CaseIterable, Identifiable {
    case situation
    case wordDocument
    case physicalTests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .situation: return "De la situación"
        case .wordDocument: return "Documento Word"
        case .physicalTests: return "Pruebas físicas"
        }
    }
}

/// Pantallas que se apilan dentro de la hoja (con «Atrás»), en vez de hojas encima de hojas.
enum LearningSituationEvaluationRoute: Hashable {
    case instrumentsReview
    case physicalTestsReview
}

struct LearningSituationEvaluationSheet: View {
    let situation: LearningSituation
    let bridge: KmpBridge
    let initialClassId: Int64?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: LearningSituationEvaluationSource = .situation
    @State private var path: [LearningSituationEvaluationRoute] = []
    @State private var selectedClassIds: Set<Int64> = []
    @State private var linkedClassIds: Set<Int64> = []
    @State private var proposals: [LearningSituationEvaluationDraft] = []
    @State private var activeProposalId: UUID?
    @State private var showingInstrumentImporter = false
    @State private var showingRubricImporter = false
    @State private var showingRubricBuilder = false
    @State private var instrumentImportDraft: LearningSituationAssessmentImportDraft?
    @State private var instrumentReviewDraft: LearningSituationAssessmentImportDraft?
    @State private var showingPhysicalTestsImporter = false
    @State private var physicalTestsImportDraft: PhysicalTestsImportDraft?
    @State private var physicalTestsReviewDraft: PhysicalTestsImportDraft?
    @State private var targetTabTitle: String = "Evaluación"
    @State private var availableTabTitles: [String] = []
    @State private var isCreatingNewTab = false
    @State private var newTargetTabName = ""
    @State private var isImportingInstrumentDocument = false
    @State private var isImportingPhysicalTests = false
    @State private var rubricImportSummaries: [UUID: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage = ""
    @ScaledMetric(relativeTo: .body) private var minimumTapSize: CGFloat = 44

    private var selectedProposals: [LearningSituationEvaluationDraft] {
        proposals.filter(\.isSelected)
    }

    private var hasTargetTab: Bool {
        !targetTabTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        guard !selectedClassIds.isEmpty, !isSaving else { return false }
        switch source {
        case .physicalTests:
            guard let physicalTestsImportDraft else { return false }
            return !physicalTestsImportDraft.testDefinitions.isEmpty && hasTargetTab
        case .wordDocument:
            guard instrumentImportDraft != nil else { return false }
            return !selectedImportedInstruments.isEmpty && hasTargetTab
        case .situation:
            return !selectedProposals.isEmpty &&
                selectedProposals.allSatisfy { $0.rubricId != nil } &&
                hasTargetTab
        }
    }

    private var selectedImportedInstruments: [AssessmentInstrumentDraft] {
        instrumentImportDraft?.instruments.filter(\.isSelected) ?? []
    }

    private var selectedWeightTotal: Double {
        selectedImportedInstruments.compactMap(\.weightPercent).reduce(0, +)
    }

    private var selectedProposalWeightTotal: Double {
        selectedProposals.compactMap(\.weightPercent).reduce(0, +)
    }

    /// Solo se avisa si hay pesos y no suman 100 %.
    private var proposalWeightsAreOff: Bool {
        selectedProposals.contains { $0.weightPercent != nil } && abs(selectedProposalWeightTotal - 100) >= 0.5
    }

    private var importedWeightsAreOff: Bool {
        !selectedImportedInstruments.isEmpty && abs(selectedWeightTotal - 100) >= 0.5
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    // Segmentado si cabe; si no (iPhone, letra grande), menú.
                    ViewThatFits(in: .horizontal) {
                        sourcePicker
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        sourcePicker
                            .pickerStyle(.menu)
                    }
                } header: {
                    Text("¿De dónde salen los instrumentos?")
                }

                groupsSection
                targetTabSection

                switch source {
                case .situation:
                    situationProposalsSection
                case .wordDocument:
                    wordDocumentSection
                case .physicalTests:
                    physicalTestsSection
                }

                if !errorMessage.isEmpty {
                    Section {
                        LearningSituationInlineNotice(
                            kind: .error,
                            message: errorMessage,
                            actionTitle: "Cerrar aviso"
                        ) {
                            errorMessage = ""
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Evaluar")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationDestination(for: LearningSituationEvaluationRoute.self) { route in
                switch route {
                case .instrumentsReview:
                    if let instrumentReviewDraft {
                        LearningSituationAssessmentReviewView(draft: instrumentReviewDraft) { accepted in
                            instrumentImportDraft = accepted
                            source = .wordDocument
                            path.removeAll()
                        }
                    }
                case .physicalTestsReview:
                    if let physicalTestsReviewDraft {
                        PhysicalTestsImportPreviewSheet(
                            draft: physicalTestsReviewDraft,
                            embedsInNavigationStack: false,
                            confirmTitle: "Añadir pruebas"
                        ) {
                            path.removeAll()
                        } confirm: { accepted in
                            physicalTestsImportDraft = accepted
                            source = .physicalTests
                            path.removeAll()
                        }
                    }
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
            // El editor de rúbricas es otro módulo y en Mac necesita mucho ancho: sigue en hoja.
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
        }
#if os(macOS)
        .frame(minWidth: 620, minHeight: 600)
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

    private var sourcePicker: some View {
        Picker("Origen", selection: $source) {
            ForEach(LearningSituationEvaluationSource.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .accessibilityLabel("Origen de la evaluación")
    }

    // MARK: - Grupos y pestaña

    private var groupsSection: some View {
        Section {
            if bridge.classes.isEmpty {
                Text("No hay grupos creados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                    HStack(spacing: 8) {
                        Text(schoolClass.name)
                        if linkedClassIds.contains(schoolClass.id) {
                            Label("Vinculado", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.accent)
                        }
                    }
                }
            }
        } header: {
            Text(selectedClassIds.count == 1 ? "Grupo (1 elegido)" : "Grupos (\(selectedClassIds.count) elegidos)")
        }
    }

    private var targetTabSection: some View {
        Section {
            if availableTabTitles.isEmpty {
                TextField("Nombre de la nueva pestaña", text: $targetTabTitle)
                Text("No hay pestañas en estos grupos. Se creará esta.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Pestaña", selection: $targetTabTitle) {
                    ForEach(availableTabTitles, id: \.self) { title in
                        Text(title).tag(title)
                    }
                }
                if isCreatingNewTab {
                    HStack(spacing: 8) {
                        TextField("Nombre de la nueva pestaña", text: $newTargetTabName)
                            .onSubmit { Task { await createInstrumentTargetTab() } }
                        Button("Usar") {
                            Task { await createInstrumentTargetTab() }
                            isCreatingNewTab = false
                        }
                        .disabled(newTargetTabName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancelar", role: .cancel) {
                            isCreatingNewTab = false
                            newTargetTabName = ""
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: minimumTapSize)
                } else {
                    Button {
                        newTargetTabName = ""
                        isCreatingNewTab = true
                    } label: {
                        Label("Nueva pestaña…", systemImage: "plus")
                    }
                    .frame(minHeight: minimumTapSize)
                }
            }
        } header: {
            Text("Pestaña del Cuaderno")
        } footer: {
            Text("Las columnas se añaden en «\(targetTabTitle)» en cada grupo (se crea si no existe).")
        }
    }

    // MARK: - Origen: la situación

    @ViewBuilder
    private var situationProposalsSection: some View {
        Section {
            if proposals.isEmpty {
                Text("Esta situación no trae instrumentos. Elige «Documento Word» o «Pruebas físicas».")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if proposalWeightsAreOff {
                LearningSituationInlineNotice(
                    kind: .warning,
                    message: "Los pesos suman \(Int(selectedProposalWeightTotal.rounded())) %. Revisa las filas marcadas."
                )
            }
            ForEach($proposals) { $proposal in
                proposalRow($proposal)
            }
        } header: {
            Text("Instrumentos de la situación")
        }
    }

    private func proposalRow(_ proposal: Binding<LearningSituationEvaluationDraft>) -> some View {
        let value = proposal.wrappedValue
        // Fila afectada: las que no tienen peso; si todas lo tienen, todas las marcadas.
        let anyMissingWeight = selectedProposals.contains { ($0.weightPercent ?? 0) <= 0 }
        let flagged = proposalWeightsAreOff && value.isSelected &&
            (anyMissingWeight ? (value.weightPercent ?? 0) <= 0 : true)
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: proposal.isSelected) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.title)
                        .font(.body.weight(.semibold))
                    weightLabel(value.weightPercent, flagged: flagged)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    rubricStatus(for: value)
                    Spacer(minLength: 8)
                    rubricMenu(for: proposal)
                }
                VStack(alignment: .leading, spacing: 8) {
                    rubricStatus(for: value)
                    rubricMenu(for: proposal)
                }
            }
            if let summary = rubricImportSummaries[value.id] {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(flagged ? IOSAppStyle.warning.opacity(0.12) : nil)
    }

    private func weightLabel(_ weight: Double?, flagged: Bool) -> some View {
        HStack(spacing: 4) {
            Text(weight.map { "\(Int($0.rounded())) %" } ?? "Sin peso")
            if flagged {
                Label("Revisar peso", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(IOSAppStyle.warning)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func rubricStatus(for proposal: LearningSituationEvaluationDraft) -> some View {
        let rubric = proposal.rubricId.flatMap { rubricId in
            bridge.rubrics.first(where: { $0.rubric.id == rubricId })
        }
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(rubric.map { "Rúbrica lista: \($0.rubric.name)" } ?? "Falta elegir la rúbrica")
                    .font(.subheadline.weight(.semibold))
                if let rubric {
                    Text("\(rubric.criteria.count) criterios")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: rubric == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(rubric == nil ? IOSAppStyle.warning : EvaluationDesign.success)
        }
        .accessibilityElement(children: .combine)
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
            Text(proposal.wrappedValue.rubricId == nil ? "Elegir rúbrica" : "Cambiar rúbrica")
                .frame(minHeight: minimumTapSize - 12)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
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

    // MARK: - Origen: documento Word

    @ViewBuilder
    private var wordDocumentSection: some View {
        Section {
            if let instrumentImportDraft {
                LearningSituationInlineNotice(
                    kind: .info,
                    message: "\(instrumentImportDraft.sourceFileName) · \(instrumentImportDraft.instruments.count) instrumentos encontrados"
                )
                if importedWeightsAreOff {
                    LearningSituationInlineNotice(
                        kind: .warning,
                        message: "Los pesos suman \(Int(selectedWeightTotal.rounded())) %. Revisa las filas marcadas."
                    )
                }
                importedInstrumentRows
                Button {
                    instrumentReviewDraft = instrumentImportDraft
                    path.append(.instrumentsReview)
                } label: {
                    Label("Revisar instrumentos", systemImage: "slider.horizontal.3")
                }
                .frame(minHeight: minimumTapSize)
            }
            Button {
                showingInstrumentImporter = true
            } label: {
                if isImportingInstrumentDocument {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Leyendo documento…")
                    }
                } else {
                    Label(instrumentImportDraft == nil ? "Elegir documento Word…" : "Cambiar documento…", systemImage: "doc.badge.plus")
                }
            }
            .disabled(isImportingInstrumentDocument)
            .frame(minHeight: minimumTapSize)
        } header: {
            Text("Instrumentos del Word")
        } footer: {
            if instrumentImportDraft == nil {
                Text("Elige el Word con los instrumentos. Podrás revisarlos antes de crear.")
            }
        }
    }

    private var importedInstrumentRows: some View {
        ForEach(instrumentImportDraft?.instruments ?? [], id: \.id) { instrument in
            let flagged = importedWeightsAreOff && instrument.isSelected && (instrument.weightPercent ?? 0) > 0
            Toggle(isOn: Binding(
                get: {
                    instrumentImportDraft?.instruments.first(where: { $0.id == instrument.id })?.isSelected ?? false
                },
                set: { newValue in
                    guard let index = instrumentImportDraft?.instruments.firstIndex(where: { $0.id == instrument.id }) else { return }
                    instrumentImportDraft?.instruments[index].isSelected = newValue
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(instrument.title)
                        .font(.body.weight(.semibold))
                    Text(importedInstrumentSubtitle(instrument))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let weight = instrument.weightPercent, weight > 0 {
                        weightLabel(weight, flagged: flagged)
                    } else {
                        Text("Auxiliar (no cuenta para la media)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(flagged ? IOSAppStyle.warning.opacity(0.12) : nil)
        }
    }

    // MARK: - Origen: pruebas físicas

    @ViewBuilder
    private var physicalTestsSection: some View {
        Section {
            if let physicalTestsImportDraft {
                Label(physicalTestsImportDraft.assignmentTemplate.batteryName, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(EvaluationDesign.success)
                Text(physicalTestsImportDraft.testDefinitions.count == 1
                    ? "1 prueba"
                    : "\(physicalTestsImportDraft.testDefinitions.count) pruebas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(physicalTestsImportDraft.scoreIsDisabled
                    ? "Diagnóstico: se crearán columnas de marca sin nota, media ni ranking."
                    : "Se crearán las columnas configuradas en el archivo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    physicalTestsReviewDraft = physicalTestsImportDraft
                    path.append(.physicalTestsReview)
                } label: {
                    Label("Revisar pruebas", systemImage: "slider.horizontal.3")
                }
                .frame(minHeight: minimumTapSize)
                Button(role: .destructive) {
                    self.physicalTestsImportDraft = nil
                } label: {
                    Label("Quitar pruebas", systemImage: "trash")
                }
                .frame(minHeight: minimumTapSize)
            }
            Button {
                showingPhysicalTestsImporter = true
            } label: {
                if isImportingPhysicalTests {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Comprobando el archivo…")
                    }
                } else {
                    Label(physicalTestsImportDraft == nil ? "Elegir archivo de pruebas…" : "Cambiar archivo…", systemImage: "figure.run.circle")
                }
            }
            .disabled(isImportingPhysicalTests)
            .frame(minHeight: minimumTapSize)
        } header: {
            Text("Pruebas físicas")
        } footer: {
            if physicalTestsImportDraft == nil {
                Text("Elige el archivo JSON preparado para esta situación: batería, escalas y columnas de marca.")
            }
        }
    }

    // MARK: - Pie

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                footerStatus
                Spacer(minLength: 8)
                createButton
            }
            VStack(alignment: .leading, spacing: 8) {
                footerStatus
                createButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footerStatus: some View {
        Text(statusMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var createButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Creando…")
                }
            } else {
                Text("Crear en el Cuaderno")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!canSave)
    }

    private var statusMessage: String {
        if isSaving { return "Creando en \(groupCountLabel)…" }
        if selectedClassIds.isEmpty { return "Elige al menos un grupo." }
        if !hasTargetTab { return "Escribe el nombre de la pestaña." }
        switch source {
        case .physicalTests:
            guard physicalTestsImportDraft != nil else { return "Elige el archivo de pruebas físicas." }
            return canSave
                ? "Se crearán la batería, las referencias y las columnas de marca en \(groupCountLabel)."
                : "Revisa las pruebas antes de crear."
        case .wordDocument:
            guard instrumentImportDraft != nil else { return "Elige el documento Word." }
            if !canSave { return "Marca al menos un instrumento." }
            let weightNote = importedWeightsAreOff ? " · pesos \(Int(selectedWeightTotal.rounded())) %" : ""
            return "\(selectedImportedInstruments.count) columnas en \(groupCountLabel)\(weightNote)"
        case .situation:
            if selectedProposals.isEmpty { return "Marca al menos un instrumento." }
            if let pending = selectedProposals.first(where: { $0.rubricId == nil }) {
                return "Falta elegir la rúbrica de «\(pending.title)»."
            }
            let weightNote = proposalWeightsAreOff ? " · pesos \(Int(selectedProposalWeightTotal.rounded())) %" : ""
            return "\(selectedProposals.count) columnas en \(groupCountLabel)\(weightNote)"
        }
    }

    private var groupCountLabel: String {
        selectedClassIds.count == 1 ? "1 grupo" : "\(selectedClassIds.count) grupos"
    }

    // MARK: - Acciones

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
            instrumentReviewDraft = try await withTimeout(seconds: 20) {
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
            path = [.instrumentsReview]
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
            physicalTestsReviewDraft = try await withTimeout(seconds: 20) {
                try service.preview(from: url, data: data)
            }
            path = [.physicalTestsReview]
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

    /// La hoja de cálculo va directa al editor de rúbricas (sin vista previa intermedia).
    /// Si no tiene niveles o criterios, se avisa en línea y no se abre el editor.
    @MainActor
    private func handleRubricImportFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            let preview = makeRubricImportPreview(from: rows)
            guard preview.levelCount > 0, preview.criterionCount > 0 else {
                errorMessage = (["No se pudo usar la hoja de cálculo."] + preview.warnings).joined(separator: " ")
                return
            }
            if let activeProposalId {
                rubricImportSummaries[activeProposalId] = "Del Excel: \(preview.levelCount) niveles · \(preview.criterionCount) criterios. Guárdala en el editor para usarla."
            }
            await confirmRubricImport(preview)
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
        rubricImportSummaries[activeProposalId] = nil
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
        isCreatingNewTab = false
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
        isSaving = true
        defer { isSaving = false }
        errorMessage = ""
        do {
            for classId in selectedClassIds {
                switch source {
                case .physicalTests:
                    guard let physicalTestsImportDraft else { return }
                    try await bridge.materializeLearningSituationPhysicalTests(
                        situation: situation,
                        classId: classId,
                        draft: physicalTestsImportDraft,
                        targetTabId: resolvedTabName
                    )
                case .wordDocument:
                    guard let instrumentImportDraft else { return }
                    try await bridge.materializeLearningSituationAssessmentInstruments(
                        situation: situation,
                        classId: classId,
                        draft: instrumentImportDraft,
                        targetTabId: resolvedTabName
                    )
                case .situation:
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
            errorMessage = "No se pudo crear. \(error.localizedDescription)"
        }
    }

    private func importedInstrumentSubtitle(_ instrument: AssessmentInstrumentDraft?) -> String {
        guard let instrument else { return "" }
        var parts = [instrument.kind.label]
        if let criterion = instrument.criterionLabel, !criterion.isEmpty { parts.append(criterion) }
        let detailCount = instrument.rubric?.criteria.count ?? instrument.checklistItems.count + instrument.quizQuestions.count + instrument.observationFields.count
        if detailCount > 0 { parts.append("\(detailCount) ítems") }
        return parts.joined(separator: " · ")
    }
}
