package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.repository.UnseenStudentsRepositorySqlDelight
import com.migestor.shared.attention.ContactKind
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Consultas de solo lectura de «Alumnos invisibles» (`Attention.sq`). Alumnado inventado. */
class UnseenStudentsRepositoryTest {

    private val utc = TimeZone.UTC

    private fun ms(iso: String): Long =
        LocalDateTime.parse("${iso}T12:00:00").toInstant(utc).toEpochMilliseconds()

    private fun setup(): Triple<JdbcSqliteDriver, KmpContainer, UnseenStudentsRepositorySqlDelight> {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val container = KmpContainer(driver)
        return Triple(driver, container, UnseenStudentsRepositorySqlDelight(container.database, container.classesRepository) { utc })
    }

    private fun JdbcSqliteDriver.sql(statement: String) = execute(null, statement, 0)

    @Test
    fun cadaTipoDeRegistroCuentaYPasarListaSinNotaNo() = runTest {
        val (driver, c, repo) = setup()
        val classId = c.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        val otherClass = c.classesRepository.saveClass(name = "1º BACH A (inventado)", course = 1)
        listOf(1L to "Ana", 2L to "Pablo", 3L to "Lucía", 4L to "Marta", 5L to "Jorge", 6L to "Sara").forEach { (id, name) ->
            c.studentsRepository.saveStudent(id = id, firstName = name, lastName = "(inventado)")
            c.classesRepository.addStudentToClass(classId, id)
        }
        driver.sql("INSERT INTO grades(class_id, student_id, column_id, value, created_at_epoch_ms, updated_at_epoch_ms) VALUES ($classId, 1, 'c1', 7.5, ${ms("2026-11-01")}, ${ms("2026-11-10")})")
        // Nota vacía: no cuenta.
        driver.sql("INSERT INTO grades(class_id, student_id, column_id, value, created_at_epoch_ms, updated_at_epoch_ms) VALUES ($classId, 2, 'c1', NULL, ${ms("2026-11-20")}, ${ms("2026-11-20")})")
        // Otro grupo: no cuenta en este.
        driver.sql("INSERT INTO grades(class_id, student_id, column_id, value, created_at_epoch_ms, updated_at_epoch_ms) VALUES ($otherClass, 2, 'c9', 9.0, ${ms("2026-11-25")}, ${ms("2026-11-25")})")
        driver.sql("INSERT INTO incidents(class_id, student_id, title, detail, date_epoch_ms) VALUES ($classId, 3, 'Observación', 'Participa más', ${ms("2026-11-24")})")
        driver.sql("INSERT INTO attendance(student_id, class_id, date_epoch_ms, status, note) VALUES (4, $classId, ${ms("2026-11-26")}, 'PRESENTE', '')")
        driver.sql("INSERT INTO attendance(student_id, class_id, date_epoch_ms, status, note) VALUES (5, $classId, ${ms("2026-11-21")}, 'RETRASO', 'Llega tarde del recreo')")
        driver.sql("INSERT INTO planner_session(id, date, group_id, period) VALUES (70, '2026-11-19', $classId, 3)")
        driver.sql("INSERT INTO session_journal(id, planning_session_id) VALUES (80, 70)")
        driver.sql("INSERT INTO session_journal_individual_note(journal_id, student_id, note) VALUES (80, 6, 'Lidera el calentamiento')")
        driver.sql("INSERT INTO student_tutoring_sessions(student_id, date_iso) VALUES (6, '2026-11-05')")

        val contacts = repo.lastContacts(classId).groupBy { it.studentId }
        assertEquals(ContactKind.GRADE, contacts.getValue(1).single().kind)
        assertEquals(LocalDate.parse("2026-11-10"), contacts.getValue(1).single().date)
        assertTrue(2L !in contacts)
        assertEquals(ContactKind.OBSERVATION, contacts.getValue(3).single().kind)
        assertTrue(4L !in contacts, "pasar lista sin nota no cuenta")
        assertEquals(ContactKind.ATTENDANCE_NOTE, contacts.getValue(5).single().kind)
        assertEquals(
            setOf(ContactKind.JOURNAL_NOTE to LocalDate.parse("2026-11-19"), ContactKind.FAMILY_MEETING to LocalDate.parse("2026-11-05")),
            contacts.getValue(6).map { it.kind to it.date }.toSet(),
        )
        assertEquals(6, repo.students(classId).size)
    }

    @Test
    fun altasYMedidasDeApoyoDelGrupo() = runTest {
        val (driver, c, repo) = setup()
        val classId = c.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        listOf(1L, 2L).forEach { id ->
            c.studentsRepository.saveStudent(id = id, firstName = "Alumno $id", lastName = "(inventado)")
            c.classesRepository.addStudentToClass(classId, id)
        }
        driver.sql("UPDATE student_enrollments SET created_at_epoch_ms = CASE student_id WHEN 2 THEN ${ms("2026-11-20")} ELSE 0 END WHERE class_id = $classId")
        driver.sql("INSERT INTO student_support_measures(student_id, level, measure_type, start_date_iso, is_active) VALUES (1, 'III', 'ACIS', '2026-09-15', 1)")
        driver.sql("INSERT INTO student_support_measures(student_id, level, measure_type, start_date_iso, is_active) VALUES (2, 'IV', 'ACIS', '2026-09-15', 0)")

        assertEquals(mapOf(2L to LocalDate.parse("2026-11-20")), repo.enrollmentStarts(classId))
        assertEquals(setOf(1L), repo.studentsWithSupportMeasure(classId))
    }
}
