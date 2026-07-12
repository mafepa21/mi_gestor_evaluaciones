package com.migestor.shared.domain

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

data class AuditTrace(
    val authorUserId: Long? = null,
    val createdAt: Instant = Clock.System.now(),
    val updatedAt: Instant = Clock.System.now(),
    val associatedGroupId: Long? = null,
    val deviceId: String? = null,
    val syncVersion: Long = 0,
)

enum class UserRole {
    DOCENTE,
    ALUMNO,
    FAMILIA,
    ADMIN,
}

data class SchoolCenter(
    val id: Long,
    val code: String,
    val name: String,
    val trace: AuditTrace = AuditTrace(),
)

data class AcademicYear(
    val id: Long,
    val centerId: Long,
    val name: String,
    val startAt: Instant,
    val endAt: Instant,
    val status: AcademicYearStatus = AcademicYearStatus.ACTIVE,
    val isActive: Boolean = false,
    val archivedAt: Instant? = null,
    val trace: AuditTrace = AuditTrace(),
)

enum class AcademicYearStatus {
    ACTIVE,
    ARCHIVED,
    TRASHED,
}

data class StudentEnrollment(
    val id: Long,
    val studentId: Long,
    val classId: Long,
    val academicYearId: Long,
    val status: EnrollmentStatus = EnrollmentStatus.ACTIVE,
    val promotionStatus: PromotionStatus = PromotionStatus.PENDING,
    val previousEnrollmentId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

enum class EnrollmentStatus {
    ACTIVE,
    TRANSFERRED,
    WITHDRAWN,
    ARCHIVED,
}

enum class PromotionStatus {
    PROMOTED,
    REPEATING,
    GROUP_CHANGED,
    LEFT_SCHOOL,
    PENDING,
}

data class StageCycle(
    val id: Long,
    val centerId: Long,
    val name: String,
    val level: String? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class Subject(
    val id: Long,
    val code: String,
    val name: String,
    val stageCycleId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class AppUser(
    val id: Long,
    val externalId: String? = null,
    val displayName: String,
    val email: String? = null,
    val role: UserRole,
    val centerId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class Student(
    val id: Long,
    val firstName: String,
    val lastName: String,
    val email: String? = null,
    val photoPath: String? = null,
    val isInjured: Boolean = false,
    val sex: StudentSex = StudentSex.UNSPECIFIED,
    val sexSource: StudentSexSource = StudentSexSource.UNKNOWN,
    val birthDate: LocalDate? = null,
    val trace: AuditTrace = AuditTrace(),
) {
    val fullName: String get() = listOf(firstName, lastName).joinToString(" ").trim()

    fun ageOn(date: LocalDate): Int? {
        val born = birthDate ?: return null
        var age = date.year - born.year
        if (date.monthNumber < born.monthNumber ||
            (date.monthNumber == born.monthNumber && date.dayOfMonth < born.dayOfMonth)
        ) {
            age -= 1
        }
        return age.takeIf { it >= 0 }
    }
}

enum class StudentSex {
    MALE,
    FEMALE,
    UNSPECIFIED,
}

enum class StudentSexSource {
    MANUAL,
    AI_INFERRED,
    IMPORTED,
    UNKNOWN,
}

fun normalizedStudentSex(value: String?): StudentSex {
    val normalized = value
        ?.trim()
        ?.lowercase()
        ?.replace("é", "e")
        ?.replace("á", "a")
        ?: return StudentSex.UNSPECIFIED
    return when (normalized) {
        "male", "m", "h", "hombre", "masculino", "chico", "boy" -> StudentSex.MALE
        "female", "f", "mujer", "femenino", "chica", "girl" -> StudentSex.FEMALE
        else -> StudentSex.UNSPECIFIED
    }
}

data class SchoolClass(
    val id: Long,
    val name: String,
    val course: Int,
    val description: String? = null,
    val centerId: Long? = null,
    val academicYearId: Long? = null,
    val stageCycleId: Long? = null,
    val subjectId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class Period(
    val id: Long,
    val name: String,
    val startAt: Instant,
    val endAt: Instant,
    val trace: AuditTrace = AuditTrace(),
)

data class UnitPlan(
    val id: Long,
    val periodId: Long,
    val title: String,
    val objectives: String,
    val competences: String,
    val trace: AuditTrace = AuditTrace(),
)

data class SessionPlan(
    val id: Long,
    val unitId: Long,
    val date: Instant,
    val description: String,
    val trace: AuditTrace = AuditTrace(),
)

data class PlanPeriod(
    val period: Period,
    val units: List<PlanUnit>,
)

data class PlanUnit(
    val unit: UnitPlan,
    val sessions: List<SessionPlan>,
)

data class Rubric(
    val id: Long,
    val name: String,
    val description: String? = null,
    val classId: Long? = null,
    val teachingUnitId: Long? = null,
    val competencyId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class RubricCriterion(
    val id: Long,
    val rubricId: Long,
    val description: String,
    val weight: Double,
    val order: Int,
    val competencyId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class RubricLevel(
    val id: Long,
    val criterionId: Long,
    val name: String,
    val points: Int,
    val description: String? = null,
    val order: Int,
    val trace: AuditTrace = AuditTrace(),
)

data class RubricCriterionWithLevels(
    val criterion: RubricCriterion,
    val levels: List<RubricLevel>,
)

data class RubricDetail(
    val rubric: Rubric,
    val criteria: List<RubricCriterionWithLevels>,
) {
    /**
     * Calculates the total score (0-10) based on selected level IDs for each criterion.
     * Only evaluated criteria contribute to the denominator, so partial in-progress
     * rubric evaluations can still reach 10.0 over the criteria already assessed.
     */
    fun calculateScore(selectedLevelIds: Map<Long, Long>): Double {
        if (criteria.isEmpty()) return 0.0

        var totalWeightedPercentage = 0.0
        var totalWeightUsed = 0.0

        for (criterionWithLevels in criteria) {
            val selectedLevelId = selectedLevelIds[criterionWithLevels.criterion.id]
            val selectedLevel = criterionWithLevels.levels.find { it.id == selectedLevelId }

            if (selectedLevel != null) {
                // Use level points if provided (> 0), otherwise use its order/position
                val points = if (selectedLevel.points > 0) selectedLevel.points.toDouble() else selectedLevel.order.toDouble()
                
                // Max points for this criterion is the maximum points/order across all its levels
                val maxPossiblePoints = criterionWithLevels.levels.maxOf { 
                    if (it.points > 0) it.points.toDouble() else it.order.toDouble() 
                }.coerceAtLeast(1.0)
                
                val criterionWeight = criterionWithLevels.criterion.weight
                    .takeIf { it > 0.0 } ?: 1.0
                val criterionPercentage = (points / maxPossiblePoints).coerceIn(0.0, 1.0)
                totalWeightedPercentage += criterionPercentage * criterionWeight
                totalWeightUsed += criterionWeight
            }
        }

        if (totalWeightUsed == 0.0) return 0.0

        // Return score scaled to 10.0, rounded to 2 decimal places for storage safety
        val rawScore = (totalWeightedPercentage / totalWeightUsed) * 10.0
        return kotlin.math.round(rawScore * 100.0) / 100.0
    }
}

data class RubricAssessment(
    val studentId: Long,
    val evaluationId: Long,
    val criterionId: Long,
    val levelId: Long,
    val trace: AuditTrace = AuditTrace(),
)

data class Evaluation(
    val id: Long,
    val classId: Long,
    val code: String,
    val name: String,
    val type: String,
    val weight: Double = 1.0,
    val formula: String? = null,
    val rubricId: Long? = null,
    val description: String? = null,
    val competencyLinks: List<EvaluationCompetencyLink> = emptyList(),
    val trace: AuditTrace = AuditTrace(),
)

data class Grade(
    val id: Long,
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val evaluationId: Long?,
    val value: Double?,
    val evidence: String? = null,
    val evidencePath: String? = null,
    val rubricSelections: String? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class PhysicalTestDefinition(
    val id: String,
    val name: String,
    val capacity: PhysicalCapacity,
    val measurementKind: PhysicalMeasurementKind,
    val unit: String,
    val higherIsBetter: Boolean,
    val protocol: String = "",
    val material: String = "",
    val attempts: Int = 1,
    val resultMode: PhysicalResultMode = PhysicalResultMode.BEST,
    val trace: AuditTrace = AuditTrace(),
)

enum class PhysicalCapacity {
    RESISTANCE,
    STRENGTH,
    SPEED,
    FLEXIBILITY,
    COORDINATION,
    AGILITY,
    CUSTOM,
}

enum class PhysicalMeasurementKind {
    TIME,
    DISTANCE,
    REPETITIONS,
    LEVEL,
    SCORE,
}

enum class PhysicalResultMode {
    BEST,
    AVERAGE,
    LAST,
}

data class PhysicalTestBattery(
    val id: String,
    val name: String,
    val description: String = "",
    val defaultCourse: Int? = null,
    val defaultAgeFrom: Int? = null,
    val defaultAgeTo: Int? = null,
    val testIds: List<String>,
    val trace: AuditTrace = AuditTrace(),
)

data class PhysicalTestAssignment(
    val id: String,
    val batteryId: String,
    val classId: Long,
    val course: Int?,
    val ageFrom: Int?,
    val ageTo: Int?,
    val termLabel: String?,
    val dateEpochMs: Long,
    val rawColumnMode: Boolean = true,
    val scoreColumnMode: Boolean = true,
    val trace: AuditTrace = AuditTrace(),
)

data class PhysicalTestScale(
    val id: String,
    val testId: String,
    val name: String,
    val course: Int? = null,
    val ageFrom: Int? = null,
    val ageTo: Int? = null,
    val sex: String? = null,
    val batteryId: String? = null,
    val direction: PhysicalScaleDirection,
    val ranges: List<PhysicalTestScaleRange>,
    val trace: AuditTrace = AuditTrace(),
)

enum class PhysicalScaleDirection {
    HIGHER_IS_BETTER,
    LOWER_IS_BETTER,
}

data class PhysicalTestScaleRange(
    val id: String,
    val scaleId: String,
    val minValue: Double?,
    val maxValue: Double?,
    val score: Double,
    val label: String? = null,
    val sortOrder: Int = 0,
)

data class PhysicalTestResult(
    val id: String,
    val assignmentId: String,
    val testId: String,
    val classId: Long,
    val studentId: Long,
    val rawValue: Double?,
    val rawText: String,
    val score: Double?,
    val scaleId: String?,
    val observedAtEpochMs: Long,
    val rawColumnId: String?,
    val scoreColumnId: String?,
    val trace: AuditTrace = AuditTrace(),
)

data class PhysicalTestAttempt(
    val id: String,
    val resultId: String,
    val attemptNumber: Int,
    val rawValue: Double?,
    val rawText: String,
)

data class PhysicalTestNotebookLink(
    val assignmentId: String,
    val testId: String,
    val rawColumnId: String?,
    val scoreColumnId: String?,
    val trace: AuditTrace = AuditTrace(),
)

fun PhysicalTestScale.scoreFor(rawValue: Double): Double? {
    if (!rawValue.isFinite()) return null
    val range = ranges
        .sortedBy { it.sortOrder }
        .firstOrNull { range ->
            val minOk = range.minValue?.let { rawValue >= it } ?: true
            val maxOk = range.maxValue?.let { rawValue <= it } ?: true
            minOk && maxOk
        } ?: return null
    return range.score.coerceIn(0.0, 10.0)
}

fun resolvedPhysicalResult(
    attempts: List<Double>,
    direction: PhysicalScaleDirection,
    resultMode: PhysicalResultMode,
): Double? {
    val validAttempts = attempts.filter { it.isFinite() }
    if (validAttempts.isEmpty()) return null
    return when (resultMode) {
        PhysicalResultMode.BEST -> when (direction) {
            PhysicalScaleDirection.HIGHER_IS_BETTER -> validAttempts.maxOrNull()
            PhysicalScaleDirection.LOWER_IS_BETTER -> validAttempts.minOrNull()
        }
        PhysicalResultMode.AVERAGE -> validAttempts.average()
        PhysicalResultMode.LAST -> validAttempts.last()
    }
}

data class CompetencyCriterion(
    val id: Long,
    val code: String,
    val name: String,
    val description: String? = null,
    val stageCycleId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class LearningActivity(
    val id: Long,
    val classId: Long,
    val title: String,
    val description: String? = null,
    val dueAt: Instant? = null,
    val rubricId: Long? = null,
    val competencyIds: List<Long> = emptyList(),
    val trace: AuditTrace = AuditTrace(),
)

data class EvaluationCompetencyLink(
    val id: Long,
    val evaluationId: Long,
    val competencyId: Long,
    val weight: Double = 1.0,
    val trace: AuditTrace = AuditTrace(),
)

data class AIAuditEvent(
    val id: Long = 0,
    val createdAtEpochMs: Long,
    val service: String,
    val useCase: String,
    val reportKind: String? = null,
    val classId: Long? = null,
    val studentHash: String? = null,
    val availability: String,
    val modelAvailable: Boolean,
    val success: Boolean,
    val durationMs: Long = 0,
    val errorKind: String? = null,
    val errorMessage: String? = null,
)

data class AIAuditUseCaseTotal(
    val useCase: String,
    val totalCount: Long,
    val successCount: Long,
    val lastCreatedAtEpochMs: Long,
)

data class AIAuditAvailabilityTotal(
    val availability: String,
    val totalCount: Long,
    val lastCreatedAtEpochMs: Long,
)

data class EvidenceAttachment(
    val id: Long,
    val evaluationId: Long,
    val studentId: Long,
    val kind: String,
    val pathOrUri: String,
    val note: String? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class Attendance(
    val id: Long,
    val studentId: Long,
    val classId: Long,
    val date: Instant,
    val status: String,
    val note: String = "",
    val hasIncident: Boolean = false,
    val followUpRequired: Boolean = false,
    val sessionId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

enum class SupportMeasureLevel { III, IV }

enum class SupportMeasureType {
    REFUERZO,
    ENRIQUECIMIENTO,
    ADAPTACION_ACCESO,
    APOYO_PT,
    APOYO_AL,
    ACIS,
    EXENCION,
    FLEXIBILIZACION,
    PERMANENCIA_EXTRAORDINARIA,
    ESCOLARIZACION_ESPECIFICA,
}

enum class SupportMeasureIntensity { BAJA, MEDIA, ALTA }

data class StudentSupportMeasure(
    val id: Long,
    val studentId: Long,
    val level: SupportMeasureLevel,
    val measureType: SupportMeasureType,
    val startDate: LocalDate,
    val endDate: LocalDate? = null,
    val responsible: String? = null,
    val intensity: SupportMeasureIntensity? = null,
    val followUpNotes: String = "",
    val documentRef: String? = null,
    val reviewDue: LocalDate? = null,
    val isActive: Boolean = true,
    val trace: AuditTrace = AuditTrace(),
)

data class Incident(
    val id: Long,
    val classId: Long,
    val studentId: Long? = null,
    val title: String,
    val detail: String? = null,
    val severity: String = "low",
    val date: Instant,
    val trace: AuditTrace = AuditTrace(),
)

data class CalendarEvent(
    val id: Long,
    val classId: Long? = null,
    val title: String,
    val description: String? = null,
    val startAt: Instant,
    val endAt: Instant,
    val externalProvider: String? = null,
    val externalId: String? = null,
    val trace: AuditTrace = AuditTrace(),
)

enum class ConfigTemplateKind {
    NOTEBOOK_COLUMNS,
    RUBRIC,
    UNIT_TEMPLATE,
    CLASS_STRUCTURE,
}

data class ConfigTemplate(
    val id: Long,
    val centerId: Long? = null,
    val ownerUserId: Long,
    val name: String,
    val kind: ConfigTemplateKind,
    val trace: AuditTrace = AuditTrace(),
)

data class ConfigTemplateVersion(
    val id: Long,
    val templateId: Long,
    val versionNumber: Int,
    val payloadJson: String,
    val basedOnVersionId: Long? = null,
    val sourceAcademicYearId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

enum class LearningSituationStatus {
    DRAFT,
    ACTIVE,
    ARCHIVED,
}

enum class LearningSituationResourceKind {
    TEACHING_UNIT,
    PLANNING_SESSION,
    EVALUATION,
    RUBRIC,
    NOTEBOOK_COLUMN,
}

data class LearningSituation(
    val id: Long = 0,
    val title: String,
    val stageLabel: String = "",
    val courseLabel: String = "",
    val subjectLabel: String = "",
    val termLabel: String = "",
    val centerLabel: String = "",
    val sessionCount: Int = 0,
    val challenge: String = "",
    val finalProduct: String = "",
    val payloadJson: String = "{}",
    val status: LearningSituationStatus = LearningSituationStatus.DRAFT,
    val trace: AuditTrace = AuditTrace(),
)

data class LearningSituationVersion(
    val id: Long = 0,
    val learningSituationId: Long,
    val versionNumber: Int = 1,
    val originalFileName: String,
    val sha256: String,
    val localPath: String? = null,
    val sizeBytes: Long = 0,
    val payloadJson: String = "{}",
    val warningsJson: String = "[]",
    val trace: AuditTrace = AuditTrace(),
)

data class LearningSituationSessionSequenceVersion(
    val id: Long = 0,
    val learningSituationId: Long,
    val versionNumber: Int = 1,
    val originalFileName: String,
    val sha256: String,
    val localPath: String? = null,
    val sizeBytes: Long = 0,
    val payloadJson: String = "{}",
    val warningsJson: String = "[]",
    val trace: AuditTrace = AuditTrace(),
)

data class LearningSituationSessionPlan(
    val id: Long = 0,
    val learningSituationId: Long,
    val sequenceVersionId: Long,
    val sessionNumber: Int,
    val sourceLabel: String = "",
    val title: String,
    val sessionType: String = "",
    val effectiveMinutes: Int = 0,
    val objective: String = "",
    val criteriaJson: String = "[]",
    val material: String = "",
    val developmentJson: String = "[]",
    val adaptationsJson: String = "[]",
    val trace: AuditTrace = AuditTrace(),
)

data class LearningSituationClassLink(
    val learningSituationId: Long,
    val classId: Long,
    val trace: AuditTrace = AuditTrace(),
)

data class LearningSituationEvaluationProposal(
    val id: String,
    val title: String,
    val criterion: String,
    val evidence: String,
    val weight: Double? = null,
)

data class LearningSituationLinkedResource(
    val id: Long = 0,
    val learningSituationId: Long,
    val kind: LearningSituationResourceKind,
    val resourceId: String,
    val classId: Long? = null,
    val label: String = "",
    val trace: AuditTrace = AuditTrace(),
)

data class BackupEntry(
    val id: Long,
    val path: String,
    val createdAt: Instant,
    val platform: String,
    val sizeBytes: Long,
)

data class DashboardStats(
    val totalStudents: Int,
    val totalClasses: Int,
    val totalEvaluations: Int,
    val totalRubrics: Int,
    val totalSessions: Int,
)

enum class DashboardMode {
    CLASSROOM,
    OFFICE,
}

data class DashboardFilters(
    val classId: Long? = null,
    val severity: String? = null,
    val priority: String? = null,
    val sessionStatus: String? = null,
)

data class TodaySessionItem(
    val id: Long,
    val classId: Long?,
    val groupName: String,
    val timeLabel: String,
    val didacticUnit: String,
    val space: String,
    val sessionStatus: String,
)

data class AlertItem(
    val id: String,
    val classId: Long?,
    val studentId: Long? = null,
    val type: String,
    val title: String,
    val detail: String,
    val severity: String,
    val priority: String,
    val count: Int = 1,
)

data class GroupSummary(
    val classId: Long,
    val groupName: String,
    val attendancePct: Int,
    val evaluationCompletedPct: Int,
    val averageScore: Double,
    val studentsInFollowUp: Int,
    val lastNotes: String,
)

data class AgendaNavigationTarget(
    val id: String,
    val navigationKind: String = "none",
    val label: String,
    val studentId: Long? = null,
    val classId: Long? = null,
    val evaluationId: Long? = null,
    val rubricId: Long? = null,
    val columnId: String? = null,
)

data class AgendaItem(
    val id: String,
    val classId: Long?,
    val type: String,
    val title: String,
    val subtitle: String,
    val timeLabel: String,
    val status: String,
    val navigationKind: String = "none",
    val navigationTargets: List<AgendaNavigationTarget> = emptyList(),
)

data class PEOperationalItem(
    val id: String,
    val classId: Long?,
    val type: String,
    val title: String,
    val detail: String,
    val severity: String = "low",
)

data class DashboardSnapshot(
    val generatedAt: Instant = Clock.System.now(),
    val mode: DashboardMode = DashboardMode.OFFICE,
    val filters: DashboardFilters = DashboardFilters(),
    val todayCount: Int = 0,
    val alertsCount: Int = 0,
    val pendingCount: Int = 0,
    val nextSessionLabel: String = "Sin próxima sesión",
    val todaySessions: List<TodaySessionItem> = emptyList(),
    val alerts: List<AlertItem> = emptyList(),
    val quickColumns: List<String> = emptyList(),
    val quickRubrics: List<String> = emptyList(),
    val groupSummaries: List<GroupSummary> = emptyList(),
    val agendaItems: List<AgendaItem> = emptyList(),
    val peItems: List<PEOperationalItem> = emptyList(),
)

enum class QuickActionType {
    PASS_LIST,
    REGISTER_OBSERVATION,
    QUICK_EVALUATION,
}

data class QuickActionCommand(
    val type: QuickActionType,
    val classId: Long,
    val studentId: Long? = null,
    val evaluationId: Long? = null,
    val note: String? = null,
    val attendanceStatus: String? = null,
    val score: Double? = null,
)

data class QuickActionResult(
    val success: Boolean,
    val message: String,
    val updatedAt: Instant = Clock.System.now(),
)

data class NotebookCell(
    val evaluationId: Long,
    val value: Double?,
)

enum class NotebookColumnType {
    NUMERIC,
    TEXT,
    ICON,
    CHECK,
    ORDINAL,
    RUBRIC,
    ATTENDANCE,
    CALCULATED,
}

enum class NotebookColumnCategoryKind {
    EVALUATION,
    FOLLOW_UP,
    ATTENDANCE,
    EXTRAS,
    PHYSICAL_EDUCATION,
    CUSTOM,
}

enum class CellSemanticKind {
    NUMERIC,
    PERCENTAGE,
    DATE,
    ATTENDANCE,
    AVERAGE,
    RUBRIC,
    CHECK,
    TEXT,
    EMPTY,
}

data class CellDisplayValue(
    val text: String,
    val semanticKind: CellSemanticKind,
)

enum class NotebookInstrumentKind {
    WRITTEN_TEST,
    RUBRIC,
    SYSTEMATIC_OBSERVATION,
    CHECKLIST,
    OBSERVATION_SCALE,
    SELF_ASSESSMENT,
    PEER_ASSESSMENT,
    FINAL_PRODUCT,
    PRESENTATION,
    TASK,
    PRACTICE,
    PHYSICAL_TEST,
    LEARNING_SITUATION,
    PARTICIPATION,
    ATTITUDE,
    DAILY_WORK,
    PROGRESS,
    MATERIAL,
    BEHAVIOUR,
    INCIDENT,
    ADAPTATION,
    REINFORCEMENT,
    RECOVERY,
    BONUS,
    PENALTY,
    FREE_OBSERVATION,
    ATTACHMENT,
    MULTIMEDIA_EVIDENCE,
    PRIVATE_COMMENT,
    FAMILY_COMMUNICATION,
    CUSTOM,
}

enum class NotebookCellInputKind {
    NUMERIC_0_10,
    NUMERIC_1_4,
    PERCENTAGE,
    TIME,
    REPETITIONS,
    DISTANCE,
    EXCELLENT_GOOD_PROGRESS,
    YES_NO,
    ACHIEVED_PARTIAL_NOT_ACHIEVED,
    LETTER_ABCD,
    QUICK_SELECTOR,
    RUBRIC,
    CHECK,
    SHORT_NOTE,
    EVIDENCE,
    ATTENDANCE_STATUS,
    CALCULATED,
    STRUCTURED_CHECKLIST,
    STRUCTURED_OBSERVATION,
    STRUCTURED_FORM,
    STRUCTURED_QUIZ,
    TEXT,
}

enum class NotebookScaleKind {
    TEN_POINT,
    FOUR_LEVEL,
    PERCENTAGE,
    TIME,
    DISTANCE,
    REPETITIONS,
    LETTER_ABCD,
    ACHIEVEMENT,
    YES_NO,
    CUSTOM,
}

private val rawPhysicalScaleKinds = setOf(
    NotebookScaleKind.TIME,
    NotebookScaleKind.DISTANCE,
    NotebookScaleKind.REPETITIONS,
)

private fun String?.isPhysicalRawDataLabel(): Boolean {
    val normalized = this
        ?.trim()
        ?.lowercase()
        ?.replace("á", "a")
        ?.replace("é", "e")
        ?: return false
    return normalized.startsWith("dato bruto") ||
        normalized.startsWith("marca fisica") ||
        normalized == "marca" ||
        normalized == "nivel"
}

enum class NotebookColumnVisibility {
    VISIBLE,
    HIDDEN,
    ARCHIVED,
}

enum class NotebookEmptyCellPolicy {
    EXCLUDE_FROM_AVERAGE, // vacío no cuenta
    COUNT_AS_ZERO,        // vacío cuenta como 0
    COUNT_AS_PENDING      // vacío no baja la nota, pero aparece como pendiente
}

data class NotebookAverageColumnConfig(
    val columnId: String,
    val countsTowardAverage: Boolean,
    val weight: Double,
    val emptyCellPolicy: NotebookEmptyCellPolicy? = null,
)

enum class NotebookDeletionTargetKind {
    COLUMN,
    CATEGORY,
    TAB,
}

data class NotebookDeletionImpact(
    val targetId: String,
    val targetName: String,
    val targetKind: NotebookDeletionTargetKind,
    val affectedColumnCount: Int,
    val affectedGradeCount: Int,
    val affectedFormulaColumnCount: Int,
    val affectedAverageColumnCount: Int,
    val hasLockedColumns: Boolean,
)

data class NotebookTab(
    val id: String,
    val title: String,
    val description: String? = null,
    val order: Int = -1,
    val parentTabId: String? = null,
    val fixedColumnWidth: Double? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookWorkGroup(
    val id: Long,
    val classId: Long,
    val tabId: String,
    val name: String,
    val order: Int = 0,
    val learningSituationId: Long? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookWorkGroupMember(
    val classId: Long,
    val tabId: String,
    val groupId: Long,
    val studentId: Long,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookColumnCategory(
    val id: String,
    val classId: Long,
    val tabId: String,
    val name: String,
    val order: Int = 0,
    val isCollapsed: Boolean = false,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookColumnDefinition(
    val id: String,
    val title: String,
    val type: NotebookColumnType,
    val categoryKind: NotebookColumnCategoryKind = NotebookColumnCategoryKind.CUSTOM,
    val instrumentKind: NotebookInstrumentKind = NotebookInstrumentKind.CUSTOM,
    val inputKind: NotebookCellInputKind = NotebookCellInputKind.TEXT,
    val evaluationId: Long? = null,
    val rubricId: Long? = null, // Temporary field for column creation linked to a rubric
    val formula: String? = null,
    val weight: Double = 1.0,
    val dateEpochMs: Long? = null,
    val unitOrSituation: String? = null,
    val competencyCriteriaIds: List<Long> = emptyList(),
    val scaleKind: NotebookScaleKind = NotebookScaleKind.CUSTOM,
    val tabIds: List<String> = emptyList(),
    val sessions: List<PlanningSession> = emptyList(),
    val sharedAcrossTabs: Boolean = false,
    val colorHex: String? = null,
    val iconName: String? = null,
    val order: Int = -1,
    val widthDp: Double = 0.0,
    val categoryId: String? = null,
    val ordinalLevels: List<String> = emptyList(),
    val availableIcons: List<String> = emptyList(),
    val countsTowardAverage: Boolean = true,
    val isPinned: Boolean = false,
    val isHidden: Boolean = false,
    val visibility: NotebookColumnVisibility = NotebookColumnVisibility.VISIBLE,
    val isLocked: Boolean = false,
    val isTemplate: Boolean = false,
    val emptyCellPolicy: NotebookEmptyCellPolicy = NotebookEmptyCellPolicy.EXCLUDE_FROM_AVERAGE,
    val trace: AuditTrace = AuditTrace(),
) {
    fun countsTowardAverage(): Boolean {
        if (!countsTowardAverage || weight <= 0.0) return false
        if (visibility == NotebookColumnVisibility.ARCHIVED) return false
        if (instrumentKind == NotebookInstrumentKind.PHYSICAL_TEST &&
            (scaleKind in rawPhysicalScaleKinds || unitOrSituation.isPhysicalRawDataLabel())
        ) {
            return false
        }
        return when (type) {
            NotebookColumnType.NUMERIC,
            NotebookColumnType.RUBRIC,
            NotebookColumnType.CALCULATED,
            NotebookColumnType.CHECK -> true
            NotebookColumnType.ORDINAL -> hasAverageOrdinalScore()
            else -> false
        }
    }

    fun averageExclusionReason(): NotebookAverageExclusionReason {
        if (visibility == NotebookColumnVisibility.ARCHIVED) return NotebookAverageExclusionReason.LOCKED_OR_ARCHIVED
        if (instrumentKind == NotebookInstrumentKind.PHYSICAL_TEST &&
            (scaleKind in rawPhysicalScaleKinds || unitOrSituation.isPhysicalRawDataLabel())
        ) {
            return NotebookAverageExclusionReason.RAW_VALUE_ONLY
        }
        if (weight <= 0.0) return NotebookAverageExclusionReason.RAW_VALUE_ONLY
        if (!countsTowardAverage) return NotebookAverageExclusionReason.COLUMN_DOES_NOT_COUNT
        return when (type) {
            NotebookColumnType.NUMERIC,
            NotebookColumnType.RUBRIC,
            NotebookColumnType.CALCULATED,
            NotebookColumnType.CHECK -> NotebookAverageExclusionReason.COLUMN_DOES_NOT_COUNT
            NotebookColumnType.ORDINAL -> {
                if (hasAverageOrdinalScore()) {
                    NotebookAverageExclusionReason.COLUMN_DOES_NOT_COUNT
                } else {
                    NotebookAverageExclusionReason.NON_NUMERIC
                }
            }
            else -> NotebookAverageExclusionReason.NON_NUMERIC
        }
    }

    fun hasAverageOrdinalScore(): Boolean =
        type == NotebookColumnType.ORDINAL &&
            instrumentKind == NotebookInstrumentKind.PARTICIPATION &&
            scaleKind == NotebookScaleKind.ACHIEVEMENT
}

data class NotebookCellAnnotation(
    val note: String? = null,
    val icon: String? = null,
    val colorHex: String? = null,
    val attachmentUris: List<String> = emptyList(),
)

data class NotebookStudentInsight(
    val studentId: Long,
    val averageScore: Double? = null,
    val latestAttendanceStatus: String? = null,
    val followUpCount: Int = 0,
    val incidentCount: Int = 0,
    val evidenceCount: Int = 0,
    val linkedCompetencyIds: List<Long> = emptyList(),
    val linkedCompetencyLabels: List<String> = emptyList(),
)

enum class RadarPriority {
    HIGH,
    MEDIUM,
    LOW,
    POSITIVE,
}

enum class RadarCategory {
    STUDENT_RISK,
    EVIDENCE_GAP,
    RUBRIC_COMPLETION,
    ATTENDANCE,
    PENDING_TASK,
    POSITIVE_PROGRESS,
    GROUP_SUMMARY,
}

data class TeacherRadarInsight(
    val id: String,
    val classId: Long,
    val studentId: Long?,
    val priority: RadarPriority,
    val category: RadarCategory,
    val title: String,
    val explanation: String,
    val suggestedAction: String,
    val evidence: List<String>,
)

data class NotebookSeatAssignment(
    val classId: Long,
    val studentId: Long,
    val tabId: String? = null,
    val normalizedX: Double = 0.5,
    val normalizedY: Double = 0.5,
    val zIndex: Int = 0,
    val trace: AuditTrace = AuditTrace(),
)

data class SeatingPlan(
    val classId: Long,
    val tabId: String? = null,
    val assignments: List<NotebookSeatAssignment> = emptyList(),
)

data class SeatActionState(
    val studentId: Long,
    val attendanceStatus: String? = null,
    val followUpRequired: Boolean = false,
    val incidentCount: Int = 0,
)

data class NotebookTypedCell(
    val studentId: Long,
    val columnId: String,
    val numericValue: Double? = null,
    val textValue: String? = null,
    val boolValue: Boolean? = null,
    val ordinalValue: String? = null,
    val iconValue: String? = null,
    val annotation: NotebookCellAnnotation? = null,
)

enum class NotebookCellAuditAction {
    CREATED,
    UPDATED,
    CLEARED,
    RESTORED,
    IMPORTED,
    SYNC_MERGED,
}

data class NotebookCellAuditEvent(
    val id: Long,
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val previousNumericValue: Double?,
    val newNumericValue: Double?,
    val previousTextValue: String?,
    val newTextValue: String?,
    val action: NotebookCellAuditAction,
    val changedAtEpochMs: Long,
    val authorUserId: Long?,
    val deviceId: String?,
    val syncVersion: Long,
)

data class PersistedNotebookCell(
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val textValue: String? = null,
    val boolValue: Boolean? = null,
    val iconValue: String? = null,
    val ordinalValue: String? = null,
    val displayValue: String? = null,
    val observedAtEpochMs: Long? = null,
    val competencyCriteriaIds: List<Long> = emptyList(),
    val effectiveWeight: Double? = null,
    val countsTowardAverage: Boolean? = null,
    val annotation: NotebookCellAnnotation? = null,
    val trace: AuditTrace = AuditTrace(),
)

enum class NotebookInstrumentTemplateKind {
    CHECKLIST,
    OBSERVATION,
    FORM,
    QUIZ,
}

enum class NotebookInstrumentItemType {
    CHECK,
    TEXT,
    NUMBER,
    SCALE_1_4,
    CHOICE,
}

data class NotebookInstrumentTemplate(
    val id: String,
    val classId: Long,
    val columnId: String,
    val evaluationId: Long? = null,
    val title: String,
    val kind: NotebookInstrumentTemplateKind,
    val inputKind: NotebookCellInputKind,
    val source: String? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookInstrumentItem(
    val id: String,
    val templateId: String,
    val key: String,
    val title: String,
    val type: NotebookInstrumentItemType,
    val options: List<String> = emptyList(),
    val required: Boolean = true,
    val order: Int = 0,
    val helpText: String? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookInstrumentResponse(
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val itemId: String,
    val textValue: String? = null,
    val boolValue: Boolean? = null,
    val numberValue: Double? = null,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookInstrumentDetail(
    val template: NotebookInstrumentTemplate,
    val items: List<NotebookInstrumentItem>,
)

data class NotebookInstrumentCellSummary(
    val completedCount: Int,
    val totalCount: Int,
    val displayValue: String,
    val isComplete: Boolean,
)

data class NotebookReusableInstrument(
    val id: String,
    val name: String,
    val categoryKind: NotebookColumnCategoryKind = NotebookColumnCategoryKind.CUSTOM,
    val instrumentKind: NotebookInstrumentKind = NotebookInstrumentKind.CUSTOM,
    val inputKind: NotebookCellInputKind = NotebookCellInputKind.TEXT,
    val scaleKind: NotebookScaleKind = NotebookScaleKind.CUSTOM,
    val weight: Double = 1.0,
    val competencyCriteriaIds: List<Long> = emptyList(),
    val colorHex: String? = null,
    val iconName: String? = null,
    val isTemplate: Boolean = false,
    val trace: AuditTrace = AuditTrace(),
)

data class NotebookConfig(
    val classId: Long,
    val tabs: List<NotebookTab>,
    val columns: List<NotebookColumnDefinition>,
    val columnCategories: List<NotebookColumnCategory> = emptyList(),
    val workGroups: List<NotebookWorkGroup> = emptyList(),
    val workGroupMembers: List<NotebookWorkGroupMember> = emptyList(),
)

data class NotebookSheet(
    val classId: Long,
    val tabs: List<NotebookTab>,
    val columns: List<NotebookColumnDefinition>,
    val columnCategories: List<NotebookColumnCategory> = emptyList(),
    val rows: List<NotebookRow>,
    val workGroups: List<NotebookWorkGroup> = emptyList(),
    val workGroupMembers: List<NotebookWorkGroupMember> = emptyList(),
    val insights: List<NotebookStudentInsight> = emptyList(),
)

data class NotebookGroupedRows(
    val group: NotebookWorkGroup? = null,
    val rows: List<NotebookRow>,
    val isUngrouped: Boolean = false,
)

data class NotebookRow(
    val student: Student,
    val cells: List<NotebookCell>,
    val weightedAverage: Double?,
    val averageExplanation: NotebookAverageExplanation? = null,
    val persistedCells: List<PersistedNotebookCell> = emptyList(),
    val persistedGrades: List<Grade> = emptyList(),
)

data class NotebookAverageExplanation(
    val studentId: Long,
    val average: Double?,
    val included: List<NotebookAverageContribution>,
    val excluded: List<NotebookAverageExclusion>,
    val totalIncludedWeight: Double,
    val policy: NotebookEmptyCellPolicy,
    val includedColumns: List<IncludedColumn> = included.map {
        IncludedColumn(
            columnId = it.columnId,
            title = it.title,
            value = it.value,
            weight = it.weight,
        )
    },
    val excludedColumns: List<ExcludedColumn> = excluded
        .filter { it.reason != NotebookAverageExclusionReason.EMPTY }
        .map {
            ExcludedColumn(
                columnId = it.columnId,
                title = it.title,
                reason = it.reason,
            )
        },
    val pendingCells: List<PendingCell> = excluded
        .filter { it.reason == NotebookAverageExclusionReason.EMPTY }
        .map {
            PendingCell(
                columnId = it.columnId,
                title = it.title,
                expectedWeight = 0.0,
            )
        },
    val weightedContributions: List<WeightedContribution> = included.map {
        WeightedContribution(
            columnId = it.columnId,
            title = it.title,
            value = it.value,
            weight = it.weight,
            weightedValue = it.weightedValue,
        )
    },
)

data class NotebookAverageContribution(
    val columnId: String,
    val title: String,
    val value: Double,
    val weight: Double,
    val weightedValue: Double,
)

data class IncludedColumn(
    val columnId: String,
    val title: String,
    val value: Double,
    val weight: Double,
)

data class NotebookAverageExclusion(
    val columnId: String,
    val title: String,
    val reason: NotebookAverageExclusionReason,
)

data class ExcludedColumn(
    val columnId: String,
    val title: String,
    val reason: NotebookAverageExclusionReason,
)

data class PendingCell(
    val columnId: String,
    val title: String,
    val expectedWeight: Double,
)

data class WeightedContribution(
    val columnId: String,
    val title: String,
    val value: Double,
    val weight: Double,
    val weightedValue: Double,
)

enum class NotebookAverageExclusionReason {
    EMPTY,
    COLUMN_DOES_NOT_COUNT,
    RAW_VALUE_ONLY,
    LOCKED_OR_ARCHIVED,
    NON_NUMERIC,
}

fun NotebookRow.gradeValueFor(
    column: NotebookColumnDefinition,
    calculatedValuesByColumnId: Map<String, Double> = emptyMap(),
    numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
): Double? {
    val studentId = student.id
    // 1. Check drafts (real-time input)
    val draftValue = numericDrafts[studentId to column.id]?.replace(",", ".")?.toDoubleOrNull()
        ?: column.evaluationId?.let { evalId ->
            numericDrafts[studentId to "eval_$evalId"]?.replace(",", ".")?.toDoubleOrNull()
        }
    if (draftValue != null) return draftValue

    // 2. Check calculated formula values
    calculatedValuesByColumnId[column.id]?.let { return it }

    // 3. Check cells (evaluations)
    val evaluationValue = column.evaluationId?.let { evaluationId ->
        cells.firstOrNull { it.evaluationId == evaluationId }?.value
    }
    if (evaluationValue != null) return evaluationValue

    // 4. Check persisted grades (by columnId or evaluationId)
    val persistedGrade = persistedGrades.firstOrNull { it.columnId == column.id }?.value
        ?: column.evaluationId?.let { evalId ->
            persistedGrades.firstOrNull { it.evaluationId == evalId }?.value
        }
    if (persistedGrade != null) return persistedGrade

    // 5. Check persisted cells check/bool/ordinal value
    val persistedCell = persistedCells.firstOrNull { it.columnId == column.id }
    return when (column.type) {
        NotebookColumnType.CHECK -> persistedCell?.boolValue?.let { if (it) 10.0 else 0.0 }
        NotebookColumnType.ORDINAL -> persistedCell?.ordinalValue?.let { column.ordinalScoreForAverage(it) }
        else -> persistedCell?.boolValue?.let { if (it) 10.0 else 0.0 }
    }
}

fun NotebookColumnDefinition.ordinalScoreForAverage(value: String): Double? {
    if (!hasAverageOrdinalScore()) return null
    return when (value.normalizedAverageOrdinal()) {
        "excelente" -> 10.0
        "bien" -> 7.5
        "en proceso",
        "en progreso",
        "parcial" -> 5.0
        "no logrado" -> 2.5
        else -> null
    }
}

private fun String.normalizedAverageOrdinal(): String =
    lowercase()
        .replace("á", "a")
        .replace("é", "e")
        .replace("í", "i")
        .replace("ó", "o")
        .replace("ú", "u")
        .replace("ü", "u")
        .trim()

fun NotebookRow.computeAverageExplanation(
    columns: List<NotebookColumnDefinition>,
    calculatedValuesByColumnId: Map<String, Double> = emptyMap(),
    numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
): NotebookAverageExplanation? {
    val evaluableColumns = columns.filter { it.visibility != NotebookColumnVisibility.ARCHIVED }
    if (evaluableColumns.isEmpty()) return null

    val included = mutableListOf<NotebookAverageContribution>()
    val excluded = mutableListOf<NotebookAverageExclusion>()
    val includedColumns = mutableListOf<IncludedColumn>()
    val excludedColumns = mutableListOf<ExcludedColumn>()
    val pendingCells = mutableListOf<PendingCell>()
    val weightedContributions = mutableListOf<WeightedContribution>()

    evaluableColumns.forEach { column ->
        if (!column.countsTowardAverage()) {
            val exclusion = NotebookAverageExclusion(
                columnId = column.id,
                title = column.title,
                reason = column.averageExclusionReason()
            )
            excluded += exclusion
            excludedColumns += ExcludedColumn(
                columnId = exclusion.columnId,
                title = exclusion.title,
                reason = exclusion.reason,
            )
            return@forEach
        }

        val value = gradeValueFor(column, calculatedValuesByColumnId, numericDrafts)
        if (value != null) {
            val contribution = NotebookAverageContribution(
                columnId = column.id,
                title = column.title,
                value = value,
                weight = column.weight,
                weightedValue = value * column.weight
            )
            included += contribution
            includedColumns += IncludedColumn(
                columnId = contribution.columnId,
                title = contribution.title,
                value = contribution.value,
                weight = contribution.weight,
            )
            weightedContributions += WeightedContribution(
                columnId = contribution.columnId,
                title = contribution.title,
                value = contribution.value,
                weight = contribution.weight,
                weightedValue = contribution.weightedValue,
            )
        } else {
            when (column.emptyCellPolicy) {
                NotebookEmptyCellPolicy.COUNT_AS_ZERO -> {
                    val contribution = NotebookAverageContribution(
                        columnId = column.id,
                        title = column.title,
                        value = 0.0,
                        weight = column.weight,
                        weightedValue = 0.0
                    )
                    included += contribution
                    includedColumns += IncludedColumn(
                        columnId = contribution.columnId,
                        title = contribution.title,
                        value = contribution.value,
                        weight = contribution.weight,
                    )
                    weightedContributions += WeightedContribution(
                        columnId = contribution.columnId,
                        title = contribution.title,
                        value = contribution.value,
                        weight = contribution.weight,
                        weightedValue = contribution.weightedValue,
                    )
                }
                else -> {
                    val exclusion = NotebookAverageExclusion(
                        columnId = column.id,
                        title = column.title,
                        reason = NotebookAverageExclusionReason.EMPTY
                    )
                    excluded += exclusion
                    pendingCells += PendingCell(
                        columnId = column.id,
                        title = column.title,
                        expectedWeight = column.weight,
                    )
                }
            }
        }
    }

    val totalWeight = included.sumOf { it.weight }
    val average = if (totalWeight > 0.0) {
        included.sumOf { it.weightedValue } / totalWeight
    } else {
        null
    }

    return NotebookAverageExplanation(
        studentId = student.id,
        average = average,
        included = included,
        excluded = excluded,
        totalIncludedWeight = totalWeight,
        policy = NotebookEmptyCellPolicy.EXCLUDE_FROM_AVERAGE,
        includedColumns = includedColumns,
        excludedColumns = excludedColumns,
        pendingCells = pendingCells,
        weightedContributions = weightedContributions,
    )
}

fun List<Grade>.gradeValueFor(evaluationId: Long): Double? {
    return firstOrNull { it.evaluationId == evaluationId }?.value
}

fun NotebookSheet.groupedRowsFor(tabId: String?): List<NotebookGroupedRows> {
    val selectedGroups = if (tabId == null) {
        workGroups
    } else {
        workGroups.filter { it.tabId == tabId }
    }.sortedWith(compareBy<NotebookWorkGroup> { it.order }.thenBy { it.id })

    if (selectedGroups.isEmpty()) {
        return listOf(NotebookGroupedRows(group = null, rows = rows, isUngrouped = true))
    }

    val selectedMemberships = if (tabId == null) {
        workGroupMembers
    } else {
        workGroupMembers.filter { it.tabId == tabId }
    }

    val membershipByStudentId = selectedMemberships.associateBy { it.studentId }
    val rowsGroupedStudentIds = mutableSetOf<Long>()

    val groupedSections = selectedGroups.map { group ->
        val groupRows = rows.filter { row ->
            membershipByStudentId[row.student.id]?.groupId == group.id
        }
        rowsGroupedStudentIds += groupRows.map { it.student.id }
        NotebookGroupedRows(group = group, rows = groupRows)
    }

    val ungroupedRows = rows.filterNot { it.student.id in rowsGroupedStudentIds }
    return groupedSections + NotebookGroupedRows(group = null, rows = ungroupedRows, isUngrouped = true)
}

fun NotebookSheet.rootTabs(): List<NotebookTab> {
    return tabs
        .filter { it.parentTabId == null }
        .sortedWith(compareBy<NotebookTab> { it.order }.thenBy { it.id })
}

fun NotebookSheet.childTabs(parentTabId: String?): List<NotebookTab> {
    return tabs
        .filter { it.parentTabId == parentTabId }
        .sortedWith(compareBy<NotebookTab> { it.order }.thenBy { it.id })
}

fun NotebookSheet.tabChildrenMap(): Map<String?, List<NotebookTab>> {
    return tabs.groupBy { it.parentTabId }.mapValues { (_, value) ->
        value.sortedWith(compareBy<NotebookTab> { it.order }.thenBy { it.id })
    }
}

fun NotebookSheet.visibleColumnsForTab(tabId: String?): List<NotebookColumnDefinition> {
    if (tabId == null) return emptyList()
    return columns.filter { column ->
        column.visibility == NotebookColumnVisibility.VISIBLE && (
            column.tabIds.contains(tabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty())
        )
    }.sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
}

data class NotebookColumnCategoryGroup(
    val category: NotebookColumnCategory?,
    val columns: List<NotebookColumnDefinition>,
)

fun NotebookSheet.groupColumnsForTab(tabId: String?): List<NotebookColumnCategoryGroup> {
    if (tabId == null) return emptyList()

    val tabColumns = visibleColumnsForTab(tabId)
    if (tabColumns.isEmpty()) return emptyList()

    val categoriesById = columnCategories
        .filter { it.tabId == tabId }
        .associateBy { it.id }

    val groupedByCategoryId = tabColumns.groupBy { it.categoryId?.takeIf { id -> categoriesById.containsKey(id) } }
    val sortedCategories = categoriesById.values.sortedWith(
        compareBy<NotebookColumnCategory> { it.order }.thenBy { it.id }
    )

    val result = mutableListOf<NotebookColumnCategoryGroup>()
    sortedCategories.forEach { category ->
        val cols = groupedByCategoryId[category.id].orEmpty()
            .sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
        if (cols.isNotEmpty()) {
            result += NotebookColumnCategoryGroup(category = category, columns = cols)
        }
    }

    val uncategorized = groupedByCategoryId[null].orEmpty()
        .sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
    if (uncategorized.isNotEmpty()) {
        result += NotebookColumnCategoryGroup(category = null, columns = uncategorized)
    }
    return result
}
sealed class ImportResult {
    data class Success(val students: List<Student>, val warnings: List<String>) : ImportResult()
    data class PartialSuccess(val students: List<Student>, val skippedRows: List<Pair<Int, String>>) : ImportResult()
    data class Failure(val reason: String, val rowIndex: Int? = null) : ImportResult()
}

// Slot fijo del horario semanal (Horario_Base)
data class ScheduleSlot(
    val id: Long,
    val dayOfWeek: Int,        // 1=Lun ... 5=Vie
    val period: Int,
    val startTime: String,
    val endTime: String,
    val groupId: Long,
    val classroom: String,
    val trace: AuditTrace = AuditTrace(),
)

// ─── TeachingUnit (Unidad Didáctica) ───────────────────────────────────────
data class TeachingUnit(
    val id: Long = 0,
    val name: String,
    val description: String = "",
    val colorHex: String = "#4A90D9",
    val groupId: Long? = null,
    val schoolClassId: Long? = null,
    val startDate: LocalDate? = null,
    val endDate: LocalDate? = null
)

// ─── Estado de la sesión ────────────────────────────────────────────────────
enum class SessionStatus(val label: String, val colorHex: String) {
    PLANNED("Planificada",  "#A8D5E2"),
    IN_PROGRESS("En Curso", "#F6C90E"),
    COMPLETED("Completada", "#38B000"),
    CANCELLED("Cancelada",  "#E63946")
}

// ─── Sesión de planificación ────────────────────────────────────────────────
data class PlanningSession(
    val id: Long = 0,
    val teachingUnitId: Long,
    val teachingUnitName: String,
    val teachingUnitColor: String = "#4A90D9",
    val groupId: Long,
    val groupName: String,
    val dayOfWeek: Int,    // 1 = Lunes … 5 = Viernes
    val period: Int,       // 1 – 6
    val weekNumber: Int,
    val year: Int,
    val objectives: String = "",
    val activities: String = "",
    val evaluation: String = "",
    val linkedAssessmentIdsCsv: String = "",
    val teacherScheduleSlotId: Long? = null,
    val startTime: String? = null,
    val endTime: String? = null,
    val learningSituationSessionPlanId: Long? = null,
    val status: SessionStatus = SessionStatus.PLANNED
)

enum class CollisionResolution {
    OVERWRITE,
    SKIP,
    CANCEL
}

data class SessionRelocationRequest(
    val sourceSessionIds: List<Long>,
    val targetGroupId: Long? = null,
    val targetDayOfWeek: Int? = null,
    val targetPeriod: Int? = null,
    val dayOffset: Int = 0,
    val periodOffset: Int = 0
)

data class SessionRelocationConflict(
    val sourceSessionId: Long,
    val destinationDate: LocalDate,
    val destinationGroupId: Long,
    val destinationPeriod: Int,
    val existingSessionId: Long? = null,
    val reason: String
)

data class SessionBulkResult(
    val affectedSessionIds: List<Long> = emptyList(),
    val movedOrCopied: Int = 0,
    val overwritten: Int = 0,
    val skipped: Int = 0,
    val failed: Int = 0
)

data class SessionPlacement(
    val sessionId: Long,
    val weekNumber: Int,
    val year: Int,
    val dayOfWeek: Int,
    val period: Int,
    val teacherScheduleSlotId: Long? = null,
    val startTime: String? = null,
    val endTime: String? = null,
)

data class SessionCascadeMoveRequest(
    val sourceSessionId: Long,
    val targetWeekNumber: Int,
    val targetYear: Int,
    val targetDayOfWeek: Int,
    val targetPeriod: Int,
)

data class SessionCascadeMovePreview(
    val previousPlacements: List<SessionPlacement> = emptyList(),
    val nextPlacements: List<SessionPlacement> = emptyList(),
    val completedSessionIds: List<Long> = emptyList(),
    val crossesWeekBoundary: Boolean = false,
    val isNoOp: Boolean = false,
)

data class SessionCascadeMoveResult(
    val previousPlacements: List<SessionPlacement> = emptyList(),
    val nextPlacements: List<SessionPlacement> = emptyList(),
    val movedCount: Int = 0,
    val crossesWeekBoundary: Boolean = false,
)

// ─── Configuración de franjas horarias ─────────────────────────────────────
data class TimeSlotConfig(val period: Int, val startTime: String, val endTime: String)

val DEFAULT_TIME_SLOTS = listOf(
    TimeSlotConfig(1, "08:05", "09:00"),
    TimeSlotConfig(2, "09:00", "10:00"),
    TimeSlotConfig(3, "10:00", "11:00"),
    TimeSlotConfig(4, "11:25", "12:20"),
    TimeSlotConfig(5, "12:20", "13:15"),
    TimeSlotConfig(6, "13:15", "14:10"),
    TimeSlotConfig(7, "14:25", "15:20"),
    TimeSlotConfig(8, "15:00", "15:55"),
    TimeSlotConfig(9, "15:55", "16:50")
)

// Resultado del "merge" Horario + Sesion — el tipo central de la UI
data class WeeklyPlannerSlot(
    val date: LocalDate,
    val scheduleSlot: ScheduleSlot,
    val session: PlanningSession?,
    val group: SchoolClass
)

// Plantilla permanente del horario semanal
data class WeeklySlotTemplate(
    val id: Long = 0,
    val schoolClassId: Long,        // qué grupo (SchoolClass)
    val dayOfWeek: Int,             // 1=Lunes … 5=Viernes
    val startTime: String,          // "09:00"
    val endTime: String             // "09:55"
)

data class TeacherSchedule(
    val id: Long = 0,
    val ownerUserId: Long,
    val academicYearId: Long,
    val name: String,
    val startDateIso: String,
    val endDateIso: String,
    val activeWeekdaysCsv: String = "1,2,3,4,5",
    val trace: AuditTrace = AuditTrace(),
)

data class TeacherScheduleSlot(
    val id: Long = 0,
    val teacherScheduleId: Long,
    val schoolClassId: Long,
    val subjectLabel: String = "",
    val unitLabel: String? = null,
    val dayOfWeek: Int,
    val startTime: String,
    val endTime: String,
    val weeklyTemplateId: Long? = null,
)

data class PlannerEvaluationPeriod(
    val id: Long = 0,
    val teacherScheduleId: Long,
    val name: String,
    val startDateIso: String,
    val endDateIso: String,
    val sortOrder: Int = 0,
)

data class PlannerSessionForecast(
    val periodId: Long,
    val periodName: String,
    val schoolClassId: Long? = null,
    val className: String = "",
    val expectedSessions: Int = 0,
    val plannedSessions: Int = 0,
    val remainingSessions: Int = 0,
)

// Sesión concreta generada en el planificador
data class PlannedSession(
    val id: Long = 0,
    val teachingUnitId: Long?,      // UD asociada (nullable = sesión suelta)
    val schoolClassId: Long,
    val date: LocalDate,
    val startTime: String,
    val endTime: String,
    val title: String = "",
    val objectives: String = "",
    val resources: String = "",
    val notes: String = ""
)

// Extensión de TeachingUnit (o tabla aparte si UD ya existe)
data class TeachingUnitSchedule(
    val teachingUnitId: Long,
    val schoolClassId: Long,        // para qué curso
    val startDate: LocalDate,
    val endDate: LocalDate
)
