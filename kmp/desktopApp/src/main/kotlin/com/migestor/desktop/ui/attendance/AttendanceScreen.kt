package com.migestor.desktop.ui.attendance

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AssignmentInd
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.data.di.KmpContainer
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.SessionJournalIndividualNote
import com.migestor.shared.domain.Student
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.Month
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

private enum class RollCallViewMode { QUICK_LIST, GRID }

private data class RollCallDetailState(
    val student: Student,
    val todayRecord: Attendance?,
    val absences: Int,
    val lateness: Int,
    val incidents: List<Incident>,
    val grades: List<Grade>,
    val notes: List<String>,
)

private data class NoteDialogState(
    val student: Student,
    val attendance: Attendance?,
)

@Composable
fun AttendanceScreen(
    container: KmpContainer,
    scope: CoroutineScope,
    onStatus: (String) -> Unit
) {
    val classes by container.classesRepository.observeClasses().collectAsState(emptyList())
    var selectedClassId by remember { mutableStateOf<Long?>(null) }
    var currentDate by remember {
        mutableStateOf(Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date)
    }
    var viewMode by remember { mutableStateOf(RollCallViewMode.QUICK_LIST) }
    var searchQuery by remember { mutableStateOf("") }
    var filterOnlyAbsent by remember { mutableStateOf(false) }
    var filterOnlyIncidents by remember { mutableStateOf(false) }
    var monthView by remember { mutableStateOf(true) }
    var selectedStudentId by remember { mutableStateOf<Long?>(null) }
    var noteDialogState by remember { mutableStateOf<NoteDialogState?>(null) }

    var students by remember { mutableStateOf<List<Student>>(emptyList()) }
    var monthlyAttendance by remember { mutableStateOf<List<Attendance>>(emptyList()) }
    var incidents by remember { mutableStateOf<List<Incident>>(emptyList()) }
    var sessionsInMonth by remember { mutableStateOf<List<PlanningSession>>(emptyList()) }
    var detailGrades by remember { mutableStateOf<List<Grade>>(emptyList()) }

    val selectedClass = classes.find { it.id == selectedClassId }
    val tz = TimeZone.currentSystemDefault()
    LaunchedEffect(classes) {
        if (selectedClassId == null && classes.isNotEmpty()) {
            selectedClassId = classes.first().id
        }
    }

    LaunchedEffect(selectedClassId, currentDate) {
        val classId = selectedClassId ?: return@LaunchedEffect
        scope.launch {
            try {
                val loadedStudents = container.classesRepository.listStudentsInClass(classId)
                val range = currentMonthRange(currentDate)
                val loadedAttendance = container.attendanceRepository.getAttendanceForClassBetweenDates(
                    classId,
                    range.first.atStartOfDayIn(tz).toEpochMilliseconds(),
                    range.second.atStartOfDayIn(tz).toEpochMilliseconds()
                )
                students = loadedStudents
                monthlyAttendance = loadedAttendance
                incidents = container.incidentsRepository.listIncidents(classId)
                sessionsInMonth = container.plannerRepository.listSessionsInRange(classId, range.first, range.second)
                if (selectedStudentId == null) selectedStudentId = loadedStudents.firstOrNull()?.id
                onStatus("${loadedStudents.size} alumnos listos para pase")
            } catch (e: Exception) {
                onStatus("Error al cargar el pase de lista: ${e.message}")
            }
        }
    }

    LaunchedEffect(selectedClassId, selectedStudentId, monthlyAttendance, incidents) {
        val classId = selectedClassId ?: return@LaunchedEffect
        val studentId = selectedStudentId ?: return@LaunchedEffect
        scope.launch {
            detailGrades = runCatching {
                container.gradesRepository.listGradesForStudentInClass(studentId, classId)
            }.getOrDefault(emptyList())
        }
    }

    val attendanceByKey = remember(monthlyAttendance) {
        monthlyAttendance.associateBy { it.studentId to it.date.toLocalDateTime(tz).date }
    }
    val todayAttendance = remember(attendanceByKey, currentDate) {
        attendanceByKey.filterKeys { it.second == currentDate }.mapKeys { it.key.first }
    }
    val incidentsByStudent = remember(incidents) { incidents.groupBy { it.studentId } }
    val monthDates = remember(currentDate) { monthDatesFor(currentDate) }
    val sessionByDate = remember(sessionsInMonth) {
        sessionsInMonth.groupBy { sessionDate(it) }
    }

    fun recordFor(studentId: Long, date: LocalDate = currentDate): Attendance? = attendanceByKey[studentId to date]

    fun updateLocalAttendance(updated: Attendance) {
        val mutable = monthlyAttendance.toMutableList()
        val index = mutable.indexOfFirst {
            it.studentId == updated.studentId && it.date.toLocalDateTime(tz).date == updated.date.toLocalDateTime(tz).date
        }
        if (index >= 0) mutable[index] = updated else mutable += updated
        monthlyAttendance = mutable
    }

    fun currentSessionIdFor(date: LocalDate): Long? =
        sessionByDate[date]?.minByOrNull { it.period }?.id?.takeIf { it > 0 }

    fun persistAttendance(
        student: Student,
        date: LocalDate = currentDate,
        status: AttendanceStatus? = null,
        note: String? = null,
        hasIncident: Boolean? = null,
        followUp: Boolean? = null,
    ) {
        val existing = recordFor(student.id, date)
        val dateEpochMs = date.atStartOfDayIn(tz).toEpochMilliseconds()
        val newStatus = status?.code ?: existing?.status ?: AttendanceStatus.PRESENT.code
        val newNote = note ?: existing?.note ?: ""
        val newHasIncident = hasIncident ?: existing?.hasIncident ?: false
        val newFollowUp = followUp ?: existing?.followUpRequired ?: false
        val sessionId = existing?.sessionId ?: currentSessionIdFor(date)
        scope.launch {
            try {
                val savedId = container.attendanceRepository.saveAttendance(
                    id = existing?.id?.takeIf { it > 0 },
                    studentId = student.id,
                    classId = selectedClassId ?: return@launch,
                    dateEpochMs = dateEpochMs,
                    status = newStatus,
                    note = newNote,
                    hasIncident = newHasIncident,
                    followUpRequired = newFollowUp,
                    sessionId = sessionId,
                    updatedAtEpochMs = Clock.System.now().toEpochMilliseconds(),
                )
                updateLocalAttendance(
                    Attendance(
                        id = savedId,
                        studentId = student.id,
                        classId = selectedClassId ?: return@launch,
                        date = Instant.fromEpochMilliseconds(dateEpochMs),
                        status = newStatus,
                        note = newNote,
                        hasIncident = newHasIncident,
                        followUpRequired = newFollowUp,
                        sessionId = sessionId
                    )
                )
                onStatus("Pase guardado para ${student.fullName}")
            } catch (e: Exception) {
                onStatus("No se pudo guardar la asistencia: ${e.message}")
            }
        }
    }

    fun registerIncident(student: Student, detail: String) {
        val classId = selectedClassId ?: return
        val nowMs = Clock.System.now().toEpochMilliseconds()
        scope.launch {
            try {
                container.incidentsRepository.saveIncident(
                    classId = classId,
                    studentId = student.id,
                    title = "Incidencia desde pase",
                    detail = detail.ifBlank { "Registrada desde Pase de lista" },
                    severity = "medium",
                    dateEpochMs = nowMs,
                    updatedAtEpochMs = nowMs,
                )
                incidents = container.incidentsRepository.listIncidents(classId)
                persistAttendance(student, hasIncident = true, note = detail.ifBlank { recordFor(student.id)?.note ?: "" })
                onStatus("Incidencia registrada para ${student.fullName}")
            } catch (e: Exception) {
                onStatus("No se pudo registrar la incidencia: ${e.message}")
            }
        }
    }

    fun sendToJournal(student: Student) {
        val session = sessionByDate[currentDate]?.minByOrNull { it.period }
        if (session == null) {
            onStatus("No hay sesión planificada ese día para enviar al diario")
            return
        }
        val attendance = recordFor(student.id)
        val noteText = when {
            !attendance?.note.isNullOrBlank() -> attendance?.note ?: ""
            attendance != null -> "${student.fullName}: ${AttendanceStatus.fromCode(attendance.status).label}"
            else -> "${student.fullName}: seguimiento desde pase de lista"
        }
        scope.launch {
            try {
                val aggregate = container.sessionJournalRepository.getOrCreateJournal(session)
                val updated = aggregate.copy(
                    individualNotes = aggregate.individualNotes + SessionJournalIndividualNote(
                        studentId = student.id,
                        studentName = student.fullName,
                        note = noteText,
                        tag = if (attendance?.followUpRequired == true) "seguimiento" else "asistencia"
                    )
                )
                container.sessionJournalRepository.saveJournalAggregate(updated)
                onStatus("Anotación enviada al diario de aula")
            } catch (e: Exception) {
                onStatus("No se pudo enviar al diario: ${e.message}")
            }
        }
    }

    fun markAllPresent() {
        students.forEach { persistAttendance(it, status = AttendanceStatus.PRESENT) }
        onStatus("Todos marcados como presentes")
    }

    fun repeatLastSessionPattern() {
        val classId = selectedClassId ?: return
        scope.launch {
            val allAttendance = container.attendanceRepository.listAttendance(classId)
            val previousDate = allAttendance
                .map { it.date.toLocalDateTime(tz).date }
                .filter { it < currentDate }
                .maxOrNull()
            if (previousDate == null) {
                onStatus("No hay una sesión anterior para repetir")
                return@launch
            }
            allAttendance
                .filter { it.date.toLocalDateTime(tz).date == previousDate }
                .forEach { previous ->
                    val student = students.find { it.id == previous.studentId } ?: return@forEach
                    persistAttendance(
                        student = student,
                        status = AttendanceStatus.fromCode(previous.status),
                        note = previous.note,
                        hasIncident = previous.hasIncident,
                        followUp = previous.followUpRequired,
                    )
                }
            onStatus("Patrón copiado desde ${formatDate(previousDate)}")
        }
    }

    val filteredStudents = remember(students, searchQuery, filterOnlyAbsent, filterOnlyIncidents, todayAttendance, incidentsByStudent) {
        students.filter { student ->
            val currentRecord = todayAttendance[student.id]
            val matchesSearch = searchQuery.isBlank() ||
                student.fullName.contains(searchQuery, ignoreCase = true) ||
                student.lastName.contains(searchQuery, ignoreCase = true) ||
                student.firstName.contains(searchQuery, ignoreCase = true)
            val matchesAbsent = !filterOnlyAbsent || currentRecord?.status == AttendanceStatus.ABSENT.code
            val matchesIncident = !filterOnlyIncidents || currentRecord?.hasIncident == true || !incidentsByStudent[student.id].isNullOrEmpty()
            matchesSearch && matchesAbsent && matchesIncident
        }
    }

    val selectedStudent = students.find { it.id == selectedStudentId } ?: filteredStudents.firstOrNull()
    val detailState = remember(selectedStudent, todayAttendance, incidentsByStudent, detailGrades, monthlyAttendance) {
        selectedStudent?.let { student ->
            val history = monthlyAttendance.filter { it.studentId == student.id }
            RollCallDetailState(
                student = student,
                todayRecord = todayAttendance[student.id],
                absences = history.count { it.status == AttendanceStatus.ABSENT.code },
                lateness = history.count { it.status == AttendanceStatus.LATE.code },
                incidents = incidentsByStudent[student.id].orEmpty(),
                grades = detailGrades,
                notes = history.mapNotNull { it.note.takeIf(String::isNotBlank) }.distinct()
            )
        }
    }

    LaunchedEffect(filteredStudents, selectedStudentId) {
        if (selectedStudentId == null && filteredStudents.isNotEmpty()) {
            selectedStudentId = filteredStudents.first().id
        } else if (filteredStudents.isNotEmpty() && filteredStudents.none { it.id == selectedStudentId }) {
            selectedStudentId = filteredStudents.first().id
        }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        val wideLayout = maxWidth >= 1120.dp
        Row(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            horizontalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Column(
                modifier = Modifier.weight(1.8f).fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                RollCallHeader(
                    classes = classes,
                    selectedClass = selectedClass,
                    currentDate = currentDate,
                    viewMode = viewMode,
                    monthView = monthView,
                    searchQuery = searchQuery,
                    filterOnlyAbsent = filterOnlyAbsent,
                    filterOnlyIncidents = filterOnlyIncidents,
                    onSearchChange = { searchQuery = it },
                    onClassSelected = { selectedClassId = it },
                    onDateChanged = { currentDate = it },
                    onViewModeChanged = { viewMode = it },
                    onToggleMonthView = { monthView = !monthView },
                    onToggleOnlyAbsent = { filterOnlyAbsent = !filterOnlyAbsent },
                    onToggleOnlyIncidents = { filterOnlyIncidents = !filterOnlyIncidents },
                    onMarkAllPresent = { markAllPresent() },
                    onRepeatPattern = { repeatLastSessionPattern() }
                )

                RollCallSummaryCard(
                    students = filteredStudents,
                    todayAttendance = todayAttendance,
                    currentDate = currentDate,
                )

                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    if (filteredStudents.isEmpty()) {
                        EmptyRollCallState()
                    } else if (viewMode == RollCallViewMode.QUICK_LIST) {
                        QuickListContent(
                            students = filteredStudents,
                            selectedStudentId = selectedStudent?.id,
                            attendanceForToday = todayAttendance,
                            incidentsByStudent = incidentsByStudent,
                            onSelectStudent = { selectedStudentId = it.id },
                            onStatusSelected = { student, status -> persistAttendance(student, status = status) },
                            onOpenNoteDialog = { student -> noteDialogState = NoteDialogState(student, recordFor(student.id)) },
                            onToggleFollowUp = { student ->
                                val current = recordFor(student.id)
                                persistAttendance(student, followUp = !(current?.followUpRequired ?: false))
                            },
                            onRegisterIncident = { student ->
                                val detail = recordFor(student.id)?.note ?: "Incidencia registrada desde pase"
                                registerIncident(student, detail)
                            },
                            onSendToJournal = { student -> sendToJournal(student) }
                        )
                    } else {
                        GridContent(
                            students = filteredStudents,
                            dates = if (monthView) monthDates else listOf(currentDate),
                            attendanceByKey = attendanceByKey,
                            selectedStudentId = selectedStudent?.id,
                            onSelectStudent = { selectedStudentId = it.id },
                            onCycleStatus = { student, date ->
                                val current = recordFor(student.id, date)
                                persistAttendance(
                                    student = student,
                                    date = date,
                                    status = nextStatus(current?.status)
                                )
                            }
                        )
                    }
                }

                if (!wideLayout) {
                    RollCallDetailPanel(
                        modifier = Modifier.fillMaxWidth().heightIn(min = 300.dp),
                        detail = detailState,
                        onOpenNoteDialog = {
                            selectedStudent?.let { noteDialogState = NoteDialogState(it, recordFor(it.id)) }
                        },
                        onSendToJournal = { selectedStudent?.let(::sendToJournal) },
                    )
                }
            }

            if (wideLayout) {
                RollCallDetailPanel(
                    modifier = Modifier.weight(0.62f).fillMaxHeight(),
                    detail = detailState,
                    onOpenNoteDialog = {
                        selectedStudent?.let { noteDialogState = NoteDialogState(it, recordFor(it.id)) }
                    },
                    onSendToJournal = { selectedStudent?.let(::sendToJournal) },
                )
            }
        }
    }

    if (noteDialogState != null) {
        NoteDialog(
            state = noteDialogState!!,
            onDismiss = { noteDialogState = null },
            onSave = { text ->
                persistAttendance(
                    student = noteDialogState!!.student,
                    status = noteDialogState!!.attendance?.status?.let(AttendanceStatus::fromCode) ?: AttendanceStatus.OBSERVATION,
                    note = text
                )
                noteDialogState = null
            }
        )
    }
}

