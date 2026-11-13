package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.PlannerEvaluationPeriod
import com.migestor.shared.usecase.LomloeObservationSource
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Evidencia del Comentario LOMLOE leída de repositorios reales (issue #407, parte A). */
class BuildLomloeCommentEvidenceIntegrationTest {

    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun day(iso: String): Long = LocalDate.parse(iso).atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds()

    @Test
    fun `lee criterios, competencias y observaciones del alumno y filtra por trimestre`() = runTest {
        val c = newContainer()
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val luis = c.studentsRepository.saveStudent(firstName = "Luis", lastName = "Pérez")
        val classId = c.classesRepository.saveClass(name = "1ºA", course = 1)

        val ce2 = c.competenciesRepository.saveCompetency(code = "CE2", name = "Resolución de problemas")
        c.competenciesRepository.saveCompetency(code = "CE5", name = "No trabajada")

        val rubricId = c.rubricsRepository.saveRubric(name = "Proyecto")
        val criterionId = c.rubricsRepository.saveCriterion(rubricId = rubricId, description = "Plantea el problema", weight = 1.0, order = 0)
        c.rubricsRepository.saveLevel(criterionId = criterionId, name = "Iniciado", points = 1, order = 0)
        val advanced = c.rubricsRepository.saveLevel(criterionId = criterionId, name = "Avanzado", points = 4, description = "Lo hace con autonomía", order = 1)
        val evaluationId = c.evaluationsRepository.saveEvaluation(
            classId = classId, code = "PRO", name = "Proyecto del río", type = "rubric", weight = 1.0, rubricId = rubricId,
        )
        c.evaluationsRepository.saveEvaluationCompetencyLink(evaluationId = evaluationId, competencyId = ce2)

        c.rubricsRepository.saveRubricAssessment(ana, evaluationId, criterionId, advanced, updatedAtEpochMs = day("2026-10-15"))
        c.rubricsRepository.saveRubricAssessment(luis, evaluationId, criterionId, advanced, updatedAtEpochMs = day("2026-10-15"))

        c.incidentsRepository.saveIncident(classId = classId, studentId = ana, title = "Olvida el material", detail = "Tercera vez este mes", dateEpochMs = day("2026-11-03"))
        c.incidentsRepository.saveIncident(classId = classId, studentId = ana, title = "Del segundo trimestre", detail = "No debe salir", dateEpochMs = day("2027-02-01"))
        c.incidentsRepository.saveIncident(classId = classId, studentId = luis, title = "De otro alumno", dateEpochMs = day("2026-11-03"))
        c.studentTutoringSessionRepository.save(studentId = ana, dateIso = "2026-11-10", topics = "Tema privado", agreements = "Revisar la agenda cada tarde")

        // Sin periodos configurados: se usa todo el curso y se indica.
        val wholeYear = c.buildLomloeCommentEvidence.invoke(classId, ana, "T1")
        assertFalse(wholeYear.periodApplied)
        assertEquals(3, wholeYear.observations.size)

        val schedule = c.teacherScheduleRepository.getOrCreatePrimarySchedule()
        c.teacherScheduleRepository.saveEvaluationPeriod(
            PlannerEvaluationPeriod(teacherScheduleId = schedule.id, name = "Primera", startDateIso = "2026-09-08", endDateIso = "2026-12-20", sortOrder = 0),
        )

        val evidence = c.buildLomloeCommentEvidence.invoke(classId, ana, "T1")
        assertTrue(evidence.periodApplied)

        val result = evidence.criterionResults.single()
        assertEquals("Plantea el problema", result.criterion)
        assertEquals("Proyecto del río", result.evaluationName)
        assertEquals("Avanzado", result.levelName)
        assertEquals("Lo hace con autonomía", result.levelDescription)
        assertEquals(4, result.maxPoints)
        assertEquals(listOf("CE2"), result.competencyCodes)
        assertEquals(listOf("CE2"), evidence.competencies.map { it.code })

        assertEquals(listOf("Revisar la agenda cada tarde", "Tercera vez este mes"), evidence.observations.map { it.text })
        assertEquals(listOf(LomloeObservationSource.TUTORING, LomloeObservationSource.INCIDENT), evidence.observations.map { it.source })

        // Un trimestre sin periodo definido no filtra: mejor todo que nada.
        assertFalse(c.buildLomloeCommentEvidence.invoke(classId, ana, "T3").periodApplied)
    }

    @Test
    fun `media y asistencia del trimestre salen del motor del Cuaderno y solo del periodo`() = runTest {
        val c = newContainer()
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val luis = c.studentsRepository.saveStudent(firstName = "Luis", lastName = "Pérez")
        val classId = c.classesRepository.saveClass(name = "1ºA", course = 1)
        c.classesRepository.addStudentToClass(classId = classId, studentId = ana)
        c.classesRepository.addStudentToClass(classId = classId, studentId = luis)

        // Media ponderada del Cuaderno: (8 x 3 + 4 x 1) / 4 = 7,0 (la media simple sería 6,0).
        val examen = c.evaluationsRepository.saveEvaluation(classId = classId, code = "EX", name = "Examen", type = "exam", weight = 3.0)
        val tarea = c.evaluationsRepository.saveEvaluation(classId = classId, code = "TA", name = "Tarea", type = "task", weight = 1.0)
        val segundoTrimestre = c.evaluationsRepository.saveEvaluation(classId = classId, code = "T2", name = "Del segundo", type = "exam", weight = 1.0)
        c.gradesRepository.saveGrade(classId = classId, studentId = ana, columnId = "eval_$examen", evaluationId = examen, value = 8.0, updatedAtEpochMs = day("2026-10-20"))
        c.gradesRepository.saveGrade(classId = classId, studentId = ana, columnId = "eval_$tarea", evaluationId = tarea, value = 4.0, updatedAtEpochMs = day("2026-11-05"))
        c.gradesRepository.saveGrade(classId = classId, studentId = ana, columnId = "eval_$segundoTrimestre", evaluationId = segundoTrimestre, value = 0.0, updatedAtEpochMs = day("2027-02-10"))
        c.gradesRepository.saveGrade(classId = classId, studentId = luis, columnId = "eval_$examen", evaluationId = examen, value = 1.0, updatedAtEpochMs = day("2026-10-20"))

        // Asistencia de Ana: 3 presentes y 1 ausente en el trimestre; 2 ausencias fuera de él.
        listOf("2026-09-15" to "PRESENTE", "2026-10-01" to "PRESENTE", "2026-10-02" to "PRESENTE", "2026-11-04" to "AUSENTE", "2027-01-20" to "AUSENTE", "2027-02-02" to "AUSENTE")
            .forEach { (date, status) ->
                c.attendanceRepository.saveAttendance(studentId = ana, classId = classId, dateEpochMs = day(date), status = status)
            }
        c.attendanceRepository.saveAttendance(studentId = luis, classId = classId, dateEpochMs = day("2026-10-01"), status = "AUSENTE")

        // Sin periodo configurado: sin cifras de trimestre, se mantiene el curso.
        val wholeYear = c.buildLomloeCommentEvidence.invoke(classId, ana, "T1")
        assertFalse(wholeYear.periodApplied)
        assertNull(wholeYear.termMetrics)

        val schedule = c.teacherScheduleRepository.getOrCreatePrimarySchedule()
        c.teacherScheduleRepository.saveEvaluationPeriod(
            PlannerEvaluationPeriod(teacherScheduleId = schedule.id, name = "Primera", startDateIso = "2026-09-08", endDateIso = "2026-12-20", sortOrder = 0),
        )
        c.teacherScheduleRepository.saveEvaluationPeriod(
            PlannerEvaluationPeriod(teacherScheduleId = schedule.id, name = "Segunda", startDateIso = "2027-01-08", endDateIso = "2027-03-20", sortOrder = 1),
        )

        val first = assertNotNull(c.buildLomloeCommentEvidence.invoke(classId, ana, "T1").termMetrics)
        assertEquals(7.0, assertNotNull(first.averageScore), 0.0001)
        assertEquals(2, first.averagedColumnCount)
        assertEquals(4, first.attendanceRecords)
        assertEquals(3, first.presentRecords)
        assertEquals(75.0, assertNotNull(first.attendanceRate), 0.0001)

        // Coherente con el Cuaderno: mismo motor, solo las dos evaluaciones del trimestre.
        val students = c.classesRepository.listStudentsInClass(classId)
        val sheet = c.buildNotebookSheet.build(
            classId = classId,
            evaluations = c.evaluationsRepository.listClassEvaluations(classId).filter { it.id != segundoTrimestre },
            students = students,
            tabs = emptyList(),
            configuredColumns = emptyList(),
        )
        assertEquals(sheet.rows.first { it.student.id == ana }.weightedAverage, first.averageScore)

        val second = assertNotNull(c.buildLomloeCommentEvidence.invoke(classId, ana, "T2").termMetrics)
        assertEquals(0.0, assertNotNull(second.averageScore), 0.0001)
        assertEquals(2, second.attendanceRecords)
        assertEquals(0.0, assertNotNull(second.attendanceRate), 0.0001)

        // Un alumno sin notas ni asistencia en el trimestre: cifras nulas, no las del curso.
        val sinDatos = c.studentsRepository.saveStudent(firstName = "Eva", lastName = "Sola")
        c.classesRepository.addStudentToClass(classId = classId, studentId = sinDatos)
        val empty = assertNotNull(c.buildLomloeCommentEvidence.invoke(classId, sinDatos, "T1").termMetrics)
        assertNull(empty.averageScore)
        assertNull(empty.attendanceRate)
    }
}
