import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import QuickLook
import MiGestorKit

struct PlannerNavigationContext: Equatable {
    var week: Int?
    var year: Int?
    var groupId: Int64?
    var sessionId: Int64?
}

enum PlannerWorkspaceSection: String, CaseIterable, Identifiable {
    case week = "Semana"
    case day = "Día"
    case sequence = "Secuencia"
    case summary = "Resumen"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .week: return "calendar"
        case .day: return "calendar.day.timeline.left"
        case .sequence: return "point.3.connected.trianglepath.dotted"
        case .summary: return "chart.bar.doc.horizontal"
        }
    }
}

enum PlannerDensity: String, CaseIterable, Identifiable {
    case compact = "Compacta"
    case standard = "Estándar"

    var id: String { rawValue }
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
    var learningSituationSessionPlanId: Int64? = nil
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

struct PlannerCellKey: Hashable {
    let day: Int
    let period: Int
}

struct PlannerWeekRenderModel: Equatable {
    var entriesByCell: [PlannerCellKey: [PlannerWeekCellEntry]] = [:]
    var visibleSlots: [PlannerVisibleSlot] = []
    var visibleDays: [Int] = []
    var holidays: Set<Int> = []

    static let empty = PlannerWeekRenderModel()
}

struct PlannerSituationProgress: Equatable {
    let title: String
    let total: Int
    let completed: Int
    let pending: Int
    let review: Int

    var completionRatio: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var percentLabel: String {
        "\(Int((completionRatio * 100).rounded()))%"
    }
}

struct PlannerSequenceGroup: Identifiable {
    let id: String
    let title: String
    let groupName: String
    let groupId: Int64
    let sequenceVersionId: Int64?
    let totalSessionsCount: Int
    let plannedCount: Int
    let pendingCount: Int
    let completedCount: Int
    let closedCount: Int
    let rows: [PlannerSequenceRow]
}

struct PlannerSequenceRow: Identifiable {
    let id: String
    let sessionNumber: Int
    let title: String
    let objective: String
    let statusText: String
    let statusIcon: String
    let statusColor: Color
    let planningSession: PlanningSession?
    let learningSituationSessionPlanId: Int64?
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
    @Published var density: PlannerDensity = .standard
    @Published var week = 1
    @Published var year = 2026
    @Published var groups: [SchoolClass] = []
    @Published var selectedGroupId: Int64?
    @Published var classColorHexById: [Int64: String] = [:]
    @Published var sessions: [PlanningSession] = []
    @Published var filteredSessions: [PlanningSession] = []
    @Published var sequenceGroupsEnriched: [PlannerSequenceGroup] = []
    @Published var isLoadingSequences = false
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
    @Published var lastCascadeMove: SessionCascadeMoveResult?
    @Published var holidayDays: Set<Int> = []
    @Published var weekRenderModel: PlannerWeekRenderModel = .empty

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

