package com.migestor.shared.usecase

import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.CompetencyCriterion
import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.PlannerEvaluationPeriod
import com.migestor.shared.domain.RubricAssessment
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.domain.StudentTutoringSession
import com.migestor.shared.repository.AttendanceRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.CompetenciesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.IncidentsRepository
import com.migestor.shared.repository.NotebookCellsRepository
import com.migestor.shared.repository.NotebookConfigRepository
import com.migestor.shared.repository.RubricsRepository
import com.migestor.shared.repository.StudentTutoringSessionRepository
import com.migestor.shared.repository.TeacherScheduleRepository
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.plus

/**
 * Evidencia cualitativa y por criterio de un alumno en un trimestre, lista para que
 * la IA local redacte el Comentario LOMLOE (issue #407, parte A).
 *
 * Todo sale de lo ya guardado. La única cifra que se calcula es [termMetrics] (media y
 * asistencia del trimestre), con el motor de medias del Cuaderno. Las listas
 * llegan ya recortadas y ordenadas por prioridad; [omittedCriterionResults] y
 * [omittedObservations] dicen cuánto quedó fuera para poder avisarlo en pantalla.
 */
data class LomloeCommentEvidence(
    val criterionResults: List<LomloeCriterionResult> = emptyList(),
    val competencies: List<LomloeCompetencyRef> = emptyList(),
    val observations: List<LomloeObservation> = emptyList(),
    val omittedCriterionResults: Int = 0,
    val omittedObservations: Int = 0,
    /** `true` si la evidencia se filtró por las fechas del trimestre. */
    val periodApplied: Boolean = false,
    /**
     * Media y asistencia del alumno restringidas al trimestre. Solo existe si [periodApplied];
     * sin periodo configurado es `null` y quien consume usa las cifras de todo el curso.
     */
    val termMetrics: LomloeTermMetrics? = null,
) {
    val isEmpty: Boolean get() = criterionResults.isEmpty() && observations.isEmpty() && competencies.isEmpty()
}

/** Nivel logrado en un criterio de rúbrica. [points] y [maxPoints] sitúan el nivel, no son una nota. */
data class LomloeCriterionResult(
    val evaluationName: String,
    val criterion: String,
    val levelName: String,
    val levelDescription: String? = null,
    val points: Int,
    val maxPoints: Int,
    val competencyCodes: List<String> = emptyList(),
    val assessedAtEpochMs: Long = 0,
)

/** Competencia o criterio de evaluación realmente trabajado con el alumno en el periodo. */
data class LomloeCompetencyRef(
    val code: String,
    val name: String,
)

enum class LomloeObservationSource { NOTEBOOK, INCIDENT, TUTORING }

/** Texto escrito por el docente: celda o nota del Cuaderno, incidencia o acuerdo de tutoría. */
data class LomloeObservation(
    val source: LomloeObservationSource,
    val title: String,
    val text: String,
    val dateEpochMs: Long = 0,
)

/**
 * Cifras del alumno dentro del trimestre (issue #407). Nunca se mezclan con las de curso:
 * si no hay datos en el periodo, el valor es `null` y no se rellena con el curso.
 *
 * - [averageScore]: media ponderada del Cuaderno (0-10) sobre las columnas del trimestre,
 *   o `null` si ninguna columna del periodo tiene nota.
 * - [attendanceRate]: porcentaje de asistencia 0-100 (sin redondear), o `null` si no hay
 *   registros en el periodo. "Presente" es lo mismo que en el perfil del alumno: estado `PRESENTE`.
 */
data class LomloeTermMetrics(
    val averageScore: Double? = null,
    /** Columnas que han entrado en [averageScore]. */
    val averagedColumnCount: Int = 0,
    val attendanceRate: Double? = null,
    val attendanceRecords: Int = 0,
    val presentRecords: Int = 0,
)

/** Resultado de calcular la media del Cuaderno con las columnas del trimestre. */
data class LomloeTermAverage(
    val value: Double? = null,
    val columnCount: Int = 0,
)

/** Evaluaciones y columnas del Cuaderno cuya fecha cae en el trimestre. */
data class LomloeNotebookSelection(
    val evaluations: List<Evaluation>,
    val columns: List<NotebookColumnDefinition>,
)

