import SwiftUI
import MiGestorKit

// MARK: - Column Editor
struct WeightEditorSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let column: NotebookColumnDefinition
    @State private var weight: String
    @State private var width: String
    @State private var order: String
    @State private var colorHex: String
    @State private var selectedTabIds: Set<String>

    private let palette: [String] = ["#4A90D9", "#2D9CDB", "#27AE60", "#F2994A", "#EB5757", "#9B51E0", "#111827", "#F4B400"]

    init(column: NotebookColumnDefinition) {
        self.column = column
        _weight = State(initialValue: String(format: "%.1f", column.weight))
        _width = State(initialValue: String(format: "%.0f", column.widthDp > 0 ? column.widthDp : 132.0))
        _order = State(initialValue: String(column.order >= 0 ? column.order : 0))
        _colorHex = State(initialValue: column.colorHex ?? "#4A90D9")
        _selectedTabIds = State(initialValue: Set(column.tabIds))
    }

    var body: some View {
        let accentText = contrastingTextColor(for: colorHex)

        NavigationStack {
            ZStack {
                EvaluationBackdrop()

                ScrollView {
                    VStack(spacing: NotebookStyle.sectionSpacing) {
                        VStack(spacing: NotebookStyle.stackSpacing) {
                            ZStack {
                                RoundedRectangle(cornerRadius: NotebookStyle.cardRadius, style: .continuous)
                                    .fill(Color(hex: colorHex).opacity(0.14))
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 32, weight: .regular))
                                    .foregroundColor(accentText)
                            }
                            .frame(width: 80, height: 80)
                            Text(column.title)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                            Text("Ajusta peso, ancho, orden, color y pestañas asociadas de esta columna.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.top, 40)

                        columnTabsSection

                        settingCard(title: "Peso (%)") {
                            TextField("0.0", text: $weight)
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .appKeyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 16)
                        }

                        settingCard(title: "Ancho (dp)") {
                            VStack(alignment: .leading, spacing: NotebookStyle.controlSpacing) {
                                Slider(value: Binding(
                                    get: { Double(width.replacingOccurrences(of: ",", with: ".")) ?? 132.0 },
                                    set: { width = String(format: "%.0f", $0) }
                                ), in: 96...260, step: 8)
                                Text(width + " dp")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }

                        settingCard(title: "Orden") {
                            TextField("0", text: $order)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .appKeyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 16)
                        }

                        settingCard(title: "Color") {
                            FlowLayout(spacing: NotebookStyle.controlSpacing) {
                                ForEach(palette, id: \.self) { hex in
                                    Button {
                                        colorHex = hex
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle().stroke(colorHex == hex ? Color.primary : Color.clear, lineWidth: 3)
                                            )
                                    }
                                }
                            }
                        }

                        Button(action: saveWeight) {
                            Text("Actualizar columna")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: colorHex))
                                .clipShape(RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Hecho") { saveWeight() }.fontWeight(.bold) }
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancelar") { dismiss() } }
            }
        }
    }
    private func saveWeight() {
        let weightValue = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? column.weight
        let widthValue = Double(width.replacingOccurrences(of: ",", with: ".")) ?? (column.widthDp > 0 ? column.widthDp : 132.0)
        let orderValue = Int32(order.trimmingCharacters(in: .whitespacesAndNewlines)) ?? column.order
        let updated = NotebookColumnDefinition(
            id: column.id,
            title: column.title,
            type: column.type,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            evaluationId: column.evaluationId,
            rubricId: column.rubricId,
            formula: column.formula,
            weight: weightValue,
            dateEpochMs: column.dateEpochMs,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds,
            scaleKind: column.scaleKind,
            tabIds: selectedTabIds.isEmpty ? column.tabIds : Array(selectedTabIds).sorted(),
            sessions: column.sessions,
            sharedAcrossTabs: selectedTabIds.count > 1,
            colorHex: colorHex,
            iconName: column.iconName,
            order: orderValue,
            widthDp: widthValue,
            categoryId: column.categoryId,
            ordinalLevels: column.ordinalLevels,
            availableIcons: column.availableIcons,
            countsTowardAverage: column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: column.isHidden,
            visibility: column.visibility,
            isLocked: column.isLocked,
            isTemplate: column.isTemplate,
            emptyCellPolicy: column.emptyCellPolicy,
            trace: column.trace
        )
        bridge.saveColumn(column: updated)
        dismiss()
    }

    @ViewBuilder
    private var columnTabsSection: some View {
        if let data = bridge.notebookState as? NotebookUiStateData, !data.sheet.tabs.isEmpty {
            settingCard(title: "Pestañas") {
                FlowLayout(spacing: NotebookStyle.controlSpacing) {
                    ForEach(data.sheet.tabs, id: \.id) { tab in
                        let isSelected = selectedTabIds.contains(tab.id)
                        Button {
                            if isSelected {
                                selectedTabIds.remove(tab.id)
                            } else {
                                selectedTabIds.insert(tab.id)
                            }
                        } label: {
                            NotebookPill(
                                label: tab.title,
                                active: isSelected,
                                tint: NotebookStyle.primaryTint,
                                compact: true
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surface, padding: NotebookStyle.stackSpacing) {
            VStack(alignment: .leading, spacing: NotebookStyle.controlSpacing) {
                NotebookSectionLabel(text: title)
                content()
            }
        }
        .padding(.horizontal, 24)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}
