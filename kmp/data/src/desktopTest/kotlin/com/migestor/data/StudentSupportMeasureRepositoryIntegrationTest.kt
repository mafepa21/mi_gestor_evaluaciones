package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.StudentSupportMeasureRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
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
}
