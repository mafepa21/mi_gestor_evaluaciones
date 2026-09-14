import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

struct GroupScheduleState: Identifiable {
    let classId: Int64
    let className: String
    var isIncluded: Bool
    var slots: [TermClassSlot] = []
    var metrics: TermCapacityMetrics?

    var id: Int64 { classId }

    var previewSlots: [TermClassSlot] {
        slots.filter { slot in
            if case .preview = slot.kind { return true }
            return false
        }
    }

    var previewCount: Int {
        previewSlots.count
    }
}

struct LearningSituationScheduleSheet: View {
    let situation: LearningSituation
    let bridge: KmpBridge
    let initialClassId: Int64?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var groupStates: [GroupScheduleState] = []
    @State private var selectedCompactClassId: Int64?
    @State private var selectedTermPeriodId: Int64?
    @State private var evaluationPeriods: [PlannerEvaluationPeriod] = []

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false

    // Sequence import & routes (DOCX / Bachillerato)
    @State private var isSequenceImporterPresented = false
    @State private var sequenceDraft: LearningSituationSessionSequenceImportDraft?
    @State private var selectedSequenceRoute: LearningSituationWeeklySequenceRoute?
    @State private var expandedPlanNumbers: Set<Int> = []
    @State private var isSequenceSectionExpanded = false

