import SwiftUI
import MiGestorKit

enum PhysicalTestCapacity: String, CaseIterable, Identifiable {
    case resistance = "Resistencia"
    case strength = "Fuerza"
    case speed = "Velocidad"
    case flexibility = "Movilidad"

    var id: String { rawValue }
}

enum PhysicalTestMeasurement: String, CaseIterable, Identifiable {
    case time = "Tiempo"
    case distance = "Distancia"
    case repetitions = "Repeticiones"
    case level = "Nivel"

    var id: String { rawValue }

    var inputKind: NotebookCellInputKind {
        switch self {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .numeric010
        }
    }

    var scaleKind: NotebookScaleKind {
        switch self {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .tenPoint
        }
    }
}

enum PhysicalTestResultMode: String, CaseIterable, Identifiable {
    case best = "Mejor intento"
    case average = "Media de intentos"
    case last = "Último intento"

    var id: String { rawValue }
}

struct PhysicalTestTemplate: Identifiable, Hashable {
    let id: String
    var name: String
    var capacity: PhysicalTestCapacity
    var measurement: PhysicalTestMeasurement
    var unit: String
    var direction: PhysicalTestScaleDirection
    var attempts: Int
    var resultMode: PhysicalTestResultMode
    var protocolText: String

    static let defaults: [PhysicalTestTemplate] = [
        .init(id: "course_navette", name: "Course Navette", capacity: .resistance, measurement: .level, unit: "periodo", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Test progresivo por periodos con señal acústica."),
        .init(id: "cooper", name: "Test Cooper", capacity: .resistance, measurement: .distance, unit: "m", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Distancia recorrida en 12 minutos."),
        .init(id: "horizontal_jump", name: "Salto horizontal", capacity: .strength, measurement: .distance, unit: "m", direction: .higherIsBetter, attempts: 3, resultMode: .best, protocolText: "Salto a pies juntos desde parado. Se registra la mejor marca."),
        .init(id: "push_ups", name: "Flexiones", capacity: .strength, measurement: .repetitions, unit: "rep", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Repeticiones técnicamente válidas."),
        .init(id: "sit_ups", name: "Abdominales 30\"", capacity: .strength, measurement: .repetitions, unit: "rep", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Repeticiones válidas durante 30 segundos."),
        .init(id: "speed_30m", name: "Velocidad 30 m", capacity: .speed, measurement: .time, unit: "s", direction: .lowerIsBetter, attempts: 2, resultMode: .best, protocolText: "Sprint de 30 metros con salida alta."),
        .init(id: "sit_and_reach", name: "Sit and reach", capacity: .flexibility, measurement: .distance, unit: "cm", direction: .higherIsBetter, attempts: 2, resultMode: .best, protocolText: "Flexión de tronco sentado con piernas extendidas.")
    ]
}

private enum PhysicalTestsWorkspaceTab: String, CaseIterable, Identifiable {
    case bank = "Pruebas"
    case scales = "Baremos"
    case batteries = "Baterías"
    case assignments = "Asignaciones"
    case capture = "Captura"
    case history = "Histórico"
    case reports = "Informes"

    var id: String { rawValue }
}

private enum PhysicalTestsLoadPhase: Int, Comparable {
    case shell
    case metrics
    case lists
    case ai

    static func < (lhs: PhysicalTestsLoadPhase, rhs: PhysicalTestsLoadPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func includes(_ phase: PhysicalTestsLoadPhase) -> Bool {
        rawValue >= phase.rawValue
    }
}

private enum PhysicalCompletionFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case pending = "Pendiente"
    case completed = "Completado"

    var id: String { rawValue }
}

struct PhysicalBatteryQuickTemplate: Identifiable {
    let id: String
    let title: String
    let templateIds: Set<String>

    static func defaults(for templates: [PhysicalTestTemplate]) -> [PhysicalBatteryQuickTemplate] {
        let initial = Set(["course_navette", "horizontal_jump", "speed_30m", "sit_and_reach"])
            .intersection(Set(templates.map(\.id)))
        return [
            .init(id: "initial", title: "Condición física inicial", templateIds: initial),
            .init(id: "final", title: "Condición física final", templateIds: initial),
            .init(id: "strength", title: "Fuerza", templateIds: ids(in: templates, capacity: .strength)),
            .init(id: "resistance", title: "Resistencia", templateIds: ids(in: templates, capacity: .resistance)),
            .init(id: "speed", title: "Velocidad", templateIds: ids(in: templates, capacity: .speed)),
            .init(id: "mobility", title: "Movilidad", templateIds: ids(in: templates, capacity: .flexibility))
        ]
    }

    private static func ids(in templates: [PhysicalTestTemplate], capacity: PhysicalTestCapacity) -> Set<String> {
        Set(templates.filter { $0.capacity == capacity }.map(\.id))
    }
}

private struct PhysicalTestBattery: Identifiable {
    let id: String
    var name: String
    var date: Date
    var templateIds: Set<String>
    var columnMode: PhysicalNotebookColumnMode
}

private struct PhysicalTestAssignmentDraft: Identifiable {
    let id: String
    var batteryId: String
    var classId: Int64
    var className: String
    var course: Int
    var ageFrom: Int
    var ageTo: Int
    var termLabel: String
    var date: Date
    var columnMode: PhysicalNotebookColumnMode
}

private struct PhysicalNotebookLink: Identifiable {
    var id: String { "\(assignmentId)-\(testId)" }
    var assignmentId: String
    var testId: String
    var rawColumnId: String?
    var scoreColumnId: String?
}

struct PhysicalTestsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var selectedTab: PhysicalTestsWorkspaceTab = .bank
    @State private var tests: [KmpBridge.PhysicalTestSnapshot] = []
    @State private var selectedTestId: Int64?
    @State private var selectedStudentId: Int64?
    @State private var searchText = ""
    @State private var showingCreateSheet = false
    @State private var showingCapture = false
    @State private var showingScaleEditor = false
    @State private var pendingDeleteTest: KmpBridge.PhysicalTestSnapshot?
    @State private var editingTest: KmpBridge.PhysicalTestSnapshot?
    @State private var definitions: [MiGestorKit.PhysicalTestDefinition] = []
    @State private var batteries: [MiGestorKit.PhysicalTestBattery] = []
    @State private var batteryName = "Condición física inicial"
    @State private var batteryDate = Date()
    @State private var batteryTemplateIds: Set<String> = Set(PhysicalTestTemplate.defaults.prefix(4).map(\.id))
    @State private var batteryColumnMode: PhysicalNotebookColumnMode = .rawAndScore
    @State private var selectedBatteryId: String?
    @State private var assignments: [MiGestorKit.PhysicalTestAssignment] = []
    @State private var notebookLinks: [MiGestorKit.PhysicalTestNotebookLink] = []
    @State private var assignmentNotebookTabs: [NotebookTab] = []
    @State private var selectedAssignmentNotebookTabId: String?
    @State private var newAssignmentNotebookTabName = "Condición física"
    @State private var assignmentCourse = 1
    @State private var assignmentAgeFrom = 12
    @State private var assignmentAgeTo = 13
    @State private var assignmentTermLabel = "1ª evaluación"
    @State private var scoreCountsTowardAverage = true
    @State private var selectedFilterCourse: Int?
    @State private var selectedFilterBatteryId: String?
    @State private var selectedFilterTestId: String?
    @State private var selectedFilterTerm = ""
    @State private var completionFilter: PhysicalCompletionFilter = .all
    @State private var scale = PhysicalTestScaleDraft.defaultJump
    @State private var progressAnalysis: PhysicalProgressAnalysis?
    @State private var isGeneratingProgressAnalysis = false
    @State private var progressAnalysisError: String?
    @State private var aiOrchestrator = AppleAIOrchestrator()
    @State private var loadPhase: PhysicalTestsLoadPhase = .shell
    @State private var reloadGeneration = 0

    private var selectedClassName: String {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id })?.name } ?? "Clase global"
    }

