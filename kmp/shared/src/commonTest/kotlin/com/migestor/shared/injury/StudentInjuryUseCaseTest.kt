package com.migestor.shared.injury

import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Lesiones con fecha: reglas de fechas, marca derivada y «ha vuelto». Datos inventados. */
class StudentInjuryUseCaseTest {

    private class FakeRepository : StudentInjuryRepository {
        val rows = linkedMapOf<String, StudentInjury>()
        val flagged = mutableSetOf<Long>()
        override suspend fun listAll() = rows.values.toList()
        override suspend fun listByStudent(studentId: Long) = rows.values.filter { it.studentId == studentId }
        override suspend fun get(id: String) = rows[id]
        override suspend fun save(injury: StudentInjury) { rows[injury.id] = injury }
        override suspend fun hardDelete(id: String) { rows.remove(id) }
        override suspend fun listFlaggedStudentIds() = flagged.toSet()
        override suspend fun setInjuredFlag(studentId: Long, isInjured: Boolean) {
            if (isInjured) flagged += studentId else flagged -= studentId
        }
    }

    private val ana = 1L
    private val pablo = 2L
    private fun d(iso: String) = LocalDate.parse(iso)

    private fun useCase(repo: FakeRepository, today: () -> LocalDate): StudentInjuryUseCase {
        var n = 0
        return StudentInjuryUseCase(repo, newId = { "i${++n}" }, today = today)
    }

    @Test
    fun elHastaCuentaYAlDiaSiguienteYaNoEstaActiva() {
        val injury = StudentInjury(id = "a", studentId = ana, startsOn = d("2026-11-26"), endsOn = d("2026-12-12"))
        assertFalse(StudentInjuryRules.isActiveOn(injury, d("2026-11-25")))
        assertTrue(StudentInjuryRules.isActiveOn(injury, d("2026-11-26")))
        assertTrue(StudentInjuryRules.isActiveOn(injury, d("2026-12-12")))
        assertFalse(StudentInjuryRules.isActiveOn(injury, d("2026-12-13")))
    }

    @Test
    fun sinFechaDeFinSigueActivaYBorradaNunca() {
        val open = StudentInjury(id = "a", studentId = ana, startsOn = d("2026-09-01"))
        assertTrue(StudentInjuryRules.isActiveOn(open, d("2027-06-20")))
        assertFalse(StudentInjuryRules.isActiveOn(open.copy(isDeleted = true), d("2026-10-01")))
    }

    @Test
    fun noGuardaUnHastaAnteriorAlDesdeNiUnaNotaLarga() = runTest {
        val uc = useCase(FakeRepository()) { d("2026-11-26") }
        val bad = assertFailsWith<StudentInjuryValidationException> {
            uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-11-26"), endsOn = d("2026-11-20")), 1_000, "ipad")
        }
        assertEquals(StudentInjuryValidationError.ENDS_BEFORE_START, bad.error)
        val long = assertFailsWith<StudentInjuryValidationException> {
            uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-11-26"), note = "x".repeat(141)), 1_000, "ipad")
        }
        assertEquals(StudentInjuryValidationError.NOTE_TOO_LONG, long.error)
    }

    @Test
    fun guardarMarcaAlAlumnoYLaMarcaSeQuitaSolaAlTerminar() = runTest {
        val repo = FakeRepository()
        var today = d("2026-11-26")
        val uc = useCase(repo) { today }
        val saved = uc.save(
            StudentInjuryDraft(studentId = ana, startsOn = today, endsOn = d("2026-12-12"), role = InjuryRole.REFEREE, note = "  Puede caminar.  "),
            1_000, "ipad",
        )
        assertEquals("Puede caminar.", saved.note)
        assertEquals(setOf(ana), repo.flagged)

        today = d("2026-12-12")
        assertEquals(emptySet(), uc.reconcileFlags())
        assertEquals(setOf(ana), repo.flagged)

        today = d("2026-12-13")
        assertEquals(setOf(ana), uc.reconcileFlags())
        assertEquals(emptySet(), repo.flagged)
        assertEquals(listOf(saved.id), uc.returningToday().map { it.id })

        today = d("2026-12-14")
        assertTrue(uc.returningToday().isEmpty())
    }

    @Test
    fun haVueltoTerminaAyerOBorraSiEmpezoHoy() = runTest {
        val repo = FakeRepository()
        val uc = useCase(repo) { d("2026-11-26") }
        val old = uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-11-10")), 1_000, "ipad")
        val returned = uc.markReturned(old.id, 2_000, "ipad")!!
        assertEquals(d("2026-11-25"), returned.endsOn)
        assertFalse(returned.isDeleted)
        assertFalse(ana in repo.flagged)

        val mistake = uc.save(StudentInjuryDraft(studentId = pablo, startsOn = d("2026-11-26")), 3_000, "ipad")
        assertTrue(uc.markReturned(mistake.id, 4_000, "ipad")!!.isDeleted)
        assertFalse(pablo in repo.flagged)
        assertTrue(uc.listForStudent(pablo).isEmpty())
    }

    @Test
    fun noVuelveHoySiTieneOtraLesionActiva() = runTest {
        val repo = FakeRepository()
        val uc = useCase(repo) { d("2026-12-13") }
        uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-11-26"), endsOn = d("2026-12-12")), 1_000, "ipad")
        uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-12-13")), 2_000, "ipad")
        assertTrue(uc.returningToday().isEmpty())
        assertEquals(d("2026-12-13"), uc.activeToday()[ana]?.startsOn)
    }

    @Test
    fun elInterruptorRapidoCreaYTerminaLesiones() = runTest {
        val repo = FakeRepository()
        val uc = useCase(repo) { d("2026-11-26") }
        val created = uc.setInjured(ana, injured = true, nowEpochMs = 1_000, deviceId = "mac")
        assertEquals(1, created.size)
        assertNull(created.single().endsOn)
        assertTrue(uc.setInjured(ana, injured = true, nowEpochMs = 2_000, deviceId = "mac").isEmpty())
        assertTrue(ana in repo.flagged)
        // La quitó el mismo día que la creó: se borra.
        assertTrue(uc.setInjured(ana, injured = false, nowEpochMs = 3_000, deviceId = "mac").single().isDeleted)
        assertFalse(ana in repo.flagged)
    }

    @Test
    fun laMarcaAntiguaSinLesionesNoSeTocaAlRecalcularPeroSePuedeQuitar() = runTest {
        val repo = FakeRepository()
        repo.flagged += pablo
        val uc = useCase(repo) { d("2026-11-26") }
        uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-11-26")), 1_000, "ipad")
        uc.reconcileFlags()
        assertTrue(pablo in repo.flagged)
        uc.setInjured(pablo, injured = false, nowEpochMs = 2_000, deviceId = "ipad")
        assertFalse(pablo in repo.flagged)
    }

    @Test
    fun borrarLaSacaDelHistorialYQuitaLaMarca() = runTest {
        val repo = FakeRepository()
        val uc = useCase(repo) { d("2026-11-26") }
        val injury = uc.save(StudentInjuryDraft(studentId = ana, startsOn = d("2026-11-20")), 1_000, "ipad")
        val deleted = uc.delete(injury.id, 2_000, "ipad")!!
        assertTrue(deleted.isDeleted)
        assertEquals(2L, deleted.trace.syncVersion)
        assertTrue(uc.listForStudent(ana).isEmpty())
        assertFalse(ana in repo.flagged)
    }
}
