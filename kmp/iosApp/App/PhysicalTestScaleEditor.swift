import SwiftUI

enum PhysicalTestScaleDirection: String, CaseIterable, Identifiable {
    case higherIsBetter
    case lowerIsBetter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .higherIsBetter: return "Mayor marca"
        case .lowerIsBetter: return "Menor marca"
        }
    }

    var subtitle: String {
        switch self {
        case .higherIsBetter: return "Salto, repeticiones, niveles o distancia."
        case .lowerIsBetter: return "Tiempo, velocidad o pruebas cronometradas."
        }
    }
}

struct PhysicalTestScaleRange: Identifiable, Hashable {
    let id = UUID()
    var minValue: Double?
    var maxValue: Double?
    var score: Double
    var label: String

    func contains(_ value: Double) -> Bool {
        let passesMin = minValue.map { value >= $0 } ?? true
        let passesMax = maxValue.map { value <= $0 } ?? true
        return passesMin && passesMax
    }
}

struct PhysicalTestScaleDraft: Identifiable, Hashable {
    let id = UUID()
    var persistedScaleId: String?
    var name: String
    var testId: String = ""
    var course: Int?
    var ageFrom: Int?
    var ageTo: Int?
    var sex: String = ""
    var batteryId: String = ""
    var direction: PhysicalTestScaleDirection
    var ranges: [PhysicalTestScaleRange]

    static let defaultJump = PhysicalTestScaleDraft(
        name: "Baremo salto horizontal 0-10",
        direction: .higherIsBetter,
        ranges: [
            .init(minValue: nil, maxValue: 1.19, score: 3, label: "< 1.20 m"),
            .init(minValue: 1.20, maxValue: 1.39, score: 5, label: "1.20-1.39 m"),
            .init(minValue: 1.40, maxValue: 1.59, score: 6, label: "1.40-1.59 m"),
            .init(minValue: 1.60, maxValue: 1.79, score: 8, label: "1.60-1.79 m"),
            .init(minValue: 1.80, maxValue: nil, score: 10, label: ">= 1.80 m")
        ]
    )

    static let defaultSpeed = PhysicalTestScaleDraft(
        name: "Baremo velocidad 0-10",
        direction: .lowerIsBetter,
        ranges: [
            .init(minValue: nil, maxValue: 6.0, score: 10, label: "<= 6.0 s"),
            .init(minValue: 6.1, maxValue: 6.5, score: 8, label: "6.1-6.5 s"),
            .init(minValue: 6.6, maxValue: 7.0, score: 6, label: "6.6-7.0 s"),
            .init(minValue: 7.1, maxValue: 7.5, score: 5, label: "7.1-7.5 s"),
            .init(minValue: 7.6, maxValue: nil, score: 3, label: "> 7.5 s")
        ]
    )

    func score(for rawValue: Double) -> Double? {
        ranges.first(where: { $0.contains(rawValue) })?.score
    }

    var validationMessages: [String] {
        validationMessages(testId: testId, expectedUnit: nil, expectedDirection: direction)
    }

    func validationMessages(
        testId: String?,
        expectedUnit: String?,
        expectedDirection: PhysicalTestScaleDirection
    ) -> [String] {
        var messages: [String] = []
        let normalizedTestId = testId.map(PhysicalScaleProfileCatalog.normalizedTestId) ?? ""
        let profile = PhysicalScaleProfileCatalog.profile(for: normalizedTestId, objective: "mixto")
        let boundaryStep = profile?.precision.boundaryStep ?? inferredBoundaryStep
        if ranges.count != 5 {
            messages.append("El baremo debe tener exactamente 5 rangos.")
        }
        if let expectedUnit, let profile, !expectedUnit.isEmpty, profile.unit != expectedUnit {
            messages.append("La unidad no coincide con el perfil de la prueba.")
        }
        if let profile, profile.higherIsBetter != (expectedDirection == .higherIsBetter) {
            messages.append("La dirección de mejora no coincide con el tipo de prueba.")
        }
        for range in ranges {
            if range.minValue == nil && range.maxValue == nil {
                messages.append("Hay rangos sin mínimo ni máximo.")
            }
            if let min = range.minValue, let max = range.maxValue, min > max {
                messages.append("Hay rangos con mínimo mayor que máximo.")
            }
            if !(0...10).contains(range.score) {
                messages.append("Todas las notas deben estar entre 0 y 10.")
            }
        }
        let sorted = ranges.sorted { ($0.minValue ?? -.infinity) < ($1.minValue ?? -.infinity) }
        for pair in zip(sorted, sorted.dropFirst()) {
            if let leftMax = pair.0.maxValue, let rightMin = pair.1.minValue, rightMin < leftMax {
                messages.append("Hay rangos solapados.")
                break
            }
            if let leftMax = pair.0.maxValue, let rightMin = pair.1.minValue, hasGap(from: leftMax, to: rightMin, allowedStep: boundaryStep) {
                messages.append("Hay huecos entre rangos.")
                break
            }
        }
        let scores = sorted.map(\.score)
        if let profile {
            if profile.higherIsBetter, scores != scores.sorted() {
                messages.append("Las notas deben subir cuando mejora la marca.")
            }
            if !profile.higherIsBetter, scores != scores.sorted(by: >) {
                messages.append("Las notas deben bajar cuando aumenta el tiempo.")
            }
        }
        return Array(Set(messages)).sorted()
    }

