package com.migestor.shared.workgroup

/** Persistencia de las marcas Fuerte / Necesita apoyo (tabla `student_group_marks`). */
interface StudentGroupMarkRepository {
    /** Todas, «sin marca» incluidas (Sync LAN las necesita). */
    suspend fun listAll(): List<StudentGroupMark>

    /** Las del grupo-clase, «sin marca» incluidas. */
    suspend fun listByClass(classId: Long): List<StudentGroupMark>

    suspend fun get(studentId: Long, classId: Long): StudentGroupMark?

    /**
     * Inserta o sustituye y devuelve lo que quedó guardado. Guarda tal cual
     * [updatedAtEpochMs] y [deviceId]: Sync LAN conserva la hora del otro equipo.
     */
    suspend fun save(
        studentId: Long,
        classId: Long,
        mark: WorkGroupMark,
        updatedAtEpochMs: Long,
        deviceId: String?,
    ): StudentGroupMark

    /** Borrado físico (solo para un borrado que llegue por Sync LAN). */
    suspend fun delete(studentId: Long, classId: Long)
}
