package com.migestor.shared.usecase

import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.repository.AttendanceRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.PlannerRepository
import com.migestor.shared.repository.RubricsRepository
import com.migestor.shared.repository.StudentsRepository

class SaveStudentUseCase(
    private val repository: StudentsRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        firstName: String,
        lastName: String,
        email: String? = null,
        photoPath: String? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        requireNotBlank(firstName, "Nombre")
        requireNotBlank(lastName, "Apellidos")
        return repository.saveStudent(
            id = id,
            firstName = firstName.trim(),
            lastName = lastName.trim(),
            email = email?.trim()?.ifBlank { null },
            photoPath = photoPath?.trim()?.ifBlank { null },
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId,
            syncVersion = syncVersion
        )
    }
}

class SaveClassUseCase(
    private val repository: ClassesRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        name: String,
        course: Int,
        description: String? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        requireNotBlank(name, "Nombre de clase")
        require(course > 0) { "Curso debe ser mayor que cero" }
        return repository.saveClass(id, name.trim(), course, description?.trim(), updatedAtEpochMs = updatedAtEpochMs, deviceId = deviceId, syncVersion = syncVersion)
    }
}

class SaveEvaluationUseCase(
    private val repository: EvaluationsRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        classId: Long,
        code: String,
        name: String,
        type: String,
        weight: Double,
        formula: String? = null,
        rubricId: Long? = null,
        description: String? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        require(classId > 0) { "ClassId inválido" }
        requireNotBlank(code, "Código")
        requireNotBlank(name, "Nombre")
        requireNotBlank(type, "Tipo")
        requirePositive(weight, "Peso")
        return repository.saveEvaluation(
            id = id,
            classId = classId,
            code = code.trim(),
            name = name.trim(),
            type = type.trim(),
            weight = weight,
            formula = formula?.trim()?.ifBlank { null },
            rubricId = rubricId,
            description = description?.trim()?.ifBlank { null },
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId,
            syncVersion = syncVersion
        )
    }
}

class RecordGradeUseCase(
    private val repository: GradesRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        classId: Long,
        studentId: Long,
        evaluationId: Long,
        value: Double?,
        evidence: String? = null,
        evidencePath: String? = null,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        require(classId > 0) { "ClassId inválido" }
        require(studentId > 0) { "StudentId inválido" }
        require(evaluationId > 0) { "EvaluationId inválido" }
        if (value != null) {
            require(value in 0.0..10.0) { "La nota debe estar entre 0 y 10" }
        }
        return repository.saveGrade(
            id = id,
            classId = classId,
            studentId = studentId,
            columnId = "eval_${evaluationId}",
            evaluationId = evaluationId,
            value = value,
            evidence = evidence?.trim()?.ifBlank { null },
            evidencePath = evidencePath?.trim()?.ifBlank { null },
            createdAtEpochMs = createdAtEpochMs,
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId,
            syncVersion = syncVersion
        )
    }
}

class SaveSessionUseCase(private val repo: PlannerRepository) {
    suspend operator fun invoke(session: PlanningSession): Long =
        repo.upsertSession(session)
}

class DeleteSessionUseCase(private val repo: PlannerRepository) {
    suspend operator fun invoke(sessionId: Long) =
        repo.deleteSession(sessionId)
}

class GetSessionsUseCase(private val repo: PlannerRepository) {
    fun invoke(week: Int, year: Int) =
        repo.observeSessions(week, year)
}

class SaveRubricUseCase(
    private val repository: RubricsRepository,
) {
    suspend operator fun invoke(
        id: Long? = null, 
        name: String, 
        description: String?,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null, 
        syncVersion: Long = 0
    ): Long {
        requireNotBlank(name, "Rúbrica")
        return repository.saveRubric(
            id = id,
            name = name.trim(),
            description = description?.trim()?.ifBlank { null },
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId,
            syncVersion = syncVersion
        )
    }
}

class SaveCriterionUseCase(
    private val repository: RubricsRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        rubricId: Long,
        description: String,
        weight: Double,
        order: Int,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        require(rubricId > 0) { "Rúbrica inválida" }
        requireNotBlank(description, "Criterio")
        requirePositive(weight, "Peso")
        return repository.saveCriterion(id, rubricId, description.trim(), weight, order, updatedAtEpochMs = updatedAtEpochMs, deviceId = deviceId, syncVersion = syncVersion)
    }
}

class SaveLevelUseCase(
    private val repository: RubricsRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        criterionId: Long,
        name: String,
        points: Int,
        description: String?,
        order: Int,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        require(criterionId > 0) { "Criterio inválido" }
        requireNotBlank(name, "Nivel")
        return repository.saveLevel(id, criterionId, name.trim(), points, description?.trim()?.ifBlank { null }, order, updatedAtEpochMs = updatedAtEpochMs, deviceId = deviceId, syncVersion = syncVersion)
    }
}

class SaveAttendanceUseCase(
    private val repository: AttendanceRepository,
) {
    suspend operator fun invoke(
        id: Long? = null,
        studentId: Long,
        classId: Long,
        dateEpochMs: Long,
        status: String,
        note: String = "",
        hasIncident: Boolean = false,
        followUpRequired: Boolean = false,
        sessionId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long {
        require(studentId > 0) { "Alumno inválido" }
        require(classId > 0) { "Clase inválida" }
        requireNotBlank(status, "Estado")
        return repository.saveAttendance(
            id = id,
            studentId = studentId,
            classId = classId,
            dateEpochMs = dateEpochMs,
            status = status.trim(),
            note = note.trim(),
            hasIncident = hasIncident,
            followUpRequired = followUpRequired,
            sessionId = sessionId,
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId,
            syncVersion = syncVersion
        )
    }
}
