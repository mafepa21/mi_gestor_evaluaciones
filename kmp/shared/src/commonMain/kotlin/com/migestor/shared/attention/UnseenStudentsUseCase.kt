package com.migestor.shared.attention

import kotlinx.datetime.LocalDate

/**
 * «Alumnos invisibles»: alumnado de un grupo sin ningún registro del docente
 * (nota, comentario, observación…) en los últimos 14 días lectivos.
 *
 * Métodos expuestos a Swift: sin argumentos por defecto, con @Throws y sin
 * Map ni Set en la firma (un `Map<Long, …>` de Kotlin rompe al iterarlo en Swift):
 * los días no lectivos y los alumnos «Vistos» llegan como listas.
 */
class UnseenStudentsUseCase(
    private val repository: UnseenStudentsRepository,
    private val today: () -> LocalDate,
) {

    /**
     * @param nonTeachingDaysIso días no lectivos `yyyy-MM-dd` (globales y del grupo).
     * @param hiddenStudentIds alumnos marcados «Visto» en este aparato (no salen).
     */
    @Throws(Throwable::class)
    suspend fun unseenForClass(
        classId: Long,
        nonTeachingDaysIso: List<String>,
        hiddenStudentIds: List<Long>,
    ): UnseenReport {
        val date = today()
        val nonTeaching = parseDays(nonTeachingDaysIso)
        val students = repository.students(classId)
        val contacts = repository.lastContacts(classId).groupBy { it.studentId }
        val starts = repository.enrollmentStarts(classId)
        val support = repository.studentsWithSupportMeasure(classId)
        val hidden = hiddenStudentIds.toSet()
        val unseen = students.mapNotNull { student ->
            if (student.id in hidden) return@mapNotNull null
            val last = UnseenStudentsRules.latest(contacts[student.id].orEmpty())
            if (!UnseenStudentsRules.isUnseen(last, starts[student.id], date, nonTeaching)) return@mapNotNull null
            UnseenStudent(
                studentId = student.id,
                name = student.name,
                hasSupportMeasure = student.id in support,
                daysSinceLast = last?.let { UnseenStudentsRules.naturalDays(it.date, date) } ?: -1,
                lastKind = last?.kind,
                lastLabel = last?.label.orEmpty(),
                lastDateIso = last?.date?.toString().orEmpty(),
            )
        }.sortedWith(UnseenStudentsRules.order)
        return UnseenReport(classId = classId, totalStudents = students.size, unseen = unseen)
    }

    /** Último registro del alumno en el grupo (para la ficha y el filtro de Alumnado). */
    @Throws(Throwable::class)
    suspend fun lastContact(classId: Long, studentId: Long, nonTeachingDaysIso: List<String>): LastContactSummary {
        val date = today()
        val last = UnseenStudentsRules.latest(repository.lastContacts(classId).filter { it.studentId == studentId })
        val enrolledOn = repository.enrollmentStarts(classId)[studentId]
        return LastContactSummary(
            studentId = studentId,
            classId = classId,
            daysSince = last?.let { UnseenStudentsRules.naturalDays(it.date, date) } ?: -1,
            isOverdue = UnseenStudentsRules.isUnseen(last, enrolledOn, date, parseDays(nonTeachingDaysIso)),
            kind = last?.kind,
            label = last?.label.orEmpty(),
            dateIso = last?.date?.toString().orEmpty(),
        )
    }

    private fun parseDays(isoDays: List<String>): Set<LocalDate> =
        isoDays.mapNotNullTo(mutableSetOf()) { runCatching { LocalDate.parse(it) }.getOrNull() }
}
