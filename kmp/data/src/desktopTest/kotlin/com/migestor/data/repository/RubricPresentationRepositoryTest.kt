package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.tableColumns
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Dibujos, cronómetro y marca medida de las rúbricas (migración 48). */
class RubricPresentationRepositoryTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun guardarElCriterioDeNuevoNoBorraElDibujoNiLosCortes() = runTest {
        val container = newContainer()
        val repo = container.rubricsRepository
        val rubricId = repo.saveRubric(name = "Hockey técnica")
        val criterionId = repo.saveCriterion(rubricId = rubricId, description = "Slalom", weight = 0.25, order = 0)
        repo.saveCriterionPresentation(criterionId, visualKey = "hockey.dribble_flat_face", timingConfig = "lower;10.0;12.0;15.0")

        repo.saveCriterion(id = criterionId, rubricId = rubricId, description = "Slalom 5 conos", weight = 0.25, order = 0)

        val criterion = repo.listCriteriaByRubric(rubricId).single()
        assertEquals("Slalom 5 conos", criterion.description)
        assertEquals("hockey.dribble_flat_face", criterion.visualKey)
        assertEquals("lower;10.0;12.0;15.0", criterion.timingConfig)
        val fromList = repo.listRubrics().single { it.rubric.id == rubricId }.criteria.single().criterion
        assertEquals("lower;10.0;12.0;15.0", fromList.timingConfig)

        repo.saveCriterionPresentation(criterionId, visualKey = null, timingConfig = " ")
        val cleared = repo.listCriteriaByRubric(rubricId).single()
        assertNull(cleared.visualKey)
        assertNull(cleared.timingConfig)
    }

    @Test
    fun laMarcaMedidaSobreviveACambiarElNivelAMano() = runTest {
        val container = newContainer()
        val repo = container.rubricsRepository
        val classId = container.classesRepository.saveClass(name = "4 ESO A", course = 4)
        val studentId = container.studentsRepository.saveStudent(firstName = "Prueba", lastName = "Uno")
        val evaluationId = container.evaluationsRepository.saveEvaluation(
            classId = classId, code = "RUB-1", name = "Hockey", type = "Rúbrica", weight = 1.0,
        )
        val rubricId = repo.saveRubric(name = "Hockey técnica")
        val criterionId = repo.saveCriterion(rubricId = rubricId, description = "Slalom", weight = 1.0, order = 0)
        val level3 = repo.saveLevel(criterionId = criterionId, name = "Nivel 3", points = 3, order = 2)
        val level4 = repo.saveLevel(criterionId = criterionId, name = "Nivel 4", points = 4, order = 3)

        repo.saveRubricAssessment(studentId, evaluationId, criterionId, level3, updatedAtEpochMs = 100L)
        repo.saveRubricAssessmentMeasurement(studentId, evaluationId, criterionId, 11.4)
        repo.saveRubricAssessment(studentId, evaluationId, criterionId, level4, updatedAtEpochMs = 200L)

        val assessment = repo.listRubricAssessments(studentId, evaluationId).single()
        assertEquals(level4, assessment.levelId)
        assertEquals(11.4, assessment.measuredValue)
    }

    @Test
    fun laMigracion48AnadeLasColumnasSinTocarLoGuardado() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        driver.execute(null, "CREATE TABLE rubric_criteria (id INTEGER PRIMARY KEY, rubric_id INTEGER NOT NULL, description TEXT NOT NULL, weight REAL NOT NULL)", 0)
        driver.execute(null, "INSERT INTO rubric_criteria VALUES (1, 1, 'Slalom', 1.0)", 0)

        AppDatabase.Schema.migrate(driver, 48, 49)

        assertTrue(tableColumns(driver, "rubric_criteria").containsAll(listOf("visual_key", "timing_config")))
        assertTrue("measured_value" in tableColumns(driver, "rubric_assessments"))
        assertEquals(1L, driver.scalarLong("SELECT COUNT(*) FROM rubric_criteria WHERE description = 'Slalom' AND visual_key IS NULL"))
    }
}