    private func reloadJournalSummaries() async {
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
        week = Int(truncating: current.first ?? KotlinInt(value: 1))
        year = Int(truncating: current.second ?? KotlinInt(value: 2026))
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

    func situationProgress(for session: PlanningSession?) -> PlannerSituationProgress? {
        guard let session else { return nil }
        let situationTitle = normalizedSituationTitle(session.teachingUnitName)
        let relatedSessions = sessions.filter {
            normalizedSituationTitle($0.teachingUnitName) == situationTitle
                && $0.groupId == session.groupId
        }
        guard !relatedSessions.isEmpty else { return nil }

        let completed = relatedSessions.count { candidate in
            candidate.status == .completed || summary(for: candidate.id)?.status == .completed
        }
        let review = relatedSessions.count { candidate in
            guard let summary = summary(for: candidate.id) else { return false }
            return summary.status == .draft || !summary.incidentTags.isEmpty
        }

        return PlannerSituationProgress(
            title: session.teachingUnitName.nilIfBlank ?? "Situación sin título",
            total: relatedSessions.count,
            completed: completed,
            pending: max(relatedSessions.count - completed, 0),
            review: review
        )
    }

    func sessionStateLabel(for session: PlanningSession) -> String {
        sessionStateLabel(sessionStatus: session.status, journalStatus: summary(for: session.id)?.status)
    }

    func sessionStateLabel(sessionStatus: SessionStatus?, journalStatus: SessionJournalStatus?) -> String {
        if journalStatus == .completed { return "Cerrada" }
        if journalStatus == .draft { return "Borrador" }
        if sessionStatus == .completed { return "Diario pendiente" }
        return "Planificada"
    }

    func sessionStateIcon(sessionStatus: SessionStatus?, journalStatus: SessionJournalStatus?) -> String {
        if journalStatus == .completed { return "checkmark.seal.fill" }
        if journalStatus == .draft { return "doc.text.fill" }
        if sessionStatus == .completed { return "checkmark.circle.fill" }
        return "calendar"
    }

    func sessionStateTint(sessionStatus: SessionStatus?, journalStatus: SessionJournalStatus?) -> Color {
        if journalStatus == .completed { return EvaluationDesign.success }
        if journalStatus == .draft { return EvaluationDesign.accent }
        if sessionStatus == .completed { return IOSAppStyle.warning }
        return .secondary
    }

    func classColorHex(for classId: Int64) -> String {
        classColorHexById[classId] ?? bridge?.plannerCourseColor(for: classId) ?? EvaluationDesign.plannerCoursePalette[0]
    }

    func select(session: PlanningSession) async {
        selectedSession = session
        selectedGroupId = session.groupId
        await loadJournalForSelectedSession()
    }

    func previewCascadeMove(sessionId: Int64, day: Int, period: Int) async throws -> SessionCascadeMovePreview {
        guard let bridge else { throw PlannerCascadeMoveError.bridgeUnavailable }
        return try await bridge.plannerPreviewCascadeMove(
            sourceSessionId: sessionId,
            targetWeekNumber: week,
            targetYear: year,
            targetDayOfWeek: day,
            targetPeriod: period
        )
    }

    func commitCascadeMove(sessionId: Int64, day: Int, period: Int) async throws -> SessionCascadeMoveResult {
        guard let bridge else { throw PlannerCascadeMoveError.bridgeUnavailable }
        let result = try await bridge.plannerCommitCascadeMove(
            sourceSessionId: sessionId,
            targetWeekNumber: week,
            targetYear: year,
            targetDayOfWeek: day,
            targetPeriod: period
        )
        lastCascadeMove = result
        await reloadSessionsOnly()
        return result
    }

    func restoreLastCascadeMove() async throws {
        guard let bridge, let lastCascadeMove else { return }
        _ = try await bridge.plannerRestoreCascadeMove(lastCascadeMove.previousPlacements)
        self.lastCascadeMove = nil
        await reloadSessionsOnly()
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

    func openComposer(
        for session: PlanningSession? = nil,
        day: Int? = nil,
        period: Int? = nil,
        learningSituationSessionPlanId: Int64? = nil,
        initialObjectives: String? = nil,
        initialActivities: String? = nil,
        initialTeachingUnitName: String? = nil
    ) {
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
                selectedInstrumentIds: Set(session.linkedAssessmentIdsCsv.split(separator: ",").map(String.init)),
                learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value ?? learningSituationSessionPlanId
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
                unitTitle: initialTeachingUnitName ?? "",
                objectives: initialObjectives ?? "",
                activities: initialActivities ?? "",
                dayOfWeek: resolvedDay,
                period: resolvedPeriod,
                teacherScheduleSlotId: slotMetadata.slotId,
                startTime: slotMetadata.startTime,
                endTime: slotMetadata.endTime,
                learningSituationSessionPlanId: learningSituationSessionPlanId
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
                learningSituationSessionPlanId: composerDraft.learningSituationSessionPlanId,
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
            learningSituationSessionPlanId: previous?.learningSituationSessionPlanId ?? composerDraft.learningSituationSessionPlanId.map { KotlinLong(value: $0) },
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
            learningSituationSessionPlanId: session.learningSituationSessionPlanId,
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
        rebuildWeekRenderModel()
    }

    func entries(for day: Int, period: Int) -> [PlannerWeekCellEntry] {
        weekRenderModel.entriesByCell[PlannerCellKey(day: day, period: period)] ?? buildEntries(for: day, period: period)
    }

    func daySessions(for day: Int? = nil) -> [PlanningSession] {
        let targetDay = day ?? selectedDayForDayView
        return filteredPlannerSessions()
            .filter { Int($0.dayOfWeek) == targetDay }
            .sorted {
                let lhsStart = $0.startTime ?? timeLabel(for: Int($0.period))
                let rhsStart = $1.startTime ?? timeLabel(for: Int($1.period))
                if lhsStart == rhsStart { return $0.groupName < $1.groupName }
                return lhsStart < rhsStart
            }
    }

    var selectedDayForDayView: Int {
        if let selectedSession {
            return Int(selectedSession.dayOfWeek)
        }
        let current = IsoWeekHelper.shared.current()
        let currentWeek = Int(truncating: current.first ?? KotlinInt(value: 1))
        let currentYear = Int(truncating: current.second ?? KotlinInt(value: 2026))
        if week == currentWeek, year == currentYear {
            var calendar = Calendar(identifier: .iso8601)
            calendar.locale = Locale.current
            let today = ((calendar.component(.weekday, from: Date()) + 5) % 7) + 1
            if visibleWeekdays.contains(today) { return today }
        }
        return visibleWeekdays.first ?? 1
    }

    func sequenceGroups() -> [(key: String, title: String, groupName: String, sessions: [PlanningSession])] {
        let grouped = Dictionary(grouping: filteredPlannerSessions()) { session in
            "\(session.groupId)-\(session.teachingUnitId)-\(normalizedSituationTitle(session.teachingUnitName))"
        }
        return grouped.compactMap { key, sessions in
            guard let first = sessions.first else { return nil }
            return (
                key: key,
                title: first.teachingUnitName.nilIfBlank ?? "Situación sin título",
                groupName: first.groupName,
                sessions: sessions.sorted {
                    if $0.weekNumber == $1.weekNumber {
                        if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                        return $0.dayOfWeek < $1.dayOfWeek
                    }
                    return $0.weekNumber < $1.weekNumber
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.groupName == rhs.groupName ? lhs.title < rhs.title : lhs.groupName < rhs.groupName
        }
    }

    func loadEnrichedSequences() async {
        guard let bridge = self.bridge else { return }
        isLoadingSequences = true
        defer { isLoadingSequences = false }
        
        do {
            let allSessions = try await bridge.plannerListAllSessions()
            let filteredSessions = allSessions.filter { session in
                self.selectedGroupId.map { session.groupId == $0 } ?? true
            }
            
            var uniqueSequenceVersionIds = Set<Int64>()
            for session in filteredSessions {
                if let planId = session.learningSituationSessionPlanId?.int64Value {
                    if let plan = try? await bridge.learningSituationSessionPlan(id: planId) {
                        uniqueSequenceVersionIds.insert(plan.sequenceVersionId)
                    }
                }
            }
            
            var sessionPlansBySequence: [Int64: [LearningSituationSessionPlan]] = [:]
            for seqId in uniqueSequenceVersionIds {
                if let plans = try? await bridge.learningSituationSessionPlans(sequenceVersionId: seqId) {
                    sessionPlansBySequence[seqId] = plans.sorted { $0.sessionNumber < $1.sessionNumber }
                }
            }
            
            var enriched: [PlannerSequenceGroup] = []
            let groupNames = Dictionary(uniqueKeysWithValues: self.groups.map { ($0.id, $0.name) })
            let sessionsByGroup = Dictionary(grouping: filteredSessions, by: { $0.groupId })
            
            for (groupId, groupSessions) in sessionsByGroup {
                let groupName = groupNames[groupId] ?? "Grupo \(groupId)"
                var seqIdBySessionId: [Int64: Int64] = [:]
                var planBySessionId: [Int64: LearningSituationSessionPlan] = [:]
                
                for session in groupSessions {
                    if let planId = session.learningSituationSessionPlanId?.int64Value {
                        if let plan = try? await bridge.learningSituationSessionPlan(id: planId) {
                            seqIdBySessionId[session.id] = plan.sequenceVersionId
                            planBySessionId[session.id] = plan
                        }
                    }
                }
                
                let sessionsWithSeq = groupSessions.filter { seqIdBySessionId[$0.id] != nil }
                let sessionsWithoutSeq = groupSessions.filter { seqIdBySessionId[$0.id] == nil }
                let sessionsBySeqId = Dictionary(grouping: sessionsWithSeq, by: { seqIdBySessionId[$0.id]! })
                
                for (seqId, seqSessions) in sessionsBySeqId {
                    guard let sortedPlans = sessionPlansBySequence[seqId] else { continue }
                    let firstSeqSession = seqSessions.first
                    let seqTitle = sortedPlans.first?.title.nilIfBlank 
                        ?? firstSeqSession?.teachingUnitName.nilIfBlank 
                        ?? "Secuencia didáctica"
                    
                    var rows: [PlannerSequenceRow] = []
                    var mappedSessionIds = Set<Int64>()
                    
                    for plan in sortedPlans {
                        let matchingSession = seqSessions.first { $0.learningSituationSessionPlanId?.int64Value == plan.id }
                        
                        if let session = matchingSession {
                            mappedSessionIds.insert(session.id)
                            let isCompleted = session.status == .completed || self.journalSummaryBySessionId[session.id]?.status == .completed
                            let statusText: String
                            let statusIcon: String
                            let statusColor: Color
                            
                            if isCompleted {
                                statusText = "Cerrada"
                                statusIcon = "checkmark.seal.fill"
                                statusColor = Color.green
                            } else if session.status == .completed {
                                statusText = "Impartida"
                                statusIcon = "checkmark.circle.fill"
                                statusColor = Color.green
                            } else if session.status == .inProgress {
                                statusText = "En Curso"
                                statusIcon = "circle.lefthalf.filled"
                                statusColor = Color.yellow
                            } else if session.status == .cancelled {
                                statusText = "Cancelada"
                                statusIcon = "xmark.circle.fill"
                                statusColor = Color.red
                            } else {
                                statusText = "Planificada"
                                statusIcon = "circle"
                                statusColor = EvaluationDesign.accent
                            }
                            
                            rows.append(PlannerSequenceRow(
                                id: "plan-\(plan.id)-session-\(session.id)",
                                sessionNumber: Int(plan.sessionNumber),
                                title: plan.title,
                                objective: plan.objective,
                                statusText: statusText,
                                statusIcon: statusIcon,
                                statusColor: statusColor,
                                planningSession: session,
                                learningSituationSessionPlanId: plan.id
                            ))
                        } else {
                            rows.append(PlannerSequenceRow(
                                id: "plan-\(plan.id)-unlocated",
                                sessionNumber: Int(plan.sessionNumber),
                                title: plan.title,
                                objective: plan.objective,
                                statusText: "Pendiente de ubicar",
                                statusIcon: "calendar.badge.plus",
                                statusColor: Color.orange,
                                planningSession: nil,
                                learningSituationSessionPlanId: plan.id
                            ))
                        }
                    }
                    
                    let unmappedSeqSessions = seqSessions.filter { !mappedSessionIds.contains($0.id) }
                    for session in unmappedSeqSessions {
                        rows.append(PlannerSequenceRow(
                            id: "session-fallback-\(session.id)",
                            sessionNumber: rows.count + 1,
                            title: session.objectives.nilIfBlank ?? "Sesión de calendario",
                            objective: session.activities,
                            statusText: "Solo calendario",
                            statusIcon: "calendar",
                            statusColor: Color.secondary,
                            planningSession: session,
                            learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value
                        ))
                    }
                    
                    let plannedCount = rows.count { $0.statusText == "Planificada" }
                    let pendingCount = rows.count { $0.statusText == "Pendiente de ubicar" }
                    let completedCount = rows.count { $0.statusText == "Cerrada" || $0.statusText == "Impartida" }
                    
                    enriched.append(PlannerSequenceGroup(
                        id: "\(groupId)-seq-\(seqId)",
                        title: seqTitle,
                        groupName: groupName,
                        groupId: groupId,
                        sequenceVersionId: seqId,
                        totalSessionsCount: sortedPlans.count,
                        plannedCount: plannedCount,
                        pendingCount: pendingCount,
                        completedCount: completedCount,
                        closedCount: rows.count { $0.statusText == "Cerrada" },
                        rows: rows
                    ))
                }
                
                let groupedFallback = Dictionary(grouping: sessionsWithoutSeq, by: { "\($0.teachingUnitId)-\(self.normalizedSituationTitle($0.teachingUnitName))" })
                for (fallbackKey, fallbackSessions) in groupedFallback {
                    guard let first = fallbackSessions.first else { continue }
                    let title = first.teachingUnitName.nilIfBlank ?? "Situación sin título"
                    
                    let sortedFallbackSessions = fallbackSessions.sorted {
                        if $0.weekNumber == $1.weekNumber {
                            if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                            return $0.dayOfWeek < $1.dayOfWeek
                        }
                        return $0.weekNumber < $1.weekNumber
                    }
                    
                    let rows = sortedFallbackSessions.enumerated().map { index, session in
                        let isCompleted = session.status == .completed || self.journalSummaryBySessionId[session.id]?.status == .completed
                        let statusText: String
                        let statusIcon: String
                        let statusColor: Color
                        
                        if isCompleted {
                            statusText = "Cerrada"
                            statusIcon = "checkmark.seal.fill"
                            statusColor = Color.green
                        } else if session.status == .completed {
                            statusText = "Impartida"
                            statusIcon = "checkmark.circle.fill"
                            statusColor = Color.green
                        } else {
                            statusText = "Solo calendario"
                            statusIcon = "calendar"
                            statusColor = Color.secondary
                        }
                        
                        return PlannerSequenceRow(
                            id: "fallback-session-\(session.id)",
                            sessionNumber: index + 1,
                            title: session.objectives.nilIfBlank ?? "Sesión de calendario",
                            objective: session.activities,
                            statusText: statusText,
                            statusIcon: statusIcon,
                            statusColor: statusColor,
                            planningSession: session,
                            learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value
                        )
                    }
                    
                    let plannedCount = rows.count { $0.statusText == "Planificada" || $0.statusText == "Solo calendario" }
                    let completedCount = rows.count { $0.statusText == "Cerrada" || $0.statusText == "Impartida" }
                    
                    enriched.append(PlannerSequenceGroup(
                        id: "\(groupId)-fallback-\(fallbackKey)",
                        title: title,
                        groupName: groupName,
                        groupId: groupId,
                        sequenceVersionId: nil,
                        totalSessionsCount: rows.count,
                        plannedCount: plannedCount,
                        pendingCount: 0,
                        completedCount: completedCount,
                        closedCount: rows.count { $0.statusText == "Cerrada" },
                        rows: rows
                    ))
                }
            }
            
            self.sequenceGroupsEnriched = enriched.sorted { lhs, rhs in
                lhs.groupName == rhs.groupName ? lhs.title < rhs.title : lhs.groupName < rhs.groupName
            }
        } catch {
            print("Error loading enriched sequences: \(error)")
        }
    }

    func rebuildWeekRenderModel() {
        var entriesByCell: [PlannerCellKey: [PlannerWeekCellEntry]] = [:]
        for day in visibleWeekdays {
            for slot in visibleSlots {
                let entries = buildEntries(for: day, period: Int(slot.period))
                if !entries.isEmpty {
                    entriesByCell[PlannerCellKey(day: day, period: Int(slot.period))] = entries
                }
            }
        }
        weekRenderModel = PlannerWeekRenderModel(
            entriesByCell: entriesByCell,
            visibleSlots: visibleSlots,
            visibleDays: visibleWeekdays,
            holidays: holidayDays
        )
    }

    private func filteredPlannerSessions() -> [PlanningSession] {
        sessions.filter { session in
            selectedGroupId.map { session.groupId == $0 } ?? true
        }
    }

    private func buildEntries(for day: Int, period: Int) -> [PlannerWeekCellEntry] {
        let sessionEntries = filteredPlannerSessions()
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
                if let selectedGroupId, slot.schoolClassId != selectedGroupId { return false }
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

    private func normalizedSituationTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    func reloadHolidays() async {
        guard let bridge else { return }
        do {
            let events = try await bridge.plannerNonTeachingCalendarEvents(classId: nil)
            let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
            var holidays: Set<Int> = []
            
            let calendar = Calendar.current
            
            for (index, dayDate) in days.enumerated() {
                var components = DateComponents()
                components.year = Int(dayDate.year)
                components.month = Int(dayDate.monthNumber)
                components.day = Int(dayDate.dayOfMonth)
                components.hour = 0
                components.minute = 0
                components.second = 0
                
                guard let startOfDay = calendar.date(from: components) else { continue }
                let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
                
                components.hour = 23
                components.minute = 59
                components.second = 59
                guard let endOfDay = calendar.date(from: components) else { continue }
                let endMs = Int64(endOfDay.timeIntervalSince1970 * 1000)
                
                for event in events {
                    let eventStartMs = event.startAt.toEpochMilliseconds()
                    if eventStartMs >= startMs && eventStartMs <= endMs {
                        holidays.insert(index + 1)
                        break
                    }
                }
            }
            self.holidayDays = holidays
            rebuildWeekRenderModel()
        } catch {
            print("Error al cargar festivos: \(error)")
        }
    }

    func toggleHoliday(for day: Int) async {
        guard let bridge else { return }
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
        guard day >= 1 && day <= days.count else { return }
        let targetDate = days[day - 1]
        
        let events = (try? await bridge.plannerNonTeachingCalendarEvents(classId: nil)) ?? []
        let calendar = Calendar.current
        
        var components = DateComponents()
        components.year = Int(targetDate.year)
        components.month = Int(targetDate.monthNumber)
        components.day = Int(targetDate.dayOfMonth)
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        guard let startOfDay = calendar.date(from: components) else { return }
        let startEpochMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        
        components.hour = 23
        components.minute = 59
        components.second = 59
        guard let endOfDay = calendar.date(from: components) else { return }
        let endEpochMs = Int64(endOfDay.timeIntervalSince1970 * 1000)
        
        let existingEvent = events.first { event in
            let eventStartMs = event.startAt.toEpochMilliseconds()
            return eventStartMs >= startEpochMs && eventStartMs <= endEpochMs
        }
        
        do {
            if let event = existingEvent {
                _ = try await bridge.plannerSaveCalendarEvent(
                    id: event.id,
                    classId: nil,
                    title: "Lectivo",
                    description: "Clase ordinaria",
                    startEpochMs: event.startAt.toEpochMilliseconds(),
                    endEpochMs: event.endAt.toEpochMilliseconds()
                )
            } else {
                _ = try await bridge.plannerSaveCalendarEvent(
                    id: nil,
                    classId: nil,
                    title: "Festivo",
                    description: "Día no lectivo",
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs
                )
            }
            await reloadWeekSessions()
        } catch {
            print("Error al alternar festivo: \(error)")
        }
    }

    func dayHeaderLabel(for day: Int) -> String {
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
        guard day >= 1 && day <= days.count else { return dayLabel(for: day) }
        let date = days[day - 1]
        let dayName = dayLabel(for: day)
        return "\(dayName) \(date.dayOfMonth)/\(date.monthNumber)"
    }
}

private enum PlannerCascadeMoveError: LocalizedError {
    case bridgeUnavailable

    var errorDescription: String? { "El Planner todavía no está preparado." }
}

struct PlannerWorkspaceIOS: View {
    @EnvironmentObject private var bridge: KmpBridge
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var selectedDetailSession: PlanningSession? = nil
    @State private var selectedWeekCell: PlannerCellKey? = nil
    @State private var selectedWeekDay: Int? = nil
    @State private var isClearSchedulelessWeekConfirmationPresented = false
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
        .sheet(
            isPresented: Binding(
                get: { selectedDetailSession != nil },
                set: { if !$0 { selectedDetailSession = nil } }
            )
        ) {
            if let session = selectedDetailSession {
                PlannerSessionDetailSheet(
                    session: session,
                    onOpenDiary: {
                        selectedDetailSession = nil
                        onOpenDiary?(
                            PlannerNavigationContext(
                                week: vm.week,
                                year: vm.year,
                                groupId: session.groupId,
                                sessionId: session.id
                            )
                        )
                    },
                    onEdit: {
                        selectedDetailSession = nil
                        vm.openComposer(for: session)
                    }
                )
                .environmentObject(bridge)
            }
        }
        .onDisappear {
            layoutState.clearPlannerToolbar()
        }
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
    }

    private var plannerMainContent: some View {
        VStack(spacing: 0) {
            PlannerToolbar(vm: vm)
            Group {
                switch vm.activeSection {
                case .week:
                    ZStack(alignment: .bottom) {
                        PlannerWeekMiniatureLayout(
                            vm: vm,
                            selectedCell: $selectedWeekCell,
                            selectedDay: $selectedWeekDay,
                            onOpenSession: openSessionInDiary
                        )
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 96)
                        }

                        plannerFloatingControls
                            .padding(.horizontal, EvaluationDesign.screenPadding)
                            .padding(.bottom, 32)
                    }
                case .day:
                    PlannerDayView(vm: vm, onOpenSession: openSessionInDiary)
                case .sequence:
                    PlannerSequenceGanttView(vm: vm, onOpenSession: openSessionInDiary)
                case .summary:
                    PlannerSummaryDashboard(vm: vm, onOpenSettings: onOpenSettings)
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

    private var plannerFloatingControls: some View {
        PlannerLiquidGlassControls(
            density: $vm.density,
            canOpenDiary: vm.selectedSession != nil,
            canCopySelection: !vm.selectedSessionIds.isEmpty,
            canClearSchedulelessWeek: vm.canClearSchedulelessWeekSessions,
            isSelectionModeActive: vm.selectionMode,
            shareText: vm.exportText(),
            onPreviousWeek: { Task { await vm.previousWeek() } },
            onNextWeek: { Task { await vm.nextWeek() } },
            onToday: { Task { await vm.goToCurrentWeek() } },
            onSync: {
                Task {
                    await bridge.pullMissingSyncChanges()
                    await vm.refreshCurrentWeek()
                }
            },
            onToggleSelection: {
                vm.selectionMode.toggle()
                if !vm.selectionMode { vm.selectedSessionIds.removeAll() }
            },
            onCopyToNextWeek: { Task { await vm.bulkCopyToNextWeek() } },
            onMoveOneDay: { Task { await vm.bulkMoveOneDay() } },
            onClearSchedulelessWeek: {
                isClearSchedulelessWeekConfirmationPresented = true
            },
            onOpenDiary: openSelectedSessionInDiary,
            onNewSession: { vm.openComposer() }
        )
        .frame(maxWidth: .infinity)
    }

    private func openSelectedSessionInDiary() {
        guard let session = vm.selectedSession else { return }
        openSessionInDiary(session)
    }

    private func openSessionInDiary(_ session: PlanningSession) {
        Task { await vm.select(session: session) }
        selectedDetailSession = session
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

struct PlannerToolbar: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @AppStorage("planner_toolbar_progress_expanded") private var isProgressExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isProgressExpanded.toggle()
                    }
                }) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(toolbarTitle)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(toolbarSubtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isProgressExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if isProgressExpanded {
                    Group {
                        if let progress = vm.situationProgress(for: vm.selectedSession) {
                            PlannerSituationProgressStrip(progress: progress)
                        } else {
                            PlannerWeekProgressStrip(vm: vm)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeOut(duration: 0.2)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
                }
            }
            .padding(16)
            .plannerGlassPanel(.hero, cornerRadius: 24)

            HStack(spacing: 8) {
                PlannerFloatingTabBar(activeSection: $vm.activeSection)
                    .frame(maxWidth: 376)

                HStack(spacing: 8) {
                    Picker("Grupo", selection: Binding(
                        get: { vm.selectedGroupId },
                        set: { vm.selectGroup($0) }
                    )) {
                        Text("Todos").tag(Optional<Int64>.none)
                        ForEach(vm.groups, id: \.id) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                }
                .controlSize(.small)

                IOSSearchField(text: $vm.searchText, placeholder: "Buscar sesión, unidad, objetivo…")
                    .appOnChange(of: vm.searchText) { _ in vm.applySearch() }
            }
            .frame(height: 40)

            if !vm.bulkSummary.isEmpty {
                Text(vm.bulkSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, EvaluationDesign.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var toolbarTitle: String {
        vm.selectedSession?.teachingUnitName.nilIfBlank ?? vm.weekLabel
    }

    private var toolbarSubtitle: String {
        if let session = vm.selectedSession {
            return "\(vm.weekLabel) · \(vm.dateRangeLabel) · \(session.groupName)"
        }
        return vm.dateRangeLabel
    }
}

private struct PlannerSituationProgressStrip: View {
    let progress: PlannerSituationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.completed) de \(progress.total) sesiones completadas")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(progress.percentLabel)
                    .font(.headline.weight(.black))
                    .foregroundStyle(EvaluationDesign.accent)
            }

            ProgressView(value: progress.completionRatio)
                .tint(EvaluationDesign.accent)

            HStack(spacing: 12) {
                PlannerProgressMetric(title: "Completadas", value: "\(progress.completed)", tint: EvaluationDesign.success)
                PlannerProgressMetric(title: "Pendientes", value: "\(progress.pending)", tint: .secondary)
                PlannerProgressMetric(title: "Revisión", value: "\(progress.review)", tint: IOSAppStyle.warning)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }
}

private struct PlannerWeekProgressStrip: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    private var totals: (total: Int, completed: Int, pending: Int, review: Int) {
        let total = vm.filteredSessions.count
        let completed = vm.filteredSessions.count { session in
            session.status == .completed || vm.summary(for: session.id)?.status == .completed
        }
        let review = vm.filteredSessions.count { session in
            guard let summary = vm.summary(for: session.id) else { return false }
            return summary.status == .draft || !summary.incidentTags.isEmpty
        }
        return (total, completed, max(total - completed, 0), review)
    }

    var body: some View {
        HStack(spacing: 12) {
            PlannerProgressMetric(title: "Sesiones", value: "\(totals.total)", tint: EvaluationDesign.accent)
            PlannerProgressMetric(title: "Completadas", value: "\(totals.completed)", tint: EvaluationDesign.success)
            PlannerProgressMetric(title: "Pendientes", value: "\(totals.pending)", tint: .secondary)
            PlannerProgressMetric(title: "Revisión", value: "\(totals.review)", tint: IOSAppStyle.warning)
        }
    }
}

private struct PlannerProgressMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PlannerDayView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    private var sessions: [PlanningSession] { vm.daySessions() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.dayHeaderLabel(for: vm.selectedDayForDayView))
                            .font(.title2.weight(.black))
                        Text(daySubtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.openComposer(day: vm.selectedDayForDayView, period: vm.visibleSlots.first?.period ?? 1)
                    } label: {
                        Label("Nueva sesión", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if sessions.isEmpty {
                    PlannerEmptyState(
                        title: "Sin sesiones este día",
                        systemImage: "calendar.badge.plus",
                        message: "Usa Nueva sesión o vuelve a Semana para concretar una franja."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sessions, id: \.id) { session in
                            PlannerDaySessionRow(
                                vm: vm,
                                session: session,
                                isCurrent: isCurrent(session),
                                isNext: session.id == nextSession?.id,
                                onOpen: { onOpenSession(session) },
                                onComplete: { Task { await vm.markCompleted(session) } }
                            )
                        }
                    }
                }
            }
            .padding(EvaluationDesign.screenPadding)
        }
    }

    private var daySubtitle: String {
        if let nextSession {
            return "Próxima: \(nextSession.groupName) · \(nextSession.startTime ?? vm.timeLabel(for: Int(nextSession.period)))"
        }
        return "\(sessions.count) sesiones planificadas"
    }

    private var nextSession: PlanningSession? {
        sessions.first { session in
            session.status != .completed && vm.summary(for: session.id)?.status != .completed
        }
    }

    private func isCurrent(_ session: PlanningSession) -> Bool {
        guard let start = session.startTime, let end = session.endTime else { return false }
        let current = IsoWeekHelper.shared.current()
        let currentWeek = Int(truncating: current.first ?? KotlinInt(value: 1))
        let currentYear = Int(truncating: current.second ?? KotlinInt(value: 2026))
        guard Int(session.weekNumber) == currentWeek, Int(session.year) == currentYear else { return false }
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale.current
        let today = ((calendar.component(.weekday, from: Date()) + 5) % 7) + 1
        guard Int(session.dayOfWeek) == today else { return false }
        let now = calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
        guard let startMinutes = minutes(from: start), let endMinutes = minutes(from: end) else { return false }
        return now >= startMinutes && now <= endMinutes
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}

private struct PlannerDaySessionRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    let isCurrent: Bool
    let isNext: Bool
    let onOpen: () -> Void
    let onComplete: () -> Void

    private var tint: Color { Color(hex: vm.classColorHex(for: session.groupId)) }
    private var stateTint: Color { vm.sessionStateTint(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange)
                    .font(.headline.monospacedDigit())
                Text(isCurrent ? "Ahora" : (isNext ? "Próxima" : ""))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? EvaluationDesign.success : EvaluationDesign.accent)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.groupName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                    Spacer()
                    Label(vm.sessionStateLabel(for: session), systemImage: vm.sessionStateIcon(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stateTint)
                }

                Text(session.teachingUnitName.nilIfBlank ?? "Sesión sin título")
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)

                if let objective = session.objectives.nilIfBlank ?? session.activities.nilIfBlank {
                    Text(objective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button("Abrir ficha", action: onOpen)
                        .buttonStyle(.borderedProminent)
                    Button("Impartida", action: onComplete)
                        .buttonStyle(.bordered)
                        .disabled(session.status == .completed)
                    Button("Observación", action: onOpen)
                        .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isCurrent ? EvaluationDesign.success.opacity(0.55) : EvaluationDesign.border, lineWidth: isCurrent ? 1.5 : 1)
        }
    }

    private var timeRange: String {
        if let start = session.startTime, let end = session.endTime {
            return "\(start)-\(end)"
        }
        return vm.timeLabel(for: Int(session.period))
    }
}

struct PlannerEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
    }
}

