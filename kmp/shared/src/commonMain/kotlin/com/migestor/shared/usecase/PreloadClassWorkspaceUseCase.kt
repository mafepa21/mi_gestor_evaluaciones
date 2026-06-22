package com.migestor.shared.usecase

import com.migestor.shared.domain.DashboardFilters
import com.migestor.shared.domain.DashboardMode
import com.migestor.shared.repository.AttendanceRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.DashboardOperationalRepository
import com.migestor.shared.repository.NotebookRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.supervisorScope
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.toLocalDateTime

data class ClassWorkspacePreloadResult(
    val classId: Long,
    val dashboardLoaded: Boolean,
    val notebookStructureLoaded: Boolean,
    val studentsLoaded: Boolean,
    val todayAttendanceLoaded: Boolean,
)

class PreloadClassWorkspaceUseCase internal constructor(
    private val preloadDashboard: suspend (classId: Long, date: LocalDate) -> Unit,
    private val preloadNotebookStructure: suspend (classId: Long) -> Unit,
    private val preloadStudents: suspend (classId: Long) -> Unit,
    private val preloadTodayAttendance: suspend (classId: Long, dayStartEpochMs: Long) -> Unit,
    private val todayProvider: () -> LocalDate = {
        Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
    },
    private val dayStartEpochMsProvider: (LocalDate) -> Long = { date ->
        date.atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds()
    },
) {
    constructor(
        dashboardOperationalRepository: DashboardOperationalRepository,
        notebookRepository: NotebookRepository,
        classesRepository: ClassesRepository,
        attendanceRepository: AttendanceRepository,
        notebookRowsPageSize: Long = 40,
    ) : this(
        preloadDashboard = { classId, date ->
            dashboardOperationalRepository.getSnapshot(
                date = date,
                mode = DashboardMode.OFFICE,
                filters = DashboardFilters(classId = classId),
            )
        },
        preloadNotebookStructure = { classId ->
            notebookRepository.loadNotebookSummary(classId)
            notebookRepository.listNotebookVisibleColumns(classId = classId, tabId = null)
            notebookRepository.listNotebookRowsPage(classId = classId, limit = notebookRowsPageSize, offset = 0)
        },
        preloadStudents = { classId ->
            classesRepository.listStudentsInClass(classId)
        },
        preloadTodayAttendance = { classId, dayStartEpochMs ->
            attendanceRepository.listAttendanceByDate(classId = classId, dateEpochMs = dayStartEpochMs)
        },
    )

    suspend operator fun invoke(classId: Long): ClassWorkspacePreloadResult = supervisorScope {
        val today = todayProvider()
        val dayStartEpochMs = dayStartEpochMsProvider(today)

        val dashboard = async { runCatching { preloadDashboard(classId, today) }.isSuccess }
        val notebookStructure = async { runCatching { preloadNotebookStructure(classId) }.isSuccess }
        val students = async { runCatching { preloadStudents(classId) }.isSuccess }
        val todayAttendance = async {
            runCatching { preloadTodayAttendance(classId, dayStartEpochMs) }.isSuccess
        }

        ClassWorkspacePreloadResult(
            classId = classId,
            dashboardLoaded = dashboard.await(),
            notebookStructureLoaded = notebookStructure.await(),
            studentsLoaded = students.await(),
            todayAttendanceLoaded = todayAttendance.await(),
        )
    }
}
