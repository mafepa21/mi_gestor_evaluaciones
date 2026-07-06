import SwiftUI
import MiGestorKit

struct RubricsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onOpenBuilder: () -> Void
    let onEditRubric: (RubricDetail) -> Void
    var peMode = false

    @State var searchText = ""
    @State var selectedFilter = "Todas"
    @State var selectedTeachingUnitId: Int64?
    @State var selectedRubricId: Int64?
    @State var usageSummary: KmpBridge.RubricUsageSnapshot?
    @State var teachingUnits: [TeachingUnit] = []
    @State var expandedGroupKeys: Set<String> = []
    @State var expandedCriterionIds: Set<Int64> = []

    var availableFilters: [String] {
        ["Todas", "Vinculadas", "Sin vincular", "Con evaluaciones activas", "Sin uso"]
    }

    var baseRubrics: [RubricDetail] {
        let source = bridge.rubrics
        guard peMode else { return source }
        return source.filter { detail in
            let haystack = "\(detail.rubric.name) \(detail.rubric.description_ ?? "")".lowercased()
            return haystack.contains("ef")
                || haystack.contains("educación física")
                || (bridge.rubricClassLinks[detail.rubric.id]?.contains(selectedClassId ?? -1) ?? false)
        }
    }

    var filteredRubrics: [RubricDetail] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return baseRubrics.filter { detail in
            let linkedClasses = bridge.rubricClassLinks[detail.rubric.id] ?? []
            let directClassId = detail.rubric.classId?.int64Value
            let matchesClass = selectedClassId == nil
                || directClassId == selectedClassId
                || linkedClasses.contains(selectedClassId ?? -1)
            let matchesTeachingUnit: Bool = {
                guard let selectedTeachingUnitId else { return true }
                if selectedTeachingUnitId == Int64.min {
                    return detail.rubric.teachingUnitId == nil
                }
                return detail.rubric.teachingUnitId?.int64Value == selectedTeachingUnitId
            }()
            let matchesFilter: Bool = {
                let activeEvaluations = evaluationCountEstimate(for: detail)
                switch selectedFilter {
                case "Vinculadas":
                    return !linkedClasses.isEmpty
                case "Sin vincular":
                    return linkedClasses.isEmpty
                case "Con evaluaciones activas":
                    return activeEvaluations > 0
                case "Sin uso":
                    return linkedClasses.isEmpty && activeEvaluations == 0
                default:
                    return true
                }
            }()

            let matchesQuery = query.isEmpty || [
                detail.rubric.name,
                detail.rubric.description_ ?? "",
                className(for: detail),
                teachingUnitName(for: detail),
                detail.criteria.map { sanitizeDomainText($0.criterion.description, fallback: "criterio") }.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)

            return matchesClass && matchesTeachingUnit && matchesFilter && matchesQuery
        }
        .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    var selectedRubric: RubricDetail? {
        filteredRubrics.first(where: { $0.rubric.id == selectedRubricId }) ?? baseRubrics.first(where: { $0.rubric.id == selectedRubricId })
    }

    var rubricMetrics: (total: Int, linked: Int, avgCriteria: Double) {
        let total = filteredRubrics.count
        let linked = filteredRubrics.filter { !(bridge.rubricClassLinks[$0.rubric.id] ?? []).isEmpty }.count
        let avg = filteredRubrics.isEmpty ? 0 : Double(filteredRubrics.map { $0.criteria.count }.reduce(0, +)) / Double(filteredRubrics.count)
        return (total, linked, avg)
    }

    var availableTeachingUnits: [TeachingUnit] {
        let usedIds = Set(baseRubrics.compactMap { $0.rubric.teachingUnitId?.int64Value })
        return teachingUnits
            .filter { usedIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var groupedRubrics: [(key: String, title: String, rubrics: [RubricDetail])] {
        let groups = Dictionary(grouping: filteredRubrics) { detail in
            (detail.rubric.teachingUnitId?.int64Value).map { "unit-\($0)" } ?? "without-unit"
        }
        return groups.map { key, rubrics in
            (key: key, title: rubrics.first.map(teachingUnitName(for:)) ?? "Sin situación asignada", rubrics: rubrics)
        }
        .sorted { lhs, rhs in
            if lhs.key == "without-unit" { return false }
            if rhs.key == "without-unit" { return true }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar rúbrica, criterio o descripción…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        WorkspaceCompactStat(title: "Rúbricas", value: "\(rubricMetrics.total)", tint: EvaluationDesign.accent)
                        WorkspaceCompactStat(title: "Vinculadas", value: "\(rubricMetrics.linked)", tint: EvaluationDesign.success)
                        WorkspaceCompactStat(title: "Criterios", value: String(format: "%.1f", rubricMetrics.avgCriteria), tint: IOSAppStyle.warning)
                        WorkspaceCompactStat(title: "Situaciones", value: "\(availableTeachingUnits.count)", tint: .purple)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            rubricFilterControls

                            Spacer()

                            Button {
                                onOpenBuilder()
                            } label: {
                                Label("Nueva rúbrica", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            rubricFilterControls

                            Button {
                                onOpenBuilder()
                            } label: {
                                Label("Nueva rúbrica", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(24)

                List {
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
                            ForEach(group.rubrics, id: \.rubric.id) { rubric in
                                rubricListRow(rubric)
                            }
                        } label: {
                            HStack {
                                Text(group.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(group.rubrics.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 380)

            Color.clear.frame(width: 8)

            Group {
                if let rubric = selectedRubric {
                    let presentation = rubricPresentation(rubric)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            WorkspaceInspectorHero(
                                title: presentation.title,
                                subtitle: "\(className(for: rubric)) · \(teachingUnitName(for: rubric))"
                            )

                            HStack(spacing: 16) {
                                primaryActionButton(for: rubric)
                                Menu {
                                    Button("Editar", systemImage: "square.and.pencil") {
                                        onEditRubric(rubric)
                                    }
                                    Button("Asignar a clase", systemImage: "rectangle.portrait.and.arrow.right") {
                                        bridge.startAssignRubric(rubric.rubric)
                                    }
                                    Button("Evaluación masiva", systemImage: "square.grid.3x3") {
                                        Task { await openBulkEvaluation(for: rubric) }
                                    }
                                    Button("Eliminar", systemImage: "trash", role: .destructive) {
                                        bridge.deleteRubric(id: rubric.rubric.id)
                                    }
                                } label: {
                                    Label("Más", systemImage: "ellipsis.circle")
                                }
                                .buttonStyle(.bordered)
                            }

                            compactUsageLine(for: rubric)

                            notebookUsageBlock(for: rubric)

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Criterios")
                                    .font(.headline)
                                ForEach(presentation.criteria) { item in
                                    rubricCriterionSummary(item)
                                }
                            }

                            if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Impacto evaluativo")
                                        .font(.headline)
                                    WorkspaceDetailBlock(
                                        title: "Resumen",
                                        content: "Esta rúbrica está vinculada a \(usageSummary.evaluationCount) evaluación(es) en \(usageSummary.classCount) clase(s)."
                                    )
                                    ForEach(Array(usageSummary.evaluationUsages.prefix(6))) { usage in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(usage.evaluationName)
                                                .font(.subheadline.weight(.bold))
                                            Text("\(usage.className) · \(usage.evaluationType) · Peso \(String(format: "%.1f", usage.weight))")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(16)
                                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            } else {
                                WorkspaceDetailBlock(
                                    title: "Impacto evaluativo",
                                    content: "Todavía no hay evaluaciones activas enlazadas a esta rúbrica."
                                )
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 24) {
                        WorkspaceEmptyState(
                            title: peMode ? "Selecciona una rúbrica EF" : "Selecciona una rúbrica",
                            subtitle: peMode
                                ? "Crea o reutiliza rúbricas EF para seguridad, ejecución, cooperación y fair play."
                                : "El banco de rúbricas centraliza criterios, clases vinculadas y acceso directo a evaluación."
                        )
                        HStack(spacing: 16) {
                            Button(peMode ? "Nueva rúbrica EF" : "Nueva rúbrica") {
                                onOpenBuilder()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Ver uso evaluativo") {
                                onOpenModule(.evaluationHub, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task {
            if selectedRubricId == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            await reloadUsageSummary()
            await reloadTeachingUnits()
            ensureExpandedGroups()
        }
        .appOnChange(of: selectedClassId) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task {
                await reloadUsageSummary()
                await reloadTeachingUnits()
            }
        }
        .appOnChange(of: selectedFilter) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: searchText) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: selectedTeachingUnitId) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            ensureExpandedGroups()
            Task { await reloadUsageSummary() }
        }
        .appOnChange(of: selectedRubricId) { _ in
            Task { await reloadUsageSummary() }
        }
    }

    private var rubricFilterControls: some View {
        HStack(spacing: 12) {
            Picker("Curso", selection: $selectedClassId) {
                Text("Todas").tag(Optional<Int64>.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(schoolClass.name).tag(Optional(schoolClass.id))
                }
            }
            .pickerStyle(.menu)

            Picker("SA", selection: $selectedTeachingUnitId) {
                Text("Todas las SA").tag(Optional<Int64>.none)
                ForEach(availableTeachingUnits, id: \.id) { unit in
                    Text(unit.name).tag(Optional(unit.id))
                }
                Text("Sin SA").tag(Optional(Int64.min))
            }
            .pickerStyle(.menu)

            Picker("Filtro", selection: $selectedFilter) {
                ForEach(availableFilters, id: \.self) { filter in
                    Text(filter).tag(filter)
                }
            }
            .pickerStyle(.menu)
        }
    }

    func rubricListRow(_ rubric: RubricDetail) -> some View {
        Button {
            selectedRubricId = rubric.rubric.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(rubric.rubric.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    WorkspaceTag(text: rubricStateLabel(for: rubric), systemImage: rubricStateIcon(for: rubric))
                }
                Text("\(className(for: rubric)) · \(teachingUnitName(for: rubric))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(rubric.criteria.count) criterios · \(levelCount(for: rubric)) niveles · \(linkedClassIds(for: rubric).count) clases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .appInteractiveHighlight()
    }

    @ViewBuilder
    func primaryActionButton(for rubric: RubricDetail) -> some View {
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
                Task { await openBulkEvaluation(for: rubric) }
            } label: {
                Label(evaluationCount > 1 ? "Continuar evaluación" : "Evaluar grupo", systemImage: "square.grid.3x3")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                bridge.startAssignRubric(rubric.rubric)
            } label: {
                Label("Completar vínculo", systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    func compactUsageLine(for rubric: RubricDetail) -> some View {
        WorkspaceFlowLayout(spacing: 8) {
            WorkspaceTag(text: "\(rubric.criteria.count) criterios", systemImage: "list.bullet.rectangle")
            WorkspaceTag(text: "\(levelCount(for: rubric)) niveles", systemImage: "chart.bar.xaxis")
            WorkspaceTag(text: "\(usageSummary?.classCount ?? linkedClassIds(for: rubric).count) clases", systemImage: "rectangle.3.group")
            WorkspaceTag(text: "\(usageSummary?.evaluationCount ?? evaluationCountEstimate(for: rubric)) evaluaciones", systemImage: "chart.bar.doc.horizontal")
        }
    }

    func notebookUsageBlock(for rubric: RubricDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Uso en Cuaderno")
                    .font(.headline)
                Spacer()
                WorkspaceTag(text: rubricStateLabel(for: rubric), systemImage: rubricStateIcon(for: rubric))
            }

            if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                ForEach(Array(usageSummary.evaluationUsages.prefix(4))) { usage in
                    Button {
                        Task { await openBulkEvaluation(for: usage, rubric: rubric) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(usage.evaluationName)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("\(usage.className) · \(usage.evaluationType)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Peso \(String(format: "%.1f", usage.weight))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Label("Evaluar", systemImage: "square.grid.3x3")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(EvaluationDesign.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .appInteractiveHighlight()
                    .padding(16)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Evaluar \(usage.evaluationName) en \(usage.className)")
                }
            } else {
                WorkspaceDetailBlock(
                    title: "Cuaderno",
                    content: linkedClassIds(for: rubric).isEmpty ? "Sin vínculo activo. Asigna la rúbrica para crear uso en clase." : "Asignada a clase, pendiente de evaluación activa."
                )
            }
        }
    }

    func rubricCriterionSummary(_ item: RubricInspectorModel.CriterionModel) -> some View {
        let background = appCardBackground(for: colorScheme)
        return DisclosureGroup(
            isExpanded: Binding(
                get: { expandedCriterionIds.contains(item.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedCriterionIds.insert(item.id)
                    } else {
                        expandedCriterionIds.remove(item.id)
                    }
                }
            )
        ) {
            WorkspaceFlowLayout(spacing: 8) {
                ForEach(Array(item.levels.enumerated()), id: \.offset) { _, level in
                    WorkspaceTag(text: level, systemImage: "checkmark.circle")
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Spacer()
                WorkspaceTag(text: "Peso \(item.weightText)", systemImage: "scalemass")
            }
        }
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    @MainActor
    func reloadUsageSummary() async {
        guard let rubricId = selectedRubric?.rubric.id else {
            usageSummary = nil
            return
        }
        usageSummary = try? await bridge.loadRubricUsage(rubricId: rubricId)
    }

    @MainActor
    func reloadTeachingUnits() async {
        teachingUnits = (try? await bridge.plannerTeachingUnits(for: selectedClassId)) ?? []
    }

    @MainActor
    func openBulkEvaluation(for rubric: RubricDetail) async {
        let opened = await bridge.launchBulkRubricEvaluationFromRubric(
            rubricId: rubric.rubric.id,
            preferredClassId: selectedClassId
        )
        if !opened {
            onOpenModule(.evaluationHub, selectedClassId, nil)
        }
    }

    @MainActor
    func openBulkEvaluation(for usage: KmpBridge.RubricUsageSnapshot.EvaluationUsage, rubric: RubricDetail) async {
        let opened = await bridge.launchBulkRubricEvaluationFromUsage(
            rubricId: rubric.rubric.id,
            classId: usage.classId,
            evaluationId: usage.evaluationId
        )
        if !opened {
            onOpenModule(.evaluationHub, usage.classId, nil)
        }
    }

    func ensureExpandedGroups() {
        expandedGroupKeys = Set(groupedRubrics.map(\.key))
    }

    func linkedClassIds(for rubric: RubricDetail) -> Set<Int64> {
        var ids = bridge.rubricClassLinks[rubric.rubric.id] ?? []
        if let classId = rubric.rubric.classId?.int64Value {
            ids.insert(classId)
        }
        return ids
    }

    func evaluationCountEstimate(for rubric: RubricDetail) -> Int {
        if usageSummary?.rubricId == rubric.rubric.id {
            return usageSummary?.evaluationCount ?? 0
        }
        return bridge.evaluationsInClass.filter { $0.rubricId?.int64Value == rubric.rubric.id }.count
    }

    func levelCount(for rubric: RubricDetail) -> Int {
        rubric.criteria.map { $0.levels.count }.max() ?? 0
    }

    func className(for rubric: RubricDetail) -> String {
        if let classId = rubric.rubric.classId?.int64Value,
           let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
            return schoolClass.name
        }
        let linked = linkedClassIds(for: rubric)
        if linked.count == 1,
           let classId = linked.first,
           let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
            return schoolClass.name
        }
        if linked.count > 1 {
            return "\(linked.count) clases"
        }
        return "Sin clase asociada"
    }

    func teachingUnitName(for rubric: RubricDetail) -> String {
        guard let teachingUnitId = rubric.rubric.teachingUnitId?.int64Value else {
            return "Sin situación asignada"
        }
        return teachingUnits.first(where: { $0.id == teachingUnitId })?.name ?? "SA #\(teachingUnitId)"
    }

    func rubricStateLabel(for rubric: RubricDetail) -> String {
        let linkedCount = linkedClassIds(for: rubric).count
        let evaluationCount = evaluationCountEstimate(for: rubric)
        if evaluationCount > 0 { return "En evaluación" }
        if linkedCount > 0 { return "Asignada" }
        if rubric.rubric.classId == nil && rubric.rubric.teachingUnitId == nil { return "Plantilla" }
        return "Sin uso"
    }

    func rubricStateIcon(for rubric: RubricDetail) -> String {
        switch rubricStateLabel(for: rubric) {
        case "En evaluación":
            return "clock.badge.checkmark"
        case "Asignada":
            return "checkmark.circle"
        case "Plantilla":
            return "doc.on.doc"
        default:
            return "circle"
        }
    }
}

struct ReportsWorkspaceView: View {
    enum ReportTerm: String, CaseIterable, Identifiable {
        case first = "1er Trimestre"
        case second = "2º Trimestre"
        case third = "3er Trimestre"

        var id: String { rawValue }
    }

    enum WorkspaceSurface: String, CaseIterable, Identifiable {
        case reports
        case analytics

        var id: String { rawValue }
    }

    enum AnalyticsMode: String, CaseIterable, Identifiable {
        case dashboards
        case askAI

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboards: return "Dashboards"
            case .askAI: return "Pregunta a la IA"
            }
        }
    }

    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?

    @State var activeSurface: WorkspaceSurface = .reports
    @State var preview: KmpBridge.ReportPreviewPayload?
    @State var reportContext: KmpBridge.ReportGenerationContext?
    @State var selectedReportKind: KmpBridge.ReportKind = .groupOverview
    @State var selectedReportTerm: ReportTerm = .first
    @State var aiAudience: AIReportAudience = .docente
    @State var aiTone: AIReportTone = .claro
    @State var aiAvailability: AIReportAvailabilityState = .unavailable("Comprobando disponibilidad…")
    @State var aiDraft: AIReportDraft?
    @State var aiMetadata: AppleAIGenerationMetadata?
    @State var editableDraftText = ""
    @State var previewDraftText = ""
    @State var isReportPreviewPresented = false
    @State var aiFeedbackMessage: String?
    @State var isGeneratingAIDraft = false
    @State var refinePrompt = ""
    @State var isRefiningAIDraft = false
    @State var isBulkLomloeSheetPresented = false

    @State var analyticsMode: AnalyticsMode = .dashboards
    @State var analyticsAvailability: AIAnalyticsAvailabilityState = .unavailable("Comprobando disponibilidad…")
    @State var selectedAnalyticsRange: KmpBridge.AnalyticsTimeRange = .last30Days
    @State var selectedChartKind: KmpBridge.ChartKind = .attendanceTrend
    @State var analyticsDashboards: [KmpBridge.ChartFacts] = []
    @State var queriedAnalyticsFacts: KmpBridge.ChartFacts?
    @State var analyticsInsight: AIChartInsight?
    @State var analyticsMetadata: AppleAIGenerationMetadata?
    @State var analyticsPrompt = ""
    @State var analyticsFeedbackMessage: String?
    @State var isGeneratingAnalyticsInsight = false
    @State var isResolvingAnalyticsPrompt = false

    let aiOrchestrator = AppleAIOrchestrator()

    var selectedClass: SchoolClass? {
        guard let selectedClassId else { return nil }
        return bridge.classes.first(where: { $0.id == selectedClassId })
    }

    var selectedStudent: Student? {
        guard let selectedStudentId else { return nil }
        let source = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        return source.first(where: { $0.id == selectedStudentId })
    }

    var reportMetrics: (students: Int, evaluations: Int, rubrics: Int) {
        let studentCount = bridge.studentsInClass.count
        let evaluations = bridge.evaluationsInClass.count
        let rubricIds = Set(bridge.evaluationsInClass.compactMap { $0.rubricId?.int64Value })
        return (studentCount, evaluations, rubricIds.count)
    }

    var shareableReportText: String {
        let trimmedDraft = editableDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty {
            return trimmedDraft
        }
        return preview?.previewText ?? "Sin informe disponible."
    }

    var canGenerateAIDraft: Bool {
        guard !isGeneratingAIDraft else { return false }
        guard let reportContext, reportContext.hasEnoughData else { return false }
        return !selectedReportKind.requiresStudentSelection || selectedStudent != nil
    }

    var currentAnalyticsFacts: KmpBridge.ChartFacts? {
        if analyticsMode == .askAI, let queriedAnalyticsFacts {
            return queriedAnalyticsFacts
        }
        return analyticsDashboards.first(where: { $0.chartKind == selectedChartKind })
    }

    var canAskAnalyticsAI: Bool {
        !(analyticsPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                sidebar

                Color.clear.frame(width: 8)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appPageBackground(for: colorScheme))
            }

            VStack(spacing: 0) {
                sidebar
                    .frame(maxHeight: 440)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appPageBackground(for: colorScheme))
            }
        }
        .background(appPageBackground(for: colorScheme))
        .task {
            refreshAvailability()
            await refreshWorkspaceContext()
        }
        .appOnChange(of: selectedClassId) { _ in
            Task { await refreshWorkspaceContext() }
        }
        .appOnChange(of: selectedStudentId) { _ in
            Task { await reloadPreview() }
        }
        .appOnChange(of: selectedReportKind) { _ in
            if selectedReportKind == .lomloeEvaluationComment {
                aiAudience = .familia
                aiTone = .formal
            }
            Task { await reloadPreview() }
        }
        .appOnChange(of: selectedReportTerm) { _ in
            Task { await reloadPreview() }
        }
        .appOnChange(of: selectedAnalyticsRange) { _ in
            Task { await reloadAnalyticsDashboards() }
        }
        .appOnChange(of: analyticsMode) { _ in
            analyticsInsight = nil
            analyticsFeedbackMessage = nil
        }
        .appOnChange(of: selectedChartKind) { _ in
            analyticsInsight = nil
        }
        .sheet(isPresented: $isBulkLomloeSheetPresented) {
            if let selectedClassId {
                BulkLOMLOEGenerationSheet(
                    bridge: bridge,
                    classId: selectedClassId,
                    termLabel: selectedReportTerm.rawValue,
                    audience: aiAudience,
                    tone: aiTone
                )
            }
        }
        .sheet(isPresented: $isReportPreviewPresented) {
            AppleAIPreviewSheet(
                title: selectedReportKind.title,
                subtitle: "Revisa el borrador antes de aplicarlo al informe.",
                text: $previewDraftText,
                metadata: aiMetadata
            ) {
                editableDraftText = previewDraftText
                aiMetadata?.audit.teacherEdited = false
                aiFeedbackMessage = "Borrador aplicado. Revísalo y edítalo antes de compartir."
            }
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Superficie", selection: $activeSurface) {
                    Text("Informes").tag(WorkspaceSurface.reports)
                    Text("Analítica IA").tag(WorkspaceSurface.analytics)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    WorkspaceCompactStat(title: "Alumnado", value: "\(reportMetrics.students)", tint: .blue)
                    WorkspaceCompactStat(
                        title: activeSurface == .reports ? "Evaluaciones" : "Gráficos",
                        value: activeSurface == .reports ? "\(reportMetrics.evaluations)" : "\(analyticsDashboards.count)",
                        tint: .orange
                    )
                    WorkspaceCompactStat(
                        title: activeSurface == .reports ? "Rúbricas" : "IA",
                        value: activeSurface == .reports ? "\(reportMetrics.rubrics)" : (analyticsAvailability.isAvailable ? "On" : "Off"),
                        tint: .green
                    )
                    WorkspaceCompactStat(
                        title: "Superficie",
                        value: activeSurface == .reports ? "Doc" : "IA",
                        tint: EvaluationDesign.accent
                    )
                }
            }
            .padding(24)

            List {
                if activeSurface == .reports {
                    reportsSidebarSections
                } else {
                    analyticsSidebarSections
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 336, idealWidth: 360, maxWidth: 384)
        .background(appMutedCardBackground(for: colorScheme))
    }

    @ViewBuilder
    var reportsSidebarSections: some View {
        Section("Informes disponibles") {
            ForEach(KmpBridge.ReportKind.allCases) { kind in
                reportButton(kind: kind)
            }
        }

        Section("Contexto actual") {
            currentContextSection
        }

        Section("Redacción IA") {
            LabeledContent("Estado") {
                Text(reportGenerationState.title)
                    .foregroundStyle(reportGenerationState.tint)
            }

            if selectedReportKind == .lomloeEvaluationComment {
                Picker("Trimestre", selection: $selectedReportTerm) {
                    ForEach(ReportTerm.allCases) { term in
                        Text(term.rawValue).tag(term)
                    }
                }
            }

            Picker("Audiencia", selection: $aiAudience) {
                ForEach(AIReportAudience.allCases) { audience in
                    Text(audience.title).tag(audience)
                }
            }

            Picker("Tono", selection: $aiTone) {
                ForEach(AIReportTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }

            if let reportContext {
                LabeledContent("Datos") {
                    Text(reportContext.hasEnoughData ? "Suficientes" : "Insuficientes")
                        .foregroundStyle(reportContext.hasEnoughData ? .green : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    var analyticsSidebarSections: some View {
        Section("Analítica visual") {
            Picker("Modo", selection: $analyticsMode) {
                ForEach(AnalyticsMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Periodo", selection: $selectedAnalyticsRange) {
                ForEach(KmpBridge.AnalyticsTimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
        }

        Section("Contexto actual") {
            currentContextSection
        }

        Section("Dashboards") {
            ForEach(KmpBridge.ChartKind.allCases) { kind in
                Button {
                    analyticsMode = .dashboards
                    selectedChartKind = kind
                    analyticsInsight = nil
                    queriedAnalyticsFacts = nil
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(kind.title, systemImage: kind.systemImage)
                                .font(.headline)
                            Spacer()
                            if selectedChartKind == kind && analyticsMode == .dashboards {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(kind.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .appInteractiveHighlight()
            }
        }

        Section("IA local") {
            LabeledContent("Estado") {
                Text(analyticsGenerationState.title)
                    .foregroundStyle(analyticsGenerationState.tint)
            }
            Text(analyticsAvailability.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var currentContextSection: some View {
        if let selectedClass {
            LabeledContent("Clase") {
                Text(selectedClass.name)
            }
        } else {
            Text("Selecciona una clase para trabajar con informes o analítica.")
                .foregroundStyle(.secondary)
        }

        if let selectedStudent {
            LabeledContent("Alumno") {
                Text("\(selectedStudent.firstName) \(selectedStudent.lastName)")
            }
        } else {
            LabeledContent("Alumno") {
                Text("Sin selección")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var detail: AnyView {
        if activeSurface == .reports {
            return AnyView(reportsDetail)
        } else {
            return AnyView(analyticsDetail)
        }
    }

    @ViewBuilder
    var reportsDetail: some View {
        if let preview {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WorkspaceInspectorHero(title: selectedReportKind.title, subtitle: preview.className)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                        WorkspaceMetricCard(title: "Tipo", value: selectedReportKind.title, systemImage: selectedReportKind.systemImage)
                        WorkspaceMetricCard(
                            title: "Generado",
                            value: preview.generatedAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "clock.badge.checkmark"
                        )
                        WorkspaceMetricCard(
                            title: "Destino",
                            value: selectedStudent.map { "\($0.firstName) \($0.lastName)" } ?? preview.className,
                            systemImage: selectedStudent == nil ? "rectangle.3.group" : "person.fill"
                        )
                        ForEach(reportContext?.metrics ?? []) { metric in
                            WorkspaceMetricCard(title: metric.title, value: metric.value, systemImage: metric.systemImage)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parámetros")
                            .font(.headline)
                        WorkspaceDetailBlock(title: "Descripción", content: selectedReportKind.subtitle)
                        WorkspaceDetailBlock(title: "Contexto", content: reportContextDescription)
                        if let reportContext, !reportContext.curriculumReferences.isEmpty {
                            WorkspaceDetailBlock(title: "Referencias curriculares", content: reportContext.curriculumReferences.joined(separator: ", "))
                        }
                        if let dataQualityNote = reportContext?.dataQualityNote {
                            WorkspaceDetailBlock(title: "Calidad de datos", content: dataQualityNote)
                        }
                        if let trends = reportContext?.trends {
                            let trendText = "Trayectoria \(trends.trendDirection == "UPWARD" ? "ascendente" : trends.trendDirection == "DOWNWARD" ? "descendente" : "estable"). Cobertura LOMLOE: \(IosFormatting.decimal(from: trends.curriculumCoveragePct))%. Asistencia: \(IosFormatting.decimal(from: trends.attendanceRate))%."
                            WorkspaceDetailBlock(title: "Auditoría de Tendencias IA", content: trendText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Redacción IA")
                                    .font(.headline)
                                Text("Borrador generado en local. Revisión docente obligatoria antes de compartir.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AppleAIStatusBadge(state: reportGenerationState, message: aiMetadata?.availabilityMessage ?? aiAvailability.message)
                            Button {
                                Task { await generateAIDraft() }
                            } label: {
                                if isGeneratingAIDraft {
                                    ProgressView()
                                } else {
                                    Label("Generar borrador", systemImage: "apple.intelligence")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canGenerateAIDraft)

                            if selectedReportKind == .lomloeEvaluationComment {
                                Button {
                                    isBulkLomloeSheetPresented = true
                                } label: {
                                    Label("Generar lote", systemImage: "person.3.sequence.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedClassId == nil)
                        }
                    }

                        AppleAIAuditSummaryView(metadata: aiMetadata)
                        WorkspaceDetailBlock(title: "Disponibilidad", content: aiMetadata?.availabilityMessage ?? aiAvailability.message)

                        if let aiFeedbackMessage {
                            WorkspaceDetailBlock(title: "Estado de la generación", content: aiFeedbackMessage)
                        }

                        if let aiDraft {
                            WorkspaceDetailBlock(title: "Resumen IA", content: aiDraft.summary)
                        } else if selectedReportKind.requiresStudentSelection && selectedStudent == nil {
                            WorkspaceDetailBlock(title: "IA pendiente", content: "Selecciona un alumno para generar un borrador individual con Foundation Models.")
                        } else {
                            WorkspaceDetailBlock(title: "IA pendiente", content: "Configura audiencia y tono, luego genera un borrador editable.")
                        }

                        TextEditor(text: $editableDraftText)
                            .font(.system(.body, design: .default))
                            .frame(minHeight: 260)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .appOnChange(of: editableDraftText) { _ in
                                if aiDraft != nil, !isGeneratingAIDraft {
                                    aiMetadata?.audit.teacherEdited = true
                                }
                            }

                        if aiDraft != nil {
                            HStack(alignment: .top, spacing: 10) {
                                TextField("Refinar: más breve, más cálido, foco en orientaciones...", text: $refinePrompt, axis: .vertical)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .lineLimit(2, reservesSpace: true)
                                Button {
                                    Task { await refineAIDraft() }
                                } label: {
                                    if isRefiningAIDraft {
                                        ProgressView()
                                    } else {
                                        Label("Refinar", systemImage: "wand.and.stars")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isRefiningAIDraft || refinePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    ShareLink(item: shareableReportText) {
                        Label("Compartir informe revisado", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Vista clásica")
                            .font(.headline)
                        Text(preview.previewText)
                            .font(.system(.body, design: .monospaced))
                            .padding(18)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(24)
            }
        } else {
            WorkspaceEmptyState(
                title: "Genera una vista previa",
                subtitle: "El módulo de informes reutiliza el `ReportService` y lo eleva a una superficie iPad propia."
            )
        }
    }

    @ViewBuilder
    var analyticsDetail: some View {
        if selectedClassId == nil {
            WorkspaceEmptyState(
                title: "Selecciona una clase",
                subtitle: "La analítica visual necesita un grupo activo para comparar asistencia, incidencias y medias."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            WorkspaceInspectorHero(
                                title: analyticsMode == .dashboards ? "Dashboards" : "Pregunta a la IA",
                                subtitle: selectedClass?.name ?? "Sin clase"
                            )
                            Text("La app calcula y dibuja los gráficos; la IA local los interpreta y ayuda a elegir la vista cuando está disponible.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AppleAIStatusBadge(state: analyticsGenerationState, message: analyticsMetadata?.availabilityMessage ?? analyticsAvailability.message)
                        if let facts = currentAnalyticsFacts {
                            Button {
                                Task { await generateAnalyticsInsight(for: facts) }
                            } label: {
                                if isGeneratingAnalyticsInsight {
                                    ProgressView()
                                } else {
                                    Label("Generar insight IA", systemImage: "apple.intelligence")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!facts.hasEnoughData || isGeneratingAnalyticsInsight)
                        }
                    }

                    if analyticsMode == .askAI {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Consulta libre")
                                .font(.headline)
                            TextField("Ej.: compárame 2º ESO A y B en asistencia y faltas de equipación este trimestre", text: $analyticsPrompt, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(3, reservesSpace: true)

                            HStack(spacing: 10) {
                                ForEach([
                                    "Comparar grupos del mismo curso",
                                    "Detectar alertas de asistencia",
                                    "Ver incidencias por semana",
                                    "Ranking de medias"
                                ], id: \.self) { suggestion in
                                    Button(suggestion) {
                                        analyticsPrompt = suggestion
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            HStack {
                                Button {
                                    Task { await runAnalyticsQuery() }
                                } label: {
                                    if isResolvingAnalyticsPrompt {
                                        ProgressView()
                                    } else {
                                        Label("Generar gráfico", systemImage: "wand.and.stars")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canAskAnalyticsAI || isResolvingAnalyticsPrompt)

                                Text(analyticsAvailability.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(18)
                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if let facts = currentAnalyticsFacts {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            WorkspaceMetricCard(title: "Gráfico", value: facts.chartKind.title, systemImage: facts.chartKind.systemImage)
                            WorkspaceMetricCard(title: "Tipo", value: facts.chartType, systemImage: "chart.bar.fill")
                            WorkspaceMetricCard(title: "Periodo", value: facts.timeRange, systemImage: "calendar")
                            WorkspaceMetricCard(title: "Agrupación", value: facts.grouping, systemImage: "square.grid.2x2")
                            ForEach(facts.metrics) { metric in
                                WorkspaceMetricCard(title: metric.title, value: metric.value, systemImage: metric.systemImage)
                            }
                        }

                        AnalyticsChartPanel(facts: facts, colorScheme: colorScheme)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Lectura docente")
                                .font(.headline)
                            WorkspaceDetailBlock(title: "Resumen base", content: facts.teacherDigest)
                            if let analyticsInsight {
                                AppleAIAuditSummaryView(metadata: analyticsMetadata)
                                WorkspaceDetailBlock(title: analyticsInsight.title, content: analyticsInsight.insight)
                                if !analyticsInsight.warnings.isEmpty {
                                    WorkspaceDetailBlock(title: "Advertencias IA", content: analyticsInsight.warnings.joined(separator: "\n"))
                                }
                                if !analyticsInsight.recommendedActions.isEmpty {
                                    WorkspaceDetailBlock(title: "Acciones sugeridas", content: analyticsInsight.recommendedActions.joined(separator: "\n"))
                                }
                            } else {
                                WorkspaceDetailBlock(title: "Insight IA", content: analyticsAvailability.isAvailable ? "Genera un insight para obtener lectura comparativa y sugerencias." : "Se generará una lectura por reglas locales si Apple Intelligence no está activo.")
                            }
                            if let analyticsFeedbackMessage {
                                WorkspaceDetailBlock(title: "Estado", content: analyticsFeedbackMessage)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Hechos verificables")
                                .font(.headline)
                            ForEach(facts.factLines, id: \.self) { line in
                                Text("• \(line)")
                                    .font(.subheadline)
                            }
                            if !facts.warnings.isEmpty {
                                ForEach(facts.warnings, id: \.self) { warning in
                                    Text("• \(warning)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(18)
                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        ShareLink(item: analyticsInsight?.insertableSummary ?? facts.insertableSummary) {
                            Label("Compartir resumen visual", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        WorkspaceEmptyState(
                            title: analyticsMode == .dashboards ? "Selecciona un dashboard" : "Formula una pregunta",
                            subtitle: analyticsMode == .dashboards ? "Elige una vista de la barra lateral para comparar grupos y detectar patrones." : "La IA local elegirá el gráfico más útil y luego te devolverá una lectura breve."
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    var reportContextDescription: String {
        switch selectedReportKind {
        case .groupOverview:
            return "Resumen por grupo con foco en medias del alumnado y consistencia general del cuaderno."
        case .studentSummary:
            if let selectedStudent {
                return "Resumen individual centrado en \(selectedStudent.firstName) \(selectedStudent.lastName) para revisión o tutoría."
            }
            return "Selecciona un alumno para obtener un informe individual con más sentido pedagógico."
        case .evaluationDigest:
            return "Panorámica de instrumentos activos, rúbricas vinculadas y carga evaluativa del grupo."
        case .operationsSnapshot:
            return "Salida operativa para asistencia, incidencias y estado del trabajo reciente."
        case .lomloeEvaluationComment:
            return "Comentario trimestral breve y competencial de Educación Física, alineado con CE1-CE5 y listo para informe."
        }
    }

    var aiAvailabilityLabel: String {
        switch aiAvailability {
        case .available: return "Disponible"
        case .disabled: return "Desactivada"
        case .unavailable: return "No disponible"
        }
    }

    var aiAvailabilityColor: Color {
        switch aiAvailability {
        case .available: return .green
        case .disabled: return .secondary
        case .unavailable: return .orange
        }
    }

    var analyticsAvailabilityLabel: String {
        switch analyticsAvailability {
        case .available: return "Disponible"
        case .disabled: return "Desactivada"
        case .unavailable: return "No disponible"
        }
    }

    var analyticsAvailabilityColor: Color {
        switch analyticsAvailability {
        case .available: return .green
        case .disabled: return .secondary
        case .unavailable: return .orange
        }
    }

    var reportGenerationState: AppleAIGenerationState {
        if isGeneratingAIDraft { return .preparingModel }
        if let state = aiMetadata?.state { return state }
        switch aiAvailability {
        case .available: return .available
        case .disabled: return .unavailable
        case .unavailable(let message):
            return message.localizedCaseInsensitiveContains("prepar") ? .preparingModel : .unavailable
        }
    }

    var analyticsGenerationState: AppleAIGenerationState {
        if isGeneratingAnalyticsInsight || isResolvingAnalyticsPrompt { return .preparingModel }
        if let state = analyticsMetadata?.state { return state }
        switch analyticsAvailability {
        case .available: return .available
        case .disabled: return .unavailable
        case .unavailable(let message):
            return message.localizedCaseInsensitiveContains("prepar") ? .preparingModel : .unavailable
        }
    }

    func reportButton(kind: KmpBridge.ReportKind) -> some View {
        Button {
            selectedReportKind = kind
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(.headline)
                    Spacer()
                    if selectedReportKind == kind {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(kind.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .appInteractiveHighlight()
    }

    @MainActor
    func refreshWorkspaceContext() async {
        guard let selectedClassId else { return }
        refreshAvailability()
        bridge.selectClass(id: selectedClassId)
        bridge.evaluationsInClass = (try? await bridge.evaluations(for: selectedClassId)) ?? []
        await bridge.selectStudentsClass(classId: selectedClassId)
        await reloadPreview()
        await reloadAnalyticsDashboards()
    }

    @MainActor
    func reloadPreview() async {
        guard let selectedClassId else { return }
        aiDraft = nil
        aiMetadata = nil
        editableDraftText = ""
        previewDraftText = ""
        aiFeedbackMessage = nil
        refinePrompt = ""

        guard let context = try? await bridge.buildReportGenerationContext(
            classId: selectedClassId,
            studentId: selectedStudentId,
            kind: selectedReportKind,
            termLabel: selectedReportKind == .lomloeEvaluationComment ? selectedReportTerm.rawValue : nil
        ) else {
            reportContext = nil
            preview = nil
            return
        }
        reportContext = context
        let basePreview = try? await bridge.buildReportPreview(
            classId: selectedClassId,
            studentId: selectedStudentId,
            kind: selectedReportKind,
            termLabel: selectedReportKind == .lomloeEvaluationComment ? selectedReportTerm.rawValue : nil
        )
        guard let basePreview else {
            preview = nil
            return
        }

        let decoratedText = """
        \(selectedReportKind.title)
        \(selectedClass?.name ?? basePreview.className)
        \(selectedStudent.map { "Alumno: \($0.firstName) \($0.lastName)" } ?? "Ámbito: grupo completo")

        \(reportContextDescription)

        \(context.summary)

        \(basePreview.previewText)
        """

        preview = KmpBridge.ReportPreviewPayload(
            classId: basePreview.classId,
            className: basePreview.className,
            previewText: decoratedText,
            generatedAt: Date()
        )
    }

    @MainActor
    func reloadAnalyticsDashboards() async {
        guard let selectedClassId else { return }
        analyticsFeedbackMessage = nil
        analyticsInsight = nil
        analyticsMetadata = nil
        queriedAnalyticsFacts = nil
        analyticsDashboards = (try? await bridge.buildPrebuiltAnalyticsCharts(
            classId: selectedClassId,
            timeRange: selectedAnalyticsRange
        )) ?? []
        if !analyticsDashboards.contains(where: { $0.chartKind == selectedChartKind }) {
            selectedChartKind = analyticsDashboards.first?.chartKind ?? .attendanceTrend
        }
    }

    @MainActor
    func generateAIDraft() async {
        guard let reportContext else { return }
        isGeneratingAIDraft = true
        aiFeedbackMessage = nil
        let startedAt = Date()
        defer { isGeneratingAIDraft = false }

        do {
            let generation = try await aiOrchestrator.generateWithTrace(
                .report(reportContext, aiAudience, aiTone),
                dataSource: reportContext.className,
                includedEvidence: reportContext.factLines + reportContext.curriculumReferences
            )
            guard case .report(let draft) = generation.result else { return }
            aiDraft = draft
            aiMetadata = generation.metadata
            previewDraftText = draft.editableText(for: reportContext)
            isReportPreviewPresented = true
            aiFeedbackMessage = "Borrador preparado para previsualización."
            await bridge.recordAIAuditEvent(
                service: "reports",
                useCase: "single_draft",
                reportKind: reportContext.kind.rawValue,
                classId: reportContext.classId,
                studentId: reportContext.studentId,
                availability: generation.metadata.state.title,
                modelAvailable: generation.metadata.audit.usedRealAI,
                success: true,
                durationMs: generation.metadata.audit.durationMs
            )
        } catch {
            aiFeedbackMessage = error.localizedDescription
            await bridge.recordAIAuditEvent(
                service: "reports",
                useCase: "single_draft",
                reportKind: reportContext.kind.rawValue,
                classId: reportContext.classId,
                studentId: reportContext.studentId,
                availability: aiAvailabilityLabel,
                modelAvailable: aiAvailability.isAvailable,
                success: false,
                durationMs: Int64(Date().timeIntervalSince(startedAt) * 1000),
                errorKind: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
        }
    }

    @MainActor
    func refineAIDraft() async {
        guard let reportContext else { return }
        isRefiningAIDraft = true
        aiFeedbackMessage = nil
        let startedAt = Date()
        defer { isRefiningAIDraft = false }

        do {
            let generation = try await aiOrchestrator.generateWithTrace(
                .report(reportContext, aiAudience, aiTone),
                dataSource: reportContext.className,
                includedEvidence: reportContext.factLines + ["Refino docente: \(refinePrompt)"]
            )
            guard case .report(let draft) = generation.result else { return }
            aiDraft = draft
            aiMetadata = generation.metadata
            previewDraftText = draft.editableText(for: reportContext)
            refinePrompt = ""
            isReportPreviewPresented = true
            aiFeedbackMessage = "Refino preparado para previsualización."
            await bridge.recordAIAuditEvent(
                service: "reports",
                useCase: "refine_draft",
                reportKind: reportContext.kind.rawValue,
                classId: reportContext.classId,
                studentId: reportContext.studentId,
                availability: generation.metadata.state.title,
                modelAvailable: generation.metadata.audit.usedRealAI,
                success: true,
                durationMs: generation.metadata.audit.durationMs
            )
        } catch {
            aiFeedbackMessage = error.localizedDescription
            await bridge.recordAIAuditEvent(
                service: "reports",
                useCase: "refine_draft",
                reportKind: reportContext.kind.rawValue,
                classId: reportContext.classId,
                studentId: reportContext.studentId,
                availability: aiAvailabilityLabel,
                modelAvailable: aiAvailability.isAvailable,
                success: false,
                durationMs: Int64(Date().timeIntervalSince(startedAt) * 1000),
                errorKind: String(describing: type(of: error)),
                errorMessage: error.localizedDescription
            )
        }
    }

    @MainActor
    func generateAnalyticsInsight(for facts: KmpBridge.ChartFacts) async {
        isGeneratingAnalyticsInsight = true
        analyticsFeedbackMessage = nil
        defer { isGeneratingAnalyticsInsight = false }

        do {
            let generation = try await aiOrchestrator.generateWithTrace(
                .chartInsight(facts),
                dataSource: facts.subtitle,
                includedEvidence: facts.factLines
            )
            guard case .chartInsight(let insight) = generation.result else { return }
            analyticsInsight = insight
            analyticsMetadata = generation.metadata
            analyticsFeedbackMessage = generation.metadata.audit.usedFallback ? "Insight generado por reglas locales. Revísalo antes de compartirlo." : "Insight generado en local. Revísalo antes de compartirlo o insertarlo en un informe."
        } catch {
            analyticsFeedbackMessage = error.localizedDescription
        }
    }

    @MainActor
    func runAnalyticsQuery() async {
        guard let selectedClassId else { return }
        isResolvingAnalyticsPrompt = true
        analyticsFeedbackMessage = nil
        analyticsInsight = nil
        defer { isResolvingAnalyticsPrompt = false }

        do {
            let fallbackRequest = try await bridge.resolveAnalyticsRequest(
                classId: selectedClassId,
                prompt: analyticsPrompt,
                timeRange: selectedAnalyticsRange
            )
            let interpreted: AIAnalyticsInterpretation?
            interpreted = nil

            let request = KmpBridge.AnalyticsRequest(
                chartKind: interpreted?.chartKind ?? fallbackRequest.chartKind,
                timeRange: fallbackRequest.timeRange,
                selectedClassIds: fallbackRequest.selectedClassIds,
                selectedClassNames: fallbackRequest.selectedClassNames,
                prompt: fallbackRequest.prompt,
                querySummary: interpreted?.querySummary ?? fallbackRequest.querySummary
            )
            let facts = try await bridge.buildChartFacts(classId: selectedClassId, request: request)
            queriedAnalyticsFacts = facts
            selectedChartKind = facts.chartKind
            analyticsFeedbackMessage = ([interpreted?.querySummary] + (interpreted?.warnings ?? [])).compactMap { $0 }.joined(separator: "\n")

            if facts.hasEnoughData {
                let generation = try? await aiOrchestrator.generateWithTrace(
                    .chartInsight(facts),
                    dataSource: facts.subtitle,
                    includedEvidence: facts.factLines
                )
                if case .chartInsight(let insight) = generation?.result {
                    analyticsInsight = insight
                    analyticsMetadata = generation?.metadata
                }
            }
        } catch {
            analyticsFeedbackMessage = error.localizedDescription
        }
    }

    func refreshAvailability() {
        let availability = aiOrchestrator.availability()
        switch availability {
        case .available:
            aiAvailability = .available
            analyticsAvailability = .available
        case .disabled(let message):
            aiAvailability = .disabled
            analyticsAvailability = .disabled
            aiFeedbackMessage = message
        case .preparing(let message), .unavailable(let message):
            aiAvailability = .unavailable(message)
            analyticsAvailability = .unavailable(message)
        }
    }
}

struct AnalyticsChartPanel: View {
    let facts: KmpBridge.ChartFacts
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(facts.chartKind.title)
                        .font(.headline)
                    Text(facts.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(facts.chartType)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            if !facts.hasEnoughData {
                WorkspaceDetailBlock(title: "Sin datos suficientes", content: facts.emptyStateMessage ?? "Todavía no hay datos suficientes para construir el gráfico.")
            } else if facts.chartKind == .incidentHeatmap {
                AnalyticsHeatmapView(cells: facts.heatmapCells)
                    .frame(minHeight: 220)
            } else if facts.chartKind == .attendanceTrend {
                AnalyticsLineChartView(series: facts.series.first)
                    .frame(height: 220)
            } else if facts.chartKind == .groupAveragesRanking {
                AnalyticsHorizontalBarsView(series: facts.series.first)
            } else {
                AnalyticsGroupedBarsView(series: facts.series)
            }
        }
        .padding(20)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AnalyticsLineChartView: View {
    let series: KmpBridge.ChartSeries?

    var body: some View {
        GeometryReader { geometry in
            let points = series?.points ?? []
            let maxValue = max(points.map(\.value).max() ?? 1, 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.05))

                if points.count > 1 {
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * geometry.size.width
                            let y = geometry.size.height - (CGFloat(point.value) / CGFloat(maxValue)) * geometry.size.height
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * geometry.size.width
                        let y = geometry.size.height - (CGFloat(point.value) / CGFloat(maxValue)) * geometry.size.height
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

struct AnalyticsGroupedBarsView: View {
    let series: [KmpBridge.ChartSeries]

    var labels: [String] {
        Array(Set(series.flatMap { $0.points.map(\.label) })).sorted()
    }

    var maxValue: Double {
        max(series.flatMap { $0.points.map(\.value) }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(series) { item in
                    Label(item.name, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(analyticsColor(item.colorToken))
                }
            }

            ForEach(labels, id: \.self) { label in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(series) { item in
                            let point = item.points.first(where: { $0.label == label })
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(analyticsColor(item.colorToken).gradient)
                                    .frame(width: 30, height: max(8, CGFloat((point?.value ?? 0) / maxValue) * 90))
                                Text(point.map { valueLabel(for: $0.value) } ?? "--")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 120, alignment: .bottom)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    func valueLabel(for value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))" : IosFormatting.decimal(from: value)
    }
}

struct AnalyticsHorizontalBarsView: View {
    let series: KmpBridge.ChartSeries?

    var body: some View {
        let points = series?.points ?? []
        let maxValue = max(points.map(\.value).max() ?? 1, 1)

        return VStack(spacing: 10) {
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(point.label)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(IosFormatting.decimal(from: point.value))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(Color.accentColor.gradient)
                                .frame(width: max(16, CGFloat(point.value / maxValue) * geometry.size.width))
                        }
                    }
                    .frame(height: 12)
                }
            }
        }
    }
}

struct AnalyticsHeatmapView: View {
    let cells: [KmpBridge.HeatmapCell]

    var rows: [String] {
        Array(Set(cells.map(\.rowLabel))).sorted()
    }

    var columns: [String] {
        Array(Set(cells.map(\.columnLabel))).sorted()
    }

    var maxValue: Double {
        max(cells.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer().frame(width: 44)
                ForEach(columns, id: \.self) { column in
                    Text(column)
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    Text(row)
                        .font(.caption.weight(.bold))
                        .frame(width: 44, alignment: .leading)
                    ForEach(columns, id: \.self) { column in
                        let value = cells.first(where: { $0.rowLabel == row && $0.columnLabel == column })?.value ?? 0
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.12 + (value / maxValue) * 0.76))
                            .frame(height: 28)
                            .overlay {
                                Text("\(Int(value))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(value > maxValue * 0.5 ? .white : .primary)
                            }
                    }
                }
            }
        }
    }
}

func analyticsColor(_ token: String) -> Color {
    switch token {
    case "green": return .green
    case "orange": return .orange
    case "purple": return .purple
    case "blue": return .blue
    default: return .accentColor
    }
}

struct BulkLOMLOEGenerationSheet: View {
    enum GenerationStatus: Equatable {
        case pending
        case generating
        case done
        case failed(String)
        case omitted(String)

        var title: String {
            switch self {
            case .pending: return "Pendiente"
            case .generating: return "Generando"
            case .done: return "Listo"
            case .failed: return "Error"
            case .omitted: return "Omitido"
            }
        }
    }

    struct DraftRow: Identifiable {
        let student: Student
        var status: GenerationStatus = .pending
        var text: String = ""
        var isApproved: Bool = true

        var id: Int64 { student.id }
    }

    @Environment(\.dismiss) var dismiss
    @ObservedObject var bridge: KmpBridge
    let classId: Int64
    let termLabel: String
    let audience: AIReportAudience
    let tone: AIReportTone

    @State var rows: [DraftRow] = []
    @State var onlyEmptyCells = true
    @State var columnName: String
    @State var targetColumnId: String?
    @State var isGenerating = false
    @State var isSaving = false
    @State var feedbackMessage: String?
    @State var generationMetadata: AppleAIGenerationMetadata?
    @State var aiAvailability: AppleAIAvailability = .unavailable("Comprobando disponibilidad…")

    let aiOrchestrator = AppleAIOrchestrator()

    init(
        bridge: KmpBridge,
        classId: Int64,
        termLabel: String,
        audience: AIReportAudience,
        tone: AIReportTone
    ) {
        self.bridge = bridge
        self.classId = classId
        self.termLabel = termLabel
        self.audience = audience
        self.tone = tone
        _columnName = State(initialValue: "LOMLOE IA - \(termLabel)")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                configBar
                List {
                    ForEach($rows) { $row in
                        rowEditor($row)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("LOMLOE por lotes")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await saveApprovedDrafts() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Guardar", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isSaving || isGenerating || rows.allSatisfy { !$0.isApproved || $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
            .task {
                aiAvailability = aiOrchestrator.availability()
                aiOrchestrator.prewarmIfUseful(for: .report(audience))
                if rows.isEmpty {
                    await loadStudents()
                }
            }
        }
    }

    var configBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Columna destino", text: $columnName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Toggle("Rellenar solo celdas vacías", isOn: $onlyEmptyCells)
            AppleAIStatusBadge(state: generationMetadata?.state ?? aiAvailability.generationState, message: generationMetadata?.availabilityMessage ?? aiAvailability.message)
            HStack(spacing: 12) {
                Button {
                    Task { await generateAll() }
                } label: {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Label("Generar comentarios", systemImage: "apple.intelligence")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || rows.isEmpty)

                Text(feedbackMessage ?? "\(rows.count) alumnos preparados")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if generationMetadata != nil {
                AppleAIAuditSummaryView(metadata: generationMetadata)
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }

    func rowEditor(_ row: Binding<DraftRow>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(row.wrappedValue.student.fullName)
                    .font(.headline)
                Spacer()
                statusLabel(row.wrappedValue.status)
                Toggle("", isOn: row.isApproved)
                    .labelsHidden()
            }
            TextEditor(text: row.text)
                .frame(minHeight: 96)
                .padding(8)
                .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.vertical, 8)
    }

    func statusLabel(_ status: GenerationStatus) -> some View {
        let tint: Color = {
            switch status {
            case .pending: return .secondary
            case .generating: return NotebookStyle.primaryTint
            case .done: return NotebookStyle.successTint
            case .failed: return NotebookStyle.warningTint
            case .omitted: return .secondary
            }
        }()
        return Text(status.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
    }

    @MainActor
    func loadStudents() async {
        rows = ((try? await bridge.students(forClassId: classId)) ?? bridge.studentsInClass)
            .map { DraftRow(student: $0) }
        feedbackMessage = rows.isEmpty ? "No hay alumnado en la clase." : nil
    }

    @MainActor
    func generateAll() async {
        isGenerating = true
        feedbackMessage = nil
        aiAvailability = aiOrchestrator.availability()
        defer { isGenerating = false }

        for index in rows.indices {
            rows[index].status = .generating
            let startedAt = Date()
            do {
                let context = try await bridge.buildReportGenerationContext(
                    classId: classId,
                    studentId: rows[index].student.id,
                    kind: .lomloeEvaluationComment,
                    termLabel: termLabel
                )
                guard context.hasEnoughData else {
                    rows[index].status = .omitted(context.dataQualityNote ?? "Datos insuficientes")
                    continue
                }
                let generation = try await aiOrchestrator.generateWithTrace(
                    .report(context, audience, tone),
                    dataSource: context.className,
                    includedEvidence: context.factLines + context.curriculumReferences
                )
                guard case .report(let draft) = generation.result else {
                    rows[index].status = .failed("Respuesta IA inesperada")
                    continue
                }
                rows[index].text = draft.editableText(for: context)
                rows[index].status = .done
                generationMetadata = generation.metadata
                await bridge.recordAIAuditEvent(
                    service: "reports",
                    useCase: "bulk_lomloe",
                    reportKind: context.kind.rawValue,
                    classId: context.classId,
                    studentId: context.studentId,
                    availability: generation.metadata.state.title,
                    modelAvailable: generation.metadata.audit.usedRealAI,
                    success: true,
                    durationMs: generation.metadata.audit.durationMs
                )
            } catch {
                rows[index].status = .failed(error.localizedDescription)
                let failureAvailability = aiOrchestrator.availability()
                aiAvailability = failureAvailability
                await bridge.recordAIAuditEvent(
                    service: "reports",
                    useCase: "bulk_lomloe",
                    reportKind: KmpBridge.ReportKind.lomloeEvaluationComment.rawValue,
                    classId: classId,
                    studentId: rows[index].student.id,
                    availability: failureAvailability.generationState.title,
                    modelAvailable: failureAvailability.isAvailable,
                    success: false,
                    durationMs: Int64(Date().timeIntervalSince(startedAt) * 1000),
                    errorKind: String(describing: type(of: error)),
                    errorMessage: error.localizedDescription
                )
            }
        }
        feedbackMessage = "Generación completada. Revisa y guarda los comentarios aprobados."
    }

    @MainActor
    func saveApprovedDrafts() async {
        isSaving = true
        feedbackMessage = nil
        defer { isSaving = false }

        do {
            let columnId: String
            if let targetColumnId {
                columnId = targetColumnId
            } else {
                columnId = try await bridge.createNotebookAICommentColumnForClass(classId: classId, name: columnName)
                targetColumnId = columnId
            }

            var saved = 0
            var skipped = 0
            for row in rows where row.isApproved {
                let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    skipped += 1
                    continue
                }
                if onlyEmptyCells {
                    let existing = try await bridge.notebookTextCell(classId: classId, studentId: row.student.id, columnId: columnId)
                    if !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        skipped += 1
                        continue
                    }
                }
                try await bridge.saveNotebookAICommentDirect(classId: classId, studentId: row.student.id, columnId: columnId, text: text)
                saved += 1
            }
            feedbackMessage = "Guardados: \(saved). Omitidos: \(skipped)."
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }
}
