package com.migestor.shared.inclusion

import com.migestor.shared.domain.StudentSupportMeasure
import com.migestor.shared.domain.SupportMeasureIntensity
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.domain.SupportMeasureType
import com.migestor.shared.repository.InclusionTaskRepository
import com.migestor.shared.repository.StudentSupportMeasureRepository
import com.migestor.shared.usecase.InclusionTasksUseCase
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val YEAR = "2026-2027"
private const val CLASS_ID = 7L

class InclusionTasksUseCaseTest {

    private fun measure(id: Long, studentId: Long, type: SupportMeasureType, start: String, active: Boolean = true) =
        StudentSupportMeasure(
            id = id,
            studentId = studentId,
            level = if (type == SupportMeasureType.ACIS) SupportMeasureLevel.IV else SupportMeasureLevel.III,
            measureType = type,
            startDate = LocalDate.parse(start),
            isActive = active,
        )

    private fun fixture(measures: List<StudentSupportMeasure>, students: List<Long> = listOf(1L, 2L, 3L)): Pair<InclusionTasksUseCase, FakeTasks> {
        val tasks = FakeTasks()
        val useCase = InclusionTasksUseCase(tasks, FakeMeasures(measures), studentIdsForClass = { students })
        return useCase to tasks
    }

    @Test
    fun generarEsIdempotenteYNoPisaLoMarcado() = runTest {
        val (useCase, repo) = fixture(
            listOf(
                measure(10, 1, SupportMeasureType.ACIS, "2026-09-20"),
                measure(11, 2, SupportMeasureType.ACC_MESA_ADAPTADA, "2025-10-01"),
            )
        )
        val first = useCase.generateForClass(CLASS_ID, YEAR, nowEpochMs = 1)
        // Alumno 1 (ACIS nueva): 4 comunes + Doc1 + Doc2 + Doc7 + PAPACIS = 8.
        // Alumno 2 (medida de otro curso): 4 comunes. Alumno 3 sin medidas: nada.
        assertEquals(12, first)
        val keys1 = repo.rows.values.filter { it.studentId == 1L }.map { it.templateKey }.toSet()
        assertTrue("papacis:10" in keys1)
        assertTrue(InclusionManual.KEY_DOC1 in keys1)
        assertFalse(repo.rows.values.any { it.studentId == 2L && it.templateKey == InclusionManual.KEY_DOC1 })

        val carpeta = repo.rows.values.first { it.studentId == 1L && it.templateKey == InclusionManual.KEY_CARPETA_ROJA }
        useCase.toggleDone(carpeta.id, LocalDate(2026, 9, 12), nowEpochMs = 2)

        val second = useCase.generateForClass(CLASS_ID, YEAR, nowEpochMs = 3)
        assertEquals(0, second)
        assertEquals(12, repo.rows.size)
        assertEquals(LocalDate(2026, 9, 12), repo.rows.getValue(carpeta.id).doneAt)
    }

    @Test
    fun doc1NoSeGeneraSiHuboMedidaFirmadaOtroCurso() = runTest {
        val (useCase, repo) = fixture(
            listOf(
                measure(20, 1, SupportMeasureType.APR_FORMATO_EXAMEN, "2026-09-25"),
                measure(21, 1, SupportMeasureType.APR_UBICACION_AULA, "2024-10-01", active = false),
            )
        )
        useCase.generateForClass(CLASS_ID, YEAR, nowEpochMs = 1)
        val keys = repo.rows.values.map { it.templateKey }.toSet()
        assertFalse(InclusionManual.KEY_DOC1 in keys)
        assertTrue(InclusionManual.KEY_DOC2 in keys)
    }

