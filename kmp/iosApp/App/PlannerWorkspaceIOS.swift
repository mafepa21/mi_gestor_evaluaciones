import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import MiGestorKit

struct PlannerNavigationContext: Equatable {
    var week: Int?
    var year: Int?
    var groupId: Int64?
    var sessionId: Int64?
}

enum PlannerWorkspaceSection: String, CaseIterable, Identifiable {
    case week = "Semana"
    case sessions = "Sesiones"
    case schedule = "Agenda"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .week: return "calendar"
        case .sessions: return "list.bullet.rectangle"
        case .schedule: return "clock"
        }
    }
}

struct PlannerJournalDraftNote: Identifiable, Equatable {
    var id = UUID()
    var studentId: Int64? = nil
    var studentName = ""
    var note = ""
    var tag = ""

    static func == (lhs: PlannerJournalDraftNote, rhs: PlannerJournalDraftNote) -> Bool {
        lhs.studentId == rhs.studentId
            && lhs.studentName == rhs.studentName
            && lhs.note == rhs.note
            && lhs.tag == rhs.tag
    }
}

struct PlannerJournalDraftAction: Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var detail = ""
    var isCompleted = false

    static func == (lhs: PlannerJournalDraftAction, rhs: PlannerJournalDraftAction) -> Bool {
        lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.isCompleted == rhs.isCompleted
    }
}

struct PlannerJournalDraftMedia: Identifiable, Equatable {
    var id = UUID()
    var type: SessionJournalMediaType
    var uri = ""
    var transcript = ""
    var caption = ""

    static func == (lhs: PlannerJournalDraftMedia, rhs: PlannerJournalDraftMedia) -> Bool {
        lhs.type == rhs.type
            && lhs.uri == rhs.uri
            && lhs.transcript == rhs.transcript
            && lhs.caption == rhs.caption
    }
}

struct PlannerJournalDraftLink: Identifiable, Equatable {
    var id = UUID()
    var type: SessionJournalLinkType
    var targetId = ""
    var label = ""

    static func == (lhs: PlannerJournalDraftLink, rhs: PlannerJournalDraftLink) -> Bool {
        lhs.type == rhs.type
            && lhs.targetId == rhs.targetId
            && lhs.label == rhs.label
    }
}

struct PlannerJournalDraft: Equatable {
    var teacherName = ""
    var scheduledSpace = ""
    var usedSpace = ""
    var unitLabel = ""
    var objectivePlanned = ""
    var plannedText = ""
    var actualText = ""
    var attainmentText = ""
    var adaptationsText = ""
    var incidentsText = ""
    var groupObservations = ""
    var climateScore = 0
    var participationScore = 0
    var usefulTimeScore = 0
    var perceivedDifficultyScore = 0
    var pedagogicalDecision: SessionJournalDecision = .none
    var pendingTasksText = ""
    var materialToPrepareText = ""
    var studentsToReviewText = ""
    var familyCommunicationText = ""
    var nextStepText = ""
    var weatherText = ""
    var materialUsedText = ""
    var physicalIncidentsText = ""
    var injuriesText = ""
    var unequippedStudentsText = ""
    var intensityScore = 0
    var warmupMinutes = 0
    var mainPartMinutes = 0
    var cooldownMinutes = 0
    var stationObservationsText = ""
    var incidentTags: [String] = []
    var status: SessionJournalStatus = .empty
    var notes: [PlannerJournalDraftNote] = []
    var actions: [PlannerJournalDraftAction] = []
    var media: [PlannerJournalDraftMedia] = []
    var links: [PlannerJournalDraftLink] = []

    static let empty = PlannerJournalDraft()

    init() {}

    init(aggregate: SessionJournalAggregate) {
        let journal = aggregate.journal
        teacherName = journal.teacherName
        scheduledSpace = journal.scheduledSpace
        usedSpace = journal.usedSpace
        unitLabel = journal.unitLabel
        objectivePlanned = journal.objectivePlanned
        plannedText = journal.plannedText
        actualText = journal.actualText
        attainmentText = journal.attainmentText
        adaptationsText = journal.adaptationsText
        incidentsText = journal.incidentsText
        groupObservations = journal.groupObservations
        climateScore = Int(journal.climateScore)
        participationScore = Int(journal.participationScore)
        usefulTimeScore = Int(journal.usefulTimeScore)
        perceivedDifficultyScore = Int(journal.perceivedDifficultyScore)
        pedagogicalDecision = journal.pedagogicalDecision
        pendingTasksText = journal.pendingTasksText
        materialToPrepareText = journal.materialToPrepareText
        studentsToReviewText = journal.studentsToReviewText
        familyCommunicationText = journal.familyCommunicationText
        nextStepText = journal.nextStepText
        weatherText = journal.weatherText
        materialUsedText = journal.materialUsedText
        physicalIncidentsText = journal.physicalIncidentsText
        injuriesText = journal.injuriesText
        unequippedStudentsText = journal.unequippedStudentsText
        intensityScore = Int(journal.intensityScore)
        warmupMinutes = Int(journal.warmupMinutes)
        mainPartMinutes = Int(journal.mainPartMinutes)
        cooldownMinutes = Int(journal.cooldownMinutes)
        stationObservationsText = journal.stationObservationsText
        incidentTags = journal.incidentTags
        status = journal.status
        notes = aggregate.individualNotes.map {
            PlannerJournalDraftNote(
                studentId: $0.studentId?.int64Value,
                studentName: $0.studentName,
                note: $0.note,
                tag: $0.tag
            )
        }
        actions = aggregate.actions.map {
            PlannerJournalDraftAction(
                title: $0.title,
                detail: $0.detail,
                isCompleted: $0.isCompleted
            )
        }
        media = aggregate.media.map {
            PlannerJournalDraftMedia(
                type: $0.type,
                uri: $0.uri,
                transcript: $0.transcript,
                caption: $0.caption
            )
        }
        links = aggregate.links.map {
            PlannerJournalDraftLink(
                type: $0.type,
                targetId: $0.targetId,
                label: $0.label
            )
        }
    }
}

private enum PlannerJournalFocusField: Hashable {
    case planned
    case actual
    case incidents
}

struct PlannerComposerDraft {
    var groupId: Int64? = nil
    var sessionId: Int64 = 0
    var teachingUnitId: Int64? = nil
    var unitTitle = ""
    var objectives = ""
    var activities = ""
    var dayOfWeek = 1
    var period = 1
    var teacherScheduleSlotId: Int64? = nil
    var startTime: String? = nil
    var endTime: String? = nil
    var selectedInstrumentIds: Set<String> = []
}

enum PlannerSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

struct PlannerSectionPreview: Identifiable, Hashable {
    let title: String
    let value: String
    var id: String { title }
}

struct PlannerVisibleSlot: Identifiable, Hashable {
    let period: Int
    let startTime: String
    let endTime: String

    var id: Int { period }

    var label: String {
        "\(startTime)-\(endTime)"
    }
}

struct PlannerWeekCellEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case session
        case scheduledSlot
    }

    let id: String
    let kind: Kind
    let classId: Int64
    let className: String
    let classColorHex: String
    let dayOfWeek: Int
    let period: Int
    let title: String
    let preview: String
    let sectionPreviews: [PlannerSectionPreview]
    let sessionId: Int64?
    let sessionStatus: SessionStatus?
    let journalStatus: SessionJournalStatus?
    let scheduledSlotId: Int64?
    let isCompleted: Bool
}

struct PlannerScheduleGenerationPreviewRow: Identifiable, Hashable {
    let classId: Int64
    let className: String
    let detectedSessions: Int
    let existingSessions: Int

    var id: Int64 { classId }
}

@MainActor
private final class PlannerAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var recordedURL: URL?

    func start() {
#if os(macOS)
        isRecording = false
        recordedURL = nil
#else
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("planner_audio_\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()
            self.recorder = recorder
            self.recordedURL = url
            isRecording = true
        } catch {
            _ = stop(discard: true)
        }
#endif
    }

    func stop(discard: Bool = false) -> URL? {
#if os(macOS)
        isRecording = false
        return nil
#else
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        if discard {
            if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
            recordedURL = nil
            return nil
        }
        defer { recordedURL = nil }
        return recordedURL
#endif
    }
}

@MainActor
private final class PlannerCalendarStore: ObservableObject {
    @Published var week = 1
    @Published var year = 2026
    @Published var groups: [SchoolClass] = []
    @Published var selectedGroupId: Int64?
    @Published var classColorHexById: [Int64: String] = [:]
    @Published var timeSlots: [TimeSlotConfig] = []
    @Published var visibleSlots: [PlannerVisibleSlot] = []
    @Published var visibleWeekdays: [Int] = [1, 2, 3, 4, 5]

    func reloadBootstrap(bridge: KmpBridge, scheduleFormGroupId: Int64?) async -> Int64? {
        await bridge.ensureClassesLoaded()
        groups = bridge.classes.sorted { $0.name < $1.name }
        classColorHexById = bridge.plannerCourseColors(for: groups.map(\.id))
        return scheduleFormGroupId ?? groups.first?.id
    }
}

@MainActor
private final class PlannerSessionStore: ObservableObject {
    @Published var sessions: [PlanningSession] = []
    @Published var filteredSessions: [PlanningSession] = []
    @Published var selectedSession: PlanningSession?
    @Published var searchText = ""
    @Published var selectionMode = false
    @Published var selectedSessionIds: Set<Int64> = []
    @Published var bulkSummary = ""

    func reload(bridge: KmpBridge, week: Int, year: Int) async {
        sessions = (try? await bridge.plannerListSessions(weekNumber: week, year: year, classId: nil)) ?? []
    }

    func upsertLocal(_ session: PlanningSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
}

@MainActor
private final class PlannerScheduleStore: ObservableObject {
    @Published var weeklySlots: [WeeklySlotTemplate] = []
    @Published var teacherSchedule: TeacherSchedule?
    @Published var teacherScheduleSlots: [TeacherScheduleSlot] = []
    @Published var evaluationPeriods: [PlannerEvaluationPeriod] = []
    @Published var forecastRows: [PlannerSessionForecast] = []
    @Published var scheduleError = ""
    @Published var scheduleSaveState: PlannerSaveState = .idle

    func reload(bridge: KmpBridge, groups: [SchoolClass], scheduleFormGroupId: Int64?) async -> Int64? {
        do {
            let schedule = try await bridge.plannerTeacherSchedule()
            teacherSchedule = schedule
            teacherScheduleSlots = (try? await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)) ?? []
            weeklySlots = bridge.plannerWeeklySlots(classId: nil)
            evaluationPeriods = (try? await bridge.plannerEvaluationPeriods(scheduleId: schedule.id)) ?? []
            forecastRows = (try? await bridge.plannerForecast(scheduleId: schedule.id, classId: nil)) ?? []
            return scheduleFormGroupId ?? groups.first?.id
        } catch {
            scheduleError = error.localizedDescription
            return scheduleFormGroupId
        }
    }
}

@MainActor
private final class PlannerJournalStore: ObservableObject {
    @Published var journalDraft: PlannerJournalDraft = .empty
    @Published var journalSaveState: PlannerSaveState = .idle
    @Published var journalSummaryBySessionId: [Int64: SessionJournalSummary] = [:]
    var loadedAggregate: SessionJournalAggregate?