    private func hasGap(from leftMax: Double, to rightMin: Double, allowedStep: Double) -> Bool {
        let gap = rightMin - leftMax
        guard gap > 0 else { return false }
        return gap > allowedStep + 0.000_001
    }

    private var inferredBoundaryStep: Double {
        let values = ranges.flatMap { [$0.minValue, $0.maxValue].compactMap { $0 } }
        if values.contains(where: { hasDecimalPlaces($0, places: 3) }) { return 0.001 }
        if values.contains(where: { hasDecimalPlaces($0, places: 2) }) { return 0.01 }
        if values.contains(where: { hasDecimalPlaces($0, places: 1) }) { return 0.1 }
        return 1
    }

    private func hasDecimalPlaces(_ value: Double, places: Int) -> Bool {
        let multiplier = pow(10, Double(places))
        let scaled = (value * multiplier).rounded()
        let previousMultiplier = pow(10, Double(max(places - 1, 0)))
        let previousScaled = (value * previousMultiplier).rounded()
        return abs(value * multiplier - scaled) < 0.000_001 &&
            abs(value * previousMultiplier - previousScaled) >= 0.000_001
    }
}

struct PhysicalTestScaleEditorContext {
    var testId: String
    var batteryId: String?
    var batteryName: String
    var className: String
    var termLabel: String?
    var testName: String
    var capacity: String
    var measurementKind: String
    var unit: String
    var course: Int?
    var ageFrom: Int?
    var ageTo: Int?

    var ageRange: String {
        "\(ageFrom.map(String.init) ?? "-")-\(ageTo.map(String.init) ?? "-")"
    }

    init(
        testId: String = "",
        batteryId: String? = nil,
        batteryName: String,
        className: String,
        termLabel: String?,
        testName: String,
        capacity: String,
        measurementKind: String,
        unit: String,
        course: Int?,
        ageFrom: Int?,
        ageTo: Int?
    ) {
        self.testId = testId
        self.batteryId = batteryId
        self.batteryName = batteryName
        self.className = className
        self.termLabel = termLabel
        self.testName = testName
        self.capacity = capacity
        self.measurementKind = measurementKind
        self.unit = unit
        self.course = course
        self.ageFrom = ageFrom
        self.ageTo = ageTo
    }

    init(
        testId: String = "",
        batteryId: String? = nil,
        batteryName: String,
        className: String,
        termLabel: String?,
        testName: String,
        unit: String,
        ageRange: String
    ) {
        let ages = ageRange
            .split(separator: "-")
            .map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        self.init(
            testId: testId,
            batteryId: batteryId,
            batteryName: batteryName,
            className: className,
            termLabel: termLabel,
            testName: testName,
            capacity: "Condición física",
            measurementKind: "Marca",
            unit: unit,
            course: nil,
            ageFrom: ages.first ?? nil,
            ageTo: ages.dropFirst().first ?? nil
        )
    }
}

func resolvedPhysicalResult(
    attempts: [Double],
    direction: PhysicalTestScaleDirection,
    resultMode: PhysicalTestResultMode
) -> Double? {
    let validAttempts = attempts.filter { $0.isFinite }
    guard !validAttempts.isEmpty else { return nil }
    switch resultMode {
    case .best:
        return direction == .higherIsBetter ? validAttempts.max() : validAttempts.min()
    case .average:
        return validAttempts.reduce(0, +) / Double(validAttempts.count)
    case .last:
        return validAttempts.last
    }
}

enum PhysicalTestScaleStrategy: String, CaseIterable, Identifiable {
    case recommended = "Rendimiento absoluto"
    case progress = "Progreso individual"
    case manual = "Manual por rangos"