    @Test
    fun recalcularMueveSoloLasNoEditadas() = runTest {
        val (useCase, repo) = fixture(
            listOf(
                measure(10, 1, SupportMeasureType.ACC_MESA_ADAPTADA, "2025-10-01"),
                measure(11, 2, SupportMeasureType.ACC_MESA_ADAPTADA, "2025-10-01"),
            )
        )
        useCase.generateForClass(CLASS_ID, YEAR, nowEpochMs = 1)
        val doc4a = repo.rows.values.first { it.studentId == 1L && it.templateKey == InclusionManual.KEY_DOC4 }
        val doc4b = repo.rows.values.first { it.studentId == 2L && it.templateKey == InclusionManual.KEY_DOC4 }
        // Por defecto: 22/10 + 3 días.
        assertEquals(LocalDate(2026, 10, 25), doc4a.dueDate)

        useCase.setDueDate(doc4b.id, CLASS_ID, LocalDate(2026, 11, 2), nowEpochMs = 2)
        assertTrue(repo.rows.getValue(doc4b.id).dueIsCustom)

        val moved = useCase.setInitialEvaluationDate(CLASS_ID, YEAR, LocalDate(2026, 10, 29), nowEpochMs = 3)
        assertEquals(1, moved)
        assertEquals(LocalDate(2026, 11, 1), repo.rows.getValue(doc4a.id).dueDate)
        assertEquals(LocalDate(2026, 11, 2), repo.rows.getValue(doc4b.id).dueDate)
        // Las tareas de fecha fija no se mueven.
        val itaca = repo.rows.values.first { it.studentId == 1L && it.templateKey == InclusionManual.KEY_ITACA }
        assertEquals(LocalDate(2026, 11, 20), itaca.dueDate)
    }

    @Test
    fun restablecerVuelveALaFechaDelManualActual() = runTest {
        val (useCase, repo) = fixture(listOf(measure(10, 1, SupportMeasureType.ACC_MESA_ADAPTADA, "2025-10-01")))
        useCase.generateForClass(CLASS_ID, YEAR, nowEpochMs = 1)
        val doc4 = repo.rows.values.first { it.templateKey == InclusionManual.KEY_DOC4 }

        useCase.setDueDate(doc4.id, CLASS_ID, LocalDate(2026, 12, 1), nowEpochMs = 2)
        useCase.setInitialEvaluationDate(CLASS_ID, YEAR, LocalDate(2026, 10, 27), nowEpochMs = 3)
        assertEquals(LocalDate(2026, 12, 1), repo.rows.getValue(doc4.id).dueDate)

        assertTrue(useCase.resetDueDate(doc4.id, CLASS_ID, nowEpochMs = 4))
        val reset = repo.rows.getValue(doc4.id)
        assertEquals(LocalDate(2026, 10, 30), reset.dueDate)
        assertFalse(reset.dueIsCustom)

        // Elegir justo la fecha del manual no cuenta como editada.
        useCase.setDueDate(doc4.id, CLASS_ID, LocalDate(2026, 10, 30), nowEpochMs = 5)
        assertFalse(repo.rows.getValue(doc4.id).dueIsCustom)
    }

    @Test
    fun tareaLibreNoSeRestableceNiSeRecalcula() = runTest {
        val (useCase, repo) = fixture(emptyList())
        val id = useCase.addFreeTask(1, "  Llamar a la familia ", InclusionPhase.OBSERVAR, LocalDate(2026, 10, 5), YEAR, nowEpochMs = 1)
        assertEquals("Llamar a la familia", repo.rows.getValue(id).title)
        assertNull(repo.rows.getValue(id).templateKey)
        assertFalse(useCase.resetDueDate(id, CLASS_ID, nowEpochMs = 2))
        assertEquals(0, useCase.setInitialEvaluationDate(CLASS_ID, YEAR, LocalDate(2026, 10, 1), nowEpochMs = 3))
    }

    @Test
    fun tareaLibreParaVariosAlumnosCreaUnaPorAlumno() = runTest {
        val (useCase, repo) = fixture(emptyList())
        val ids = useCase.addFreeTasks(listOf(1, 2, 2, 3), " Reunión ", InclusionPhase.NOVIEMBRE, LocalDate(2026, 11, 3), YEAR, nowEpochMs = 1, notes = "nota")
        assertEquals(3, ids.size)
        assertEquals(listOf(1L, 2L, 3L), ids.map { repo.rows.getValue(it).studentId })
        assertTrue(ids.all { repo.rows.getValue(it).title == "Reunión" && repo.rows.getValue(it).notes == "nota" && repo.rows.getValue(it).templateKey == null })
    }

