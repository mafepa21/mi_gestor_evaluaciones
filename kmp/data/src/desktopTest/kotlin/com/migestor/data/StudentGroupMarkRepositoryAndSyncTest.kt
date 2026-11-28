package com.migestor.data

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SchoolRecordsSync
import com.migestor.shared.sync.SyncChange
import com.migestor.shared.workgroup.StudentGroupMarkKeys
import com.migestor.shared.workgroup.WorkGroupMark
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Migración 52: marcas Fuerte / Necesita apoyo para grupos y Sync LAN. Alumnado inventado. */
class StudentGroupMarkRepositoryAndSyncTest {

    private fun newContainer(): Pair<JdbcSqliteDriver, KmpContainer> {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return driver to KmpContainer(driver)
    }

    private fun JdbcSqliteDriver.strings(sql: String): List<String> =
        executeQuery(null, sql, { cursor ->
            val out = mutableListOf<String>()
            while (cursor.next().value) out += cursor.getString(0)!!
            QueryResult.Value(out)
        }, 0).value

    private fun markChange(studentId: Long, classId: Long, mark: String, ms: Long, device: String = "ipad") = SyncChange(
        entity = SchoolRecordsSync.STUDENT_GROUP_MARKS,
        id = StudentGroupMarkKeys.syncId(studentId, classId),
        updatedAtEpochMs = ms,
        deviceId = device,
        payload = """{"studentId":$studentId,"classId":$classId,"mark":"$mark"}""",
    )

    @Test
    fun laInstalacionNuevaTieneLaTablaYSuIndice() {
        val (driver, _) = newContainer()
        assertEquals(
            listOf("student_id", "class_id", "mark", "created_at_epoch_ms", "updated_at_epoch_ms", "device_id", "sync_version"),
            driver.strings("SELECT name FROM pragma_table_info('student_group_marks')"),
        )
        assertEquals(
            listOf("idx_student_group_marks_class"),
            driver.strings("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'student_group_marks' AND name LIKE 'idx_%'"),
        )
    }

    @Test
    fun guardarCambiaLaMarcaEnElSitioYConservaLaFechaDeAlta() = runTest {
        val (_, c) = newContainer()
        val repo = c.studentGroupMarkRepository
        repo.save(studentId = 1, classId = 10, mark = WorkGroupMark.STRONG, updatedAtEpochMs = 1_000, deviceId = "mac")
        val saved = repo.save(studentId = 1, classId = 10, mark = WorkGroupMark.NONE, updatedAtEpochMs = 2_000, deviceId = "mac")
        assertEquals(WorkGroupMark.NONE, saved.mark)
        assertEquals(1_000, saved.trace.createdAt.toEpochMilliseconds())
        assertEquals(2_000, saved.trace.updatedAt.toEpochMilliseconds())
        assertEquals(2, saved.trace.syncVersion)
        assertEquals(1, repo.listByClass(10).size)
        assertTrue(repo.listByClass(11).isEmpty())
    }

    @Test
    fun unValorDesconocidoCuentaComoSinMarca() {
        assertEquals(WorkGroupMark.NONE, WorkGroupMark.fromStorage("CAPTAIN"))
        assertEquals(WorkGroupMark.SUPPORT, WorkGroupMark.fromStorage("SUPPORT"))
        assertNull(StudentGroupMarkKeys.parseSyncId("1|2|3"))
        assertEquals(4L to 7L, StudentGroupMarkKeys.parseSyncId("4|7"))
    }

    @Test
    fun laMarcaViajaDelMacAlIpadYQuitarlaTambien() = runTest {
        val (_, mac) = newContainer()
        val (_, ipad) = newContainer()
        mac.studentGroupMarkRepository.save(3, 10, WorkGroupMark.SUPPORT, 1_000, "mac")

        // Se manda siempre, aunque sea anterior al último envío.
        val first = SchoolRecordsSync(mac, "mac").collect(5_000).changes
            .single { it.entity == SchoolRecordsSync.STUDENT_GROUP_MARKS }
        assertEquals(1, SchoolRecordsSync(ipad, "ipad").applyAll(listOf(first)).applied)
        assertEquals(WorkGroupMark.SUPPORT, ipad.studentGroupMarkRepository.get(3, 10)!!.mark)

        mac.studentGroupMarkRepository.save(3, 10, WorkGroupMark.NONE, 2_000, "mac")
        val cleared = SchoolRecordsSync(mac, "mac").collect(0).changes
            .single { it.entity == SchoolRecordsSync.STUDENT_GROUP_MARKS }
        SchoolRecordsSync(ipad, "ipad").applyAll(listOf(cleared))
        assertEquals(WorkGroupMark.NONE, ipad.studentGroupMarkRepository.get(3, 10)!!.mark)
    }

    @Test
    fun gananLaMarcaMasNuevaYElEmpatePorDeviceId() = runTest {
        val (_, mac) = newContainer()
        mac.studentGroupMarkRepository.save(5, 10, WorkGroupMark.STRONG, 3_000, "mac")
        val sync = SchoolRecordsSync(mac, "mac")
        assertEquals(1, sync.applyAll(listOf(markChange(5, 10, "SUPPORT", 2_000))).conflictsResolvedByLww)
        assertEquals(WorkGroupMark.STRONG, mac.studentGroupMarkRepository.get(5, 10)!!.mark)
        // Empate: gana el deviceId mayor ("ipad" < "mac" pierde; "tablet" > "mac" gana).
        assertEquals(1, sync.applyAll(listOf(markChange(5, 10, "SUPPORT", 3_000, device = "ipad"))).conflictsResolvedByLww)
        assertEquals(1, sync.applyAll(listOf(markChange(5, 10, "SUPPORT", 3_000, device = "tablet"))).applied)
        assertEquals(WorkGroupMark.SUPPORT, mac.studentGroupMarkRepository.get(5, 10)!!.mark)
        // El mismo cambio otra vez ya no se aplica.
        assertEquals(1, sync.applyAll(listOf(markChange(5, 10, "SUPPORT", 3_000, device = "tablet"))).conflictsResolvedByLww)
    }

    @Test
    fun noResucitaMarcasDeUnAlumnoOGrupoBorrado() = runTest {
        val (_, mac) = newContainer()
        mac.syncTombstoneRepository.recordTombstone(entity = "student", entityId = "4", deletedAtEpochMs = 5_000, deviceId = "mac")
        mac.syncTombstoneRepository.recordTombstone(entity = "class", entityId = "20", deletedAtEpochMs = 5_000, deviceId = "mac")
        val ack = SchoolRecordsSync(mac, "mac").applyAll(
            listOf(markChange(4, 10, "STRONG", 4_000), markChange(6, 20, "SUPPORT", 4_000)),
        )
        assertEquals(2, ack.ignored)
        assertNull(mac.studentGroupMarkRepository.get(4, 10))
        assertNull(mac.studentGroupMarkRepository.get(6, 20))
    }

    @Test
    fun borrarAlumnoOGrupoBorraSusMarcas() = runTest {
        val (_, c) = newContainer()
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "López (inventada)")
        val repo = c.studentGroupMarkRepository
        repo.save(ana, 10, WorkGroupMark.STRONG, 1_000, "mac")
        repo.save(99, 20, WorkGroupMark.SUPPORT, 1_000, "mac")
        repo.save(98, 20, WorkGroupMark.STRONG, 1_000, "mac")
        c.studentsRepository.deleteStudent(ana)
        assertNull(repo.get(ana, 10))
        c.classesRepository.deleteClass(20)
        assertTrue(repo.listAll().isEmpty())
    }
}
