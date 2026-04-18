import Foundation
import MiGestorKit
import Combine
import Security
import CryptoKit

enum IosFormatting {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func decimal(_ value: Double?) -> String {
        guard let value else { return "--" }
        return decimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func decimal(_ value: KotlinDouble?) -> String {
        decimal(value?.doubleValue)
    }

    static func decimal(_ value: NSNumber?) -> String {
        decimal(value?.doubleValue)
    }

    static func decimal(from value: Any?) -> String {
        guard let value else { return "--" }
        if let value = value as? Double {
            return decimal(value)
        }
        if let value = value as? Float {
            return decimal(Double(value))
        }
        if let value = value as? NSNumber {
            return decimal(value)
        }
        if let value = value as? KotlinDouble {
            return decimal(value)
        }
        return "--"
    }

    static func scoreOutOfTen(from value: Any?) -> String {
        let text = decimal(from: value)
        return text == "--" ? "Sin dato" : "\(text) / 10"
    }
}

struct PlannerAssessmentInstrument: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case evaluation
        case rubric
    }

    let kind: Kind
    let rawId: Int64
    let title: String
    let subtitle: String
    let classId: Int64
    let teachingUnitId: Int64?
    let evaluationId: Int64?
    let rubricId: Int64?
    let resolvedEvaluationId: Int64?

    var id: String { "\(kind.rawValue):\(rawId)" }
}

struct PlannerSessionSaveResult {
    let sessionId: Int64
    let teachingUnitId: Int64
    let teachingUnitName: String
    let evaluationSummary: String
    let linkedAssessmentIdsCsv: String
}

@MainActor
final class KmpBridge: ObservableObject {
    private static let plannerCoursePalette: [String] = [
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
    @Published var statsText: String = "-"
    @Published var classes: [SchoolClass] = []
    @Published var studentsInClass: [Student] = []
    @Published var evaluationsInClass: [Evaluation] = []
    @Published var rubrics: [RubricDetail] = []
    @Published var planning: [PlanPeriod] = []
    @Published var rubricsUiState: RubricUiState? = nil
    @Published var rubricClassLinks: [Int64: Set<Int64>] = [:]
    @Published var rubricBuilderTeachingUnits: [TeachingUnit] = []
    @Published var selectedRubricTeachingUnitId: Int64? = nil
    
    // Notebook State (Bridged from NotebookViewModel)
    @Published var notebookState: NotebookUiState = NotebookUiStateLoading()
    @Published var notebookSaveState: NotebookViewModelSaveState = NotebookViewModelSaveState.saved
    
    // Rubric Evaluation State (Bridged from RubricEvaluationViewModel)
    @Published var rubricEvaluationState: RubricEvaluationUiState = RubricEvaluationUiState.companion.default()
    
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

    // LAN Sync State
    @Published var discoveredSyncHosts: [String] = []
    @Published var syncStatusMessage: String = "Sync local inactivo"
    @Published var syncPendingChanges: Int = 0
    @Published var syncLastRunAt: Date? = nil
    @Published var pairedSyncHost: String? = nil
    
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
            case classSnapshot
            case studentFollowUp
            case familyComment
            case attendancePatterns
            case followUpList
            case diarySummary
            case nextSteps
            case evaluationDigest
            case progressReadout
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

    private let container: KmpContainer
    private let appleBootstrap: AppleBridgeBootstrap
    let notebookViewModel: NotebookViewModel
    let plannerViewModel: PlannerViewModel
    let rubricEvaluationViewModel: RubricEvaluationViewModel
    let rubricBulkEvaluationViewModel: RubricBulkEvaluationViewModel
    let rubricsViewModel: RubricsViewModel
    private let lanSyncClient = LanSyncClient()
    private let lanSyncDiscovery = LanSyncDiscovery()
    private let syncSecureStore = IosKeychainStore(service: "com.migestor.sync.ios")
    private var syncToken: String? = nil
    private var pairedServerId: String? = nil
    private var pairedServerFingerprint: String? = nil
    private var discoveredPeersByHost: [String: LanDiscoveredPeer] = [:]
    private var autoSyncLoopTask: Task<Void, Never>? = nil
    private var autoSyncDebounceTask: Task<Void, Never>? = nil
    private var notebookSnapshotDebounceTask: Task<Void, Never>? = nil
    private var pendingDebouncedGradeSaves: [String: Task<Void, Never>] = [:]
    private var pendingGradeSnapshotTask: Task<Void, Never>? = nil
    private var isSyncInFlight = false
    private var syncNeedsAnotherPass = false
    private var isAppInForeground = true
    private var lastLocalMutationAt: Date = .distantPast
    private var lastSuccessfulSyncAt: Date = .distantPast
    private var lastFullPullAt: Date = .distantPast
    private var lastSyncCursorEpochMs: Int64 = UserDefaults.standard.object(forKey: "sync.last.cursor") as? Int64 ?? 0
    private var selectedNotebookTabByClassId: [String: String] = {
        guard let raw = UserDefaults.standard.dictionary(forKey: "notebook.selected.tab.by.class.v1") as? [String: String] else {
            return [:]
        }
        return raw
    }()
    private var plannerCourseColorByClassId: [String: String] = {
        guard let raw = UserDefaults.standard.dictionary(forKey: "planner.class.colors.v1") as? [String: String] else {
            return [:]
        }
        return raw
    }()
    /// Cola de cambios pendientes – persiste en UserDefaults para sobrevivir reinicios.
    private var pendingOutboundChanges: [LanSyncChange] = {
        guard let data = UserDefaults.standard.data(forKey: "sync.pending.changes.v2"),
              let decoded = try? JSONDecoder().decode([LanSyncChange].self, from: data)
        else { return [] }
        return decoded
    }()
    private var notebookSyncCache: NotebookSyncCache = {
        guard let data = UserDefaults.standard.data(forKey: "sync.notebook.cache.v1"),
              let decoded = try? JSONDecoder().decode(NotebookSyncCache.self, from: data)
        else { return NotebookSyncCache() }
        return decoded
    }()
    private lazy var localDeviceId: String = loadOrCreateLocalDeviceId()
    private var didBootstrap = false
    private var cancellables = Set<AnyCancellable>()
    private let notebookStateSubject = CurrentValueSubject<NotebookUiState, Never>(NotebookUiStateLoading())
    private var cachedNotebookStateIdentity: ObjectIdentifier? = nil
    private var cachedNotebookCellValueIndex: NotebookCellValueIndex? = nil
    private var gradeOnTenFormatCache: [String: String] = [:]

    private struct NotebookCellValueIndex {
        var textByKey: [String: String] = [:]
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

        self.lanSyncDiscovery.onPeersChanged = { [weak self] peers in
            Task { @MainActor in
                guard let self else { return }
                let uniquePeers = Self.deduplicateDiscoveredPeers(peers)
                self.discoveredPeersByHost = Dictionary(uniqueKeysWithValues: uniquePeers.map { ($0.host, $0) })
                self.discoveredSyncHosts = uniquePeers.map(\.host).sorted()
                self.rebindPairedHostIfNeeded()
            }
        }
        self.lanSyncDiscovery.start()
        startAutoSyncLoop()

        setupObservers()
    }

    deinit {
        autoSyncLoopTask?.cancel()
        autoSyncDebounceTask?.cancel()
        notebookSnapshotDebounceTask?.cancel()
        pendingGradeSnapshotTask?.cancel()
        pendingDebouncedGradeSaves.values.forEach { $0.cancel() }
    }

    private func setupObservers() {
        // Observe Notebook State with Debounce (to stabilize UI during typing)
        Task {
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
                    notebookStateSubject.send(state)
                }
            }
        }
        
