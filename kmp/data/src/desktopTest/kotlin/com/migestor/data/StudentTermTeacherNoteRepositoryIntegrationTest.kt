package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.WipeCategory
import com.migestor.shared.domain.TeacherTermNoteKeys
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Valoración del docente por alumno, grupo y trimestre (migración 49). */
class StudentTermTeacherNoteRepositoryIntegrationTest {

    private class Env(val driver: JdbcSqliteDriver, val container: KmpContainer)

    private fun newEnv(enforceForeignKeys: Boolean = false): Env {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        if (enforceForeignKeys) driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        return Env(driver, KmpContainer(driver))
    }

    private fun JdbcSqliteDriver.count(sql: String): Long =
        executeQuery(null, sql, { cursor ->
            cursor.next()
            app.cash.sqldelight.db.QueryResult.Value(cursor.getLong(0) ?: 0L)
        }, 0).value

    @Test
    fun `guarda una valoracion por alumno, grupo y trimestre sin mezclar casillas`() = runTest {
        val c = newEnv().container
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val luis = c.studentsRepository.saveStudent(firstName = "Luis", lastName = "Pérez")
        val grupo = c.classesRepository.saveClass(name = "1ºA", course = 1)
        val repo = c.studentTermTeacherNoteRepository

        assertNull(repo.get(ana, grupo, TeacherTermNoteKeys.FIRST))

        repo.save(ana, grupo, TeacherTermNoteKeys.FIRST, "  Muy constante, ayuda a sus compañeros.  ", updatedAtEpochMs = 1_000, deviceId = "ipad")
        repo.save(ana, grupo, TeacherTermNoteKeys.SECOND, "Ha bajado el ritmo.", updatedAtEpochMs = 1_000)
        repo.save(luis, grupo, TeacherTermNoteKeys.FIRST, "Le cuesta arrancar.", updatedAtEpochMs = 1_000)

        val guardada = repo.get(ana, grupo, TeacherTermNoteKeys.FIRST)
        // Se guarda sin espacios sobrantes.
        assertEquals("Muy constante, ayuda a sus compañeros.", guardada?.note)
        assertEquals("ipad", guardada?.trace?.deviceId)
        assertEquals("Ha bajado el ritmo.", repo.get(ana, grupo, TeacherTermNoteKeys.SECOND)?.note)
        assertEquals(
            setOf(ana, luis),
            repo.listByClassAndTerm(grupo, TeacherTermNoteKeys.FIRST).map { it.studentId }.toSet(),
        )
        assertEquals(3, repo.listAll().size)
    }

    @Test
    fun `editar reescribe el texto, sube la version y conserva la fecha de alta`() = runTest {
        val env = newEnv()
        val c = env.container
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val grupo = c.classesRepository.saveClass(name = "1ºA", course = 1)
        val repo = c.studentTermTeacherNoteRepository

        val primera = repo.save(ana, grupo, "T1", "Primera versión", updatedAtEpochMs = 1_000)
        val segunda = repo.save(ana, grupo, "T1", "Segunda versión", updatedAtEpochMs = 2_000)

        assertEquals(1, repo.listAll().size)
        assertEquals("Segunda versión", segunda.note)
        assertEquals(2_000, segunda.trace.updatedAt.toEpochMilliseconds())
        assertTrue(segunda.trace.syncVersion > primera.trace.syncVersion)
        assertEquals(1_000L, c.database.appDatabaseQueries.selectTermTeacherNoteCreatedAt(ana, grupo, "T1").executeAsOne())
    }

    @Test
    fun `vaciar la valoracion la guarda vacia en vez de borrarla`() = runTest {
        val c = newEnv().container
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val grupo = c.classesRepository.saveClass(name = "1ºA", course = 1)
        val repo = c.studentTermTeacherNoteRepository

        repo.save(ana, grupo, "T1", "Algo", updatedAtEpochMs = 1_000)
        repo.save(ana, grupo, "T1", "   ", updatedAtEpochMs = 2_000)

        // La fila sigue: así el vaciado también viaja por Sync LAN.
        assertEquals("", repo.get(ana, grupo, "T1")?.note)
    }

