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
    case capture = "Captura"
    case history = "Histórico"

    var id: String { rawValue }
}

private enum PhysicalNotebookColumnMode: String, CaseIterable, Identifiable {
    case rawOnly = "Solo marca"
    case rawAndScore = "Marca + nota baremada"
    case scoreOnly = "Solo nota baremada"

    var id: String { rawValue }
}

private struct PhysicalTestBattery: Identifiable {
    let id = UUID()
    var name: String
    var date: Date
    var templateIds: Set<String>
    var columnMode: PhysicalNotebookColumnMode
    var includeScoreInAverage: Bool
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
    @State private var batteries: [PhysicalTestBattery] = []
    @State private var scale = PhysicalTestScaleDraft.defaultJump

    private var selectedClassName: String {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id })?.name } ?? "Clase global"
    }

    private var selectedTest: KmpBridge.PhysicalTestSnapshot? {
        tests.first(where: { $0.evaluation.id == selectedTestId })
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

                Divider()

                Group {
                    switch selectedTab {
                    case .bank:
                        bankView
                    case .batteries:
                        batteriesView
                    case .capture:
                        captureDashboard
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
            .sheet(isPresented: $showingCreateSheet) {
                PhysicalTestCreationSheet(defaultClassId: selectedClassId, templates: PhysicalTestTemplate.defaults) {
                    Task { await reload() }
                }
                .environmentObject(bridge)
            }
            .sheet(isPresented: $showingCapture) {
                if let selectedClassId, let selectedTest {
                    PhysicalTestCaptureView(
                        bridge: bridge,
                        classId: selectedClassId,
                        test: selectedTest,
                        scale: scale,
                        onSaved: { await reload() }
                    )
                }
            }
            .sheet(isPresented: $showingScaleEditor) {
                NavigationStack {
                    PhysicalTestScaleEditor(scale: $scale)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") { showingScaleEditor = false }
                            }
                        }
                }
            }
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
                PhysicalStatCard(title: "Banco", value: "\(PhysicalTestTemplate.defaults.count)", tint: .orange)
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
                        Task { await createTest(from: template) }
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
                    onCreate: createBattery
                )

                ForEach(batteries) { battery in
                    NotebookSurface {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(battery.name)
                                    .font(.headline)
                                Text("\(battery.templateIds.count) pruebas · \(battery.columnMode.rawValue)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(battery.date, style: .date)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("TODO(kmp-physical-tests): persistir baterías como sesiones de medición y vincularlas con columnas de cuaderno.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                    .disabled(selectedClassId == nil)

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
                    ForEach(tests, id: \.evaluation.id) { test in
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

                Text("TODO(kmp-physical-tests): calcular evolución real por alumno con PhysicalTestResult histórico, rawValue, score y observedAtEpochMs.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
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
            return
        }
        tests = (try? await bridge.loadPhysicalTests(classId: selectedClassId)) ?? []
        if selectedTestId == nil || !tests.contains(where: { $0.evaluation.id == selectedTestId }) {
            selectedTestId = tests.first?.evaluation.id
        }
        if selectedStudentId == nil || !(selectedTest?.results.contains(where: { $0.student.id == selectedStudentId }) ?? false) {
            selectedStudentId = selectedTest?.results.first?.student.id
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

    private func createBattery(_ battery: PhysicalTestBattery) {
        batteries.insert(battery, at: 0)
        Task {
            for template in PhysicalTestTemplate.defaults where battery.templateIds.contains(template.id) {
                await createTest(from: template)
            }
            createNotebookColumns(for: battery)
        }
    }

    private func createNotebookColumns(for battery: PhysicalTestBattery) {
        guard let selectedClassId else { return }
        bridge.selectClass(id: selectedClassId)
        let selectedTemplates = PhysicalTestTemplate.defaults.filter { battery.templateIds.contains($0.id) }
        let categoryId = "pe_battery_\(Int64(Date().timeIntervalSince1970 * 1000))"
        bridge.saveColumnCategory(name: battery.name, categoryId: categoryId)

        for template in selectedTemplates {
            if battery.columnMode == .rawOnly || battery.columnMode == .rawAndScore {
                bridge.addColumn(
                    name: "\(template.name) · marca",
                    type: NotebookColumnType.numeric.name,
                    weight: 0,
                    formula: nil,
                    rubricId: nil,
                    categoryId: categoryId,
                    categoryKind: .physicalEducation,
                    instrumentKind: .physicalTest,
                    inputKind: template.measurement.inputKind,
                    dateEpochMs: Int64(battery.date.timeIntervalSince1970 * 1000),
                    unitOrSituation: template.unit,
                    scaleKind: template.measurement.scaleKind,
                    iconName: "stopwatch.fill",
                    countsTowardAverage: false
                )
            }

            if battery.columnMode == .rawAndScore || battery.columnMode == .scoreOnly {
                bridge.addColumn(
                    name: "\(template.name) · nota",
                    type: NotebookColumnType.numeric.name,
                    weight: 10,
                    formula: nil,
                    rubricId: nil,
                    categoryId: categoryId,
                    categoryKind: .physicalEducation,
                    instrumentKind: .physicalTest,
                    inputKind: .numeric010,
                    dateEpochMs: Int64(battery.date.timeIntervalSince1970 * 1000),
                    unitOrSituation: "Nota baremada",
                    scaleKind: .tenPoint,
                    iconName: "chart.bar.fill",
                    countsTowardAverage: battery.includeScoreInAverage
                )
            }
        }
        bridge.status = "Columnas de cuaderno preparadas para \(battery.name)."
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
                    Label("Crear prueba", systemImage: "plus.circle.fill")
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
    let onCreate: (PhysicalTestBattery) -> Void

    @State private var name = "Condición física inicial"
    @State private var date = Date()
    @State private var selectedTemplateIds: Set<String> = Set(PhysicalTestTemplate.defaults.prefix(4).map(\.id))
    @State private var columnMode: PhysicalNotebookColumnMode = .rawAndScore
    @State private var includeScoreInAverage = false

    var body: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Crear batería")
                            .font(.headline)
                        Text(selectedClassName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onCreate(
                            PhysicalTestBattery(
                                name: name,
                                date: date,
                                templateIds: selectedTemplateIds,
                                columnMode: columnMode,
                                includeScoreInAverage: includeScoreInAverage
                            )
                        )
                    } label: {
                        Label("Crear", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTemplateIds.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TextField("Nombre", text: $name)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)

                Picker("Columnas en cuaderno", selection: $columnMode) {
                    ForEach(PhysicalNotebookColumnMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("La nota baremada entra en Media", isOn: $includeScoreInAverage)
                    .disabled(columnMode == .rawOnly)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
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
                            .padding(10)
                            .background(selectedTemplateIds.contains(template.id) ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
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
