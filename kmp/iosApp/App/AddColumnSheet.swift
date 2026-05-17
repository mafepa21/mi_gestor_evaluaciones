import SwiftUI
import MiGestorKit

enum NotebookIndividualSummaryEvidenceSource: String, CaseIterable, Identifiable, Codable {
    case visibleColumns
    case evaluableColumns
    case allManagedColumns

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visibleColumns: return "Visibles"
        case .evaluableColumns: return "Evaluables"
        case .allManagedColumns: return "Todas"
        }
    }

    var subtitle: String {
        switch self {
        case .visibleColumns: return "Solo lo que el docente tiene a la vista."
        case .evaluableColumns: return "Instrumentos que aportan lectura académica."
        case .allManagedColumns: return "Incluye seguimiento, evidencias y extras."
        }
    }
}

enum NotebookIndividualSummaryLength: String, CaseIterable, Identifiable, Codable {
    case brief
    case balanced
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: return "Breve"
        case .balanced: return "Equilibrada"
        case .expanded: return "Amplia"
        }
    }

    var subtitle: String {
        switch self {
        case .brief: return "Lectura corta y directa."
        case .balanced: return "Resumen claro para revisión rápida."
        case .expanded: return "Añade fortalezas y próximos pasos."
        }
    }
}

enum NotebookIndividualSummaryGenerationMode: String, CaseIterable, Identifiable, Codable {
    case onlyEmptyCells
    case overwriteExisting
    case createNewVersion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onlyEmptyCells: return "Solo vacías"
        case .overwriteExisting: return "Regenerar"
        case .createNewVersion: return "Nueva versión"
        }
    }

    var subtitle: String {
        switch self {
        case .onlyEmptyCells: return "Conserva las síntesis ya editadas."
        case .overwriteExisting: return "Sustituye el texto actual por una nueva pasada."
        case .createNewVersion: return "Crea otra columna IA para comparar iteraciones."
        }
    }
}

struct NotebookIndividualSummaryConfiguration: Equatable, Codable {
    var evidenceSource: NotebookIndividualSummaryEvidenceSource = .allManagedColumns
    var length: NotebookIndividualSummaryLength = .balanced
    var generationMode: NotebookIndividualSummaryGenerationMode = .onlyEmptyCells
}

enum NotebookIndividualSummaryPreferences {
    private static let defaults = UserDefaults.standard
    private static let prefix = "notebook.individual.summary.config."
    static let marker = "Sintesis individual"

    static func load(columnId: String?) -> NotebookIndividualSummaryConfiguration {
        guard let columnId,
              let data = defaults.data(forKey: prefix + columnId),
              let configuration = try? JSONDecoder().decode(NotebookIndividualSummaryConfiguration.self, from: data) else {
            return NotebookIndividualSummaryConfiguration()
        }
        return configuration
    }

    static func save(_ configuration: NotebookIndividualSummaryConfiguration, columnId: String) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: prefix + columnId)
    }
}

func notebookIndividualSummaryText(
    from draft: NotebookAICommentDraft,
    length: NotebookIndividualSummaryLength
) -> String {
    switch length {
    case .brief:
        let pieces = draft.commentText
            .split(whereSeparator: { $0.isNewline })
            .flatMap { $0.split(separator: ".") }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let selected = Array(pieces.prefix(2)).map { "\($0)." }
        return selected.isEmpty ? draft.commentText : selected.joined(separator: " ")
    case .balanced:
        return draft.commentText
    case .expanded:
        let strengths = draft.strengths.prefix(2).joined(separator: " · ")
        let nextStep = draft.nextSteps.first ?? ""
        let appendedStrengths = strengths.isEmpty ? "" : "\nFortalezas observables: \(strengths)."
        let appendedNextStep = nextStep.isEmpty ? "" : "\nPróximo paso sugerido: \(nextStep)."
        return draft.commentText + appendedStrengths + appendedNextStep
    }
}

func isNotebookIndividualSummaryColumn(_ column: NotebookColumnDefinition) -> Bool {
    column.type == .text &&
    column.instrumentKind == .privateComment &&
    column.inputKind == .text &&
    !column.countsTowardAverage &&
    column.iconName == "apple.intelligence" &&
    column.unitOrSituation == NotebookIndividualSummaryPreferences.marker
}

