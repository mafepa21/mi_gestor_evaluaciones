import SwiftUI
import MiGestorKit

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
}

private struct ColumnBlueprintCard: View {
    let blueprint: NotebookColumnBlueprint
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let selectedForeground = contrastingTextColor(for: NotebookStyle.primaryTint)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: blueprint.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedForeground : NotebookStyle.primaryTint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(blueprint.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? selectedForeground : .primary)
                    Text(blueprint.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? selectedForeground.opacity(0.82) : .secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? NotebookStyle.primaryTint : NotebookStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? NotebookStyle.primaryTint : NotebookStyle.softBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AddColumnSheet: View {
    @ObservedObject var bridge: KmpBridge
    var initialCategoryId: String? = nil
    var startsCreatingCategory: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var columnName: String = ""
    @State private var selectedBlueprintId: String = "written_test"
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

    private let blueprints: [NotebookColumnBlueprint] = [
        .init(id: "written_test", title: "Prueba escrita", subtitle: "Nota numérica 0-10", icon: "doc.text.magnifyingglass", type: .numeric, categoryKind: .evaluation, instrumentKind: .writtenTest, inputKind: .numeric010, scaleKind: .tenPoint, defaultWeight: 10),
        .init(id: "rubric", title: "Rúbrica", subtitle: "Mini rúbrica emergente", icon: "checklist", type: .rubric, categoryKind: .evaluation, instrumentKind: .rubric, inputKind: .rubric, scaleKind: .tenPoint, defaultWeight: 15),
        .init(id: "checklist", title: "Lista de control", subtitle: "Sí / No rápido", icon: "checkmark.square", type: .check, categoryKind: .evaluation, instrumentKind: .checklist, inputKind: .check, scaleKind: .yesNo, defaultWeight: 5),
        .init(id: "observation", title: "Observación", subtitle: "Nota corta con inspector", icon: "note.text", type: .text, categoryKind: .followUp, instrumentKind: .systematicObservation, inputKind: .shortNote, scaleKind: .custom, defaultWeight: 0),
        .init(id: "participation", title: "Participación", subtitle: "Selector rápido por chips", icon: "person.2.wave.2", type: .ordinal, categoryKind: .followUp, instrumentKind: .participation, inputKind: .quickSelector, scaleKind: .achievement, defaultWeight: 5),
        .init(id: "attendance", title: "Asistencia", subtitle: "Presente, ausente o retraso", icon: "person.badge.clock", type: .attendance, categoryKind: .attendance, instrumentKind: .systematicObservation, inputKind: .attendanceStatus, scaleKind: .custom, defaultWeight: 0),
        .init(id: "physical_test", title: "Prueba física", subtitle: "Tiempo, distancia o repeticiones", icon: "figure.run", type: .numeric, categoryKind: .physicalEducation, instrumentKind: .physicalTest, inputKind: .distance, scaleKind: .distance, defaultWeight: 10),
        .init(id: "evidence", title: "Evidencia", subtitle: "Archivo o multimedia", icon: "paperclip.circle", type: .text, categoryKind: .extras, instrumentKind: .multimediaEvidence, inputKind: .evidence, scaleKind: .custom, defaultWeight: 0),
        .init(id: "calculated", title: "Cálculo automático", subtitle: "Media o fórmula", icon: "function", type: .calculated, categoryKind: .evaluation, instrumentKind: .custom, inputKind: .calculated, scaleKind: .tenPoint, defaultWeight: 0),
    ]

    private var selectedBlueprint: NotebookColumnBlueprint {
        blueprints.first(where: { $0.id == selectedBlueprintId }) ?? blueprints[0]
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    columnIdentitySection
                    blueprintSection
                    configurationSection
                    footerActions
                }
                .padding(24)
            }
            .background(EvaluationBackdrop())
            .navigationTitle("Nueva columna")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear {
                selectedCategoryId = initialCategoryId ?? selectedCategoryId ?? suggestedCategoryId
                categoryPlacementMode = startsCreatingCategory ? .createNew : .existing
            }
            .onChange(of: selectedBlueprintId) { _ in
                weight = String(Int(selectedBlueprint.defaultWeight))
                if categoryPlacementMode == .existing, selectedCategoryId == nil {
                    selectedCategoryId = suggestedCategoryId
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configura una columna como pieza del cuaderno, no como un simple dato suelto.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                NotebookPill(label: label(for: selectedBlueprint.categoryKind), systemImage: "square.grid.2x2", active: true, tint: color(for: selectedBlueprint.categoryKind), compact: true)
                NotebookPill(label: label(for: selectedBlueprint.instrumentKind), systemImage: selectedBlueprint.icon, active: false, tint: color(for: selectedBlueprint.categoryKind), compact: true)
            }
        }
    }