    func reloadSummaries(bridge: KmpBridge, sessionIds: [Int64]) async {
        let summaries = (try? await bridge.plannerJournalSummaries(sessionIds: sessionIds)) ?? []
        journalSummaryBySessionId = Dictionary(uniqueKeysWithValues: summaries.map { ($0.planningSessionId, $0) })
    }
}

@MainActor
private final class PlannerComposerStore: ObservableObject {
    @Published var draft = PlannerComposerDraft()
    @Published var teachingUnits: [TeachingUnit] = []
    @Published var availableInstruments: [PlannerAssessmentInstrument] = []
    @Published var contextError = ""
    @Published var isSaving = false
    @Published var saveState: PlannerSaveState = .idle

    func reloadContext(bridge: KmpBridge, groupId: Int64?, teachingUnitId: Int64?) async {
        guard let groupId else {
            teachingUnits = []
            availableInstruments = []
            contextError = ""
            return
        }
        do {
            teachingUnits = try await bridge.plannerTeachingUnits(for: groupId)
            availableInstruments = try await bridge.plannerAvailableAssessmentInstruments(
                classId: groupId,
                teachingUnitId: teachingUnitId
            )
            contextError = ""
        } catch {
            contextError = error.localizedDescription
        }
    }
}

@MainActor
final class PlannerWorkspaceViewModel: ObservableObject {
    private let calendarStore = PlannerCalendarStore()
    private let sessionStore = PlannerSessionStore()
    private let scheduleStore = PlannerScheduleStore()
    private let journalStore = PlannerJournalStore()
    private let composerStore = PlannerComposerStore()

    @Published var isLoaded = false
    @Published var activeSection: PlannerWorkspaceSection = .week
    @Published var week = 1
    @Published var year = 2026
    @Published var groups: [SchoolClass] = []
    @Published var selectedGroupId: Int64?
    @Published var classColorHexById: [Int64: String] = [:]
    @Published var sessions: [PlanningSession] = []
    @Published var filteredSessions: [PlanningSession] = []
    @Published var selectedSession: PlanningSession?
    @Published var journalDraft: PlannerJournalDraft = .empty
    @Published var journalSaveState: PlannerSaveState = .idle
    @Published var journalSummaryBySessionId: [Int64: SessionJournalSummary] = [:]
    @Published var timeSlots: [TimeSlotConfig] = []
    @Published var visibleSlots: [PlannerVisibleSlot] = []
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
    @Published var scheduleStartDate = "2026-09-01"
    @Published var scheduleEndDate = "2027-06-30"
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

    private weak var bridge: KmpBridge?
    private var autosaveTask: Task<Void, Never>?
    private var isHydratingDraft = false
    private var loadedAggregate: SessionJournalAggregate?

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
        week = Int(truncating: current.first ?? KotlinInt(value: 1))
        year = Int(truncating: current.second ?? KotlinInt(value: 2026))
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

    private func reloadWeekSessions(keepSelection: Bool = true) async {
        guard let bridge else { return }
        await sessionStore.reload(bridge: bridge, week: week, year: year)
        sessions = sessionStore.sessions
        rebuildVisiblePlannerStructure()
        await reloadJournalSummaries()
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

    private func reloadJournalSummaries() async {
        guard let bridge else { return }
        await journalStore.reloadSummaries(bridge: bridge, sessionIds: sessions.map(\.id))
        journalSummaryBySessionId = journalStore.journalSummaryBySessionId
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

    func selectGroup(_ id: Int64?) {
        selectedGroupId = id
    }

    func timeLabel(for period: Int) -> String {
        if let slot = visibleSlots.first(where: { $0.period == period }) {
            return slot.label
        }
        if let slot = timeSlots.first(where: { Int($0.period) == period }) {
            return "\(slot.startTime)-\(slot.endTime)"
        }
        return "P\(period)"
    }

    func summary(for sessionId: Int64) -> SessionJournalSummary? {
        journalSummaryBySessionId[sessionId]
    }

    func classColorHex(for classId: Int64) -> String {
        classColorHexById[classId] ?? bridge?.plannerCourseColor(for: classId) ?? EvaluationDesign.plannerCoursePalette[0]
    }

    func select(session: PlanningSession) async {
        selectedSession = session
        selectedGroupId = session.groupId
        await loadJournalForSelectedSession()
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
        let currentWeek = Int(truncating: current.first ?? KotlinInt(value: 1))
        let currentYear = Int(truncating: current.second ?? KotlinInt(value: 2026))
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

    func loadJournalForSelectedSession() async {
        guard let bridge, let selectedSession else { return }
        autosaveTask?.cancel()
        do {
            let aggregate = try await bridge.plannerJournal(for: selectedSession)
            loadedAggregate = aggregate
            journalStore.loadedAggregate = aggregate
            replaceJournalDraft(PlannerJournalDraft(aggregate: aggregate))
            journalSaveState = .idle
            journalStore.journalSaveState = .idle
        } catch {
            loadedAggregate = nil
            journalStore.loadedAggregate = nil
            replaceJournalDraft(.empty)
            journalSaveState = .failed("No se pudo cargar el diario.")
            journalStore.journalSaveState = journalSaveState
        }
    }

    func scheduleAutosave() {
        guard !isHydratingDraft, selectedSession != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.saveJournal()
        }
    }

    func saveJournal() async {
        guard let bridge, let session = selectedSession else { return }
        autosaveTask?.cancel()
        journalSaveState = .saving
        let journalId = loadedAggregate?.journal.id ?? 0
        let status = computedStatus()
        let aggregate = SessionJournalAggregate(
            journal: SessionJournal(
                id: journalId,
                planningSessionId: session.id,
                teacherName: journalDraft.teacherName,
                scheduledSpace: journalDraft.scheduledSpace,
                usedSpace: journalDraft.usedSpace,
                unitLabel: journalDraft.unitLabel.isEmpty ? session.teachingUnitName : journalDraft.unitLabel,
                objectivePlanned: journalDraft.objectivePlanned,
                plannedText: journalDraft.plannedText,
                actualText: journalDraft.actualText,
                attainmentText: journalDraft.attainmentText,
                adaptationsText: journalDraft.adaptationsText,
                incidentsText: journalDraft.incidentsText,
                groupObservations: journalDraft.groupObservations,
                climateScore: Int32(journalDraft.climateScore),
                participationScore: Int32(journalDraft.participationScore),
                usefulTimeScore: Int32(journalDraft.usefulTimeScore),
                perceivedDifficultyScore: Int32(journalDraft.perceivedDifficultyScore),
                pedagogicalDecision: journalDraft.pedagogicalDecision,
                pendingTasksText: journalDraft.pendingTasksText,
                materialToPrepareText: journalDraft.materialToPrepareText,
                studentsToReviewText: journalDraft.studentsToReviewText,
                familyCommunicationText: journalDraft.familyCommunicationText,
                nextStepText: journalDraft.nextStepText,
                weatherText: journalDraft.weatherText,
                materialUsedText: journalDraft.materialUsedText,
                physicalIncidentsText: journalDraft.physicalIncidentsText,
                injuriesText: journalDraft.injuriesText,
                unequippedStudentsText: journalDraft.unequippedStudentsText,
                intensityScore: Int32(journalDraft.intensityScore),
                warmupMinutes: Int32(journalDraft.warmupMinutes),
                mainPartMinutes: Int32(journalDraft.mainPartMinutes),
                cooldownMinutes: Int32(journalDraft.cooldownMinutes),
                stationObservationsText: journalDraft.stationObservationsText,
                incidentTags: journalDraft.incidentTags,
                status: status
            ),
            individualNotes: journalDraft.notes.map {
                SessionJournalIndividualNote(
                    id: 0,
                    journalId: journalId,
                    studentId: $0.studentId.map { KotlinLong(value: $0) },
                    studentName: $0.studentName,
                    note: $0.note,
                    tag: $0.tag
                )
            },
            actions: journalDraft.actions.map {
                SessionJournalAction(
                    id: 0,
                    journalId: journalId,
                    title: $0.title,
                    detail: $0.detail,
                    isCompleted: $0.isCompleted
                )
            },
            media: journalDraft.media.map {
                SessionJournalMedia(
                    id: 0,
                    journalId: journalId,
                    type: $0.type,
                    uri: $0.uri,
                    transcript: $0.transcript,
                    caption: $0.caption
                )
            },
            links: journalDraft.links.map {
                SessionJournalLink(
                    id: 0,
                    journalId: journalId,
                    type: $0.type,
                    targetId: $0.targetId,
                    label: $0.label
                )
            }
        )

        do {
            _ = try await bridge.plannerSaveJournal(aggregate)
            loadedAggregate = try await bridge.plannerJournal(for: session)
            journalStore.loadedAggregate = loadedAggregate
            if let loadedAggregate {
                let refreshedDraft = PlannerJournalDraft(aggregate: loadedAggregate)
                if refreshedDraft != journalDraft {
                    replaceJournalDraft(refreshedDraft)
                }
            }
            let refreshedSummaries = (try? await bridge.plannerJournalSummaries(sessionIds: sessions.map(\.id))) ?? []
            journalSummaryBySessionId = Dictionary(uniqueKeysWithValues: refreshedSummaries.map { ($0.planningSessionId, $0) })
            journalStore.journalSummaryBySessionId = journalSummaryBySessionId
            journalSaveState = .saved(Date())
            journalStore.journalSaveState = journalSaveState
        } catch {
            journalSaveState = .failed(error.localizedDescription)
            journalStore.journalSaveState = journalSaveState
        }
    }

    func toggleSelection(sessionId: Int64) {
        if selectedSessionIds.contains(sessionId) {
            selectedSessionIds.remove(sessionId)
        } else {
            selectedSessionIds.insert(sessionId)
        }
    }

    func bulkCopyToNextWeek() async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        let result = try? await bridge.plannerCopySessions(
            sourceSessionIds: Array(selectedSessionIds),
            targetGroupId: nil,
            dayOffset: 7,
            periodOffset: 0,
            resolution: .skip
        )
        if let result {
            bulkSummary = "Copiadas \(result.movedOrCopied) · omitidas \(result.skipped + result.failed)"
        }
        selectionMode = false
        selectedSessionIds.removeAll()
        await reloadSessionsOnly()
    }

    func bulkMoveOneDay() async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        let result = try? await bridge.plannerShiftSessions(
            sourceSessionIds: Array(selectedSessionIds),
            dayOffset: 1,
            periodOffset: 0,
            resolution: .skip
        )
        if let result {
            bulkSummary = "Movidas \(result.movedOrCopied) · omitidas \(result.skipped + result.failed)"
        }
        selectionMode = false
        selectedSessionIds.removeAll()
        await reloadSessionsOnly()
    }

    func clearCurrentWeekSessionsWithoutSchedule(groupId: Int64? = nil) async {
        guard let bridge, effectiveScheduleSlots.isEmpty else { return }
        let ids = sessions
            .filter { session in
                (groupId == nil || session.groupId == groupId) && session.status != .completed
            }
            .map(\.id)
        guard !ids.isEmpty else {
            bulkSummary = "No hay sesiones planificadas que limpiar en esta semana."
            return
        }

        for id in ids {
            try? await bridge.plannerDeleteSession(sessionId: id)
        }
        selectedSessionIds.removeAll()
        selectedSession = nil
        bulkSummary = "Eliminadas \(ids.count) sesiones de la semana sin franjas de agenda."
        await reloadSessionsOnly(keepSelection: false)
    }

