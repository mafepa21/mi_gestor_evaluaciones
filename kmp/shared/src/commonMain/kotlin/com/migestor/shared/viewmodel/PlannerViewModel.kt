package com.migestor.shared.viewmodel

import com.migestor.shared.usecase.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import com.migestor.shared.repository.*
import com.migestor.shared.domain.*
import com.migestor.shared.util.IsoWeekHelper
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus
import kotlinx.datetime.DateTimeUnit

class PlannerViewModel(
    private val plannerRepo: PlannerRepository,
    private val classRepo: ClassesRepository,
    private val weeklyTemplateRepo: WeeklyTemplateRepository,
    private val plannedSessionRepo: PlannedSessionRepository,
    private val generateSessionsFromUD: GenerateSessionsFromUDUseCase,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    data class SessionGridKey(val dayOfWeek: Int, val period: Int, val groupId: Long)
    data class PlannerBulkOperationResult(
        val affected: Int = 0,
        val overwritten: Int = 0,
        val omitted: Int = 0
    )
    data class CopySessionsCommand(
        val sourceGroupId: Long,
        val targetGroupId: Long,
        val fromDate: LocalDate,
        val toDate: LocalDate,
        val selectedSlots: Set<Pair<Int, Int>> = emptySet()
    )
    data class ShiftSessionsCommand(
        val groupId: Long,
        val fromDate: LocalDate,
        val toDate: LocalDate,
        val offsetSlots: Int,
        val selectedSlots: Set<Pair<Int, Int>> = emptySet()
    )
    enum class RelocationMode { COPY, SHIFT }
    data class CopyMoveDialogState(
        val mode: RelocationMode,
        val sourceSessionIds: Set<Long>,
        val sourceGroupId: Long? = null,
        val targetGroupId: Long? = null,
        val targetDayOfWeek: Int? = null,
        val targetPeriod: Int? = null,
        val dayOffset: Int = 0,
        val periodOffset: Int = 0
    )
    enum class QuickAdvance { NONE, NEXT_SLOT, NEXT_DAY }

    // ── Estado de semana ──────────────────────────────────────────────────
    private val _currentWeek = MutableStateFlow(IsoWeekHelper.current().first)
    val currentWeek: StateFlow<Int> = _currentWeek
    private val _currentYear = MutableStateFlow(IsoWeekHelper.current().second)
    val currentYear: StateFlow<Int> = _currentYear

    // ── Pestaña activa ────────────────────────────────────────────────────
    enum class PlannerTab { WEEK, TIMELINE, DAY, DETAIL }
    private val _activeTab = MutableStateFlow(PlannerTab.WEEK)
    val activeTab: StateFlow<PlannerTab> = _activeTab

    // ── Selección de Grupo ───────────────────────────────────────────────
    private val _selectedClassId = MutableStateFlow<Long?>(null)
    val selectedClassId: StateFlow<Long?> = _selectedClassId

    // ── Sesiones Planeadas (Reactivas) ───────────────────────────────────
    @OptIn(ExperimentalCoroutinesApi::class)
    val plannedSessions: StateFlow<List<PlannedSession>> = combine(
        _selectedClassId, _currentWeek, _currentYear
    ) { classId, w, y ->
        val start = IsoWeekHelper.daysOf(w, y).first()
        val end = start.plus(6, DateTimeUnit.DAY) // Cubrimos la semana completa
        
        if (classId == null) {
            plannedSessionRepo.observeAllSessions(start, end)
        } else {
            plannedSessionRepo.observeSessionsForClass(classId, start, end)
        }
    }.flatMapLatest { it }
     .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyList())

    // ── Plantilla Horaria (Reactiva) ─────────────────────────────────────
    private val allWeeklySlots: StateFlow<List<WeeklySlotTemplate>> = 
        weeklyTemplateRepo.observeAllSlots()
            .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyList())

    val weeklySlots: StateFlow<List<WeeklySlotTemplate>> = combine(allWeeklySlots, _selectedClassId) { all, selectedId ->
        if (selectedId == null) all else all.filter { it.schoolClassId == selectedId }
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyList())

    // ── Franjas horarias ──────────────────────────────────────────────────
    val timeSlots: List<TimeSlotConfig> = plannerRepo.getTimeSlots()

    // ── Grupos disponibles ────────────────────────────────────────────────
    val groups: StateFlow<List<SchoolClass>> =
        classRepo.observeClasses()
            .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyList())

    val selectedClass: StateFlow<SchoolClass?> = combine(_selectedClassId, groups) { id, list ->
        list.find { it.id == id }
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), null)
    init {
        scope.launch {
            groups.collect { classes ->
                if (_selectedClassId.value == null && classes.isNotEmpty()) {
                    _selectedClassId.value = classes.first().id
                }
            }
        }
    }

    // ── UDs ───────────────────────────────────────────────────────────────
    val teachingUnits: StateFlow<List<TeachingUnit>> =
        plannerRepo.observeTeachingUnits()
            .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyList())

    val activeUnitForSelectedClass: StateFlow<TeachingUnit?> = combine(
        selectedClass, teachingUnits, _currentWeek, _currentYear
    ) { group, units, w, y ->
        if (group == null) return@combine null
        
        val days = IsoWeekHelper.daysOf(w, y)
        if (days.isEmpty()) return@combine null
        val weekStart = days.first()
        val weekEnd = days.last()

        units.find { unit ->
            val classMatches = unit.schoolClassId == group.id || unit.groupId == group.id
            val hasDates = unit.startDate != null && unit.endDate != null
            if (!classMatches || !hasDates) return@find false
            
            unit.startDate!! <= weekEnd && unit.endDate!! >= weekStart
        }
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), null)

    // ── Sesiones indexadas por (day, period, group) ───────────────────────
    @OptIn(ExperimentalCoroutinesApi::class)
    val sessionsByCell: StateFlow<Map<SessionGridKey, PlanningSession>> =
        combine(
            combine(_currentWeek, _currentYear, _selectedClassId) { w, y, sid -> Triple(w, y, sid) },
            plannedSessions,
            allWeeklySlots,
            groups,
            teachingUnits
        ) { triple, plannedList, allTemplates, classList, units -> 
            val (w, y, selectedId) = triple
            val days = IsoWeekHelper.daysOf(w, y)
            
            // Si hay un grupo seleccionado, mostramos solo sus huecos para mayor claridad
            val templates = if (selectedId != null) {
                allTemplates.filter { it.schoolClassId == selectedId }
            } else {
                allTemplates
            }

            plannerRepo.observeSessions(w, y).map { existingList ->
                val merged = mutableMapOf<SessionGridKey, PlanningSession>()
                
                // 1. Base: Horario Lectivo (Ghost sessions con detección de UD)
                templates.forEach { slot ->
                    val group = classList.find { it.id == slot.schoolClassId }
                    val dateOfSlot = days.getOrNull(slot.dayOfWeek - 1)
                    
                    // Buscar una UD activa para este grupo en esta fecha específica
                    val activeUd = units.find { unit ->
                        // Coincidencia por classId O si es transversal (null) y estamos en el rango de fechas
                        val classMatches = unit.schoolClassId == slot.schoolClassId || 
                                         unit.groupId == slot.schoolClassId ||
                                         (unit.schoolClassId == null && unit.groupId == null)
                        
                        classMatches && 
                        dateOfSlot != null &&
                        unit.startDate != null && unit.endDate != null &&
                        dateOfSlot >= unit.startDate && dateOfSlot <= unit.endDate
                    }

                    val period = timeSlots.find { it.startTime == slot.startTime }?.period ?: 1
                    
                    merged[SessionGridKey(slot.dayOfWeek, period, slot.schoolClassId)] = PlanningSession(
                        id = -slot.id, 
                        teachingUnitId = activeUd?.id ?: 0L,
                        teachingUnitName = activeUd?.name ?: "Horario: ${group?.name ?: "Grupo ${slot.schoolClassId}"}",
                        teachingUnitColor = activeUd?.colorHex ?: "#E5E7EB", 
                        groupId = slot.schoolClassId,
                        groupName = group?.name ?: "Grupo ${slot.schoolClassId}",
                        dayOfWeek = slot.dayOfWeek,
                        period = period,
                        weekNumber = w,
                        year = y,
                        status = SessionStatus.PLANNED
                    )
                }

                // 2. Planned sessions (ahora reactivas)
                plannedList.filter { ps ->
                    IsoWeekHelper.isoWeekOf(ps.date) == w && ps.date.year == y
                }.forEach { ps ->
                    val period = timeSlots.find { it.startTime == ps.startTime }?.period ?: 1
                    merged[SessionGridKey(ps.date.dayOfWeek.isoDayNumber, period, ps.schoolClassId)] = ps.toPlanningSession(period)
                }
                
                // 3. Existing sessions (highest priority)
                existingList.forEach { s ->
                    merged[SessionGridKey(s.dayOfWeek, s.period, s.groupId)] = s
                }
                
                merged
            }
        }
        .flatMapLatest { it }
        .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyMap())

    val sessionsMap: StateFlow<Map<Pair<Int, Int>, PlanningSession>> = combine(sessionsByCell, _selectedClassId) { byCell, selectedId ->
        val filtered = if (selectedId != null) {
            byCell.filterKeys { it.groupId == selectedId }
        } else {
            byCell
        }
        filtered.entries
            .sortedBy { it.key.groupId }
            .associate { (key, value) -> (key.dayOfWeek to key.period) to value }
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyMap())

     // ── Diálogos de estado ────────────────────────────────────────────────
    data class NewSessionState(
        val dayOfWeek: Int, val period: Int,
        val weekNumber: Int, val year: Int,
        val existingSession: PlanningSession? = null,
        val draftSession: PlanningSession? = null
    )
    private val _newSessionDialog = MutableStateFlow<NewSessionState?>(null)
    val newSessionDialog: StateFlow<NewSessionState?> = _newSessionDialog

    private val _udManagerOpen = MutableStateFlow(false)
    val udManagerOpen: StateFlow<Boolean> = _udManagerOpen

    private val _selectedSession = MutableStateFlow<PlanningSession?>(null)
    val selectedSession: StateFlow<PlanningSession?> = _selectedSession
    private val _lastBulkOperation = MutableStateFlow<PlannerBulkOperationResult?>(null)
    val lastBulkOperation: StateFlow<PlannerBulkOperationResult?> = _lastBulkOperation
    private val _copyMoveDialogState = MutableStateFlow<CopyMoveDialogState?>(null)
    val copyMoveDialogState: StateFlow<CopyMoveDialogState?> = _copyMoveDialogState
    private val _copyMovePreviewConflicts = MutableStateFlow<List<SessionRelocationConflict>>(emptyList())
    val copyMovePreviewConflicts: StateFlow<List<SessionRelocationConflict>> = _copyMovePreviewConflicts

    // ── Semana ────────────────────────────────────────────────────────────
    val weekLabel: StateFlow<String> = combine(_currentWeek, _currentYear) { w: Int, y: Int ->
        "Semana $w, $y"
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), "")

    val weekDateRangeLabel: StateFlow<String> = combine(_currentWeek, _currentYear) { w, y ->
        val days = IsoWeekHelper.daysOf(w, y)
        if (days.isEmpty()) return@combine ""
        val first = days.first()
        val last = days.last()
        
        val firstMonth = first.month.name.lowercase().capitalizeFirst()
        val lastMonth = last.month.name.lowercase().capitalizeFirst()
        
        if (first.month == last.month) {
            "${first.dayOfMonth} - ${last.dayOfMonth} $firstMonth"
        } else {
            "${first.dayOfMonth} $firstMonth - ${last.dayOfMonth} $lastMonth"
        }
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), "")

    private fun String.capitalizeFirst() = replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }

    // ── Acciones ──────────────────────────────────────────────────────────
    fun openNewSessionDialog(day: Int, period: Int, existing: PlanningSession? = null, draft: PlanningSession? = null) {
        _newSessionDialog.value = NewSessionState(
            dayOfWeek = day,
            period = period,
            weekNumber = existing?.weekNumber ?: _currentWeek.value,
            year = existing?.year ?: _currentYear.value,
            existingSession = existing,
            draftSession = draft
        )
    }
    fun closeNewSessionDialog() { _newSessionDialog.value = null }
    fun selectTab(tab: PlannerTab) { _activeTab.value = tab }

    fun nextWeek() {
        if (_currentWeek.value >= 52) {
            _currentWeek.value = 1
            _currentYear.value = _currentYear.value + 1
        } else {
            _currentWeek.value = _currentWeek.value + 1
        }
    }

    fun prevWeek() {
        if (_currentWeek.value <= 1) {
            _currentWeek.value = 52
            _currentYear.value = _currentYear.value - 1
        } else {
            _currentWeek.value = _currentWeek.value - 1
        }
    }

    fun openUDManager() { _udManagerOpen.value = true }
    fun closeUDManager() { _udManagerOpen.value = false }
    fun selectSession(s: PlanningSession?) { _selectedSession.value = s }

    fun saveSession(session: PlanningSession) {
        scope.launch {
            val toSave = if (session.id < 0) session.copy(id = 0) else session
            plannerRepo.upsertSession(toSave)
            closeNewSessionDialog()
        }
    }

    fun quickCreateOrUpdateSession(session: PlanningSession, advance: QuickAdvance = QuickAdvance.NONE) {
        scope.launch {
            val toSave = if (session.id < 0) session.copy(id = 0) else session
            plannerRepo.upsertSession(toSave)
            if (advance == QuickAdvance.NONE) {
                closeNewSessionDialog()
                return@launch
            }
            val slots = weeklyTemplateRepo.getSlotsForClass(session.groupId)
                .filter { it.dayOfWeek in 1..5 }
                .sortedWith(compareBy<WeeklySlotTemplate> { it.dayOfWeek }.thenBy { it.startTime })
            if (slots.isEmpty()) {
                closeNewSessionDialog()
                return@launch
            }
            val current = slots.indexOfFirst { it.dayOfWeek == session.dayOfWeek && periodForStartTime(it.startTime) == session.period }
            val nextIndex = when (advance) {
                QuickAdvance.NEXT_SLOT -> if (current in slots.indices && current < slots.lastIndex) current + 1 else -1
                QuickAdvance.NEXT_DAY -> slots.indexOfFirst { it.dayOfWeek > session.dayOfWeek }
                QuickAdvance.NONE -> -1
            }
            if (nextIndex !in slots.indices) {
                closeNewSessionDialog()
                return@launch
            }
            val nextSlot = slots[nextIndex]
            val nextPeriod = periodForStartTime(nextSlot.startTime)
            openNewSessionDialog(
                day = nextSlot.dayOfWeek,
                period = nextPeriod,
                draft = session.copy(
                    id = 0,
                    dayOfWeek = nextSlot.dayOfWeek,
                    period = nextPeriod
                )
            )
        }
    }
    fun deleteSession(id: Long) {
        scope.launch { plannerRepo.deleteSession(id) }
    }

    fun saveTeachingUnit(unit: TeachingUnit) {
        scope.launch {
            val savedId = plannerRepo.upsertTeachingUnit(unit)
            
            // Si tiene fechas y grupo, generar sesiones automáticamente
            if (unit.startDate != null && unit.endDate != null && unit.schoolClassId != null) {
                val udWithId = unit.copy(id = savedId)
                val schedule = TeachingUnitSchedule(
                    teachingUnitId = savedId,
                    schoolClassId = unit.schoolClassId,
                    startDate = unit.startDate,
                    endDate = unit.endDate
                )
                generateSessionsFromUD.execute(udWithId, schedule)
            }
        }
    }

    fun deleteTeachingUnit(id: Long) {
        scope.launch { plannerRepo.deleteTeachingUnit(id) }
    }

    private fun PlannedSession.toPlanningSession(period: Int): PlanningSession {
        return PlanningSession(
            id = this.id,
            teachingUnitId = this.teachingUnitId ?: 0L,
            teachingUnitName = this.title,
            teachingUnitColor = "#4A90D9", 
            groupId = this.schoolClassId,
            groupName = "Grupo ${this.schoolClassId}", 
            dayOfWeek = this.date.dayOfWeek.isoDayNumber,
            period = period,
            weekNumber = IsoWeekHelper.isoWeekOf(this.date),
            year = this.date.year,
            objectives = this.objectives,
            activities = this.notes,
            status = SessionStatus.PLANNED
        )
    }

    // ── Acciones de Plantilla y Generación ───────────────────────────────
    fun selectClass(classId: Long?) {
        _selectedClassId.value = classId
    }

    fun saveWeeklySlot(slot: WeeklySlotTemplate) {
        scope.launch {
            weeklyTemplateRepo.insert(slot)
        }
    }

    fun deleteWeeklySlot(id: Long) {
        scope.launch {
            weeklyTemplateRepo.delete(id)
        }
    }

    fun generateSessions(ud: TeachingUnit, schedule: TeachingUnitSchedule) {
        scope.launch {
            // Sincronizamos las fechas y el grupo en la propia UD
            val updatedUd = ud.copy(
                startDate = schedule.startDate, 
                endDate = schedule.endDate,
                schoolClassId = schedule.schoolClassId,
                groupId = schedule.schoolClassId
            )
            plannerRepo.upsertTeachingUnit(updatedUd)
            generateSessionsFromUD.execute(updatedUd, schedule)
        }
    }

    fun moveCurrentWeekByWeeks(offsetWeeks: Int) {
        scope.launch {
            plannerRepo.moveSessionsFromWeek(_currentWeek.value, _currentYear.value, offsetWeeks)
        }
    }

    fun openCopyMoveDialog(
        mode: RelocationMode,
        sourceSessionIds: Set<Long>,
        sourceGroupId: Long? = null
    ) {
        _copyMoveDialogState.value = CopyMoveDialogState(
            mode = mode,
            sourceSessionIds = sourceSessionIds.filter { it > 0 }.toSet(),
            sourceGroupId = sourceGroupId
        )
        _copyMovePreviewConflicts.value = emptyList()
    }

    fun closeCopyMoveDialog() {
        _copyMoveDialogState.value = null
        _copyMovePreviewConflicts.value = emptyList()
    }

    fun previewCopy(
        targetGroupId: Long,
        targetDayOfWeek: Int? = null,
        targetPeriod: Int? = null,
        dayOffset: Int = 0,
        periodOffset: Int = 0
    ) {
        val state = _copyMoveDialogState.value ?: return
        if (state.mode != RelocationMode.COPY) return
        val request = SessionRelocationRequest(
            sourceSessionIds = state.sourceSessionIds.toList(),
            targetGroupId = targetGroupId,
            targetDayOfWeek = targetDayOfWeek,
            targetPeriod = targetPeriod,
            dayOffset = dayOffset,
            periodOffset = periodOffset
        )
        scope.launch {
            _copyMovePreviewConflicts.value = plannerRepo.previewSessionRelocation(request)
            _copyMoveDialogState.value = state.copy(
                targetGroupId = targetGroupId,
                targetDayOfWeek = targetDayOfWeek,
                targetPeriod = targetPeriod,
                dayOffset = dayOffset,
                periodOffset = periodOffset
            )
        }
    }

    fun confirmCopy(resolution: CollisionResolution) {
        val state = _copyMoveDialogState.value ?: return
        if (state.mode != RelocationMode.COPY) return
        scope.launch {
            val result = plannerRepo.copySessions(
                request = SessionRelocationRequest(
                    sourceSessionIds = state.sourceSessionIds.toList(),
                    targetGroupId = state.targetGroupId,
                    targetDayOfWeek = state.targetDayOfWeek,
                    targetPeriod = state.targetPeriod,
                    dayOffset = state.dayOffset,
                    periodOffset = state.periodOffset
                ),
                resolution = resolution
            )
            _lastBulkOperation.value = PlannerBulkOperationResult(
                affected = result.movedOrCopied,
                overwritten = result.overwritten,
                omitted = result.skipped + result.failed
            )
            closeCopyMoveDialog()
        }
    }

    fun previewShift(
        dayOffset: Int = 0,
        periodOffset: Int = 0,
        targetDayOfWeek: Int? = null,
        targetPeriod: Int? = null
    ) {
        val state = _copyMoveDialogState.value ?: return
        if (state.mode != RelocationMode.SHIFT) return
        val request = SessionRelocationRequest(
            sourceSessionIds = state.sourceSessionIds.toList(),
            targetGroupId = state.sourceGroupId,
            targetDayOfWeek = targetDayOfWeek,
            targetPeriod = targetPeriod,
            dayOffset = dayOffset,
            periodOffset = periodOffset
        )
        scope.launch {
            _copyMovePreviewConflicts.value = plannerRepo.previewSessionRelocation(request)
            _copyMoveDialogState.value = state.copy(
                targetDayOfWeek = targetDayOfWeek,
                targetPeriod = targetPeriod,
                dayOffset = dayOffset,
                periodOffset = periodOffset
            )
        }
    }

    fun confirmShift(resolution: CollisionResolution) {
        val state = _copyMoveDialogState.value ?: return
        if (state.mode != RelocationMode.SHIFT) return
        scope.launch {
            val result = plannerRepo.shiftSelectedSessions(
                request = SessionRelocationRequest(
                    sourceSessionIds = state.sourceSessionIds.toList(),
                    targetGroupId = state.sourceGroupId,
                    targetDayOfWeek = state.targetDayOfWeek,
                    targetPeriod = state.targetPeriod,
                    dayOffset = state.dayOffset,
                    periodOffset = state.periodOffset
                ),
                resolution = resolution
            )
            _lastBulkOperation.value = PlannerBulkOperationResult(
                affected = result.movedOrCopied,
                overwritten = result.overwritten,
                omitted = result.skipped + result.failed
            )
            closeCopyMoveDialog()
        }
    }

    fun copySessionsBetweenGroups(command: CopySessionsCommand) {
        scope.launch {
            val sourceManual = plannerRepo.listSessionsInRange(command.sourceGroupId, command.fromDate, command.toDate)
            val sourcePlanned = plannedSessionRepo.listSessionsInRange(command.sourceGroupId, command.fromDate, command.toDate)
            val sourceItems = (sourceManual.map { CopySourceItem.Manual(it) } + sourcePlanned.map { CopySourceItem.Planned(it) })
                .sortedBy { it.startDateTimeKey(timeSlots) }
                .filter { item ->
                    if (command.selectedSlots.isEmpty()) true
                    else command.selectedSlots.contains(item.dayPeriod(timeSlots))
                }
            val targetSlots = expandedGroupSlots(command.targetGroupId, command.fromDate, command.toDate)
            if (targetSlots.isEmpty() || sourceItems.isEmpty()) {
                _lastBulkOperation.value = PlannerBulkOperationResult(affected = 0, omitted = sourceItems.size)
                return@launch
            }

            val targetManualExisting = plannerRepo.listSessionsInRange(command.targetGroupId, command.fromDate, command.toDate)
            val targetManualKeys = targetManualExisting.map { Triple(it.groupId, toDate(it), it.period) }.toSet()
            val targetPlannedExisting = plannedSessionRepo.listSessionsInRange(command.targetGroupId, command.fromDate, command.toDate)
            val targetPlannedKeys = targetPlannedExisting.map { Triple(it.schoolClassId, it.date, it.startTime) }.toSet()

            val mappedPairs = sourceItems.zip(targetSlots).take(minOf(sourceItems.size, targetSlots.size))
            val plannerToSave = mutableListOf<PlanningSession>()
            val plannedToSave = mutableListOf<PlannedSession>()
            var overwritten = 0
            mappedPairs.forEach { (item, target) ->
                when (item) {
                    is CopySourceItem.Manual -> {
                        val mapped = item.session.copy(
                            id = 0,
                            groupId = command.targetGroupId,
                            groupName = groups.value.firstOrNull { it.id == command.targetGroupId }?.name ?: item.session.groupName,
                            dayOfWeek = target.dayOfWeek,
                            period = target.period,
                            weekNumber = IsoWeekHelper.isoWeekOf(target.date),
                            year = target.date.year
                        )
                        if (targetManualKeys.contains(Triple(mapped.groupId, target.date, mapped.period))) overwritten++
                        plannerToSave += mapped
                    }
                    is CopySourceItem.Planned -> {
                        val mapped = item.session.copy(
                            id = 0,
                            schoolClassId = command.targetGroupId,
                            date = target.date,
                            startTime = target.startTime,
                            endTime = target.endTime
                        )
                        if (targetPlannedKeys.contains(Triple(mapped.schoolClassId, mapped.date, mapped.startTime))) overwritten++
                        plannedToSave += mapped
                    }
                }
            }
            plannerRepo.bulkUpsertSessions(plannerToSave)
            plannedSessionRepo.bulkUpsertOrReplacePlannedSessions(plannedToSave)
            _lastBulkOperation.value = PlannerBulkOperationResult(
                affected = plannerToSave.size + plannedToSave.size,
                overwritten = overwritten,
                omitted = (sourceItems.size - mappedPairs.size).coerceAtLeast(0)
            )
        }
    }

    fun shiftSessionsWithinGroup(command: ShiftSessionsCommand) {
        scope.launch {
            if (command.offsetSlots == 0) return@launch
            val sourceManual = plannerRepo.listSessionsInRange(command.groupId, command.fromDate, command.toDate)
            val sourcePlanned = plannedSessionRepo.listSessionsInRange(command.groupId, command.fromDate, command.toDate)
            val sourceItems = (sourceManual.map { CopySourceItem.Manual(it) } + sourcePlanned.map { CopySourceItem.Planned(it) })
                .sortedBy { it.startDateTimeKey(timeSlots) }
                .filter { item ->
                    if (command.selectedSlots.isEmpty()) true
                    else command.selectedSlots.contains(item.dayPeriod(timeSlots))
                }
            val slots = expandedGroupSlots(command.groupId, command.fromDate, command.toDate)
            if (slots.isEmpty() || sourceItems.isEmpty()) {
                _lastBulkOperation.value = PlannerBulkOperationResult(affected = 0, omitted = sourceItems.size)
                return@launch
            }
            val slotIndexByKey = slots.withIndex().associate { it.value.key() to it.index }
            val movedPlanner = mutableListOf<PlanningSession>()
            val movedPlanned = mutableListOf<PlannedSession>()
            val plannerIdsToDelete = mutableListOf<Long>()
            val plannedIdsToDelete = mutableListOf<Long>()
            var omitted = 0
            sourceItems.forEach { item ->
                val currentKey = when (item) {
                    is CopySourceItem.Manual -> SlotKey(toDate(item.session), periodToStartTime(item.session.period), periodToEndTime(item.session.period), item.session.dayOfWeek, item.session.period)
                    is CopySourceItem.Planned -> {
                        val period = periodForStartTime(item.session.startTime)
                        SlotKey(item.session.date, item.session.startTime, item.session.endTime, item.session.date.dayOfWeek.isoDayNumber, period)
                    }
                }
                val index = slotIndexByKey[currentKey] ?: run { omitted++; return@forEach }
                val targetIndex = index + command.offsetSlots
                if (targetIndex !in slots.indices) {
                    omitted++
                    return@forEach
                }
                val target = slots[targetIndex]
                when (item) {
                    is CopySourceItem.Manual -> {
                        plannerIdsToDelete += item.session.id
                        movedPlanner += item.session.copy(
                            id = 0,
                            dayOfWeek = target.dayOfWeek,
                            period = target.period,
                            weekNumber = IsoWeekHelper.isoWeekOf(target.date),
                            year = target.date.year
                        )
                    }
                    is CopySourceItem.Planned -> {
                        plannedIdsToDelete += item.session.id
                        movedPlanned += item.session.copy(
                            id = 0,
                            date = target.date,
                            startTime = target.startTime,
                            endTime = target.endTime
                        )
                    }
                }
            }
            plannerRepo.deleteSessions(plannerIdsToDelete.distinct())
            plannedSessionRepo.deleteSessions(plannedIdsToDelete.distinct())
            plannerRepo.bulkUpsertSessions(movedPlanner)
            plannedSessionRepo.bulkUpsertOrReplacePlannedSessions(movedPlanned)
            _lastBulkOperation.value = PlannerBulkOperationResult(
                affected = movedPlanner.size + movedPlanned.size,
                overwritten = 0,
                omitted = omitted
            )
        }
    }

    private data class SlotKey(
        val date: LocalDate,
        val startTime: String,
        val endTime: String,
        val dayOfWeek: Int,
        val period: Int
    )

    private sealed interface CopySourceItem {
        data class Manual(val session: PlanningSession) : CopySourceItem
        data class Planned(val session: PlannedSession) : CopySourceItem
    }

    private fun CopySourceItem.startDateTimeKey(timeSlots: List<TimeSlotConfig>): String {
        return when (this) {
            is CopySourceItem.Manual -> "${session.year}-${session.weekNumber}-${session.dayOfWeek}-${session.period}"
            is CopySourceItem.Planned -> "${session.date}-${session.startTime}"
        }
    }

    private fun CopySourceItem.dayPeriod(timeSlots: List<TimeSlotConfig>): Pair<Int, Int> = when (this) {
        is CopySourceItem.Manual -> session.dayOfWeek to session.period
        is CopySourceItem.Planned -> session.date.dayOfWeek.isoDayNumber to periodForStartTime(session.startTime)
    }

    private suspend fun expandedGroupSlots(groupId: Long, fromDate: LocalDate, toDate: LocalDate): List<SlotKey> {
        val templates = weeklyTemplateRepo.getSlotsForClass(groupId)
        if (templates.isEmpty()) return emptyList()
        val slots = mutableListOf<SlotKey>()
        var date = fromDate
        while (date <= toDate) {
            val day = date.dayOfWeek.isoDayNumber
            templates.filter { it.dayOfWeek == day }
                .sortedBy { it.startTime }
                .forEach { template ->
                    slots += SlotKey(
                        date = date,
                        startTime = template.startTime,
                        endTime = template.endTime,
                        dayOfWeek = template.dayOfWeek,
                        period = periodForStartTime(template.startTime)
                    )
                }
            date = date.plus(1, DateTimeUnit.DAY)
        }
        return slots
    }

    private fun SlotKey.key(): SlotKey = this

    private fun periodForStartTime(startTime: String): Int = timeSlots.firstOrNull { it.startTime == startTime }?.period ?: 1
    private fun periodToStartTime(period: Int): String = timeSlots.firstOrNull { it.period == period }?.startTime ?: "08:00"
    private fun periodToEndTime(period: Int): String = timeSlots.firstOrNull { it.period == period }?.endTime ?: "09:00"
    private fun toDate(session: PlanningSession): LocalDate = IsoWeekHelper.daysOf(session.weekNumber, session.year)[(session.dayOfWeek - 1).coerceIn(0, 4)]
}
