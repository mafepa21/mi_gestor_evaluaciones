import SwiftUI
import Combine
import MiGestorKit

@MainActor
final class PlannerWorkspaceViewModel: ObservableObject {
    let calendarStore = PlannerCalendarStore()
    let sessionStore = PlannerSessionStore()
    let scheduleStore = PlannerScheduleStore()
    let journalStore = PlannerJournalStore()
    let composerStore = PlannerComposerStore()
    let weekBoard = PlannerWeekBoardStore()
    private var cancellables = Set<AnyCancellable>()

    @Published var isLoaded = false
    @Published var activeSection: PlannerWorkspaceSection = .week
    @Published var density: PlannerDensity = .standard
    @Published var groups: [SchoolClass] = []
    @Published var selectedGroupId: Int64?
    @Published var classColorHexById: [Int64: String] = [:]
    @Published var sessions: [PlanningSession] = []
    @Published var filteredSessions: [PlanningSession] = []
    @Published var sequenceGroupsEnriched: [PlannerSequenceGroup] = []
    @Published var isLoadingSequences = false
    @Published var selectedSession: PlanningSession?
    @Published var dayViewSelectedDay: Int?
    @Published var journalDraft: PlannerJournalDraft = .empty
    @Published var journalSaveState: PlannerSaveState = .idle
    @Published var journalSummaryBySessionId: [Int64: SessionJournalSummary] = [:]
    @Published var visibleWeekdays: [Int] = [1, 2, 3, 4, 5]
    @Published var weeklySlots: [WeeklySlotTemplate] = []
    @Published var teacherSchedule: TeacherSchedule?
    @Published var teacherScheduleSlots: [TeacherScheduleSlot] = []
    @Published var evaluationPeriods: [PlannerEvaluationPeriod] = []
    @Published var forecastRows: [PlannerSessionForecast] = []
    @Published var searchText = ""
    @Published var selectionMode = false
    @Published var selectedSessionIds: Set<Int64> = []
    @Published var showingComposer = false
    @Published var showingShareSheet = false
    @Published var bulkSummary = ""
    @Published var scheduleName = "Agenda docente"
    @Published var scheduleStartDate = PlannerCalendar.defaultSchoolYearStartIso
    @Published var scheduleEndDate = PlannerCalendar.defaultSchoolYearEndIso
    @Published var activeWeekdays: Set<Int> = [1, 2, 3, 4, 5]
    @Published var scheduleFormGroupId: Int64?
    @Published var scheduleFormDay = 1
    @Published var scheduleFormStart = "08:05"
    @Published var scheduleFormEnd = "09:00"
    @Published var scheduleFormSubject = ""
    @Published var scheduleFormUnit = ""
    @Published var scheduleError = ""
    @Published var scheduleSaveState: PlannerSaveState = .idle
    @Published var evaluationFormName = ""
    @Published var evaluationFormStart = ""
    @Published var evaluationFormEnd = ""
    @Published var composerDraft = PlannerComposerDraft()
    @Published var composerTeachingUnits: [TeachingUnit] = []
    @Published var composerAvailableInstruments: [PlannerAssessmentInstrument] = []
    @Published var composerContextError = ""
    @Published var isSavingComposer = false
    @Published var composerSaveState: PlannerSaveState = .idle
    @Published var scheduleGenerationPreview: [PlannerScheduleGenerationPreviewRow] = []
    @Published var scheduleGenerationSummary = ""
    @Published var isGeneratingScheduleSessions = false
    @Published var lastCascadeMove: SessionCascadeMoveResult?

    weak var bridge: KmpBridge?
    var autosaveTask: Task<Void, Never>?
    var isHydratingDraft = false
    var loadedAggregate: SessionJournalAggregate?

    var week: Int {
        get { weekBoard.week }
        set { weekBoard.week = newValue }
    }
    var year: Int {
        get { weekBoard.year }
        set { weekBoard.year = newValue }
    }
    var visibleSlots: [PlannerVisibleSlot] {
        get { weekBoard.visibleSlots }
        set { weekBoard.visibleSlots = newValue }
    }
    var timeSlots: [TimeSlotConfig] {
        get { weekBoard.timeSlots }
        set { weekBoard.timeSlots = newValue }
    }
    var holidayDays: Set<Int> {
        get { weekBoard.holidayDays }
        set { weekBoard.holidayDays = newValue }
    }
    var weekRenderModel: PlannerWeekRenderModel {
        get { weekBoard.weekRenderModel }
        set { weekBoard.weekRenderModel = newValue }
    }