    func markCompleted(_ session: PlanningSession) async {
        guard let bridge else { return }
        _ = try? await bridge.plannerUpsertSession(
            id: session.id,
            teachingUnitId: session.teachingUnitId,
            teachingUnitName: session.teachingUnitName,
            teachingUnitColor: session.teachingUnitColor,
            groupId: session.groupId,
            groupName: session.groupName,
            dayOfWeek: Int(session.dayOfWeek),
            period: Int(session.period),
            weekNumber: Int(session.weekNumber),
            year: Int(session.year),
            objectives: session.objectives,
            activities: session.activities,
            evaluation: session.evaluation,
            linkedAssessmentIdsCsv: session.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: session.teacherScheduleSlotId?.int64Value,
            startTime: session.startTime,
            endTime: session.endTime,
            status: .completed
        )
        updateLocalSession(session, status: .completed)
        await reloadJournalSummaries()
    }

    func openComposer(for session: PlanningSession? = nil, day: Int? = nil, period: Int? = nil) {
        if let session {
            composerDraft = PlannerComposerDraft(
                groupId: session.groupId,
                sessionId: session.id,
                teachingUnitId: session.teachingUnitId == 0 ? nil : session.teachingUnitId,
                unitTitle: session.teachingUnitName,
                objectives: session.objectives,
                activities: session.activities,
                dayOfWeek: Int(session.dayOfWeek),
                period: Int(session.period),
                teacherScheduleSlotId: session.teacherScheduleSlotId?.int64Value,
                startTime: session.startTime,
                endTime: session.endTime,
                selectedInstrumentIds: Set(session.linkedAssessmentIdsCsv.split(separator: ",").map(String.init))
            )
        } else {
            let firstVisibleDay = visibleWeekdays.first ?? 1
            let firstVisiblePeriod = visibleSlots.first?.period ?? 1
            let resolvedDay = day ?? firstVisibleDay
            let resolvedPeriod = period ?? firstVisiblePeriod
            let slotMetadata = composerSlotMetadata(day: resolvedDay, period: resolvedPeriod, groupId: selectedGroupId ?? groups.first?.id)
            composerDraft = PlannerComposerDraft(
                groupId: selectedGroupId ?? groups.first?.id,
                teachingUnitId: nil,
                unitTitle: "",
                objectives: "",
                activities: "",
                dayOfWeek: resolvedDay,
                period: resolvedPeriod,
                teacherScheduleSlotId: slotMetadata.slotId,
                startTime: slotMetadata.startTime,
                endTime: slotMetadata.endTime
            )
        }
        composerSaveState = .idle
        Task { await refreshComposerContext() }
        showingComposer = true
    }

    @discardableResult
    func saveComposer() async -> Bool {
        guard let bridge, let groupId = composerDraft.groupId else {
            composerContextError = "Selecciona un grupo antes de guardar."
            composerSaveState = .failed(composerContextError)
            return false
        }
        let groupName = groups.first(where: { $0.id == groupId })?.name ?? "Grupo \(groupId)"
        let selectedInstruments = composerAvailableInstruments.filter { composerDraft.selectedInstrumentIds.contains($0.id) }
        let slotMetadata = composerSlotMetadata(day: composerDraft.dayOfWeek, period: composerDraft.period, groupId: groupId)
        isSavingComposer = true
        composerSaveState = .saving
        defer { isSavingComposer = false }
        do {
            let result = try await bridge.plannerSaveSessionWithLinks(
                id: composerDraft.sessionId,
                groupId: groupId,
                groupName: groupName,
                dayOfWeek: composerDraft.dayOfWeek,
                period: composerDraft.period,
                weekNumber: week,
                year: year,
                teachingUnitId: composerDraft.teachingUnitId,
                newTeachingUnitName: composerDraft.unitTitle,
                objectives: composerDraft.objectives,
                activities: composerDraft.activities,
                teacherScheduleSlotId: slotMetadata.slotId,
                startTime: slotMetadata.startTime,
                endTime: slotMetadata.endTime,
                selectedInstruments: selectedInstruments
            )
            composerContextError = ""
            composerSaveState = .saved(Date())
            showingComposer = false
            updateSessionFromComposerSave(result: result, groupId: groupId, groupName: groupName, slotMetadata: slotMetadata)
            return true
        } catch {
            composerContextError = "No se pudo guardar la sesión: \(error.localizedDescription)"
            composerSaveState = .failed(composerContextError)
            return false
        }
    }

    func toggleComposerInstrument(_ instrumentId: String) {
        if composerDraft.selectedInstrumentIds.contains(instrumentId) {
            composerDraft.selectedInstrumentIds.remove(instrumentId)
        } else {
            composerDraft.selectedInstrumentIds.insert(instrumentId)
        }
    }

    func refreshComposerContext() async {
        guard let bridge, let groupId = composerDraft.groupId else {
            composerTeachingUnits = []
            composerAvailableInstruments = []
            composerContextError = ""
            return
        }
        await composerStore.reloadContext(bridge: bridge, groupId: groupId, teachingUnitId: composerDraft.teachingUnitId)
        composerTeachingUnits = composerStore.teachingUnits
        composerAvailableInstruments = composerStore.availableInstruments
        composerContextError = composerStore.contextError
    }

    private func updateSessionFromComposerSave(
        result: PlannerSessionSaveResult,
        groupId: Int64,
        groupName: String,
        slotMetadata: (slotId: Int64?, startTime: String?, endTime: String?)
    ) {
        let previous = sessions.first(where: { $0.id == result.sessionId || $0.id == composerDraft.sessionId })
        let updated = PlanningSession(
            id: result.sessionId,
            teachingUnitId: result.teachingUnitId,
            teachingUnitName: result.teachingUnitName,
            teachingUnitColor: previous?.teachingUnitColor ?? EvaluationDesign.plannerCoursePalette.first ?? "#2563EB",
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: Int32(composerDraft.dayOfWeek),
            period: Int32(composerDraft.period),
            weekNumber: Int32(week),
            year: Int32(year),
            objectives: composerDraft.objectives,
            activities: composerDraft.activities,
            evaluation: result.evaluationSummary,
            linkedAssessmentIdsCsv: result.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: slotMetadata.slotId.map { KotlinLong(value: $0) },
            startTime: slotMetadata.startTime,
            endTime: slotMetadata.endTime,
            status: previous?.status ?? .planned
        )
        sessionStore.upsertLocal(updated)
        sessions = sessionStore.sessions
        applySearch()
        selectedSession = updated
        selectedGroupId = groupId
        rebuildVisiblePlannerStructure()
    }

    private func updateLocalSession(_ session: PlanningSession, status: SessionStatus) {
        let updated = PlanningSession(
            id: session.id,
            teachingUnitId: session.teachingUnitId,
            teachingUnitName: session.teachingUnitName,
            teachingUnitColor: session.teachingUnitColor,
            groupId: session.groupId,
            groupName: session.groupName,
            dayOfWeek: session.dayOfWeek,
            period: session.period,
            weekNumber: session.weekNumber,
            year: session.year,
            objectives: session.objectives,
            activities: session.activities,
            evaluation: session.evaluation,
            linkedAssessmentIdsCsv: session.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: session.teacherScheduleSlotId,
            startTime: session.startTime,
            endTime: session.endTime,
            status: status
        )
        sessionStore.upsertLocal(updated)
        sessions = sessionStore.sessions
        applySearch()
        if selectedSession?.id == session.id {
            selectedSession = updated
        }
        rebuildVisiblePlannerStructure()
    }

    private func composerSlotMetadata(day: Int, period: Int, groupId: Int64?) -> (slotId: Int64?, startTime: String?, endTime: String?) {
        let visibleSlot = visibleSlots.first(where: { $0.period == period })
        let scheduleSlot = teacherScheduleSlots.first { slot in
            guard Int(slot.dayOfWeek) == day else { return false }
            if let groupId, slot.schoolClassId != groupId { return false }
            if let visibleSlot {
                return slot.startTime == visibleSlot.startTime && slot.endTime == visibleSlot.endTime
            }
            return false
        }
        return (
            scheduleSlot?.id,
            scheduleSlot?.startTime ?? visibleSlot?.startTime,
            scheduleSlot?.endTime ?? visibleSlot?.endTime
        )
    }

