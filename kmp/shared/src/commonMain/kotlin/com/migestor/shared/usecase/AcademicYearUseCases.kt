package com.migestor.shared.usecase

import com.migestor.shared.domain.AcademicYear
import com.migestor.shared.repository.AcademicYearsRepository

class ListAcademicYearsUseCase(private val repository: AcademicYearsRepository) {
    suspend operator fun invoke(): List<AcademicYear> = repository.listAcademicYears()
}

class GetActiveAcademicYearUseCase(private val repository: AcademicYearsRepository) {
    suspend operator fun invoke(): AcademicYear? = repository.getActiveAcademicYear()
}

class CreateAcademicYearUseCase(private val repository: AcademicYearsRepository) {
    suspend operator fun invoke(
        name: String,
        startEpochMs: Long,
        endEpochMs: Long,
        makeActive: Boolean = true,
    ): Long = repository.createAcademicYear(
        name = name,
        startEpochMs = startEpochMs,
        endEpochMs = endEpochMs,
        makeActive = makeActive,
    )
}

class SetActiveAcademicYearUseCase(private val repository: AcademicYearsRepository) {
    suspend operator fun invoke(academicYearId: Long) = repository.setActiveAcademicYear(academicYearId)
}

class ArchiveAcademicYearUseCase(private val repository: AcademicYearsRepository) {
    suspend operator fun invoke(academicYearId: Long) = repository.archiveAcademicYear(academicYearId)
}

class TrashAcademicYearUseCase(private val repository: AcademicYearsRepository) {
    suspend operator fun invoke(academicYearId: Long) = repository.trashAcademicYear(academicYearId)
}
