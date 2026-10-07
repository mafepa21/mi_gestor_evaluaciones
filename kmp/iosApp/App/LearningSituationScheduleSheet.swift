import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

struct GroupScheduleState: Identifiable {
    let classId: Int64
    let className: String
    var isIncluded: Bool
    var startDate: Date = Date()
    var slots: [TermClassSlot] = []
    var metrics: TermCapacityMetrics?
    var scheduledSlots: [LearningSituationScheduledSlot] = []
    var inferredRoute: LearningSituationWeeklySequenceRoute?

    var id: Int64 { classId }

    var previewSlots: [TermClassSlot] {
        slots.filter { slot in
            if case .preview = slot.kind { return true }
            return false
        }
    }

    var previewCount: Int {
        if !scheduledSlots.isEmpty {
            return scheduledSlots.count
        }
        let uniqueSessions = Set(previewSlots.compactMap { slot -> Int? in
            if case .preview(let num, _, _, _, _) = slot.kind { return num }
            return nil
        })
        return uniqueSessions.isEmpty ? previewSlots.count : uniqueSessions.count
    }
}

/// Acción que se repite con «Reintentar» tras un error en línea.
enum LearningSituationScheduleRetry: Equatable {
    case loadAll
    case project
    case save
}

struct LearningSituationScheduleSheet: View {
    let situation: LearningSituation
    let bridge: KmpBridge
    let initialClassId: Int64?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var minimumTapSize: CGFloat = 44

    @State private var groupStates: [GroupScheduleState] = []
    @State private var selectedCompactClassId: Int64?
    @State private var selectedTermPeriodId: Int64?
    @State private var situationStartDate = Date()
    @State private var evaluationPeriods: [PlannerEvaluationPeriod] = []

    @State private var isLoading = false
    @State private var isSaving = false
    // Errores y avisos en línea (sin alertas).
    @State private var errorMessage = ""
    @State private var failedAction: LearningSituationScheduleRetry?
    @State private var hasNoEvaluationPeriods = false
    @State private var hasLoadedGroups = false

    // Sequence import & routes (DOCX / Bachillerato)
    @State private var isSequenceImporterPresented = false
    @State private var sequenceDraft: LearningSituationSessionSequenceImportDraft?
    @State private var selectedSequenceRoute: LearningSituationWeeklySequenceRoute?
    @State private var expandedPlanNumbers: Set<Int> = []

    private var sortedEvaluationPeriods: [PlannerEvaluationPeriod] {
        evaluationPeriods.sorted { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }
    }

    private var activePeriod: PlannerEvaluationPeriod? {
        if let id = selectedTermPeriodId, let match = evaluationPeriods.first(where: { $0.id == id }) {
            return match
        }
        return sortedEvaluationPeriods.first
    }

