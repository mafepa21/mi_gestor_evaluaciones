package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookCell
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.workgroup.WorkGroupMark
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Reparto «Por nivel técnico» y sugerencia de columnas. Alumnado inventado. */
class ComposeWorkGroupsBySkillTest {
    private val useCase = ComposeWorkGroupsUseCase()

    private fun skillOptions(groupCount: Int, mixSex: Boolean = false) = WorkGroupComposeOptions(
        groupCount = groupCount,
        strategy = WorkGroupComposeStrategy.SKILL_LEVEL,
        mixSex = mixSex,
    )

    private fun techniqueMeans(groups: List<ComposedWorkGroup>, byId: Map<Long, WorkGroupStudentInput>) =
        groups.map { group -> group.studentIds.map { byId.getValue(it).skillLevel }.average() }

    @Test
    fun `las medias de tecnica de los grupos se parecen y los tamanos son iguales`() {
        val students = (1L..12L).map { WorkGroupStudentInput(studentId = it, technique = it.toDouble() * 0.8) }
        val groups = useCase.compose(students, skillOptions(groupCount = 3))
        val means = techniqueMeans(groups, students.associateBy { it.studentId })
        assertTrue(means.max() - means.min() <= 0.6, "Medias: $means")
        assertEquals(listOf(4, 4, 4), groups.map { it.studentIds.size })
        assertEquals((1L..12L).toSet(), groups.flatMap { it.studentIds }.toSet())
    }

    @Test
    fun `cada grupo tiene un lider si hay lideres suficientes`() {
        val students = (1L..12L).map { id ->
            WorkGroupStudentInput(
                studentId = id,
                technique = 5.0,
                leadership = if (id <= 3) 9.0 else 3.0 + id / 10.0,
            )
        }
        val groups = useCase.compose(students, skillOptions(groupCount = 3, mixSex = true))
        groups.forEach { group ->
            assertEquals(1, group.studentIds.count { it <= 3 }, "Grupo sin un líder: ${group.studentIds}")
        }
    }

    @Test
    fun `un lider lesionado sigue contando como lider de su grupo`() {
        val students = (1L..9L).map { id ->
            WorkGroupStudentInput(
                studentId = id,
                technique = 5.0,
                leadership = if (id <= 3) 9.0 - id / 10.0 else 2.0,
                isInjured = id == 1L || id == 2L,
            )
        }
        val groups = useCase.compose(students, skillOptions(groupCount = 3))
        groups.forEach { group ->
            assertEquals(1, group.studentIds.count { it <= 3 }, "Líderes: ${group.studentIds}")
        }
        groups.forEach { group -> assertTrue(group.studentIds.count { it == 1L || it == 2L } <= 1) }
    }

    @Test
    fun `el comportamiento bajo se reparte entre grupos`() {
        val students = (1L..9L).map { id ->
            WorkGroupStudentInput(studentId = id, technique = 10.0 - id, behaviour = if (id in setOf(1L, 2L, 3L)) 2.0 else 8.0)
        }
        val groups = useCase.compose(
            students,
            skillOptions(groupCount = 3).copy(oneLeaderPerGroup = false),
        )
        groups.forEach { group ->
            assertEquals(1, group.studentIds.count { it <= 3 }, "Comportamiento bajo junto: ${group.studentIds}")
        }
    }

    @Test
    fun `las marcas del docente mandan sobre la nota`() {
        val strong = WorkGroupStudentInput(studentId = 1, technique = 2.0, mark = WorkGroupMark.STRONG)
        val support = WorkGroupStudentInput(studentId = 2, technique = 9.0, mark = WorkGroupMark.SUPPORT)
        val noData = WorkGroupStudentInput(studentId = 3)
        val withAverage = WorkGroupStudentInput(studentId = 4, average = 7.0)
        assertEquals(WorkGroupStudentInput.STRONG_FLOOR, strong.skillLevel)
        assertEquals(WorkGroupStudentInput.SUPPORT_CEILING, support.skillLevel)
        assertEquals(WorkGroupStudentInput.NEUTRAL_LEVEL, noData.skillLevel)
        assertEquals(7.0, withAverage.skillLevel)
    }

