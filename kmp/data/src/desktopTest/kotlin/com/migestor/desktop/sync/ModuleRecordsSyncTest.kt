package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.ModuleRecordsSync
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.PhysicalCapacity
import com.migestor.shared.domain.PhysicalMeasurementKind
import com.migestor.shared.domain.PhysicalTestAssignment
import com.migestor.shared.domain.PhysicalTestAttempt
import com.migestor.shared.domain.PhysicalTestBattery
import com.migestor.shared.domain.PhysicalTestDefinition
import com.migestor.shared.domain.PhysicalTestResult
import com.migestor.shared.inclusion.InclusionPhase
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ModuleRecordsSyncTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    /** Mismo grupo y alumno en los dos dispositivos (como tras «Igualar dispositivos»). */
    private suspend fun seed(container: KmpContainer): Pair<Long, Long> {
        val classId = container.classesRepository.saveClass(name = "2 ESO B", course = 2, description = null)
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        return classId to studentId
    }

    private fun trace(updatedAt: Long) = AuditTrace(
        createdAt = Instant.fromEpochMilliseconds(updatedAt),
        updatedAt = Instant.fromEpochMilliseconds(updatedAt),
        deviceId = "mac",
    )

    @Test
    fun elPlanSemanalViajaPorGrupoYSemanaAunqueLosIdsNoCoincidan() = runTest {
        val mac = newContainer()
        val (classId, _) = seed(mac)
        // En el iPad ya hay otro plan con el id 1: el del Mac no debe pisarlo.
        val ipad = newContainer()
        seed(ipad)
        ipad.plannerWeekPlanRepository.save(classId = classId, year = 2026, week = 40, notes = "otra semana", updatedAtEpochMs = 1_000)
        mac.plannerWeekPlanRepository.save(classId = classId, year = 2026, week = 43, strategies = listOf("gamificacion"), notes = "Cooperativo", updatedAtEpochMs = 5_000)

        val changes = ModuleRecordsSync(mac, "mac").collect(0L).changes.filter { it.entity == ModuleRecordsSync.WEEK_PLAN }
        assertEquals(listOf("$classId|2026|43"), changes.map { it.id })
        ModuleRecordsSync(ipad, "ipad").applyAll(changes)

        val received = assertNotNull(ipad.plannerWeekPlanRepository.getPlan(classId, 2026, 43))
        assertEquals("Cooperativo", received.notes)
        assertEquals(listOf("gamificacion"), received.strategies)
        assertEquals("otra semana", ipad.plannerWeekPlanRepository.getPlan(classId, 2026, 40)?.notes)
    }

    @Test
    fun marcarHechaUnaTareaDelManualLlegaAunqueCadaDispositivoLaGenereConSuId() = runTest {
        val mac = newContainer()
        val (_, studentId) = seed(mac)
        val ipad = newContainer()
        seed(ipad)
        // El iPad generó antes otras tareas: los ids autoincrementales ya no coinciden.
        ipad.inclusionTaskRepository.insertFreeTask(studentId, "Llamar a la familia", InclusionPhase.SEPTIEMBRE, "2026-09-20", "", "2026-2027", 100)
        listOf(mac, ipad).forEach {
            it.inclusionTaskRepository.insertTemplateIfAbsent(studentId, null, "papacis", "Revisar PAPACIS", InclusionPhase.NOVIEMBRE, "2026-11-15", "2026-2027", 200)
        }
        val macTask = mac.inclusionTaskRepository.listByStudents(listOf(studentId), "2026-2027").single()
        mac.inclusionTaskRepository.setDone(macTask.id, "2026-10-22", 9_000)

        val changes = ModuleRecordsSync(mac, "mac").collect(0L).changes.filter { it.entity == ModuleRecordsSync.INCLUSION_TASK }
        val ack = ModuleRecordsSync(ipad, "ipad").applyAll(changes)
        assertEquals(1, ack.applied)

        val tasks = ipad.inclusionTaskRepository.listByStudents(listOf(studentId), "2026-2027")
        assertEquals(2, tasks.size)
        assertEquals("2026-10-22", tasks.single { it.templateKey == "papacis" }.doneAt.toString())
        assertNull(tasks.single { it.templateKey == null }.doneAt)
    }

    @Test
    fun unaTareaLibreSeCreaUnaSolaVez() = runTest {
        val ipad = newContainer()
        val (_, studentId) = seed(ipad)
        ipad.inclusionTaskRepository.insertFreeTask(studentId, "Reunión con orientación", InclusionPhase.OBSERVAR, "2026-10-01", "Llevar informe", "2026-2027", 4_000)
        val changes = ModuleRecordsSync(ipad, "ipad").collect(0L).changes.filter { it.entity == ModuleRecordsSync.INCLUSION_TASK }

        val mac = newContainer()
        seed(mac)
        val sync = ModuleRecordsSync(mac, "mac")
        sync.applyAll(changes)
        sync.applyAll(changes)
        val task = mac.inclusionTaskRepository.listByStudents(listOf(studentId), "2026-2027").single()
        assertEquals("Reunión con orientación", task.title)
        assertEquals("Llevar informe", task.notes)
    }

    @Test
    fun laFechaDeEvaluacionInicialSinFechaDeCambioSoloRellenaHuecos() = runTest {
        val mac = newContainer()
        val (classId, _) = seed(mac)
        mac.inclusionTaskRepository.setInitialEvaluationDate(classId, "2026-2027", "2026-10-10")
        val first = ModuleRecordsSync(mac, "mac")
        val baseline = first.collect(0L).changes.filter { it.entity == ModuleRecordsSync.INCLUSION_GROUP_SETTING }
        assertEquals(0L, baseline.single().updatedAtEpochMs)

        val ipad = newContainer()
        seed(ipad)
        ModuleRecordsSync(ipad, "ipad").applyAll(baseline)
        assertEquals("2026-10-10", ipad.inclusionTaskRepository.getInitialEvaluationDate(classId, "2026-2027"))

        // El iPad la cambia; la recogida antigua del Mac (fecha 0) no la devuelve atrás.
        ipad.inclusionTaskRepository.setInitialEvaluationDate(classId, "2026-2027", "2026-10-17")
        ModuleRecordsSync(ipad, "ipad").applyAll(baseline)
        assertEquals("2026-10-17", ipad.inclusionTaskRepository.getInitialEvaluationDate(classId, "2026-2027"))

        // Un cambio detectado en el Mac sí se aplica.
        mac.inclusionTaskRepository.setInitialEvaluationDate(classId, "2026-2027", "2026-10-24")
        val changed = first.collect(0L).changes.filter { it.entity == ModuleRecordsSync.INCLUSION_GROUP_SETTING }
        assertTrue(changed.single().updatedAtEpochMs > 0)
        ModuleRecordsSync(ipad, "ipad").applyAll(changed)
        assertEquals("2026-10-24", ipad.inclusionTaskRepository.getInitialEvaluationDate(classId, "2026-2027"))
    }

    @Test
    fun losResultadosDeLasPruebasFisicasLleganConSusIntentos() = runTest {
        val ipad = newContainer()
        val (classId, studentId) = seed(ipad)
        val physical = ipad.physicalTestsRepository
        physical.saveDefinition(
            PhysicalTestDefinition(
                id = "test-course-navette", name = "Course Navette", capacity = PhysicalCapacity.entries.first(),
                measurementKind = PhysicalMeasurementKind.entries.first(), unit = "paliers", higherIsBetter = true,
                attempts = 2, trace = trace(1_000),
            ),
        )
        physical.saveBattery(PhysicalTestBattery(id = "bat-1", name = "Inicial", testIds = listOf("test-course-navette"), trace = trace(1_000)))
        physical.assignBatteryToClass(
            PhysicalTestAssignment(
                id = "asg-1", batteryId = "bat-1", classId = classId, course = 2, ageFrom = null, ageTo = null,
                termLabel = "1T", dateEpochMs = 2_000, trace = trace(2_000),
            ),
        )
        physical.saveResult(
            PhysicalTestResult(
                id = "res-1", assignmentId = "asg-1", testId = "test-course-navette", classId = classId, studentId = studentId,
                rawValue = 7.5, rawText = "7.5", score = 6.0, scaleId = null, observedAtEpochMs = 3_000,
                rawColumnId = null, scoreColumnId = null, trace = trace(3_000),
            ),
            listOf(
                PhysicalTestAttempt(id = "att-1", resultId = "res-1", attemptNumber = 1, rawValue = 6.0, rawText = "6"),
                PhysicalTestAttempt(id = "att-2", resultId = "res-1", attemptNumber = 2, rawValue = 7.5, rawText = "7.5"),
            ),
        )

        val changes = ModuleRecordsSync(ipad, "ipad").collect(0L).changes
        val mac = newContainer()
        seed(mac)
        val ack = SqlDelightSyncAdapter(mac, localDeviceId = "mac").applyIncomingChangesLww(changes)
        assertEquals(0, ack.failed)

        val result = mac.physicalTestsRepository.listResultsForAssignment("asg-1").single()
        assertEquals(7.5, result.rawValue)
        assertEquals(3_000, result.trace.updatedAt.toEpochMilliseconds())
        val attempts = mac.database.appDatabaseQueries.selectPhysicalAttemptsForResult("res-1").executeAsList()
        assertEquals(listOf(6.0, 7.5), attempts.sortedBy { it.attempt_number }.map { it.raw_value })
        assertEquals(listOf("test-course-navette"), mac.physicalTestsRepository.listBatteries().single().testIds)

        // Un resultado más viejo no pisa el que ya hay.
        val stale = changes.first { it.entity == ModuleRecordsSync.PE_RESULT }.copy(
            updatedAtEpochMs = 1_000,
            payload = changes.first { it.entity == ModuleRecordsSync.PE_RESULT }.payload.replace("\"rawValue\":7.5", "\"rawValue\":1.0"),
        )
        assertEquals(1, ModuleRecordsSync(mac, "mac").applyAll(listOf(stale)).conflictsResolvedByLww)
        assertEquals(7.5, mac.physicalTestsRepository.listResultsForAssignment("asg-1").single().rawValue)
    }

    @Test
    fun borrarUnPlanSemanalEnElMacLoBorraEnElIpad() = runTest {
        val mac = newContainer()
        val (classId, _) = seed(mac)
        val planId = mac.plannerWeekPlanRepository.save(classId = classId, year = 2026, week = 43, notes = "x", updatedAtEpochMs = 5_000)
        val adapter = SqlDelightSyncAdapter(mac, localDeviceId = "mac")
        adapter.collectLocalChanges(0L)
        mac.plannerWeekPlanRepository.delete(planId)
        val delete = adapter.collectLocalChanges(0L).single { it.entity == ModuleRecordsSync.WEEK_PLAN && it.op == "delete" }

        val ipad = newContainer()
        seed(ipad)
        ipad.plannerWeekPlanRepository.save(classId = classId, year = 2026, week = 43, notes = "x", updatedAtEpochMs = 5_000)
        ModuleRecordsSync(ipad, "ipad").applyAll(listOf(delete))
        assertNull(ipad.plannerWeekPlanRepository.getPlan(classId, 2026, 43))
    }
}
