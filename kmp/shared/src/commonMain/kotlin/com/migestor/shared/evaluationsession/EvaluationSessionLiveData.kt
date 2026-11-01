package com.migestor.shared.evaluationsession

import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.StudentSupportMeasure
import com.migestor.shared.repository.StudentAttendanceStats

/** Datos «en vivo» que la junta muestra mientras está abierta y copia al cerrar. */
interface EvaluationSessionLiveDataSource {
    /** Alumnado matriculado y activo en el grupo (curso escolar del grupo). */
    @Throws(Throwable::class)
    suspend fun studentIdsInClass(classId: Long): List<Long>

    @Throws(Throwable::class)
    suspend fun snapshots(classId: Long, studentIds: List<Long>): Map<Long, EvaluationSessionStudentSnapshot>
}

/**
 * Implementación sobre las fuentes ya existentes. Se inyectan funciones (como en
 * InclusionTasksUseCase) para no depender de contratos enormes y poder probarla.
 *
 * - Media: la del Cuaderno del grupo (BuildNotebookSheetUseCase), sin recalcular.
 * - Faltas: getStudentAttendanceStats (nº de ausencias y % sobre registros).
 * - Medidas: solo el nivel más alto activo (III/IV); nunca tipo ni notas.
 * - Incidencias: las del alumno en ese grupo.
 */
class DefaultEvaluationSessionLiveData(
    private val studentIdsForClass: suspend (Long) -> List<Long>,
    private val notebookAverages: suspend (Long) -> Map<Long, Double?>,
    private val attendanceStats: suspend (classId: Long, studentId: Long) -> StudentAttendanceStats,
    private val incidentsForClass: suspend (Long) -> List<Incident>,
    private val supportMeasures: suspend (Long) -> List<StudentSupportMeasure>,
) : EvaluationSessionLiveDataSource {

    override suspend fun studentIdsInClass(classId: Long): List<Long> = studentIdsForClass(classId).distinct()

    override suspend fun snapshots(
        classId: Long,
        studentIds: List<Long>,
    ): Map<Long, EvaluationSessionStudentSnapshot> {
        if (studentIds.isEmpty()) return emptyMap()
        val averages = notebookAverages(classId)
        val incidentCounts = incidentsForClass(classId)
            .mapNotNull { it.studentId }
            .groupingBy { it }
            .eachCount()
        return studentIds.distinct().associateWith { studentId ->
            val average = averages[studentId]
            val stats = attendanceStats(classId, studentId)
            EvaluationSessionStudentSnapshot(
                studentId = studentId,
                average = average,
                ownFailed = EvaluationSessionRules.ownFailed(average),
                absencePercent = EvaluationSessionRules.absencePercent(stats),
                absenceCount = stats.absentCount.toInt(),
                supportLevel = EvaluationSessionRules.highestActiveLevel(supportMeasures(studentId)),
                incidentCount = incidentCounts[studentId] ?: 0,
            )
        }
    }
}
