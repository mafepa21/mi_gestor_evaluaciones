import SwiftUI
import MiGestorKit

struct RubricsBuilderScreen: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var onSaved: ((Int64) -> Void)? = nil
    @State private var saveFeedback: String? = nil

    private var state: RubricUiState? {
        bridge.rubricsUiState
    }

    var body: some View {
        NavigationStack {
            Group {
                if let state {
                    VStack(alignment: .leading, spacing: 16) {
                        RubricBuilderHeader(
                            state: state,
                            rubricName: rubricNameBinding,
                            selectedClassId: selectedClassBinding,
                            selectedTeachingUnitId: selectedTeachingUnitBinding
                        )
                        .environmentObject(bridge)

                        TextEditor(text: instructionsBinding)
                            .frame(height: 88)
                            .padding(8)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: RubricsStyle.blueprintCardRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RubricsStyle.blueprintCardRadius, style: .continuous)
                                    .stroke(RubricsStyle.fieldBorder, lineWidth: 1)
                            )

                        RubricBuilderGridView(state: state)
                            .environmentObject(bridge)
                            .frame(maxHeight: .infinity)

                        Button {
                            bridge.addRubricCriterion()
                        } label: {
                            Label("Añadir Nuevo Criterio", systemImage: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: RubricsStyle.blueprintCardRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        HStack {
                            if state.isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Guardando...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 14))
                                Text(saveFeedback ?? "Guardado")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { @MainActor in
                                    do {
                                        let rubricId = try await bridge.saveRubricFromBuilderReturningId()
                                        saveFeedback = "Rúbrica guardada correctamente"
                                        onSaved?(rubricId)
                                        dismiss()
                                    } catch {
                                        saveFeedback = "Error al guardar"
                                    }
                                }
                            } label: {
                            Label("Guardar Rúbrica", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(contrastingTextColor(for: Color.accentColor))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: RubricsStyle.blueprintCardRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(state.rubricName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isSaving)
                        }
                    }
                    .padding(24)
                } else {
                    ProgressView("Cargando editor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private var rubricNameBinding: Binding<String> {
        Binding(
            get: { bridge.rubricsUiState?.rubricName ?? "" },
            set: { bridge.updateRubricName($0) }
        )
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { bridge.rubricsUiState?.instructions ?? "" },
            set: { bridge.updateRubricInstructions($0) }
        )
    }

    private var selectedClassBinding: Binding<Int64?> {
        Binding(
            get: { bridge.rubricsUiState?.selectedClassId?.int64Value },
            set: { bridge.selectRubricClass($0) }
        )
    }

    private var selectedTeachingUnitBinding: Binding<Int64?> {
        Binding(
            get: { bridge.selectedRubricTeachingUnitId },
            set: { bridge.selectRubricTeachingUnit($0) }
        )
    }
}

private struct RubricBuilderHeader: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    let state: RubricUiState
    let rubricName: Binding<String>
    let selectedClassId: Binding<Int64?>
    let selectedTeachingUnitId: Binding<Int64?>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("¿Cómo se llama esta rúbrica?", text: rubricName)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .textFieldStyle(.plain)

            HStack(spacing: 8) {
                Menu {
                    Button("Ninguna") { selectedClassId.wrappedValue = nil }
                    ForEach(state.allClasses, id: \.id) { schoolClass in
                        Button(schoolClass.name) { selectedClassId.wrappedValue = schoolClass.id }
                    }
                } label: {
                    Label(
                        selectedClassName ?? "+ Asignar clase",
                        systemImage: "person.3.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(appCardBackground(for: colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)

                if selectedClassId.wrappedValue != nil {
                    Menu {
                        Button("Sin SA concreta") { selectedTeachingUnitId.wrappedValue = nil }
                        ForEach(bridge.rubricBuilderTeachingUnits, id: \.id) { unit in
                            Button(unit.name) { selectedTeachingUnitId.wrappedValue = unit.id }
                        }
                    } label: {
                        Label(
                            selectedTeachingUnitName ?? "+ Asignar SA",
                            systemImage: "square.stack.3d.up.fill"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(appCardBackground(for: colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text("Niveles:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(["Estándar", "Binario", "Numérico"], id: \.self) { preset in
                    Button(preset) { bridge.applyRubricPreset(preset) }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(appCardBackground(for: colorScheme).opacity(0.95), in: Capsule())
                        .buttonStyle(.plain)
                }

                Spacer()
                Label(
                    "Peso: \(Int((state.totalWeight * 100).rounded()))%",
                    systemImage: state.totalWeight == 1.0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(state.totalWeight == 1.0 ? Color.green : Color.red)
            }
        }
    }

    private var selectedClassName: String? {
        guard let selectedId = selectedClassId.wrappedValue else { return nil }
        return state.allClasses.first(where: { $0.id == selectedId })?.name
    }

    private var selectedTeachingUnitName: String? {
        guard let selectedId = selectedTeachingUnitId.wrappedValue else { return nil }
        return bridge.rubricBuilderTeachingUnits.first(where: { $0.id == selectedId })?.name
    }
}

private struct RubricBuilderGridView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    let state: RubricUiState

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(in: proxy.size)
            VStack(alignment: .leading, spacing: layout.rowSpacing) {
                headerRow(layout: layout)
                ForEach(Array(state.criteria.enumerated()), id: \.offset) { index, criterion in
                    criterionRow(index: index, criterion: criterion, layout: layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
        }
    }

    private func headerRow(layout: RubricGridLayout) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Criterio / Niveles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: layout.criterionWidth, alignment: .leading)
                .padding(.top, 8)

            ForEach(Array(state.levels.enumerated()), id: \.element.uid) { index, level in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Nivel", text: Binding(
                            get: { level.name },
                            set: { bridge.updateRubricLevelName(at: index, name: $0) }
                        ))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                        Button(role: .destructive) {
                            bridge.removeRubricLevel(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Stepper(value: Binding(
                        get: { Int(level.points) },
                        set: { bridge.updateRubricLevelPoints(at: index, points: $0) }
                    ), in: 0...20) {
                        Text("Pts: \(level.points)")
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(width: layout.levelWidth, alignment: .leading)
            }

            Button {
                bridge.addRubricLevel()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func criterionRow(index: Int, criterion: RubricCriterionState, layout: RubricGridLayout) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Nombre del criterio", text: Binding(
                    get: { criterion.description_ },
                    set: { bridge.updateRubricCriterionDescription(at: index, description: $0) }
                ), axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                Slider(value: Binding(
                    get: { criterion.weight },
                    set: { bridge.updateRubricCriterionWeight(at: index, weight: $0) }
                ), in: 0...1)
                .tint(Color.accentColor)

                Text("\(Int((criterion.weight * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: layout.criterionWidth, alignment: .leading)

            ForEach(state.levels, id: \.uid) { level in
                TextEditor(text: Binding(
                    get: { criterion.levelDescriptions[level.uid] ?? "" },
                    set: { bridge.updateRubricLevelDescription(criterionIndex: index, levelUid: level.uid, description: $0) }
                ))
                .frame(width: layout.levelWidth, height: layout.editorHeight)
                .padding(8)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Button(role: .destructive) {
                bridge.removeRubricCriterion(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.vertical, layout.rowPadding)
    }

    private func makeLayout(in size: CGSize) -> RubricGridLayout {
        let horizontalPadding: CGFloat = 24
        let spacing: CGFloat = 8
        let availableWidth = max(size.width - horizontalPadding, 320)
        let controlsWidth: CGFloat = 48
        let criterionWidth = min(max(availableWidth * 0.26, 176), 256)
        let levelCount = max(state.levels.count, 1)
        let levelsArea = availableWidth - criterionWidth - controlsWidth - (spacing * CGFloat(levelCount + 1))
        let levelWidth = min(max(levelsArea / CGFloat(levelCount), 96), 224)

        let availableHeight = max(size.height - 24, 240)
        let criteriaCount = max(state.criteria.count, 1)
        let headerHeight: CGFloat = 88
        let rowsHeight = max(availableHeight - headerHeight, 120)
        let editorHeight = min(max((rowsHeight / CGFloat(criteriaCount)) - 24, 56), 128)
        let rowPadding = max(min((rowsHeight / CGFloat(criteriaCount) - editorHeight) / 2, 8), 2)

        return RubricGridLayout(
            criterionWidth: criterionWidth,
            levelWidth: levelWidth,
            editorHeight: editorHeight,
            rowSpacing: 8,
            rowPadding: rowPadding
        )
    }
}

private struct RubricGridLayout {
    let criterionWidth: CGFloat
    let levelWidth: CGFloat
    let editorHeight: CGFloat
    let rowSpacing: CGFloat
    let rowPadding: CGFloat
}