/** Tramo de fechas de un trimestre, inclusivo en ambos extremos. */
data class LomloePeriod(
    val startEpochMs: Long,
    val endEpochMs: Long,
) {
    /** Un dato sin fecha conocida (0) no se descarta: es mejor usarlo que perderlo. */
    fun contains(epochMs: Long): Boolean = epochMs <= 0L || epochMs in startEpochMs..endEpochMs
}

/** Datos ya cargados sobre los que se construye la evidencia. Sin acceso a repositorios. */
data class LomloeEvidenceInput(
    val studentId: Long,
    val evaluations: List<Evaluation> = emptyList(),
    val rubrics: List<RubricDetail> = emptyList(),
    val assessments: List<RubricAssessment> = emptyList(),
    val grades: List<Grade> = emptyList(),
    val competencies: List<CompetencyCriterion> = emptyList(),
    val columns: List<NotebookColumnDefinition> = emptyList(),
    val cells: List<PersistedNotebookCell> = emptyList(),
    val incidents: List<Incident> = emptyList(),
    val tutoringSessions: List<StudentTutoringSession> = emptyList(),
    val attendance: List<Attendance> = emptyList(),
)

object LomloeCommentEvidenceBuilder {
    const val DEFAULT_MAX_CRITERION_RESULTS = 8
    const val DEFAULT_MAX_OBSERVATIONS = 6

    /** Icono que marca las columnas de texto generadas por IA (Comentario IA, Síntesis pedagógica). */
    const val AI_COLUMN_ICON = "apple.intelligence"

    /**
     * Fechas del trimestre a partir de los periodos de evaluación del horario docente.
     * `T1` es el primer periodo por orden, `T2` el segundo... Devuelve `null` si no hay
     * periodo para esa clave o sus fechas no se pueden leer: entonces no se filtra.
     */
    fun resolvePeriod(
        periods: List<PlannerEvaluationPeriod>,
        termKey: String,
        timeZone: TimeZone = TimeZone.currentSystemDefault(),
    ): LomloePeriod? {
        val index = termKey.removePrefix("T").toIntOrNull()?.minus(1) ?: return null
        val period = periods
            .sortedWith(compareBy<PlannerEvaluationPeriod> { it.sortOrder }.thenBy { it.startDateIso })
            .getOrNull(index) ?: return null
        val start = runCatching { LocalDate.parse(period.startDateIso) }.getOrNull() ?: return null
        val end = runCatching { LocalDate.parse(period.endDateIso) }.getOrNull() ?: return null
        if (end < start) return null
        return LomloePeriod(
            startEpochMs = start.atStartOfDayIn(timeZone).toEpochMilliseconds(),
            // Hasta el último milisegundo del día final.
            endEpochMs = end.plus(1, DateTimeUnit.DAY).atStartOfDayIn(timeZone).toEpochMilliseconds() - 1,
        )
    }

    /**
     * Qué parte del Cuaderno cuenta para la media del trimestre.
     *
     * Regla: una columna (o evaluación) entra si su fecha cae en [period]. Fecha de la columna:
     * la fecha propia de la columna si la tiene; si no, la última modificación de la nota o celda
     * del alumno en ella; sin ninguna fecha (0) no se descarta, igual que el resto de la evidencia.
     * Una evaluación sin columna configurada usa la última modificación de su nota.
     * No toca pesos, categorías ni columnas ocultas: eso lo resuelve el mismo motor de medias del Cuaderno.
     */
    fun selectNotebookForPeriod(input: LomloeEvidenceInput, period: LomloePeriod): LomloeNotebookSelection {
        val grades = input.grades.filter { it.studentId == input.studentId }
        val cells = input.cells.filter { it.studentId == input.studentId }

        fun valueDate(columnId: String, evaluationId: Long?): Long {
            val gradeDates = grades
                .filter { it.columnId == columnId || (evaluationId != null && it.evaluationId == evaluationId) }
                .map { it.trace.updatedAt.toEpochMilliseconds() }
            val cellDates = cells.filter { it.columnId == columnId }.map { it.trace.updatedAt.toEpochMilliseconds() }
            return (gradeDates + cellDates).maxOrNull() ?: 0L
        }

        fun columnDate(column: NotebookColumnDefinition): Long =
            column.dateEpochMs?.takeIf { it > 0L } ?: valueDate(column.id, column.evaluationId)

        val columnByEvaluationId = input.columns
            .filter { it.evaluationId != null }
            .associateBy { it.evaluationId }
        val evaluations = input.evaluations.filter { evaluation ->
            val date = columnByEvaluationId[evaluation.id]?.let(::columnDate)
                ?: valueDate("eval_${evaluation.id}", evaluation.id)
            period.contains(date)
        }
        val columns = input.columns.filter { period.contains(columnDate(it)) }
        return LomloeNotebookSelection(evaluations = evaluations, columns = columns)
    }