    var id: String { rawValue }

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .recommended:
            return "Usa el baremo local disponible como punto de partida y deja la ponderación para el Cuaderno."
        case .progress:
            return "Evalúa la mejora entre mediciones cuando exista histórico persistente de condición física."
        case .manual:
            return "Define rangos de marca y nota para un baremo específico."
        }
    }
}

enum PhysicalScaleRecommendationObjective: String, CaseIterable, Identifiable {
    case initial = "Evaluación inicial"
    case final = "Evaluación final"
    case individualProgress = "Progreso individual"
    case mixed = "Mixto"

    var id: String { rawValue }
}

struct PhysicalTestScaleEditor: View {
    @Binding var scale: PhysicalTestScaleDraft
    var context: PhysicalTestScaleEditorContext?
    var canSave: Bool
    var onSave: ((PhysicalTestScaleDraft) -> Void)?
    @State private var strategy: PhysicalTestScaleStrategy = .manual
    @State private var aiObjective: PhysicalScaleRecommendationObjective = .mixed
    @State private var previewValue = ""
    @State private var savedMessage: String?
    @State private var aiService = AppleFoundationContextualAIService()
    @State private var aiAvailability: AIContextualAvailabilityState = .unavailable("Comprobando disponibilidad de Apple Foundation Models.")
    @State private var aiProposal: PhysicalScaleRecommendationDraft?
    @State private var aiErrorMessage: String?
    @State private var isGeneratingAIProposal = false

    init(
        scale: Binding<PhysicalTestScaleDraft>,
        context: PhysicalTestScaleEditorContext? = nil,
        canSave: Bool = true,
        onSave: ((PhysicalTestScaleDraft) -> Void)? = nil
    ) {
        self._scale = scale
        self.context = context
        self.canSave = canSave
        self.onSave = onSave
    }

    private var previewScore: Double? {
        Double(previewValue.replacingOccurrences(of: ",", with: ".")).flatMap { scale.score(for: $0) }
    }

    private var previewRange: PhysicalTestScaleRange? {
        Double(previewValue.replacingOccurrences(of: ",", with: ".")).flatMap { raw in
            scale.ranges.first(where: { $0.contains(raw) })
        }
    }

