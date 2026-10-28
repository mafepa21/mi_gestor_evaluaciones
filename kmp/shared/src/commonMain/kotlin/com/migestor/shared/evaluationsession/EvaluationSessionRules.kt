package com.migestor.shared.evaluationsession

import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.StudentSupportMeasure
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.repository.StudentAttendanceStats
import kotlin.random.Random

/** Reglas puras de la junta: sin E/S, fáciles de probar. */
object EvaluationSessionRules {
    /** Tope de «otras suspensas» que admite la junta. */
    const val MAX_OTHER_FAILED = 15
    const val PASS_THRESHOLD = 5.0

    fun validateOtherFailed(count: Int) {
        if (count !in 0..MAX_OTHER_FAILED) {
            throw EvaluationSessionException("Otras suspensas debe estar entre 0 y $MAX_OTHER_FAILED.")
        }
    }

    /** `null` sin Media; `true` si la Media es menor que 5 (mismo umbral que el Cuaderno). */
    fun ownFailed(average: Double?): Boolean? = average?.let { it < PASS_THRESHOLD }

    fun totalFailed(otherFailedCount: Int, ownFailed: Boolean?): Int =
        otherFailedCount + if (ownFailed == true) 1 else 0

    /** Porcentaje de faltas sobre los registros de asistencia. `null` si no hay registros. */
    fun absencePercent(stats: StudentAttendanceStats): Double? =
        if (stats.totalRecords <= 0L) null else stats.absentCount * 100.0 / stats.totalRecords

    /** Nivel más alto entre las medidas activas. Solo el nivel: nada clínico. */
    fun highestActiveLevel(measures: List<StudentSupportMeasure>): SupportMeasureLevel? =
        measures.filter { it.isActive }.maxByOrNull { it.level.ordinal }?.level

    /**
     * Media de cada alumno tal como la calcula el Cuaderno (BuildNotebookSheetUseCase).
     * No recalcula nada: lee la explicación de la media ya construida.
     */
    fun averagesFromNotebook(sheet: NotebookSheet): Map<Long, Double?> =
        sheet.rows.associate { row -> row.student.id to (row.averageExplanation?.average ?: row.weightedAverage) }

    fun frozenSnapshot(record: EvaluationSessionStudentRecord): EvaluationSessionStudentSnapshot =
        EvaluationSessionStudentSnapshot(
            studentId = record.studentId,
            average = record.frozenAverage,
            ownFailed = record.frozenOwnFailed,
            absencePercent = record.frozenAbsencePercent,
            absenceCount = record.frozenAbsenceCount,
            supportLevel = record.frozenSupportLevel,
            incidentCount = record.frozenIncidentCount,
        )

    fun emptySnapshot(studentId: Long) = EvaluationSessionStudentSnapshot(
        studentId = studentId,
        average = null,
        ownFailed = null,
        absencePercent = null,
        absenceCount = null,
        supportLevel = null,
        incidentCount = null,
    )

    fun row(
        record: EvaluationSessionStudentRecord,
        data: EvaluationSessionStudentSnapshot,
        isFrozen: Boolean,
    ) = EvaluationSessionStudentRow(
        studentId = record.studentId,
        firstName = record.firstName,
        lastName = record.lastName,
        average = data.average,
        ownFailed = data.ownFailed,
        absencePercent = data.absencePercent,
        absenceCount = data.absenceCount,
        supportLevel = data.supportLevel,
        incidentCount = data.incidentCount,
        otherFailedCount = record.otherFailedCount,
        totalFailed = totalFailed(record.otherFailedCount, data.ownFailed),
        agreement = record.agreement,
        isReviewed = record.isReviewed,
        isFrozen = isFrozen,
    )

    fun summary(rows: List<EvaluationSessionStudentRow>) = EvaluationSessionSummary(
        studentCount = rows.size,
        passAllCount = rows.count { it.totalFailed == 0 },
        oneOrTwoFailedCount = rows.count { it.totalFailed in 1..2 },
        threeOrMoreFailedCount = rows.count { it.totalFailed >= 3 },
        passedOwnSubjectCount = rows.count { it.ownFailed == false },
        reviewedCount = rows.count { it.isReviewed },
    )
}

/** UUID v4 en texto. Kotlin 1.9 no trae `kotlin.uuid` en código común. */
fun randomEvaluationSessionId(random: Random = Random.Default): String {
    val bytes = random.nextBytes(16)
    bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x40).toByte()
    bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
    val hex = bytes.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
        "${hex.substring(16, 20)}-${hex.substring(20)}"
}