    /**
     * Asistencia del alumno en el trimestre. Mismo criterio de "presente" que el perfil del
     * alumno (`loadStudentProfile`): el estado contiene `PRESENT` sin distinguir mayúsculas,
     * así que solo cuenta `PRESENTE` (tarde, justificado o exento no suman). Un registro sin
     * fecha (0) no se descarta.
     */
    fun termAttendance(input: LomloeEvidenceInput, period: LomloePeriod): LomloeTermMetrics {
        val records = input.attendance.filter {
            it.studentId == input.studentId && period.contains(it.date.toEpochMilliseconds())
        }
        val present = records.count { it.status.uppercase().contains("PRESENT") }
        return LomloeTermMetrics(
            attendanceRate = if (records.isEmpty()) null else present * 100.0 / records.size,
            attendanceRecords = records.size,
            presentRecords = present,
        )
    }

    fun build(
        input: LomloeEvidenceInput,
        period: LomloePeriod? = null,
        maxCriterionResults: Int = DEFAULT_MAX_CRITERION_RESULTS,
        maxObservations: Int = DEFAULT_MAX_OBSERVATIONS,
        termAverage: LomloeTermAverage? = null,
    ): LomloeCommentEvidence {
        fun inPeriod(epochMs: Long) = period?.contains(epochMs) ?: true

        val competencyById = input.competencies.associateBy { it.id }
        val evaluationById = input.evaluations.associateBy { it.id }
        val usedCompetencyIds = linkedSetOf<Long>()

        // --- Resultados por criterio de rúbrica ---
        val criteriaById = input.rubrics
            .flatMap { it.criteria }
            .associateBy { it.criterion.id }
        val allResults = input.assessments
            .filter { it.studentId == input.studentId }
            .filter { inPeriod(it.trace.updatedAt.toEpochMilliseconds()) }
            .mapNotNull { assessment ->
                val evaluation = evaluationById[assessment.evaluationId] ?: return@mapNotNull null
                val criterion = criteriaById[assessment.criterionId] ?: return@mapNotNull null
                val level = criterion.levels.firstOrNull { it.id == assessment.levelId } ?: return@mapNotNull null
                val competencyIds = listOfNotNull(criterion.criterion.competencyId) +
                    evaluation.competencyLinks.map { it.competencyId }
                usedCompetencyIds += competencyIds
                LomloeCriterionResult(
                    evaluationName = evaluation.name.trim(),
                    criterion = criterion.criterion.description.trim(),
                    levelName = level.name.trim(),
                    levelDescription = level.description?.trim()?.takeIf { it.isNotEmpty() },
                    points = level.points,
                    maxPoints = criterion.levels.maxOfOrNull { it.points } ?: level.points,
                    competencyCodes = competencyIds.distinct().mapNotNull { competencyById[it]?.code },
                    assessedAtEpochMs = assessment.trace.updatedAt.toEpochMilliseconds(),
                )
            }
            // Lo más reciente primero; a igualdad, orden estable por textos.
            .sortedWith(
                compareByDescending<LomloeCriterionResult> { it.assessedAtEpochMs }
                    .thenBy { it.evaluationName }
                    .thenBy { it.criterion },
            )
        val criterionResults = pickCriterionResults(allResults, maxCriterionResults)

        // --- Competencias de evaluaciones con nota del alumno en el periodo ---
        input.grades
            .filter { it.studentId == input.studentId && it.value != null }
            .filter { inPeriod(it.trace.updatedAt.toEpochMilliseconds()) }
            .mapNotNull { it.evaluationId?.let(evaluationById::get) }
            .forEach { evaluation -> usedCompetencyIds += evaluation.competencyLinks.map { it.competencyId } }

        // --- Observaciones del Cuaderno ---
        val columnById = input.columns.associateBy { it.id }
        val notebookObservations = input.cells
            .filter { it.studentId == input.studentId }
            .flatMap { cell ->
                val column = columnById[cell.columnId] ?: return@flatMap emptyList()
                if (isAiGeneratedColumn(column)) return@flatMap emptyList()
                val date = cell.observedAtEpochMs ?: column.dateEpochMs ?: cell.trace.updatedAt.toEpochMilliseconds()
                if (!inPeriod(date)) return@flatMap emptyList()
                // Una celda con contenido en el periodo cuenta como competencia trabajada.
                if (cellHasContent(cell)) {
                    usedCompetencyIds += cell.competencyCriteriaIds.ifEmpty { column.competencyCriteriaIds }
                }
                buildList {
                    if (column.type == NotebookColumnType.TEXT) {
                        cleanText(cell.textValue)?.let { add(LomloeObservation(LomloeObservationSource.NOTEBOOK, column.title.trim(), it, date)) }
                    }
                    cleanText(cell.annotation?.note)?.let { add(LomloeObservation(LomloeObservationSource.NOTEBOOK, column.title.trim(), it, date)) }
                }
            }

        // --- Incidencias y tutorías ---
        val incidentObservations = input.incidents
            .filter { it.studentId == input.studentId }
            .filter { inPeriod(it.date.toEpochMilliseconds()) }
            .mapNotNull { incident ->
                val title = incident.title.trim()
                val text = cleanText(incident.detail) ?: title.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                LomloeObservation(LomloeObservationSource.INCIDENT, title, text, incident.date.toEpochMilliseconds())
            }
        val timeZone = TimeZone.currentSystemDefault()
        val tutoringObservations = input.tutoringSessions
            .filter { it.studentId == input.studentId }
            .mapNotNull { session ->
                val date = session.date.atStartOfDayIn(timeZone).toEpochMilliseconds()
                if (!inPeriod(date)) return@mapNotNull null
                // Solo los acuerdos: los temas tratados con la familia no se pasan a la IA.
                val text = cleanText(session.agreements) ?: return@mapNotNull null
                LomloeObservation(LomloeObservationSource.TUTORING, "Acuerdo de tutoría", text, date)
            }

        val allObservations = (notebookObservations + incidentObservations + tutoringObservations)
            .distinctBy { it.text.lowercase() }
            .sortedWith(compareByDescending<LomloeObservation> { it.dateEpochMs }.thenBy { it.title }.thenBy { it.text })
        val observations = allObservations.take(maxObservations.coerceAtLeast(0))

        val competencies = usedCompetencyIds
            .mapNotNull(competencyById::get)
            .distinctBy { it.code.trim().lowercase() }
            .sortedBy { it.code }
            .map { LomloeCompetencyRef(code = it.code.trim(), name = it.name.trim()) }

        return LomloeCommentEvidence(
            criterionResults = criterionResults,
            competencies = competencies,
            observations = observations,
            omittedCriterionResults = allResults.size - criterionResults.size,
            omittedObservations = allObservations.size - observations.size,
            periodApplied = period != null,
            termMetrics = period?.let {
                termAttendance(input, it).copy(
                    averageScore = termAverage?.value,
                    averagedColumnCount = termAverage?.columnCount ?: 0,
                )
            },
        )
    }

