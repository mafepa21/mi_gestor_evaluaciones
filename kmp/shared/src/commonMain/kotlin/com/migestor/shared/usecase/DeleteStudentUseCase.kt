package com.migestor.shared.usecase

import com.migestor.shared.repository.StudentsRepository
import com.migestor.shared.repository.ClassesRepository

class DeleteStudentUseCase(
    private val studentsRepository: StudentsRepository,
    private val classesRepository: ClassesRepository
) {
    /**
     * Con [classId], solo da de baja al alumno en ese curso.
     * La ficha entera se borra únicamente si [deleteEverywhere] es true.
     * Sin curso y sin esa orden, no borra nada.
     */
    suspend fun execute(
        studentId: Long,
        classId: Long? = null,
        deleteEverywhere: Boolean = false,
    ): Result<Unit> {
        return runCatching {
            when {
                deleteEverywhere -> studentsRepository.deleteStudent(studentId)
                classId != null -> classesRepository.removeStudentFromClass(classId, studentId)
                else -> error("Hace falta un curso o una orden explícita para borrar al alumno.")
            }
        }
    }
}