private struct NotebookColumnBlueprint: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let type: NotebookColumnType
    let categoryKind: NotebookColumnCategoryKind
    let instrumentKind: NotebookInstrumentKind
    let inputKind: NotebookCellInputKind
    let scaleKind: NotebookScaleKind
    let defaultWeight: Double

    var isIndividualSummary: Bool {
        id == "individual_summary"
    }
}

private struct ColumnBlueprintCard: View {
    let blueprint: NotebookColumnBlueprint
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        let selectedForeground = contrastingTextColor(for: tint)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? selectedForeground.opacity(0.18) : tint.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: blueprint.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? selectedForeground : tint)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(blueprint.title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? selectedForeground : .primary)
                    Text(blueprint.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? selectedForeground.opacity(0.86) : .secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? tint : NotebookStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? tint : NotebookStyle.softBorder, lineWidth: 1)
            )
            .shadow(color: NotebookStyle.shadow.opacity(isSelected ? 0.75 : 0.4), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(blueprint.title)
    }
}

private struct NotebookConfigurationOptionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? contrastingTextColor(for: tint) : .primary)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(contrastingTextColor(for: tint))
                            .accessibilityHidden(true)
                    }
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? contrastingTextColor(for: tint).opacity(0.84) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? tint : NotebookStyle.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? tint : NotebookStyle.softBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct NotebookSummaryPreviewCard: View {
    let title: String
    let subtitle: String
    let configuration: NotebookIndividualSummaryConfiguration
    let tint: Color

    var body: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .frame(width: 52, height: 52)

                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(tint)
                            .accessibilityLabel("Síntesis individual")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title2.weight(.bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    NotebookPill(label: configuration.evidenceSource.title, systemImage: "tray.full", active: false, tint: tint, compact: true)
                    NotebookPill(label: configuration.length.title, systemImage: "text.alignleft", active: false, tint: tint, compact: true)
                    NotebookPill(label: configuration.generationMode.title, systemImage: "arrow.trianglehead.2.clockwise.rotate.90", active: true, tint: tint, compact: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("La síntesis se guardará como texto editable por alumno y quedará fuera de la media.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(sampleText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(NotebookStyle.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(NotebookStyle.softBorder, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var sampleText: String {
        switch configuration.length {
        case .brief:
            return "Muestra avance estable y constancia en las tareas recientes. Conviene mantener el ritmo y reforzar la expresión final."
        case .balanced:
            return "Muestra avance estable y constancia en las tareas recientes. Participa con criterio cuando cuenta con referencias claras y sostiene una evolución positiva. Conviene reforzar la expresión final para consolidar lo aprendido."
        case .expanded:
            return "Muestra avance estable y constancia en las tareas recientes. Participa con criterio cuando cuenta con referencias claras y sostiene una evolución positiva. Conviene reforzar la expresión final para consolidar lo aprendido.\nFortalezas observables: seguimiento constante · buena respuesta a la retroalimentación.\nPróximo paso sugerido: cerrar cada tarea con una síntesis más precisa."
        }
    }
}

private struct NotebookChecklistPreviewCard: View {
    let tint: Color

    var body: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vista previa")
                            .font(.headline)
                        Text("Cada celda se marcará como Sí o No.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    checklistSampleCell(title: "Completado", isChecked: true)
                    checklistSampleCell(title: "Pendiente", isChecked: false)
                }
            }
        }
    }

    private func checklistSampleCell(title: String, isChecked: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isChecked ? tint : .secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NotebookStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        )
    }
}

struct AddColumnSheet: View {
    @ObservedObject var bridge: KmpBridge
    var initialCategoryId: String? = nil
    var startsCreatingCategory: Bool = false
    var onCreatedSummaryColumn: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notebook.addColumn.lastBlueprintId") private var lastBlueprintId: String = "written_test"
    @FocusState private var isNameFocused: Bool

