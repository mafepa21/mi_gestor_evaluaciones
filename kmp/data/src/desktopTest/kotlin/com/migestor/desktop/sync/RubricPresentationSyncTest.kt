package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RubricPresentationSyncTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun elDibujoLosCortesYElTiempoViajanYUnEquipoAntiguoNoLosBorra() = runTest {
        val origin = newContainer()
        val classId = origin.classesRepository.saveClass(name = "4 ESO A", course = 4)
        val studentId = origin.studentsRepository.saveStudent(firstName = "Prueba", lastName = "Uno")
        origin.classesRepository.addStudentToClass(classId, studentId)
        val rubricId = origin.rubricsRepository.saveRubric(name = "Hockey técnica", updatedAtEpochMs = 100L)
        val evaluationId = origin.evaluationsRepository.saveEvaluation(
            classId = classId, code = "RUB-$rubricId", name = "Hockey", type = "Rúbrica", weight = 1.0, rubricId = rubricId,
        )
        val criterionId = origin.rubricsRepository.saveCriterion(rubricId = rubricId, description = "Slalom", weight = 1.0, order = 0)
        val levelId = origin.rubricsRepository.saveLevel(criterionId = criterionId, name = "Nivel 3", points = 3, order = 2)
        origin.rubricsRepository.saveCriterionPresentation(criterionId, "hockey.dribble_flat_face", "lower;10.0;12.0;15.0")
        origin.rubricsRepository.saveRubricAssessment(studentId, evaluationId, criterionId, levelId, updatedAtEpochMs = 150L)
        origin.rubricsRepository.saveRubricAssessmentMeasurement(studentId, evaluationId, criterionId, 11.4)

        val changes = SqlDelightSyncAdapter(origin, localDeviceId = "mac").collectLocalChanges(0L)
        val bundle = changes.single { it.entity == "rubric_bundle" }
        val assessment = changes.single { it.entity == "rubric_assessment" }

        val target = newContainer()
        target.classesRepository.saveClass(id = classId, name = "4 ESO A", course = 4)
        target.studentsRepository.saveStudent(id = studentId, firstName = "Prueba", lastName = "Uno")
        target.evaluationsRepository.saveEvaluation(
            id = evaluationId, classId = classId, code = "RUB-$rubricId", name = "Hockey", type = "Rúbrica", weight = 1.0, rubricId = rubricId,
        )
        val adapter = SqlDelightSyncAdapter(target, localDeviceId = "ipad")
        adapter.applyIncomingChangesLww(listOf(bundle, assessment))

        val criterion = target.rubricsRepository.listCriteriaByRubric(rubricId).single()
        assertEquals("hockey.dribble_flat_face", criterion.visualKey)
        assertEquals("lower;10.0;12.0;15.0", criterion.timingConfig)
        assertEquals(11.4, target.rubricsRepository.listRubricAssessments(studentId, evaluationId).single().measuredValue)

        // Un equipo sin esta versión manda el criterio sin las claves nuevas.
        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "rubric_bundle",
                    id = rubricId.toString(),
                    updatedAtEpochMs = 300L,
                    deviceId = "viejo",
                    payload = """{"rubricId":$rubricId,"name":"Hockey técnica","criteria":[{"id":$criterionId,"description":"Slalom 5 conos","weight":1.0,"order":0}]}""",
                ),
            )
        )
        val kept = target.rubricsRepository.listCriteriaByRubric(rubricId).single()
        assertEquals("Slalom 5 conos", kept.description)
        assertEquals("hockey.dribble_flat_face", kept.visualKey)
        assertEquals("lower;10.0;12.0;15.0", kept.timingConfig)
    }

    @Test
    fun unaRubricaNuevaViajaConSuClaseYSuUnidad() = runTest {
        val origin = newContainer()
        val classId = origin.classesRepository.saveClass(name = "4 ESO A", course = 4)
        val rubricId = origin.rubricsRepository.saveRubric(name = "Hockey", classId = classId, updatedAtEpochMs = 100L)
        val sinClaseId = origin.rubricsRepository.saveRubric(name = "General", updatedAtEpochMs = 100L)

        val bundles = SqlDelightSyncAdapter(origin, localDeviceId = "mac").collectLocalChanges(0L)
            .filter { it.entity == "rubric_bundle" }
        // El iPad descarta una rúbrica nueva si el paquete no trae estas claves.
        bundles.forEach { bundle ->
            assertTrue("\"classId\"" in bundle.payload, bundle.payload)
            assertTrue("\"teachingUnitId\"" in bundle.payload, bundle.payload)
        }

        val target = newContainer()
        target.classesRepository.saveClass(id = classId, name = "4 ESO A", course = 4)
        SqlDelightSyncAdapter(target, localDeviceId = "ipad").applyIncomingChangesLww(bundles)

        assertEquals(classId, target.rubricsRepository.getRubricDetail(rubricId)?.rubric?.classId)
        assertEquals(null, target.rubricsRepository.getRubricDetail(sinClaseId)?.rubric?.classId)
    }
}
