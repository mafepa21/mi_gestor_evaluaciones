package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookTab
import kotlinx.coroutines.test.runTest
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** La IA cita la nota de evaluación (por bloques), la misma del Resumen. Datos inventados. */
class LomloeEvaluationAverageTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun numeric(id: String, tab: String, weight: Double) = NotebookColumnDefinition(
        id = id, title = id, type = NotebookColumnType.NUMERIC, weight = weight, tabIds = listOf(tab),
    )

    @Test
    fun laEvidenciaTraeLaNotaDeEvaluacionDelTrimestre() = runTest {
        val c = newContainer()
        val classId = c.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "Inventada")
        c.classesRepository.addStudentToClass(classId, ana)
        val config = c.notebookConfigRepository
        config.saveTab(classId, NotebookTab(id = "ev1", title = "1.ª Evaluación", order = 0, trace = AuditTrace()))
        config.saveTab(classId, NotebookTab(id = "hockey", title = "Hockey", order = 0, parentTabId = "ev1", weight = 60.0, trace = AuditTrace()))
        config.saveTab(classId, NotebookTab(id = "ultimate", title = "Ultimate", order = 1, parentTabId = "ev1", weight = 40.0, trace = AuditTrace()))
        val grades = mapOf(
            numeric("conduccion", "hockey", 33.0) to 8.0,
            numeric("pase", "hockey", 33.0) to 7.0,
            numeric("partido", "hockey", 33.0) to 7.5,
            numeric("lanzamiento", "ultimate", 30.0) to 6.0,
            numeric("recepcion", "ultimate", 30.0) to 6.0,
            numeric("tactica", "ultimate", 30.0) to 5.0,
            numeric("actitud", "ultimate", 10.0) to 9.0,
        )
        grades.forEach { (column, value) ->
            config.saveColumn(classId, column)
            c.gradesRepository.saveGrade(classId = classId, studentId = ana, columnId = column.id, evaluationId = null, value = value)
        }

        val evidence = c.buildLomloeCommentEvidence.invoke(classId = classId, studentId = ana, termKey = "T1")
        val average = evidence.evaluationAverage
        assertTrue(average != null && abs(average - 6.9) < 0.001, "esperaba 6,9 y salió $average")

        // Otro trimestre sin pestaña de evaluación: sin nota de evaluación.
        assertNull(c.buildLomloeCommentEvidence.invoke(classId = classId, studentId = ana, termKey = "T2").evaluationAverage)
    }
}