    init() {
        weekBoard.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var weekLabel: String { "Semana \(week), \(year)" }

    var dateRangeLabel: String {
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.dayOfMonth)/\(first.monthNumber) - \(last.dayOfMonth)/\(last.monthNumber)"
    }

    var activeWeekdaySummary: String {
        let labels = activeWeekdays.sorted().map(dayLabel(for:))
        return labels.isEmpty ? "Sin días lectivos" : labels.joined(separator: " · ")
    }

    var effectiveScheduleSlots: [TeacherScheduleSlot] {
        teacherScheduleSlots.sorted(by: { ($0.dayOfWeek, $0.startTime) < ($1.dayOfWeek, $1.startTime) })
    }

    var visibleScheduleSlotsSummaryCount: Int {
        effectiveScheduleSlots.count
    }

    var isUsingLegacyWeeklySlots: Bool {
        false
    }

    var generationPreviewTotals: (detected: Int, omitted: Int) {
        scheduleGenerationPreview.reduce(into: (detected: 0, omitted: 0)) { result, row in
            result.detected += row.detectedSessions
            result.omitted += row.existingSessions
        }
    }

    var canClearSchedulelessWeekSessions: Bool {
        schedulelessWeekSessionsToClearCount() > 0
    }

    func schedulelessWeekSessionsToClearCount(groupId: Int64? = nil) -> Int {
        guard effectiveScheduleSlots.isEmpty else { return 0 }
        return sessions.count { session in
            (groupId == nil || session.groupId == groupId) && session.status != .completed
        }
    }

    func bind(bridge: KmpBridge) async {
        guard !isLoaded else { return }
        self.bridge = bridge
        let current = IsoWeekHelper.shared.current()
        let currentIsoFallback = PlannerCalendar.currentIsoYearWeek
        week = Int(truncating: current.first ?? KotlinInt(value: Int32(currentIsoFallback.week)))
        year = Int(truncating: current.second ?? KotlinInt(value: Int32(currentIsoFallback.year)))
        timeSlots = bridge.plannerTimeSlots()
        await reloadPlannerBootstrap()
        await reloadScheduleOnly()
        await reloadSessionsOnly(keepSelection: false)
        isLoaded = true
    }

    func reloadAll(keepSelection: Bool = true) async {
        await reloadPlannerBootstrap()
        await reloadScheduleOnly()
        await reloadSessionsOnly(keepSelection: keepSelection)
    }

    func reloadSessionsOnly(keepSelection: Bool = true) async {
        await reloadWeekSessions(keepSelection: keepSelection)
    }

    func reloadScheduleOnly() async {
        await reloadScheduleConfiguration()
    }

    func reloadJournalOnly() async {
        await reloadJournalSummaries()
        await reloadSelectedJournal()
    }

    func reloadComposerContextOnly() async {
        await refreshComposerContext()
    }

    private func reloadPlannerBootstrap() async {
        guard let bridge else { return }
        scheduleFormGroupId = await calendarStore.reloadBootstrap(bridge: bridge, scheduleFormGroupId: scheduleFormGroupId)
        groups = calendarStore.groups
        classColorHexById = calendarStore.classColorHexById
    }

    func reloadWeekSessions(keepSelection: Bool = true) async {
        guard let bridge else { return }
        await sessionStore.reload(bridge: bridge, week: week, year: year)
        sessions = sessionStore.sessions
        rebuildVisiblePlannerStructure()
        await reloadJournalSummaries()
        await reloadHolidays()
        rebuildWeekRenderModel()
        applySearch()

        if keepSelection, let selectedSession {
            self.selectedSession = sessions.first(where: { $0.id == selectedSession.id })
            if self.selectedSession != nil {
                await reloadSelectedJournal()
            }
        } else if let first = filteredSessions.first {
            selectedSession = first
            await reloadSelectedJournal()
        } else {
            clearSelection()
        }
    }