    private var sortedEvaluationPeriods: [PlannerEvaluationPeriod] {
        evaluationPeriods.sorted { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header & Configuration Strip
                sheetHeader
                    .padding(.horizontal, EvaluationDesign.screenPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Main Content
                if isLoading && groupStates.allSatisfy({ $0.slots.isEmpty }) {
                    loadingView
                } else if includedGroups.isEmpty {
                    noGroupsSelectedView
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 16) {
                            sequenceDetailsCard

                            if includedGroups.count == 1, let single = includedGroups.first {
                                singleGroupView(single)
                            } else {
                                multiGroupAdaptiveView
                            }
                        }
                        .padding(.horizontal, EvaluationDesign.screenPadding)
                        .padding(.bottom, 96)
                    }
                }
            }
            .background(EvaluationDesign.surface)
            .navigationTitle("Programar SA")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                floatingBottomBar
            }
            .alert("No se pudo programar", isPresented: $showingErrorAlert) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(errorMessage)
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
        .frame(minWidth: 1040, minHeight: 740)
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

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.accent)
                    .frame(width: 42, height: 42)
                    .background(EvaluationDesign.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(situation.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)

                        if !situation.subjectLabel.isEmpty {
                            Text(situation.subjectLabel)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Planificación curricular · Previsión de encaje sobre franjas lectivas reales")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Controls: Period Picker & DOCX Import
            HStack(spacing: 12) {
                if !sortedEvaluationPeriods.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(Color.purple)
                        Picker("Evaluación", selection: $selectedTermPeriodId) {
                            ForEach(sortedEvaluationPeriods, id: \.id) { period in
                                Text(period.name).tag(Optional(period.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer()

                Button {
                    isSequenceImporterPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sequenceDraft == nil ? "doc.badge.plus" : "doc.text.fill")
                        Text(sequenceDraft == nil ? "Secuenciación DOCX" : "DOCX cargado")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(sequenceDraft == nil ? .secondary : EvaluationDesign.accent)
            }

            // Group Selection Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Grupos:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach($groupStates) { $group in
                        Toggle(isOn: $group.isIncluded) {
                            HStack(spacing: 4) {
                                Image(systemName: group.isIncluded ? "checkmark.circle.fill" : "circle")
                                Text("\(group.className) (\(group.previewCount)/\(targetSessionCount))")
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .tint(group.isIncluded ? EvaluationDesign.accent : .secondary)
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
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(14)
        .plannerGlassPanel(.content, cornerRadius: 16)
    }

    // MARK: - Body Views (Single & Multi-Group Adaptive)

    private func singleGroupView(_ group: GroupScheduleState) -> some View {
        VStack(spacing: 16) {
            if let metrics = group.metrics {
                TermBoardMetricsStrip(metrics: metrics)
            }
            if group.slots.isEmpty {
                emptySlotsView(for: group.className)
            } else {
                TermBoardTimelineView(
                    slots: group.slots,
                    bottomPadding: 24
                )
            }
        }
    }

    private var multiGroupAdaptiveView: some View {
        ViewThatFits(in: .horizontal) {
            // 1. Regular Horizontal View (iPad landscape, macOS): Two columns side by side!
            twoColumnHorizontalView

            // 2. Compact Fallback (iPhone, iPad portrait / split 1/3): Segmented selector
            compactSegmentedView
        }
    }

    private var twoColumnHorizontalView: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(includedGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(group.className)
                            .font(.headline.weight(.bold))
                        Spacer()
                        Text("\(group.previewCount) de \(targetSessionCount) sesiones")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(group.previewCount >= targetSessionCount ? NotebookStyle.successTint : NotebookStyle.warningTint)
                    }

                    if let metrics = group.metrics {
                        TermBoardMetricsStrip(metrics: metrics)
                    }

                    if group.slots.isEmpty {
                        emptySlotsView(for: group.className)
                    } else {
                        TermBoardTimelineView(
                            slots: group.slots,
                            bottomPadding: 24
                        )
                    }
                }
                .padding(14)
                .plannerGlassPanel(.content, cornerRadius: 16)
                #if os(macOS)
                .frame(minWidth: 440)
                #endif
            }
        }
    }

    private var compactSegmentedView: some View {
        VStack(spacing: 12) {
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
            .pickerStyle(.segmented)

            if let active = includedGroups.first(where: { $0.classId == (selectedCompactClassId ?? includedGroups.first?.classId) }) {
                singleGroupView(active)
            }
        }
    }

    // MARK: - Sequence Details Card

    @ViewBuilder
    private var sequenceDetailsCard: some View {
        if let draft = sequenceDraft {
            DisclosureGroup(isExpanded: $isSequenceSectionExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    if isRouteAwareDocument {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Itinerario de franjas horarias:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

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
                            .pickerStyle(.segmented)
                        }
                    }

                    if !draft.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(draft.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(EvaluationDesign.danger)
                            }
                        }
                        .padding(8)
                        .background(EvaluationDesign.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // Quick list of detected session titles
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planes de sesión detectados:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(draft.plans, id: \.sessionNumber) { plan in
                            HStack(spacing: 8) {
                                Text("S\(plan.sessionNumber)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(EvaluationDesign.accentSoft, in: Capsule())
                                    .foregroundStyle(EvaluationDesign.accent)

                                Text(plan.title)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                if !plan.criteria.isEmpty {
                                    Text("\(plan.criteria.count) criterios")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(EvaluationDesign.accent)
                    Text("Secuenciación activa: \(draft.sourceFileName)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(draft.plans.count) sesiones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .plannerGlassPanel(.content, cornerRadius: 14)
        }
    }

    // MARK: - Floating Bottom Bar

    private var floatingBottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(EvaluationDesign.accent)
                    Text("\(totalPreviewSlotsCount) de \(targetSessionCount * max(1, includedGroups.count)) sesiones encajadas")
                        .font(.headline)
                }
                Text(includedGroups.map { "\($0.className): \($0.previewCount) ses." }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancelar") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(minWidth: 100)
                } else {
                    Label("Programar en \(includedGroups.count) grupo\(includedGroups.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(EvaluationDesign.accent)
            .disabled(!canProgram)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .plannerGlassPanel(.content, cornerRadius: 18, isInteractive: true)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 12, y: 6)
        .padding(.horizontal, EvaluationDesign.screenPadding)
        .padding(.bottom, 16)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Proyectando encaje en los calendarios lectivos…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptySlotsView(for groupName: String? = nil) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sin franjas lectivas encontradas")
                .font(.headline)
            Text("El grupo \(groupName ?? "") no tiene franjas horarias configuradas en este periodo de evaluación.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var noGroupsSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Ningún grupo seleccionado")
                .font(.headline)
            Text("Activa al menos un grupo arriba para ver su proyección horaria y programar sesiones.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Projection & Persistence Logic

    @MainActor
    private func loadPeriodsAndProject() async {
        do {
            let schedule = try await bridge.plannerTeacherSchedule()
            evaluationPeriods = try await bridge.plannerEvaluationPeriods(scheduleId: schedule.id)
            if let current = currentPeriodForToday() {
                selectedTermPeriodId = current.id
            } else {
                selectedTermPeriodId = sortedEvaluationPeriods.first?.id
            }

            // Discover linked groups from SA
            let links = (try? await bridge.learningSituationClassLinks(id: situation.id)) ?? []
            var initialGroupIds = links.map(\.classId)
            if initialGroupIds.isEmpty, let initial = initialClassId {
                initialGroupIds = [initial]
            } else if initialGroupIds.isEmpty, let first = bridge.classes.first?.id {
                initialGroupIds = [first]
            }

            self.groupStates = initialGroupIds.compactMap { cid in
                guard let schoolClass = bridge.classes.first(where: { $0.id == cid }) else { return nil }
                return GroupScheduleState(classId: cid, className: schoolClass.name, isIncluded: true)
            }
            if selectedCompactClassId == nil {
                selectedCompactClassId = groupStates.first?.classId
            }

            await loadAndProject()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    private func addGroup(classId: Int64, className: String) {
        guard !groupStates.contains(where: { $0.classId == classId }) else { return }
        groupStates.append(GroupScheduleState(classId: classId, className: className, isIncluded: true))
        Task { await loadAndProject() }
    }

    private func currentPeriodForToday() -> PlannerEvaluationPeriod? {
        let calendar = Calendar(identifier: .iso8601)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = calendar
        let todayIso = dateFormatter.string(from: Date())

        return evaluationPeriods.first { period in
            period.startDateIso <= todayIso && todayIso <= period.endDateIso
        }
    }

    @MainActor
    private func loadAndProject() async {
        guard !groupStates.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

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
                errorMessage = "No hay periodos de evaluación configurados."
                showingErrorAlert = true
                return
            }

            let allScheduleSlots = try await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)
            let globalNonTeaching = try await bridge.plannerNonTeachingCalendarEvents(classId: nil)
            let allSessions = try await bridge.plannerListAllSessions()
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
                let versions = (try? await bridge.learningSituationSessionSequenceVersionsAll()) ?? []
                let sitVersions = versions.filter { $0.learningSituationId == situation.id }
                if let latestVersion = sitVersions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    let allPlans = (try? await bridge.learningSituationSessionPlansAll()) ?? []
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

            for index in groupStates.indices {
                let classId = groupStates[index].classId
                let classNonTeaching = try await bridge.plannerNonTeachingCalendarEvents(classId: classId)
                let allNonTeaching = globalNonTeaching + classNonTeaching

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
                    defaultTimeSlots: visibleSlots
                )

                groupStates[index].slots = projection.slots
                groupStates[index].metrics = projection.metrics
            }
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    private func selectRoute(_ route: LearningSituationWeeklySequenceRoute?) {
        selectedSequenceRoute = route
        guard let sequenceDraft else { return }
        let fallback = route ?? (routeVariants[.shortFirst] != nil ? .shortFirst : (routeOptions.first ?? .shortFirst))
        if let plans = sequenceDraft.routeVariants[fallback] {
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
                isSequenceSectionExpanded = true
                Task { await loadAndProject() }
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    @MainActor
    private func save() async {
        let targets = groupStates.filter(\.isIncluded)
        guard !targets.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            for group in targets {
                guard let schoolClass = bridge.classes.first(where: { $0.id == group.classId }) else { continue }
                let previewSlots = group.previewSlots
                guard !previewSlots.isEmpty else { continue }

                let scheduledSlots: [LearningSituationScheduledSlot] = previewSlots.compactMap { slot in
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

                try await bridge.programLearningSituationSessions(
                    situation: situation,
                    classId: group.classId,
                    groupName: schoolClass.name,
                    scheduledSlots: scheduledSlots,
                    sequenceDraft: sequenceDraft
                )
            }
            dismiss()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
}
