import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import QuickLook
import MiGestorKit

enum PlannerCalendar {
    /// Año y semana ISO calculados a partir del mismo instante para evitar que,
    /// justo en el cambio de año, uno quede desfasado respecto al otro.
    static var currentIsoYearWeek: (year: Int, week: Int) {
        let calendar = Calendar(identifier: .iso8601)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return (
            components.yearForWeekOfYear ?? calendar.component(.yearForWeekOfYear, from: Date()),
            components.weekOfYear ?? calendar.component(.weekOfYear, from: Date())
        )
    }

    static var currentIsoYear: Int { currentIsoYearWeek.year }

    static var currentIsoWeek: Int { currentIsoYearWeek.week }

    /// Curso escolar por defecto (sept–jun) alrededor de la fecha actual.
    static var defaultSchoolYearStartIso: String {
        "\(schoolYearStartYear)-09-01"
    }

    static var defaultSchoolYearEndIso: String {
        "\(schoolYearStartYear + 1)-06-30"
    }

    private static var schoolYearStartYear: Int {
        let calendar = Calendar(identifier: .iso8601)
        let year = calendar.component(.year, from: Date())
        let month = calendar.component(.month, from: Date())
        return month >= 8 ? year : year - 1
    }
}

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
final class PlannerAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
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
final class PlannerCalendarStore: ObservableObject {
    @Published var week = PlannerCalendar.currentIsoWeek
    @Published var year = PlannerCalendar.currentIsoYear
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
final class PlannerSessionStore: ObservableObject {
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
final class PlannerScheduleStore: ObservableObject {
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
final class PlannerJournalStore: ObservableObject {
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
final class PlannerComposerStore: ObservableObject {
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

/// Aísla el estado que pinta el grid semanal (PlannerWeekMiniatureGrid/Layout/DetailPane)
/// en su propio ObservableObject para que escribir en el buscador u otros campos del
/// facade no invalide esas vistas: solo observan este store, no PlannerWorkspaceViewModel.
@MainActor
final class PlannerWeekBoardStore: ObservableObject {
    @Published var week = PlannerCalendar.currentIsoWeek
    @Published var year = PlannerCalendar.currentIsoYear
    @Published var visibleSlots: [PlannerVisibleSlot] = []
    @Published var timeSlots: [TimeSlotConfig] = []
    @Published var holidayDays: Set<Int> = []
    @Published var weekRenderModel: PlannerWeekRenderModel = .empty
}

/// Rango temporal del Resumen/informe: semana en curso, mes natural o una
/// evaluación completa (usa los periodos ya configurados por el docente).
enum PlannerReportRange: Hashable {
    case week
    case month
    case evaluationPeriod(Int64)
}

/// Datos ya resueltos para un rango del Resumen/informe: sesiones del rango,
/// sus resúmenes de diario y las semanas ISO que lo componen (para el PDF y
/// para las métricas de plan vs. real).
struct PlannerRangeData {
    let range: PlannerReportRange
    let rangeLabel: String
    let sessions: [PlanningSession]
    let journalSummaryBySessionId: [Int64: SessionJournalSummary]
    let weeks: [PlannerGanttWeek]

    static let empty = PlannerRangeData(
        range: .week,
        rangeLabel: "",
        sessions: [],
        journalSummaryBySessionId: [:],
        weeks: []
    )
}

