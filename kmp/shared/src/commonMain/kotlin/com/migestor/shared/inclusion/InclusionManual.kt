package com.migestor.shared.inclusion

import com.migestor.shared.domain.StudentSupportMeasure
import com.migestor.shared.domain.SupportMeasureType
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.daysUntil
import kotlinx.datetime.plus

/**
 * Fases del curso según el Manual de Inclusión 2026-2027.
 * Se persisten por `name` en `inclusion_tasks.phase`: no renombrar.
 */
enum class InclusionPhase { SEPTIEMBRE, OBSERVAR, EVALUACION_INICIAL, NOVIEMBRE, DICIEMBRE }

/** Estado de plazo. "Esta semana" = los próximos 7 días desde hoy (hoy incluido). */
enum class InclusionDeadlineStatus { DONE, OVERDUE, SOON, NORMAL }

/** Cómo calcula el manual la fecha de una tarea. */
sealed class InclusionDueRule {
    /** Día fijo del curso. Septiembre-diciembre caen en el primer año; enero-agosto, en el segundo. */
    data class Fixed(val month: Int, val day: Int) : InclusionDueRule()
    /** N días después de la evaluación inicial del grupo. */
    data class AfterInitialEvaluation(val days: Int) : InclusionDueRule()
}

data class InclusionTaskTemplate(
    val key: String,
    val title: String,
    val phase: InclusionPhase,
    val rule: InclusionDueRule,
    /** Medida que origina la tarea (anexos PAPACIS...). `null` = tarea del alumno. */
    val measureId: Long? = null,
)

data class InclusionTask(
    val id: Long,
    val studentId: Long,
    val measureId: Long?,
    /** `null` = tarea libre del docente. */
    val templateKey: String?,
    val title: String,
    val phase: InclusionPhase,
    val dueDate: LocalDate,
    val dueIsCustom: Boolean,
    val doneAt: LocalDate?,
    val notes: String,
    val schoolYear: String,
    val createdAtEpochMs: Long,
    val updatedAtEpochMs: Long,
) {
    val isDone: Boolean get() = doneAt != null
}

/** Tarea lista para pintar: fecha del manual y estado ya calculados en KMP. */
data class InclusionTaskItem(
    val task: InclusionTask,
    /** Fecha del manual vigente. En tareas libres coincide con la fecha de la tarea. */
    val manualDue: LocalDate,
    val isEdited: Boolean,
    val status: InclusionDeadlineStatus,
    val canReset: Boolean,
)

data class InclusionSummary(val overdue: Int, val dueThisWeek: Int)

data class InclusionStudentBoard(
    val studentId: Long,
    val items: List<InclusionTaskItem>,
) {
    val doneCount: Int get() = items.count { it.task.isDone }
    val overdueCount: Int get() = items.count { it.status == InclusionDeadlineStatus.OVERDUE }
}

data class InclusionGroupBoard(
    val classId: Long,
    val schoolYear: String,
    val initialEvaluationDate: LocalDate,
    val students: List<InclusionStudentBoard>,
    val summary: InclusionSummary,
)

/**
 * Plantillas del Manual de Inclusión 2026-2027. Viven en código, no en BD:
 * cambian una vez por curso y van con la versión de la app.
 */
object InclusionManual {
    const val KEY_CARPETA_ROJA = "carpeta_roja"
    const val KEY_DOC1 = "doc1_consentimiento"
    const val KEY_DOC2 = "doc2_acta_reunion"
    const val KEY_DOC7_PAP = "doc7_pap"
    const val KEY_DOC4 = "doc4_audiencia_familia"
    const val KEY_ITACA = "itaca_medidas"
    const val KEY_EDUCAMOS = "educamos_firmados"
    const val PREFIX_PAPACIS = "papacis:"

    /** Días tras la evaluación inicial para el Doc4 (igual que la maqueta). */
    const val DOC4_DAYS_AFTER_INITIAL_EVAL = 3

    /** Sin fecha guardada para el grupo se usa el 22 de octubre del primer año. */
    fun defaultInitialEvaluationDate(schoolYear: String): LocalDate =
        LocalDate(startYear(schoolYear), 10, 22)

    /** "2026-2027" a partir de una fecha: el curso empieza el 1 de septiembre. */
    fun schoolYearFor(date: LocalDate): String {
        val start = if (date.monthNumber >= 9) date.year else date.year - 1
        return "$start-${start + 1}"
    }

    fun startYear(schoolYear: String): Int =
        schoolYear.substringBefore('-').toIntOrNull()
            ?: throw IllegalArgumentException("Curso escolar no válido: $schoolYear")

    fun schoolYearStart(schoolYear: String): LocalDate = LocalDate(startYear(schoolYear), 9, 1)

    private val fixedCommon = listOf(
        InclusionTaskTemplate(KEY_CARPETA_ROJA, "Revisar la carpeta roja", InclusionPhase.SEPTIEMBRE, InclusionDueRule.Fixed(9, 15)),
        InclusionTaskTemplate(KEY_DOC4, "Doc4: audiencia a la familia", InclusionPhase.EVALUACION_INICIAL, InclusionDueRule.AfterInitialEvaluation(DOC4_DAYS_AFTER_INITIAL_EVAL)),
        InclusionTaskTemplate(KEY_ITACA, "Marcar las medidas en ITACA", InclusionPhase.NOVIEMBRE, InclusionDueRule.Fixed(11, 20)),
        InclusionTaskTemplate(KEY_EDUCAMOS, "Subir los documentos firmados a Educamos", InclusionPhase.DICIEMBRE, InclusionDueRule.Fixed(12, 18)),
    )