    @Test
    fun tareaLibreParaVariosRechazaTituloVacioOSinAlumnos() = runTest {
        val (useCase, repo) = fixture(emptyList())
        assertFailsWith<IllegalArgumentException> {
            useCase.addFreeTasks(listOf(1), "  ", InclusionPhase.OBSERVAR, LocalDate(2026, 10, 5), YEAR, nowEpochMs = 1)
        }
        assertFailsWith<IllegalArgumentException> {
            useCase.addFreeTasks(emptyList(), "x", InclusionPhase.OBSERVAR, LocalDate(2026, 10, 5), YEAR, nowEpochMs = 1)
        }
        assertTrue(repo.rows.isEmpty())
    }

    @Test
    fun estadosDePlazoConEstaSemanaIgualASieteDias() {
        val today = LocalDate(2026, 10, 8)
        fun task(due: LocalDate, done: LocalDate? = null) = InclusionTask(
            1, 1, null, null, "t", InclusionPhase.OBSERVAR, due, false, done, "", YEAR, 0, 0,
        )
        assertEquals(InclusionDeadlineStatus.OVERDUE, InclusionManual.status(task(LocalDate(2026, 10, 7)), today))
        assertEquals(InclusionDeadlineStatus.SOON, InclusionManual.status(task(today), today))
        assertEquals(InclusionDeadlineStatus.SOON, InclusionManual.status(task(LocalDate(2026, 10, 15)), today))
        assertEquals(InclusionDeadlineStatus.NORMAL, InclusionManual.status(task(LocalDate(2026, 10, 16)), today))
        assertEquals(InclusionDeadlineStatus.DONE, InclusionManual.status(task(LocalDate(2026, 10, 1), done = today), today))

        val summary = InclusionManual.summary(
            listOf(task(LocalDate(2026, 10, 1)), task(LocalDate(2026, 10, 10)), task(LocalDate(2026, 10, 2), done = today)),
            today,
        )
        assertEquals(InclusionSummary(overdue = 1, dueThisWeek = 1), summary)
    }

    @Test
    fun fechasFijasCaenEnElAnoCorrectoDelCurso() {
        assertEquals(LocalDate(2026, 12, 18), InclusionManual.manualDue(InclusionDueRule.Fixed(12, 18), YEAR, LocalDate(2026, 10, 22)))
        assertEquals(LocalDate(2027, 2, 1), InclusionManual.manualDue(InclusionDueRule.Fixed(2, 1), YEAR, LocalDate(2026, 10, 22)))
        assertEquals("2026-2027", InclusionManual.schoolYearFor(LocalDate(2026, 9, 1)))
        assertEquals("2025-2026", InclusionManual.schoolYearFor(LocalDate(2026, 8, 31)))
    }

    @Test
    fun tableroResumeVencidasYEstaSemana() = runTest {
        val (useCase, _) = fixture(listOf(measure(10, 1, SupportMeasureType.ACC_MESA_ADAPTADA, "2025-10-01")))
        useCase.generateForClass(CLASS_ID, YEAR, nowEpochMs = 1)
        val board = useCase.loadBoard(CLASS_ID, YEAR, today = LocalDate(2026, 10, 20))
        assertEquals(1, board.students.size)
        // Carpeta roja (15/09) vencida; Doc4 (25/10) esta semana.
        assertEquals(InclusionSummary(overdue = 1, dueThisWeek = 1), board.summary)
        assertTrue(board.students.single().items.none { it.isEdited })
    }
}

