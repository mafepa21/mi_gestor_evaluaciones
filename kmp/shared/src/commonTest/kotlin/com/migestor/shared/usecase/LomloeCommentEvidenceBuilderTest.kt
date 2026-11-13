package com.migestor.shared.usecase

import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.CompetencyCriterion
import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.EvaluationCompetencyLink
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.NotebookCellAnnotation
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.PlannerEvaluationPeriod
import com.migestor.shared.domain.Rubric
import com.migestor.shared.domain.RubricAssessment
import com.migestor.shared.domain.RubricCriterion
import com.migestor.shared.domain.RubricCriterionWithLevels
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.domain.RubricLevel
import com.migestor.shared.domain.StudentTutoringSession
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LomloeCommentEvidenceBuilderTest {
    private val ana = 1L
    private val luis = 2L

    private fun at(ms: Long) = AuditTrace(createdAt = Instant.fromEpochMilliseconds(ms), updatedAt = Instant.fromEpochMilliseconds(ms))

    private fun criterion(id: Long, text: String, competencyId: Long? = null) = RubricCriterionWithLevels(
        criterion = RubricCriterion(id = id, rubricId = 10, description = text, weight = 1.0, order = id.toInt(), competencyId = competencyId),
        levels = listOf(
            RubricLevel(id = id * 10 + 1, criterionId = id, name = "Iniciado", points = 1, description = "Necesita ayuda constante", order = 0),
            RubricLevel(id = id * 10 + 2, criterionId = id, name = "Avanzado", points = 4, description = "  Lo hace con   autonomía ", order = 1),
        ),
    )

    private val competencies = listOf(
        CompetencyCriterion(id = 100, code = "CE2", name = "Resolución de problemas"),
        CompetencyCriterion(id = 101, code = "CE4", name = "Trabajo en equipo"),
        CompetencyCriterion(id = 102, code = "CE5", name = "No trabajada"),
    )
    private val rubric = RubricDetail(
        rubric = Rubric(id = 10, name = "Proyecto"),
        criteria = listOf(criterion(1, "Plantea el problema", competencyId = 100), criterion(2, "Coopera con el grupo")),
    )
    private val project = Evaluation(
        id = 50, classId = 7, code = "PRO", name = "Proyecto del río", type = "rubric", rubricId = 10,
        competencyLinks = listOf(EvaluationCompetencyLink(id = 1, evaluationId = 50, competencyId = 101)),
    )
    private val exam = Evaluation(
        id = 51, classId = 7, code = "EX", name = "Prueba escrita", type = "exam",
        competencyLinks = listOf(EvaluationCompetencyLink(id = 2, evaluationId = 51, competencyId = 100)),
    )

    private fun assessment(studentId: Long, criterionId: Long, levelId: Long, ms: Long, evaluationId: Long = 50) =
        RubricAssessment(studentId = studentId, evaluationId = evaluationId, criterionId = criterionId, levelId = levelId, trace = at(ms))

    private fun textColumn(id: String, title: String, icon: String? = null, kind: NotebookInstrumentKind = NotebookInstrumentKind.SYSTEMATIC_OBSERVATION) =
        NotebookColumnDefinition(id = id, title = title, type = NotebookColumnType.TEXT, instrumentKind = kind, iconName = icon)

    @Test
    fun elResultadoPorCriterioLlevaNivelDescriptorYCompetenciasReales() {
        val evidence = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(
                studentId = ana,
                evaluations = listOf(project, exam),
                rubrics = listOf(rubric),
                assessments = listOf(assessment(ana, 1, 12, 2_000), assessment(ana, 2, 21, 1_000), assessment(luis, 1, 11, 3_000)),
                competencies = competencies,
            ),
        )

        assertEquals(2, evidence.criterionResults.size)
        val first = evidence.criterionResults.first()
        // Lo más reciente primero, y solo lo de Ana.
        assertEquals("Plantea el problema", first.criterion)
        assertEquals("Proyecto del río", first.evaluationName)
        assertEquals("Avanzado", first.levelName)
        assertEquals("Lo hace con   autonomía", first.levelDescription)
        assertEquals(4, first.points)
        assertEquals(4, first.maxPoints)
        // Competencia del criterio y de la evaluación.
        assertEquals(listOf("CE2", "CE4"), first.competencyCodes)
        assertEquals(listOf("CE4"), evidence.criterionResults.last().competencyCodes)
        // Solo las realmente trabajadas: CE5 no aparece.
        assertEquals(listOf("CE2", "CE4"), evidence.competencies.map { it.code })
        assertEquals(0, evidence.omittedCriterionResults)
        assertFalse(evidence.periodApplied)
    }

    @Test
    fun unaNotaEnElPeriodoTambienCuentaSuCompetencia() {
        val evidence = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(
                studentId = ana,
                evaluations = listOf(exam),
                grades = listOf(
                    Grade(id = 1, classId = 7, studentId = ana, columnId = "c", evaluationId = 51, value = 6.5, trace = at(1_500)),
                    // Sin valor no cuenta como trabajada.
                    Grade(id = 2, classId = 7, studentId = ana, columnId = "d", evaluationId = 50, value = null, trace = at(1_500)),
                ),
                competencies = competencies,
            ),
        )
        assertEquals(listOf(LomloeCompetencyRef("CE2", "Resolución de problemas")), evidence.competencies)
        assertTrue(evidence.criterionResults.isEmpty())
    }

    @Test
    fun recogeTextosDelCuadernoIncidenciasYAcuerdosPeroNoLoGeneradoPorIA() {
        val evidence = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(
                studentId = ana,
                columns = listOf(
                    textColumn("obs", "Observación diaria"),
                    textColumn("ia", "Comentario IA", icon = LomloeCommentEvidenceBuilder.AI_COLUMN_ICON, kind = NotebookInstrumentKind.PRIVATE_COMMENT),
                    NotebookColumnDefinition(id = "nota", title = "Examen T1", type = NotebookColumnType.NUMERIC, competencyCriteriaIds = listOf(101)),
                ),
                cells = listOf(
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "obs", textValue = "  Ayuda a   sus compañeros ", trace = at(4_000)),
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "ia", textValue = "Texto generado antes", trace = at(5_000)),
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "nota", textValue = "7", annotation = NotebookCellAnnotation(note = "Mejoró mucho la presentación"), trace = at(3_000)),
                    PersistedNotebookCell(classId = 7, studentId = luis, columnId = "obs", textValue = "De otro alumno", trace = at(6_000)),
                ),
                incidents = listOf(
                    Incident(id = 1, classId = 7, studentId = ana, title = "Olvida el material", detail = "Tercera vez este mes", date = Instant.fromEpochMilliseconds(2_000)),
                    Incident(id = 2, classId = 7, studentId = null, title = "Del grupo entero", date = Instant.fromEpochMilliseconds(2_500)),
                ),
                tutoringSessions = listOf(
                    StudentTutoringSession(id = 1, studentId = ana, date = LocalDate(1970, 1, 1), topics = "Tema privado de la familia", agreements = "Revisar la agenda cada tarde"),
                ),
                competencies = competencies,
            ),
        )

        assertEquals(
            listOf("Ayuda a sus compañeros", "Mejoró mucho la presentación", "Tercera vez este mes", "Revisar la agenda cada tarde"),
            evidence.observations.map { it.text },
        )
        assertEquals(
            listOf(LomloeObservationSource.NOTEBOOK, LomloeObservationSource.NOTEBOOK, LomloeObservationSource.INCIDENT, LomloeObservationSource.TUTORING),
            evidence.observations.map { it.source },
        )
        assertEquals("Examen T1", evidence.observations[1].title)
        // Ni lo generado por IA ni los temas tratados con la familia llegan a la evidencia.
        assertTrue(evidence.observations.none { "generado" in it.text || "privado" in it.text })
        // La columna con contenido aporta su competencia.
        assertEquals(listOf("CE4"), evidence.competencies.map { it.code })
    }

    @Test
    fun elTrimestreFiltraPorFechaYLoSinFechaNoSePierde() {
        val period = LomloePeriod(startEpochMs = 1_000, endEpochMs = 2_000)
        val evidence = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(
                studentId = ana,
                evaluations = listOf(project),
                rubrics = listOf(rubric),
                assessments = listOf(assessment(ana, 1, 12, 1_500), assessment(ana, 2, 21, 2_500)),
                columns = listOf(textColumn("obs", "Observación"), textColumn("sin", "Sin fecha")),
                cells = listOf(
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "obs", textValue = "Fuera del trimestre", observedAtEpochMs = 9_000, trace = at(1_500)),
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "sin", textValue = "Sin fecha conocida", trace = at(0)),
                ),
                incidents = listOf(
                    Incident(id = 1, classId = 7, studentId = ana, title = "Dentro", date = Instant.fromEpochMilliseconds(2_000)),
                    Incident(id = 2, classId = 7, studentId = ana, title = "Después", date = Instant.fromEpochMilliseconds(2_001)),
                ),
                competencies = competencies,
            ),
            period = period,
        )
        assertTrue(evidence.periodApplied)
        assertEquals(listOf("Plantea el problema"), evidence.criterionResults.map { it.criterion })
        assertEquals(listOf("Dentro", "Sin fecha conocida"), evidence.observations.map { it.text })
    }

    @Test
    fun conPocoHuecoPriorizaCriteriosDistintosYCuentaLoOmitido() {
        val evaluations = listOf(project, project.copy(id = 60, name = "Proyecto del bosque"))
        val evidence = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(
                studentId = ana,
                evaluations = evaluations,
                rubrics = listOf(rubric),
                assessments = listOf(
                    assessment(ana, 1, 12, 5_000, evaluationId = 60),
                    assessment(ana, 1, 11, 4_000, evaluationId = 50),
                    assessment(ana, 2, 22, 1_000, evaluationId = 50),
                ),
                columns = listOf(textColumn("a", "A"), textColumn("b", "B"), textColumn("c", "C")),
                cells = listOf(
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "a", textValue = "Muy participativa", trace = at(3_000)),
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "b", textValue = "muy participativa", trace = at(2_000)),
                    PersistedNotebookCell(classId = 7, studentId = ana, columnId = "c", textValue = "Entrega tarde", trace = at(1_000)),
                ),
            ),
            maxCriterionResults = 2,
            maxObservations = 1,
        )
        // El criterio 2 entra antes que la repetición más antigua del criterio 1.
        assertEquals(listOf("Plantea el problema", "Coopera con el grupo"), evidence.criterionResults.map { it.criterion })
        assertEquals("Proyecto del bosque", evidence.criterionResults.first().evaluationName)
        assertEquals(1, evidence.omittedCriterionResults)
        // El texto repetido solo cuenta una vez.
        assertEquals(listOf("Muy participativa"), evidence.observations.map { it.text })
        assertEquals(1, evidence.omittedObservations)
    }

    @Test
    fun sinDatosLaEvidenciaQuedaVaciaYNoFalla() {
        val evidence = LomloeCommentEvidenceBuilder.build(LomloeEvidenceInput(studentId = ana))
        assertTrue(evidence.isEmpty)
        // Valoración con criterio o nivel que ya no existe: se ignora.
        val huerfana = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(studentId = ana, evaluations = listOf(project), rubrics = listOf(rubric), assessments = listOf(assessment(ana, 99, 1, 1), assessment(ana, 1, 999, 1))),
        )
        assertTrue(huerfana.criterionResults.isEmpty())
    }

    @Test
    fun elTrimestreSaleDeLosPeriodosDelHorarioPorOrden() {
        val periods = listOf(
            PlannerEvaluationPeriod(id = 2, teacherScheduleId = 1, name = "Segunda", startDateIso = "2026-12-23", endDateIso = "2027-03-20", sortOrder = 1),
            PlannerEvaluationPeriod(id = 1, teacherScheduleId = 1, name = "Primera", startDateIso = "2026-09-10", endDateIso = "2026-12-22", sortOrder = 0),
        )
        val first = assertNotNull(LomloeCommentEvidenceBuilder.resolvePeriod(periods, "T1", TimeZone.UTC))
        assertEquals(Instant.parse("2026-09-10T00:00:00Z").toEpochMilliseconds(), first.startEpochMs)
        assertEquals(Instant.parse("2026-12-22T23:59:59.999Z").toEpochMilliseconds(), first.endEpochMs)
        assertEquals(
            Instant.parse("2026-12-23T00:00:00Z").toEpochMilliseconds(),
            LomloeCommentEvidenceBuilder.resolvePeriod(periods, "T2", TimeZone.UTC)?.startEpochMs,
        )
        // Sin tercer periodo, con clave rara o con fechas ilegibles no se filtra.
        assertNull(LomloeCommentEvidenceBuilder.resolvePeriod(periods, "T3", TimeZone.UTC))
        assertNull(LomloeCommentEvidenceBuilder.resolvePeriod(periods, "X_final", TimeZone.UTC))
        assertNull(LomloeCommentEvidenceBuilder.resolvePeriod(listOf(periods[1].copy(startDateIso = "ayer")), "T1", TimeZone.UTC))
        assertNull(LomloeCommentEvidenceBuilder.resolvePeriod(emptyList(), "T1", TimeZone.UTC))
    }

    // --- Cifras del trimestre (media y asistencia) ---

    private val term = LomloePeriod(startEpochMs = 1_000, endEpochMs = 2_000)

    private fun attendance(id: Long, studentId: Long, ms: Long, status: String) =
        Attendance(id = id, studentId = studentId, classId = 7, date = Instant.fromEpochMilliseconds(ms), status = status)

    private fun grade(studentId: Long, columnId: String, evaluationId: Long?, ms: Long) =
        Grade(id = ms, classId = 7, studentId = studentId, columnId = columnId, evaluationId = evaluationId, value = 7.0, trace = at(ms))

    @Test
    fun laAsistenciaDelTrimestreSoloCuentaRegistrosDelAlumnoDentroDelPeriodo() {
        val metrics = assertNotNull(
            LomloeCommentEvidenceBuilder.build(
                LomloeEvidenceInput(
                    studentId = ana,
                    attendance = listOf(
                        attendance(1, ana, 1_500, "PRESENTE"),
                        attendance(2, ana, 1_600, "Presente"),
                        attendance(3, ana, 1_700, "AUSENTE"),
                        attendance(4, ana, 1_800, "TARDE"),
                        // Fuera del periodo y de otro alumno: no cuentan.
                        attendance(5, ana, 500, "AUSENTE"),
                        attendance(6, ana, 2_500, "AUSENTE"),
                        attendance(7, luis, 1_500, "AUSENTE"),
                    ),
                ),
                period = term,
            ).termMetrics,
        )
        assertEquals(4, metrics.attendanceRecords)
        assertEquals(2, metrics.presentRecords)
        assertEquals(50.0, metrics.attendanceRate)
    }

    @Test
    fun sinRegistrosDeAsistenciaEnElPeriodoLaTasaEsNulaYNoSeRellenaConElCurso() {
        val metrics = assertNotNull(
            LomloeCommentEvidenceBuilder.build(
                LomloeEvidenceInput(studentId = ana, attendance = listOf(attendance(1, ana, 5_000, "PRESENTE"))),
                period = term,
            ).termMetrics,
        )
        assertNull(metrics.attendanceRate)
        assertEquals(0, metrics.attendanceRecords)
    }

    @Test
    fun unRegistroDeAsistenciaSinFechaNoSeDescarta() {
        val metrics = assertNotNull(
            LomloeCommentEvidenceBuilder.build(
                LomloeEvidenceInput(studentId = ana, attendance = listOf(attendance(1, ana, 0, "PRESENTE"))),
                period = term,
            ).termMetrics,
        )
        assertEquals(100.0, metrics.attendanceRate)
    }

    @Test
    fun sinPeriodoNoHayCifrasDeTrimestreYSeUsaTodoElCurso() {
        val evidence = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(studentId = ana, attendance = listOf(attendance(1, ana, 1_500, "PRESENTE"))),
            period = null,
            termAverage = LomloeTermAverage(value = 8.0, columnCount = 1),
        )
        assertFalse(evidence.periodApplied)
        assertNull(evidence.termMetrics)
    }

    @Test
    fun laMediaDelTrimestreSeCopiaDelMotorDelCuadernoYSinNotasEsNula() {
        val withAverage = LomloeCommentEvidenceBuilder.build(
            LomloeEvidenceInput(studentId = ana),
            period = term,
            termAverage = LomloeTermAverage(value = 6.5, columnCount = 3),
        )
        assertEquals(6.5, withAverage.termMetrics?.averageScore)
        assertEquals(3, withAverage.termMetrics?.averagedColumnCount)
        // Sin notas en el periodo: periodo aplicado, pero media nula.
        val noGrades = LomloeCommentEvidenceBuilder.build(LomloeEvidenceInput(studentId = ana), period = term)
        assertTrue(noGrades.periodApplied)
        assertNull(assertNotNull(noGrades.termMetrics).averageScore)
    }

    @Test
    fun laMediaSoloUsaLasColumnasDelTrimestreSegunFechaDeColumnaONota() {
        val inTerm = NotebookColumnDefinition(id = "c_in", title = "Dentro", type = NotebookColumnType.NUMERIC, dateEpochMs = 1_500)
        val outOfTerm = NotebookColumnDefinition(id = "c_out", title = "Fuera", type = NotebookColumnType.NUMERIC, dateEpochMs = 5_000)
        // Sin fecha de columna: manda la última modificación de la nota del alumno.
        val gradedIn = NotebookColumnDefinition(id = "eval_50", title = "Proyecto", type = NotebookColumnType.NUMERIC, evaluationId = 50)
        val gradedOut = NotebookColumnDefinition(id = "eval_51", title = "Prueba", type = NotebookColumnType.NUMERIC, evaluationId = 51)
        // Sin fecha de columna ni nota: no se descarta.
        val undated = NotebookColumnDefinition(id = "c_undated", title = "Sin fecha", type = NotebookColumnType.NUMERIC)
        val selection = LomloeCommentEvidenceBuilder.selectNotebookForPeriod(
            LomloeEvidenceInput(
                studentId = ana,
                evaluations = listOf(project, exam),
                columns = listOf(inTerm, outOfTerm, gradedIn, gradedOut, undated),
                grades = listOf(
                    grade(ana, "eval_50", 50, 1_200),
                    grade(ana, "eval_51", 51, 9_000),
                    // La nota de otro alumno no mueve la fecha del alumno.
                    grade(luis, "eval_51", 51, 1_200),
                ),
            ),
            term,
        )
        assertEquals(listOf("c_in", "eval_50", "c_undated"), selection.columns.map { it.id })
        assertEquals(listOf(50L), selection.evaluations.map { it.id })
    }

    @Test
    fun unaEvaluacionSinColumnaConfiguradaUsaLaFechaDeSuNota() {
        val selection = LomloeCommentEvidenceBuilder.selectNotebookForPeriod(
            LomloeEvidenceInput(
                studentId = ana,
                evaluations = listOf(project, exam),
                grades = listOf(grade(ana, "eval_50", 50, 1_200), grade(ana, "eval_51", 51, 3_000)),
            ),
            term,
        )
        assertEquals(listOf(50L), selection.evaluations.map { it.id })
    }
}
