//
//  KmpBridgeModels.swift
//  MiGestorKMP
//
//  Created for modularization of KmpBridge.
//

import Foundation
import MiGestorKit
import SwiftUI

extension KmpBridge {
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

}
