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
    case bank = "Banco"
    case batteries = "Baterías"
    case assignments = "Asignaciones"
    case capture = "Captura"
    case scales = "Baremos"
    case history = "Histórico"

    var id: String { rawValue }
}

private enum PhysicalNotebookColumnMode: String, CaseIterable, Identifiable {
    case rawOnly = "Solo marca"
    case rawAndScore = "Marca + nota baremada"
    case scoreOnly = "Solo nota baremada"

    var id: String { rawValue }
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
    @State private var definitions: [MiGestorKit.PhysicalTestDefinition] = []
    @State private var batteries: [MiGestorKit.PhysicalTestBattery] = []
    @State private var batteryName = "Condición física inicial"
    @State private var batteryDate = Date()
    @State private var batteryTemplateIds: Set<String> = Set(PhysicalTestTemplate.defaults.prefix(4).map(\.id))
    @State private var batteryColumnMode: PhysicalNotebookColumnMode = .rawAndScore
    @State private var selectedBatteryId: String?
    @State private var assignments: [MiGestorKit.PhysicalTestAssignment] = []
    @State private var notebookLinks: [MiGestorKit.PhysicalTestNotebookLink] = []
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

    private var activeScaleEditorContext: PhysicalTestScaleEditorContext? {
        let testId = selectedTest.map(testDefinitionId(for:)) ?? selectedFilterTestId ?? PhysicalTestTemplate.defaults.first?.id
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

                Group {
                    switch selectedTab {
                    case .bank:
                        bankView
                    case .batteries:
                        batteriesView
                    case .assignments:
                        assignmentsView
                    case .capture:
                        captureDashboard
                    case .scales:
                        scalesView
                    case .history:
                        historyView
                    }
                }
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
            .onChange(of: selectedClassId) { _ in Task { await reload() } }
            .onChange(of: selectedClassId) { _ in syncSelectedClassDefaults() }
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
                        attemptsCount: attemptsCount(for: testDefinitionId(for: selectedTest)),
                        direction: direction(for: testDefinitionId(for: selectedTest)),
                        resultMode: resultMode(for: testDefinitionId(for: selectedTest)),
                        onSaved: { await reload() }
                    )
                }
            }
            .sheet(isPresented: $showingScaleEditor) {
                NavigationStack {
                    PhysicalTestScaleEditor(scale: $scale, context: activeScaleEditorContext)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") { showingScaleEditor = false }
                            }
                        }
                }
            }
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
                    showingScaleEditor = true
                } label: {
                    Label("Baremos", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                PhysicalStatCard(title: "Pruebas", value: "\(tests.count)", tint: .blue)
                PhysicalStatCard(title: "Registros", value: "\(recordedCount)", tint: .green)
                PhysicalStatCard(title: "Banco", value: "\(max(definitions.count, PhysicalTestTemplate.defaults.count))", tint: .orange)
                PhysicalStatCard(title: "Baterías", value: "\(batteries.count)", tint: .purple)
            }
        }
        .padding(20)
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
                            set: { selectedClassId = $0 }
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
                        Picker("Columnas", selection: $batteryColumnMode) {
                            ForEach(PhysicalNotebookColumnMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("La nota cuenta para la media", isOn: $scoreCountsTowardAverage)
                        Button {
                            Task { await createAssignment() }
                        } label: {
                            Label("Crear asignación y columnas", systemImage: "link.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedClassId == nil || batteries.isEmpty)
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
        HStack(spacing: 0) {
            testsList
                .frame(minWidth: 320, maxWidth: 380)

            Divider()

            if let selectedTest {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedTest.evaluation.name)
                        .font(.system(size: 30, weight: .black, design: .rounded))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
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
                .padding(20)
            } else {
                PhysicalEmptyState(
                    title: "Sin prueba seleccionada",
                    systemImage: "stopwatch",
                    subtitle: "Crea o selecciona una prueba física para capturar marcas."
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            PhysicalTestScaleEditor(scale: $scale, context: activeScaleEditorContext)
                .navigationTitle("Baremos")
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
                }
            }
        }
        .listStyle(.sidebar)
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
        guard let selectedClassId else {
            tests = []
            selectedTestId = nil
            selectedStudentId = nil
            assignments = []
            notebookLinks = []
            return
        }
        definitions = (try? await bridge.listPhysicalDefinitions()) ?? []
        batteries = (try? await bridge.listPhysicalBatteries()) ?? []
        assignments = (try? await bridge.listPhysicalAssignmentsForClass(classId: selectedClassId)) ?? []
        notebookLinks = []
        for assignment in assignments {
            let links = (try? await bridge.listPhysicalNotebookLinksForAssignment(assignmentId: assignment.id)) ?? []
            notebookLinks.append(contentsOf: links)
        }
        tests = (try? await bridge.loadPhysicalTests(classId: selectedClassId)) ?? []
        if selectedBatteryId == nil || !batteries.contains(where: { $0.id == selectedBatteryId }) {
            selectedBatteryId = batteries.first?.id
        }
        if selectedTestId == nil || !filteredTests.contains(where: { $0.evaluation.id == selectedTestId }) {
            selectedTestId = filteredTests.first?.evaluation.id
        }
        if selectedStudentId == nil || !(selectedTest?.results.contains(where: { $0.student.id == selectedStudentId }) ?? false) {
            selectedStudentId = selectedTest?.results.first?.student.id
        }
        syncSelectedClassDefaults()
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
            try await createNotebookColumns(for: battery, assignment: assignment)
            await reload()
        } catch {
            bridge.status = "No se pudo crear la asignación: \(error.localizedDescription)"
        }
    }

    private func createNotebookColumns(for battery: MiGestorKit.PhysicalTestBattery, assignment: MiGestorKit.PhysicalTestAssignment) async throws {
        let selectedClassId = assignment.classId
        bridge.selectClass(id: selectedClassId)
        let selectedTemplates = PhysicalTestTemplate.defaults.filter { battery.testIds.contains($0.id) }
        let categoryId = assignment.id
        bridge.saveColumnCategory(name: "\(battery.name) · \(assignment.termLabel ?? "Evaluación física")", categoryId: categoryId)

        for template in selectedTemplates {
            var rawColumnId: String?
            var scoreColumnId: String?
            if assignment.rawColumnMode {
                rawColumnId = try await bridge.createNotebookPhysicalColumnForClass(
                    classId: selectedClassId,
                    name: "\(template.name) · marca",
                    categoryId: categoryId,
                    inputKind: template.measurement.inputKind,
                    unitOrSituation: template.unit,
                    scaleKind: template.measurement.scaleKind,
                    iconName: "stopwatch.fill",
                    weight: 0,
                    countsTowardAverage: false,
                    dateEpochMs: assignment.dateEpochMs
                )
            }

            if assignment.scoreColumnMode {
                scoreColumnId = try await bridge.createNotebookPhysicalColumnForClass(
                    classId: selectedClassId,
                    name: "\(template.name) · nota",
                    categoryId: categoryId,
                    inputKind: .numeric010,
                    unitOrSituation: "Nota baremada",
                    scaleKind: .tenPoint,
                    iconName: "chart.bar.fill",
                    weight: 10,
                    countsTowardAverage: scoreCountsTowardAverage,
                    dateEpochMs: assignment.dateEpochMs
                )
            }
            try await bridge.savePhysicalNotebookLink(
                MiGestorKit.PhysicalTestNotebookLink(
                    assignmentId: assignment.id,
                    testId: template.id,
                    rawColumnId: rawColumnId,
                    scoreColumnId: scoreColumnId,
                    trace: auditTrace()
                )
            )
        }
        bridge.status = "Asignación creada y columnas preparadas para \(battery.name)."
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
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Columnas en cuaderno", selection: $columnMode) {
                            ForEach(PhysicalNotebookColumnMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Las notas se podrán ponderar después desde la columna Media.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
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

    var body: some View {
        NavigationStack {
            Form {
                Picker("Plantilla", selection: $selectedTemplateId) {
                    ForEach(templates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
                .onChange(of: selectedTemplateId) { _ in syncTemplate() }

                TextField("Código", text: $code)
                TextField("Nombre", text: $name)
                TextField("Peso", text: $weight)
                    .appKeyboardType(.decimalPad)
                TextField("Protocolo", text: $description, axis: .vertical)
            }
            .navigationTitle("Nueva prueba física")
            .onAppear(perform: syncTemplate)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                    .fontWeight(.bold)
                }
            }
        }
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
