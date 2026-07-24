package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.StudentSupportMeasureRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.data.repository.scalarLong
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.domain.SupportMeasureType
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class StudentSupportMeasureRepositoryIntegrationTest {
    @Test
    fun `saves, lists and retires a support measure without losing history`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val studentsRepo = StudentsRepositorySqlDelight(db)
        val measuresRepo = StudentSupportMeasureRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Ana", lastName = "Garcia", email = null)

        val measureId = measuresRepo.save(
            studentId = studentId,
            level = SupportMeasureLevel.IV,
            measureType = SupportMeasureType.ACIS,
            startDateIso = "2026-09-15",
            responsible = "Orientador",
            reviewDueIso = "2027-09-15",
        )

        assertTrue(measureId > 0)
        assertEquals(setOf(studentId), measuresRepo.listActiveStudentIds())

        var measures = measuresRepo.listByStudent(studentId)
        assertEquals(1, measures.size)
        assertTrue(measures.first().isActive)

        measuresRepo.retire(measureId, endDateIso = "2027-06-20")

        measures = measuresRepo.listByStudent(studentId)
        assertEquals(1, measures.size, "retirar no debe borrar el histórico")
        assertEquals(false, measures.first().isActive)
        assertEquals(true, measuresRepo.listActiveStudentIds().isEmpty())
    }

    @Test
    fun `ignores rows with a stale measure_type instead of crashing`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val studentsRepo = StudentsRepositorySqlDelight(db)
        val measuresRepo = StudentSupportMeasureRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Luis", lastName = "Perez", email = null)

        measuresRepo.save(
            studentId = studentId,
            level = SupportMeasureLevel.III,
            measureType = SupportMeasureType.APR_FORMATO_EXAMEN,
            startDateIso = "2026-09-15",
        )
        // Simula datos persistidos con un enum de una version anterior de la app
        // (catalogo genérico ya eliminado), como puede quedar en el dispositivo de un docente
        // tras actualizar. `listByStudent` no debe lanzar, debe descartar solo esa fila.
        db.appDatabaseQueries.upsertSupportMeasure(
            null, studentId, "III", "REFUERZO", "2026-09-01", null, null, null, "", null, null, 1, 0, 0, null, 0
        )

        val measures = measuresRepo.listByStudent(studentId)
        assertEquals(1, measures.size, "la fila con enum obsoleto debe descartarse, no crashear")
        assertEquals(SupportMeasureType.APR_FORMATO_EXAMEN, measures.first().measureType)
    }

    @Test
    fun `editing an existing measure preserves created_at and bumps sync_version`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val studentsRepo = StudentsRepositorySqlDelight(db)
        val measuresRepo = StudentSupportMeasureRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Marta", lastName = "Ruiz", email = null)

        val measureId = measuresRepo.save(
            studentId = studentId,
            level = SupportMeasureLevel.III,
            measureType = SupportMeasureType.APR_FORMATO_EXAMEN,
            startDateIso = "2026-09-15",
            createdAtEpochMs = 1_000L,
            updatedAtEpochMs = 1_000L,
            syncVersion = 1,
        )

        // Simula lo que envía KmpBridge al editar: createdAtEpochMs a 0 y syncVersion fijo a 1,
        // como si fuera un guardado nuevo. El repositorio debe ignorar esos valores para una
        // fila existente y preservar el created_at original, no resetearlo a 0.
        measuresRepo.save(
            id = measureId,
            studentId = studentId,
            level = SupportMeasureLevel.III,
            measureType = SupportMeasureType.APR_REVISION_EXAMEN,
            startDateIso = "2026-09-16",
            createdAtEpochMs = 0,
            updatedAtEpochMs = 2_000L,
            syncVersion = 1,
        )

        val createdAt = driver.scalarLong("SELECT created_at_epoch_ms FROM student_support_measures WHERE id = $measureId")
        val syncVersion = driver.scalarLong("SELECT sync_version FROM student_support_measures WHERE id = $measureId")
        assertEquals(1_000L, createdAt, "editar no debe resetear created_at_epoch_ms")
        assertEquals(2L, syncVersion, "editar debe incrementar sync_version, no fijarlo")

        val updated = measuresRepo.listByStudent(studentId).first()
        assertEquals(SupportMeasureType.APR_REVISION_EXAMEN, updated.measureType, "el campo editado sí debe cambiar")
    }

    @Test
    fun `editing a retired measure does not reactivate it`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val studentsRepo = StudentsRepositorySqlDelight(db)
        val measuresRepo = StudentSupportMeasureRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Pablo", lastName = "Diaz", email = null)

        val measureId = measuresRepo.save(
            studentId = studentId,
            level = SupportMeasureLevel.III,
            measureType = SupportMeasureType.APR_FORMATO_EXAMEN,
            startDateIso = "2026-09-15",
        )
        measuresRepo.retire(measureId, endDateIso = "2026-10-01")

        // Simula editar (p.ej. solo cambiar el responsable) una medida ya retirada: la fila
        // debe seguir retirada, no reactivarse por el `isActive = true` por defecto del draft.
        measuresRepo.save(
            id = measureId,
            studentId = studentId,
            level = SupportMeasureLevel.III,
            measureType = SupportMeasureType.APR_FORMATO_EXAMEN,
            startDateIso = "2026-09-15",
            responsible = "PT",
            isActive = true,
        )

        val isActive = driver.scalarLong("SELECT is_active FROM student_support_measures WHERE id = $measureId")
        val endDateIso = measuresRepo.listByStudent(studentId).first().endDate
        assertEquals(0L, isActive, "editar no debe reactivar una medida retirada")
        assertEquals(kotlinx.datetime.LocalDate.parse("2026-10-01"), endDateIso)
    }
}
