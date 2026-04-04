package com.migestor.data.repository

import com.migestor.shared.domain.AgendaItem
import com.migestor.shared.domain.AlertItem
import com.migestor.shared.domain.DashboardFilters
import com.migestor.shared.domain.DashboardMode
import com.migestor.shared.domain.DashboardSnapshot
import com.migestor.shared.domain.GroupSummary
import com.migestor.shared.domain.PEOperationalItem
import com.migestor.shared.domain.QuickActionCommand
import com.migestor.shared.domain.QuickActionResult
import com.migestor.shared.domain.QuickActionType
import com.migestor.shared.domain.TodaySessionItem
import com.migestor.shared.repository.AttendanceRepository
import com.migestor.shared.repository.CalendarRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.DashboardOperationalRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.IncidentsRepository
import com.migestor.shared.repository.PlannerRepository
import com.migestor.shared.repository.RubricsRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime
import kotlin.math.roundToInt

class DashboardOperationalRepositoryDefault(
    private val classesRepository: ClassesRepository,
    private val attendanceRepository: AttendanceRepository,
    private val evaluationsRepository: EvaluationsRepository,
    private val gradesRepository: GradesRepository,
    private val incidentsRepository: IncidentsRepository,
    private val calendarRepository: CalendarRepository,
    private val plannerRepository: PlannerRepository,
    private val rubricsRepository: RubricsRepository,
) : DashboardOperationalRepository {

    override suspend fun getSnapshot(
        date: LocalDate,
        mode: DashboardMode,
        filters: DashboardFilters,
    ): DashboardSnapshot {
        val now = Clock.System.now()
        val tz = TimeZone.currentSystemDefault()
        val dayStart = date.atStartOfDayIn(tz)
        val dayEnd = date.plus(1, DateTimeUnit.DAY).atStartOfDayIn(tz)
        val dateMinus7 = date.minus(7, DateTimeUnit.DAY).atStartOfDayIn(tz)
        val dateMinus30 = date.minus(30, DateTimeUnit.DAY).atStartOfDayIn(tz)

        val allClasses = classesRepository.listClasses()
        val targetClasses = filters.classId?.let { id -> allClasses.filter { it.id == id } } ?: allClasses
        val classNameById = allClasses.associateBy({ it.id }, { it.name })
        val studentsByClass = targetClasses.associate { it.id to classesRepository.listStudentsInClass(it.id) }
        val gradesByClass = targetClasses.associate { it.id to gradesRepository.listGradesForClass(it.id) }
        val evaluationsByClass = targetClasses.associate { it.id to evaluationsRepository.listClassEvaluations(it.id) }
        val incidencesByClass = targetClasses.associate { it.id to incidentsRepository.listIncidents(it.id) }
        val attendanceByClass = targetClasses.associate {
            it.id to attendanceRepository.getAttendanceForClassBetweenDates(
                classId = it.id,
                startDateMs = dateMinus30.toEpochMilliseconds(),
                endDateMs = dayEnd.toEpochMilliseconds(),
            )
        }

        val todayEvents = calendarRepository.listEvents(classId = null)
            .asSequence()
            .filter { event -> event.startAt >= dayStart && event.startAt < dayEnd }
            .filter { event -> filters.classId == null || event.classId == filters.classId }
            .map { event ->
                val start = event.startAt.toLocalDateTime(tz)
                val end = event.endAt.toLocalDateTime(tz)
                TodaySessionItem(
                    id = event.id,
                    classId = event.classId,
                    groupName = classNameById[event.classId] ?: "Grupo sin clase",
                    timeLabel = "${start.hour.toString().padStart(2, '0')}:${start.minute.toString().padStart(2, '0')} - ${end.hour.toString().padStart(2, '0')}:${end.minute.toString().padStart(2, '0')}",
                    didacticUnit = event.title,
                    space = extractSpace(event.description),
                    sessionStatus = resolveSessionStatus(event.startAt, event.endAt, event.title, event.description, now),
                )
            }
            .sortedBy { it.timeLabel }
            .toList()

        val filteredTodaySessions = todayEvents.filter { session ->
            filters.sessionStatus.isNullOrBlank() || session.sessionStatus.equals(filters.sessionStatus, ignoreCase = true)
        }

        val riskStudentByClass = mutableMapOf<Long, Set<Long>>()
        val alerts = mutableListOf<AlertItem>()
        targetClasses.forEach { schoolClass ->
            val classId = schoolClass.id
            val students = studentsByClass[classId].orEmpty()
            val grades = gradesByClass[classId].orEmpty()
            val evaluations = evaluationsByClass[classId].orEmpty()
            val incidents = incidencesByClass[classId].orEmpty()
            val attendance = attendanceByClass[classId].orEmpty()

            val attendanceByStudent = attendance.groupBy { it.studentId }
            val riskStudents = mutableSetOf<Long>()
            students.forEach { student ->
                val absences = attendanceByStudent[student.id].orEmpty()
                    .count { isAbsenceStatus(it.status) }
                if (absences >= 3) {
                    riskStudents += student.id
                    alerts += AlertItem(
                        id = "absence_${classId}_${student.id}",
                        classId = classId,
                        studentId = student.id,
                        type = "faltas_acumuladas",
                        title = "${student.fullName} con faltas acumuladas",
                        detail = "$absences faltas en los últimos 30 días",
                        severity = "high",
                        priority = "high",
                        count = absences,
                    )
                }
            }

            val gradesByStudentEval = grades.mapNotNull { grade ->
                val evalId = grade.evaluationId ?: return@mapNotNull null
                Pair("${grade.studentId}_$evalId", grade)
            }.toMap()

            students.forEach { student ->
                val pending = evaluations.count { eval ->
                    gradesByStudentEval["${student.id}_${eval.id}"]?.value == null
                }
                if (pending >= 2) {
                    riskStudents += student.id
                    alerts += AlertItem(
                        id = "pending_eval_${classId}_${student.id}",
                        classId = classId,
                        studentId = student.id,
                        type = "sin_evaluar",
                        title = "${student.fullName} sin evaluar",
                        detail = "$pending evaluaciones pendientes",
                        severity = "medium",
                        priority = "high",
                        count = pending,
                    )
                }
            }

            riskStudentByClass[classId] = riskStudents

            val pendingRubrics = (
                evaluations.count { it.rubricId != null } -
                    grades.count { it.evaluationId != null && evaluations.any { e -> e.id == it.evaluationId && e.rubricId != null } }
                ).coerceAtLeast(0)
            if (pendingRubrics > 0) {
                alerts += AlertItem(
                    id = "instrument_${classId}",
                    classId = classId,
                    type = "instrumentos_pendientes",
                    title = "Instrumentos pendientes",
                    detail = "$pendingRubrics rúbricas sin registrar",
                    severity = "medium",
                    priority = "medium",
                    count = pendingRubrics,
                )
            }

            val recentIncidents = incidents.filter { it.date >= dateMinus7 }
            if (recentIncidents.isNotEmpty()) {
                alerts += AlertItem(
                    id = "incident_${classId}",
                    classId = classId,
                    type = "incidencias_recientes",
                    title = "Incidencias recientes",
                    detail = "${recentIncidents.size} incidencias en los últimos 7 días",
                    severity = "high",
                    priority = "medium",
                    count = recentIncidents.size,
                )
            }

            if (recentIncidents.any { it.severity.equals("high", ignoreCase = true) || it.severity.equals("critical", ignoreCase = true) }) {
                alerts += AlertItem(
                    id = "family_${classId}",
                    classId = classId,
                    type = "familias_sin_comunicar",
                    title = "Familias por comunicar",
                    detail = "Revisar comunicación a familias por incidencias recientes",
                    severity = "medium",
                    priority = "medium",
                    count = 1,
                )
            }
        }

        val filteredAlerts = alerts
            .filter { filters.classId == null || it.classId == filters.classId }
            .filter { filters.severity.isNullOrBlank() || it.severity.equals(filters.severity, ignoreCase = true) }
            .filter { filters.priority.isNullOrBlank() || it.priority.equals(filters.priority, ignoreCase = true) }
            .sortedWith(compareByDescending<AlertItem> { priorityScore(it.priority) }.thenByDescending { severityScore(it.severity) }.thenBy { it.title })

        val groupSummaries = targetClasses.map { schoolClass ->
            val classId = schoolClass.id
            val students = studentsByClass[classId].orEmpty()
            val grades = gradesByClass[classId].orEmpty().filter { it.value != null }
            val evaluations = evaluationsByClass[classId].orEmpty()
            val attendance = attendanceByClass[classId].orEmpty()
            val totalRecords = attendance.size.coerceAtLeast(1)
            val presentRecords = attendance.count { it.status.equals("presente", ignoreCase = true) || it.status.equals("present", ignoreCase = true) }
            val attendancePct = ((presentRecords.toDouble() / totalRecords.toDouble()) * 100).roundToInt()

            val totalExpected = (students.size * evaluations.size).coerceAtLeast(1)
            val completedCount = grades.count { it.evaluationId != null }
            val evaluationCompletedPct = ((completedCount.toDouble() / totalExpected.toDouble()) * 100).roundToInt()
            val averageScore = grades.mapNotNull { it.value }.ifEmpty { listOf(0.0) }.average()
            val followUp = riskStudentByClass[classId].orEmpty().size
            val lastNotes = if (grades.isEmpty()) {
                "Sin notas recientes"
            } else {
                "${grades.takeLast(3).size} notas registradas"
            }
            GroupSummary(
                classId = classId,
                groupName = schoolClass.name,
                attendancePct = attendancePct,
                evaluationCompletedPct = evaluationCompletedPct,
                averageScore = (averageScore * 100.0).roundToInt() / 100.0,
                studentsInFollowUp = followUp,
                lastNotes = lastNotes,
            )
        }.sortedBy { it.groupName }

        val pendingAgenda = filteredAlerts.take(4).mapIndexed { index, alert ->
            AgendaItem(
                id = "agenda_alert_$index",
                classId = alert.classId,
                type = "recordatorio",
                title = alert.title,
                subtitle = alert.detail,
                timeLabel = "Hoy",
                status = "pendiente",
            )
        }
        val sessionAgenda = filteredTodaySessions.mapIndexed { index, session ->
            AgendaItem(
                id = "agenda_session_$index",
                classId = session.classId,
                type = "sesion",
                title = "${session.groupName} · ${session.didacticUnit}",
                subtitle = "Estado: ${session.sessionStatus}",
                timeLabel = session.timeLabel,
                status = session.sessionStatus,
            )
        }
        val plannerAgenda = plannerRepository.listSessionsInRange(
            groupId = filters.classId,
            fromDate = date,
            toDate = date.plus(1, DateTimeUnit.DAY)
        ).mapIndexed { index, session ->
            AgendaItem(
                id = "agenda_plan_$index",
                classId = session.groupId,
                type = "revision",
                title = "${session.groupName} · P${session.period}",
                subtitle = session.activities.ifBlank { session.objectives.ifBlank { "Sin detalle" } },
                timeLabel = "P${session.period}",
                status = session.status.label.lowercase(),
            )
        }
        val agendaItems = (sessionAgenda + plannerAgenda + pendingAgenda).distinctBy { it.id }.take(12)

        val quickColumns = evaluationsByClass.values.flatten()
            .sortedByDescending { it.trace.updatedAt }
            .map { it.name }
            .distinct()
            .take(5)
        val quickRubrics = rubricsRepository.listRubrics()
            .sortedByDescending { it.rubric.trace.updatedAt }
            .map { it.rubric.name }
            .distinct()
            .take(5)

        val peItems = buildPeItems(
            classes = targetClasses.map { it.id },
            sessions = filteredTodaySessions,
            studentsByClass = studentsByClass,
            incidencesByClass = incidencesByClass,
            evaluationsByClass = evaluationsByClass,
            since = dateMinus7,
        )

        val nextSession = calendarRepository.listEvents(classId = filters.classId)
            .filter { it.startAt >= now }
            .sortedBy { it.startAt }
            .firstOrNull()

        return DashboardSnapshot(
            mode = mode,
            filters = filters,
            todayCount = filteredTodaySessions.size,
            alertsCount = filteredAlerts.size,
            pendingCount = agendaItems.count { it.status.equals("pendiente", ignoreCase = true) },
            nextSessionLabel = nextSession?.let { event ->
                val local = event.startAt.toLocalDateTime(tz)
                val className = classNameById[event.classId] ?: "Sin grupo"
                "${local.hour.toString().padStart(2, '0')}:${local.minute.toString().padStart(2, '0')} · $className"
            } ?: "Sin próxima sesión",
            todaySessions = filteredTodaySessions,
            alerts = filteredAlerts,
            quickColumns = quickColumns,
            quickRubrics = quickRubrics,
            groupSummaries = groupSummaries,
            agendaItems = agendaItems,
            peItems = peItems,
        )
    }

    override suspend fun executeQuickAction(command: QuickActionCommand): QuickActionResult {
        val nowMs = Clock.System.now().toEpochMilliseconds()
        return when (command.type) {
            QuickActionType.PASS_LIST -> {
                val students = classesRepository.listStudentsInClass(command.classId)
                val status = command.attendanceStatus ?: "presente"
                students.forEach { student ->
                    attendanceRepository.saveAttendance(
                        studentId = student.id,
                        classId = command.classId,
                        dateEpochMs = nowMs,
                        status = status,
                        updatedAtEpochMs = nowMs,
                    )
                }
                QuickActionResult(
                    success = true,
                    message = "Lista registrada para ${students.size} alumnos",
                )
            }

            QuickActionType.REGISTER_OBSERVATION -> {
                incidentsRepository.saveIncident(
                    classId = command.classId,
                    studentId = command.studentId,
                    title = "Observación rápida",
                    detail = command.note ?: "Sin detalle",
                    severity = "low",
                    dateEpochMs = nowMs,
                    updatedAtEpochMs = nowMs,
                )
                QuickActionResult(success = true, message = "Observación registrada")
            }

            QuickActionType.QUICK_EVALUATION -> {
                val evaluationId = command.evaluationId
                    ?: return QuickActionResult(success = false, message = "Falta evaluationId")
                val studentId = command.studentId
                    ?: return QuickActionResult(success = false, message = "Falta studentId")
                gradesRepository.upsertGrade(
                    classId = command.classId,
                    studentId = studentId,
                    columnId = "eval_$evaluationId",
                    evaluationId = evaluationId,
                    value = command.score,
                    updatedAtEpochMs = nowMs,
                )
                QuickActionResult(success = true, message = "Evaluación rápida guardada")
            }
        }
    }

    private fun buildPeItems(
        classes: List<Long>,
        sessions: List<TodaySessionItem>,
        studentsByClass: Map<Long, List<com.migestor.shared.domain.Student>>,
        incidencesByClass: Map<Long, List<com.migestor.shared.domain.Incident>>,
        evaluationsByClass: Map<Long, List<com.migestor.shared.domain.Evaluation>>,
        since: Instant,
    ): List<PEOperationalItem> {
        val result = mutableListOf<PEOperationalItem>()

        val spaces = sessions.map { it.space }.filter { it.isNotBlank() && it != "Sin espacio" }.distinct()
        if (spaces.isNotEmpty()) {
            result += PEOperationalItem(
                id = "pe_spaces",
                classId = null,
                type = "espacios_ocupados",
                title = "Espacios ocupados hoy",
                detail = spaces.joinToString(", "),
                severity = "low",
            )
        }

        val injured = classes.flatMap { classId -> studentsByClass[classId].orEmpty().filter { it.isInjured } }
        if (injured.isNotEmpty()) {
            result += PEOperationalItem(
                id = "pe_exempt",
                classId = null,
                type = "exentos_adaptacion",
                title = "Alumnado exento/adaptación",
                detail = injured.take(5).joinToString(", ") { it.fullName },
                severity = "medium",
            )
        }

        val recentPhysicalIncidents = classes.flatMap { classId ->
            incidencesByClass[classId].orEmpty().filter {
                it.date >= since && (
                    it.title.contains("les", ignoreCase = true) ||
                        it.detail?.contains("les", ignoreCase = true) == true ||
                        it.title.contains("fís", ignoreCase = true) ||
                        it.detail?.contains("fís", ignoreCase = true) == true
                    )
            }
        }
        if (recentPhysicalIncidents.isNotEmpty()) {
            result += PEOperationalItem(
                id = "pe_incidents",
                classId = null,
                type = "incidencias_fisicas",
                title = "Incidencias físicas recientes",
                detail = "${recentPhysicalIncidents.size} incidencias en últimos 7 días",
                severity = "high",
            )
        }

        val activeTests = classes.flatMap { classId ->
            evaluationsByClass[classId].orEmpty().filter {
                it.rubricId != null ||
                    it.type.contains("prueba", ignoreCase = true) ||
                    it.name.contains("prueba", ignoreCase = true)
            }
        }
        if (activeTests.isNotEmpty()) {
            result += PEOperationalItem(
                id = "pe_tests",
                classId = null,
                type = "prueba_rubrica_activa",
                title = "Prueba/rúbrica activa",
                detail = activeTests.take(3).joinToString(", ") { it.name },
                severity = "medium",
            )
        }

        val materials = sessions
            .mapNotNull { session ->
                if (session.didacticUnit.contains("balon", ignoreCase = true)) "Balones"
                else if (session.didacticUnit.contains("gim", ignoreCase = true)) "Colchonetas"
                else null
            }
            .distinct()
        if (materials.isNotEmpty()) {
            result += PEOperationalItem(
                id = "pe_material",
                classId = null,
                type = "material_hoy",
                title = "Material necesario hoy",
                detail = materials.joinToString(", "),
                severity = "low",
            )
        }

        return result
    }

    private fun extractSpace(description: String?): String {
        if (description.isNullOrBlank()) return "Sin espacio"
        val trimmed = description.trim()
        val prefix = "espacio:"
        val lower = trimmed.lowercase()
        val index = lower.indexOf(prefix)
        if (index >= 0) {
            val value = trimmed.substring(index + prefix.length).trim()
            if (value.isNotBlank()) return value
        }
        return "Sin espacio"
    }

    private fun resolveSessionStatus(
        startAt: Instant,
        endAt: Instant,
        title: String,
        description: String?,
        now: Instant,
    ): String {
        if (endAt < now) return "cerrada"
        val text = (title + " " + (description ?: "")).lowercase()
        if (text.contains("incompleta") || text.contains("pendiente")) return "incompleta"
        if (text.contains("evalua") || text.contains("rúbrica") || text.contains("rubrica")) return "evaluable"
        if (startAt <= now && endAt >= now) return "evaluable"
        return "preparada"
    }

    private fun isAbsenceStatus(status: String): Boolean {
        val normalized = status.trim().lowercase()
        return normalized in setOf("ausente", "falta", "absent", "no asiste", "justificada")
    }

    private fun priorityScore(priority: String): Int = when (priority.lowercase()) {
        "high" -> 3
        "medium" -> 2
        "low" -> 1
        else -> 0
    }

    private fun severityScore(severity: String): Int = when (severity.lowercase()) {
        "critical" -> 4
        "high" -> 3
        "medium" -> 2
        "low" -> 1
        else -> 0
    }
}
