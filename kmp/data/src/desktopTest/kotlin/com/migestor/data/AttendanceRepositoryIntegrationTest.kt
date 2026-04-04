package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.AttendanceRepositorySqlDelight
import com.migestor.data.repository.ClassesRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals

class AttendanceRepositoryIntegrationTest {
    @Test
    fun `retrieves attendance records between dates`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val attendanceRepo = AttendanceRepositorySqlDelight(db)
        val classesRepo = ClassesRepositorySqlDelight(db)
        val studentsRepo = StudentsRepositorySqlDelight(db)

        val classId = classesRepo.saveClass(name = "Test Class", course = 1, description = null)
        val studentId = studentsRepo.saveStudent(firstName = "John", lastName = "Doe", email = null)
        classesRepo.addStudentToClass(classId, studentId)

        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val todayMs = today.atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds()
        val yesterday = today.minus(1, DateTimeUnit.DAY)
        val yesterdayMs = yesterday.atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds()
        val twoDaysAgo = today.minus(2, DateTimeUnit.DAY)
        val twoDaysAgoMs = twoDaysAgo.atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds()

        // Save attendance for 3 different days
        attendanceRepo.saveAttendance(null, studentId, classId, todayMs, "PRESENTE")
        attendanceRepo.saveAttendance(null, studentId, classId, yesterdayMs, "AUSENTE")
        attendanceRepo.saveAttendance(null, studentId, classId, twoDaysAgoMs, "TARDE")

        // Query for last 2 days (today and yesterday)
        val results = attendanceRepo.getAttendanceForClassBetweenDates(classId, yesterdayMs, todayMs)

        assertEquals(2, results.size)
        assertEquals("PRESENTE", results[0].status) // Ordered by date desc
        assertEquals("AUSENTE", results[1].status)
    }
}
