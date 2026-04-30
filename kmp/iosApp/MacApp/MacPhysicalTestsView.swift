import SwiftUI
import MiGestorKit
import Charts

extension KmpBridge.PhysicalTestSnapshot: Identifiable {
    var id: Int64 { evaluation.id }
}

extension PhysicalTestBattery: @retroactive Identifiable {}
extension PhysicalTestAssignment: @retroactive Identifiable {}
extension PhysicalTestResult: @retroactive Identifiable {}

private enum PhysicalTestsMacSection: String, CaseIterable, Identifiable {
    case dashboard
    case bank
    case batteries
    case assignments
    case capture
    case scales
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Resumen"
        case .bank: return "Banco de pruebas"
        case .batteries: return "Baterías"
        case .assignments: return "Asignaciones"
        case .capture: return "Captura"
        case .scales: return "Baremos"
        case .history: return "Histórico"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .bank: return "list.bullet.rectangle"
        case .batteries: return "rectangle.stack.badge.plus"
        case .assignments: return "link.circle"
        case .capture: return "tablecells"
        case .scales: return "slider.horizontal.3"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

private enum MacPhysicalNotebookColumnMode: String, CaseIterable, Identifiable {
    case rawOnly = "Solo marca"
    case rawAndScore = "Marca + nota baremada"
    case scoreOnly = "Solo nota baremada"

    var id: String { rawValue }
}

private struct MacPhysicalTestBattery: Identifiable {
    let id: String
    var name: String
    var date: Date
    var templateIds: Set<String>
    var columnMode: MacPhysicalNotebookColumnMode
}

private struct MacPhysicalTestAssignment: Identifiable {
    let id: String
    var batteryId: String
    var classId: Int64
    var className: String
    var course: Int
    var ageFrom: Int
    var ageTo: Int
    var termLabel: String
    var date: Date
    var columnMode: MacPhysicalNotebookColumnMode
}

private enum MacPhysicalAssignmentStatus: String {
    case columnsCreated = "Columnas creadas"
    case noColumns = "Sin columnas"
    case pendingCapture = "Pendiente de captura"

    var tint: Color {
        switch self {
        case .columnsCreated: return MacAppStyle.successTint
        case .noColumns: return MacAppStyle.warningTint
        case .pendingCapture: return MacAppStyle.infoTint
        }
    }
}

private struct MacPhysicalHistoryRow: Identifiable {
    let id: String
    let studentId: Int64
    let studentName: String
    let course: Int
    let testId: String
    let testName: String
    let rawValue: Double?
    let score: Double?
    let date: Date
    let evolution: Double?
}

private struct MacPhysicalTimePoint: Identifiable {
    let id = UUID()
    let date: Date
    let testName: String
    let value: Double
}

private struct MacPhysicalBucket: Identifiable {
    let id: String
    let label: String
    let count: Int
}

private enum MacPhysicalScaleStatus: String {
    case missing = "Sin baremo"
    case created = "Baremo creado"
    case needsReview = "Revisar rangos"

    var tint: Color {
        switch self {
        case .missing: return MacAppStyle.warningTint
        case .created: return MacAppStyle.successTint
        case .needsReview: return MacAppStyle.infoTint
        }
    }
}

private struct MacPhysicalScaleTestRow: Identifiable {
    let id: String
    let name: String
    let measurement: String
    let unit: String
    let direction: PhysicalTestScaleDirection
    let status: MacPhysicalScaleStatus
}

private struct MacPhysicalTestCaptureRow: Identifiable {
    let id: Int64
    let studentName: String
    var attempt1: String
    var attempt2: String
    var attempt3: String
    var result: String
    var score: String
    var status: String
}

struct MacPhysicalTestsView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @ObservedObject var toolbarActions: MacPhysicalTestsToolbarActions

    @State private var section: PhysicalTestsMacSection = .dashboard
    @State private var tests: [KmpBridge.PhysicalTestSnapshot] = []
    @State private var selectedTestId: Int64?
    @State private var selectedTemplateId: String? = PhysicalTestTemplate.defaults.first?.id
    @State private var definitions: [MiGestorKit.PhysicalTestDefinition] = []
    @State private var batteries: [MiGestorKit.PhysicalTestBattery] = []
    @State private var assignments: [MiGestorKit.PhysicalTestAssignment] = []
    @State private var notebookLinks: [MiGestorKit.PhysicalTestNotebookLink] = []
    @State private var physicalResults: [MiGestorKit.PhysicalTestResult] = []
    @State private var batteryName = "Condición física inicial"
    @State private var batteryDate = Date()
    @State private var batteryTemplateIds = Set(PhysicalTestTemplate.defaults.prefix(4).map(\.id))
    @State private var batteryColumnMode: MacPhysicalNotebookColumnMode = .rawAndScore
    @State private var selectedBatteryId: String?
    @State private var assignmentCourse = 1
    @State private var assignmentAgeFrom = 12
    @State private var assignmentAgeTo = 13
    @State private var assignmentTermLabel = "1ª evaluación"
    @State private var assignmentNotebookTabs: [NotebookTab] = []
    @State private var selectedAssignmentNotebookTabId: String?
    @State private var newAssignmentNotebookTabName = "Condición física"
    @State private var historyBatteryFilter: String?
    @State private var historyTestFilter: String?
    @State private var historyPeriodFilter = ""
    @State private var selectedScaleAssignmentId: String?
    @State private var selectedScaleTestId: String?
    @State private var physicalScalesByTestId: [String: [MiGestorKit.PhysicalTestScale]] = [:]
    @State private var captureDrafts: [Int64: [String]] = [:]
    @State private var scale = PhysicalTestScaleDraft.defaultJump