    func addScheduleSlot() async {
        guard let bridge, let schedule = teacherSchedule, let groupId = scheduleFormGroupId else { return }
        scheduleSaveState = .saving
        do {
            _ = try await bridge.plannerSaveTeacherScheduleSlot(
                scheduleId: schedule.id,
                classId: groupId,
                subjectLabel: scheduleFormSubject,
                unitLabel: scheduleFormUnit.nilIfBlank,
                dayOfWeek: scheduleFormDay,
                startTime: scheduleFormStart,
                endTime: scheduleFormEnd
            )
            scheduleError = ""
            scheduleFormSubject = ""
            scheduleFormUnit = ""
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func buildScheduleGenerationPreview(groupId: Int64? = nil) {
        let targetSlots = effectiveScheduleSlots.filter { slot in
            guard let groupId else { return true }
            return slot.schoolClassId == groupId
        }
        let rows = Dictionary(grouping: targetSlots, by: \.schoolClassId)
            .compactMap { classId, slots -> PlannerScheduleGenerationPreviewRow? in
                let className = groups.first(where: { $0.id == classId })?.name ?? "Grupo \(classId)"
                let detected = slots.count
                let existing = slots.filter { slot in
                    sessions.contains { session in
                        session.groupId == slot.schoolClassId &&
                        Int(session.dayOfWeek) == Int(slot.dayOfWeek) &&
                        (
                            session.teacherScheduleSlotId?.int64Value == slot.id ||
                            (session.startTime == slot.startTime && session.endTime == slot.endTime) ||
                            Int(session.period) == period(for: slot)
                        )
                    }
                }.count
                return PlannerScheduleGenerationPreviewRow(
                    classId: classId,
                    className: className,
                    detectedSessions: detected,
                    existingSessions: existing
                )
            }
            .sorted { $0.className < $1.className }
        scheduleGenerationPreview = rows
        let totals = rows.reduce(into: (detected: 0, omitted: 0)) { result, row in
            result.detected += row.detectedSessions
            result.omitted += row.existingSessions
        }
        scheduleGenerationSummary = "\(totals.detected) franjas detectadas · \(totals.omitted) sesiones ya existentes omitidas"
    }

    func generateSessionsFromSchedule(groupId: Int64? = nil) async {
        guard let bridge else { return }
        let targetSlots = effectiveScheduleSlots.filter { slot in
            guard let groupId else { return true }
            return slot.schoolClassId == groupId
        }
        guard !targetSlots.isEmpty else {
            scheduleGenerationSummary = "No hay franjas para generar sesiones."
            return
        }
        isGeneratingScheduleSessions = true
        defer { isGeneratingScheduleSessions = false }

        var created = 0
        var omitted = 0
        for slot in targetSlots {
            let slotPeriod = period(for: slot)
            let alreadyExists = sessions.contains { session in
                session.groupId == slot.schoolClassId &&
                Int(session.dayOfWeek) == Int(slot.dayOfWeek) &&
                (
                    session.teacherScheduleSlotId?.int64Value == slot.id ||
                    (session.startTime == slot.startTime && session.endTime == slot.endTime) ||
                    Int(session.period) == slotPeriod
                )
            }
            if alreadyExists {
                omitted += 1
                continue
            }

            do {
                _ = try await bridge.plannerSaveSessionWithLinks(
                    id: 0,
                    groupId: slot.schoolClassId,
                    groupName: groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                    dayOfWeek: Int(slot.dayOfWeek),
                    period: slotPeriod,
                    weekNumber: week,
                    year: year,
                    teachingUnitId: nil,
                    newTeachingUnitName: slot.unitLabel?.nilIfBlank ?? slot.subjectLabel.nilIfBlank ?? "Planificación semanal",
                    objectives: "",
                    activities: "",
                    teacherScheduleSlotId: slot.id,
                    startTime: slot.startTime,
                    endTime: slot.endTime,
                    selectedInstruments: []
                )
                created += 1
            } catch {
                omitted += 1
                scheduleGenerationSummary = "No se pudo generar una sesión: \(error.localizedDescription)"
            }
        }

        await reloadSessionsOnly(keepSelection: false)
        buildScheduleGenerationPreview(groupId: groupId)
        scheduleGenerationSummary = "\(created) sesiones creadas · \(omitted) omitidas"
    }

    private func period(for slot: TeacherScheduleSlot) -> Int {
        if let visibleSlot = visibleSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime }) {
            return visibleSlot.period
        }
        if let defaultSlot = timeSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime }) {
            return Int(defaultSlot.period)
        }
        return Int(slot.dayOfWeek) * 100 + Int(slot.id % 100)
    }

    func deleteScheduleSlot(_ slotId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteTeacherScheduleSlot(slotId: slotId)
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func saveTeacherSchedule() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        scheduleSaveState = .saving
        do {
            let savedId = try await bridge.plannerSaveTeacherSchedule(
                scheduleId: schedule.id,
                ownerUserId: schedule.ownerUserId,
                academicYearId: schedule.academicYearId,
                name: scheduleName,
                startDateIso: scheduleStartDate,
                endDateIso: scheduleEndDate,
                activeWeekdaysCsv: activeWeekdays.sorted().map(String.init).joined(separator: ","),
                trace: schedule.trace
            )
            teacherSchedule = TeacherSchedule(
                id: savedId,
                ownerUserId: schedule.ownerUserId,
                academicYearId: schedule.academicYearId,
                name: scheduleName,
                startDateIso: scheduleStartDate,
                endDateIso: scheduleEndDate,
                activeWeekdaysCsv: activeWeekdays.sorted().map(String.init).joined(separator: ","),
                trace: schedule.trace
            )
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func addEvaluationPeriod() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        let normalizedName = evaluationFormName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            scheduleError = "Añade un nombre para la evaluación."
            scheduleSaveState = .failed(scheduleError)
            return
        }
        scheduleSaveState = .saving
        do {
            _ = try await bridge.plannerSaveEvaluationPeriod(
                periodId: 0,
                scheduleId: schedule.id,
                name: normalizedName,
                startDateIso: evaluationFormStart,
                endDateIso: evaluationFormEnd,
                sortOrder: evaluationPeriods.count + 1
            )
            evaluationFormName = ""
            evaluationFormStart = ""
            evaluationFormEnd = ""
            scheduleError = ""
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func deleteEvaluationPeriod(_ periodId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteEvaluationPeriod(periodId: periodId)
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func toggleActiveWeekday(_ day: Int) {
        if activeWeekdays.contains(day) {
            activeWeekdays.remove(day)
        } else {
            activeWeekdays.insert(day)
        }
    }

    func dayLabel(for day: Int) -> String {
        switch day {
        case 1: return "Lun"
        case 2: return "Mar"
        case 3: return "Mié"
        case 4: return "Jue"
        case 5: return "Vie"
        case 6: return "Sáb"
        case 7: return "Dom"
        default: return "D\(day)"
        }
    }

    func appendIncidentLink() async {
        guard let bridge, let session = selectedSession else { return }
        let title = journalDraft.incidentsText.nilIfBlank ?? "Incidencia de sesión"
        let detail = "Grupo \(session.groupName) · \(journalDraft.actualText.nilIfBlank ?? session.activities)"
        if let link = try? await bridge.plannerRegisterJournalIncident(session: session, title: title, detail: detail) {
            journalDraft.links.append(
                PlannerJournalDraftLink(
                    type: link.type,
                    targetId: link.targetId,
                    label: link.label
                )
            )
            if !journalDraft.incidentTags.contains("Incidencia") {
                journalDraft.incidentTags.append("Incidencia")
            }
        }
    }

    func appendTraceLink(type: SessionJournalLinkType, label: String) {
        journalDraft.links.append(
            PlannerJournalDraftLink(
                type: type,
                targetId: UUID().uuidString,
                label: label
            )
        )
    }

    func exportText() -> String {
        guard let session = selectedSession else { return "Sin sesión seleccionada" }
        return """
        Diario · \(session.teachingUnitName) · \(session.groupName)
        Objetivo previsto: \(journalDraft.objectivePlanned)
        Lo planificado: \(journalDraft.plannedText)
        Lo realizado: \(journalDraft.actualText)
        Participación: \(journalDraft.participationScore)/5
        Clima: \(journalDraft.climateScore)/5
        Tiempo útil: \(journalDraft.usefulTimeScore)/5
        Próximo paso: \(journalDraft.nextStepText)
        """
    }

    private func computedStatus() -> SessionJournalStatus {
        let importantFields = [
            journalDraft.actualText,
            journalDraft.plannedText,
            journalDraft.nextStepText,
            journalDraft.groupObservations
        ].joined()
        if importantFields.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && journalDraft.notes.isEmpty && journalDraft.actions.isEmpty {
            return .empty
        }
        let metricsReady = journalDraft.participationScore > 0 && journalDraft.climateScore > 0 && journalDraft.usefulTimeScore > 0
        let closingReady = !journalDraft.nextStepText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return metricsReady && closingReady ? .completed : .draft
    }

    private func reloadScheduleConfiguration() async {
        guard let bridge else { return }
        scheduleFormGroupId = await scheduleStore.reload(bridge: bridge, groups: groups, scheduleFormGroupId: scheduleFormGroupId)
        teacherSchedule = scheduleStore.teacherSchedule
        teacherScheduleSlots = scheduleStore.teacherScheduleSlots
        weeklySlots = scheduleStore.weeklySlots
        evaluationPeriods = scheduleStore.evaluationPeriods
        forecastRows = scheduleStore.forecastRows
        scheduleError = scheduleStore.scheduleError
        if let schedule = teacherSchedule {
            scheduleName = schedule.name
            scheduleStartDate = schedule.startDateIso
            scheduleEndDate = schedule.endDateIso
            activeWeekdays = Set(
                schedule.activeWeekdaysCsv
                    .split(separator: ",")
                    .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            )
            rebuildVisiblePlannerStructure()
        }
    }

    private func replaceJournalDraft(_ draft: PlannerJournalDraft) {
        autosaveTask?.cancel()
        isHydratingDraft = true
        journalDraft = draft
        journalStore.journalDraft = draft
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.isHydratingDraft = false
        }
    }

    private static func isoWeeks(in year: Int) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let date = DateComponents(calendar: calendar, year: year, month: 12, day: 28).date ?? Date()
        return calendar.component(.weekOfYear, from: date)
    }

    private func rebuildVisiblePlannerStructure() {
        let relevantTeacherSlots = teacherScheduleSlots
        let relevantWeeklySlots = weeklySlots

        var rangesByPeriod: [Int: PlannerVisibleSlot] = [:]
        for slot in timeSlots {
            rangesByPeriod[Int(slot.period)] = PlannerVisibleSlot(
                period: Int(slot.period),
                startTime: slot.startTime,
                endTime: slot.endTime
            )
        }

        for session in sessions {
            if let matchingDefault = timeSlots.first(where: { Int($0.period) == Int(session.period) }) {
                rangesByPeriod[Int(session.period)] = PlannerVisibleSlot(
                    period: Int(session.period),
                    startTime: matchingDefault.startTime,
                    endTime: matchingDefault.endTime
                )
            } else if let startTime = session.startTime, let endTime = session.endTime {
                rangesByPeriod[Int(session.period)] = PlannerVisibleSlot(
                    period: Int(session.period),
                    startTime: startTime,
                    endTime: endTime
                )
            }
        }

        struct TimeRange: Hashable {
            let start: String
            let end: String
        }
        let teacherRanges: [TimeRange] = relevantTeacherSlots.map { TimeRange(start: $0.startTime, end: $0.endTime) }
        let weeklyRanges: [TimeRange] = relevantWeeklySlots.map { TimeRange(start: $0.startTime, end: $0.endTime) }
        let allRanges: [TimeRange] = teacherRanges + weeklyRanges
        let filteredRanges: [TimeRange] = allRanges.filter { range in
            !timeSlots.contains(where: { $0.startTime == range.start && $0.endTime == range.end })
        }
        let uniqueCustomRanges = Set(filteredRanges)
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
            }

        var nextCustomPeriod = (timeSlots.map { Int($0.period) }.max() ?? 0) + 1
        for range in uniqueCustomRanges {
            rangesByPeriod[nextCustomPeriod] = PlannerVisibleSlot(
                period: nextCustomPeriod,
                startTime: range.start,
                endTime: range.end
            )
            nextCustomPeriod += 1
        }

        let scheduleDerivedSlots = rangesByPeriod.values.sorted {
            $0.startTime == $1.startTime ? $0.endTime < $1.endTime : $0.startTime < $1.startTime
        }

        visibleSlots = scheduleDerivedSlots.isEmpty
            ? timeSlots.map {
                PlannerVisibleSlot(period: Int($0.period), startTime: $0.startTime, endTime: $0.endTime)
            }
            : scheduleDerivedSlots

        let activeDays = Set(activeWeekdays)
        let slotDays = Set(relevantTeacherSlots.map { Int($0.dayOfWeek) } + relevantWeeklySlots.map { Int($0.dayOfWeek) })
        let mergedDays = activeDays.union(slotDays)
        let sortedDays = mergedDays.isEmpty ? [1, 2, 3, 4, 5] : mergedDays.sorted()
        visibleWeekdays = sortedDays.filter { (1...7).contains($0) }

        if !visibleWeekdays.contains(composerDraft.dayOfWeek) {
            composerDraft.dayOfWeek = visibleWeekdays.first ?? 1
        }
        if !visibleSlots.contains(where: { $0.period == composerDraft.period }) {
            composerDraft.period = visibleSlots.first?.period ?? 1
        }
    }

    func entries(for day: Int, period: Int) -> [PlannerWeekCellEntry] {
        let sessionEntries = sessions
            .filter { Int($0.dayOfWeek) == day && Int($0.period) == period }
            .sorted {
                if $0.groupName == $1.groupName { return $0.teachingUnitName < $1.teachingUnitName }
                return $0.groupName < $1.groupName
            }
            .map { session in
                let summary = summary(for: session.id)
                let sections = previewSections(
                    teachingUnitName: session.teachingUnitName,
                    objective: session.objectives,
                    activity: session.activities,
                    evaluation: session.evaluation
                )
                let preview = sections.first?.value ?? preferredPreviewText(
                    objective: session.objectives,
                    activity: session.activities,
                    evaluation: session.evaluation
                )
                let completed = session.status == .completed || summary?.status == .completed
                return PlannerWeekCellEntry(
                    id: "session-\(session.id)",
                    kind: .session,
                    classId: session.groupId,
                    className: session.groupName,
                    classColorHex: classColorHex(for: session.groupId),
                    dayOfWeek: Int(session.dayOfWeek),
                    period: Int(session.period),
                    title: session.teachingUnitName,
                    preview: preview,
                    sectionPreviews: sections,
                    sessionId: session.id,
                    sessionStatus: session.status,
                    journalStatus: summary?.status,
                    scheduledSlotId: nil,
                    isCompleted: completed
                )
            }

        let existingClassIds = Set(sessionEntries.map(\.classId))
        let scheduledEntries = teacherScheduleSlots
            .filter { slot in
                guard Int(slot.dayOfWeek) == day else { return false }
                guard let visibleSlot = visibleSlots.first(where: { $0.period == period }) else { return false }
                return slot.startTime == visibleSlot.startTime && slot.endTime == visibleSlot.endTime && !existingClassIds.contains(slot.schoolClassId)
            }
            .sorted { lhs, rhs in
                let lhsName = groups.first(where: { $0.id == lhs.schoolClassId })?.name ?? ""
                let rhsName = groups.first(where: { $0.id == rhs.schoolClassId })?.name ?? ""
                return lhsName < rhsName
            }
            .map { slot in
                PlannerWeekCellEntry(
                    id: "slot-\(slot.id)",
                    kind: .scheduledSlot,
                    classId: slot.schoolClassId,
                    className: groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                    classColorHex: classColorHex(for: slot.schoolClassId),
                    dayOfWeek: Int(slot.dayOfWeek),
                    period: period,
                    title: slot.unitLabel?.nilIfBlank ?? slot.subjectLabel.nilIfBlank ?? "Franja preparada",
                    preview: slot.subjectLabel.nilIfBlank ?? "Pendiente de concretar",
                    sectionPreviews: [
                        PlannerSectionPreview(title: "Curso", value: groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)"),
                        PlannerSectionPreview(title: "Bloque", value: slot.unitLabel?.nilIfBlank ?? slot.subjectLabel.nilIfBlank ?? "Pendiente")
                    ],
                    sessionId: nil,
                    sessionStatus: nil,
                    journalStatus: nil,
                    scheduledSlotId: slot.id,
                    isCompleted: false
                )
            }

        return sessionEntries + scheduledEntries
    }

    private func preferredPreviewText(objective: String, activity: String, evaluation: String) -> String {
        if let objective = objective.nilIfBlank { return objective }
        if let activity = activity.nilIfBlank { return activity }
        if let evaluation = evaluation.nilIfBlank { return evaluation }
        return "Sesión por concretar"
    }

    private func previewSections(
        teachingUnitName: String,
        objective: String,
        activity: String,
        evaluation: String
    ) -> [PlannerSectionPreview] {
        var sections: [PlannerSectionPreview] = []
        if let unit = teachingUnitName.nilIfBlank {
            sections.append(.init(title: "SA", value: unit))
        }
        if let objective = objective.nilIfBlank {
            sections.append(.init(title: "Objetivos", value: objective))
        }
        if let activity = activity.nilIfBlank {
            sections.append(.init(title: "Resumen", value: activity))
        }
        if let evaluation = evaluation.nilIfBlank {
            sections.append(.init(title: "Evaluación", value: evaluation))
        }
        return sections
    }
}