    private var selectedSchoolClass: SchoolClass? {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id }) }
    }

    private var selectedTest: KmpBridge.PhysicalTestSnapshot? {
        filteredTests.first(where: { $0.evaluation.id == selectedTestId })
    }

    private var filteredTests: [KmpBridge.PhysicalTestSnapshot] {
        tests.filter { test in
            let definitionId = testDefinitionId(for: test)
            if let selectedFilterTestId, definitionId != selectedFilterTestId { return false }
            switch completionFilter {
            case .all:
                return true
            case .pending:
                return test.recordedCount < test.results.count
            case .completed:
                return test.recordedCount >= test.results.count && test.results.count > 0
            }
        }
    }

    private var filteredAssignments: [MiGestorKit.PhysicalTestAssignment] {
        assignments.filter { assignment in
            if let selectedFilterCourse, assignment.course?.intValue != selectedFilterCourse { return false }
            if let selectedFilterBatteryId, assignment.batteryId != selectedFilterBatteryId { return false }
            if !selectedFilterTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !(assignment.termLabel ?? "").localizedCaseInsensitiveContains(selectedFilterTerm) {
                return false
            }
            return true
        }
    }

    private var activeAssignment: MiGestorKit.PhysicalTestAssignment? {
        guard let selectedTest else { return filteredAssignments.first ?? assignments.first }
        let definitionId = testDefinitionId(for: selectedTest)
        return filteredAssignments.first { assignment in
            guard let battery = batteries.first(where: { $0.id == assignment.batteryId }) else { return false }
            return battery.testIds.contains(definitionId)
        } ?? assignments.first { assignment in
            guard let battery = batteries.first(where: { $0.id == assignment.batteryId }) else { return false }
            return battery.testIds.contains(definitionId)
        }
    }

    private var activeNotebookLink: MiGestorKit.PhysicalTestNotebookLink? {
        guard let selectedTest, let activeAssignment else { return nil }
        let definitionId = testDefinitionId(for: selectedTest)
        return notebookLinks.first { $0.assignmentId == activeAssignment.id && $0.testId == definitionId }
    }

    private var selectedAssignmentNotebookTab: NotebookTab? {
        selectedAssignmentNotebookTabId.flatMap { id in assignmentNotebookTabs.first(where: { $0.id == id }) }
    }

    private var selectedResult: KmpBridge.PhysicalTestSnapshot.StudentResult? {
        filteredResults.first(where: { $0.student.id == selectedStudentId }) ??
        selectedTest?.results.first(where: { $0.student.id == selectedStudentId })
    }

    private var filteredResults: [KmpBridge.PhysicalTestSnapshot.StudentResult] {
        guard let selectedTest else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selectedTest.results }
        return selectedTest.results.filter { result in
            "\(result.student.firstName) \(result.student.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    private var recordedCount: Int {
        tests.reduce(0) { $0 + $1.recordedCount }
    }

    private var physicalProgressEvidence: PhysicalProgressEvidence {
        PhysicalProgressEvidence(
            className: selectedClassName,
            termLabel: selectedFilterTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedFilterTerm,
            metrics: filteredTests.map { test in
                let testId = testDefinitionId(for: test)
                return PhysicalProgressMetric(
                    id: test.evaluation.id.description,
                    testName: test.evaluation.name,
                    average: test.average,
                    best: test.best,
                    recordedCount: test.recordedCount,
                    totalCount: test.results.count,
                    directionLabel: direction(for: testId) == .higherIsBetter ? "mayor marca = mejor" : "menor marca = mejor"
                )
            }
        )
    }

    private var activeScaleTestId: String? {
        selectedTest.map(testDefinitionId(for:)) ?? selectedFilterTestId ?? PhysicalTestTemplate.defaults.first?.id
    }

    private var activeScaleEditorContext: PhysicalTestScaleEditorContext? {
        let testId = activeScaleTestId
        guard let testId, let descriptor = physicalTestDescriptor(for: testId) else { return nil }
        let assignment = activeAssignment ?? filteredAssignments.first ?? assignments.first
        let battery = assignment.flatMap { assignment in batteries.first(where: { $0.id == assignment.batteryId }) }
            ?? selectedBatteryId.flatMap { id in batteries.first(where: { $0.id == id }) }
            ?? batteries.first
        let course = assignment?.course?.intValue ?? selectedSchoolClass.map { Int($0.course) } ?? assignmentCourse
        let ageFrom = assignment?.ageFrom?.intValue ?? assignmentAgeFrom
        let ageTo = assignment?.ageTo?.intValue ?? assignmentAgeTo
        let termLabel = assignment?.termLabel ?? assignmentTermLabel
        return PhysicalTestScaleEditorContext(
            testId: testId,
            batteryId: assignment?.batteryId ?? battery?.id,
            batteryName: battery?.name ?? "Condición física",
            className: selectedClassName,
            termLabel: termLabel,
            testName: descriptor.name,
            capacity: descriptor.capacity,
            measurementKind: descriptor.measurementKind,
            unit: descriptor.unit,
            course: course,
            ageFrom: ageFrom,
            ageTo: ageTo
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Picker("Sección", selection: $selectedTab) {
                    ForEach(PhysicalTestsWorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                filtersBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Divider()

                physicalContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(EvaluationBackdrop())
            .navigationTitle("EF · Condición física")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("Nueva prueba", systemImage: "plus")
                    }
                }
            }
            .task { await reload() }
            .appOnChange(of: selectedClassId) { _ in Task { await reload() } }
            .appOnChange(of: selectedClassId) { _ in syncSelectedClassDefaults() }
            .appOnChange(of: selectedTestId) { _ in resetScaleDraftForActiveTest() }
            .appOnChange(of: selectedFilterTestId) { _ in resetScaleDraftForActiveTest() }
            .appOnChange(of: selectedTab) { tab in
                if tab == .reports, progressAnalysis == nil {
                    loadPhase = max(loadPhase, .lists)
                    Task { await generateProgressAnalysis() }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                PhysicalTestCreationSheet(defaultClassId: selectedClassId, templates: PhysicalTestTemplate.defaults) {
                    Task { await reload() }
                }
                .environmentObject(bridge)
            }
            .sheet(isPresented: $showingCapture) {
                if let selectedClassId, let selectedTest, let activeAssignment {
                    PhysicalTestCaptureView(
                        bridge: bridge,
                        classId: selectedClassId,
                        test: selectedTest,
                        assignmentId: activeAssignment.id,
                        batteryId: activeAssignment.batteryId,
                        testDefinitionId: testDefinitionId(for: selectedTest),
                        course: activeAssignment.course?.intValue,
                        age: activeAssignment.ageFrom?.intValue,
                        rawColumnId: activeNotebookLink?.rawColumnId,
                        scoreColumnId: activeNotebookLink?.scoreColumnId,
                        recordScore: activeAssignment.scoreColumnMode,
                        attemptsCount: attemptsCount(for: testDefinitionId(for: selectedTest)),
                        direction: direction(for: testDefinitionId(for: selectedTest)),
                        resultMode: resultMode(for: testDefinitionId(for: selectedTest)),
                        onSaved: { await reload() }
                    )
                }
            }
            .sheet(isPresented: $showingScaleEditor) {
                NavigationStack {
                    PhysicalTestScaleEditor(scale: $scale, context: activeScaleEditorContext) { draft in
                        Task { await saveScale(draft) }
                    }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") { showingScaleEditor = false }
                            }
                        }
                }
                #if !os(macOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
    }

    @ViewBuilder
    private var physicalContent: some View {
        if loadPhase.includes(.lists) {
            switch selectedTab {
            case .bank:
                bankView
            case .scales:
                scalesView
            case .batteries:
                batteriesView
            case .assignments:
                assignmentsView
            case .capture:
                captureDashboard
            case .history:
                historyView
            case .reports:
                reportsView
            }
        } else {
            physicalTabSkeleton
        }
    }

    private var filtersBar: some View {
        HStack(spacing: 10) {
            Picker("Clase", selection: Binding<Int64?>(
                get: { selectedClassId },
                set: { selectedClassId = $0 }
            )) {
                Text("Clase").tag(Optional<Int64>.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(schoolClass.name).tag(Optional(schoolClass.id))
                }
            }
            .pickerStyle(.menu)

            Picker("Curso", selection: Binding<Int?>(
                get: { selectedFilterCourse },
                set: { selectedFilterCourse = $0 }
            )) {
                Text("Curso").tag(Optional<Int>.none)
                ForEach(Array(Set(bridge.classes.map { Int($0.course) })).sorted(), id: \.self) { course in
                    Text("\(course)º").tag(Optional(course))
                }
            }
            .pickerStyle(.menu)

            Picker("Batería", selection: Binding<String?>(
                get: { selectedFilterBatteryId },
                set: { selectedFilterBatteryId = $0 }
            )) {
                Text("Batería").tag(Optional<String>.none)
                ForEach(batteries, id: \.id) { battery in
                    Text(battery.name).tag(Optional(battery.id))
                }
            }
            .pickerStyle(.menu)

            Picker("Test", selection: Binding<String?>(
                get: { selectedFilterTestId },
                set: { selectedFilterTestId = $0 }
            )) {
                Text("Test").tag(Optional<String>.none)
                ForEach(definitions, id: \.id) { definition in
                    Text(definition.name).tag(Optional(definition.id))
                }
            }
            .pickerStyle(.menu)

            TextField("Trimestre", text: $selectedFilterTerm)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            Picker("Estado", selection: $completionFilter) {
                ForEach(PhysicalCompletionFilter.allCases) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EF · Condición física")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Text("\(selectedClassName) · pruebas, baremos e históricos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    resetScaleDraftForActiveTest(force: true)
                    showingScaleEditor = true
                } label: {
                    Label("Baremos", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }

            if loadPhase.includes(.metrics) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    PhysicalStatCard(title: "Pruebas", value: "\(tests.count)", tint: .blue)
                    PhysicalStatCard(title: "Registros", value: "\(recordedCount)", tint: .green)
                    PhysicalStatCard(title: "Banco", value: "\(max(definitions.count, PhysicalTestTemplate.defaults.count))", tint: .orange)
                    PhysicalStatCard(title: "Baterías", value: "\(batteries.count)", tint: .purple)
                }
            } else {
                physicalMetricsSkeleton
            }
        }
        .padding(20)
    }

    private var physicalMetricsSkeleton: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: index == 2 ? 64 : 72, height: 10)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 48, height: 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Cargando métricas de condición física")
    }

    private var physicalTabSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if selectedTab == .capture {
                    physicalCaptureSkeleton
                } else {
                    ForEach(0..<4, id: \.self) { index in
                        NotebookSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.primary.opacity(0.12))
                                        .frame(width: index == 0 ? 176 : 136, height: 14)
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 72, height: 20)
                                }
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 220, height: 10)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Cargando sección de condición física")
    }

    private var physicalCaptureSkeleton: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: index == 0 ? 160 : 128, height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                            .frame(width: 180, height: 10)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(minWidth: 320, maxWidth: 380)

            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 220, height: 28)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 88)
                    }
                }
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 48)
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 44)
                }
            }
        }
    }

    private var bankView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(PhysicalTestTemplate.defaults) { template in
                    PhysicalTemplateCard(template: template) {
                        addTemplateToBattery(template)
                    }
                }
            }
            .padding(20)
        }
    }

    private var batteriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PhysicalBatteryBuilder(
                    templates: PhysicalTestTemplate.defaults,
                    selectedClassName: selectedClassName,
                    name: $batteryName,
                    date: $batteryDate,
                    selectedTemplateIds: $batteryTemplateIds,
                    columnMode: $batteryColumnMode,
                    onCreate: createBattery
                )

                ForEach(batteries, id: \.id) { battery in
                    NotebookSurface {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(battery.name)
                                    .font(.headline)
                                Text("\(battery.testIds.count) pruebas")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(battery.description.isEmpty ? "Sin descripción" : battery.description)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Las columnas del cuaderno se crean desde Asignaciones, cuando ya hay clase, curso, edad y fecha.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private var assignmentsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NotebookSurface {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Asignar batería a clase")
                            .font(.headline)
                        Picker("Clase", selection: Binding<Int64?>(
                            get: { selectedClassId },
                            set: { newValue in
                                selectedClassId = newValue
                                syncSelectedClassDefaults()
                                Task { await refreshAssignmentNotebookTabs() }
                            }
                        )) {
                            Text("Selecciona clase").tag(Optional<Int64>.none)
                            ForEach(bridge.classes, id: \.id) { schoolClass in
                                Text(schoolClass.name).tag(Optional(schoolClass.id))
                            }
                        }
                        Picker("Batería", selection: Binding<String?>(
                            get: { selectedBatteryId ?? batteries.first?.id },
                            set: { selectedBatteryId = $0 }
                        )) {
                            ForEach(batteries, id: \.id) { battery in
                                Text(battery.name).tag(Optional(battery.id))
                            }
                        }
                        HStack {
                            Stepper("Curso \(assignmentCourse)", value: $assignmentCourse, in: 1...6)
                            Stepper("Edad \(assignmentAgeFrom)-\(assignmentAgeTo)", value: $assignmentAgeFrom, in: 3...20)
                            Stepper("Hasta \(assignmentAgeTo)", value: $assignmentAgeTo, in: assignmentAgeFrom...20)
                        }
                        TextField("Evaluación / trimestre", text: $assignmentTermLabel)
                            .textFieldStyle(.roundedBorder)
                        DatePicker("Fecha de medición", selection: $batteryDate, displayedComponents: .date)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pestaña del cuaderno")
                                .font(.subheadline.weight(.semibold))
                            if assignmentNotebookTabs.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Esta clase todavía no tiene pestañas para ubicar las columnas.")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Button {
                                        createAssignmentNotebookTab(defaultName: "Condición física")
                                    } label: {
                                        Label("Crear pestaña Condición física", systemImage: "plus.rectangle.on.folder")
                                    }
                                    .disabled(selectedClassId == nil)
                                }
                            } else {
                                Picker("Pestaña del cuaderno", selection: Binding<String?>(
                                    get: { selectedAssignmentNotebookTabId ?? assignmentNotebookTabs.first?.id },
                                    set: { selectedAssignmentNotebookTabId = $0; bridge.setSelectedNotebookTab(id: $0) }
                                )) {
                                    ForEach(assignmentNotebookTabs, id: \.id) { tab in
                                        Text(tab.title).tag(Optional(tab.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                Text("Las columnas de marca y nota se crearán dentro de esta pestaña.")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                TextField("Nueva pestaña", text: $newAssignmentNotebookTabName)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    createAssignmentNotebookTab()
                                } label: {
                                    Label("Crear pestaña", systemImage: "plus")
                                }
                                .disabled(selectedClassId == nil || trimmedOrNil(newAssignmentNotebookTabName) == nil)
                            }
                        }
                        PhysicalTestsColumnOptionsView(
                            columnMode: $batteryColumnMode,
                            scoreCountsTowardAverage: $scoreCountsTowardAverage
                        )
                        Button {
                            Task { await createAssignment() }
                        } label: {
                            Label("Crear asignación y columnas", systemImage: "link.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedClassId == nil || batteries.isEmpty || selectedAssignmentNotebookTabId == nil)
                    }
                }

                ForEach(filteredAssignments, id: \.id) { assignment in
                    NotebookSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(assignment.termLabel ?? "Evaluación física")
                                .font(.headline)
                            Text("\(className(for: assignment.classId)) · curso \(assignment.course?.intValue ?? 0) · \(assignment.ageFrom?.intValue ?? 0)-\(assignment.ageTo?.intValue ?? 0) años")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Columnas: \(columnModeLabel(for: assignment)) · \(Date(timeIntervalSince1970: TimeInterval(assignment.dateEpochMs) / 1000).formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if filteredAssignments.isEmpty {
                    PhysicalEmptyState(
                        title: "Sin asignaciones",
                        systemImage: "link.circle",
                        subtitle: "Crea una batería y asígnala a una clase antes de generar columnas o capturar marcas."
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(20)
        }
    }

    private var captureDashboard: some View {
        ViewThatFits(in: .horizontal) {
            regularCaptureDashboard
            compactCaptureDashboard
        }
    }

    private var regularCaptureDashboard: some View {
        HStack(spacing: 0) {
            testsList
                .frame(minWidth: 320, maxWidth: 380)

            Divider()

            captureDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760)
    }

    private var compactCaptureDashboard: some View {
        VStack(spacing: 16) {
            testsList
                .frame(maxWidth: .infinity)
                .frame(minHeight: 320, maxHeight: 480)

            captureDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    @ViewBuilder
    private var captureDetailPane: some View {
        if let selectedTest {
            VStack(alignment: .leading, spacing: 24) {
                Text(selectedTest.evaluation.name)
                    .font(.system(size: 30, weight: .black, design: .rounded))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                    PhysicalMetricCard(title: "Completado", value: "\(selectedTest.recordedCount)/\(selectedTest.results.count)", systemImage: "checkmark.circle.fill")
                    PhysicalMetricCard(title: "Media grupo", value: PhysicalTestsFormatting.decimal(selectedTest.average), systemImage: "chart.line.uptrend.xyaxis")
                    PhysicalMetricCard(title: "Mejor marca", value: selectedTest.best.map { PhysicalTestsFormatting.decimal($0) } ?? "-", systemImage: "trophy.fill")
                }

                Button {
                    showingCapture = true
                } label: {
                    Label("Abrir captura en pista", systemImage: "figure.run.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedClassId == nil || activeAssignment == nil)

                searchField
                resultsList

                Spacer(minLength: 0)
            }
            .padding(24)
        } else {
            PhysicalEmptyState(
                title: "Sin prueba seleccionada",
                systemImage: "stopwatch",
                subtitle: "Crea o selecciona una prueba física para capturar marcas."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if tests.isEmpty {
                    PhysicalEmptyState(
                        title: "Sin histórico",
                        systemImage: "chart.line.uptrend.xyaxis",
                        subtitle: "Las marcas guardadas aparecerán aquí como resumen básico de evolución."
                    )
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    ForEach(filteredTests, id: \.evaluation.id) { test in
                        NotebookSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(test.evaluation.name)
                                            .font(.headline)
                                        Text(test.evaluation.type)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(test.recordedCount)/\(test.results.count)")
                                        .font(.headline.monospacedDigit())
                                }

                                ProgressView(value: Double(test.recordedCount), total: Double(max(test.results.count, 1)))

                                HStack {
                                    PhysicalHistoryValue(title: "Media", value: PhysicalTestsFormatting.decimal(test.average))
                                    PhysicalHistoryValue(title: "Mejor", value: test.best.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                                    PhysicalHistoryValue(title: "Pendientes", value: "\(max(test.results.count - test.recordedCount, 0))")
                                }
                            }
                        }
                    }
                }

            }
            .padding(20)
        }
    }

    private var scalesView: some View {
        NavigationStack {
            PhysicalTestScaleEditor(scale: $scale, context: activeScaleEditorContext) { draft in
                Task { await saveScale(draft) }
            }
                .navigationTitle("Baremos")
                .onAppear { resetScaleDraftForActiveTest() }
        }
    }

    private var testsList: some View {
        List(selection: $selectedTestId) {
            Section("Pruebas") {
                ForEach(tests, id: \.evaluation.id) { test in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(test.evaluation.name)
                            .font(.headline)
                        Text("\(test.recordedCount) registros · media \(PhysicalTestsFormatting.decimal(test.average))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(test.evaluation.id))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Eliminar", role: .destructive) {
                            pendingDeleteTest = test
                        }
                        .tint(IOSAppStyle.danger)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Editar") {
                            editingTest = test
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editingTest = test
                        } label: {
                            Label("Editar prueba", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDeleteTest = test
                        } label: {
                            Label("Eliminar prueba", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(
            isPresented: Binding(
                get: { editingTest != nil },
                set: { if !$0 { editingTest = nil } }
            )
        ) {
            if let editingTest {
                PhysicalTestEditSheet(test: editingTest) { name, weight, description in
                    Task { await updatePhysicalTest(editingTest, name: name, weight: weight, description: description) }
                }
            }
        }
        .confirmationDialog(
            "Eliminar prueba física",
            isPresented: Binding(
                get: { pendingDeleteTest != nil },
                set: { if !$0 { pendingDeleteTest = nil } }
            ),
            presenting: pendingDeleteTest
        ) { test in
            Button("Eliminar \(test.evaluation.name)", role: .destructive) {
                Task { await deletePhysicalTest(test) }
            }
            Button("Cancelar", role: .cancel) {
                pendingDeleteTest = nil
            }
        } message: { test in
            Text("Se eliminará \(test.evaluation.name) y todas sus marcas registradas.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar alumno", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var resultsList: some View {
        List(filteredResults, id: \.student.id, selection: $selectedStudentId) { result in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.student.firstName) \(result.student.lastName)")
                        .font(.subheadline.weight(.bold))
                    Text(result.value == nil ? "Sin marca" : "Marca registrada")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(result.value.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                    .font(.headline.monospacedDigit())
            }
            .tag(Optional(result.student.id))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Alumno") { onOpenModule(.students, selectedClassId, result.student.id) }
                    .tint(.indigo)
                Button("Cuaderno") { onOpenModule(.notebook, selectedClassId, result.student.id) }
                    .tint(.blue)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("Evaluación") { onOpenModule(.evaluationHub, selectedClassId, result.student.id) }
                    .tint(.purple)
            }
            .contextMenu {
                Button("Abrir alumno") { onOpenModule(.students, selectedClassId, result.student.id) }
                Button("Abrir cuaderno") { onOpenModule(.notebook, selectedClassId, result.student.id) }
                Button("Abrir evaluación") { onOpenModule(.evaluationHub, selectedClassId, result.student.id) }
            }
        }
        .listStyle(.plain)
    }

    @MainActor
    private func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        loadPhase = .shell
        progressAnalysis = nil
        progressAnalysisError = nil
        guard let selectedClassId else {
            tests = []
            selectedTestId = nil
            selectedStudentId = nil
            assignments = []
            notebookLinks = []
            assignmentNotebookTabs = []
            selectedAssignmentNotebookTabId = nil
            loadPhase = .lists
            return
        }
        await refreshAssignmentNotebookTabs()
        guard generation == reloadGeneration else { return }
        let loadedDefinitions = (try? await bridge.listPhysicalDefinitions()) ?? []
        guard generation == reloadGeneration else { return }
        definitions = loadedDefinitions
        let loadedBatteries = (try? await bridge.listPhysicalBatteries()) ?? []
        guard generation == reloadGeneration else { return }
        batteries = loadedBatteries
        let loadedTests = (try? await bridge.loadPhysicalTests(classId: selectedClassId)) ?? []
        guard generation == reloadGeneration else { return }
        tests = loadedTests
        if selectedBatteryId == nil || !batteries.contains(where: { $0.id == selectedBatteryId }) {
            selectedBatteryId = batteries.first?.id
        }
        if selectedTestId == nil || !filteredTests.contains(where: { $0.evaluation.id == selectedTestId }) {
            selectedTestId = filteredTests.first?.evaluation.id
        }
        if selectedStudentId == nil || !(selectedTest?.results.contains(where: { $0.student.id == selectedStudentId }) ?? false) {
            selectedStudentId = selectedTest?.results.first?.student.id
        }
        loadPhase = .metrics
        let loadedAssignments = (try? await bridge.listPhysicalAssignmentsForClass(classId: selectedClassId)) ?? []
        guard generation == reloadGeneration else { return }
        var loadedNotebookLinks: [MiGestorKit.PhysicalTestNotebookLink] = []
        for assignment in loadedAssignments {
            let links = (try? await bridge.listPhysicalNotebookLinksForAssignment(assignmentId: assignment.id)) ?? []
            guard generation == reloadGeneration else { return }
            loadedNotebookLinks.append(contentsOf: links)
        }
        assignments = loadedAssignments
        notebookLinks = loadedNotebookLinks
        syncSelectedClassDefaults()
        resetScaleDraftForActiveTest()
        loadPhase = .lists
        if selectedTab == .reports {
            Task { await generateProgressAnalysis() }
        }
    }

    @MainActor
    private func refreshAssignmentNotebookTabs() async {
        guard let selectedClassId else {
            assignmentNotebookTabs = []
            selectedAssignmentNotebookTabId = nil
            return
        }
        bridge.selectClass(id: selectedClassId)
        await Task.yield()
        let tabs = (bridge.notebookState as? NotebookUiStateData)?.sheet.tabs ?? []
        assignmentNotebookTabs = tabs.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        if let selectedAssignmentNotebookTabId,
           assignmentNotebookTabs.contains(where: { $0.id == selectedAssignmentNotebookTabId }) {
            bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
            return
        }
        let preferred = assignmentNotebookTabs.first { tab in
            tab.title.localizedCaseInsensitiveContains("condición") ||
            tab.title.localizedCaseInsensitiveContains("fis")
        }
        selectedAssignmentNotebookTabId = preferred?.id ?? assignmentNotebookTabs.first?.id
        bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
    }

    @MainActor
    private func createAssignmentNotebookTab(defaultName: String? = nil) {
        guard let selectedClassId else {
            bridge.status = "Selecciona una clase antes de crear una pestaña."
            return
        }
        let requestedName = (defaultName ?? newAssignmentNotebookTabName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedName.isEmpty else { return }
        if let existing = assignmentNotebookTabs.first(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(requestedName) == .orderedSame }) {
            selectedAssignmentNotebookTabId = existing.id
            bridge.selectClass(id: selectedClassId)
            bridge.setSelectedNotebookTab(id: existing.id)
            bridge.status = "La pestaña \(existing.title) ya existía y queda seleccionada."
            return
        }
        bridge.selectClass(id: selectedClassId)
        if let createdTabId = bridge.createTab(title: requestedName) {
            selectedAssignmentNotebookTabId = createdTabId
            bridge.setSelectedNotebookTab(id: createdTabId)
            bridge.status = "Pestaña creada: \(requestedName)"
            Task { await refreshAssignmentNotebookTabs() }
        } else {
            bridge.status = "No se pudo crear la pestaña del cuaderno."
        }
    }

    private func createTest(from template: PhysicalTestTemplate) async {
        guard let selectedClassId else {
            bridge.status = "Selecciona una clase para crear la prueba física."
            return
        }
        do {
            try await bridge.createPhysicalTest(
                classId: selectedClassId,
                code: "EF_\(template.id.uppercased())",
                name: template.name,
                kind: template.measurement.rawValue,
                weight: 1,
                description: template.protocolText
            )
            bridge.status = "Prueba física creada: \(template.name)"
            await reload()
        } catch {
            bridge.status = "No se pudo crear la prueba física: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deletePhysicalTest(_ test: KmpBridge.PhysicalTestSnapshot) async {
        pendingDeleteTest = nil
        do {
            try await bridge.deletePhysicalTest(evaluationId: test.evaluation.id)
            if selectedTestId == test.evaluation.id {
                selectedTestId = nil
            }
            bridge.status = "\(test.evaluation.name) eliminada."
            await reload()
        } catch {
            bridge.status = "No se pudo eliminar la prueba física: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func updatePhysicalTest(_ test: KmpBridge.PhysicalTestSnapshot, name: String, weight: Double, description: String?) async {
        editingTest = nil
        let evaluation = test.evaluation
        let kind = evaluation.type.components(separatedBy: " · ").last ?? evaluation.type
        do {
            try await bridge.updatePhysicalTest(
                evaluationId: evaluation.id,
                classId: evaluation.classId,
                code: evaluation.code,
                name: name,
                kind: kind,
                weight: weight,
                description: description,
                formula: evaluation.formula,
                rubricId: evaluation.rubricId?.int64Value
            )
            bridge.status = "\(name) actualizada."
            await reload()
        } catch {
            bridge.status = "No se pudo actualizar la prueba física: \(error.localizedDescription)"
        }
    }

    private func addTemplateToBattery(_ template: PhysicalTestTemplate) {
        batteryTemplateIds.insert(template.id)
        if batteryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            batteryName = "Condición física"
        }
        selectedTab = .batteries
        bridge.status = "\(template.name) añadida al borrador de batería."
    }

    private func createBattery(_ battery: PhysicalTestBattery) {
        Task {
            for template in PhysicalTestTemplate.defaults where battery.templateIds.contains(template.id) {
                try? await bridge.savePhysicalDefinition(physicalDefinition(from: template))
                await createTest(from: template)
            }
            do {
                let persisted = MiGestorKit.PhysicalTestBattery(
                    id: battery.id,
                    name: battery.name,
                    description: "Creada desde iOS",
                    defaultCourse: selectedSchoolClass.map { KotlinInt(value: $0.course) },
                    defaultAgeFrom: KotlinInt(value: Int32(assignmentAgeFrom)),
                    defaultAgeTo: KotlinInt(value: Int32(assignmentAgeTo)),
                    testIds: Array(battery.templateIds),
                    trace: auditTrace()
                )
                try await bridge.savePhysicalBattery(persisted)
                selectedBatteryId = persisted.id
            } catch {
                bridge.status = "No se pudo guardar la batería física: \(error.localizedDescription)"
            }
            await reload()
            selectedTab = .assignments
            bridge.status = "Batería creada. Asígnala a una clase para crear columnas."
        }
    }

    @MainActor
    private func createAssignment() async {
        guard let selectedClassId else {
            bridge.status = "Selecciona una clase antes de asignar la batería."
            return
        }
        guard let battery = selectedBatteryId.flatMap({ id in batteries.first(where: { $0.id == id }) }) ?? batteries.first else {
            bridge.status = "Crea una batería antes de asignarla."
            return
        }
        guard let selectedAssignmentNotebookTabId else {
            bridge.status = "Selecciona o crea una pestaña del cuaderno para ubicar las columnas."
            return
        }
        bridge.selectClass(id: selectedClassId)
        bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
        let assignment = MiGestorKit.PhysicalTestAssignment(
            id: "pe_assignment_\(Int64(Date().timeIntervalSince1970 * 1000))",
            batteryId: battery.id,
            classId: selectedClassId,
            course: KotlinInt(value: Int32(assignmentCourse)),
            ageFrom: KotlinInt(value: Int32(assignmentAgeFrom)),
            ageTo: KotlinInt(value: Int32(max(assignmentAgeFrom, assignmentAgeTo))),
            termLabel: trimmedOrNil(assignmentTermLabel),
            dateEpochMs: Int64(batteryDate.timeIntervalSince1970 * 1000),
            rawColumnMode: batteryColumnMode == .rawOnly || batteryColumnMode == .rawAndScore,
            scoreColumnMode: batteryColumnMode == .scoreOnly || batteryColumnMode == .rawAndScore,
            trace: auditTrace()
        )
        do {
            try await bridge.assignPhysicalBatteryToClass(assignment)
            try await PhysicalTestsColumnCreationPolicy.createNotebookColumns(
                bridge: bridge,
                battery: battery,
                assignment: assignment,
                selectedAssignmentNotebookTabId: selectedAssignmentNotebookTabId,
                scoreCountsTowardAverage: scoreCountsTowardAverage
            )
            let tabName = selectedAssignmentNotebookTab?.title ?? "la pestaña seleccionada"
            bridge.status = "Asignación creada y columnas preparadas en \(tabName)."
            await reload()
        } catch {
            bridge.status = "No se pudo crear la asignación: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveScale(_ draft: PhysicalTestScaleDraft) async {
        guard let context = activeScaleEditorContext,
              let testId = activeScaleTestId else {
            bridge.status = "Selecciona una prueba antes de guardar el baremo."
            return
        }
        guard draft.validationMessages.isEmpty, !draft.ranges.isEmpty else {
            bridge.status = "Revisa los rangos antes de guardar el baremo."
            return
        }
        let assignment = activeAssignment ?? filteredAssignments.first ?? assignments.first
        let draftBatteryId = trimmedOrNil(draft.batteryId)
        let batteryId = assignment?.batteryId ?? context.batteryId ?? draftBatteryId
        let scaleId = draft.persistedScaleId ?? "ios_pe_scale_\(assignment?.id ?? "global")_\(testId)"
        let ranges = draft.ranges.enumerated().map { index, range in
            MiGestorKit.PhysicalTestScaleRange(
                id: "\(scaleId)_range_\(index + 1)",
                scaleId: scaleId,
                minValue: range.minValue.map { KotlinDouble(value: $0) },
                maxValue: range.maxValue.map { KotlinDouble(value: $0) },
                score: range.score,
                label: trimmedOrNil(range.label),
                sortOrder: Int32(index)
            )
        }
        let persisted = MiGestorKit.PhysicalTestScale(
            id: scaleId,
            testId: testId,
            name: trimmedOrNil(draft.name) ?? "Baremo \(context.testName)",
            course: assignment?.course ?? context.course.map { KotlinInt(value: Int32($0)) },
            ageFrom: assignment?.ageFrom ?? context.ageFrom.map { KotlinInt(value: Int32($0)) },
            ageTo: assignment?.ageTo ?? context.ageTo.map { KotlinInt(value: Int32($0)) },
            sex: trimmedOrNil(draft.sex),
            batteryId: batteryId,
            direction: draft.direction == .lowerIsBetter ? .lowerIsBetter : .higherIsBetter,
            ranges: ranges,
            trace: auditTrace()
        )
        do {
            try await bridge.savePhysicalScale(persisted)
            let resolved = try await bridge.resolvePhysicalScale(
                testId: testId,
                course: persisted.course?.intValue,
                age: persisted.ageFrom?.intValue,
                sex: persisted.sex,
                batteryId: persisted.batteryId
            )
            await reload()
            scale = scaleDraft(from: persisted)
            bridge.status = resolved?.id == persisted.id
                ? "Baremo guardado y resoluble para \(context.testName)."
                : "Baremo guardado para \(context.testName), pero no se pudo resolver con el contexto actual."
        } catch {
            bridge.status = "No se pudo guardar el baremo: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generateProgressAnalysis() async {
        loadPhase = max(loadPhase, .lists)
        let evidence = physicalProgressEvidence
        guard evidence.hasEnoughData else {
            progressAnalysis = nil
            progressAnalysisError = "Registra al menos una marca para analizar la condición física."
            loadPhase = .ai
            return
        }
        isGeneratingProgressAnalysis = true
        progressAnalysisError = nil
        defer {
            isGeneratingProgressAnalysis = false
            loadPhase = .ai
        }
        do {
            let result = try await aiOrchestrator.generate(
                capability: .physicalProgressAnalysis,
                input: .physical(evidence)
            )
            if case .physicalProgressAnalysis(let analysis) = result {
                progressAnalysis = analysis
            }
        } catch {
            progressAnalysisError = error.localizedDescription
        }
    }

    private func scaleDraft(from persisted: MiGestorKit.PhysicalTestScale) -> PhysicalTestScaleDraft {
        PhysicalTestScaleDraft(
            persistedScaleId: persisted.id,
            name: persisted.name,
            testId: persisted.testId,
            course: persisted.course?.intValue,
            ageFrom: persisted.ageFrom?.intValue,
            ageTo: persisted.ageTo?.intValue,
            sex: persisted.sex ?? "",
            batteryId: persisted.batteryId ?? "",
            direction: persisted.direction == .lowerIsBetter ? .lowerIsBetter : .higherIsBetter,
            ranges: persisted.ranges.map {
                PhysicalTestScaleRange(
                    minValue: $0.minValue?.doubleValue,
                    maxValue: $0.maxValue?.doubleValue,
                    score: $0.score,
                    label: $0.label ?? ""
                )
            }
        )
    }



    private func syncSelectedClassDefaults() {
        guard let selectedSchoolClass else { return }
        assignmentCourse = Int(selectedSchoolClass.course)
        selectedFilterCourse = Int(selectedSchoolClass.course)
    }

    private func className(for classId: Int64) -> String {
        bridge.classes.first(where: { $0.id == classId })?.name ?? "Clase \(classId)"
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func columnModeLabel(for assignment: MiGestorKit.PhysicalTestAssignment) -> String {
        switch (assignment.rawColumnMode, assignment.scoreColumnMode) {
        case (true, true): return PhysicalNotebookColumnMode.rawAndScore.rawValue
        case (true, false): return PhysicalNotebookColumnMode.rawOnly.rawValue
        case (false, true): return PhysicalNotebookColumnMode.scoreOnly.rawValue
        default: return "Sin columnas"
        }
    }

    private func testDefinitionId(for test: KmpBridge.PhysicalTestSnapshot) -> String {
        test.evaluation.code
            .replacingOccurrences(of: "EF_", with: "")
            .lowercased()
    }

    private func attemptsCount(for testId: String) -> Int {
        definitions.first(where: { $0.id == testId }).map { Int($0.attempts) }
            ?? PhysicalTestTemplate.defaults.first(where: { $0.id == testId })?.attempts
            ?? 1
    }

    private func direction(for testId: String) -> PhysicalTestScaleDirection {
        if let definition = definitions.first(where: { $0.id == testId }) {
            return definition.higherIsBetter ? .higherIsBetter : .lowerIsBetter
        }
        return PhysicalTestTemplate.defaults.first(where: { $0.id == testId })?.direction ?? .higherIsBetter
    }

    private func resultMode(for testId: String) -> PhysicalTestResultMode {
        guard let mode = definitions.first(where: { $0.id == testId })?.resultMode else {
            return PhysicalTestTemplate.defaults.first(where: { $0.id == testId })?.resultMode ?? .best
        }
        switch mode {
        case .average: return .average
        case .last: return .last
        default: return .best
        }
    }

    private func resetScaleDraftForActiveTest(force: Bool = false) {
        guard let testId = activeScaleTestId, let context = activeScaleEditorContext else { return }
        let normalized = PhysicalScaleProfileCatalog.normalizedTestId(testId)
        guard force || scale.testId != normalized else { return }
        scale = defaultScaleDraft(for: normalized, context: context)
    }

    private func defaultScaleDraft(for testId: String, context: PhysicalTestScaleEditorContext) -> PhysicalTestScaleDraft {
        let input = PhysicalScaleRecommendationInput(
            testId: testId,
            testName: context.testName,
            capacity: context.capacity,
            measurementKind: context.measurementKind,
            unit: context.unit,
            directionLabel: direction(for: testId) == .higherIsBetter ? "mayor marca = mejor nota" : "menor marca = mejor nota",
            sex: scale.sex.isEmpty ? "UNSPECIFIED" : scale.sex,
            course: context.course.map { "\($0)º" } ?? "Sin curso",
            ageFrom: context.ageFrom,
            ageTo: context.ageTo,
            objective: "Mixto",
            scoreScale: "0-10"
        )
        let ranges = PhysicalScaleProfileCatalog.seedRanges(for: input).map {
            PhysicalTestScaleRange(minValue: $0.minValue, maxValue: $0.maxValue, score: $0.score, label: $0.label)
        }
        return PhysicalTestScaleDraft(
            persistedScaleId: nil,
            name: "Baremo \(context.testName) 0-10",
            testId: testId,
            course: context.course,
            ageFrom: context.ageFrom,
            ageTo: context.ageTo,
            sex: "",
            batteryId: context.batteryId ?? "",
            direction: direction(for: testId),
            ranges: ranges
        )
    }

    private func physicalTestDescriptor(for testId: String) -> (name: String, capacity: String, measurementKind: String, unit: String)? {
        if let template = PhysicalTestTemplate.defaults.first(where: { $0.id == testId }) {
            return (template.name, template.capacity.rawValue, template.measurement.rawValue, template.unit)
        }
        if let definition = definitions.first(where: { $0.id == testId }) {
            return (
                definition.name,
                physicalCapacityLabel(definition.capacity),
                physicalMeasurementLabel(definition.measurementKind),
                definition.unit
            )
        }
        if let selectedTest, testDefinitionId(for: selectedTest) == testId {
            return (selectedTest.evaluation.name, selectedTest.evaluation.type, selectedTest.evaluation.type, "")
        }
        return nil
    }

    private func physicalCapacityLabel(_ capacity: PhysicalCapacity) -> String {
        switch capacity {
        case .resistance: return PhysicalTestCapacity.resistance.rawValue
        case .strength: return PhysicalTestCapacity.strength.rawValue
        case .speed: return PhysicalTestCapacity.speed.rawValue
        case .flexibility: return PhysicalTestCapacity.flexibility.rawValue
        default: return String(describing: capacity)
        }
    }

    private func physicalMeasurementLabel(_ measurement: PhysicalMeasurementKind) -> String {
        switch measurement {
        case .time: return PhysicalTestMeasurement.time.rawValue
        case .distance: return PhysicalTestMeasurement.distance.rawValue
        case .repetitions: return PhysicalTestMeasurement.repetitions.rawValue
        case .level: return PhysicalTestMeasurement.level.rawValue
        default: return String(describing: measurement)
        }
    }

    private func auditTrace() -> AuditTrace {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: selectedClassId.map { KotlinLong(value: $0) }, deviceId: nil, syncVersion: 0)
    }

    private func physicalDefinition(from template: PhysicalTestTemplate) -> MiGestorKit.PhysicalTestDefinition {
        MiGestorKit.PhysicalTestDefinition(
            id: template.id,
            name: template.name,
            capacity: physicalCapacity(from: template.capacity),
            measurementKind: physicalMeasurement(from: template.measurement),
            unit: template.unit,
            higherIsBetter: template.direction == .higherIsBetter,
            protocol: template.protocolText,
            material: "",
            attempts: Int32(template.attempts),
            resultMode: physicalResultMode(from: template.resultMode),
            trace: auditTrace()
        )
    }

    private func physicalCapacity(from capacity: PhysicalTestCapacity) -> PhysicalCapacity {
        switch capacity {
        case .resistance: return .resistance
        case .strength: return .strength
        case .speed: return .speed
        case .flexibility: return .flexibility
        }
    }

    private func physicalMeasurement(from measurement: PhysicalTestMeasurement) -> PhysicalMeasurementKind {
        switch measurement {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .level
        }
    }

    private func physicalResultMode(from mode: PhysicalTestResultMode) -> PhysicalResultMode {
        switch mode {
        case .best: return .best
        case .average: return .average
        case .last: return .last
        }
    }
}

private struct PhysicalStatCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.24)))
    }
}

private struct PhysicalMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PhysicalTemplateCard: View {
    let template: PhysicalTestTemplate
    let onCreate: () -> Void

    var body: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(template.capacity.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Text(template.name)
                    .font(.headline)
                Text("\(template.measurement.rawValue) · \(template.unit) · \(template.resultMode.rawValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(template.protocolText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Button {
                    onCreate()
                } label: {
                    Label("Añadir a batería", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var icon: String {
        switch template.capacity {
        case .resistance: return "lungs.fill"
        case .strength: return "figure.strengthtraining.traditional"
        case .speed: return "hare.fill"
        case .flexibility: return "figure.cooldown"
        }
    }
}

private struct PhysicalBatteryBuilder: View {
    let templates: [PhysicalTestTemplate]
    let selectedClassName: String
    @Binding var name: String
    @Binding var date: Date
    @Binding var selectedTemplateIds: Set<String>
    @Binding var columnMode: PhysicalNotebookColumnMode
    let onCreate: (PhysicalTestBattery) -> Void

    @State private var dummyScoreCountsTowardAverage = true

    private var quickTemplates: [PhysicalBatteryQuickTemplate] {
        PhysicalBatteryQuickTemplate.defaults(for: templates)
    }

    var body: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crear batería")
                        .font(.headline)
                    Text(selectedClassName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                TextField("Nombre", text: $name)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plantillas rápidas")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                        ForEach(quickTemplates) { quickTemplate in
                            Button {
                                name = quickTemplate.title
                                selectedTemplateIds = quickTemplate.templateIds
                            } label: {
                                Text(quickTemplate.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pruebas")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                        ForEach(templates) { template in
                            Button {
                                if selectedTemplateIds.contains(template.id) {
                                    selectedTemplateIds.remove(template.id)
                                } else {
                                    selectedTemplateIds.insert(template.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedTemplateIds.contains(template.id) ? "checkmark.circle.fill" : "circle")
                                    Text(template.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(8)
                                .background(selectedTemplateIds.contains(template.id) ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                DisclosureGroup("Opciones avanzadas") {
                    PhysicalTestsColumnOptionsView(
                        columnMode: $columnMode,
                        scoreCountsTowardAverage: $dummyScoreCountsTowardAverage
                    )
                    .padding(.top, 8)
                }

                Button {
                    onCreate(
                        PhysicalTestBattery(
                            id: "pe_battery_\(Int64(Date().timeIntervalSince1970 * 1000))",
                            name: name,
                            date: date,
                            templateIds: selectedTemplateIds,
                            columnMode: columnMode
                        )
                    )
                } label: {
                    Label("Crear batería", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTemplateIds.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

extension PhysicalTestsWorkspaceView {
    private var reportsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Informe de condición física")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                if tests.isEmpty {
                    PhysicalEmptyState(
                        title: "Sin datos para informes",
                        systemImage: "doc.text.magnifyingglass",
                        subtitle: "Registra marcas en capturas para ver estadísticas e informes de rendimiento de la clase."
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    PhysicalProgressAnalysisCard(
                        analysis: progressAnalysis,
                        evidence: physicalProgressEvidence,
                        isLoading: isGeneratingProgressAnalysis,
                        errorMessage: progressAnalysisError,
                        onRefresh: {
                            Task { await generateProgressAnalysis() }
                        }
                    )

                    NotebookSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Resumen de rendimiento de la clase")
                                .font(.headline)
                            
                            HStack {
                                Spacer()
                                ShareLink(item: physicalReportExportText) {
                                    Label("Exportar informe de clase", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            
                            Divider()

                            ForEach(tests, id: \.evaluation.id) { test in
                                HStack {
                                    Text(test.evaluation.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("Media: \(PhysicalTestsFormatting.decimal(test.average))")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        Text("Mejor: \(test.best.map { PhysicalTestsFormatting.decimal($0) } ?? "-")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .padding(20)
        }
    }

    private var physicalReportExportText: String {
        var lines = [
            "Informe de Condición Física de \(selectedClassName)",
            "Pruebas registradas: \(tests.count)",
            "Registros totales: \(recordedCount)"
        ]
        if let progressAnalysis {
            lines += [
                "",
                "Análisis",
                progressAnalysis.summary,
                "Tendencia: \(progressAnalysis.trend)"
            ]
            if !progressAnalysis.strengths.isEmpty {
                lines += ["", "Fortalezas"] + progressAnalysis.strengths.map { "- \($0)" }
            }
            if !progressAnalysis.weaknesses.isEmpty {
                lines += ["", "A vigilar"] + progressAnalysis.weaknesses.map { "- \($0)" }
            }
            if !progressAnalysis.recommendations.isEmpty {
                lines += ["", "Recomendaciones"] + progressAnalysis.recommendations.map { "- \($0)" }
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct PhysicalProgressAnalysisCard: View {
    let analysis: PhysicalProgressAnalysis?
    let evidence: PhysicalProgressEvidence
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Análisis EF local", systemImage: "figure.run.circle")
                            .font(.headline)
                        Text("Cobertura \(IosFormatting.decimal(from: evidence.completionRate))% · \(evidence.recordedCount)/\(evidence.totalCount) registros")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: onRefresh) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    .accessibilityLabel("Actualizar análisis de condición física")
                }

                if isLoading && analysis == nil {
                    ProgressView("Analizando marcas registradas...")
                        .tint(NotebookStyle.primaryTint)
                } else if let analysis {
                    Text(analysis.summary)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        PhysicalAnalysisBadge(title: "Tendencia", value: analysis.trend, systemImage: "chart.line.uptrend.xyaxis")
                        PhysicalAnalysisBadge(
                            title: "Mejora",
                            value: analysis.improvementPercentage.map { "\(IosFormatting.decimal(from: $0))%" } ?? "Sin histórico",
                            systemImage: "percent"
                        )
                    }

                    PhysicalAnalysisList(title: "Fortalezas", items: analysis.strengths, tint: .green)
                    PhysicalAnalysisList(title: "A vigilar", items: analysis.weaknesses, tint: .orange)
                    PhysicalAnalysisList(title: "Recomendaciones", items: analysis.recommendations, tint: NotebookStyle.primaryTint)

                    if !analysis.alerts.isEmpty {
                        PhysicalAnalysisList(title: "Alertas", items: analysis.alerts, tint: .red)
                    }

                    Text(analysis.confidenceNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(errorMessage ?? "Sin análisis disponible todavía.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PhysicalAnalysisBadge: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(NotebookStyle.primaryTint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PhysicalAnalysisList: View {
    let title: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Sin datos destacados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(tint)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(item)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct PhysicalHistoryValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PhysicalEmptyState: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.black))
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct PhysicalTestEditSheet: View {
    let test: KmpBridge.PhysicalTestSnapshot
    let onSave: (String, Double, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var weightText: String
    @State private var description: String

    init(test: KmpBridge.PhysicalTestSnapshot, onSave: @escaping (String, Double, String?) -> Void) {
        self.test = test
        self.onSave = onSave
        _name = State(initialValue: test.evaluation.name)
        _weightText = State(initialValue: PhysicalTestsFormatting.decimal(test.evaluation.weight))
        _description = State(initialValue: test.evaluation.description_ ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prueba física") {
                    TextField("Nombre", text: $name)
                    TextField("Peso", text: $weightText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Descripción", text: $description)
                }
            }
            .navigationTitle("Editar prueba")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? test.evaluation.weight
                        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            weight,
                            trimmedDescription.isEmpty ? nil : trimmedDescription
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct PhysicalTestCreationSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let templates: [PhysicalTestTemplate]
    let onSaved: () -> Void

    @State private var selectedTemplateId = PhysicalTestTemplate.defaults.first?.id ?? ""
    @State private var name = ""
    @State private var code = ""
    @State private var weight = "1"
    @State private var description = ""

    private var selectedTemplate: PhysicalTestTemplate? {
        templates.first(where: { $0.id == selectedTemplateId })
    }

    private var canSave: Bool {
        defaultClassId != nil &&
        selectedTemplate != nil &&
        Double(weight.replacingOccurrences(of: ",", with: ".")) != nil &&
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        PhysicalTestCreationScaffold(
            title: "Nueva prueba física",
            subtitle: "Crea una medición lista para capturar marcas del grupo actual.",
            systemImage: "stopwatch",
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: { Task { await save() } }
        ) {
            PremiumCard.section(title: "Plantilla", systemImage: "figure.run") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Plantilla", selection: $selectedTemplateId) {
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .appOnChange(of: selectedTemplateId) { _ in syncTemplate() }

                    if let selectedTemplate {
                        PhysicalTestTemplateSummary(template: selectedTemplate)
                    }
                }
            }

            PremiumCard.section(title: "Datos evaluables", systemImage: "number.square") {
                VStack(spacing: 14) {
                    PhysicalTestSheetTextField(title: "Código", placeholder: "EF_NAVETTE", text: $code)
                    PhysicalTestSheetTextField(title: "Nombre", placeholder: "Course Navette", text: $name)
                    PhysicalTestSheetTextField(title: "Peso", placeholder: "1", text: $weight)
                        .appKeyboardType(.decimalPad)
                }
            }

            PremiumCard.section(title: "Protocolo", systemImage: "checklist") {
                TextField("Protocolo", text: $description, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(EvaluationDesign.border, lineWidth: 1)
                    }
            }

            if defaultClassId == nil {
                PhysicalTestSheetNotice(
                    systemImage: "person.3.sequence",
                    text: "Selecciona una clase antes de crear la prueba física.",
                    tint: .orange
                )
            }
        }
        .onAppear(perform: syncTemplate)
    }

    private func syncTemplate() {
        guard let selectedTemplate else { return }
        if name.isEmpty { name = selectedTemplate.name }
        if code.isEmpty { code = "EF_\(selectedTemplate.id.uppercased())" }
        if description.isEmpty { description = selectedTemplate.protocolText }
    }

    private func save() async {
        guard let defaultClassId,
              let numericWeight = Double(weight.replacingOccurrences(of: ",", with: ".")),
              let selectedTemplate,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            bridge.status = "Completa clase, código, nombre y peso para crear la prueba."
            return
        }
        do {
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            try await bridge.createPhysicalTest(
                classId: defaultClassId,
                code: code,
                name: name,
                kind: selectedTemplate.measurement.rawValue,
                weight: numericWeight,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription
            )
            bridge.status = "Prueba física creada."
            onSaved()
            dismiss()
        } catch {
            bridge.status = "No se pudo crear la prueba física: \(error.localizedDescription)"
        }
    }
}

private struct PhysicalTestCreationScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PhysicalTestCreationHero(title: title, subtitle: subtitle, systemImage: systemImage)
                    content
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(EvaluationDesign.surface.opacity(0.45))
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: onSave)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 720, minHeight: 560, idealHeight: 660)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

private struct PhysicalTestCreationHero: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(EvaluationDesign.accent)
                .frame(width: 48, height: 48)
                .background(EvaluationDesign.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        }
    }
}

private struct PhysicalTestTemplateSummary: View {
    let template: PhysicalTestTemplate

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                pills
            }

            VStack(alignment: .leading, spacing: 10) {
                pills
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pills: some View {
        PhysicalTestTemplatePill(title: template.capacity.rawValue, systemImage: "heart.text.square")
        PhysicalTestTemplatePill(title: "\(template.measurement.rawValue) · \(template.unit)", systemImage: "ruler")
        PhysicalTestTemplatePill(title: template.resultMode.rawValue, systemImage: "target")
    }
}

private struct PhysicalTestTemplatePill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(EvaluationDesign.surface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(EvaluationDesign.border, lineWidth: 1)
            }
    }
}

private struct PhysicalTestSheetTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 1)
                }
        }
    }
}

private struct PhysicalTestSheetNotice: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        }
    }
}