    private var columnIdentitySection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                NotebookSectionLabel(text: "Identidad")
                TextField("Nombre de la columna", text: $columnName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                TextField("Unidad / situación de aprendizaje", text: $unitOrSituation)
                    .font(.system(size: 15, weight: .medium, design: .rounded))

                DatePicker("Fecha", selection: $selectedDate, displayedComponents: .date)

                categorySelector
            }
        }
    }

    private var blueprintSection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                NotebookSectionLabel(text: "Instrumento")
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(blueprints) { blueprint in
                        ColumnBlueprintCard(blueprint: blueprint, isSelected: blueprint.id == selectedBlueprintId) {
                            selectedBlueprintId = blueprint.id
                        }
                    }
                }
            }
        }
    }

    private var configurationSection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 18) {
                NotebookSectionLabel(text: "Configuración")

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Peso")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        TextField("0", text: $weight)
                            .appKeyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Entrada")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(label(for: selectedBlueprint.inputKind))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if selectedBlueprint.type == .calculated {
                    TextField("Fórmula", text: $formula)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                if selectedBlueprint.type == .rubric {
                    Picker("Rúbrica", selection: Binding<Int64>(
                        get: { selectedRubricId ?? 0 },
                        set: { selectedRubricId = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Selecciona una rúbrica").tag(Int64(0))
                        ForEach(bridge.rubrics, id: \.rubric.id) { rubric in
                            Text(rubric.rubric.name).tag(rubric.rubric.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Cuenta para la media", isOn: $countsTowardAverage)
                Toggle("Fijar al inicio", isOn: $isPinned)
                Toggle("Columna bloqueada", isOn: $isLocked)
                Toggle("Guardar como plantilla", isOn: $isTemplate)
            }
        }
    }

    private var footerActions: some View {
        Button(action: saveColumn) {
            Text("Crear columna")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(contrastingTextColor(for: canSave ? color(for: selectedBlueprint.categoryKind) : .gray))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(canSave ? color(for: selectedBlueprint.categoryKind) : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ubicación de la columna")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("La categoría agrupa columnas relacionadas en el cuaderno.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aún no hay categorías")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Puedes crear una nueva categoría o continuar con una columna sin categoría.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
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
                    .padding(14)
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
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Nombre de la categoría", text: $newCategoryName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill.badge.plus")
                            .foregroundStyle(color(for: selectedBlueprint.categoryKind))
                        Text(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultSuggestedCategoryName() : newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Spacer()
                        Capsule(style: .continuous)
                            .fill(color(for: selectedBlueprint.categoryKind).opacity(0.16))
                            .frame(width: 42, height: 18)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(color(for: selectedBlueprint.categoryKind).opacity(0.4), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(color(for: selectedBlueprint.categoryKind).opacity(0.08))
                    )
                }
            }
        }
    }

    private var availableCategories: [NotebookColumnCategory] {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return [] }
        return data.sheet.columnCategories.sorted { $0.order < $1.order }
    }

    private var canSave: Bool {
        if columnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if selectedBlueprint.type == .rubric && selectedRubricId == nil { return false }
        if selectedBlueprint.type == .calculated && formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if categoryPlacementMode == .createNew && resolvedNewCategoryName.isEmpty { return false }
        return true
    }

    private func saveColumn() {
        var resolvedCategoryId = categoryPlacementMode == .existing ? selectedCategoryId : nil
        if categoryPlacementMode == .createNew {
            let generatedCategoryId = "cat_\(Int64(Date().timeIntervalSince1970 * 1000))"
            bridge.saveColumnCategory(name: resolvedNewCategoryName, categoryId: generatedCategoryId)
            resolvedCategoryId = generatedCategoryId
        }

        bridge.addColumn(
            name: columnName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: selectedBlueprint.type.name,
            weight: Double(weight.replacingOccurrences(of: ",", with: ".")) ?? selectedBlueprint.defaultWeight,
            formula: trimmedOrNil(formula),
            rubricId: selectedRubricId,
            categoryId: resolvedCategoryId,
            categoryKind: selectedBlueprint.categoryKind,
            instrumentKind: selectedBlueprint.instrumentKind,
            inputKind: selectedBlueprint.inputKind,
            dateEpochMs: Int64(selectedDate.timeIntervalSince1970 * 1000),
            unitOrSituation: trimmedOrNil(unitOrSituation),
            competencyCriteriaIds: [],
            scaleKind: selectedBlueprint.scaleKind,
            iconName: selectedBlueprint.icon,
            countsTowardAverage: countsTowardAverage,
            isPinned: isPinned,
            isHidden: false,
            visibility: .visible,
            isLocked: isLocked,
            isTemplate: isTemplate
        )
        dismiss()
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
        default: return "Instrumento"
        }
    }

    private func label(for inputKind: NotebookCellInputKind) -> String {
        switch inputKind {
        case .numeric010: return "Numérica 0-10"
        case .rubric: return "Rúbrica"
        case .check: return "Check"
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

    private var resolvedNewCategoryName: String {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSuggestedCategoryName() : trimmed
    }

    private var suggestedCategoryId: String? {
        availableCategories.first(where: { $0.name.localizedCaseInsensitiveContains(defaultSuggestedCategoryName()) })?.id
            ?? availableCategories.first(where: { $0.name.localizedCaseInsensitiveContains(label(for: selectedBlueprint.categoryKind)) })?.id
    }

    private func defaultSuggestedCategoryName() -> String {
        switch selectedBlueprint.categoryKind {
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