struct PlannerWorkspaceIOS: View {
    @EnvironmentObject private var bridge: KmpBridge
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = PlannerWorkspaceViewModel()
    private let initialSection: PlannerWorkspaceSection
    private let context: PlannerNavigationContext
    private let onOpenDiary: ((PlannerNavigationContext) -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onNavigationContextChange: ((PlannerNavigationContext) -> Void)?

    init(
        initialSection: PlannerWorkspaceSection = .week,
        context: PlannerNavigationContext = PlannerNavigationContext(),
        onOpenDiary: ((PlannerNavigationContext) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onNavigationContextChange: ((PlannerNavigationContext) -> Void)? = nil
    ) {
        self.initialSection = initialSection
        self.context = context
        self.onOpenDiary = onOpenDiary
        self.onOpenSettings = onOpenSettings
        self.onNavigationContextChange = onNavigationContextChange
    }

    var body: some View {
        plannerMainContent
        .task {
            await vm.bind(bridge: bridge)
            vm.activeSection = initialSection
            await vm.applyExternalContext(
                week: context.week,
                year: context.year,
                groupId: context.groupId,
                sessionId: context.sessionId
            )
            configurePlannerToolbar()
            syncNavigationContext()
        }
        .onAppear(perform: configurePlannerToolbar)
        .appOnChange(of: context) { newValue in
            Task {
                await vm.applyExternalContext(
                    week: newValue.week,
                    year: newValue.year,
                    groupId: newValue.groupId,
                    sessionId: newValue.sessionId
                )
                syncNavigationContext()
            }
        }
        .appOnChange(of: vm.selectedSession?.id) { _ in configurePlannerToolbar() }
        .appOnChange(of: vm.activeSection) { _ in configurePlannerToolbar() }
        .appOnChange(of: vm.week) { _ in syncNavigationContext() }
        .appOnChange(of: vm.year) { _ in syncNavigationContext() }
        .appOnChange(of: vm.selectedGroupId) { _ in syncNavigationContext() }
        .appOnChange(of: vm.selectedSession?.id) { _ in syncNavigationContext() }
        .sheet(isPresented: $vm.showingComposer) {
            PlannerSessionComposerSheet(vm: vm)
        }
        .onDisappear {
            layoutState.clearPlannerToolbar()
        }
    }

    private var plannerMainContent: some View {
        VStack(spacing: 0) {
            if vm.activeSection != .schedule {
                PlannerToolbar(vm: vm, onOpenDiary: openSelectedSessionInDiary)
                Divider().opacity(0.18)
            }
            Group {
                switch vm.activeSection {
                case .week:
                    PlannerWeekBoard(vm: vm, onOpenDiary: openSessionInDiary)
                case .sessions:
                    PlannerSessionsList(vm: vm, source: vm.filteredSessions, onOpenDiary: openSessionInDiary)
                case .schedule:
                    PlannerScheduleBoard(vm: vm, onOpenSettings: onOpenSettings)
                }
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        }
    }

    private func configurePlannerToolbar() {
        layoutState.configurePlannerToolbar(addSessionAvailable: true) {
            vm.openComposer()
        }
    }

    private func openSelectedSessionInDiary() {
        guard let session = vm.selectedSession else { return }
        openSessionInDiary(session)
    }

    private func openSessionInDiary(_ session: PlanningSession) {
        onOpenDiary?(
            PlannerNavigationContext(
                week: vm.week,
                year: vm.year,
                groupId: session.groupId,
                sessionId: session.id
            )
        )
    }

    private func syncNavigationContext() {
        onNavigationContextChange?(
            PlannerNavigationContext(
                week: vm.week,
                year: vm.year,
                groupId: vm.selectedGroupId,
                sessionId: vm.selectedSession?.id
            )
        )
    }
}

private struct PlannerToolbar: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenDiary: () -> Void
    @State private var isClearSchedulelessWeekConfirmationPresented = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.weekLabel)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text(vm.dateRangeLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await vm.previousWeek() } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                Button { Task { await vm.nextWeek() } } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                ShareLink(item: vm.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                IOSSearchField(text: $vm.searchText, placeholder: "Buscar sesión, unidad, objetivo…")
                    .appOnChange(of: vm.searchText) { _ in vm.applySearch() }

                Menu {
                    Button(vm.selectionMode ? "Salir de selección" : "Seleccionar sesiones") {
                        vm.selectionMode.toggle()
                        if !vm.selectionMode { vm.selectedSessionIds.removeAll() }
                    }
                    Button("Copiar a la semana siguiente") { Task { await vm.bulkCopyToNextWeek() } }
                        .disabled(vm.selectedSessionIds.isEmpty)
                    Button("Mover +1 día") { Task { await vm.bulkMoveOneDay() } }
                        .disabled(vm.selectedSessionIds.isEmpty)
                    Divider()
                    Button("Limpiar semana sin franjas", role: .destructive) {
                        isClearSchedulelessWeekConfirmationPresented = true
                    }
                    .disabled(!vm.canClearSchedulelessWeekSessions)
                } label: {
                    Label("Acciones", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "Eliminar sesiones de esta semana",
                    isPresented: $isClearSchedulelessWeekConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Eliminar sesiones planificadas", role: .destructive) {
                        Task { await vm.clearCurrentWeekSessionsWithoutSchedule() }
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("No hay franjas en la agenda. Se eliminarán las sesiones planificadas de la semana actual y se conservarán las completadas.")
                }

                if vm.selectedSession != nil {
                    Button(action: onOpenDiary) {
                        Label("Abrir diario", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !vm.bulkSummary.isEmpty {
                Text(vm.bulkSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, EvaluationDesign.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

private struct PlannerWeekBoard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenDiary: (PlanningSession) -> Void

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cellHeader("Franja", width: 110)
                    ForEach(vm.visibleWeekdays, id: \.self) { day in
                        cellHeader(vm.dayLabel(for: day), width: 230)
                    }
                }

                ForEach(vm.visibleSlots, id: \.period) { slot in
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text(slot.period > 9 ? "Fx" : "P\(slot.period)")
                                .font(.caption.bold())
                            Text(slot.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 110, height: 150)
                        .background(EvaluationDesign.surfaceSoft)

                        ForEach(vm.visibleWeekdays, id: \.self) { day in
                            PlannerWeekCellCard(
                                entries: vm.entries(for: day, period: Int(slot.period)),
                                onCreate: {
                                    vm.openComposer(day: day, period: Int(slot.period))
                                },
                                onOpenEntry: { entry in
                                    if let sessionId = entry.sessionId,
                                       let session = vm.sessions.first(where: { $0.id == sessionId }) {
                                        if vm.selectionMode {
                                            vm.toggleSelection(sessionId: session.id)
                                        } else {
                                            onOpenDiary(session)
                                        }
                                    } else {
                                        vm.selectGroup(entry.classId)
                                        vm.openComposer(day: day, period: Int(slot.period))
                                        vm.composerDraft.groupId = entry.classId
                                    }
                                },
                                onEditEntry: { entry in
                                    guard let sessionId = entry.sessionId,
                                          let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
                                    vm.openComposer(for: session)
                                },
                                onDuplicateEntry: { entry in
                                    guard let sessionId = entry.sessionId else { return }
                                    vm.selectedSessionIds = [sessionId]
                                    Task { await vm.bulkCopyToNextWeek() }
                                },
                                onCompleteEntry: { entry in
                                    guard let sessionId = entry.sessionId,
                                          let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
                                    Task { await vm.markCompleted(session) }
                                },
                                onOpenDiaryEntry: { entry in
                                    guard let sessionId = entry.sessionId,
                                          let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
                                    onOpenDiary(session)
                                }
                            )
                        }
                    }
                }
            }
            .padding(EvaluationDesign.screenPadding)
        }
    }

    private func cellHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.bold())
            .frame(width: width, height: 42)
            .background(EvaluationDesign.surfaceSoft)
    }
}

private struct PlannerWeekCellCard: View {
    let entries: [PlannerWeekCellEntry]
    let onCreate: () -> Void
    let onOpenEntry: (PlannerWeekCellEntry) -> Void
    let onEditEntry: (PlannerWeekCellEntry) -> Void
    let onDuplicateEntry: (PlannerWeekCellEntry) -> Void
    let onCompleteEntry: (PlannerWeekCellEntry) -> Void
    let onOpenDiaryEntry: (PlannerWeekCellEntry) -> Void

