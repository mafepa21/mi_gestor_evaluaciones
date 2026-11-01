import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

/// Asistente «Nueva prueba»: Test → Baremo → Guardar y añadir al cuaderno.
///
/// Maqueta aprobada: `docs/maquetas/pruebas_fisicas_asistente_2026-10-26.html`.
/// No observa `KmpBridge`: solo lee grupos al abrir y llama a acciones.
struct PhysicalTestSetupWizardSheet: View {
    let bridge: KmpBridge
    let initialClassId: Int64?
    var onSaved: (PhysicalTestSetupOutcome) -> Void = { _ in }
    var onOpenNotebook: ((Int64) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var path: [Step] = []

    // Paso 1 · Test
    @State private var definitions: [MiGestorKit.PhysicalTestDefinition] = []
    @State private var existingDefinitionId: String?
    @State private var name = ""
    @State private var unit: UnitOption = .centimeters
    @State private var higherIsBetter = true
    @State private var capacity: PhysicalTestCapacity = .strength
    @State private var attempts = 1
    @State private var resultMode: PhysicalTestResultMode = .best

    // Paso 2 · Baremo
    @State private var scalePhase: ScalePhase = .empty
    @State private var existingScaleCount = 0
    @State private var isPickingFile = false
    @State private var manualRows: [ManualRow] = [ManualRow(), ManualRow()]
    @State private var courseFilter: Int?
    @State private var sexFilter: String?
    @State private var templateURL: URL?

    // Paso 3 · Guardar
    @State private var classes: [SchoolClass] = []
    @State private var classId: Int64?
    @State private var tabs: [NotebookTab] = []
    @State private var tabSelection = WizardTab.newTabTitle
    @State private var date = Date()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var outcome: PhysicalTestSetupOutcome?

    @State private var showingDiscard = false

    private enum Step: Hashable { case scale, destination }

    private enum ScalePhase: Equatable {
        case empty
        case loading(String)
        case loaded(PhysicalScaleSpreadsheetImport.Result, fileName: String)
        case unreadable(String)
        case manual
        case skipped
    }

    private enum WizardTab {
        static let newTabTitle = "Condición física"
    }

    private struct ManualRow: Identifiable, Equatable {
        let id = UUID()
        var from = ""
        var to = ""
        var score = ""
    }

    enum UnitOption: String, CaseIterable, Identifiable {
        case seconds = "segundos"
        case meters = "metros"
        case centimeters = "centímetros"
        case repetitions = "repeticiones"
        case level = "nivel"

        var id: String { rawValue }

        var measurement: PhysicalTestMeasurement {
            switch self {
            case .seconds: return .time
            case .meters, .centimeters: return .distance
            case .repetitions: return .repetitions
            case .level: return .level
            }
        }

        var symbol: String {
            switch self {
            case .seconds: return "s"
            case .meters: return "m"
            case .centimeters: return "cm"
            case .repetitions: return "rep"
            case .level: return "nivel"
            }
        }

        static func matching(unit: String, measurement: PhysicalTestMeasurement) -> UnitOption {
            allCases.first { $0.symbol == unit && $0.measurement == measurement }
                ?? allCases.first { $0.measurement == measurement }
                ?? .centimeters
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            testStep
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .scale: scaleStep
                    case .destination: destinationStep
                    }
                }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
        .confirmationDialog("¿Descartar la prueba nueva?", isPresented: $showingDiscard, titleVisibility: .visible) {
            Button("Descartar cambios", role: .destructive) { dismiss() }
        } message: {
            Text("Se perderá lo que has escrito.")
        }
        .task { await loadInitialData() }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.xlsx, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handlePickedFile(result)
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 600, idealHeight: 640)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Paso 1 · Test

