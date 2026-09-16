import Foundation
import MiGestorKit
import Combine
import Security
import CryptoKit

typealias KmpSubject = MiGestorKit.Subject
typealias WipeCategory = MiGestorKit.WipeCategory

@MainActor
final class KmpBridge: ObservableObject {
    static let plannerCoursePalette: [String] = [
        "#2563EB",
        "#0F766E",
        "#DC2626",
        "#7C3AED",
        "#EA580C",
        "#0891B2",
        "#65A30D",
        "#BE185D",
        "#4F46E5",
        "#B45309"
    ]

    @Published var status: String = "Inicializando..."
    /// Se pone a `true` al final de `bootstrap()`, tanto si termina bien como si
    /// falla. Permite a quien necesite saber si la carga inicial —incluido el
    /// primer *pull* de Sync LAN— ya ha terminado, esperarlo en vez de leer
    /// `classes`/`allStudents` mientras aún pueden estar vacíos de forma
    /// transitoria (p. ej. `OnboardingStore`, que decidiría "base vacía" en un
    /// iPad recién emparejado si mirara antes de que llegue el primer *pull*).
    @Published private(set) var hasCompletedBootstrap = false
    @Published var statsText: String = "-"
    @Published var classes: [SchoolClass] = []
    @Published var academicYears: [AcademicYearSnapshot] = []
    @Published var activeAcademicYear: AcademicYearSnapshot?
    @Published var archivedAcademicYears: [AcademicYearSnapshot] = []
    @Published var subjects: [KmpSubject] = []
    @Published var studentsInClass: [Student] = []
    @Published var evaluationsInClass: [Evaluation] = []
    @Published var rubrics: [RubricDetail] = []
    @Published var planning: [PlanPeriod] = []
    @Published var rubricsUiState: RubricUiState? = nil
    @Published var rubricClassLinks: [Int64: Set<Int64>] = [:]
    @Published var rubricBuilderTeachingUnits: [TeachingUnit] = []
    @Published var selectedRubricTeachingUnitId: Int64? = nil
    @Published var editingRubricBuilderId: Int64? = nil
    
    // Notebook State (Bridged from NotebookViewModel)
    @Published var notebookState: NotebookUiState = NotebookUiStateLoading()
    @Published var notebookStructureState = KmpBridge.emptyNotebookStructureState()
    @Published var notebookRowsState = KmpBridge.emptyNotebookRowsState()
    @Published var notebookSelectionState = KmpBridge.emptyNotebookSelectionState()
    @Published var notebookSaveState: NotebookViewModelSaveState = NotebookViewModelSaveState.saved
    @Published var notebookSplitSaveState = KmpBridge.emptyNotebookSaveState()
    @Published var notebookInspectorState = KmpBridge.emptyNotebookInspectorState()
    @Published var notebookAverageState = KmpBridge.emptyNotebookAverageState()
    
    // Rubric Evaluation State (Bridged from RubricEvaluationViewModel)
    @Published var rubricEvaluationState: RubricEvaluationUiState = RubricEvaluationUiState.companion.default()
    @Published var isNotebookRubricAutoAdvanceActive: Bool = false
    @Published var rubricEvaluationCoordinator = RubricEvaluationCoordinator()
    
    // Bulk Rubric Evaluation State
    @Published var bulkRubricEvaluationState: BulkRubricEvaluationUiState? = nil
    @Published var showingBulkRubricEvaluation: Bool = false
    
    // Detailed Dashboard Data
    @Published var upcomingClasses: [CalendarEvent] = []
    @Published var pendingTasks: [Incident] = []
    @Published var esoPercentage: Int = 0
    @Published var bachPercentage: Int = 0
    @Published var activityGroups: [ActivityGroup] = []
    @Published var dashboardSnapshot: DashboardSnapshot? = nil
    @Published var dashboardFilters: DashboardFilters = DashboardFilters(classId: nil, severity: nil, priority: nil, sessionStatus: nil)
    @Published var allStudents: [Student] = []
    @Published var selectedStudentsClassId: Int64? = nil
    @Published var studentImportPreview: AppleStudentImportPreview? = nil
    @Published var isImportingStudents = false

    // LAN Sync State
    @Published var discoveredSyncHosts: [String] = []
    @Published var syncStatusMessage: String = "Sync local inactivo"
    @Published var syncPendingChanges: Int = 0
    @Published var syncLastRunAt: Date? = nil
    @Published var pairedSyncHost: String? = nil
    @Published var syncDivergence: SyncDivergenceReport? = nil
    var lastDivergenceCheckAt: Date = .distantPast

    var hasPersistedLanPairing: Bool {
        !(syncToken?.isEmpty ?? true) && !((pairedServerId?.isEmpty ?? true) && (pairedServerFingerprint?.isEmpty ?? true))
    }
    
    // UI State for Sheets
    @Published var showingAddColumn = false
    @Published var editingWeightColumn: NotebookColumnDefinition? = nil
    @Published var selectedNotebookTabId: String? = nil

    struct ActivityGroup: Identifiable {
        let id = UUID()
        let name: String
        let average: Double
    }

    struct CourseInspectorSnapshot {
        let schoolClass: SchoolClass
        let studentCount: Int
        let injuredStudentCount: Int
        let attendanceRate: Int
        let todayPresentCount: Int
        let todayAbsentCount: Int
        let todayLateCount: Int
        let evaluationCount: Int
        let incidentCount: Int
        let severeIncidentCount: Int
        let weeklySlotCount: Int
        let averageScore: Double
        let rosterPreview: [Student]
        let activeEvaluationNames: [String]
    }

    struct AcademicYearSnapshot: Identifiable, Equatable {
        let id: Int64
        let name: String
        let startDate: Date
        let endDate: Date
        let status: String
        let isActive: Bool
        let archivedAt: Date?
        let classCount: Int
        let enrollmentCount: Int64
    }

    struct ClassroomCaptureContextSnapshot: Equatable {
        let classId: Int64
        let className: String
        let sessionId: Int64?
        let sessionTitle: String
    }

    struct StudentTimelineEntry: Identifiable {
        enum Kind {
            case attendance
            case incident
            case evaluation
        }

        let id = UUID()
        let date: Date
        let title: String
        let subtitle: String
        let kind: Kind
    }

    struct AttendanceRecordSnapshot: Identifiable {
        let id: Int64
        let studentId: Int64
        let classId: Int64
        let date: Date
        let status: String
        let note: String
        let hasIncident: Bool
        let followUpRequired: Bool
        let sessionId: Int64?
    }

    struct AttendanceDraft {
        let studentId: Int64
        let classId: Int64
        let date: Date
        let status: String
        let note: String
        let hasIncident: Bool
        let followUpRequired: Bool?
        let sessionId: Int64?
    }

    struct AttendanceClassOverview: Identifiable {
        let id: Int64
        let schoolClass: SchoolClass
        let studentCount: Int
        let presentCount: Int
        let absentCount: Int
        let lateCount: Int
        let pendingTodayCount: Int
        let attendanceRate: Int
    }

    struct TutoringSessionSnapshot: Identifiable, Hashable {
        let id: Int64
        let studentId: Int64
        let dateIso: String
        let channel: TutoringChannelUI
        let attendees: String
        let topics: String
        let agreements: String
        let reviewDueIso: String?
        let isClosed: Bool
    }

    struct TutoringSessionDraft {
        var studentId: Int64
        var dateIso: String
        var channel: TutoringChannelUI = .inPerson
        var attendees: String = ""
        var topics: String = ""
        var agreements: String = ""
        var reviewDueIso: String?
        var isClosed: Bool = false
    }

    struct MeetingAgreementSnapshot: Identifiable, Hashable {
        let id: Int64
        let meetingId: Int64
        let description: String
        let responsible: String
        let dueIso: String?
        let isDone: Bool
    }

    struct MeetingSnapshot: Identifiable, Hashable {
        let id: Int64
        let title: String
        let dateIso: String
        let type: MeetingTypeUI
        let location: String
        let attendees: String
        let summary: String
        let isClosed: Bool
        let agreements: [MeetingAgreementSnapshot]
    }

    struct MeetingDraft {
        var title: String = ""
        var dateIso: String
        var type: MeetingTypeUI = .otra
        var location: String = ""
        var attendees: String = ""
        var summary: String = ""
        var isClosed: Bool = false
    }

    struct MeetingAgreementDraft {
        var meetingId: Int64
        var description: String = ""
        var responsible: String = ""
        var dueIso: String?
        var isDone: Bool = false
    }

    struct WeekPlanSnapshot: Identifiable, Hashable {
        let id: Int64?
        let classId: Int64
        let year: Int
        let week: Int
        let strategyKeys: [String]
        let instrumentKeys: [String]
        let notes: String
    }

    struct WeekPlanDraft {
        var classId: Int64
        var year: Int
        var week: Int
        var strategyKeys: [String] = []
        var instrumentKeys: [String] = []
        var notes: String = ""
    }

    struct SupportMeasureSnapshot: Identifiable {
        let id: Int64
        let studentId: Int64
        let level: SupportMeasureLevelUI
        let measureType: SupportMeasureTypeUI
        let startDateIso: String
        let endDateIso: String?
        let responsible: String?
        let intensity: SupportMeasureIntensityUI?
        let followUpNotes: String
        let documentRef: String?
        let reviewDueIso: String?
        let isActive: Bool

        var asRow: SupportMeasureRow {
            SupportMeasureRow(
                id: id,
                studentId: studentId,
                level: level,
                measureType: measureType,
                startDateIso: startDateIso,
                endDateIso: endDateIso,
                responsible: responsible,
                intensity: intensity,
                followUpNotes: followUpNotes,
                documentRef: documentRef,
                reviewDueIso: reviewDueIso,
                isActive: isActive
            )
        }
    }

    struct AttendanceSessionSnapshot: Identifiable {
        let id: Int64
        let session: PlanningSession
        let journalSummary: SessionJournalSummary?
    }

    struct DiarySessionSnapshot: Identifiable {
        let id: Int64
        let session: PlanningSession
        let journalSummary: SessionJournalSummary?

        var hasIncidents: Bool {
            !(journalSummary?.incidentTags.isEmpty ?? true)
        }
    }

    struct StudentProfileSnapshot {
        let student: Student
        let schoolClass: SchoolClass?
        let attendanceRate: Int
        let averageScore: Double
        let incidentCount: Int
        let followUpCount: Int
        let instrumentsCount: Int
        let evidenceCount: Int
        let familyCommunicationCount: Int
        let journalSessionCount: Int
        let journalNoteCount: Int
        let adaptationsSummary: String?
        let familyCommunicationSummary: String?
        let latestAttendanceStatus: String?
        let evaluationTitles: [String]
        let recentAttendance: [AttendanceRecordSnapshot]
        let incidents: [Incident]
        let evaluations: [Evaluation]
        let timeline: [StudentTimelineEntry]
    }

    struct MacStudentRowSnapshot: Identifiable {
        let id: Int64
        let student: Student
        let classId: Int64?
        let className: String
        let allClassMemberships: [MacStudentClassMembership]
        let followUpLabel: String
        let recentAttendanceLabel: String
        let averageText: String
        let incidentCount: Int
        let lastObservationText: String
        let isInjured: Bool
        let isFollowUp: Bool
        let workGroupName: String
    }

    struct MacStudentClassMembership: Identifiable {
        let id: Int64
        let className: String
    }

    struct ReportPreviewPayload {
        let classId: Int64
        let className: String
        let previewText: String
        let generatedAt: Date
    }

    enum ReportKind: String, CaseIterable, Identifiable {
        case groupOverview
        case studentSummary
        case evaluationDigest
        case operationsSnapshot
        case lomloeEvaluationComment

        var id: String { rawValue }

        var title: String {
            switch self {
            case .groupOverview: return "Informe de grupo"
            case .studentSummary: return "Informe individual"
            case .evaluationDigest: return "Resumen de evaluación"
            case .operationsSnapshot: return "Resumen operativo"
            case .lomloeEvaluationComment: return "Comentario LOMLOE"
            }
        }

        var subtitle: String {
            switch self {
            case .groupOverview: return "Medias y pulso general del grupo"
            case .studentSummary: return "Seguimiento sintético para tutoría"
            case .evaluationDigest: return "Instrumentos, rúbricas y carga activa"
            case .operationsSnapshot: return "Asistencia, incidencias y estado docente"
            case .lomloeEvaluationComment: return "Comentario trimestral de EF listo para informe"
            }
        }

        var systemImage: String {
            switch self {
            case .groupOverview: return "person.3.sequence.fill"
            case .studentSummary: return "person.text.rectangle.fill"
            case .evaluationDigest: return "chart.bar.doc.horizontal"
            case .operationsSnapshot: return "bolt.badge.clock.fill"
            case .lomloeEvaluationComment: return "text.badge.star"
            }
        }

        var requiresStudentSelection: Bool {
            self == .studentSummary || self == .lomloeEvaluationComment
        }
    }

    struct ReportMetric: Identifiable {
        let title: String
        let value: String
        let systemImage: String

        var id: String { title }
    }

    struct ReportGenerationContext {
        let classId: Int64
        let className: String
        let studentId: Int64?
        let studentName: String?
        let kind: ReportKind
        let reportTitle: String
        let courseLabel: String?
        let termLabel: String?
        let numericScore: Double?
        let curriculumReferences: [String]
        let promptDirectives: [String]
        let audienceHint: String
        let summary: String
        let metrics: [ReportMetric]
        let factLines: [String]
        let strengths: [String]
        let needsAttention: [String]
        let recommendedActions: [String]
        let supportNotes: [String]
        let classicReportText: String
        let hasEnoughData: Bool
        let dataQualityNote: String?
        let trends: AITrendsSnapshot?
    }

    enum AnalyticsTimeRange: String, CaseIterable, Identifiable {
        case last14Days
        case last30Days
        case last90Days

        var id: String { rawValue }

        var title: String {
            switch self {
            case .last14Days: return "Últimos 14 días"
            case .last30Days: return "Últimos 30 días"
            case .last90Days: return "Últimos 90 días"
            }
        }

        var dayCount: Int {
            switch self {
            case .last14Days: return 14
            case .last30Days: return 30
            case .last90Days: return 90
            }
        }
    }

    enum ChartKind: String, CaseIterable, Identifiable {
        case attendanceTrend
        case attendanceComparison
        case incidentHeatmap
        case uniformComparison
        case groupAveragesRanking
        case sameCourseComparison

        var id: String { rawValue }

        var title: String {
            switch self {
            case .attendanceTrend: return "Evolución de asistencia"
            case .attendanceComparison: return "Comparativa de asistencia"
            case .incidentHeatmap: return "Heatmap de incidencias"
            case .uniformComparison: return "Faltas de equipación"
            case .groupAveragesRanking: return "Ranking de medias"
            case .sameCourseComparison: return "Comparativa global"
            }
        }

        var subtitle: String {
            switch self {
            case .attendanceTrend: return "Pulso temporal del grupo"
            case .attendanceComparison: return "Comparación entre grupos del mismo curso"
            case .incidentHeatmap: return "Patrones por día de la semana"
            case .uniformComparison: return "Alertas operativas en EF"
            case .groupAveragesRanking: return "Medias registradas por grupo"
            case .sameCourseComparison: return "Asistencia, evaluación y rendimiento"
            }
        }

        var systemImage: String {
            switch self {
            case .attendanceTrend: return "waveform.path.ecg"
            case .attendanceComparison: return "person.3.sequence.fill"
            case .incidentHeatmap: return "square.grid.3x3.topleft.filled"
            case .uniformComparison: return "figure.run.square.stack"
            case .groupAveragesRanking: return "chart.bar.xaxis"
            case .sameCourseComparison: return "chart.xyaxis.line"
            }
        }

        var chartTypeLabel: String {
            switch self {
            case .attendanceTrend: return "Línea"
            case .attendanceComparison: return "Barras agrupadas"
            case .incidentHeatmap: return "Heatmap"
            case .uniformComparison: return "Barras agrupadas"
            case .groupAveragesRanking: return "Ranking horizontal"
            case .sameCourseComparison: return "Barras comparativas"
            }
        }

        var groupingLabel: String {
            switch self {
            case .attendanceTrend: return "Día"
            case .incidentHeatmap: return "Semana y día"
            default: return "Grupo"
            }
        }
    }

