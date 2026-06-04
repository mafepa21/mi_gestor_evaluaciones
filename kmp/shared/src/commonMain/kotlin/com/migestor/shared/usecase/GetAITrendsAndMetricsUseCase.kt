package com.migestor.shared.usecase

import com.migestor.shared.repository.AITrendsRepository
import com.migestor.shared.repository.StudentGradeHistoryPoint
import com.migestor.shared.repository.StudentAttendanceStats
import com.migestor.shared.repository.StudentIncidentPoint
import com.migestor.shared.repository.CompetencyCoveragePoint

data class AITrendsSnapshot(
    val trendDirection: String, // "UPWARD", "STABLE", "DOWNWARD", "INSUFFICIENT"
    val averageGradeDelta: Double,
    val attendanceCorrelationNote: String,
    val behaviorIncidentSummary: String,
    val curriculumCoveragePct: Double,
    val missingCompetencyLabels: List<String>,
    val recentGrades: List<Double>,
    val attendanceRate: Double
)

class GetAITrendsAndMetricsUseCase(
    private val aiTrendsRepository: AITrendsRepository
) {
    suspend operator fun invoke(classId: Long, studentId: Long?): AITrendsSnapshot {
        val gradesHistory = studentId?.let { aiTrendsRepository.getStudentGradesHistory(classId, it) } ?: emptyList()
        val attendance = studentId?.let { aiTrendsRepository.getStudentAttendanceStats(classId, it) }
        val incidents = studentId?.let { aiTrendsRepository.getStudentIncidentsHistory(classId, it) } ?: emptyList()
        val competencyCoverage = aiTrendsRepository.getCompetencyCoverage(classId)

        // 1. Calcular Tendencia de Notas
        val recentGrades = gradesHistory.map { it.score }
        val (trendDirection, gradeDelta) = if (recentGrades.size < 2) {
            Pair("INSUFFICIENT", 0.0)
        } else {
            val midIndex = recentGrades.size / 2
            val firstHalf = recentGrades.subList(0, midIndex)
            val secondHalf = recentGrades.subList(midIndex, recentGrades.size)
            
            val avgFirst = firstHalf.average()
            val avgSecond = secondHalf.average()
            val delta = avgSecond - avgFirst
            
            val direction = when {
                delta > 0.5 -> "UPWARD"
                delta < -0.5 -> "DOWNWARD"
                else -> "STABLE"
            }
            Pair(direction, delta)
        }

        // 2. Procesar Asistencia
        val totalAttendanceRecords = attendance?.totalRecords ?: 0L
        val absentCount = attendance?.absentCount ?: 0L
        val attendanceRate = if (totalAttendanceRecords > 0L) {
            ((totalAttendanceRecords - absentCount).toDouble() / totalAttendanceRecords.toDouble()) * 100.0
        } else {
            100.0
        }

        val attendanceNote = when {
            totalAttendanceRecords == 0L -> "Sin registros de asistencia."
            attendanceRate < 85.0 -> "Baja asistencia (\${IosDecimal(attendanceRate)}%) que puede condicionar la evaluación y el ritmo."
            attendanceRate < 90.0 -> "Asistencia en nivel de atención puntual (\${IosDecimal(attendanceRate)}%)."
            else -> "Asistencia regular y correcta (\${IosDecimal(attendanceRate)}%)."
        }

        // 3. Procesar Incidencias
        val totalIncidents = incidents.size
        val highSeverityIncidents = incidents.filter { it.severity.lowercase() == "high" || it.severity.lowercase() == "grave" }.size
        val behaviorSummary = when {
            totalIncidents == 0 -> "Sin incidencias de convivencia registradas."
            highSeverityIncidents > 0 -> "Registra \${totalIncidents} incidencias, con \${highSeverityIncidents} de gravedad alta."
            else -> "Registra \${totalIncidents} incidencias de carácter leve/moderado."
        }

        // 4. Calcular Cobertura LOMLOE
        val totalCompetencies = competencyCoverage.size
        val coveredCompetencies = competencyCoverage.filter { it.columnsCount > 0L }.size
        val coveragePct = if (totalCompetencies > 0) {
            (coveredCompetencies.toDouble() / totalCompetencies.toDouble()) * 100.0
        } else {
            100.0
        }

        val missingCompetencies = competencyCoverage
            .filter { it.columnsCount == 0L }
            .map { it.code }

        return AITrendsSnapshot(
            trendDirection = trendDirection,
            averageGradeDelta = gradeDelta,
            attendanceCorrelationNote = attendanceNote,
            behaviorIncidentSummary = behaviorSummary,
            curriculumCoveragePct = coveragePct,
            missingCompetencyLabels = missingCompetencies,
            recentGrades = recentGrades,
            attendanceRate = attendanceRate
        )
    }

    private fun IosDecimal(value: Double): String {
        val multiplied = (value * 10).toInt()
        val integral = multiplied / 10
        val fractional = multiplied % 10
        return "$integral.$fractional"
    }
}
