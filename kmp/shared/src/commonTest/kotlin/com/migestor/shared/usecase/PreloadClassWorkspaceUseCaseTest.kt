package com.migestor.shared.usecase

import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PreloadClassWorkspaceUseCaseTest {
    @Test
    fun `preloads only critical class workspace data`() = runTest {
        val calls = mutableListOf<String>()
        val useCase = PreloadClassWorkspaceUseCase(
            preloadDashboard = { classId, date ->
                calls += "dashboard:$classId:$date"
            },
            preloadNotebookStructure = { classId ->
                calls += "notebook-structure:$classId"
            },
            preloadStudents = { classId ->
                calls += "students:$classId"
            },
            preloadTodayAttendance = { classId, dayStartEpochMs ->
                calls += "today-attendance:$classId:$dayStartEpochMs"
            },
            todayProvider = { LocalDate(2026, 6, 19) },
            dayStartEpochMsProvider = { 1_797_619_200_000L },
        )

        val result = useCase(classId = 42L)

        assertEquals(42L, result.classId)
        assertTrue(result.dashboardLoaded)
        assertTrue(result.notebookStructureLoaded)
        assertTrue(result.studentsLoaded)
        assertTrue(result.todayAttendanceLoaded)
        assertEquals(
            listOf(
                "dashboard:42:2026-06-19",
                "notebook-structure:42",
                "students:42",
                "today-attendance:42:1797619200000",
            ).sorted(),
            calls.sorted(),
        )
    }

    @Test
    fun `returns partial preload flags when one source fails`() = runTest {
        val calls = mutableListOf<String>()
        val useCase = PreloadClassWorkspaceUseCase(
            preloadDashboard = { classId, _ ->
                calls += "dashboard:$classId"
            },
            preloadNotebookStructure = {
                calls += "notebook-structure"
                error("Notebook structure unavailable")
            },
            preloadStudents = { classId ->
                calls += "students:$classId"
            },
            preloadTodayAttendance = { classId, _ ->
                calls += "today-attendance:$classId"
            },
            todayProvider = { LocalDate(2026, 6, 19) },
            dayStartEpochMsProvider = { 1_797_619_200_000L },
        )

        val result = useCase(classId = 7L)

        assertEquals(7L, result.classId)
        assertTrue(result.dashboardLoaded)
        assertFalse(result.notebookStructureLoaded)
        assertTrue(result.studentsLoaded)
        assertTrue(result.todayAttendanceLoaded)
        assertEquals(
            listOf("dashboard:7", "notebook-structure", "students:7", "today-attendance:7").sorted(),
            calls.sorted(),
        )
    }
}