    struct ChartPoint: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let value: Double
        let note: String?
    }

    struct ChartSeries: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let colorToken: String
        let points: [ChartPoint]
    }

    struct HeatmapCell: Identifiable, Hashable {
        let id = UUID()
        let rowLabel: String
        let columnLabel: String
        let value: Double
    }

    struct ChartFacts: Identifiable {
        let chartKind: ChartKind
        let title: String
        let subtitle: String
        let chartType: String
        let timeRange: String
        let grouping: String
        let metrics: [ReportMetric]
        let factLines: [String]
        let highlights: [String]
        let warnings: [String]
        let series: [ChartSeries]
        let heatmapCells: [HeatmapCell]
        let hasEnoughData: Bool
        let emptyStateMessage: String?
        let teacherDigest: String
        let insertableSummary: String

        var id: String { chartKind.rawValue }
    }

    struct AnalyticsRequest {
        let chartKind: ChartKind
        let timeRange: AnalyticsTimeRange
        let selectedClassIds: [Int64]
        let selectedClassNames: [String]
        let prompt: String?
        let querySummary: String
    }

    enum ScreenAIContextKind: String, Identifiable {
        case dashboard
        case courses
        case students
        case notebook
        case attendance
        case diary
        case evaluation
        case reports
        case pe

        var id: String { rawValue }
    }

    struct ContextualAIAction: Identifiable, Hashable {
        enum ActionID: String {
            case operationalSummary
            case prioritizedAlerts
            case weeklyDigest
            case dailyBriefing
            case classSnapshot
            case studentFollowUp
            case studentRiskRadar
            case familyComment
            case tutoringDraft
            case attendancePatterns
            case followUpList
            case diarySummary
            case nextSteps
            case sessionClosure
            case evaluationDigest
            case progressReadout
            case groupInsight
            case notebookGroupSummary
            case notebookStudentComment
            case observationProposal
            case reportBridge
            case peOperationalSummary
            case peEquipmentSummary
            case peComparison
        }

        let actionId: ActionID
        let title: String
        let subtitle: String
        let systemImage: String
        let promptHint: String

        var id: String { actionId.rawValue }
    }

    struct ScreenAIContext {
        let kind: ScreenAIContextKind
        let title: String
        let subtitle: String
        let classId: Int64?
        let className: String?
        let studentId: Int64?
        let studentName: String?
        let summary: String
        let metrics: [ReportMetric]
        let factLines: [String]
        let supportNotes: [String]
        let suggestedActions: [ContextualAIAction]
        let hasEnoughData: Bool
        let dataQualityNote: String?

        func copy(
            kind: ScreenAIContextKind? = nil,
            title: String? = nil,
            subtitle: String? = nil,
            classId: Int64? = nil,
            className: String? = nil,
            studentId: Int64? = nil,
            studentName: String? = nil,
            summary: String? = nil,
            metrics: [ReportMetric]? = nil,
            factLines: [String]? = nil,
            supportNotes: [String]? = nil,
            suggestedActions: [ContextualAIAction]? = nil,
            hasEnoughData: Bool? = nil,
            dataQualityNote: String? = nil
        ) -> ScreenAIContext {
            ScreenAIContext(
                kind: kind ?? self.kind,
                title: title ?? self.title,
                subtitle: subtitle ?? self.subtitle,
                classId: classId ?? self.classId,
                className: className ?? self.className,
                studentId: studentId ?? self.studentId,
                studentName: studentName ?? self.studentName,
                summary: summary ?? self.summary,
                metrics: metrics ?? self.metrics,
                factLines: factLines ?? self.factLines,
                supportNotes: supportNotes ?? self.supportNotes,
                suggestedActions: suggestedActions ?? self.suggestedActions,
                hasEnoughData: hasEnoughData ?? self.hasEnoughData,
                dataQualityNote: dataQualityNote ?? self.dataQualityNote
            )
        }
    }

    struct NotebookAIColumnValue: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let categoryLabel: String
    }

    struct NotebookAICommentContext {
        let classId: Int64
        let className: String
        let studentId: Int64
        let studentName: String
        let averageScore: Double?
        let attendanceStatus: String?
        let followUpCount: Int
        let incidentCount: Int
        let evidenceCount: Int
        let competencyLabels: [String]
        let relevantValues: [NotebookAIColumnValue]
        let existingComment: String?
        let summary: String
        let hasEnoughData: Bool
        let dataQualityNote: String?
        let trends: AITrendsSnapshot?
    }

    struct AITrendsSnapshot: Codable, Equatable {
        let trendDirection: String
        let averageGradeDelta: Double
        let attendanceCorrelationNote: String
        let behaviorIncidentSummary: String
        let curriculumCoveragePct: Double
        let missingCompetencyLabels: [String]
        let recentGrades: [Double]
        let attendanceRate: Double
    }

    struct RubricUsageSnapshot {
        struct EvaluationUsage: Identifiable {
            let id = UUID()
            let classId: Int64
            let className: String
            let evaluationId: Int64
            let evaluationName: String
            let evaluationType: String
            let weight: Double
        }

        let rubricId: Int64
        let classCount: Int
        let evaluationCount: Int
        let linkedClassNames: [String]
        let evaluationUsages: [EvaluationUsage]
    }

    struct PhysicalTestSnapshot {
        struct StudentResult: Identifiable {
            let id: Int64
            let student: Student
            let gradeId: Int64?
            let value: Double?
        }

        let evaluation: Evaluation
        let results: [StudentResult]
        let average: Double
        let best: Double?
        let recordedCount: Int
    }

    struct PESessionSnapshot: Identifiable {
        let id: Int64
        let session: PlanningSession
        let summary: SessionJournalSummary?
        let materialToPrepareText: String
        let materialUsedText: String
        let injuriesText: String
        let unequippedStudentsText: String
        let intensityScore: Int
        let stationObservationsText: String
        let physicalIncidentsText: String
    }

    let container: KmpContainer
    let appleBootstrap: AppleBridgeBootstrap
    let appleImportFacade = AppleImportFacade()
    let notebookViewModel: NotebookViewModel
    let plannerViewModel: PlannerViewModel
    let rubricEvaluationViewModel: RubricEvaluationViewModel
    let rubricBulkEvaluationViewModel: RubricBulkEvaluationViewModel
    let rubricsViewModel: RubricsViewModel
    let lanSyncClient = LanSyncClient()
    let syncEventListener = SyncEventListener()
    let lanSyncDiscovery = LanSyncDiscovery()
    let syncSecureStore = IosKeychainStore(service: "com.migestor.sync.ios")
    var syncToken: String? = nil
    var pairedServerId: String? = nil
    var pairedServerFingerprint: String? = nil
    /// Canonical JSON por SHA y número de sesión. Evita volver a parsear el mismo DOCX una vez
    /// por plan al abrir el Planner o al reparar una planificación histórica.
    var sessionPlanJSONCacheBySource: [String: [Int: String]] = [:]
    var discoveredPeersByHost: [String: LanDiscoveredPeer] = [:]
    var autoSyncLoopTask: Task<Void, Never>? = nil
    var autoSyncDebounceTask: Task<Void, Never>? = nil
    var localChangesNotifyTask: Task<Void, Never>? = nil
    var pendingChangesPersistenceTask: Task<Void, Never>? = nil
    var notebookSnapshotDebounceTask: Task<Void, Never>? = nil
    var pendingGradeSnapshotTask: Task<Void, Never>? = nil
    var postSyncRefreshTask: Task<Void, Never>? = nil
    var isPairingInFlight = false
    var isSyncInFlight = false
    var syncNeedsAnotherPass = false
    var isAppInForeground = true
    var lastLocalMutationAt: Date = .distantPast
    var lastCheckedDbModificationDate: Date = .distantPast
    var lastSuccessfulSyncAt: Date = .distantPast
    var lastFullPullAt: Date = .distantPast
    var lastSilentSyncAttemptAt: Date = .distantPast
    var lastSyncCursorEpochMs: Int64 = UserDefaults.standard.object(forKey: "sync.last.cursor") as? Int64 ?? 0
    var selectedNotebookTabByClassId: [String: String] = {
        guard let raw = UserDefaults.standard.dictionary(forKey: "notebook.selected.tab.by.class.v1") as? [String: String] else {
            return [:]
        }
        return raw
    }()
    var plannerCourseColorByClassId: [String: String] = {
        guard let raw = UserDefaults.standard.dictionary(forKey: "planner.class.colors.v1") as? [String: String] else {
            return [:]
        }
        return raw
    }()
    /// Cola de cambios pendientes – persiste en UserDefaults para sobrevivir reinicios.
    var pendingOutboundChanges: [LanSyncChange] = {
        guard let data = UserDefaults.standard.data(forKey: "sync.pending.changes.v2"),
              let decoded = try? JSONDecoder().decode([LanSyncChange].self, from: data)
        else { return [] }
        return decoded
    }()
    var pendingLocalSseChanges: [LanSyncChange] = []
    var notebookSyncCache: NotebookSyncCache = {
        guard let data = UserDefaults.standard.data(forKey: "sync.notebook.cache.v1"),
              let decoded = try? JSONDecoder().decode(NotebookSyncCache.self, from: data)
        else { return NotebookSyncCache() }
        return decoded
    }()
    lazy var localDeviceId: String = loadOrCreateLocalDeviceId()
    private var didBootstrap = false
    private var cancellables = Set<AnyCancellable>()
    private let notebookStateSubject = CurrentValueSubject<NotebookUiState, Never>(NotebookUiStateLoading())
    var cachedNotebookStateIdentity: ObjectIdentifier? = nil
    var cachedNotebookCellValueIndex: NotebookCellValueIndex? = nil
    var lastNotebookAggregateSignature: String? = nil
    private var gradeOnTenFormatCache: [String: String] = [:]
    private struct OptimisticAnnotation {
        let note: String?
        let icon: String?
        let attachmentUris: [String]
    }
    private var optimisticGradeDrafts: [String: String] = [:]
    private var optimisticTextDrafts: [String: String] = [:]
    private var optimisticAnnotations: [String: OptimisticAnnotation] = [:]

    struct NotebookCellValueIndex {
        var textByKey: [String: String] = [:]
        var displayByKey: [String: String] = [:]
        var checkByKey: [String: Bool] = [:]
        var numericByKey: [String: String] = [:]
        var numericByEvalKey: [String: String] = [:]
        var numericDraftByKey: [String: String] = [:]
        var checkDraftByKey: [String: Bool] = [:]
        var textDraftByKey: [String: String] = [:]
    }

    init() {
        self.appleBootstrap = AppleBridgeBootstrap.current()
        self.container = appleBootstrap.container
        
        // Initialize Shared ViewModels
        self.notebookViewModel = NotebookViewModel(
            notebookRepository: container.notebookRepository,
            evaluationsRepository: container.evaluationsRepository,
            rubricsRepository: container.rubricsRepository,
            studentImporter: StudentImporter(),
            scope: MainScope()
        )

        self.plannerViewModel = PlannerViewModel(
            plannerRepo: container.plannerRepository,
            classRepo: container.classesRepository,
            weeklyTemplateRepo: container.weeklyTemplateRepository,
            plannedSessionRepo: container.plannedSessionRepository,
            generateSessionsFromUD: container.generateSessionsFromUD,
            scope: MainScope()
        )
        
        self.rubricEvaluationViewModel = RubricEvaluationViewModel(
            rubricsRepository: container.rubricsRepository,
            studentsRepository: container.studentsRepository,
            evaluationsRepository: container.evaluationsRepository,
            gradesRepository: container.gradesRepository,
            notebookRepository: container.notebookRepository,
            scope: MainScope()
        )
        
        self.rubricBulkEvaluationViewModel = RubricBulkEvaluationViewModel(
            rubricsRepository: container.rubricsRepository,
            studentsRepository: container.studentsRepository,
            notebookRepository: container.notebookRepository,
            gradesRepository: container.gradesRepository,
            scope: MainScope()
        )
        
        self.rubricsViewModel = RubricsViewModel(
            rubricsRepository: container.rubricsRepository,
            classesRepository: container.classesRepository,
            evaluationsRepository: container.evaluationsRepository,
            notebookRepository: container.notebookRepository,
            scope: MainScope()
        )
        
        migrateLegacySyncSecretsFromUserDefaults()
        self.syncToken = syncSecureStore.loadString(key: "sync.token")
        self.pairedSyncHost = syncSecureStore.loadString(key: "sync.host")
        self.pairedServerId = syncSecureStore.loadString(key: "sync.server.id")
        self.pairedServerFingerprint = syncSecureStore.loadString(key: "sync.server.fingerprint")
        
        #if os(macOS)
        // On macOS the sync endpoint is the helper process, which is NOT running yet at
        // init time. We intentionally leave pairedSyncHost as nil here so that
        // startSyncEventListenerIfPaired() and syncNow() are no-ops until
        // MacCommandCenterCoordinator calls notifyHelperReady(host:port:) once the
        // helper has published a valid LAN IP address.
        self.syncToken = "loopback-token"
        self.pairedSyncHost = nil
        self.pairedServerFingerprint = nil
        #endif

        self.lanSyncDiscovery.onPeersChanged = { [weak self] peers in
            Task { @MainActor in
                guard let self else { return }
                let uniquePeers = Self.deduplicateDiscoveredPeers(peers)
                self.discoveredPeersByHost = Dictionary(
                    uniquePeers.map { ($0.host, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                self.discoveredSyncHosts = uniquePeers.map(\.host).sorted()
                self.rebindPairedHostIfNeeded()
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lanSyncDiscovery.start()
            self.startAutoSyncLoop()
            self.startSyncEventListenerIfPaired()
            #if os(iOS)
            // On iOS the persisted host/token come from a real pairing; rehydrate on launch.
            if self.hasPersistedLanPairing {
                await self.syncNow(reason: "rehydrate", forceFullPull: false, silent: true)
            }
            #endif
        }

        setupObservers()
    }

    deinit {
        autoSyncLoopTask?.cancel()
        autoSyncDebounceTask?.cancel()
        pendingChangesPersistenceTask?.cancel()
        syncEventListener.stop()
        notebookSnapshotDebounceTask?.cancel()
        pendingGradeSnapshotTask?.cancel()
        postSyncRefreshTask?.cancel()
    }

    private static func emptyNotebookStructureState() -> NotebookStructureState {
        NotebookStructureState(
            classId: nil,
            tabs: [],
            columns: [],
            categories: [],
            workGroups: [],
            workGroupMembers: [],
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookRowsState() -> NotebookRowsState {
        NotebookRowsState(
            classId: nil,
            rows: [],
            numericDrafts: [:],
            textDrafts: [:],
            checkDrafts: [:],
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookSelectionState() -> NotebookSelectionState {
        NotebookSelectionState(
            selectedColumnIds: [],
            isColumnSelectionMode: false,
            activeCell: nil,
            activeCellEditor: nil,
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookSaveState() -> NotebookSaveState {
        NotebookSaveState(
            state: NotebookViewModelSaveState.saved,
            isDirty: false,
            isSaving: false,
            isSaved: true
        )
    }

    private static func emptyNotebookInspectorState() -> NotebookInspectorState {
        NotebookInspectorState(
            rubricEvaluationTarget: nil,
            activeCellEditor: nil,
            activeCell: nil,
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookAverageState() -> NotebookAverageState {
        NotebookAverageState(
            classId: nil,
            averagesByStudentId: [:],
            explanationsByStudentId: [:],
            isLoading: true,
            errorMessage: nil
        )
    }

    private func notebookAggregateSignature(for state: NotebookUiState) -> String? {
        guard let data = state as? NotebookUiStateData else {
            return String(describing: type(of: state))
        }

        let sheet = data.sheet
        let columnsSignature = sheet.columns.map { column in
            [
                column.id,
                column.title,
                "\(column.order)",
                "\(column.widthDp)",
                "\(column.visibility)",
                "\(column.isHidden)",
                column.categoryId ?? "",
                column.tabIds.joined(separator: ","),
                "\(column.weight)",
                "\(column.countsTowardAverage)"
            ].joined(separator: ":")
        }.joined(separator: "|")

        let categoriesSignature = sheet.columnCategories.map { category in
            "\(category.id):\(category.tabId):\(category.name):\(category.order):\(category.isCollapsed)"
        }.joined(separator: "|")

        let rowsSignature = sheet.rows.map { row in
            let cells = row.cells.map { cell in
                "\(String(describing: cell.evaluationId)):\(String(describing: cell.value))"
            }.joined(separator: ",")
            let persistedCells = row.persistedCells.map { cell in
                [
                    cell.columnId,
                    cell.textValue ?? "",
                    String(describing: cell.boolValue),
                    cell.iconValue ?? "",
                    cell.annotation?.icon ?? "",
                    cell.annotation?.note ?? "",
                    "\(cell.annotation?.attachmentUris.count ?? 0)",
                    cell.ordinalValue ?? "",
                    cell.displayValue ?? ""
                ].joined(separator: ":")
            }.joined(separator: ",")
            let grades = row.persistedGrades.map { grade in
                "\(grade.columnId):\(String(describing: grade.value)):\(String(describing: grade.evaluationId))"
            }.joined(separator: ",")
            return "\(row.student.id):\(String(describing: row.weightedAverage)):\(cells):\(persistedCells):\(grades)"
        }.joined(separator: "|")

        return [
            "class:\(sheet.classId)",
            "tabs:\(sheet.tabs.map { "\($0.id):\($0.title):\($0.order)" }.joined(separator: "|"))",
            "columns:\(columnsSignature)",
            "categories:\(categoriesSignature)",
            "rows:\(rowsSignature)",
            "numeric:\(data.numericDrafts.description)",
            "text:\(data.textDrafts.description)",
            "check:\(data.checkDrafts.description)",
            "groups:\(sheet.workGroups.map { "\($0.id):\($0.tabId):\($0.name):\($0.order):\($0.learningSituationId?.int64Value ?? -1)" }.joined(separator: ";"))",
            "groupMembers:\(sheet.workGroupMembers.map { "\($0.tabId):\($0.groupId):\($0.studentId)" }.joined(separator: ";"))"
        ].joined(separator: "¬")
    }

    private func setupObservers() {
        #if os(macOS)
        // macOS: react to the helper process lifecycle via NotificationCenter so the
        // SSE listener and auto-sync loop start only when the server is actually ready.
        NotificationCenter.default.addObserver(
            forName: .syncHelperBecameReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let host = notification.userInfo?["host"] as? String,
                  let port = notification.userInfo?["port"] as? Int else { return }
            Task { @MainActor in
                self.notifyHelperReady(host: host, port: port)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .syncHelperStopped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.notifyHelperStopped()
            }
        }
        #endif

        // Observe Notebook State with Debounce (to stabilize UI during typing)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.state.asAsyncSequence(type: NotebookUiState.self)
            for await state in sequence {
                if state is NotebookUiStateLoading {
                    // Solo propagar Loading si aún no tenemos datos previos (primera carga).
                    // Si ya había datos, ignoramos la transición a Loading para no destruir
                    // la jerarquía SwiftUI ni los @State/@FocusState de las celdas en edición.
                    if self.notebookState is NotebookUiStateLoading {
                        self.notebookState = state
                        self.invalidateNotebookCellValueIndexCache()
                    }
                    // Si ya teníamos datos, ignoramos el Loading: el ViewModel
                    // emitirá Data de vuelta cuando termine la recarga silenciosa.
                } else {
                    let signature = self.notebookAggregateSignature(for: state)
                    if signature == nil || signature != self.lastNotebookAggregateSignature {
                        self.lastNotebookAggregateSignature = signature
                        notebookStateSubject.send(state)
                    }
                }
            }
        }
        
        notebookStateSubject
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.notebookState = state
                self.invalidateNotebookCellValueIndexCache()
            }
            .store(in: &cancellables)
        
        // Observe Notebook Save State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.saveState.asAsyncSequence(type: NotebookViewModelSaveState.self)
            for await saveState in sequence {
                self.notebookSaveState = saveState
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.structureState.asAsyncSequence(type: NotebookStructureState.self)
            for await state in sequence {
                self.notebookStructureState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.rowsState.asAsyncSequence(type: NotebookRowsState.self)
            for await state in sequence {
                self.notebookRowsState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.selectionState.asAsyncSequence(type: NotebookSelectionState.self)
            for await state in sequence {
                self.notebookSelectionState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.notebookSaveState.asAsyncSequence(type: NotebookSaveState.self)
            for await state in sequence {
                self.notebookSplitSaveState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.inspectorState.asAsyncSequence(type: NotebookInspectorState.self)
            for await state in sequence {
                self.notebookInspectorState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.averageState.asAsyncSequence(type: NotebookAverageState.self)
            for await state in sequence {
                self.notebookAverageState = state
            }
        }
        
        // Observe Rubric Evaluation State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = rubricEvaluationViewModel.uiState.asAsyncSequence(type: RubricEvaluationUiState.self)
            for await state in sequence {
                let wasSaveSuccessful = self.rubricEvaluationState.isSaveSuccessful
                self.rubricEvaluationState = state
                if state.isSaveSuccessful && !wasSaveSuccessful && !self.isNotebookRubricAutoAdvanceActive {
                    self.refreshCurrentNotebook()
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
            }
        }
        
        // Observe Rubric Bulk Evaluation State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = rubricBulkEvaluationViewModel.uiState.asAsyncSequence(type: BulkRubricEvaluationUiState.self)
            for await state in sequence {
                let wasSaveSuccessful = self.bulkRubricEvaluationState?.isSaveSuccessful ?? false
                self.bulkRubricEvaluationState = state
                if state.isSaveSuccessful && !wasSaveSuccessful {
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
            }
        }

        // Observe Rubrics Builder/Bank State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = rubricsViewModel.uiState.asAsyncSequence(type: RubricUiState.self)
            for await state in sequence {
                self.rubricsUiState = state
                self.rubrics = state.savedRubrics
            }
        }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            if !UserDefaults.standard.bool(forKey: Self.hasCompletedInitialSeedKey) {
                try await seedIfNeeded()
                UserDefaults.standard.set(true, forKey: Self.hasCompletedInitialSeedKey)
            }
            try await refreshDashboard()
            try await loadDashboard(mode: .office)
            try await refreshClasses()
            try await refreshSubjects()
            try await refreshRubrics()
            try await refreshRubricClassLinks()
            try await refreshPlanning()
            try await refreshStudentsDirectory()
            await syncNow(reason: "bootstrap", forceFullPull: true, silent: true)
            status = appleBootstrap.connectedStatusText
        } catch {
            didBootstrap = false
            status = "Error: \(error.localizedDescription)"
        }
        hasCompletedBootstrap = true
    }

    var appDatabasePath: String {
        appleBootstrap.databasePath
    }

    /// Fuera del SQLite a propósito: `wipeAllData()` (Ajustes → Zona de Riesgo)
    /// borra el fichero de base de datos entero, así que cualquier marca que
    /// viviera dentro de una tabla desaparecería con él y la siembra de
    /// datos de demo (`seedDemoDataIfEmpty`, que solo mira si hay alumnos)
    /// volvería a dispararse en el siguiente arranque, deshaciendo el
    /// borrado. `UserDefaults` sobrevive al borrado del SQLite, así que una
    /// vez sembrado no se vuelve a sembrar nunca más, ni siquiera tras un
    /// borrado deliberado.
    private static let hasCompletedInitialSeedKey = "demo.seed.completed.v1"

    private func seedIfNeeded() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.seedDemoDataIfEmpty { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func refreshDashboard() async throws {
        let stats = try await container.dashboardRepository.getStats()
        
        // Fetch Upcoming Classes
        let allEvents = try await container.calendarRepository.listEvents(classId: nil)
        let now = ClockSystem.shared.now()
        let upcoming = allEvents.filter { $0.startAt.epochSeconds > now.epochSeconds }
            .sorted { $0.startAt.epochSeconds < $1.startAt.epochSeconds }
            .prefix(3).map { $0 }

        // Fetch Classes for distribution and tasks
        let allClasses = try await container.classesRepository.listClasses()
        
        // Pending Tasks (Incidents)
        var allIncidents: [Incident] = []
        for cls in allClasses {
            let incidents = try await container.incidentsRepository.listIncidents(classId: cls.id)
            allIncidents.append(contentsOf: incidents)
        }
        let pending = Array(allIncidents.prefix(3))
        
        // Activity Groups (Averages by Class)
        var groups: [ActivityGroup] = []
        let recentClasses = allClasses.prefix(6)
        for cls in recentClasses {
            let grades = try await container.gradesRepository.listGradesForClass(classId: cls.id)
            let values = grades.compactMap { $0.value?.doubleValue }
            let avg = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
            groups.append(ActivityGroup(name: cls.name, average: avg))
        }

        statsText = "Alumnos \(stats.totalStudents) · Clases \(stats.totalClasses) · Eval \(stats.totalEvaluations)"
        self.upcomingClasses = upcoming
        
        // Distribution
        let esoCount = allClasses.filter { $0.course <= 4 }.count
        let totalC = max(allClasses.count, 1)
        let ratio = Double(esoCount) / Double(totalC)
        self.esoPercentage = Int(ratio * 100)
        self.bachPercentage = 100 - self.esoPercentage
        
        self.pendingTasks = pending
        self.activityGroups = groups
    }

    func loadDashboard(mode: DashboardMode) async throws {
        dashboardFilters = DashboardFilters(
            classId: dashboardFilters.classId,
            severity: dashboardFilters.severity,
            priority: dashboardFilters.priority,
            sessionStatus: dashboardFilters.sessionStatus
        )
        let snapshot = try await container.getOperationalDashboardSnapshot.invoke(
            mode: mode,
            filters: dashboardFilters
        )
        dashboardSnapshot = snapshot
    }

    func refreshDashboard(mode: DashboardMode) async {
        do {
            try await loadDashboard(mode: mode)
        } catch {
            status = "Error dashboard operativo: \(error.localizedDescription)"
        }
    }

    func preloadClassWorkspace(classId: Int64) async {
        do {
            _ = try await container.preloadClassWorkspace.invoke(classId: classId)
        } catch {
            status = "Error precargando clase: \(error.localizedDescription)"
        }
    }

    func updateDashboardFilters(
        classId: Int64?,
        severity: String?,
        priority: String?,
        sessionStatus: String?
    ) {
        dashboardFilters = DashboardFilters(
            classId: kotlinLong(classId),
            severity: severity?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            priority: priority?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            sessionStatus: sessionStatus?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
    }

    func performQuickAction(
        type: QuickActionType,
        mode: DashboardMode,
        classId: Int64,
        studentId: Int64? = nil,
        evaluationId: Int64? = nil,
        note: String? = nil,
        attendanceStatus: String? = nil,
        score: Double? = nil
    ) async {
        do {
            let result = try await container.dashboardOperationalRepository.executeQuickAction(
                command: QuickActionCommand(
                    type: type,
                    classId: classId,
                    studentId: kotlinLong(studentId),
                    evaluationId: kotlinLong(evaluationId),
                    note: note,
                    attendanceStatus: attendanceStatus,
                    score: score.map { KotlinDouble(value: $0) }
                )
            )
            status = result.message
            try await loadDashboard(mode: mode)
            try await refreshDashboard()
        } catch {
            status = "Quick action error: \(error.localizedDescription)"
        }
    }

    func firstQuickEvaluationTarget(classId: Int64) async -> (studentId: Int64?, evaluationId: Int64?) {
        do {
            let students = try await container.classesRepository.listStudentsInClass(classId: classId)
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
            return (students.first?.id, evaluations.first?.id)
        } catch {
            return (nil, nil)
        }
    }

    func classroomCaptureContext(classId: Int64, on date: Date) async throws -> ClassroomCaptureContextSnapshot? {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            return nil
        }

        let sessions = try await container.plannerRepository.listAllSessions()
            .filter { $0.groupId == classId && Calendar.current.isDate(self.date(from: $0), inSameDayAs: date) }
            .sorted {
                if $0.period == $1.period {
                    return ($0.startTime ?? "") < ($1.startTime ?? "")
                }
                return $0.period < $1.period
            }

        let session = sessions.first
        let sessionTitle = session.map { session in
            let unit = session.teachingUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !unit.isEmpty { return unit }
            let activities = session.activities.trimmingCharacters(in: .whitespacesAndNewlines)
            return activities.isEmpty ? "Sesión de hoy" : activities
        } ?? ""

        return ClassroomCaptureContextSnapshot(
            classId: classId,
            className: schoolClass.name,
            sessionId: session?.id,
            sessionTitle: sessionTitle
        )
    }

    func refreshClasses() async throws {
        try await refreshAcademicYears()
        let classes = try await container.classesRepository.listClasses()
        self.classes = classes
        // If notebook has no class selected, pick the first one
        if notebookViewModel.currentClassId == nil, let first = classes.first {
            selectClass(id: first.id)
        }
    }

    private func academicYearSnapshot(from year: AcademicYear) async throws -> AcademicYearSnapshot {
        let classCount = try await container.classesRepository.listClassesForAcademicYear(academicYearId: year.id).count
        let enrollmentCount = try await container.academicYearsRepository.enrollmentCount(academicYearId: year.id)
        return AcademicYearSnapshot(
            id: year.id,
            name: year.name,
            startDate: Date(timeIntervalSince1970: TimeInterval(year.startAt.toEpochMilliseconds()) / 1000),
            endDate: Date(timeIntervalSince1970: TimeInterval(year.endAt.toEpochMilliseconds()) / 1000),
            status: year.status.name,
            isActive: year.isActive,
            archivedAt: year.archivedAt.map { Date(timeIntervalSince1970: TimeInterval($0.toEpochMilliseconds()) / 1000) },
            classCount: classCount,
            enrollmentCount: enrollmentCount.int64Value
        )
    }

    func refreshAcademicYears() async throws {
        let years = try await container.academicYearsRepository.listAcademicYears()
        var snapshots: [AcademicYearSnapshot] = []
        for year in years {
            snapshots.append(try await academicYearSnapshot(from: year))
        }
        self.academicYears = snapshots
        self.activeAcademicYear = snapshots.first(where: \.isActive)
        self.archivedAcademicYears = snapshots.filter { !$0.isActive }
    }

    func refreshSubjects() async throws {
        subjects = try await container.subjectsRepository.listSubjects()
    }

    func ensureClassesLoaded() async {
        try? await refreshAcademicYears()
        if classes.isEmpty {
            try? await refreshClasses()
        }
        if subjects.isEmpty {
            try? await refreshSubjects()
        }
    }

    func refreshStudentsDirectory() async throws {
        if classes.isEmpty {
            try await refreshClasses()
        }
        let currentClasses = self.classes
        let currentSelectedClassId = selectedStudentsClassId

        let all = try await container.studentsRepository.listStudents()
        let resolvedClassId = currentSelectedClassId ?? currentClasses.first?.id
        
        let inClass: [Student]
        if let classId = resolvedClassId {
            inClass = try await container.classesRepository.listStudentsInClass(classId: classId)
        } else {
            inClass = []
        }

        self.allStudents = all
        if selectedStudentsClassId == nil {
            selectedStudentsClassId = resolvedClassId
        }
        self.studentsInClass = inClass
    }

    func selectStudentsClass(classId: Int64?) async {
        selectedStudentsClassId = classId
        do {
            if let classId {
                studentsInClass = try await container.classesRepository.listStudentsInClass(classId: classId)
            } else {
                studentsInClass = []
            }
        } catch {
            status = "Error cargando alumnos: \(error.localizedDescription)"
        }
    }

    func students(forClassId classId: Int64) async throws -> [Student] {
        try await container.classesRepository.listStudentsInClass(classId: classId)
    }

    func createAcademicYear(
        name: String,
        startDate: Date,
        endDate: Date,
        copyGroupsFrom sourceAcademicYearId: Int64?,
        promoteStudents: Bool
    ) async throws -> Int64 {
        let sourceClasses: [SchoolClass]
        if let sourceAcademicYearId {
            sourceClasses = try await container.classesRepository.listClassesForAcademicYear(academicYearId: sourceAcademicYearId)
        } else {
            sourceClasses = []
        }

        let targetYearId = try await container.academicYearsRepository.createAcademicYear(
            name: name,
            startEpochMs: Int64(startDate.timeIntervalSince1970 * 1000),
            endEpochMs: Int64(endDate.timeIntervalSince1970 * 1000),
            centerId: nil,
            makeActive: true
        ).int64Value

        var classMapping: [Int64: Int64] = [:]
        for sourceClass in sourceClasses {
            let targetClassId = try await container.classesRepository.saveClass(
                id: nil,
                name: sourceClass.name,
                course: sourceClass.course,
                description: sourceClass.description_,
                centerId: sourceClass.centerId,
                academicYearId: KotlinLong(value: targetYearId),
                stageCycleId: sourceClass.stageCycleId,
                subjectId: sourceClass.subjectId,
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            classMapping[sourceClass.id] = targetClassId
        }

        if promoteStudents {
            var targetClasses = try await container.classesRepository.listClassesForAcademicYear(academicYearId: targetYearId)
            
            for sourceClass in sourceClasses {
                let students = try await container.classesRepository.listStudentsInClass(classId: sourceClass.id)
                guard !students.isEmpty else { continue }
                guard let targetPlan = promotedStudentTargetClass(from: sourceClass) else { continue }
                let targetClass = try await ensurePromotionTargetClass(
                    targetPlan,
                    sourceClass: sourceClass,
                    targetYearId: targetYearId,
                    targetClasses: &targetClasses
                )
                for student in students {
                    try await container.classesRepository.promoteStudentToClass(
                        sourceClassId: sourceClass.id,
                        targetClassId: targetClass.id,
                        studentId: student.id,
                        promotionStatus: PromotionStatus.promoted.name
                    )
                }
            }
        }

        try await refreshAcademicYears()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        try await enqueueAcademicYearSnapshots()
        enqueueClassSnapshots()
        try await enqueueRosterSnapshotsForClasses(classes)
        selectedStudentsClassId = classes.first?.id
        status = promoteStudents ? "Curso escolar creado con alumnado promocionado." : "Curso escolar creado."
        return targetYearId
    }

    func setActiveAcademicYear(id: Int64) async throws {
        try await container.academicYearsRepository.setActiveAcademicYear(academicYearId: id)
        selectedStudentsClassId = nil
        try await refreshAcademicYears()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        try await enqueueAcademicYearSnapshots()
        status = "Curso escolar activo actualizado."
    }

    func archiveAcademicYear(id: Int64) async throws {
        guard activeAcademicYear?.id != id else {
            status = "Activa otro curso escolar antes de archivar el curso actual."
            return
        }
        try await container.academicYearsRepository.archiveAcademicYear(academicYearId: id)
        try await refreshAcademicYears()
        try await refreshClasses()
        try await enqueueAcademicYearSnapshots()
        status = "Curso escolar archivado."
    }

    func deleteArchivedAcademicYear(id: Int64) async throws {
        guard activeAcademicYear?.id != id else {
            status = "No se puede eliminar el curso escolar activo."
            return
        }
        try await container.academicYearsRepository.deleteArchivedAcademicYear(academicYearId: id)
        try await refreshAcademicYears()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        enqueueLocalChange(
            entity: "academic_year",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        status = "Curso escolar archivado eliminado."
    }

    private func enqueueAcademicYearSnapshots() async throws {
        let years = try await container.academicYearsRepository.listAcademicYears()
        for year in years {
            enqueueLocalChange(
                entity: "academic_year",
                id: "\(year.id)",
                updatedAtEpochMs: year.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": year.id,
                    "centerId": year.centerId,
                    "name": year.name,
                    "startEpochMs": year.startAt.toEpochMilliseconds(),
                    "endEpochMs": year.endAt.toEpochMilliseconds(),
                    "status": year.status.name,
                    "isActive": year.isActive,
                    "archivedAtEpochMs": year.archivedAt?.toEpochMilliseconds() ?? 0
                ]
            )
        }
    }

    private func enqueueClassSnapshots() {
        for schoolClass in classes {
            enqueueLocalChange(
                entity: "class",
                id: "\(schoolClass.id)",
                updatedAtEpochMs: schoolClass.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": schoolClass.id,
                    "name": schoolClass.name,
                    "course": Int(schoolClass.course),
                    "description": schoolClass.description_ ?? NSNull(),
                    "centerId": schoolClass.centerId?.int64Value ?? 0,
                    "academicYearId": schoolClass.academicYearId?.int64Value ?? 0,
                    "stageCycleId": schoolClass.stageCycleId?.int64Value ?? 0,
                    "subjectId": schoolClass.subjectId?.int64Value ?? 0
                ]
            )
        }
    }

    private func enqueueRosterSnapshotsForClasses(_ schoolClasses: [SchoolClass]) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for schoolClass in schoolClasses {
            let studentIds = try await container.classesRepository
                .listStudentsInClass(classId: schoolClass.id)
                .map { $0.id }
                .sorted()
            enqueueLocalChange(
                entity: "class_roster",
                id: "\(schoolClass.id)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "classId": schoolClass.id,
                    "studentIds": studentIds
                ]
            )
        }
    }

    func archivedAcademicYearExportText(id: Int64) async throws -> String {
        let years = try await container.academicYearsRepository.listAcademicYears()
        guard let year = years.first(where: { $0.id == id }) else {
            throw NSError(domain: "KmpBridge", code: -90, userInfo: [NSLocalizedDescriptionKey: "Curso escolar no encontrado."])
        }

        let classes = try await container.classesRepository.listClassesForAcademicYear(academicYearId: id)
        var lines: [String] = [
            "Curso escolar: \(year.name)",
            "Estado: \(year.status.name)",
            "Inicio: \(Date(timeIntervalSince1970: TimeInterval(year.startAt.toEpochMilliseconds()) / 1000).formatted(.dateTime.day().month().year()))",
            "Fin: \(Date(timeIntervalSince1970: TimeInterval(year.endAt.toEpochMilliseconds()) / 1000).formatted(.dateTime.day().month().year()))",
            "Grupos: \(classes.count)",
            ""
        ]

        for schoolClass in classes {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            let grades = try await container.gradesRepository.listGradesForClass(classId: schoolClass.id)
            let notebookCells = try await container.notebookCellsRepository.listClassCells(classId: schoolClass.id)
            let attendance = try await container.attendanceRepository.listAttendance(classId: schoolClass.id)
            let incidents = try await container.incidentsRepository.listIncidents(classId: schoolClass.id)
            let physicalAssignments = try await container.physicalTestsRepository.listAssignmentsForClass(classId: schoolClass.id)
            var physicalResultsCount = 0
            for assignment in physicalAssignments {
                physicalResultsCount += try await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignment.id).count
            }
            let subject = schoolClass.subjectId.flatMap { subjectId in
                subjects.first(where: { $0.id == subjectId.int64Value })?.name
            } ?? "Sin asignatura"
            lines.append("## \(schoolClass.name) · Curso \(schoolClass.course) · \(subject)")
            lines.append("Matriculas: \(roster.count)")
            lines.append("Evaluaciones: \(evaluations.count)")
            lines.append("Calificaciones: \(grades.count)")
            lines.append("Celdas de cuaderno: \(notebookCells.count)")
            lines.append("Registros de asistencia: \(attendance.count)")
            lines.append("Incidencias: \(incidents.count)")
            lines.append("Pruebas fisicas: \(physicalAssignments.count) asignaciones · \(physicalResultsCount) resultados")
            if roster.isEmpty {
                lines.append("- Sin alumnado matriculado")
            } else {
                for student in roster.sorted(by: { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }) {
                    lines.append("- \(student.fullName)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private struct PromotionTargetClassPlan {
        let name: String
        let course: Int32
    }

    private func ensurePromotionTargetClass(
        _ plan: PromotionTargetClassPlan,
        sourceClass: SchoolClass,
        targetYearId: Int64,
        targetClasses: inout [SchoolClass]
    ) async throws -> SchoolClass {
        if let existing = targetClasses.first(where: { promotionClassNamesEquivalent($0.name, plan.name) }) {
            return existing
        }
        let targetClassId = try await container.classesRepository.saveClass(
            id: nil,
            name: plan.name,
            course: plan.course,
            description: sourceClass.description_,
            centerId: sourceClass.centerId,
            academicYearId: KotlinLong(value: targetYearId),
            stageCycleId: sourceClass.stageCycleId,
            subjectId: sourceClass.subjectId,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        let refreshed = try await container.classesRepository.listClassesForAcademicYear(academicYearId: targetYearId)
        targetClasses = refreshed
        guard let created = refreshed.first(where: { $0.id == targetClassId }) else {
            throw NSError(
                domain: "KmpBridge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el grupo destino de promoción."]
            )
        }
        return created
    }

    private func promotedStudentTargetClass(from sourceClass: SchoolClass) -> PromotionTargetClassPlan? {
        let sourceName = sourceClass.name
        let levelsMap: [(course: Int, stage: String, target: String?, targetCourse: Int32?)] = [
            (1, "ESO", "2º ESO", 2),
            (2, "ESO", "3º ESO", 3),
            (3, "ESO", "4º ESO", 4),
            (4, "ESO", "1º BAC", 1),
            (1, "BAC", nil, nil),
            (2, "BAC", nil, nil),
        ]
        for level in levelsMap {
            if let suffix = promotionSuffix(from: sourceName, course: level.course, stage: level.stage) {
                guard let target = level.target, let course = level.targetCourse else { return nil }
                return PromotionTargetClassPlan(name: target + suffix, course: course)
            }
        }
        return nil
    }

    private func promotionSuffix(from sourceName: String, course: Int, stage: String) -> String? {
        let stagePattern = stage == "BAC" ? "(?:BAC|BACH|BACHILLERATO)" : stage
        let pattern = #"^\s*\#(course)\s*(?:º|°)?\s*\#(stagePattern)\b\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let fullRange = NSRange(sourceName.startIndex..<sourceName.endIndex, in: sourceName)
        guard let match = regex.firstMatch(in: sourceName, range: fullRange),
              match.range.location == 0,
              let suffixStart = Range(match.range, in: sourceName)?.upperBound else {
            return nil
        }
        let rawSuffix = String(sourceName[suffixStart...])
        return normalizedPromotionSuffix(rawSuffix)
    }

    private func normalizedPromotionSuffix(_ suffix: String) -> String {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let letter = singleGroupLetter(in: trimmed) {
            return " \(letter)"
        }
        return trimmed.hasPrefix("-") ? " \(trimmed)" : " \(trimmed)"
    }

    private func singleGroupLetter(in suffix: String) -> String? {
        let pattern = #"^(?:[\(\[]\s*)?([A-Za-z])(?:\s*[\)\]])?$|^[-–—]\s*([A-Za-z])$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)
        guard let match = regex.firstMatch(in: suffix, range: range) else { return nil }
        for index in 1..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: suffix) {
                return String(suffix[swiftRange]).uppercased()
            }
        }
        return nil
    }

    private func promotionClassNamesEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        normalizedPromotionClassName(lhs) == normalizedPromotionClassName(rhs)
    }

    private func normalizedPromotionClassName(_ name: String) -> String {
        var normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .replacingOccurrences(of: "BACHILLERATO", with: "BAC")
            .replacingOccurrences(of: "BACH", with: "BAC")
            .replacingOccurrences(of: "º", with: "")
            .replacingOccurrences(of: "°", with: "")
        normalized = normalized.replacingOccurrences(
            of: #"[\(\)\[\]\-–—_/\\.]+"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    func previewStudentImport(tsv: String) async throws -> AppleStudentImportPreview {
        let preview = appleImportFacade.previewStudentsFromTsv(text: tsv)
        let existingStudents = try await container.studentsRepository.listStudents()
        let existingByFullName = Dictionary(
            existingStudents.map { (normalizedStudentName(firstName: $0.firstName, lastName: $0.lastName), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingLastNames = Set(existingStudents.map { normalizedNamePart($0.lastName) }.filter { !$0.isEmpty })
        let students = preview.students.map { student in
            let normalizedFullName = normalizedStudentName(firstName: student.firstName, lastName: student.lastName)
            let normalizedLastName = normalizedNamePart(student.lastName)
            let duplicateStatus: AppleStudentDuplicateStatus
            let duplicateDetail: String?
            let existingStudentId: Int64?
            if let existingStudent = existingByFullName[normalizedFullName] {
                duplicateStatus = .alreadyExists
                duplicateDetail = existingStudent.fullName
                existingStudentId = existingStudent.id
            } else if !normalizedLastName.isEmpty && existingLastNames.contains(normalizedLastName) {
                duplicateStatus = .possibleDuplicate
                duplicateDetail = "Coinciden apellidos"
                existingStudentId = nil
            } else {
                duplicateStatus = .new
                duplicateDetail = nil
                existingStudentId = nil
            }
            return AppleParsedStudent(
                id: Int(student.rowNumber),
                rowNumber: Int(student.rowNumber),
                fullName: student.fullName,
                firstName: student.firstName,
                lastName: student.lastName,
                duplicateStatus: duplicateStatus,
                duplicateDetail: duplicateDetail,
                existingStudentId: existingStudentId
            )
        }

        guard !students.isEmpty else {
            throw NSError(domain: "KmpBridge", code: -60, userInfo: [NSLocalizedDescriptionKey: "No se encontraron alumnos en el archivo."])
        }

        let applePreview = AppleStudentImportPreview(
            className: preview.className,
            course: preview.course,
            students: students
        )
        studentImportPreview = applePreview
        return applePreview
    }

    func confirmStudentImport(selectedRows: [Int], targetClassId: Int64?, omitDuplicates: Bool = true) async throws {
        guard let preview = studentImportPreview else {
            throw NSError(domain: "KmpBridge", code: -61, userInfo: [NSLocalizedDescriptionKey: "No hay una previsualización de importación activa."])
        }

        let selectedRowSet = Set(selectedRows)
        let studentsToProcess = preview.students.filter { student in
            selectedRowSet.contains(student.rowNumber) && (!omitDuplicates || student.duplicateStatus == .new)
        }
        guard !studentsToProcess.isEmpty else {
            throw NSError(domain: "KmpBridge", code: -62, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un alumno para importar."])
        }

        isImportingStudents = true
        defer { isImportingStudents = false }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var studentIdsToEnroll: [Int64] = []

        for student in studentsToProcess {
            if let existingId = student.existingStudentId {
                // Alumno ya existente en la base de datos: no lo duplicamos, usamos su id existente
                studentIdsToEnroll.append(existingId)
            } else {
                let studentId = try await container.studentsRepository.saveStudent(
                    id: nil,
                    firstName: student.firstName,
                    lastName: student.lastName,
                    email: nil,
                    photoPath: nil,
                    isInjured: false,
                    sex: .unspecified,
                    sexSource: .imported,
                    birthDate: nil,
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: 1
                ).int64Value
                studentIdsToEnroll.append(studentId)

                enqueueLocalChange(
                    entity: "student",
                    id: "\(studentId)",
                    updatedAtEpochMs: nowMs,
                    payload: [
                        "id": studentId,
                        "firstName": student.firstName,
                        "lastName": student.lastName,
                        "email": NSNull(),
                        "photoPath": NSNull(),
                        "isInjured": false,
                        "sex": StudentSex.unspecified.name,
                        "sexSource": StudentSexSource.imported.name,
                        "birthDate": NSNull()
                    ]
                )
            }
        }

        if let targetClassId {
            for studentId in studentIdsToEnroll {
                try await container.classesRepository.addStudentToClass(classId: targetClassId, studentId: studentId)
            }
            enqueueRosterSnapshot(forClassId: targetClassId, updatedAtEpochMs: nowMs)
            selectedStudentsClassId = targetClassId
            await selectStudentsClass(classId: targetClassId)
        }

        studentImportPreview = nil
        try await refreshStudentsDirectory()
        try await refreshDashboard()
    }

    private func normalizedStudentName(firstName: String, lastName: String) -> String {
        normalizedNamePart([firstName, lastName].joined(separator: " "))
    }

    private func normalizedNamePart(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }


    func createClass(name: String, course: Int32, subjectId: Int64? = nil) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let classId = try await container.saveClass.invoke(
            id: nil,
            name: name,
            course: course,
            description: nil,
            centerId: nil,
            academicYearId: kotlinLong(activeAcademicYear?.id),
            stageCycleId: nil,
            subjectId: kotlinLong(subjectId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await refreshClasses()
        selectedStudentsClassId = classId.int64Value
        try await refreshStudentsDirectory()
        enqueueLocalChange(
            entity: "class",
            id: "\(classId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": classId.int64Value,
                "name": name,
                "course": Int(course),
                "description": NSNull(),
                "centerId": NSNull(),
                "academicYearId": activeAcademicYear?.id ?? 0,
                "stageCycleId": NSNull(),
                "subjectId": subjectId.map { NSNumber(value: $0) } ?? NSNull()
            ]
        )
        return classId.int64Value
    }

    func updateClass(
        id: Int64,
        name: String,
        course: Int32,
        description: String?,
        centerId: Int64?,
        academicYearId: Int64?,
        stageCycleId: Int64?,
        subjectId: Int64?
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveClass.invoke(
            id: kotlinLong(id),
            name: name,
            course: course,
            description: description,
            centerId: kotlinLong(centerId),
            academicYearId: kotlinLong(academicYearId),
            stageCycleId: kotlinLong(stageCycleId),
            subjectId: kotlinLong(subjectId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await refreshClasses()
        if selectedStudentsClassId == id {
            try await refreshStudentsDirectory()
        }
        enqueueLocalChange(
            entity: "class",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "name": name,
                "course": Int(course),
                "description": description ?? NSNull(),
                "centerId": centerId.map { NSNumber(value: $0) } ?? NSNull(),
                "academicYearId": academicYearId.map { NSNumber(value: $0) } ?? NSNull(),
                "stageCycleId": stageCycleId.map { NSNumber(value: $0) } ?? NSNull(),
                "subjectId": subjectId.map { NSNumber(value: $0) } ?? NSNull()
            ]
        )
    }

    func deleteClass(id: Int64) async throws {
        try await container.classesRepository.deleteClass(classId: id)
        try await refreshClasses()
        if selectedStudentsClassId == id {
            selectedStudentsClassId = classes.first?.id
            try await refreshStudentsDirectory()
        }
        enqueueLocalChange(
            entity: "class",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": id
            ],
            op: "delete"
        )
    }

    func saveSubject(id: Int64? = nil, code: String, name: String, stageCycleId: Int64? = nil) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let subjectId = try await container.saveSubject.invoke(
            id: kotlinLong(id),
            code: code,
            name: name,
            stageCycleId: kotlinLong(stageCycleId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await refreshSubjects()
        enqueueLocalChange(
            entity: "subject",
            id: "\(subjectId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": subjectId.int64Value,
                "code": code,
                "name": name,
                "stageCycleId": stageCycleId.map { NSNumber(value: $0) } ?? NSNull()
            ]
        )
        return subjectId.int64Value
    }

    func deleteSubject(id: Int64) async throws {
        try await container.subjectsRepository.deleteSubject(subjectId: id)
        try await refreshSubjects()
        try await refreshClasses()
    }

    func createStudentAndAssignToClass(firstName: String, lastName: String, classId: Int64) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sexResolution: (sex: StudentSex, source: StudentSexSource) = (.unspecified, .unknown)
        let studentId = try await container.saveStudent.invoke(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            sex: sexResolution.sex,
            sexSource: sexResolution.source,
            birthDate: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId.int64Value)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(studentId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": studentId.int64Value,
                "firstName": firstName,
                "lastName": lastName,
                "email": NSNull(),
                "photoPath": NSNull(),
                "isInjured": false,
                "sex": sexResolution.sex.name,
                "sexSource": sexResolution.source.name,
                "birthDate": NSNull()
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
    }

    func createStudentInSelectedClass(
        firstName: String,
        lastName: String,
        isInjured: Bool = false,
        sex: StudentSex? = nil,
        sexSource: StudentSexSource? = nil,
        birthDate: LocalDate? = nil
    ) async throws {
        guard let classId = selectedStudentsClassId else {
            throw NSError(domain: "KMP", code: -20, userInfo: [NSLocalizedDescriptionKey: "Selecciona una clase primero"])
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sexResolution = await resolvedStudentSex(firstName: firstName, lastName: lastName, sex: sex, sexSource: sexSource)
        let studentId = try await container.studentsRepository.saveStudent(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            isInjured: isInjured,
            sex: sexResolution.sex,
            sexSource: sexResolution.source,
            birthDate: birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let newStudentId = studentId.int64Value
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: newStudentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(newStudentId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": newStudentId,
                "firstName": firstName,
                "lastName": lastName,
                "email": NSNull(),
                "photoPath": NSNull(),
                "isInjured": isInjured,
                "sex": sexResolution.sex.name,
                "sexSource": sexResolution.source.name,
                "birthDate": birthDate == nil ? NSNull() : birthDate!.description()
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
    }

    func createMacStudent(
        firstName: String,
        lastName: String,
        email: String?,
        isInjured: Bool,
        classId: Int64
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sexResolution = await resolvedStudentSex(firstName: firstName, lastName: lastName, sex: nil, sexSource: nil)
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let studentId = try await container.studentsRepository.saveStudent(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: normalizedEmail,
            photoPath: nil,
            isInjured: isInjured,
            sex: sexResolution.sex,
            sexSource: sexResolution.source,
            birthDate: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(studentId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": studentId,
                "firstName": firstName,
                "lastName": lastName,
                "email": normalizedEmail ?? NSNull(),
                "photoPath": NSNull(),
                "isInjured": isInjured,
                "sex": sexResolution.sex.name,
                "sexSource": sexResolution.source.name,
                "birthDate": NSNull()
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
        return studentId
    }

    func updateMacStudent(
        student: Student,
        firstName: String,
        lastName: String,
        email: String?,
        isInjured: Bool
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: firstName,
            lastName: lastName,
            email: normalizedEmail,
            photoPath: student.photoPath,
            isInjured: isInjured,
            sex: student.sex,
            sexSource: student.sexSource,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": firstName,
                "lastName": lastName,
                "email": normalizedEmail ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": isInjured,
                "sex": student.sex.name,
                "sexSource": student.sexSource.name,
                "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
            ]
        )
    }

    func updateStudentFull(
        student: Student,
        firstName: String,
        lastName: String,
        email: String?,
        isInjured: Bool,
        sex: StudentSex,
        birthDate: LocalDate?
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let sexSource: StudentSexSource = (sex == student.sex)
            ? student.sexSource
            : (sex == .unspecified ? StudentSexSource.unknown : StudentSexSource.manual)

        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: firstName,
            lastName: lastName,
            email: normalizedEmail,
            photoPath: student.photoPath,
            isInjured: isInjured,
            sex: sex,
            sexSource: sexSource,
            birthDate: birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": firstName,
                "lastName": lastName,
                "email": normalizedEmail ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": isInjured,
                "sex": sex.name,
                "sexSource": sexSource.name,
                "birthDate": birthDate == nil ? NSNull() : birthDate!.description()
            ]
        )
    }

    func updateStudentInjuryStatus(
        studentId: Int64,
        isInjured: Bool,
        classId: Int64?
    ) async throws {
        guard let student = try await container.studentsRepository.listStudents().first(where: { $0.id == studentId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró el alumno \(studentId)."])
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: student.firstName,
            lastName: student.lastName,
            email: student.email,
            photoPath: student.photoPath,
            isInjured: isInjured,
            sex: student.sex,
            sexSource: student.sexSource,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": student.firstName,
                "lastName": student.lastName,
                "email": student.email ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": isInjured,
                "sex": student.sex.name,
                "sexSource": student.sexSource.name,
                "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
            ]
        )

        if let classId {
            enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
        }
    }

    private func resolvedStudentSex(
        firstName: String,
        lastName: String,
        sex: StudentSex?,
        sexSource: StudentSexSource?
    ) async -> (sex: StudentSex, source: StudentSexSource) {
        if let sex, sex != .unspecified {
            return (sex, sexSource ?? .manual)
        }
        return (.unspecified, .unknown)
    }

    func updateStudentSex(_ student: Student, sex: StudentSex) async throws {
        try await updateStudentSex(
            student,
            sex: sex,
            source: sex == .unspecified ? .unknown : .manual
        )
    }

    /// Persists a sex value while keeping its provenance explicit for sync and audit.
    /// Name-based inference is deliberately guarded here as well as in the UI, so a
    /// stale suggestion cannot overwrite a value that has since been entered/imported.
    func updateStudentSex(
        _ student: Student,
        sex: StudentSex,
        source: StudentSexSource
    ) async throws {
        try await persistStudentSex(student, sex: sex, source: source, refreshDirectory: true)
    }

    func applyStudentSexInference(_ assignments: [StudentSexInferenceAssignment]) async throws {
        var appliedCount = 0
        for assignment in assignments {
            guard assignment.sex != .unspecified else { continue }
            guard let current = try await container.studentsRepository.getStudent(studentId: assignment.student.id),
                  current.sex == .unspecified,
                  current.sexSource == .unknown else { continue }

            try await persistStudentSex(
                current,
                sex: assignment.sex,
                source: .nameInferred,
                refreshDirectory: false
            )
            appliedCount += 1
        }

        if appliedCount > 0 {
            try await refreshStudentsDirectory()
            try await refreshDashboard()
        }
    }

    private func persistStudentSex(
        _ student: Student,
        sex: StudentSex,
        source: StudentSexSource,
        refreshDirectory: Bool
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let persistedSource = sex == .unspecified ? StudentSexSource.unknown : source
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: student.firstName,
            lastName: student.lastName,
            email: student.email,
            photoPath: student.photoPath,
            isInjured: student.isInjured,
            sex: sex,
            sexSource: persistedSource,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        if refreshDirectory {
            try await refreshStudentsDirectory()
            try await refreshDashboard()
        }
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": student.firstName,
                "lastName": student.lastName,
                "email": student.email ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": student.isInjured,
                "sex": sex.name,
                "sexSource": persistedSource.name,
                "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
            ]
        )
    }

    func evaluations(for classId: Int64) async throws -> [Evaluation] {
        try await container.evaluationsRepository.listClassEvaluations(classId: classId)
    }

    func incidents(for classId: Int64) async throws -> [Incident] {
        try await container.incidentsRepository.listIncidents(classId: classId)
            .sorted { lhs, rhs in
                lhs.date.epochSeconds > rhs.date.epochSeconds
            }
    }

    func attendanceRecords(for classId: Int64, on date: Date) async throws -> [AttendanceRecordSnapshot] {
        let rows = try await container.attendanceRepository.listAttendanceByDate(
            classId: classId,
            dateEpochMs: startOfDayEpochMs(for: date)
        )
        return rows.map(attendanceSnapshot(from:))
    }

    func attendanceHistory(for classId: Int64, days: Int = 14) async throws -> [AttendanceRecordSnapshot] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let rows = try await container.attendanceRepository.getAttendanceForClassBetweenDates(
            classId: classId,
            startDateMs: startOfDayEpochMs(for: start),
            endDateMs: startOfDayEpochMs(for: end)
        )
        return rows.map(attendanceSnapshot(from:))
    }

    func attendanceHistory(for classId: Int64, from startDate: Date, to endDate: Date) async throws -> [AttendanceRecordSnapshot] {
        let rows = try await container.attendanceRepository.getAttendanceForClassBetweenDates(
            classId: classId,
            startDateMs: startOfDayEpochMs(for: startDate),
            endDateMs: startOfDayEpochMs(for: endDate)
        )
        return rows.map(attendanceSnapshot(from:))
    }

    func attendanceOverview(for classIds: [Int64], from startDate: Date, to endDate: Date) async throws -> [AttendanceClassOverview] {
        var overviews: [AttendanceClassOverview] = []
        let todayEpochMs = startOfDayEpochMs(for: Date())
        for classId in classIds {
            guard let schoolClass = classes.first(where: { $0.id == classId }) else { continue }
            let students = try await container.classesRepository.listStudentsInClass(classId: classId)
            let history = try await container.attendanceRepository.getAttendanceForClassBetweenDates(
                classId: classId,
                startDateMs: startOfDayEpochMs(for: startDate),
                endDateMs: startOfDayEpochMs(for: endDate)
            )
            let todayRecords = try await container.attendanceRepository.listAttendanceByDate(
                classId: classId,
                dateEpochMs: todayEpochMs
            )
            let present = history.filter { $0.status.uppercased().contains("PRESENT") }.count
            let absent = history.filter { $0.status.uppercased().contains("AUS") }.count
            let late = history.filter {
                let status = $0.status.uppercased()
                return status.contains("TARD") || status.contains("RETR")
            }.count
            let attendanceRate = history.isEmpty ? 0 : Int((Double(present) / Double(history.count)) * 100.0)
            overviews.append(
                AttendanceClassOverview(
                    id: classId,
                    schoolClass: schoolClass,
                    studentCount: students.count,
                    presentCount: present,
                    absentCount: absent,
                    lateCount: late,
                    pendingTodayCount: max(students.count - todayRecords.count, 0),
                    attendanceRate: attendanceRate
                )
            )
        }
        return overviews.sorted { $0.schoolClass.name.localizedCaseInsensitiveCompare($1.schoolClass.name) == .orderedAscending }
    }

    func attendanceSessions(for classId: Int64, on date: Date) async throws -> [AttendanceSessionSnapshot] {
        let calendar = Calendar(identifier: .iso8601)
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
        let weekday = isoWeekday(from: date)
        let sessions = try await plannerListSessions(weekNumber: weekOfYear, year: yearForWeek, classId: classId)
            .filter { Int($0.dayOfWeek) == weekday }
            .sorted { $0.period < $1.period }
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(
            summaries.map { ($0.planningSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions.map { session in
            AttendanceSessionSnapshot(
                id: session.id,
                session: session,
                journalSummary: summariesById[session.id]
            )
        }
    }

    func diarySessions(weekNumber: Int, year: Int, classId: Int64?) async throws -> [DiarySessionSnapshot] {
        let sessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(
            summaries.map { ($0.planningSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions
            .sorted {
                if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                return $0.dayOfWeek < $1.dayOfWeek
            }
            .map { session in
                DiarySessionSnapshot(
                    id: session.id,
                    session: session,
                    journalSummary: summariesById[session.id]
                )
            }
    }

    /// `note`/`hasIncident`/`followUpRequired` son `nil` por defecto (no `""`/`false`)
    /// a proposito: la mayoria de llamadas solo cambian el `status` (toque rapido
    /// de asistencia) y no deben borrar una observacion o incidencia ya guardada
    /// ese dia. `nil` conserva el valor existente; un valor explicito lo sustituye.
    func saveAttendance(
        studentId: Int64,
        classId: Int64,
        on date: Date,
        status: String,
        note: String? = nil,
        hasIncident: Bool? = nil,
        followUpRequired: Bool? = nil,
        sessionId: Int64? = nil
    ) async throws {
        let dateEpochMs = startOfDayEpochMs(for: date)
        let existingRecords = try await container.attendanceRepository.listAttendanceByDate(classId: classId, dateEpochMs: dateEpochMs)
        let linkedSessionId = sessionId
        let existing = existingRecords.first { record in
            record.studentId == studentId && record.sessionId?.int64Value == linkedSessionId
        } ?? existingRecords.first { record in
            record.studentId == studentId
        }
        let resolvedNote = note ?? existing?.note ?? ""
        let resolvedHasIncident = hasIncident ?? existing?.hasIncident ?? false
        let resolvedFollowUpRequired = followUpRequired ?? existing?.followUpRequired ?? resolvedHasIncident
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.attendanceRepository.saveAttendance(
            id: kotlinLong(existing?.id),
            studentId: studentId,
            classId: classId,
            dateEpochMs: dateEpochMs,
            status: status,
            note: resolvedNote,
            hasIncident: resolvedHasIncident,
            followUpRequired: resolvedFollowUpRequired,
            sessionId: kotlinLong(linkedSessionId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "attendance",
            id: "\(classId)-\(studentId)-\(dateEpochMs)",
            updatedAtEpochMs: nowMs,
            payload: [
                "studentId": studentId,
                "classId": classId,
                "dateEpochMs": dateEpochMs,
                "status": status,
                "note": resolvedNote,
                "hasIncident": resolvedHasIncident,
                "followUpRequired": resolvedFollowUpRequired,
                "sessionId": linkedSessionId ?? NSNull()
            ]
        )
    }

    /// Medidas de respuesta educativa Nivel III/IV (Decreto 104/2018 + Orden 20/2019, CV).
    /// El docente de aula consulta e implementa; nunca redacta aquí el informe
    /// sociopsicopedagógico ni el PAP, solo referencia el documento oficial.
    func supportMeasures(for studentId: Int64) async throws -> [SupportMeasureSnapshot] {
        let rows = try await container.studentSupportMeasureRepository.listByStudent(studentId: studentId)
        return rows.compactMap(supportMeasureSnapshot(from:))
    }

    func activeSupportMeasureStudentIds() async throws -> Set<Int64> {
        let ids = try await container.studentSupportMeasureRepository.listActiveStudentIds()
        return Set(ids.map { $0.int64Value })
    }

    @discardableResult
    func saveSupportMeasure(id: Int64? = nil, draft: SupportMeasureDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.studentSupportMeasureRepository.save(
            id: kotlinLong(id),
            studentId: draft.studentId,
            level: kotlinSupportMeasureLevel(draft.level),
            measureType: kotlinSupportMeasureType(draft.measureType),
            startDateIso: draft.startDateIso,
            endDateIso: nil,
            responsible: draft.responsible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.responsible,
            intensity: draft.intensity.map(kotlinSupportMeasureIntensity(_:)),
            followUpNotes: draft.followUpNotes,
            documentRef: draft.documentRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.documentRef,
            reviewDueIso: draft.reviewDueIso,
            isActive: true,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "student_support_measures",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "studentId": draft.studentId,
                "level": draft.level.rawValue,
                "measureType": draft.measureType.rawValue,
                "startDateIso": draft.startDateIso,
                "responsible": draft.responsible,
                "intensity": draft.intensity?.rawValue ?? NSNull(),
                "followUpNotes": draft.followUpNotes,
                "documentRef": draft.documentRef,
                "reviewDueIso": draft.reviewDueIso ?? NSNull(),
                "isActive": true
            ]
        )
        return savedId
    }

    func retireSupportMeasure(id: Int64, endDateIso: String) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try await container.studentSupportMeasureRepository.retire(
            id: id,
            endDateIso: endDateIso,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId
        )
        enqueueLocalChange(
            entity: "student_support_measures",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "endDateIso": endDateIso,
                "isActive": false
            ]
        )
    }

    func deleteSupportMeasure(id: Int64) async throws {
        try await container.studentSupportMeasureRepository.delete(id: id)
        enqueueLocalChange(
            entity: "student_support_measures",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    func tutoringSessions(for studentId: Int64) async throws -> [TutoringSessionSnapshot] {
        let rows = try await container.studentTutoringSessionRepository.listByStudent(studentId: studentId)
        return rows.compactMap(tutoringSessionSnapshot(from:))
    }

    /// Seguimientos abiertos cuya revisión vence en o antes de `onOrBeforeIso`.
    func pendingTutoringReviews(onOrBefore onOrBeforeIso: String) async throws -> [TutoringSessionSnapshot] {
        let rows = try await container.studentTutoringSessionRepository.listPendingReviews(onOrBeforeIso: onOrBeforeIso)
        return rows.compactMap(tutoringSessionSnapshot(from:))
    }

    @discardableResult
    func saveTutoringSession(id: Int64? = nil, draft: TutoringSessionDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.studentTutoringSessionRepository.save(
            id: kotlinLong(id),
            studentId: draft.studentId,
            dateIso: draft.dateIso,
            channel: kotlinTutoringChannel(draft.channel),
            attendees: draft.attendees,
            topics: draft.topics,
            agreements: draft.agreements,
            reviewDueIso: draft.reviewDueIso,
            isClosed: draft.isClosed,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "student_tutoring_sessions",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "studentId": draft.studentId,
                "dateIso": draft.dateIso,
                "channel": draft.channel.rawValue,
                "attendees": draft.attendees,
                "topics": draft.topics,
                "agreements": draft.agreements,
                "reviewDueIso": draft.reviewDueIso ?? NSNull(),
                "isClosed": draft.isClosed
            ]
        )
        return savedId
    }

    func deleteTutoringSession(id: Int64) async throws {
        try await container.studentTutoringSessionRepository.delete(id: id)
        enqueueLocalChange(
            entity: "student_tutoring_sessions",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    /// `nil` si la fila trae un canal que esta version no conoce. Se descarta en
    /// vez de forzar un valor: mismo criterio que las medidas de apoyo.
    private func tutoringSessionSnapshot(from session: StudentTutoringSession) -> TutoringSessionSnapshot? {
        guard let channel = TutoringChannelUI(rawValue: session.channel.name) else { return nil }
        return TutoringSessionSnapshot(
            id: session.id,
            studentId: session.studentId,
            dateIso: session.date.description(),
            channel: channel,
            attendees: session.attendees,
            topics: session.topics,
            agreements: session.agreements,
            reviewDueIso: session.reviewDue?.description(),
            isClosed: session.isClosed
        )
    }

    private func kotlinTutoringChannel(_ channel: TutoringChannelUI) -> TutoringChannel {
        TutoringChannel.entries.first { $0.name == channel.rawValue } ?? TutoringChannel.entries[0]
    }

    private func supportMeasureSnapshot(from measure: StudentSupportMeasure) -> SupportMeasureSnapshot? {
        guard
            let level = SupportMeasureLevelUI(rawValue: measure.level.name),
            let measureType = SupportMeasureTypeUI(rawValue: measure.measureType.name)
        else { return nil }
        return SupportMeasureSnapshot(
            id: measure.id,
            studentId: measure.studentId,
            level: level,
            measureType: measureType,
            startDateIso: measure.startDate.description(),
            endDateIso: measure.endDate?.description(),
            responsible: measure.responsible,
            intensity: measure.intensity.flatMap { SupportMeasureIntensityUI(rawValue: $0.name) },
            followUpNotes: measure.followUpNotes,
            documentRef: measure.documentRef,
            reviewDueIso: measure.reviewDue?.description(),
            isActive: measure.isActive
        )
    }

    private func kotlinSupportMeasureLevel(_ level: SupportMeasureLevelUI) -> SupportMeasureLevel {
        SupportMeasureLevel.entries.first { $0.name == level.rawValue } ?? SupportMeasureLevel.entries[0]
    }

    private func kotlinSupportMeasureType(_ type: SupportMeasureTypeUI) -> SupportMeasureType {
        SupportMeasureType.entries.first { $0.name == type.rawValue } ?? SupportMeasureType.entries[0]
    }

    private func kotlinSupportMeasureIntensity(_ intensity: SupportMeasureIntensityUI) -> SupportMeasureIntensity {
        SupportMeasureIntensity.entries.first { $0.name == intensity.rawValue } ?? SupportMeasureIntensity.entries[0]
    }

    func saveAttendanceBatch(records drafts: [AttendanceDraft]) async throws {
        guard !drafts.isEmpty else { return }

        var existingByKey: [String: Attendance_] = [:]
        let groupedDrafts = Dictionary(grouping: drafts) { draft in
            "\(draft.classId)-\(startOfDayEpochMs(for: draft.date))"
        }

        for (_, grouped) in groupedDrafts {
            guard let sample = grouped.first else { continue }
            let dateEpochMs = startOfDayEpochMs(for: sample.date)
            let existingRecords = try await container.attendanceRepository.listAttendanceByDate(
                classId: sample.classId,
                dateEpochMs: dateEpochMs
            )
            for record in existingRecords {
                let sessionKey = record.sessionId.map { String($0.int64Value) } ?? "none"
                existingByKey["\(record.classId)-\(record.studentId)-\(dateEpochMs)-\(sessionKey)"] = record
                existingByKey["\(record.classId)-\(record.studentId)-\(dateEpochMs)-any"] = record
            }
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for draft in drafts {
            let dateEpochMs = startOfDayEpochMs(for: draft.date)
            let sessionKey = draft.sessionId.map(String.init) ?? "none"
            let existing = existingByKey["\(draft.classId)-\(draft.studentId)-\(dateEpochMs)-\(sessionKey)"]
                ?? existingByKey["\(draft.classId)-\(draft.studentId)-\(dateEpochMs)-any"]
            _ = try await container.attendanceRepository.saveAttendance(
                id: kotlinLong(existing?.id),
                studentId: draft.studentId,
                classId: draft.classId,
                dateEpochMs: dateEpochMs,
                status: draft.status,
                note: draft.note,
                hasIncident: draft.hasIncident,
                followUpRequired: draft.followUpRequired ?? draft.hasIncident,
                sessionId: kotlinLong(draft.sessionId),
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId,
                syncVersion: (existing?.trace.syncVersion ?? 0) + 1
            )
            enqueueLocalChange(
                entity: "attendance",
                id: "\(draft.classId)-\(draft.studentId)-\(dateEpochMs)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "studentId": draft.studentId,
                    "classId": draft.classId,
                    "dateEpochMs": dateEpochMs,
                    "status": draft.status,
                    "note": draft.note,
                    "hasIncident": draft.hasIncident,
                    "followUpRequired": draft.followUpRequired ?? draft.hasIncident,
                    "sessionId": draft.sessionId ?? NSNull()
                ]
            )
        }
    }

    func repeatLatestAttendancePattern(classId: Int64, targetDate: Date) async throws -> Int {
        let targetDay = startOfDayEpochMs(for: targetDate)
        let history = try await container.attendanceRepository.listAttendance(classId: classId)
            .map(attendanceSnapshot(from:))
            .sorted { lhs, rhs in lhs.date > rhs.date }

        let sourceDate = history
            .map { startOfDayEpochMs(for: $0.date) }
            .first(where: { $0 < targetDay })

        guard let sourceDate else { return 0 }

        let sourceRecords = try await container.attendanceRepository.listAttendanceByDate(classId: classId, dateEpochMs: sourceDate)
        var applied = 0
        for record in sourceRecords {
            try await saveAttendance(
                studentId: record.studentId,
                classId: classId,
                on: targetDate,
                status: record.status,
                note: record.note,
                hasIncident: record.hasIncident
            )
            applied += 1
        }
        return applied
    }

    func createIncident(
        classId: Int64,
        studentId: Int64?,
        title: String,
        detail: String,
        severity: String = "medium"
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let incidentId = try await container.incidentsRepository.saveIncident(
            id: nil,
            classId: classId,
            studentId: kotlinLong(studentId),
            title: title,
            detail: detail,
            severity: severity,
            dateEpochMs: nowMs,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "incident",
            id: "\(incidentId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": incidentId.int64Value,
                "classId": classId,
                "studentId": studentId ?? NSNull(),
                "title": title,
                "detail": detail,
                "severity": severity,
                "dateEpochMs": nowMs
            ]
        )
        return incidentId.int64Value
    }

    func updateIncident(
        id: Int64,
        classId: Int64,
        studentId: Int64?,
        title: String,
        detail: String,
        severity: String,
        dateEpochMs: Int64
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.incidentsRepository.saveIncident(
            id: KotlinLong(value: id),
            classId: classId,
            studentId: kotlinLong(studentId),
            title: title,
            detail: detail,
            severity: severity,
            dateEpochMs: dateEpochMs,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "incident",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "classId": classId,
                "studentId": studentId ?? NSNull(),
                "title": title,
                "detail": detail,
                "severity": severity,
                "dateEpochMs": dateEpochMs
            ]
        )
    }

    func deleteIncident(id: Int64) async throws {
        try await container.incidentsRepository.deleteIncident(id: id)
        enqueueLocalChange(
            entity: "incident",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    func loadCourseSummary(classId: Int64) async throws -> CourseInspectorSnapshot {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let attendance = try await attendanceHistory(for: classId, days: 21)
        let todayAttendance = try await attendanceRecords(for: classId, on: Date())
        let evaluations = try await evaluations(for: classId)
        let classIncidents = try await incidents(for: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        let weeklySlots = container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
        let values = grades.compactMap { $0.value?.doubleValue }
        let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
        let attendanceRate: Int
        if attendance.isEmpty {
            attendanceRate = 0
        } else {
            let presentCount = attendance.filter { $0.status.uppercased().contains("PRESENT") }.count
            attendanceRate = Int((Double(presentCount) / Double(attendance.count)) * 100.0)
        }
        return CourseInspectorSnapshot(
            schoolClass: schoolClass,
            studentCount: students.count,
            injuredStudentCount: students.filter(\.isInjured).count,
            attendanceRate: attendanceRate,
            todayPresentCount: todayAttendance.filter { $0.status.uppercased().contains("PRESENT") }.count,
            todayAbsentCount: todayAttendance.filter { $0.status.uppercased().contains("AUS") }.count,
            todayLateCount: todayAttendance.filter { $0.status.uppercased().contains("TARD") || $0.status.uppercased().contains("RETR") }.count,
            evaluationCount: evaluations.count,
            incidentCount: classIncidents.count,
            severeIncidentCount: classIncidents.filter { $0.severity.lowercased() == "high" || $0.severity.lowercased() == "critical" }.count,
            weeklySlotCount: weeklySlots.count,
            averageScore: average
            ,
            rosterPreview: Array(students.prefix(8)),
            activeEvaluationNames: Array(evaluations.map(\.name).prefix(5))
        )
    }

    func loadStudentProfile(studentId: Int64, classId: Int64?) async throws -> StudentProfileSnapshot {
        guard let student = try await container.studentsRepository.listStudents().first(where: { $0.id == studentId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró el alumno \(studentId)."])
        }
        let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId })
        let attendanceData: [AttendanceRecordSnapshot]
        let evaluationsData: [Evaluation]
        let gradesData: [Grade]
        let incidentsData: [Incident]
        let journalAggregates: [SessionJournalAggregate]
        let journalDateByJournalId: [Int64: Date]

        if let classId {
            attendanceData = try await container.attendanceRepository.listAttendance(classId: classId)
                .map(attendanceSnapshot(from:))
                .filter { $0.studentId == studentId }
            evaluationsData = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
            gradesData = try await container.gradesRepository.listGradesForClass(classId: classId)
                .filter { $0.studentId == studentId }
            incidentsData = try await container.incidentsRepository.listIncidents(classId: classId)
                .filter { $0.studentId?.int64Value == studentId }
            let sessions = try await container.plannerRepository.listAllSessions()
                .filter { $0.groupId == classId }
            let sessionDateById = Dictionary(
                sessions.map { session in
                    (session.id, self.date(from: session))
                },
                uniquingKeysWith: { first, _ in first }
            )
            var collectedAggregates: [SessionJournalAggregate] = []
            for session in sessions {
                let aggregate = try await self.container.sessionJournalRepository.getJournalForSession(
                    planningSessionId: session.id
                )
                if let aggregate,
                   aggregate.individualNotes.contains(where: { $0.studentId?.int64Value == studentId }) {
                    collectedAggregates.append(aggregate)
                }
            }
            journalAggregates = collectedAggregates
            journalDateByJournalId = Dictionary(
                journalAggregates.map { aggregate in
                    let sessionDate = sessionDateById[aggregate.journal.planningSessionId] ?? Date.distantPast
                    return (aggregate.journal.id, sessionDate)
                },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            attendanceData = []
            evaluationsData = []
            gradesData = []
            incidentsData = []
            journalAggregates = []
            journalDateByJournalId = [:]
        }

        let presentCount = attendanceData.filter { $0.status.uppercased().contains("PRESENT") }.count
        let attendanceRate = attendanceData.isEmpty ? 0 : Int((Double(presentCount) / Double(attendanceData.count)) * 100.0)
        let averageScore: Double = {
            let values = gradesData.compactMap { $0.value?.doubleValue }
            guard !values.isEmpty else { return 0.0 }
            return values.reduce(0, +) / Double(values.count)
        }()
        let evidenceCount = gradesData.filter {
            !($0.evidence?.isEmpty ?? true) || !($0.evidencePath?.isEmpty ?? true)
        }.count
        let studentJournalNotes = journalAggregates.flatMap { aggregate in
            aggregate.individualNotes.filter { $0.studentId?.int64Value == studentId }
        }
        let familyCommunications = journalAggregates
            .map(\.journal.familyCommunicationText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let adaptations = journalAggregates
            .map(\.journal.adaptationsText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var timeline: [StudentTimelineEntry] = attendanceData.prefix(8).map {
            StudentTimelineEntry(
                date: $0.date,
                title: "Asistencia · \($0.status.capitalized)",
                subtitle: $0.note.isEmpty ? "Registro diario" : $0.note,
                kind: .attendance
            )
        }

        timeline.append(contentsOf: incidentsData.prefix(6).map {
            StudentTimelineEntry(
                date: Date(timeIntervalSince1970: TimeInterval($0.date.epochSeconds)),
                title: $0.title,
                subtitle: $0.detail ?? "Incidencia registrada",
                kind: .incident
            )
        })

        let evaluationsById = Dictionary(
            evaluationsData.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        timeline.append(contentsOf: gradesData.prefix(8).map { grade in
            let evaluationName = grade.evaluationId.flatMap { evaluationsById[$0.int64Value]?.name } ?? grade.columnId
            let subtitle: String
            if let value = grade.value {
                subtitle = String(format: "Nota %.1f", value.doubleValue)
            } else {
                subtitle = "Sin nota"
            }
            return StudentTimelineEntry(
                date: Date(timeIntervalSince1970: TimeInterval(grade.trace.updatedAt.epochSeconds)),
                title: "Evaluación · \(evaluationName)",
                subtitle: subtitle,
                kind: .evaluation
            )
        })

        timeline.append(contentsOf: studentJournalNotes.prefix(6).map { note in
            StudentTimelineEntry(
                date: journalDateByJournalId[note.journalId] ?? Date.distantPast,
                title: note.tag.isEmpty ? "Diario de aula" : "Diario · \(note.tag)",
                subtitle: note.note,
                kind: .incident
            )
        })

        timeline.sort { $0.date > $1.date }

        return StudentProfileSnapshot(
            student: student,
            schoolClass: schoolClass,
            attendanceRate: attendanceRate,
            averageScore: averageScore,
            incidentCount: incidentsData.count,
            followUpCount: attendanceData.filter(\.followUpRequired).count,
            instrumentsCount: gradesData.count,
            evidenceCount: evidenceCount,
            familyCommunicationCount: familyCommunications.count,
            journalSessionCount: journalAggregates.count,
            journalNoteCount: studentJournalNotes.count,
            adaptationsSummary: adaptations.first,
            familyCommunicationSummary: familyCommunications.first,
            latestAttendanceStatus: attendanceData.sorted { $0.date > $1.date }.first?.status,
            evaluationTitles: Array(evaluationsData.map(\.name).prefix(6)),
            recentAttendance: Array(attendanceData.sorted { $0.date > $1.date }.prefix(8)),
            incidents: incidentsData.sorted { $0.date.epochSeconds > $1.date.epochSeconds },
            evaluations: evaluationsData,
            timeline: timeline
        )
    }

    // Audit debt: this aggregates business data for the Mac roster. Keep it as a bridge shim
    // until an equivalent KMP use case can own the query and row-shaping logic.
    func loadMacStudentRows(classId: Int64?) async throws -> [MacStudentRowSnapshot] {
        let allClasses = try await container.classesRepository.listClasses()
        let classesToScan = classId.map { selectedClassId in
            allClasses.filter { $0.id == selectedClassId }
        } ?? allClasses
        let allStudents = try await container.studentsRepository.listStudents()
        let allStudentsById = Dictionary(allStudents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var studentsById: [Int64: Student] = [:]
        var membershipsByStudentId: [Int64: [MacStudentClassMembership]] = [:]
        var attendanceByStudentId: [Int64: [AttendanceRecordSnapshot]] = [:]
        var incidentsByStudentId: [Int64: [Incident]] = [:]
        var averageValuesByStudentId: [Int64: [Double]] = [:]
        var workGroupByStudentClassKey: [String: String] = [:]

        for schoolClass in classesToScan {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            roster.forEach { student in
                studentsById[student.id] = student
                membershipsByStudentId[student.id, default: []].append(
                    MacStudentClassMembership(id: schoolClass.id, className: schoolClass.name)
                )
            }

            let attendance = try await container.attendanceRepository.listAttendance(classId: schoolClass.id)
                .map(attendanceSnapshot(from:))
            for record in attendance {
                attendanceByStudentId[record.studentId, default: []].append(record)
            }

            let incidents = try await container.incidentsRepository.listIncidents(classId: schoolClass.id)
            for incident in incidents {
                guard let studentId = incident.studentId?.int64Value else { continue }
                incidentsByStudentId[studentId, default: []].append(incident)
            }

            if let notebookSheet = try? await container.notebookRepository.loadNotebookSnapshot(classId: schoolClass.id) {
                for row in notebookSheet.rows {
                    if let average = row.weightedAverage?.doubleValue {
                        averageValuesByStudentId[row.student.id, default: []].append(average)
                    }
                }
            }

            let groups = try await container.notebookRepository.listWorkGroups(classId: schoolClass.id, tabId: nil)
            let groupNames = Dictionary(
                groups.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
            let members = try await container.notebookRepository.listWorkGroupMembers(classId: schoolClass.id, tabId: nil)
            for member in members {
                let key = macStudentClassKey(studentId: member.studentId, classId: schoolClass.id)
                if workGroupByStudentClassKey[key] == nil {
                    workGroupByStudentClassKey[key] = groupNames[member.groupId]
                }
            }
        }

        if classId == nil {
            for student in allStudents where studentsById[student.id] == nil {
                studentsById[student.id] = student
            }
        }

        var rows: [MacStudentRowSnapshot] = []
        for student in studentsById.values.sorted(by: { lhs, rhs in
            let lhsName = "\(lhs.lastName) \(lhs.firstName)"
            let rhsName = "\(rhs.lastName) \(rhs.firstName)"
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }) {
            let memberships = (membershipsByStudentId[student.id] ?? [])
                .sorted { $0.className.localizedCaseInsensitiveCompare($1.className) == .orderedAscending }
            let primaryMembership = classId.flatMap { selectedClassId in
                memberships.first(where: { $0.id == selectedClassId })
            } ?? memberships.first
            let attendance = attendanceByStudentId[student.id, default: []]
            let incidents = incidentsByStudentId[student.id, default: []]
            let followUpCount = attendance.filter(\.followUpRequired).count
            let incidentCount = incidents.count
            let isFollowUp = student.isInjured || followUpCount > 0 || incidentCount > 0
            let followUpLabel: String
            if student.isInjured {
                followUpLabel = "Lesión"
            } else if followUpCount > 0 {
                followUpLabel = "Seguimiento"
            } else if incidentCount > 0 {
                followUpLabel = "Incidencias"
            } else {
                followUpLabel = "Normal"
            }

            let latestAttendance = attendance.sorted { $0.date > $1.date }.first
            let averageValues = averageValuesByStudentId[student.id, default: []]
            // TODO(KMP): expose an official cross-class student average when "Todas" spans memberships.
            let averageScore = averageValues.isEmpty ? nil : averageValues.reduce(0, +) / Double(averageValues.count)
            let latestObservation = latestObservationText(attendance: attendance, incidents: incidents)
            let workGroupKey = primaryMembership.map { macStudentClassKey(studentId: student.id, classId: $0.id) }
            rows.append(
                MacStudentRowSnapshot(
                    id: student.id,
                    student: allStudentsById[student.id] ?? student,
                    classId: primaryMembership?.id,
                    className: primaryMembership?.className ?? "Sin clase",
                    allClassMemberships: memberships,
                    followUpLabel: followUpLabel,
                    recentAttendanceLabel: latestAttendance?.status ?? "Sin registro",
                    averageText: averageScore.map { IosFormatting.decimal($0) } ?? "--",
                    incidentCount: incidentCount,
                    lastObservationText: latestObservation,
                    isInjured: student.isInjured,
                    isFollowUp: isFollowUp,
                    workGroupName: workGroupKey.flatMap { workGroupByStudentClassKey[$0] } ?? "Sin grupo"
                )
            )
        }
        return rows
    }

    private func macStudentClassKey(studentId: Int64, classId: Int64) -> String {
        "\(studentId)|\(classId)"
    }

    // Audit debt: quick-note persistence belongs in shared domain logic once a KMP use case exists.
    func saveQuickStudentNote(studentId: Int64, classId: Int64?, note: String) async throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let classId else {
            throw NSError(domain: "KmpBridge", code: -4101, userInfo: [NSLocalizedDescriptionKey: "Selecciona una clase para guardar notas rápidas."])
        }
        guard let student = try await container.studentsRepository.listStudents().first(where: { $0.id == studentId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró el alumno \(studentId)."])
        }
        let now = Date()
        let sessions = try await container.plannerRepository.listAllSessions()
            .filter { $0.groupId == classId }
            .sorted { date(from: $0) > date(from: $1) }
        guard let session = sessions.first(where: { date(from: $0) <= now }) else {
            throw NSError(domain: "KmpBridge", code: -4102, userInfo: [NSLocalizedDescriptionKey: "No hay sesiones pasadas o de hoy donde guardar la nota rápida."])
        }

        let aggregate = try await container.sessionJournalRepository.getOrCreateJournal(session: session)
        let journalId = aggregate.journal.id
        let quickNote = SessionJournalIndividualNote(
            id: 0,
            journalId: journalId,
            studentId: KotlinLong(value: studentId),
            studentName: student.fullName,
            note: trimmed,
            tag: "nota rápida"
        )
        let updatedAggregate = SessionJournalAggregate(
            journal: aggregate.journal,
            individualNotes: aggregate.individualNotes + [quickNote],
            actions: aggregate.actions,
            media: aggregate.media,
            links: aggregate.links
        )
        _ = try await container.sessionJournalRepository.saveJournalAggregate(aggregate: updatedAggregate)
        enqueueLocalChange(
            entity: "session_journal",
            id: "\(journalId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": journalId,
                "planningSessionId": aggregate.journal.planningSessionId,
                "classId": classId,
                "studentId": studentId,
                "note": trimmed,
                "tag": "nota rápida"
            ]
        )
        status = "Nota rápida guardada para \(student.fullName)"
    }

    // Audit debt: presentation summary rules should move beside StudentProfileSnapshot creation in KMP.
    private func latestObservationText(from profile: StudentProfileSnapshot?) -> String {
        guard let profile else { return "Sin observaciones" }
        if let attendanceNote = profile.recentAttendance.first(where: { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.note {
            return attendanceNote
        }
        if let incident = profile.incidents.first {
            return incident.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? incident.detail ?? incident.title
                : incident.title
        }
        if let timelineEntry = profile.timeline.first, timelineEntry.subtitle != "Registro diario" {
            return timelineEntry.subtitle
        }
        return "Sin observaciones"
    }

    private func latestObservationText(attendance: [AttendanceRecordSnapshot], incidents: [Incident]) -> String {
        let recentAttendance = attendance.sorted { $0.date > $1.date }
        if let attendanceNote = recentAttendance.first(where: { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.note {
            return attendanceNote
        }
        if let incident = incidents.sorted(by: { $0.date.epochSeconds > $1.date.epochSeconds }).first {
            return incident.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? incident.detail ?? incident.title
                : incident.title
        }
        return "Sin observaciones"
    }

    func buildReportPreview(
        classId: Int64,
        studentId: Int64? = nil,
        kind: ReportKind = .groupOverview,
        termLabel: String? = nil
    ) async throws -> ReportPreviewPayload {
        let context = try await buildReportGenerationContext(classId: classId, studentId: studentId, kind: kind, termLabel: termLabel)
        return ReportPreviewPayload(
            classId: context.classId,
            className: context.className,
            previewText: context.classicReportText,
            generatedAt: Date()
        )
    }

    func buildReportGenerationContext(
        classId: Int64,
        studentId: Int64? = nil,
        kind: ReportKind,
        termLabel: String? = nil
    ) async throws -> ReportGenerationContext {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }

        let trends = try? await getAITrendsAndMetrics(classId: classId, studentId: studentId)

        let resolvedCourseLabel = courseLabel(for: schoolClass)

        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await evaluations(for: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        let groupedGrades = Dictionary(grouping: grades, by: \.studentId)
        let rubricCount = Set(evaluations.compactMap { $0.rubricId?.int64Value }).count
        let rows = students.map { student -> String in
            let values = groupedGrades[student.id, default: []].compactMap { $0.value?.doubleValue }
            let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
            return "\(student.lastName), \(student.firstName): \(IosFormatting.decimal(from: average))"
        }
        let bytes = try await container.reportService.exportNotebookReport(
            request: NotebookReportRequest(className: schoolClass.name, rows: rows)
        )
        let classicText = String(data: data(from: bytes), encoding: .utf8) ?? "Vista previa no disponible para este informe."

        switch kind {
        case .groupOverview:
            let summary = try await loadCourseSummary(classId: classId)
            let strengths = compactSuggestions(
                summary.averageScore >= 7.0 ? "El grupo mantiene una media global sólida en el cuaderno." : nil,
                summary.attendanceRate >= 90 ? "La asistencia reciente sostiene una dinámica estable." : nil,
                summary.severeIncidentCount == 0 && summary.incidentCount <= 2 ? "La convivencia está contenida y sin alertas graves." : nil,
                summary.evaluationCount >= 3 ? "Hay variedad suficiente de instrumentos para argumentar el informe." : nil
            )
            let needsAttention = compactSuggestions(
                summary.studentCount == 0 ? "Todavía no hay alumnado asociado al grupo." : nil,
                summary.averageScore > 0 && summary.averageScore < 5.0 ? "La media del grupo pide refuerzo pedagógico." : nil,
                (1..<85).contains(summary.attendanceRate) ? "La asistencia reciente está por debajo del umbral deseable." : nil,
                summary.severeIncidentCount > 0 ? "Existen incidencias graves que conviene contextualizar con cuidado." : nil
            )
            let actions = compactSuggestions(
                (1..<85).contains(summary.attendanceRate) ? "Planificar seguimiento específico de asistencia para el alumnado con más ausencias." : nil,
                summary.averageScore > 0 && summary.averageScore < 5.0 ? "Revisar instrumentos y preparar refuerzo para la próxima unidad." : nil,
                summary.evaluationCount < 2 ? "Añadir más evidencias evaluativas antes de emitir conclusiones firmes." : nil
            )
            let facts = [
                "Alumnado total: \(summary.studentCount).",
                "Media global registrada: \(IosFormatting.decimal(from: summary.averageScore)).",
                "Asistencia reciente estimada: \(summary.attendanceRate)%.",
                "Evaluaciones activas: \(summary.evaluationCount) y rúbricas vinculadas: \(rubricCount).",
                "Incidencias registradas: \(summary.incidentCount), graves: \(summary.severeIncidentCount).",
                summary.activeEvaluationNames.isEmpty ? "No hay instrumentos activos destacados." : "Instrumentos activos destacados: \(summary.activeEvaluationNames.joined(separator: ", "))."
            ]
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: nil,
                studentName: nil,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: summary.averageScore,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "docente",
                summary: "Síntesis global del grupo con foco en rendimiento, asistencia y clima.",
                metrics: [
                    ReportMetric(title: "Alumnado", value: "\(summary.studentCount)", systemImage: "person.3.fill"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: summary.averageScore), systemImage: "sum"),
                    ReportMetric(title: "Asistencia", value: "\(summary.attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Incidencias", value: "\(summary.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                ],
                factLines: facts,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: summary.rosterPreview.isEmpty ? [] : ["Muestra de roster: \(summary.rosterPreview.map(\.fullName).joined(separator: ", "))."],
                classicReportText: classicText,
                hasEnoughData: summary.studentCount > 0,
                dataQualityNote: summary.evaluationCount == 0 ? "No hay evaluaciones registradas todavía; el relato debe ser prudente." : nil,
                trends: trends
            )

        case .studentSummary:
            guard let studentId else {
                return ReportGenerationContext(
                    classId: classId,
                    className: schoolClass.name,
                    studentId: nil,
                    studentName: nil,
                    kind: kind,
                    reportTitle: kind.title,
                    courseLabel: resolvedCourseLabel,
                    termLabel: termLabel,
                    numericScore: nil,
                    curriculumReferences: [],
                    promptDirectives: [],
                    audienceHint: "tutoria",
                    summary: "Hace falta seleccionar un alumno para construir este informe.",
                    metrics: [],
                    factLines: ["No se ha seleccionado alumnado para el informe individual."],
                    strengths: [],
                    needsAttention: ["Selecciona un alumno antes de generar el borrador con IA."],
                    recommendedActions: [],
                    supportNotes: [],
                    classicReportText: classicText,
                    hasEnoughData: false,
                    dataQualityNote: "El informe individual requiere selección de alumno.",
                    trends: nil
                )
            }
            let profile = try await loadStudentProfile(studentId: studentId, classId: classId)
            let strengths = compactSuggestions(
                profile.averageScore >= 7.0 ? "Mantiene un rendimiento medio sólido en los instrumentos registrados." : nil,
                profile.attendanceRate >= 90 ? "Sostiene una asistencia alta en el periodo analizado." : nil,
                profile.incidentCount == 0 ? "No presenta incidencias registradas en el grupo." : nil,
                profile.evidenceCount > 0 ? "Cuenta con evidencias adjuntas que apoyan la valoración." : nil
            )
            let needsAttention = compactSuggestions(
                profile.instrumentsCount == 0 ? "No hay todavía instrumentos suficientes para una valoración cerrada." : nil,
                profile.averageScore > 0 && profile.averageScore < 5.0 ? "El rendimiento registrado está por debajo del nivel esperado." : nil,
                (1..<85).contains(profile.attendanceRate) ? "La asistencia necesita seguimiento." : nil,
                profile.incidentCount > 0 ? "Existen incidencias registradas que conviene contextualizar pedagógicamente." : nil,
                profile.followUpCount > 0 ? "Hay registros de seguimiento en asistencia que requieren continuidad." : nil
            )
            let actions = compactSuggestions(
                profile.averageScore > 0 && profile.averageScore < 5.0 ? "Proponer refuerzo específico en los instrumentos con peor resultado." : nil,
                (1..<85).contains(profile.attendanceRate) ? "Acordar rutina de seguimiento de asistencia con tutoría y familia." : nil,
                profile.familyCommunicationCount == 0 ? "Preparar una comunicación breve a familia si el caso lo requiere." : nil,
                profile.evaluationTitles.isEmpty ? "Recoger nuevas evidencias antes del siguiente informe." : nil
            )
            let facts = compactSuggestions(
                "Alumno: \(profile.student.fullName).",
                "Asistencia estimada: \(profile.attendanceRate)%.",
                profile.averageScore > 0 ? "Media registrada: \(IosFormatting.decimal(from: profile.averageScore))." : "Sin media consolidada todavía.",
                "Incidencias registradas: \(profile.incidentCount).",
                "Seguimientos activos: \(profile.followUpCount).",
                profile.latestAttendanceStatus == nil ? nil : "Último estado de asistencia: \(profile.latestAttendanceStatus ?? "").",
                profile.evaluationTitles.isEmpty ? "No hay evaluaciones vinculadas todavía." : "Instrumentos presentes: \(profile.evaluationTitles.joined(separator: ", "))."
            )
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: studentId,
                studentName: profile.student.fullName,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: profile.averageScore > 0 ? profile.averageScore : nil,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "tutoria",
                summary: "Síntesis individual centrada en seguimiento, evidencias y próximos pasos.",
                metrics: [
                    ReportMetric(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum"),
                    ReportMetric(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill"),
                    ReportMetric(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                ],
                factLines: facts,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: compactSuggestions(
                    profile.adaptationsSummary,
                    profile.familyCommunicationSummary,
                    profile.timeline.first.map { "Último hito registrado: \($0.title). \($0.subtitle)" }
                ),
                classicReportText: classicText,
                hasEnoughData: profile.instrumentsCount > 0 || profile.journalNoteCount > 0 || profile.incidentCount > 0,
                dataQualityNote: profile.instrumentsCount == 0 ? "Hay poca evidencia evaluativa registrada; conviene evitar conclusiones fuertes." : nil,
                trends: trends
            )

        case .evaluationDigest:
            let values = grades.compactMap { $0.value?.doubleValue }
            let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
            let evaluationsWithRubric = evaluations.filter { $0.rubricId != nil }.count
            let strengths = compactSuggestions(
                evaluations.count >= 3 ? "Existe una base suficiente de instrumentos activos para describir el proceso evaluativo." : nil,
                evaluationsWithRubric > 0 ? "Hay rúbricas vinculadas que ayudan a justificar criterios y niveles." : nil,
                !values.isEmpty ? "Ya existen calificaciones registradas sobre las que redactar el digest." : nil
            )
            let needsAttention = compactSuggestions(
                evaluations.isEmpty ? "No hay instrumentos evaluativos creados en este grupo." : nil,
                evaluationsWithRubric == 0 && !evaluations.isEmpty ? "Ninguna evaluación está enlazada a una rúbrica." : nil,
                values.isEmpty ? "Todavía no hay calificaciones registradas para sintetizar resultados." : nil
            )
            let actions = compactSuggestions(
                evaluationsWithRubric == 0 && !evaluations.isEmpty ? "Valorar vincular rúbricas a los instrumentos más relevantes." : nil,
                values.isEmpty ? "Registrar evidencias antes de compartir un resumen valorativo." : nil,
                evaluations.count < 2 ? "Diversificar instrumentos si se necesita una foto más completa del aprendizaje." : nil
            )
            let factLines = [
                "Instrumentos activos: \(evaluations.count).",
                "Rúbricas vinculadas: \(evaluationsWithRubric) de \(evaluations.count).",
                values.isEmpty ? "No hay notas registradas todavía." : "Media agregada de calificaciones: \(IosFormatting.decimal(from: average)).",
                evaluations.isEmpty ? "Sin nombres de instrumentos disponibles." : "Instrumentos destacados: \(evaluations.prefix(6).map(\.name).joined(separator: ", "))."
            ]
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: nil,
                studentName: nil,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: average > 0 ? average : nil,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "docente",
                summary: "Lectura narrativa de instrumentos, pesos, rúbricas y evidencias disponibles.",
                metrics: [
                    ReportMetric(title: "Instrumentos", value: "\(evaluations.count)", systemImage: "chart.bar.doc.horizontal"),
                    ReportMetric(title: "Rúbricas", value: "\(evaluationsWithRubric)", systemImage: "checklist"),
                    ReportMetric(title: "Notas", value: "\(values.count)", systemImage: "number"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: average), systemImage: "sum")
                ],
                factLines: factLines,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: evaluations.prefix(4).map { "\($0.name) · peso \(IosFormatting.decimal(from: $0.weight)) · tipo \($0.type)" },
                classicReportText: classicText,
                hasEnoughData: !evaluations.isEmpty,
                dataQualityNote: values.isEmpty ? "Hay estructura evaluativa, pero faltan calificaciones para una síntesis más sólida." : nil,
                trends: trends
            )

        case .operationsSnapshot:
            let attendance = try await attendanceHistory(for: classId, days: 14)
            let incidents = try await incidents(for: classId)
            let sessions = try await container.plannerRepository.listAllSessions()
                .filter { $0.groupId == classId }
                .sorted { lhs, rhs in
                    if lhs.year == rhs.year, lhs.weekNumber == rhs.weekNumber {
                        if lhs.dayOfWeek == rhs.dayOfWeek { return lhs.period > rhs.period }
                        return lhs.dayOfWeek > rhs.dayOfWeek
                    }
                    if lhs.year == rhs.year { return lhs.weekNumber > rhs.weekNumber }
                    return lhs.year > rhs.year
                }
            var journalSummaries: [SessionJournalSummary] = []
            if !sessions.isEmpty {
                journalSummaries = try await plannerJournalSummaries(sessionIds: Array(sessions.prefix(8).map(\.id)))
            }
            let presentCount = attendance.filter { $0.status.uppercased().contains("PRESENT") }.count
            let attendanceRate = attendance.isEmpty ? 0 : Int((Double(presentCount) / Double(attendance.count)) * 100.0)
            let climateValues = journalSummaries.map(\.climateScore).filter { $0 > 0 }
            let climateAverage = climateValues.isEmpty ? 0.0 : Double(climateValues.reduce(0, +)) / Double(climateValues.count)
            let strengths = compactSuggestions(
                attendanceRate >= 90 ? "La asistencia reciente favorece una operativa estable." : nil,
                incidents.prefix(5).isEmpty ? "No hay incidencias recientes relevantes en el grupo." : nil,
                climateAverage >= 4.0 ? "El clima de aula registrado en diarios es positivo." : nil
            )
            let needsAttention = compactSuggestions(
                (1..<85).contains(attendanceRate) ? "La asistencia reciente pide vigilancia operativa." : nil,
                incidents.prefix(5).count >= 3 ? "Se acumulan varias incidencias recientes." : nil,
                climateAverage > 0 && climateAverage < 3.0 ? "El clima de aula reportado es frágil." : nil,
                journalSummaries.isEmpty ? "No hay diarios recientes suficientes para sostener el resumen operativo." : nil
            )
            let actions = compactSuggestions(
                (1..<85).contains(attendanceRate) ? "Revisar alumnado con ausencias o retrasos repetidos." : nil,
                incidents.prefix(5).count >= 3 ? "Agrupar incidencias por patrón y definir seguimiento corto." : nil,
                journalSummaries.isEmpty ? "Completar diarios de sesión para enriquecer el seguimiento semanal." : nil
            )
            let factLines = compactSuggestions(
                "Asistencia reciente estimada: \(attendanceRate)%.",
                "Incidencias en histórico reciente: \(incidents.prefix(8).count).",
                journalSummaries.isEmpty ? "Sin diarios recientes disponibles." : "Diarios recientes consultados: \(journalSummaries.count).",
                climateAverage > 0 ? "Clima medio registrado: \(IosFormatting.decimal(from: climateAverage))." : "Sin puntuación media de clima disponible.",
                incidents.first.map { "Última incidencia: \($0.title)." }
            )
            let supportNotes = compactSuggestions(
                incidents.first?.detail,
                journalSummaries.first.map { "Última sesión con incidencia: etiquetas \($0.incidentTags.joined(separator: ", "))" }
            )
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: nil,
                studentName: nil,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: climateAverage > 0 ? climateAverage : nil,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "docente",
                summary: "Resumen semanal de operativa, asistencia, incidencias y señales del diario.",
                metrics: [
                    ReportMetric(title: "Asistencia", value: "\(attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Incidencias", value: "\(incidents.prefix(8).count)", systemImage: "exclamationmark.bubble.fill"),
                    ReportMetric(title: "Diarios", value: "\(journalSummaries.count)", systemImage: "doc.text.fill"),
                    ReportMetric(title: "Clima", value: IosFormatting.decimal(from: climateAverage), systemImage: "sun.max.fill")
                ],
                factLines: factLines,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: supportNotes,
                classicReportText: classicText,
                hasEnoughData: !attendance.isEmpty || !incidents.isEmpty || !journalSummaries.isEmpty,
                dataQualityNote: journalSummaries.isEmpty ? "El resumen operativo se apoya más en asistencia e incidencias que en diarios completos." : nil,
                trends: trends
            )

        case .lomloeEvaluationComment:
            guard let studentId else {
                return ReportGenerationContext(
                    classId: classId,
                    className: schoolClass.name,
                    studentId: nil,
                    studentName: nil,
                    kind: kind,
                    reportTitle: kind.title,
                    courseLabel: resolvedCourseLabel,
                    termLabel: termLabel,
                    numericScore: nil,
                    curriculumReferences: ["CE1", "CE2", "CE3", "CE4", "CE5"],
                    promptDirectives: ["Comentario breve, personalizado, competencial y listo para informe trimestral."],
                    audienceHint: "familia",
                    summary: "Hace falta seleccionar un alumno para generar el comentario LOMLOE.",
                    metrics: [],
                    factLines: ["Selecciona un alumno para generar el comentario de evaluación."],
                    strengths: [],
                    needsAttention: ["El comentario LOMLOE requiere un alumno concreto."],
                    recommendedActions: [],
                    supportNotes: [],
                    classicReportText: "Selecciona un alumno para generar el comentario LOMLOE.",
                    hasEnoughData: false,
                    dataQualityNote: "El comentario LOMLOE es individual y requiere selección de alumno.",
                    trends: nil
                )
            }
            let profile = try await loadStudentProfile(studentId: studentId, classId: classId)
            let numericScore = profile.averageScore > 0 ? profile.averageScore : nil
            let performanceBand: String = {
                guard let numericScore else { return "Sin calificación consolidada" }
                switch numericScore {
                case ..<5: return "Insuficiente"
                case 5..<6: return "Suficiente"
                case 6..<7: return "Bien"
                case 7..<9: return "Notable"
                default: return "Sobresaliente"
                }
            }()
            let curriculumReferences = inferredCurriculumReferences(for: profile)
            let strengths = compactSuggestions(
                profile.averageScore >= 7.0 ? "Ha alcanzado satisfactoriamente buena parte de los criterios trabajados." : nil,
                profile.attendanceRate >= 90 ? "Mantiene una asistencia que favorece la continuidad del aprendizaje." : nil,
                profile.incidentCount == 0 ? "Participa sin incidencias relevantes en el periodo observado." : nil,
                profile.evidenceCount > 0 ? "Existen evidencias registradas que respaldan su progreso." : nil
            )
            let needsAttention = compactSuggestions(
                numericScore == nil ? "La valoración debe ser prudente porque la evidencia numérica todavía es limitada." : nil,
                numericScore != nil && numericScore! < 5.0 ? "Varios criterios siguen en desarrollo y requieren refuerzo guiado." : nil,
                (1..<85).contains(profile.attendanceRate) ? "La continuidad en la asistencia condiciona parte del progreso." : nil,
                profile.evaluationTitles.isEmpty ? "Conviene ampliar instrumentos y evidencias antes del siguiente informe." : nil
            )
            let recommendedActions = compactSuggestions(
                numericScore != nil && numericScore! < 5.0 ? "Reforzar de forma progresiva los criterios prioritarios del siguiente periodo." : nil,
                profile.adaptationsSummary == nil && profile.followUpCount > 0 ? "Mantener seguimiento cercano y propuestas de mejora concretas." : nil,
                "Se recomienda seguir consolidando hábitos de participación, autonomía y transferencia a nuevas situaciones motrices."
            )
            let facts = compactSuggestions(
                "Alumno: \(profile.student.fullName).",
                "Curso: \(resolvedCourseLabel).",
                termLabel.map { "Trimestre: \($0)." },
                numericScore.map { "Calificación orientativa interna: \(IosFormatting.decimal(from: $0)) (\(performanceBand))." },
                "Asistencia estimada: \(profile.attendanceRate)%.",
                profile.evaluationTitles.isEmpty ? "No hay instrumentos específicos nombrados." : "Instrumentos trabajados: \(profile.evaluationTitles.joined(separator: ", ")).",
                "Referencias curriculares sugeridas: \(curriculumReferences.joined(separator: ", "))."
            )
            let supportNotes = compactSuggestions(
                profile.adaptationsSummary.map { "Adaptaciones o apoyos: \($0)" },
                profile.familyCommunicationSummary.map { "Comunicación familia: \($0)" },
                profile.timeline.first.map { "Última evidencia relevante: \($0.title). \($0.subtitle)" }
            )
            let classicCommentShell = """
            ---
            COMENTARIO DE EVALUACIÓN — \(profile.student.fullName) | \(resolvedCourseLabel) | \(termLabel ?? "Trimestre")

            Comentario pendiente de generación IA local. Usa el botón “Generar borrador” para crear el texto final en formato LOMLOE.
            ---
            """
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: studentId,
                studentName: profile.student.fullName,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: numericScore,
                curriculumReferences: curriculumReferences,
                promptDirectives: [
                    "Aplicar estructura de 4 bloques breve para comentario trimestral LOMLOE.",
                    "No mencionar la nota numérica en el texto final.",
                    "Mencionar al menos una competencia específica CE1-CE5.",
                    "Tono positivo, específico y listo para copiar en el informe."
                ],
                audienceHint: "familia",
                summary: "Comentario cualitativo trimestral de Educación Física, breve, competencial y listo para informe.",
                metrics: [
                    ReportMetric(title: "Curso", value: resolvedCourseLabel, systemImage: "graduationcap.fill"),
                    ReportMetric(title: "Trimestre", value: termLabel ?? "Sin definir", systemImage: "calendar"),
                    ReportMetric(title: "Nota guía", value: numericScore.map { IosFormatting.decimal(from: $0) } ?? "Sin nota", systemImage: "number"),
                    ReportMetric(title: "CE", value: curriculumReferences.joined(separator: ", "), systemImage: "list.bullet.clipboard")
                ],
                factLines: facts,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: recommendedActions,
                supportNotes: supportNotes,
                classicReportText: classicCommentShell,
                hasEnoughData: numericScore != nil || !profile.evaluationTitles.isEmpty || !profile.timeline.isEmpty,
                dataQualityNote: numericScore == nil ? "Si hay poca nota numérica, el comentario debe apoyarse en evidencias, actitud y progreso observado." : nil,
                trends: trends
            )
        }
    }

    func loadTemplates(kind: ConfigTemplateKind? = nil) async throws -> [ConfigTemplate] {
        try await container.configurationTemplateRepository.listTemplates(kind: kind)
    }

    func loadTemplateVersions(templateId: Int64) async throws -> [ConfigTemplateVersion] {
        try await container.configurationTemplateRepository.listTemplateVersions(templateId: templateId)
    }

    func learningSituations() async throws -> [LearningSituation] {
        try await container.learningSituationsRepository.listSituations()
    }

    func deleteLearningSituation(id: Int64) async throws {
        try await container.learningSituationsRepository.deleteSituation(id: id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: ["id": id],
            op: "delete"
        )
    }

    func updateLearningSituationStatus(id: Int64, status: LearningSituationStatus) async throws {
        guard let situation = try await container.learningSituationsRepository.getSituation(id: id) else {
            throw NSError(domain: "LearningSituations", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se encontró la situación para actualizar su estado."])
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let updatedTrace = situation.trace.doCopy(
            authorUserId: situation.trace.authorUserId,
            createdAt: situation.trace.createdAt,
            updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            associatedGroupId: situation.trace.associatedGroupId,
            deviceId: localDeviceId,
            syncVersion: situation.trace.syncVersion + 1
        )
        let updated = situation.doCopy(
            id: situation.id,
            title: situation.title,
            stageLabel: situation.stageLabel,
            courseLabel: situation.courseLabel,
            subjectLabel: situation.subjectLabel,
            termLabel: situation.termLabel,
            centerLabel: situation.centerLabel,
            sessionCount: situation.sessionCount,
            challenge: situation.challenge,
            finalProduct: situation.finalProduct,
            payloadJson: situation.payloadJson,
            status: status,
            trace: updatedTrace
        )
        _ = try await container.learningSituationsRepository.saveSituation(situation: updated)
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": situation.id, "title": situation.title, "stageLabel": situation.stageLabel,
                "courseLabel": situation.courseLabel, "subjectLabel": situation.subjectLabel,
                "termLabel": situation.termLabel, "centerLabel": situation.centerLabel,
                "sessionCount": situation.sessionCount, "challenge": situation.challenge,
                "finalProduct": situation.finalProduct, "payloadJson": situation.payloadJson,
                "status": status.name
            ]
        )
    }

    func learningSituationVersions(id: Int64) async throws -> [LearningSituationVersion] {

        try await container.learningSituationsRepository.listVersions(learningSituationId: id)
    }

    func learningSituationClassLinks(id: Int64) async throws -> [LearningSituationClassLink] {
        try await container.learningSituationsRepository.listClassLinks(learningSituationId: id)
    }

    /// Bulk read used by the iPad/Mac Situaciones, Cuaderno and Planner surfaces.
    /// Keeping the aggregation at repository level avoids one SQLite round-trip per
    /// situation when a workspace is opened.
    func learningSituationClassLinksAll() async throws -> [LearningSituationClassLink] {
        try await container.learningSituationsRepository.listAllClassLinks()
    }

    func addLearningSituationClassLink(situationId: Int64, classId: Int64) async throws {
        let current = try await container.learningSituationsRepository.listClassLinks(learningSituationId: situationId)
        var classIds = Set(current.map { $0.classId })
        if !classIds.contains(classId) {
            classIds.insert(classId)
            try await container.learningSituationsRepository.replaceClassLinks(
                learningSituationId: situationId,
                classIds: Array(classIds).sorted().map { KotlinLong(value: $0) }
            )
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            enqueueLocalChange(
                entity: "learning_situation_class_link",
                id: "\(situationId)-\(classId)",
                updatedAtEpochMs: nowMs,
                payload: ["learningSituationId": situationId, "classId": classId]
            )
        }
    }

    func learningSituationResources(id: Int64) async throws -> [LearningSituationLinkedResource] {
        try await container.learningSituationsRepository.listLinkedResources(learningSituationId: id)
    }

    func learningSituationSessionPlan(id: Int64) async throws -> LearningSituationSessionPlan? {
        guard let plan = try await container.learningSituationsRepository.getSessionPlan(id: id) else { return nil }
        return try await repairPersistedSessionPlanIfNeeded(plan)
    }

    func learningSituationSessionPlans(sequenceVersionId: Int64) async throws -> [LearningSituationSessionPlan] {
        let plans = try await container.learningSituationsRepository.listSessionPlans(sequenceVersionId: sequenceVersionId)
        var repaired: [LearningSituationSessionPlan] = []
        repaired.reserveCapacity(plans.count)
        for plan in plans {
            repaired.append(try await repairPersistedSessionPlanIfNeeded(plan))
        }
        return repaired
    }

    /// Bulk read used by Planner sequence enrichment to avoid one query per session plan.
    func learningSituationSessionPlansAll() async throws -> [LearningSituationSessionPlan] {
        let plans = try await container.learningSituationsRepository.listAllSessionPlans()
        var repaired: [LearningSituationSessionPlan] = []
        repaired.reserveCapacity(plans.count)
        for plan in plans {
            repaired.append(try await repairPersistedSessionPlanIfNeeded(plan))
        }
        return repaired
    }

    /// Repara planes históricos sin cambiar sus IDs ni exigir borrar la planificación.
    /// Primero se recupera el DOCX original (incluida la descarga metadata-first por hash).
    /// Si el binario aún no está disponible, se deja el registro intacto: la proyección v2
    /// puede representar el plan mientras tanto, pero no se persiste un v2 incompleto que
    /// impida recuperar PREPARES/CONSOLIDATES cuando llegue el documento.
    private func repairPersistedSessionPlanIfNeeded(
        _ plan: LearningSituationSessionPlan
    ) async throws -> LearningSituationSessionPlan {
        let versions = try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: plan.learningSituationId)
        let version = versions.first { $0.id == plan.sequenceVersionId }
        let payload = LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)
        let expectedHash = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedHash = payload?.sourceDocumentSHA256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSyntheticProjection = payload?.activities.contains { activity in
            let key = activity.activityKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return key.hasPrefix("LEGACY-") || key.hasPrefix("ACTIVIDAD ")
        } ?? false
        let alreadyCanonical = payload?.schema == "session-plan-v2"
            && plan.developmentJson.contains("\"prepares\":")
            && plan.developmentJson.contains("\"consolidates\":")
            && !hasSyntheticProjection
            && (expectedHash.isEmpty || storedHash == expectedHash)
        guard !alreadyCanonical else { return plan }

        if let sourceURL = await ensureLearningSituationSessionSequenceDocument(version: version),
           let repairedJSON = await canonicalDevelopmentJSON(
               from: sourceURL,
               sessionNumber: Int(plan.sessionNumber),
               sourceSHA256: expectedHash.isEmpty ? nil : expectedHash
           ) {
            return try await persistDerivedDevelopmentJSON(repairedJSON, for: plan)
        }

        return plan
    }

    private nonisolated static func canonicalDevelopmentJSON(
        for draft: LearningSituationSessionPlanDraft,
        sourceSHA256: String? = nil
    ) -> String? {
        let payload = LearningSituationSessionDevelopmentPayload(
            organisation: draft.organisation,
            coreKnowledge: draft.coreKnowledge,
            assessment: draft.assessment,
            sections: draft.development,
            activities: draft.activities,
            guidingQuestions: draft.guidingQuestions,
            closure: draft.closure,
            visuals: draft.visuals,
            sequenceRoute: draft.sequenceRoute,
            sourceDocumentSHA256: sourceSHA256
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func canonicalDevelopmentJSON(
        from sourceURL: URL,
        sessionNumber: Int,
        sourceSHA256: String?
    ) async -> String? {
        let trimmedSourceHash = sourceSHA256?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = trimmedSourceHash?.isEmpty == false ? trimmedSourceHash! : sourceURL.path
        if let cached = sessionPlanJSONCacheBySource[cacheKey]?[sessionNumber] {
            return cached
        }

        let result: String? = await Task.detached(priority: .utility) { () -> String? in
            guard let imported = try? LearningSituationSessionSequenceDocumentImportService().preview(from: sourceURL),
                  let draft = imported.plans.first(where: { $0.sessionNumber == sessionNumber }) else {
                return nil
            }
            return KmpBridge.canonicalDevelopmentJSON(for: draft, sourceSHA256: sourceSHA256)
        }.value
        if let result {
            var plans = sessionPlanJSONCacheBySource[cacheKey] ?? [:]
            plans[sessionNumber] = result
            sessionPlanJSONCacheBySource[cacheKey] = plans
        }
        return result
    }

    private func persistDerivedDevelopmentJSON(
        _ repairedJSON: String,
        for plan: LearningSituationSessionPlan
    ) async throws -> LearningSituationSessionPlan {
        guard repairedJSON != plan.developmentJson,
              !semanticallyEquivalentDevelopmentJSON(plan.developmentJson, repairedJSON) else {
            return plan
        }
        let repairedPlan = LearningSituationSessionPlan(
            id: plan.id,
            learningSituationId: plan.learningSituationId,
            sequenceVersionId: plan.sequenceVersionId,
            sessionNumber: plan.sessionNumber,
            sourceLabel: plan.sourceLabel,
            title: plan.title,
            sessionType: plan.sessionType,
            effectiveMinutes: plan.effectiveMinutes,
            objective: plan.objective,
            criteriaJson: plan.criteriaJson,
            material: plan.material,
            developmentJson: repairedJSON,
            adaptationsJson: plan.adaptationsJson,
            trace: plan.trace
        )
        _ = try await container.learningSituationsRepository.saveSessionPlan(plan: repairedPlan)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation_session_plan",
            id: "\(plan.learningSituationId)-\(plan.sequenceVersionId)-\(plan.sessionNumber)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": plan.id, "learningSituationId": plan.learningSituationId,
                "sequenceVersionId": plan.sequenceVersionId, "sessionNumber": plan.sessionNumber,
                "sourceLabel": plan.sourceLabel, "title": plan.title,
                "sessionType": plan.sessionType, "effectiveMinutes": plan.effectiveMinutes,
                "objective": plan.objective, "criteriaJson": plan.criteriaJson,
                "material": plan.material, "developmentJson": repairedJSON,
                "adaptationsJson": plan.adaptationsJson
            ]
        )
        return repairedPlan
    }

    /// Los drafts del importador llevan UUIDs de UI que se regeneran al volver a leer el mismo
    /// DOCX. No deben provocar una escritura ni una notificación de sync si el contenido docente
    /// y la procedencia son iguales.
    private func semanticallyEquivalentDevelopmentJSON(_ lhs: String, _ rhs: String) -> Bool {
        func canonicalData(_ json: String) -> Data? {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            func removingRuntimeIDs(_ value: Any) -> Any {
                if let dictionary = value as? [String: Any] {
                    var result: [String: Any] = [:]
                    for (key, nested) in dictionary {
                        if key == "id", let string = nested as? String, UUID(uuidString: string) != nil {
                            continue
                        }
                        result[key] = removingRuntimeIDs(nested)
                    }
                    return result
                }
                if let array = value as? [Any] {
                    return array.map(removingRuntimeIDs)
                }
                return value
            }
            return try? JSONSerialization.data(
                withJSONObject: removingRuntimeIDs(object),
                options: [.sortedKeys]
            )
        }
        guard let lhsData = canonicalData(lhs), let rhsData = canonicalData(rhs) else { return false }
        return lhsData == rhsData
    }

    private func localSequenceSourceURL(_ version: LearningSituationSessionSequenceVersion?) -> URL? {
        if let path = version?.localPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: path)
            if let expectedHash = version?.sha256,
               !expectedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let data = try? Data(contentsOf: url) {
                let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if actualHash == expectedHash { return url }
            }
        }
        guard let sha256 = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha256.isEmpty else { return nil }
        let url = LearningSituationDocumentStore().directoryURL
            .appendingPathComponent("\(sha256).docx")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actualHash == sha256 ? url : nil
    }

    /// Exposición de solo lectura para que el Planner pueda representar la última
    /// secuencia teórica incluso antes de que exista una sesión en el calendario.
    func learningSituationSessionSequenceVersions(
        learningSituationId: Int64
    ) async throws -> [LearningSituationSessionSequenceVersion] {
        try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: learningSituationId)
    }

    /// Bulk read used by Planner sequence enrichment to avoid one query per situation.
    func learningSituationSessionSequenceVersionsAll() async throws -> [LearningSituationSessionSequenceVersion] {
        try await container.learningSituationsRepository.listAllSessionSequenceVersions()
    }

    func learningSituationSessionSequenceVersion(id: Int64, learningSituationId: Int64) async throws -> LearningSituationSessionSequenceVersion? {
        try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: learningSituationId)
            .first { $0.id == id }
    }

    /// Makes the original DOCX available to the Planner when the metadata arrived by
    /// sync before the binary did. The download is cache-by-hash and is safe to repeat.
    func ensureLearningSituationSessionSequenceDocument(
        version: LearningSituationSessionSequenceVersion?
    ) async -> URL? {
        if let localURL = localSequenceSourceURL(version) { return localURL }
        guard let sha256 = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha256.isEmpty,
              let path = await downloadLearningSituationDocumentIfNeeded(sha256: sha256) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func confirmLearningSituationImport(
        draft: LearningSituationImportDraft,
        existingSituationId: Int64? = nil
    ) async throws -> Int64 {
        guard !draft.selectedClassIds.isEmpty else {
            throw NSError(domain: "LearningSituations", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un grupo antes de guardar."])
        }
        let storedURL = try LearningSituationDocumentStore().persistSourceDocument(from: draft.sourceURL, sha256: draft.sha256)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            associatedGroupId: nil,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let situationId = try await container.learningSituationsRepository.saveSituation(
            situation: LearningSituation(
                id: existingSituationId ?? 0,
                title: draft.title,
                stageLabel: draft.stageLabel,
                courseLabel: draft.courseLabel,
                subjectLabel: draft.subjectLabel,
                termLabel: draft.termLabel,
                centerLabel: draft.centerLabel,
                sessionCount: Int32(draft.sessionCount),
                challenge: draft.challenge,
                finalProduct: draft.finalProduct,
                payloadJson: draft.payloadJSON,
                status: .active,
                trace: trace
            )
        ).int64Value
        let warningJSON = (try? JSONEncoder().encode(draft.warnings))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        _ = try await container.learningSituationsRepository.saveVersion(
            version: LearningSituationVersion(
                id: 0,
                learningSituationId: situationId,
                versionNumber: 0,
                originalFileName: draft.sourceFileName,
                sha256: draft.sha256,
                localPath: storedURL.path,
                sizeBytes: draft.sizeBytes,
                payloadJson: draft.payloadJSON,
                warningsJson: warningJSON,
                trace: trace
            )
        )
        let acceptedVersionNumber = try await container.learningSituationsRepository
            .listVersions(learningSituationId: situationId)
            .first?.versionNumber ?? 1
        try await container.learningSituationsRepository.replaceClassLinks(
            learningSituationId: situationId,
            classIds: draft.selectedClassIds.sorted().map { KotlinLong(value: $0) }
        )
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(situationId)",
            updatedAtEpochMs: nowMs,
            payload: learningSituationSyncPayload(id: situationId, draft: draft)
        )
        enqueueLocalChange(
            entity: "learning_situation_version",
            id: "\(situationId)-\(draft.sha256)",
            updatedAtEpochMs: nowMs,
            payload: [
                "learningSituationId": situationId,
                "versionNumber": acceptedVersionNumber,
                "originalFileName": draft.sourceFileName,
                "sha256": draft.sha256,
                "sizeBytes": draft.sizeBytes,
                "payloadJson": draft.payloadJSON,
                "warningsJson": warningJSON
            ]
        )
        for classId in draft.selectedClassIds {
            enqueueLocalChange(
                entity: "learning_situation_class_link",
                id: "\(situationId)-\(classId)",
                updatedAtEpochMs: nowMs,
                payload: ["learningSituationId": situationId, "classId": classId]
            )
        }
        try await uploadLearningSituationDocumentIfPaired(at: storedURL, sha256: draft.sha256)
        return situationId
    }

    func duplicateLearningSituation(_ source: LearningSituation, classIds: [Int64]) async throws -> Int64 {
        let versions = try await learningSituationVersions(id: source.id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            associatedGroupId: nil,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let newId = try await container.learningSituationsRepository.saveSituation(
            situation: LearningSituation(
                id: 0,
                title: "\(source.title) (copia)",
                stageLabel: source.stageLabel,
                courseLabel: source.courseLabel,
                subjectLabel: source.subjectLabel,
                termLabel: source.termLabel,
                centerLabel: source.centerLabel,
                sessionCount: source.sessionCount,
                challenge: source.challenge,
                finalProduct: source.finalProduct,
                payloadJson: source.payloadJson,
                status: .draft,
                trace: trace
            )
        ).int64Value
        if let latest = versions.first {
            _ = try await container.learningSituationsRepository.saveVersion(
                version: LearningSituationVersion(
                    id: 0,
                    learningSituationId: newId,
                    versionNumber: 0,
                    originalFileName: latest.originalFileName,
                    sha256: latest.sha256,
                    localPath: latest.localPath,
                    sizeBytes: latest.sizeBytes,
                    payloadJson: latest.payloadJson,
                    warningsJson: latest.warningsJson,
                    trace: trace
                )
            )
            enqueueLocalChange(
                entity: "learning_situation_version",
                id: "\(newId)-\(latest.sha256)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "learningSituationId": newId,
                    "versionNumber": 1,
                    "originalFileName": latest.originalFileName,
                    "sha256": latest.sha256,
                    "sizeBytes": latest.sizeBytes,
                    "payloadJson": latest.payloadJson,
                    "warningsJson": latest.warningsJson
                ]
            )
        }
        try await container.learningSituationsRepository.replaceClassLinks(
            learningSituationId: newId,
            classIds: classIds.map { KotlinLong(value: $0) }
        )
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(newId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": newId, "title": "\(source.title) (copia)", "stageLabel": source.stageLabel,
                "courseLabel": source.courseLabel, "subjectLabel": source.subjectLabel,
                "termLabel": source.termLabel, "centerLabel": source.centerLabel,
                "sessionCount": source.sessionCount, "challenge": source.challenge,
                "finalProduct": source.finalProduct, "payloadJson": source.payloadJson,
                "status": "DRAFT"
            ]
        )
        for classId in classIds {
            enqueueLocalChange(
                entity: "learning_situation_class_link",
                id: "\(newId)-\(classId)",
                updatedAtEpochMs: nowMs,
                payload: ["learningSituationId": newId, "classId": classId]
            )
        }
        return newId
    }

    func programLearningSituationSessions(
        situation: LearningSituation,
        classId: Int64,
        groupName: String,
        scheduledSlots: [LearningSituationScheduledSlot],
        sequenceDraft: LearningSituationSessionSequenceImportDraft? = nil
    ) async throws {
        guard !scheduledSlots.isEmpty else { return }
        guard !LearningSituationScheduleProjection.hasDuplicateDestinations(scheduledSlots) else {
            throw NSError(
                domain: "LearningSituations",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No se puede programar más de una sesión en la misma fecha y franja. Revisa la previsualización."
                ]
            )
        }
        let detailedPlanIds: [Int: Int64]
        if let sequenceDraft {
            detailedPlanIds = try await persistSessionSequence(situation: situation, draft: sequenceDraft)
        } else {
            detailedPlanIds = [:]
        }
        let orderedDraftPlans = sequenceDraft?.plans.sorted { $0.sessionNumber < $1.sessionNumber } ?? []
        let unitId = try await ensureTeachingUnitForLearningSituation(situation: situation, classId: classId)
        let calendar = Calendar(identifier: .iso8601)
        for (index, slot) in scheduledSlots.enumerated() {
            let detailedDraft: LearningSituationSessionPlanDraft?
            if let planSessionNumber = slot.planSessionNumber {
                detailedDraft = orderedDraftPlans.first(where: { $0.sessionNumber == planSessionNumber })
            } else {
                detailedDraft = index < orderedDraftPlans.count ? orderedDraftPlans[index] : nil
            }
            let components = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear, .weekday], from: slot.date)
            let weekday = ((components.weekday ?? 2) + 5) % 7 + 1
            let weekNumber = components.weekOfYear ?? 1
            let year = components.yearForWeekOfYear ?? Calendar.current.component(.year, from: slot.date)
            let existingSessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
            for (destinationIndex, destination) in slot.destinationSlots.enumerated() {
                let occupiedSession = existingSessions.first {
                    Int($0.dayOfWeek) == weekday && Int($0.period) == destination.period
                }
                let sessionId = try await plannerUpsertSession(
                    id: occupiedSession?.id ?? 0,
                    teachingUnitId: unitId,
                    teachingUnitName: situation.title,
                    teachingUnitColor: plannerCourseColor(for: classId),
                    groupId: classId,
                    groupName: groupName,
                    dayOfWeek: weekday,
                    period: destination.period,
                    weekNumber: weekNumber,
                    year: year,
                    objectives: detailedDraft?.objective ?? situation.challenge,
                    activities: detailedDraft?.developmentSummary ?? "Sesión vinculada a \(situation.title)",
                    evaluation: detailedDraft?.criteria.joined(separator: ", ") ?? "",
                    teacherScheduleSlotId: destination.teacherScheduleSlotId,
                    startTime: destination.startTime.isEmpty ? slot.startTime : destination.startTime,
                    endTime: destination.endTime.isEmpty ? slot.endTime : destination.endTime,
                    learningSituationSessionPlanId: detailedDraft.flatMap { detailedPlanIds[$0.sessionNumber] },
                    status: .planned
                )
                let resourceLabel = destinationIndex == 0 ? slot.label : "\(slot.label) · continuación"
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .planningSession,
                    resourceId: "\(sessionId)",
                    classId: classId,
                    label: resourceLabel,
                    trace: situation.trace
                )
            }
        }
    }

    private func persistSessionSequence(
        situation: LearningSituation,
        draft: LearningSituationSessionSequenceImportDraft
    ) async throws -> [Int: Int64] {
        let existingVersions = try await container.learningSituationsRepository.listSessionSequenceVersions(learningSituationId: situation.id)
        if let identicalVersion = existingVersions.first(where: { $0.sha256 == draft.sha256 }) {
            let existingPlans = try await container.learningSituationsRepository.listSessionPlans(sequenceVersionId: identicalVersion.id)
            for existingPlan in existingPlans {
                guard let importedPlan = draft.plans.first(where: { $0.sessionNumber == Int(existingPlan.sessionNumber) }),
                      let developmentJSON = Self.canonicalDevelopmentJSON(
                          for: importedPlan,
                          sourceSHA256: draft.sha256
                      ) else { continue }
                _ = try await persistDerivedDevelopmentJSON(developmentJSON, for: existingPlan)
            }
            return Dictionary(
                existingPlans.map { (Int($0.sessionNumber), $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        let storedURL = try LearningSituationDocumentStore().persistSourceDocument(from: draft.sourceURL, sha256: draft.sha256)
        let warningsJSON = String(data: try JSONEncoder().encode(draft.warnings), encoding: .utf8) ?? "[]"
        let versionNumber = Int32((existingVersions.first?.versionNumber ?? 0) + 1)
        let versionId = try await container.learningSituationsRepository.saveSessionSequenceVersion(
            version: LearningSituationSessionSequenceVersion(
                id: 0,
                learningSituationId: situation.id,
                versionNumber: versionNumber,
                originalFileName: draft.sourceFileName,
                sha256: draft.sha256,
                localPath: storedURL.path,
                sizeBytes: draft.sizeBytes,
                payloadJson: draft.payloadJSON,
                warningsJson: warningsJSON,
                trace: situation.trace
            )
        ).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation_sequence_version",
            id: "\(situation.id)-\(versionNumber)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": versionId, "learningSituationId": situation.id, "versionNumber": versionNumber,
                "originalFileName": draft.sourceFileName, "sha256": draft.sha256,
                "sizeBytes": draft.sizeBytes, "payloadJson": draft.payloadJSON,
                "warningsJson": warningsJSON
            ]
        )
        var planIds: [Int: Int64] = [:]
        for plan in draft.plans {
            let criteriaJSON = String(data: try JSONEncoder().encode(plan.criteria), encoding: .utf8) ?? "[]"
            let developmentPayload = LearningSituationSessionDevelopmentPayload(
                organisation: plan.organisation,
                coreKnowledge: plan.coreKnowledge,
                assessment: plan.assessment,
                sections: plan.development,
                activities: plan.activities,
                guidingQuestions: plan.guidingQuestions,
                closure: plan.closure,
                visuals: plan.visuals,
                sequenceRoute: plan.sequenceRoute,
                sourceDocumentSHA256: draft.sha256
            )
            let developmentJSON = String(data: try JSONEncoder().encode(developmentPayload), encoding: .utf8) ?? "{}"
            let adaptationsJSON = String(data: try JSONEncoder().encode(plan.adaptations), encoding: .utf8) ?? "[]"
            let planId = try await container.learningSituationsRepository.saveSessionPlan(
                plan: LearningSituationSessionPlan(
                    id: 0,
                    learningSituationId: situation.id,
                    sequenceVersionId: versionId,
                    sessionNumber: Int32(plan.sessionNumber),
                    sourceLabel: plan.sourceLabel,
                    title: plan.title,
                    sessionType: plan.sessionType,
                    effectiveMinutes: Int32(plan.effectiveMinutes),
                    objective: plan.objective,
                    criteriaJson: criteriaJSON,
                    material: plan.material,
                    developmentJson: developmentJSON,
                    adaptationsJson: adaptationsJSON,
                    trace: situation.trace
                )
            ).int64Value
            planIds[plan.sessionNumber] = planId
            enqueueLocalChange(
                entity: "learning_situation_session_plan",
                id: "\(situation.id)-\(versionId)-\(plan.sessionNumber)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "id": planId, "learningSituationId": situation.id, "sequenceVersionId": versionId,
                    "sessionNumber": plan.sessionNumber, "sourceLabel": plan.sourceLabel,
                    "title": plan.title, "sessionType": plan.sessionType,
                    "effectiveMinutes": plan.effectiveMinutes, "objective": plan.objective,
                    "criteriaJson": criteriaJSON, "material": plan.material,
                    "developmentJson": developmentJSON, "adaptationsJson": adaptationsJSON
                ]
            )
        }
        try await uploadLearningSituationDocumentIfPaired(at: storedURL, sha256: draft.sha256)
        return planIds
    }

    func materializeLearningSituationEvaluations(
        situation: LearningSituation,
        classId: Int64,
        proposals: [LearningSituationEvaluationDraft],
        targetTabId: String? = nil
    ) async throws {
        for (index, proposal) in proposals.filter(\.isSelected).enumerated() {
            let code = "SA\(situation.id)-E\(index + 1)"
            let evaluationId = try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: code,
                name: proposal.title,
                type: "Situación de aprendizaje",
                weight: (proposal.weightPercent ?? 0) / 100.0,
                formula: nil,
                rubricId: proposal.rubricId.map { KotlinLong(value: $0) },
                description: situation.title,
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            try await ensureNotebookColumnForEvaluation(classId: classId, evaluationId: evaluationId, title: proposal.title, rubricId: proposal.rubricId, targetTabId: targetTabId)
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: proposal.title,
                trace: situation.trace
            )
        }
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
    }

    func materializeLearningSituationPhysicalTests(
        situation: LearningSituation,
        classId: Int64,
        draft: PhysicalTestsImportDraft,
        targetTabId: String? = nil
    ) async throws {
        guard !draft.testDefinitions.isEmpty else {
            throw NSError(
                domain: "LearningSituations",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "El manifiesto no contiene pruebas físicas."]
            )
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = physicalImportTrace(classId: classId, epochMs: nowMs)
        let assignmentTemplate = draft.assignmentTemplate
        let assignmentId = "pe_assignment_sa\(situation.id)_\(classId)_\(assignmentTemplate.batteryId)"
        let scoreColumnMode = assignmentTemplate.scoreColumnMode && assignmentTemplate.recordScore
        // SaveEvaluationUseCase requires a positive weight. Diagnostic imports
        // remain excluded from the notebook average through their raw columns.
        let physicalEvaluationWeight = 1.0
        let tabId = try await resolveNotebookTargetTabId(classId: classId, preferredTabId: targetTabId)

        var evaluationsByCode = Dictionary(
            (try await container.evaluationsRepository.listClassEvaluations(classId: classId)).map { ($0.code, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        for definition in draft.testDefinitions {
            try await container.physicalTestsRepository.saveDefinition(
                definition: PhysicalTestDefinition(
                    id: definition.id,
                    name: definition.name,
                    capacity: importedPhysicalCapacity(definition.capacity),
                    measurementKind: importedPhysicalMeasurement(definition.measurementKind),
                    unit: definition.unit,
                    higherIsBetter: definition.higherIsBetter,
                    protocol: definition.protocolText,
                    material: "",
                    attempts: Int32(definition.attempts),
                    resultMode: importedPhysicalResultMode(definition.resultMode),
                    trace: trace
                )
            )
        }

        try await container.physicalTestsRepository.saveBattery(
            battery: PhysicalTestBattery(
                id: assignmentTemplate.batteryId,
                name: assignmentTemplate.batteryName,
                description: "Importada desde \(draft.sourceFileName) · \(draft.purpose)",
                defaultCourse: draft.courseNumber.map { KotlinInt(value: Int32($0)) },
                defaultAgeFrom: draft.referenceScales.compactMap(\.ageFrom).min().map { KotlinInt(value: Int32($0)) },
                defaultAgeTo: draft.referenceScales.compactMap(\.ageTo).max().map { KotlinInt(value: Int32($0)) },
                testIds: draft.testDefinitions.map(\.id),
                trace: trace
            )
        )

        for scale in draft.referenceScales {
            let isLinear = scale.scoring?.mode.uppercased() == "LINEAR"
            let persistedRanges: [MiGestorKit.PhysicalTestScaleRange] = isLinear
                ? (scale.scoring?.points ?? []).enumerated().map { index, point in
                    MiGestorKit.PhysicalTestScaleRange(
                        id: point.id ?? "\(scale.id)_point_\(index + 1)",
                        scaleId: scale.id,
                        minValue: KotlinDouble(value: point.value),
                        maxValue: nil,
                        score: point.score,
                        label: scaleLabelOrNil(point.label),
                        sortOrder: Int32(point.sortOrder ?? index)
                    )
                }
                : scale.ranges.map { range in
                    MiGestorKit.PhysicalTestScaleRange(
                        id: range.id,
                        scaleId: scale.id,
                        minValue: range.minValue.map { KotlinDouble(value: $0) },
                        maxValue: range.maxValue.map { KotlinDouble(value: $0) },
                        score: range.score,
                        label: scaleLabelOrNil(range.label),
                        sortOrder: Int32(range.sortOrder)
                    )
                }
            try await container.physicalTestsRepository.saveScale(
                scale: PhysicalTestScale(
                    id: scale.id,
                    testId: scale.testId,
                    name: scale.name,
                    course: scale.course.map { KotlinInt(value: Int32($0)) },
                    ageFrom: scale.ageFrom.map { KotlinInt(value: Int32($0)) },
                    ageTo: scale.ageTo.map { KotlinInt(value: Int32($0)) },
                    sex: scaleLabelOrNil(scale.canonicalSex),
                    batteryId: assignmentTemplate.batteryId,
                    direction: scale.direction == "LOWER_IS_BETTER" ? .lowerIsBetter : .higherIsBetter,
                    ranges: persistedRanges,
                    scoringMode: isLinear ? .linear : .step,
                    scoreRoundTo: scale.scoring?.roundTo.map { KotlinDouble(value: $0) },
                    trace: trace
                )
            )
        }

        let assignment = PhysicalTestAssignment(
            id: assignmentId,
            batteryId: assignmentTemplate.batteryId,
            classId: classId,
            course: draft.courseNumber.map { KotlinInt(value: Int32($0)) },
            ageFrom: draft.referenceScales.compactMap(\.ageFrom).min().map { KotlinInt(value: Int32($0)) },
            ageTo: draft.referenceScales.compactMap(\.ageTo).max().map { KotlinInt(value: Int32($0)) },
            termLabel: scaleLabelOrNil(assignmentTemplate.termLabel),
            dateEpochMs: nowMs,
            rawColumnMode: assignmentTemplate.rawColumnMode,
            scoreColumnMode: scoreColumnMode,
            trace: trace
        )
        try await container.physicalTestsRepository.assignBatteryToClass(assignment: assignment)

        let categories = try await container.notebookRepository.listColumnCategories(classId: classId, tabId: tabId)
        if !categories.contains(where: { $0.id == assignmentId }) {
            let categoryOrder = (categories.map(\.order).max() ?? -1) + 1
            try await container.notebookRepository.saveColumnCategory(
                classId: classId,
                category: NotebookColumnCategory(
                    id: assignmentId,
                    classId: classId,
                    tabId: tabId,
                    name: "\(assignmentTemplate.batteryName) · \(assignmentTemplate.termLabel)",
                    order: categoryOrder,
                    isCollapsed: false,
                    trace: trace
                )
            )
        }

        let existingLinks = try await container.physicalTestsRepository.listNotebookLinksForAssignment(assignmentId: assignmentId)
        let existingColumns = try await container.notebookConfigRepository.listColumns(classId: classId)

        for definition in draft.testDefinitions {
            let code = "EF_\(definition.id.uppercased())"
            let evaluationId: Int64
            if let existingEvaluationId = evaluationsByCode[code] {
                evaluationId = existingEvaluationId
            } else {
                evaluationId = try await createPhysicalTest(
                    classId: classId,
                    code: code,
                    name: definition.name,
                    kind: definition.measurementKind,
                    weight: physicalEvaluationWeight,
                    description: definition.protocolText
                )
                evaluationsByCode[code] = evaluationId
            }

            let existingLink = existingLinks.first { $0.testId == definition.id }
            let rawTitle = "\(definition.name) · Marca"
            let scoreTitle = "\(definition.name) · Nota"
            let rawColumnId: String?
            if assignmentTemplate.rawColumnMode {
                if let existingColumnId = existingLink?.rawColumnId
                    ?? existingColumns.first(where: { $0.title == rawTitle && $0.categoryId == assignmentId })?.id {
                    rawColumnId = existingColumnId
                } else {
                    rawColumnId = try await createNotebookPhysicalColumnForClass(
                        classId: classId,
                        name: rawTitle,
                        categoryId: assignmentId,
                        inputKind: importedPhysicalInputKind(definition.measurementKind),
                        unitOrSituation: "Dato bruto · \(definition.unit)",
                        scaleKind: importedPhysicalScaleKind(definition.measurementKind),
                        iconName: "stopwatch.fill",
                        weight: 0,
                        countsTowardAverage: false,
                        dateEpochMs: nowMs,
                        targetTabId: tabId
                    )
                }
            } else {
                rawColumnId = nil
            }

            let scoreColumnId: String?
            if scoreColumnMode {
                if let existingColumnId = existingLink?.scoreColumnId
                    ?? existingColumns.first(where: { $0.title == scoreTitle && $0.categoryId == assignmentId })?.id {
                    scoreColumnId = existingColumnId
                } else {
                    scoreColumnId = try await createNotebookPhysicalColumnForClass(
                        classId: classId,
                        name: scoreTitle,
                        categoryId: assignmentId,
                        inputKind: .numeric010,
                        unitOrSituation: "Nota baremada",
                        scaleKind: .tenPoint,
                        iconName: "chart.bar.fill",
                        weight: 10,
                        countsTowardAverage: assignmentTemplate.countsTowardAverage && assignmentTemplate.recordScore,
                        dateEpochMs: nowMs,
                        targetTabId: tabId
                    )
                }
            } else {
                scoreColumnId = nil
            }

            if existingLink?.rawColumnId != rawColumnId || existingLink?.scoreColumnId != scoreColumnId {
                try await container.physicalTestsRepository.saveNotebookLink(
                    link: PhysicalTestNotebookLink(
                        assignmentId: assignmentId,
                        testId: definition.id,
                        rawColumnId: rawColumnId,
                        scoreColumnId: scoreColumnId,
                        trace: trace
                    )
                )
            }

            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: definition.name,
                trace: situation.trace
            )
            if let rawColumnId {
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .notebookColumn,
                    resourceId: rawColumnId,
                    classId: classId,
                    label: definition.name,
                    trace: situation.trace
                )
            }
            if let scoreColumnId {
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .notebookColumn,
                    resourceId: scoreColumnId,
                    classId: classId,
                    label: "\(definition.name) · Nota",
                    trace: situation.trace
                )
            }
        }

        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
    }

    private func physicalImportTrace(classId: Int64, epochMs: Int64) -> AuditTrace {
        let instant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: epochMs)
        return AuditTrace(
            authorUserId: nil,
            createdAt: instant,
            updatedAt: instant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 1
        )
    }

    private func scaleLabelOrNil(_ value: String?) -> String? {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
    }

    private func importedPhysicalCapacity(_ value: String) -> PhysicalCapacity {
        switch value {
        case "RESISTANCE": return .resistance
        case "STRENGTH": return .strength
        case "SPEED": return .speed
        case "FLEXIBILITY": return .flexibility
        case "COORDINATION": return .coordination
        case "AGILITY": return .agility
        default: return .custom
        }
    }

    private func importedPhysicalMeasurement(_ value: String) -> PhysicalMeasurementKind {
        switch value {
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        case "LEVEL": return .level
        default: return .score
        }
    }

    private func importedPhysicalResultMode(_ value: String) -> PhysicalResultMode {
        switch value {
        case "AVERAGE": return .average
        case "LAST": return .last
        default: return .best
        }
    }

    private func importedPhysicalInputKind(_ value: String) -> NotebookCellInputKind {
        switch value {
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        default: return .numeric010
        }
    }

    private func importedPhysicalScaleKind(_ value: String) -> NotebookScaleKind {
        switch value {
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        default: return .tenPoint
        }
    }

    func materializeLearningSituationAssessmentInstruments(
        situation: LearningSituation,
        classId: Int64,
        draft: LearningSituationAssessmentImportDraft,
        targetTabId: String? = nil
    ) async throws {
        let selectedInstruments = draft.instruments.filter(\.isSelected)
        guard !selectedInstruments.isEmpty else {
            throw NSError(domain: "LearningSituations", code: 2, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un instrumento."])
        }

        try await repairLearningSituationAssessmentInstrumentImportIfNeeded(classId: classId)

        let existingInstrumentTitles = try await existingLearningSituationAssessmentTitles(
            situationId: situation.id,
            classId: classId
        )
        let instrumentsToCreate = selectedInstruments.filter { instrument in
            !existingInstrumentTitles.contains(normalizedAssessmentInstrumentTitle(instrument.title))
        }
        guard !instrumentsToCreate.isEmpty else { return }

        let teachingUnitId = try await ensureTeachingUnitForLearningSituation(situation: situation, classId: classId)

        for (index, instrument) in instrumentsToCreate.enumerated() {
            let rubricId = try await saveAssessmentInstrumentRubricIfNeeded(
                instrument: instrument,
                classId: classId,
                teachingUnitId: teachingUnitId,
                sourceFileName: draft.sourceFileName
            )
            let evaluationId = try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: "SA\(situation.id)-I\(index + 1)",
                name: instrument.title,
                type: instrument.kind.label,
                weight: (instrument.weightPercent ?? 0) / 100.0,
                formula: nil,
                rubricId: rubricId.map { KotlinLong(value: $0) },
                // El texto real del criterio de evaluacion (buscado por titulo del instrumento en
                // el catalogo de 1r de Batxillerat - EF) es lo que se enseña en el Cuaderno como
                // "Criterio: X". La nota generica de importacion solo se usa cuando el instrumento
                // no esta en ese catalogo (otra materia/curso, o titulo editado a mano).
                description: EvaluationCriteriaReference.shared.criterionStatement(instrumentTitle: instrument.title)
                    ?? "Instrumento importado desde \(draft.sourceFileName) para \(situation.title)",
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            let columnId = try await ensureNotebookColumnForAssessmentInstrument(
                classId: classId,
                evaluationId: evaluationId,
                title: instrument.title,
                rubricId: rubricId,
                instrument: instrument,
                situationTitle: situation.title,
                targetTabId: targetTabId
            )
            if rubricId == nil {
                try await saveAssessmentInstrumentTemplateIfNeeded(
                    instrument: instrument,
                    classId: classId,
                    evaluationId: evaluationId,
                    columnId: columnId,
                    sourceFileName: draft.sourceFileName
                )
            }
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: instrument.title,
                trace: situation.trace
            )
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .notebookColumn,
                resourceId: columnId,
                classId: classId,
                label: instrument.title,
                trace: situation.trace
            )
            if let rubricId {
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .rubric,
                    resourceId: "\(rubricId)",
                    classId: classId,
                    label: "Rubrica · \(instrument.title)",
                    trace: situation.trace
                )
            }
        }
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
    }

    private func existingLearningSituationAssessmentTitles(
        situationId: Int64,
        classId: Int64
    ) async throws -> Set<String> {
        let resources = try await container.learningSituationsRepository.listLinkedResources(learningSituationId: situationId)
        let liveColumnIds = Set(try await container.notebookConfigRepository.listColumns(classId: classId).map(\.id))
        return Set(resources.compactMap { resource in
            guard resource.classId?.int64Value == classId else { return nil }
            guard resource.kind == .notebookColumn else { return nil }
            guard liveColumnIds.contains(resource.resourceId) else { return nil }
            return normalizedAssessmentInstrumentTitle(resource.label)
        })
    }

    private func normalizedAssessmentInstrumentTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    func learningSituationNotebookTabs(for classId: Int64) async throws -> [NotebookTab] {
        try await container.notebookConfigRepository.listTabs(classId: classId)
    }

    func fetchNotebookTabs(for classId: Int64) async throws -> [NotebookTab] {
        try await container.notebookConfigRepository.listTabs(classId: classId)
    }

    func fetchNotebookColumns(for classId: Int64) async throws -> [NotebookColumnDefinition] {
        try await container.notebookConfigRepository.listColumns(classId: classId)
    }

    func clearNotebookForClass(classId: Int64) async throws {
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        for col in columns {
            deleteColumn(id: col.id, evaluationId: col.evaluationId?.int64Value)
        }
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        for tab in tabs {
            deleteTab(id: tab.id)
        }
    }


    func ensureTeachingUnitForLearningSituation(
        situation: LearningSituation,
        classId: Int64
    ) async throws -> Int64 {
        let linkedResources = try await container.learningSituationsRepository.listLinkedResources(learningSituationId: situation.id)
        if let existingResource = linkedResources.first(where: {
            $0.kind == .teachingUnit && ($0.classId == nil || $0.classId?.int64Value == classId)
        }),
           let unitId = Int64(existingResource.resourceId) {
            return unitId
        }

        let existingUnits = try await container.plannerRepository.listAllTeachingUnits()
        if let found = existingUnits.first(where: {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ==
            situation.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) &&
            ($0.schoolClassId?.int64Value == classId || $0.groupId?.int64Value == classId)
        }) {
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .teachingUnit,
                resourceId: "\(found.id)",
                classId: classId,
                label: situation.title,
                trace: situation.trace
            )
            return found.id
        }

        let unit = TeachingUnit(
            id: 0,
            name: situation.title,
            description: "Situación de aprendizaje: \(situation.challenge)",
            colorHex: plannerCourseColor(for: classId),
            groupId: KotlinLong(value: classId),
            schoolClassId: KotlinLong(value: classId),
            startDate: nil,
            endDate: nil
        )
        let unitId = try await container.plannerRepository.upsertTeachingUnit(unit: unit).int64Value
        try await saveLearningSituationLinkedResource(
            situationId: situation.id,
            kind: .teachingUnit,
            resourceId: "\(unitId)",
            classId: classId,
            label: situation.title,
            trace: situation.trace
        )
        return unitId
    }

    func repairLearningSituationAssessmentInstrumentImportIfNeeded(classId: Int64) async throws {
        let repairedLevels = try await repairAssessmentInstrumentRubricLevelPoints(classId: classId)
        let repairedColumns = try await repairAssessmentInstrumentNotebookColumns(classId: classId)
        let repairedEvaluations = try await repairAssessmentInstrumentEvaluations(classId: classId)
        let repairedTemplates = try await repairStructuredAssessmentInstrumentTemplates(classId: classId)
        let repairedRubricUnits = try await repairAssessmentInstrumentRubricTeachingUnits(classId: classId)
        let repairedDescriptions = try await repairCorruptedEvaluationDescriptions(classId: classId)
        let repairedCriteria = try await repairAssessmentInstrumentCriterionDescriptions(classId: classId)
        if repairedLevels || repairedColumns || repairedEvaluations || repairedTemplates || repairedRubricUnits || repairedDescriptions || repairedCriteria {
            refreshCurrentNotebook()
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    private func repairAssessmentInstrumentRubricTeachingUnits(classId: Int64) async throws -> Bool {
        let allSituations = try await container.learningSituationsRepository.listSituations()
        var situations: [LearningSituation] = []
        for candidate in allSituations {
            let links = try await container.learningSituationsRepository.listClassLinks(learningSituationId: candidate.id)
            if links.contains(where: { $0.classId == classId }) {
                situations.append(candidate)
            }
        }
        guard !situations.isEmpty else { return false }

        let rubrics = try await container.rubricsRepository.listRubrics()
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        for situation in situations {
            let teachingUnitId = try await ensureTeachingUnitForLearningSituation(situation: situation, classId: classId)
            let linkedResources = try await container.learningSituationsRepository.listLinkedResources(learningSituationId: situation.id)

            for resource in linkedResources where resource.kind == .rubric {
                guard let rubricId = Int64(resource.resourceId),
                      let detail = rubrics.first(where: { $0.rubric.id == rubricId }),
                      detail.rubric.teachingUnitId?.int64Value != teachingUnitId else { continue }

                _ = try await container.rubricsRepository.saveRubric(
                    id: KotlinLong(value: detail.rubric.id),
                    name: detail.rubric.name,
                    description: detail.rubric.description,
                    classId: detail.rubric.classId ?? KotlinLong(value: classId),
                    teachingUnitId: KotlinLong(value: teachingUnitId),
                    createdAtEpochMs: detail.rubric.trace.createdAt.toEpochMilliseconds(),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: detail.rubric.trace.syncVersion
                )
                didRepair = true
            }

            for resource in linkedResources where resource.kind == .evaluation {
                guard let evaluationId = Int64(resource.resourceId),
                      let ev = evaluations.first(where: { $0.id == evaluationId }),
                      let rubricId = ev.rubricId?.int64Value,
                      let detail = rubrics.first(where: { $0.rubric.id == rubricId }),
                      detail.rubric.teachingUnitId?.int64Value != teachingUnitId else { continue }

                _ = try await container.rubricsRepository.saveRubric(
                    id: KotlinLong(value: detail.rubric.id),
                    name: detail.rubric.name,
                    description: detail.rubric.description,
                    classId: detail.rubric.classId ?? KotlinLong(value: classId),
                    teachingUnitId: KotlinLong(value: teachingUnitId),
                    createdAtEpochMs: detail.rubric.trace.createdAt.toEpochMilliseconds(),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: detail.rubric.trace.syncVersion
                )
                didRepair = true
            }
        }

        if didRepair {
            try? await refreshRubrics()
            try? await refreshRubricClassLinks()
        }
        return didRepair
    }

    private func saveAssessmentInstrumentRubricIfNeeded(
        instrument: AssessmentInstrumentDraft,
        classId: Int64,
        teachingUnitId: Int64? = nil,
        sourceFileName: String
    ) async throws -> Int64? {
        guard instrument.kind == .rubric else { return nil }
        guard let rubric = instrument.rubric, !rubric.criteria.isEmpty, !rubric.levels.isEmpty else {
            return nil
        }
        let existingRubrics = try await container.rubricsRepository.listRubrics()
        if let matching = existingRubrics.first(where: {
            $0.rubric.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ==
            instrument.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }) {
            return matching.rubric.id
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rubricId = try await container.rubricsRepository.saveRubric(
            id: nil,
            name: instrument.title,
            description: "Importada desde \(sourceFileName)",
            classId: KotlinLong(value: classId),
            teachingUnitId: teachingUnitId.map { KotlinLong(value: $0) },
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value

        for (criterionIndex, criterion) in rubric.criteria.enumerated() {
            let criterionId = try await container.rubricsRepository.saveCriterion(
                id: nil,
                rubricId: rubricId,
                description: criterion.title,
                weight: criterion.weight,
                order: Int32(criterionIndex),
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            for (levelIndex, level) in rubric.levels.enumerated() {
                let description = levelIndex < criterion.descriptors.count
                    ? criterion.descriptors[levelIndex].nilIfBlank
                    : nil
                _ = try await container.rubricsRepository.saveLevel(
                    id: nil,
                    criterionId: criterionId,
                    name: level.label,
                    points: Int32(level.points),
                    description: description,
                    order: Int32(levelIndex),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: 1
                )
            }
        }
        try? await refreshRubrics()
        try? await refreshRubricClassLinks()
        return rubricId
    }

    private func saveAssessmentInstrumentTemplateIfNeeded(
        instrument: AssessmentInstrumentDraft,
        classId: Int64,
        evaluationId: Int64,
        columnId: String,
        sourceFileName: String
    ) async throws {
        let items = assessmentInstrumentItems(for: instrument, columnId: columnId)
        guard !items.isEmpty else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let template = NotebookInstrumentTemplate(
            id: "template_\(columnId)",
            classId: classId,
            columnId: columnId,
            evaluationId: KotlinLong(value: evaluationId),
            title: instrument.title,
            kind: templateKind(for: instrument.kind),
            inputKind: structuredInputKind(for: instrument.kind),
            source: sourceFileName,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: nowInstant,
                updatedAt: nowInstant,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            )
        )
        try await container.notebookInstrumentsRepository.saveTemplate(template: template, items: items)
    }
    private func ensureNotebookColumnForAssessmentInstrument(
        classId: Int64,
        evaluationId: Int64,
        title: String,
        rubricId: Int64?,
        instrument: AssessmentInstrumentDraft,
        situationTitle: String,
        targetTabId: String?
    ) async throws -> String {
        if let existingColumnId = try await container.notebookRepository.getColumnIdForEvaluation(evaluationId: evaluationId) {
            return existingColumnId
        }
        let targetTabId = try await resolveNotebookTargetTabId(classId: classId, preferredTabId: targetTabId)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let resolvedWeight = instrument.weightPercent ?? 0
        let columnId = "eval_\(evaluationId)"
        let column = NotebookColumnDefinition(
            id: columnId,
            title: title,
            type: notebookColumnType(for: instrument, rubricId: rubricId),
            categoryKind: .evaluation,
            instrumentKind: notebookInstrumentKind(for: instrument.kind),
            inputKind: notebookInputKind(for: instrument, rubricId: rubricId),
            evaluationId: KotlinLong(value: evaluationId),
            rubricId: rubricId.map { KotlinLong(value: $0) },
            formula: nil,
            weight: resolvedWeight,
            dateEpochMs: nil,
            unitOrSituation: situationTitle,
            competencyCriteriaIds: [],
            scaleKind: notebookScaleKind(for: instrument, rubricId: rubricId),
            tabIds: [targetTabId],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: -1,
            widthDp: 132,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: instrument.countsTowardAverage &&
                resolvedWeight > 0 &&
                canMaterializeAverage(for: instrument.scoreStrategy),
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: notebookEmptyCellPolicy(for: instrument.emptyCellPolicy),
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: nowInstant,
                updatedAt: nowInstant,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            )
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        return columnId
    }

    func resolveNotebookTargetTabId(classId: Int64, preferredTabId: String?) async throws -> String {
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        if let preferredTabId, tabs.contains(where: { $0.id == preferredTabId }) {
            return preferredTabId
        }
        if let candidateTitle = preferredTabId?.trimmingCharacters(in: .whitespacesAndNewlines), !candidateTitle.isEmpty {
            if let match = tabs.first(where: { $0.title.caseInsensitiveCompare(candidateTitle) == .orderedSame }) {
                return match.id
            }
            let createdTitle = try await container.notebookRepository.createTab(classId: classId, tabName: candidateTitle)
            let refreshedTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
            return refreshedTabs.first(where: { $0.title.caseInsensitiveCompare(createdTitle) == .orderedSame })?.id ?? refreshedTabs.first?.id ?? "TAB_\(classId)"
        }
        if let first = tabs.first?.id {
            return first
        }
        let createdTitle = try await container.notebookRepository.createTab(classId: classId, tabName: "Evaluación")
        let refreshedTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        return refreshedTabs.first(where: { $0.title == createdTitle })?.id ?? refreshedTabs.first?.id ?? "TAB_\(classId)"
    }

    private func templateKind(for kind: AssessmentInstrumentKind) -> NotebookInstrumentTemplateKind {
        switch kind {
        case .checklist, .submissionChecklist:
            return .checklist
        case .teacherObservation:
            return .observation
        case .observationGrid:
            return .form
        case .rubric:
            return .form
        case .quizQuestions:
            return .quiz
        case .selfAssessment, .peerAssessment:
            return .form
        }
    }

    private func structuredInputKind(for kind: AssessmentInstrumentKind) -> NotebookCellInputKind {
        switch kind {
        case .checklist, .submissionChecklist:
            return .structuredChecklist
        case .teacherObservation:
            return .structuredObservation
        case .observationGrid:
            return .structuredForm
        case .rubric:
            return .structuredForm
        case .quizQuestions:
            return .structuredQuiz
        case .selfAssessment, .peerAssessment:
            return .structuredForm
        }
    }

    private func assessmentInstrumentItems(for instrument: AssessmentInstrumentDraft, columnId: String) -> [NotebookInstrumentItem] {
        let normalizedTitle = instrument.title.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalizedTitle == "daily workout log" {
            var specs: [(String, String, NotebookInstrumentItemType, [String])] = []
            for index in 1...4 {
                specs.append(("exercise_\(index)_level", "Ejercicio \(index) · Nivel", .text, []))
                specs.append(("exercise_\(index)_volume", "Ejercicio \(index) · Volumen / reps", .text, []))
                specs.append(("exercise_\(index)_rpe", "Ejercicio \(index) · RPE 1-10", .number, []))
                specs.append(("exercise_\(index)_safe", "Ejercicio \(index) · Técnica segura", .choice, ["Yes", "No"]))
                specs.append(("exercise_\(index)_coach_note", "Ejercicio \(index) · Nota del coach", .text, []))
            }
            specs.append(("peak_hr", "Peak radial HR (6 seconds x 10)", .number, []))
            specs.append(("hr_after_1_min", "Radial HR after 1 minute", .number, []))
            specs.append(("net_recovery", "Net recovery", .number, []))
            specs.append(("coach_signature", "Coach signature", .text, []))
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        if normalizedTitle == "diagnostic record sheet - session 1" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("adapted_pushups", "Adapted push-ups 1'", .number, []),
                ("sit_and_reach", "Sit-and-reach", .text, []),
                ("resting_radial_hr", "Resting radial HR", .number, []),
                ("goal_chosen", "Goal chosen", .choice, ["Strength", "Cardio"]),
                ("initial_observation", "Initial observation", .text, []),
            ])
        }

        if normalizedTitle == "teacher observation grid ce 2.2 - execution and self-regulation" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("technique", "Technique", .scale14, []),
                ("rpe_target", "RPE target", .scale14, []),
                ("reliable_log", "Reliable log", .scale14, []),
                ("intensity_adjustment", "Intensity adjustment", .scale14, []),
                ("motor_engagement", "Motor engagement", .scale14, []),
                ("mark", "Mark", .number, []),
            ])
        }

        if normalizedTitle == "adjustment sheet - session 7" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("compared_data", "Compared data: HR / reps / RPE / recovery", .text, []),
                ("change_applied", "Change applied", .choice, ["+10% volume", "shorter rest", "level change", "other"]),
                ("reason", "Reason", .text, []),
                ("technique_safe", "Is technique still safe?", .choice, ["Yes", "Needs adaptation"]),
            ])
        }

        if normalizedTitle == "healthy habits quiz - session 8" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("hydration", "Best hydration option for normal PE", .choice, ["water", "energy drink", "soft drink"]),
                ("sleep", "Recommended sleep duration for teenagers", .text, []),
                ("protein_shakes", "Protein shakes are necessary for every active teenager", .choice, ["True", "False"]),
                ("water_estimate", "Estimate daily water for 60 kg: 60 / 30", .number, []),
                ("caffeine_effect", "A high-caffeine, high-sugar drink before PE may affect", .choice, ["sleep", "HR", "hydration habits", "all"]),
            ])
        }

        if normalizedTitle == "quiz de cierre del rol coach y pasaporte saludable" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("coach_registro", "He registrado tiempos, repeticiones o RPE de forma responsable.", .scale14, []),
                ("coach_seguridad", "He observado la técnica y he avisado con respeto ante riesgos o ajustes necesarios.", .scale14, []),
                ("coach_feedback", "He ofrecido un feedback concreto, respetuoso y útil a mi compañero/a.", .scale14, []),
                ("coach_cooperacion", "He cumplido mi rol y he colaborado para que ambos pudiéramos entrenar con seguridad.", .scale14, []),
                ("proximo_paso", "Identifico un ajuste realista para mejorar como deportista o como Coach.", .scale14, []),
                ("evidencia_feedback", "Describe el mejor feedback que diste o recibiste. ¿Qué ocurrió y por qué fue útil?", .text, []),
                ("compromiso", "¿Qué acción concreta aplicarás en tu próxima práctica?", .text, []),
            ])
        }

        // Instrumento mixto que rellena el alumnado: los indicadores de la rúbrica van con clave
        // `rub_<n>` y escala 1-4 (de ahí deriva la nota `NotebookInstrumentsRepositorySqlDelight`)
        // y las preguntas de reflexión con clave `open_<n>`, que no intervienen en la nota.
        if instrument.kind.isStudentAuthored {
            var specs: [(String, String, NotebookInstrumentItemType, [String])] = []
            var helpTextByKey: [String: String] = [:]
            for (index, criterion) in (instrument.rubric?.criteria ?? []).enumerated() {
                let key = "rub_\(index + 1)"
                specs.append((key, criterion.title, .scale14, []))
                // La plantilla del Cuaderno no guarda etiquetas por nivel, así que los cuatro
                // descriptores de la rúbrica viajan en el texto de ayuda: es lo que ve el
                // alumnado al responder, también en el formulario web publicado.
                let descriptors = zip(instrument.rubric?.levels ?? [], criterion.descriptors)
                    .map { level, descriptor in "\(level.label): \(descriptor)" }
                    .joined(separator: " · ")
                if !descriptors.isEmpty { helpTextByKey[key] = descriptors }
            }
            for (index, question) in instrument.quizQuestions.enumerated() {
                let itemType: NotebookInstrumentItemType = question.options.isEmpty ? .text : .choice
                specs.append(("open_\(index + 1)", question.questionText, itemType, question.options))
            }
            return makeInstrumentItems(columnId: columnId, specs: specs, helpTextByKey: helpTextByKey)
        }

        if !instrument.checklistItems.isEmpty {
            // La checklist ponderada usa el prefijo de clave `chkp_` para que
            // `NotebookInstrumentsRepositorySqlDelight.saveResponses` derive su nota
            // proporcional (ítems marcados / total × 10). Las checklists de requisito de
            // entrega y las de todo/nada mantienen `check_` y no generan nota automática.
            let keyPrefix = instrument.scoreStrategy == .checklistProportional ? "chkp" : "check"
            let specs = instrument.checklistItems.enumerated().map { index, item in
                ("\(keyPrefix)_\(index + 1)", item.title, NotebookInstrumentItemType.check, [] as [String])
            }
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        if !instrument.observationFields.isEmpty {
            let specs = instrument.observationFields.enumerated().map { index, field in
                (field.key ?? "field_\(index + 1)", field.title, NotebookInstrumentItemType.scale14, [] as [String])
            }
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        if !instrument.quizQuestions.isEmpty {
            let specs = instrument.quizQuestions.enumerated().map { index, question -> (String, String, NotebookInstrumentItemType, [String]) in
                let itemType: NotebookInstrumentItemType = question.options.isEmpty ? .text : .choice
                return ("question_\(index + 1)", question.questionText, itemType, question.options)
            }
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        return []
    }

    private func makeInstrumentItems(
        columnId: String,
        specs: [(String, String, NotebookInstrumentItemType, [String])],
        helpTextByKey: [String: String] = [:]
    ) -> [NotebookInstrumentItem] {
        let templateId = "template_\(columnId)"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        return specs.enumerated().map { index, spec in
            NotebookInstrumentItem(
                id: "\(templateId)_\(spec.0)",
                templateId: templateId,
                key: spec.0,
                title: spec.1,
                type: spec.2,
                options: spec.3,
                required: true,
                order: Int32(index),
                helpText: helpTextByKey[spec.0],
                trace: AuditTrace(
                    authorUserId: nil,
                    createdAt: nowInstant,
                    updatedAt: nowInstant,
                    associatedGroupId: nil,
                    deviceId: localDeviceId,
                    syncVersion: 1
                )
            )
        }
    }
    private func repairAssessmentInstrumentRubricLevelPoints(classId: Int64) async throws -> Bool {
        let targetNames: Set<String> = ["Plan Design Rubric", "Peer-Coaching Rubric"]
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let importedRubrics = try await container.rubricsRepository.listRubrics().filter { detail in
            targetNames.contains(detail.rubric.name) && detail.rubric.classId?.int64Value == classId
        }
        var didRepair = false
        for detail in importedRubrics {
            for criterion in detail.criteria {
                for level in criterion.levels {
                    let expectedPoints = level.order + 1
                    guard level.points != expectedPoints else { continue }
                    _ = try await container.rubricsRepository.saveLevel(
                        id: KotlinLong(value: level.id),
                        criterionId: level.criterionId,
                        name: level.name,
                        points: Int32(expectedPoints),
                        description: level.description,
                        order: Int32(level.order),
                        updatedAtEpochMs: nowMs,
                        deviceId: localDeviceId,
                        syncVersion: level.trace.syncVersion
                    )
                    didRepair = true
                }
            }
        }
        if didRepair {
            try? await refreshRubrics()
            try? await refreshRubricClassLinks()
        }
        return didRepair
    }

    private func repairAssessmentInstrumentNotebookColumns(classId: Int64) async throws -> Bool {
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        var didRepair = false

        for column in columns {
            // Rejilla de observación con nota derivada de respuestas 1-4 (ver
            // notebookInputKind/deriveObservationGridScore): ya está en el estado correcto
            // (numérica, computable) aunque tenga una plantilla estructurada asociada. Sin
            // este guard, la rama genérica de más abajo la degradaría a .text/.custom
            // (auxiliar sin nota) en cuanto detectara esa plantilla.
            if column.type == .numeric, column.scaleKind == .fourLevel {
                continue
            }

            var repairType = column.type
            var repairInstrumentKind = column.instrumentKind
            var repairInputKind = column.inputKind
            var repairScaleKind = column.scaleKind

            if let repair = assessmentInstrumentColumnRepair(for: column.title) {
                repairType = repair.type
                repairInstrumentKind = repair.instrumentKind
                repairInputKind = repair.inputKind
                repairScaleKind = repair.scaleKind
            } else if let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id) {
                repairType = .text
                repairScaleKind = .custom
                
                let templateInputKind = detail.template_.inputKind
                repairInputKind = templateInputKind
                
                switch detail.template_.kind {
                case .checklist:
                    repairInstrumentKind = .checklist
                case .observation:
                    repairInstrumentKind = .systematicObservation
                case .form:
                    if templateInputKind == NotebookCellInputKind.structuredQuiz {
                        repairInstrumentKind = .checklist
                    } else {
                        repairInstrumentKind = .dailyWork
                    }
                default:
                    break
                }
            }

            guard column.type != repairType ||
                    column.instrumentKind != repairInstrumentKind ||
                    column.inputKind != repairInputKind ||
                    column.scaleKind != repairScaleKind else {
                continue
            }

            let repaired = NotebookColumnDefinition(
                id: column.id,
                title: column.title,
                type: repairType,
                categoryKind: .evaluation,
                instrumentKind: repairInstrumentKind,
                inputKind: repairInputKind,
                evaluationId: column.evaluationId,
                rubricId: nil,
                formula: column.formula,
                weight: column.weight,
                dateEpochMs: column.dateEpochMs,
                unitOrSituation: column.unitOrSituation,
                competencyCriteriaIds: column.competencyCriteriaIds,
                scaleKind: repairScaleKind,
                tabIds: column.tabIds,
                sessions: column.sessions,
                sharedAcrossTabs: column.sharedAcrossTabs,
                colorHex: column.colorHex,
                iconName: column.iconName,
                order: Int32(column.order),
                widthDp: column.widthDp,
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
                trace: AuditTrace(
                    authorUserId: nil,
                    createdAt: column.trace.createdAt,
                    updatedAt: nowInstant,
                    associatedGroupId: KotlinLong(value: classId),
                    deviceId: localDeviceId,
                    syncVersion: column.trace.syncVersion
                )
            )
            try await container.notebookConfigRepository.saveColumn(classId: classId, column: repaired)
            didRepair = true
        }
        return didRepair
    }

    private func repairStructuredAssessmentInstrumentTemplates(classId: Int64) async throws -> Bool {
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        var didRepair = false

        for column in columns {
            guard let instrument = importedAssessmentInstrumentDraft(for: column.title) else { continue }
            let existing = try await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id)
            guard existing == nil else { continue }
            try await saveAssessmentInstrumentTemplateIfNeeded(
                instrument: instrument,
                classId: classId,
                evaluationId: column.evaluationId?.int64Value ?? 0,
                columnId: column.id,
                sourceFileName: "instrumentos_evaluacion.docx"
            )
            didRepair = true
        }

        return didRepair
    }

    private func importedAssessmentInstrumentDraft(for title: String) -> AssessmentInstrumentDraft? {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Daily Workout Log":
            return repairAssessmentInstrumentDraft(title: title, kind: .observationGrid, criterionLabel: "CE 2.2")
        case "Diagnostic Record Sheet - Session 1":
            return repairAssessmentInstrumentDraft(title: title, kind: .observationGrid)
        case "Plan Safety Checklist - Session 2":
            return repairAssessmentInstrumentDraft(
                title: title,
                kind: .checklist,
                checklistItems: [
                    ChecklistItemDraft(title: "The 4 exercises have bronze/silver/gold levels.", required: true),
                    ChecklistItemDraft(title: "Technique can be performed without pain or obvious risk.", required: true),
                    ChecklistItemDraft(title: "Target RPE stays between 5 and 7 for the main part.", required: true),
                    ChecklistItemDraft(title: "Warm-up and cool-down are included.", required: true),
                    ChecklistItemDraft(title: "Rest time allows safe technique.", required: true),
                    ChecklistItemDraft(title: "The teacher has reviewed any doubtful or risky plan.", required: true),
                ]
            )
        case "Teacher Observation Grid CE 2.2 - Execution and self-regulation":
            return repairAssessmentInstrumentDraft(title: title, kind: .teacherObservation, criterionLabel: "CE 2.2")
        case "Adjustment Sheet - Session 7":
            return repairAssessmentInstrumentDraft(title: title, kind: .checklist)
        case "Healthy Habits Quiz - Session 8":
            return repairAssessmentInstrumentDraft(title: title, kind: .checklist)
        case "Quiz de cierre del rol Coach y Pasaporte Saludable":
            return repairAssessmentInstrumentDraft(
                title: title,
                kind: .quizQuestions,
                criterionLabel: "CE 3.2",
                quizQuestions: [
                    QuizQuestionDraft(questionText: "He registrado tiempos, repeticiones o RPE de forma responsable.", options: []),
                    QuizQuestionDraft(questionText: "He observado la técnica y he avisado con respeto ante riesgos o ajustes necesarios.", options: []),
                    QuizQuestionDraft(questionText: "He ofrecido un feedback concreto, respetuoso y útil a mi compañero/a.", options: []),
                    QuizQuestionDraft(questionText: "He cumplido mi rol y he colaborado para que ambos pudiéramos entrenar con seguridad.", options: []),
                    QuizQuestionDraft(questionText: "Identifico un ajuste realista para mejorar como deportista o como Coach.", options: []),
                    QuizQuestionDraft(questionText: "Describe el mejor feedback que diste o recibiste. ¿Qué ocurrió y por qué fue útil?", options: []),
                    QuizQuestionDraft(questionText: "¿Qué acción concreta aplicarás en tu próxima práctica?", options: []),
                ]
            )
        case "Final Submission Checklist":
            return repairAssessmentInstrumentDraft(
                title: title,
                kind: .submissionChecklist,
                checklistItems: [
                    ChecklistItemDraft(title: "Baseline diagnosis complete.", required: true),
                    ChecklistItemDraft(title: "FITT-PV plan validated.", required: true),
                    ChecklistItemDraft(title: "Logs for S3, S4, S5, S6, S7 and S9.", required: true),
                    ChecklistItemDraft(title: "Session 7 adjustment explained.", required: true),
                    ChecklistItemDraft(title: "Habits quiz completed.", required: true),
                    ChecklistItemDraft(title: "Peer Coach assessment signed.", required: true),
                    ChecklistItemDraft(title: "Final self-assessment complete.", required: true),
                ]
            )
        default:
            return nil
        }
    }

    private func repairAssessmentInstrumentDraft(
        title: String,
        kind: AssessmentInstrumentKind,
        criterionLabel: String? = nil,
        checklistItems: [ChecklistItemDraft] = [],
        quizQuestions: [QuizQuestionDraft] = []
    ) -> AssessmentInstrumentDraft {
        AssessmentInstrumentDraft(
            title: title,
            kind: kind,
            criterionLabel: criterionLabel,
            weightPercent: nil,
            isSelected: true,
            countsTowardAverage: false,
            scoreStrategy: .none,
            rubric: nil,
            checklistItems: checklistItems,
            quizQuestions: quizQuestions
        )
    }

    private func repairAssessmentInstrumentEvaluations(classId: Int64) async throws -> Bool {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        for evaluation in evaluations {
            let currentRubricId = evaluation.rubricId?.int64Value
            let targetRepair = assessmentInstrumentColumnRepair(for: evaluation.name)
            let shouldClearImportedRubric = targetRepair != nil && targetRepair?.type != .rubric && currentRubricId != nil
            let shouldClearZeroRubric = currentRubricId == 0
            guard shouldClearImportedRubric || shouldClearZeroRubric else { continue }
            _ = try await container.evaluationsRepository.saveEvaluation(
                id: KotlinLong(value: evaluation.id),
                classId: classId,
                code: evaluation.code,
                name: evaluation.name,
                type: evaluation.type,
                weight: evaluation.weight,
                formula: evaluation.formula,
                rubricId: nil,
                description: evaluation.description_,
                authorUserId: evaluation.trace.authorUserId,
                createdAtEpochMs: evaluation.trace.createdAt.toEpochMilliseconds(),
                updatedAtEpochMs: 0,
                associatedGroupId: evaluation.trace.associatedGroupId,
                deviceId: localDeviceId,
                syncVersion: evaluation.trace.syncVersion
            )
            didRepair = true
        }
        return didRepair
    }

    private struct AssessmentInstrumentColumnRepair {
        let type: NotebookColumnType
        let instrumentKind: NotebookInstrumentKind
        let inputKind: NotebookCellInputKind
        let scaleKind: NotebookScaleKind
    }

    private func assessmentInstrumentColumnRepair(for title: String) -> AssessmentInstrumentColumnRepair? {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Plan Design Rubric", "Peer-Coaching Rubric":
            return AssessmentInstrumentColumnRepair(type: .rubric, instrumentKind: .rubric, inputKind: .rubric, scaleKind: .tenPoint)
        case "Daily Workout Log", "Diagnostic Record Sheet - Session 1":
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .dailyWork, inputKind: .structuredForm, scaleKind: .custom)
        case "Plan Safety Checklist - Session 2", "Adjustment Sheet - Session 7", "Healthy Habits Quiz - Session 8":
            let inputKind: NotebookCellInputKind = title == "Healthy Habits Quiz - Session 8" ? .structuredQuiz : (title == "Adjustment Sheet - Session 7" ? .structuredForm : .structuredChecklist)
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .checklist, inputKind: inputKind, scaleKind: .custom)
        case "Final Submission Checklist":
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .finalProduct, inputKind: .structuredChecklist, scaleKind: .custom)
        case "Teacher Observation Grid CE 2.2 - Execution and self-regulation":
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .systematicObservation, inputKind: .structuredObservation, scaleKind: .custom)
        default:
            return nil
        }
    }

    private func notebookColumnType(for instrument: AssessmentInstrumentDraft, rubricId: Int64?) -> NotebookColumnType {
        if rubricId != nil { return .rubric }
        switch instrument.scoreStrategy {
        case .numeric0To10, .observationScale1To4:
            return .numeric
        case .checklistAllOrNothing:
            return .check
        case .rubric:
            return .numeric
        case .quizPercentCorrect:
            return .numeric
        // La checklist ponderada materializa nota 0-10 derivada de los ítems marcados, así que
        // su columna es numérica como la de la rejilla de observación (la entrada sigue siendo
        // la checklist estructurada).
        case .checklistProportional:
            return .numeric
        case .none:
            return .text
        }
    }

    private func canMaterializeAverage(for strategy: AssessmentInstrumentScoreStrategy) -> Bool {
        switch strategy {
        case .numeric0To10, .rubric, .checklistAllOrNothing, .observationScale1To4,
             .quizPercentCorrect, .checklistProportional:
            return true
        case .none:
            return false
        }
    }

    private func notebookInstrumentKind(for kind: AssessmentInstrumentKind) -> NotebookInstrumentKind {
        switch kind {
        case .rubric:
            return .rubric
        case .observationGrid:
            return .dailyWork
        case .checklist:
            return .checklist
        case .teacherObservation:
            return .systematicObservation
        case .submissionChecklist:
            return .finalProduct
        case .quizQuestions:
            return .writtenTest
        case .selfAssessment:
            return .selfAssessment
        case .peerAssessment:
            return .peerAssessment
        }
    }

    private func notebookInputKind(for instrument: AssessmentInstrumentDraft, rubricId: Int64?) -> NotebookCellInputKind {
        if rubricId != nil { return .rubric }
        switch instrument.scoreStrategy {
        case .numeric0To10:
            return .numeric010
        case .observationScale1To4:
            // La rejilla tiene una plantilla estructurada (sesiones × indicadores 1-4) con
            // nota derivada calculada en NotebookInstrumentsRepositorySqlDelight.saveResponses:
            // abre el sheet estructurado en vez de una casilla numérica manual. El tipo de
            // columna sigue siendo .numeric (ver notebookColumnType) para que cuente en la media.
            return .structuredObservation
        case .checklistAllOrNothing:
            return .check
        case .rubric:
            return .numeric010
        case .quizPercentCorrect:
            return .percentage
        case .checklistProportional, .none:
            break
        }
        switch instrument.kind {
        case .checklist, .submissionChecklist:
            return .structuredChecklist
        case .teacherObservation:
            return .structuredObservation
        case .observationGrid:
            return .structuredForm
        case .rubric:
            return .numeric010
        case .quizQuestions:
            return .structuredQuiz
        case .selfAssessment, .peerAssessment:
            return .structuredForm
        }
    }

    private func notebookScaleKind(for instrument: AssessmentInstrumentDraft, rubricId: Int64?) -> NotebookScaleKind {
        if rubricId != nil { return .tenPoint }
        switch instrument.scoreStrategy {
        case .numeric0To10, .rubric:
            return .tenPoint
        case .observationScale1To4:
            return .fourLevel
        case .checklistAllOrNothing:
            return .yesNo
        case .quizPercentCorrect:
            return .percentage
        // Nota derivada 0-10 (ítems marcados / total × 10).
        case .checklistProportional:
            return .tenPoint
        case .none:
            return .custom
        }
    }

    private func notebookEmptyCellPolicy(for policy: AssessmentInstrumentEmptyCellPolicy) -> NotebookEmptyCellPolicy {
        switch policy {
        case .excludeFromAverage:
            return .excludeFromAverage
        case .countAsZero:
            return .countAsZero
        }
    }

    private func saveLearningSituationLinkedResource(
        situationId: Int64,
        kind: LearningSituationResourceKind,
        resourceId: String,
        classId: Int64?,
        label: String,
        trace: AuditTrace
    ) async throws {
        _ = try await container.learningSituationsRepository.saveLinkedResource(
            resource: LearningSituationLinkedResource(
                id: 0,
                learningSituationId: situationId,
                kind: kind,
                resourceId: resourceId,
                classId: classId.map { KotlinLong(value: $0) },
                label: label,
                trace: trace
            )
        )
        enqueueLocalChange(
            entity: "learning_situation_link",
            id: "\(situationId)-\(kind.name)-\(resourceId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "learningSituationId": situationId,
                "kind": kind.name,
                "resourceId": resourceId,
                "classId": classId ?? NSNull(),
                "label": label
            ]
        )
    }

    private func learningSituationSyncPayload(id: Int64, draft: LearningSituationImportDraft) -> [String: Any] {
        [
            "id": id, "title": draft.title, "stageLabel": draft.stageLabel,
            "courseLabel": draft.courseLabel, "subjectLabel": draft.subjectLabel,
            "termLabel": draft.termLabel, "centerLabel": draft.centerLabel,
            "sessionCount": draft.sessionCount, "challenge": draft.challenge,
            "finalProduct": draft.finalProduct, "payloadJson": draft.payloadJSON,
            "status": "ACTIVE"
        ]
    }

    private func uploadLearningSituationDocumentIfPaired(at url: URL, sha256: String) async throws {
        guard let host = pairedSyncHost, let token = syncToken else { return }
        try await lanSyncClient.uploadDocument(
            host: host,
            token: token,
            sha256: sha256,
            fileURL: url,
            pinnedFingerprint: pairedServerFingerprint
        )
    }

    func downloadLearningSituationDocumentIfNeeded(sha256: String) async -> String? {
        let store = LearningSituationDocumentStore()
        let destination = store.directoryURL.appendingPathComponent("\(sha256).docx")
        if let existing = try? Data(contentsOf: destination) {
            let actualHash = SHA256.hash(data: existing).map { String(format: "%02x", $0) }.joined()
            if actualHash == sha256 { return destination.path }
        }
        guard let host = pairedSyncHost, let token = syncToken else { return nil }
        do {
            try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
            let data = try await lanSyncClient.downloadDocument(
                host: host,
                token: token,
                sha256: sha256,
                pinnedFingerprint: pairedServerFingerprint
            )
            let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualHash == sha256 else { return nil }
            try data.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            return nil
        }
    }

    func loadPhysicalTests(classId: Int64) async throws -> [PhysicalTestSnapshot] {
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)

        let physicalEvaluations = evaluations.filter { evaluation in
            let normalized = "\(evaluation.type) \(evaluation.name) \(evaluation.description_ ?? "")".lowercased()
            return normalized.contains("physical")
                || normalized.contains("física")
                || normalized.contains("fisica")
                || normalized.contains("prueba")
                || normalized.contains("test")
        }

        return physicalEvaluations.map { evaluation in
            let evaluationGrades = grades.filter { $0.evaluationId?.int64Value == evaluation.id }
            let gradesByStudent = Dictionary(
                evaluationGrades.map { ($0.studentId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let results = students.map { student in
                let grade = gradesByStudent[student.id]
                return PhysicalTestSnapshot.StudentResult(
                    id: student.id,
                    student: student,
                    gradeId: grade?.id,
                    value: grade?.value?.doubleValue
                )
            }
            let numericValues = results.compactMap(\.value)
            let average = numericValues.isEmpty ? 0 : numericValues.reduce(0, +) / Double(numericValues.count)
            return PhysicalTestSnapshot(
                evaluation: evaluation,
                results: results,
                average: average,
                best: numericValues.max(),
                recordedCount: numericValues.count
            )
        }
        .sorted { lhs, rhs in
            lhs.evaluation.name.localizedCaseInsensitiveCompare(rhs.evaluation.name) == .orderedAscending
        }
    }

    func listPhysicalDefinitions() async throws -> [PhysicalTestDefinition] {
        try await container.physicalTestsRepository.listDefinitions()
    }

    func savePhysicalDefinition(_ definition: PhysicalTestDefinition) async throws {
        try await container.physicalTestsRepository.saveDefinition(definition: definition)
    }

    func listPhysicalBatteries() async throws -> [PhysicalTestBattery] {
        try await container.physicalTestsRepository.listBatteries()
    }

    func savePhysicalBattery(_ battery: PhysicalTestBattery) async throws {
        try await container.physicalTestsRepository.saveBattery(battery: battery)
    }

    func assignPhysicalBatteryToClass(_ assignment: PhysicalTestAssignment) async throws {
        try await container.physicalTestsRepository.assignBatteryToClass(assignment: assignment)
    }

    func listPhysicalAssignmentsForClass(classId: Int64) async throws -> [PhysicalTestAssignment] {
        try await container.physicalTestsRepository.listAssignmentsForClass(classId: classId)
    }

    func listPhysicalScalesForTest(testId: String) async throws -> [PhysicalTestScale] {
        try await container.physicalTestsRepository.listScalesForTest(testId: testId)
    }

    func savePhysicalScale(_ scale: PhysicalTestScale) async throws {
        try await container.physicalTestsRepository.saveScale(scale: scale)
    }

    func resolvePhysicalScale(
        testId: String,
        course: Int?,
        age: Int?,
        sex: String?,
        batteryId: String?
    ) async throws -> PhysicalTestScale? {
        try await container.physicalTestsRepository.resolveScale(
            testId: testId,
            course: course.map { KotlinInt(value: Int32($0)) },
            age: age.map { KotlinInt(value: Int32($0)) },
            sex: sex,
            batteryId: batteryId
        )
    }

    func savePhysicalNotebookLink(_ link: PhysicalTestNotebookLink) async throws {
        try await container.physicalTestsRepository.saveNotebookLink(link: link)
    }

    func listPhysicalNotebookLinksForAssignment(assignmentId: String) async throws -> [PhysicalTestNotebookLink] {
        try await container.physicalTestsRepository.listNotebookLinksForAssignment(assignmentId: assignmentId)
    }

    /// Resuelve la nota de referencia de una marca física del cuaderno sin crear
    /// una segunda columna evaluable. Esto permite que los manifiestos
    /// diagnósticos (`recordScore=false`) sigan guardando solo el dato bruto,
    /// pero ofrezcan al docente la orientación del baremo al capturarlo.
    func resolvePhysicalNotebookScore(
        classId: Int64,
        student: Student,
        columnId: String,
        rawValue: Double
    ) async -> Double? {
        guard rawValue.isFinite else { return nil }

        do {
            let assignments = try await container.physicalTestsRepository.listAssignmentsForClass(classId: classId)
            for assignment in assignments {
                let links = try await container.physicalTestsRepository.listNotebookLinksForAssignment(assignmentId: assignment.id)
                guard let link = links.first(where: { $0.rawColumnId == columnId }) else { continue }

                let scale = try await container.physicalTestsRepository.resolveScale(
                    testId: link.testId,
                    course: assignment.course,
                    age: physicalScaleAge(for: student).map { KotlinInt(value: Int32($0)) },
                    sex: physicalScaleSex(for: student),
                    batteryId: assignment.batteryId
                )
                guard let scale else { return nil }
                let score = scale.scoreFor(rawValue: rawValue)
                return score?.doubleValue
            }
        } catch {
            return nil
        }
        return nil
    }

    func savePhysicalResult(_ result: PhysicalTestResult, attempts: [PhysicalTestAttempt]) async throws {
        try await container.physicalTestsRepository.saveResult(result: result, attempts: attempts)
    }

    func listPhysicalResultsForAssignment(assignmentId: String) async throws -> [PhysicalTestResult] {
        try await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignmentId)
    }

    func listPhysicalResultsForStudent(studentId: Int64, testId: String) async throws -> [PhysicalTestResult] {
        try await container.physicalTestsRepository.listResultsForStudent(studentId: studentId, testId: testId)
    }

    private func physicalScaleSex(for student: Student) -> String? {
        switch student.sex {
        case .male: return "MALE"
        case .female: return "FEMALE"
        default: return nil
        }
    }

    private func physicalScaleAge(for student: Student) -> Int? {
        guard let birthDate = student.birthDate else { return nil }
        let now = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let year = now.year, let month = now.month, let day = now.day else { return nil }
        var age = year - Int(birthDate.year)
        if month < Int(birthDate.monthNumber) ||
            (month == Int(birthDate.monthNumber) && day < Int(birthDate.dayOfMonth)) {
            age -= 1
        }
        return age >= 0 ? age : nil
    }

    func createNotebookPhysicalColumnForClass(
        classId: Int64,
        name: String,
        categoryId: String?,
        inputKind: NotebookCellInputKind,
        unitOrSituation: String?,
        scaleKind: NotebookScaleKind,
        iconName: String,
        weight: Double,
        countsTowardAverage: Bool,
        dateEpochMs: Int64,
        targetTabId: String? = nil
    ) async throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NSError(domain: "KmpBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "El nombre de la columna no puede estar vacío."])
        }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let columnId = "COL_PE_\(nowMillis)_\(abs(normalized.hashValue))"
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMillis)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let tabIds = targetTabId.map { [$0] } ?? selectedNotebookTabId.map { [$0] } ?? tabs.first.map { [$0.id] } ?? []
        let column = NotebookColumnDefinition(
            id: columnId,
            title: normalized,
            type: .numeric,
            categoryKind: .physicalEducation,
            instrumentKind: .physicalTest,
            inputKind: inputKind,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: weight,
            dateEpochMs: KotlinLong(value: dateEpochMs),
            unitOrSituation: unitOrSituation,
            competencyCriteriaIds: [],
            scaleKind: scaleKind,
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "F97316",
            iconName: iconName,
            order: -1,
            widthDp: 120,
            categoryId: categoryId,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: countsTowardAverage,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        scheduleNotebookSnapshotSync(forClassId: classId)
        return columnId
    }

    func saveNotebookPhysicalValue(
        classId: Int64,
        studentId: Int64,
        columnId: String,
        value: Double
    ) async throws {
        try await container.notebookRepository.upsertGrade(
            classId: classId,
            studentId: studentId,
            columnId: columnId,
            evaluationId: nil,
            numericValue: value,
            rubricSelections: nil,
            evidence: nil,
            createdAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            deviceId: localDeviceId,
            syncVersion: 1
        )
        scheduleGradeSnapshotSync(forClassId: classId)
    }

    func loadPESessions(weekNumber: Int, year: Int, classId: Int64?) async throws -> [PESessionSnapshot] {
        let sessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(
            summaries.map { ($0.planningSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var snapshots: [PESessionSnapshot] = []
        for session in sessions.sorted(by: {
            if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
            return $0.dayOfWeek < $1.dayOfWeek
        }) {
            let aggregate = try? await plannerJournal(for: session)
            let journal = aggregate?.journal
            snapshots.append(
                PESessionSnapshot(
                    id: session.id,
                    session: session,
                    summary: summariesById[session.id],
                    materialToPrepareText: journal?.materialToPrepareText ?? "",
                    materialUsedText: journal?.materialUsedText ?? "",
                    injuriesText: journal?.injuriesText ?? "",
                    unequippedStudentsText: journal?.unequippedStudentsText ?? "",
                    intensityScore: Int(journal?.intensityScore ?? 0),
                    stationObservationsText: journal?.stationObservationsText ?? "",
                    physicalIncidentsText: journal?.physicalIncidentsText ?? ""
                )
            )
        }
        return snapshots
    }

    func removeStudentFromSelectedClass(studentId: Int64) async throws {
        guard let classId = selectedStudentsClassId else { return }
        try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: studentId)
        try await refreshStudentsDirectory()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func deleteStudentEverywhere(studentId: Int64) async throws {
        try await container.studentsRepository.deleteStudent(studentId: studentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student_deleted",
            id: "\(studentId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": studentId]
        )
    }

    func assignStudentToClass(studentId: Int64, classId: Int64) async throws {
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func assignStudentsToClass(studentIds: [Int64], classId: Int64) async throws {
        for studentId in studentIds {
            try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId)
        }
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func removeStudentsFromClass(studentIds: [Int64], classId: Int64) async throws {
        for studentId in studentIds {
            try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: studentId)
        }
        try await refreshStudentsDirectory()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func deleteStudentsEverywhere(studentIds: [Int64]) async throws {
        let nowEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        for studentId in studentIds {
            try await container.studentsRepository.deleteStudent(studentId: studentId)
            enqueueLocalChange(
                entity: "student_deleted",
                id: "\(studentId)",
                updatedAtEpochMs: nowEpochMs,
                payload: ["id": studentId]
            )
        }
        try await refreshStudentsDirectory()
        try await refreshDashboard()
    }

    func listClassesForStudent(studentId: Int64) async throws -> [SchoolClass] {
        let allClasses = try await container.classesRepository.listClasses()
        var matched: [SchoolClass] = []
        for schoolClass in allClasses {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            if roster.contains(where: { $0.id == studentId }) {
                matched.append(schoolClass)
            }
        }
        return matched
    }

    func unassignedStudentIds() async throws -> Set<Int64> {
        let allClasses = try await container.classesRepository.listClasses()
        var assignedIds = Set<Int64>()
        for schoolClass in allClasses {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            for student in roster {
                assignedIds.insert(student.id)
            }
        }
        let allStudents = try await container.studentsRepository.listStudents()
        return Set(allStudents.map(\.id)).subtracting(assignedIds)
    }

    private static let stableDayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // Extrae año/mes/día con la zona horaria local (respeta el día que el usuario
    // quiso decir) pero ancla el epoch resultante a UTC, para que el mismo día
    // civil siempre produzca el mismo valor aunque cambie la zona horaria del
    // dispositivo (viajes, cambios de huso) entre una escritura y la siguiente.
    private func startOfDayEpochMs(for date: Date) -> Int64 {
        let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let stableDate = Self.stableDayCalendar.date(from: dayComponents) ?? date
        return Int64(stableDate.timeIntervalSince1970 * 1000)
    }

    private func startOfDayEpochMs(forEpochSeconds epochSeconds: Int64) -> Int64 {
        startOfDayEpochMs(for: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    private func attendanceSnapshot(from row: Attendance_) -> AttendanceRecordSnapshot {
        AttendanceRecordSnapshot(
            id: row.id,
            studentId: row.studentId,
            classId: row.classId,
            date: Date(timeIntervalSince1970: TimeInterval(row.date.epochSeconds)),
            status: row.status,
            note: row.note,
            hasIncident: row.hasIncident,
            followUpRequired: row.followUpRequired,
            sessionId: row.sessionId?.int64Value
        )
    }

    func compactSuggestions(_ values: String?...) -> [String] {
        values.compactMap {
            guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
    }

    func courseLabel(for schoolClass: SchoolClass) -> String {
        let lowercasedName = schoolClass.name.lowercased()
        if lowercasedName.contains("bach") || lowercasedName.contains("bac") || lowercasedName.contains("bto") || lowercasedName.contains("bat") {
            return "\(schoolClass.course)º Bachillerato"
        }
        if lowercasedName.contains("prim") || lowercasedName.contains("pri") {
            return "\(schoolClass.course)º Primaria"
        }
        if lowercasedName.contains("eso") || (1...4).contains(schoolClass.course) {
            return "\(schoolClass.course)º ESO"
        }
        return "\(schoolClass.course)º"
    }

    private func inferredCurriculumReferences(for profile: StudentProfileSnapshot) -> [String] {
        var references: [String] = []
        if profile.attendanceRate > 0 {
            references.append("CE1")
        }
        if !profile.evaluationTitles.isEmpty || profile.averageScore > 0 {
            references.append("CE2")
        }
        if profile.evidenceCount > 0 {
            references.append("CE3")
        }
        if profile.timeline.contains(where: { $0.title.localizedCaseInsensitiveContains("salida") || $0.title.localizedCaseInsensitiveContains("entorno") }) {
            references.append("CE4")
        }
        if profile.incidentCount == 0 || profile.followUpCount > 0 {
            references.append("CE5")
        }
        let source = references.isEmpty ? ["CE1", "CE2", "CE5"] : references
        var seen = Set<String>()
        return source.filter { seen.insert($0).inserted }
    }

    private func data(from byteArray: KotlinByteArray) -> Data {
        var buffer = Data(capacity: Int(byteArray.size))
        for index in 0..<Int(byteArray.size) {
            let value = UInt8(bitPattern: byteArray.get(index: Int32(index)))
            buffer.append(value)
        }
        return buffer
    }

    private func isoWeekday(from date: Date) -> Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: date)
        switch weekday {
        case 1: return 7
        default: return weekday - 1
        }
    }

    func createEvaluation(classId: Int64, code: String, name: String, type: String, weight: Double) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveEvaluation.invoke(
            id: nil,
            classId: classId,
            code: code,
            name: name,
            type: type,
            weight: weight,
            formula: nil,
            rubricId: nil,
            description: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(classId)-\(code)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": NSNull(),
                "classId": classId,
                "code": code,
                "name": name,
                "type": type,
                "weight": weight,
                "formula": NSNull(),
                "rubricId": NSNull(),
                "description": NSNull()
            ]
        )
    }

    func createPhysicalTest(
        classId: Int64,
        code: String,
        name: String,
        kind: String,
        weight: Double,
        description: String?
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let evaluationId = try await container.saveEvaluation.invoke(
            id: nil,
            classId: classId,
            code: code,
            name: name,
            type: "Prueba física · \(kind)",
            weight: weight,
            formula: nil,
            rubricId: nil,
            description: description,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(classId)-\(code)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": NSNull(),
                "classId": classId,
                "code": code,
                "name": name,
                "type": "Prueba física · \(kind)",
                "weight": weight,
                "formula": NSNull(),
                "rubricId": NSNull(),
                "description": description ?? NSNull()
            ]
        )
        return evaluationId.int64Value
    }

    func updatePhysicalTest(
        evaluationId: Int64,
        classId: Int64,
        code: String,
        name: String,
        kind: String,
        weight: Double,
        description: String?,
        formula: String? = nil,
        rubricId: Int64? = nil
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveEvaluation.invoke(
            id: KotlinLong(value: evaluationId),
            classId: classId,
            code: code,
            name: name,
            type: "Prueba física · \(kind)",
            weight: weight,
            formula: formula,
            rubricId: kotlinLong(rubricId),
            description: description,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(evaluationId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": evaluationId,
                "classId": classId,
                "code": code,
                "name": name,
                "type": "Prueba física · \(kind)",
                "weight": weight,
                "formula": formula ?? NSNull(),
                "rubricId": rubricId ?? NSNull(),
                "description": description ?? NSNull()
            ]
        )
    }

    func deletePhysicalTest(evaluationId: Int64) async throws {
        try await container.evaluationsRepository.deleteEvaluation(evaluationId: evaluationId)
        enqueueLocalChange(
            entity: "evaluation",
            id: "\(evaluationId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": evaluationId],
            op: "delete"
        )
    }

    func saveGrade(studentId: Int64, evaluationId: Int64, value: Double?, classId: Int64) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try await container.recordGrade.invoke(
            id: nil,
            classId: classId,
            studentId: studentId,
            evaluationId: evaluationId,
            value: value.map { KotlinDouble(value: $0) },
            evidence: nil,
            evidencePath: nil,
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "grade",
            id: "\(classId)-\(studentId)-\(evaluationId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "classId": classId,
                "studentId": studentId,
                "evaluationId": evaluationId,
                "value": value ?? NSNull()
            ]
        )
    }

    func createPESession(
        classId: Int64,
        title: String,
        dayOfWeek: Int,
        period: Int,
        weekNumber: Int,
        year: Int,
        objectives: String,
        activities: String,
        evaluation: String = "",
        status: SessionStatus = .planned,
        scheduledSpace: String = "",
        usedSpace: String = "",
        materialToPrepare: String = "",
        materialUsed: String = "",
        injuries: String = "",
        unequippedStudents: String = "",
        intensityScore: Int = 0,
        stationObservations: String = "",
        physicalIncidents: String = ""
    ) async throws -> Int64 {
        let resolvedClass: SchoolClass?
        if let cachedClass = classes.first(where: { $0.id == classId }) {
            resolvedClass = cachedClass
        } else {
            resolvedClass = try await container.classesRepository.listClasses().first { $0.id == classId }
        }

        guard let schoolClass = resolvedClass else {
            throw NSError(domain: "KmpBridge", code: -3001, userInfo: [NSLocalizedDescriptionKey: "No se encontró el grupo para crear la sesión EF"])
        }

        let sessionId = try await plannerUpsertSession(
            id: 0,
            teachingUnitId: 0,
            teachingUnitName: title,
            teachingUnitColor: "#1E88E5",
            groupId: classId,
            groupName: schoolClass.name,
            dayOfWeek: dayOfWeek,
            period: period,
            weekNumber: weekNumber,
            year: year,
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            status: status
        )

        try await savePESessionOperationalData(
            sessionId: sessionId,
            scheduledSpace: scheduledSpace,
            usedSpace: usedSpace,
            materialToPrepare: materialToPrepare,
            materialUsed: materialUsed,
            injuries: injuries,
            unequippedStudents: unequippedStudents,
            intensityScore: intensityScore,
            stationObservations: stationObservations,
            physicalIncidents: physicalIncidents,
            journalStatus: .draft
        )
        try await refreshPlanning()
        return sessionId
    }

    func savePESessionOperationalData(
        sessionId: Int64,
        scheduledSpace: String,
        usedSpace: String,
        materialToPrepare: String,
        materialUsed: String,
        injuries: String,
        unequippedStudents: String,
        intensityScore: Int,
        stationObservations: String,
        physicalIncidents: String,
        journalStatus: SessionJournalStatus
    ) async throws {
        guard let session = try await container.plannerRepository.listAllSessions().first(where: { $0.id == sessionId }) else {
            throw NSError(domain: "KmpBridge", code: -3002, userInfo: [NSLocalizedDescriptionKey: "No se encontró la sesión EF"])
        }

        let aggregate = try await container.sessionJournalRepository.getOrCreateJournal(session: session)
        let current = aggregate.journal
        let updatedJournal = SessionJournal(
            id: current.id,
            planningSessionId: current.planningSessionId,
            teacherName: current.teacherName,
            scheduledSpace: scheduledSpace.isEmpty ? current.scheduledSpace : scheduledSpace,
            usedSpace: usedSpace.isEmpty ? current.usedSpace : usedSpace,
            unitLabel: current.unitLabel,
            objectivePlanned: current.objectivePlanned,
            plannedText: current.plannedText,
            actualText: current.actualText,
            attainmentText: current.attainmentText,
            adaptationsText: current.adaptationsText,
            incidentsText: current.incidentsText,
            groupObservations: current.groupObservations,
            climateScore: current.climateScore,
            participationScore: current.participationScore,
            usefulTimeScore: current.usefulTimeScore,
            perceivedDifficultyScore: current.perceivedDifficultyScore,
            pedagogicalDecision: current.pedagogicalDecision,
            pendingTasksText: current.pendingTasksText,
            materialToPrepareText: materialToPrepare,
            studentsToReviewText: current.studentsToReviewText,
            familyCommunicationText: current.familyCommunicationText,
            nextStepText: current.nextStepText,
            weatherText: current.weatherText,
            materialUsedText: materialUsed,
            physicalIncidentsText: physicalIncidents,
            injuriesText: injuries,
            unequippedStudentsText: unequippedStudents,
            intensityScore: Int32(max(0, min(intensityScore, 5))),
            warmupMinutes: current.warmupMinutes,
            mainPartMinutes: current.mainPartMinutes,
            cooldownMinutes: current.cooldownMinutes,
            stationObservationsText: stationObservations,
            incidentTags: current.incidentTags,
            status: journalStatus
        )
        let updatedAggregate = SessionJournalAggregate(
            journal: updatedJournal,
            individualNotes: aggregate.individualNotes,
            actions: aggregate.actions,
            media: aggregate.media,
            links: aggregate.links
        )
        _ = try await container.sessionJournalRepository.saveJournalAggregate(aggregate: updatedAggregate)
    }

    // Proxy Methods for NotebookViewModel
    func selectClass(id: Int64) {
        let restoredTabId = restoredSelectedNotebookTab(forClassId: id)
        selectedNotebookTabId = restoredTabId
        notebookViewModel.setSelectedTabId(tabId: restoredTabId)
        notebookViewModel.selectClass(classId: id, force: true)
    }

    var currentNotebookClassId: Int64? {
        notebookViewModel.currentClassId?.int64Value
    }

    func setSelectedNotebookTab(id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        selectedNotebookTabId = normalized
        notebookViewModel.setSelectedTabId(tabId: normalized)
        rememberSelectedNotebookTab(normalized, forClassId: notebookViewModel.currentClassId?.int64Value)
    }
    
    func saveColumnGrade(studentId: Int64, column: NotebookColumnDefinition, value: String) {
        let key = cellKey(studentId: studentId, columnId: column.id)
        if column.type == .numeric || column.type == .rubric || column.type == .calculated {
            optimisticGradeDrafts[key] = value
            if let evalId = column.evaluationId?.int64Value {
                optimisticGradeDrafts[cellKey(studentId: studentId, columnId: "eval_\(evalId)")] = value
            }
        } else {
            optimisticTextDrafts[key] = value
        }
        notebookViewModel.saveColumnGrade(studentId: studentId, column: column, value: value)
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func saveColumnGradeDebounced(
        studentId: Int64,
        column: NotebookColumnDefinition,
        value: String
    ) {
        let key = cellKey(studentId: studentId, columnId: column.id)
        if column.type == .numeric || column.type == .rubric || column.type == .calculated {
            optimisticGradeDrafts[key] = value
            if let evalId = column.evaluationId?.int64Value {
                optimisticGradeDrafts[cellKey(studentId: studentId, columnId: "eval_\(evalId)")] = value
            }
        } else {
            optimisticTextDrafts[key] = value
        }
        notebookViewModel.saveColumnGrade(studentId: studentId, column: column, value: value)
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func flushPendingColumnGradeSave(studentId: Int64, columnId: String? = nil) {
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func saveNotebook() {
        notebookViewModel.saveCurrentNotebook(completionHandler: { [weak self] saved, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.status = "Error al guardar cuaderno: \(error.localizedDescription)"
                    return
                }

                let didSave = saved?.boolValue ?? false
                self.status = didSave ? "Cuaderno guardado" : "No se pudo guardar el cuaderno"
                if didSave, let classId = self.notebookViewModel.currentClassId?.int64Value {
                    self.scheduleNotebookSnapshotSync(forClassId: classId)
                }
            }
        })
    }
    
    func addStudent(firstName: String, lastName: String, isInjured: Bool) {
        notebookViewModel.addStudent(firstName: firstName, lastName: lastName, isInjured: isInjured)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func deleteStudent(id: Int64) {
        let classId = notebookViewModel.currentClassId?.int64Value
        
        // Encolar borrado explícito
        enqueueLocalChange(
            entity: "student",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        
        notebookViewModel.deleteStudent(studentId: id)
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func saveColumn(column: NotebookColumnDefinition) {
        notebookViewModel.saveColumn(column: column)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveAverageConfiguration(updates: [NotebookAverageColumnConfig]) {
        notebookViewModel.saveAverageConfiguration(updates: updates)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func reorderNotebookColumn(columnId: String, targetColumnId: String) {
        notebookViewModel.reorderColumns(columnId: columnId, targetColumnId: targetColumnId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    
    func saveTab(tab: NotebookTab) {
        notebookViewModel.saveTab(tab: tab)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveTabFixedWidth(tabId: String, widthDp: Double) {
        notebookViewModel.saveTabFixedWidth(tabId: tabId, widthDp: widthDp)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveNotebookWorkGroup(name: String, learningSituationId: Int64? = nil, studentIds: [Int64] = [], tabId: String? = nil) {
        let situationKotlin = KotlinLong(value: learningSituationId ?? -1)
        let studentsKotlin = studentIds.map { KotlinLong(value: $0) }
        notebookViewModel.saveWorkGroup(name: name, groupId: nil, studentIds: studentsKotlin, learningSituationId: situationKotlin, tabId: tabId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func updateNotebookWorkGroup(groupId: Int64, name: String, learningSituationId: Int64? = nil, studentIds: [Int64] = [], tabId: String? = nil) {
        let situationKotlin = KotlinLong(value: learningSituationId ?? -1)
        let studentsKotlin = studentIds.map { KotlinLong(value: $0) }
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: studentsKotlin, learningSituationId: situationKotlin, tabId: tabId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func renameNotebookWorkGroup(groupId: Int64, name: String) {
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: [], learningSituationId: nil, tabId: nil)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteNotebookWorkGroup(groupId: Int64) {
        notebookViewModel.deleteWorkGroup(groupId: groupId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func assignStudentToNotebookGroup(groupName: String?, studentId: Int64) {
        notebookViewModel.assignStudentToWorkGroup(groupName: groupName, studentId: studentId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func assignStudentsToNotebookGroup(groupId: Int64?, studentIds: [Int64], tabId: String? = nil) {
        notebookViewModel.assignStudentsToWorkGroup(
            groupId: groupId.map { KotlinLong(value: $0) },
            studentIds: studentIds.map { KotlinLong(value: $0) },
            tabId: tabId
        )
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func importNotebookWorkGroups(
        classId: Int64,
        tabId: String,
        groups: [(name: String, studentIds: [Int64], learningSituationId: Int64?)],
        clearExisting: Bool = false
    ) async throws {
        let batchItems: [NotebookWorkGroupBatchItem] = groups.map { item in
            NotebookWorkGroupBatchItem(
                name: item.name,
                studentIds: item.studentIds.map { KotlinLong(value: $0) },
                learningSituationId: item.learningSituationId.map { KotlinLong(value: $0) }
            )
        }
        try await container.notebookRepository.replaceWorkGroups(
            classId: classId,
            tabId: tabId,
            groups: batchItems,
            clearExisting: clearExisting
        )
        await MainActor.run {
            self.notebookViewModel.selectClass(classId: classId, force: true)
            self.scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    @discardableResult
    func autoComposeNotebookWorkGroups(
        groupCount: Int32,
        strategy: String,
        mixSex: Bool,
        spreadInjured: Bool,
        learningSituationId: Int64? = nil,
        tabId: String? = nil,
        clearExisting: Bool = true
    ) -> [ComposedWorkGroup] {
        let situationKotlin = learningSituationId.map { KotlinLong(value: $0) }
        let composed = notebookViewModel.autoComposeWorkGroups(
            groupCount: groupCount,
            strategy: strategy,
            mixSex: mixSex,
            spreadInjured: spreadInjured,
            learningSituationId: situationKotlin,
            tabId: tabId,
            clearExisting: clearExisting
        )
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
        return composed
    }
    
    func createTab(title: String, parentTabId: String? = nil) -> String? {
        guard let classId = notebookViewModel.currentClassId?.int64Value else { return nil }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        let tabId = "tab_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: nil,
            deviceId: nil,
            syncVersion: 0
        )
        let tabs = (notebookState as? NotebookUiStateData)?.sheet.tabs ?? []
        let siblingCount = tabs.filter { $0.parentTabId == parentTabId }.count
        let order = Int32(siblingCount)
        let newTab = NotebookTab(id: tabId, title: normalizedTitle, description: nil, order: order, parentTabId: parentTabId, fixedColumnWidth: nil, trace: trace)
        notebookViewModel.saveTab(tab: newTab)
        notebookViewModel.selectClass(classId: classId, force: true)
        scheduleNotebookSnapshotSync(forClassId: classId)
        return tabId
    }
    
    func deleteTab(id: String) {
        let classId = notebookViewModel.currentClassId?.int64Value
        // Encolar borrado para sincronización antes de eliminar localmente
        enqueueLocalChange(
            entity: "notebook_tab",
            id: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        
        notebookViewModel.deleteTab(tabId: id)
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func confirmAndAdvance(studentIndex: Int32, column: NotebookColumnDefinition, value: String) {
        notebookViewModel.confirmAndAdvance(studentIndex: studentIndex, column: column, value: value)
    }

    func addColumn(
        name: String,
        type: String,
        weight: Double,
        formula: String?,
        rubricId: Int64?,
        categoryId: String? = nil,
        categoryKind: NotebookColumnCategoryKind = .custom,
        instrumentKind: NotebookInstrumentKind = .custom,
        inputKind: NotebookCellInputKind = .text,
        dateEpochMs: Int64? = nil,
        unitOrSituation: String? = nil,
        competencyCriteriaIds: [Int64] = [],
        scaleKind: NotebookScaleKind = .custom,
        iconName: String? = nil,
        countsTowardAverage: Bool = true,
        isPinned: Bool = false,
        isHidden: Bool = false,
        visibility: NotebookColumnVisibility = .visible,
        isLocked: Bool = false,
        isTemplate: Bool = false
    ) {
        let classId = notebookViewModel.currentClassId?.int64Value
        notebookViewModel.addColumn(
            name: name,
            type: type,
            weight: weight,
            formula: formula,
            rubricId: rubricId.map { KotlinLong(value: $0) },
            categoryId: categoryId,
            categoryKind: categoryKind,
            instrumentKind: instrumentKind,
            inputKind: inputKind,
            dateEpochMs: dateEpochMs.map { KotlinLong(value: $0) },
            unitOrSituation: unitOrSituation,
            competencyCriteriaIds: competencyCriteriaIds.map { KotlinLong(value: $0) },
            scaleKind: scaleKind,
            iconName: iconName,
            countsTowardAverage: countsTowardAverage,
            isPinned: isPinned,
            isHidden: isHidden,
            visibility: visibility,
            isLocked: isLocked,
            isTemplate: isTemplate
        )
        // iOS-specific safety refresh to reflect new columns immediately.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            refreshCurrentNotebook()
        }
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func addColumnWithOptionalCategory(
        name: String,
        type: String,
        weight: Double,
        formula: String?,
        rubricId: Int64?,
        categoryId: String? = nil,
        newCategoryName: String? = nil,
        categoryKind: NotebookColumnCategoryKind = .custom,
        instrumentKind: NotebookInstrumentKind = .custom,
        inputKind: NotebookCellInputKind = .text,
        dateEpochMs: Int64? = nil,
        unitOrSituation: String? = nil,
        competencyCriteriaIds: [Int64] = [],
        scaleKind: NotebookScaleKind = .custom,
        iconName: String? = nil,
        countsTowardAverage: Bool = true,
        isPinned: Bool = false,
        isHidden: Bool = false,
        visibility: NotebookColumnVisibility = .visible,
        isLocked: Bool = false,
        isTemplate: Bool = false
    ) async throws -> NotebookCreatedColumnResult {
        guard let classId = notebookViewModel.currentClassId?.int64Value else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No hay clase activa."])
        }

        let currentData = notebookState as? NotebookUiStateData
        let tabs = currentData?.sheet.tabs ?? []
        let selectedTab = selectedNotebookTabId ?? tabs.first?.id
        let resolvedTabIds = selectedTab.map { [$0] } ?? []
        let existingCategories = currentData?.sheet.columnCategories ?? []
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let finalCategory: NotebookColumnCategory?
        if let rawName = newCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let tabId = selectedTab ?? tabs.first?.id ?? "TAB_\(classId)"
            let nextOrder = (existingCategories.filter { $0.tabId == tabId }.map(\.order).max() ?? -1) + 1
            let category = NotebookColumnCategory(
                id: "cat_\(nowMs)",
                classId: classId,
                tabId: tabId,
                name: rawName,
                order: nextOrder,
                isCollapsed: false,
                trace: trace
            )
            try await container.notebookRepository.saveColumnCategory(classId: classId, category: category)
            finalCategory = category
        } else if let categoryId {
            finalCategory = existingCategories.first(where: { $0.id == categoryId })
        } else {
            finalCategory = nil
        }

        let columnType = notebookColumnType(from: type)
        let needsEvaluation = columnType == .numeric || columnType == .rubric
        let evaluationId: Int64?
        if needsEvaluation {
            let savedEvaluationId = try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: "COL_\(nowMs)",
                name: name,
                type: columnType == .rubric ? "Rúbrica" : "Evaluación",
                weight: weight,
                formula: nil,
                rubricId: rubricId.map { KotlinLong(value: $0) },
                description: nil,
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
            evaluationId = savedEvaluationId.int64Value
        } else {
            evaluationId = nil
        }
        let columnId = evaluationId.map { "eval_\($0)" } ?? "COL_\(nowMs)"
        let nextOrder = (currentData?.sheet.columns.map(\.order).max() ?? -1) + 1
        let column = NotebookColumnDefinition(
            id: columnId,
            title: name,
            type: columnType,
            categoryKind: categoryKind,
            instrumentKind: instrumentKind,
            inputKind: inputKind,
            evaluationId: evaluationId.map { KotlinLong(value: $0) },
            rubricId: rubricId.map { KotlinLong(value: $0) },
            formula: columnType == .calculated ? formula?.nilIfEmpty : nil,
            weight: weight,
            dateEpochMs: dateEpochMs.map { KotlinLong(value: $0) },
            unitOrSituation: unitOrSituation?.nilIfEmpty,
            competencyCriteriaIds: competencyCriteriaIds.map { KotlinLong(value: $0) },
            scaleKind: scaleKind,
            tabIds: resolvedTabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: iconName,
            order: nextOrder,
            widthDp: 132,
            categoryId: finalCategory?.id ?? categoryId,
            ordinalLevels: defaultOrdinalLevels(
                columnType: columnType,
                instrumentKind: instrumentKind,
                scaleKind: scaleKind
            ),
            availableIcons: [],
            countsTowardAverage: countsTowardAverage,
            isPinned: isPinned,
            isHidden: isHidden,
            visibility: visibility,
            isLocked: isLocked,
            isTemplate: isTemplate,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
        return NotebookCreatedColumnResult(column: column, category: finalCategory)
    }

    private func defaultOrdinalLevels(
        columnType: NotebookColumnType,
        instrumentKind: NotebookInstrumentKind,
        scaleKind: NotebookScaleKind
    ) -> [String] {
        guard columnType == .ordinal else { return [] }
        if instrumentKind == .participation, scaleKind == .achievement {
            return ["Excelente", "Bien", "En proceso", "No logrado"]
        }
        return []
    }

    func saveNotebookCellAnnotation(
        studentId: Int64,
        columnId: String,
        note: String,
        iconValue: String? = nil,
        attachmentUris: [String] = []
    ) {
        let key = cellKey(studentId: studentId, columnId: columnId)
        optimisticAnnotations[key] = OptimisticAnnotation(
            note: note.nilIfEmpty,
            icon: iconValue?.nilIfEmpty,
            attachmentUris: attachmentUris
        )
        lastNotebookAggregateSignature = nil
        notebookViewModel.saveCellAnnotation(
            studentId: studentId,
            columnId: columnId,
            note: note.nilIfEmpty,
            iconValue: iconValue?.nilIfEmpty,
            attachmentUris: attachmentUris
        )
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func saveColumnCategory(name: String, categoryId: String? = nil) {
        notebookViewModel.saveColumnCategory(name: name, categoryId: categoryId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteColumnCategory(id: String, preserveColumns: Bool = true) {
        enqueueLocalChange(
            entity: "notebook_column_category",
            id: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": id,
                "classId": notebookViewModel.currentClassId?.int64Value ?? 0,
                "preserveColumns": preserveColumns
            ],
            op: "delete"
        )

        if !preserveColumns, let data = notebookState as? NotebookUiStateData {
            let categoryColumns = data.sheet.columns.filter { $0.categoryId == id }
            for column in categoryColumns {
                enqueueLocalChange(
                    entity: "notebook_column",
                    id: column.id,
                    updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                    payload: ["id": column.id],
                    op: "delete"
                )
            }
        }

        notebookViewModel.deleteColumnCategory(categoryId: id, preserveColumns: preserveColumns)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func toggleColumnCategory(id: String, collapsed: Bool) {
        notebookViewModel.toggleColumnCategoryCollapsed(categoryId: id, isCollapsed: collapsed)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func assignColumn(_ columnId: String, toCategory categoryId: String?) {
        notebookViewModel.assignColumnToCategory(columnId: columnId, categoryId: categoryId)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteColumn(id: String, evaluationId: Int64?) {
        let classId = notebookViewModel.currentClassId?.int64Value
        
        // Encolar borrado explícito
        enqueueLocalChange(
            entity: "notebook_column",
            id: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        
        if let evalId = evaluationId {
            notebookViewModel.deleteColumnByEvaluationId(columnId: evalId)
        } else {
            notebookViewModel.deleteColumnById(columnId: id)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self.refreshCurrentNotebook()
        }
        
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func deleteColumns(idsAndEvalIds: [(id: String, evaluationId: Int64?)]) {
        let classId = notebookViewModel.currentClassId?.int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        
        for item in idsAndEvalIds {
            enqueueLocalChange(
                entity: "notebook_column",
                id: item.id,
                updatedAtEpochMs: nowMs,
                payload: ["id": item.id],
                op: "delete"
            )
            
            if let evalId = item.evaluationId {
                notebookViewModel.deleteColumnByEvaluationId(columnId: evalId)
            } else {
                notebookViewModel.deleteColumnById(columnId: item.id)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self.refreshCurrentNotebook()
        }
        
        if let classId {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func updateColumnWeight(columnId: Int64, newWeight: Double) {
        notebookViewModel.updateColumnWeight(columnId: columnId, newWeight: newWeight)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func loadForNotebookCell(studentId: Int64, columnId: String, rubricId: Int64, evaluationId: Int64) {
        rubricEvaluationViewModel.loadForNotebookCell(studentId: studentId, columnId: columnId, rubricId: rubricId, evaluationId: evaluationId)
    }

    /// Detecta si el `description` de una evaluación es en realidad un volcado del objeto Kotlin
    /// y, si lo es, recupera el texto original que quedó sepultado dentro.
    ///
    /// Durante un tiempo `enqueueNotebookSnapshot` envió por sync `evaluation.description` (el
    /// `description` de NSObject, o sea el `toString` del objeto) en vez del campo real del dominio
    /// `description_`. Cada vez que el bug se disparaba, el volcado anterior se leía como si fuera
    /// la descripción y se envolvía en uno nuevo, así que en las bases de datos ya sincronizadas
    /// hay valores anidados varios niveles:
    ///
    ///     Evaluation(id=35, …, description=Evaluation(id=35, …, description=<texto real>,
    ///                competencyLinks=[], trace=…), competencyLinks=[], trace=…)
    ///
    /// El texto real es siempre el `description=` más interno, es decir el último del volcado, y
    /// termina justo antes de `, competencyLinks=`. Si no se puede extraer con confianza (sigue
    /// pareciendo un volcado, está vacío o es `null`) se devuelve `nil` a propósito: la cascada de
    /// `criterionLabel` cae entonces al código o al nombre de la evaluación, que es preferible a
    /// enseñar basura.
    static func recoveredEvaluationDescription(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("Evaluation(id=") || trimmed.contains("description=Evaluation(") else {
            return trimmed
        }
        guard let markerRange = trimmed.range(of: "description=", options: .backwards) else {
            return nil
        }
        let afterMarker = trimmed[markerRange.upperBound...]
        guard let endRange = afterMarker.range(of: ", competencyLinks=") else {
            return nil
        }
        let inner = afterMarker[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty, inner != "null", !inner.hasPrefix("Evaluation(") else {
            return nil
        }
        return inner
    }

    /// Reescribe en base de datos el `description` de una evaluación cuyo valor guardado es un
    /// volcado del objeto. Se hace en cuanto se detecta, no solo al pintarlo, porque el dato
    /// corrupto ya está sincronizado entre dispositivos: si solo se limpiara en pantalla seguiría
    /// circulando y reapareciendo. Si el texto original no se puede recuperar se deja como está en
    /// vez de borrarlo, para no destruir lo poco que quede.
    @discardableResult
    private func repairCorruptedEvaluationDescription(_ evaluation: Evaluation) async -> String? {
        guard let stored = evaluation.description_,
              stored.hasPrefix("Evaluation(id=") || stored.contains("description=Evaluation(") else {
            return evaluation.description_
        }
        guard let recovered = KmpBridge.recoveredEvaluationDescription(from: stored) else {
            return nil
        }
        await saveEvaluationWithDescription(evaluation, description: recovered)
        return recovered
    }

    /// Recorre las evaluaciones de una clase y limpia las descripciones que quedaron convertidas en
    /// un volcado del objeto. Se engancha a la cadena de reparaciones que ya existe para el
    /// importador de instrumentos.
    private func repairCorruptedEvaluationDescriptions(classId: Int64) async throws -> Bool {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        for evaluation in evaluations {
            guard let stored = evaluation.description_,
                  stored.hasPrefix("Evaluation(id=") || stored.contains("description=Evaluation(") else {
                continue
            }
            guard KmpBridge.recoveredEvaluationDescription(from: stored) != nil else { continue }
            await repairCorruptedEvaluationDescription(evaluation)
            didRepair = true
        }
        return didRepair
    }

    /// Recorre las evaluaciones de una clase creadas por el importador de instrumentos y sustituye
    /// la nota generica de importacion ("Instrumento importado desde...", ver
    /// materializeLearningSituationAssessmentInstruments) o una descripcion vacia por el enunciado
    /// oficial del criterio de evaluacion, buscado por el titulo del instrumento en
    /// EvaluationCriteriaReference. Sin esto, cualquier instrumento importado antes de este fix se
    /// queda enseñando la nota generica para siempre: el importador ya no la escribe, pero no
    /// reescribe lo que ya existe en la base de datos del docente.
    private func repairAssessmentInstrumentCriterionDescriptions(classId: Int64) async throws -> Bool {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        for evaluation in evaluations {
            let stored = evaluation.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let looksGeneric = stored.isEmpty || stored.hasPrefix("Instrumento importado desde ")
            guard looksGeneric,
                  let statement = EvaluationCriteriaReference.shared.criterionStatement(instrumentTitle: evaluation.name),
                  statement != stored else { continue }
            await saveEvaluationWithDescription(evaluation, description: statement)
            didRepair = true
        }
        return didRepair
    }

    private func saveEvaluationWithDescription(_ evaluation: Evaluation, description: String) async {
        _ = try? await container.evaluationsRepository.saveEvaluation(
            id: KotlinLong(value: evaluation.id),
            classId: evaluation.classId,
            code: evaluation.code,
            name: evaluation.name,
            type: evaluation.type,
            weight: evaluation.weight,
            formula: evaluation.formula,
            rubricId: evaluation.rubricId,
            description: description,
            authorUserId: evaluation.trace.authorUserId,
            createdAtEpochMs: evaluation.trace.createdAt.toEpochMilliseconds(),
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            associatedGroupId: evaluation.trace.associatedGroupId,
            deviceId: localDeviceId,
            syncVersion: evaluation.trace.syncVersion
        )
    }

    func loadStructuredInstrumentEvaluation(
        classId: Int64,
        studentId: Int64,
        columnId: String
    ) async throws -> StructuredInstrumentEvaluationModel? {
        // La plantilla estructurada de una columna solo la crea el importador de instrumentos de
        // la situación de aprendizaje (`saveAssessmentInstrumentTemplateIfNeeded`) o llega por
        // SyncLAN desde el dispositivo donde se importó. Si no existe, se devuelve `nil` y la hoja
        // enseña su estado vacío: sintetizar una plantilla aquí escribiría en la base de datos del
        // docente sesiones e indicadores que él nunca ha definido, y esa invención luego se
        // sincroniza al resto de dispositivos como si fuera trabajo real suyo.
        guard let detail = try await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId) else {
            return nil
        }
        let columns = (try? await container.notebookConfigRepository.listColumns(classId: classId)) ?? []
        let column = columns.first(where: { $0.id == columnId })

        // Descripción del criterio de evaluación que se evalúa con el instrumento. Si la
        // `description` de la evaluación asociada está vacía o es la nota genérica de importación,
        // se busca el enunciado oficial en EvaluationCriteriaReference por el título del
        // instrumento y se persiste. `competencyCriteriaIds` guarda identificadores de fila, no
        // códigos curriculares, así que no sirve como etiqueta legible. Si no hay ningún texto
        // real, no se muestra nada en vez de repetir el título de la columna, que ya es el título
        // de la hoja.
        var criterionLabel: String? = nil
        var criterionStatements: [CriterionStatement] = []
        let targetEvalId = column?.evaluationId?.int64Value ?? detail.template_.evaluationId?.int64Value
        if let evalId = targetEvalId, evalId > 0,
           let evaluation = try? await container.evaluationsRepository.getEvaluation(evaluationId: evalId) {
            criterionStatements = EvaluationCriteriaReference.shared.criterionStatements(instrumentTitle: evaluation.name)
            // `description_` puede llevar arrastrando un volcado del objeto (ver
            // repairCorruptedEvaluationDescription) de cuando el sync mandaba `description` de
            // NSObject en vez del campo real; se repara aquí, no solo al pintarlo, para que deje de
            // circular entre dispositivos.
            var desc = await repairCorruptedEvaluationDescription(evaluation)
            let looksGeneric = (desc?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                || (desc?.hasPrefix("Instrumento importado desde ") ?? false)
            if looksGeneric, let statement = EvaluationCriteriaReference.shared.criterionStatement(instrumentTitle: evaluation.name) {
                await saveEvaluationWithDescription(evaluation, description: statement)
                desc = statement
            }
            if let desc, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                criterionLabel = desc
            } else if !evaluation.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                criterionLabel = evaluation.code
            } else if !evaluation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                criterionLabel = evaluation.name
            }
        }
        if criterionLabel == nil,
           let unit = column?.unitOrSituation,
           !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            criterionLabel = unit
        }

        let responses = try await container.notebookInstrumentsRepository.listResponsesForCell(
            classId: classId,
            studentId: studentId,
            columnId: columnId
        )
        let responseByItemId = Dictionary(uniqueKeysWithValues: responses.map { ($0.itemId, $0) })
        let items = detail.items.map { item in
            let response = responseByItemId[item.id]
            return StructuredInstrumentEvaluationItem(
                id: item.id,
                key: item.key,
                title: item.title,
                type: item.type,
                options: item.options,
                helpText: item.helpText,
                textValue: response?.textValue ?? "",
                boolValue: response?.boolValue?.boolValue ?? false,
                numberValue: response?.numberValue.map { plainStructuredNumberString($0.doubleValue) } ?? ""
            )
        }
        return StructuredInstrumentEvaluationModel(
            id: "\(classId)-\(studentId)-\(columnId)",
            classId: classId,
            studentId: studentId,
            columnId: columnId,
            title: detail.template_.title,
            kind: detail.template_.kind,
            criterionLabel: criterionLabel,
            criterionStatements: criterionStatements,
            items: items
        )
    }

    @discardableResult
    func saveStructuredInstrumentEvaluation(_ model: StructuredInstrumentEvaluationModel) async throws -> NotebookInstrumentCellSummary {
        let responses = model.items.map { item in
            NotebookInstrumentResponse(
                classId: model.classId,
                studentId: model.studentId,
                columnId: model.columnId,
                itemId: item.id,
                textValue: structuredTextValue(for: item),
                boolValue: item.type == .check ? KotlinBoolean(value: item.boolValue) : nil,
                numberValue: structuredNumberValue(for: item).map { KotlinDouble(value: $0) },
                trace: AuditTrace(
                    authorUserId: nil,
                    createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                    updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)),
                    associatedGroupId: nil,
                    deviceId: localDeviceId,
                    syncVersion: 1
                )
            )
        }
        let summary = try await container.notebookInstrumentsRepository.saveResponses(
            classId: model.classId,
            studentId: model.studentId,
            columnId: model.columnId,
            responses: responses,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let key = cellKey(studentId: model.studentId, columnId: model.columnId)
        optimisticTextDrafts[key] = summary.displayValue
        invalidateNotebookCellValueIndexCache()
        lastNotebookAggregateSignature = nil
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: model.classId)
        return summary
    }

    private func structuredTextValue(for item: StructuredInstrumentEvaluationItem) -> String? {
        switch item.type {
        case .text, .choice:
            let value = item.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    /// `IosFormatting.decimal` fuerza siempre 2 decimales ("4.00"/"4,00" según locale), lo que
    /// no coincide con los tags planos "1".."4" de los selectores segmentados (.scale14) ni con
    /// lo que escribe una casilla numérica libre — el valor cargado no seleccionaba ningún nivel
    /// al reabrir el sheet, pareciendo que el guardado se había perdido aunque sí persistía.
    func plainStructuredNumberString(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    private func structuredNumberValue(for item: StructuredInstrumentEvaluationItem) -> Double? {
        switch item.type {
        case .number, .scale14:
            return Double(item.numberValue.replacingOccurrences(of: ",", with: "."))
        default:
            return nil
        }
    }


    private func enqueueRosterSnapshot(forClassId classId: Int64, updatedAtEpochMs: Int64) {
        let studentIds = studentsInClass.map { $0.id }.sorted()
        enqueueLocalChange(
            entity: "class_roster",
            id: "\(classId)",
            updatedAtEpochMs: updatedAtEpochMs,
            payload: [
                "classId": classId,
                "studentIds": studentIds
            ]
        )
    }

    func enqueueLocalChange(
        entity: String,
        id: String,
        updatedAtEpochMs: Int64,
        payload: [String: Any],
        op: String = "upsert",
        shouldPersist: Bool = true,
        shouldScheduleAutoSync: Bool = true,
        autoSyncDelayNanoseconds: UInt64 = 250_000_000
    ) {
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            return
        }
        let newChange = LanSyncChange(
            entity: entity,
            id: id,
            updatedAtEpochMs: updatedAtEpochMs,
            deviceId: localDeviceId,
            payload: payloadString,
            op: op
        )
        if let idx = pendingOutboundChanges.firstIndex(where: { $0.entity == entity && $0.id == id }) {
            pendingOutboundChanges[idx] = newChange
        } else {
            pendingOutboundChanges.append(newChange)
        }
        lastLocalMutationAt = Date()
        let pendingChangesCount = pendingOutboundChanges.count
        publishSyncState {
            $0.syncPendingChanges = pendingChangesCount
        }
        
        if shouldPersist {
            persistPendingChanges()
        }
        enqueueLocalSseNotification(newChange)
        if shouldScheduleAutoSync {
            triggerAutoSyncSoon(delayNanoseconds: autoSyncDelayNanoseconds)
        }
    }

    private func enqueueLocalSseNotification(_ change: LanSyncChange) {
        #if os(macOS)
        guard pairedSyncHost != nil else { return }
        if let idx = pendingLocalSseChanges.firstIndex(where: { $0.entity == change.entity && $0.id == change.id }) {
            pendingLocalSseChanges[idx] = change
        } else {
            pendingLocalSseChanges.append(change)
        }
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                let changes = self.pendingLocalSseChanges
                self.pendingLocalSseChanges.removeAll()
                guard !changes.isEmpty else { return }
                try await self.lanSyncClient.notifyLocalChanges(
                    host: self.pairedSyncHost ?? "127.0.0.1",
                    changes: changes,
                    pinnedFingerprint: self.pairedServerFingerprint
                )
            } catch is CancellationError {
                return
            } catch {
                // Best-effort: the periodic LAN sync loop and helper DB monitor remain
                // as fallbacks, so local editing should never fail because SSE notify did.
            }
        }
        #endif
    }

    private func sanitizePersistedCellText(_ text: String, columnType: NotebookColumnType?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard columnType != .icon else { return trimmed }

        // Si es un nombre crudo de símbolo SF (ej. "trophy.fill", "star.fill")
        if NotebookCellStampCatalog.item(for: trimmed) != nil || trimmed.hasSuffix(".fill") {
            return ""
        }

        // Si contiene un símbolo crudo concatenado (ej. "9 trophy.fill")
        for stamp in NotebookCellStampCatalog.allStamps {
            if trimmed.contains(stamp.symbol) {
                let cleaned = trimmed.replacingOccurrences(of: stamp.symbol, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned
            }
        }
        return trimmed
    }

    private func notebookCellValueIndex() -> NotebookCellValueIndex? {
        guard let data = notebookState as? NotebookUiStateData else { return nil }
        let stateIdentity = ObjectIdentifier(data)
        if cachedNotebookStateIdentity == stateIdentity, let cachedNotebookCellValueIndex {
            return cachedNotebookCellValueIndex
        }

        var index = NotebookCellValueIndex()

        let columnTypesById = Dictionary(
            data.sheet.columns.map { ($0.id, $0.type) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in data.sheet.rows {
            let studentId = row.student.id

            for persisted in row.persistedCells {
                let key = cellKey(studentId: studentId, columnId: persisted.columnId)
                let columnType = columnTypesById[persisted.columnId]

                if let display = persisted.displayValue, !display.isEmpty {
                    index.displayByKey[key] = sanitizePersistedCellText(display, columnType: columnType)
                }
                if columnType == .icon, let icon = persisted.iconValue, !icon.isEmpty {
                    index.textByKey[key] = icon
                } else if let text = persisted.textValue, !text.isEmpty {
                    index.textByKey[key] = sanitizePersistedCellText(text, columnType: columnType)
                } else if let ordinal = persisted.ordinalValue, !ordinal.isEmpty {
                    index.textByKey[key] = ordinal
                } else {
                    index.textByKey[key] = ""
                }
                index.checkByKey[key] = persisted.boolValue?.boolValue ?? false
            }

            for grade in row.persistedGrades {
                guard let value = grade.value else { continue }
                let formatted = IosFormatting.decimal(from: value.doubleValue)
                index.numericByKey[cellKey(studentId: studentId, columnId: grade.columnId)] = formatted
                if let evalId = grade.evaluationId?.int64Value {
                    index.numericByEvalKey[cellKey(studentId: studentId, columnId: "eval_\(evalId)")] = formatted
                }
            }

            for cell in row.cells {
                guard let value = cell.value else { continue }
                let evalId = cell.evaluationId
                let key = cellKey(studentId: studentId, columnId: "eval_\(evalId)")
                if index.numericByEvalKey[key] == nil {
                    index.numericByEvalKey[key] = IosFormatting.decimal(from: value.doubleValue)
                }
            }
        }

        for (key, value) in data.numericDrafts {
            guard let studentId = key.first?.int64Value, let columnId = key.second as String? else { continue }
            let rowKey = cellKey(studentId: studentId, columnId: columnId)
            index.numericDraftByKey[rowKey] = value
        }
        for (key, value) in data.textDrafts {
            guard let studentId = key.first?.int64Value, let columnId = key.second as String? else { continue }
            let rowKey = cellKey(studentId: studentId, columnId: columnId)
            index.textDraftByKey[rowKey] = value
        }
        for (key, value) in data.checkDrafts {
            guard let studentId = key.first?.int64Value, let columnId = key.second as String? else { continue }
            let rowKey = cellKey(studentId: studentId, columnId: columnId)
            index.checkDraftByKey[rowKey] = value.boolValue
        }

        for (key, value) in optimisticGradeDrafts {
            index.numericDraftByKey[key] = value
        }
        for (key, value) in optimisticTextDrafts {
            index.textDraftByKey[key] = value
            index.displayByKey[key] = value
            if let b = Bool(value) {
                index.checkDraftByKey[key] = b
            } else if value == "1" {
                index.checkDraftByKey[key] = true
            } else if value == "0" {
                index.checkDraftByKey[key] = false
            }
        }

        cachedNotebookStateIdentity = stateIdentity
        cachedNotebookCellValueIndex = index
        return index
    }

    func cellText(studentId: Int64, columnId: String) -> String {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticTextDrafts[key] {
            return opt
        }
        guard let index = notebookCellValueIndex() else { return "" }
        return index.textDraftByKey[key] ?? index.textByKey[key] ?? ""
    }

    func structuredCellDisplayText(studentId: Int64, columnId: String) -> String {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticTextDrafts[key] {
            return opt
        }
        guard let index = notebookCellValueIndex() else { return "" }
        return index.displayByKey[key] ?? index.textByKey[key] ?? ""
    }

    func cellAnnotation(studentId: Int64, columnId: String) -> (note: String?, icon: String?, attachmentUris: [String])? {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticAnnotations[key] {
            return (note: opt.note, icon: opt.icon, attachmentUris: opt.attachmentUris)
        }
        return nil
    }
    
    func numericGradeText(studentId: Int64, columnId: String) -> String {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let opt = optimisticGradeDrafts[key] {
            return opt
        }
        guard let index = notebookCellValueIndex() else { return "" }
        if let draft = index.numericDraftByKey[key] {
            return draft
        }
        if let persisted = index.numericByKey[key] {
            return persisted
        }
        if let persistedEval = index.numericByEvalKey[key] {
            return persistedEval
        }
        return ""
    }

    func numericGradeText(studentId: Int64, column: NotebookColumnDefinition) -> String {
        let raw = numericGradeText(studentId: studentId, columnId: column.id)
        guard column.inputKind == .time else { return raw }
        guard let seconds = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) else {
            return raw
        }
        let centiseconds = max(0, Int((seconds * 100.0).rounded()))
        let minutes = centiseconds / 6000
        let remainingSeconds = (centiseconds / 100) % 60
        let fraction = centiseconds % 100
        return String(format: "%02d:%02d,%02d", minutes, remainingSeconds, fraction)
    }

    func numericGradeOnTenText(studentId: Int64, columnId: String) -> String {
        formatGradeOnTen(numericGradeText(studentId: studentId, columnId: columnId))
    }

    func rubricGradeText(studentId: Int64, column: NotebookColumnDefinition) -> String {
        guard let index = notebookCellValueIndex() else { return "" }
        let directKey = cellKey(studentId: studentId, columnId: column.id)
        if let directValue = index.numericDraftByKey[directKey], !directValue.isEmpty {
            return directValue
        }

        if let evaluationId = column.evaluationId?.int64Value {
            let evalKey = cellKey(studentId: studentId, columnId: "eval_\(evaluationId)")
            if let evalValue = index.numericDraftByKey[evalKey], !evalValue.isEmpty {
                return evalValue
            }
            if let persisted = index.numericByKey[directKey] {
                return persisted
            }
            if let persistedByEval = index.numericByEvalKey[evalKey] {
                return persistedByEval
            }
        } else if let persisted = index.numericByKey[directKey] {
            return persisted
        }

        return ""
    }

    func rubricGradeOnTenText(studentId: Int64, column: NotebookColumnDefinition) -> String {
        formatGradeOnTen(rubricGradeText(studentId: studentId, column: column))
    }

    func cellCheck(studentId: Int64, columnId: String) -> Bool {
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let optText = optimisticTextDrafts[key] {
            if let b = Bool(optText) {
                return b
            }
            if optText == "1" { return true }
            if optText == "0" { return false }
        }
        guard let index = notebookCellValueIndex() else { return false }
        if let draft = index.checkDraftByKey[key] {
            return draft
        }
        if let persisted = index.checkByKey[key] {
            return persisted
        }
        return false
    }

    private func cellKey(studentId: Int64, columnId: String) -> String {
        "\(studentId)|\(columnId)"
    }

    private func formatGradeOnTen(_ rawValue: String) -> String {
        if let cached = gradeOnTenFormatCache[rawValue] {
            return cached
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            gradeOnTenFormatCache[rawValue] = ""
            return ""
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let numeric = Double(normalized) else {
            gradeOnTenFormatCache[rawValue] = trimmed
            return trimmed
        }
        let formatted = IosFormatting.scoreOutOfTen(from: numeric)
        gradeOnTenFormatCache[rawValue] = formatted
        return formatted
    }

    func kotlinLong(_ value: Int64?) -> KotlinLong? {
        value.map { KotlinLong(value: $0) }
    }

    func int64Value(_ raw: Any?) -> Int64? {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String { return Int64(value) }
        return nil
    }

    func positiveInt64Value(_ raw: Any?) -> Int64? {
        int64Value(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Float { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        if let value = raw as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func studentSex(from raw: Any?) -> StudentSex {
        let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch value {
        case "MALE", "M", "H", "HOMBRE", "MASCULINO":
            return .male
        case "FEMALE", "F", "MUJER", "FEMENINO":
            return .female
        default:
            return .unspecified
        }
    }

    func studentSexSource(from raw: Any?) -> StudentSexSource {
        let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch value {
        case "MANUAL":
            return .manual
        case "NAME_INFERRED", "NAMEINFERRED", "NOMBRE":
            return .nameInferred
        case "AI_INFERRED", "AIINFERRED", "IA":
            return .aiInferred
        case "IMPORTED":
            return .imported
        default:
            return .unknown
        }
    }

    func localDate(from raw: Any?) -> LocalDate? {
        guard let value = raw as? String else { return nil }
        let parts = value.split(separator: "-").compactMap { Int32($0) }
        guard parts.count == 3 else { return nil }
        return LocalDate(year: parts[0], monthNumber: parts[1], dayOfMonth: parts[2])
    }

    func longList(_ raw: Any?) -> [KotlinLong] {
        if let values = raw as? [Int64] {
            return values.map { KotlinLong(value: $0) }
        }
        if let values = raw as? [NSNumber] {
            return values.map { KotlinLong(value: $0.int64Value) }
        }
        if let csv = raw as? String {
            return csv
                .split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { KotlinLong(value: $0) }
        }
        return []
    }

    func notebookColumnType(from raw: String?) -> NotebookColumnType {
        switch raw?.uppercased() {
        case "TEXT":
            return .text
        case "ICON":
            return .icon
        case "CHECK":
            return .check
        case "ORDINAL":
            return .ordinal
        case "RUBRIC":
            return .rubric
        case "ATTENDANCE":
            return .attendance
        case "CALCULATED":
            return .calculated
        default:
            return .numeric
        }
    }

    func notebookCategoryKind(_ raw: String?) -> NotebookColumnCategoryKind {
        switch raw?.uppercased() {
        case "EVALUATION": return .evaluation
        case "FOLLOW_UP": return .followUp
        case "ATTENDANCE": return .attendance
        case "EXTRAS": return .extras
        case "PHYSICAL_EDUCATION": return .physicalEducation
        default: return .custom
        }
    }

    func notebookInstrumentKind(_ raw: String?) -> NotebookInstrumentKind {
        switch raw?.uppercased() {
        case "WRITTEN_TEST": return .writtenTest
        case "RUBRIC": return .rubric
        case "SYSTEMATIC_OBSERVATION": return .systematicObservation
        case "CHECKLIST": return .checklist
        case "OBSERVATION_SCALE": return .observationScale
        case "FINAL_PRODUCT": return .finalProduct
        case "DAILY_WORK": return .dailyWork
        case "TASK": return .task
        case "PARTICIPATION": return .participation
        case "PHYSICAL_TEST": return .physicalTest
        case "MULTIMEDIA_EVIDENCE": return .multimediaEvidence
        default: return .custom
        }
    }

    func notebookInputKind(_ raw: String?) -> NotebookCellInputKind {
        switch raw?.uppercased() {
        case "NUMERIC_0_10": return .numeric010
        case "NUMERIC_1_4": return .numeric14
        case "PERCENTAGE": return .percentage
        case "TIME": return .time
        case "REPETITIONS": return .repetitions
        case "DISTANCE": return .distance
        case "EXCELLENT_GOOD_PROGRESS": return .excellentGoodProgress
        case "YES_NO": return .yesNo
        case "ACHIEVED_PARTIAL_NOT_ACHIEVED": return .achievedPartialNotAchieved
        case "LETTER_ABCD": return .letterAbcd
        case "QUICK_SELECTOR": return .quickSelector
        case "RUBRIC": return .rubric
        case "CHECK": return .check
        case "SHORT_NOTE": return .shortNote
        case "EVIDENCE": return .evidence
        case "ATTENDANCE_STATUS": return .attendanceStatus
        case "CALCULATED": return .calculated
        case "STRUCTURED_CHECKLIST": return .structuredChecklist
        case "STRUCTURED_OBSERVATION": return .structuredObservation
        case "STRUCTURED_FORM": return .structuredForm
        case "STRUCTURED_QUIZ": return .structuredQuiz
        default: return .text
        }
    }

    func notebookScaleKind(_ raw: String?) -> NotebookScaleKind {
        switch raw?.uppercased() {
        case "TEN_POINT": return .tenPoint
        case "FOUR_LEVEL": return .fourLevel
        case "PERCENTAGE": return .percentage
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        case "LETTER_ABCD": return .letterAbcd
        case "ACHIEVEMENT": return .achievement
        case "YES_NO": return .yesNo
        default: return .custom
        }
    }

    func notebookColumnVisibility(_ raw: String?) -> NotebookColumnVisibility {
        switch raw?.uppercased() {
        case "HIDDEN": return .hidden
        case "ARCHIVED": return .archived
        default: return .visible
        }
    }

    func notebookInstrumentTemplateKind(_ raw: String?) -> NotebookInstrumentTemplateKind {
        switch raw?.uppercased() {
        case "CHECKLIST": return .checklist
        case "OBSERVATION": return .observation
        case "QUIZ": return .quiz
        default: return .form
        }
    }

    func notebookInstrumentItemType(_ raw: String?) -> NotebookInstrumentItemType {
        switch raw?.uppercased() {
        case "CHECK": return .check
        case "CHOICE": return .choice
        case "NUMBER": return .number
        case "TEXT": return .text
        default: return .scale14
        }
    }

    func normalizeHexColor(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let validLength = hex.count == 3 || hex.count == 6
        guard validLength else { return nil }
        let isHex = hex.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789ABCDEFabcdef").contains(scalar)
        }
        guard isHex else { return nil }
        return "#\(hex.uppercased())"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
