package com.migestor.shared.usecase

import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.CompetencyCriterion
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.NotebookStudentInsight

class BuildNotebookInsightsUseCase {
    fun build(
        sheet: NotebookSheet,
        competencies: List<CompetencyCriterion> = emptyList(),
        attendance: List<Attendance> = emptyList(),
        incidents: List<Incident> = emptyList(),
    ): List<NotebookStudentInsight> {
        val competencyNamesById = competencies.associate { it.id to "${it.code} · ${it.name}" }
        val attendanceByStudent = attendance.groupBy { it.studentId }
        val incidentsByStudent = incidents.groupBy { it.studentId }

        return sheet.rows.map { row ->
            val persistedCells = row.persistedCells
            val studentAttendance = attendanceByStudent[row.student.id].orEmpty()
            val latestAttendance = studentAttendance.maxByOrNull { it.date.toEpochMilliseconds() }
            val followUpCount = studentAttendance.count { it.followUpRequired || it.hasIncident }
            val studentIncidents = incidentsByStudent[row.student.id].orEmpty()
            val linkedCompetencyIds = (
                sheet.columns.filter { column ->
                    row.persistedGrades.any { it.columnId == column.id || (column.evaluationId != null && it.evaluationId == column.evaluationId) }
                }.flatMap { it.competencyCriteriaIds } +
                    persistedCells.flatMap { it.competencyCriteriaIds }
                ).distinct()

            NotebookStudentInsight(
                studentId = row.student.id,
                averageScore = row.weightedAverage,
                latestAttendanceStatus = latestAttendance?.status,
                followUpCount = followUpCount,
                incidentCount = studentIncidents.size,
                evidenceCount = row.persistedGrades.count { !it.evidence.isNullOrBlank() || !it.evidencePath.isNullOrBlank() } +
                    persistedCells.sumOf { it.annotation?.attachmentUris?.size ?: 0 },
                linkedCompetencyIds = linkedCompetencyIds,
                linkedCompetencyLabels = linkedCompetencyIds.mapNotNull(competencyNamesById::get),
            )
        }
    }
}