    @State private var columnName: String = ""
    @State private var selectedBlueprintId: String? = nil
    @State private var weight: String = "10"
    @State private var formula: String = ""
    @State private var selectedRubricId: Int64? = nil
    @State private var selectedCategoryId: String? = nil
    @State private var newCategoryName: String = ""
    @State private var categoryPlacementMode: CategoryPlacementMode = .existing
    @State private var unitOrSituation: String = ""
    @State private var selectedDate: Date = .now
    @State private var countsTowardAverage = true
    @State private var isPinned = false
    @State private var isTemplate = false
    @State private var isLocked = false
    @State private var summaryConfiguration = NotebookIndividualSummaryConfiguration()
    @State private var summaryAvailability: AIContextualAvailabilityState = .unavailable("Apple Intelligence no está disponible en este dispositivo. Podrás rellenarla manualmente.")
    @State private var summaryAIService = AppleFoundationContextualAIService()

    private let blueprints: [NotebookColumnBlueprint] = [
        .init(id: "written_test", title: "Nota numérica", subtitle: "Calificación 0-10", icon: "number.circle", type: .numeric, categoryKind: .evaluation, instrumentKind: .writtenTest, inputKind: .numeric010, scaleKind: .tenPoint, defaultWeight: 10),
        .init(id: "rubric", title: "Rúbrica", subtitle: "Mini rúbrica emergente", icon: "checklist", type: .rubric, categoryKind: .evaluation, instrumentKind: .rubric, inputKind: .rubric, scaleKind: .tenPoint, defaultWeight: 15),
        .init(id: "checklist", title: "Lista de control", subtitle: "Sí / No rápido", icon: "checkmark.square", type: .check, categoryKind: .evaluation, instrumentKind: .checklist, inputKind: .check, scaleKind: .yesNo, defaultWeight: 5),
        .init(id: "observation", title: "Observación", subtitle: "Nota corta con inspector", icon: "note.text", type: .text, categoryKind: .followUp, instrumentKind: .systematicObservation, inputKind: .shortNote, scaleKind: .custom, defaultWeight: 0),
        .init(id: "participation", title: "Participación", subtitle: "Selector rápido por chips", icon: "person.2.wave.2", type: .ordinal, categoryKind: .followUp, instrumentKind: .participation, inputKind: .quickSelector, scaleKind: .achievement, defaultWeight: 5),
        .init(id: "calculated", title: "Cálculo / Fórmula", subtitle: "Fórmula con referencias a columnas", icon: "function", type: .calculated, categoryKind: .evaluation, instrumentKind: .custom, inputKind: .calculated, scaleKind: .tenPoint, defaultWeight: 0),
        .init(id: "evidence", title: "Evidencia", subtitle: "Adjunto desde inspector o celda", icon: "paperclip.circle", type: .text, categoryKind: .extras, instrumentKind: .multimediaEvidence, inputKind: .evidence, scaleKind: .custom, defaultWeight: 0),
        .init(id: "individual_summary", title: "Síntesis pedagógica", subtitle: "Columna IA editable y regenerable por alumno", icon: "apple.intelligence", type: .text, categoryKind: .followUp, instrumentKind: .privateComment, inputKind: .text, scaleKind: .custom, defaultWeight: 0),
    ]

    private var basicBlueprints: [NotebookColumnBlueprint] {
        blueprints.filter { ["written_test", "rubric", "checklist", "observation", "participation"].contains($0.id) }
    }

    private var advancedBlueprints: [NotebookColumnBlueprint] {
        blueprints.filter { ["calculated", "evidence", "individual_summary"].contains($0.id) }
    }

    private var selectedBlueprint: NotebookColumnBlueprint? {
        guard let selectedBlueprintId else { return nil }
        return blueprints.first(where: { $0.id == selectedBlueprintId })
    }

    private enum CategoryPlacementMode: String, CaseIterable, Identifiable {
        case existing
        case createNew

        var id: String { rawValue }