    func reloadJournalSummaries() async {
        guard let bridge else { return }
        await journalStore.reloadSummaries(bridge: bridge, sessionIds: sessions.map(\.id))
        journalSummaryBySessionId = journalStore.journalSummaryBySessionId
        rebuildWeekRenderModel()
    }

    private func reloadSelectedJournal() async {
        await loadJournalForSelectedSession()
    }

    func applySearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            filteredSessions = sessions.sorted { lhs, rhs in
                if lhs.dayOfWeek == rhs.dayOfWeek {
                    if lhs.period == rhs.period { return lhs.groupName < rhs.groupName }
                    return lhs.period < rhs.period
                }
                return lhs.dayOfWeek < rhs.dayOfWeek
            }
            return
        }
        filteredSessions = sessions.filter {
            [$0.groupName, $0.teachingUnitName, $0.objectives, $0.activities]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    func previousWeek() async {
        if week <= 1 {
            year -= 1
            week = Self.isoWeeks(in: year)
        } else {
            week -= 1
        }
        await reloadSessionsOnly(keepSelection: false)
    }

    func nextWeek() async {
        if week >= Self.isoWeeks(in: year) {
            week = 1
            year += 1
        } else {
            week += 1
        }
        await reloadSessionsOnly(keepSelection: false)
    }

    func goToCurrentWeek() async {
        let current = IsoWeekHelper.shared.current()
        let currentIsoFallback = PlannerCalendar.currentIsoYearWeek
        week = Int(truncating: current.first ?? KotlinInt(value: Int32(currentIsoFallback.week)))
        year = Int(truncating: current.second ?? KotlinInt(value: Int32(currentIsoFallback.year)))
        await reloadSessionsOnly(keepSelection: false)
        await selectTodaySessionIfPossible(preferredGroupId: selectedGroupId)
    }

    func refreshCurrentWeek() async {
        await reloadSessionsOnly()
    }

    func selectGroup(_ id: Int64?) {
        selectedGroupId = id
        rebuildWeekRenderModel()
    }

    func clearSelection() {
        autosaveTask?.cancel()
        selectedSession = nil
        journalDraft = .empty
        loadedAggregate = nil
        journalSaveState = .idle
    }

    func applyExternalContext(week: Int?, year: Int?, groupId: Int64?, sessionId: Int64?) async {
        var shouldReload = false

        if let week, self.week != week {
            self.week = week
            shouldReload = true
        }
        if let year, self.year != year {
            self.year = year
            shouldReload = true
        }
        if let groupId, self.selectedGroupId != groupId {
            self.selectedGroupId = groupId
            self.scheduleFormGroupId = groupId
        }

        if shouldReload {
            await reloadSessionsOnly(keepSelection: false)
        }

        if let sessionId,
           let session = sessions.first(where: { $0.id == sessionId }) {
            await select(session: session)
        } else {
            await selectTodaySessionIfPossible(preferredGroupId: groupId)
        }
    }

    func selectTodaySessionIfPossible(preferredGroupId: Int64?) async {
        let current = IsoWeekHelper.shared.current()
        let currentIsoFallback = PlannerCalendar.currentIsoYearWeek
        let currentWeek = Int(truncating: current.first ?? KotlinInt(value: Int32(currentIsoFallback.week)))
        let currentYear = Int(truncating: current.second ?? KotlinInt(value: Int32(currentIsoFallback.year)))
        guard week == currentWeek, year == currentYear else { return }

        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale.current
        let todayWeekday = ((calendar.component(.weekday, from: Date()) + 5) % 7) + 1
        let candidates = sessions
            .filter { session in
                Int(session.dayOfWeek) == todayWeekday &&
                    (preferredGroupId == nil || session.groupId == preferredGroupId)
            }
            .sorted {
                if $0.period == $1.period {
                    return ($0.startTime ?? "") < ($1.startTime ?? "")
                }
                return $0.period < $1.period
            }

        guard let todaySession = candidates.first else { return }
        if selectedSession?.id != todaySession.id {
            await select(session: todaySession)
        }
    }

}