    private static let isoDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        return df
    }()

    private var selectedPeriodDateRange: ClosedRange<Date> {
        let calendar = Calendar(identifier: .iso8601)
        if let period = activePeriod,
           let start = Self.isoDateFormatter.date(from: period.startDateIso),
           let end = Self.isoDateFormatter.date(from: period.endDateIso),
           start <= end {
            return start...end
        }
        let now = Date()
        return now...calendar.date(byAdding: .month, value: 3, to: now)!
    }

    private var routeVariants: [LearningSituationWeeklySequenceRoute: [LearningSituationSessionPlanDraft]] {
        sequenceDraft?.routeVariants ?? [:]
    }

    private var isRouteAwareDocument: Bool {
        !routeVariants.isEmpty
    }

    private var routeOptions: [LearningSituationWeeklySequenceRoute] {
        routeVariants.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private var activeInferredRoute: LearningSituationWeeklySequenceRoute? {
        let active = includedGroups.first(where: { $0.classId == (selectedCompactClassId ?? includedGroups.first?.classId) }) ?? groupStates.first
        return active?.inferredRoute
    }

    private var targetSessionCount: Int {
        if let draft = sequenceDraft {
            return LearningSituationScheduleProjection.targetSessionCount(
                plans: draft.plans,
                annualSessionCount: Int(situation.sessionCount),
                sequenceKind: LearningSituationScheduleProjection.sequenceKind(for: draft.plans)
            )
        }
        return max(1, Int(situation.sessionCount))
    }

    private var includedGroups: [GroupScheduleState] {
        groupStates.filter(\.isIncluded)
    }

    private var totalPreviewSlotsCount: Int {
        includedGroups.map(\.previewCount).reduce(0, +)
    }

    private var canProgram: Bool {
        guard !isSaving && !isLoading else { return false }
        return includedGroups.contains { $0.previewCount > 0 }
    }

    /// Grupos incluidos cuya fecha de inicio no coincide con el «Inicio común».
    private var groupsWithOtherStartDate: Int {
        let calendar = Calendar(identifier: .iso8601)
        return includedGroups.filter { !calendar.isDate($0.startDate, inSameDayAs: situationStartDate) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    sheetHeader
                    if !errorMessage.isEmpty {
                        LearningSituationInlineNotice(
                            kind: .error,
                            message: errorMessage,
                            actionTitle: failedAction == nil ? "Cerrar aviso" : "Reintentar"
                        ) {
                            retryFailedAction()
                        }
                    }
                    mainContent
                }
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.vertical, 16)
            }
            .background(EvaluationDesign.surface)
            .navigationTitle("Programar sesiones")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .fileImporter(
                isPresented: $isSequenceImporterPresented,
                allowedContentTypes: [.docx],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 640, idealHeight: 740)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            await loadPeriodsAndProject()
        }
        .appOnChange(of: selectedTermPeriodId) { _ in
            Task { await loadAndProject() }
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private var mainContent: some View {
        if !hasLoadedGroups || (isLoading && groupStates.allSatisfy({ $0.slots.isEmpty })) {
            loadingView
        } else if hasNoEvaluationPeriods {
            LearningSituationInlineNotice(
                kind: .warning,
                message: "Faltan periodos de evaluación. Créalos en el Planner y vuelve a programar."
            )
        } else if groupStates.isEmpty {
            ContentUnavailableView {
                Label("No hay grupos vinculados", systemImage: "person.2.slash")
            } description: {
                Text("Añade un grupo arriba para programar las sesiones.")
            }
            .frame(minHeight: 240)
        } else if includedGroups.isEmpty {
            ContentUnavailableView {
                Label("Ningún grupo elegido", systemImage: "person.2.slash")
            } description: {
                Text("Marca al menos un grupo arriba para ver su horario.")
            }
            .frame(minHeight: 240)
        } else {
            sequenceSection

            if includedGroups.count == 1, let single = includedGroups.first {
                groupCard(single)
            } else {
                multiGroupAdaptiveView
            }
        }
    }

    // MARK: - Cabecera

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(situation.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Elige cuándo empieza en cada grupo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Los controles se reparten en varias líneas cuando no caben.
            LearningSituationFlowLayout(spacing: 16) {
                if !sortedEvaluationPeriods.isEmpty {
                    labeledControl("Evaluación") {
                        Picker("Evaluación", selection: $selectedTermPeriodId) {
                            ForEach(sortedEvaluationPeriods, id: \.id) { period in
                                Text(period.name).tag(Optional(period.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                if includedGroups.count > 1 {
                    labeledControl("Inicio común") {
                        HStack(spacing: 8) {
                            DatePicker(
                                "Inicio común",
                                selection: $situationStartDate,
                                in: selectedPeriodDateRange,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            Button("Aplicar a todos", action: applyCommonStartDate)
                                .buttonStyle(.bordered)
                                .disabled(groupsWithOtherStartDate == 0)
                        }
                    }
                }
            }

            if includedGroups.count > 1 && groupsWithOtherStartDate > 0 {
                Text("«Aplicar a todos» cambiará la fecha de \(groupsWithOtherStartDate == 1 ? "1 grupo" : "\(groupsWithOtherStartDate) grupos"). Podrás ajustarlas después.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            groupSelection
        }
    }

    private func labeledControl<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let control = content()
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            control
                .frame(minHeight: minimumTapSize)
        }
    }

    private var groupSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grupos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LearningSituationFlowLayout(spacing: 8) {
                ForEach($groupStates) { $group in
                    Toggle(isOn: $group.isIncluded) {
                        Label(
                            "\(group.className) · \(group.previewCount)/\(targetSessionCount)",
                            systemImage: group.isIncluded ? "checkmark.circle.fill" : "circle"
                        )
                        .frame(minHeight: minimumTapSize - 12)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(group.isIncluded ? EvaluationDesign.accent : .secondary)
                    .accessibilityLabel("\(group.className), \(group.previewCount) de \(targetSessionCount) sesiones")
                }

                let unaddedClasses = bridge.classes.filter { c in !groupStates.contains(where: { $0.classId == c.id }) }
                if !unaddedClasses.isEmpty {
                    Menu {
                        ForEach(unaddedClasses, id: \.id) { sc in
                            Button(sc.name) {
                                addGroup(classId: sc.id, className: sc.name)
                            }
                        }
                    } label: {
                        Label("Añadir grupo", systemImage: "plus")
                            .frame(minHeight: minimumTapSize - 12)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Grupos (uno o varios)

    private func groupStartDatePicker(for group: GroupScheduleState) -> some View {
        DatePicker(
            "Fecha de inicio",
            selection: Binding(
                get: { group.startDate },
                set: { newDate in
                    if let idx = groupStates.firstIndex(where: { $0.classId == group.classId }) {
                        groupStates[idx].startDate = newDate
                        Task { await loadAndProject() }
                    }
                }
            ),
            in: selectedPeriodDateRange,
            displayedComponents: [.date]
        )
        .frame(minHeight: minimumTapSize)
    }

    private func groupCard(_ group: GroupScheduleState) -> some View {
        LearningSituationCard {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        groupTitle(group)
                        Spacer(minLength: 8)
                        groupStartDatePicker(for: group)
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        groupTitle(group)
                        groupStartDatePicker(for: group)
                    }
                }

                if group.slots.isEmpty {
                    LearningSituationInlineNotice(
                        kind: .warning,
                        message: "\(group.className) no tiene franjas en el horario de esta evaluación. Revisa el horario del Planner."
                    )
                } else {
                    if let metrics = group.metrics {
                        TermBoardMetricsStrip(metrics: metrics)
                    }
                    TermBoardTimelineView(
                        slots: group.slots,
                        bottomPadding: 24
                    )
                }
            }
        }
    }

    private func groupTitle(_ group: GroupScheduleState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.className)
                .font(.headline)
            let isComplete = group.previewCount >= targetSessionCount
            Label(
                "\(group.previewCount) de \(targetSessionCount) sesiones",
                systemImage: isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(isComplete ? EvaluationDesign.success : IOSAppStyle.warning)
        }
        .accessibilityElement(children: .combine)
    }

    private var multiGroupAdaptiveView: some View {
        ViewThatFits(in: .horizontal) {
            // Ancho regular (iPad horizontal, Mac): grupos lado a lado.
            HStack(alignment: .top, spacing: 16) {
                ForEach(includedGroups) { group in
                    groupCard(group)
                        .frame(minWidth: 440)
                }
            }

            // Compacto (iPhone, iPad vertical o en multitarea): selector de grupo.
            compactGroupView
        }
    }

    private var compactGroupView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                compactGroupPicker
                    .pickerStyle(.segmented)
                compactGroupPicker
                    .pickerStyle(.menu)
            }

            if let active = includedGroups.first(where: { $0.classId == (selectedCompactClassId ?? includedGroups.first?.classId) }) {
                groupCard(active)
            }
            let others = includedGroups.count - 1
            Text(others == 1 ? "Hay 1 grupo más. Cámbialo en el selector de arriba." : "Hay \(others) grupos más. Cámbialos en el selector de arriba.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var compactGroupPicker: some View {
        Picker("Grupo", selection: Binding(
            get: {
                if let selected = selectedCompactClassId, includedGroups.contains(where: { $0.classId == selected }) {
                    return selected
                }
                return includedGroups.first?.classId ?? 0
            },
            set: { selectedCompactClassId = $0 }
        )) {
            ForEach(includedGroups) { grp in
                Text("\(grp.className) (\(grp.previewCount))").tag(grp.classId)
            }
        }
    }

    // MARK: - Secuencia desde Word

    @ViewBuilder
    private var sequenceSection: some View {
        if let draft = sequenceDraft {
            LearningSituationCard(title: "Secuencia desde Word") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(draft.sourceFileName) · \(draft.plans.count) sesiones")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isRouteAwareDocument {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Itinerario")
                                    .font(.subheadline.weight(.semibold))
                                if selectedSequenceRoute == nil, let inferred = activeInferredRoute {
                                    Text("Según el horario: \(inferred.displayName)")
                                        .font(.subheadline)
                                        .foregroundStyle(EvaluationDesign.accent)
                                }
                            }
                            ViewThatFits(in: .horizontal) {
                                routePicker
                                    .pickerStyle(.segmented)
                                routePicker
                                    .pickerStyle(.menu)
                            }
                        }
                    }

                    ForEach(draft.warnings, id: \.self) { warning in
                        LearningSituationInlineNotice(kind: .warning, message: warning)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sesiones del documento")
                            .font(.subheadline.weight(.semibold))
                        ForEach(draft.plans, id: \.sessionNumber) { plan in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("S\(plan.sessionNumber)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(EvaluationDesign.accent)
                                Text(plan.title)
                                    .font(.subheadline)
                                Spacer(minLength: 8)
                                if !plan.criteria.isEmpty {
                                    Text(plan.criteria.count == 1 ? "1 criterio" : "\(plan.criteria.count) criterios")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Button("Cambiar documento") {
                        isSequenceImporterPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            Button {
                isSequenceImporterPresented = true
            } label: {
                Label("Usar secuencia desde Word…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var routePicker: some View {
        Picker(
            "Itinerario",
            selection: Binding<LearningSituationWeeklySequenceRoute?>(
                get: { selectedSequenceRoute },
                set: { selectRoute($0) }
            )
        ) {
            Text("Automático según horario").tag(nil as LearningSituationWeeklySequenceRoute?)
            ForEach(routeOptions, id: \.self) { route in
                Text(route.displayName).tag(Optional(route))
            }
        }
        .labelsHidden()
    }

    // MARK: - Barra inferior (chrome del sistema)

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                bottomStatus
                Spacer(minLength: 8)
                programButton
            }
            VStack(alignment: .leading, spacing: 8) {
                bottomStatus
                programButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var bottomStatus: some View {
        Text(bottomStatusMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bottomStatusMessage: String {
        if isSaving { return "Guardando \(totalPreviewSlotsCount) sesiones…" }
        if isLoading { return "Calculando horario…" }
        if hasNoEvaluationPeriods { return "No se puede programar" }
        if includedGroups.isEmpty { return "Sin grupos" }
        if !canProgram { return "No se puede programar: no hay franjas libres" }
        let groups = includedGroups.count == 1 ? "1 grupo" : "\(includedGroups.count) grupos"
        return "\(groups) · \(totalPreviewSlotsCount) de \(targetSessionCount * max(1, includedGroups.count)) sesiones"
    }

    private var programButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Guardando…")
                }
            } else {
                Text("Programar")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!canProgram)
    }

    // MARK: - Estados

    private var loadingView: some View {
        LearningSituationCard {
            HStack(spacing: 8) {
                ProgressView()
                Text("Calculando horario…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LearningSituationSkeletonBlock(lines: 3)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Errores en línea

    private func showError(_ message: String, retry: LearningSituationScheduleRetry?) {
        errorMessage = message
        failedAction = retry
    }

    private func clearError() {
        errorMessage = ""
        failedAction = nil
    }

    private func retryFailedAction() {
        let action = failedAction
        clearError()
        switch action {
        case .loadAll:
            Task { await loadPeriodsAndProject() }
        case .project:
            Task { await loadAndProject() }
        case .save:
            Task { await save() }
        case nil:
            break
        }
    }

    /// Aplica el «Inicio común» a todos los grupos incluidos (tras el aviso visible).
    private func applyCommonStartDate() {
        for index in groupStates.indices where groupStates[index].isIncluded {
            groupStates[index].startDate = situationStartDate
        }
        Task { await loadAndProject() }
    }

    // MARK: - Projection & Persistence Logic

    @MainActor
    private func loadPeriodsAndProject() async {
        defer { hasLoadedGroups = true }
        do {
            let schedule = try await bridge.plannerTeacherSchedule()
            evaluationPeriods = try await bridge.plannerEvaluationPeriods(scheduleId: schedule.id)
            if let current = currentPeriodForToday() {
                selectedTermPeriodId = current.id
                situationStartDate = Date()
            } else if let first = sortedEvaluationPeriods.first {
                selectedTermPeriodId = first.id
                situationStartDate = Self.isoDateFormatter.date(from: first.startDateIso) ?? Date()
            }

            // Discover linked groups from SA
            let links: [LearningSituationClassLink]
            do {
                links = try await bridge.learningSituationClassLinks(id: situation.id)
            } catch {
                showError(LearningSituationScheduleLoad.linksFailure, retry: .loadAll)
                return
            }
            var initialGroupIds = links.map(\.classId)
            if initialGroupIds.isEmpty, let initial = initialClassId {
                initialGroupIds = [initial]
            } else if initialGroupIds.isEmpty, let first = bridge.classes.first?.id {
                initialGroupIds = [first]
            }

            self.groupStates = initialGroupIds.compactMap { cid in
                guard let schoolClass = bridge.classes.first(where: { $0.id == cid }) else { return nil }
                return GroupScheduleState(classId: cid, className: schoolClass.name, isIncluded: true, startDate: situationStartDate)
            }
            if selectedCompactClassId == nil {
                selectedCompactClassId = groupStates.first?.classId
            }

            await loadAndProject()
        } catch {
            showError(error.localizedDescription, retry: .loadAll)
        }
    }

    private func addGroup(classId: Int64, className: String) {
        guard !groupStates.contains(where: { $0.classId == classId }) else { return }
        groupStates.append(GroupScheduleState(classId: classId, className: className, isIncluded: true, startDate: situationStartDate))
        Task { await loadAndProject() }
    }

    private func currentPeriodForToday() -> PlannerEvaluationPeriod? {
        let todayIso = Self.isoDateFormatter.string(from: Date())

        return evaluationPeriods.first { period in
            period.startDateIso <= todayIso && todayIso <= period.endDateIso
        }
    }

    @MainActor
    private func loadAndProject() async {
        guard !groupStates.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if failedAction == .loadAll || failedAction == .project {
            clearError()
        }

        do {
            let schedule = try await bridge.plannerTeacherSchedule()
            if evaluationPeriods.isEmpty {
                evaluationPeriods = try await bridge.plannerEvaluationPeriods(scheduleId: schedule.id)
            }

            let resolvedPeriod: PlannerEvaluationPeriod
            if let id = selectedTermPeriodId, let match = evaluationPeriods.first(where: { $0.id == id }) {
                resolvedPeriod = match
            } else if let first = sortedEvaluationPeriods.first {
                selectedTermPeriodId = first.id
                resolvedPeriod = first
            } else {
                // Estado en línea, no error: faltan periodos de evaluación en el Planner.
                hasNoEvaluationPeriods = true
                return
            }
            hasNoEvaluationPeriods = false

            let allScheduleSlots = try await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)
            let globalNonTeaching = try await bridge.plannerNonTeachingCalendarEvents(classId: nil)
            let allSessions = try await bridge.plannerListSessions(
                fromIso: resolvedPeriod.startDateIso,
                toIso: resolvedPeriod.endDateIso,
                classId: nil
            )
            let visibleSlots = bridge.plannerTimeSlots().map {
                PlannerVisibleSlot(period: Int($0.period), startTime: $0.startTime, endTime: $0.endTime)
            }

            // Simulation plans: from sequenceDraft or from persisted plans / sessionCount
            let simPlans: [TermSimulationPlanItem]
            if let draft = sequenceDraft {
                simPlans = draft.plans.map { plan in
                    TermSimulationPlanItem(
                        planId: nil,
                        sessionNumber: plan.sessionNumber,
                        title: plan.title,
                        objective: plan.objective,
                        hasEvaluation: !plan.criteria.isEmpty
                    )
                }
            } else {
                var loadedPlans: [TermSimulationPlanItem] = []
                let versions: [LearningSituationSessionSequenceVersion]
                do {
                    versions = try await bridge.learningSituationSessionSequenceVersionsAll()
                } catch {
                    showError(LearningSituationScheduleLoad.sequenceFailure, retry: .project)
                    return
                }
                let sitVersions = versions.filter { $0.learningSituationId == situation.id }
                if let latestVersion = sitVersions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    let allPlans: [LearningSituationSessionPlan]
                    do {
                        allPlans = try await bridge.learningSituationSessionPlansAll()
                    } catch {
                        showError(LearningSituationScheduleLoad.sequenceFailure, retry: .project)
                        return
                    }
                    let plans = allPlans
                        .filter { $0.sequenceVersionId == latestVersion.id }
                        .sorted { $0.sessionNumber < $1.sessionNumber }
                    loadedPlans = plans.map { plan in
                        let hasEvidence = !plan.developmentJson.isEmpty && plan.developmentJson.contains("evidence")
                        return TermSimulationPlanItem(
                            planId: plan.id,
                            sessionNumber: Int(plan.sessionNumber),
                            title: plan.title,
                            objective: plan.objective,
                            hasEvaluation: hasEvidence
                        )
                    }
                }

                if !loadedPlans.isEmpty {
                    simPlans = loadedPlans
                } else {
                    let count = max(1, Int(situation.sessionCount))
                    simPlans = (1...count).map { num in
                        TermSimulationPlanItem(
                            planId: nil,
                            sessionNumber: num,
                            title: "Sesión \(num) · \(situation.title)",
                            objective: situation.challenge,
                            hasEvaluation: num == count
                        )
                    }
                }
            }

            let calendar = Calendar(identifier: .iso8601)
            let pStart = Self.isoDateFormatter.date(from: resolvedPeriod.startDateIso)
            let pEnd = Self.isoDateFormatter.date(from: resolvedPeriod.endDateIso)

            // Ensure situationStartDate falls within the resolved period range
            if let pStart, let pEnd {
                if situationStartDate < pStart || situationStartDate > pEnd {
                    situationStartDate = pStart
                }
            }

            for index in groupStates.indices {
                // Ensure individual group startDate falls within the period range
                if let pStart, let pEnd {
                    if groupStates[index].startDate < pStart || groupStates[index].startDate > pEnd {
                        groupStates[index].startDate = situationStartDate
                    }
                }
                let groupSimStartDateIso = Self.isoDateFormatter.string(from: groupStates[index].startDate)

                let classId = groupStates[index].classId
                let classSlots = allScheduleSlots.filter { $0.schoolClassId == classId }
                let classNonTeaching = try await bridge.plannerNonTeachingCalendarEvents(classId: classId)
                let allNonTeaching = globalNonTeaching + classNonTeaching
                var nonTeachingDates = Set<Date>()
                for event in allNonTeaching {
                    let eventStart = Date(timeIntervalSince1970: Double(event.startAt.toEpochMilliseconds()) / 1000.0)
                    let eventEnd = Date(timeIntervalSince1970: Double(event.endAt.toEpochMilliseconds()) / 1000.0)
                    var cursor = calendar.startOfDay(for: eventStart)
                    let endDay = calendar.startOfDay(for: eventEnd)
                    while cursor <= endDay {
                        nonTeachingDates.insert(cursor)
                        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                        cursor = next
                    }
                }

                if let draft = sequenceDraft {
                    let inferred = LearningSituationScheduleProjection.inferRouteForFirstBlock(
                        startDate: groupStates[index].startDate,
                        template: classSlots,
                        periodForSlot: { slot in
                            visibleSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime })?.period ?? 1
                        },
                        excludedDates: nonTeachingDates
                    )
                    groupStates[index].inferredRoute = inferred

                    let effectiveRoute: LearningSituationWeeklySequenceRoute = {
                        if let explicit = selectedSequenceRoute {
                            return explicit
                        }
                        if let inferred, draft.routeVariants[inferred] != nil {
                            return inferred
                        }
                        return draft.routeVariants[.shortFirst] != nil ? .shortFirst : (routeOptions.first ?? .shortFirst)
                    }()

                    let groupPlans = draft.routeVariants[effectiveRoute] ?? draft.plans
                    let targetCount = LearningSituationScheduleProjection.targetSessionCount(
                        plans: groupPlans,
                        annualSessionCount: Int(situation.sessionCount),
                        sequenceKind: LearningSituationScheduleProjection.sequenceKind(for: groupPlans)
                    )

                    let projectionResult = LearningSituationScheduleProjection.planAwareSlots(
                        plans: groupPlans,
                        startDate: groupStates[index].startDate,
                        template: classSlots,
                        periodForSlot: { slot in
                            visibleSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime })?.period ?? 1
                        },
                        targetSessionCount: targetCount,
                        excludedDates: nonTeachingDates
                    )
                    groupStates[index].scheduledSlots = projectionResult.slots

                    // Base timeline from TermBoardProjectionEngine (holidays, existing sessions, free slots)
                    let baseProjection = TermBoardProjectionEngine.project(
                        periodName: resolvedPeriod.name,
                        startDateIso: resolvedPeriod.startDateIso,
                        endDateIso: resolvedPeriod.endDateIso,
                        deadlineDateIso: nil,
                        classId: classId,
                        scheduleSlots: allScheduleSlots,
                        nonTeachingEvents: allNonTeaching,
                        existingSessions: allSessions,
                        simulationPlans: nil,
                        simulationSituationTitle: situation.title,
                        simulationStartDateIso: groupSimStartDateIso,
                        defaultTimeSlots: visibleSlots
                    )

                    var updatedSlots = baseProjection.slots
                    var placedPeriodsCount = 0

                    for assigned in projectionResult.slots {
                        guard let planNumber = assigned.planSessionNumber else { continue }
                        let plan = groupPlans.first(where: { $0.sessionNumber == planNumber })
                        let assignedDateIso = Self.isoDateFormatter.string(from: assigned.date)
                        let isLong = assigned.occupiedPeriods.count > 1

                        for (destinationIndex, destination) in assigned.destinationSlots.enumerated() {
                            if let slotIndex = updatedSlots.firstIndex(where: {
                                $0.dateIso == assignedDateIso && $0.period == destination.period
                            }) {
                                if case .free = updatedSlots[slotIndex].kind {
                                    let suffix = (isLong && destinationIndex > 0) ? " (cont.)" : ""
                                    let title = (plan?.title.isEmpty == false ? plan!.title : "Sesión \(planNumber)") + suffix
                                    let objective = destinationIndex == 0 ? (plan?.objective ?? "") : "Continuación de la sesión doble"
                                    let hasEvaluation = destinationIndex == 0 ? (!(plan?.criteria.isEmpty ?? true)) : false

                                    updatedSlots[slotIndex] = TermClassSlot(
                                        id: updatedSlots[slotIndex].id,
                                        date: updatedSlots[slotIndex].date,
                                        dateIso: updatedSlots[slotIndex].dateIso,
                                        dayOfWeek: updatedSlots[slotIndex].dayOfWeek,
                                        period: updatedSlots[slotIndex].period,
                                        startTime: destination.startTime.isEmpty ? updatedSlots[slotIndex].startTime : destination.startTime,
                                        endTime: destination.endTime.isEmpty ? updatedSlots[slotIndex].endTime : destination.endTime,
                                        teacherScheduleSlotId: destination.teacherScheduleSlotId ?? updatedSlots[slotIndex].teacherScheduleSlotId,
                                        lessonIndex: updatedSlots[slotIndex].lessonIndex,
                                        kind: .preview(
                                            sessionNumber: planNumber,
                                            title: title,
                                            objective: objective,
                                            hasEvaluation: hasEvaluation,
                                            planId: nil
                                        ),
                                        isAfterEvaluationDeadline: updatedSlots[slotIndex].isAfterEvaluationDeadline
                                    )
                                    placedPeriodsCount += 1
                                }
                            }
                        }
                    }

                    let updatedMetrics = TermCapacityMetrics(
                        totalLectivas: baseProjection.metrics.totalLectivas,
                        totalFestivos: baseProjection.metrics.totalFestivos,
                        totalOcupadas: baseProjection.metrics.totalOcupadas,
                        totalLibres: max(0, baseProjection.metrics.totalLibres - placedPeriodsCount),
                        evaluationPeriodName: baseProjection.metrics.evaluationPeriodName,
                        startDate: baseProjection.metrics.startDate,
                        endDate: baseProjection.metrics.endDate
                    )

                    groupStates[index].slots = updatedSlots
                    groupStates[index].metrics = updatedMetrics
                } else {
                    let projection = TermBoardProjectionEngine.project(
                        periodName: resolvedPeriod.name,
                        startDateIso: resolvedPeriod.startDateIso,
                        endDateIso: resolvedPeriod.endDateIso,
                        deadlineDateIso: nil,
                        classId: classId,
                        scheduleSlots: allScheduleSlots,
                        nonTeachingEvents: allNonTeaching,
                        existingSessions: allSessions,
                        simulationPlans: simPlans,
                        simulationSituationTitle: situation.title,
                        simulationStartDateIso: groupSimStartDateIso,
                        defaultTimeSlots: visibleSlots
                    )

                    groupStates[index].slots = projection.slots
                    groupStates[index].metrics = projection.metrics
                }
            }

            if selectedSequenceRoute == nil, let draft = sequenceDraft {
                let activeGrp = includedGroups.first(where: { $0.classId == (selectedCompactClassId ?? includedGroups.first?.classId) }) ?? groupStates.first
                if let activeGrp, let inferred = activeGrp.inferredRoute, let plans = draft.routeVariants[inferred] {
                    self.sequenceDraft?.plans = plans
                }
            }
        } catch {
            showError(error.localizedDescription, retry: .project)
        }
    }

    private func selectRoute(_ route: LearningSituationWeeklySequenceRoute?) {
        selectedSequenceRoute = route
        guard let sequenceDraft else { return }
        if let route, let plans = sequenceDraft.routeVariants[route] {
            self.sequenceDraft?.plans = plans
            expandedPlanNumbers = Set(plans.prefix(3).map(\.sessionNumber))
        }
        Task { await loadAndProject() }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                var draft = try LearningSituationSessionSequenceDocumentImportService().preview(from: url)
                let isWeekly = LearningSituationScheduleProjection.sequenceKind(for: draft.plans) == .canonicalWeekly
                let annualSessionCount = Int(situation.sessionCount)
                let expectedPlanCount: Int? = if LearningSituationScheduleProjection.sequenceKind(for: draft.plans) == .routeAware {
                    nil
                } else {
                    isWeekly
                        ? LearningSituationScheduleProjection.canonicalBlockCount(forAnnualSessionCount: annualSessionCount)
                        : annualSessionCount
                }
                if let expectedPlanCount, situation.sessionCount > 0 && draft.plans.count != expectedPlanCount {
                    let expectedLabel = isWeekly ? "bloques canónicos para \(annualSessionCount) sesiones lectivas" : "sesiones"
                    draft.warnings.append("La programación anual exige \(annualSessionCount) sesiones y se esperaban \(expectedPlanCount) \(expectedLabel), pero el documento contiene \(draft.plans.count).")
                }
                sequenceDraft = draft
                selectedSequenceRoute = nil
                expandedPlanNumbers = Set(draft.plans.prefix(3).map(\.sessionNumber))
                Task { await loadAndProject() }
            } catch {
                showError(error.localizedDescription, retry: nil)
            }
        case .failure(let error):
            showError(error.localizedDescription, retry: nil)
        }
    }

    @MainActor
    private func save() async {
        let targets = groupStates.filter(\.isIncluded)
        guard !targets.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        if failedAction == .save { clearError() }

        do {
            for group in targets {
                guard let schoolClass = bridge.classes.first(where: { $0.id == group.classId }) else { continue }
                
                let scheduledSlots: [LearningSituationScheduledSlot]
                if !group.scheduledSlots.isEmpty {
                    scheduledSlots = group.scheduledSlots
                } else {
                    let previewSlots = group.previewSlots
                    guard !previewSlots.isEmpty else { continue }

                    scheduledSlots = previewSlots.compactMap { slot in
                        guard case .preview(let sessionNumber, _, _, _, _) = slot.kind else { return nil }
                        return LearningSituationScheduledSlot(
                            date: slot.date,
                            period: slot.period,
                            teacherScheduleSlotId: slot.teacherScheduleSlotId,
                            startTime: slot.startTime,
                            endTime: slot.endTime,
                            planSessionNumber: sessionNumber,
                            blockKind: nil,
                            occupiedPeriods: [slot.period],
                            occupiedScheduleSlots: [
                                LearningSituationScheduledDestination(
                                    period: slot.period,
                                    teacherScheduleSlotId: slot.teacherScheduleSlotId,
                                    startTime: slot.startTime,
                                    endTime: slot.endTime
                                )
                            ],
                            isSelected: true
                        )
                    }
                }
                guard !scheduledSlots.isEmpty else { continue }

                var groupSequenceDraft = sequenceDraft
                if let draft = sequenceDraft, isRouteAwareDocument {
                    let effectiveRoute = selectedSequenceRoute ?? group.inferredRoute ?? .shortFirst
                    if let routePlans = draft.routeVariants[effectiveRoute] {
                        var modifiedDraft = draft
                        modifiedDraft.plans = routePlans
                        groupSequenceDraft = modifiedDraft
                    }
                }

                try await bridge.programLearningSituationSessions(
                    situation: situation,
                    classId: group.classId,
                    groupName: schoolClass.name,
                    scheduledSlots: scheduledSlots,
                    sequenceDraft: groupSequenceDraft
                )
            }
            dismiss()
            onSaved()
        } catch {
            showError("No se pudieron crear las sesiones. \(error.localizedDescription)", retry: .save)
        }
    }
}