        notebookStateSubject
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [unowned self] state in
                self.notebookState = state
                self.invalidateNotebookCellValueIndexCache()
            }
            .store(in: &cancellables)
        
        // Observe Notebook Save State
        Task {
            let sequence = notebookViewModel.saveState.asAsyncSequence(type: NotebookViewModelSaveState.self)
            for await saveState in sequence {
                self.notebookSaveState = saveState
            }
        }
        
        // Observe Rubric Evaluation State
        Task {
            let sequence = rubricEvaluationViewModel.uiState.asAsyncSequence(type: RubricEvaluationUiState.self)
            for await state in sequence {
                let wasSaveSuccessful = self.rubricEvaluationState.isSaveSuccessful
                self.rubricEvaluationState = state
                if state.isSaveSuccessful && !wasSaveSuccessful {
                    self.refreshCurrentNotebook()
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
            }
        }
        
        // Observe Rubric Bulk Evaluation State
        Task {
            let sequence = rubricBulkEvaluationViewModel.uiState.asAsyncSequence(type: BulkRubricEvaluationUiState.self)
            for await state in sequence {
                let wasSaveSuccessful = self.bulkRubricEvaluationState?.isSaveSuccessful ?? false
                self.bulkRubricEvaluationState = state
                if state.isSaveSuccessful && !wasSaveSuccessful {
                    self.refreshCurrentNotebook()
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
            }
        }

        // Observe Rubrics Builder/Bank State
        Task {
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
            try await seedIfNeeded()
            try await refreshDashboard()
            try await loadDashboard(mode: .office)
            try await refreshClasses()
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
    }

    var appDatabasePath: String {
        appleBootstrap.databasePath
    }

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

    private func refreshDashboard() async throws {
        let stats: DashboardStats = try await container.dashboardRepository.getStats()

        statsText = "Alumnos \(stats.totalStudents) · Clases \(stats.totalClasses) · Eval \(stats.totalEvaluations)"
        
        // Fetch Upcoming Classes
        let allEvents = try await container.calendarRepository.listEvents(classId: nil)
        
        let now = ClockSystem.shared.now()
        self.upcomingClasses = allEvents.filter { $0.startAt.epochSeconds > now.epochSeconds }
            .sorted { $0.startAt.epochSeconds < $1.startAt.epochSeconds }
            .prefix(3).map { $0 }

        // Fetch Classes for distribution and tasks
        let allClasses = try await container.classesRepository.listClasses()
        
        // Distribution
        let esoCount = allClasses.filter { $0.course <= 4 }.count
        let totalC = max(allClasses.count, 1)
        self.esoPercentage = Int((Double(esoCount) / Double(totalC)) * 100)
        self.bachPercentage = 100 - self.esoPercentage
        
        // Pending Tasks (Incidents)
        var allIncidents: [Incident] = []
        for cls in allClasses {
            let incidents = try await container.incidentsRepository.listIncidents(classId: cls.id)
            allIncidents.append(contentsOf: incidents)
        }
        self.pendingTasks = Array(allIncidents.prefix(3))
        
        // Activity Groups (Averages by Class)
        var groups: [ActivityGroup] = []
        let recentClasses = allClasses.prefix(6)
        for cls in recentClasses {
            let grades = try await container.gradesRepository.listGradesForClass(classId: cls.id)
            let values = grades.compactMap { $0.value?.doubleValue }
            let avg = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
            groups.append(ActivityGroup(name: cls.name, average: avg))
        }
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

    private func refreshClasses() async throws {
        classes = try await container.classesRepository.listClasses()
        // If notebook has no class selected, pick the first one
        if notebookViewModel.currentClassId == nil, let first = classes.first {
            selectClass(id: first.id)
        }
    }

    func ensureClassesLoaded() async {
        if classes.isEmpty {
            try? await refreshClasses()
        }
    }

    func refreshStudentsDirectory() async throws {
        if classes.isEmpty {
            try await refreshClasses()
        }
        allStudents = try await container.studentsRepository.listStudents()

        if selectedStudentsClassId == nil {
            selectedStudentsClassId = classes.first?.id
        }
        if let selectedClassId = selectedStudentsClassId {
            studentsInClass = try await container.classesRepository.listStudentsInClass(classId: selectedClassId)
        } else {
            studentsInClass = []
        }
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

    func refreshRubrics() async throws {
        rubrics = try await container.rubricsRepository.listRubrics()
    }

    func refreshRubricClassLinks() async throws {
        if classes.isEmpty {
            try await refreshClasses()
        }

        var links: [Int64: Set<Int64>] = [:]
        for schoolClass in classes {
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            for evaluation in evaluations {
                if let rubricId = evaluation.rubricId?.int64Value {
                    var classSet = links[rubricId] ?? Set<Int64>()
                    classSet.insert(schoolClass.id)
                    links[rubricId] = classSet
                }
            }
        }
        rubricClassLinks = links
    }

    private func refreshRubricBuilderTeachingUnits(for classId: Int64?) async throws {
        rubricBuilderTeachingUnits = try await plannerTeachingUnits(for: classId)
    }

    func refreshPlanning() async throws {
        let sessions = try await container.plannerRepository.listAllSessions()
        
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let audit = AuditTrace(authorUserId: nil, createdAt: nowInstant, updatedAt: nowInstant, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
        
        // Group sessions into PlanPeriod for UI compatibility
        let dummyPeriod = Period(id: 1, name: "Planificación (\(sessions.count) sesiones)", startAt: nowInstant, endAt: nowInstant, trace: audit)
        
        var unitMap: [Int64: PlanUnit] = [:]
        for session in sessions {
            let uId = session.teachingUnitId
            if unitMap[uId] == nil {
                let unit = UnitPlan(id: uId, periodId: 1, title: session.teachingUnitName, objectives: "", competences: "", trace: audit)
                unitMap[uId] = PlanUnit(unit: unit, sessions: [])
            }
            let updatedUnit = unitMap[uId]!
            var updatedSessions = updatedUnit.sessions
            let sessionPlan = SessionPlan(id: session.id, unitId: uId, date: nowInstant, description: session.activities, trace: audit)
            updatedSessions.append(sessionPlan)
            unitMap[uId] = PlanUnit(unit: updatedUnit.unit, sessions: updatedSessions)
        }
        
        let planPeriod = PlanPeriod(period: dummyPeriod, units: Array(unitMap.values))
        self.planning = [planPeriod]
    }

    // MARK: - Planner iOS (Week Grid + Copy/Move)
    func plannerTimeSlots() -> [TimeSlotConfig] {
        container.plannerRepository.getTimeSlots()
    }

    func plannerListSessions(weekNumber: Int, year: Int, classId: Int64? = nil) async throws -> [PlanningSession] {
        let sessions = try await container.plannerRepository.listSessions(weekNumber: Int32(weekNumber), year: Int32(year))
        guard let classId else { return sessions }
        return sessions.filter { $0.groupId == classId }
    }

    func plannerWeeklySlots(classId: Int64?) -> [WeeklySlotTemplate] {
        if let classId {
            return container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
        }
        return classes.flatMap { container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: $0.id) }
    }

    private func plannerTeachingUnitName(for teachingUnitId: Int64, cachedUnits: [TeachingUnit]) -> String? {
        cachedUnits.first(where: { $0.id == teachingUnitId })?.name
    }

    private func resolvePlannerTeachingUnit(
        classId: Int64,
        teachingUnitId: Int64?,
        newTeachingUnitName: String?
    ) async throws -> TeachingUnit {
        let existingUnits = try await plannerTeachingUnits(for: classId)
        if let teachingUnitId,
           let found = existingUnits.first(where: { $0.id == teachingUnitId }) {
            return found
        }

        let normalizedName = newTeachingUnitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let existing = existingUnits.first(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            return existing
        }

        let classColor = plannerCourseColor(for: classId)
        let unit = TeachingUnit(
            id: 0,
            name: normalizedName.isEmpty ? "Sesión" : normalizedName,
            description: "",
            colorHex: classColor,
            groupId: KotlinLong(value: classId),
            schoolClassId: KotlinLong(value: classId),
            startDate: nil,
            endDate: nil
        )
        let savedId = try await container.plannerRepository.upsertTeachingUnit(unit: unit).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "teaching_unit",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": savedId,
                "name": unit.name,
                "description": unit.description,
                "colorHex": unit.colorHex,
                "groupId": classId,
                "schoolClassId": classId
            ]
        )
        return TeachingUnit(
            id: savedId,
            name: unit.name,
            description: unit.description,
            colorHex: unit.colorHex,
            groupId: unit.groupId,
            schoolClassId: unit.schoolClassId,
            startDate: unit.startDate,
            endDate: unit.endDate
        )
    }

    private func resolvePlannerAssessmentLinks(
        classId: Int64,
        teachingUnit: TeachingUnit,
        selectedInstruments: [PlannerAssessmentInstrument]
    ) async throws -> String {
        var resolvedTokens: [String] = []
        for instrument in selectedInstruments {
            switch instrument.kind {
            case .evaluation:
                if let evaluationId = instrument.evaluationId {
                    try await ensureNotebookColumnForEvaluation(
                        classId: classId,
                        evaluationId: evaluationId,
                        title: instrument.title,
                        rubricId: instrument.rubricId
                    )
                    resolvedTokens.append("evaluation:\(evaluationId)")
                }
            case .rubric:
                guard let rubricId = instrument.rubricId else { continue }
                let evaluationId = try await ensureEvaluationForRubric(
                    classId: classId,
                    rubricId: rubricId,
                    teachingUnit: teachingUnit,
                    title: instrument.title
                )
                resolvedTokens.append("rubric:\(rubricId)")
                resolvedTokens.append("evaluation:\(evaluationId)")
            }
        }
        return Array(Set(resolvedTokens)).sorted().joined(separator: ",")
    }

    private func ensureEvaluationForRubric(
        classId: Int64,
        rubricId: Int64,
        teachingUnit: TeachingUnit,
        title: String
    ) async throws -> Int64 {
        let code = "PLN-RUB-\(rubricId)-SA-\(teachingUnit.id)"
        let existing = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
            .first { $0.code == code }
        let evaluationId = if let existing {
            existing.id
        } else {
            try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: code,
                name: title,
                type: "Rúbrica",
                weight: 1.0,
                formula: nil,
                rubricId: KotlinLong(value: rubricId),
                description: teachingUnit.name,
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: nil,
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
        }
        try await ensureNotebookColumnForEvaluation(classId: classId, evaluationId: evaluationId, title: title, rubricId: rubricId)
        return evaluationId
    }

    private func ensureNotebookColumnForEvaluation(
        classId: Int64,
        evaluationId: Int64,
        title: String,
        rubricId: Int64?
    ) async throws {
        if try await container.notebookRepository.getColumnIdForEvaluation(evaluationId: evaluationId) != nil {
            return
        }
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let targetTabId: String
        if let first = tabs.first?.id {
            targetTabId = first
        } else {
            let createdTitle = try await container.notebookRepository.createTab(classId: classId, tabName: "Evaluación")
            let refreshedTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
            targetTabId = refreshedTabs.first(where: { $0.title == createdTitle })?.id ?? refreshedTabs.first?.id ?? "TAB_\(classId)"
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let columnType: NotebookColumnType = rubricId == nil ? .numeric : .rubric
        let column = NotebookColumnDefinition(
            id: "eval_\(evaluationId)",
            title: title,
            type: columnType,
            categoryKind: .evaluation,
            instrumentKind: rubricId == nil ? .writtenTest : .rubric,
            inputKind: rubricId == nil ? .numeric010 : .rubric,
            evaluationId: KotlinLong(value: evaluationId),
            rubricId: rubricId.map { KotlinLong(value: $0) },
            formula: nil,
            weight: 1.0,
            dateEpochMs: nil,
            unitOrSituation: nil,
            competencyCriteriaIds: [],
            scaleKind: .tenPoint,
            tabIds: [targetTabId],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: -1,
            widthDp: 0.0,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: true,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: nowInstant,
                updatedAt: nowInstant,
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
    }

    func plannerTeacherSchedule() async throws -> TeacherSchedule {
        try await container.teacherScheduleRepository.getOrCreatePrimarySchedule()
    }

    func plannerCourseColor(for classId: Int64) -> String {
        if let stored = plannerCourseColorByClassId[String(classId)],
           let normalized = normalizeHexColor(stored) {
            return normalized
        }
        let palette = Self.plannerCoursePalette
        let index = Int(abs(classId) % Int64(palette.count))
        return palette[index]
    }

    func plannerCourseColors(for classIds: [Int64]) -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: classIds.map { ($0, plannerCourseColor(for: $0)) })
    }

    func plannerSetCourseColor(_ colorHex: String, for classId: Int64) {
        let normalized = normalizeHexColor(colorHex) ?? plannerCourseColor(for: classId)
        plannerCourseColorByClassId[String(classId)] = normalized
        UserDefaults.standard.set(plannerCourseColorByClassId, forKey: "planner.class.colors.v1")
    }

    func plannerTeacherScheduleSlots(scheduleId: Int64) async throws -> [TeacherScheduleSlot] {
        try await container.teacherScheduleRepository.listScheduleSlots(scheduleId: scheduleId)
    }

    func plannerEvaluationPeriods(scheduleId: Int64) async throws -> [PlannerEvaluationPeriod] {
        try await container.teacherScheduleRepository.listEvaluationPeriods(scheduleId: scheduleId)
    }

    func plannerForecast(scheduleId: Int64, classId: Int64? = nil) async throws -> [PlannerSessionForecast] {
        try await container.teacherScheduleRepository.buildForecasts(
            scheduleId: scheduleId,
            classId: classId.map { KotlinLong(value: $0) }
        )
    }

    func plannerNonTeachingCalendarEvents(classId: Int64? = nil) async throws -> [CalendarEvent] {
        let events = try await container.calendarRepository.listEvents(classId: classId.map { KotlinLong(value: $0) })
        return events
            .filter { isNonTeachingCalendarEvent(title: $0.title, description: $0.description_) }
            .sorted { $0.startAt.toEpochMilliseconds() < $1.startAt.toEpochMilliseconds() }
    }

    func plannerSaveTeacherSchedule(
        scheduleId: Int64,
        ownerUserId: Int64,
        academicYearId: Int64,
        name: String,
        startDateIso: String,
        endDateIso: String,
        activeWeekdaysCsv: String,
        trace: AuditTrace
    ) async throws -> Int64 {
        try await container.teacherScheduleRepository.saveSchedule(
            schedule: TeacherSchedule(
                id: scheduleId,
                ownerUserId: ownerUserId,
                academicYearId: academicYearId,
                name: name,
                startDateIso: startDateIso,
                endDateIso: endDateIso,
                activeWeekdaysCsv: activeWeekdaysCsv,
                trace: trace
            )
        ).int64Value
    }

    func plannerSaveTeacherScheduleSlot(
        scheduleId: Int64,
        classId: Int64,
        subjectLabel: String,
        unitLabel: String?,
        dayOfWeek: Int,
        startTime: String,
        endTime: String,
        editingSlotId: Int64? = nil,
        existingWeeklyTemplateId: Int64? = nil
    ) async throws -> Int64 {
        let existing = try await container.teacherScheduleRepository.listScheduleSlots(scheduleId: scheduleId)
        let normalizedStart = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        let collides = existing.contains {
            if let editingSlotId, $0.id == editingSlotId { return false }
            guard $0.schoolClassId == classId, Int($0.dayOfWeek) == dayOfWeek else { return false }
            return rangesOverlap(startA: $0.startTime, endA: $0.endTime, startB: normalizedStart, endB: normalizedEnd)
        }
        if collides {
            throw NSError(domain: "Planner", code: -320, userInfo: [NSLocalizedDescriptionKey: "La franja docente se solapa con otra del mismo grupo"])
        }

        let weeklyTemplateId = try await {
            _ = try await plannerSaveWeeklySlot(
                classId: classId,
                dayOfWeek: dayOfWeek,
                startTime: normalizedStart,
                endTime: normalizedEnd,
                editingSlotId: existingWeeklyTemplateId
            )
            let refreshed = container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
            return refreshed.first {
                $0.dayOfWeek == Int32(dayOfWeek) && $0.startTime == normalizedStart && $0.endTime == normalizedEnd
            }?.id ?? existingWeeklyTemplateId ?? 0
        }()

        return try await container.teacherScheduleRepository.saveScheduleSlot(
            slot: TeacherScheduleSlot(
                id: editingSlotId ?? 0,
                teacherScheduleId: scheduleId,
                schoolClassId: classId,
                subjectLabel: subjectLabel,
                unitLabel: unitLabel,
                dayOfWeek: Int32(dayOfWeek),
                startTime: normalizedStart,
                endTime: normalizedEnd,
                weeklyTemplateId: weeklyTemplateId == 0 ? nil : KotlinLong(value: weeklyTemplateId)
            )
        ).int64Value
    }

    func plannerDeleteTeacherScheduleSlot(slotId: Int64) async throws {
        if let slot = try await container.teacherScheduleRepository.getScheduleSlot(slotId: slotId),
           let weeklyTemplateId = slot.weeklyTemplateId {
            try? await container.weeklyTemplateRepository.delete(slotId: weeklyTemplateId.int64Value)
        }
        try await container.teacherScheduleRepository.deleteScheduleSlot(slotId: slotId)
    }

    func plannerSaveEvaluationPeriod(
        periodId: Int64,
        scheduleId: Int64,
        name: String,
        startDateIso: String,
        endDateIso: String,
        sortOrder: Int
    ) async throws -> Int64 {
        try await container.teacherScheduleRepository.saveEvaluationPeriod(
            period: PlannerEvaluationPeriod(
                id: periodId,
                teacherScheduleId: scheduleId,
                name: name,
                startDateIso: startDateIso,
                endDateIso: endDateIso,
                sortOrder: Int32(sortOrder)
            )
        ).int64Value
    }

    func plannerDeleteEvaluationPeriod(periodId: Int64) async throws {
        try await container.teacherScheduleRepository.deleteEvaluationPeriod(periodId: periodId)
    }

    func plannerSaveWeeklySlot(
        classId: Int64,
        dayOfWeek: Int,
        startTime: String,
        endTime: String,
        editingSlotId: Int64? = nil
    ) async throws -> Int64 {
        let existing = container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
        let normalizedStart = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        let collides = existing.contains {
            if let editingSlotId, $0.id == editingSlotId { return false }
            guard $0.dayOfWeek == Int32(dayOfWeek) else { return false }
            return rangesOverlap(startA: $0.startTime, endA: $0.endTime, startB: normalizedStart, endB: normalizedEnd)
        }
        if collides {
            throw NSError(domain: "Planner", code: -310, userInfo: [NSLocalizedDescriptionKey: "La franja se solapa con otra del mismo grupo"])
        }

        let duplicated = existing.contains {
            if let editingSlotId, $0.id == editingSlotId { return false }
            return $0.dayOfWeek == Int32(dayOfWeek) && $0.startTime == normalizedStart
        }
        if duplicated {
            throw NSError(domain: "Planner", code: -311, userInfo: [NSLocalizedDescriptionKey: "Ya existe una franja con el mismo inicio"])
        }

        if let editingSlotId {
            enqueueLocalChange(
                entity: "weekly_slot",
                id: "\(editingSlotId)",
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                payload: [
                    "id": editingSlotId,
                    "schoolClassId": classId
                ],
                op: "delete"
            )
            try await container.weeklyTemplateRepository.delete(slotId: editingSlotId)
        }

        let insertedId = try await container.weeklyTemplateRepository.insert(
            slot: WeeklySlotTemplate(
                id: 0,
                schoolClassId: classId,
                dayOfWeek: Int32(dayOfWeek),
                startTime: normalizedStart,
                endTime: normalizedEnd
            )
        )
        let updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "weekly_slot",
            id: "\(insertedId.int64Value)",
            updatedAtEpochMs: updatedAtEpochMs,
            payload: [
                "id": insertedId.int64Value,
                "schoolClassId": classId,
                "dayOfWeek": dayOfWeek,
                "startTime": normalizedStart,
                "endTime": normalizedEnd
            ]
        )
        return insertedId.int64Value
    }

    func plannerDeleteWeeklySlot(slotId: Int64) async throws {
        let existingSlot = plannerWeeklySlots(classId: nil).first(where: { $0.id == slotId })
        try await container.weeklyTemplateRepository.delete(slotId: slotId)
        enqueueLocalChange(
            entity: "weekly_slot",
            id: "\(slotId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": slotId,
                "schoolClassId": existingSlot?.schoolClassId ?? 0
            ],
            op: "delete"
        )
    }

    func plannerUpsertSession(
        id: Int64,
        teachingUnitId: Int64,
        teachingUnitName: String,
        teachingUnitColor: String,
        groupId: Int64,
        groupName: String,
        dayOfWeek: Int,
        period: Int,
        weekNumber: Int,
        year: Int,
        objectives: String,
        activities: String,
        evaluation: String,
        linkedAssessmentIdsCsv: String = "",
        status: SessionStatus
    ) async throws -> Int64 {
        let session = PlanningSession(
            id: id,
            teachingUnitId: teachingUnitId,
            teachingUnitName: teachingUnitName,
            teachingUnitColor: teachingUnitColor,
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: Int32(dayOfWeek),
            period: Int32(period),
            weekNumber: Int32(weekNumber),
            year: Int32(year),
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            linkedAssessmentIdsCsv: linkedAssessmentIdsCsv,
            status: status
        )
        let sessionId = try await container.plannerRepository.upsertSession(session: session).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(sessionId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": sessionId,
                "teachingUnitId": teachingUnitId,
                "teachingUnitName": teachingUnitName,
                "teachingUnitColor": teachingUnitColor,
                "groupId": groupId,
                "groupName": groupName,
                "dayOfWeek": dayOfWeek,
                "period": period,
                "weekNumber": weekNumber,
                "year": year,
                "objectives": objectives,
                "activities": activities,
                "evaluation": evaluation,
                "linkedAssessmentIdsCsv": linkedAssessmentIdsCsv,
                "status": status.name
            ]
        )
        return sessionId
    }

    func plannerDeleteSession(sessionId: Int64) async throws {
        try await container.plannerRepository.deleteSession(sessionId: sessionId)
    }

    func plannerJournal(for session: PlanningSession) async throws -> SessionJournalAggregate {
        try await container.sessionJournalRepository.getOrCreateJournal(session: session)
    }

    func plannerJournalSummaries(sessionIds: [Int64]) async throws -> [SessionJournalSummary] {
        try await container.sessionJournalRepository.listSummariesForSessions(
            planningSessionIds: sessionIds.map { KotlinLong(value: $0) }
        )
    }

    func plannerSaveJournal(_ aggregate: SessionJournalAggregate) async throws -> Int64 {
        try await container.sessionJournalRepository.saveJournalAggregate(aggregate: aggregate).int64Value
    }

    func plannerRegisterJournalIncident(
        session: PlanningSession,
        title: String,
        detail: String
    ) async throws -> SessionJournalLink {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let incidentId = try await container.incidentsRepository.saveIncident(
            id: nil,
            classId: session.groupId,
            studentId: nil,
            title: title,
            detail: detail,
            severity: "medium",
            dateEpochMs: nowMs,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        return SessionJournalLink(
            id: 0,
            journalId: 0,
            type: .incident,
            targetId: "incident_\(incidentId.int64Value)",
            label: title
        )
    }

    func plannerPreviewRelocation(
        sourceSessionIds: [Int64],
        targetGroupId: Int64? = nil,
        targetDayOfWeek: Int? = nil,
        targetPeriod: Int? = nil,
        dayOffset: Int = 0,
        periodOffset: Int = 0
    ) async throws -> [SessionRelocationConflict] {
        let request = SessionRelocationRequest(
            sourceSessionIds: sourceSessionIds.map { KotlinLong(value: $0) },
            targetGroupId: targetGroupId.map { KotlinLong(value: $0) },
            targetDayOfWeek: targetDayOfWeek.map { KotlinInt(value: Int32($0)) },
            targetPeriod: targetPeriod.map { KotlinInt(value: Int32($0)) },
            dayOffset: Int32(dayOffset),
            periodOffset: Int32(periodOffset)
        )
        return try await container.plannerRepository.previewSessionRelocation(request: request)
    }

    func plannerCopySessions(
        sourceSessionIds: [Int64],
        targetGroupId: Int64?,
        targetDayOfWeek: Int? = nil,
        targetPeriod: Int? = nil,
        dayOffset: Int = 0,
        periodOffset: Int = 0,
        resolution: CollisionResolution
    ) async throws -> SessionBulkResult {
        let request = SessionRelocationRequest(
            sourceSessionIds: sourceSessionIds.map { KotlinLong(value: $0) },
            targetGroupId: targetGroupId.map { KotlinLong(value: $0) },
            targetDayOfWeek: targetDayOfWeek.map { KotlinInt(value: Int32($0)) },
            targetPeriod: targetPeriod.map { KotlinInt(value: Int32($0)) },
            dayOffset: Int32(dayOffset),
            periodOffset: Int32(periodOffset)
        )
        return try await container.plannerRepository.doCopySessions(request: request, resolution: resolution)
    }

    func plannerShiftSessions(
        sourceSessionIds: [Int64],
        dayOffset: Int = 0,
        periodOffset: Int = 0,
        resolution: CollisionResolution
    ) async throws -> SessionBulkResult {
        let request = SessionRelocationRequest(
            sourceSessionIds: sourceSessionIds.map { KotlinLong(value: $0) },
            targetGroupId: nil,
            targetDayOfWeek: nil,
            targetPeriod: nil,
            dayOffset: Int32(dayOffset),
            periodOffset: Int32(periodOffset)
        )
        return try await container.plannerRepository.shiftSelectedSessions(request: request, resolution: resolution)
    }

    private func rangesOverlap(startA: String, endA: String, startB: String, endB: String) -> Bool {
        guard let a0 = plannerMinutes(startA), let a1 = plannerMinutes(endA), let b0 = plannerMinutes(startB), let b1 = plannerMinutes(endB) else {
            return false
        }
        return max(a0, b0) < min(a1, b1)
    }

    private func isNonTeachingCalendarEvent(title: String, description: String?) -> Bool {
        let haystack = [title, description ?? ""]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let markers = ["festivo", "no lectivo", "vacaciones", "puente", "holiday"]
        return markers.contains { haystack.contains($0) }
    }

    private func plannerMinutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private func date(from session: PlanningSession) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.yearForWeekOfYear = Int(session.year)
        components.weekOfYear = Int(session.weekNumber)
        components.weekday = Int(session.dayOfWeek) + 1
        return components.date ?? Date.distantPast
    }

    func createClass(name: String, course: Int32) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let classId = try await container.saveClass.invoke(
            id: nil,
            name: name,
            course: course,
            description: nil,
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
                "description": NSNull()
            ]
        )
        return classId.int64Value
    }

    func createStudentAndAssignToClass(firstName: String, lastName: String, classId: Int64) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let studentId = try await container.saveStudent.invoke(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
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
                "isInjured": false
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
    }

    func createStudentInSelectedClass(firstName: String, lastName: String, isInjured: Bool = false) async throws {
        guard let classId = selectedStudentsClassId else {
            throw NSError(domain: "KMP", code: -20, userInfo: [NSLocalizedDescriptionKey: "Selecciona una clase primero"])
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let studentId = try await container.studentsRepository.saveStudent(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            isInjured: isInjured,
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
                "isInjured": isInjured
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
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

    func attendanceSessions(for classId: Int64, on date: Date) async throws -> [AttendanceSessionSnapshot] {
        let calendar = Calendar(identifier: .iso8601)
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
        let weekday = isoWeekday(from: date)
        let sessions = try await plannerListSessions(weekNumber: weekOfYear, year: yearForWeek, classId: classId)
            .filter { Int($0.dayOfWeek) == weekday }
            .sorted { $0.period < $1.period }
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.planningSessionId, $0) })
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
        let summariesById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.planningSessionId, $0) })
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

    func saveAttendance(
        studentId: Int64,
        classId: Int64,
        on date: Date,
        status: String,
        note: String = "",
        hasIncident: Bool = false
    ) async throws {
        let dateEpochMs = startOfDayEpochMs(for: date)
        let existing = try await container.attendanceRepository.listAttendanceByDate(classId: classId, dateEpochMs: dateEpochMs)
            .first(where: { $0.studentId == studentId })
        let linkedSessionId = try await attendanceSessions(for: classId, on: date).first?.session.id
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.attendanceRepository.saveAttendance(
            id: kotlinLong(existing?.id),
            studentId: studentId,
            classId: classId,
            dateEpochMs: dateEpochMs,
            status: status,
            note: note,
            hasIncident: hasIncident,
            followUpRequired: hasIncident,
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
                "note": note,
                "hasIncident": hasIncident,
                "sessionId": linkedSessionId ?? NSNull()
            ]
        )
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
            let sessionDateById = Dictionary(uniqueKeysWithValues: sessions.map { session in
                (session.id, self.date(from: session))
            })
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
            journalDateByJournalId = Dictionary(uniqueKeysWithValues: journalAggregates.map { aggregate in
                let sessionDate = sessionDateById[aggregate.journal.planningSessionId] ?? Date.distantPast
                return (aggregate.journal.id, sessionDate)
            })
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

        let evaluationsById = Dictionary(uniqueKeysWithValues: evaluationsData.map { ($0.id, $0) })
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
                dataQualityNote: summary.evaluationCount == 0 ? "No hay evaluaciones registradas todavía; el relato debe ser prudente." : nil
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
                    dataQualityNote: "El informe individual requiere selección de alumno."
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
                dataQualityNote: profile.instrumentsCount == 0 ? "Hay poca evidencia evaluativa registrada; conviene evitar conclusiones fuertes." : nil
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
                dataQualityNote: values.isEmpty ? "Hay estructura evaluativa, pero faltan calificaciones para una síntesis más sólida." : nil
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
                dataQualityNote: journalSummaries.isEmpty ? "El resumen operativo se apoya más en asistencia e incidencias que en diarios completos." : nil
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
                    dataQualityNote: "El comentario LOMLOE es individual y requiere selección de alumno."
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
                dataQualityNote: numericScore == nil ? "Si hay poca nota numérica, el comentario debe apoyarse en evidencias, actitud y progreso observado." : nil
            )
        }
    }

    func loadTemplates(kind: ConfigTemplateKind? = nil) async throws -> [ConfigTemplate] {
        try await container.configurationTemplateRepository.listTemplates(kind: kind)
    }

    func loadTemplateVersions(templateId: Int64) async throws -> [ConfigTemplateVersion] {
        try await container.configurationTemplateRepository.listTemplateVersions(templateId: templateId)
    }

    func loadRubricUsage(rubricId: Int64) async throws -> RubricUsageSnapshot {
        if classes.isEmpty {
            try await refreshClasses()
        }

        var usages: [RubricUsageSnapshot.EvaluationUsage] = []
        for schoolClass in classes {
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            let matching = evaluations.filter { $0.rubricId?.int64Value == rubricId }
            usages.append(contentsOf: matching.map { evaluation in
                RubricUsageSnapshot.EvaluationUsage(
                    classId: schoolClass.id,
                    className: schoolClass.name,
                    evaluationId: evaluation.id,
                    evaluationName: evaluation.name,
                    evaluationType: evaluation.type,
                    weight: evaluation.weight
                )
            })
        }

        let classNames = Array(Set(usages.map(\.className))).sorted()
        return RubricUsageSnapshot(
            rubricId: rubricId,
            classCount: classNames.count,
            evaluationCount: usages.count,
            linkedClassNames: classNames,
            evaluationUsages: usages.sorted { lhs, rhs in
                if lhs.className == rhs.className {
                    return lhs.evaluationName.localizedCaseInsensitiveCompare(rhs.evaluationName) == .orderedAscending
                }
                return lhs.className.localizedCaseInsensitiveCompare(rhs.className) == .orderedAscending
            }
        )
    }

    func loadPhysicalTests(classId: Int64) async throws -> [PhysicalTestSnapshot] {
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)

        let physicalEvaluations = evaluations.filter { evaluation in
            let normalized = "\(evaluation.type) \(evaluation.name) \(evaluation.description)".lowercased()
            return normalized.contains("physical")
                || normalized.contains("física")
                || normalized.contains("fisica")
                || normalized.contains("prueba")
                || normalized.contains("test")
        }

        return physicalEvaluations.map { evaluation in
            let evaluationGrades = grades.filter { $0.evaluationId?.int64Value == evaluation.id }
            let gradesByStudent = Dictionary(uniqueKeysWithValues: evaluationGrades.map { ($0.studentId, $0) })
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

    func loadPESessions(weekNumber: Int, year: Int, classId: Int64?) async throws -> [PESessionSnapshot] {
        let sessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.planningSessionId, $0) })

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

    private func startOfDayEpochMs(for date: Date) -> Int64 {
        Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970 * 1000)
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

    private func compactSuggestions(_ values: String?...) -> [String] {
        values.compactMap {
            guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
    }

    private func courseLabel(for schoolClass: SchoolClass) -> String {
        let lowercasedName = schoolClass.name.lowercased()
        if lowercasedName.contains("bach") {
            return "\(schoolClass.course)º Bachillerato"
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

    func pairLanSync(
        host: String,
        pin: String,
        expectedServerId: String? = nil,
        expectedFingerprint: String? = nil
    ) async throws {
        let normalizedHost = LanSyncClient.normalizeHost(host)
        guard !normalizedHost.isEmpty else {
            throw NSError(
                domain: "Sync",
                code: -204,
                userInfo: [NSLocalizedDescriptionKey: "Introduce un host LAN válido para el desktop."]
            )
        }

        let result = try await lanSyncClient.handshake(
            host: normalizedHost,
            pin: pin,
            deviceId: localDeviceId,
            pinnedFingerprint: expectedFingerprint
        )
        if let expectedServerId, expectedServerId != result.serverId {
            throw NSError(domain: "Sync", code: -203, userInfo: [NSLocalizedDescriptionKey: "Server ID no coincide con el esperado"])
        }

        let previousToken = syncToken
        let previousHost = pairedSyncHost
        let previousServerId = pairedServerId
        let previousFingerprint = pairedServerFingerprint

        syncToken = result.token
        pairedSyncHost = normalizedHost
        pairedServerId = result.serverId
        pairedServerFingerprint = result.certificateFingerprint

        do {
            try await performPullSync(silent: true, sinceEpochMsOverride: 0)
            persistSyncSecrets()
            syncStatusMessage = "Emparejado con \(normalizedHost)"
        } catch {
            syncToken = previousToken
            pairedSyncHost = previousHost
            pairedServerId = previousServerId
            pairedServerFingerprint = previousFingerprint
            throw NSError(
                domain: "Sync",
                code: -205,
                userInfo: [
                    NSLocalizedDescriptionKey: "El desktop respondió al emparejamiento, pero no al primer pull. Verifica que siga abierto y escuchando en la misma LAN. Detalle: \(error.localizedDescription)"
                ]
            )
        }

        await syncNow(reason: "pairing", forceFullPull: false, silent: true)
    }

    func unpairLanSync() async {
        if let host = pairedSyncHost, let token = syncToken {
            _ = try? await lanSyncClient.unpair(host: host, token: token, pinnedFingerprint: pairedServerFingerprint)
        }
        clearPersistedPairing()
        syncStatusMessage = "Desvinculado. Empareja de nuevo para reactivar la sync."
    }

    func discoveredPeer(forHost host: String) -> LanDiscoveredPeer? {
        discoveredPeersByHost[host]
    }

    func runLanPullSync() async throws {
        try await performPullSync(silent: false)
    }

    func pullMissingSyncChanges() async {
        do {
            try await performPullSync(silent: false)
        } catch {
            syncStatusMessage = "Pull manual fallido: \(error.localizedDescription)"
        }
    }

    func createLocalBackup(fileName: String = "mi_gestor_backup.sqlite") async throws -> BackupResult {
        try await container.backupService.createBackup(fileName: fileName)
    }

    func restoreLocalBackup(from path: String) async throws -> Bool {
        try await container.backupService.restoreBackup(backupPath: path).boolValue
    }

    func runLanPushSync() async throws {
        try await performPushSync(silent: false)
    }

    private func performPullSync(silent: Bool, sinceEpochMsOverride: Int64? = nil) async throws {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -40, userInfo: [NSLocalizedDescriptionKey: "No hay emparejamiento activo"])
        }

        let cursor = sinceEpochMsOverride ?? lastSyncCursorEpochMs
        let pull: LanPullResult
        do {
            pull = try await lanSyncClient.pull(
                host: host,
                token: token,
                sinceEpochMs: cursor,
                pinnedFingerprint: pairedServerFingerprint
            )
        } catch {
            guard recoverHostAfterNetworkChange(previousHost: host), let reboundHost = pairedSyncHost else {
                throw error
            }
            pull = try await lanSyncClient.pull(
                host: reboundHost,
                token: token,
                sinceEpochMs: cursor,
                pinnedFingerprint: pairedServerFingerprint
            )
        }
        
        // Si no hay cambios, no hacemos nada más.
        guard !pull.changes.isEmpty else {
            lastSyncCursorEpochMs = pull.serverEpochMs
            UserDefaults.standard.set(lastSyncCursorEpochMs, forKey: "sync.last.cursor")
            syncLastRunAt = Date()
            return
        }

        try await applyPulledChanges(pull.changes)
        lastSyncCursorEpochMs = pull.serverEpochMs
        UserDefaults.standard.set(lastSyncCursorEpochMs, forKey: "sync.last.cursor")
        syncPendingChanges = pendingOutboundChanges.count
        syncLastRunAt = Date()
        if !silent {
            syncStatusMessage = "Pull OK (\(pull.changeCount) cambios)"
        }

        try await refreshDashboard()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        try await refreshRubrics()
        try await refreshRubricClassLinks()
        try await refreshPlanning()

        // Solo refrescar el cuaderno si alguno de los cambios sincronizados
        // afecta a entidades del cuaderno (grades, columnas, celdas, rúbricas).
        // Esto evita recargas innecesarias cuando solo cambian clases o alumnos.
        let notebookEntityTypes: Set<String> = [
            "grade", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_cell", "rubric_assessment", "student", "class_roster", "evaluation", "notebook_group", "notebook_group_member"
        ]
        let hasNotebookChangesFromRemote = pull.changes.contains {
            notebookEntityTypes.contains($0.entity) && $0.deviceId != localDeviceId
        }
        if hasNotebookChangesFromRemote {
            refreshCurrentNotebook()
        }
    }

    private func performPushSync(silent: Bool) async throws {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -41, userInfo: [NSLocalizedDescriptionKey: "No hay emparejamiento activo"])
        }
        guard !pendingOutboundChanges.isEmpty else {
            if !silent {
                syncStatusMessage = "No hay cambios pendientes"
            }
            return
        }

        let applied: Int
        do {
            applied = try await lanSyncClient.push(
                host: host,
                token: token,
                deviceId: localDeviceId,
                changes: pendingOutboundChanges,
                lastKnownServerEpochMs: lastSyncCursorEpochMs,
                pinnedFingerprint: pairedServerFingerprint
            )
        } catch {
            guard recoverHostAfterNetworkChange(previousHost: host), let reboundHost = pairedSyncHost else {
                throw error
            }
            applied = try await lanSyncClient.push(
                host: reboundHost,
                token: token,
                deviceId: localDeviceId,
                changes: pendingOutboundChanges,
                lastKnownServerEpochMs: lastSyncCursorEpochMs,
                pinnedFingerprint: pairedServerFingerprint
            )
        }
        if applied > 0 {
            pendingOutboundChanges.removeAll()
            UserDefaults.standard.removeObject(forKey: "sync.pending.changes.v2")
        }
        syncPendingChanges = pendingOutboundChanges.count
        syncLastRunAt = Date()
        if !silent {
            syncStatusMessage = "Push OK (\(applied) aplicados)"
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
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveEvaluation.invoke(
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

    func setSelectedNotebookTab(id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        selectedNotebookTabId = normalized
        notebookViewModel.setSelectedTabId(tabId: normalized)
        rememberSelectedNotebookTab(normalized, forClassId: notebookViewModel.currentClassId?.int64Value)
    }
    
    func saveColumnGrade(studentId: Int64, column: NotebookColumnDefinition, value: String) {
        notebookViewModel.saveColumnGrade(studentId: studentId, column: column, value: value)
        invalidateNotebookCellValueIndexCache()
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleGradeSnapshotSync(forClassId: classId)
        }
    }

    func saveColumnGradeDebounced(
        studentId: Int64,
        column: NotebookColumnDefinition,
        value: String,
        debounceMs: UInt64 = 360
    ) {
        let key = cellKey(studentId: studentId, columnId: column.id)
        pendingDebouncedGradeSaves[key]?.cancel()
        pendingDebouncedGradeSaves[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            guard !Task.isCancelled else { return }
            self.saveColumnGrade(studentId: studentId, column: column, value: value)
            self.pendingDebouncedGradeSaves[key] = nil
        }
    }

    func flushPendingColumnGradeSave(studentId: Int64, columnId: String? = nil) {
        if let columnId {
            let key = cellKey(studentId: studentId, columnId: columnId)
            pendingDebouncedGradeSaves[key]?.cancel()
            pendingDebouncedGradeSaves[key] = nil
            return
        }

        let prefix = "\(studentId)|"
        for key in pendingDebouncedGradeSaves.keys where key.hasPrefix(prefix) {
            pendingDebouncedGradeSaves[key]?.cancel()
            pendingDebouncedGradeSaves[key] = nil
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

    func saveNotebookWorkGroup(name: String) {
        notebookViewModel.saveWorkGroup(name: name, groupId: nil, studentIds: [])
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func updateNotebookWorkGroup(groupId: Int64, name: String) {
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: [])
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func renameNotebookWorkGroup(groupId: Int64, name: String) {
        updateNotebookWorkGroup(groupId: groupId, name: name)
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

    func assignStudentsToNotebookGroup(groupId: Int64?, studentIds: [Int64]) {
        notebookViewModel.assignStudentsToWorkGroup(
            groupId: groupId.map { KotlinLong(value: $0) },
            studentIds: studentIds.map { KotlinLong(value: $0) }
        )
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
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
        let newTab = NotebookTab(id: tabId, title: normalizedTitle, description: nil, order: order, parentTabId: parentTabId, trace: trace)
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

    func saveNotebookCellAnnotation(
        studentId: Int64,
        columnId: String,
        note: String,
        iconValue: String? = nil,
        attachmentUris: [String] = []
    ) {
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

    func updateColumnWeight(columnId: Int64, newWeight: Double) {
        notebookViewModel.updateColumnWeight(columnId: columnId, newWeight: newWeight)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }
    
    func loadForNotebookCell(studentId: Int64, columnId: String, rubricId: Int64, evaluationId: Int64) {
        rubricEvaluationViewModel.loadForNotebookCell(studentId: studentId, columnId: columnId, rubricId: rubricId, evaluationId: evaluationId)
    }

    func saveRubricEvaluation(manual: Bool = true, onSuccess: @escaping () -> Void = {}) {
        rubricEvaluationViewModel.save(manual: manual) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshCurrentNotebook()
                if let classId = self.notebookViewModel.currentClassId?.int64Value {
                    self.scheduleNotebookSnapshotSync(forClassId: classId)
                }
                onSuccess()
            }
        }
    }
    
    func startBulkRubricEvaluation(column: NotebookColumnDefinition) {
        guard let classId = notebookViewModel.currentClassId?.int64Value,
              let evaluationId = column.evaluationId?.int64Value,
              let rubricId = column.rubricId?.int64Value else {
            return
        }
        // Evitamos que quede una evaluación individual abierta detrás del panel masivo.
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
        rubricBulkEvaluationViewModel.load(
            classId: classId,
            evaluationId: evaluationId,
            rubricId: rubricId,
            columnId: column.id,
            tabId: nil
        )
        showingBulkRubricEvaluation = true
    }
    
    func closeBulkRubricEvaluation() {
        showingBulkRubricEvaluation = false
        // Al cerrar la masiva, limpiamos cualquier overlay individual residual.
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
    }

    func closeRubricEvaluation() {
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
    }

    func refreshCurrentNotebook() {
        guard let classId = notebookViewModel.currentClassId?.int64Value else { return }
        let preservedTab = selectedNotebookTabId ?? restoredSelectedNotebookTab(forClassId: classId)
        notebookViewModel.setSelectedTabId(tabId: preservedTab)
        notebookViewModel.selectClass(classId: classId, force: true)
    }

    private func restoredSelectedNotebookTab(forClassId classId: Int64?) -> String? {
        guard let classId else { return nil }
        return selectedNotebookTabByClassId["\(classId)"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func rememberSelectedNotebookTab(_ tabId: String?, forClassId classId: Int64?) {
        guard let classId else { return }
        let key = "\(classId)"
        if let tabId = tabId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            selectedNotebookTabByClassId[key] = tabId
        } else {
            selectedNotebookTabByClassId.removeValue(forKey: key)
        }
        UserDefaults.standard.set(selectedNotebookTabByClassId, forKey: "notebook.selected.tab.by.class.v1")
    }
    
    func bulkSelectLevel(studentId: Int64, criterionId: Int64, levelId: Int64) {
        rubricBulkEvaluationViewModel.selectLevel(studentId: studentId, criterionId: criterionId, levelId: levelId)
    }
    
    func bulkSelectedLevelId(studentId: Int64, criterionId: Int64) -> Int64? {
        guard let state = bulkRubricEvaluationState,
              let studentMap = state.assessments[KotlinLong(value: studentId)] else {
            return nil
        }
        return studentMap[KotlinLong(value: criterionId)]?.int64Value
    }
    
    func bulkScore(studentId: Int64) -> Double? {
        bulkRubricEvaluationState?.scores[KotlinLong(value: studentId)]?.doubleValue
    }
    
    func bulkSaveAllAndClose() {
        rubricBulkEvaluationViewModel.saveAll()
        showingBulkRubricEvaluation = false
    }

    func bulkSaveAll() {
        rubricBulkEvaluationViewModel.saveAll()
    }

    func bulkCopyAssessment(studentId: Int64) {
        rubricBulkEvaluationViewModel.doCopyAssessment(studentId: studentId)
    }

    func bulkPasteAssessment(studentId: Int64) {
        rubricBulkEvaluationViewModel.pasteAssessment(studentId: studentId)
    }

    func duplicateNotebookStructure(to targetClassId: Int64) async throws {
        guard let sourceClassId = notebookViewModel.currentClassId?.int64Value else {
            throw NSError(
                domain: "KMP",
                code: -61,
                userInfo: [NSLocalizedDescriptionKey: "No hay curso origen seleccionado"]
            )
        }

        try await container.notebookRepository.duplicateConfigToClass(
            sourceClassId: sourceClassId,
            targetClassId: targetClassId
        )

        scheduleNotebookSnapshotSync(forClassId: targetClassId)
        try await refreshRubricClassLinks()
        status = "Estructura duplicada correctamente"
    }

    func createRubric(name: String, criterion: String, level: String, points: Int32) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCriterion = criterion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLevel = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "KMP", code: -12, userInfo: [NSLocalizedDescriptionKey: "La rúbrica no puede estar vacía"])
        }
        guard !trimmedCriterion.isEmpty else {
            throw NSError(domain: "KMP", code: -13, userInfo: [NSLocalizedDescriptionKey: "El criterio no puede estar vacío"])
        }
        guard !trimmedLevel.isEmpty else {
            throw NSError(domain: "KMP", code: -14, userInfo: [NSLocalizedDescriptionKey: "El nivel no puede estar vacío"])
        }
        guard points >= 0 else {
            throw NSError(domain: "KMP", code: -15, userInfo: [NSLocalizedDescriptionKey: "Los puntos deben ser un valor positivo"])
        }

        try await container.createRubricBundle(
            name: trimmedName,
            criterion: trimmedCriterion,
            level: trimmedLevel,
            points: points
        )

        try await refreshRubrics()
        try await refreshRubricClassLinks()
    }

    // Proxy Methods for RubricsViewModel
    func resetRubricBuilder() {
        selectedRubricTeachingUnitId = nil
        rubricBuilderTeachingUnits = []
        rubricsViewModel.resetBuilder()
    }

    func loadRubricForEditing(_ rubric: RubricDetail) {
        rubricsViewModel.loadRubric(rubricDetail: rubric)
        let classId = rubric.rubric.classId?.int64Value
        let teachingUnitId = rubric.rubric.teachingUnitId?.int64Value
        if let classId {
            selectRubricClass(classId)
            Task { @MainActor in
                try? await refreshRubricBuilderTeachingUnits(for: classId)
                selectedRubricTeachingUnitId = teachingUnitId
            }
        } else {
            selectedRubricTeachingUnitId = teachingUnitId
            rubricBuilderTeachingUnits = []
        }
    }

    func deleteRubric(id: Int64) {
        enqueueLocalChange(
            entity: "rubric_bundle",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["rubricId": id],
            op: "delete"
        )
        rubricsViewModel.deleteRubric(rubricId: id)
        Task {
            try? await refreshRubrics()
            try? await refreshRubricClassLinks()
        }
    }

    func startAssignRubric(_ rubric: Rubric) {
        rubricsViewModel.startAssignRubricToClass(rubric: rubric)
    }

    func setRubricFilterClass(_ classId: Int64?) {
        let kotlinId = classId.map { KotlinLong(value: $0) }
        rubricsViewModel.setFilterClass(classId: kotlinId)
    }

    func onAssignClassSelected(_ classId: Int64) {
        rubricsViewModel.onAssignClassSelected(classId: classId)
    }

    func onAssignTabSelected(_ tabName: String) {
        rubricsViewModel.onAssignTabSelected(tabName: tabName)
    }

    func onToggleCreateNewTab(_ create: Bool) {
        rubricsViewModel.onToggleCreateNewTab(create: create)
    }

    func onNewTabNameChanged(_ name: String) {
        rubricsViewModel.onNewTabNameChanged(name: name)
    }

    func confirmAssignRubric() {
        rubricsViewModel.confirmAssignRubric()
        Task {
            try? await refreshRubricClassLinks()
            refreshCurrentNotebook()
        }
    }

    func dismissAssignRubricDialog() {
        rubricsViewModel.dismissAssignDialog()
    }

    func updateRubricName(_ name: String) {
        rubricsViewModel.updateRubricName(name: name)
    }

    func updateRubricInstructions(_ text: String) {
        rubricsViewModel.updateInstructions(text: text)
    }

    func selectRubricClass(_ classId: Int64?) {
        let kotlinId = classId.map { KotlinLong(value: $0) }
        rubricsViewModel.selectClass(classId: kotlinId)
        selectedRubricTeachingUnitId = nil
        Task { @MainActor in
            try? await refreshRubricBuilderTeachingUnits(for: classId)
        }
    }

    func selectRubricTeachingUnit(_ teachingUnitId: Int64?) {
        selectedRubricTeachingUnitId = teachingUnitId
    }

    func applyRubricPreset(_ preset: String) {
        rubricsViewModel.applyPresetLevels(preset: preset)
    }

    func addRubricLevel() {
        rubricsViewModel.addLevel()
    }

    func removeRubricLevel(at index: Int) {
        rubricsViewModel.removeLevel(index: Int32(index))
    }

    func updateRubricLevelName(at index: Int, name: String) {
        rubricsViewModel.updateLevelName(index: Int32(index), name: name)
    }

    func updateRubricLevelPoints(at index: Int, points: Int) {
        rubricsViewModel.updateLevelPoints(index: Int32(index), points: Int32(points))
    }

    func addRubricCriterion() {
        rubricsViewModel.addCriterion()
    }

    func removeRubricCriterion(at index: Int) {
        rubricsViewModel.removeCriterion(index: Int32(index))
    }

    func updateRubricCriterionDescription(at index: Int, description: String) {
        rubricsViewModel.updateCriterionDescription(index: Int32(index), description: description)
    }

    func updateRubricCriterionWeight(at index: Int, weight: Double) {
        rubricsViewModel.updateCriterionWeight(index: Int32(index), weight: weight)
    }

    func updateRubricLevelDescription(criterionIndex: Int, levelUid: String, description: String) {
        rubricsViewModel.updateLevelDescription(criterionIndex: Int32(criterionIndex), levelUid: levelUid, description: description)
    }

    func saveRubricFromBuilder(onComplete: @escaping (Bool) -> Void) {
        guard let state = rubricsUiState else {
            onComplete(false)
            return
        }

        Task { @MainActor in
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            do {
                let rubricId = try await container.rubricsRepository.saveRubric(
                    id: nil,
                    name: state.rubricName,
                    description: state.instructions.nilIfBlank,
                    classId: state.selectedClassId,
                    teachingUnitId: selectedRubricTeachingUnitId.map { KotlinLong(value: $0) },
                    createdAtEpochMs: nowMs,
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: 1
                ).int64Value

                for criterion in state.criteria {
                    let criterionId = try await container.rubricsRepository.saveCriterion(
                        id: nil,
                        rubricId: rubricId,
                        description: criterion.description_,
                        weight: criterion.weight,
                        order: Int32(criterion.order),
                        updatedAtEpochMs: nowMs,
                        deviceId: localDeviceId,
                        syncVersion: 1
                    ).int64Value

                    for level in state.levels {
                        _ = try await container.rubricsRepository.saveLevel(
                            id: nil,
                            criterionId: criterionId,
                            name: level.name,
                            points: Int32(level.points),
                            description: criterion.levelDescriptions[level.uid],
                            order: Int32(level.order),
                            updatedAtEpochMs: nowMs,
                            deviceId: localDeviceId,
                            syncVersion: 1
                        )
                    }
                }

                enqueueLocalChange(
                    entity: "rubric_bundle",
                    id: "\(rubricId)",
                    updatedAtEpochMs: nowMs,
                    payload: [
                        "rubricId": rubricId,
                        "name": state.rubricName,
                        "description": state.instructions.nilIfBlank ?? NSNull(),
                        "classId": state.selectedClassId?.int64Value ?? NSNull(),
                        "teachingUnitId": selectedRubricTeachingUnitId ?? NSNull(),
                        "criteria": state.criteria.map { criterion in
                            [
                                "description": criterion.description_,
                                "weight": criterion.weight,
                                "order": Int(criterion.order),
                                "levels": state.levels.map { level in
                                    [
                                        "name": level.name,
                                        "points": Int(level.points),
                                        "description": criterion.levelDescriptions[level.uid] ?? "",
                                        "order": Int(level.order)
                                    ]
                                }
                            ]
                        }
                    ]
                )

                try? await refreshRubrics()
                try? await refreshRubricClassLinks()
                if let classId = state.selectedClassId?.int64Value {
                    try? await refreshRubricBuilderTeachingUnits(for: classId)
                }
                onComplete(true)
            } catch {
                onComplete(false)
            }
        }
    }

    func plannerTeachingUnits(for classId: Int64?) async throws -> [TeachingUnit] {
        let units = try await container.plannerRepository.listAllTeachingUnits()
        guard let classId else { return units }
        return units
            .filter {
                ($0.schoolClassId?.int64Value == classId) || ($0.groupId?.int64Value == classId)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func plannerAvailableAssessmentInstruments(classId: Int64, teachingUnitId: Int64?) async throws -> [PlannerAssessmentInstrument] {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let rubricDetails = try await container.rubricsRepository.listRubrics()
        let classUnits = try await plannerTeachingUnits(for: classId)

        let evaluationInstruments = evaluations.map { evaluation in
            PlannerAssessmentInstrument(
                kind: .evaluation,
                rawId: evaluation.id,
                title: evaluation.name,
                subtitle: evaluation.type,
                classId: classId,
                teachingUnitId: nil,
                evaluationId: evaluation.id,
                rubricId: evaluation.rubricId?.int64Value,
                resolvedEvaluationId: evaluation.id
            )
        }

        let rubricInstruments = rubricDetails.compactMap { detail -> PlannerAssessmentInstrument? in
            let rubric = detail.rubric
            let rubricClassId = rubric.classId?.int64Value
            if let rubricClassId, rubricClassId != classId {
                return nil
            }
            return PlannerAssessmentInstrument(
                kind: .rubric,
                rawId: rubric.id,
                title: rubric.name,
                subtitle: rubric.teachingUnitId.flatMap { kotlinLongVal -> String? in
                    plannerTeachingUnitName(for: kotlinLongVal.int64Value, cachedUnits: classUnits)
                } ?? "Rúbrica",
                classId: classId,
                teachingUnitId: rubric.teachingUnitId?.int64Value,
                evaluationId: nil,
                rubricId: rubric.id,
                resolvedEvaluationId: nil
            )
        }

        let prioritized = rubricInstruments.sorted { lhs, rhs in
            let lhsMatch = lhs.teachingUnitId == teachingUnitId
            let rhsMatch = rhs.teachingUnitId == teachingUnitId
            if lhsMatch != rhsMatch { return lhsMatch && !rhsMatch }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return (evaluationInstruments + prioritized).sorted {
            if $0.kind != $1.kind { return $0.kind == .rubric }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func plannerSaveSessionWithLinks(
        id: Int64,
        groupId: Int64,
        groupName: String,
        dayOfWeek: Int,
        period: Int,
        weekNumber: Int,
        year: Int,
        teachingUnitId: Int64?,
        newTeachingUnitName: String?,
        objectives: String,
        activities: String,
        selectedInstruments: [PlannerAssessmentInstrument]
    ) async throws -> PlannerSessionSaveResult {
        let resolvedTeachingUnit = try await resolvePlannerTeachingUnit(
            classId: groupId,
            teachingUnitId: teachingUnitId,
            newTeachingUnitName: newTeachingUnitName
        )
        let linkedIds = try await resolvePlannerAssessmentLinks(
            classId: groupId,
            teachingUnit: resolvedTeachingUnit,
            selectedInstruments: selectedInstruments
        )
        let evaluationSummary = selectedInstruments.map(\.title).joined(separator: " · ")

        let sessionId = try await plannerUpsertSession(
            id: id,
            teachingUnitId: resolvedTeachingUnit.id,
            teachingUnitName: resolvedTeachingUnit.name,
            teachingUnitColor: resolvedTeachingUnit.colorHex,
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: dayOfWeek,
            period: period,
            weekNumber: weekNumber,
            year: year,
            objectives: objectives,
            activities: activities,
            evaluation: evaluationSummary,
            linkedAssessmentIdsCsv: linkedIds,
            status: .planned
        )

        return PlannerSessionSaveResult(
            sessionId: sessionId,
            teachingUnitId: resolvedTeachingUnit.id,
            teachingUnitName: resolvedTeachingUnit.name,
            evaluationSummary: evaluationSummary,
            linkedAssessmentIdsCsv: linkedIds
        )
    }

    func createPlanning(periodName: String, unitTitle: String, sessionDescription: String) async throws {
        let current = IsoWeekHelper.shared.current()
        let weekNum = current.first?.int32Value ?? 0
        let yearNum = current.second?.int32Value ?? 0
        
        let unit = TeachingUnit(
            id: 0,
            name: unitTitle,
            description: "Periodo: \(periodName)",
            colorHex: "#4A90D9",
            groupId: nil,
            schoolClassId: nil,
            startDate: nil,
            endDate: nil
        )
        
        let unitId = try await container.plannerRepository.upsertTeachingUnit(unit: unit)

        let session = PlanningSession(
            id: 0,
            teachingUnitId: Int64(truncating: unitId),
            teachingUnitName: unitTitle,
            teachingUnitColor: "#4A90D9",
            groupId: 0,
            groupName: "",
            dayOfWeek: 1,
            period: 1,
            weekNumber: weekNum,
            year: yearNum,
            objectives: "",
            activities: sessionDescription,
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            status: SessionStatus.planned
        )
        
        try await container.plannerRepository.upsertSession(session: session)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(weekNum)-\(yearNum)-\(unitId.int64Value)-1",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": NSNull(),
                "teachingUnitId": unitId.int64Value,
                "teachingUnitName": unitTitle,
                "teachingUnitColor": "#4A90D9",
                "groupId": 0,
                "groupName": "",
                "dayOfWeek": 1,
                "period": 1,
                "weekNumber": Int(weekNum),
                "year": Int(yearNum),
                "objectives": "",
                "activities": sessionDescription,
                "evaluation": "",
                "linkedAssessmentIdsCsv": "",
                "status": "PLANNED"
            ]
        )
        
        try await refreshPlanning()
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

    private func enqueueLocalChange(entity: String, id: String, updatedAtEpochMs: Int64, payload: [String: Any], op: String = "upsert", shouldPersist: Bool = true) {
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
        syncPendingChanges = pendingOutboundChanges.count
        
        if shouldPersist {
            persistPendingChanges()
        }
        triggerAutoSyncSoon()
    }

    private func persistPendingChanges() {
        if let encoded = try? JSONEncoder().encode(pendingOutboundChanges) {
            UserDefaults.standard.set(encoded, forKey: "sync.pending.changes.v2")
        }
    }

    private func invalidateNotebookCellValueIndexCache() {
        cachedNotebookStateIdentity = nil
        cachedNotebookCellValueIndex = nil
    }

    private func scheduleGradeSnapshotSync(forClassId classId: Int64) {
        pendingGradeSnapshotTask?.cancel()
        pendingGradeSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            try? await self.enqueueNotebookSnapshot(forClassId: classId)
        }
    }

    private func scheduleNotebookSnapshotSync(forClassId classId: Int64) {
        notebookSnapshotDebounceTask?.cancel()
        notebookSnapshotDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            try? await self.enqueueNotebookSnapshot(forClassId: classId)
        }
    }

    private func enqueueNotebookSnapshot(forClassId classId: Int64) async throws {
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        let columnCategories = try await container.notebookConfigRepository.listColumnCategories(classId: classId, tabId: nil)
        let workGroups = try await container.notebookConfigRepository.listWorkGroups(classId: classId, tabId: nil)
        let workGroupMembers = try await container.notebookConfigRepository.listWorkGroupMembers(classId: classId, tabId: nil)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        let cells = try await container.notebookCellsRepository.listClassCells(classId: classId)
        let rubricEvaluations = evaluations.filter { $0.rubricId?.int64Value ?? 0 > 0 }

        students.forEach { student in
            notebookSyncCache.deviceIdByEntityId["\(student.id)"] = student.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "student",
                id: "\(student.id)",
                updatedAtEpochMs: student.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": student.id,
                    "firstName": student.firstName,
                    "lastName": student.lastName,
                    "email": student.email ?? NSNull(),
                    "photoPath": student.photoPath ?? NSNull(),
                    "isInjured": student.isInjured
                ],
                shouldPersist: false
            )
        }

        enqueueLocalChange(
            entity: "class_roster",
            id: "\(classId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "classId": classId,
                "studentIds": students.map(\.id).sorted()
            ],
            shouldPersist: false
        )

        evaluations.forEach { evaluation in
            notebookSyncCache.deviceIdByEntityId["\(evaluation.id)"] = evaluation.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "evaluation",
                id: "\(evaluation.id)",
                updatedAtEpochMs: evaluation.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": evaluation.id,
                    "classId": evaluation.classId,
                    "code": evaluation.code,
                    "name": evaluation.name,
                    "type": evaluation.type,
                    "weight": evaluation.weight,
                    "formula": evaluation.formula ?? "",
                    "rubricId": evaluation.rubricId ?? 0,
                    "description": evaluation.description
                ],
                shouldPersist: false
            )
        }

        tabs.forEach { tab in
            notebookSyncCache.deviceIdByEntityId[tab.id] = tab.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_tab",
                id: tab.id,
                updatedAtEpochMs: tab.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": tab.id,
                    "classId": classId,
                    "title": tab.title,
                    "description": tab.description,
                    "order": Int(tab.order),
                    "parentTabId": tab.parentTabId ?? ""
                ],
                shouldPersist: false
            )
        }

        workGroups.forEach { group in
            let groupId = "\(group.id)"
            notebookSyncCache.deviceIdByEntityId[groupId] = group.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_group",
                id: groupId,
                updatedAtEpochMs: group.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": group.id,
                    "classId": classId,
                    "tabId": group.tabId,
                    "name": group.name,
                    "order": Int(group.order)
                ],
                shouldPersist: false
            )
        }

        workGroupMembers.forEach { member in
            let memberId = "\(member.classId)|\(member.tabId)|\(member.groupId)|\(member.studentId)"
            notebookSyncCache.deviceIdByEntityId[memberId] = member.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_group_member",
                id: memberId,
                updatedAtEpochMs: member.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "classId": member.classId,
                    "tabId": member.tabId,
                    "groupId": member.groupId,
                    "studentId": member.studentId
                ],
                shouldPersist: false
            )
        }

        columnCategories.forEach { category in
            notebookSyncCache.deviceIdByEntityId[category.id] = category.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_column_category",
                id: category.id,
                updatedAtEpochMs: category.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": category.id,
                    "classId": category.classId,
                    "tabId": category.tabId,
                    "name": category.name,
                    "order": Int(category.order),
                    "isCollapsed": category.isCollapsed
                ],
                shouldPersist: false
            )
        }

        columns.forEach { column in
            notebookSyncCache.deviceIdByEntityId[column.id] = column.trace.deviceId ?? localDeviceId
            let tabTitlesById = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.title) })
            let tabTitlesCsv = column.tabIds.compactMap { tabTitlesById[$0] }.joined(separator: ",")
            enqueueLocalChange(
                entity: "notebook_column",
                id: column.id,
                updatedAtEpochMs: column.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": column.id,
                    "classId": classId,
                    "title": column.title,
                    "type": column.type.name,
                    "column_type": column.type.name,
                    "evaluationId": column.evaluationId ?? 0,
                    "rubricId": column.rubricId ?? 0,
                    "formula": column.formula ?? "",
                    "weight": column.weight,
                    "tabIdsCsv": column.tabIds.joined(separator: ","),
                    "tab_ids_csv": column.tabIds.joined(separator: ","),
                    "tabTitlesCsv": tabTitlesCsv,
                    "tab_titles_csv": tabTitlesCsv,
                    "categoryId": column.categoryId ?? "",
                    "category_id": column.categoryId ?? "",
                    "sharedAcrossTabs": column.sharedAcrossTabs,
                    "shared_across_tabs": column.sharedAcrossTabs,
                    "colorHex": column.colorHex ?? ""
                ],
                shouldPersist: false
            )
        }

        grades.forEach { grade in
            enqueueLocalChange(
                entity: "grade",
                id: "\(grade.classId)-\(grade.studentId)-\(grade.columnId)",
                updatedAtEpochMs: grade.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "classId": grade.classId,
                    "studentId": grade.studentId,
                    "columnId": grade.columnId,
                    "evaluationId": grade.evaluationId ?? 0,
                    "value": grade.value ?? NSNull()
                ],
                shouldPersist: false
            )
        }

        cells.forEach { cell in
            enqueueLocalChange(
                entity: "notebook_cell",
                id: "\(cell.classId)-\(cell.studentId)-\(cell.columnId)",
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000), // cells no tienen trace todavía
                payload: [
                    "classId": cell.classId,
                    "studentId": cell.studentId,
                    "columnId": cell.columnId,
                    "textValue": cell.textValue ?? NSNull(),
                    "boolValue": cell.boolValue?.boolValue ?? NSNull(),
                    "iconValue": cell.iconValue ?? NSNull(),
                    "ordinalValue": cell.ordinalValue ?? NSNull(),
                    "note": cell.annotation?.note ?? NSNull(),
                    "colorHex": cell.annotation?.colorHex ?? NSNull(),
                    "attachmentUris": cell.annotation?.attachmentUris ?? []
                ],
                shouldPersist: false
            )
        }

        for evaluation in rubricEvaluations {
            for student in students {
                let assessments = try await container.rubricsRepository.listRubricAssessments(
                    studentId: student.id,
                    evaluationId: evaluation.id
                )
                assessments.forEach { assessment in
                    enqueueLocalChange(
                        entity: "rubric_assessment",
                        id: "\(assessment.studentId)-\(assessment.evaluationId)-\(assessment.criterionId)",
                        updatedAtEpochMs: assessment.trace.updatedAt.toEpochMilliseconds(),
                        payload: [
                            "studentId": assessment.studentId,
                            "evaluationId": assessment.evaluationId,
                            "criterionId": assessment.criterionId,
                            "levelId": assessment.levelId
                        ],
                        shouldPersist: false
                    )
                }
            }
        }

        enqueueNotebookDeletes(
            entity: "evaluation",
            classId: classId,
            currentIds: Set(evaluations.map { "\($0.id)" }),
            payloadForId: { id in ["id": Int64(id) ?? 0] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_tab",
            classId: classId,
            currentIds: Set(tabs.map(\.id)),
            payloadForId: { id in ["id": id] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_group",
            classId: classId,
            currentIds: Set(workGroups.map { "group-\($0.id)" }),
            payloadForId: { id in ["id": Int64(id.replacingOccurrences(of: "group-", with: "")) ?? 0] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_group_member",
            classId: classId,
            currentIds: Set(workGroupMembers.map { "group-member-\($0.classId)-\($0.tabId)-\($0.groupId)-\($0.studentId)" }),
            payloadForId: { id in
                let parts = id.replacingOccurrences(of: "group-member-", with: "").split(separator: "-").map(String.init)
                return [
                    "classId": Int64(parts[safe: 0] ?? "") ?? 0,
                    "tabId": parts[safe: 1] ?? "",
                    "groupId": Int64(parts[safe: 2] ?? "") ?? 0,
                    "studentId": Int64(parts[safe: 3] ?? "") ?? 0
                ]
            }
        )
        enqueueNotebookDeletes(
            entity: "notebook_column",
            classId: classId,
            currentIds: Set(columns.map(\.id)),
            payloadForId: { id in ["id": id] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_column_category",
            classId: classId,
            currentIds: Set(columnCategories.map(\.id)),
            payloadForId: { id in ["id": id, "classId": classId] }
        )
        
        // Persistencia final de todos los cambios del snapshot
        persistPendingChanges()
    }

    private func enqueueNotebookDeletes(
        entity: String,
        classId: Int64,
        currentIds: Set<String>,
        payloadForId: (String) -> [String: Any]
    ) {
        let scopeKey = notebookSyncScopeKey(classId: classId, entity: entity)
        let previousIds = Set(notebookSyncCache.entityIdsByScope[scopeKey] ?? [])
        
        // SEGURIDAD: Si currentIds está vacío pero antes teníamos datos para esta clase,
        // es probable que sea un error de carga de snapshot. Evitamos borrar todo.
        if currentIds.isEmpty && !previousIds.isEmpty {
            return
        }

        let deletedIds = previousIds.subtracting(currentIds)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        deletedIds.forEach { deletedId in
            // SEGURIDAD: Solo encolamos el borrado si nosotros éramos los dueños de este ID
            // O si no tenemos registro de quién lo creó (fallback conservador).
            // Esto evita que iOS mande a borrar columnas de Desktop solo porque no las ve en "algunos" snapshots.
            let ownerId = notebookSyncCache.deviceIdByEntityId[deletedId]
            if let ownerId = ownerId, ownerId != localDeviceId {
                // El dueño es otro dispositivo, no lo borramos nosotros del sync queue local.
                return
            }

            // SEGURIDAD ADICIONAL: Si el deletedId empieza por COL_ pero tenemos un eval_ equivalente en currentIds,
            // no lo mandamos a borrar como 'delete' porque es una migración local controlada por el repositorio KMP.
            if deletedId.hasPrefix("COL_") {
                // Posible ID antiguo, lo dejamos que el repositorio KMP lo gestione
                return
            }

            enqueueLocalChange(
                entity: entity,
                id: deletedId,
                updatedAtEpochMs: nowMs,
                payload: payloadForId(deletedId),
                op: "delete",
                shouldPersist: false
            )
            
            // Limpiar el dueño ya que se ha borrado
            notebookSyncCache.deviceIdByEntityId.removeValue(forKey: deletedId)
        }

        notebookSyncCache.entityIdsByScope[scopeKey] = Array(currentIds).sorted()
        persistNotebookSyncCache()
    }

    private func notebookSyncScopeKey(classId: Int64, entity: String) -> String {
        "\(classId)|\(entity)"
    }

    private func persistNotebookSyncCache() {
        if let encoded = try? JSONEncoder().encode(notebookSyncCache) {
            UserDefaults.standard.set(encoded, forKey: "sync.notebook.cache.v1")
        }
    }

    private func applyPulledChanges(_ changes: [LanSyncChange]) async throws {
        for change in orderedPulledChanges(changes) {
            do {
            let payloadData = change.payload.data(using: .utf8) ?? Data()
            let payloadObject = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]

            if change.op == "delete" {
                try await applyDeletedChange(change: change, payloadObject: payloadObject)
                continue
            }

            switch change.entity {
            case "class":
                guard
                    let name = payloadObject["name"] as? String,
                    let course = payloadObject["course"] as? Int
                else { continue }
                let classId = int64Value(payloadObject["id"]) ?? 0
                _ = try await container.classesRepository.saveClass(
                    id: kotlinLong(classId > 0 ? classId : nil),
                    name: name,
                    course: Int32(course),
                    description: payloadObject["description"] as? String,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "student":
                guard
                    let firstName = payloadObject["firstName"] as? String,
                    let lastName = payloadObject["lastName"] as? String
                else { continue }
                let studentId = int64Value(payloadObject["id"]) ?? 0
                _ = try await container.studentsRepository.saveStudent(
                    id: kotlinLong(studentId > 0 ? studentId : nil),
                    firstName: firstName,
                    lastName: lastName,
                    email: payloadObject["email"] as? String,
                    photoPath: payloadObject["photoPath"] as? String,
                    isInjured: payloadObject["isInjured"] as? Bool ?? false,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "student_deleted":
                let studentId = int64Value(payloadObject["id"]) ?? 0
                if studentId > 0 {
                    try await container.studentsRepository.deleteStudent(studentId: studentId)
                }

            case "class_roster":
                let classId = int64Value(payloadObject["classId"]) ?? 0
                guard classId > 0 else { continue }
                let rawStudentIds = payloadObject["studentIds"] as? [Any] ?? []
                let remoteIds = Set(rawStudentIds.compactMap { int64Value($0) })
                let localIds = Set(try await container.classesRepository.listStudentsInClass(classId: classId).map { $0.id })
                for id in remoteIds.subtracting(localIds) {
                    try await container.classesRepository.addStudentToClass(classId: classId, studentId: id)
                }
                for id in localIds.subtracting(remoteIds) {
                    try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: id)
                }

            case "evaluation":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let code = payloadObject["code"] as? String,
                    let name = payloadObject["name"] as? String,
                    let type = payloadObject["type"] as? String,
                    let weight = doubleValue(payloadObject["weight"])
                else { continue }
                let evaluationId = int64Value(payloadObject["id"]) ?? 0
                let rubricId = int64Value(payloadObject["rubricId"])
                _ = try await container.evaluationsRepository.saveEvaluation(
                    id: kotlinLong(evaluationId > 0 ? evaluationId : nil),
                    classId: classId,
                    code: code,
                    name: name,
                    type: type,
                    weight: weight,
                    formula: payloadObject["formula"] as? String,
                    rubricId: kotlinLong(rubricId),
                    description: payloadObject["description"] as? String,
                    authorUserId: nil,
                    createdAtEpochMs: change.updatedAtEpochMs,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "grade":
                let classId = int64Value(payloadObject["classId"]) ?? 0
                let studentId = int64Value(payloadObject["studentId"]) ?? 0
                let receivedColumnId = payloadObject["columnId"] as? String
                let evaluationIdValue = int64Value(payloadObject["evaluationId"])
                
                // Forzar ID estandarizado si tiene evaluación
                let columnId: String
                if let evalId = evaluationIdValue, evalId > 0 {
                    columnId = "eval_\(evalId)"
                } else if let col = receivedColumnId, !col.isEmpty {
                    columnId = col
                } else {
                    columnId = "eval_0"
                }

                if classId > 0, studentId > 0 {
                    try await container.gradesRepository.upsertGrade(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId,
                        evaluationId: kotlinLong(evaluationIdValue),
                        value: doubleValue(payloadObject["value"]).map { KotlinDouble(value: $0) },
                        evidence: nil,
                        evidencePath: nil,
                        rubricSelections: nil,
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                }

            case "weekly_slot":
                guard
                    let classId = int64Value(payloadObject["schoolClassId"] ?? payloadObject["classId"]),
                    let dayOfWeek = int64Value(payloadObject["dayOfWeek"]).map(Int.init),
                    let startTime = payloadObject["startTime"] as? String,
                    let endTime = payloadObject["endTime"] as? String
                else { continue }
                _ = try await container.weeklyTemplateRepository.insert(
                    slot: WeeklySlotTemplate(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        schoolClassId: classId,
                        dayOfWeek: Int32(dayOfWeek),
                        startTime: startTime,
                        endTime: endTime
                    )
                )

            case "notebook_tab":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let tabId = payloadObject["id"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }
                let order = payloadObject["order"] as? Int ?? 0
                let parentTabId = (payloadObject["parentTabId"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let description = (payloadObject["description"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                try await container.notebookRepository.saveTab(
                    classId: classId,
                    tab: NotebookTab(
                        id: tabId,
                        title: title,
                        description: description,
                        order: Int32(order),
                        parentTabId: parentTabId,
                        trace: trace
                    )
                )

            case "notebook_group":
                guard
                    let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]),
                    let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String),
                    let name = payloadObject["name"] as? String
                else { continue }
                let groupId = int64Value(payloadObject["id"]) ?? int64Value(payloadObject["group_id"]) ?? 0
                let order = (payloadObject["order"] as? Int) ?? (int64Value(payloadObject["order"]).map { Int($0) }) ?? 0
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                _ = try await container.notebookRepository.saveWorkGroup(
                    classId: classId,
                    workGroup: NotebookWorkGroup(
                        id: groupId,
                        classId: classId,
                        tabId: tabId,
                        name: name,
                        order: Int32(order),
                        trace: trace
                    )
                )

            case "notebook_group_member":
                guard
                    let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]),
                    let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String),
                    let groupId = int64Value(payloadObject["groupId"]) ?? int64Value(payloadObject["group_id"]),
                    let studentId = int64Value(payloadObject["studentId"]) ?? int64Value(payloadObject["student_id"])
                else { continue }
                try await container.notebookConfigRepository.assignStudentsToWorkGroup(
                    classId: classId,
                    tabId: tabId,
                    groupId: groupId,
                    studentIds: [KotlinLong(value: studentId)]
                )

            case "notebook_column_category":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let id = payloadObject["id"] as? String,
                    let tabId = payloadObject["tabId"] as? String,
                    let name = payloadObject["name"] as? String
                else { continue }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                try await container.notebookRepository.saveColumnCategory(
                    classId: classId,
                    category: NotebookColumnCategory(
                        id: id,
                        classId: classId,
                        tabId: tabId,
                        name: name,
                        order: Int32(payloadObject["order"] as? Int ?? 0),
                        isCollapsed: boolValue(payloadObject["isCollapsed"] ?? payloadObject["is_collapsed"]) ?? false,
                        trace: trace
                    )
                )

            case "notebook_column":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let _ = payloadObject["id"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let type = notebookColumnType(
                    from: (payloadObject["type"] as? String) ?? (payloadObject["column_type"] as? String)
                )
                let evaluationIdValue = int64Value(payloadObject["evaluationId"]).flatMap { $0 > 0 ? $0 : nil }
                let rubricId = int64Value(payloadObject["rubricId"]).flatMap { $0 > 0 ? $0 : nil }
                
                let resolvedColumnId: String = {
                    if let evalId = evaluationIdValue, evalId > 0 { return "eval_\(evalId)" }
                    return payloadObject["id"] as? String ?? UUID().uuidString
                }()

                let rawTabIds: [String] = {
                    if let csv = payloadObject["tabIdsCsv"] as? String {
                        return csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } else if let csv = payloadObject["tab_ids_csv"] as? String {
                        return csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } else if let arr = (payloadObject["tabIdsCsv"] ?? payloadObject["tabIds"]) as? [String] {
                        return arr
                    } else if let arr = (payloadObject["tab_ids_csv"] ?? payloadObject["tab_ids"]) as? [String] {
                        return arr
                    } else {
                        return []
                    }
                }()

                let existingTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
                let incomingTitles = parseDelimitedStringList(payloadObject["tabTitlesCsv"] ?? payloadObject["tab_titles_csv"])
                let resolvedTabIds = resolveNotebookColumnTabIds(
                    rawTabIds: rawTabIds,
                    incomingTitles: incomingTitles,
                    existingTabs: existingTabs
                )

                let sharedAcrossTabs = boolValue(payloadObject["sharedAcrossTabs"] ?? payloadObject["shared_across_tabs"]) ?? false
                let finalTabIds = sharedAcrossTabs ? existingTabs.map { $0.id } : resolvedTabIds
                let colorHex = normalizeHexColor(payloadObject["colorHex"] as? String)
                let formula = payloadObject["formula"] as? String
                let categoryIdRaw = (payloadObject["categoryId"] as? String) ?? (payloadObject["category_id"] as? String)
                let categoryId = categoryIdRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? categoryIdRaw : nil

                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

                // Evita perder columnas sincronizadas por FK cuando la evaluación aún no
                // ha llegado en este pull (desfase de cursores u orden de cambios).
                if let evalId = evaluationIdValue {
                    let existingEval = try await container.evaluationsRepository.getEvaluation(evaluationId: evalId)
                    if existingEval == nil {
                        let payloadType = (payloadObject["type"] as? String) ?? (payloadObject["column_type"] as? String) ?? "Evaluación"
                        _ = try await container.evaluationsRepository.saveEvaluation(
                            id: KotlinLong(value: evalId),
                            classId: classId,
                            code: "SYNC_\(evalId)",
                            name: title,
                            type: payloadType,
                            weight: doubleValue(payloadObject["weight"]) ?? 1.0,
                            formula: payloadObject["formula"] as? String,
                            rubricId: kotlinLong(rubricId),
                            description: nil,
                            authorUserId: nil,
                            createdAtEpochMs: change.updatedAtEpochMs,
                            updatedAtEpochMs: change.updatedAtEpochMs,
                            associatedGroupId: nil,
                            deviceId: change.deviceId,
                            syncVersion: 1
                        )
                    }
                }

                try await container.notebookRepository.saveColumn(
                    classId: classId,
                    column: NotebookColumnDefinition(
                        id: resolvedColumnId,
                        title: title,
                        type: type,
                        categoryKind: notebookCategoryKind(payloadObject["categoryKind"] as? String),
                        instrumentKind: notebookInstrumentKind(payloadObject["instrumentKind"] as? String),
                        inputKind: notebookInputKind(payloadObject["inputKind"] as? String),
                        evaluationId: kotlinLong(evaluationIdValue),
                        rubricId: kotlinLong(rubricId),
                        formula: formula,
                        weight: doubleValue(payloadObject["weight"]) ?? 1.0,
                        dateEpochMs: kotlinLong(int64Value(payloadObject["dateEpochMs"] ?? payloadObject["date_epoch_ms"])),
                        unitOrSituation: payloadObject["unitOrSituation"] as? String ?? payloadObject["unit_name"] as? String,
                        competencyCriteriaIds: longList(payloadObject["competencyCriteriaIds"] ?? payloadObject["competency_criteria_ids_csv"]),
                        scaleKind: notebookScaleKind(payloadObject["scaleKind"] as? String),
                        tabIds: finalTabIds,
                        sessions: [],
                        sharedAcrossTabs: sharedAcrossTabs,
                        colorHex: colorHex,
                        iconName: payloadObject["iconName"] as? String ?? payloadObject["icon_name"] as? String,
                        order: Int32(payloadObject["order"] as? Int ?? -1),
                        widthDp: doubleValue(payloadObject["widthDp"] ?? payloadObject["width_dp"]) ?? 0.0,
                        categoryId: categoryId,
                        ordinalLevels: [],
                        availableIcons: [],
                        countsTowardAverage: boolValue(payloadObject["countsTowardAverage"] ?? payloadObject["counts_toward_average"]) ?? true,
                        isPinned: boolValue(payloadObject["isPinned"] ?? payloadObject["is_pinned"]) ?? false,
                        isHidden: boolValue(payloadObject["isHidden"] ?? payloadObject["is_hidden"]) ?? false,
                        visibility: notebookColumnVisibility(payloadObject["visibility"] as? String),
                        isLocked: boolValue(payloadObject["isLocked"] ?? payloadObject["is_locked"]) ?? false,
                        isTemplate: boolValue(payloadObject["isTemplate"] ?? payloadObject["is_template"]) ?? false,
                        trace: trace
                    )
                )

            case "notebook_cell":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let studentId = int64Value(payloadObject["studentId"]),
                    let columnId = payloadObject["columnId"] as? String
                else { continue }

                let textValue = payloadObject["textValue"] as? String
                let boolValue = payloadObject["boolValue"] as? Bool
                let iconValue = payloadObject["iconValue"] as? String
                let ordinalValue = payloadObject["ordinalValue"] as? String
                let note = payloadObject["note"] as? String
                let colorHex = normalizeHexColor(payloadObject["colorHex"] as? String)
                let attachmentUris = (payloadObject["attachmentUris"] as? [String]) ?? []

                try await container.notebookRepository.saveCell(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    textValue: textValue?.isEmpty == true ? nil : textValue,
                    boolValue: boolValue.map { KotlinBoolean(value: $0) },
                    iconValue: iconValue?.isEmpty == true ? nil : iconValue,
                    ordinalValue: ordinalValue?.isEmpty == true ? nil : ordinalValue,
                    note: note?.isEmpty == true ? nil : note,
                    colorHex: colorHex?.isEmpty == true ? nil : colorHex,
                    attachmentUris: attachmentUris,
                    authorUserId: nil,
                    associatedGroupId: nil
                )

            case "teaching_unit":
                guard let name = payloadObject["name"] as? String else { continue }
                let unit = TeachingUnit(
                    id: int64Value(payloadObject["id"]) ?? 0,
                    name: name,
                    description: payloadObject["description"] as? String ?? "",
                    colorHex: normalizeHexColor(payloadObject["colorHex"] as? String) ?? "#4A90D9",
                    groupId: kotlinLong(int64Value(payloadObject["groupId"])),
                    schoolClassId: kotlinLong(int64Value(payloadObject["schoolClassId"])),
                    startDate: nil,
                    endDate: nil
                )
                _ = try await container.plannerRepository.upsertTeachingUnit(unit: unit)

            case "planning_session":
                let sessionId = int64Value(payloadObject["id"]) ?? 0
                let teachingUnitId = int64Value(payloadObject["teachingUnitId"]) ?? 0
                let dayOfWeek = payloadObject["dayOfWeek"] as? Int ?? 1
                let period = payloadObject["period"] as? Int ?? 1
                let weekNumber = payloadObject["weekNumber"] as? Int ?? 1
                let year = payloadObject["year"] as? Int ?? 2026
                let statusRaw = (payloadObject["status"] as? String ?? "PLANNED").uppercased()
                let status: SessionStatus
                switch statusRaw {
                case "IN_PROGRESS":
                    status = .inProgress
                case "COMPLETED":
                    status = .completed
                case "CANCELLED":
                    status = .cancelled
                default:
                    status = .planned
                }
                let session = PlanningSession(
                    id: sessionId,
                    teachingUnitId: teachingUnitId,
                    teachingUnitName: payloadObject["teachingUnitName"] as? String ?? "Unidad",
                    teachingUnitColor: payloadObject["teachingUnitColor"] as? String ?? "#4A90D9",
                    groupId: int64Value(payloadObject["groupId"]) ?? 0,
                    groupName: payloadObject["groupName"] as? String ?? "",
                    dayOfWeek: Int32(dayOfWeek),
                    period: Int32(period),
                    weekNumber: Int32(weekNumber),
                    year: Int32(year),
                    objectives: payloadObject["objectives"] as? String ?? "",
                    activities: payloadObject["activities"] as? String ?? "",
                    evaluation: payloadObject["evaluation"] as? String ?? "",
                    linkedAssessmentIdsCsv: payloadObject["linkedAssessmentIdsCsv"] as? String ?? "",
                    status: status
                )
                _ = try await container.plannerRepository.upsertSession(session: session)

            case "rubric_bundle":
                guard let rubricName = payloadObject["name"] as? String else { continue }
                let rubricId = int64Value(payloadObject["rubricId"])
                let savedRubricId = try await container.rubricsRepository.saveRubric(
                    id: kotlinLong(rubricId),
                    name: rubricName,
                    description: payloadObject["description"] as? String,
                    classId: int64Value(payloadObject["classId"]).map { KotlinLong(value: $0) },
                    teachingUnitId: int64Value(payloadObject["teachingUnitId"]).map { KotlinLong(value: $0) },
                    createdAtEpochMs: change.updatedAtEpochMs,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                let criteria = payloadObject["criteria"] as? [[String: Any]] ?? []
                for criterion in criteria {
                    guard let criterionDescription = criterion["description"] as? String else { continue }
                    let criterionId = int64Value(criterion["id"])
                    let savedCriterionId = try await container.rubricsRepository.saveCriterion(
                        id: kotlinLong(criterionId),
                        rubricId: savedRubricId.int64Value,
                        description: criterionDescription,
                        weight: doubleValue(criterion["weight"]) ?? 1.0,
                        order: criterion["order"] as? Int32 ?? Int32(criterion["order"] as? Int ?? 0),
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                    let levels = criterion["levels"] as? [[String: Any]] ?? []
                    for level in levels {
                        guard let levelName = level["name"] as? String else { continue }
                        _ = try await container.rubricsRepository.saveLevel(
                            id: kotlinLong(int64Value(level["id"])),
                            criterionId: savedCriterionId.int64Value,
                            name: levelName,
                            points: level["points"] as? Int32 ?? Int32(level["points"] as? Int ?? 0),
                            description: level["description"] as? String,
                            order: level["order"] as? Int32 ?? Int32(level["order"] as? Int ?? 0),
                            updatedAtEpochMs: change.updatedAtEpochMs,
                            deviceId: change.deviceId,
                            syncVersion: 1
                        )
                    }
                }

            case "attendance":
                guard
                    let studentId = int64Value(payloadObject["studentId"]),
                    let classId = int64Value(payloadObject["classId"]),
                    let dateEpochMs = int64Value(payloadObject["dateEpochMs"]),
                    let status = payloadObject["status"] as? String
                else { continue }
                _ = try await container.attendanceRepository.saveAttendance(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    studentId: studentId,
                    classId: classId,
                    dateEpochMs: dateEpochMs,
                    status: status,
                    note: payloadObject["note"] as? String ?? "",
                    hasIncident: payloadObject["hasIncident"] as? Bool ?? false,
                    followUpRequired: payloadObject["followUpRequired"] as? Bool ?? false,
                    sessionId: kotlinLong(int64Value(payloadObject["sessionId"]).flatMap { $0 > 0 ? $0 : nil }),
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "incident":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let title = payloadObject["title"] as? String,
                    let dateEpochMs = int64Value(payloadObject["dateEpochMs"])
                else { continue }
                _ = try await container.incidentsRepository.saveIncident(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    classId: classId,
                    studentId: kotlinLong(int64Value(payloadObject["studentId"]).flatMap { $0 > 0 ? $0 : nil }),
                    title: title,
                    detail: payloadObject["detail"] as? String,
                    severity: payloadObject["severity"] as? String ?? "low",
                    dateEpochMs: dateEpochMs,
                    authorUserId: nil,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "calendar_event":
                guard
                    let title = payloadObject["title"] as? String,
                    let startEpochMs = int64Value(payloadObject["startEpochMs"]),
                    let endEpochMs = int64Value(payloadObject["endEpochMs"])
                else { continue }
                _ = try await container.calendarRepository.saveEvent(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    classId: kotlinLong(int64Value(payloadObject["classId"]).flatMap { $0 > 0 ? $0 : nil }),
                    title: title,
                    description: payloadObject["description"] as? String,
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs,
                    externalProvider: payloadObject["externalProvider"] as? String,
                    externalId: payloadObject["externalId"] as? String,
                    authorUserId: nil,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "rubric_assessment":
                guard
                    let studentId = int64Value(payloadObject["studentId"]),
                    let evaluationId = int64Value(payloadObject["evaluationId"]),
                    let criterionId = int64Value(payloadObject["criterionId"]),
                    let levelId = int64Value(payloadObject["levelId"])
                else { continue }
                let resolvedScore = try await container.rubricsRepository.saveRubricAssessment(
                    studentId: studentId,
                    evaluationId: evaluationId,
                    criterionId: criterionId,
                    levelId: levelId,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                if let evaluation = try await container.evaluationsRepository.getEvaluation(evaluationId: evaluationId),
                   let classId = int64Value(evaluation.classId),
                   classId > 0 {
                    let columnId = try await container.notebookRepository.getColumnIdForEvaluation(evaluationId: evaluationId) ?? "eval_\(evaluationId)"
                    let allAssessments = try await container.rubricsRepository.listRubricAssessments(
                        studentId: studentId,
                        evaluationId: evaluationId
                    )
                    let selections = allAssessments
                        .map { "\($0.criterionId):\($0.levelId)" }
                        .sorted()
                        .joined(separator: ",")
                    try await container.notebookRepository.upsertGrade(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId,
                        numericValue: resolvedScore?.doubleValue ?? 0.0,
                        rubricSelections: selections.isEmpty ? nil : selections,
                        evidence: nil,
                        createdAtEpochMs: change.updatedAtEpochMs,
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                }

            default:
                continue
            }
            } catch {
                // No abortar el pull completo por un único cambio defectuoso
                // (p.ej. entidad fuera de orden o payload parcial).
                continue
            }
        }
    }

    private func applyDeletedChange(change: LanSyncChange, payloadObject: [String: Any]) async throws {
        switch change.entity {
        case "student_deleted", "student":
            let studentId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if studentId > 0 {
                try await container.studentsRepository.deleteStudent(studentId: studentId)
            }
        case "evaluation":
            let evaluationId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if evaluationId > 0 {
                try await container.evaluationsRepository.deleteEvaluation(evaluationId: evaluationId)
            }
        case "weekly_slot":
            let slotId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if slotId > 0 {
                try await container.weeklyTemplateRepository.delete(slotId: slotId)
            }
        case "notebook_tab":
            let tabId = (payloadObject["id"] as? String) ?? change.id
            if !tabId.isEmpty {
                try await container.notebookRepository.deleteTab(tabId: tabId)
            }
        case "notebook_group":
            let groupId = int64Value(payloadObject["id"]) ?? Int64(change.id.replacingOccurrences(of: "group-", with: "")) ?? 0
            if groupId > 0 {
                try await container.notebookRepository.deleteWorkGroup(groupId: groupId)
            }
        case "notebook_group_member":
            let parts = change.id.contains("|") ? change.id.split(separator: "|") : change.id.split(separator: "-")
            guard
                let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]) ?? (parts.count > 0 ? Int64(parts.last == parts.first ? parts[0] : parts[parts.count-4]) : nil),
                let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String) ?? (parts.count > 1 ? String(parts[parts.count-3]) : nil),
                let studentId = int64Value(payloadObject["studentId"]) ?? int64Value(payloadObject["student_id"]) ?? (parts.count > 3 ? Int64(parts.last!) : nil)
            else { break }
            try await container.notebookConfigRepository.clearStudentsFromWorkGroup(
                classId: classId,
                tabId: tabId,
                studentIds: [KotlinLong(value: studentId)]
            )
        case "notebook_column":
            let columnId = (payloadObject["id"] as? String) ?? change.id
            if !columnId.isEmpty {
                try await container.notebookRepository.deleteColumn(columnId: columnId)
            }
        case "notebook_column_category":
            let categoryId = (payloadObject["id"] as? String) ?? change.id
            let classId = int64Value(payloadObject["classId"]) ?? notebookViewModel.currentClassId?.int64Value ?? 0
            if classId > 0 && !categoryId.isEmpty {
                let preserveColumns = (payloadObject["preserveColumns"] as? Bool) ?? true
                try await container.notebookRepository.deleteColumnCategory(classId: classId, categoryId: categoryId, preserveColumns: preserveColumns)
            }
        case "rubric_bundle":
            let rubricId = int64Value(payloadObject["rubricId"]) ?? Int64(change.id) ?? 0
            if rubricId > 0 {
                try await container.rubricsRepository.deleteRubric(rubricId: rubricId)
            }
        default:
            break
        }
    }

    private func orderedPulledChanges(_ changes: [LanSyncChange]) -> [LanSyncChange] {
        changes.sorted { lhs, rhs in
            let lhsPriority = syncApplyPriority(for: lhs.entity)
            let rhsPriority = syncApplyPriority(for: rhs.entity)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.updatedAtEpochMs != rhs.updatedAtEpochMs {
                return lhs.updatedAtEpochMs < rhs.updatedAtEpochMs
            }
            return lhs.id < rhs.id
        }
    }

    private func resolveNotebookColumnTabIds(
        rawTabIds: [String],
        incomingTitles: [String],
        existingTabs: [NotebookTab]
    ) -> [String] {
        guard !existingTabs.isEmpty else { return [] }

        let tabsById = Dictionary(uniqueKeysWithValues: existingTabs.map { ($0.id.lowercased(), $0.id) })
        var tabsByTitle: [String: String] = [:]
        for tab in existingTabs {
            let key = tab.title.lowercased()
            if tabsByTitle[key] == nil {
                tabsByTitle[key] = tab.id
            }
        }
        let candidateCount = max(rawTabIds.count, incomingTitles.count)
        var resolvedTabIds: [String] = []

        for index in 0..<candidateCount {
            if index < rawTabIds.count,
               let exactId = tabsById[rawTabIds[index].lowercased()] {
                appendResolvedTabId(exactId, into: &resolvedTabIds)
                continue
            }

            guard index < incomingTitles.count else { continue }
            if let matchingTabId = tabsByTitle[incomingTitles[index].lowercased()] {
                appendResolvedTabId(matchingTabId, into: &resolvedTabIds)
            }
        }

        return resolvedTabIds
    }

    private func appendResolvedTabId(_ tabId: String, into resolvedTabIds: inout [String]) {
        guard !resolvedTabIds.contains(tabId) else { return }
        resolvedTabIds.append(tabId)
    }

    private func parseDelimitedStringList(_ value: Any?) -> [String] {
        if let csv = value as? String {
            return csv
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else if let arr = value as? [String] {
            return arr
        } else {
            return []
        }
    }

    private func syncApplyPriority(for entity: String) -> Int {
        switch entity {
        case "class", "student", "rubric_bundle", "teaching_unit", "calendar_event":
            return 0
        case "evaluation", "weekly_slot", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_group", "notebook_group_member":
            return 1
        case "class_roster", "attendance", "incident":
            return 2
        case "grade", "notebook_cell", "rubric_assessment", "planning_session":
            return 3
        case "student_deleted":
            return 4
        default:
            return 5
        }
    }

    private func notebookCellValueIndex() -> NotebookCellValueIndex? {
        guard let data = notebookState as? NotebookUiStateData else { return nil }
        let stateIdentity = ObjectIdentifier(data)
        if cachedNotebookStateIdentity == stateIdentity, let cachedNotebookCellValueIndex {
            return cachedNotebookCellValueIndex
        }

        var index = NotebookCellValueIndex()

        for row in data.sheet.rows {
            let studentId = row.student.id

            for persisted in row.persistedCells {
                let key = cellKey(studentId: studentId, columnId: persisted.columnId)
                if let icon = persisted.iconValue, !icon.isEmpty {
                    index.textByKey[key] = icon
                } else if let text = persisted.textValue, !text.isEmpty {
                    index.textByKey[key] = text
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

        cachedNotebookStateIdentity = stateIdentity
        cachedNotebookCellValueIndex = index
        return index
    }

    func cellText(studentId: Int64, columnId: String) -> String {
        guard let index = notebookCellValueIndex() else { return "" }
        let key = cellKey(studentId: studentId, columnId: columnId)
        return index.textByKey[key] ?? index.textDraftByKey[key] ?? ""
    }
    
    func numericGradeText(studentId: Int64, columnId: String) -> String {
        guard let index = notebookCellValueIndex() else { return "" }
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let persisted = index.numericByKey[key] {
            return persisted
        }
        if let persistedEval = index.numericByEvalKey[key] {
            return persistedEval
        }
        return index.numericDraftByKey[key] ?? ""
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
        guard let index = notebookCellValueIndex() else { return false }
        let key = cellKey(studentId: studentId, columnId: columnId)
        if let persisted = index.checkByKey[key] {
            return persisted
        }
        if let draft = index.checkDraftByKey[key] {
            return draft
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

    private func kotlinLong(_ value: Int64?) -> KotlinLong? {
        value.map { KotlinLong(value: $0) }
    }

    private func int64Value(_ raw: Any?) -> Int64? {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String { return Int64(value) }
        return nil
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Float { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private func boolValue(_ raw: Any?) -> Bool? {
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

    private func longList(_ raw: Any?) -> [KotlinLong] {
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

    private func notebookColumnType(from raw: String?) -> NotebookColumnType {
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

    private func notebookCategoryKind(_ raw: String?) -> NotebookColumnCategoryKind {
        switch raw?.uppercased() {
        case "EVALUATION": return .evaluation
        case "FOLLOW_UP": return .followUp
        case "ATTENDANCE": return .attendance
        case "EXTRAS": return .extras
        case "PHYSICAL_EDUCATION": return .physicalEducation
        default: return .custom
        }
    }

    private func notebookInstrumentKind(_ raw: String?) -> NotebookInstrumentKind {
        switch raw?.uppercased() {
        case "WRITTEN_TEST": return .writtenTest
        case "RUBRIC": return .rubric
        case "SYSTEMATIC_OBSERVATION": return .systematicObservation
        case "CHECKLIST": return .checklist
        case "PARTICIPATION": return .participation
        case "PHYSICAL_TEST": return .physicalTest
        case "MULTIMEDIA_EVIDENCE": return .multimediaEvidence
        default: return .custom
        }
    }

    private func notebookInputKind(_ raw: String?) -> NotebookCellInputKind {
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
        default: return .text
        }
    }

    private func notebookScaleKind(_ raw: String?) -> NotebookScaleKind {
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

    private func notebookColumnVisibility(_ raw: String?) -> NotebookColumnVisibility {
        switch raw?.uppercased() {
        case "HIDDEN": return .hidden
        case "ARCHIVED": return .archived
        default: return .visible
        }
    }

    private func normalizeHexColor(_ raw: String?) -> String? {
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

    private func loadOrCreateLocalDeviceId() -> String {
        if let existingSecure = syncSecureStore.loadString(key: "sync.device.id"), !existingSecure.isEmpty {
            return existingSecure
        }
        if let legacy = UserDefaults.standard.string(forKey: "sync.device.id"), !legacy.isEmpty {
            syncSecureStore.saveString(legacy, key: "sync.device.id")
            UserDefaults.standard.removeObject(forKey: "sync.device.id")
            return legacy
        }
        let id = "ios-\(UUID().uuidString.prefix(8))"
        syncSecureStore.saveString(id, key: "sync.device.id")
        return id
    }

    private func migrateLegacySyncSecretsFromUserDefaults() {
        if let legacyToken = UserDefaults.standard.string(forKey: "sync.token"), !legacyToken.isEmpty {
            syncSecureStore.saveString(legacyToken, key: "sync.token")
            UserDefaults.standard.removeObject(forKey: "sync.token")
        }
        if let legacyHost = UserDefaults.standard.string(forKey: "sync.host"), !legacyHost.isEmpty {
            syncSecureStore.saveString(legacyHost, key: "sync.host")
            UserDefaults.standard.removeObject(forKey: "sync.host")
        }
    }

    private func persistSyncSecrets() {
        if let token = syncToken {
            syncSecureStore.saveString(token, key: "sync.token")
        }
        if let host = pairedSyncHost {
            syncSecureStore.saveString(host, key: "sync.host")
        }
        if let sid = pairedServerId {
            syncSecureStore.saveString(sid, key: "sync.server.id")
        }
        if let fingerprint = pairedServerFingerprint {
            syncSecureStore.saveString(fingerprint, key: "sync.server.fingerprint")
        }
    }

    private func clearPersistedPairing() {
        syncToken = nil
        pairedSyncHost = nil
        pairedServerId = nil
        pairedServerFingerprint = nil
        syncSecureStore.delete(key: "sync.token")
        syncSecureStore.delete(key: "sync.host")
        syncSecureStore.delete(key: "sync.server.id")
        syncSecureStore.delete(key: "sync.server.fingerprint")
    }

    private func rebindPairedHostIfNeeded() {
        _ = recoverHostAfterNetworkChange(previousHost: pairedSyncHost)
    }

    private func recoverHostAfterNetworkChange(previousHost: String?) -> Bool {
        guard let matched = bestDiscoveredPeerForRecovery() else { return false }
        let previous = previousHost ?? pairedSyncHost
        var changed = false

        if pairedSyncHost != matched.host {
            pairedSyncHost = matched.host
            syncStatusMessage = "Host actualizado automáticamente: \(matched.host)"
            changed = true
        }
        if (pairedServerId == nil || pairedServerId?.isEmpty == true), !matched.serverId.isEmpty {
            pairedServerId = matched.serverId
            changed = true
        }
        if (pairedServerFingerprint == nil || pairedServerFingerprint?.isEmpty == true), !matched.fingerprint.isEmpty {
            pairedServerFingerprint = matched.fingerprint
            changed = true
        }

        if changed {
            persistSyncSecrets()
        }

        return changed && previous != matched.host
    }

    private func bestDiscoveredPeerForRecovery() -> LanDiscoveredPeer? {
        if let sid = pairedServerId, !sid.isEmpty,
           let byServerId = discoveredPeersByHost.values.first(where: { $0.serverId == sid }) {
            return byServerId
        }
        if let fingerprint = pairedServerFingerprint, !fingerprint.isEmpty,
           let byFingerprint = discoveredPeersByHost.values.first(where: { $0.fingerprint == fingerprint }) {
            return byFingerprint
        }
        return nil
    }

    nonisolated fileprivate static func deduplicateDiscoveredPeers(_ peers: [LanDiscoveredPeer]) -> [LanDiscoveredPeer] {
        var peersByHost: [String: LanDiscoveredPeer] = [:]
        for peer in peers {
            if let existing = peersByHost[peer.host] {
                peersByHost[peer.host] = preferredDiscoveredPeer(existing, peer)
            } else {
                peersByHost[peer.host] = peer
            }
        }
        return peersByHost.values.sorted { lhs, rhs in
            if lhs.host == rhs.host {
                return lhs.identityScore > rhs.identityScore
            }
            return lhs.host < rhs.host
        }
    }

    nonisolated fileprivate static func preferredDiscoveredPeer(_ lhs: LanDiscoveredPeer, _ rhs: LanDiscoveredPeer) -> LanDiscoveredPeer {
        if lhs.identityScore != rhs.identityScore {
            return lhs.identityScore >= rhs.identityScore ? lhs : rhs
        }
        if lhs.scheme != rhs.scheme {
            return lhs.scheme == "https" ? lhs : rhs
        }
        return lhs
    }

    private func startAutoSyncLoop() {
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.nextAutoSyncIntervalNanoseconds())
                    guard self.pairedSyncHost != nil, self.syncToken != nil else { continue }
                    await self.syncNow(reason: "periodic", forceFullPull: false, silent: true)
                } catch {
                    // Evitamos romper el bucle por errores transitorios de red.
                }
            }
        }
    }

    private func triggerAutoSyncSoon() {
        guard pairedSyncHost != nil, syncToken != nil else { return }
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Disparamos rápido para que desktop reciba cambios de estado casi inmediatos.
                try await Task.sleep(nanoseconds: 250_000_000)
                await self.syncNow(reason: "debounced_local_change", forceFullPull: false, silent: true)
            } catch {
                self.syncStatusMessage = "Auto-sync pendiente (reconectando...)"
            }
        }
    }

    func onAppDidBecomeActive() {
        isAppInForeground = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "foreground", forceFullPull: true, silent: true)
        }
    }

    func onAppDidEnterBackground() {
        isAppInForeground = false
        autoSyncDebounceTask?.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "background_flush", forceFullPull: false, silent: true)
        }
    }

    private func syncNow(reason: String, forceFullPull: Bool, silent: Bool) async {
        guard pairedSyncHost != nil, syncToken != nil else { return }

        if isSyncInFlight {
            syncNeedsAnotherPass = true
            return
        }

        isSyncInFlight = true
        defer { isSyncInFlight = false }

        var shouldRunAnotherPass = false
        repeat {
            syncNeedsAnotherPass = false
            do {
                if !pendingOutboundChanges.isEmpty {
                    try await performPushSync(silent: true)
                }

                let now = Date()
                let shouldForceFullPull = forceFullPull || now.timeIntervalSince(lastFullPullAt) > 180
                try await performPullSync(
                    silent: true,
                    sinceEpochMsOverride: shouldForceFullPull ? 0 : nil
                )
                if shouldForceFullPull {
                    lastFullPullAt = now
                }
                lastSuccessfulSyncAt = now

                if !silent {
                    syncStatusMessage = "Sincronizado (\(reason))"
                }
            } catch {
                if !silent {
                    syncStatusMessage = "Sync fallido (\(reason)): \(error.localizedDescription)"
                } else {
                    syncStatusMessage = "Auto-sync pendiente (reconectando...)"
                }
            }

            shouldRunAnotherPass = syncNeedsAnotherPass
        } while shouldRunAnotherPass
    }

    private func nextAutoSyncIntervalNanoseconds() -> UInt64 {
        if !isAppInForeground {
            return 8_000_000_000
        }
        if !pendingOutboundChanges.isEmpty {
            return 1_200_000_000
        }

        let now = Date()
        if now.timeIntervalSince(lastLocalMutationAt) < 10 {
            return 2_000_000_000
        }
        if now.timeIntervalSince(lastSuccessfulSyncAt) > 15 {
            return 2_500_000_000
        }
        return 4_500_000_000
    }
}

// Helper for UI Scopes
class MainScope: CoroutineScope {
    let coroutineContext: KotlinCoroutineContext = Dispatchers.shared.Main
}

// MARK: - Flow to AsyncSequence Adapter

struct FlowAsyncSequence<T>: AsyncSequence {
    typealias Element = T
    let flow: Flow

    struct AsyncIterator: AsyncIteratorProtocol {
        private var streamIterator: AsyncStream<T>.Iterator

        init(flow: Flow) {
            let stream = AsyncStream<T> { continuation in
                flow.collect(collector: Collector { value in
                    if let element = value as? T {
                        continuation.yield(element)
                    }
                }) { error in
                    continuation.finish()
                }
            }
            self.streamIterator = stream.makeAsyncIterator()
        }

        mutating func next() async -> T? {
            await streamIterator.next()
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(flow: flow)
    }
}

class Collector: FlowCollector {
    let callback: (Any?) -> Void
    init(callback: @escaping (Any?) -> Void) {
        self.callback = callback
    }
    func emit(value: Any?, completionHandler: @escaping (Error?) -> Void) {
        callback(value)
        completionHandler(nil)
    }
}

extension Flow {
    func asAsyncSequence<T>(type: T.Type) -> FlowAsyncSequence<T> {
        FlowAsyncSequence(flow: self)
    }
}

extension RubricEvaluationTarget: @retroactive Identifiable {
    public var id: String {
        return "\(studentId)|\(columnId)"
    }
}

extension NotebookColumnDefinition: @retroactive Identifiable {}

struct LanSyncChange: Codable, Equatable {
    let entity: String
    let id: String
    let updatedAtEpochMs: Int64
    let deviceId: String
    let payload: String
    var op: String = "upsert"
    var schemaVersion: Int = 1
}

private struct NotebookSyncCache: Codable {
    var entityIdsByScope: [String: [String]] = [:]
    /// Mapeo de ID de entidad a ID de dispositivo que la creó/posee.
    /// Esto evita que borremos localmente (en el sync queue) cosas que vienen de otro dispositivo.
    var deviceIdByEntityId: [String: String] = [:]
}

struct LanPullResult {
    let serverEpochMs: Int64
    let changes: [LanSyncChange]
    var changeCount: Int { changes.count }
}

struct LanHandshakeResult {
    let token: String
    let serverId: String
    let certificateFingerprint: String
}

private struct LanHandshakeRequest: Codable {
    let pin: String
    let deviceId: String
}

private struct LanHandshakeResponse: Codable {
    let token: String
    let serverId: String?
    let certificateFingerprint: String?
    let serverEpochMs: Int64?
}

private struct LanPullResponse: Codable {
    let serverEpochMs: Int64
    let changes: [LanSyncChange]
}

private struct LanPushRequest: Codable {
    let clientDeviceId: String
    let lastKnownServerEpochMs: Int64
    let changes: [LanSyncChange]
}

private struct LanPushResponse: Codable {
    let applied: Int
    let conflictsResolvedByLww: Int?
    let serverEpochMs: Int64?
}

final class LanSyncClient {
    static func normalizeHost(_ rawHost: String) -> String {
        var normalized = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "" }

        if let components = URLComponents(string: normalized), let host = components.host, !host.isEmpty {
            normalized = host
        } else {
            normalized = normalized
                .replacingOccurrences(of: "https://", with: "", options: [.caseInsensitive, .anchored])
                .replacingOccurrences(of: "http://", with: "", options: [.caseInsensitive, .anchored])
            if let slashIndex = normalized.firstIndex(of: "/") {
                normalized = String(normalized[..<slashIndex])
            }
            if let queryIndex = normalized.firstIndex(of: "?") {
                normalized = String(normalized[..<queryIndex])
            }
        }

        if normalized.hasPrefix("["),
           normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }

        if let colonIndex = normalized.lastIndex(of: ":"), !normalized.contains("::") {
            let suffix = normalized[normalized.index(after: colonIndex)...]
            if suffix.allSatisfy(\.isNumber) {
                normalized = String(normalized[..<colonIndex])
            }
        }

        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    func handshake(
        host: String,
        pin: String,
        deviceId: String,
        pinnedFingerprint: String?
    ) async throws -> LanHandshakeResult {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/handshake")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            LanHandshakeRequest(pin: pin, deviceId: deviceId)
        )
        print("🔗 LAN Sync: Intentando handshake con \(host) (deviceId: \(deviceId))")
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "handshake",
            host: host
        )
        
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -200, userInfo: [NSLocalizedDescriptionKey: "Respuesta no es HTTP"])
        }
        
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            print("❌ LAN Sync Handshake Fallido: HTTP \(http.statusCode) - \(body)")
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Handshake LAN fallido (\(http.statusCode)): \(body)"
            ])
        }
        let decoded = try JSONDecoder().decode(LanHandshakeResponse.self, from: data)
        let fingerprint = decoded.certificateFingerprint ?? pinnedFingerprint ?? ""
        return LanHandshakeResult(
            token: decoded.token,
            serverId: decoded.serverId ?? "",
            certificateFingerprint: fingerprint
        )
    }

    func pull(host: String, token: String, sinceEpochMs: Int64, pinnedFingerprint: String?) async throws -> LanPullResult {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/pull", queryItems: [
            URLQueryItem(name: "since", value: "\(sinceEpochMs)")
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "pull",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -201, userInfo: [NSLocalizedDescriptionKey: "Pull LAN fallido: respuesta no HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Pull LAN fallido (\(http.statusCode)): \(body)"
            ])
        }
        let result = try JSONDecoder().decode(LanPullResponse.self, from: data)
        return LanPullResult(serverEpochMs: result.serverEpochMs, changes: result.changes)
    }

    func push(
        host: String,
        token: String,
        deviceId: String,
        changes: [LanSyncChange],
        lastKnownServerEpochMs: Int64,
        pinnedFingerprint: String?
    ) async throws -> Int {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/push")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            LanPushRequest(
                clientDeviceId: deviceId,
                lastKnownServerEpochMs: lastKnownServerEpochMs,
                changes: changes
            )
        )
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "push",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -202, userInfo: [NSLocalizedDescriptionKey: "Push LAN fallido: respuesta no HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Push LAN fallido (\(http.statusCode)): \(body)"
            ])
        }
        return try JSONDecoder().decode(LanPushResponse.self, from: data).applied
    }

    func unpair(host: String, token: String, pinnedFingerprint: String?) async throws -> Bool {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/unpair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (_, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "unpair",
            host: host
        )
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func makeSession(pinnedFingerprint: String?) -> URLSession {
        let delegate = PinnedTLSDelegate(pinnedFingerprint: pinnedFingerprint)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    private func buildURL(
        host: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard !host.isEmpty else {
            throw NSError(
                domain: "Sync",
                code: -206,
                userInfo: [NSLocalizedDescriptionKey: "El host de sincronización está vacío o no es válido."]
            )
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = 8765
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw NSError(
                domain: "Sync",
                code: -207,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo construir la URL de sincronización para '\(host)'."]
            )
        }
        return url
    }

    private func executeDataTask(
        request: URLRequest,
        pinnedFingerprint: String?,
        operation: String,
        host: String
    ) async throws -> (Data, URLResponse) {
        let session = makeSession(pinnedFingerprint: pinnedFingerprint)
        do {
            let result = try await session.data(for: request)
            session.finishTasksAndInvalidate()
            return result
        } catch let urlError as URLError {
            session.invalidateAndCancel()
            if urlError.code == .timedOut {
                throw NSError(
                    domain: "Sync",
                    code: -210,
                    userInfo: [NSLocalizedDescriptionKey: "La petición de \(operation) a \(host) superó el tiempo límite. Reintenta con la app desktop abierta y en la misma LAN."]
                )
            }
            if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                throw NSError(
                    domain: "Sync",
                    code: -212,
                    userInfo: [NSLocalizedDescriptionKey: "No se pudo conectar con \(host):8765 para \(operation). Comprueba que el desktop siga abierto y que ese host sea el correcto."]
                )
            }
            if urlError.code == .cannotFindHost || urlError.code == .dnsLookupFailed {
                throw NSError(
                    domain: "Sync",
                    code: -213,
                    userInfo: [NSLocalizedDescriptionKey: "No se pudo resolver el host '\(host)'. Usa el nombre Bonjour o la IP actual del desktop."]
                )
            }
            if urlError.code == .serverCertificateUntrusted ||
                urlError.code == .serverCertificateHasBadDate ||
                urlError.code == .serverCertificateHasUnknownRoot ||
                urlError.code == .secureConnectionFailed {
                throw NSError(
                    domain: "Sync",
                    code: -214,
                    userInfo: [NSLocalizedDescriptionKey: "El certificado TLS del desktop no coincide con el esperado. Conviene desvincular y emparejar de nuevo."]
                )
            }
            throw NSError(
                domain: "Sync",
                code: -211,
                userInfo: [NSLocalizedDescriptionKey: "Error de red en \(operation) con \(host): \(urlError.localizedDescription)"]
            )
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }
}

extension KmpBridge {
    func buildDashboardAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let snapshot = try await container.getOperationalDashboardSnapshot.invoke(
            mode: .office,
            filters: DashboardFilters(classId: classId.map { KotlinLong(value: $0) }, severity: nil, priority: nil, sessionStatus: nil)
        )
        let selectedSummary = classId.flatMap { id in snapshot.groupSummaries.first(where: { $0.classId == id }) }
        return ScreenAIContext(
            kind: .dashboard,
            title: "Dashboard docente",
            subtitle: selectedSummary?.groupName ?? "Visión operativa del día",
            classId: classId,
            className: selectedSummary?.groupName,
            studentId: nil,
            studentName: nil,
            summary: "Resumen operativo con alertas, agenda y grupos que conviene revisar.",
            metrics: [
                ReportMetric(title: "Hoy", value: "\(snapshot.todayCount)", systemImage: "calendar"),
                ReportMetric(title: "Alertas", value: "\(snapshot.alertsCount)", systemImage: "exclamationmark.bubble.fill"),
                ReportMetric(title: "Pendientes", value: "\(snapshot.pendingCount)", systemImage: "clock.badge.exclamationmark"),
                ReportMetric(title: "Grupos", value: "\(snapshot.groupSummaries.count)", systemImage: "rectangle.3.group")
            ],
            factLines: compactSuggestions(
                "Sesiones previstas hoy: \(snapshot.todayCount).",
                "Alertas visibles: \(snapshot.alertsCount).",
                "Pendientes operativos: \(snapshot.pendingCount).",
                snapshot.nextSessionLabel == "Sin próxima sesión" ? nil : "Próxima sesión: \(snapshot.nextSessionLabel).",
                selectedSummary.map { "Grupo destacado: \($0.groupName) con asistencia \($0.attendancePct)% y media \(IosFormatting.decimal(from: $0.averageScore))." }
            ),
            supportNotes: compactSuggestions(
                snapshot.alerts.first.map { "\($0.title): \($0.detail)" },
                snapshot.agendaItems.first.map { "\($0.title) · \($0.subtitle)" }
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .operationalSummary, title: "Resumen operativo", subtitle: "Prioriza lo importante del día", systemImage: "bolt.badge.clock.fill", promptHint: "Resume el estado operativo y lo urgente."),
                ContextualAIAction(actionId: .prioritizedAlerts, title: "Alertas priorizadas", subtitle: "Ordena incidencias y seguimiento", systemImage: "exclamationmark.triangle.fill", promptHint: "Ordena alertas y explica por qué conviene revisarlas."),
                ContextualAIAction(actionId: .weeklyDigest, title: "Digest semanal", subtitle: "Texto breve para seguimiento docente", systemImage: "doc.text.fill", promptHint: "Crea un digest semanal breve y accionable.")
            ],
            hasEnoughData: snapshot.todayCount > 0 || snapshot.alertsCount > 0 || !snapshot.groupSummaries.isEmpty,
            dataQualityNote: snapshot.groupSummaries.isEmpty ? "No hay resúmenes de grupo cargados todavía en el dashboard." : nil
        )
    }

    func buildCoursesAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let classes = try await container.classesRepository.listClasses()
        let selectedClass = classId.flatMap { id in classes.first(where: { $0.id == id }) }
        let summary: CourseInspectorSnapshot? = if let selectedClass {
            try? await loadCourseSummary(classId: selectedClass.id)
        } else {
            nil
        }
        return ScreenAIContext(
            kind: .courses,
            title: "Cursos",
            subtitle: selectedClass?.name ?? "Panorámica de grupos",
            classId: selectedClass?.id,
            className: selectedClass?.name,
            studentId: nil,
            studentName: nil,
            summary: selectedClass == nil ? "Contexto docente del conjunto de grupos." : "Resumen rápido del grupo activo para decidir próximos pasos.",
            metrics: [
                ReportMetric(title: "Grupos", value: "\(classes.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Curso", value: selectedClass.map { courseLabel(for: $0) } ?? "General", systemImage: "graduationcap.fill"),
                ReportMetric(title: "Alumnado", value: summary.map { "\($0.studentCount)" } ?? "--", systemImage: "person.3.fill"),
                ReportMetric(title: "Asistencia", value: summary.map { "\($0.attendanceRate)%" } ?? "--", systemImage: "checklist.checked")
            ],
            factLines: compactSuggestions(
                "Clases registradas: \(classes.count).",
                selectedClass.map { "Grupo activo: \($0.name)." },
                summary.map { "Evaluaciones activas: \($0.evaluationCount)." },
                summary.map { "Incidencias registradas: \($0.incidentCount)." }
            ),
            supportNotes: compactSuggestions(
                summary?.activeEvaluationNames.first.map { "Instrumento destacado: \($0)" }
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .classSnapshot, title: "Foto del grupo", subtitle: "Resumen del grupo activo", systemImage: "rectangle.3.group.bubble.left.fill", promptHint: "Resume lo importante del grupo activo."),
                ContextualAIAction(actionId: .observationProposal, title: "Observaciones", subtitle: "Propuesta breve de observación docente", systemImage: "note.text.badge.plus", promptHint: "Sugiere observaciones breves y prudentes para este grupo.")
            ],
            hasEnoughData: !classes.isEmpty,
            dataQualityNote: selectedClass == nil ? "No hay grupo seleccionado; la salida será general." : nil
        )
    }

    func buildStudentsAIContext(classId: Int64?, studentId: Int64?) async throws -> ScreenAIContext {
        if let studentId {
            let profile = try await loadStudentProfile(studentId: studentId, classId: classId)
            return ScreenAIContext(
                kind: .students,
                title: "Ficha del alumno",
                subtitle: profile.student.fullName,
                classId: classId,
                className: profile.schoolClass?.name,
                studentId: studentId,
                studentName: profile.student.fullName,
                summary: "Síntesis individual para seguimiento, tutoría o comunicación con familia.",
                metrics: [
                    ReportMetric(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum"),
                    ReportMetric(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill"),
                    ReportMetric(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                ],
                factLines: compactSuggestions(
                    "Alumno: \(profile.student.fullName).",
                    "Asistencia estimada: \(profile.attendanceRate)%.",
                    profile.averageScore > 0 ? "Media registrada: \(IosFormatting.decimal(from: profile.averageScore))." : "Sin media consolidada todavía.",
                    "Seguimientos activos: \(profile.followUpCount).",
                    profile.latestAttendanceStatus.map { "Último estado de asistencia: \($0)." }
                ),
                supportNotes: compactSuggestions(
                    profile.adaptationsSummary,
                    profile.familyCommunicationSummary,
                    profile.timeline.first.map { "\($0.title) · \($0.subtitle)" }
                ),
                suggestedActions: [
                    ContextualAIAction(actionId: .studentFollowUp, title: "Resumen de seguimiento", subtitle: "Lectura docente breve", systemImage: "person.text.rectangle.fill", promptHint: "Resume el seguimiento del alumno de forma accionable."),
                    ContextualAIAction(actionId: .familyComment, title: "Comentario para familia", subtitle: "Versión clara y respetuosa", systemImage: "person.2.badge.gearshape.fill", promptHint: "Redacta un comentario claro para familia."),
                    ContextualAIAction(actionId: .observationProposal, title: "Propuesta de observación", subtitle: "Texto corto editable", systemImage: "text.badge.plus", promptHint: "Genera una observación breve y prudente.")
                ],
                hasEnoughData: profile.instrumentsCount > 0 || profile.incidentCount > 0 || profile.journalNoteCount > 0,
                dataQualityNote: profile.instrumentsCount == 0 ? "Hay poca evidencia evaluativa registrada para este alumno." : nil
            )
        }

        return try await buildCoursesAIContext(classId: classId).copy(kind: .students, title: "Alumnado", summary: "Selecciona un alumno para un contexto más preciso.")
    }

    func buildAttendanceAIContext(classId: Int64?) async throws -> ScreenAIContext {
        guard let classId else {
            return ScreenAIContext(
                kind: .attendance,
                title: "Asistencia",
                subtitle: "Sin clase activa",
                classId: nil,
                className: nil,
                studentId: nil,
                studentName: nil,
                summary: "Selecciona una clase para analizar patrones de asistencia.",
                metrics: [],
                factLines: ["No hay grupo seleccionado."],
                supportNotes: [],
                suggestedActions: [],
                hasEnoughData: false,
                dataQualityNote: "La asistencia necesita un grupo activo."
            )
        }
        let summary = try await loadCourseSummary(classId: classId)
        let history = try await attendanceHistory(for: classId, days: 21)
        let absent = history.filter { normalizedAnalyticsText($0.status).contains("aus") }.count
        let late = history.filter { normalizedAnalyticsText($0.status).contains("tard") || normalizedAnalyticsText($0.status).contains("retr") }.count
        return ScreenAIContext(
            kind: .attendance,
            title: "Asistencia",
            subtitle: summary.schoolClass.name,
            classId: classId,
            className: summary.schoolClass.name,
            studentId: nil,
            studentName: nil,
            summary: "Lectura de asistencia reciente con foco en ausencias, retrasos y seguimiento.",
            metrics: [
                ReportMetric(title: "Asistencia", value: "\(summary.attendanceRate)%", systemImage: "checklist.checked"),
                ReportMetric(title: "Ausencias", value: "\(absent)", systemImage: "xmark.circle.fill"),
                ReportMetric(title: "Retrasos", value: "\(late)", systemImage: "clock.badge.exclamationmark"),
                ReportMetric(title: "Registros", value: "\(history.count)", systemImage: "calendar")
            ],
            factLines: compactSuggestions(
                "Grupo: \(summary.schoolClass.name).",
                "Asistencia reciente estimada: \(summary.attendanceRate)%.",
                "Ausencias en el periodo: \(absent).",
                "Retrasos en el periodo: \(late)."
            ),
            supportNotes: compactSuggestions(
                late > 0 ? "Hay retrasos suficientes como para revisar patrones horarios." : nil
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .attendancePatterns, title: "Patrones de asistencia", subtitle: "Detecta señales y brechas", systemImage: "waveform.path.ecg", promptHint: "Explica los patrones recientes de asistencia."),
                ContextualAIAction(actionId: .followUpList, title: "Lista de seguimiento", subtitle: "Quién conviene revisar primero", systemImage: "list.bullet.clipboard.fill", promptHint: "Prioriza seguimiento por asistencia e incidencias.")
            ],
            hasEnoughData: !history.isEmpty,
            dataQualityNote: history.isEmpty ? "Todavía no hay suficientes registros de asistencia." : nil
        )
    }

    func buildDiaryAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        let sessions = try await diarySessions(weekNumber: week, year: year, classId: classId)
        let withIncidents = sessions.filter(\.hasIncidents).count
        let className = classId.flatMap { id in classes.first(where: { $0.id == id })?.name }
        return ScreenAIContext(
            kind: .diary,
            title: "Diario de aula",
            subtitle: className ?? "Semana actual",
            classId: classId,
            className: className,
            studentId: nil,
            studentName: nil,
            summary: "Resumen semanal del diario con incidencias, trazabilidad y próximos pasos.",
            metrics: [
                ReportMetric(title: "Sesiones", value: "\(sessions.count)", systemImage: "doc.text.fill"),
                ReportMetric(title: "Con incidencias", value: "\(withIncidents)", systemImage: "exclamationmark.bubble.fill")
            ],
            factLines: compactSuggestions(
                "Sesiones revisadas esta semana: \(sessions.count).",
                "Sesiones con incidencias: \(withIncidents).",
                sessions.first.map { "Última sesión: \(fallbackString($0.session.teachingUnitName, fallback: "Sin unidad"))." }
            ),
            supportNotes: compactSuggestions(
                sessions.first?.journalSummary?.incidentTags.isEmpty == false ? "Etiquetas recientes: \(sessions.first?.journalSummary?.incidentTags.joined(separator: ", ") ?? "")" : nil
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .diarySummary, title: "Síntesis semanal", subtitle: "Resumen docente breve", systemImage: "doc.plaintext.fill", promptHint: "Resume la semana lectiva con foco en lo relevante."),
                ContextualAIAction(actionId: .nextSteps, title: "Próximos pasos", subtitle: "Acciones sugeridas para la siguiente sesión", systemImage: "arrowshape.right.fill", promptHint: "Propón próximos pasos realistas y prudentes.")
            ],
            hasEnoughData: !sessions.isEmpty,
            dataQualityNote: sessions.isEmpty ? "No hay sesiones de diario registradas esta semana." : nil
        )
    }

    func buildEvaluationAIContext(classId: Int64?) async throws -> ScreenAIContext {
        guard let classId else {
            return ScreenAIContext(kind: .evaluation, title: "Evaluación", subtitle: "Sin clase activa", classId: nil, className: nil, studentId: nil, studentName: nil, summary: "Selecciona una clase para leer instrumentos y progreso.", metrics: [], factLines: ["No hay clase activa."], supportNotes: [], suggestedActions: [], hasEnoughData: false, dataQualityNote: "La evaluación necesita un grupo activo.")
        }
        let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId })
        let evaluations = try await evaluations(for: classId)
        let values = try await container.gradesRepository.listGradesForClass(classId: classId).compactMap { $0.value?.doubleValue }
        let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
        let rubrics = evaluations.filter { $0.rubricId != nil }.count
        return ScreenAIContext(
            kind: .evaluation,
            title: "Evaluación",
            subtitle: schoolClass?.name ?? "Grupo activo",
            classId: classId,
            className: schoolClass?.name,
            studentId: nil,
            studentName: nil,
            summary: "Digest breve de instrumentos, rúbricas y progreso evaluativo del grupo.",
            metrics: [
                ReportMetric(title: "Instrumentos", value: "\(evaluations.count)", systemImage: "chart.bar.doc.horizontal"),
                ReportMetric(title: "Rúbricas", value: "\(rubrics)", systemImage: "checklist"),
                ReportMetric(title: "Notas", value: "\(values.count)", systemImage: "number"),
                ReportMetric(title: "Media", value: IosFormatting.decimal(from: average), systemImage: "sum")
            ],
            factLines: compactSuggestions(
                "Instrumentos activos: \(evaluations.count).",
                "Rúbricas vinculadas: \(rubrics).",
                values.isEmpty ? "Todavía no hay calificaciones registradas." : "Media agregada: \(IosFormatting.decimal(from: average))."
            ),
            supportNotes: evaluations.prefix(4).map { "\($0.name) · peso \(IosFormatting.decimal(from: $0.weight))" },
            suggestedActions: [
                ContextualAIAction(actionId: .evaluationDigest, title: "Digest de evaluación", subtitle: "Lectura narrativa de los instrumentos", systemImage: "chart.bar.doc.horizontal.fill", promptHint: "Resume instrumentos, pesos y progreso."),
                ContextualAIAction(actionId: .progressReadout, title: "Lectura de progreso", subtitle: "Explica el avance del grupo", systemImage: "chart.line.uptrend.xyaxis", promptHint: "Explica el estado de progreso del grupo con prudencia.")
            ],
            hasEnoughData: !evaluations.isEmpty,
            dataQualityNote: values.isEmpty ? "Hay estructura evaluativa pero faltan calificaciones para una lectura más sólida." : nil
        )
    }

    func buildReportsAIContext(classId: Int64?, studentId: Int64?) async throws -> ScreenAIContext {
        guard let classId else {
            return ScreenAIContext(kind: .reports, title: "Informes", subtitle: "Sin clase activa", classId: nil, className: nil, studentId: nil, studentName: nil, summary: "Selecciona una clase para generar apoyo contextual al informe.", metrics: [], factLines: ["No hay clase activa."], supportNotes: [], suggestedActions: [], hasEnoughData: false, dataQualityNote: "Los informes necesitan un grupo activo.")
        }
        let context = try await buildReportGenerationContext(
            classId: classId,
            studentId: studentId,
            kind: studentId == nil ? .groupOverview : .studentSummary,
            termLabel: nil
        )
        return ScreenAIContext(
            kind: .reports,
            title: "Informes",
            subtitle: context.studentName ?? context.className,
            classId: classId,
            className: context.className,
            studentId: studentId,
            studentName: context.studentName,
            summary: context.summary,
            metrics: context.metrics,
            factLines: context.factLines,
            supportNotes: context.supportNotes,
            suggestedActions: [
                ContextualAIAction(actionId: .reportBridge, title: "Puente a informe", subtitle: "Preparar texto base para informe", systemImage: "doc.richtext.fill", promptHint: "Resume este contexto con formato listo para informe."),
                ContextualAIAction(actionId: .familyComment, title: "Versión para familia", subtitle: "Lenguaje más claro y cercano", systemImage: "person.2.badge.gearshape.fill", promptHint: "Reescribe el resumen con lenguaje para familia.")
            ],
            hasEnoughData: context.hasEnoughData,
            dataQualityNote: context.dataQualityNote
        )
    }

    func buildPEAIContext(classId: Int64?) async throws -> ScreenAIContext {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        let sessions = try await loadPESessions(weekNumber: week, year: year, classId: classId)
        let unequippedCount = sessions.reduce(0) { $0 + tokenCount(in: $1.unequippedStudentsText) }
        let injuriesCount = sessions.filter { !$0.injuriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let className = classId.flatMap { id in classes.first(where: { $0.id == id })?.name }
        return ScreenAIContext(
            kind: .pe,
            title: "Educación Física",
            subtitle: className ?? "Operativa EF",
            classId: classId,
            className: className,
            studentId: nil,
            studentName: nil,
            summary: "Resumen de operativa EF con equipación, incidencias físicas y clima de sesión.",
            metrics: [
                ReportMetric(title: "Sesiones", value: "\(sessions.count)", systemImage: "figure.run"),
                ReportMetric(title: "Sin equipación", value: "\(unequippedCount)", systemImage: "figure.run.square.stack"),
                ReportMetric(title: "Lesiones", value: "\(injuriesCount)", systemImage: "cross.case.fill")
            ],
            factLines: compactSuggestions(
                "Sesiones EF revisadas: \(sessions.count).",
                "Registros de alumnado sin equipación: \(unequippedCount).",
                "Sesiones con lesiones registradas: \(injuriesCount)."
            ),
            supportNotes: compactSuggestions(
                sessions.first.map { "Última sesión: \(fallbackString($0.session.teachingUnitName, fallback: "Sin unidad"))." },
                sessions.first.map { fallbackString($0.physicalIncidentsText, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 }
            ),
            suggestedActions: [
                ContextualAIAction(actionId: .peOperationalSummary, title: "Resumen EF", subtitle: "Síntesis operativa de la semana", systemImage: "figure.run.circle.fill", promptHint: "Resume la operativa EF de la semana."),
                ContextualAIAction(actionId: .peEquipmentSummary, title: "Equipación", subtitle: "Lectura breve de incidencias de material y ropa", systemImage: "figure.run.square.stack.fill", promptHint: "Explica las señales sobre equipación y seguimiento.")
            ],
            hasEnoughData: !sessions.isEmpty,
            dataQualityNote: sessions.isEmpty ? "No hay sesiones EF registradas esta semana." : nil
        )
    }

    func buildNotebookAIContext(classId: Int64?) -> ScreenAIContext {
        guard let data = notebookState as? NotebookUiStateData else {
            return ScreenAIContext(kind: .notebook, title: "Cuaderno", subtitle: "Sin datos", classId: classId, className: nil, studentId: nil, studentName: nil, summary: "Selecciona una clase para trabajar con el cuaderno.", metrics: [], factLines: ["No hay datos del cuaderno cargados todavía."], supportNotes: [], suggestedActions: [], hasEnoughData: false, dataQualityNote: "El cuaderno necesita estado cargado.")
        }
        let className = classId.flatMap { id in classes.first(where: { $0.id == id })?.name }
        let rows = data.sheet.rows
        let averages = rows.compactMap { $0.weightedAverage?.doubleValue }
        let avg = averages.isEmpty ? 0.0 : averages.reduce(0, +) / Double(averages.count)
        let commentColumns = data.sheet.columns.filter { isNotebookAICommentColumn($0) }
        return ScreenAIContext(
            kind: .notebook,
            title: "Cuaderno",
            subtitle: className ?? "Grupo activo",
            classId: classId,
            className: className,
            studentId: nil,
            studentName: nil,
            summary: "Lectura del cuaderno con foco en medias, señales de seguimiento y comentarios IA por alumno.",
            metrics: [
                ReportMetric(title: "Alumnado", value: "\(rows.count)", systemImage: "person.3.fill"),
                ReportMetric(title: "Columnas", value: "\(data.sheet.columns.count)", systemImage: "tablecells"),
                ReportMetric(title: "Media grupo", value: IosFormatting.decimal(from: avg), systemImage: "sum"),
                ReportMetric(title: "Comentarios IA", value: "\(commentColumns.count)", systemImage: "apple.intelligence")
            ],
            factLines: compactSuggestions(
                "Filas del cuaderno: \(rows.count).",
                "Columnas visibles/configuradas: \(data.sheet.columns.count).",
                "Media aproximada del grupo: \(IosFormatting.decimal(from: avg)).",
                commentColumns.isEmpty ? "Todavía no hay columnas de comentario IA." : "Columnas de comentario IA detectadas: \(commentColumns.map(\.title).joined(separator: ", "))."
            ),
            supportNotes: [],
            suggestedActions: [
                ContextualAIAction(actionId: .notebookGroupSummary, title: "Resumen del cuaderno", subtitle: "Lectura global del grupo", systemImage: "tablecells.badge.ellipsis", promptHint: "Resume el estado general del cuaderno del grupo."),
                ContextualAIAction(actionId: .notebookStudentComment, title: "Comentario por alumno", subtitle: "Texto breve editable", systemImage: "person.text.rectangle.fill", promptHint: "Genera comentario breve por alumno usando columnas visibles."),
                ContextualAIAction(actionId: .observationProposal, title: "Observaciones", subtitle: "Propón observaciones accionables", systemImage: "note.text.badge.plus", promptHint: "Sugiere observaciones breves para el grupo.")
            ],
            hasEnoughData: !rows.isEmpty && !data.sheet.columns.isEmpty,
            dataQualityNote: rows.isEmpty ? "El cuaderno no tiene alumnado o filas visibles." : nil
        )
    }

    func generateNotebookAICommentContexts(
        includedColumnIds: [String],
        studentIds: [Int64]? = nil
    ) -> [NotebookAICommentContext] {
        guard let data = notebookState as? NotebookUiStateData,
              let classId = notebookViewModel.currentClassId?.int64Value,
              let schoolClass = classes.first(where: { $0.id == classId })
        else { return [] }

        let selectedColumns = data.sheet.columns.filter { includedColumnIds.contains($0.id) }
        let columnCategoryNames = Dictionary(uniqueKeysWithValues: data.sheet.columnCategories.map { ($0.id, $0.name) })
        let filteredRows = data.sheet.rows.filter { row in
            guard let studentIds else { return true }
            return studentIds.contains(row.student.id)
        }

        return filteredRows.map { row in
            let insight = data.sheet.insights.first(where: { $0.studentId == row.student.id })
            let values = selectedColumns.compactMap { column -> NotebookAIColumnValue? in
                let value = notebookDisplayValue(for: row, column: column)
                guard !value.isEmpty else { return nil }
                return NotebookAIColumnValue(
                    title: column.title,
                    value: value,
                    categoryLabel: column.categoryId.flatMap { columnCategoryNames[$0] } ?? notebookCategoryLabel(column.categoryKind)
                )
            }
            let existingCommentColumn = data.sheet.columns.first(where: isNotebookAICommentColumn)
            let existingComment = existingCommentColumn.map { cellText(studentId: row.student.id, columnId: $0.id) }.flatMap { $0.nilIfBlank }
            let averageValue = row.weightedAverage?.doubleValue
            let averageText = averageValue.map { IosFormatting.decimal(from: $0) } ?? "Sin media"
            return NotebookAICommentContext(
                classId: classId,
                className: schoolClass.name,
                studentId: row.student.id,
                studentName: row.student.fullName,
                averageScore: averageValue,
                attendanceStatus: insight?.latestAttendanceStatus,
                followUpCount: Int(insight?.followUpCount ?? 0),
                incidentCount: Int(insight?.incidentCount ?? 0),
                evidenceCount: Int(insight?.evidenceCount ?? 0),
                competencyLabels: insight?.linkedCompetencyLabels ?? [],
                relevantValues: values,
                existingComment: existingComment,
                summary: "Alumno \(row.student.fullName) con media \(averageText), \(values.count) evidencias de cuaderno y seguimiento complementario.",
                hasEnoughData: averageValue != nil || !values.isEmpty || Int(insight?.incidentCount ?? 0) > 0 || Int(insight?.evidenceCount ?? 0) > 0,
                dataQualityNote: values.isEmpty ? "Hay pocas columnas con dato visible para este alumno." : nil
            )
        }
    }

    func createNotebookAICommentColumn(
        name: String,
        categoryKind: NotebookColumnCategoryKind = .followUp
    ) -> String? {
        guard let classId = notebookViewModel.currentClassId?.int64Value else { return nil }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let columnId = "COL_AI_\(nowMillis)"
        let nowMs = KotlinLong(value: nowMillis)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMillis)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let column = NotebookColumnDefinition(
            id: columnId,
            title: normalized,
            type: .text,
            categoryKind: categoryKind,
            instrumentKind: .privateComment,
            inputKind: .text,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: 0,
            dateEpochMs: nowMs,
            unitOrSituation: "Comentario IA",
            competencyCriteriaIds: [],
            scaleKind: .custom,
            tabIds: selectedNotebookTabId.map { [$0] } ?? [],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "3D7DFF",
            iconName: "apple.intelligence",
            order: -1,
            widthDp: 220,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: false,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            trace: trace
        )
        saveColumn(column: column)
        return columnId
    }

    func saveNotebookAIComment(studentId: Int64, columnId: String, text: String) {
        guard let data = notebookState as? NotebookUiStateData,
              let column = data.sheet.columns.first(where: { $0.id == columnId }) else { return }
        saveColumnGrade(studentId: studentId, column: column, value: text)
    }

    func isNotebookAICommentColumn(_ column: NotebookColumnDefinition) -> Bool {
        column.type == .text &&
        column.instrumentKind == .privateComment &&
        column.inputKind == .text &&
        !column.countsTowardAverage &&
        column.iconName == "apple.intelligence"
    }

    func buildPrebuiltAnalyticsCharts(
        classId: Int64,
        timeRange: AnalyticsTimeRange = .last30Days
    ) async throws -> [ChartFacts] {
        let attendanceTrend = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .attendanceTrend,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Evolución reciente de asistencia del grupo."
            )
        )
        let attendanceComparison = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .attendanceComparison,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Comparativa de asistencia entre grupos del mismo curso."
            )
        )
        let incidentHeatmap = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .incidentHeatmap,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Patrones de incidencias por día de la semana."
            )
        )
        let uniformComparison = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .uniformComparison,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Comparativa de faltas de equipación entre grupos."
            )
        )
        let averagesRanking = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .groupAveragesRanking,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Ranking de medias entre grupos del mismo curso."
            )
        )
        let sameCourseComparison = try await buildChartFacts(
            classId: classId,
            request: AnalyticsRequest(
                chartKind: .sameCourseComparison,
                timeRange: timeRange,
                selectedClassIds: [classId],
                selectedClassNames: [],
                prompt: nil,
                querySummary: "Comparativa global del mismo curso."
            )
        )
        return [
            attendanceTrend,
            attendanceComparison,
            incidentHeatmap,
            uniformComparison,
            averagesRanking,
            sameCourseComparison,
        ]
    }

    func resolveAnalyticsRequest(
        classId: Int64,
        prompt: String,
        timeRange: AnalyticsTimeRange = .last30Days,
        selectedClassIds: [Int64] = []
    ) async throws -> AnalyticsRequest {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }

        let allClasses = try await container.classesRepository.listClasses()
        let relatedClasses = relatedClasses(for: schoolClass, allClasses: allClasses)
        let normalizedPrompt = normalizedAnalyticsText(prompt)
        let resolvedChartKind: ChartKind

        if normalizedPrompt.contains("equip") || normalizedPrompt.contains("uniform") {
            resolvedChartKind = .uniformComparison
        } else if normalizedPrompt.contains("inciden") || normalizedPrompt.contains("conviven") || normalizedPrompt.contains("alerta") {
            resolvedChartKind = .incidentHeatmap
        } else if normalizedPrompt.contains("media") || normalizedPrompt.contains("nota") || normalizedPrompt.contains("promedio") || normalizedPrompt.contains("rendimiento") {
            resolvedChartKind = normalizedPrompt.contains("compar") ? .sameCourseComparison : .groupAveragesRanking
        } else if normalizedPrompt.contains("compar") || normalizedPrompt.contains("grupo") || normalizedPrompt.contains("curso") {
            resolvedChartKind = .attendanceComparison
        } else {
            resolvedChartKind = .attendanceTrend
        }

        let requestedIds = Array(Set(selectedClassIds + relatedClasses
            .filter { candidate in
                let normalizedName = normalizedAnalyticsText(candidate.name)
                return normalizedPrompt.contains(normalizedName)
            }
            .map(\.id)
        )).sorted()
        let finalIds = requestedIds.isEmpty ? [classId] : requestedIds
        let finalNames = relatedClasses
            .filter { finalIds.contains($0.id) }
            .map(\.name)

        return AnalyticsRequest(
            chartKind: resolvedChartKind,
            timeRange: timeRange,
            selectedClassIds: finalIds,
            selectedClassNames: finalNames,
            prompt: prompt.nilIfBlank,
            querySummary: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func buildChartFacts(
        classId: Int64,
        request: AnalyticsRequest
    ) async throws -> ChartFacts {
        guard let primaryClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }

        let allClasses = try await container.classesRepository.listClasses()
        let relatedClasses = relatedClasses(for: primaryClass, allClasses: allClasses)
        let comparisonClasses = relatedClasses.filter { schoolClass in
            request.selectedClassIds.isEmpty || request.selectedClassIds.contains(schoolClass.id)
        }

        switch request.chartKind {
        case .attendanceTrend:
            return try await buildAttendanceTrendFacts(for: primaryClass, timeRange: request.timeRange, prompt: request.prompt)
        case .attendanceComparison:
            return try await buildAttendanceComparisonFacts(for: primaryClass, comparisonClasses: comparisonClasses, timeRange: request.timeRange, prompt: request.prompt)
        case .incidentHeatmap:
            return try await buildIncidentHeatmapFacts(for: primaryClass, timeRange: request.timeRange, prompt: request.prompt)
        case .uniformComparison:
            return try await buildUniformComparisonFacts(for: primaryClass, comparisonClasses: comparisonClasses, timeRange: request.timeRange, prompt: request.prompt)
        case .groupAveragesRanking:
            return try await buildGroupAveragesRankingFacts(for: primaryClass, comparisonClasses: comparisonClasses, prompt: request.prompt)
        case .sameCourseComparison:
            return try await buildSameCourseComparisonFacts(for: primaryClass, comparisonClasses: comparisonClasses, prompt: request.prompt)
        }
    }

    private func buildAttendanceTrendFacts(
        for schoolClass: SchoolClass,
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let history = try await attendanceHistory(for: schoolClass.id, days: timeRange.dayCount)
        let grouped = Dictionary(grouping: history) { record in
            Calendar.current.startOfDay(for: record.date)
        }
        let dates = grouped.keys.sorted()
        let points = dates.map { day -> ChartPoint in
            let records = grouped[day, default: []]
            let present = records.filter { isPresentStatus($0.status) }.count
            let rate = records.isEmpty ? 0.0 : (Double(present) / Double(records.count)) * 100.0
            return ChartPoint(
                label: shortDateLabel(day),
                value: rate,
                note: records.isEmpty ? "Sin marcaje" : "\(present)/\(records.count) presentes"
            )
        }
        let average = points.isEmpty ? 0.0 : points.map(\.value).reduce(0, +) / Double(points.count)
        let lowDays = points.filter { $0.value > 0 && $0.value < 85 }.count
        let digest = lowDays > 0
            ? "La asistencia del grupo muestra \(lowDays) jornadas por debajo del umbral del 85%."
            : "La asistencia del grupo mantiene un patrón estable en el periodo analizado."
        return ChartFacts(
            chartKind: .attendanceTrend,
            title: schoolClass.name,
            subtitle: prompt ?? "Evolución diaria de la asistencia registrada.",
            chartType: ChartKind.attendanceTrend.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.attendanceTrend.groupingLabel,
            metrics: [
                ReportMetric(title: "Sesiones con registro", value: "\(points.count)", systemImage: "calendar"),
                ReportMetric(title: "Asistencia media", value: "\(Int(average.rounded()))%", systemImage: "checklist.checked"),
                ReportMetric(title: "Días frágiles", value: "\(lowDays)", systemImage: "exclamationmark.triangle.fill"),
            ],
            factLines: compactSuggestions(
                "Grupo analizado: \(schoolClass.name).",
                "Serie temporal calculada a partir de \(history.count) registros de asistencia.",
                points.last.map { "Último valor: \(Int($0.value.rounded()))% el \($0.label)." }
            ),
            highlights: compactSuggestions(
                average >= 90 ? "La asistencia media del periodo es sólida." : nil,
                points.last.map { $0.value > average ? "La última sesión mejora la media del periodo." : nil } ?? nil
            ),
            warnings: compactSuggestions(
                points.isEmpty ? "No hay datos de asistencia suficientes para dibujar una serie temporal." : nil,
                lowDays > 1 ? "Hay varias jornadas con asistencia claramente baja." : nil
            ),
            series: [
                ChartSeries(name: "Asistencia", colorToken: "blue", points: points)
            ],
            heatmapCells: [],
            hasEnoughData: !points.isEmpty,
            emptyStateMessage: "Todavía no hay marcajes suficientes para construir la evolución de asistencia.",
            teacherDigest: digest,
            insertableSummary: "Asistencia media del periodo: \(Int(average.rounded()))%."
        )
    }

    private func buildAttendanceComparisonFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let classesToCompare = comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses
        var points: [ChartPoint] = []
        for item in classesToCompare {
            let history = try await attendanceHistory(for: item.id, days: timeRange.dayCount)
            let present = history.filter { isPresentStatus($0.status) }.count
            let rate = history.isEmpty ? 0.0 : (Double(present) / Double(history.count)) * 100.0
            points.append(ChartPoint(label: item.name, value: rate, note: "\(history.count) registros"))
        }
        let sorted = points.sorted { $0.value > $1.value }
        let spread = (sorted.first?.value ?? 0) - (sorted.last?.value ?? 0)
        return ChartFacts(
            chartKind: .attendanceComparison,
            title: "Curso \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Comparativa de asistencia entre grupos equivalentes.",
            chartType: ChartKind.attendanceComparison.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.attendanceComparison.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(sorted.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Mejor tasa", value: "\(Int((sorted.first?.value ?? 0).rounded()))%", systemImage: "arrow.up.right"),
                ReportMetric(title: "Brecha", value: "\(Int(spread.rounded())) pt", systemImage: "arrow.left.and.right")
            ],
            factLines: compactSuggestions(
                "Se comparan grupos del mismo curso: \(sorted.map(\.label).joined(separator: ", ")).",
                sorted.first.map { "Mejor dato de asistencia: \($0.label) con \(Int($0.value.rounded()))%." },
                sorted.last.map { "Dato más bajo: \($0.label) con \(Int($0.value.rounded()))%." }
            ),
            highlights: compactSuggestions(
                spread < 5 ? "Las diferencias entre grupos son reducidas." : nil,
                sorted.first.map { "\($0.label) destaca en regularidad de asistencia." }
            ),
            warnings: compactSuggestions(
                sorted.count < 2 ? "Solo hay un grupo comparable en este curso." : nil,
                spread >= 10 ? "La brecha entre grupos ya merece seguimiento docente." : nil
            ),
            series: [
                ChartSeries(name: "Asistencia", colorToken: "green", points: sorted)
            ],
            heatmapCells: [],
            hasEnoughData: !sorted.isEmpty,
            emptyStateMessage: "No hay grupos comparables con datos de asistencia suficientes.",
            teacherDigest: spread >= 10
                ? "La asistencia presenta diferencias significativas entre grupos del mismo curso."
                : "La asistencia entre grupos del mismo curso se mueve en una franja relativamente estable.",
            insertableSummary: "Comparativa de asistencia entre grupos del mismo curso con una brecha de \(Int(spread.rounded())) puntos."
        )
    }

    private func buildIncidentHeatmapFacts(
        for schoolClass: SchoolClass,
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let incidents = try await incidents(for: schoolClass.id)
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.dayCount, to: Date()) ?? Date.distantPast
        let filtered = incidents.filter { Date(timeIntervalSince1970: TimeInterval($0.date.epochSeconds)) >= cutoff }
        let weekdaySymbols = ["L", "M", "X", "J", "V", "S", "D"]
        let weeksBack = max(2, min(6, timeRange.dayCount / 14 + 1))
        var cells: [HeatmapCell] = []
        for offset in 0..<weeksBack {
            let weekLabel = "S-\(weeksBack - offset)"
            for weekday in 2...8 {
                let count = filtered.filter { incident in
                    let date = Date(timeIntervalSince1970: TimeInterval(incident.date.epochSeconds))
                    let weeksDifference = Calendar.current.dateComponents([.weekOfYear], from: date, to: Date()).weekOfYear ?? 0
                    let weekdayValue = Calendar.current.component(.weekday, from: date)
                    return weeksDifference == offset && weekdayValue == weekday
                }.count
                cells.append(
                    HeatmapCell(
                        rowLabel: weekLabel,
                        columnLabel: weekdaySymbols[max(0, min(weekdaySymbols.count - 1, weekday - 2))],
                        value: Double(count)
                    )
                )
            }
        }
        let total = filtered.count
        let maxCell = cells.max(by: { $0.value < $1.value })
        return ChartFacts(
            chartKind: .incidentHeatmap,
            title: schoolClass.name,
            subtitle: prompt ?? "Concentración de incidencias por semana y día lectivo.",
            chartType: ChartKind.incidentHeatmap.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.incidentHeatmap.groupingLabel,
            metrics: [
                ReportMetric(title: "Incidencias", value: "\(total)", systemImage: "exclamationmark.bubble.fill"),
                ReportMetric(title: "Pico", value: "\(Int(maxCell?.value ?? 0))", systemImage: "flame.fill"),
                ReportMetric(title: "Semanas", value: "\(weeksBack)", systemImage: "calendar.badge.clock")
            ],
            factLines: compactSuggestions(
                "Se han revisado \(total) incidencias en el periodo seleccionado.",
                maxCell.map { "Mayor concentración: \($0.rowLabel) · \($0.columnLabel) con \(Int($0.value)) incidencias." }
            ),
            highlights: compactSuggestions(
                total == 0 ? "No hay incidencias registradas en el periodo." : nil,
                maxCell.map { $0.value <= 1 ? "Las incidencias aparecen dispersas y sin patrón fuerte." : nil } ?? nil
            ),
            warnings: compactSuggestions(
                total >= 5 ? "Ya hay una masa crítica de incidencias como para revisar patrones de grupo." : nil
            ),
            series: [],
            heatmapCells: cells,
            hasEnoughData: !cells.isEmpty,
            emptyStateMessage: "No hay datos suficientes para construir el heatmap de incidencias.",
            teacherDigest: total == 0
                ? "No se observan incidencias recientes en el grupo."
                : "El heatmap permite localizar los días con mayor concentración de incidencias.",
            insertableSummary: total == 0
                ? "Sin incidencias registradas en el periodo analizado."
                : "Heatmap de incidencias con \(total) registros en el periodo."
        )
    }

    private func buildUniformComparisonFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        timeRange: AnalyticsTimeRange,
        prompt: String?
    ) async throws -> ChartFacts {
        let classesToCompare = comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses
        var points: [ChartPoint] = []
        for item in classesToCompare {
            let count = try await unequippedEventsCount(for: item.id, sinceDays: timeRange.dayCount)
            points.append(ChartPoint(label: item.name, value: Double(count), note: "Sesiones con alumnado sin equipación"))
        }
        let sorted = points.sorted { $0.value > $1.value }
        return ChartFacts(
            chartKind: .uniformComparison,
            title: "Operativa EF · \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Comparativa de faltas de equipación o registros equivalentes en diarios.",
            chartType: ChartKind.uniformComparison.chartTypeLabel,
            timeRange: timeRange.title,
            grouping: ChartKind.uniformComparison.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(sorted.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Máximo", value: "\(Int(sorted.first?.value ?? 0))", systemImage: "arrow.up.right"),
                ReportMetric(title: "Total", value: "\(Int(sorted.map(\.value).reduce(0, +)))", systemImage: "sum")
            ],
            factLines: compactSuggestions(
                "Se han usado los diarios de sesión y el campo de alumnado sin equipación.",
                sorted.first.map { "Mayor carga operativa: \($0.label) con \(Int($0.value)) registros." }
            ),
            highlights: compactSuggestions(
                sorted.allSatisfy { $0.value == 0 } ? "No constan faltas de equipación recientes en los grupos comparados." : nil
            ),
            warnings: compactSuggestions(
                "Esta vista depende de que el diario de EF se complete con regularidad."
            ),
            series: [
                ChartSeries(name: "Sin equipación", colorToken: "orange", points: sorted)
            ],
            heatmapCells: [],
            hasEnoughData: !sorted.isEmpty,
            emptyStateMessage: "No hay grupos o diarios suficientes para comparar faltas de equipación.",
            teacherDigest: sorted.allSatisfy { $0.value == 0 }
                ? "No aparecen faltas de equipación en el periodo analizado."
                : "Las faltas de equipación se concentran en algunos grupos concretos y pueden tratarse como señal operativa.",
            insertableSummary: "Comparativa de faltas de equipación entre grupos del mismo curso."
        )
    }

    private func buildGroupAveragesRankingFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        prompt: String?
    ) async throws -> ChartFacts {
        let classesToCompare = comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses
        var points: [ChartPoint] = []
        for item in classesToCompare {
            let summary = try await loadCourseSummary(classId: item.id)
            points.append(ChartPoint(label: item.name, value: summary.averageScore, note: "Media del grupo"))
        }
        let sorted = points.sorted { $0.value > $1.value }
        let gap = (sorted.first?.value ?? 0) - (sorted.last?.value ?? 0)
        return ChartFacts(
            chartKind: .groupAveragesRanking,
            title: "Ranking · \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Ordenación de medias registradas por grupo.",
            chartType: ChartKind.groupAveragesRanking.chartTypeLabel,
            timeRange: "Curso actual",
            grouping: ChartKind.groupAveragesRanking.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(sorted.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Mejor media", value: IosFormatting.decimal(from: sorted.first?.value), systemImage: "arrow.up.right"),
                ReportMetric(title: "Brecha", value: IosFormatting.decimal(from: gap), systemImage: "arrow.left.and.right")
            ],
            factLines: compactSuggestions(
                sorted.first.map { "Media más alta: \($0.label) con \(IosFormatting.decimal(from: $0.value))." },
                sorted.last.map { "Media más baja: \($0.label) con \(IosFormatting.decimal(from: $0.value))." }
            ),
            highlights: compactSuggestions(
                gap < 1.0 ? "Las medias entre grupos son bastante homogéneas." : nil,
                sorted.first.map { "\($0.label) lidera el ranking de rendimiento registrado." }
            ),
            warnings: compactSuggestions(
                sorted.contains(where: { $0.value == 0 }) ? "Algún grupo todavía no tiene media consolidada." : nil
            ),
            series: [
                ChartSeries(name: "Media", colorToken: "purple", points: sorted)
            ],
            heatmapCells: [],
            hasEnoughData: !sorted.isEmpty,
            emptyStateMessage: "No hay datos suficientes para construir el ranking de medias.",
            teacherDigest: gap >= 1.5
                ? "Las medias entre grupos muestran una brecha relevante."
                : "Las medias entre grupos del mismo curso son relativamente cercanas.",
            insertableSummary: "Ranking de medias entre grupos del mismo curso."
        )
    }

    private func buildSameCourseComparisonFacts(
        for schoolClass: SchoolClass,
        comparisonClasses: [SchoolClass],
        prompt: String?
    ) async throws -> ChartFacts {
        let snapshot = try await container.getOperationalDashboardSnapshot.invoke(
            mode: .office,
            filters: DashboardFilters(classId: nil, severity: nil, priority: nil, sessionStatus: nil)
        )
        let allowedIds = Set((comparisonClasses.isEmpty ? [schoolClass] : comparisonClasses).map(\.id))
        let summaries = snapshot.groupSummaries.filter { allowedIds.contains($0.classId) }
        let attendancePoints = summaries.map {
            ChartPoint(label: $0.groupName, value: Double($0.attendancePct), note: "Asistencia")
        }
        let evaluationPoints = summaries.map {
            ChartPoint(label: $0.groupName, value: Double($0.evaluationCompletedPct), note: "Evaluación completada")
        }
        let averagePoints = summaries.map {
            ChartPoint(label: $0.groupName, value: $0.averageScore * 10.0, note: "Media normalizada x10")
        }
        return ChartFacts(
            chartKind: .sameCourseComparison,
            title: "Comparativa global · \(courseLabel(for: schoolClass))",
            subtitle: prompt ?? "Asistencia, evaluación completada y media normalizada por grupo.",
            chartType: ChartKind.sameCourseComparison.chartTypeLabel,
            timeRange: "Curso actual",
            grouping: ChartKind.sameCourseComparison.groupingLabel,
            metrics: [
                ReportMetric(title: "Grupos", value: "\(summaries.count)", systemImage: "rectangle.3.group"),
                ReportMetric(title: "Seguimiento", value: "\(summaries.map(\.studentsInFollowUp).reduce(0, +))", systemImage: "arrow.triangle.branch"),
                ReportMetric(title: "Media curso", value: IosFormatting.decimal(from: summaries.isEmpty ? nil : summaries.map(\.averageScore).reduce(0, +) / Double(summaries.count)), systemImage: "sum")
            ],
            factLines: compactSuggestions(
                summaries.isEmpty ? "No hay resúmenes operativos de grupo disponibles." : "Se comparan \(summaries.count) grupos del mismo curso.",
                summaries.max(by: { $0.attendancePct < $1.attendancePct }).map { "Mayor asistencia: \($0.groupName) con \($0.attendancePct)%." },
                summaries.max(by: { $0.averageScore < $1.averageScore }).map { "Mejor media: \($0.groupName) con \(IosFormatting.decimal(from: $0.averageScore))." }
            ),
            highlights: compactSuggestions(
                summaries.filter { $0.studentsInFollowUp == 0 }.isEmpty ? nil : "Hay grupos sin alumnado en seguimiento activo."
            ),
            warnings: compactSuggestions(
                summaries.isEmpty ? "No hay suficientes datos agregados para una comparativa global." : nil
            ),
            series: [
                ChartSeries(name: "Asistencia %", colorToken: "green", points: attendancePoints),
                ChartSeries(name: "Evaluación %", colorToken: "blue", points: evaluationPoints),
                ChartSeries(name: "Media x10", colorToken: "purple", points: averagePoints)
            ],
            heatmapCells: [],
            hasEnoughData: !summaries.isEmpty,
            emptyStateMessage: "Faltan resúmenes de grupo para construir la comparativa global.",
            teacherDigest: summaries.isEmpty
                ? "La comparativa global necesita más datos agregados."
                : "La comparativa global permite ver de un vistazo la relación entre asistencia, avance evaluativo y media del grupo.",
            insertableSummary: "Comparativa global entre grupos del mismo curso."
        )
    }

    private func relatedClasses(for schoolClass: SchoolClass, allClasses: [SchoolClass]) -> [SchoolClass] {
        let filtered = allClasses.filter { $0.course == schoolClass.course }
        return filtered.isEmpty ? [schoolClass] : filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func unequippedEventsCount(for classId: Int64, sinceDays days: Int) async throws -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let sessions = try await container.plannerRepository.listAllSessions()
            .filter { $0.groupId == classId && date(from: $0) >= cutoff }
        var count = 0
        for session in sessions {
            guard let aggregate = try? await container.sessionJournalRepository.getJournalForSession(planningSessionId: session.id) else {
                continue
            }
            let text = aggregate.journal.unequippedStudentsText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                count += max(1, tokenCount(in: text))
            }
        }
        return count
    }

    private func tokenCount(in text: String) -> Int {
        let separators = CharacterSet(charactersIn: ",;\n")
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func isPresentStatus(_ status: String) -> Bool {
        let normalized = normalizedAnalyticsText(status)
        return normalized.contains("present")
    }

    private func normalizedAnalyticsText(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func notebookDisplayValue(for row: NotebookRow, column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric:
            if let persisted = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
                return IosFormatting.decimal(from: persisted)
            }
            if let evaluationId = column.evaluationId?.int64Value,
               let cellValue = row.cells.first(where: { $0.evaluationId == evaluationId })?.value?.doubleValue {
                return IosFormatting.decimal(from: cellValue)
            }
            return ""
        case .rubric:
            if let persisted = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
                return IosFormatting.decimal(from: persisted)
            }
            return ""
        case .check:
            if let boolValue = row.persistedCells.first(where: { $0.columnId == column.id })?.boolValue?.boolValue {
                return boolValue ? "Sí" : "No"
            }
            return ""
        case .ordinal:
            return row.persistedCells.first(where: { $0.columnId == column.id })?.ordinalValue ?? ""
        default:
            return row.persistedCells.first(where: { $0.columnId == column.id })?.textValue ?? ""
        }
    }

    private func notebookCategoryLabel(_ kind: NotebookColumnCategoryKind) -> String {
        if kind == .evaluation { return "Evaluación" }
        if kind == .followUp { return "Seguimiento" }
        if kind == .attendance { return "Asistencia" }
        if kind == .extras { return "Extras" }
        if kind == .physicalEducation { return "Educación Física" }
        return "Personalizada"
    }

    private func fallbackString(_ value: String?, fallback: String) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? fallback
    }
}