    /**
     * Con hueco limitado, primero un resultado por criterio distinto (el más reciente),
     * y solo después repeticiones del mismo criterio en otras evaluaciones.
     */
    private fun pickCriterionResults(sorted: List<LomloeCriterionResult>, max: Int): List<LomloeCriterionResult> {
        if (max <= 0) return emptyList()
        val firstPerCriterion = sorted.distinctBy { it.criterion.lowercase() }
        val rest = sorted - firstPerCriterion.toSet()
        return (firstPerCriterion + rest).take(max)
    }

    private fun isAiGeneratedColumn(column: NotebookColumnDefinition): Boolean =
        column.type == NotebookColumnType.TEXT &&
            column.instrumentKind == NotebookInstrumentKind.PRIVATE_COMMENT &&
            column.iconName == AI_COLUMN_ICON

    private fun cellHasContent(cell: PersistedNotebookCell): Boolean =
        !cell.textValue.isNullOrBlank() || cell.boolValue != null || !cell.iconValue.isNullOrBlank() ||
            !cell.ordinalValue.isNullOrBlank() || !cell.annotation?.note.isNullOrBlank()

    private fun cleanText(value: String?): String? =
        value?.split(Regex("\\s+"))?.filter { it.isNotEmpty() }?.joinToString(" ")?.takeIf { it.isNotEmpty() }
}