enum SessionJournalEFVisibility {
    case always
    case contextual
    case hidden
}

enum PlannerJournalPresentationMode {
    case minimal
    case full
}

struct PlannerJournalDetailPane: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var efVisibility: SessionJournalEFVisibility = .always
    var presentationMode: PlannerJournalPresentationMode = .minimal
    @StateObject private var recorder = PlannerAudioRecorder()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isAdvancedReflectionPresented = false

    var body: some View {
        Group {
            if let session = vm.selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: EvaluationDesign.cardSpacing) {
                        SessionJournalQuickPulseCard(vm: vm)
                        SessionJournalQuickObservationCard(vm: vm)
                        SessionJournalQuickNextStepCard(vm: vm)

                        if presentationMode == .full {
                            advancedJournalContent(for: session)
                        } else {
                            DisclosureGroup(isExpanded: $isAdvancedReflectionPresented) {
                                VStack(alignment: .leading, spacing: EvaluationDesign.cardSpacing) {
                                    advancedJournalContent(for: session)
                                }
                                .padding(.top, 12)
                            } label: {
                                HStack {
                                    Label("Reflexión avanzada", systemImage: "slider.horizontal.3")
                                        .font(.headline.weight(.semibold))
                                    Spacer()
                                    Text("Opcional")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
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

    @ViewBuilder
    private func advancedJournalContent(for session: PlanningSession) -> some View {
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

private struct SessionJournalQuickPulseCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        EvaluationGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSectionTitle(
                    eyebrow: "10 segundos",
                    title: "Pulso de la sesión",
                    subtitle: "Cierra lo esencial sin convertir el diario en un informe."
                )

                HStack(spacing: 8) {
                    pulseButton("Muy bien", icon: "checkmark.circle.fill", climate: 5, usefulTime: 5, difficulty: 1, tint: EvaluationDesign.success)
                    pulseButton("Normal", icon: "circle.lefthalf.filled", climate: 3, usefulTime: 3, difficulty: 3, tint: EvaluationDesign.accent)
                    pulseButton("Revisar", icon: "exclamationmark.triangle.fill", climate: 2, usefulTime: 2, difficulty: 5, tint: IOSAppStyle.warning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Participación")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        participationButton("Baja", value: 2)
                        participationButton("Media", value: 3)
                        participationButton("Alta", value: 5)
                    }
                }
            }
        }
    }

    private func pulseButton(_ title: String, icon: String, climate: Int, usefulTime: Int, difficulty: Int, tint: Color) -> some View {
        let isSelected = vm.journalDraft.climateScore == climate
            && vm.journalDraft.usefulTimeScore == usefulTime
            && vm.journalDraft.perceivedDifficultyScore == difficulty
        return Button {
            vm.journalDraft.climateScore = climate
            vm.journalDraft.usefulTimeScore = usefulTime
            vm.journalDraft.perceivedDifficultyScore = difficulty
            if title == "Revisar", !vm.journalDraft.incidentTags.contains("Revisión") {
                vm.journalDraft.incidentTags.append("Revisión")
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : tint)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tint : tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
        )
    }

    private func participationButton(_ title: String, value: Int) -> some View {
        let isSelected = vm.journalDraft.participationScore == value
        return Button {
            vm.journalDraft.participationScore = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : EvaluationDesign.accent)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? EvaluationDesign.accent : EvaluationDesign.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.accent.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
        )
    }
}

private struct SessionJournalQuickObservationCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "30 segundos",
            title: "Observación rápida",
            subtitle: "Una nota breve basta para mantener trazabilidad diaria."
        ) {
            TextField("Han necesitado más tiempo para la actividad 2…", text: $vm.journalDraft.groupObservations, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalQuickNextStepCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Siguiente sesión",
            title: "Próximo paso",
            subtitle: "Una decisión breve para no perder continuidad."
        ) {
            TextField("Repetir actividad 2, avanzar, adaptar material…", text: $vm.journalDraft.nextStepText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalDevelopmentCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Reflexión completa",
            title: "Lo planificado y lo realizado",
            subtitle: "Completar solo cuando haga falta más detalle pedagógico."
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
            ForEach(vm.journalDraft.notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Alumno", text: noteBinding(note.id, \.studentName))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Tag", text: noteBinding(note.id, \.tag))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(role: .destructive) {
                            vm.journalDraft.notes.removeAll { $0.id == note.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Observación", text: noteBinding(note.id, \.note), axis: .vertical)
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

    private func noteBinding(_ id: UUID, _ keyPath: WritableKeyPath<PlannerJournalDraftNote, String>) -> Binding<String> {
        Binding(
            get: {
                vm.journalDraft.notes.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = vm.journalDraft.notes.firstIndex(where: { $0.id == id }) else { return }
                vm.journalDraft.notes[index][keyPath: keyPath] = newValue
            }
        )
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

            ForEach(vm.journalDraft.media, id: \.id) { media in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(media.type.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            vm.journalDraft.media.removeAll { $0.id == media.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Título", text: mediaBinding(media.id, \.caption))
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                    if !media.uri.isEmpty {
                        Text(media.uri)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    TextField("Transcripción editable", text: mediaBinding(media.id, \.transcript), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func mediaBinding(_ id: UUID, _ keyPath: WritableKeyPath<PlannerJournalDraftMedia, String>) -> Binding<String> {
        Binding(
            get: {
                vm.journalDraft.media.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = vm.journalDraft.media.firstIndex(where: { $0.id == id }) else { return }
                vm.journalDraft.media[index][keyPath: keyPath] = newValue
            }
        )
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
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
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
                withAnimation(uiFeatureFlags.interactionAnimation) {
                    isExpanded.toggle()
                }
                AppleInteractionFeedback.play(.lightImpact)
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
                                withAnimation(uiFeatureFlags.interactionAnimation) {
                                    expandedGroupTitles = recommendedGroupTitles
                                }
                                AppleInteractionFeedback.play(.lightImpact)
                            }
                            .buttonStyle(.borderless)

                            Button("Contraer todo") {
                                withAnimation(uiFeatureFlags.interactionAnimation) {
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
                                    AppleInteractionFeedback.play(.selection)
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
                .transition(uiFeatureFlags.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
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
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
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
                withAnimation(uiFeatureFlags.interactionAnimation) {
                    isExpanded.toggle()
                }
                AppleInteractionFeedback.play(.lightImpact)
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
                .transition(uiFeatureFlags.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
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

struct PlannerSessionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    
    let session: PlanningSession
    let onOpenDiary: () -> Void
    let onEdit: () -> Void
    
    @State private var linkedInstruments: [PlannerAssessmentInstrument] = []
    @State private var isLoadingInstruments = false
    @State private var detailedPlan: LearningSituationSessionPlan?
    @State private var sequenceVersion: LearningSituationSessionSequenceVersion?
    @State private var sourceDocumentURL: URL?
    
    private var tint: Color {
        Color(hex: session.teachingUnitColor)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sessionBriefHeader
                quickActionBar
                ScrollView {
                    VStack(spacing: 16) {
                        if let detailedPlan {
                            teacherAtAGlanceSection(detailedPlan)
                            developmentTimeline(detailedPlan)
                            sourceDocumentSection(detailedPlan)
                        } else {
                            fallbackSessionSections
                        }
                        instrumentsSection
                    }
                    .padding(24)
                }
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Sesión")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDetailedPlan()
                await loadLinkedInstruments()
            }
            .quickLookPreview($sourceDocumentURL)
        }
#if os(macOS)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 720, idealHeight: 820)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }
    
    private var sessionBriefHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        sessionChip(session.groupName, systemImage: "person.3.fill")
                        sessionChip("Planificada", systemImage: "checkmark.circle.fill")
                        if let detailedPlan {
                            sessionChip("Sesión \(detailedPlan.sessionNumber)", systemImage: "number")
                            sessionChip("\(detailedPlan.sessionType) · \(detailedPlan.effectiveMinutes) min", systemImage: "timer")
                        }
                    }
                    Text(detailedPlan?.title ?? session.teachingUnitName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(dateAndTimeLabel, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openSourceDocumentPreview()
                } label: {
                    Label("Ver DOCX", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(sourceDocumentFileURL == nil)
            }
        }
        .padding(24)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var quickActionBar: some View {
        HStack(spacing: 16) {
            Button(action: onOpenDiary) {
                Label("Abrir ejecución", systemImage: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .keyboardShortcut(.defaultAction)

            Button(action: onEdit) {
                Label("Editar", systemImage: "pencil")
                    .font(.headline.weight(.semibold))
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(EvaluationDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var fallbackSessionSections: some View {
        VStack(spacing: 16) {
            let objText = session.objectives.trimmingCharacters(in: .whitespacesAndNewlines)
            if !objText.isEmpty {
                teacherCard(title: "Objetivo de hoy", icon: "target", text: objText, prominence: .hero)
            }

            let actText = session.activities.trimmingCharacters(in: .whitespacesAndNewlines)
            if !actText.isEmpty {
                teacherCard(title: "Actividades programadas", icon: "list.bullet.rectangle.portrait", text: actText)
            }

            let evalText = session.evaluation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !evalText.isEmpty {
                teacherCard(title: "Evaluación", icon: "checkmark.seal", text: evalText)
            }
        }
    }

    private func teacherAtAGlanceSection(_ plan: LearningSituationSessionPlan) -> some View {
        VStack(spacing: 16) {
            let objective = plan.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            if !objective.isEmpty {
                teacherCard(title: "Objetivo de hoy", icon: "target", text: objective, prominence: .hero)
            }

            let criteria = decodedCriteria(plan)
            let evidence = evidenceText(from: decodedDevelopment(plan))
            if !criteria.isEmpty || !evidence.isEmpty {
                evaluationCard(criteria: criteria, evidence: evidence)
            }

            let material = plan.material.trimmingCharacters(in: .whitespacesAndNewlines)
            if !material.isEmpty {
                materialCard(material)
            }

            let adaptations = decodedAdaptations(plan)
            if !adaptations.isEmpty {
                teacherCard(title: "Adaptaciones y contexto", icon: "person.crop.rectangle", text: adaptations.joined(separator: "\n"))
            }
        }
    }

    private func teacherCard(title: String, icon: String, text: String, prominence: TeacherCardProminence = .standard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(prominence == .hero ? .title3.weight(.semibold) : .body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(prominence == .hero ? 24 : 20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func evaluationCard(criteria: [String], evidence: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Evaluación", systemImage: "checkmark.seal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            if !criteria.isEmpty {
                WorkspaceFlowLayout(spacing: 8) {
                    ForEach(criteria, id: \.self) { criterion in
                        Text(criterion)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                }
            }
            if !evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidencia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(evidence)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func materialCard(_ material: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Material preparado", systemImage: "shippingbox")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            WorkspaceFlowLayout(spacing: 8) {
                ForEach(materialItems(from: material), id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(EvaluationDesign.surfaceSoft, in: Capsule())
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func developmentTimeline(_ plan: LearningSituationSessionPlan) -> some View {
        let sections = timelineSections(from: decodedDevelopment(plan))
        return Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Label("Desarrollo de la clase", systemImage: "list.bullet.rectangle.portrait")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(tint)
                        Spacer()
                        if plan.effectiveMinutes > 0 {
                            Text("\(plan.effectiveMinutes) min útiles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tint.opacity(0.10), in: Capsule())
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(sections) { section in
                            timelineBlock(section)
                        }
                    }
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
            }
        }
    }

    private func timelineBlock(_ section: LearningSituationSessionSectionDraft) -> some View {
        let marker = timelineMarker(from: section.title)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Capsule()
                    .fill(tint.opacity(0.16))
                    .frame(width: 2, height: 44)
            }
            .padding(.top, 8)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let marker {
                        Text(marker)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                    Text(cleanTimelineTitle(section.title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        timelineStep(line)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func timelineStep(_ line: String) -> some View {
        let parts = developmentLineParts(line)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(tint.opacity(0.72))
                .padding(.top, 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let title = parts.title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(parts.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func developmentLineParts(_ line: String) -> (title: String?, detail: String) {
        guard let separator = line.firstIndex(of: ":") else {
            return (nil, line)
        }
        let title = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !detail.isEmpty else { return (nil, line) }
        return (title, detail)
    }

    private func sourceDocumentSection(_ plan: LearningSituationSessionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documento original")
                        .font(.headline.weight(.semibold))
                    Text(sequenceVersion?.originalFileName ?? plan.sourceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    openSourceDocumentPreview()
                } label: {
                    Label("Ver documento", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(sourceDocumentFileURL == nil)
            }

            Text(sourceDocumentFileURL == nil ? "Documento original no disponible en este dispositivo." : "Abre una previsualización nativa para resolver dudas sin salir del planificador.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private var sourceDocumentFileURL: URL? {
        guard let path = sequenceVersion?.localPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func openSourceDocumentPreview() {
        guard let url = sourceDocumentFileURL else { return }
        sourceDocumentURL = url
    }

    private var dateAndTimeLabel: String {
        if let startTime = session.startTime, let endTime = session.endTime {
            return "\(dateString) · \(startTime)-\(endTime)"
        }
        return "\(dateString) · Periodo \(session.period)"
    }

    private func sessionChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private enum TeacherCardProminence {
        case standard
        case hero
    }

    private func decodedCriteria(_ plan: LearningSituationSessionPlan) -> [String] {
        ((try? JSONDecoder().decode([String].self, from: Data(plan.criteriaJson.utf8))) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodedDevelopment(_ plan: LearningSituationSessionPlan) -> [LearningSituationSessionSectionDraft] {
        (try? JSONDecoder().decode([LearningSituationSessionSectionDraft].self, from: Data(plan.developmentJson.utf8))) ?? []
    }

    private func decodedAdaptations(_ plan: LearningSituationSessionPlan) -> [String] {
        ((try? JSONDecoder().decode([String].self, from: Data(plan.adaptationsJson.utf8))) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func evidenceText(from sections: [LearningSituationSessionSectionDraft]) -> String {
        sections
            .filter { isEvidenceSection($0) }
            .flatMap { section in
                section.lines.isEmpty ? [metadataValue(from: section.title) ?? section.title] : section.lines
            }
            .map { metadataValue(from: $0) ?? $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func timelineSections(from sections: [LearningSituationSessionSectionDraft]) -> [LearningSituationSessionSectionDraft] {
        sections.compactMap { section in
            guard !isEvidenceSection(section), !isMetadataLine(section.title) else { return nil }
            let filteredLines = section.lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isMetadataLine($0) }
            if filteredLines.isEmpty, !looksLikeTimelineTitle(section.title) { return nil }
            return LearningSituationSessionSectionDraft(title: section.title, lines: filteredLines)
        }
    }

    private func isEvidenceSection(_ section: LearningSituationSessionSectionDraft) -> Bool {
        let title = normalizedSessionText(section.title)
        return title.hasPrefix("evidencia") || title.hasPrefix("evidence")
    }

    private func isMetadataLine(_ text: String) -> Bool {
        let value = normalizedSessionText(text)
        return value.hasPrefix("objective:")
            || value.hasPrefix("objectives:")
            || value.hasPrefix("objetivo:")
            || value.hasPrefix("objetivos:")
            || value.hasPrefix("criterion:")
            || value.hasPrefix("criteria:")
            || value.hasPrefix("criterio:")
            || value.hasPrefix("criterios:")
            || value.hasPrefix("materials:")
            || value.hasPrefix("material:")
            || value.hasPrefix("materiales:")
            || value.hasPrefix("evidence:")
            || value.hasPrefix("evidencia:")
    }

    private func metadataValue(from text: String) -> String? {
        guard let separator = text.firstIndex(of: ":") else { return nil }
        let prefix = normalizedSessionText(String(text[..<separator]))
        guard ["evidence", "evidencia"].contains(prefix) else { return nil }
        return String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func materialItems(from material: String) -> [String] {
        let items = material
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        return items.isEmpty ? [material] : items
    }

    private func timelineMarker(from title: String) -> String? {
        if let range = title.range(of: #"^[0-9]{1,3}\s*(?:'|’|min)?\s*[-–—]\s*[0-9]{1,3}\s*(?:'|’|min)?"#, options: .regularExpression) {
            return String(title[range])
        }
        if let range = title.range(of: #"\([0-9]{1,3}\s*(?:'|’|min)\)"#, options: .regularExpression) {
            return String(title[range]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        }
        return nil
    }

    private func cleanTimelineTitle(_ title: String) -> String {
        var result = title
            .replacingOccurrences(of: #"^[0-9]{1,3}\s*(?:'|’|min)?\s*[-–—]\s*[0-9]{1,3}\s*(?:'|’|min)?\s*:?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = title }
        return result
    }

    private func looksLikeTimelineTitle(_ title: String) -> Bool {
        timelineMarker(from: title) != nil ||
            normalizedSessionText(title).hasPrefix("block ") ||
            normalizedSessionText(title).hasPrefix("bloque ") ||
            normalizedSessionText(title).hasPrefix("break") ||
            normalizedSessionText(title).hasPrefix("descanso")
    }

    private func normalizedSessionText(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadDetailedPlan() async {
        guard let planId = session.learningSituationSessionPlanId?.int64Value else { return }
        guard let plan = try? await bridge.learningSituationSessionPlan(id: planId) else { return }
        detailedPlan = plan
        sequenceVersion = try? await bridge.learningSituationSessionSequenceVersion(
            id: plan.sequenceVersionId,
            learningSituationId: plan.learningSituationId
        )
    }
    
    private var instrumentsSection: some View {
        Group {
            if isLoadingInstruments {
                ProgressView()
                    .padding()
            } else if !linkedInstruments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.plaintext.fill")
                            .foregroundColor(tint)
                            .font(.headline)
                        Text("Evaluaciones enlazadas")
                            .font(.system(.headline, design: .rounded))
                            .bold()
                            .foregroundColor(.primary)
                    }
                    
                    VStack(spacing: 10) {
                        ForEach(linkedInstruments, id: \.id) { instrument in
                            HStack(spacing: 12) {
                                Image(systemName: instrument.kind == .rubric ? "tablecells" : "doc.text.magnifyingglass")
                                    .foregroundColor(tint)
                                    .font(.subheadline)
                                    .padding(8)
                                    .background(tint.opacity(0.1))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instrument.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(instrument.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(EvaluationDesign.surfaceSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 1)
                )
            }
        }
    }
    
    private var dateString: String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.yearForWeekOfYear = Int(session.year)
        components.weekOfYear = Int(session.weekNumber)
        components.weekday = Int(session.dayOfWeek) + 1
        
        guard let date = components.date else { return "" }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadLinkedInstruments() async {
        guard !session.linkedAssessmentIdsCsv.isEmpty else { return }
        isLoadingInstruments = true
        defer { isLoadingInstruments = false }
        
        do {
            let allInstruments = try await bridge.plannerAvailableAssessmentInstruments(
                classId: session.groupId,
                teachingUnitId: session.teachingUnitId == 0 ? nil : session.teachingUnitId
            )
            let linkedIds = Set(session.linkedAssessmentIdsCsv.split(separator: ",").map(String.init))
            linkedInstruments = allInstruments.filter { linkedIds.contains($0.id) }
        } catch {
            print("Error loading linked instruments: \(error)")
        }
    }
}