        var title: String {
            switch self {
            case .existing: return "Añadir a categoría existente"
            case .createNew: return "Crear categoría nueva"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                VStack(alignment: .leading, spacing: 0) {
                    sheetHeader

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            blueprintSection

                            if selectedBlueprint != nil {
                                Divider()
                                contentLayout(for: geometry.size.width)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(24)
                    }
                    .animation(.spring(duration: 0.25), value: selectedBlueprintId)

                    Divider()

                    footerActions
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial)
                }
                .background(EvaluationBackdrop())
                .navigationTitle("Nueva columna")
                .appInlineNavigationBarTitleDisplayMode()
                .onAppear {
                    selectedCategoryId = initialCategoryId ?? selectedCategoryId ?? suggestedCategoryId
                    categoryPlacementMode = startsCreatingCategory ? .createNew : .existing
                    if selectedBlueprintId == nil {
                        selectedBlueprintId = blueprints.contains(where: { $0.id == lastBlueprintId }) ? lastBlueprintId : "written_test"
                    }
                    syncBlueprintDefaults()
                    refreshSummaryAvailability()
                    syncRubricNameIfNeeded()
                    #if os(iOS)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isNameFocused = true
                    }
                    #endif
                }
                .appOnChange(of: selectedBlueprintId) { _ in
                    syncBlueprintDefaults()
                    refreshSummaryAvailability()
                    syncRubricNameIfNeeded()
                    if categoryPlacementMode == .existing, selectedCategoryId == nil {
                        selectedCategoryId = suggestedCategoryId
                    }
                }
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            #endif
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 640, minHeight: 560, idealHeight: 620)
    }

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: selectedBlueprint?.icon ?? "tablecells")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tintForSelectedBlueprint)
                .frame(width: 48, height: 48)
                .background(tintForSelectedBlueprint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nueva columna")
                    .font(.title2.weight(.bold))
                Text(selectedBlueprint?.subtitle ?? "Elige el tipo de dato que quieres añadir al cuaderno.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let selectedBlueprint {
                NotebookPill(
                    label: label(for: selectedBlueprint.categoryKind),
                    systemImage: selectedBlueprint.icon,
                    active: true,
                    tint: tintForSelectedBlueprint,
                    compact: true
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func contentLayout(for availableWidth: CGFloat) -> some View {
        let usesTwoColumns = availableWidth >= 720

        if usesTwoColumns {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    columnIdentitySection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                configurationSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                columnIdentitySection
                configurationSection
            }
        }
    }

    private var columnIdentitySection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                NotebookSectionLabel(text: "Configuración")

                TextField((selectedBlueprint?.isIndividualSummary ?? false) ? "Nombre de la síntesis pedagógica" : "Nombre de la columna", text: $columnName)
                    .font(.title2.weight(.bold))
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if canSave {
                            saveColumn()
                        }
                    }

                categorySelector
            }
        }
    }

    private var blueprintSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tipo de columna")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(basicBlueprints) { blueprint in
                        NotebookPill(
                            label: blueprint.title,
                            systemImage: blueprint.icon,
                            active: blueprint.id == selectedBlueprint?.id,
                            tint: color(for: blueprint.categoryKind),
                            compact: true
                        )
                        .onTapGesture {
                            selectedBlueprintId = blueprint.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            DisclosureGroup {
                let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(advancedBlueprints) { blueprint in
                            ColumnBlueprintCard(
                                blueprint: blueprint,
                                isSelected: blueprint.id == selectedBlueprint?.id,
                                tint: color(for: blueprint.categoryKind)
                            ) {
                                selectedBlueprintId = blueprint.id
                            }
                        }
                    }

                    externalColumnDestinations
                }
                .padding(.top, 12)
            } label: {
                Label("Más opciones", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
        }
    }

    private var externalColumnDestinations: some View {
        VStack(alignment: .leading, spacing: 12) {
            externalDestinationCard(
                title: "Asistencia",
                subtitle: "Los estados de asistencia se gestionan desde el módulo Asistencia.",
                icon: "person.badge.clock",
                tint: NotebookStyle.warningTint
            )

            externalDestinationCard(
                title: "Pruebas físicas",
                subtitle: "Crea baterías, asignaciones, marcas y baremos desde EF · Condición física.",
                icon: "figure.run",
                tint: .orange
            )
        }
    }

    private func externalDestinationCard(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NotebookStyle.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.softBorder, lineWidth: 1)
        )
    }

    private var configurationSection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                NotebookSectionLabel(text: (selectedBlueprint?.isIndividualSummary ?? false) ? "Síntesis pedagógica" : "Detalles")

                if selectedBlueprint?.isIndividualSummary == true {
                    individualSummaryConfiguration
                } else {
                    genericConfiguration
                }
            }
        }
    }

    private var genericConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            if selectedBlueprint?.type == .rubric {
                selectedRubricCard
            }

            if selectedBlueprint?.type == .check {
                NotebookChecklistPreviewCard(tint: tintForSelectedBlueprint)
            }

            if shouldShowWeightControls {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Peso")
                            .font(.headline)
                        TextField("0", text: $weight)
                            .appKeyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    Toggle("Cuenta para la media", isOn: $countsTowardAverage)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entrada")
                        .font(.headline)
                    Text(label(for: resolvedInputKind))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            if selectedBlueprint?.type == .calculated {
                NotebookFormulaKeyboard(
                    formula: $formula,
                    availableColumns: availableFormulaColumns
                )
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Unidad / situación de aprendizaje", text: $unitOrSituation)
                        .font(.subheadline.weight(.medium))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    DatePicker("Fecha", selection: $selectedDate, displayedComponents: .date)
                    Toggle("Fijar al inicio", isOn: $isPinned)
                    Toggle("Columna bloqueada", isOn: $isLocked)
                    Toggle("Guardar como plantilla", isOn: $isTemplate)

                    externalDestinationCard(
                        title: "Pruebas físicas",
                        subtitle: "Se gestionan desde EF · Condición física.",
                        icon: "figure.run",
                        tint: .orange
                    )
                }
                .padding(.top, 8)
            } label: {
                Label("Más opciones", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
        }
    }

    private var individualSummaryConfiguration: some View {
        VStack(alignment: .leading, spacing: 24) {
            configurationGroup(
                title: "Fuente de evidencias",
                subtitle: "Define qué columnas nutren cada síntesis."
            ) {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(NotebookIndividualSummaryEvidenceSource.allCases) { option in
                        NotebookConfigurationOptionCard(
                            title: option.title,
                            subtitle: option.subtitle,
                            isSelected: summaryConfiguration.evidenceSource == option,
                            tint: tintForSelectedBlueprint
                        ) {
                            summaryConfiguration.evidenceSource = option
                        }
                    }
                }
            }

            configurationGroup(
                title: "Longitud",
                subtitle: "Ajusta cuánto detalle se conserva en el texto final."
            ) {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(NotebookIndividualSummaryLength.allCases) { option in
                        NotebookConfigurationOptionCard(
                            title: option.title,
                            subtitle: option.subtitle,
                            isSelected: summaryConfiguration.length == option,
                            tint: tintForSelectedBlueprint
                        ) {
                            summaryConfiguration.length = option
                        }
                    }
                }
            }

            configurationGroup(
                title: "Modo de relleno",
                subtitle: "Decide si la síntesis completa solo celdas vacías, regenera o crea una nueva versión."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(NotebookIndividualSummaryGenerationMode.allCases) { option in
                        NotebookConfigurationOptionCard(
                            title: option.title,
                            subtitle: option.subtitle,
                            isSelected: summaryConfiguration.generationMode == option,
                            tint: tintForSelectedBlueprint
                        ) {
                            summaryConfiguration.generationMode = option
                        }
                    }
                }
            }

            Toggle("Fijar al inicio", isOn: $isPinned)
            Toggle("Columna bloqueada", isOn: $isLocked)
            Toggle("Texto editable por el docente", isOn: .constant(true))
                .disabled(true)
            Toggle("Guardar como plantilla", isOn: $isTemplate)
        }
    }

    private var selectedRubricCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rúbrica")
                .font(.headline)

            if let selected = bridge.rubrics.first(where: { $0.rubric.id == selectedRubricId }) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selected.criteria.prefix(4), id: \.criterion.id) { criterion in
                            Text("• \(criterion.criterion.description_)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.rubric.name)
                            .font(.subheadline.weight(.bold))
                        Text("\(selected.criteria.count) criterios")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NotebookStyle.surfaceSoft)
                )
            }

            Picker("Cambiar rúbrica", selection: Binding<Int64>(
                get: { selectedRubricId ?? 0 },
                set: { newValue in
                    selectedRubricId = newValue == 0 ? nil : newValue
                    syncRubricNameIfNeeded()
                }
            )) {
                Text("Selecciona una rúbrica").tag(Int64(0))
                ForEach(bridge.rubrics, id: \.rubric.id) { rubric in
                    Text(rubric.rubric.name).tag(rubric.rubric.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(canSave ? "Lista para crear" : "Completa la configuración")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(canSave ? NotebookStyle.successTint : .secondary)

                    if selectedBlueprint?.isIndividualSummary == true {
                        Text(summaryFooterMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let canSaveReason {
                        Text(canSaveReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Se añadirá al cuaderno actual con la configuración indicada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button(action: saveColumn) {
                    Label(primaryActionTitle, systemImage: "plus.circle.fill")
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
    }

    private func configurationGroup<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ubicación de la columna")
                    .font(.headline)
                Text("La categoría agrupa columnas relacionadas en el cuaderno.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Ubicación", selection: $categoryPlacementMode) {
                ForEach(CategoryPlacementMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if categoryPlacementMode == .existing {
                if availableCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Aún no hay categorías")
                            .font(.headline)
                        Text("Puedes crear una nueva categoría o continuar con una columna sin categoría.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Crear categoría") {
                                categoryPlacementMode = .createNew
                                newCategoryName = defaultSuggestedCategoryName()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Columna sin categoría") {
                                selectedCategoryId = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NotebookStyle.surfaceSoft)
                    )
                } else {
                    Picker("Categoría existente", selection: Binding<String>(
                        get: { selectedCategoryId ?? "__none__" },
                        set: { selectedCategoryId = $0 == "__none__" ? nil : $0 }
                    )) {
                        Text("Sin categoría").tag("__none__")
                        ForEach(availableCategories, id: \.id) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Nombre de la categoría", text: $newCategoryName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill.badge.plus")
                            .foregroundStyle(tintForSelectedBlueprint)
                            .accessibilityHidden(true)
                        Text(resolvedNewCategoryName)
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Capsule(style: .continuous)
                            .fill(tintForSelectedBlueprint.opacity(0.16))
                            .frame(width: 40, height: 16)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(tintForSelectedBlueprint.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tintForSelectedBlueprint.opacity(0.08))
                    )
                }
            }
        }
    }

    private var availableCategories: [NotebookColumnCategory] {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return [] }
        return data.sheet.columnCategories.sorted { $0.order < $1.order }
    }

    private var availableFormulaColumns: [NotebookColumnDefinition] {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return [] }
        let activeTabId = bridge.selectedNotebookTabId ?? data.sheet.tabs.first?.id
        return data.sheet.columns
            .filter { !$0.isHidden }
            .filter { $0.type != .calculated }
            .filter { column in
                guard let activeTabId else { return true }
                return column.tabIds.contains(activeTabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty)
            }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private var canSaveReason: String? {
        guard let selectedBlueprint else {
            return "Selecciona un tipo de columna."
        }
        if resolvedColumnName.isEmpty {
            return "Escribe un nombre para la columna."
        }
        if selectedBlueprint.type == .rubric && selectedRubricId == nil {
            return "Selecciona una rúbrica."
        }
        if selectedBlueprint.type == .calculated {
            let trimmedFormula = formula.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedFormula.isEmpty {
                return "Escribe una fórmula."
            }
            if !trimmedFormula.contains("[") || !trimmedFormula.contains("]") {
                return "Añade al menos una columna usando los botones de referencia."
            }
        }
        if shouldShowWeightControls && parsedWeight == nil {
            return "Revisa el peso de la columna."
        }
        if categoryPlacementMode == .createNew && resolvedNewCategoryName.isEmpty {
            return "Escribe un nombre para la categoría."
        }
        return nil
    }

    private var canSave: Bool {
        canSaveReason == nil
    }

    private var primaryActionTitle: String {
        guard selectedBlueprint?.isIndividualSummary == true else { return "Crear" }
        return summaryAvailability.isAvailable ? "Crear y generar" : "Crear columna"
    }

    private var summaryFooterMessage: String {
        if summaryAvailability.isAvailable {
            return "Se creará una columna editable y después podrás generar una síntesis por alumno."
        }
        return "Apple Intelligence no está disponible en este dispositivo. Podrás rellenarla manualmente."
    }

    private var parsedWeight: Double? {
        let normalized = weight
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Double(normalized), value >= 0 else {
            return nil
        }

        return value
    }

    private var shouldShowWeightControls: Bool {
        guard let selectedBlueprint else { return false }
        return selectedBlueprint.type != .text && !selectedBlueprint.isIndividualSummary
    }

    private var resolvedColumnName: String {
        let trimmed = columnName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return selectedBlueprint?.isIndividualSummary == true ? "Síntesis pedagógica" : ""
        }
        return trimmed
    }

    private var resolvedNewCategoryName: String {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSuggestedCategoryName() : trimmed
    }

    private var tintForSelectedBlueprint: Color {
        color(for: selectedBlueprint?.categoryKind ?? .evaluation)
    }

    private var resolvedInputKind: NotebookCellInputKind {
        selectedBlueprint?.inputKind ?? .text
    }

    private var resolvedScaleKind: NotebookScaleKind {
        selectedBlueprint?.scaleKind ?? .custom
    }

    private var resolvedCountsTowardAverage: Bool {
        guard let selectedBlueprint else { return false }

        if selectedBlueprint.isIndividualSummary {
            return false
        }

        return shouldShowWeightControls && countsTowardAverage
    }

    private func saveColumn() {
        guard let selectedBlueprint else { return }
        lastBlueprintId = selectedBlueprint.id
        if selectedBlueprint.isIndividualSummary {
            saveIndividualSummaryColumn()
            return
        }

        var resolvedCategoryId = categoryPlacementMode == .existing ? selectedCategoryId : nil
        if categoryPlacementMode == .createNew {
            let generatedCategoryId = UUID().uuidString
            bridge.saveColumnCategory(name: resolvedNewCategoryName, categoryId: generatedCategoryId)
            resolvedCategoryId = generatedCategoryId
        }

        bridge.addColumn(
            name: resolvedColumnName,
            type: selectedBlueprint.type.name,
            weight: shouldShowWeightControls ? (parsedWeight ?? selectedBlueprint.defaultWeight) : 0,
            formula: trimmedOrNil(formula),
            rubricId: selectedRubricId,
            categoryId: resolvedCategoryId,
            categoryKind: selectedBlueprint.categoryKind,
            instrumentKind: selectedBlueprint.instrumentKind,
            inputKind: resolvedInputKind,
            dateEpochMs: Int64(selectedDate.timeIntervalSince1970 * 1000),
            unitOrSituation: trimmedOrNil(unitOrSituation),
            competencyCriteriaIds: [],
            scaleKind: resolvedScaleKind,
            iconName: selectedBlueprint.icon,
            countsTowardAverage: resolvedCountsTowardAverage,
            isPinned: isPinned,
            isHidden: false,
            visibility: .visible,
            isLocked: isLocked,
            isTemplate: isTemplate
        )
        dismiss()
    }

    private func refreshSummaryAvailability() {
        guard selectedBlueprint?.isIndividualSummary == true else { return }
        summaryAvailability = summaryAIService.currentAvailability()
    }

    private func saveIndividualSummaryColumn() {
        guard let selectedBlueprint else { return }
        var resolvedCategoryId = categoryPlacementMode == .existing ? selectedCategoryId : nil
        if categoryPlacementMode == .createNew {
            let generatedCategoryId = UUID().uuidString
            bridge.saveColumnCategory(name: resolvedNewCategoryName, categoryId: generatedCategoryId)
            resolvedCategoryId = generatedCategoryId
        }

        let activeTabIds: [String] = bridge.selectedNotebookTabId.map { [$0] } ?? []

        guard let columnId = bridge.createNotebookAICommentColumn(name: resolvedColumnName),
              let data = bridge.notebookState as? NotebookUiStateData,
              let createdColumn = data.sheet.columns.first(where: { $0.id == columnId }) else {
            return
        }

        let updatedColumn = NotebookColumnDefinition(
            id: createdColumn.id,
            title: resolvedColumnName,
            type: .text,
            categoryKind: selectedBlueprint.categoryKind,
            instrumentKind: .privateComment,
            inputKind: .text,
            evaluationId: createdColumn.evaluationId,
            rubricId: createdColumn.rubricId,
            formula: createdColumn.formula,
            weight: 0,
            dateEpochMs: KotlinLong(value: Int64(selectedDate.timeIntervalSince1970 * 1000)),
            unitOrSituation: NotebookIndividualSummaryPreferences.marker,
            competencyCriteriaIds: createdColumn.competencyCriteriaIds,
            scaleKind: .custom,
            tabIds: activeTabIds,
            sessions: createdColumn.sessions,
            sharedAcrossTabs: activeTabIds.isEmpty,
            colorHex: createdColumn.colorHex,
            iconName: "apple.intelligence",
            order: createdColumn.order,
            widthDp: createdColumn.widthDp,
            categoryId: resolvedCategoryId,
            ordinalLevels: createdColumn.ordinalLevels,
            availableIcons: createdColumn.availableIcons,
            countsTowardAverage: false,
            isPinned: isPinned,
            isHidden: false,
            visibility: .visible,
            isLocked: isLocked,
            isTemplate: isTemplate,
            emptyCellPolicy: createdColumn.emptyCellPolicy,
            trace: createdColumn.trace
        )
        bridge.saveColumn(column: updatedColumn)
        NotebookIndividualSummaryPreferences.save(summaryConfiguration, columnId: columnId)
        dismiss()
        onCreatedSummaryColumn?(columnId)
    }

    private func syncBlueprintDefaults() {
        guard let selectedBlueprint else { return }
        weight = String(Int(selectedBlueprint.defaultWeight))
        countsTowardAverage = defaultCountsTowardAverage(for: selectedBlueprint)
        if selectedBlueprint.isIndividualSummary {
            if columnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || columnName == "Comentario IA" {
                columnName = "Síntesis pedagógica"
            }
            if unitOrSituation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unitOrSituation == "Comentario IA" {
                unitOrSituation = NotebookIndividualSummaryPreferences.marker
            }
        }
    }

    private func defaultCountsTowardAverage(for blueprint: NotebookColumnBlueprint) -> Bool {
        if blueprint.isIndividualSummary {
            return false
        }

        switch blueprint.instrumentKind {
        case .writtenTest, .rubric, .checklist, .participation:
            return true
        case .systematicObservation:
            return false
        case .multimediaEvidence, .physicalTest, .privateComment:
            return false
        default:
            return blueprint.defaultWeight > 0
        }
    }

    private func color(for category: NotebookColumnCategoryKind) -> Color {
        switch category {
        case .evaluation:
            return NotebookStyle.primaryTint
        case .followUp:
            return NotebookStyle.successTint
        case .attendance:
            return NotebookStyle.warningTint
        case .extras:
            return .pink
        case .physicalEducation:
            return .orange
        case .custom:
            return .secondary
        default:
            return .secondary
        }
    }

    private func label(for category: NotebookColumnCategoryKind) -> String {
        switch category {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .custom: return "Personalizada"
        default: return "Personalizada"
        }
    }

    private func label(for instrument: NotebookInstrumentKind) -> String {
        switch instrument {
        case .writtenTest: return "Prueba escrita"
        case .rubric: return "Rúbrica"
        case .systematicObservation: return "Observación"
        case .checklist: return "Lista de control"
        case .participation: return "Participación"
        case .physicalTest: return "Prueba física"
        case .multimediaEvidence: return "Evidencia"
        case .privateComment: return "Síntesis pedagógica"
        default: return "Instrumento"
        }
    }

    private func label(for inputKind: NotebookCellInputKind) -> String {
        switch inputKind {
        case .numeric010: return "Numérica 0-10"
        case .rubric: return "Rúbrica"
        case .check: return "Sí / No"
        case .quickSelector: return "Selector rápido"
        case .attendanceStatus: return "Estado de asistencia"
        case .distance: return "Distancia"
        case .evidence: return "Evidencia"
        case .calculated: return "Calculada"
        case .shortNote: return "Observación corta"
        default: return "Texto"
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func syncRubricNameIfNeeded() {
        guard selectedBlueprint?.type == .rubric,
              columnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selectedRubricId,
              let rubric = bridge.rubrics.first(where: { $0.rubric.id == selectedRubricId })
        else { return }

        columnName = rubric.rubric.name
    }

    private var suggestedCategoryId: String? {
        availableCategories.first(where: { $0.name.localizedCaseInsensitiveContains(defaultSuggestedCategoryName()) })?.id
            ?? availableCategories.first(where: { $0.name.localizedCaseInsensitiveContains(label(for: selectedBlueprint?.categoryKind ?? .evaluation)) })?.id
    }

    private func defaultSuggestedCategoryName() -> String {
        switch selectedBlueprint?.categoryKind ?? .evaluation {
        case .evaluation: return "Evaluación"
        case .followUp: return "Seguimiento"
        case .attendance: return "Asistencia"
        case .extras: return "Extras"
        case .physicalEducation: return "EF"
        case .custom: return "Categoría"
        default: return "Categoría"
        }
    }
}