    private var testStep: some View {
        Form {
            Section {
                NavigationLink {
                    savedTestPicker
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Elegir una prueba guardada")
                            Text(savedTestsSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(definitions.isEmpty)
            } header: {
                stepHeader(1)
            }

            if let existingDefinitionId, let definition = definitions.first(where: { $0.id == existingDefinitionId }) {
                Section("Prueba elegida") {
                    LabeledContent("Nombre", value: definition.name)
                    LabeledContent("Unidad", value: definition.unit)
                    LabeledContent("Mejor resultado", value: definition.higherIsBetter ? "Más alto" : "Más bajo")
                    Button("Crear una nueva en su lugar", role: .destructive) {
                        clearExistingSelection()
                    }
                }
            } else {
                Section("O crea una nueva") {
                    TextField("Nombre", text: $name, prompt: Text("Ej. Salto horizontal"))
                    Picker("Unidad", selection: $unit) {
                        ForEach(UnitOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    Picker("Mejor resultado", selection: $higherIsBetter) {
                        Text("Más alto").tag(true)
                        Text("Más bajo").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    DisclosureGroup("Opciones") {
                        Picker("Capacidad", selection: $capacity) {
                            ForEach(PhysicalTestCapacity.allCases) { capacity in
                                Text(capacity.rawValue).tag(capacity)
                            }
                        }
                        Stepper("Intentos: \(attempts)", value: $attempts, in: 1...5)
                        if attempts > 1 {
                            Picker("Cuenta", selection: $resultMode) {
                                ForEach(PhysicalTestResultMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Capacidad, intentos y cómo se cuentan. Puedes dejarlo así.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nueva prueba")
        .wizardInlineTitle()
        .appOnChange(of: unit) { option in
            // Lo normal en tiempo es que menos sea mejor.
            higherIsBetter = option.measurement != .time
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                cancelButton
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Siguiente") { path.append(.scale) }
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private var savedTestPicker: some View {
        SavedPhysicalTestPicker(definitions: definitions, selectedId: existingDefinitionId) { definition in
            Task { await selectExisting(definition) }
        }
    }

    private var savedTestsSummary: String {
        switch definitions.count {
        case 0: return "Aún no tienes pruebas guardadas"
        case 1: return definitions[0].name
        default:
            let names = definitions.prefix(2).map(\.name).joined(separator: ", ")
            let rest = definitions.count - 2
            return rest > 0 ? "\(names) y \(rest) más" : names
        }
    }

    // MARK: - Paso 2 · Baremo

    private var scaleStep: some View {
        Form {
            switch scalePhase {
            case .empty, .skipped:
                scaleEmptySections
            case .loading(let fileName):
                Section {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Leyendo «\(fileName)»…")
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    stepHeader(2)
                }
            case .loaded(let result, let fileName):
                if result.isValid {
                    scaleLoadedSections(result, fileName: fileName)
                } else {
                    scaleErrorSections(result)
                }
            case .unreadable(let message):
                Section {
                    ContentUnavailableView {
                        Label("No se pudo abrir el archivo", systemImage: "xmark.octagon")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Elegir otro archivo") { isPickingFile = true }
                            .buttonStyle(.borderedProminent)
                        Button("Escribirlo a mano") { scalePhase = .manual }
                    }
                } header: {
                    stepHeader(2)
                }
            case .manual:
                manualSections
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Baremo")
        .wizardInlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                cancelButton
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Siguiente") {
                    if !hasUsableScale, existingScaleCount == 0 { scalePhase = .skipped }
                    path.append(.destination)
                }
                .disabled(!canLeaveScaleStep)
            }
        }
    }

    @ViewBuilder
    private var scaleEmptySections: some View {
        Section {
            Text("Convierte cada marca en una nota de 0 a 10.")
                .foregroundStyle(.secondary)
            if existingScaleCount > 0 {
                Label(
                    existingScaleCount == 1 ? "Esta prueba ya tiene un baremo." : "Esta prueba ya tiene \(existingScaleCount) baremos.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
        } header: {
            stepHeader(2)
        }

        Section {
            Button {
                isPickingFile = true
            } label: {
                choiceLabel(
                    title: existingScaleCount > 0 ? "Importar otro Excel" : "Importar desde Excel",
                    subtitle: ".xlsx o .csv con tus tramos",
                    systemImage: "tablecells"
                )
            }
            Button {
                scalePhase = .manual
            } label: {
                choiceLabel(title: "Escribir a mano", subtitle: "Añade los tramos uno a uno", systemImage: "pencil")
            }
        } footer: {
            templateFooter
        }

        if existingScaleCount == 0 {
            Section {
                Button("Seguir sin baremo") {
                    scalePhase = .skipped
                    path.append(.destination)
                }
            } footer: {
                Text("Se guardará la marca. La nota se puede añadir después.")
            }
        }
    }

    @ViewBuilder
    private func scaleLoadedSections(_ result: PhysicalScaleSpreadsheetImport.Result, fileName: String) -> some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.rangeCount == 1 ? "1 tramo listo" : "\(result.rangeCount) tramos listos")
                        .font(.headline)
                    Text(loadedSummary(result))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Cambiar") { isPickingFile = true }
                    .accessibilityHint("Elige otro archivo")
            }
            .accessibilityElement(children: .contain)
        } header: {
            stepHeader(2)
        } footer: {
            Text(fileName)
        }

        if !result.warnings.isEmpty {
            Section("Avisos") {
                ForEach(result.warnings) { issue in
                    Label(issue.text, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Aviso. \(issue.text)")
                }
            }
        }

        Section {
            if result.courses.count > 1 || result.sexes.count > 1 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { scaleFilters(result) }
                    VStack(alignment: .leading, spacing: 8) { scaleFilters(result) }
                }
            }
            let group = visibleGroup(in: result)
            if let group {
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Desde (\(unitSymbol))")
                        Text("Hasta (\(unitSymbol))")
                        Text("Nota")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    ForEach(group.ranges, id: \.row) { range in
                        GridRow {
                            Text(range.minValue.map(PhysicalScaleSpreadsheetImport.format) ?? "—")
                            Text(range.maxValue.map(PhysicalScaleSpreadsheetImport.format) ?? "en adelante")
                            Text(PhysicalScaleSpreadsheetImport.format(range.score)).bold()
                        }
                        .monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(rangeAccessibilityLabel(range))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } header: {
            Text(visibleGroup(in: result)?.title ?? "Tramos")
        }
    }

    @ViewBuilder
    private func scaleFilters(_ result: PhysicalScaleSpreadsheetImport.Result) -> some View {
        if result.courses.count > 1 {
            Picker("Curso", selection: courseFilterBinding(result)) {
                ForEach(result.courses, id: \.self) { course in
                    Text(course.map { "\($0)º" } ?? "Todos").tag(course)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Curso")
        }
        if result.sexes.count > 1 {
            Picker("Sexo", selection: sexFilterBinding(result)) {
                ForEach(result.sexes, id: \.self) { sex in
                    Text(sexLabel(sex)).tag(sex)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Sexo")
        }
    }

    @ViewBuilder
    private func scaleErrorSections(_ result: PhysicalScaleSpreadsheetImport.Result) -> some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.errors.count == 1 ? "El Excel tiene 1 error" : "El Excel tiene \(result.errors.count) errores")
                        .font(.headline)
                    Text("Corrígelo en el Excel y vuelve a importarlo. No se ha guardado nada.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            stepHeader(2)
        }

        Section("Qué falla") {
            ForEach(result.errors) { issue in
                Label {
                    Text(issue.text)
                } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                .accessibilityLabel("Error. \(issue.text)")
            }
        }

        Section {
            Button("Elegir otro archivo") { isPickingFile = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } footer: {
            templateFooter
        }
    }

    @ViewBuilder
    private var manualSections: some View {
        Section {
            Text("Una fila por tramo. Deja «Hasta» vacío en el último.")
                .foregroundStyle(.secondary)
        } header: {
            stepHeader(2)
        }

        Section {
            ForEach($manualRows) { $row in
                HStack(spacing: 8) {
                    TextField("Desde", text: $row.from)
                    Text("a").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Hasta", text: $row.to)
                    Text("→").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Nota", text: $row.score)
                }
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .wizardDecimalKeyboard()
            }
            .onDelete { manualRows.remove(atOffsets: $0) }
            Button {
                manualRows.append(ManualRow())
            } label: {
                Label("Añadir tramo", systemImage: "plus")
            }
        } header: {
            Text("Desde (\(unitSymbol)) · Hasta · Nota")
        }

        let result = manualResult
        if let result, !result.errors.isEmpty {
            Section("Qué falla") {
                ForEach(result.errors) { issue in
                    Label(manualIssueText(issue), systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error. \(manualIssueText(issue))")
                }
            }
        } else if let result, !result.warnings.isEmpty {
            Section("Avisos") {
                ForEach(result.warnings) { issue in
                    Label(manualIssueText(issue), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }

        Section {
            Button("Importar desde Excel") { isPickingFile = true }
        } footer: {
            templateFooter
        }
    }

    @ViewBuilder
    private var templateFooter: some View {
        if let templateURL {
            ShareLink(item: templateURL) {
                Label("Descargar plantilla", systemImage: "arrow.down.doc")
            }
            .font(.footnote)
        }
    }

    private func choiceLabel(title: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    // MARK: - Paso 3 · Guardar

    private var destinationStep: some View {
        Form {
            if let outcome {
                doneSection(outcome)
            } else if classes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Aún no tienes grupos",
                        systemImage: "person.2",
                        description: Text("Guarda la prueba y su baremo ahora. La añades al cuaderno cuando crees un grupo.")
                    )
                } header: {
                    stepHeader(3)
                }
                saveErrorSection
            } else {
                Section {
                    Picker("Grupo", selection: $classId) {
                        ForEach(classes, id: \.id) { schoolClass in
                            Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
                        }
                    }
                    Picker("Pestaña", selection: $tabSelection) {
                        ForEach(tabs, id: \.id) { tab in
                            Text(tab.title).tag(tab.id)
                        }
                        if !tabs.contains(where: { $0.title.caseInsensitiveCompare(WizardTab.newTabTitle) == .orderedSame }) {
                            Text("Nueva: \(WizardTab.newTabTitle)").tag(WizardTab.newTabTitle)
                        }
                    }
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                } header: {
                    stepHeader(3)
                }

                Section {
                    columnPreview(title: "\(trimmedName) · \(unit.measurement == .level ? "Nivel" : "Marca")", detail: "Marca en \(unitSymbol). No cuenta en la media.")
                    if willHaveScale {
                        columnPreview(title: "\(trimmedName) · Nota", detail: "Nota de 0 a 10 según el baremo. Cuenta en la media.")
                    }
                } header: {
                    Text("Así aparecerá en el cuaderno")
                }

                if !willHaveScale {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sin baremo").font(.headline)
                                Text("La columna guardará la marca, pero no la nota. Puedes añadir el baremo después.")
                                    .font(.footnote)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.orange)
                    }
                }
                saveErrorSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(outcome == nil ? "Guardar" : "Hecho")
        .wizardInlineTitle()
        .navigationBarBackButtonHidden(outcome != nil || isSaving)
        .appOnChange(of: classId) { _ in Task { await loadTabs() } }
        .toolbar {
            if outcome == nil {
                ToolbarItem(placement: .cancellationAction) {
                    cancelButton.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("Guardando")
                    } else {
                        Button(classes.isEmpty ? "Guardar" : (saveError == nil ? "Guardar y añadir" : "Reintentar")) {
                            Task { await save() }
                        }
                    }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var saveErrorSection: some View {
        if let saveError {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No se pudo guardar").font(.headline)
                        Text("No se ha perdido nada. \(saveError)").font(.footnote)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func columnPreview(title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "tablecells")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func doneSection(_ outcome: PhysicalTestSetupOutcome) -> some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(doneTitle(outcome))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(doneDetail(outcome))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let classId = outcome.classId, let onOpenNotebook {
                    Button("Abrir el cuaderno") {
                        dismiss()
                        onOpenNotebook(classId)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Piezas comunes

    private func stepHeader(_ number: Int) -> some View {
        let names = ["Test", "Baremo", "Guardar"]
        return Text("Paso \(number) de 3 · \(names[number - 1])")
            .accessibilityLabel("Paso \(number) de 3, \(names[number - 1])")
            .accessibilityAddTraits(.isHeader)
    }

    private var cancelButton: some View {
        Button("Cancelar") {
            if isDirty { showingDiscard = true } else { dismiss() }
        }
    }

    // MARK: - Estado derivado

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var unitSymbol: String { unit.symbol }

    private var isDirty: Bool {
        guard outcome == nil else { return false }
        if !trimmedName.isEmpty || existingDefinitionId != nil { return true }
        if case .loaded = scalePhase { return true }
        return manualRows.contains { !$0.from.isEmpty || !$0.to.isEmpty || !$0.score.isEmpty }
    }

    /// Grupos de baremo listos para guardar, vengan del Excel o de la mano.
    private var scaleGroups: [PhysicalScaleSpreadsheetImport.Group] {
        switch scalePhase {
        case .loaded(let result, _) where result.isValid:
            return result.groups
        case .manual:
            guard let result = manualResult, result.isValid else { return [] }
            return result.groups
        default:
            return []
        }
    }

    private var hasUsableScale: Bool { !scaleGroups.isEmpty }

    private var willHaveScale: Bool { hasUsableScale || existingScaleCount > 0 }

    private var canLeaveScaleStep: Bool {
        switch scalePhase {
        case .loading, .unreadable: return false
        case .loaded(let result, _): return result.isValid
        case .manual: return hasUsableScale
        case .empty, .skipped: return existingScaleCount > 0
        }
    }

    private var manualResult: PhysicalScaleSpreadsheetImport.Result? {
        let filled = manualRows.filter { !$0.from.isEmpty || !$0.to.isEmpty || !$0.score.isEmpty }
        guard !filled.isEmpty else { return nil }
        return PhysicalScaleSpreadsheetImport.parse(
            rows: [["Desde", "Hasta", "Nota"]] + filled.map { [$0.from, $0.to, $0.score] }
        )
    }

    /// En la tabla a mano no hay «fila del archivo»: la fila 2 es el tramo 1.
    private func manualIssueText(_ issue: PhysicalScaleSpreadsheetImport.Issue) -> String {
        guard let row = issue.row else { return issue.message }
        let message = issue.message.replacingOccurrences(
            of: #"fila (\d+)"#,
            with: "tramo $1",
            options: .regularExpression
        )
        return "Tramo \(row - 1): \(renumberTramos(message))"
    }

    private func renumberTramos(_ text: String) -> String {
        guard let match = text.range(of: #"tramo (\d+)"#, options: .regularExpression),
              let number = Int(text[match].dropFirst("tramo ".count)) else { return text }
        return text.replacingCharacters(in: match, with: "tramo \(number - 1)")
    }

    private func loadedSummary(_ result: PhysicalScaleSpreadsheetImport.Result) -> String {
        let courses = result.courses.map { $0.map { "\($0)º" } ?? "todos los cursos" }
        let sexes = result.sexes.map { sexLabel($0).lowercased() }
        return [ListFormatter.localizedString(byJoining: courses), ListFormatter.localizedString(byJoining: sexes), "nota de 0 a 10"]
            .joined(separator: " · ")
    }

    private func visibleGroup(in result: PhysicalScaleSpreadsheetImport.Result) -> PhysicalScaleSpreadsheetImport.Group? {
        let course = courseFilterBinding(result).wrappedValue
        let sex = sexFilterBinding(result).wrappedValue
        return result.groups.first { $0.course == course && $0.sex == sex }
            ?? result.groups.first { $0.course == course }
            ?? result.groups.first
    }

    private func courseFilterBinding(_ result: PhysicalScaleSpreadsheetImport.Result) -> Binding<Int?> {
        Binding(
            get: { result.courses.contains(courseFilter) ? courseFilter : result.courses.first ?? nil },
            set: { courseFilter = $0 }
        )
    }

    private func sexFilterBinding(_ result: PhysicalScaleSpreadsheetImport.Result) -> Binding<String?> {
        Binding(
            get: { result.sexes.contains(sexFilter) ? sexFilter : result.sexes.first ?? nil },
            set: { sexFilter = $0 }
        )
    }

    private func sexLabel(_ sex: String?) -> String {
        switch sex {
        case "FEMALE": return "Chicas"
        case "MALE": return "Chicos"
        default: return "Todos"
        }
    }

    private func rangeAccessibilityLabel(_ range: PhysicalScaleSpreadsheetImport.Range) -> String {
        let from = range.minValue.map { "De \(PhysicalScaleSpreadsheetImport.format($0))" } ?? "Hasta"
        let to = range.maxValue.map { " a \(PhysicalScaleSpreadsheetImport.format($0)) \(unitSymbol)" } ?? " \(unitSymbol) en adelante"
        let text = range.minValue == nil
            ? "Hasta \(range.maxValue.map(PhysicalScaleSpreadsheetImport.format) ?? "") \(unitSymbol)"
            : from + to
        return "\(text), nota \(PhysicalScaleSpreadsheetImport.format(range.score))"
    }

    private func doneTitle(_ outcome: PhysicalTestSetupOutcome) -> String {
        guard let classId = outcome.classId, let schoolClass = classes.first(where: { $0.id == classId }) else {
            return "Prueba guardada"
        }
        return "Añadida a \(schoolClass.name)"
    }

    private func doneDetail(_ outcome: PhysicalTestSetupOutcome) -> String {
        guard outcome.classId != nil else {
            return "«\(trimmedName)» y su baremo ya están guardados."
        }
        let tabName = tabs.first { $0.id == outcome.notebookTabId }?.title ?? WizardTab.newTabTitle
        return "«\(trimmedName)» ya está en la pestaña \(tabName)."
    }

    // MARK: - Acciones

    @MainActor
    private func loadInitialData() async {
        if templateURL == nil {
            templateURL = try? PhysicalScaleSpreadsheetImport.writeTemplate()
        }
        classes = bridge.classes
        if classId == nil {
            classId = initialClassId.flatMap { id in classes.first { $0.id == id }?.id } ?? classes.first?.id
        }
        definitions = ((try? await bridge.listPhysicalDefinitions()) ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        await loadTabs()
    }

    @MainActor
    private func loadTabs() async {
        guard let classId else {
            tabs = []
            return
        }
        tabs = (try? await bridge.listNotebookTabsForClass(classId: classId)) ?? []
        if tabs.contains(where: { $0.id == tabSelection }) { return }
        tabSelection = tabs.first { tab in
            tab.title.localizedCaseInsensitiveContains("condición") || tab.title.localizedCaseInsensitiveContains("física")
        }?.id ?? WizardTab.newTabTitle
    }

    @MainActor
    private func selectExisting(_ definition: MiGestorKit.PhysicalTestDefinition) async {
        existingDefinitionId = definition.id
        name = definition.name
        let measurement: PhysicalTestMeasurement
        switch definition.measurementKind {
        case .time: measurement = .time
        case .repetitions: measurement = .repetitions
        case .level: measurement = .level
        default: measurement = .distance
        }
        unit = UnitOption.matching(unit: definition.unit, measurement: measurement)
        higherIsBetter = definition.higherIsBetter
        attempts = Int(definition.attempts)
        existingScaleCount = (try? await bridge.listPhysicalScalesForTest(testId: definition.id).count) ?? 0
        scalePhase = .empty
    }

    private func clearExistingSelection() {
        existingDefinitionId = nil
        existingScaleCount = 0
        name = ""
        scalePhase = .empty
    }

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                scalePhase = .unreadable(error.localizedDescription)
            }
            return
        }
        let fileName = url.lastPathComponent
        scalePhase = .loading(fileName)
        courseFilter = nil
        sexFilter = nil
        Task.detached(priority: .userInitiated) {
            let parsed: Result<PhysicalScaleSpreadsheetImport.Result, Error> = Result {
                try PhysicalScaleSpreadsheetImport.parse(url: url)
            }
            await MainActor.run {
                switch parsed {
                case .success(let importResult):
                    scalePhase = .loaded(importResult, fileName: fileName)
                    AccessibilityNotification.Announcement(
                        importResult.isValid ? "\(importResult.rangeCount) tramos listos" : "El Excel tiene errores"
                    ).post()
                case .failure:
                    scalePhase = .unreadable("No es un Excel o está dañado.")
                }
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let draft = PhysicalTestSetupDraft(
            existingDefinitionId: existingDefinitionId,
            name: trimmedName,
            unit: unit.symbol,
            measurement: unit.measurement,
            capacity: capacity,
            higherIsBetter: higherIsBetter,
            attempts: attempts,
            resultMode: attempts > 1 ? resultMode : .last,
            scaleGroups: scaleGroups,
            classId: classes.isEmpty ? nil : classId,
            notebookTab: classes.isEmpty ? nil : tabSelection,
            date: date
        )
        do {
            let saved = try await bridge.savePhysicalTestSetup(draft)
            if saved.classId != nil { await loadTabs() }
            outcome = saved
            onSaved(saved)
            AccessibilityNotification.Announcement(doneTitle(saved)).post()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Lista con buscador de las pruebas ya guardadas.
private struct SavedPhysicalTestPicker: View {
    let definitions: [MiGestorKit.PhysicalTestDefinition]
    let selectedId: String?
    let onSelect: (MiGestorKit.PhysicalTestDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [MiGestorKit.PhysicalTestDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return definitions }
        return definitions.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(filtered, id: \.id) { definition in
            Button {
                onSelect(definition)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(definition.name).foregroundStyle(.primary)
                        Text("\(definition.unit) · \(definition.higherIsBetter ? "más es mejor" : "menos es mejor")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if definition.id == selectedId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Elegida")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Buscar prueba")
        .navigationTitle("Pruebas guardadas")
        .wizardInlineTitle()
    }
}

private extension View {
    @ViewBuilder
    func wizardInlineTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    func wizardDecimalKeyboard() -> some View {
        #if os(macOS)
        self
        #else
        keyboardType(.decimalPad)
        #endif
    }
}