private class FakeMeasures(private val all: List<StudentSupportMeasure>) : StudentSupportMeasureRepository {
    override suspend fun listByStudent(studentId: Long) = all.filter { it.studentId == studentId }
    override suspend fun listActiveStudentIds() = all.filter { it.isActive }.map { it.studentId }.toSet()
    override suspend fun save(
        id: Long?, studentId: Long, level: SupportMeasureLevel, measureType: SupportMeasureType, startDateIso: String,
        endDateIso: String?, responsible: String?, intensity: SupportMeasureIntensity?, followUpNotes: String,
        documentRef: String?, reviewDueIso: String?, isActive: Boolean, createdAtEpochMs: Long, updatedAtEpochMs: Long,
        deviceId: String?, syncVersion: Long,
    ): Long = error("no usado")
    override suspend fun retire(id: Long, endDateIso: String, updatedAtEpochMs: Long, deviceId: String?) = error("no usado")
    override suspend fun delete(id: Long) = error("no usado")
}

/** Doble en memoria que respeta UNIQUE(student_id, template_key, school_year) y due_is_custom. */
private class FakeTasks : InclusionTaskRepository {
    val rows = linkedMapOf<Long, InclusionTask>()
    private val evalDates = mutableMapOf<Pair<Long, String>, String>()
    private var nextId = 1L

    override suspend fun listByStudents(studentIds: List<Long>, schoolYear: String) =
        rows.values.filter { it.studentId in studentIds && it.schoolYear == schoolYear }

    override suspend fun getById(id: Long) = rows[id]

    override suspend fun insertTemplateIfAbsent(
        studentId: Long, measureId: Long?, templateKey: String, title: String, phase: InclusionPhase,
        dueDateIso: String, schoolYear: String, nowEpochMs: Long,
    ): Boolean {
        if (rows.values.any { it.studentId == studentId && it.templateKey == templateKey && it.schoolYear == schoolYear }) return false
        val id = nextId++
        rows[id] = InclusionTask(id, studentId, measureId, templateKey, title, phase, LocalDate.parse(dueDateIso), false, null, "", schoolYear, nowEpochMs, nowEpochMs)
        return true
    }

    override suspend fun insertFreeTask(
        studentId: Long, title: String, phase: InclusionPhase, dueDateIso: String, notes: String, schoolYear: String, nowEpochMs: Long,
    ): Long {
        val id = nextId++
        rows[id] = InclusionTask(id, studentId, null, null, title, phase, LocalDate.parse(dueDateIso), false, null, notes, schoolYear, nowEpochMs, nowEpochMs)
        return id
    }

    override suspend fun insertFreeTasks(
        studentIds: List<Long>, title: String, phase: InclusionPhase, dueDateIso: String, notes: String, schoolYear: String, nowEpochMs: Long,
    ): List<Long> = studentIds.map { insertFreeTask(it, title, phase, dueDateIso, notes, schoolYear, nowEpochMs) }

    override suspend fun setDone(id: Long, doneAtIso: String?, nowEpochMs: Long) {
        rows[id] = rows.getValue(id).copy(doneAt = doneAtIso?.let(LocalDate::parse), updatedAtEpochMs = nowEpochMs)
    }

    override suspend fun setDue(id: Long, dueDateIso: String, isCustom: Boolean, nowEpochMs: Long) {
        rows[id] = rows.getValue(id).copy(dueDate = LocalDate.parse(dueDateIso), dueIsCustom = isCustom, updatedAtEpochMs = nowEpochMs)
    }

    override suspend fun updateDueIfNotCustom(id: Long, dueDateIso: String, nowEpochMs: Long): Boolean {
        val task = rows.getValue(id)
        if (task.dueIsCustom) return false
        rows[id] = task.copy(dueDate = LocalDate.parse(dueDateIso), updatedAtEpochMs = nowEpochMs)
        return true
    }

    override suspend fun delete(id: Long) { rows.remove(id) }

    override suspend fun getInitialEvaluationDate(classId: Long, schoolYear: String) = evalDates[classId to schoolYear]

    override suspend fun setInitialEvaluationDate(classId: Long, schoolYear: String, dateIso: String) {
        evalDates[classId to schoolYear] = dateIso
    }
}
