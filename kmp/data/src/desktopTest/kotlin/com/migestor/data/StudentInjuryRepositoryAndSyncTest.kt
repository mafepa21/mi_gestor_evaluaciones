package com.migestor.data

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SchoolRecordsSync
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.injury.InjuryRole
import com.migestor.shared.injury.StudentInjury
import com.migestor.shared.injury.StudentInjuryDraft
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Migración 51: lesiones con fecha, marca derivada y Sync LAN. Alumnado inventado. */
class StudentInjuryRepositoryAndSyncTest {

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

    private fun JdbcSqliteDriver.longs(sql: String): List<Long> =
        executeQuery(null, sql, { cursor ->
            val out = mutableListOf<Long>()
            while (cursor.next().value) out += cursor.getLong(0)!!
            QueryResult.Value(out)
        }, 0).value

    private fun injury(id: String, studentId: Long, startsOn: String, endsOn: String? = null, ms: Long = 1_000) = StudentInjury(
        id = id,
        studentId = studentId,
        startsOn = LocalDate.parse(startsOn),
        endsOn = endsOn?.let(LocalDate::parse),
        role = InjuryRole.REFEREE,
        note = "Puede caminar.",
        proofDelivered = true,
        trace = AuditTrace(
            createdAt = Instant.fromEpochMilliseconds(ms),
            updatedAt = Instant.fromEpochMilliseconds(ms),
            deviceId = "mac",
            syncVersion = 1,
        ),
    )

    @Test
    fun laInstalacionNuevaTieneLaTablaYSuIndice() {
        val (driver, _) = newContainer()
        assertEquals(
            listOf(
                "id", "student_id", "starts_on", "ends_on", "alternate_role", "note", "proof_delivered",
                "is_deleted", "created_at_epoch_ms", "updated_at_epoch_ms", "device_id", "sync_version",
            ),
            driver.strings("SELECT name FROM pragma_table_info('student_injuries')"),
        )
        assertEquals(
            listOf("idx_student_injuries_student"),
            driver.strings("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'student_injuries' AND name LIKE 'idx_%'"),
        )
    }

    @Test
    fun laMigracion51ConservaLaMarcaDeLosYaLesionados() = runTest {
        val (driver, c) = newContainer()
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "López (inventada)", isInjured = true)
        c.studentsRepository.saveStudent(firstName = "Pablo", lastName = "García (inventado)")
        // Simula una base en la versión 51 (sin la tabla) y migra.
        driver.execute(null, "DROP TABLE student_injuries", 0)
        AppDatabase.Schema.migrate(driver, 51, 52)
        AppDatabase.Schema.migrate(driver, 51, 52) // repetirla no duplica