    var body: some View {
        let singleRichEntry = entries.count == 1 && entries.first?.kind == .session
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Button(action: onCreate) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("Libre")
                            .font(.caption.weight(.bold))
                        Text("Añadir sesión")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(entries.prefix(singleRichEntry ? 1 : 3)) { entry in
                    PlannerWeekEntryCard(
                        entry: entry,
                        fillsCell: singleRichEntry,
                        onTap: { onOpenEntry(entry) },
                        onEdit: { onEditEntry(entry) },
                        onDuplicate: { onDuplicateEntry(entry) },
                        onComplete: { onCompleteEntry(entry) },
                        onOpenDiary: { onOpenDiaryEntry(entry) }
                    )
                }
                if !singleRichEntry && entries.count > 3 {
                    Text("+\(entries.count - 3) más")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: 230, height: 150, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvaluationDesign.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }
}

private struct PlannerWeekEntryCard: View {
    let entry: PlannerWeekCellEntry
    let fillsCell: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onComplete: () -> Void
    let onOpenDiary: () -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(tint)
                        .frame(width: 10, height: 24)
                    Text(entry.className)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if entry.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(EvaluationDesign.success)
                    } else if entry.kind == .session {
                        Text("Planificada")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint.opacity(0.9))
                    }
                }

                ScrollView(.vertical, showsIndicators: fillsCell) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entry.sectionPreviews) { section in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Text(section.value)
                                    .font(section.title == "SA" ? .caption.weight(.bold) : .caption2)
                                    .foregroundColor(entry.isCompleted ? Color.primary.opacity(0.92) : Color.primary.opacity(0.86))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if entry.sectionPreviews.isEmpty {
                            Text(entry.preview)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: entry.isCompleted ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.sessionId != nil {
                Button("Abrir diario", action: onOpenDiary)
                Button("Edición rápida", action: onEdit)
                Button("Duplicar próxima semana", action: onDuplicate)
                Button("Marcar impartida", action: onComplete)
            }
        }
    }

    private var backgroundFill: Color {
        switch entry.kind {
        case .scheduledSlot:
            return tint.opacity(0.10)
        case .session:
            return entry.isCompleted ? tint.opacity(0.24) : tint.opacity(0.14)
        }
    }

    private var borderColor: Color {
        switch entry.kind {
        case .scheduledSlot:
            return tint.opacity(0.35)
        case .session:
            return entry.isCompleted ? tint.opacity(0.8) : tint.opacity(0.45)
        }
    }
}

private struct PlannerStatusPill: View {
    let status: SessionJournalStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
    }

    private var label: String {
        switch status {
        case .empty: return "Vacío"
        case .draft: return "Borrador"
        case .completed: return "Cerrado"
        default: return "Borrador"
        }
    }

    private var tint: Color {
        switch status {
        case .empty: return .secondary
        case .draft: return EvaluationDesign.accent
        case .completed: return EvaluationDesign.success
        default: return EvaluationDesign.accent
        }
    }
}

private struct PlannerSessionsList: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let source: [PlanningSession]
    let onOpenDiary: (PlanningSession) -> Void

    var body: some View {
        List(source, id: \.id) { session in
            Button {
                Task { await vm.select(session: session) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.teachingUnitName)
                            .font(.headline)
                        Text("\(session.groupName) · \(vm.timeLabel(for: Int(session.period)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.objectives)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    PlannerStatusPill(status: vm.summary(for: session.id)?.status ?? .empty)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Abrir diario") {
                    onOpenDiary(session)
                }
            }
        }
    }
}

private struct PlannerScheduleBoard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSettings: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                IOSSectionCard(title: "Resumen operativo", systemImage: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("La configuración editable vive ahora en Ajustes para que Planner conserve una sola tarea principal.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            IOSMetricCard(title: "Agenda", value: vm.scheduleName, tint: .blue)
                            IOSMetricCard(title: "Curso", value: "\(vm.scheduleStartDate) · \(vm.scheduleEndDate)", tint: .indigo)
                            IOSMetricCard(title: "Franjas", value: "\(vm.visibleScheduleSlotsSummaryCount)", tint: .teal)
                            IOSMetricCard(title: "Evaluaciones", value: "\(vm.evaluationPeriods.count)", tint: .orange)
                        }

                        Label(vm.activeWeekdaySummary, systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let onOpenSettings {
                            Button("Configurar en Ajustes") {
                                onOpenSettings()
                            }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                IOSSectionCard(title: "Franjas activas", systemImage: "clock.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Resumen de las franjas que ya están alimentando el tablero semanal actual.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        if vm.effectiveScheduleSlots.isEmpty {
                            Text("Todavía no hay franjas definidas para esta agenda.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if vm.isUsingLegacyWeeklySlots {
                            Text("Mostrando franjas heredadas del horario original de KMP Desktop.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(vm.effectiveScheduleSlots, id: \.id) { slot in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(vm.dayLabel(for: Int(slot.dayOfWeek))) · \(slot.startTime)-\(slot.endTime)")
                                        .font(.body.weight(.semibold))
                                    Text([
                                        vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                                        slot.subjectLabel,
                                        slot.unitLabel
                                    ]
                                    .compactMap { value in
                                        guard let string = value?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
                                        return string
                                    }
                                    .joined(separator: " · "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                IOSSectionCard(title: "Previsión lectiva", systemImage: "calendar.badge.exclamationmark") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Sigue visible en Planner para contrastar lo previsto con lo ya creado, pero se edita desde Ajustes.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        if vm.evaluationPeriods.isEmpty {
                            Text("Aún no hay periodos evaluativos configurados.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.evaluationPeriods.sorted(by: { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }), id: \.id) { period in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(period.name)
                                                .font(.headline)
                                            Text("\(period.startDateIso) · \(period.endDateIso)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    let periodForecast = vm.forecastRows.filter { $0.periodId == period.id }
                                    if periodForecast.isEmpty {
                                        Text("Sin previsión todavía. Añade franjas o revisa las fechas del curso.")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(Array(periodForecast.enumerated()), id: \.offset) { _, row in
                                            PlannerForecastRowView(row: row)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(EvaluationDesign.surfaceSoft)
                                )
                            }
                        }
                    }
                }
            }
            .padding(IOSAppStyle.pagePadding)
        }
    }
}

// PlannerSummaryMetric removed in favor of IOSMetricCard

private struct PlannerForecastRowView: View {
    let row: PlannerSessionForecast

    private var deltaColor: Color {
        row.remainingSessions > 0 ? EvaluationDesign.danger : EvaluationDesign.success
    }

    var body: some View {
        HStack {
            Text(row.className)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Previstas \(row.expectedSessions)")
                .font(.caption.weight(.bold))
            Text("Creadas \(row.plannedSessions)")
                .font(.caption.weight(.bold))
            Text("Δ \(row.remainingSessions)")
                .font(.caption.weight(.bold))
                .foregroundStyle(deltaColor)
        }
    }
}

enum SessionJournalEFVisibility {
    case always
    case contextual
    case hidden
}

struct PlannerJournalDetailPane: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var efVisibility: SessionJournalEFVisibility = .always
    @StateObject private var recorder = PlannerAudioRecorder()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Group {
            if let session = vm.selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: EvaluationDesign.cardSpacing) {
                        SessionJournalHeaderCard(vm: vm, session: session)
                        SessionJournalDevelopmentCard(vm: vm)
                        SessionJournalEvaluationCard(vm: vm)
                        SessionJournalClosingCard(vm: vm)
                        JournalIndividualNotesList(vm: vm)
                        JournalActionBar(vm: vm)
                        JournalMediaDock(
                            vm: vm,
                            recorder: recorder,
                            selectedPhoto: $selectedPhoto
                        )
                        if shouldShowEFCard(for: session) {
                            SessionJournalEFCard(vm: vm)
                        }
                    }
                    .padding(EvaluationDesign.screenPadding)
                }
                .appOnChange(of: vm.journalDraft) { _ in
                    vm.scheduleAutosave()
                }
                .appOnChange(of: selectedPhoto) { item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let url = persistMediaData(data, ext: "jpg") {
                            vm.journalDraft.media.append(
                                PlannerJournalDraftMedia(type: .photo, uri: url.absoluteString, caption: "Foto de sesión")
                            )
                        }
                        selectedPhoto = nil
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selecciona una sesión")
                        .font(.title2.weight(.black))
                    Text("La ficha de diario aparecerá aquí con edición inline, métricas y multimedia.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(EvaluationDesign.screenPadding)
            }
        }
    }

    private func shouldShowEFCard(for session: PlanningSession) -> Bool {
        switch efVisibility {
        case .always:
            return true
        case .hidden:
            return false
        case .contextual:
            if vm.journalDraft.intensityScore > 0
                || vm.journalDraft.warmupMinutes > 0
                || vm.journalDraft.mainPartMinutes > 0
                || vm.journalDraft.cooldownMinutes > 0 {
                return true
            }

            let efTexts = [
                vm.journalDraft.weatherText,
                vm.journalDraft.usedSpace,
                vm.journalDraft.materialUsedText,
                vm.journalDraft.physicalIncidentsText,
                vm.journalDraft.injuriesText,
                vm.journalDraft.unequippedStudentsText,
                vm.journalDraft.stationObservationsText,
                session.groupName,
                session.teachingUnitName,
                session.objectives,
                session.activities,
                session.evaluation
            ]
                .joined(separator: " ")
                .lowercased()

            let efSignals = [
                "educación física",
                "educacion fisica",
                "ef",
                "calentamiento",
                "vuelta a la calma",
                "material",
                "pista",
                "circuito",
                "motriz"
            ]

            return efSignals.contains { efTexts.contains($0) }
        }
    }

    private func persistMediaData(_ data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("planner_media_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private struct SessionJournalHeaderCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession

    var body: some View {
        EvaluationGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                EvaluationSectionTitle(
                    eyebrow: "Diario",
                    title: session.teachingUnitName,
                    subtitle: "\(session.groupName) · \(vm.timeLabel(for: Int(session.period)))"
                )

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    quickField("Fecha", value: vm.dateRangeLabel)
                    quickField("Grupo", value: session.groupName)
                    quickField("Hora", value: vm.timeLabel(for: Int(session.period)))
                    editableField("Profesor", text: $vm.journalDraft.teacherName)
                    editableField("Espacio", text: $vm.journalDraft.scheduledSpace)
                    editableField("Unidad / SA", text: $vm.journalDraft.unitLabel)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Objetivo previsto")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Pase y juego sin balón", text: $vm.journalDraft.objectivePlanned)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }

    private func quickField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Sin dato" : value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editableField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalDevelopmentCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Desarrollo",
            title: "Lo planificado y lo realizado",
            subtitle: "Registro estructurado de la sesión, no bloc libre."
        ) {
            JournalTextBlock(title: "Qué estaba planificado", text: $vm.journalDraft.plannedText)
            JournalTextBlock(title: "Qué se ha hecho realmente", text: $vm.journalDraft.actualText)
            JournalTextBlock(title: "Nivel de consecución", text: $vm.journalDraft.attainmentText)
            JournalTextBlock(title: "Adaptaciones realizadas", text: $vm.journalDraft.adaptationsText)
            JournalTextBlock(title: "Incidencias", text: $vm.journalDraft.incidentsText)
            JournalTextBlock(title: "Observaciones del grupo", text: $vm.journalDraft.groupObservations)

            JournalQuickChips(
                title: "Incidencias",
                options: ["Lesión", "Equipación", "Material", "Clima", "Espacio", "Tiempo"],
                selected: $vm.journalDraft.incidentTags
            )
        }
    }
}