@Composable
private fun EmptyRollCallState() {
    OrganicGlassCard(modifier = Modifier.fillMaxSize(), cornerRadius = 24.dp) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text = "No hay alumnos que coincidan con el filtro actual.",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RollCallHeader(
    classes: List<SchoolClass>,
    selectedClass: SchoolClass?,
    currentDate: LocalDate,
    viewMode: RollCallViewMode,
    monthView: Boolean,
    searchQuery: String,
    filterOnlyAbsent: Boolean,
    filterOnlyIncidents: Boolean,
    onSearchChange: (String) -> Unit,
    onClassSelected: (Long) -> Unit,
    onDateChanged: (LocalDate) -> Unit,
    onViewModeChanged: (RollCallViewMode) -> Unit,
    onToggleMonthView: () -> Unit,
    onToggleOnlyAbsent: () -> Unit,
    onToggleOnlyIncidents: () -> Unit,
    onMarkAllPresent: () -> Unit,
    onRepeatPattern: () -> Unit,
) {
    OrganicGlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 24.dp) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Pase de lista",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.ExtraBold
                    )
                    Text(
                        text = "Toma asistencia rápida, abre ficha y envía incidencias o seguimiento sin salir del flujo.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(onClick = { onViewModeChanged(RollCallViewMode.QUICK_LIST) }) {
                        Text(if (viewMode == RollCallViewMode.QUICK_LIST) "Lista rápida activa" else "Lista rápida")
                    }
                    OutlinedButton(onClick = { onViewModeChanged(RollCallViewMode.GRID) }) {
                        Text(if (viewMode == RollCallViewMode.GRID) "Rejilla activa" else "Rejilla")
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = onSearchChange,
                    modifier = Modifier.weight(1f),
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    placeholder = { Text("Buscar alumno o alumna") },
                    singleLine = true,
                    shape = RoundedCornerShape(18.dp)
                )

                Box {
                    var expanded by remember { mutableStateOf(false) }
                    OutlinedButton(onClick = { expanded = true }) {
                        Icon(Icons.Default.Group, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(selectedClass?.name ?: "Seleccionar grupo")
                    }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        classes.forEach { schoolClass ->
                            DropdownMenuItem(
                                text = { Text(schoolClass.name) },
                                onClick = {
                                    expanded = false
                                    onClassSelected(schoolClass.id)
                                }
                            )
                        }
                    }
                }

                IconButton(onClick = { onDateChanged(currentDate.minus(1, DateTimeUnit.DAY)) }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Día anterior")
                }
                Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f)) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(formatDate(currentDate), fontWeight = FontWeight.SemiBold)
                    }
                }
                IconButton(onClick = { onDateChanged(currentDate.plus(1, DateTimeUnit.DAY)) }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Día siguiente")
                }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AssistChip(
                    onClick = {},
                    label = { Text("Filtro visible: nombre y apellidos del grupo seleccionado") },
                    leadingIcon = { Icon(Icons.Default.FactCheck, contentDescription = null, modifier = Modifier.size(18.dp)) }
                )
                FilterChip(selected = filterOnlyAbsent, onClick = onToggleOnlyAbsent, label = { Text("Solo ausentes") })
                FilterChip(selected = filterOnlyIncidents, onClick = onToggleOnlyIncidents, label = { Text("Solo incidencias") })
                FilterChip(selected = monthView, onClick = onToggleMonthView, label = { Text("Vista por mes") })
                Button(onClick = onMarkAllPresent) {
                    Icon(Icons.Default.Check, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Marcar todos presentes")
                }
                OutlinedButton(onClick = onRepeatPattern) {
                    Icon(Icons.Default.Repeat, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Repetir última sesión")
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RollCallSummaryCard(
    students: List<Student>,
    todayAttendance: Map<Long, Attendance>,
    currentDate: LocalDate,
) {
    val counts = AttendanceStatus.values().associateWith { status ->
        todayAttendance.values.count { it.status == status.code }
    }
    val followUp = todayAttendance.values.count { it.followUpRequired }
    val incidents = todayAttendance.values.count { it.hasIncident }
    val unregistered = students.size - todayAttendance.size

    OrganicGlassCard(modifier = Modifier.fillMaxWidth(), cornerRadius = 20.dp) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Resumen automático · ${formatDate(currentDate)}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SummaryChip("Presente", counts[AttendanceStatus.PRESENT] ?: 0, AttendanceStatus.PRESENT.color)
                SummaryChip("Ausente", counts[AttendanceStatus.ABSENT] ?: 0, AttendanceStatus.ABSENT.color)
                SummaryChip("Retraso", counts[AttendanceStatus.LATE] ?: 0, AttendanceStatus.LATE.color)
                SummaryChip("Incidencias", incidents, MaterialTheme.colorScheme.error)
                SummaryChip("Seguimiento", followUp, MaterialTheme.colorScheme.tertiary)
            }
            if (unregistered > 0) {
                Text(
                    text = "Quedan $unregistered alumnos sin registrar hoy.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun SummaryChip(label: String, value: Int, accent: Color) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = accent.copy(alpha = 0.14f)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value.toString(), fontWeight = FontWeight.ExtraBold, color = accent)
            Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun QuickListContent(
    students: List<Student>,
    selectedStudentId: Long?,
    attendanceForToday: Map<Long, Attendance>,
    incidentsByStudent: Map<Long?, List<Incident>>,
    onSelectStudent: (Student) -> Unit,
    onStatusSelected: (Student, AttendanceStatus) -> Unit,
    onOpenNoteDialog: (Student) -> Unit,
    onToggleFollowUp: (Student) -> Unit,
    onRegisterIncident: (Student) -> Unit,
    onSendToJournal: (Student) -> Unit,
) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items(students, key = { it.id }) { student ->
            val record = attendanceForToday[student.id]
            val currentStatus = record?.status?.let(AttendanceStatus::fromCode)
            StudentQuickRow(
                student = student,
                isSelected = selectedStudentId == student.id,
                currentStatus = currentStatus,
                hasIncident = record?.hasIncident == true || !incidentsByStudent[student.id].isNullOrEmpty(),
                followUp = record?.followUpRequired == true,
                note = record?.note.orEmpty(),
                onSelect = { onSelectStudent(student) },
                onStatusSelected = { onStatusSelected(student, it) },
                onOpenNoteDialog = { onOpenNoteDialog(student) },
                onToggleFollowUp = { onToggleFollowUp(student) },
                onRegisterIncident = { onRegisterIncident(student) },
                onSendToJournal = { onSendToJournal(student) },
            )
        }
    }
}

@Composable
private fun StudentQuickRow(
    student: Student,
    isSelected: Boolean,
    currentStatus: AttendanceStatus?,
    hasIncident: Boolean,
    followUp: Boolean,
    note: String,
    onSelect: () -> Unit,
    onStatusSelected: (AttendanceStatus) -> Unit,
    onOpenNoteDialog: () -> Unit,
    onToggleFollowUp: () -> Unit,
    onRegisterIncident: () -> Unit,
    onSendToJournal: () -> Unit,
) {
    OrganicGlassCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 20.dp,
        backgroundColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.24f) else MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().clickable { onSelect() }.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StudentAvatar(student = student)
                    Column {
                        Text(student.fullName, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            if (currentStatus != null) StatusBadge(currentStatus)
                            if (hasIncident) FlagBadge("Incidencia", MaterialTheme.colorScheme.error)
                            if (followUp) FlagBadge("Seguimiento", MaterialTheme.colorScheme.tertiary)
                        }
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    var menuExpanded by remember { mutableStateOf(false) }
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Default.MoreHoriz, contentDescription = "Más acciones")
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(text = { Text("Añadir motivo") }, onClick = { menuExpanded = false; onOpenNoteDialog() })
                        DropdownMenuItem(text = { Text("Registrar incidencia") }, onClick = { menuExpanded = false; onRegisterIncident() })
                        DropdownMenuItem(text = { Text("Marcar seguimiento") }, onClick = { menuExpanded = false; onToggleFollowUp() })
                        DropdownMenuItem(text = { Text("Abrir ficha") }, onClick = { menuExpanded = false; onSelect() })
                        DropdownMenuItem(text = { Text("Enviar al diario") }, onClick = { menuExpanded = false; onSendToJournal() })
                    }
                }
            }

            CompactStatusSelector(
                selectedStatus = currentStatus,
                onStatusSelected = onStatusSelected
            )

            if (note.isNotBlank()) {
                Text(
                    text = note,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun GridContent(
    students: List<Student>,
    dates: List<LocalDate>,
    attendanceByKey: Map<Pair<Long, LocalDate>, Attendance>,
    selectedStudentId: Long?,
    onSelectStudent: (Student) -> Unit,
    onCycleStatus: (Student, LocalDate) -> Unit,
) {
    val horizontal = rememberScrollState()
    val vertical = rememberScrollState()
    OrganicGlassCard(modifier = Modifier.fillMaxSize(), cornerRadius = 24.dp) {
        Column(
            modifier = Modifier.fillMaxSize().horizontalScroll(horizontal).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    modifier = Modifier.width(220.dp),
                    color = Color.Transparent
                ) { Text("Alumno", fontWeight = FontWeight.Bold, modifier = Modifier.padding(8.dp)) }
                dates.forEach { date ->
                    Surface(
                        modifier = Modifier.width(56.dp),
                        shape = RoundedCornerShape(12.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 8.dp)) {
                            Text(shortWeekday(date.dayOfWeek), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(date.dayOfMonth.toString(), fontWeight = FontWeight.Bold)
                        }
                    }
                    Spacer(modifier = Modifier.width(6.dp))
                }
            }

            Column(modifier = Modifier.verticalScroll(vertical), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                students.forEach { student ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(
                            modifier = Modifier.width(220.dp).clickable { onSelectStudent(student) },
                            shape = RoundedCornerShape(16.dp),
                            color = if (selectedStudentId == student.id) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.24f) else Color.Transparent
                        ) {
                            Text(
                                text = student.fullName,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 14.dp),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                fontWeight = if (selectedStudentId == student.id) FontWeight.Bold else FontWeight.Medium
                            )
                        }
                        dates.forEach { date ->
                            val record = attendanceByKey[student.id to date]
                            val status = record?.status?.let(AttendanceStatus::fromCode)
                            Surface(
                                modifier = Modifier
                                    .width(56.dp)
                                    .height(52.dp)
                                    .clickable { onCycleStatus(student, date) },
                                shape = RoundedCornerShape(14.dp),
                                color = status?.color?.copy(alpha = 0.18f) ?: MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.20f)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Text(
                                        text = status?.shortLabel ?: "·",
                                        fontWeight = FontWeight.ExtraBold,
                                        color = status?.color ?: MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.width(6.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RollCallDetailPanel(
    modifier: Modifier,
    detail: RollCallDetailState?,
    onOpenNoteDialog: () -> Unit,
    onSendToJournal: () -> Unit,
) {
    OrganicGlassCard(modifier = modifier, cornerRadius = 28.dp) {
        if (detail == null) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Selecciona un alumno para abrir su ficha contextual.")
            }
            return@OrganicGlassCard
        }

        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StudentAvatar(detail.student)
                    Column {
                        Text("Ficha de alumno", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                        Text(detail.student.fullName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold)
                    }
                }
                Row {
                    IconButton(onClick = onOpenNoteDialog) { Icon(Icons.Default.OpenInNew, contentDescription = "Añadir observación") }
                    IconButton(onClick = onSendToJournal) { Icon(Icons.Default.Send, contentDescription = "Enviar al diario") }
                }
            }

            DetailSection("Datos básicos") {
                Text(detail.student.email ?: "Sin correo registrado", color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (detail.student.isInjured) {
                    FlagBadge("Exención/lesión activa", MaterialTheme.colorScheme.secondary)
                }
            }

            DetailSection("Asistencia y alertas") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    detail.todayRecord?.status?.let { StatusBadge(AttendanceStatus.fromCode(it)) }
                    if (detail.todayRecord?.hasIncident == true) FlagBadge("Incidencia abierta", MaterialTheme.colorScheme.error)
                    if (detail.todayRecord?.followUpRequired == true) FlagBadge("Seguimiento", MaterialTheme.colorScheme.tertiary)
                }
                Text("Faltas acumuladas: ${detail.absences}", color = if (detail.absences >= 3) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Retrasos acumulados: ${detail.lateness}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (detail.todayRecord?.note?.isNotBlank() == true) {
                    Text(detail.todayRecord.note, color = MaterialTheme.colorScheme.onSurface)
                }
            }

            DetailSection("Evolución") {
                Text("Instrumentos realizados: ${detail.grades.count { it.evaluationId != null }}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Evidencias registradas: ${detail.grades.count { !it.evidence.isNullOrBlank() || !it.evidencePath.isNullOrBlank() }}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            DetailSection("Observaciones") {
                if (detail.notes.isEmpty()) {
                    Text("Sin observaciones recientes.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    detail.notes.take(4).forEach { Text("• $it") }
                }
            }

            DetailSection("Adaptaciones") {
                Text(if (detail.student.isInjured) "Alumno marcado con adaptación por lesión/exención." else "Sin adaptaciones registradas todavía.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            DetailSection("Incidencias") {
                if (detail.incidents.isEmpty()) {
                    Text("Sin incidencias registradas.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    detail.incidents.take(3).forEach {
                        Text("• ${it.title}${it.detail?.let { detailText -> ": $detailText" } ?: ""}")
                    }
                }
            }

            DetailSection("Evidencias") {
                Text("Evidencias con texto o archivo: ${detail.grades.count { !it.evidence.isNullOrBlank() || !it.evidencePath.isNullOrBlank() }}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            DetailSection("Comunicaciones") {
                Text(
                    if (detail.incidents.isNotEmpty()) "Preparado para registrar tutoría o contacto con familias a partir de las incidencias y seguimientos." else "Sin comunicaciones registradas.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun DetailSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        Surface(
            shape = RoundedCornerShape(18.dp),
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.24f)
        ) {
            Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                content()
            }
        }
    }
}

@Composable
private fun StudentAvatar(student: Student) {
    Box(
        modifier = Modifier.size(44.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = student.firstName.take(1).uppercase(),
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun StatusBadge(status: AttendanceStatus) {
    Surface(
        shape = RoundedCornerShape(999.dp),
        color = status.color.copy(alpha = 0.15f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(status.icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = status.color)
            Text(status.label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = status.color)
        }
    }
}

@Composable
private fun FlagBadge(label: String, color: Color) {
    Surface(shape = RoundedCornerShape(999.dp), color = color.copy(alpha = 0.12f)) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            fontSize = 12.sp,
            color = color,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun NoteDialog(
    state: NoteDialogState,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var text by remember(state) { mutableStateOf(state.attendance?.note.orEmpty()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Motivo u observación") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                minLines = 4,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Añade motivo, equipación, observación o seguimiento para ${state.student.fullName}") }
            )
        },
        confirmButton = {
            Button(onClick = { onSave(text) }) { Text("Guardar") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancelar") }
        }
    )
}

private fun nextStatus(currentCode: String?): AttendanceStatus {
    val values = AttendanceStatus.values()
    val current = currentCode?.let(AttendanceStatus::fromCode)
    val index = values.indexOf(current)
    return if (index < 0 || index == values.lastIndex) values.first() else values[index + 1]
}

private fun currentMonthRange(date: LocalDate): Pair<LocalDate, LocalDate> {
    val start = LocalDate(date.year, date.month, 1)
    val end = start.plus(1, DateTimeUnit.MONTH).minus(1, DateTimeUnit.DAY)
    return start to end
}

private fun monthDatesFor(date: LocalDate): List<LocalDate> {
    val start = LocalDate(date.year, date.month, 1)
    val dates = mutableListOf<LocalDate>()
    var cursor = start
    while (cursor.month == start.month) {
        dates += cursor
        cursor = cursor.plus(1, DateTimeUnit.DAY)
    }
    return dates
}

private fun formatDate(date: LocalDate): String {
    return "${date.dayOfMonth} ${monthName(date.month)} ${date.year}"
}

private fun monthName(month: Month): String = when (month) {
    Month.JANUARY -> "ene"
    Month.FEBRUARY -> "feb"
    Month.MARCH -> "mar"
    Month.APRIL -> "abr"
    Month.MAY -> "may"
    Month.JUNE -> "jun"
    Month.JULY -> "jul"
    Month.AUGUST -> "ago"
    Month.SEPTEMBER -> "sep"
    Month.OCTOBER -> "oct"
    Month.NOVEMBER -> "nov"
    Month.DECEMBER -> "dic"
}

private fun shortWeekday(dayOfWeek: DayOfWeek): String = when (dayOfWeek) {
    DayOfWeek.MONDAY -> "L"
    DayOfWeek.TUESDAY -> "M"
    DayOfWeek.WEDNESDAY -> "X"
    DayOfWeek.THURSDAY -> "J"
    DayOfWeek.FRIDAY -> "V"
    DayOfWeek.SATURDAY -> "S"
    DayOfWeek.SUNDAY -> "D"
}

private fun sessionDate(session: PlanningSession): LocalDate {
    val monday = mondayOfIsoWeek(session.weekNumber, session.year)
    return monday.plus(session.dayOfWeek - 1, DateTimeUnit.DAY)
}

private fun mondayOfIsoWeek(week: Int, year: Int): LocalDate {
    var date = LocalDate(year, Month.JANUARY, 4)
    while (date.dayOfWeek != DayOfWeek.MONDAY) {
        date = date.minus(1, DateTimeUnit.DAY)
    }
    return date.plus((week - 1) * 7, DateTimeUnit.DAY)
}