        val rows = c.studentInjuryRepository.listAll()
        assertEquals(listOf("legacy-$ana"), rows.map { it.id })
        assertNull(rows.single().endsOn)
        assertEquals(InjuryRole.NONE, rows.single().role)
        assertEquals(setOf(ana), c.studentInjuryRepository.listFlaggedStudentIds())
        // Recalcular no le quita la marca: la lesión migrada está activa hoy.
        assertTrue(c.studentInjuries.reconcileFlags().isEmpty())
    }

    @Test
    fun guardarCambiaLaMarcaSinTocarLaFechaDelAlumno() = runTest {
        val (driver, c) = newContainer()
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "López (inventada)", updatedAtEpochMs = 500)
        c.studentInjuries.save(
            StudentInjuryDraft(studentId = ana, startsOn = LocalDate.parse("2020-01-01"), role = InjuryRole.TIMEKEEPER),
            nowEpochMs = 1_000,
            deviceId = "ipad",
        )
        assertTrue(c.studentsRepository.getStudent(ana)!!.isInjured)
        assertEquals(listOf(500L), driver.longs("SELECT updated_at_epoch_ms FROM students WHERE id = $ana"))
        assertEquals(InjuryRole.TIMEKEEPER, c.studentInjuries.listForStudent(ana).single().role)
    }

    @Test
    fun lasLesionesViajanDelMacAlIPadYRecalculanLaMarca() = runTest {
        val (_, mac) = newContainer()
        val (_, ipad) = newContainer()
        mac.studentsRepository.saveStudent(id = 7, firstName = "Ana", lastName = "López (inventada)")
        ipad.studentsRepository.saveStudent(id = 7, firstName = "Ana", lastName = "López (inventada)")
        mac.studentInjuryRepository.save(injury("les-1", 7, "2020-01-01"))

        val collected = SchoolRecordsSync(mac, "mac").collect(0)
        val change = collected.changes.single { it.entity == SchoolRecordsSync.STUDENT_INJURIES }
        assertEquals(setOf("les-1"), collected.liveIdsByEntity.getValue(SchoolRecordsSync.STUDENT_INJURIES))

        val ack = SqlDelightSyncAdapter(ipad, "ipad").applyIncomingChangesLww(listOf(change))
        assertEquals(1, ack.applied)
        val received = ipad.studentInjuryRepository.get("les-1")!!
        assertEquals(InjuryRole.REFEREE, received.role)
        assertTrue(received.proofDelivered)
        assertEquals("Puede caminar.", received.note)
        assertTrue(ipad.studentsRepository.getStudent(7)!!.isInjured)

        // «Ha vuelto» en el Mac (termina en el pasado) → el iPad quita la marca.
        mac.studentInjuryRepository.save(injury("les-1", 7, "2020-01-01", endsOn = "2020-02-01", ms = 2_000))
        val ended = SchoolRecordsSync(mac, "mac").collect(1_500).changes.single()
        SchoolRecordsSync(ipad, "ipad").applyAll(listOf(ended))
        assertEquals(LocalDate.parse("2020-02-01"), ipad.studentInjuryRepository.get("les-1")!!.endsOn)
        assertFalse(ipad.studentsRepository.getStudent(7)!!.isInjured)

        // Un cambio más viejo no pisa lo que ya hay.
        val stale = change.copy(updatedAtEpochMs = 500)
        assertEquals(1, SchoolRecordsSync(ipad, "ipad").applyAll(listOf(stale)).conflictsResolvedByLww)
        assertEquals(LocalDate.parse("2020-02-01"), ipad.studentInjuryRepository.get("les-1")!!.endsOn)
    }

    @Test
    fun elPayloadDeAppleSeAplicaIgualYElBorradoLogicoViaja() = runTest {
        val (_, ipad) = newContainer()
        val (_, mac) = newContainer()
        ipad.studentsRepository.saveStudent(id = 3, firstName = "Pablo", lastName = "García (inventado)")
        mac.studentsRepository.saveStudent(id = 3, firstName = "Pablo", lastName = "García (inventado)")
        val deleted = injury("les-2", 3, "2020-01-01", ms = 3_000).copy(isDeleted = true)
        val change = com.migestor.shared.sync.SyncChange(
            entity = SchoolRecordsSync.STUDENT_INJURIES,
            id = deleted.id,
            updatedAtEpochMs = 3_000,
            deviceId = "ipad",
            payload = SchoolRecordsSync.injuryPayload(deleted),
        )
        SchoolRecordsSync(mac, "mac").applyAll(listOf(change))
        assertTrue(mac.studentInjuryRepository.get("les-2")!!.isDeleted)
        assertFalse(mac.studentsRepository.getStudent(3)!!.isInjured)
        assertTrue(mac.studentInjuries.listForStudent(3).isEmpty())
    }

    @Test
    fun lasFilasLegacyEmpatadasConvergenPorDeviceIdYSeMandanSiempre() = runTest {
        val (_, mac) = newContainer()
        val (_, ipad) = newContainer()
        val legacy = injury("legacy-9", 9, "2026-11-20", ms = 0)
        mac.studentInjuryRepository.save(legacy.copy(trace = legacy.trace.copy(deviceId = null)))
        ipad.studentInjuryRepository.save(
            legacy.copy(startsOn = LocalDate.parse("2026-11-26"), trace = legacy.trace.copy(deviceId = null)),
        )
        // Fecha 0: aun así sale en un envío incremental.
        val change = SchoolRecordsSync(mac, "mac").collect(1_000).changes.single { it.entity == SchoolRecordsSync.STUDENT_INJURIES }
        assertEquals("mac", change.deviceId)
        SchoolRecordsSync(ipad, "ipad").applyAll(listOf(change))
        assertEquals(LocalDate.parse("2026-11-20"), ipad.studentInjuryRepository.get("legacy-9")!!.startsOn)
        // El mismo cambio otra vez ya no se aplica (empate con el mismo aparato).
        assertEquals(1, SchoolRecordsSync(ipad, "ipad").applyAll(listOf(change)).conflictsResolvedByLww)
    }

    @Test
    fun noResucitaLesionesDeUnAlumnoBorrado() = runTest {
        val (_, mac) = newContainer()
        mac.syncTombstoneRepository.recordTombstone(entity = "student", entityId = "4", deletedAtEpochMs = 5_000, deviceId = "mac")
        val change = com.migestor.shared.sync.SyncChange(
            entity = SchoolRecordsSync.STUDENT_INJURIES,
            id = "les-4",
            updatedAtEpochMs = 4_000,
            deviceId = "ipad",
            payload = SchoolRecordsSync.injuryPayload(injury("les-4", 4, "2026-11-26", ms = 4_000)),
        )
        assertEquals(1, SchoolRecordsSync(mac, "mac").applyAll(listOf(change)).ignored)
        assertNull(mac.studentInjuryRepository.get("les-4"))
    }

    @Test
    fun borrarAlAlumnoBorraSusLesiones() = runTest {
        val (_, c) = newContainer()
        val ana = c.studentsRepository.saveStudent(firstName = "Ana", lastName = "López (inventada)")
        c.studentInjuryRepository.save(injury("les-3", ana, "2026-11-26"))
        c.studentsRepository.deleteStudent(ana)
        assertNull(c.studentInjuryRepository.get("les-3"))
    }
}
