package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SyncDatasetFingerprint
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class SyncDatasetFingerprintTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun `mismo dataset produce exactamente el mismo digest`() = runTest {
        val c1 = newContainer()
        val c2 = newContainer()

        val fixedEpoch = 1700000000000L
        c1.academicYearsRepository.upsertAcademicYear(
            id = 1L, centerId = 1L, name = "2026-2027", startEpochMs = 1000L, endEpochMs = 2000L,
            status = "ACTIVE", isActive = true, archivedAtEpochMs = null, updatedAtEpochMs = fixedEpoch, deviceId = "test", syncVersion = 1L
        )
        c1.classesRepository.saveClass(
            id = 1L, name = "1 ESO A", course = 1, description = null, centerId = 1L, academicYearId = 1L,
            stageCycleId = null, subjectId = null, updatedAtEpochMs = fixedEpoch, deviceId = "test", syncVersion = 1L
        )
        c1.studentsRepository.saveStudent(
            id = 1L, firstName = "Marc", lastName = "García", email = null, photoPath = null, isInjured = false,
            updatedAtEpochMs = fixedEpoch, deviceId = "test", syncVersion = 1L
        )
        c1.classesRepository.addStudentToClass(classId = 1L, studentId = 1L)

        c2.academicYearsRepository.upsertAcademicYear(
            id = 1L, centerId = 1L, name = "2026-2027", startEpochMs = 1000L, endEpochMs = 2000L,
            status = "ACTIVE", isActive = true, archivedAtEpochMs = null, updatedAtEpochMs = fixedEpoch, deviceId = "test", syncVersion = 1L
        )
        c2.classesRepository.saveClass(
            id = 1L, name = "1 ESO A", course = 1, description = null, centerId = 1L, academicYearId = 1L,
            stageCycleId = null, subjectId = null, updatedAtEpochMs = fixedEpoch, deviceId = "test", syncVersion = 1L
        )
        c2.studentsRepository.saveStudent(
            id = 1L, firstName = "Marc", lastName = "García", email = null, photoPath = null, isInjured = false,
            updatedAtEpochMs = fixedEpoch, deviceId = "test", syncVersion = 1L
        )
        c2.classesRepository.addStudentToClass(classId = 1L, studentId = 1L)

        val fp1 = SyncDatasetFingerprint.compute(c1)
        val fp2 = SyncDatasetFingerprint.compute(c2)

        assertEquals(fp1.schemaVersion, fp2.schemaVersion)
        assertEquals(fp1.countsByEntity, fp2.countsByEntity)
        assertEquals(fp1.digest, fp2.digest)
    }

    @Test
    fun `un cambio en un registro cambia el digest`() = runTest {
        val c1 = newContainer()
        val c2 = newContainer()

        c1.classesRepository.saveClass(name = "1 ESO A", course = 1)
        c2.classesRepository.saveClass(name = "1 ESO B", course = 1)

        val fp1 = SyncDatasetFingerprint.compute(c1)
        val fp2 = SyncDatasetFingerprint.compute(c2)

        assertEquals(fp1.countsByEntity, fp2.countsByEntity)
        assertNotEquals(fp1.digest, fp2.digest)
    }

    @Test
    fun `orden de insercion irrelevante para el calculo del digest`() {
        val recordsA = listOf(
            "student:1:1000",
            "class:2:2000",
            "evaluation:3:3000"
        )
        val recordsB = listOf(
            "evaluation:3:3000",
            "student:1:1000",
            "class:2:2000"
        )

        val digestA = SyncDatasetFingerprint.computeDigest(recordsA)
        val digestB = SyncDatasetFingerprint.computeDigest(recordsB)

        assertEquals(digestA, digestB)
    }

    @Test
    fun `toJson genera estructura json correcta`() = runTest {
        val c = newContainer()
        c.classesRepository.saveClass(name = "1 ESO A", course = 1)

        val fp = SyncDatasetFingerprint.compute(c)
        val json = fp.toJson()

        assertTrue(json.contains("\"schemaVersion\":${fp.schemaVersion}"))
        assertTrue(json.contains("\"digest\":\"${fp.digest}\""))
        assertTrue(json.contains("\"class\":1"))
        assertTrue(json.contains("\"student\":0"))
    }
}
