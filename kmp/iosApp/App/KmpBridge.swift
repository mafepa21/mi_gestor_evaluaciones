import Foundation
import MiGestorKit
import Combine
import Security
import CryptoKit

typealias KmpSubject = MiGestorKit.Subject
typealias WipeCategory = MiGestorKit.WipeCategory

struct StructuredInstrumentEvaluationModel: Identifiable {
    let id: String
    let classId: Int64
    let studentId: Int64
    let columnId: String
    let title: String
    let kind: NotebookInstrumentTemplateKind
    let criterionLabel: String?
    let criterionStatements: [CriterionStatement]
    var items: [StructuredInstrumentEvaluationItem]
}

struct StructuredInstrumentEvaluationItem: Identifiable {
    let id: String
    let title: String
    let type: NotebookInstrumentItemType
    let options: [String]
    var textValue: String
    var boolValue: Bool
    var numberValue: String
}

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
    let groupTitle: String
    let isRecommendedForCurrentSA: Bool

    var id: String { "\(kind.rawValue):\(rawId)" }
}

struct PlannerSessionSaveResult {
    let sessionId: Int64
    let teachingUnitId: Int64
    let teachingUnitName: String
    let evaluationSummary: String
    let linkedAssessmentIdsCsv: String
}

struct NotebookCreatedColumnResult {
    let column: NotebookColumnDefinition
    let category: NotebookColumnCategory?
}

struct RubricEvaluationAdvanceSummary {
    let evaluatedCount: Int
    let remainingCount: Int
}

enum RubricEvaluationAdvanceResult {
    case openedNext(studentId: Int64, remainingCount: Int)
    case completed(RubricEvaluationAdvanceSummary)
    case closed
}

@MainActor
final class RubricEvaluationCoordinator: ObservableObject {
    struct Context {
        let columnId: String
        let rubricId: Int64
        let classId: Int64
        let evaluationId: Int64
        let studentIds: [Int64]
        var currentStudentId: Int64
    }

    @Published private(set) var context: Context?
    @Published private(set) var lastSummary: RubricEvaluationAdvanceSummary?

    var isActive: Bool { context != nil }
    var currentStudentId: Int64? { context?.currentStudentId }

    func start(
        columnId: String,
        rubricId: Int64,
        classId: Int64,
        evaluationId: Int64,
        studentIds: [Int64],
        currentStudentId: Int64
    ) {
        let orderedIds = normalizedStudentIds(studentIds, currentStudentId: currentStudentId)
        context = Context(
            columnId: columnId,
            rubricId: rubricId,
            classId: classId,
            evaluationId: evaluationId,
            studentIds: orderedIds,
            currentStudentId: currentStudentId
        )
        lastSummary = nil
    }

    func advance(visibleStudentIds: [Int64]? = nil) -> Int64? {
        guard var context else { return nil }
        let orderedIds = normalizedStudentIds(
            visibleStudentIds?.filter { context.studentIds.contains($0) } ?? context.studentIds,
            currentStudentId: context.currentStudentId
        )
        guard let currentIndex = orderedIds.firstIndex(of: context.currentStudentId) else {
            finish(evaluatedCount: completedCount(in: orderedIds, currentStudentId: context.currentStudentId), remainingCount: 0)
            return nil
        }
        let remainingIds = orderedIds.dropFirst(currentIndex + 1)
        guard let nextStudentId = remainingIds.first else {
            finish(evaluatedCount: orderedIds.count, remainingCount: 0)
            return nil
        }
        context.currentStudentId = nextStudentId
        self.context = context
        lastSummary = RubricEvaluationAdvanceSummary(
            evaluatedCount: currentIndex + 1,
            remainingCount: remainingIds.count
        )
        return nextStudentId
    }

    func finish(evaluatedCount: Int? = nil, remainingCount: Int = 0) {
        let completed = evaluatedCount ?? context?.studentIds.count ?? 0
        lastSummary = RubricEvaluationAdvanceSummary(evaluatedCount: completed, remainingCount: remainingCount)
        context = nil
    }

    func reset() {
        context = nil
        lastSummary = nil
    }

    private func normalizedStudentIds(_ studentIds: [Int64], currentStudentId: Int64) -> [Int64] {
        var seen = Set<Int64>()
        var ordered = studentIds.filter { seen.insert($0).inserted }
        if !ordered.contains(currentStudentId) {
            ordered.insert(currentStudentId, at: 0)
        }
        return ordered
    }

    private func completedCount(in orderedIds: [Int64], currentStudentId: Int64) -> Int {
        guard let index = orderedIds.firstIndex(of: currentStudentId) else { return 0 }
        return index + 1
    }
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

    private let container: KmpContainer
    private let appleBootstrap: AppleBridgeBootstrap
    private let appleImportFacade = AppleImportFacade()
    let notebookViewModel: NotebookViewModel
    let plannerViewModel: PlannerViewModel
    let rubricEvaluationViewModel: RubricEvaluationViewModel
    let rubricBulkEvaluationViewModel: RubricBulkEvaluationViewModel
    let rubricsViewModel: RubricsViewModel
    private let lanSyncClient = LanSyncClient()
    private let syncEventListener = SyncEventListener()
    private let lanSyncDiscovery = LanSyncDiscovery()
    private let syncSecureStore = IosKeychainStore(service: "com.migestor.sync.ios")
    private var syncToken: String? = nil
    private var pairedServerId: String? = nil
    private var pairedServerFingerprint: String? = nil
    private var discoveredPeersByHost: [String: LanDiscoveredPeer] = [:]
    private var autoSyncLoopTask: Task<Void, Never>? = nil
    private var autoSyncDebounceTask: Task<Void, Never>? = nil
    private var localChangesNotifyTask: Task<Void, Never>? = nil
    private var pendingChangesPersistenceTask: Task<Void, Never>? = nil
    private var notebookSnapshotDebounceTask: Task<Void, Never>? = nil
    private var pendingGradeSnapshotTask: Task<Void, Never>? = nil
    private var postSyncRefreshTask: Task<Void, Never>? = nil
    private var isPairingInFlight = false
    private var isSyncInFlight = false
    private var syncNeedsAnotherPass = false
    private var isAppInForeground = true
    private var lastLocalMutationAt: Date = .distantPast
    private var lastCheckedDbModificationDate: Date = .distantPast
    private var lastSuccessfulSyncAt: Date = .distantPast
    private var lastFullPullAt: Date = .distantPast
    private var lastSilentSyncAttemptAt: Date = .distantPast
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
    private var pendingLocalSseChanges: [LanSyncChange] = []
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
    private var lastNotebookAggregateSignature: String? = nil
    private var gradeOnTenFormatCache: [String: String] = [:]

    private struct NotebookCellValueIndex {
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
            "groups:\(sheet.workGroups.count):\(sheet.workGroupMembers.count)"
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

