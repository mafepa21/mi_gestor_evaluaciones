package com.migestor.shared.attention

import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** «Alumnos invisibles»: ventana, no lectivos, altas recientes, «Visto» y orden. Datos inventados. */
class UnseenStudentsUseCaseTest {

    private fun d(iso: String) = LocalDate.parse(iso)

    private class FakeRepository(
        val students: List<AttentionStudent>,
        val contacts: List<ContactRecord> = emptyList(),
        val starts: Map<Long, LocalDate> = emptyMap(),
        val support: Set<Long> = emptySet(),
    ) : UnseenStudentsRepository {
        override suspend fun lastContacts(classId: Long) = contacts
        override suspend fun enrollmentStarts(classId: Long) = starts
        override suspend fun studentsWithSupportMeasure(classId: Long) = support
        override suspend fun students(classId: Long) = students
    }

    private val ana = AttentionStudent(1, "Ana López")
    private val pablo = AttentionStudent(2, "Pablo García")
    private val lucia = AttentionStudent(3, "Lucía Martín")
    private val marta = AttentionStudent(4, "Marta Sanz")

    @Test
    fun catorceDiasSinRegistroSaleYUnRegistroLoSaca() = runTest {
        val repo = FakeRepository(
            students = listOf(ana, pablo),
            contacts = listOf(
                ContactRecord(1, ContactKind.GRADE, d("2026-11-13"), "Hockey"), // 14 días antes del 27
                ContactRecord(2, ContactKind.GRADE, d("2026-11-14"), "Hockey"), // 13 días
            ),
        )
        val report = UnseenStudentsUseCase(repo) { d("2026-11-27") }.unseenForClass(10, emptyList(), emptyList())
        assertEquals(listOf(1L), report.unseen.map { it.studentId })
        assertEquals(14, report.unseen.single().daysSinceLast)
        assertEquals("Hockey", report.unseen.single().lastLabel)
        assertEquals(2, report.totalStudents)
    }

    @Test
    fun cuentaElRegistroMasRecienteDeCualquierTipo() = runTest {
        val repo = FakeRepository(
            students = listOf(ana),
            contacts = listOf(
                ContactRecord(1, ContactKind.GRADE, d("2026-10-01")),
                ContactRecord(1, ContactKind.OBSERVATION, d("2026-11-25")),
            ),
        )
        assertTrue(UnseenStudentsUseCase(repo) { d("2026-11-27") }.unseenForClass(10, emptyList(), emptyList()).unseen.isEmpty())
    }

    @Test
    fun lasVacacionesNoCuentan() = runTest {
        val repo = FakeRepository(
            students = listOf(ana),
            contacts = listOf(ContactRecord(1, ContactKind.GRADE, d("2026-12-18"))),
        )
        val christmas = (22..31).map { "2026-12-$it" } + (1..7).map { "2027-01-0$it" }
        val uc = UnseenStudentsUseCase(repo) { d("2027-01-08") }
        // 21 días naturales, pero 17 son no lectivos: solo cuentan 4.
        assertTrue(uc.unseenForClass(10, christmas, emptyList()).unseen.isEmpty())
        assertEquals(1, uc.unseenForClass(10, emptyList(), emptyList()).unseen.size)
    }

    @Test
    fun losRecienLlegadosNoSalenHastaCumplirElPlazo() = runTest {
        val repo = FakeRepository(
            students = listOf(ana, marta),
            starts = mapOf(1L to d("2026-11-20"), 4L to d("2026-09-10")),
        )
        val report = UnseenStudentsUseCase(repo) { d("2026-11-27") }.unseenForClass(10, emptyList(), emptyList())
        assertEquals(listOf(4L), report.unseen.map { it.studentId })
        assertEquals(-1, report.unseen.single().daysSinceLast)
        assertEquals(null, report.unseen.single().lastKind)
    }

    @Test
    fun vistoLoEscondeYElOrdenPoneDelanteMedidaYNunca() = runTest {
        val repo = FakeRepository(
            students = listOf(ana, pablo, lucia, marta),
            contacts = listOf(
                ContactRecord(1, ContactKind.GRADE, d("2026-11-10")), // 17
                ContactRecord(2, ContactKind.GRADE, d("2026-11-08")), // 19
                ContactRecord(3, ContactKind.GRADE, d("2026-11-11")), // 16
            ),
            support = setOf(3L),
        )
        val uc = UnseenStudentsUseCase(repo) { d("2026-11-27") }
        val all = uc.unseenForClass(10, emptyList(), emptyList()).unseen
        assertEquals(listOf(3L, 4L, 2L, 1L), all.map { it.studentId })
        assertTrue(all.first().hasSupportMeasure)
        assertEquals(listOf(3L, 4L, 1L), uc.unseenForClass(10, emptyList(), listOf(2L)).unseen.map { it.studentId })
    }

    @Test
    fun ultimoRegistroParaLaFicha() = runTest {
        val repo = FakeRepository(
            students = listOf(ana),
            contacts = listOf(ContactRecord(1, ContactKind.CELL_ENTRY, d("2026-11-25"), "Bádminton")),
        )
        val uc = UnseenStudentsUseCase(repo) { d("2026-11-27") }
        val summary = uc.lastContact(10, 1, emptyList())
        assertEquals(2, summary.daysSince)
        assertFalse(summary.isOverdue)
        assertEquals(ContactKind.CELL_ENTRY, summary.kind)
        assertEquals("2026-11-25", summary.dateIso)
        val none = uc.lastContact(10, 99, emptyList())
        assertEquals(-1, none.daysSince)
        assertTrue(none.isOverdue)
    }

    @Test
    fun unAltaRecienteConRegistrosAntiguosNoSaleTodavia() = runTest {
        val repo = FakeRepository(
            students = listOf(ana),
            contacts = listOf(ContactRecord(1, ContactKind.GRADE, d("2026-09-20"))),
            starts = mapOf(1L to d("2026-11-20")),
        )
        assertTrue(UnseenStudentsUseCase(repo) { d("2026-11-27") }.unseenForClass(10, emptyList(), emptyList()).unseen.isEmpty())
    }

    @Test
    fun diasContadosExcluyenElDiaDeInicio() {
        assertEquals(0, UnseenStudentsRules.countedDays(d("2026-11-27"), d("2026-11-27"), emptySet()))
        assertEquals(1, UnseenStudentsRules.countedDays(d("2026-11-26"), d("2026-11-27"), emptySet()))
        assertEquals(0, UnseenStudentsRules.countedDays(d("2026-11-26"), d("2026-11-27"), setOf(d("2026-11-27"))))
    }
}
