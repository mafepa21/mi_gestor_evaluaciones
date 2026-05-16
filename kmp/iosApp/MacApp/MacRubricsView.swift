import SwiftUI
import AppKit
import MiGestorKit

struct MacRubricsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var selectedRubricId: Int64?
    @State private var selectedFilterClassId: Int64?
    @State private var selectedTeachingUnitId: Int64?
    @State private var selectedStatusFilter = "Todas"
    @State private var searchText = ""
    @State private var expandedGroupKeys: Set<String> = []
    @State private var expandedCriterionIds: Set<Int64> = []
    @State private var teachingUnits: [TeachingUnit] = []
    @State private var usageSummary: KmpBridge.RubricUsageSnapshot?
    @State private var usageLoading = false
    @State private var bulkOptions: [KmpBridge.RubricUsageSnapshot.EvaluationUsage] = []
    @State private var bulkLaunchInFlight = false
    @State private var showingBuilder = false

    private var filteredRubrics: [RubricDetail] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bridge.rubrics.filter { rubric in
            let matchesClass: Bool = {
                guard let selectedFilterClassId else { return true }
                let directClassMatch = rubric.rubric.classId?.int64Value == selectedFilterClassId
                let usageMatch = bridge.rubricClassLinks[rubric.rubric.id]?.contains(selectedFilterClassId) == true
                return directClassMatch || usageMatch
            }()

            let matchesTeachingUnit: Bool = {
                guard let selectedTeachingUnitId else { return true }
                if selectedTeachingUnitId == Int64.min {
                    return rubric.rubric.teachingUnitId == nil
                }
                return rubric.rubric.teachingUnitId?.int64Value == selectedTeachingUnitId
            }()

            let matchesStatus = statusMatches(rubric)

            let matchesQuery = query.isEmpty || [
                rubric.rubric.name,
                rubric.rubric.description_ ?? "",
                className(for: rubric),
                teachingUnitName(for: rubric),
                rubric.criteria.map { $0.criterion.description_ }.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)

            return matchesClass && matchesTeachingUnit && matchesStatus && matchesQuery
        }
        .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    private var selectedRubric: RubricDetail? {
        filteredRubrics.first(where: { $0.rubric.id == selectedRubricId }) ?? filteredRubrics.first
    }

    private var availableStatusFilters: [String] {
        ["Todas", "Vinculadas", "Sin vincular", "Con evaluaciones activas", "Sin uso"]
    }

    private var availableTeachingUnits: [TeachingUnit] {
        let usedIds = Set(bridge.rubrics.compactMap { $0.rubric.teachingUnitId?.int64Value })
        return teachingUnits
            .filter { usedIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var groupedRubrics: [(key: String, title: String, rubrics: [RubricDetail])] {
        let groups = Dictionary(grouping: filteredRubrics) { rubric in
            (rubric.rubric.teachingUnitId?.int64Value).map { "unit-\($0)" } ?? "without-unit"
        }

        return groups.map { key, rubrics in
            let title = rubrics.first.map(teachingUnitName(for:)) ?? "Sin situación asignada"
            return (key: key, title: title, rubrics: rubrics)
        }
        .sorted { lhs, rhs in
            if lhs.key == "without-unit" { return false }
            if rhs.key == "without-unit" { return true }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rúbricas")
                        .font(MacAppStyle.pageTitle)
                    Text("Banco operativo para encontrar, asignar y evaluar rápido.")
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
                    .frame(width: 180)
                }

                Picker("SA", selection: $selectedTeachingUnitId) {
                    Text("Todas las SA").tag(Optional<Int64>.none)
                    ForEach(availableTeachingUnits, id: \.id) { unit in
                        Text(unit.name).tag(Optional(unit.id))
                    }
                    Text("Sin situación asignada").tag(Optional(Int64.min))
                }
                .frame(width: 220)

                Picker("Estado", selection: $selectedStatusFilter) {
                    ForEach(availableStatusFilters, id: \.self) { filter in
                        Text(filter).tag(filter)
                    }
                }
                .frame(width: 190)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 220)

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
                        .frame(minWidth: 400, idealWidth: 480, maxWidth: 560)
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
            await reloadTeachingUnits()
            ensureExpandedGroups()
        }
        .appOnChange(of: selectedFilterClassId) { newValue in
            bridge.setRubricFilterClass(newValue)
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task {
                await reloadUsageSummary()
                await reloadTeachingUnits()
                ensureExpandedGroups()
            }
        }
        .appOnChange(of: selectedTeachingUnitId) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: selectedStatusFilter) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: searchText) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: bridge.rubrics.count) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
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
                Text("Banco")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(filteredRubrics.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MacAppStyle.innerPadding)
            .padding(.vertical, 12)
            .background(MacAppStyle.subtleFill)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedRubrics, id: \.key) { group in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedGroupKeys.contains(group.key) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedGroupKeys.insert(group.key)
                                    } else {
                                        expandedGroupKeys.remove(group.key)
                                    }
                                }
                            )
                        ) {
                            VStack(spacing: 0) {
                                ForEach(group.rubrics, id: \.rubric.id) { rubric in
                                    rubricRow(rubric)
                                    Divider()
                                        .padding(.leading, MacAppStyle.innerPadding)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            HStack {
                                Text(group.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(group.rubrics.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, MacAppStyle.innerPadding)
                            .padding(.vertical, 8)
                        }
                        .disclosureGroupStyle(.automatic)
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

    private func rubricRow(_ rubric: RubricDetail) -> some View {
        Button {
            selectedRubricId = rubric.rubric.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(rubric.rubric.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    MacStatusPill(
                        label: rubricStateLabel(for: rubric),
                        isActive: rubricStateLabel(for: rubric) != "Sin uso",
                        tint: rubricStateTint(for: rubric)
                    )
                }

                Text("\(className(for: rubric)) · \(teachingUnitName(for: rubric))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(rubric.criteria.count) criterios")
                    Text("\(levelCount(for: rubric)) niveles")
                    Text("\(linkedClassIds(for: rubric).count) clases")
                    if evaluationCountEstimate(for: rubric) > 0 {
                        Text("\(evaluationCountEstimate(for: rubric)) eval.")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MacAppStyle.innerPadding)
            .padding(.vertical, 12)
            .background(
                selectedRubricId == rubric.rubric.id
                    ? Color.accentColor.opacity(0.10)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rubricDetailPanel: some View {
        if let rubric = selectedRubric {
            ScrollView {
                VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                    inspectorHeader(for: rubric)

                    usageLine(for: rubric)

                    notebookUsageBlock(for: rubric)

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
                        Text("Criterios")
                            .font(MacAppStyle.sectionTitle)
                        ForEach(rubric.criteria, id: \.criterion.id) { item in
                            MacRubricCriterionSummary(
                                item: item,
                                isExpanded: Binding(
                                    get: { expandedCriterionIds.contains(item.criterion.id) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedCriterionIds.insert(item.criterion.id)
                                        } else {
                                            expandedCriterionIds.remove(item.criterion.id)
                                        }
                                    }
                                )
                            )
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

    private func inspectorHeader(for rubric: RubricDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(rubric.rubric.name)
                    .font(.title2.weight(.semibold))
                Text("\(className(for: rubric)) · \(teachingUnitName(for: rubric)) · \(formattedDate(for: rubric))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let description = rubric.rubric.description_,
                   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(description)
                        .font(MacAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                primaryActionButton(for: rubric)
                Menu {
                    Button {
                        bridge.loadRubricForEditing(rubric)
                        showingBuilder = true
                    } label: {
                        Label("Editar", systemImage: "square.and.pencil")
                    }

                    Button {
                        bridge.startAssignRubric(rubric.rubric)
                    } label: {
                        Label("Asignar a clase", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button {
                        Task { await openBulkEvaluationFlow(for: rubric) }
                    } label: {
                        Label("Evaluación masiva", systemImage: "square.grid.3x3")
                    }
                    .disabled((usageSummary?.evaluationCount ?? 0) == 0 || bulkLaunchInFlight)

                    Divider()

                    Button(role: .destructive) {
                        bridge.deleteRubric(id: rubric.rubric.id)
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                } label: {
                    Label("Más", systemImage: "ellipsis.circle")
                }
                .menuStyle(.button)
            }
        }
    }

    @ViewBuilder
    private func primaryActionButton(for rubric: RubricDetail) -> some View {
        let linkedCount = linkedClassIds(for: rubric).count
        let evaluationCount = usageSummary?.rubricId == rubric.rubric.id ? usageSummary?.evaluationCount ?? 0 : evaluationCountEstimate(for: rubric)

        if linkedCount == 0 {
            Button {
                bridge.startAssignRubric(rubric.rubric)
            } label: {
                Label("Asignar al cuaderno", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderedProminent)
        } else if evaluationCount > 0 {
            Button {
                Task { await openBulkEvaluationFlow(for: rubric) }
            } label: {
                if bulkLaunchInFlight {
                    Label("Abriendo…", systemImage: "hourglass")
                } else {
                    Label(evaluationCount > 1 ? "Continuar evaluación" : "Evaluar grupo", systemImage: "square.grid.3x3")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(bulkLaunchInFlight)
        } else {
            Button {
                bridge.startAssignRubric(rubric.rubric)
            } label: {
                Label("Completar vínculo", systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func usageLine(for rubric: RubricDetail) -> some View {
        HStack(spacing: 8) {
            MacStatusPill(label: "\(rubric.criteria.count) criterios", isActive: true, tint: MacAppStyle.infoTint)
            MacStatusPill(label: "\(levelCount(for: rubric)) niveles", isActive: true, tint: MacAppStyle.infoTint)
            MacStatusPill(label: "\(usageSummary?.classCount ?? linkedClassIds(for: rubric).count) clases", isActive: true, tint: MacAppStyle.successTint)
            MacStatusPill(label: "\(usageSummary?.evaluationCount ?? evaluationCountEstimate(for: rubric)) evaluaciones", isActive: (usageSummary?.evaluationCount ?? evaluationCountEstimate(for: rubric)) > 0, tint: MacAppStyle.warningTint)
        }
    }

    private func notebookUsageBlock(for rubric: RubricDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Uso en Cuaderno")
                    .font(MacAppStyle.sectionTitle)
                Spacer()
                MacStatusPill(
                    label: rubricStateLabel(for: rubric),
                    isActive: rubricStateLabel(for: rubric) != "Sin uso",
                    tint: rubricStateTint(for: rubric)
                )
            }

            if usageLoading {
                ProgressView()
            } else if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                ForEach(usageSummary.evaluationUsages.prefix(4), id: \.evaluationId) { usage in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(usage.evaluationName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(usage.className) · \(usage.evaluationType)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Peso \(String(format: "%.1f", usage.weight))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                Text(linkedClassIds(for: rubric).isEmpty ? "Sin columna o evaluación vinculada todavía." : "Asignada a clase, pendiente de evaluación activa.")
                    .font(MacAppStyle.bodyText)
                    .foregroundStyle(.secondary)
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
    private func reloadTeachingUnits() async {
        teachingUnits = (try? await bridge.plannerTeachingUnits(for: selectedFilterClassId)) ?? []
    }

    private func ensureExpandedGroups() {
        let keys = Set(groupedRubrics.map(\.key))
        if expandedGroupKeys.isEmpty {
            expandedGroupKeys = keys
        } else {
            expandedGroupKeys = expandedGroupKeys.intersection(keys).union(keys.subtracting(expandedGroupKeys))
        }
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

    private func linkedClassIds(for rubric: RubricDetail) -> Set<Int64> {
        var ids = bridge.rubricClassLinks[rubric.rubric.id] ?? []
        if let classId = rubric.rubric.classId?.int64Value {
            ids.insert(classId)
        }
        return ids
    }

    private func evaluationCountEstimate(for rubric: RubricDetail) -> Int {
        if usageSummary?.rubricId == rubric.rubric.id {
            return usageSummary?.evaluationCount ?? 0
        }
        return bridge.evaluationsInClass.filter { $0.rubricId?.int64Value == rubric.rubric.id }.count
    }

    private func levelCount(for rubric: RubricDetail) -> Int {
        rubric.criteria.map { $0.levels.count }.max() ?? 0
    }

    private func statusMatches(_ rubric: RubricDetail) -> Bool {
        let linkedCount = linkedClassIds(for: rubric).count
        let evaluationCount = evaluationCountEstimate(for: rubric)
        switch selectedStatusFilter {
        case "Vinculadas":
            return linkedCount > 0
        case "Sin vincular", "Sin uso":
            return linkedCount == 0 && evaluationCount == 0
        case "Con evaluaciones activas":
            return evaluationCount > 0
        default:
            return true
        }
    }

    private func rubricStateLabel(for rubric: RubricDetail) -> String {
        let linkedCount = linkedClassIds(for: rubric).count
        let evaluationCount = evaluationCountEstimate(for: rubric)
        if evaluationCount > 0 { return "En evaluación" }
        if linkedCount > 0 { return "Asignada" }
        if rubric.rubric.classId == nil && rubric.rubric.teachingUnitId == nil { return "Plantilla" }
        return "Sin uso"
    }

    private func rubricStateTint(for rubric: RubricDetail) -> Color {
        switch rubricStateLabel(for: rubric) {
        case "En evaluación":
            return MacAppStyle.warningTint
        case "Asignada":
            return MacAppStyle.successTint
        case "Plantilla":
            return MacAppStyle.infoTint
        default:
            return .secondary
        }
    }

    private func className(for rubric: RubricDetail) -> String {
        if let classId = rubric.rubric.classId?.int64Value,
           let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
            return schoolClass.name
        }
        return "Sin clase asociada"
    }

    private func teachingUnitName(for rubric: RubricDetail) -> String {
        guard let teachingUnitId = rubric.rubric.teachingUnitId?.int64Value else {
            return "Sin situación asignada"
        }
        return teachingUnits.first(where: { $0.id == teachingUnitId })?.name ?? "SA #\(teachingUnitId)"
    }

    private func formattedDate(for rubric: RubricDetail) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(rubric.rubric.trace.updatedAt.epochSeconds))
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct MacRubricCriterionSummary: View {
    let item: RubricCriterionWithLevels
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                ForEach(item.levels.sorted(by: { $0.order < $1.order }), id: \.id) { level in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        HStack {
                            Text(level.name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(Int(level.points)) pts")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(MacAppStyle.infoTint)
                        }

                        if let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.criterion.description_)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text("Peso \(Int((item.criterion.weight * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
