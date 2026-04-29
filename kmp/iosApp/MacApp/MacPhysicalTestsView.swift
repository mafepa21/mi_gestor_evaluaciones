import SwiftUI
import MiGestorKit

extension KmpBridge.PhysicalTestSnapshot: Identifiable {
    var id: Int64 { evaluation.id }
}

private enum PhysicalTestsMacSection: String, CaseIterable, Identifiable {
    case dashboard
    case bank
    case batteries
    case capture
    case scales
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Resumen"
        case .bank: return "Banco de pruebas"
        case .batteries: return "Baterías"
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
    let id = UUID()
    var name: String
    var date: Date
    var templateIds: Set<String>
    var columnMode: MacPhysicalNotebookColumnMode
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
    @State private var batteries: [MacPhysicalTestBattery] = []
    @State private var batteryName = "Condición física inicial"
    @State private var batteryDate = Date()
    @State private var batteryTemplateIds = Set(PhysicalTestTemplate.defaults.prefix(4).map(\.id))
    @State private var batteryColumnMode: MacPhysicalNotebookColumnMode = .rawAndScore
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

    private var recordedCount: Int {
        tests.reduce(0) { $0 + $1.recordedCount }
    }

    private var studentCount: Int {
        selectedTest?.results.count ?? 0
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
                            Text(battery.date, style: .date)
                        }
                        TableColumn("Pruebas") { battery in
                            Text("\(battery.templateIds.count)")
                        }
                        TableColumn("Cuaderno") { battery in
                            Text(battery.columnMode.rawValue)
                        }
                    }
                    .frame(minHeight: 260)
                }

                Text("TODO(kmp-physical-tests): persistir baterías macOS como sesiones de medición compartidas con iPad.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(MacAppStyle.pagePadding)
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

            Text("TODO(kmp-physical-tests): persistir intentos individuales, rawText, resultado final, baremo aplicado y score como PhysicalTestResult.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var scalesView: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            header(title: "Baremos", subtitle: "Selección local de evaluación física, preparada para migrar a KMP/SQLDelight.")

            PhysicalTestScaleEditor(scale: $scale)
                .frame(maxWidth: 720, maxHeight: .infinity, alignment: .leading)
                .background(MacAppStyle.pageBackground)
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            header(title: "Histórico", subtitle: "Resumen de completado, media y mejor marca por prueba.")

            testsTable

            Text("TODO(kmp-physical-tests): calcular evolución por alumno con observedAtEpochMs, rawValue, score y batería.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(MacAppStyle.pagePadding)
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
                createBattery(createTests: false)
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
            configureToolbar()
            return
        }
        tests = (try? await bridge.loadPhysicalTests(classId: selectedClassId)) ?? []
        if selectedTestId == nil || !tests.contains(where: { $0.evaluation.id == selectedTestId }) {
            selectedTestId = tests.first?.evaluation.id
        }
        syncSelectedStudent()
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

    private func createBattery(createTests: Bool = true) {
        let battery = MacPhysicalTestBattery(
            name: batteryName,
            date: batteryDate,
            templateIds: batteryTemplateIds,
            columnMode: batteryColumnMode
        )
        batteries.insert(battery, at: 0)
        Task {
            if createTests {
                for template in PhysicalTestTemplate.defaults where battery.templateIds.contains(template.id) {
                    await createTest(from: template)
                }
            }
            createNotebookColumns(for: battery)
        }
    }

    private func createNotebookColumns(for battery: MacPhysicalTestBattery) {
        guard let selectedClassId else { return }
        bridge.selectClass(id: selectedClassId)
        let selectedTemplates = PhysicalTestTemplate.defaults.filter { battery.templateIds.contains($0.id) }
        let categoryId = "mac_pe_battery_\(Int64(Date().timeIntervalSince1970 * 1000))"
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
                    countsTowardAverage: false
                )
            }
            // TODO(kmp-physical-tests): vincular testId -> rawColumnId / scoreColumnId cuando addColumn o KMP devuelvan IDs persistentes.
        }
        bridge.status = "Columnas de condición física preparadas en el cuaderno."
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
        return values.max() ?? result.value
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
