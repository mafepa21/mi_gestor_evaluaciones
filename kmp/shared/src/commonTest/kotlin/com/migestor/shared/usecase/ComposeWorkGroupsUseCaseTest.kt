package com.migestor.shared.usecase

import com.migestor.shared.domain.StudentSex
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ComposeWorkGroupsUseCaseTest {
    private val useCase = ComposeWorkGroupsUseCase()

    @Test
    fun `heterogeneous snake splits high and low averages`() {
        val students = (1L..6L).map { id ->
            WorkGroupStudentInput(studentId = id, average = 10.0 - id)
        }
        val groups = useCase.compose(
            students,
            WorkGroupComposeOptions(
                groupCount = 3,
                strategy = WorkGroupComposeStrategy.HETEROGENEOUS_GRADE,
                random = Random(1),
            ),
        )
        assertEquals(3, groups.size)
        assertEquals(listOf(1L, 6L), groups[0].studentIds)
        assertEquals(listOf(2L, 5L), groups[1].studentIds)
        assertEquals(listOf(3L, 4L), groups[2].studentIds)
    }

    @Test
    fun `homogeneous keeps similar averages together`() {
        val students = (1L..6L).map { id ->
            WorkGroupStudentInput(studentId = id, average = 10.0 - id)
        }
        val groups = useCase.compose(
            students,
            WorkGroupComposeOptions(
                groupCount = 3,
                strategy = WorkGroupComposeStrategy.HOMOGENEOUS_GRADE,
            ),
        )
        assertEquals(listOf(1L, 2L), groups[0].studentIds)
        assertEquals(listOf(3L, 4L), groups[1].studentIds)
        assertEquals(listOf(5L, 6L), groups[2].studentIds)
    }

    @Test
    fun `mix sex interleaves boys and girls`() {
        val students = listOf(
            WorkGroupStudentInput(1, 9.0, StudentSex.MALE),
            WorkGroupStudentInput(2, 8.0, StudentSex.MALE),
            WorkGroupStudentInput(3, 7.0, StudentSex.FEMALE),
            WorkGroupStudentInput(4, 6.0, StudentSex.FEMALE),
        )
        val groups = useCase.compose(
            students,
            WorkGroupComposeOptions(
                groupCount = 2,
                mixSex = true,
            ),
        )
        groups.forEach { group ->
            val members = students.filter { it.studentId in group.studentIds }
            assertEquals(1, members.count { it.sex == StudentSex.MALE })
            assertEquals(1, members.count { it.sex == StudentSex.FEMALE })
        }
    }

    @Test
    fun `injured students are spread across groups`() {
        val students = listOf(
            WorkGroupStudentInput(1, 9.0, isInjured = true),
            WorkGroupStudentInput(2, 8.0, isInjured = true),
            WorkGroupStudentInput(3, 7.0),
            WorkGroupStudentInput(4, 6.0),
        )
        val groups = useCase.compose(
            students,
            WorkGroupComposeOptions(
                groupCount = 2,
                spreadInjured = true,
                random = Random(2),
            ),
        )
        groups.forEach { group ->
            val injuredCount = students.count { it.studentId in group.studentIds && it.isInjured }
            assertTrue(injuredCount <= 1)
        }
    }

    @Test
    fun `groups stay as even as possible`() {
        val students = (1L..35L).map { id ->
            WorkGroupStudentInput(studentId = id, average = id.toDouble(), isInjured = id <= 3)
        }
        val groups = useCase.compose(
            students,
            WorkGroupComposeOptions(
                groupCount = 4,
                mixSex = true,
                spreadInjured = true,
                random = Random(7),
            ),
        )
        val sizes = groups.map { it.studentIds.size }
        assertEquals(35, sizes.sum())
        assertEquals(1, sizes.maxOrNull()!! - sizes.minOrNull()!!)
        assertTrue(sizes.all { it == 8 || it == 9 })
    }
}