    private var validationMessages: [String] {
        scale.validationMessages(
            testId: context?.testId ?? scale.testId,
            expectedUnit: context?.unit,
            expectedDirection: scale.direction
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    scaleConfiguration
                    rangesEditor
                }
                .padding(20)
            }
            .frame(minWidth: 430, maxWidth: 560, maxHeight: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    validationPanel
                    previewPanel
                    aiSuggestionPanel
                }
                .padding(20)
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Baremo")
        .frame(minWidth: 860, minHeight: 600)
        .task { refreshAIAvailability() }
    }

    private var scaleConfiguration: some View {
        ScaleEditorCard(title: "Configuración") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Nombre del baremo", text: $scale.name)
                    .font(.title3.weight(.semibold))

                if let context {
                    VStack(alignment: .leading, spacing: 8) {
                        LockedScaleContextRow(title: "Prueba", value: "\(context.testName) · \(context.unit)")
                        LockedScaleContextRow(title: "Capacidad", value: context.capacity)
                        LockedScaleContextRow(title: "Medición", value: context.measurementKind)
                        LockedScaleContextRow(title: "Batería", value: context.batteryName)
                        LockedScaleContextRow(title: "Curso / clase", value: "\(context.course.map { "\($0)º" } ?? "Sin curso") · \(context.className)")
                        LockedScaleContextRow(title: "Edad", value: context.ageRange)
                        if let termLabel = context.termLabel {
                            LockedScaleContextRow(title: "Evaluación", value: termLabel)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        LockedScaleContextRow(title: "Prueba", value: scale.testId.isEmpty ? "Selecciona una prueba" : scale.testId)
                        LockedScaleContextRow(title: "Batería", value: scale.batteryId.isEmpty ? "Sin batería seleccionada" : scale.batteryId)
                        LockedScaleContextRow(title: "Curso", value: scale.course.map { "\($0)º" } ?? "Sin curso")
                        LockedScaleContextRow(title: "Edad", value: "\(scale.ageFrom.map(String.init) ?? "-")-\(scale.ageTo.map(String.init) ?? "-")")
                    }
                }

                Picker("Dirección", selection: $scale.direction) {
                    ForEach(PhysicalTestScaleDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                Text(scale.direction.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Tipo de baremo", selection: $strategy) {
                    ForEach(PhysicalTestScaleStrategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                Text(strategy.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Objetivo IA", selection: $aiObjective) {
                    ForEach(PhysicalScaleRecommendationObjective.allCases) { objective in
                        Text(objective.rawValue).tag(objective)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var rangesEditor: some View {
        ScaleEditorCard(title: "Rangos") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Desde").frame(width: 86, alignment: .leading)
                    Text("Hasta").frame(width: 86, alignment: .leading)
                    Text("Nota").frame(width: 76, alignment: .leading)
                    Text("Etiqueta").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

                ForEach($scale.ranges) { $range in
                    HStack(spacing: 10) {
                        NumberDraftField(title: "", value: $range.minValue)
                            .frame(width: 86)
                        NumberDraftField(title: "", value: $range.maxValue)
                            .frame(width: 86)
                        NumberDraftFieldRequired(title: "", value: $range.score)
                            .frame(width: 76)
                        TextField("Etiqueta", text: $range.label)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Button {
                        scale.ranges.append(.init(minValue: nil, maxValue: nil, score: 5, label: "Nuevo rango"))
                    } label: {
                        Label("Añadir rango", systemImage: "plus")
                    }

                    Button {
                        scale.ranges.sort { ($0.minValue ?? -.infinity) < ($1.minValue ?? -.infinity) }
                    } label: {
                        Label("Ordenar rangos", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        normalizeLabels()
                    } label: {
                        Label("Normalizar etiquetas", systemImage: "textformat")
                    }

                    Spacer()

                    Button {
                        if validationMessages.isEmpty, canSave {
                            onSave?(scale)
                            savedMessage = "Baremo guardado para esta prueba."
                        } else {
                            savedMessage = "Revisa la validación antes de guardar."
                        }
                    } label: {
                        Label("Guardar baremo de esta prueba", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || !validationMessages.isEmpty)
                }

                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(validationMessages.isEmpty ? .green : .orange)
                }
            }
        }
    }

    private var validationPanel: some View {
        ScaleEditorCard(title: "Validación") {
            if validationMessages.isEmpty {
                Label("Sin incidencias detectadas", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var previewPanel: some View {
        ScaleEditorCard(title: "Preview") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Marca de prueba", text: $previewValue)
                    .appKeyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Nota baremada")
                    Spacer()
                    Text(previewScore.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rango aplicado")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(previewExplanation)
                        .font(.callout.weight(.semibold))
                    if let previewRange {
                        Text("\(previewRange.minValue.map(PhysicalTestsFormatting.decimal) ?? "-∞") a \(previewRange.maxValue.map(PhysicalTestsFormatting.decimal) ?? "+∞") · nota \(PhysicalTestsFormatting.decimal(previewRange.score))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var aiSuggestionPanel: some View {
        ScaleEditorCard(title: "Sugerir baremo con IA") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: aiAvailability.isAvailable ? "sparkles" : "sparkles.rectangle.stack")
                        .foregroundStyle(aiAvailability.isAvailable ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Propuesta IA")
                            .font(.subheadline.weight(.bold))
                        Text(aiAvailability.message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                Label("Revisión docente necesaria", systemImage: "checkmark.seal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PhysicalScaleProfileCatalog.safetyWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Text("La IA generará rangos orientativos editables. No son oficiales y deben revisarse antes de usarse con el grupo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await generateAIProposal() }
                } label: {
                    Label(isGeneratingAIProposal ? "Generando propuesta" : "Generar propuesta", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!aiAvailability.isAvailable || isGeneratingAIProposal)

                if isGeneratingAIProposal {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let aiErrorMessage {
                    Label(aiErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if let aiProposal {
                    Divider()
                    aiProposalPreview(aiProposal)
                }
            }
        }
    }

    private func aiProposalPreview(_ proposal: PhysicalScaleRecommendationDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.title)
                    .font(.headline)
                Text(proposal.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rango").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Nota").frame(width: 54, alignment: .trailing)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

                ForEach(proposal.ranges) { range in
                    HStack(spacing: 10) {
                        Text(range.label.isEmpty ? formattedRange(range) : range.label)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(PhysicalTestsFormatting.decimal(range.score))
                            .font(.caption.weight(.black).monospacedDigit())
                            .frame(width: 54, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            Text(proposal.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(proposal.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Button {
                    applyAIProposal(proposal)
                } label: {
                    Label("Aplicar al baremo", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    aiProposal = nil
                    aiErrorMessage = nil
                } label: {
                    Label("Descartar", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var previewExplanation: String {
        guard !previewValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Introduce una marca para comprobar el baremo."
        }
        guard let previewRange else {
            return "No hay ningún rango que cubra esta marca."
        }
        let label = previewRange.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let rangeText = label.isEmpty ? "\(previewRange.minValue.map(PhysicalTestsFormatting.decimal) ?? "-∞")-\(previewRange.maxValue.map(PhysicalTestsFormatting.decimal) ?? "+∞")" : label
        return "Esta marca entra en el rango \(rangeText) y obtiene \(PhysicalTestsFormatting.decimal(previewRange.score))."
    }

    private func normalizeLabels() {
        for index in scale.ranges.indices {
            let minText = scale.ranges[index].minValue.map(PhysicalTestsFormatting.decimal) ?? "-∞"
            let maxText = scale.ranges[index].maxValue.map(PhysicalTestsFormatting.decimal) ?? "+∞"
            scale.ranges[index].label = "\(minText)-\(maxText)"
        }
    }

    private func refreshAIAvailability() {
        aiAvailability = aiService.currentAvailability()
    }

    private func generateAIProposal() async {
        refreshAIAvailability()
        aiErrorMessage = nil
        isGeneratingAIProposal = true
        defer { isGeneratingAIProposal = false }
        do {
            aiProposal = try await aiService.generatePhysicalScaleRecommendation(from: recommendationInput)
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    private func applyAIProposal(_ proposal: PhysicalScaleRecommendationDraft) {
        scale.ranges = proposal.ranges.map {
            PhysicalTestScaleRange(minValue: $0.minValue, maxValue: $0.maxValue, score: $0.score, label: $0.label)
        }
        scale.testId = recommendationInput.testId
        if let profile = PhysicalScaleProfileCatalog.profile(for: recommendationInput.testId, objective: recommendationInput.objective) {
            scale.direction = profile.higherIsBetter ? .higherIsBetter : .lowerIsBetter
        }
        scale.course = context?.course ?? scale.course
        scale.ageFrom = context?.ageFrom ?? scale.ageFrom
        scale.ageTo = context?.ageTo ?? scale.ageTo
        scale.batteryId = context?.batteryId ?? scale.batteryId
        if !proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scale.name = proposal.title
        }
        aiProposal = nil
        savedMessage = "Propuesta IA aplicada al baremo. Revisa y guarda cuando esté ajustada."
    }

    private var recommendationInput: PhysicalScaleRecommendationInput {
        PhysicalScaleRecommendationInput(
            testId: PhysicalScaleProfileCatalog.normalizedTestId(context?.testId ?? scale.testId),
            testName: context?.testName ?? (scale.testId.isEmpty ? scale.name : scale.testId),
            capacity: context?.capacity ?? "Sin capacidad definida",
            measurementKind: context?.measurementKind ?? "Sin medición definida",
            unit: context?.unit ?? "unidad",
            directionLabel: scale.direction == .higherIsBetter ? "mayor marca = mejor nota" : "menor marca = mejor nota",
            course: context?.course.map { "\($0)º" } ?? scale.course.map { "\($0)º" } ?? "Sin curso",
            ageFrom: context?.ageFrom ?? scale.ageFrom,
            ageTo: context?.ageTo ?? scale.ageTo,
            objective: aiObjective.rawValue,
            scoreScale: "0-10"
        )
    }

    private func formattedRange(_ range: PhysicalScaleRecommendedRange) -> String {
        let minText = range.minValue.map(PhysicalTestsFormatting.decimal) ?? "-∞"
        let maxText = range.maxValue.map(PhysicalTestsFormatting.decimal) ?? "+∞"
        return "\(minText)-\(maxText) \(context?.unit ?? "")"
    }
}

private struct LockedScaleContextRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.callout.weight(.semibold))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct ScaleEditorCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?

    private var text: Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { value = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("-", text: text)
                .appKeyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct NumberDraftField: View {
    let title: String
    @Binding var value: Double?

    private var text: Binding<String> {
        Binding(
            get: { value.map { PhysicalTestsFormatting.decimal($0) } ?? "" },
            set: { value = Double($0.replacingOccurrences(of: ",", with: ".")) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("-", text: text)
                .appKeyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct NumberDraftFieldRequired: View {
    let title: String
    @Binding var value: Double

    private var text: Binding<String> {
        Binding(
            get: { PhysicalTestsFormatting.decimal(value) },
            set: { value = Double($0.replacingOccurrences(of: ",", with: ".")) ?? value }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("-", text: text)
                .appKeyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

enum PhysicalTestsFormatting {
    static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
