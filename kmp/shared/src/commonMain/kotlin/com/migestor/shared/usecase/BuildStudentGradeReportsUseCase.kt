package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.RubricAssessment
import com.migestor.shared.domain.RubricDetail

/**
 * Nivel de una nota sobre 10 con las bandas habituales de la LOMLOE.
 * Solo es una etiqueta para el informe: no cambia ninguna nota.
 */
enum class GradeLevel(val label: String) {
    INSUFICIENTE("Insuficiente"),
    SUFICIENTE("Suficiente"),
    BIEN("Bien"),
    NOTABLE("Notable"),
    SOBRESALIENTE("Sobresaliente");

    companion object {
        fun of(score: Double): GradeLevel = when {
            score >= 9.0 -> SOBRESALIENTE
            score >= 7.0 -> NOTABLE
            score >= 6.0 -> BIEN
            score >= 5.0 -> SUFICIENTE
            else -> INSUFICIENTE
        }
    }
}

/** Un instrumento que entra en la Media del alumno, con su peso en porcentaje del total. */
data class GradeReportInstrument(
    val columnId: String,
    val title: String,
    val value: Double,
    val weight: Double,
    val weightPercent: Double,
    val level: GradeLevel,
    val criterionCodes: List<String>,
)

/** Nivel logrado en un criterio de rúbrica, con el texto de ese nivel tal cual está en la rúbrica. */
data class GradeReportRubricCriterion(
    val criterionId: Long,
    val name: String,
    val levelName: String,
    /** Posición del nivel logrado de menos a más puntos, empezando en 1. */
    val levelPosition: Int,
    val levelCount: Int,
    val levelDescription: String?,
)

data class GradeReportRubric(
    val columnId: String,
    val title: String,
    val criteria: List<GradeReportRubricCriterion>,
)

/**
 * Informe de notas de un alumno a partir del Cuaderno ya calculado.
 * La nota final es la Media de la fila: el informe nunca la recalcula de otra forma.
 */
data class StudentGradeReport(
    val studentId: Long,
    val studentName: String,
    val firstName: String,
    val email: String?,
    val finalGrade: Double?,
    val finalLevel: GradeLevel?,
    val instruments: List<GradeReportInstrument>,
    val rubrics: List<GradeReportRubric>,
    /** Instrumentos que cuentan pero aún no tienen nota. */
    val pendingTitles: List<String>,
) {
    val hasEmail: Boolean get() = !email.isNullOrBlank()
    val hasGrades: Boolean get() = finalGrade != null && instruments.isNotEmpty()
    val bestInstrument: GradeReportInstrument? get() = instruments.maxByOrNull { it.value }
    val weakestInstrument: GradeReportInstrument? get() = instruments.minByOrNull { it.value }
}

class BuildStudentGradeReportsUseCase {
    /**
     * @param columns columnas del Cuaderno (las mismas que dieron la Media de cada fila).
     * @param rows filas con `averageExplanation` ya calculada para la pestaña activa.
     * @param rubricsByColumn rúbrica de cada columna de rúbrica que cuenta.
     * @param assessmentsByColumn valoraciones guardadas de cada columna de rúbrica.
     * @param criterionCodes códigos de criterio de evaluación (p. ej. «CE 2.1») por id.
     */
    fun build(
        columns: List<NotebookColumnDefinition>,
        rows: List<NotebookRow>,
        rubricsByColumn: Map<String, RubricDetail> = emptyMap(),
        assessmentsByColumn: Map<String, List<RubricAssessment>> = emptyMap(),
        criterionCodes: Map<Long, String> = emptyMap(),
    ): List<StudentGradeReport> {
        val columnsById = columns.associateBy { it.id }
        return rows.map { row ->
            val explanation = row.averageExplanation
            val included = explanation?.included.orEmpty()
            val totalWeight = included.sumOf { it.weight }
            val instruments = included.map { contribution ->
                val column = columnsById[contribution.columnId]
                GradeReportInstrument(
                    columnId = contribution.columnId,
                    title = contribution.title,
                    value = contribution.value,
                    weight = contribution.weight,
                    weightPercent = if (totalWeight > 0.0) contribution.weight / totalWeight * 100.0 else 0.0,
                    level = GradeLevel.of(contribution.value),
                    criterionCodes = column?.competencyCriteriaIds.orEmpty()
                        .distinct()
                        .mapNotNull { criterionCodes[it]?.takeIf { code -> code.isNotBlank() } },
                )
            }
            val rubrics = instruments.mapNotNull { instrument ->
                rubricFor(
                    studentId = row.student.id,
                    instrument = instrument,
                    rubric = rubricsByColumn[instrument.columnId],
                    assessments = assessmentsByColumn[instrument.columnId].orEmpty(),
                )
            }
            val finalGrade = row.weightedAverage ?: explanation?.average
            StudentGradeReport(
                studentId = row.student.id,
                studentName = row.student.fullName,
                firstName = row.student.firstName.trim().ifEmpty { row.student.fullName },
                email = row.student.email?.trim()?.takeIf { it.isNotEmpty() },
                finalGrade = finalGrade,
                finalLevel = finalGrade?.let { GradeLevel.of(it) },
                instruments = instruments,
                rubrics = rubrics,
                pendingTitles = explanation?.pendingCells.orEmpty().map { it.title },
            )
        }
    }

    private fun rubricFor(
        studentId: Long,
        instrument: GradeReportInstrument,
        rubric: RubricDetail?,
        assessments: List<RubricAssessment>,
    ): GradeReportRubric? {
        if (rubric == null) return null
        val levelByCriterion = assessments
            .filter { it.studentId == studentId }
            .associate { it.criterionId to it.levelId }
        val criteria = rubric.criteria
            .sortedBy { it.criterion.order }
            .mapNotNull { withLevels ->
                val levelId = levelByCriterion[withLevels.criterion.id] ?: return@mapNotNull null
                // De menos a más puntos: la posición 1 es el nivel más bajo, sea cual sea el orden de edición.
                val levels = withLevels.levels.sortedWith(compareBy({ it.points }, { it.order }))
                val index = levels.indexOfFirst { it.id == levelId }
                if (index < 0) return@mapNotNull null
                val level = levels[index]
                GradeReportRubricCriterion(
                    criterionId = withLevels.criterion.id,
                    name = withLevels.criterion.description.trim(),
                    levelName = level.name.trim(),
                    levelPosition = index + 1,
                    levelCount = levels.size,
                    levelDescription = level.description?.trim()?.takeIf { it.isNotEmpty() },
                )
            }
        if (criteria.isEmpty()) return null
        return GradeReportRubric(columnId = instrument.columnId, title = instrument.title, criteria = criteria)
    }
}