final class LanSyncDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    var onPeersChanged: (([LanDiscoveredPeer]) -> Void)?

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_migestor-sync._tcp.", inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        if let existingIndex = services.firstIndex(where: { existing in
            existing.name == service.name && existing.type == service.type && existing.domain == service.domain
        }) {
            services[existingIndex] = service
        } else {
            services.append(service)
        }
        service.resolve(withTimeout: 3)
        if !moreComing {
            emitHosts()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0.name == service.name }
        if !moreComing {
            emitHosts()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        emitHosts()
    }

    private func emitHosts() {
        let peers = services.compactMap { service -> LanDiscoveredPeer? in
            guard let raw = service.hostName else { return nil }
            let host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let txtData = service.txtRecordData() ?? Data()
            let txt = NetService.dictionary(fromTXTRecord: txtData)
            let sid = txt["sid"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let fp = txt["fp"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let proto = txt["proto"].flatMap { String(data: $0, encoding: .utf8) } ?? "https"
            return LanDiscoveredPeer(host: host, serverId: sid, fingerprint: fp, scheme: proto)
        }
        let unique = KmpBridge.deduplicateDiscoveredPeers(peers)
        onPeersChanged?(unique.sorted { $0.host < $1.host })
    }
}

struct LanDiscoveredPeer: Equatable {
    let host: String
    let serverId: String
    let fingerprint: String
    let scheme: String

    var identityScore: Int {
        var score = 0
        if !serverId.isEmpty { score += 2 }
        if !fingerprint.isEmpty { score += 2 }
        if scheme == "https" { score += 1 }
        return score
    }
}

private final class IosKeychainStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func loadString(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveString(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private final class PinnedTLSDelegate: NSObject, URLSessionDelegate {
    private let pinnedFingerprint: String?

    init(pinnedFingerprint: String?) {
        self.pinnedFingerprint = pinnedFingerprint?.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if let pinnedFingerprint, !pinnedFingerprint.isEmpty {
            let certData = SecCertificateCopyData(certificate) as Data
            let computed = SHA256.hash(data: certData).map { String(format: "%02x", $0) }.joined()
            guard computed == pinnedFingerprint else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