    @Test
    fun `los fuertes marcados no acaban juntos`() {
        val students = (1L..8L).map { id ->
            WorkGroupStudentInput(
                studentId = id,
                technique = 5.0,
                mark = if (id <= 2) WorkGroupMark.STRONG else WorkGroupMark.NONE,
            )
        }
        val groups = useCase.compose(students, skillOptions(groupCount = 2))
        groups.forEach { assertEquals(1, it.studentIds.count { id -> id <= 2 }) }
    }

    @Test
    fun `mezclar sexos no rompe el equilibrio de tecnica`() {
        val students = (1L..8L).map { id ->
            WorkGroupStudentInput(
                studentId = id,
                technique = id.toDouble(),
                sex = if (id <= 4) StudentSex.MALE else StudentSex.FEMALE,
            )
        }
        val groups = useCase.compose(students, skillOptions(groupCount = 2, mixSex = true))
        val byId = students.associateBy { it.studentId }
        groups.forEach { group ->
            val males = group.studentIds.count { byId.getValue(it).sex == StudentSex.MALE }
            assertEquals(2, males, "Sexos: ${group.studentIds}")
        }
        val means = techniqueMeans(groups, byId)
        assertTrue(abs(means[0] - means[1]) <= 1.0, "Medias: $means")
    }

    @Test
    fun `el mismo curso da siempre los mismos grupos`() {
        val students = (1L..10L).map { WorkGroupStudentInput(studentId = it, technique = (it % 4).toDouble(), leadership = it.toDouble()) }
        assertEquals(
            useCase.compose(students, skillOptions(groupCount = 3)),
            useCase.compose(students.reversed(), skillOptions(groupCount = 3)),
        )
    }

    // ---- Columnas ----

    private fun column(id: String, title: String, type: NotebookColumnType = NotebookColumnType.RUBRIC, evaluationId: Long? = null) =
        NotebookColumnDefinition(id = id, title = title, type = type, evaluationId = evaluationId)

    @Test
    fun `sugiere columnas por nombre y por tipo de instrumento`() {
        val columns = listOf(
            column("c1", "Rúbrica técnica de pase"),
            column("c2", "Actitud en clase"),
            column("c3", "Examen teórico", NotebookColumnType.NUMERIC),
            column("c4", "Liderazgo en el juego"),
            column("c5", "Observación diaria").copy(instrumentKind = NotebookInstrumentKind.BEHAVIOUR),
            column("c6", "Técnica (antigua)").copy(visibility = NotebookColumnVisibility.ARCHIVED),
            column("c7", "Habilidad total", NotebookColumnType.CALCULATED),
        )
        assertEquals(listOf("c1"), WorkGroupSkillColumns.suggest(columns, WorkGroupSkillDimension.TECHNIQUE))
        assertEquals(listOf("c2", "c5"), WorkGroupSkillColumns.suggest(columns, WorkGroupSkillDimension.BEHAVIOUR))
        assertEquals(listOf("c4"), WorkGroupSkillColumns.suggest(columns, WorkGroupSkillDimension.LEADERSHIP))
        assertEquals(listOf("c1", "c2", "c3", "c4", "c5"), WorkGroupSkillColumns.candidates(columns).map { it.id })
    }

    @Test
    fun `la nota del apartado es la media de las columnas con nota`() {
        val columns = listOf(
            column("a", "Técnica 1", NotebookColumnType.NUMERIC, evaluationId = 1),
            column("b", "Técnica 2", NotebookColumnType.NUMERIC, evaluationId = 2),
        )
        fun row(id: Long, vararg cells: Pair<Long, Double?>) = NotebookRow(
            student = Student(id = id, firstName = "Alumno $id", lastName = "Inventado"),
            cells = cells.map { NotebookCell(it.first, it.second) },
            weightedAverage = null,
        )
        val rows = listOf(
            row(1, 1L to 6.0, 2L to 8.0),
            row(2, 1L to 4.0, 2L to null),
            row(3),
        )
        val scores = WorkGroupSkillColumns.scores(rows, columns, listOf("a", "b"))
        assertEquals(mapOf(1L to 7.0, 2L to 4.0), scores)
        assertTrue(WorkGroupSkillColumns.scores(rows, columns, emptyList()).isEmpty())
    }
}
