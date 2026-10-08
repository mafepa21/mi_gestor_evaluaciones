package com.migestor.shared.usecase

import com.migestor.shared.inclusion.InclusionGroupBoard
import com.migestor.shared.inclusion.InclusionManual
import com.migestor.shared.inclusion.InclusionPhase
import com.migestor.shared.inclusion.InclusionStudentBoard
import com.migestor.shared.inclusion.InclusionTask
import com.migestor.shared.inclusion.InclusionTaskItem
import com.migestor.shared.inclusion.InclusionDueRule
import com.migestor.shared.repository.InclusionTaskRepository
import com.migestor.shared.repository.StudentSupportMeasureRepository
import kotlinx.datetime.LocalDate

/**
 * Seguimiento de plazos del Manual de Inclusión para un grupo.
 *
 * La fecha de evaluación inicial es por grupo y curso. Si un alumno está en
 * varios grupos con fechas distintas, manda el grupo desde el que se opera.
 *
 * @param studentIdsForClass alumnado matriculado en el grupo (se inyecta para no
 *   depender del contrato completo de ClassesRepository y poder probarlo).
 */
class InclusionTasksUseCase(
    private val tasks: InclusionTaskRepository,
    private val measures: StudentSupportMeasureRepository,
    private val studentIdsForClass: suspend (Long) -> List<Long>,
) {

    @Throws(Throwable::class)
    suspend fun initialEvaluationDate(classId: Long, schoolYear: String): LocalDate =
        tasks.getInitialEvaluationDate(classId, schoolYear)
            ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?: InclusionManual.defaultInitialEvaluationDate(schoolYear)

    /**
     * Crea las tareas del manual que falten para el alumnado del grupo con alguna
     * medida activa de nivel III/IV. Idempotente: lo ya creado (marcado, editado)
     * no se toca. Devuelve cuántas tareas nuevas ha creado.
     */
    @Throws(Throwable::class)
    suspend fun generateForClass(classId: Long, schoolYear: String, nowEpochMs: Long): Int {
        val evalDate = initialEvaluationDate(classId, schoolYear)
        var created = 0
        for (studentId in studentIdsForClass(classId).distinct()) {
            val all = measures.listByStudent(studentId)
            val active = all.filter { it.isActive }
            val templates = InclusionManual.templatesFor(schoolYear, active, all)
            for (template in templates) {
                val due = InclusionManual.manualDue(template.rule, schoolYear, evalDate)
                val inserted = tasks.insertTemplateIfAbsent(
                    studentId = studentId,
                    measureId = template.measureId,
                    templateKey = template.key,
                    title = template.title,
                    phase = template.phase,
                    dueDateIso = due.toString(),
                    schoolYear = schoolYear,
                    nowEpochMs = nowEpochMs,
                )
                if (inserted) created++
            }
        }
        return created
    }

    /** Tablero del grupo: solo alumnado con alguna tarea este curso. */
    @Throws(Throwable::class)
    suspend fun loadBoard(classId: Long, schoolYear: String, today: LocalDate): InclusionGroupBoard {
        val evalDate = initialEvaluationDate(classId, schoolYear)
        val studentIds = studentIdsForClass(classId).distinct()
        val all = if (studentIds.isEmpty()) emptyList() else tasks.listByStudents(studentIds, schoolYear)
        val byStudent = all.groupBy { it.studentId }
        val boards = studentIds.mapNotNull { id ->
            val list = byStudent[id] ?: return@mapNotNull null
            InclusionStudentBoard(id, list.map { item(it, evalDate, today) }.sortedBy { it.task.dueDate })
        }
        return InclusionGroupBoard(
            classId = classId,
            schoolYear = schoolYear,
            initialEvaluationDate = evalDate,
            students = boards,
            summary = InclusionManual.summary(all, today),
        )
    }

    fun item(task: InclusionTask, initialEvaluation: LocalDate, today: LocalDate): InclusionTaskItem {
        val manual = manualDueOf(task, initialEvaluation)
        val isTemplate = manual != null
        return InclusionTaskItem(
            task = task,
            manualDue = manual ?: task.dueDate,
            isEdited = isTemplate && task.dueDate != manual,
            status = InclusionManual.status(task, today),
            canReset = isTemplate && task.dueDate != manual,
        )
    }

    /** Marca o desmarca. Devuelve el nuevo estado (`true` = hecha). */
    @Throws(Throwable::class)
    suspend fun toggleDone(taskId: Long, today: LocalDate, nowEpochMs: Long): Boolean {
        val task = tasks.getById(taskId) ?: throw IllegalArgumentException("Tarea $taskId no encontrada")
        val done = !task.isDone
        tasks.setDone(taskId, if (done) today.toString() else null, nowEpochMs)
        return done
    }

    /** Fecha elegida por el docente. Si coincide con la del manual, deja de contar como editada. */
    @Throws(Throwable::class)
    suspend fun setDueDate(taskId: Long, classId: Long, date: LocalDate, nowEpochMs: Long) {
        val task = tasks.getById(taskId) ?: throw IllegalArgumentException("Tarea $taskId no encontrada")
        val manual = manualDueOf(task, initialEvaluationDate(classId, task.schoolYear))
        val isCustom = manual == null || date != manual
        tasks.setDue(taskId, date.toString(), isCustom, nowEpochMs)
    }

    /** Vuelve a la fecha del manual vigente. En tareas libres no hace nada. */
    @Throws(Throwable::class)
    suspend fun resetDueDate(taskId: Long, classId: Long, nowEpochMs: Long): Boolean {
        val task = tasks.getById(taskId) ?: throw IllegalArgumentException("Tarea $taskId no encontrada")
        val manual = manualDueOf(task, initialEvaluationDate(classId, task.schoolYear)) ?: return false
        tasks.setDue(taskId, manual.toString(), false, nowEpochMs)
        return true
    }

    /**
     * Guarda la evaluación inicial del grupo y mueve las tareas que dependen de
     * ella. Las editadas a mano (due_is_custom = 1) conservan su fecha.
     * Devuelve cuántas fechas se han movido.
     */
    @Throws(Throwable::class)
    suspend fun setInitialEvaluationDate(classId: Long, schoolYear: String, date: LocalDate, nowEpochMs: Long): Int {
        tasks.setInitialEvaluationDate(classId, schoolYear, date.toString())
        val studentIds = studentIdsForClass(classId).distinct()
        if (studentIds.isEmpty()) return 0
        var moved = 0
        for (task in tasks.listByStudents(studentIds, schoolYear)) {
            val rule = InclusionManual.ruleFor(task.templateKey) as? InclusionDueRule.AfterInitialEvaluation ?: continue
            if (task.dueIsCustom) continue
            val newDue = InclusionManual.manualDue(rule, schoolYear, date)
            if (newDue == task.dueDate) continue
            if (tasks.updateDueIfNotCustom(task.id, newDue.toString(), nowEpochMs)) moved++
        }
        return moved
    }

    @Throws(Throwable::class)
    suspend fun addFreeTask(
        studentId: Long,
        title: String,
        phase: InclusionPhase,
        due: LocalDate,
        schoolYear: String,
        nowEpochMs: Long,
        notes: String = "",
    ): Long {
        val clean = title.trim()
        require(clean.isNotEmpty()) { "La tarea necesita un título" }
        return tasks.insertFreeTask(studentId, clean, phase, due.toString(), notes, schoolYear, nowEpochMs)
    }

    private fun manualDueOf(task: InclusionTask, initialEvaluation: LocalDate): LocalDate? {
        val rule = InclusionManual.ruleFor(task.templateKey) ?: return null
        return InclusionManual.manualDue(rule, task.schoolYear, initialEvaluation)
    }
}