    private func refreshDashboard() async throws {
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

    @MainActor
    func launchFirstBulkRubricEvaluationForClass(classId: Int64) async -> Bool {
        do {
            let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
            guard let column = columns.first(where: { $0.rubricId != nil && $0.evaluationId != nil }),
                  let rubricId = column.rubricId?.int64Value,
                  let evaluationId = column.evaluationId?.int64Value else {
                status = "No hay una rúbrica vinculada al cuaderno de esta clase."
                return false
            }
            startBulkRubricEvaluation(
                classId: classId,
                evaluationId: evaluationId,
                rubricId: rubricId,
                columnId: column.id,
                tabId: column.tabIds.first
            )
            return true
        } catch {
            status = "No se pudo abrir la rúbrica rápida: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshClasses() async throws {
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

    private func refreshSubjects() async throws {
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
            existingStudents.map { (normalizedStudentName(firstName: $0.firstName, lastName: $0.lastName), $0.fullName) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingLastNames = Set(existingStudents.map { normalizedNamePart($0.lastName) }.filter { !$0.isEmpty })
        let students = preview.students.map { student in
            let normalizedFullName = normalizedStudentName(firstName: student.firstName, lastName: student.lastName)
            let normalizedLastName = normalizedNamePart(student.lastName)
            let duplicateStatus: AppleStudentDuplicateStatus
            let duplicateDetail: String?
            if let existingName = existingByFullName[normalizedFullName] {
                duplicateStatus = .alreadyExists
                duplicateDetail = existingName
            } else if !normalizedLastName.isEmpty && existingLastNames.contains(normalizedLastName) {
                duplicateStatus = .possibleDuplicate
                duplicateDetail = "Coinciden apellidos"
            } else {
                duplicateStatus = .new
                duplicateDetail = nil
            }
            return AppleParsedStudent(
                id: Int(student.rowNumber),
                rowNumber: Int(student.rowNumber),
                fullName: student.fullName,
                firstName: student.firstName,
                lastName: student.lastName,
                duplicateStatus: duplicateStatus,
                duplicateDetail: duplicateDetail
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
        let studentsToImport = preview.students.filter { student in
            selectedRowSet.contains(student.rowNumber) && (!omitDuplicates || student.duplicateStatus == .new)
        }
        guard !studentsToImport.isEmpty else {
            throw NSError(domain: "KmpBridge", code: -62, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un alumno para importar."])
        }

        isImportingStudents = true
        defer { isImportingStudents = false }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var importedIds: [Int64] = []

        for student in studentsToImport {
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
            importedIds.append(studentId)

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

        if let targetClassId {
            for studentId in importedIds {
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

    func refreshRubrics() async throws {
        let rubrics = try await container.rubricsRepository.listRubrics()
        self.rubrics = rubrics
    }

    func refreshRubricClassLinks() async throws {
        if classes.isEmpty {
            try await refreshClasses()
        }

        let currentClasses = self.classes
        var links: [Int64: Set<Int64>] = [:]
        for schoolClass in currentClasses {
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            for evaluation in evaluations {
                if let rubricId = evaluation.rubricId?.int64Value {
                    var classSet = links[rubricId] ?? Set<Int64>()
                    classSet.insert(schoolClass.id)
                    links[rubricId] = classSet
                }
            }
        }
        self.rubricClassLinks = links
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

    func plannerListAllSessions() async throws -> [PlanningSession] {
        try await container.plannerRepository.listAllSessions()
    }

    func plannerListSessions(weekNumber: Int, year: Int, classId: Int64? = nil) async throws -> [PlanningSession] {
        let sessions = try await container.plannerRepository.listSessions(weekNumber: Int32(weekNumber), year: Int32(year))
        guard let classId else { return sessions }
        return sessions.filter { $0.groupId == classId }
    }

    func plannerGetSession(id: Int64) async throws -> PlanningSession {
        let sessions = try await container.plannerRepository.listAllSessions()
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        return session
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

    private func cleanPlannerInstrumentText(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ") ?? ""
        guard !trimmed.isEmpty else { return fallback }

        let upper = trimmed.uppercased()
        let looksLikeObjectDump =
            upper.contains("EVALUATION(") ||
            upper.contains("CLASSID=") ||
            upper.contains("RUBRICID=") ||
            upper.contains("TRACE=") ||
            upper.contains("AUDITTRACE") ||
            upper.contains("UPDATEDAT=") ||
            upper.contains("CREATEDAT=")

        if looksLikeObjectDump {
            return fallback
        }
        return String(trimmed.prefix(90))
    }

    private func plannerInstrumentGroupTitle(
        teachingUnitId: Int64?,
        evaluationDescription: String?,
        cachedUnits: [TeachingUnit]
    ) -> String {
        if let teachingUnitId,
           let unitName = plannerTeachingUnitName(for: teachingUnitId, cachedUnits: cachedUnits) {
            return cleanPlannerInstrumentText(unitName, fallback: "Sin situación asignada")
        }
        let cleanDescription = cleanPlannerInstrumentText(evaluationDescription, fallback: "")
        if !cleanDescription.isEmpty {
            return cleanDescription
        }
        return "Sin situación asignada"
    }

    private func plannerInstrumentMatchesCurrentSA(
        teachingUnitId: Int64?,
        groupTitle: String,
        currentTeachingUnitId: Int64?,
        currentTeachingUnitName: String?
    ) -> Bool {
        if let teachingUnitId, let currentTeachingUnitId, teachingUnitId == currentTeachingUnitId {
            return true
        }
        guard let currentTeachingUnitName, !currentTeachingUnitName.isEmpty else { return false }
        return groupTitle.localizedCaseInsensitiveCompare(currentTeachingUnitName) == .orderedSame
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
            emptyCellPolicy: .excludeFromAverage,
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
        Dictionary(
            classIds.map { ($0, plannerCourseColor(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
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

    func plannerSaveCalendarEvent(
        id: Int64?,
        classId: Int64?,
        title: String,
        description: String?,
        startEpochMs: Int64,
        endEpochMs: Int64
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.calendarRepository.saveEvent(
            id: kotlinLong(id),
            classId: kotlinLong(classId),
            title: title,
            description: description,
            startEpochMs: startEpochMs,
            endEpochMs: endEpochMs,
            externalProvider: nil,
            externalId: nil,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        
        enqueueLocalChange(
            entity: "calendar_event",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": savedId,
                "classId": classId ?? 0,
                "title": title,
                "description": description ?? "",
                "startEpochMs": startEpochMs,
                "endEpochMs": endEpochMs
            ]
        )
        return savedId
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
        let savedId = try await container.teacherScheduleRepository.saveSchedule(
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
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "teacher_schedule",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": savedId,
                "ownerUserId": ownerUserId,
                "academicYearId": academicYearId,
                "name": name,
                "startDateIso": startDateIso,
                "endDateIso": endDateIso,
                "activeWeekdaysCsv": activeWeekdaysCsv,
                "authorUserId": trace.authorUserId?.int64Value ?? 0,
                "createdAtEpochMs": trace.createdAt.toEpochMilliseconds(),
                "updatedAtEpochMs": nowMs,
                "associatedGroupId": trace.associatedGroupId?.int64Value ?? 0
            ]
        )
        return savedId
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

        if let existingWeeklyTemplateId {
            try? await container.weeklyTemplateRepository.delete(slotId: existingWeeklyTemplateId)
            enqueueLocalChange(
                entity: "weekly_slot",
                id: "\(existingWeeklyTemplateId)",
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                payload: [
                    "id": existingWeeklyTemplateId,
                    "schoolClassId": classId
                ],
                op: "delete"
            )
        }

        let savedId = try await container.teacherScheduleRepository.saveScheduleSlot(
            slot: TeacherScheduleSlot(
                id: editingSlotId ?? 0,
                teacherScheduleId: scheduleId,
                schoolClassId: classId,
                subjectLabel: subjectLabel,
                unitLabel: unitLabel,
                dayOfWeek: Int32(dayOfWeek),
                startTime: normalizedStart,
                endTime: normalizedEnd,
                weeklyTemplateId: nil
            )
        ).int64Value
        enqueueLocalChange(
            entity: "teacher_schedule_slot",
            id: "\(savedId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": savedId,
                "teacherScheduleId": scheduleId,
                "schoolClassId": classId,
                "subjectLabel": subjectLabel,
                "unitLabel": unitLabel ?? "",
                "dayOfWeek": dayOfWeek,
                "startTime": normalizedStart,
                "endTime": normalizedEnd,
                "weeklyTemplateId": 0
            ]
        )
        return savedId
    }

    func plannerDeleteTeacherScheduleSlot(slotId: Int64) async throws {
        let existingSlot = try await container.teacherScheduleRepository.getScheduleSlot(slotId: slotId)
        if let slot = try await container.teacherScheduleRepository.getScheduleSlot(slotId: slotId),
           let weeklyTemplateId = slot.weeklyTemplateId {
            try? await container.weeklyTemplateRepository.delete(slotId: weeklyTemplateId.int64Value)
        }
        try await container.teacherScheduleRepository.deleteScheduleSlot(slotId: slotId)
        enqueueLocalChange(
            entity: "teacher_schedule_slot",
            id: "\(slotId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": slotId,
                "teacherScheduleId": existingSlot?.teacherScheduleId ?? 0
            ],
            op: "delete"
        )
    }

    func plannerSaveEvaluationPeriod(
        periodId: Int64,
        scheduleId: Int64,
        name: String,
        startDateIso: String,
        endDateIso: String,
        sortOrder: Int
    ) async throws -> Int64 {
        let savedId = try await container.teacherScheduleRepository.saveEvaluationPeriod(
            period: PlannerEvaluationPeriod(
                id: periodId,
                teacherScheduleId: scheduleId,
                name: name,
                startDateIso: startDateIso,
                endDateIso: endDateIso,
                sortOrder: Int32(sortOrder)
            )
        ).int64Value
        enqueueLocalChange(
            entity: "planner_evaluation_period",
            id: "\(savedId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": savedId,
                "teacherScheduleId": scheduleId,
                "name": name,
                "startDateIso": startDateIso,
                "endDateIso": endDateIso,
                "sortOrder": sortOrder
            ]
        )
        return savedId
    }

    func plannerDeleteEvaluationPeriod(periodId: Int64) async throws {
        try await container.teacherScheduleRepository.deleteEvaluationPeriod(periodId: periodId)
        enqueueLocalChange(
            entity: "planner_evaluation_period",
            id: "\(periodId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": periodId
            ],
            op: "delete"
        )
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
        teacherScheduleSlotId: Int64? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        learningSituationSessionPlanId: Int64? = nil,
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
            teacherScheduleSlotId: teacherScheduleSlotId.map { KotlinLong(value: $0) },
            startTime: startTime,
            endTime: endTime,
            learningSituationSessionPlanId: learningSituationSessionPlanId.map { KotlinLong(value: $0) },
            status: status
        )
        let sessionId = try await container.plannerRepository.upsertSession(session: session).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var payload: [String: Any] = [
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
        if let teacherScheduleSlotId {
            payload["teacherScheduleSlotId"] = teacherScheduleSlotId
        }
        if let startTime {
            payload["startTime"] = startTime
        }
        if let endTime {
            payload["endTime"] = endTime
        }
        if let learningSituationSessionPlanId {
            payload["learningSituationSessionPlanId"] = learningSituationSessionPlanId
        }
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(sessionId)",
            updatedAtEpochMs: nowMs,
            payload: payload
        )
        return sessionId
    }

    func plannerDeleteSession(sessionId: Int64) async throws {
        try await container.plannerRepository.deleteSession(sessionId: sessionId)
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(sessionId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": sessionId
            ],
            op: "delete"
        )
    }

    func plannerListSessionTemplates() async throws -> [PlannerSessionTemplate] {
        try await container.plannerRepository.listSessionTemplates()
    }

    func plannerSaveSessionTemplate(
        id: Int64 = 0,
        title: String,
        category: String = "GENERAL",
        objectives: String,
        activities: String,
        evaluation: String = ""
    ) async throws -> Int64 {
        let template = PlannerSessionTemplate(
            id: id,
            title: title,
            category: category,
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            createdAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        return try await container.plannerRepository.saveSessionTemplate(template: template).int64Value
    }

    func plannerDeleteSessionTemplate(id: Int64) async throws -> Bool {
        try await container.plannerRepository.deleteSessionTemplate(templateId: id).boolValue
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

    func plannerPreviewCascadeMove(
        sourceSessionId: Int64,
        targetWeekNumber: Int,
        targetYear: Int,
        targetDayOfWeek: Int,
        targetPeriod: Int
    ) async throws -> SessionCascadeMovePreview {
        let request = SessionCascadeMoveRequest(
            sourceSessionId: sourceSessionId,
            targetWeekNumber: Int32(targetWeekNumber),
            targetYear: Int32(targetYear),
            targetDayOfWeek: Int32(targetDayOfWeek),
            targetPeriod: Int32(targetPeriod)
        )
        return try await container.plannerRepository.previewCascadeMove(request: request)
    }

    func plannerCommitCascadeMove(
        sourceSessionId: Int64,
        targetWeekNumber: Int,
        targetYear: Int,
        targetDayOfWeek: Int,
        targetPeriod: Int
    ) async throws -> SessionCascadeMoveResult {
        let request = SessionCascadeMoveRequest(
            sourceSessionId: sourceSessionId,
            targetWeekNumber: Int32(targetWeekNumber),
            targetYear: Int32(targetYear),
            targetDayOfWeek: Int32(targetDayOfWeek),
            targetPeriod: Int32(targetPeriod)
        )
        return try await container.plannerRepository.commitCascadeMove(request: request)
    }

    func plannerRestoreCascadeMove(_ previousPlacements: [SessionPlacement]) async throws -> SessionCascadeMoveResult {
        try await container.plannerRepository.restoreCascadeMove(previousPlacements: previousPlacements)
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
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: student.firstName,
            lastName: student.lastName,
            email: student.email,
            photoPath: student.photoPath,
            isInjured: student.isInjured,
            sex: sex,
            sexSource: sex == .unspecified ? .unknown : .manual,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
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
                "sexSource": sex == .unspecified ? StudentSexSource.unknown.name : StudentSexSource.manual.name,
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

    // MARK: - Reuniones de centro y actas (B-2)

    func meetings() async throws -> [MeetingSnapshot] {
        let rows = try await container.meetingRepository.listAll()
        return rows.compactMap(meetingSnapshot(from:))
    }

    func meeting(id: Int64) async throws -> MeetingSnapshot? {
        guard let row = try await container.meetingRepository.getById(id: id) else { return nil }
        return meetingSnapshot(from: row)
    }

    /// Acuerdos abiertos cuya fecha límite vence en o antes de `onOrBeforeIso`.
    func pendingMeetingAgreements(onOrBefore onOrBeforeIso: String) async throws -> [MeetingAgreementSnapshot] {
        let rows = try await container.meetingRepository.listPendingAgreements(onOrBeforeIso: onOrBeforeIso)
        return rows.map(meetingAgreementSnapshot(from:))
    }

    @discardableResult
    func saveMeeting(id: Int64? = nil, draft: MeetingDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.meetingRepository.saveMeeting(
            id: kotlinLong(id),
            title: draft.title,
            dateIso: draft.dateIso,
            type: kotlinMeetingType(draft.type),
            location: draft.location,
            attendees: draft.attendees,
            summary: draft.summary,
            isClosed: draft.isClosed,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "meetings",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "title": draft.title,
                "dateIso": draft.dateIso,
                "type": draft.type.rawValue,
                "location": draft.location,
                "attendees": draft.attendees,
                "summary": draft.summary,
                "isClosed": draft.isClosed
            ]
        )
        return savedId
    }

    func deleteMeeting(id: Int64) async throws {
        try await container.meetingRepository.deleteMeeting(id: id)
        enqueueLocalChange(
            entity: "meetings",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    @discardableResult
    func saveMeetingAgreement(id: Int64? = nil, draft: MeetingAgreementDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.meetingRepository.saveAgreement(
            id: kotlinLong(id),
            meetingId: draft.meetingId,
            description: draft.description,
            responsible: draft.responsible,
            dueIso: draft.dueIso,
            isDone: draft.isDone,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "meeting_agreements",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "meetingId": draft.meetingId,
                "description": draft.description,
                "responsible": draft.responsible,
                "dueIso": draft.dueIso ?? NSNull(),
                "isDone": draft.isDone
            ]
        )
        return savedId
    }

    func deleteMeetingAgreement(id: Int64) async throws {
        try await container.meetingRepository.deleteAgreement(id: id)
        enqueueLocalChange(
            entity: "meeting_agreements",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    /// `nil` si la fila trae un tipo que esta versión no conoce. Se descarta en
    /// vez de forzar un valor: mismo criterio que las tutorías.
    private func meetingSnapshot(from meeting: Meeting) -> MeetingSnapshot? {
        guard let type = MeetingTypeUI(rawValue: meeting.type.name) else { return nil }
        return MeetingSnapshot(
            id: meeting.id,
            title: meeting.title,
            dateIso: meeting.date.description(),
            type: type,
            location: meeting.location,
            attendees: meeting.attendees,
            summary: meeting.summary,
            isClosed: meeting.isClosed,
            agreements: meeting.agreements.map(meetingAgreementSnapshot(from:))
        )
    }

    private func meetingAgreementSnapshot(from agreement: MeetingAgreement) -> MeetingAgreementSnapshot {
        MeetingAgreementSnapshot(
            id: agreement.id,
            meetingId: agreement.meetingId,
            // `description_` con guion bajo: el nombre Kotlin `description` colisiona
            // con `-[NSObject description]`, y el puente lo renombra. Usar `.description`
            // devolvería el toString del objeto entero.
            description: agreement.description_,
            responsible: agreement.responsible,
            dueIso: agreement.due?.description(),
            isDone: agreement.isDone
        )
    }

    private func kotlinMeetingType(_ type: MeetingTypeUI) -> MeetingType {
        MeetingType.entries.first { $0.name == type.rawValue } ?? MeetingType.entries[0]
    }

    // MARK: - Plan pedagógico semanal (B-3)

    /// `nil` si aún no hay plan guardado para esa (clase, año, semana).
    func weekPlan(classId: Int64, year: Int, week: Int) async throws -> WeekPlanSnapshot? {
        guard let plan = try await container.plannerWeekPlanRepository.getPlan(
            classId: classId,
            year: Int32(year),
            week: Int32(week)
        ) else { return nil }
        return weekPlanSnapshot(from: plan)
    }

    @discardableResult
    func saveWeekPlan(id: Int64? = nil, draft: WeekPlanDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.plannerWeekPlanRepository.save(
            id: kotlinLong(id),
            classId: draft.classId,
            year: Int32(draft.year),
            week: Int32(draft.week),
            strategies: draft.strategyKeys,
            instruments: draft.instrumentKeys,
            notes: draft.notes,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "planner_week_plan",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "classId": draft.classId,
                "year": draft.year,
                "week": draft.week,
                "strategies": draft.strategyKeys,
                "instruments": draft.instrumentKeys,
                "notes": draft.notes
            ]
        )
        return savedId
    }

    private func weekPlanSnapshot(from plan: PlannerWeekPlan) -> WeekPlanSnapshot {
        WeekPlanSnapshot(
            id: plan.id,
            classId: plan.classId,
            year: Int(plan.year),
            week: Int(plan.week),
            strategyKeys: plan.strategies.map { String(describing: $0) },
            instrumentKeys: plan.instruments.map { String(describing: $0) },
            notes: plan.notes
        )
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
        try await container.learningSituationsRepository.getSessionPlan(id: id)
    }

    func learningSituationSessionPlans(sequenceVersionId: Int64) async throws -> [LearningSituationSessionPlan] {
        try await container.learningSituationsRepository.listSessionPlans(sequenceVersionId: sequenceVersionId)
    }

    /// Exposición de solo lectura para que el Planner pueda representar la última
    /// secuencia teórica incluso antes de que exista una sesión en el calendario.
    func learningSituationSessionSequenceVersions(
        learningSituationId: Int64
    ) async throws -> [LearningSituationSessionSequenceVersion] {
        try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: learningSituationId)
    }

    func learningSituationSessionSequenceVersion(id: Int64, learningSituationId: Int64) async throws -> LearningSituationSessionSequenceVersion? {
        try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: learningSituationId)
            .first { $0.id == id }
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
        let detailedPlanIds: [Int: Int64]
        if let sequenceDraft {
            detailedPlanIds = try await persistSessionSequence(situation: situation, draft: sequenceDraft)
        } else {
            detailedPlanIds = [:]
        }
        let orderedDraftPlans = sequenceDraft?.plans.sorted { $0.sessionNumber < $1.sessionNumber } ?? []
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
        let calendar = Calendar(identifier: .iso8601)
        for (index, slot) in scheduledSlots.enumerated() {
            let detailedDraft = index < orderedDraftPlans.count ? orderedDraftPlans[index] : nil
            let components = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear, .weekday], from: slot.date)
            let weekday = ((components.weekday ?? 2) + 5) % 7 + 1
            let weekNumber = components.weekOfYear ?? 1
            let year = components.yearForWeekOfYear ?? Calendar.current.component(.year, from: slot.date)
            let occupiedSession = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
                .first {
                    Int($0.dayOfWeek) == weekday && Int($0.period) == slot.period
                }
            let sessionId = try await plannerUpsertSession(
                id: occupiedSession?.id ?? 0,
                teachingUnitId: unitId,
                teachingUnitName: situation.title,
                teachingUnitColor: plannerCourseColor(for: classId),
                groupId: classId,
                groupName: groupName,
                dayOfWeek: weekday,
                period: slot.period,
                weekNumber: weekNumber,
                year: year,
                objectives: detailedDraft?.objective ?? situation.challenge,
                activities: detailedDraft?.developmentSummary ?? "Sesión vinculada a \(situation.title)",
                evaluation: detailedDraft?.criteria.joined(separator: ", ") ?? "",
                teacherScheduleSlotId: slot.teacherScheduleSlotId,
                startTime: slot.startTime,
                endTime: slot.endTime,
                learningSituationSessionPlanId: detailedDraft.flatMap { detailedPlanIds[$0.sessionNumber] },
                status: .planned
            )
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .planningSession,
                resourceId: "\(sessionId)",
                classId: classId,
                label: slot.label,
                trace: situation.trace
            )
        }
    }

    private func persistSessionSequence(
        situation: LearningSituation,
        draft: LearningSituationSessionSequenceImportDraft
    ) async throws -> [Int: Int64] {
        let storedURL = try LearningSituationDocumentStore().persistSourceDocument(from: draft.sourceURL, sha256: draft.sha256)
        let warningsJSON = String(data: try JSONEncoder().encode(draft.warnings), encoding: .utf8) ?? "[]"
        let existingVersions = try await container.learningSituationsRepository.listSessionSequenceVersions(learningSituationId: situation.id)
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
            let developmentJSON = String(data: try JSONEncoder().encode(plan.development), encoding: .utf8) ?? "[]"
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
        proposals: [LearningSituationEvaluationDraft]
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
            try await ensureNotebookColumnForEvaluation(classId: classId, evaluationId: evaluationId, title: proposal.title, rubricId: proposal.rubricId)
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: proposal.title,
                trace: situation.trace
            )
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
        if let existingResource = linkedResources.first(where: { $0.kind == .teachingUnit }),
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

    private func resolveNotebookTargetTabId(classId: Int64, preferredTabId: String?) async throws -> String {
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        if let preferredTabId, tabs.contains(where: { $0.id == preferredTabId }) {
            return preferredTabId
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
        specs: [(String, String, NotebookInstrumentItemType, [String])]
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
                helpText: nil,
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
        checklistItems: [ChecklistItemDraft] = []
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
            checklistItems: checklistItems
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

    private func downloadLearningSituationDocumentIfNeeded(sha256: String) async -> String? {
        let store = LearningSituationDocumentStore()
        let destination = store.directoryURL.appendingPathComponent("\(sha256).docx")
        if FileManager.default.fileExists(atPath: destination.path) { return destination.path }
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

    func savePhysicalResult(_ result: PhysicalTestResult, attempts: [PhysicalTestAttempt]) async throws {
        try await container.physicalTestsRepository.saveResult(result: result, attempts: attempts)
    }

    func listPhysicalResultsForAssignment(assignmentId: String) async throws -> [PhysicalTestResult] {
        try await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignmentId)
    }

    func listPhysicalResultsForStudent(studentId: Int64, testId: String) async throws -> [PhysicalTestResult] {
        try await container.physicalTestsRepository.listResultsForStudent(studentId: studentId, testId: testId)
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
        dateEpochMs: Int64
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
        let tabIds = selectedNotebookTabId.map { [$0] } ?? tabs.first.map { [$0.id] } ?? []
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
        guard !isPairingInFlight else {
            throw NSError(
                domain: "Sync",
                code: -207,
                userInfo: [NSLocalizedDescriptionKey: "Ya hay un emparejamiento LAN en curso."]
            )
        }

        let normalizedHost = LanSyncClient.normalizeHost(host)
        guard !normalizedHost.isEmpty else {
            throw NSError(
                domain: "Sync",
                code: -204,
                userInfo: [NSLocalizedDescriptionKey: "Introduce un host LAN válido para el desktop."]
            )
        }

        let previousToken = syncToken
        let previousHost = pairedSyncHost
        let previousServerId = pairedServerId
        let previousFingerprint = pairedServerFingerprint

        isPairingInFlight = true
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        defer {
            isPairingInFlight = false
        }

        let result: LanHandshakeResult
        do {
            result = try await runSyncOperationWithTimeout(seconds: 12) {
                try await self.lanSyncClient.handshake(
                    host: normalizedHost,
                    pin: pin,
                    deviceId: self.localDeviceId,
                    pinnedFingerprint: expectedFingerprint
                )
            }
        } catch {
            restartAutoSyncLoopIfPaired()
            throw error
        }
        if let expectedServerId, expectedServerId != result.serverId {
            restartAutoSyncLoopIfPaired()
            throw NSError(domain: "Sync", code: -203, userInfo: [NSLocalizedDescriptionKey: "Server ID no coincide con el esperado"])
        }

        syncToken = result.token
        pairedSyncHost = normalizedHost
        pairedServerId = result.serverId
        pairedServerFingerprint = result.certificateFingerprint

        do {
            try await runSyncOperationWithTimeout(seconds: 12) {
                try await self.performPullSync(
                    silent: true,
                    sinceEpochMsOverride: 0,
                    refreshAfterApply: false
                )
            }
            persistSyncSecrets()
            let now = Date()
            lastSuccessfulSyncAt = now
            lastFullPullAt = now
            publishSyncState {
                $0.syncStatusMessage = "Emparejado con \(normalizedHost)"
            }
            isPairingInFlight = false
            startAutoSyncLoop()
            startSyncEventListenerIfPaired()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncNow(reason: "pairing_refresh", forceFullPull: false, silent: true)
            }
        } catch {
            syncToken = previousToken
            pairedSyncHost = previousHost
            pairedServerId = previousServerId
            pairedServerFingerprint = previousFingerprint
            isPairingInFlight = false
            restartAutoSyncLoopIfPaired()
            throw NSError(
                domain: "Sync",
                code: -205,
                userInfo: [
                    NSLocalizedDescriptionKey: "El desktop respondió al emparejamiento, pero no al primer pull. Verifica que siga abierto y escuchando en la misma LAN. Detalle: \(error.localizedDescription)"
                ]
            )
        }
    }

    func unpairLanSync() async {
        if let host = pairedSyncHost, let token = syncToken {
            _ = try? await lanSyncClient.unpair(host: host, token: token, pinnedFingerprint: pairedServerFingerprint)
        }
        clearPersistedPairing()
        publishSyncState {
            $0.syncStatusMessage = "Desvinculado. Empareja de nuevo para reactivar la sync."
        }
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
            publishSyncState {
                $0.syncStatusMessage = "Pull manual fallido: \(error.localizedDescription)"
            }
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
        try await performPullSync(
            silent: silent,
            sinceEpochMsOverride: sinceEpochMsOverride,
            refreshAfterApply: true
        )
    }

    private func performPullSync(
        silent: Bool,
        sinceEpochMsOverride: Int64? = nil,
        refreshAfterApply: Bool
    ) async throws {
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
                deviceId: localDeviceId,
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
                deviceId: localDeviceId,
                pinnedFingerprint: pairedServerFingerprint
            )
        }
        
        try await applyIncomingLanChanges(
            pull.changes,
            serverEpochMs: pull.serverEpochMs,
            refreshAfterApply: refreshAfterApply
        )
        if !silent {
            publishSyncState {
                $0.syncStatusMessage = "Pull OK (\(pull.changeCount) cambios)"
            }
        }
    }

    private func applySyncEvent(_ event: LanSyncEvent) async {
        guard let changes = event.changes, !changes.isEmpty else {
            await syncNow(reason: "sse_event", forceFullPull: false, silent: true)
            return
        }
        do {
            try await applyIncomingLanChanges(
                changes,
                serverEpochMs: event.serverEpochMs,
                refreshAfterApply: true
            )
            publishSyncState {
                $0.syncStatusMessage = "Evento LAN OK (\(changes.count) cambios)"
            }
        } catch {
            await syncNow(reason: "sse_event_fallback", forceFullPull: false, silent: true)
        }
    }

    private func applyIncomingLanChanges(
        _ changes: [LanSyncChange],
        serverEpochMs: Int64,
        refreshAfterApply: Bool
    ) async throws {
        guard !changes.isEmpty else {
            lastSyncCursorEpochMs = serverEpochMs
            UserDefaults.standard.set(lastSyncCursorEpochMs, forKey: "sync.last.cursor")
            publishSyncState {
                $0.syncLastRunAt = Date()
            }
            return
        }

        try await applyPulledChanges(changes)
        lastSyncCursorEpochMs = serverEpochMs
        UserDefaults.standard.set(lastSyncCursorEpochMs, forKey: "sync.last.cursor")
        let pendingChangesCount = pendingOutboundChanges.count
        publishSyncState {
            $0.syncPendingChanges = pendingChangesCount
            $0.syncLastRunAt = Date()
        }

        guard refreshAfterApply else { return }

        // Ejecutamos los refreshes en una Task de utilidad para no bloquear el
        // MainActor run loop durante las queries encadenadas. Esto evita que la UI
        // se congele cuando el servidor LAN tarda o no está disponible.
        let capturedChanges = changes
        let capturedLocalDeviceId = localDeviceId
        postSyncRefreshTask?.cancel()
        postSyncRefreshTask = Task(priority: .utility) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.refreshDashboard()
                guard !Task.isCancelled else { return }
                try await self.refreshClasses()
                guard !Task.isCancelled else { return }
                try await self.refreshStudentsDirectory()
                guard !Task.isCancelled else { return }
                try await self.refreshRubrics()
                guard !Task.isCancelled else { return }
                try await self.refreshRubricClassLinks()
                guard !Task.isCancelled else { return }
                try await self.refreshPlanning()
                guard !Task.isCancelled else { return }

                // Solo refrescar el cuaderno si alguno de los cambios sincronizados
                // afecta a entidades del cuaderno (grades, columnas, celdas, rúbricas).
                // Esto evita recargas innecesarias cuando solo cambian clases o alumnos.
                let notebookEntityTypes: Set<String> = [
                    "grade", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_cell", "rubric_assessment", "student", "class", "class_roster", "evaluation", "notebook_group", "notebook_group_member", "notebook_instrument_template", "notebook_instrument_item", "notebook_instrument_response"
                ]
                let hasNotebookChangesFromRemote = capturedChanges.contains {
                    notebookEntityTypes.contains($0.entity) && $0.deviceId != capturedLocalDeviceId
                }
                if hasNotebookChangesFromRemote {
                    self.refreshCurrentNotebook()
                }
            } catch {
                self.publishSyncState {
                    $0.syncStatusMessage = "Error al refrescar datos tras sincronizar: \(error.localizedDescription)"
                }
                print("No se pudieron refrescar los datos tras aplicar cambios LAN: \(error.localizedDescription)")
            }
        }
    }

    private func performPushSync(silent: Bool) async throws {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -41, userInfo: [NSLocalizedDescriptionKey: "No hay emparejamiento activo"])
        }
        guard !pendingOutboundChanges.isEmpty else {
            if !silent {
                publishSyncState {
                    $0.syncStatusMessage = "No hay cambios pendientes"
                }
            }
            return
        }

        // Snapshot lo que vamos a enviar. Los cambios que se encolen mientras la
        // petición de red está en curso (el `await`) no deben perderse cuando
        // limpiemos la cola al recibir la respuesta.
        let sentChanges = pendingOutboundChanges

        let ack: LanPushResult
        do {
            ack = try await lanSyncClient.push(
                host: host,
                token: token,
                deviceId: localDeviceId,
                changes: sentChanges,
                lastKnownServerEpochMs: lastSyncCursorEpochMs,
                pinnedFingerprint: pairedServerFingerprint
            )
        } catch {
            guard recoverHostAfterNetworkChange(previousHost: host), let reboundHost = pairedSyncHost else {
                throw error
            }
            ack = try await lanSyncClient.push(
                host: reboundHost,
                token: token,
                deviceId: localDeviceId,
                changes: sentChanges,
                lastKnownServerEpochMs: lastSyncCursorEpochMs,
                pinnedFingerprint: pairedServerFingerprint
            )
        }
        // Un round-trip exitoso significa que el servidor ya resolvió cada cambio
        // del lote (aplicado, ignorado por LWW o rechazado por payload inválido).
        // Reintentar un ignored/failed sin una edición local más reciente nunca
        // tendría éxito, así que soltamos siempre el snapshot enviado en vez de
        // condicionar a `applied > 0` — de lo contrario un lote totalmente
        // ignorado reintentaría para siempre y "pendientes" nunca bajaría a 0.
        // Solo quitamos las entradas que coinciden exactamente con lo enviado:
        // si el mismo entity/id se volvió a editar durante el `await`, la entrada
        // más nueva en la cola no será igual (Equatable) al snapshot y se conserva.
        pendingOutboundChanges.removeAll { sentChanges.contains($0) }
        persistPendingChanges()
        if ack.desktopAuthoritative {
            try await performPullSync(
                silent: true,
                sinceEpochMsOverride: 0
            )
        }
        let pendingChangesCount = pendingOutboundChanges.count
        publishSyncState {
            $0.syncPendingChanges = pendingChangesCount
            $0.syncLastRunAt = Date()
        }
        if !silent {
            let statusMessage = ack.desktopAuthoritative
                ? "macOS prevalece; cambios locales descartados"
                : "Push OK (\(ack.applied) aplicados)"
            publishSyncState {
                $0.syncStatusMessage = statusMessage
            }
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

    func saveNotebookWorkGroup(name: String, learningSituationId: Int64? = nil) {
        let situationKotlin = KotlinLong(value: learningSituationId ?? -1)
        notebookViewModel.saveWorkGroup(name: name, groupId: nil, studentIds: [], learningSituationId: situationKotlin)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func updateNotebookWorkGroup(groupId: Int64, name: String, learningSituationId: Int64? = nil) {
        let situationKotlin = KotlinLong(value: learningSituationId ?? -1)
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: [], learningSituationId: situationKotlin)
        if let classId = notebookViewModel.currentClassId?.int64Value {
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    func renameNotebookWorkGroup(groupId: Int64, name: String) {
        notebookViewModel.saveWorkGroup(name: name, groupId: KotlinLong(value: groupId), studentIds: [], learningSituationId: nil)
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

    @MainActor
    func startRubricEvaluationCoordinator(
        columnId: String,
        rubricId: Int64,
        classId: Int64,
        evaluationId: Int64,
        studentIds: [Int64],
        currentStudentId: Int64
    ) {
        rubricEvaluationCoordinator.start(
            columnId: columnId,
            rubricId: rubricId,
            classId: classId,
            evaluationId: evaluationId,
            studentIds: studentIds,
            currentStudentId: currentStudentId
        )
        isNotebookRubricAutoAdvanceActive = true
    }

    @MainActor
    func openRubricEvaluationFromNotebook(studentId: Int64, columnId: String, rubricId: Int64, evaluationId: Int64) {
        closeBulkRubricEvaluation()
        isNotebookRubricAutoAdvanceActive = true
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
                title: item.title,
                type: item.type,
                options: item.options,
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
    private func plainStructuredNumberString(_ value: Double) -> String {
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

    @MainActor
    func advanceRubricEvaluationToNextStudent(visibleStudentIds: [Int64]? = nil) -> RubricEvaluationAdvanceResult {
        guard let context = rubricEvaluationCoordinator.context else {
            closeRubricEvaluation()
            return .closed
        }

        refreshCurrentNotebook()
        if context.classId > 0 {
            scheduleNotebookSnapshotSync(forClassId: context.classId)
        }

        if let nextStudentId = rubricEvaluationCoordinator.advance(visibleStudentIds: visibleStudentIds),
           let nextContext = rubricEvaluationCoordinator.context {
            rubricEvaluationState = RubricEvaluationUiState.companion.default()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.openRubricEvaluationFromNotebook(
                    studentId: nextStudentId,
                    columnId: nextContext.columnId,
                    rubricId: nextContext.rubricId,
                    evaluationId: nextContext.evaluationId
                )
            }
            return .openedNext(
                studentId: nextStudentId,
                remainingCount: rubricEvaluationCoordinator.lastSummary?.remainingCount ?? 0
            )
        }

        let summary = rubricEvaluationCoordinator.lastSummary ?? RubricEvaluationAdvanceSummary(
            evaluatedCount: context.studentIds.count,
            remainingCount: 0
        )
        closeRubricEvaluation()
        return .completed(summary)
    }

    func openAgendaNavigationTarget(_ target: AgendaNavigationTarget) {
        guard let studentId = target.studentId?.int64Value,
              let classId = target.classId?.int64Value,
              let evaluationId = target.evaluationId?.int64Value,
              let rubricId = target.rubricId?.int64Value,
              let columnId = target.columnId?.nilIfEmpty else {
            status = "La agenda no pudo resolver la rúbrica seleccionada."
            return
        }

        if showingBulkRubricEvaluation {
            closeBulkRubricEvaluation()
        }
        closeRubricEvaluation()
        if notebookViewModel.currentClassId?.int64Value != classId {
            selectClass(id: classId)
        }
        rubricEvaluationViewModel.loadForNotebookCell(
            studentId: studentId,
            columnId: columnId,
            rubricId: rubricId,
            evaluationId: evaluationId
        )
    }

    func saveRubricEvaluation(
        manual: Bool = true,
        emitNotebookRefresh: Bool = true,
        onSuccess: @escaping () -> Void = {}
    ) {
        rubricEvaluationViewModel.save(manual: manual, emitNotebookRefresh: emitNotebookRefresh) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if emitNotebookRefresh {
                    self.refreshCurrentNotebook()
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
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

    func startBulkRubricEvaluation(
        classId: Int64,
        evaluationId: Int64,
        rubricId: Int64,
        columnId: String? = nil,
        tabId: String? = nil
    ) {
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
        rubricBulkEvaluationViewModel.load(
            classId: classId,
            evaluationId: evaluationId,
            rubricId: rubricId,
            columnId: columnId,
            tabId: tabId
        )
        showingBulkRubricEvaluation = true
    }

    @MainActor
    func launchBulkRubricEvaluationFromRubric(
        rubricId: Int64,
        preferredClassId: Int64? = nil
    ) async -> Bool {
        do {
            let usage = try await loadRubricUsage(rubricId: rubricId)
            let sortedUsages = usage.evaluationUsages.sorted { lhs, rhs in
                if let preferredClassId {
                    if lhs.classId == preferredClassId && rhs.classId != preferredClassId { return true }
                    if rhs.classId == preferredClassId && lhs.classId != preferredClassId { return false }
                }
                if lhs.className == rhs.className {
                    return lhs.evaluationName.localizedCaseInsensitiveCompare(rhs.evaluationName) == .orderedAscending
                }
                return lhs.className.localizedCaseInsensitiveCompare(rhs.className) == .orderedAscending
            }

            guard let target = sortedUsages.first else {
                status = "Esta rúbrica no está vinculada a ninguna evaluación."
                return false
            }

            return await launchBulkRubricEvaluationFromUsage(
                rubricId: rubricId,
                classId: target.classId,
                evaluationId: target.evaluationId
            )
        } catch {
            status = "Error abriendo evaluación masiva: \(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    func launchBulkRubricEvaluationFromUsage(
        rubricId: Int64,
        classId: Int64,
        evaluationId: Int64
    ) async -> Bool {
        do {
            let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
            let column = columns.first { $0.evaluationId?.int64Value == evaluationId }

            rubricEvaluationState = RubricEvaluationUiState.companion.default()
            rubricBulkEvaluationViewModel.load(
                classId: classId,
                evaluationId: evaluationId,
                rubricId: rubricId,
                columnId: column?.id,
                tabId: column?.tabIds.first
            )
            showingBulkRubricEvaluation = true

            if column == nil {
                status = "Abriendo evaluación masiva sin columna vinculada del cuaderno."
            }
            return true
        } catch {
            status = "Error abriendo evaluación masiva: \(error.localizedDescription)"
            return false
        }
    }
    
    func closeBulkRubricEvaluation() {
        showingBulkRubricEvaluation = false
        // Al cerrar la masiva, limpiamos cualquier overlay individual residual.
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
    }

    func closeRubricEvaluation() {
        rubricEvaluationState = RubricEvaluationUiState.companion.default()
        isNotebookRubricAutoAdvanceActive = false
        rubricEvaluationCoordinator.reset()
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
        bulkAssessmentSnapshot()[studentId]?[criterionId]
    }
    
    func bulkScore(studentId: Int64) -> Double? {
        bulkScoreSnapshot()[studentId]
    }

    func bulkAssessmentSnapshot() -> [Int64: [Int64: Int64]] {
        guard let rawAssessments = bulkRubricEvaluationState?.assessments as NSDictionary? else {
            return [:]
        }

        var snapshot: [Int64: [Int64: Int64]] = [:]
        for (rawStudentId, rawStudentAssessments) in rawAssessments {
            guard let studentId = int64Value(rawStudentId),
                  let rawStudentAssessments = rawStudentAssessments as? NSDictionary else {
                continue
            }

            var selections: [Int64: Int64] = [:]
            for (rawCriterionId, rawLevelId) in rawStudentAssessments {
                guard let criterionId = int64Value(rawCriterionId),
                      let levelId = int64Value(rawLevelId) else {
                    continue
                }
                selections[criterionId] = levelId
            }
            snapshot[studentId] = selections
        }

        return snapshot
    }

    func bulkScoreSnapshot() -> [Int64: Double] {
        guard let rawScores = bulkRubricEvaluationState?.scores as NSDictionary? else {
            return [:]
        }

        var snapshot: [Int64: Double] = [:]
        for (rawStudentId, rawScore) in rawScores {
            guard let studentId = int64Value(rawStudentId),
                  let score = doubleValue(rawScore) else {
                continue
            }
            snapshot[studentId] = score
        }
        return snapshot
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
        editingRubricBuilderId = nil
        selectedRubricTeachingUnitId = nil
        rubricBuilderTeachingUnits = []
        rubricsViewModel.resetBuilder()
    }

    func importRubricDraft(tsv: String) async throws {
        guard let imported = appleImportFacade.previewRubricFromTsv(text: tsv) else {
            throw NSError(domain: "KmpBridge", code: -63, userInfo: [NSLocalizedDescriptionKey: "El archivo no tiene un formato de rúbrica válido."])
        }
        editingRubricBuilderId = nil
        selectedRubricTeachingUnitId = nil
        rubricBuilderTeachingUnits = []
        rubricsViewModel.loadImportedRubric(importedState: imported)
        rubricsUiState = rubricsViewModel.uiState.value as? RubricUiState
    }

    func loadRubricForEditing(_ rubric: RubricDetail) {
        editingRubricBuilderId = rubric.rubric.id
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

    // Audit debt: this mirrors RubricsViewModel save/edit logic in Swift. Keep changes minimal
    // here and move persistence orchestration back to KMP with dedicated tests in a later pass.
    @MainActor
    func saveRubricFromBuilderReturningId() async throws -> Int64 {
        guard let state = rubricsUiState else {
            throw NSError(domain: "KmpBridge", code: -71, userInfo: [NSLocalizedDescriptionKey: "No hay una rúbrica preparada para guardar."])
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let editingRubricId = editingRubricBuilderId
        let rubricId = try await container.rubricsRepository.saveRubric(
            id: editingRubricId.map { KotlinLong(value: $0) },
            name: state.rubricName,
            description: state.instructions.nilIfBlank,
            classId: state.selectedClassId,
            teachingUnitId: selectedRubricTeachingUnitId.map { KotlinLong(value: $0) },
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: editingRubricId == nil ? 1 : 2
        ).int64Value

        if let editingRubricId {
            let retainedCriterionIds = Set(state.criteria.compactMap { $0.id?.int64Value })
            let existingCriteria = try await container.rubricsRepository.listCriteriaByRubric(rubricId: editingRubricId)
            for existingCriterion in existingCriteria where !retainedCriterionIds.contains(existingCriterion.id) {
                try await container.rubricsRepository.deleteCriterion(criterionId: existingCriterion.id)
            }
        }

        let retainedLevelOrders = Set(state.levels.map { Int32($0.order) })
        for criterion in state.criteria {
            let existingLevelsByOrder: [Int32: RubricLevel]
            if let existingCriterionId = criterion.id?.int64Value {
                let existingLevels = try await container.rubricsRepository.listLevelsByCriterion(criterionId: existingCriterionId)
                for existingLevel in existingLevels where !retainedLevelOrders.contains(Int32(existingLevel.order)) {
                    try await container.rubricsRepository.deleteLevel(levelId: existingLevel.id)
                }
                existingLevelsByOrder = Dictionary(
                    existingLevels.map { (Int32($0.order), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                existingLevelsByOrder = [:]
            }

            let criterionId = try await container.rubricsRepository.saveCriterion(
                id: criterion.id,
                rubricId: rubricId,
                description: criterion.description_,
                weight: criterion.weight,
                order: Int32(criterion.order),
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId,
                syncVersion: criterion.id == nil ? 1 : 2
            ).int64Value

            for level in state.levels {
                let reusableLevelId = existingLevelsByOrder[Int32(level.order)]?.id
                _ = try await container.rubricsRepository.saveLevel(
                    id: reusableLevelId.map { KotlinLong(value: $0) },
                    criterionId: criterionId,
                    name: level.name,
                    points: Int32(level.points),
                    description: criterion.levelDescriptions[level.uid],
                    order: Int32(level.order),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: reusableLevelId == nil ? 1 : 2
                )
            }
        }

        enqueueLocalChange(
            entity: "rubric_bundle",
            id: "\(rubricId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "rubricId": rubricId,
                "editingRubricId": editingRubricId ?? NSNull(),
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
        editingRubricBuilderId = rubricId
        return rubricId
    }

    func saveRubricFromBuilder(onComplete: @escaping (Bool) -> Void) {
        Task { @MainActor in
            do {
                _ = try await saveRubricFromBuilderReturningId()
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

    func plannerRenameTeachingUnit(_ unit: TeachingUnit, newName: String) async throws {
        let normalized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let renamed = TeachingUnit(
            id: unit.id,
            name: normalized,
            description: unit.description,
            colorHex: unit.colorHex,
            groupId: unit.groupId,
            schoolClassId: unit.schoolClassId,
            startDate: unit.startDate,
            endDate: unit.endDate
        )
        _ = try await container.plannerRepository.upsertTeachingUnit(unit: renamed)
    }

    func plannerDeleteTeachingUnit(_ unitId: Int64) async throws {
        let sessionsUsingUnit = try await container.plannerRepository.listAllSessions()
            .filter { $0.teachingUnitId == unitId }
        guard sessionsUsingUnit.isEmpty else {
            throw NSError(
                domain: "KmpBridge",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "No se puede eliminar: hay \(sessionsUsingUnit.count) sesión(es) que usan esta unidad. Elimínalas o cámbialas de unidad primero."]
            )
        }
        _ = try await container.plannerRepository.deleteTeachingUnit(unitId: unitId)
    }

    func plannerAvailableAssessmentInstruments(classId: Int64, teachingUnitId: Int64?) async throws -> [PlannerAssessmentInstrument] {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let rubricDetails = try await container.rubricsRepository.listRubrics()
        let classUnits = try await plannerTeachingUnits(for: classId)
        let currentTeachingUnitName = teachingUnitId.flatMap { plannerTeachingUnitName(for: $0, cachedUnits: classUnits) }
        let evaluationsByRubricId = Dictionary(grouping: evaluations.compactMap { evaluation -> (Int64, Evaluation)? in
            guard let rubricId = evaluation.rubricId?.int64Value else { return nil }
            return (rubricId, evaluation)
        }, by: { $0.0 }).mapValues { pairs in
            pairs.map(\.1)
        }
        let rubricIdsFromEvaluations = Set(evaluationsByRubricId.keys)

        let evaluationInstruments = evaluations.map { evaluation in
            let groupTitle = plannerInstrumentGroupTitle(
                teachingUnitId: nil,
                evaluationDescription: evaluation.description_,
                cachedUnits: classUnits
            )
            let cleanTitle = cleanPlannerInstrumentText(evaluation.name, fallback: "Evaluación")
            let cleanType = cleanPlannerInstrumentText(evaluation.type, fallback: "Evaluación")
            let cleanDescription = cleanPlannerInstrumentText(evaluation.description_, fallback: "")
            return PlannerAssessmentInstrument(
                kind: .evaluation,
                rawId: evaluation.id,
                title: cleanTitle,
                subtitle: cleanDescription.isEmpty ? cleanType : "\(cleanType) · \(cleanDescription)",
                classId: classId,
                teachingUnitId: nil,
                evaluationId: evaluation.id,
                rubricId: evaluation.rubricId?.int64Value,
                resolvedEvaluationId: evaluation.id,
                groupTitle: groupTitle,
                isRecommendedForCurrentSA: plannerInstrumentMatchesCurrentSA(
                    teachingUnitId: nil,
                    groupTitle: groupTitle,
                    currentTeachingUnitId: teachingUnitId,
                    currentTeachingUnitName: currentTeachingUnitName
                )
            )
        }

        let rubricInstruments = rubricDetails.compactMap { detail -> PlannerAssessmentInstrument? in
            let rubric = detail.rubric
            let rubricClassId = rubric.classId?.int64Value
            let linkedEvaluations = evaluationsByRubricId[rubric.id] ?? []
            let isDirectlyForClass = rubricClassId == classId
            let isLinkedToClassEvaluation = rubricIdsFromEvaluations.contains(rubric.id)
            guard isDirectlyForClass || isLinkedToClassEvaluation else {
                return nil
            }
            let rubricTeachingUnitId = rubric.teachingUnitId?.int64Value
            let linkedEvaluationDescription = linkedEvaluations
                .compactMap { $0.description_?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let groupTitle = plannerInstrumentGroupTitle(
                teachingUnitId: rubricTeachingUnitId,
                evaluationDescription: linkedEvaluationDescription,
                cachedUnits: classUnits
            )
            let resolvedEvaluationId = linkedEvaluations.first?.id
            let cleanTitle = cleanPlannerInstrumentText(rubric.name, fallback: "Rúbrica")
            return PlannerAssessmentInstrument(
                kind: .rubric,
                rawId: rubric.id,
                title: cleanTitle,
                subtitle: groupTitle == "Sin situación asignada" ? "Rúbrica" : cleanPlannerInstrumentText(groupTitle, fallback: "Rúbrica"),
                classId: classId,
                teachingUnitId: rubricTeachingUnitId,
                evaluationId: resolvedEvaluationId,
                rubricId: rubric.id,
                resolvedEvaluationId: resolvedEvaluationId,
                groupTitle: groupTitle,
                isRecommendedForCurrentSA: plannerInstrumentMatchesCurrentSA(
                    teachingUnitId: rubricTeachingUnitId,
                    groupTitle: groupTitle,
                    currentTeachingUnitId: teachingUnitId,
                    currentTeachingUnitName: currentTeachingUnitName
                )
            )
        }

        let prioritized = rubricInstruments.sorted { lhs, rhs in
            let lhsMatch = lhs.teachingUnitId == teachingUnitId
            let rhsMatch = rhs.teachingUnitId == teachingUnitId
            if lhsMatch != rhsMatch { return lhsMatch && !rhsMatch }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        var seenInstrumentIds = Set<String>()
        let uniqueInstruments = (evaluationInstruments + prioritized).filter { instrument in
            seenInstrumentIds.insert(instrument.id).inserted
        }

        return uniqueInstruments.sorted {
            if $0.groupTitle != $1.groupTitle {
                return $0.groupTitle.localizedCaseInsensitiveCompare($1.groupTitle) == .orderedAscending
            }
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
        teacherScheduleSlotId: Int64? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        learningSituationSessionPlanId: Int64? = nil,
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
            teacherScheduleSlotId: teacherScheduleSlotId,
            startTime: startTime,
            endTime: endTime,
            learningSituationSessionPlanId: learningSituationSessionPlanId,
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
            teacherScheduleSlotId: nil,
            startTime: nil,
            endTime: nil,
            learningSituationSessionPlanId: nil,
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

    private func enqueueLocalChange(
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

    private func publishSyncState(_ update: @escaping @MainActor (KmpBridge) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            update(self)
        }
    }

    func setSyncStatusMessage(_ message: String) {
        publishSyncState {
            $0.syncStatusMessage = message
        }
    }

    private func persistPendingChanges() {
        pendingChangesPersistenceTask?.cancel()
        let snapshot = pendingOutboundChanges
        pendingChangesPersistenceTask = Task.detached(priority: .utility) {
            guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
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
            try? await Task.sleep(nanoseconds: 900_000_000)
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
                    "isInjured": student.isInjured,
                    "sex": student.sex.name,
                    "sexSource": student.sexSource.name,
                    "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
            shouldPersist: false,
            shouldScheduleAutoSync: false
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
                    "rubricId": evaluation.rubricId?.int64Value ?? 0,
                    // `description` a secas es el `description` de NSObject (el toString del
                    // objeto Kotlin, "Evaluation(id=…, code=…)"); el campo real del dominio se
                    // expone en Swift como `description_`. Enviar el primero sincronizaba ese
                    // volcado como si fuera la descripción del criterio de evaluación.
                    "description": evaluation.description_ ?? ""
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        columns.forEach { column in
            notebookSyncCache.deviceIdByEntityId[column.id] = column.trace.deviceId ?? localDeviceId
            let tabTitlesById = Dictionary(
                tabs.map { ($0.id, $0.title) },
                uniquingKeysWith: { first, _ in first }
            )
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
                    "evaluationId": column.evaluationId?.int64Value ?? 0,
                    "rubricId": column.rubricId?.int64Value ?? 0,
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
                    "colorHex": column.colorHex ?? "",
                    "categoryKind": column.categoryKind.name,
                    "instrumentKind": column.instrumentKind.name,
                    "inputKind": column.inputKind.name,
                    "scaleKind": column.scaleKind.name,
                    "dateEpochMs": column.dateEpochMs?.int64Value ?? 0,
                    "unitOrSituation": column.unitOrSituation ?? "",
                    "competencyCriteriaIds": column.competencyCriteriaIds.map { "\($0)" }.joined(separator: ","),
                    "iconName": column.iconName ?? "",
                    "order": Int(column.order),
                    "widthDp": column.widthDp,
                    "countsTowardAverage": column.countsTowardAverage,
                    "isPinned": column.isPinned,
                    "isHidden": column.isHidden,
                    "visibility": column.visibility.name,
                    "isLocked": column.isLocked,
                    "isTemplate": column.isTemplate
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
                    "evaluationId": grade.evaluationId?.int64Value ?? 0,
                    "value": grade.value ?? NSNull(),
                    "evidence": grade.evidence ?? NSNull(),
                    "evidencePath": grade.evidencePath ?? NSNull(),
                    "rubricSelections": grade.rubricSelections ?? NSNull()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        // Instrumentos estructurados (plantilla, sus ítems y las respuestas por alumno). Sin esto
        // el dispositivo donde se importa la situación de aprendizaje se queda la rejilla para sí:
        // el resto solo recibe la columna, abre la celda y ve "Sin plantilla". `KmpBridge` y
        // `SqlDelightSyncAdapter` ya sabían aplicar estas tres entidades al recibirlas, pero nadie
        // las emitía.
        for column in columns where column.inputKind.isStructuredInstrument {
            guard let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id) else {
                continue
            }
            let template = detail.template_
            enqueueLocalChange(
                entity: "notebook_instrument_template",
                id: template.id,
                updatedAtEpochMs: template.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": template.id,
                    "classId": template.classId,
                    "columnId": template.columnId,
                    "evaluationId": template.evaluationId?.int64Value ?? 0,
                    "title": template.title,
                    "kind": template.kind.name,
                    "inputKind": template.inputKind.name,
                    "source": template.source ?? "",
                    "createdAtEpochMs": template.trace.createdAt.toEpochMilliseconds()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
            detail.items.forEach { item in
                enqueueLocalChange(
                    entity: "notebook_instrument_item",
                    id: item.id,
                    updatedAtEpochMs: item.trace.updatedAt.toEpochMilliseconds(),
                    payload: [
                        "id": item.id,
                        "templateId": item.templateId,
                        "itemKey": item.key,
                        "title": item.title,
                        "itemType": item.type.name,
                        "optionsCsv": item.options.joined(separator: "|"),
                        "required": item.required,
                        "sortOrder": Int(item.order),
                        "helpText": item.helpText ?? ""
                    ],
                    shouldPersist: false,
                    shouldScheduleAutoSync: false
                )
            }
            for student in students {
                let studentResponses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(
                    classId: classId,
                    studentId: student.id,
                    columnId: column.id
                )) ?? []
                studentResponses.forEach { response in
                    enqueueLocalChange(
                        entity: "notebook_instrument_response",
                        id: "\(response.classId)-\(response.studentId)-\(response.columnId)-\(response.itemId)",
                        updatedAtEpochMs: response.trace.updatedAt.toEpochMilliseconds(),
                        payload: [
                            "classId": response.classId,
                            "studentId": response.studentId,
                            "columnId": response.columnId,
                            "itemId": response.itemId,
                            "valueText": response.textValue ?? "",
                            "valueBool": response.boolValue?.boolValue ?? false,
                            "valueNumber": response.numberValue.map { plainStructuredNumberString($0.doubleValue) } ?? ""
                        ],
                        shouldPersist: false,
                        shouldScheduleAutoSync: false
                    )
                }
            }
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
                        shouldPersist: false,
                        shouldScheduleAutoSync: false
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
        triggerAutoSyncSoon(delayNanoseconds: 900_000_000)
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
                shouldPersist: false,
                shouldScheduleAutoSync: false
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
        let orderedChanges = orderedPulledChanges(changes)
        for (index, change) in orderedChanges.enumerated() {
            if index.isMultiple(of: 25) {
                await Task.yield()
            }
            // El servidor ya filtra los cambios propios del dispositivo que pide el
            // pull (ver /sync/pull en LocalSyncServer.kt), pero mantenemos esta
            // comprobación como red de seguridad por si el peer aún no tiene ese
            // filtro (versión anterior del Mac) — reaplicar nuestro propio cambio
            // es, en el mejor caso, trabajo desperdiciado y, en el peor, un pull
            // completo periódico reprocesando toda la base de datos local.
            if change.deviceId == localDeviceId {
                continue
            }
            do {
            let payloadData = change.payload.data(using: .utf8) ?? Data()
            let payloadObject = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]

            if change.op == "delete" {
                try await applyDeletedChange(change: change, payloadObject: payloadObject)
                // Deja un tombstone: si el otro dispositivo empuja más tarde un upsert
                // fechado ANTES de este borrado, no debe resucitar la entidad (ver el
                // chequeo simétrico justo antes del switch de abajo).
                try? await container.syncTombstoneRepository.recordTombstone(
                    entity: change.entity,
                    entityId: change.id,
                    deletedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId
                )
                continue
            }

            // Un upsert fechado antes (o igual) que el último borrado conocido de esta
            // misma entidad no debe resucitarla: el borrado es más reciente y gana LWW.
            let isBlockedByTombstone = (try? await container.syncTombstoneRepository.isDeletedAtOrAfter(
                entity: change.entity,
                entityId: change.id,
                updatedAtEpochMs: change.updatedAtEpochMs
            ))?.boolValue ?? false
            if isBlockedByTombstone {
                continue
            }

            switch change.entity {
            case "academic_year":
                guard
                    let yearId = int64Value(payloadObject["id"]),
                    let name = payloadObject["name"] as? String,
                    let startEpochMs = int64Value(payloadObject["startEpochMs"]),
                    let endEpochMs = int64Value(payloadObject["endEpochMs"])
                else { continue }
                _ = try await container.academicYearsRepository.upsertAcademicYear(
                    id: yearId,
                    centerId: int64Value(payloadObject["centerId"]) ?? 1,
                    name: name,
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs,
                    status: payloadObject["status"] as? String ?? "ACTIVE",
                    isActive: payloadObject["isActive"] as? Bool ?? false,
                    archivedAtEpochMs: kotlinLong(positiveInt64Value(payloadObject["archivedAtEpochMs"])),
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

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
                    centerId: kotlinLong(positiveInt64Value(payloadObject["centerId"])),
                    academicYearId: kotlinLong(positiveInt64Value(payloadObject["academicYearId"])),
                    stageCycleId: kotlinLong(positiveInt64Value(payloadObject["stageCycleId"])),
                    subjectId: kotlinLong(positiveInt64Value(payloadObject["subjectId"])),
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
                    sex: studentSex(from: payloadObject["sex"]),
                    sexSource: studentSexSource(from: payloadObject["sexSource"]),
                    birthDate: localDate(from: payloadObject["birthDate"]),
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
                    // Añadir siempre es seguro (ver razonamiento equivalente en
                    // SqlDelightSyncAdapter.applyIncomingChangesLww, misma entidad).
                    try await container.classesRepository.addStudentToClass(classId: classId, studentId: id)
                }
                for id in localIds.subtracting(remoteIds) {
                    // Solo dar de baja si este snapshot es al menos tan reciente como
                    // la última alta/baja local conocida para ESTE alumno: evita que un
                    // snapshot de roster desactualizado borre a alguien recién añadido.
                    let localEnrollmentAt = (try await container.classesRepository.latestEnrollmentUpdatedAt(classId: classId, studentId: id))?.int64Value
                    if localEnrollmentAt == nil || change.updatedAtEpochMs >= localEnrollmentAt! {
                        try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: id)
                    }
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
                        evidence: payloadObject["evidence"] as? String,
                        evidencePath: payloadObject["evidencePath"] as? String,
                        rubricSelections: payloadObject["rubricSelections"] as? String,
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
                        fixedColumnWidth: nil,
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
                        learningSituationId: nil,
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
                        emptyCellPolicy: .excludeFromAverage,
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

            case "notebook_instrument_template":
                guard
                    let id = payloadObject["id"] as? String,
                    let classId = int64Value(payloadObject["classId"]),
                    let columnId = payloadObject["columnId"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let kindStr = (payloadObject["kind"] as? String) ?? "observation"
                let inputKindStr = (payloadObject["inputKind"] as? String) ?? "structuredObservation"
                let kind = notebookInstrumentTemplateKind(kindStr)
                let inputKind = notebookInputKind(inputKindStr)
                let evaluationId = int64Value(payloadObject["evaluationId"]).flatMap { $0 > 0 ? KotlinLong(value: $0) : nil }
                let source = payloadObject["source"] as? String
                let createdAtMs = int64Value(payloadObject["createdAtEpochMs"]) ?? change.updatedAtEpochMs
                let createdAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: createdAtMs)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)

                let template = NotebookInstrumentTemplate(
                    id: id,
                    classId: classId,
                    columnId: columnId,
                    evaluationId: evaluationId,
                    title: title,
                    kind: kind,
                    inputKind: inputKind,
                    source: source,
                    trace: AuditTrace(
                        authorUserId: nil,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        associatedGroupId: KotlinLong(value: classId),
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                let existingItems = (try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId))?.items ?? []
                try await container.notebookInstrumentsRepository.saveTemplate(template: template, items: existingItems)

            case "notebook_instrument_item":
                guard
                    let id = payloadObject["id"] as? String,
                    let templateId = payloadObject["templateId"] as? String,
                    let itemKey = payloadObject["itemKey"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let itemTypeStr = (payloadObject["itemType"] as? String) ?? "scale14"
                let itemType = notebookInstrumentItemType(itemTypeStr)
                let optionsCsv = (payloadObject["optionsCsv"] as? String) ?? ""
                let options = optionsCsv.split(separator: "|").map(String.init).filter { !$0.isEmpty }
                let required = boolValue(payloadObject["required"]) ?? true
                let sortOrder = int64Value(payloadObject["sortOrder"]) ?? 0
                let helpText = payloadObject["helpText"] as? String
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)

                let item = NotebookInstrumentItem(
                    id: id,
                    templateId: templateId,
                    key: itemKey,
                    title: title,
                    type: itemType,
                    options: options,
                    required: required,
                    order: Int32(sortOrder),
                    helpText: helpText?.isEmpty == true ? nil : helpText,
                    trace: AuditTrace(
                        authorUserId: nil,
                        createdAt: updatedAt,
                        updatedAt: updatedAt,
                        associatedGroupId: nil,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                let targetColId = templateId.hasPrefix("template_") ? String(templateId.dropFirst(9)) : templateId
                if var detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: targetColId) {
                    var items = detail.items.filter { $0.id != id }
                    items.append(item)
                    items.sort { $0.order < $1.order }
                    try await container.notebookInstrumentsRepository.saveTemplate(template: detail.template_, items: items)
                }

            case "notebook_instrument_response":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let studentId = int64Value(payloadObject["studentId"]),
                    let columnId = payloadObject["columnId"] as? String,
                    let itemId = payloadObject["itemId"] as? String
                else { continue }

                let textValue = payloadObject["valueText"] as? String
                let boolVal = boolValue(payloadObject["valueBool"])
                let numValue = (payloadObject["valueNumber"] as? String) ?? ""

                var responses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(classId: classId, studentId: studentId, columnId: columnId)) ?? []
                responses.removeAll { $0.itemId == itemId }
                responses.append(NotebookInstrumentResponse(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    itemId: itemId,
                    textValue: textValue ?? "",
                    boolValue: boolVal.map { KotlinBoolean(value: $0) },
                    numberValue: numValue.isEmpty ? nil : KotlinDouble(value: Double(numValue) ?? 0.0),
                    trace: AuditTrace(
                        authorUserId: nil,
                        createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs),
                        updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs),
                        associatedGroupId: nil,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                ))
                _ = try await container.notebookInstrumentsRepository.saveResponses(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    responses: responses,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
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

            case "learning_situation":
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSituation(
                    situation: LearningSituation(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        title: payloadObject["title"] as? String ?? "Situación",
                        stageLabel: payloadObject["stageLabel"] as? String ?? "",
                        courseLabel: payloadObject["courseLabel"] as? String ?? "",
                        subjectLabel: payloadObject["subjectLabel"] as? String ?? "",
                        termLabel: payloadObject["termLabel"] as? String ?? "",
                        centerLabel: payloadObject["centerLabel"] as? String ?? "",
                        sessionCount: Int32(int64Value(payloadObject["sessionCount"]) ?? 0),
                        challenge: payloadObject["challenge"] as? String ?? "",
                        finalProduct: payloadObject["finalProduct"] as? String ?? "",
                        payloadJson: payloadObject["payloadJson"] as? String ?? "{}",
                        status: (payloadObject["status"] as? String == "DRAFT") ? .draft : .active,
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_version":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let hash = payloadObject["sha256"] as? String else { continue }
                let localPath = await downloadLearningSituationDocumentIfNeeded(sha256: hash)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveVersion(
                    version: LearningSituationVersion(
                        id: 0,
                        learningSituationId: situationId,
                        versionNumber: Int32(int64Value(payloadObject["versionNumber"]) ?? 0),
                        originalFileName: payloadObject["originalFileName"] as? String ?? "\(hash).docx",
                        sha256: hash,
                        localPath: localPath,
                        sizeBytes: int64Value(payloadObject["sizeBytes"]) ?? 0,
                        payloadJson: payloadObject["payloadJson"] as? String ?? "{}",
                        warningsJson: payloadObject["warningsJson"] as? String ?? "[]",
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_sequence_version":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let hash = payloadObject["sha256"] as? String else { continue }
                let localPath = await downloadLearningSituationDocumentIfNeeded(sha256: hash)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSessionSequenceVersion(
                    version: LearningSituationSessionSequenceVersion(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        learningSituationId: situationId,
                        versionNumber: Int32(int64Value(payloadObject["versionNumber"]) ?? 0),
                        originalFileName: payloadObject["originalFileName"] as? String ?? "\(hash).docx",
                        sha256: hash,
                        localPath: localPath,
                        sizeBytes: int64Value(payloadObject["sizeBytes"]) ?? 0,
                        payloadJson: payloadObject["payloadJson"] as? String ?? "{}",
                        warningsJson: payloadObject["warningsJson"] as? String ?? "[]",
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_session_plan":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let sequenceVersionId = int64Value(payloadObject["sequenceVersionId"]),
                      let title = payloadObject["title"] as? String else { continue }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSessionPlan(
                    plan: LearningSituationSessionPlan(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        learningSituationId: situationId,
                        sequenceVersionId: sequenceVersionId,
                        sessionNumber: Int32(int64Value(payloadObject["sessionNumber"]) ?? 0),
                        sourceLabel: payloadObject["sourceLabel"] as? String ?? "",
                        title: title,
                        sessionType: payloadObject["sessionType"] as? String ?? "",
                        effectiveMinutes: Int32(int64Value(payloadObject["effectiveMinutes"]) ?? 0),
                        objective: payloadObject["objective"] as? String ?? "",
                        criteriaJson: payloadObject["criteriaJson"] as? String ?? "[]",
                        material: payloadObject["material"] as? String ?? "",
                        developmentJson: payloadObject["developmentJson"] as? String ?? "[]",
                        adaptationsJson: payloadObject["adaptationsJson"] as? String ?? "[]",
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_class_link":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let classId = int64Value(payloadObject["classId"]) else { continue }
                let current = try await container.learningSituationsRepository.listClassLinks(learningSituationId: situationId)
                let classIds = Set(current.map(\.classId) + [classId])
                try await container.learningSituationsRepository.replaceClassLinks(
                    learningSituationId: situationId,
                    classIds: Array(classIds).map { KotlinLong(value: $0) }
                )

            case "learning_situation_link":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let kindName = payloadObject["kind"] as? String,
                      let resourceId = payloadObject["resourceId"] as? String else { continue }
                let kind: LearningSituationResourceKind
                switch kindName {
                case "TEACHING_UNIT": kind = .teachingUnit
                case "PLANNING_SESSION": kind = .planningSession
                case "EVALUATION": kind = .evaluation
                case "RUBRIC": kind = .rubric
                default: kind = .notebookColumn
                }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveLinkedResource(
                    resource: LearningSituationLinkedResource(
                        id: 0,
                        learningSituationId: situationId,
                        kind: kind,
                        resourceId: resourceId,
                        classId: int64Value(payloadObject["classId"]).map { KotlinLong(value: $0) },
                        label: payloadObject["label"] as? String ?? "",
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

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
                    teacherScheduleSlotId: int64Value(payloadObject["teacherScheduleSlotId"]).map { KotlinLong(value: $0) },
                    startTime: payloadObject["startTime"] as? String,
                    endTime: payloadObject["endTime"] as? String,
                    learningSituationSessionPlanId: int64Value(payloadObject["learningSituationSessionPlanId"]).map { KotlinLong(value: $0) },
                    status: status
                )
                do {
                    _ = try await container.plannerRepository.upsertSession(session: session)
                } catch {
                    print("LAN Sync: upsertSession failed for planning_session \(change.id): \(error)")
                    continue
                }

            case "teacher_schedule":
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let schedule = TeacherSchedule(
                    id: int64Value(payloadObject["id"]) ?? 0,
                    ownerUserId: int64Value(payloadObject["ownerUserId"]) ?? 1,
                    academicYearId: int64Value(payloadObject["academicYearId"]) ?? 1,
                    name: payloadObject["name"] as? String ?? "Agenda docente",
                    startDateIso: payloadObject["startDateIso"] as? String ?? "",
                    endDateIso: payloadObject["endDateIso"] as? String ?? "",
                    activeWeekdaysCsv: payloadObject["activeWeekdaysCsv"] as? String ?? "1,2,3,4,5",
                    trace: AuditTrace(
                        authorUserId: kotlinLong(int64Value(payloadObject["authorUserId"])),
                        createdAt: Instant.companion.fromEpochMilliseconds(
                            epochMilliseconds: int64Value(payloadObject["createdAtEpochMs"]) ?? change.updatedAtEpochMs
                        ),
                        updatedAt: updatedAt,
                        associatedGroupId: kotlinLong(int64Value(payloadObject["associatedGroupId"])),
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                _ = try await container.teacherScheduleRepository.saveSchedule(schedule: schedule)

            case "teacher_schedule_slot":
                guard
                    let teacherScheduleId = int64Value(payloadObject["teacherScheduleId"]),
                    let schoolClassId = int64Value(payloadObject["schoolClassId"]),
                    let startTime = payloadObject["startTime"] as? String,
                    let endTime = payloadObject["endTime"] as? String
                else { continue }
                _ = try await container.teacherScheduleRepository.saveScheduleSlot(
                    slot: TeacherScheduleSlot(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        teacherScheduleId: teacherScheduleId,
                        schoolClassId: schoolClassId,
                        subjectLabel: payloadObject["subjectLabel"] as? String ?? "",
                        unitLabel: (payloadObject["unitLabel"] as? String)?.nilIfEmpty,
                        dayOfWeek: Int32(int64Value(payloadObject["dayOfWeek"]) ?? 1),
                        startTime: startTime,
                        endTime: endTime,
                        weeklyTemplateId: kotlinLong(int64Value(payloadObject["weeklyTemplateId"]))
                    )
                )

            case "planner_evaluation_period":
                guard
                    let teacherScheduleId = int64Value(payloadObject["teacherScheduleId"])
                else { continue }
                _ = try await container.teacherScheduleRepository.saveEvaluationPeriod(
                    period: PlannerEvaluationPeriod(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        teacherScheduleId: teacherScheduleId,
                        name: payloadObject["name"] as? String ?? "",
                        startDateIso: payloadObject["startDateIso"] as? String ?? "",
                        endDateIso: payloadObject["endDateIso"] as? String ?? "",
                        sortOrder: Int32(int64Value(payloadObject["sortOrder"]) ?? 0)
                    )
                )

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
                        evaluationId: kotlinLong(evaluationId),
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
            // Si llegamos aquí, el upsert se aplicó (o quedó fuera antes de tiempo por
            // un guard interno). Retirar el tombstone es seguro/idempotente en ambos
            // casos: ya no bloquea futuros upserts legítimos de esta misma entidad.
            try? await container.syncTombstoneRepository.clearTombstone(entity: change.entity, entityId: change.id)
            } catch {
                // No abortar el pull completo por un único cambio defectuoso
                // (p.ej. entidad fuera de orden o payload parcial).
                continue
            }
        }
    }

    private func applyDeletedChange(change: LanSyncChange, payloadObject: [String: Any]) async throws {
        switch change.entity {
        case "academic_year":
            let yearId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if yearId > 0 {
                try? await container.academicYearsRepository.deleteArchivedAcademicYear(academicYearId: yearId)
            }
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
            // Formato "classId|tabId|groupId|studentId" o tombstone "group-member-classId-tabId-groupId-studentId".
            let rawId = change.id.hasPrefix("group-member-")
                ? String(change.id.dropFirst("group-member-".count))
                : change.id
            let idParts: [String] = rawId.contains("|")
                ? rawId.split(separator: "|").map(String.init)
                : rawId.split(separator: "-").map(String.init)
            guard
                let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]) ?? idParts[safe: 0].flatMap(Int64.init),
                let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String) ?? idParts[safe: 1],
                let studentId = int64Value(payloadObject["studentId"]) ?? int64Value(payloadObject["student_id"]) ?? idParts[safe: 3].flatMap(Int64.init)
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
        case "notebook_instrument_template":
            let templateId = (payloadObject["id"] as? String) ?? change.id
            let columnId = templateId.hasPrefix("template_") ? String(templateId.dropFirst(9)) : templateId
            if var detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId) {
                try await container.notebookInstrumentsRepository.saveTemplate(template: detail.template_, items: [])
            }
        case "notebook_instrument_response":
            if let classId = int64Value(payloadObject["classId"]),
               let studentId = int64Value(payloadObject["studentId"]),
               let columnId = payloadObject["columnId"] as? String,
               let itemId = payloadObject["itemId"] as? String {
                var responses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(classId: classId, studentId: studentId, columnId: columnId)) ?? []
                responses.removeAll { $0.itemId == itemId }
                _ = try await container.notebookInstrumentsRepository.saveResponses(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    responses: responses,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
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
        case "planning_session":
            let sessionId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if sessionId > 0 {
                try await container.plannerRepository.deleteSession(sessionId: sessionId)
            }
        case "teaching_unit":
            let unitId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if unitId > 0 {
                _ = try await container.plannerRepository.deleteTeachingUnit(unitId: unitId)
            }
        case "teacher_schedule_slot":
            let slotId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if slotId > 0 {
                try await container.teacherScheduleRepository.deleteScheduleSlot(slotId: slotId)
            }
        case "planner_evaluation_period":
            let periodId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if periodId > 0 {
                try await container.teacherScheduleRepository.deleteEvaluationPeriod(periodId: periodId)
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

        let tabsById = Dictionary(
            existingTabs.map { ($0.id.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
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
        case "academic_year":
            return 0
        case "class", "student", "rubric_bundle", "teaching_unit", "calendar_event", "teacher_schedule", "learning_situation":
            return 1
        case "evaluation", "weekly_slot", "teacher_schedule_slot", "planner_evaluation_period", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_group", "notebook_group_member", "learning_situation_version", "learning_situation_class_link", "learning_situation_link", "notebook_instrument_template":
            return 2
        case "class_roster", "attendance", "incident", "notebook_instrument_item":
            return 3
        case "grade", "notebook_cell", "rubric_assessment", "planning_session", "notebook_instrument_response":
            return 4
        case "student_deleted":
            return 5
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
                if let display = persisted.displayValue, !display.isEmpty {
                    index.displayByKey[key] = display
                }
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
        return index.textDraftByKey[key] ?? index.textByKey[key] ?? ""
    }

    func structuredCellDisplayText(studentId: Int64, columnId: String) -> String {
        guard let index = notebookCellValueIndex() else { return "" }
        let key = cellKey(studentId: studentId, columnId: columnId)
        return index.displayByKey[key] ?? index.textByKey[key] ?? ""
    }
    
    func numericGradeText(studentId: Int64, columnId: String) -> String {
        guard let index = notebookCellValueIndex() else { return "" }
        let key = cellKey(studentId: studentId, columnId: columnId)
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

    private func positiveInt64Value(_ raw: Any?) -> Int64? {
        int64Value(raw).flatMap { $0 > 0 ? $0 : nil }
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

    private func studentSex(from raw: Any?) -> StudentSex {
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

    private func studentSexSource(from raw: Any?) -> StudentSexSource {
        let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch value {
        case "MANUAL":
            return .manual
        case "AI_INFERRED", "AIINFERRED", "IA":
            return .aiInferred
        case "IMPORTED":
            return .imported
        default:
            return .unknown
        }
    }

    private func localDate(from raw: Any?) -> LocalDate? {
        guard let value = raw as? String else { return nil }
        let parts = value.split(separator: "-").compactMap { Int32($0) }
        guard parts.count == 3 else { return nil }
        return LocalDate(year: parts[0], monthNumber: parts[1], dayOfMonth: parts[2])
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
        case "STRUCTURED_CHECKLIST": return .structuredChecklist
        case "STRUCTURED_OBSERVATION": return .structuredObservation
        case "STRUCTURED_FORM": return .structuredForm
        case "STRUCTURED_QUIZ": return .structuredQuiz
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

    private func notebookInstrumentTemplateKind(_ raw: String?) -> NotebookInstrumentTemplateKind {
        switch raw?.uppercased() {
        case "CHECKLIST": return .checklist
        case "OBSERVATION": return .observation
        case "QUIZ": return .quiz
        default: return .form
        }
    }

    private func notebookInstrumentItemType(_ raw: String?) -> NotebookInstrumentItemType {
        switch raw?.uppercased() {
        case "CHECK": return .check
        case "CHOICE": return .choice
        case "NUMBER": return .number
        case "TEXT": return .text
        default: return .scale14
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
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        pendingChangesPersistenceTask?.cancel()
        pendingChangesPersistenceTask = nil
        syncEventListener.stop()
        syncSecureStore.delete(key: "sync.token")
        syncSecureStore.delete(key: "sync.host")
        syncSecureStore.delete(key: "sync.server.id")
        syncSecureStore.delete(key: "sync.server.fingerprint")
        // El cursor pertenece al servidor con el que estábamos emparejados; un Mac
        // distinto tiene su propio reloj/epoch y no debe heredar este valor.
        // (Los cambios pendientes de envío SÍ se conservan: son ediciones locales
        // reales aún no sincronizadas y deben llegar al próximo dispositivo emparejado.)
        lastSyncCursorEpochMs = 0
        UserDefaults.standard.removeObject(forKey: "sync.last.cursor")
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
            publishSyncState {
                $0.syncStatusMessage = "Host actualizado automáticamente: \(matched.host)"
            }
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
            startSyncEventListenerIfPaired()
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
        guard pairedSyncHost != nil, syncToken != nil else {
            autoSyncLoopTask?.cancel()
            autoSyncLoopTask = nil
            return
        }
        if let autoSyncLoopTask, !autoSyncLoopTask.isCancelled {
            return
        }
        autoSyncLoopTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.autoSyncLoopTask?.isCancelled ?? true {
                        self.autoSyncLoopTask = nil
                    }
                }
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.nextAutoSyncIntervalNanoseconds())
                    guard self.pairedSyncHost != nil, self.syncToken != nil else { continue }
                    guard !AppleBackupService.shared.needsRestart else { continue }
                    #if os(macOS)
                    await self.checkLocalDbFileModification()
                    #endif
                    await self.syncNow(reason: "periodic", forceFullPull: false, silent: true)
                } catch {
                    // Evitamos romper el bucle por errores transitorios de red.
                }
            }
        }
    }

    private func restartAutoSyncLoopIfPaired() {
        guard pairedSyncHost != nil, syncToken != nil else {
            autoSyncLoopTask?.cancel()
            autoSyncLoopTask = nil
            localChangesNotifyTask?.cancel()
            localChangesNotifyTask = nil
            pendingLocalSseChanges.removeAll()
            syncEventListener.stop()
            return
        }
        startAutoSyncLoop()
        startSyncEventListenerIfPaired()
    }

    private func startSyncEventListenerIfPaired() {
        guard let host = pairedSyncHost, let token = syncToken else {
            syncEventListener.stop()
            return
        }
        syncEventListener.start(
            host: host,
            token: token,
            pinnedFingerprint: pairedServerFingerprint
        ) { [weak self] event in
            guard let self else { return }
            guard let event else {
                await self.syncNow(reason: "sse_event", forceFullPull: false, silent: true)
                return
            }
            await self.applySyncEvent(event)
        }
    }

    // MARK: - Helper lifecycle notifications (macOS only)

    /// Called by MacCommandCenterCoordinator (via Notification) when the helper process
    /// has published a valid LAN IP address. At that point it is safe to start the
    /// event listener and trigger an initial sync.
    func notifyHelperReady(host: String, port: Int) {
        #if os(macOS)
        let normalizedHost = LanSyncClient.normalizeHost(host)
        guard !normalizedHost.isEmpty else { return }
        print("[Sync] helper ready at \(normalizedHost):\(port) — starting listener")
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = nil
        pendingLocalSseChanges.removeAll()
        syncNeedsAnotherPass = false
        syncEventListener.stop()
        pairedSyncHost = normalizedHost
        startSyncEventListenerIfPaired()
        startAutoSyncLoop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "helper_ready", forceFullPull: true, silent: true)
        }
        #endif
    }

    /// Called by MacCommandCenterCoordinator (via Notification) when the helper process
    /// has stopped. Stops the event listener and periodic sync loop without clearing
    /// the paired state, so the UI remains accurate.
    func notifyHelperStopped() {
        #if os(macOS)
        print("[Sync] helper stopped — suspending listener")
        syncEventListener.stop()
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = nil
        pendingLocalSseChanges.removeAll()
        syncNeedsAnotherPass = false
        pairedSyncHost = nil
        #endif
    }

    /// Detiene todo el trabajo en segundo plano que pueda tocar la base de
    /// datos: el bucle de auto-sync, los debounces de guardado (cambios
    /// locales, notas del cuaderno, snapshot de calificaciones) y el
    /// listener de eventos de sync. Se llama antes de cualquier operación
    /// que borre o sustituya los ficheros de la base de datos en disco
    /// (p.ej. el borrado nuclear de Ajustes → Zona de Riesgo): sin esto,
    /// una tarea en curso puede intentar leer/escribir un fichero que
    /// acaba de desaparecer y lanzar una excepción Kotlin que no está
    /// declarada `@Throws` en el contrato, y el runtime de Kotlin/Native
    /// la trata como fatal (aborta el proceso) en vez de propagarla como
    /// error de Swift capturable.
    func stopBackgroundSyncWork() {
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = nil
        pendingChangesPersistenceTask?.cancel()
        pendingChangesPersistenceTask = nil
        notebookSnapshotDebounceTask?.cancel()
        notebookSnapshotDebounceTask = nil
        pendingGradeSnapshotTask?.cancel()
        pendingGradeSnapshotTask = nil
        postSyncRefreshTask?.cancel()
        postSyncRefreshTask = nil
        syncEventListener.stop()
    }

    /// Vacía todas las tablas de la base con la conexión que ya está abierta.
    ///
    /// Existe para que el borrado total (`SettingsDangerZoneView`) deje de eliminar el
    /// fichero SQLite del disco por debajo del driver: eso invalidaba los descriptores
    /// del pool y abortaba el proceso. El contenedor es privado, así que la vista no
    /// puede llegar a él sin abrir un driver nuevo por su cuenta.
    func wipeAllDatabaseData() throws {
        try container.wipeAllData()
    }

    func wipeSelectiveDatabaseData(categories: Set<WipeCategory>) throws {
        try container.wipeSelectiveData(categories: categories)
    }

    /// Ruta de la base de datos activa. Se pide al bootstrap, que a su vez la pide al
    /// módulo que abre el driver: es la única fuente de verdad. Reconstruirla a mano aquí
    /// ya produjo dos rutas divergentes (macOS apuntaba a un fichero fantasma, e iOS a
    /// "MiGestor/" cuando su directorio real es "MiGestorKMPiOS/").
    private func getDatabaseURL() -> URL? {
        URL(fileURLWithPath: appleBootstrap.databasePath)
    }

    private func checkLocalDbFileModification() async {
        guard !AppleBackupService.shared.needsRestart else { return }
        guard let dbURL = getDatabaseURL() else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbURL.path)
            guard let modificationDate = attributes[.modificationDate] as? Date else { return }
            
            let isFirstCheck = lastCheckedDbModificationDate == .distantPast
            if isFirstCheck {
                lastCheckedDbModificationDate = modificationDate
                return
            }
            
            if modificationDate > lastCheckedDbModificationDate {
                let timeSinceLocalMutation = Date().timeIntervalSince(lastLocalMutationAt)
                if timeSinceLocalMutation > 1.5 {
                    await MainActor.run {
                        self.refreshCurrentNotebook()
                        Task(priority: .utility) { [weak self] in
                            guard let self else { return }
                            try? await self.refreshDashboard()
                            try? await self.refreshClasses()
                            try? await self.refreshStudentsDirectory()
                            try? await self.refreshRubrics()
                            try? await self.refreshRubricClassLinks()
                            try? await self.refreshPlanning()
                        }
                    }
                }
                lastCheckedDbModificationDate = modificationDate
            }
        } catch {
            // El archivo no existe o no se puede leer
        }
    }

    private func triggerAutoSyncSoon(delayNanoseconds: UInt64 = 250_000_000) {
        guard pairedSyncHost != nil, syncToken != nil else { return }
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
                await self.syncNow(reason: "debounced_local_change", forceFullPull: false, silent: true)
            } catch {
                self.publishSyncState {
                    $0.syncStatusMessage = "Auto-sync pendiente (reconectando...)"
                }
            }
        }
    }

    func onAppDidBecomeActive() {
        isAppInForeground = true
        startSyncEventListenerIfPaired()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "foreground", forceFullPull: true, silent: true)
        }
    }

    func onAppDidEnterBackground() {
        isAppInForeground = false
        autoSyncDebounceTask?.cancel()
        // Cerrar la ventana justo después de "Borrar todos los datos" dispara
        // esta transición de scenePhase (macOS pasa a `.background` al perder
        // el último foco), y sin este guard se lanzaba un `Task` nuevo que
        // `stopBackgroundSyncWork()` no puede cancelar porque todavía no
        // existe en ese momento — mismo crash que la propia siembra de
        // fondo: `syncNow` toca repositorios Kotlin no declarados `@Throws`
        // sobre un fichero de base de datos que acaba de desaparecer.
        guard !AppleBackupService.shared.needsRestart else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "background_flush", forceFullPull: false, silent: true)
        }
    }

    private func syncNow(reason: String, forceFullPull: Bool, silent: Bool) async {
        // Red de seguridad centralizada: `syncNow` tiene varios puntos de
        // entrada (arranque, primer plano, segundo plano, bucle de
        // auto-sync, listener SSE, helper listo...). Tras un borrado
        // nuclear (`needsRestart == true`) ninguno de ellos debe tocar la
        // base de datos, así que el guard vive aquí en vez de repetirlo en
        // cada llamante.
        guard !AppleBackupService.shared.needsRestart else { return }
        guard pairedSyncHost != nil, syncToken != nil else { return }
        guard !isPairingInFlight else { return }
        let now = Date()
        let latencyCriticalReason = reason == "sse_event" || reason == "debounced_local_change" || reason == "background_flush"

        if silent,
           !forceFullPull,
           !latencyCriticalReason,
           pendingOutboundChanges.isEmpty,
           now.timeIntervalSince(lastSuccessfulSyncAt) < 1.5,
           now.timeIntervalSince(lastSilentSyncAttemptAt) < 1.5 {
            return
        }

        if silent {
            lastSilentSyncAttemptAt = now
        }

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
                    publishSyncState {
                        $0.syncStatusMessage = "Sincronizado (\(reason))"
                    }
                }
            } catch {
                if !silent {
                    let statusMessage = "Sync fallido (\(reason)): \(error.localizedDescription)"
                    publishSyncState {
                        $0.syncStatusMessage = statusMessage
                    }
                } else {
                    publishSyncState {
                        $0.syncStatusMessage = "Auto-sync pendiente (reconectando...)"
                    }
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

    private func runSyncOperationWithTimeout<T>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw NSError(
                    domain: "Sync",
                    code: -206,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Tiempo de espera agotado. Comprueba que la app macOS esté abierta y en la misma red."
                    ]
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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

struct LanSyncEvent: Codable {
    let serverEpochMs: Int64
    let entities: [String]
    let changes: [LanSyncChange]?
}

struct LanPushResult {
    let applied: Int
    let ignored: Int
    let failed: Int
    let serverEpochMs: Int64?
    let desktopAuthoritative: Bool
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
    let ignored: Int?
    let failed: Int?
    let desktopAuthoritative: Bool?
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

    func pull(host: String, token: String, sinceEpochMs: Int64, deviceId: String, pinnedFingerprint: String?) async throws -> LanPullResult {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/pull", queryItems: [
            URLQueryItem(name: "since", value: "\(sinceEpochMs)"),
            URLQueryItem(name: "deviceId", value: deviceId)
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
    ) async throws -> LanPushResult {
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
        let decoded = try JSONDecoder().decode(LanPushResponse.self, from: data)
        return LanPushResult(
            applied: decoded.applied,
            ignored: decoded.ignored ?? 0,
            failed: decoded.failed ?? 0,
            serverEpochMs: decoded.serverEpochMs,
            desktopAuthoritative: decoded.desktopAuthoritative ?? false
        )
    }

    func notifyLocalChanges(
        host: String,
        changes: [LanSyncChange],
        pinnedFingerprint: String?
    ) async throws {
        guard !changes.isEmpty else { return }
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost.isEmpty ? "127.0.0.1" : normalizedHost, path: "/sync/local-changes")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try JSONEncoder().encode(changes)

        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "local-changes",
            host: host
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: -215, userInfo: [
                NSLocalizedDescriptionKey: "Notificación local LAN fallida: \(body)"
            ])
        }
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

    func uploadDocument(host: String, token: String, sha256: String, fileURL: URL, pinnedFingerprint: String?) async throws {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/documents/\(sha256)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.openxmlformats-officedocument.wordprocessingml.document", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: fileURL)
        request.timeoutInterval = 45
        let (_, response) = try await executeDataTask(request: request, pinnedFingerprint: pinnedFingerprint, operation: "document-upload", host: host)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Sync", code: -211, userInfo: [NSLocalizedDescriptionKey: "No se pudo sincronizar el documento de la situación."])
        }
    }

    func downloadDocument(host: String, token: String, sha256: String, pinnedFingerprint: String?) async throws -> Data {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/documents/\(sha256)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        let (data, response) = try await executeDataTask(request: request, pinnedFingerprint: pinnedFingerprint, operation: "document-download", host: host)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Sync", code: -212, userInfo: [NSLocalizedDescriptionKey: "Documento no disponible en el dispositivo emparejado."])
        }
        return data
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
        #if os(macOS)
        components.host = "127.0.0.1"
        #else
        components.host = host
        #endif
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
                ContextualAIAction(actionId: .dailyBriefing, title: "Briefing diario", subtitle: "Qué atender hoy y por qué", systemImage: "sun.max.fill", promptHint: "Prioriza el arranque del día con hechos y acciones docentes."),
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
                    ContextualAIAction(actionId: .studentRiskRadar, title: "Radar de riesgo", subtitle: "Clasificación prudente y explicable", systemImage: "shield.lefthalf.filled.badge.exclamationmark", promptHint: "Explica el nivel de atención del alumno con hechos verificables."),
                    ContextualAIAction(actionId: .familyComment, title: "Comentario para familia", subtitle: "Versión clara y respetuosa", systemImage: "person.2.badge.gearshape.fill", promptHint: "Redacta un comentario claro para familia."),
                    ContextualAIAction(actionId: .tutoringDraft, title: "Borrador de tutoría", subtitle: "Texto base con siguiente acción", systemImage: "person.crop.rectangle.stack.fill", promptHint: "Prepara un borrador prudente para tutoría o seguimiento."),
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
                ContextualAIAction(actionId: .nextSteps, title: "Próximos pasos", subtitle: "Acciones sugeridas para la siguiente sesión", systemImage: "arrowshape.right.fill", promptHint: "Propón próximos pasos realistas y prudentes."),
                ContextualAIAction(actionId: .sessionClosure, title: "Cierre de sesión", subtitle: "Qué pasó y qué ajustar después", systemImage: "flag.checkered.2.crossed", promptHint: "Cierra la sesión con hechos, aprendizaje y siguiente paso.")
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
                ContextualAIAction(actionId: .progressReadout, title: "Lectura de progreso", subtitle: "Explica el avance del grupo", systemImage: "chart.line.uptrend.xyaxis", promptHint: "Explica el estado de progreso del grupo con prudencia."),
                ContextualAIAction(actionId: .groupInsight, title: "Inspector analítico", subtitle: "Patrones del grupo apoyados en evidencia", systemImage: "chart.xyaxis.line", promptHint: "Resume patrones del grupo a partir de paneles analíticos y hechos verificables.")
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
                ContextualAIAction(actionId: .familyComment, title: "Versión para familia", subtitle: "Lenguaje más claro y cercano", systemImage: "person.2.badge.gearshape.fill", promptHint: "Reescribe el resumen con lenguaje para familia."),
                ContextualAIAction(actionId: .tutoringDraft, title: "Borrador de tutoría", subtitle: "Modo interno, tutoría o familia", systemImage: "text.document.fill", promptHint: "Prepara un borrador prudente con siguiente acción sugerida.")
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

    func getAITrendsAndMetrics(classId: Int64, studentId: Int64?) async throws -> AITrendsSnapshot {
        let kotlinSnapshot = try await container.getAITrendsAndMetrics.invoke(
            classId: classId,
            studentId: studentId.map { KotlinLong(value: $0) }
        )
        return AITrendsSnapshot(
            trendDirection: kotlinSnapshot.trendDirection,
            averageGradeDelta: kotlinSnapshot.averageGradeDelta,
            attendanceCorrelationNote: kotlinSnapshot.attendanceCorrelationNote,
            behaviorIncidentSummary: kotlinSnapshot.behaviorIncidentSummary,
            curriculumCoveragePct: kotlinSnapshot.curriculumCoveragePct,
            missingCompetencyLabels: kotlinSnapshot.missingCompetencyLabels,
            recentGrades: kotlinSnapshot.recentGrades.map { $0.doubleValue },
            attendanceRate: kotlinSnapshot.attendanceRate
        )
    }

    func generateNotebookAICommentContexts(
        includedColumnIds: [String],
        studentIds: [Int64]? = nil
    ) async -> [NotebookAICommentContext] {
        guard let data = notebookState as? NotebookUiStateData,
              let classId = notebookViewModel.currentClassId?.int64Value,
              let schoolClass = classes.first(where: { $0.id == classId })
        else { return [] }

        let selectedColumns = data.sheet.columns.filter { includedColumnIds.contains($0.id) }
        let columnCategoryNames = Dictionary(
            data.sheet.columnCategories.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let filteredRows = data.sheet.rows.filter { row in
            guard let studentIds else { return true }
            return studentIds.contains(row.student.id)
        }

        var contexts: [NotebookAICommentContext] = []
        for row in filteredRows {
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
            let trends = try? await getAITrendsAndMetrics(classId: classId, studentId: row.student.id)
            
            contexts.append(
                NotebookAICommentContext(
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
                    dataQualityNote: values.isEmpty ? "Hay pocas columnas con dato visible para este alumno." : nil,
                    trends: trends
                )
            )
        }
        return contexts
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
            emptyCellPolicy: .excludeFromAverage,
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

    func createNotebookAICommentColumnForClass(
        classId: Int64,
        name: String,
        categoryKind: NotebookColumnCategoryKind = .followUp
    ) async throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw NSError(domain: "KmpBridge", code: 422, userInfo: [NSLocalizedDescriptionKey: "El nombre de la columna no puede estar vacío."])
        }
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
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let tabIds = selectedNotebookTabId.map { [$0] } ?? tabs.first.map { [$0.id] } ?? []
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
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "3D7DFF",
            iconName: "apple.intelligence",
            order: -1,
            widthDp: 260,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: false,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        return columnId
    }

    func saveNotebookAICommentDirect(
        classId: Int64,
        studentId: Int64,
        columnId: String,
        text: String
    ) async throws {
        try await container.notebookRepository.saveCell(
            classId: classId,
            studentId: studentId,
            columnId: columnId,
            textValue: text,
            boolValue: nil,
            iconValue: nil,
            ordinalValue: nil,
            note: nil,
            colorHex: nil,
            attachmentUris: [],
            authorUserId: nil,
            associatedGroupId: nil
        )
    }

    func notebookTextCell(classId: Int64, studentId: Int64, columnId: String) async throws -> String {
        let cells = try await container.notebookCellsRepository.listClassCells(classId: classId)
        return cells.first { $0.studentId == studentId && $0.columnId == columnId }?.textValue ?? ""
    }

    func recordAIAuditEvent(
        service: String,
        useCase: String,
        reportKind: String? = nil,
        classId: Int64? = nil,
        studentId: Int64? = nil,
        availability: String,
        modelAvailable: Bool,
        success: Bool,
        durationMs: Int64,
        errorKind: String? = nil,
        errorMessage: String? = nil
    ) async {
        let createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        let studentHash = studentId.map { anonymizedStudentHash($0) }
        let event = AIAuditEvent(
            id: 0,
            createdAtEpochMs: createdAt,
            service: service,
            useCase: useCase,
            reportKind: reportKind,
            classId: classId.map { KotlinLong(value: $0) },
            studentHash: studentHash,
            availability: availability,
            modelAvailable: modelAvailable,
            success: success,
            durationMs: durationMs,
            errorKind: errorKind,
            errorMessage: errorMessage
        )
        try? await container.aiAuditRepository.recordEvent(event: event)
    }

    func aiAuditTotalsByUseCase() async throws -> [AIAuditUseCaseTotal] {
        try await container.aiAuditRepository.totalsByUseCase()
    }

    func recentAIAuditFailures(limit: Int64 = 20) async throws -> [AIAuditEvent] {
        try await container.aiAuditRepository.recentFailures(limit: limit)
    }

    private func anonymizedStudentHash(_ studentId: Int64) -> String {
        let payload = "\(localDeviceId)|\(studentId)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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

        // Semana escolar: empieza en lunes, y las filas son semanas naturales,
        // no ventanas móviles de 7 días contadas desde hoy. Con el reparto
        // anterior, el viernes de una semana y el lunes de la siguiente caían
        // en la misma fila, que es justo el eje que da sentido al gráfico.
        let calendar = Calendar.current

        // Lunes de la semana de `date`, calculado a mano a partir del día de la
        // semana. Deliberadamente NO se usa `dateInterval(of: .weekOfYear:)`:
        // depende de `firstWeekday` y de la configuración regional, y su rama de
        // fallo obliga a un fallback que, si se activa, convierte las filas en
        // días sueltos y deja la rejilla entera a cero sin avisar.
        func startOfWeek(for date: Date) -> Date {
            let day = calendar.startOfDay(for: date)
            // `weekday`: 1 = domingo … 7 = sábado. Lunes -> 0, domingo -> 6.
            let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
            return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
        }

        // Días en el orden lectivo L→D. `Calendar.component(.weekday)` devuelve
        // 1 = domingo … 7 = sábado; el bucle anterior iteraba 2...8, así que la
        // columna del domingo nunca podía recibir nada y el propio domingo no
        // se contaba en ninguna columna.
        let weekdayColumns: [(symbol: String, weekday: Int)] = [
            ("L", 2), ("M", 3), ("X", 4), ("J", 5), ("V", 6), ("S", 7), ("D", 1)
        ]

        let weeksBack = max(2, min(6, timeRange.dayCount / 14 + 1))
        let currentWeekStart = startOfWeek(for: Date())
        let oldestWeekStart = calendar.date(byAdding: .weekOfYear, value: -(weeksBack - 1), to: currentWeekStart) ?? currentWeekStart

        // El recorte es el inicio de la semana más antigua que se pinta, no
        // `timeRange.dayCount` días naturales: así el total y el pico describen
        // exactamente lo que se ve en la rejilla y no un periodo más ancho.
        let filtered = incidents.filter {
            Date(timeIntervalSince1970: TimeInterval($0.date.epochSeconds)) >= oldestWeekStart
        }

        let weekLabelFormatter = DateFormatter()
        weekLabelFormatter.locale = Locale(identifier: "es_ES")
        weekLabelFormatter.setLocalizedDateFormatFromTemplate("d/M")

        // De la semana más antigua a la más reciente, para que la rejilla se lea
        // de arriba abajo en orden cronológico. Las etiquetas son la fecha del
        // lunes de cada semana: `S-1`…`S-6` se leía al revés de lo que sugiere.
        var cells: [HeatmapCell] = []
        for offset in stride(from: weeksBack - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) else { continue }
            let weekLabel = weekLabelFormatter.string(from: weekStart)
            for column in weekdayColumns {
                let count = filtered.filter { incident in
                    let date = Date(timeIntervalSince1970: TimeInterval(incident.date.epochSeconds))
                    // Comparación por día, no por `Date` exacta: los cambios de
                    // hora dejan medianoches que no son iguales al segundo.
                    return calendar.isDate(startOfWeek(for: date), inSameDayAs: weekStart)
                        && calendar.component(.weekday, from: date) == column.weekday
                }.count
                cells.append(
                    HeatmapCell(
                        rowLabel: weekLabel,
                        columnLabel: column.symbol,
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
                maxCell.map { "Mayor concentración: semana del \($0.rowLabel), \($0.columnLabel), con \(Int($0.value)) incidencias." }
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

final class PinnedTLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pinnedFingerprint: String?

    init(pinnedFingerprint: String?) {
        self.pinnedFingerprint = pinnedFingerprint?.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificateChain.first else {
            completionHandler(.performDefaultHandling, nil)
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
}