private struct SessionJournalEvaluationCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Evaluación",
            title: "Cómo ha funcionado la sesión",
            subtitle: "Valora rápidamente el clima, la participación y el tiempo útil."
        ) {
            JournalMetricStrip(title: "Clima de aula", value: $vm.journalDraft.climateScore)
            JournalMetricStrip(title: "Participación", value: $vm.journalDraft.participationScore)
            JournalMetricStrip(title: "Tiempo útil", value: $vm.journalDraft.usefulTimeScore)
            JournalMetricStrip(title: "Dificultad percibida", value: $vm.journalDraft.perceivedDifficultyScore)

            VStack(alignment: .leading, spacing: 8) {
                Text("Decisión pedagógica")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    decisionButton("Repetir", value: .repeatSession)
                    decisionButton("Reforzar", value: .reinforce)
                    decisionButton("Avanzar", value: .advance)
                }
            }
        }
    }

    private func decisionButton(_ title: String, value: SessionJournalDecision) -> some View {
        Button(title) {
            vm.journalDraft.pedagogicalDecision = value
        }
        .buttonStyle(.bordered)
        .tint(vm.journalDraft.pedagogicalDecision == value ? EvaluationDesign.accent : .gray)
    }
}

private struct SessionJournalClosingCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Cierre",
            title: "Qué queda pendiente",
            subtitle: "Prepara la siguiente sesión y deja trazabilidad docente."
        ) {
            JournalTextBlock(title: "Tareas pendientes", text: $vm.journalDraft.pendingTasksText)
            JournalTextBlock(title: "Material a preparar", text: $vm.journalDraft.materialToPrepareText)
            JournalTextBlock(title: "Alumnado a revisar", text: $vm.journalDraft.studentsToReviewText)
            JournalTextBlock(title: "Comunicación con familias", text: $vm.journalDraft.familyCommunicationText)
            JournalTextBlock(title: "Siguiente paso", text: $vm.journalDraft.nextStepText)

            VStack(alignment: .leading, spacing: 8) {
                Text("Próxima acción")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    actionChip("Repetir tarea 2")
                    actionChip("Adaptar a Pablo")
                    actionChip("Llevar más conos")
                }
            }
        }
    }

    private func actionChip(_ title: String) -> some View {
        Button(title) {
            if !vm.journalDraft.actions.contains(where: { $0.title == title }) {
                vm.journalDraft.actions.append(PlannerJournalDraftAction(title: title))
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct SessionJournalEFCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "EF",
            title: "Bloque específico de Educación Física",
            subtitle: "Meteorología, material, lesiones e intensidad en una misma ficha."
        ) {
            editableGridField("Meteorología", text: $vm.journalDraft.weatherText)
            editableGridField("Espacio usado", text: $vm.journalDraft.usedSpace)
            editableGridField("Material empleado", text: $vm.journalDraft.materialUsedText)
            editableGridField("Incidencias físicas", text: $vm.journalDraft.physicalIncidentsText)
            editableGridField("Lesiones / molestias", text: $vm.journalDraft.injuriesText)
            editableGridField("Sin equipación", text: $vm.journalDraft.unequippedStudentsText)

            JournalMetricStrip(title: "Intensidad percibida", value: $vm.journalDraft.intensityScore)

            HStack(spacing: 12) {
                minuteStepper("Calentamiento", value: $vm.journalDraft.warmupMinutes)
                minuteStepper("Parte principal", value: $vm.journalDraft.mainPartMinutes)
                minuteStepper("Vuelta a la calma", value: $vm.journalDraft.cooldownMinutes)
            }

            JournalTextBlock(title: "Observaciones motrices por grupos o estaciones", text: $vm.journalDraft.stationObservationsText)
        }
    }

    private func editableGridField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private func minuteStepper(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Stepper("\(value.wrappedValue) min", value: value, in: 0...90, step: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalIndividualNotesList: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Alumnado",
            title: "Observaciones individuales",
            subtitle: "Notas breves por alumno con intención de seguimiento."
        ) {
            ForEach(Array(vm.journalDraft.notes.enumerated()), id: \.element.id) { index, _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Alumno", text: Binding(
                            get: { vm.journalDraft.notes[index].studentName },
                            set: { vm.journalDraft.notes[index].studentName = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Tag", text: Binding(
                            get: { vm.journalDraft.notes[index].tag },
                            set: { vm.journalDraft.notes[index].tag = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(role: .destructive) {
                            vm.journalDraft.notes.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Observación", text: Binding(
                        get: { vm.journalDraft.notes[index].note },
                        set: { vm.journalDraft.notes[index].note = $0 }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.vertical, 4)
            }

            Button {
                vm.journalDraft.notes.append(PlannerJournalDraftNote())
            } label: {
                Label("Añadir observación individual", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct JournalMediaDock: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @ObservedObject var recorder: PlannerAudioRecorder
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Multimedia",
            title: "Fotos, audio y transcripción",
            subtitle: "Captura evidencia ligera sin salir del diario."
        ) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Añadir foto", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                Button {
                    if recorder.isRecording {
                        if let url = recorder.stop() {
                            vm.journalDraft.media.append(
                                PlannerJournalDraftMedia(type: .audio, uri: url.absoluteString, caption: "Audio de sesión")
                            )
                        }
                    } else {
                        recorder.start()
                    }
                } label: {
                    Label(recorder.isRecording ? "Detener audio" : "Grabar audio", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    vm.journalDraft.media.append(
                        PlannerJournalDraftMedia(type: .transcript, uri: "", transcript: "", caption: "Dictado / transcripción")
                    )
                } label: {
                    Label("Añadir dictado", systemImage: "waveform.and.mic")
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array(vm.journalDraft.media.enumerated()), id: \.element.id) { index, media in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(media.type.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            vm.journalDraft.media.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Título", text: Binding(
                        get: { vm.journalDraft.media[index].caption },
                        set: { vm.journalDraft.media[index].caption = $0 }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                    if !vm.journalDraft.media[index].uri.isEmpty {
                        Text(vm.journalDraft.media[index].uri)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    TextField("Transcripción editable", text: Binding(
                        get: { vm.journalDraft.media[index].transcript },
                        set: { vm.journalDraft.media[index].transcript = $0 }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct JournalActionBar: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Acciones",
            title: "Integraciones y seguimiento",
            subtitle: "Lanza acciones explícitas y deja trazabilidad de lo ya trasladado."
        ) {
            HStack(spacing: 10) {
                Button("Enviar observación al cuaderno") {
                    vm.appendTraceLink(type: .notebook, label: "Pendiente de trasladar al cuaderno")
                }
                .buttonStyle(.bordered)

                Button("Registrar incidencia") {
                    Task { await vm.appendIncidentLink() }
                }
                .buttonStyle(.bordered)

                Button("Reflejar asistencia") {
                    vm.appendTraceLink(type: .attendance, label: "Asistencia / participación reflejada")
                }
                .buttonStyle(.bordered)

                Button("Seguimiento familias") {
                    vm.appendTraceLink(type: .family, label: "Seguimiento familiar marcado")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                saveStateLabel
                    .font(.caption)
                    .foregroundStyle(saveStateColor)
                Spacer()
                Button("Guardar ahora") { Task { await vm.saveJournal() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.journalSaveState == .saving)
            }

            ForEach(vm.journalDraft.links) { link in
                HStack {
                    Text(link.type.title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(link.label)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var saveStateLabel: Text {
        switch vm.journalSaveState {
        case .idle:
            return Text("Usa el dictado nativo del teclado en cualquier campo de texto para capturar voz.")
        case .saving:
            return Text("Guardando...")
        case .saved(let date):
            let seconds = max(0, Int(Date().timeIntervalSince(date)))
            return Text(seconds < 3 ? "Guardado ahora" : "Guardado hace \(seconds) s")
        case .failed(let message):
            return Text("Error al guardar: \(message)")
        }
    }

    private var saveStateColor: Color {
        switch vm.journalSaveState {
        case .failed:
            return .red
        default:
            return .secondary
        }
    }
}

private struct SessionJournalSectionCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let content: Content

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        EvaluationGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSectionTitle(eyebrow: eyebrow, title: title, subtitle: subtitle)
                content
            }
        }
    }
}

private struct JournalTextBlock: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct JournalMetricStrip: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { item in
                    Button("\(item)") { value = item }
                        .buttonStyle(.bordered)
                        .tint(value == item ? EvaluationDesign.accent : .gray)
                }
            }
        }
    }
}

private struct JournalQuickChips: View {
    let title: String
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        if selected.contains(option) {
                            selected.removeAll { $0 == option }
                        } else {
                            selected.append(option)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected.contains(option) ? EvaluationDesign.danger : .gray)
                }
            }
        }
    }
}

private struct PlannerInstrumentCompactPicker: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var expandedGroupTitles: Set<String> = []

    private var summaryText: String {
        let availableIds = Set(vm.composerAvailableInstruments.map(\.id))
        let count = vm.composerDraft.selectedInstrumentIds.intersection(availableIds).count
        if count == 1 { return "1 seleccionado" }
        return "\(count) seleccionados"
    }

    private var rubricCount: Int {
        vm.composerAvailableInstruments.filter { $0.kind == .rubric }.count
    }

    private var evaluationCount: Int {
        vm.composerAvailableInstruments.filter { $0.kind != .rubric }.count
    }

    private var recommendedCount: Int {
        vm.composerAvailableInstruments.filter(\.isRecommendedForCurrentSA).count
    }

    private var groupedInstruments: [PlannerInstrumentCompactGroup] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = vm.composerAvailableInstruments.filter { instrument in
            guard !trimmedSearch.isEmpty else { return true }
            let haystack = [
                safeDisplayText(instrument.title, fallback: "Instrumento"),
                safeDisplayText(instrument.subtitle, fallback: instrument.kind == .rubric ? "Rúbrica" : "Evaluación"),
                safeDisplayText(instrument.groupTitle, fallback: "Sin situación asignada"),
                instrument.kind == .rubric ? "Rúbrica" : "Evaluación"
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(trimmedSearch)
        }

        var groups: [PlannerInstrumentCompactGroup] = []
        let recommended = filtered
            .filter(\.isRecommendedForCurrentSA)
            .sorted(by: instrumentSort)
        if !recommended.isEmpty {
            groups.append(PlannerInstrumentCompactGroup(title: "Recomendados para esta SA", items: recommended))
        }

        let remaining = filtered.filter { !$0.isRecommendedForCurrentSA }
        let grouped = Dictionary(grouping: remaining) { instrument in
            safeDisplayText(instrument.groupTitle, fallback: "Sin situación asignada")
        }
        let sortedTitles = grouped.keys.sorted { lhs, rhs in
            if lhs == "Sin situación asignada" { return false }
            if rhs == "Sin situación asignada" { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        groups.append(contentsOf: sortedTitles.map { title in
            PlannerInstrumentCompactGroup(title: title, items: (grouped[title] ?? []).sorted(by: instrumentSort))
        })
        return groups
    }

    private var recommendedGroupTitles: Set<String> {
        Set(groupedInstruments.filter { group in
            group.items.contains(where: \.isRecommendedForCurrentSA)
        }.map(\.title))
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(EvaluationDesign.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Instrumentos enlazados")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(summaryText) · Ver instrumentos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Buscar rúbrica o evaluación", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    if groupedInstruments.isEmpty {
                        Text("No hay instrumentos que coincidan con la búsqueda.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 8) {
                            EvaluationChip(label: "\(recommendedCount) criterios SA", systemImage: "scope", active: recommendedCount > 0, tint: EvaluationDesign.accent)
                            EvaluationChip(label: "\(rubricCount) rúbricas", systemImage: "checklist", active: rubricCount > 0, tint: EvaluationDesign.success)
                            EvaluationChip(label: "\(evaluationCount) evaluaciones", systemImage: "chart.bar.doc.horizontal", active: evaluationCount > 0, tint: EvaluationDesign.danger)
                        }

                        HStack(spacing: 16) {
                            Button("Expandir recomendadas") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    expandedGroupTitles = recommendedGroupTitles
                                }
                            }
                            .buttonStyle(.borderless)

                            Button("Contraer todo") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    expandedGroupTitles.removeAll()
                                }
                            }
                            .buttonStyle(.borderless)

                            Spacer()
                        }
                        .font(.caption.weight(.semibold))

                        ForEach(groupedInstruments) { group in
                            PlannerInstrumentDisclosureSection(
                                title: safeDisplayText(group.title, fallback: "Sin situación asignada"),
                                items: group.items,
                                isExpanded: Binding(
                                    get: {
                                        !trimmedSearchText.isEmpty || expandedGroupTitles.contains(group.title)
                                    },
                                    set: { newValue in
                                        if newValue {
                                            expandedGroupTitles.insert(group.title)
                                        } else {
                                            expandedGroupTitles.remove(group.title)
                                        }
                                    }
                                ),
                                selectedIds: vm.composerDraft.selectedInstrumentIds,
                                toggle: { instrument in
                                    vm.toggleComposerInstrument(instrument.id)
                                }
                            )
                        }
                    }
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 0.5)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .task {
            if expandedGroupTitles.isEmpty {
                expandedGroupTitles = recommendedGroupTitles
            }
        }
        .appOnChange(of: vm.composerAvailableInstruments) { _ in
            if expandedGroupTitles.isEmpty {
                expandedGroupTitles = recommendedGroupTitles
            }
        }
    }

    private func instrumentSort(_ lhs: PlannerAssessmentInstrument, _ rhs: PlannerAssessmentInstrument) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .rubric }
        return safeDisplayText(lhs.title, fallback: "Instrumento")
            .localizedCaseInsensitiveCompare(safeDisplayText(rhs.title, fallback: "Instrumento")) == .orderedAscending
    }

    private func safeDisplayText(_ value: String, fallback: String) -> String {
        plannerSafeDisplayText(value, fallback: fallback)
    }
}

