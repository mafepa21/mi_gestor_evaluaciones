package com.migestor.shared.workgroup

import com.migestor.shared.domain.AuditTrace

/**
 * Marca que el docente pone a un alumno para organizar grupos de trabajo:
 * «Fuerte» o «Necesita apoyo». [NONE] es «sin marca» y se guarda como una fila
 * más para que quitar la marca viaje por Sync LAN igual que ponerla.
 */
enum class WorkGroupMark {
    NONE,
    STRONG,
    SUPPORT;

    companion object {
        /** Un valor desconocido (de una versión más nueva) cuenta como sin marca. */
        fun fromStorage(raw: String?): WorkGroupMark =
            entries.firstOrNull { it.name == raw } ?: NONE
    }
}

/** Marca de un alumno en un grupo-clase (tabla `student_group_marks`, migración 52). */
data class StudentGroupMark(
    val studentId: Long,
    val classId: Long,
    val mark: WorkGroupMark,
    val trace: AuditTrace = AuditTrace(),
) {
    /** Id de Sync LAN: la clave natural, igual en todos los dispositivos. */
    val syncId: String get() = StudentGroupMarkKeys.syncId(studentId, classId)
}

object StudentGroupMarkKeys {
    fun syncId(studentId: Long, classId: Long): String = "$studentId|$classId"

    /** `null` si el id no tiene la forma `alumno|grupo`. */
    fun parseSyncId(id: String): Pair<Long, Long>? {
        val parts = id.split("|")
        if (parts.size != 2) return null
        val studentId = parts[0].toLongOrNull() ?: return null
        val classId = parts[1].toLongOrNull() ?: return null
        return studentId to classId
    }
}
