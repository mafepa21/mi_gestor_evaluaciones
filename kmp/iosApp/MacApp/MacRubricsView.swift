import SwiftUI
import AppKit
import MiGestorKit

struct MacRubricsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var selectedRubricId: Int64?
    @State private var selectedFilterClassId: Int64?
    @State private var usageSummary: KmpBridge.RubricUsageSnapshot?
    @State private var usageLoading = false
    @State private var bulkOptions: [KmpBridge.RubricUsageSnapshot.EvaluationUsage] = []
    @State private var bulkLaunchInFlight = false
    @State private var showingBuilder = false

    private var filteredRubrics: [RubricDetail] {
        bridge.rubrics.filter { rubric in
            guard let selectedFilterClassId else { return true }
            return rubric.rubric.classId?.int64Value == selectedFilterClassId
        }
    }

    private var selectedRubric: RubricDetail? {
        filteredRubrics.first(where: { $0.rubric.id == selectedRubricId }) ?? filteredRubrics.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rúbricas")
                        .font(MacAppStyle.pageTitle)
                    Text("Workspace Mac con banco, detalle e impacto evaluativo.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !bridge.classes.isEmpty {
                    Picker("Clase", selection: $selectedFilterClassId) {
                        Text("Todas").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .frame(width: 220)
                }
                Button {
                    bridge.resetRubricBuilder()
                    showingBuilder = true
                } label: {
                    Label("Nueva rúbrica", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if bridge.rubrics.isEmpty {
                ContentUnavailableView(
                    "Sin rúbricas",
                    systemImage: "checklist",
                    description: Text("Aún no hay rúbricas cargadas en el bridge.")
                )
            } else {
                HStack(alignment: .top, spacing: MacAppStyle.sectionSpacing) {
                    rubricsTable
                        .frame(minWidth: 430, idealWidth: 520, maxWidth: 620)
                    rubricDetailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(MacAppStyle.pagePadding)
        .task {
            if selectedRubricId == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            await reloadUsageSummary()
        }
        .appOnChange(of: selectedFilterClassId) { newValue in
            bridge.setRubricFilterClass(newValue)
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: bridge.rubrics.count) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: selectedRubricId) { _ in
            Task { await reloadUsageSummary() }
        }
        .confirmationDialog(
            "Elegir evaluación masiva",
            isPresented: Binding(
                get: { !bulkOptions.isEmpty },
                set: { if !$0 { bulkOptions = [] } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(bulkOptions, id: \.evaluationId) { usage in
                Button("\(usage.className) · \(usage.evaluationName)") {
                    openBulkEvaluation(for: usage)
                }
            }
            Button("Cancelar", role: .cancel) {
                bulkOptions = []
            }
        } message: {
            Text("Selecciona la clase y evaluación que quieres abrir.")
        }
        .sheet(isPresented: $showingBuilder) {
            RubricsBuilderScreen()
                .environmentObject(bridge)
                .frame(minWidth: 1200, minHeight: 820)
        }
        .sheet(
            isPresented: Binding(
                get: { bridge.rubricsUiState?.assignDialogState != nil },
                set: { visible in
                    if !visible {
                        bridge.dismissAssignRubricDialog()
                    }
                }
            )
        ) {
            AssignRubricToTabView()
                .environmentObject(bridge)
                .frame(minWidth: 640, minHeight: 520)
        }
        .sheet(
            isPresented: Binding(
                get: { bridge.showingBulkRubricEvaluation },
                set: { visible in
                    if !visible {
                        bridge.closeBulkRubricEvaluation()
                    }
                }
            )
        ) {
            RubricBulkEvaluationSheet(bridge: bridge)
                .environmentObject(bridge)
                .frame(minWidth: 1320, minHeight: 860)
        }
    }

    private var rubricsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nombre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Criterios")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Text("Uso")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.horizontal, MacAppStyle.innerPadding)
            .padding(.vertical, 10)
            .background(MacAppStyle.subtleFill)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRubrics, id: \.rubric.id) { rubric in
                        Button {
                            selectedRubricId = rubric.rubric.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rubric.rubric.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(className(for: rubric))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(rubric.criteria.count)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                MacStatusPill(
                                    label: usageLabel(for: rubric),
                                    isActive: usageCount(for: rubric) > 0,
                                    tint: usageCount(for: rubric) > 0 ? MacAppStyle.infoTint : .secondary
                                )
                                .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, MacAppStyle.innerPadding)
                            .padding(.vertical, 12)
                            .background(
                                selectedRubricId == rubric.rubric.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
            }
        }
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var rubricDetailPanel: some View {
        if let rubric = selectedRubric {
            ScrollView {
                VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rubric.rubric.name)
                            .font(.title2.weight(.semibold))
                        Text("\(className(for: rubric)) · \(formattedDate(for: rubric))")
                            .foregroundStyle(.secondary)
                        if let description = rubric.rubric.description_, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: MacAppStyle.cardSpacing) {
                        MacMetricCard(label: "Criterios", value: "\(rubric.criteria.count)", systemImage: "list.bullet.rectangle")
                        MacMetricCard(label: "Clases", value: "\(usageSummary?.classCount ?? 0)", systemImage: "rectangle.3.group")
                        MacMetricCard(label: "Evaluaciones", value: "\(usageSummary?.evaluationCount ?? 0)", systemImage: "chart.bar.doc.horizontal")
                        MacMetricCard(label: "Uso", value: usageLabel(for: rubric), systemImage: "checklist")
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await openBulkEvaluationFlow(for: rubric) }
                        } label: {
                            if bulkLaunchInFlight {
                                Label("Abriendo…", systemImage: "hourglass")
                            } else {
                                Label("Evaluación masiva", systemImage: "square.grid.3x3")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((usageSummary?.evaluationCount ?? 0) == 0 || bulkLaunchInFlight)

                        Button {
                            bridge.loadRubricForEditing(rubric)
                            showingBuilder = true
                        } label: {
                            Label("Abrir vista de edición", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            bridge.startAssignRubric(rubric.rubric)
                        } label: {
                            Label("Asignar a clase", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            bridge.deleteRubric(id: rubric.rubric.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Impacto evaluativo")
                            .font(MacAppStyle.sectionTitle)
                        if usageLoading {
                            ProgressView()
                        } else if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                            Text("Esta rúbrica está vinculada a \(usageSummary.evaluationCount) evaluación(es) en \(usageSummary.classCount) clase(s).")
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)

                            MacFlowLayout(spacing: 8) {
                                ForEach(usageSummary.linkedClassNames, id: \.self) { className in
                                    MacStatusPill(label: className, isActive: true, tint: MacAppStyle.infoTint)
                                }
                            }

                            VStack(spacing: 8) {
                                ForEach(usageSummary.evaluationUsages.prefix(6), id: \.evaluationId) { usage in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(usage.evaluationName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(usage.className) · \(usage.evaluationType) · Peso \(String(format: "%.1f", usage.weight))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(MacAppStyle.cardBackground)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                                            .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                                }
                            }
                        } else {
                            Text("Todavía no hay evaluaciones activas enlazadas a esta rúbrica.")
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Criterios y niveles")
                            .font(MacAppStyle.sectionTitle)
                        ForEach(rubric.criteria, id: \.criterion.id) { item in
                            MacRubricCriterionCard(item: item)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Selecciona una rúbrica",
                systemImage: "checklist",
                description: Text("El detalle mostrará criterios, niveles y acceso a evaluación masiva.")
            )
        }
    }

    @MainActor
    private func reloadUsageSummary() async {
        guard let rubricId = selectedRubric?.rubric.id else {
            usageSummary = nil
            return
        }
        usageLoading = true
        defer { usageLoading = false }
        usageSummary = try? await bridge.loadRubricUsage(rubricId: rubricId)
    }

    @MainActor
    private func openBulkEvaluationFlow(for rubric: RubricDetail) async {
        guard let usageSummary else { return }
        if usageSummary.evaluationUsages.count == 1 {
            bulkLaunchInFlight = true
            defer { bulkLaunchInFlight = false }
            _ = await bridge.launchBulkRubricEvaluationFromRubric(
                rubricId: rubric.rubric.id,
                preferredClassId: rubric.rubric.classId?.int64Value
            )
        } else {
            bulkOptions = usageSummary.evaluationUsages
        }
    }

    private func openBulkEvaluation(for usage: KmpBridge.RubricUsageSnapshot.EvaluationUsage) {
        bulkOptions = []
        Task { @MainActor in
            bulkLaunchInFlight = true
            defer { bulkLaunchInFlight = false }
            _ = await bridge.launchBulkRubricEvaluationFromUsage(
                rubricId: selectedRubric?.rubric.id ?? usageSummary?.rubricId ?? 0,
                classId: usage.classId,
                evaluationId: usage.evaluationId
            )
        }
    }

    private func usageCount(for rubric: RubricDetail) -> Int {
        if usageSummary?.rubricId == rubric.rubric.id {
            return usageSummary?.evaluationCount ?? 0
        }
        return (bridge.rubricClassLinks[rubric.rubric.id] ?? []).isEmpty ? 0 : 1
    }

    private func usageLabel(for rubric: RubricDetail) -> String {
        let count = usageCount(for: rubric)
        switch count {
        case 0: return "Sin uso"
        case 1: return "1 eval."
        default: return "\(count) evals."
        }
    }

    private func className(for rubric: RubricDetail) -> String {
        if let classId = rubric.rubric.classId?.int64Value,
           let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
            return schoolClass.name
        }
        return "Sin clase asociada"
    }

    private func formattedDate(for rubric: RubricDetail) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(rubric.rubric.trace.updatedAt.epochSeconds))
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct MacRubricCriterionCard: View {
    let item: RubricCriterionWithLevels

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.criterion.description_)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                MacStatusPill(
                    label: "Peso \(Int((item.criterion.weight * 100).rounded()))%",
                    isActive: true,
                    tint: MacAppStyle.infoTint
                )
            }

            VStack(spacing: 10) {
                ForEach(item.levels.sorted(by: { $0.order < $1.order }), id: \.id) { level in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(level.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(Int(level.points)) pts")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MacAppStyle.infoTint)
                        }

                        if let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 800
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: maxWidth,
            height: currentY + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