private struct PlannerInstrumentCompactGroup: Identifiable {
    let title: String
    let items: [PlannerAssessmentInstrument]

    var id: String { title }
}

private struct PlannerInstrumentDisclosureSection: View {
    let title: String
    let items: [PlannerAssessmentInstrument]
    @Binding var isExpanded: Bool
    let selectedIds: Set<String>
    let toggle: (PlannerAssessmentInstrument) -> Void

    private var selectedCount: Int {
        items.filter { selectedIds.contains($0.id) }.count
    }

    private var recommendedCount: Int {
        items.filter(\.isRecommendedForCurrentSA).count
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plannerSafeDisplayText(title, fallback: "Sin situación asignada"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .textCase(.uppercase)
                            .lineLimit(1)

                        Text(sectionSubtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedCount > 0 {
                        Text("\(selectedCount) seleccionados")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(EvaluationDesign.accent.opacity(0.12), in: Capsule())
                    }

                    Text("\(items.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    isExpanded ? EvaluationDesign.surfaceSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { instrument in
                        PlannerInstrumentCompactRow(
                            instrument: instrument,
                            isSelected: selectedIds.contains(instrument.id),
                            toggle: { toggle(instrument) }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 0.5)
        }
        .shadow(color: EvaluationDesign.shadow, radius: 12, x: 0, y: 4)
    }

    private var sectionSubtitle: String {
        if selectedCount > 0 {
            return "\(selectedCount) de \(items.count) seleccionados"
        }
        if recommendedCount > 0 {
            return "\(recommendedCount) recomendados para esta SA"
        }
        return "\(items.count) instrumentos"
    }
}

private struct PlannerInstrumentCompactRow: View {
    let instrument: PlannerAssessmentInstrument
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? EvaluationDesign.accent : .secondary)
                    .font(.callout.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(safeTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if instrument.isRecommendedForCurrentSA {
                            Text("SA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EvaluationDesign.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EvaluationDesign.accent.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(safeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(instrument.kind == .rubric ? "Rúbrica" : "Evaluación")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? EvaluationDesign.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var safeTitle: String {
        plannerSafeDisplayText(instrument.title, fallback: "Instrumento")
    }

    private var safeSubtitle: String {
        plannerSafeDisplayText(instrument.subtitle, fallback: instrument.kind == .rubric ? "Rúbrica" : "Evaluación")
    }
}

private func plannerSafeDisplayText(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let upper = trimmed.uppercased()

    if trimmed.isEmpty ||
        upper.contains("EVALUATION(") ||
        upper.contains("CLASSID=") ||
        upper.contains("RUBRICID=") ||
        upper.contains("TRACE=") ||
        upper.contains("AUDITTRACE") ||
        upper.contains("UPDATEDAT=") ||
        upper.contains("CREATEDAT=") {
        return fallback
    }

    return trimmed
}

struct PlannerSessionComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacPopupActionBar(
                title: vm.composerDraft.sessionId == 0 ? "Nueva sesión" : "Editar sesión",
                subtitle: "Planificación",
                saveTitle: vm.composerSaveState == .saving ? "Guardando..." : "Guardar",
                canSave: canSave,
                onClose: { dismiss() },
                onSave: saveAndDismiss
            )
            .frame(maxWidth: .infinity)
            .zIndex(2)

            composerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 10) {
                        PlannerSaveStateInlineStatus(state: vm.composerSaveState)
                        Spacer()
                        Button("Cancelar") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)

                        Button("Guardar") {
                            saveAndDismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .keyboardShortcut("s", modifiers: [.command])
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(MacAppStyle.divider.opacity(0.7))
                            .frame(height: 0.5)
                    }
                }
        }
        .frame(minWidth: 920, minHeight: 720)
        .task {
            await vm.refreshComposerContext()
        }
        .appOnChange(of: vm.composerDraft.groupId) { _ in
            vm.composerDraft.teachingUnitId = nil
            Task { await vm.refreshComposerContext() }
        }
        .appOnChange(of: vm.composerDraft.teachingUnitId) { newValue in
            if let newValue,
               let unit = vm.composerTeachingUnits.first(where: { $0.id == newValue }) {
                vm.composerDraft.unitTitle = unit.name
            }
            Task { await vm.refreshComposerContext() }
        }
        #else
        NavigationStack {
            composerContent
            .navigationTitle(vm.composerDraft.sessionId == 0 ? "Nueva sesión" : "Editar sesión")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            if await vm.saveComposer() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.composerDraft.groupId == nil || vm.isSavingComposer)
                }
            }
            .task {
                await vm.refreshComposerContext()
            }
            .appOnChange(of: vm.composerDraft.groupId) { _ in
                vm.composerDraft.teachingUnitId = nil
                Task { await vm.refreshComposerContext() }
            }
            .appOnChange(of: vm.composerDraft.teachingUnitId) { newValue in
                if let newValue,
                   let unit = vm.composerTeachingUnits.first(where: { $0.id == newValue }) {
                    vm.composerDraft.unitTitle = unit.name
                }
                Task { await vm.refreshComposerContext() }
            }
        }
        #endif
    }

    private var canSave: Bool {
        vm.composerDraft.groupId != nil && !vm.isSavingComposer
    }

    private var composerContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                IOSSectionCard(title: vm.composerDraft.sessionId == 0 ? "Nueva sesión" : "Editar sesión", systemImage: "pencil.and.outline") {
                    VStack(alignment: .leading, spacing: 14) {
                        PlannerSaveStateInlineStatus(state: vm.composerSaveState)

                        Text("Redacta la sesión en formato largo y déjala ya planificada.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        Picker("Curso", selection: $vm.composerDraft.groupId) {
                            Text("Selecciona curso").tag(Optional<Int64>.none)
                            ForEach(vm.groups, id: \.id) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Unidad / SA existente", selection: $vm.composerDraft.teachingUnitId) {
                            Text("Crear o elegir después").tag(Optional<Int64>.none)
                            ForEach(vm.composerTeachingUnits, id: \.id) { unit in
                                Text(unit.name).tag(Optional(unit.id))
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("Nueva Unidad / SA", text: $vm.composerDraft.unitTitle, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Objetivos")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $vm.composerDraft.objectives)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resumen de la sesión")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $vm.composerDraft.activities)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }

                IOSSectionCard(title: "Instrumentos enlazados", systemImage: "doc.plaintext.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selecciona evaluaciones o rúbricas filtradas por el curso y la situación de aprendizaje.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        if !vm.composerContextError.isEmpty {
                            Text(vm.composerContextError)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        if vm.composerAvailableInstruments.isEmpty {
                            Text("No hay instrumentos disponibles para este curso todavía.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            PlannerInstrumentCompactPicker(vm: vm)
                        }
                    }
                }

                IOSSectionCard(title: "Dónde cae la sesión", systemImage: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Se guardará como planificada en la franja seleccionada.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        Picker("Día", selection: $vm.composerDraft.dayOfWeek) {
                            ForEach(vm.visibleWeekdays, id: \.self) { day in
                                Text(vm.dayLabel(for: day)).tag(day)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Franja", selection: $vm.composerDraft.period) {
                            ForEach(vm.visibleSlots, id: \.period) { slot in
                                Text(slot.label).tag(slot.period)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(IOSAppStyle.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveAndDismiss() {
        guard canSave else { return }
        Task {
            if await vm.saveComposer() {
                dismiss()
            }
        }
    }
}

private struct PlannerSaveStateInlineStatus: View {
    let state: PlannerSaveState

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                if state == .saving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: iconName)
                }
                Text(message)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
        }
    }

    private var message: String? {
        switch state {
        case .idle:
            return nil
        case .saving:
            return "Guardando..."
        case .saved:
            return "Guardado"
        case .failed(let text):
            return text
        }
    }

    private var iconName: String {
        switch state {
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .failed:
            return EvaluationDesign.danger
        case .saving:
            return EvaluationDesign.accent
        default:
            return EvaluationDesign.success
        }
    }
}

private extension SessionJournalMediaType {
    var title: String {
        switch self {
        case .photo: return "Foto"
        case .audio: return "Audio"
        case .transcript: return "Dictado"
        default: return "Media"
        }
    }
}

private extension SessionJournalLinkType {
    var title: String {
        switch self {
        case .notebook: return "Cuaderno"
        case .attendance: return "Asistencia"
        case .incident: return "Incidencia"
        case .family: return "Familias"
        default: return "Enlace"
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where !value.isEmpty: return value
        default: return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
