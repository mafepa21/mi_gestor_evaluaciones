package com.migestor.shared.usecase

import com.migestor.shared.repository.StudentsRepository
import com.migestor.shared.repository.ClassesRepository

class DeleteStudentUseCase(
    private val studentsRepository: StudentsRepository,
    private val classesRepository: ClassesRepository
) {
    suspend fun execute(studentId: Long, classId: Long? = null): Result<Unit> {
        return runCatching {
            if (classId != null) {
                // If classId is provided, we might just want to remove from class
                // but usually the "delete" from notebook means deleting the student record
                // or removing them from that specific course.
                // The user said: "se han de poder eliminar también"
                // Let's assume full deletion for now as CASCADE is active.
                studentsRepository.deleteStudent(studentId)
            } else {
                studentsRepository.deleteStudent(studentId)
            }
        }
    }
}
