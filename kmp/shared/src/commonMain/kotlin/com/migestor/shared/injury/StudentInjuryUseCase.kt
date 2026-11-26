package com.migestor.shared.injury

import com.migestor.shared.domain.AuditTrace
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

/**
 * Lesiones con fecha: guardar, «ha vuelto», borrar y la marca derivada
 * `students.is_injured` («tiene una lesión activa hoy»).
 *
 * La marca solo la gestiona este caso de uso y solo en alumnos con alguna lesión
 * guardada: un alumno marcado sin lesiones (p. ej. llegado de una versión antigua)
 * no se toca, para no quitarle la marca por sorpresa.
 *
 * Métodos expuestos a Swift: sin argumentos por defecto y con @Throws.
 * Los que cambian lesiones devuelven las lesiones tocadas para encolarlas en Sync LAN.
 */
class StudentInjuryUseCase(
    private val repository: StudentInjuryRepository,
    private val newId: () -> String,
    private val today: () -> LocalDate,
) {

    /** Lesiones del alumno sin las borradas, la más reciente primero. */
    @Throws(Throwable::class)
    suspend fun listForStudent(studentId: Long): List<StudentInjury> =
        repository.listByStudent(studentId)
            .filter { !it.isDeleted }
            .sortedWith(compareByDescending<StudentInjury> { it.startsOn }.thenByDescending { it.trace.updatedAt })

    /**
     * Lesión activa hoy de cada alumno lesionado (una por alumno), para etiquetas de
     * Asistencia y ficha. Lista y no Map: un `Map<Long, …>` exportado a Swift rompe al
     * iterarlo (las claves no se convierten a `KotlinLong`) y cerraba la app.
     */
    @Throws(Throwable::class)
    suspend fun activeToday(): List<StudentInjury> {
        val date = today()
        return repository.listAll()
            .groupBy { it.studentId }
            .mapNotNull { (_, list) -> StudentInjuryRules.activeOn(list, date) }
            .sortedBy { it.studentId }
    }

    /** Alumnos que vuelven hoy (su lesión terminó ayer). */
    @Throws(Throwable::class)
    suspend fun returningToday(): List<StudentInjury> =
        StudentInjuryRules.returningOn(repository.listAll(), today())

    /**
     * Crea o edita una lesión. Valida fechas y nota, recorta la nota y recalcula la
     * marca del alumno. Lanza [StudentInjuryValidationException] si no es válida.
     */
    @Throws(Throwable::class)
    suspend fun save(draft: StudentInjuryDraft, nowEpochMs: Long, deviceId: String?): StudentInjury {
        StudentInjuryRules.validate(draft)?.let { throw StudentInjuryValidationException(it) }
        val existing = draft.id?.let { repository.get(it) }
        val now = Instant.fromEpochMilliseconds(nowEpochMs)
        val injury = StudentInjury(
            id = existing?.id ?: draft.id ?: newId(),
            studentId = existing?.studentId ?: draft.studentId,
            startsOn = draft.startsOn,
            endsOn = draft.endsOn,
            role = draft.role,
            note = draft.note.trim(),
            proofDelivered = draft.proofDelivered,
            isDeleted = false,
            trace = touched(existing?.trace, now, deviceId),
        )
        repository.save(injury)
        reconcileStudent(injury.studentId)
        return injury
    }

    /** «Ha vuelto»: la lesión termina ayer (o se borra si empezó hoy). */
    @Throws(Throwable::class)
    suspend fun markReturned(injuryId: String, nowEpochMs: Long, deviceId: String?): StudentInjury? {
        val existing = repository.get(injuryId) ?: return null
        val updated = StudentInjuryRules.returnedToday(existing, today())
            .copy(trace = touched(existing.trace, Instant.fromEpochMilliseconds(nowEpochMs), deviceId))
        repository.save(updated)
        reconcileStudent(updated.studentId)
        return updated
    }

    /** Borrado lógico (lesión puesta por error). Sale del historial. */
    @Throws(Throwable::class)
    suspend fun delete(injuryId: String, nowEpochMs: Long, deviceId: String?): StudentInjury? {
        val existing = repository.get(injuryId) ?: return null
        val updated = existing.copy(
            isDeleted = true,
            trace = touched(existing.trace, Instant.fromEpochMilliseconds(nowEpochMs), deviceId),
        )
        repository.save(updated)
        reconcileStudent(updated.studentId)
        return updated
    }

    /**
     * Para los interruptores rápidos de siempre («Marcar lesión» / «Quitar lesión»).
     * Marcar: si no tiene lesión activa, crea una desde hoy sin fecha de fin.
     * Quitar: marca «ha vuelto» en todas sus lesiones activas.
     * Si el alumno no tiene lesiones pero sí la marca antigua, la quita directamente.
     */
    @Throws(Throwable::class)
    suspend fun setInjured(studentId: Long, injured: Boolean, nowEpochMs: Long, deviceId: String?): List<StudentInjury> {
        val date = today()
        val injuries = repository.listByStudent(studentId)
        val active = injuries.filter { StudentInjuryRules.isActiveOn(it, date) }
        val changed = mutableListOf<StudentInjury>()
        if (injured) {
            if (active.isEmpty()) {
                changed += save(StudentInjuryDraft(studentId = studentId, startsOn = date), nowEpochMs, deviceId)
            }
        } else {
            active.forEach { injury -> markReturned(injury.id, nowEpochMs, deviceId)?.let { changed += it } }
        }
        if (injuries.isEmpty() && !injured && studentId in repository.listFlaggedStudentIds()) {
            // Marca antigua sin lesiones: se guarda la lesión `legacy-` como borrada y con
            // fecha de ahora. Así viaja por Sync LAN, pisa la `legacy-` del otro aparato
            // (fecha 0) y desde ahí el alumno se calcula desde las lesiones en los dos.
            val now = Instant.fromEpochMilliseconds(nowEpochMs)
            val tombstone = StudentInjury(
                id = legacyId(studentId),
                studentId = studentId,
                startsOn = date,
                isDeleted = true,
                trace = touched(null, now, deviceId),
            )
            repository.save(tombstone)
            changed += tombstone
        }
        reconcileStudent(studentId)
        return changed
    }

    /**
     * Recalcula la marca de todos los alumnos con lesiones para hoy. Se llama al abrir
     * la app, al cambiar de día y tras recibir datos por Sync LAN.
     * Devuelve los alumnos cuya marca cambió.
     */
    @Throws(Throwable::class)
    suspend fun reconcileFlags(): Set<Long> {
        val all = repository.listAll()
        if (all.isEmpty()) return emptySet()
        val managed = all.mapTo(mutableSetOf()) { it.studentId }
        val shouldBeInjured = StudentInjuryRules.injuredStudentIds(all, today())
        val flagged = repository.listFlaggedStudentIds()
        val changed = mutableSetOf<Long>()
        managed.forEach { studentId ->
            val target = studentId in shouldBeInjured
            if (target != (studentId in flagged)) {
                repository.setInjuredFlag(studentId, target)
                changed += studentId
            }
        }
        return changed
    }

    private suspend fun reconcileStudent(studentId: Long) {
        val target = StudentInjuryRules.activeOn(repository.listByStudent(studentId), today()) != null
        if (target != (studentId in repository.listFlaggedStudentIds())) {
            repository.setInjuredFlag(studentId, target)
        }
    }

    private fun touched(previous: AuditTrace?, now: Instant, deviceId: String?): AuditTrace =
        AuditTrace(
            createdAt = previous?.createdAt ?: now,
            updatedAt = now,
            deviceId = deviceId,
            syncVersion = (previous?.syncVersion ?: 0) + 1,
        )

    companion object {
        /** Id de la lesión que crea la migración 51 para una marca antigua. */
        fun legacyId(studentId: Long): String = "legacy-$studentId"

        /** Id nuevo con forma de UUID v4 (mismo formato que las juntas). */
        fun randomId(): String = com.migestor.shared.evaluationsession.randomEvaluationSessionId()
    }
}
