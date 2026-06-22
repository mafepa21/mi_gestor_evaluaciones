package com.migestor.shared.domain.usecase

import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.RadarCategory
import com.migestor.shared.domain.RadarPriority
import com.migestor.shared.domain.TeacherRadarInsight
import kotlin.math.roundToInt

class BuildTeacherRadarUseCase {
    fun build(
        sheet: NotebookSheet,
        attendance: List<Attendance> = emptyList(),
        previousAveragesByStudentId: Map<Long, Double> = emptyMap(),
        requiredEvidenceWindow: Int = 3,
    ): List<TeacherRadarInsight> {
        val attendanceByStudentId = attendance.groupBy { it.studentId }
        val rubricColumns = sheet.columns.filter { it.type == NotebookColumnType.RUBRIC }
        val requiredColumns = sheet.columns.filter { it.type == NotebookColumnType.RUBRIC || it.rubricId != null }
        val insights = mutableListOf<TeacherRadarInsight>()

        sheet.rows.forEach { row ->
            val student = row.student
            val average = row.weightedAverage
            val attendanceRate = attendanceRate(attendanceByStudentId[student.id].orEmpty())
            val evidenceCount = row.persistedGrades.count { !it.evidence.isNullOrBlank() || !it.evidencePath.isNullOrBlank() } +
                row.persistedCells.sumOf { it.attachmentCount }
            val missingRubrics = rubricColumns.count { column ->
                val grade = row.persistedGrades.firstOrNull { it.columnId == column.id || it.evaluationId == column.evaluationId }
                grade?.rubricSelections.isNullOrBlank() && grade?.value == null
            }
            val pendingRequired = requiredColumns.count { column ->
                val grade = row.persistedGrades.firstOrNull { it.columnId == column.id || it.evaluationId == column.evaluationId }
                val cell = row.persistedCells.firstOrNull { it.columnId == column.id }
                grade?.value == null && grade?.rubricSelections.isNullOrBlank() && cell?.displayValue.isNullOrBlank()
            }
            val previousAverage = previousAveragesByStudentId[student.id]
            val dropped = average != null && previousAverage != null && average + 0.5 < previousAverage
            val improved = average != null && previousAverage != null && average - previousAverage > 1.0
            val attendanceEvidence = attendanceRate?.let { "Asistencia: ${it}%." }

            if (average != null && average < 5.0 && attendanceRate != null && attendanceRate < 80) {
                insights += TeacherRadarInsight(
                    id = "student-${student.id}-high-risk",
                    classId = sheet.classId,
                    studentId = student.id,
                    priority = RadarPriority.HIGH,
                    category = RadarCategory.STUDENT_RISK,
                    title = "${student.fullName}: media < 5 y asistencia < 80%",
                    explanation = "Concurren bajo rendimiento registrado y baja asistencia.",
                    suggestedAction = "Revisar hoy evidencias recientes y acordar una intervención breve.",
                    evidence = listOfNotNull("Media: ${average.formatOneDecimal()}.", attendanceEvidence)
                )
            } else if (average != null && average in 5.0..6.0 || dropped) {
                insights += TeacherRadarInsight(
                    id = "student-${student.id}-medium-risk",
                    classId = sheet.classId,
                    studentId = student.id,
                    priority = RadarPriority.MEDIUM,
                    category = RadarCategory.STUDENT_RISK,
                    title = "${student.fullName}: seguimiento académico",
                    explanation = if (dropped) "La media baja respecto al corte anterior." else "La media está en una franja frágil.",
                    suggestedAction = "Observar un criterio concreto en la próxima sesión y registrar evidencia.",
                    evidence = listOfNotNull("Media actual: ${average?.formatOneDecimal() ?: "sin dato"}.", previousAverage?.let { "Media anterior: ${it.formatOneDecimal()}." })
                )
            }

            if (evidenceCount < requiredEvidenceWindow) {
                insights += TeacherRadarInsight(
                    id = "student-${student.id}-evidence-gap",
                    classId = sheet.classId,
                    studentId = student.id,
                    priority = if (evidenceCount == 0) RadarPriority.HIGH else RadarPriority.MEDIUM,
                    category = RadarCategory.EVIDENCE_GAP,
                    title = "${student.fullName}: pocas evidencias recientes",
                    explanation = "Hay menos de $requiredEvidenceWindow evidencias asociadas en el cuaderno.",
                    suggestedAction = "Recoger una evidencia observable y vincularla al cuaderno.",
                    evidence = listOf("Evidencias: $evidenceCount/$requiredEvidenceWindow.")
                )
            }

            if (missingRubrics > 0 || pendingRequired > 0) {
                insights += TeacherRadarInsight(
                    id = "student-${student.id}-rubric-pending",
                    classId = sheet.classId,
                    studentId = student.id,
                    priority = RadarPriority.MEDIUM,
                    category = RadarCategory.RUBRIC_COMPLETION,
                    title = "${student.fullName}: rúbrica o tarea pendiente",
                    explanation = "Quedan instrumentos obligatorios incompletos.",
                    suggestedAction = "Completar la rúbrica pendiente antes del siguiente corte.",
                    evidence = listOf("Rúbricas incompletas: $missingRubrics.", "Tareas/criterios pendientes: $pendingRequired.")
                )
            }

            if (improved && attendanceRate?.let { it >= 90 } != false) {
                insights += TeacherRadarInsight(
                    id = "student-${student.id}-positive-progress",
                    classId = sheet.classId,
                    studentId = student.id,
                    priority = RadarPriority.POSITIVE,
                    category = RadarCategory.POSITIVE_PROGRESS,
                    title = "${student.fullName}: mejora significativa",
                    explanation = "La media mejora más de 1 punto y no hay señal negativa de asistencia.",
                    suggestedAction = "Dar feedback positivo y mantener el seguimiento.",
                    evidence = listOfNotNull("Media: ${previousAverage?.formatOneDecimal()} -> ${average?.formatOneDecimal()}.", attendanceEvidence)
                )
            }
        }

        val incompleteRubrics = if (rubricColumns.isEmpty()) 0 else sheet.rows.count { row ->
            rubricColumns.any { column ->
                val grade = row.persistedGrades.firstOrNull { it.columnId == column.id || it.evaluationId == column.evaluationId }
                grade?.rubricSelections.isNullOrBlank() && grade?.value == null
            }
        }
        if (incompleteRubrics > 0) {
            insights += TeacherRadarInsight(
                id = "class-${sheet.classId}-rubric-summary",
                classId = sheet.classId,
                studentId = null,
                priority = RadarPriority.HIGH,
                category = RadarCategory.GROUP_SUMMARY,
                title = "Grupo: rúbricas incompletas en $incompleteRubrics alumnos",
                explanation = "Hay criterios de rúbrica sin completar en el grupo.",
                suggestedAction = "Planificar una sesión con observación específica de los criterios pendientes.",
                evidence = listOf("Columnas de rúbrica: ${rubricColumns.size}.", "Alumnos afectados: $incompleteRubrics.")
            )
        }

        return insights.sortedWith(
            compareBy<TeacherRadarInsight> { it.priority.sortWeight }
                .thenBy { it.studentId ?: Long.MAX_VALUE }
                .thenBy { it.title }
        )
    }

    private val RadarPriority.sortWeight: Int
        get() = when (this) {
            RadarPriority.HIGH -> 0
            RadarPriority.MEDIUM -> 1
            RadarPriority.LOW -> 2
            RadarPriority.POSITIVE -> 3
        }

    private fun attendanceRate(attendance: List<Attendance>): Int? {
        if (attendance.isEmpty()) return null
        val present = attendance.count { it.status.equals("PRESENTE", ignoreCase = true) || it.status.equals("JUSTIFICADO", ignoreCase = true) }
        return ((present.toDouble() / attendance.size.toDouble()) * 100.0).roundToInt().coerceIn(0, 100)
    }

    private fun Double.formatOneDecimal(): String =
        (kotlin.math.round(this * 10.0) / 10.0).toString()
}