/**
 * Carga de los repositorios lo que necesita [LomloeCommentEvidenceBuilder] para un
 * alumno, grupo y trimestre. El trimestre se filtra con los periodos de evaluación
 * del horario docente; si no están configurados, se usa todo el curso y
 * `periodApplied` queda en `false`.
 */
class BuildLomloeCommentEvidenceUseCase(
    private val evaluations: EvaluationsRepository,
    private val rubrics: RubricsRepository,
    private val grades: GradesRepository,
    private val competencies: CompetenciesRepository,
    private val notebookConfig: NotebookConfigRepository,
    private val notebookCells: NotebookCellsRepository,
    private val incidents: IncidentsRepository,
    private val tutoring: StudentTutoringSessionRepository,
    private val schedules: TeacherScheduleRepository,
    private val classes: ClassesRepository,
    private val attendance: AttendanceRepository,
    /** El mismo motor de medias que el Cuaderno: así la media del trimestre es coherente con la pantalla. */
    private val notebookSheet: BuildNotebookSheetUseCase,
) {
    @Throws(Throwable::class)
    suspend fun invoke(
        classId: Long,
        studentId: Long,
        termKey: String,
        maxCriterionResults: Int = LomloeCommentEvidenceBuilder.DEFAULT_MAX_CRITERION_RESULTS,
        maxObservations: Int = LomloeCommentEvidenceBuilder.DEFAULT_MAX_OBSERVATIONS,
    ): LomloeCommentEvidence {
        // El listado de evaluaciones no trae sus competencias: se cargan aparte.
        val classEvaluations = evaluations.listClassEvaluations(classId).map { evaluation ->
            evaluation.copy(competencyLinks = evaluations.listEvaluationCompetencyLinks(evaluation.id))
        }
        val rubricIds = classEvaluations.mapNotNull { it.rubricId }.toSet()
        val classRubrics = if (rubricIds.isEmpty()) emptyList() else rubrics.listRubrics().filter { it.rubric.id in rubricIds }
        val assessments = classEvaluations
            .filter { it.rubricId != null }
            .flatMap { rubrics.listRubricAssessments(studentId, it.id) }
        // Solo lectura: no se crea un horario si el docente aún no tiene.
        val period = schedules.findExistingSchedule()
            ?.let { schedules.listEvaluationPeriods(it.id) }
            ?.let { LomloeCommentEvidenceBuilder.resolvePeriod(it, termKey) }
        val studentGrades = grades.listGradesForClass(classId).filter { it.studentId == studentId }
        val studentCells = notebookCells.listClassCells(classId).filter { it.studentId == studentId }
        val columns = notebookConfig.listColumns(classId)
        val input = LomloeEvidenceInput(
            studentId = studentId,
            evaluations = classEvaluations,
            rubrics = classRubrics,
            assessments = assessments,
            grades = studentGrades,
            competencies = competencies.listCompetencies(),
            columns = columns,
            cells = studentCells,
            incidents = incidents.listIncidents(classId).filter { it.studentId == studentId },
            tutoringSessions = tutoring.listByStudent(studentId),
            attendance = attendance.listAttendance(classId).filter { it.studentId == studentId },
        )
        return LomloeCommentEvidenceBuilder.build(
            input = input,
            period = period,
            maxCriterionResults = maxCriterionResults,
            maxObservations = maxObservations,
            termAverage = period?.let { termAverage(classId, studentId, input, it) },
        )
    }

    /** Media del Cuaderno del alumno, calculada solo con las columnas del trimestre. */
    private suspend fun termAverage(
        classId: Long,
        studentId: Long,
        input: LomloeEvidenceInput,
        period: LomloePeriod,
    ): LomloeTermAverage {
        val student = classes.listStudentsInClass(classId).firstOrNull { it.id == studentId }
            ?: return LomloeTermAverage()
        val selection = LomloeCommentEvidenceBuilder.selectNotebookForPeriod(input, period)
        val sheet = notebookSheet.build(
            classId = classId,
            evaluations = selection.evaluations,
            students = listOf(student),
            tabs = notebookConfig.listTabs(classId),
            configuredColumns = selection.columns,
            persistedGrades = input.grades,
            persistedCells = input.cells,
        )
        val row = sheet.rows.firstOrNull { it.student.id == studentId }
        return LomloeTermAverage(
            value = row?.weightedAverage,
            columnCount = row?.averageExplanation?.included?.size ?: 0,
        )
    }
}
