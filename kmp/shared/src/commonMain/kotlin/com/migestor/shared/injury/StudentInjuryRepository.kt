package com.migestor.shared.injury

/** Persistencia de las lesiones (tabla `student_injuries`, migración 51). */
interface StudentInjuryRepository {
    /** Todas, borradas incluidas (Sync LAN las necesita). */
    suspend fun listAll(): List<StudentInjury>

    /** Las del alumno, borradas incluidas. */
    suspend fun listByStudent(studentId: Long): List<StudentInjury>

    suspend fun get(id: String): StudentInjury?

    /** Inserta o sustituye. Guarda tal cual `trace.updatedAt` y `trace.deviceId`. */
    suspend fun save(injury: StudentInjury)

    /** Borrado físico (solo para un borrado que llegue por Sync LAN). */
    suspend fun hardDelete(id: String)

    /** Alumnos con la marca `students.is_injured = 1`. */
    suspend fun listFlaggedStudentIds(): Set<Long>

    /**
     * Cambia la marca derivada `students.is_injured` sin tocar `updated_at` del alumno:
     * cada dispositivo la calcula desde las lesiones, así no compite con otros cambios
     * del alumno en Sync LAN.
     */
    suspend fun setInjuredFlag(studentId: Long, isInjured: Boolean)
}