    /**
     * Medidas que piden Doc7 (PAP) y su anexo. Hoy el catálogo solo tiene ACIS;
     * AyL y enriquecimiento no existen aún en [SupportMeasureType] y se añadirán
     * aquí cuando entren en el catálogo.
     */
    private val papAnnexByType: Map<SupportMeasureType, String> = mapOf(
        SupportMeasureType.ACIS to "PAPACIS",
    )

    /**
     * Plantillas que tocan a un alumno según sus medidas.
     * @param activeMeasures medidas activas (nivel III/IV) del alumno.
     * @param allMeasures todas sus medidas, también retiradas: sirven para saber si el Doc1 ya se firmó otro curso.
     */
    fun templatesFor(
        schoolYear: String,
        activeMeasures: List<StudentSupportMeasure>,
        allMeasures: List<StudentSupportMeasure> = activeMeasures,
    ): List<InclusionTaskTemplate> {
        if (activeMeasures.isEmpty()) return emptyList()
        val yearStart = schoolYearStart(schoolYear)
        val result = fixedCommon.toMutableList()

        val hasNewMeasure = activeMeasures.any { it.startDate >= yearStart }
        if (hasNewMeasure) {
            val signedOtherYear = allMeasures.any { it.startDate < yearStart }
            if (!signedOtherYear) {
                result += InclusionTaskTemplate(KEY_DOC1, "Doc1: consentimiento de la familia", InclusionPhase.SEPTIEMBRE, InclusionDueRule.Fixed(9, 30))
            }
            result += InclusionTaskTemplate(KEY_DOC2, "Doc2: acta de la reunión conjunta", InclusionPhase.OBSERVAR, InclusionDueRule.Fixed(10, 9))
        }

        val papMeasures = activeMeasures.filter { it.measureType in papAnnexByType }.sortedBy { it.id }
        if (papMeasures.isNotEmpty()) {
            result += InclusionTaskTemplate(KEY_DOC7_PAP, "Doc7: PAP", InclusionPhase.OBSERVAR, InclusionDueRule.Fixed(10, 15))
            papMeasures.forEach { measure ->
                val annex = papAnnexByType.getValue(measure.measureType)
                result += InclusionTaskTemplate(
                    key = annexKey(measure),
                    title = "Anexo $annex",
                    phase = InclusionPhase.OBSERVAR,
                    rule = InclusionDueRule.Fixed(10, 15),
                    measureId = measure.id,
                )
            }
        }
        return result
    }

    private fun annexKey(measure: StudentSupportMeasure): String = when (measure.measureType) {
        SupportMeasureType.ACIS -> "$PREFIX_PAPACIS${measure.id}"
        else -> "anexo_${measure.measureType.name.lowercase()}:${measure.id}"
    }

    /** Regla de una clave guardada. `null` = tarea libre o clave que ya no existe en el manual. */
    fun ruleFor(templateKey: String?): InclusionDueRule? {
        if (templateKey == null) return null
        fixedCommon.firstOrNull { it.key == templateKey }?.let { return it.rule }
        return when {
            templateKey == KEY_DOC1 -> InclusionDueRule.Fixed(9, 30)
            templateKey == KEY_DOC2 -> InclusionDueRule.Fixed(10, 9)
            templateKey == KEY_DOC7_PAP -> InclusionDueRule.Fixed(10, 15)
            templateKey.startsWith(PREFIX_PAPACIS) -> InclusionDueRule.Fixed(10, 15)
            templateKey.startsWith("anexo_") -> InclusionDueRule.Fixed(10, 15)
            else -> null
        }
    }

    fun manualDue(rule: InclusionDueRule, schoolYear: String, initialEvaluation: LocalDate): LocalDate = when (rule) {
        is InclusionDueRule.Fixed -> {
            val start = startYear(schoolYear)
            LocalDate(if (rule.month >= 9) start else start + 1, rule.month, rule.day)
        }
        is InclusionDueRule.AfterInitialEvaluation -> initialEvaluation.plus(DatePeriod(days = rule.days))
    }

    fun status(task: InclusionTask, today: LocalDate): InclusionDeadlineStatus {
        if (task.isDone) return InclusionDeadlineStatus.DONE
        val delta = today.daysUntil(task.dueDate)
        return when {
            delta < 0 -> InclusionDeadlineStatus.OVERDUE
            delta <= 7 -> InclusionDeadlineStatus.SOON
            else -> InclusionDeadlineStatus.NORMAL
        }
    }

    fun summary(tasks: List<InclusionTask>, today: LocalDate): InclusionSummary {
        val statuses = tasks.map { status(it, today) }
        return InclusionSummary(
            overdue = statuses.count { it == InclusionDeadlineStatus.OVERDUE },
            dueThisWeek = statuses.count { it == InclusionDeadlineStatus.SOON },
        )
    }
}