    @Test
    fun `el texto se recorta al tope`() = runTest {
        val c = newEnv().container
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val grupo = c.classesRepository.saveClass(name = "1ºA", course = 1)
        val guardada = c.studentTermTeacherNoteRepository.save(ana, grupo, "T1", "a".repeat(TeacherTermNoteKeys.MAX_NOTE_LENGTH + 500))
        assertEquals(TeacherTermNoteKeys.MAX_NOTE_LENGTH, guardada.note.length)
    }

    @Test
    fun `borrar el grupo o el alumno se lleva sus valoraciones`() = runTest {
        val env = newEnv(enforceForeignKeys = true)
        val c = env.container
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val luis = c.studentsRepository.saveStudent(firstName = "Luis", lastName = "Pérez")
        val grupoA = c.classesRepository.saveClass(name = "1ºA", course = 1)
        val grupoB = c.classesRepository.saveClass(name = "1ºB", course = 1)
        val repo = c.studentTermTeacherNoteRepository
        repo.save(ana, grupoA, "T1", "A")
        repo.save(ana, grupoB, "T1", "B")
        repo.save(luis, grupoB, "T1", "C")

        env.driver.execute(null, "DELETE FROM classes WHERE id = $grupoA", 0)
        assertEquals(listOf("B", "C"), repo.listAll().map { it.note }.sorted())

        env.driver.execute(null, "DELETE FROM students WHERE id = $ana", 0)
        assertEquals(listOf("C"), repo.listAll().map { it.note })

        assertTrue("student_term_teacher_notes" in WipeCategory.CLASSES.tableNames)
        assertTrue("student_term_teacher_notes" in WipeCategory.STUDENTS.tableNames)
    }

    @Test
    fun `sin claves ajenas activas, como en produccion, el borrado tambien las limpia`() = runTest {
        // FK apagadas: no hay cascada, lo hacen deleteClass y deleteStudent a mano.
        val c = newEnv(enforceForeignKeys = false).container
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "García")
        val luis = c.studentsRepository.saveStudent(firstName = "Luis", lastName = "Pérez")
        val grupoA = c.classesRepository.saveClass(name = "1ºA", course = 1)
        val grupoB = c.classesRepository.saveClass(name = "1ºB", course = 1)
        val repo = c.studentTermTeacherNoteRepository
        repo.save(ana, grupoA, "T1", "A")
        repo.save(ana, grupoB, "T1", "B")
        repo.save(luis, grupoB, "T1", "C")

        c.classesRepository.deleteClass(grupoA)
        assertEquals(listOf("B", "C"), repo.listAll().map { it.note }.sorted())

        c.studentsRepository.deleteStudent(ana)
        assertEquals(listOf("C"), repo.listAll().map { it.note })
    }

    @Test
    fun `la migracion 49 crea la tabla sin tocar lo guardado y se puede repetir`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        // Base anterior a la 49: alumnado y grupos con datos, sin la tabla nueva.
        driver.execute(null, "CREATE TABLE students (id INTEGER PRIMARY KEY, first_name TEXT NOT NULL)", 0)
        driver.execute(null, "CREATE TABLE classes (id INTEGER PRIMARY KEY, name TEXT NOT NULL)", 0)
        driver.execute(null, "INSERT INTO students VALUES (1, 'Ana')", 0)
        driver.execute(null, "INSERT INTO classes VALUES (7, '1ºA')", 0)

        AppDatabase.Schema.migrate(driver, 49, 50)
        AppDatabase.Schema.migrate(driver, 49, 50) // repetirla no debe fallar

        assertEquals(1L, driver.count("SELECT COUNT(*) FROM students WHERE first_name = 'Ana'"))
        assertEquals(1L, driver.count("SELECT COUNT(*) FROM classes WHERE name = '1ºA'"))
        assertEquals(1L, driver.count("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'student_term_teacher_notes'"))
        assertEquals(1L, driver.count("SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_term_teacher_notes_class_term'"))

        driver.execute(null, "INSERT INTO student_term_teacher_notes(student_id, class_id, term_key, note) VALUES (1, 7, 'T1', 'Hola')", 0)
        assertEquals(1L, driver.count("SELECT COUNT(*) FROM student_term_teacher_notes WHERE sync_version = 0 AND note = 'Hola'"))
    }
}