    private var selectedClassName: String {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id })?.name } ?? "Sin clase seleccionada"
    }

    private var selectedTest: KmpBridge.PhysicalTestSnapshot? {
        tests.first(where: { $0.evaluation.id == selectedTestId }) ?? tests.first
    }

    private var selectedTemplate: PhysicalTestTemplate {
        PhysicalTestTemplate.defaults.first(where: { $0.id == selectedTemplateId }) ?? PhysicalTestTemplate.defaults[0]
    }

    private var selectedSchoolClass: SchoolClass? {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id }) }
    }

    private var selectedAssignmentNotebookTab: NotebookTab? {
        selectedAssignmentNotebookTabId.flatMap { id in assignmentNotebookTabs.first(where: { $0.id == id }) }
    }

    private var selectedScaleAssignment: MiGestorKit.PhysicalTestAssignment? {
        selectedScaleAssignmentId.flatMap { id in assignments.first(where: { $0.id == id }) } ?? assignments.first
    }

    private var selectedScaleBattery: MiGestorKit.PhysicalTestBattery? {
        guard let selectedScaleAssignment else { return nil }
        return batteries.first(where: { $0.id == selectedScaleAssignment.batteryId })
    }

    private var selectedScaleTestRow: MacPhysicalScaleTestRow? {
        scaleTestRows.first(where: { $0.id == selectedScaleTestId }) ?? scaleTestRows.first
    }

    private var selectedScaleDefinition: MiGestorKit.PhysicalTestDefinition? {
        guard let testId = selectedScaleTestRow?.id else { return nil }
        return definitions.first(where: { $0.id == testId })
    }

    private var recordedCount: Int {
        tests.reduce(0) { $0 + $1.recordedCount }
    }

    private var studentCount: Int {
        selectedTest?.results.count ?? 0
    }

    private var selectedClassStudentCount: Int {
        tests.first?.results.count ?? bridge.studentsInClass.count
    }

    private var historyRows: [MacPhysicalHistoryRow] {
        let classCourse = selectedSchoolClass.map { Int($0.course) } ?? assignmentCourse
        let previousByStudentAndTest = Dictionary(grouping: physicalResults, by: { "\($0.studentId)|\($0.testId)" })
        let studentsById = Dictionary((tests.first?.results ?? []).map { ($0.student.id, "\($0.student.firstName) \($0.student.lastName)") }, uniquingKeysWith: { first, _ in first })
        return physicalResults
            .filter { result in
                if let historyTestFilter, result.testId != historyTestFilter { return false }
                if let historyBatteryFilter {
                    guard let assignment = assignments.first(where: { $0.id == result.assignmentId }) else { return false }
                    if assignment.batteryId != historyBatteryFilter { return false }
                }
                if !historyPeriodFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    guard let assignment = assignments.first(where: { $0.id == result.assignmentId }) else { return false }
                    if !(assignment.termLabel ?? "").localizedCaseInsensitiveContains(historyPeriodFilter) { return false }
                }
                return true
            }
            .map { result in
                let ordered = previousByStudentAndTest["\(result.studentId)|\(result.testId)", default: []]
                    .sorted { $0.observedAtEpochMs < $1.observedAtEpochMs }
                let previous = ordered.last(where: { $0.observedAtEpochMs < result.observedAtEpochMs })?.rawValue?.doubleValue
                let rawValue = result.rawValue?.doubleValue
                return MacPhysicalHistoryRow(
                    id: result.id,
                    studentId: result.studentId,
                    studentName: studentsById[result.studentId] ?? "Alumno \(result.studentId)",
                    course: assignments.first(where: { $0.id == result.assignmentId })?.course?.intValue ?? classCourse,
                    testId: result.testId,
                    testName: testName(for: result.testId),
                    rawValue: rawValue,
                    score: result.score?.doubleValue,
                    date: Date(timeIntervalSince1970: TimeInterval(result.observedAtEpochMs) / 1000),
                    evolution: rawValue.flatMap { raw in previous.map { raw - $0 } }
                )
            }
            .sorted { $0.date > $1.date }
    }

    private var historyAverageRaw: Double? {
        average(historyRows.compactMap(\.rawValue))
    }

    private var historyBestRaw: Double? {
        historyRows.compactMap(\.rawValue).max()
    }

    private var historyAverageScore: Double? {
        average(historyRows.compactMap(\.score))
    }

    private var historyAverageEvolution: Double? {
        let values = historyRows.compactMap(\.evolution)
        guard values.count >= 2 else { return nil }
        return average(values)
    }

    private var scaleTestRows: [MacPhysicalScaleTestRow] {
        guard let battery = selectedScaleBattery else { return [] }
        return battery.testIds.map { testId in
            let template = PhysicalTestTemplate.defaults.first(where: { $0.id == testId })
            let definition = definitions.first(where: { $0.id == testId })
            let direction = definition.map { $0.higherIsBetter ? PhysicalTestScaleDirection.higherIsBetter : .lowerIsBetter }
                ?? template?.direction
                ?? .higherIsBetter
            return MacPhysicalScaleTestRow(
                id: testId,
                name: definition?.name ?? template?.name ?? testId,
                measurement: template?.measurement.rawValue ?? "\(definition?.measurementKind ?? .distance)",
                unit: definition?.unit ?? template?.unit ?? "",
                direction: direction,
                status: scaleStatus(for: testId)
            )
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Condición física") {
                    ForEach(PhysicalTestsMacSection.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("EF")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector
                    .frame(width: 280)
                    .background(MacAppStyle.cardBackground)
            }
            .background(MacAppStyle.pageBackground)
        }
        .task { await reload() }
        .onChange(of: selectedClassId) { _ in Task { await reload() } }
        .onChange(of: selectedTestId) { _ in syncSelectedStudent() }
        .onAppear(perform: configureToolbar)
        .onChange(of: section) { _ in configureToolbar() }
        .onChange(of: selectedClassId) { _ in configureToolbar() }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .dashboard:
            dashboard
        case .bank:
            bank
        case .batteries:
            batteriesView
        case .assignments:
            assignmentsView
        case .capture:
            captureTable
        case .scales:
            scalesView
        case .history:
            history
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                header(title: "EF · Condición física", subtitle: "\(selectedClassName) · Baremos, marcas e históricos")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    MacMetricCard(label: "Pruebas", value: "\(tests.count)", tint: .orange, systemImage: "stopwatch.fill")
                    MacMetricCard(label: "Registros", value: "\(recordedCount)", tint: .green, systemImage: "checkmark.circle.fill")
                    MacMetricCard(label: "Alumnado", value: "\(studentCount)", tint: .blue, systemImage: "person.3.fill")
                    MacMetricCard(label: "Baterías", value: "\(batteries.count)", tint: .purple, systemImage: "rectangle.stack.fill")
                }

                MacSectionHeader(title: "Pruebas activas")
                testsTable
                    .frame(minHeight: 260)
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var bank: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            header(title: "Banco de pruebas", subtitle: "Plantillas reutilizables para crear evaluaciones físicas en la clase activa.")

            Table(PhysicalTestTemplate.defaults, selection: $selectedTemplateId) {
                TableColumn("Prueba") { template in
                    Text(template.name)
                        .font(.callout.weight(.medium))
                }
                TableColumn("Capacidad") { template in
                    Text(template.capacity.rawValue)
                }
                TableColumn("Medida") { template in
                    Text("\(template.measurement.rawValue) · \(template.unit)")
                }
                TableColumn("Intentos") { template in
                    Text("\(template.attempts)")
                }
                TableColumn("Resultado") { template in
                    Text(template.resultMode.rawValue)
                }
            }

            HStack {
                Text(selectedTemplate.protocolText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addSelectedTemplateToBattery()
                } label: {
                    Label("Añadir a batería", systemImage: "plus.circle.fill")
                }
                .disabled(selectedClassId == nil)
            }
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var batteriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                header(title: "Baterías", subtitle: "Agrupa pruebas, prepara columnas de cuaderno y deja el flujo listo para captura.")

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("Nombre de batería", text: $batteryName)
                        DatePicker("Fecha", selection: $batteryDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plantillas rápidas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                            ForEach(PhysicalBatteryQuickTemplate.defaults(for: PhysicalTestTemplate.defaults)) { quickTemplate in
                                Button(quickTemplate.title) {
                                    batteryName = quickTemplate.title
                                    batteryTemplateIds = quickTemplate.templateIds
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pruebas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                            ForEach(PhysicalTestTemplate.defaults) { template in
                                Toggle(template.name, isOn: Binding(
                                    get: { batteryTemplateIds.contains(template.id) },
                                    set: { enabled in
                                        if enabled {
                                            batteryTemplateIds.insert(template.id)
                                        } else {
                                            batteryTemplateIds.remove(template.id)
                                        }
                                    }
                                ))
                            }
                        }
                    }

                    DisclosureGroup("Opciones avanzadas") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Columnas", selection: $batteryColumnMode) {
                                ForEach(MacPhysicalNotebookColumnMode.allCases) { mode in
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

                    HStack {
                        Spacer()
                        Button {
                            createBattery()
                        } label: {
                            Label("Crear batería", systemImage: "plus.rectangle.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedClassId == nil || batteryTemplateIds.isEmpty || batteryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

                MacSectionHeader(title: "Baterías creadas")
                if batteries.isEmpty {
                    MacPhysicalEmptyState(title: "Sin baterías", systemImage: "rectangle.stack.badge.plus", subtitle: "Crea una batería para preparar pruebas y columnas de cuaderno.")
                        .frame(minHeight: 220)
                } else {
                    Table(batteries) {
                        TableColumn("Batería") { battery in
                            Text(battery.name)
                        }
                        TableColumn("Fecha") { battery in
                            Text(Date(timeIntervalSince1970: TimeInterval(battery.trace.createdAt.toEpochMilliseconds()) / 1000), style: .date)
                        }
                        TableColumn("Pruebas") { battery in
                            Text("\(battery.testIds.count)")
                        }
                        TableColumn("Cuaderno") { battery in
                            Text(battery.description.isEmpty ? "Preparada" : battery.description)
                        }
                    }
                    .frame(minHeight: 260)
                }

                Text("Las columnas se crean desde Asignaciones, cuando ya hay clase, curso, edad y fecha.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var assignmentsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                header(title: "Asignaciones", subtitle: "Vincula batería, clase, curso, edad, trimestre y columnas de cuaderno.")

                HStack(alignment: .top, spacing: MacAppStyle.sectionSpacing) {
                    assignmentForm
                        .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)

                    VStack(alignment: .leading, spacing: 12) {
                        MacSectionHeader(title: "Asignaciones creadas")
                        if assignments.isEmpty {
                            MacPhysicalEmptyState(
                                title: "Sin asignaciones",
                                systemImage: "link.circle",
                                subtitle: "Selecciona una batería, clase destino y evaluación para crear columnas conectadas con el cuaderno."
                            )
                            .frame(minHeight: 300)
                        } else {
                            assignmentsTable
                                .frame(minHeight: 360)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var assignmentForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            MacSectionHeader(title: "Nueva asignación")

            VStack(alignment: .leading, spacing: 8) {
                Text("Evaluación / trimestre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("1ª evaluación", text: $assignmentTermLabel)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Curso destino")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Clase destino", selection: Binding<Int64?>(
                    get: { selectedClassId },
                    set: { newValue in
                        selectedClassId = newValue
                        syncAssignmentCourseFromClass()
                        Task { await refreshAssignmentNotebookTabs() }
                    }
                )) {
                    Text("Selecciona clase").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(classPickerLabel(for: schoolClass)).tag(Optional(schoolClass.id))
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pestaña del cuaderno")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if assignmentNotebookTabs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Esta clase todavía no tiene pestañas de cuaderno disponibles para ubicar las columnas.")
                            .font(.caption)
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
                        set: { selectedAssignmentNotebookTabId = $0 }
                    )) {
                        ForEach(assignmentNotebookTabs, id: \.id) { tab in
                            Text(tab.title).tag(Optional(tab.id))
                        }
                    }
                    .labelsHidden()
                    Text("Las categorías y columnas de marca/nota se crearán dentro de esta pestaña.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("Nueva pestaña", text: $newAssignmentNotebookTabName)
                    Button {
                        createAssignmentNotebookTab()
                    } label: {
                        Label("Crear pestaña", systemImage: "plus")
                    }
                    .disabled(selectedClassId == nil || trimmedOrNil(newAssignmentNotebookTabName) == nil)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Edad")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Stepper("Desde \(assignmentAgeFrom)", value: $assignmentAgeFrom, in: 3...20)
                    Stepper("Hasta \(assignmentAgeTo)", value: $assignmentAgeTo, in: assignmentAgeFrom...20)
                }
            }

            DatePicker("Fecha", selection: $batteryDate, displayedComponents: .date)

            Picker("Columnas", selection: $batteryColumnMode) {
                ForEach(MacPhysicalNotebookColumnMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Batería", selection: Binding<String?>(
                get: { selectedBatteryId ?? batteries.first?.id },
                set: { selectedBatteryId = $0 }
            )) {
                ForEach(batteries, id: \.id) { battery in
                    Text(battery.name).tag(Optional(battery.id))
                }
            }
            .disabled(batteries.isEmpty)

            Button {
                Task { await createAssignment() }
            } label: {
                Label("Crear asignación y columnas", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedClassId == nil || batteries.isEmpty || selectedAssignmentNotebookTabId == nil)
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var assignmentsTable: some View {
        Table(assignments) {
            TableColumn("Clase") { assignment in Text(className(for: assignment.classId)) }
            TableColumn("Curso") { assignment in Text("\(assignment.course?.intValue ?? 0)º") }
            TableColumn("Pestaña") { assignment in Text(notebookTabLabel(for: assignment)) }
            TableColumn("Edad") { assignment in Text("\(assignment.ageFrom?.intValue ?? 0)-\(assignment.ageTo?.intValue ?? 0)") }
            TableColumn("Trimestre") { assignment in Text(assignment.termLabel ?? "Evaluación física") }
            TableColumn("Fecha") { assignment in Text(Date(timeIntervalSince1970: TimeInterval(assignment.dateEpochMs) / 1000), style: .date) }
            TableColumn("Columnas") { assignment in Text(columnModeLabel(for: assignment)) }
            TableColumn("Estado") { assignment in
                let status = assignmentStatus(for: assignment)
                MacStatusPill(label: status.rawValue, isActive: status != .noColumns, tint: status.tint)
            }
        }
    }

    private var captureTable: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            header(title: "Captura de marcas", subtitle: "Registra intentos en tabla y conserva el flujo de nota baremada para el cuaderno.")

            Picker("Prueba", selection: $selectedTestId) {
                ForEach(tests, id: \.evaluation.id) { test in
                    Text(test.evaluation.name).tag(Optional(test.evaluation.id))
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            .disabled(tests.isEmpty)

            Table(captureRows, selection: $selectedStudentId) {
                TableColumn("Alumno") { row in
                    Text(row.studentName)
                        .font(.callout.weight(.medium))
                }
                TableColumn("Intento 1") { row in
                    TextField("-", text: attemptBinding(studentId: row.id, index: 0))
                        .monospacedDigit()
                        .textFieldStyle(.roundedBorder)
                }
                TableColumn("Intento 2") { row in
                    TextField("-", text: attemptBinding(studentId: row.id, index: 1))
                        .monospacedDigit()
                        .textFieldStyle(.roundedBorder)
                }
                TableColumn("Intento 3") { row in
                    TextField("-", text: attemptBinding(studentId: row.id, index: 2))
                        .monospacedDigit()
                        .textFieldStyle(.roundedBorder)
                }
                TableColumn("Resultado") { row in
                    Text(row.result)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
                TableColumn("Nota") { row in
                    Text(row.score)
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                }
                TableColumn("Estado") { row in
                    Text(row.status)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await saveSelectedCaptureRow() }
                } label: {
                    Label("Guardar cambios", systemImage: "checkmark.circle")
                }
                .disabled(selectedStudentId == nil)

                Button {
                    Task { await saveAllCaptureRows() }
                } label: {
                    Label("Guardar todo", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTest == nil)
            }
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var scalesView: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            header(title: "Baremos", subtitle: "Define baremos por clase, batería asignada y prueba concreta.")

            scaleContextSelector

            if assignments.isEmpty || selectedScaleBattery == nil {
                MacPhysicalEmptyState(
                    title: "Sin baterías asignadas",
                    systemImage: "slider.horizontal.3",
                    subtitle: "Primero crea una batería y asígnala a un curso desde Asignaciones."
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    scaleTestsPanel
                        .frame(width: 270)
                        .frame(maxHeight: .infinity)

                    Divider()

                    PhysicalTestScaleEditor(
                        scale: $scale,
                        context: scaleEditorContext,
                        canSave: canSaveScale,
                        onSave: { draft in
                            Task { await saveScale(draft) }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MacAppStyle.pageBackground)
                }
                .background(MacAppStyle.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var scaleContextSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Selecciona batería")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Curso / clase", selection: Binding<Int64?>(
                        get: { selectedClassId },
                        set: { newValue in
                            selectedClassId = newValue
                            selectedScaleAssignmentId = nil
                            selectedScaleTestId = nil
                            Task { await reload() }
                        }
                    )) {
                        Text("Selecciona clase").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(classPickerLabel(for: schoolClass)).tag(Optional(schoolClass.id))
                        }
                    }
                    .frame(minWidth: 260)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Batería asignada")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Batería asignada", selection: Binding<String?>(
                        get: { selectedScaleAssignment?.id },
                        set: { newValue in
                            selectedScaleAssignmentId = newValue
                            selectedScaleTestId = nil
                            Task {
                                await loadScalesForSelectedBattery()
                                syncScaleDraftFromSelection()
                            }
                        }
                    )) {
                        ForEach(assignments, id: \.id) { assignment in
                            Text(scaleAssignmentLabel(for: assignment)).tag(Optional(assignment.id))
                        }
                    }
                    .frame(minWidth: 320)
                    .disabled(assignments.isEmpty)
                }

                Spacer()
            }

            if let assignment = selectedScaleAssignment, let battery = selectedScaleBattery {
                HStack(spacing: 10) {
                    MacStatusPill(label: className(for: assignment.classId), isActive: true, tint: MacAppStyle.infoTint)
                    MacStatusPill(label: "\(assignment.course?.intValue ?? 0)º", isActive: true, tint: MacAppStyle.infoTint)
                    MacStatusPill(label: "Edad \(assignment.ageFrom?.intValue ?? 0)-\(assignment.ageTo?.intValue ?? 0)", isActive: true, tint: MacAppStyle.infoTint)
                    MacStatusPill(label: assignment.termLabel ?? "Evaluación física", isActive: true, tint: MacAppStyle.infoTint)
                    MacStatusPill(label: Date(timeIntervalSince1970: TimeInterval(assignment.dateEpochMs) / 1000).formatted(date: .abbreviated, time: .omitted), isActive: true, tint: MacAppStyle.infoTint)
                    MacStatusPill(label: "\(battery.testIds.count) pruebas", isActive: true, tint: MacAppStyle.successTint)
                }
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var scaleTestsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("2. Elige prueba")
                    .font(MacAppStyle.sectionTitle)
                Text("Pruebas incluidas en la batería asignada.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scaleTestRows.isEmpty {
                MacPhysicalEmptyState(title: "Batería sin pruebas", systemImage: "list.bullet.rectangle", subtitle: "Añade pruebas a la batería antes de definir baremos.")
            } else {
                List(selection: $selectedScaleTestId) {
                    ForEach(scaleTestRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name)
                                .font(.callout.weight(.semibold))
                            Text("\(row.measurement) · \(row.unit) · \(row.direction.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MacStatusPill(label: row.status.rawValue, isActive: row.status != .missing, tint: row.status.tint)
                        }
                        .padding(.vertical, 4)
                        .tag(Optional(row.id))
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedScaleTestId) { _ in syncScaleDraftFromSelection() }
            }

            Spacer(minLength: 0)
        }
        .padding(MacAppStyle.innerPadding)
    }

    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                header(title: "Histórico", subtitle: "Análisis de resultados físicos persistidos por clase, batería y prueba.")

                historyFilters

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    MacMetricCard(label: "Registros", value: "\(historyRows.count)", tint: .orange, systemImage: "tray.full")
                    MacMetricCard(label: "Media grupo", value: historyAverageRaw.map(PhysicalTestsFormatting.decimal) ?? "-", tint: .blue, systemImage: "chart.xyaxis.line")
                    MacMetricCard(label: "Mejor marca", value: historyBestRaw.map(PhysicalTestsFormatting.decimal) ?? "-", tint: .green, systemImage: "trophy")
                    MacMetricCard(label: "Nota media", value: historyAverageScore.map(PhysicalTestsFormatting.decimal) ?? "-", tint: .purple, systemImage: "number.circle")
                    MacMetricCard(label: "Mejora media", value: historyAverageEvolution.map(PhysicalTestsFormatting.decimal) ?? "-", tint: .teal, systemImage: "arrow.up.right")
                }

                if historyRows.isEmpty {
                    MacPhysicalEmptyState(
                        title: "Sin histórico físico",
                        systemImage: "chart.line.uptrend.xyaxis",
                        subtitle: "Captura marcas desde una asignación con columnas creadas para ver evolución, distribución y notas baremadas."
                    )
                    .frame(minHeight: 360)
                } else {
                    historyCharts
                    historyDetailTable
                        .frame(minHeight: 360)
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var historyFilters: some View {
        HStack(spacing: 12) {
            Picker("Curso / clase", selection: Binding<Int64?>(
                get: { selectedClassId },
                set: { selectedClassId = $0 }
            )) {
                Text("Todas las clases").tag(Optional<Int64>.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(classPickerLabel(for: schoolClass)).tag(Optional(schoolClass.id))
                }
            }

            Picker("Batería", selection: Binding<String?>(
                get: { historyBatteryFilter },
                set: { historyBatteryFilter = $0 }
            )) {
                Text("Todas las baterías").tag(Optional<String>.none)
                ForEach(batteries, id: \.id) { battery in
                    Text(battery.name).tag(Optional(battery.id))
                }
            }

            Picker("Prueba", selection: Binding<String?>(
                get: { historyTestFilter },
                set: { historyTestFilter = $0 }
            )) {
                Text("Todas las pruebas").tag(Optional<String>.none)
                ForEach(definitions, id: \.id) { definition in
                    Text(definition.name).tag(Optional(definition.id))
                }
            }

            TextField("Periodo", text: $historyPeriodFilter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
        }
        .controlSize(.regular)
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var historyCharts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            MacChartCard(title: "Evolución temporal") {
                Chart(historyTimePoints) { point in
                    LineMark(
                        x: .value("Fecha", point.date),
                        y: .value("Marca media", point.value),
                        series: .value("Prueba", point.testName)
                    )
                    PointMark(
                        x: .value("Fecha", point.date),
                        y: .value("Marca media", point.value)
                    )
                }
                .frame(height: 220)
            }

            MacChartCard(title: "Distribución de marcas") {
                Chart(rawBuckets) { bucket in
                    BarMark(x: .value("Rango", bucket.label), y: .value("Registros", bucket.count))
                        .foregroundStyle(MacAppStyle.infoTint)
                }
                .frame(height: 220)
            }

            MacChartCard(title: "Distribución de notas") {
                if scoreBuckets.isEmpty {
                    MacPhysicalEmptyState(title: "Sin notas", systemImage: "number.circle", subtitle: "Cuando haya baremos aplicables, la distribución de notas aparecerá aquí.")
                } else {
                    Chart(scoreBuckets) { bucket in
                        BarMark(x: .value("Nota", bucket.label), y: .value("Registros", bucket.count))
                            .foregroundStyle(MacAppStyle.successTint)
                    }
                }
            }
            .frame(height: 280)
        }
    }

    private var historyDetailTable: some View {
        Table(historyRows) {
            TableColumn("Alumno") { row in Text(row.studentName) }
            TableColumn("Curso") { row in Text("\(row.course)º") }
            TableColumn("Prueba") { row in Text(row.testName) }
            TableColumn("Marca") { row in Text(row.rawValue.map(PhysicalTestsFormatting.decimal) ?? "-").monospacedDigit() }
            TableColumn("Nota") { row in Text(row.score.map(PhysicalTestsFormatting.decimal) ?? "-").monospacedDigit() }
            TableColumn("Fecha") { row in Text(row.date, style: .date) }
            TableColumn("Evolución") { row in
                Text(row.evolution.map { value in value > 0 ? "+\(PhysicalTestsFormatting.decimal(value))" : PhysicalTestsFormatting.decimal(value) } ?? "-")
                    .foregroundStyle((row.evolution ?? 0) >= 0 ? MacAppStyle.successTint : MacAppStyle.warningTint)
                    .monospacedDigit()
            }
        }
    }

    private var testsTable: some View {
        Table(tests, selection: $selectedTestId) {
            TableColumn("Prueba") { test in
                Text(test.evaluation.name)
                    .font(.callout.weight(.medium))
            }
            TableColumn("Tipo") { test in
                Text(test.evaluation.type)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Registros") { test in
                Text("\(test.recordedCount)/\(test.results.count)")
                    .monospacedDigit()
            }
            TableColumn("Media") { test in
                Text(PhysicalTestsFormatting.decimal(test.average))
                    .monospacedDigit()
            }
            TableColumn("Mejor") { test in
                Text(test.best.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                    .monospacedDigit()
            }
        }
    }

    private var captureRows: [MacPhysicalTestCaptureRow] {
        guard let selectedTest else { return [] }
        return selectedTest.results.map { result in
            let attempts = attemptTexts(for: result)
            let numericValue = resolvedCaptureValue(for: result)
            let value = numericValue.map { PhysicalTestsFormatting.decimal($0) } ?? "-"
            return MacPhysicalTestCaptureRow(
                id: result.student.id,
                studentName: "\(result.student.firstName) \(result.student.lastName)",
                attempt1: attempts[0],
                attempt2: attempts[1],
                attempt3: attempts[2],
                result: value,
                score: numericValue.flatMap { scale.score(for: $0) }.map { PhysicalTestsFormatting.decimal($0) } ?? "-",
                status: result.value == nil ? "Pendiente" : "Guardado"
            )
        }
    }

    private var scaleEditorContext: PhysicalTestScaleEditorContext? {
        guard let assignment = selectedScaleAssignment,
              let battery = selectedScaleBattery,
              let row = selectedScaleTestRow else { return nil }
        return PhysicalTestScaleEditorContext(
            batteryName: battery.name,
            className: "\(className(for: assignment.classId)) · \(assignment.course?.intValue ?? 0)º",
            termLabel: assignment.termLabel,
            testName: row.name,
            unit: row.unit,
            ageRange: "\(assignment.ageFrom?.intValue ?? 0)-\(assignment.ageTo?.intValue ?? 0)"
        )
    }

    private var canSaveScale: Bool {
        selectedClassId != nil
            && selectedScaleAssignment != nil
            && selectedScaleBattery != nil
            && selectedScaleTestRow != nil
            && !scale.ranges.isEmpty
            && scale.validationMessages.isEmpty
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Label("Inspector", systemImage: "sidebar.right")
                .font(.headline)

            Divider()

            if let selectedTest {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedTest.evaluation.name)
                        .font(.title3.weight(.semibold))
                    Text(selectedTest.evaluation.type)
                        .foregroundStyle(.secondary)
                    MacStatusPill(label: "\(selectedTest.recordedCount) registros", isActive: selectedTest.recordedCount > 0, tint: .orange)
                }

                Divider()

                InspectorLine(title: "Media", value: PhysicalTestsFormatting.decimal(selectedTest.average))
                InspectorLine(title: "Mejor marca", value: selectedTest.best.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                InspectorLine(title: "Alumnos", value: "\(selectedTest.results.count)")

                Button {
                    section = .capture
                } label: {
                    Label("Abrir captura", systemImage: "tablecells")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onOpenModule(.notebook, selectedClassId, selectedStudentId)
                } label: {
                    Label("Abrir cuaderno", systemImage: "book.closed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Selecciona o crea una prueba física para ver detalles.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(MacAppStyle.pagePadding)
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MacAppStyle.pageTitle)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func configureToolbar() {
        toolbarActions.configure(
            canUseClassActions: selectedClassId != nil,
            onNewBattery: {
                section = .batteries
            },
            onCapture: {
                section = .capture
            },
            onCreateColumns: {
                section = .assignments
            },
            onRefresh: {
                Task { await reload() }
            }
        )
    }

    @MainActor
    private func reload() async {
        guard let selectedClassId else {
            tests = []
            selectedTestId = nil
            selectedStudentId = nil
            assignments = []
            notebookLinks = []
            physicalResults = []
            assignmentNotebookTabs = []
            selectedAssignmentNotebookTabId = nil
            selectedScaleAssignmentId = nil
            selectedScaleTestId = nil
            physicalScalesByTestId = [:]
            configureToolbar()
            return
        }
        await refreshAssignmentNotebookTabs()
        definitions = (try? await bridge.listPhysicalDefinitions()) ?? []
        batteries = (try? await bridge.listPhysicalBatteries()) ?? []
        assignments = (try? await bridge.listPhysicalAssignmentsForClass(classId: selectedClassId)) ?? []
        syncScaleSelection()
        await loadScalesForSelectedBattery()
        notebookLinks = []
        physicalResults = []
        for assignment in assignments {
            let links = (try? await bridge.listPhysicalNotebookLinksForAssignment(assignmentId: assignment.id)) ?? []
            notebookLinks.append(contentsOf: links)
            let results = (try? await bridge.listPhysicalResultsForAssignment(assignmentId: assignment.id)) ?? []
            physicalResults.append(contentsOf: results)
        }
        if selectedBatteryId == nil || !batteries.contains(where: { $0.id == selectedBatteryId }) {
            selectedBatteryId = batteries.first?.id
        }
        syncAssignmentCourseFromClass()
        tests = (try? await bridge.loadPhysicalTests(classId: selectedClassId)) ?? []
        if selectedTestId == nil || !tests.contains(where: { $0.evaluation.id == selectedTestId }) {
            selectedTestId = tests.first?.evaluation.id
        }
        syncSelectedStudent()
        syncScaleDraftFromSelection()
        configureToolbar()
    }

    private func syncSelectedStudent() {
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

    private func addSelectedTemplateToBattery() {
        batteryTemplateIds.insert(selectedTemplate.id)
        section = .batteries
        bridge.status = "\(selectedTemplate.name) añadida al borrador de batería."
    }

    private func syncScaleSelection() {
        if selectedScaleAssignmentId == nil || !assignments.contains(where: { $0.id == selectedScaleAssignmentId }) {
            selectedScaleAssignmentId = assignments.first?.id
        }
        if selectedScaleTestId == nil || !scaleTestRows.contains(where: { $0.id == selectedScaleTestId }) {
            selectedScaleTestId = scaleTestRows.first?.id
        }
    }

    @MainActor
    private func loadScalesForSelectedBattery() async {
        guard let battery = selectedScaleBattery else {
            physicalScalesByTestId = [:]
            return
        }
        var loaded: [String: [MiGestorKit.PhysicalTestScale]] = [:]
        for testId in battery.testIds {
            loaded[testId] = (try? await bridge.listPhysicalScalesForTest(testId: testId)) ?? []
        }
        physicalScalesByTestId = loaded
    }

    private func syncScaleDraftFromSelection() {
        syncScaleSelection()
        guard let row = selectedScaleTestRow,
              let assignment = selectedScaleAssignment,
              let battery = selectedScaleBattery else { return }
        if let existing = matchingScale(for: row.id, assignment: assignment, battery: battery) {
            scale = scaleDraft(from: existing)
            return
        }
        scale = PhysicalTestScaleDraft(
            persistedScaleId: nil,
            name: "Baremo \(row.name)",
            testId: row.id,
            course: assignment.course?.intValue,
            ageFrom: assignment.ageFrom?.intValue,
            ageTo: assignment.ageTo?.intValue,
            sex: "",
            batteryId: battery.id,
            direction: row.direction,
            ranges: defaultScaleRanges(for: row.direction)
        )
    }

    private func matchingScale(
        for testId: String,
        assignment: MiGestorKit.PhysicalTestAssignment,
        battery: MiGestorKit.PhysicalTestBattery
    ) -> MiGestorKit.PhysicalTestScale? {
        physicalScalesByTestId[testId, default: []].first { persisted in
            persisted.batteryId == battery.id
                && persisted.course?.intValue == assignment.course?.intValue
                && persisted.ageFrom?.intValue == assignment.ageFrom?.intValue
                && persisted.ageTo?.intValue == assignment.ageTo?.intValue
        }
    }

    private func scaleStatus(for testId: String) -> MacPhysicalScaleStatus {
        guard let assignment = selectedScaleAssignment, let battery = selectedScaleBattery else { return .missing }
        guard let persisted = matchingScale(for: testId, assignment: assignment, battery: battery) else { return .missing }
        return scaleDraft(from: persisted).validationMessages.isEmpty ? .created : .needsReview
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
            ranges: persisted.ranges.sorted { $0.sortOrder < $1.sortOrder }.map { range in
                PhysicalTestScaleRange(
                    minValue: range.minValue?.doubleValue,
                    maxValue: range.maxValue?.doubleValue,
                    score: range.score,
                    label: range.label ?? ""
                )
            }
        )
    }

    private func defaultScaleRanges(for direction: PhysicalTestScaleDirection) -> [PhysicalTestScaleRange] {
        switch direction {
        case .higherIsBetter:
            return PhysicalTestScaleDraft.defaultJump.ranges
        case .lowerIsBetter:
            return PhysicalTestScaleDraft.defaultSpeed.ranges
        }
    }

    @MainActor
    private func saveScale(_ draft: PhysicalTestScaleDraft) async {
        guard let assignment = selectedScaleAssignment,
              let battery = selectedScaleBattery,
              let row = selectedScaleTestRow else {
            bridge.status = "Selecciona clase, batería y prueba antes de guardar el baremo."
            return
        }
        guard draft.validationMessages.isEmpty, !draft.ranges.isEmpty else {
            bridge.status = "Revisa los rangos antes de guardar el baremo."
            return
        }
        let scaleId = draft.persistedScaleId ?? "mac_pe_scale_\(assignment.id)_\(row.id)"
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
            testId: row.id,
            name: trimmedOrNil(draft.name) ?? "Baremo \(row.name)",
            course: assignment.course,
            ageFrom: assignment.ageFrom,
            ageTo: assignment.ageTo,
            sex: trimmedOrNil(draft.sex),
            batteryId: battery.id,
            direction: draft.direction == .lowerIsBetter ? .lowerIsBetter : .higherIsBetter,
            ranges: ranges,
            trace: auditTrace()
        )
        do {
            try await bridge.savePhysicalScale(persisted)
            physicalScalesByTestId[row.id] = (try? await bridge.listPhysicalScalesForTest(testId: row.id)) ?? [persisted]
            scale = scaleDraft(from: persisted)
            bridge.status = "Baremo guardado para \(row.name)."
        } catch {
            bridge.status = "No se pudo guardar el baremo: \(error.localizedDescription)"
        }
    }

    private func createBattery(createTests: Bool = true) {
        Task {
            if createTests {
                for template in PhysicalTestTemplate.defaults where batteryTemplateIds.contains(template.id) {
                    try? await bridge.savePhysicalDefinition(physicalDefinition(from: template))
                    await createTest(from: template)
                }
            }
            do {
                let battery = MiGestorKit.PhysicalTestBattery(
                    id: "mac_pe_battery_\(Int64(Date().timeIntervalSince1970 * 1000))",
                    name: batteryName,
                    description: "Creada desde macOS",
                    defaultCourse: selectedSchoolClass.map { KotlinInt(value: $0.course) },
                    defaultAgeFrom: KotlinInt(value: Int32(assignmentAgeFrom)),
                    defaultAgeTo: KotlinInt(value: Int32(assignmentAgeTo)),
                    testIds: Array(batteryTemplateIds),
                    trace: auditTrace()
                )
                try await bridge.savePhysicalBattery(battery)
                selectedBatteryId = battery.id
                await reload()
            } catch {
                bridge.status = "No se pudo guardar la batería física: \(error.localizedDescription)"
            }
            section = .assignments
            bridge.status = "Batería creada. Asígnala a una clase para crear columnas."
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
        } else {
            let preferred = assignmentNotebookTabs.first { $0.title.localizedCaseInsensitiveContains("condición") || $0.title.localizedCaseInsensitiveContains("fis") }
            selectedAssignmentNotebookTabId = preferred?.id ?? assignmentNotebookTabs.first?.id
            bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
        }
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

    @MainActor
    private func createAssignment() async {
        guard let selectedClassId,
              let battery = selectedBatteryId.flatMap({ id in batteries.first(where: { $0.id == id }) }) ?? batteries.first else {
            bridge.status = "Crea una batería y selecciona una clase antes de asignar."
            return
        }
        guard let selectedAssignmentNotebookTabId else {
            bridge.status = "Selecciona o crea una pestaña del cuaderno para ubicar las columnas."
            return
        }
        bridge.selectClass(id: selectedClassId)
        bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
        let assignment = MiGestorKit.PhysicalTestAssignment(
            id: "mac_pe_assignment_\(Int64(Date().timeIntervalSince1970 * 1000))",
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
        guard let selectedAssignmentNotebookTabId else {
            throw NSError(domain: "MacPhysicalTestsView", code: 422, userInfo: [NSLocalizedDescriptionKey: "Selecciona una pestaña del cuaderno para crear las columnas."])
        }
        bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
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
                    countsTowardAverage: true,
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
        let tabName = selectedAssignmentNotebookTab?.title ?? "la pestaña seleccionada"
        bridge.status = "Columnas de condición física preparadas en \(tabName)."
    }

    private func attemptBinding(studentId: Int64, index: Int) -> Binding<String> {
        Binding(
            get: {
                let attempts = captureDrafts[studentId] ?? defaultAttemptTexts(studentId: studentId)
                return attempts.indices.contains(index) ? attempts[index] : ""
            },
            set: { newValue in
                var attempts = captureDrafts[studentId] ?? defaultAttemptTexts(studentId: studentId)
                while attempts.count < 3 {
                    attempts.append("")
                }
                attempts[index] = newValue
                captureDrafts[studentId] = attempts
            }
        )
    }

    private func attemptTexts(for result: KmpBridge.PhysicalTestSnapshot.StudentResult) -> [String] {
        captureDrafts[result.student.id] ?? defaultAttemptTexts(studentId: result.student.id)
    }

    private func defaultAttemptTexts(studentId: Int64) -> [String] {
        guard let result = selectedTest?.results.first(where: { $0.student.id == studentId }),
              let value = result.value else {
            return ["", "", ""]
        }
        return [PhysicalTestsFormatting.decimal(value), "", ""]
    }

    private func resolvedCaptureValue(for result: KmpBridge.PhysicalTestSnapshot.StudentResult) -> Double? {
        let values = attemptTexts(for: result).compactMap { text in
            Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return resolvedPhysicalResult(
            attempts: values,
            direction: scale.direction,
            resultMode: .best
        ) ?? result.value
    }

    @MainActor
    private func saveSelectedCaptureRow() async {
        guard let studentId = selectedStudentId,
              let result = selectedTest?.results.first(where: { $0.student.id == studentId }) else { return }
        await saveCaptureResult(result)
    }

    @MainActor
    private func saveAllCaptureRows() async {
        guard let selectedTest else { return }
        for result in selectedTest.results {
            await saveCaptureResult(result)
        }
        await reload()
    }

    @MainActor
    private func saveCaptureResult(_ result: KmpBridge.PhysicalTestSnapshot.StudentResult) async {
        guard let selectedTest, let selectedClassId else { return }
        do {
            try await bridge.saveGrade(
                studentId: result.student.id,
                evaluationId: selectedTest.evaluation.id,
                value: resolvedCaptureValue(for: result),
                classId: selectedClassId
            )
            bridge.status = "Marca física guardada."
        } catch {
            bridge.status = "No se pudo guardar la marca: \(error.localizedDescription)"
        }
    }

    private var historyTimePoints: [MacPhysicalTimePoint] {
        let grouped = Dictionary(grouping: historyRows.filter { $0.rawValue != nil }) { row in
            "\(Calendar.current.startOfDay(for: row.date).timeIntervalSince1970)|\(row.testId)"
        }
        return grouped.compactMap { _, rows in
            guard let first = rows.first, let value = average(rows.compactMap(\.rawValue)) else { return nil }
            return MacPhysicalTimePoint(date: Calendar.current.startOfDay(for: first.date), testName: first.testName, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    private var rawBuckets: [MacPhysicalBucket] {
        buckets(for: historyRows.compactMap(\.rawValue), prefix: "")
    }

    private var scoreBuckets: [MacPhysicalBucket] {
        buckets(for: historyRows.compactMap(\.score), prefix: "")
    }

    private func buckets(for values: [Double], prefix: String) -> [MacPhysicalBucket] {
        guard let lowerBound = values.min(), let upperBound = values.max(), lowerBound != upperBound else {
            guard let value = values.first else { return [] }
            let label = "\(prefix)\(PhysicalTestsFormatting.decimal(value))"
            return [MacPhysicalBucket(id: label, label: label, count: values.count)]
        }
        let bucketCount = Swift.min(6, Swift.max(3, values.count))
        let step = Swift.max((upperBound - lowerBound) / Double(bucketCount), 0.1)
        return (0..<bucketCount).map { index in
            let lower = lowerBound + Double(index) * step
            let upper = index == bucketCount - 1 ? upperBound : lower + step
            let count = values.filter { value in
                index == bucketCount - 1 ? value >= lower && value <= upper : value >= lower && value < upper
            }.count
            let label = "\(PhysicalTestsFormatting.decimal(lower))-\(PhysicalTestsFormatting.decimal(upper))"
            return MacPhysicalBucket(id: "\(index)-\(label)", label: label, count: count)
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func classPickerLabel(for schoolClass: SchoolClass) -> String {
        let count = tests.first?.results.count
        let suffix = count.map { " · \($0) alumnos" } ?? ""
        return "\(schoolClass.name) · \(schoolClass.course)º\(suffix)"
    }

    private func className(for classId: Int64) -> String {
        bridge.classes.first(where: { $0.id == classId })?.name ?? "Clase \(classId)"
    }

    private func scaleAssignmentLabel(for assignment: MiGestorKit.PhysicalTestAssignment) -> String {
        let batteryName = batteries.first(where: { $0.id == assignment.batteryId })?.name ?? "Batería"
        let term = assignment.termLabel ?? "Evaluación física"
        let date = Date(timeIntervalSince1970: TimeInterval(assignment.dateEpochMs) / 1000).formatted(date: .abbreviated, time: .omitted)
        return "\(batteryName) · \(term) · \(date)"
    }

    private func columnModeLabel(for assignment: MiGestorKit.PhysicalTestAssignment) -> String {
        switch (assignment.rawColumnMode, assignment.scoreColumnMode) {
        case (true, true): return MacPhysicalNotebookColumnMode.rawAndScore.rawValue
        case (true, false): return MacPhysicalNotebookColumnMode.rawOnly.rawValue
        case (false, true): return MacPhysicalNotebookColumnMode.scoreOnly.rawValue
        default: return "Sin columnas"
        }
    }

    private func notebookTabLabel(for assignment: MiGestorKit.PhysicalTestAssignment) -> String {
        let assignmentLinks = notebookLinks.filter { $0.assignmentId == assignment.id }
        let columnIds = Set(assignmentLinks.flatMap { link in [link.rawColumnId, link.scoreColumnId].compactMap(\.self) })
        guard !columnIds.isEmpty else { return selectedAssignmentNotebookTab?.title ?? "-" }
        guard let data = bridge.notebookState as? NotebookUiStateData else { return "-" }
        let tabsById = Dictionary(data.sheet.tabs.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let tabNames = data.sheet.columns
            .filter { columnIds.contains($0.id) }
            .flatMap(\.tabIds)
            .compactMap { tabsById[$0] }
        let uniqueNames = Array(Set(tabNames)).sorted()
        return uniqueNames.isEmpty ? "-" : uniqueNames.joined(separator: ", ")
    }

    private func assignmentStatus(for assignment: MiGestorKit.PhysicalTestAssignment) -> MacPhysicalAssignmentStatus {
        let links = notebookLinks.filter { $0.assignmentId == assignment.id }
        let hasColumns = links.contains { $0.rawColumnId != nil || $0.scoreColumnId != nil }
        guard hasColumns else { return .noColumns }
        let hasResults = physicalResults.contains { $0.assignmentId == assignment.id }
        return hasResults ? .columnsCreated : .pendingCapture
    }

    private func testName(for testId: String) -> String {
        definitions.first(where: { $0.id == testId })?.name
            ?? PhysicalTestTemplate.defaults.first(where: { $0.id == testId })?.name
            ?? testId
    }

    private func syncAssignmentCourseFromClass() {
        guard let selectedSchoolClass else { return }
        assignmentCourse = Int(selectedSchoolClass.course)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private struct MacChartCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            content
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct InspectorLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct MacPhysicalEmptyState: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MacAppStyle.pagePadding)
    }
}
