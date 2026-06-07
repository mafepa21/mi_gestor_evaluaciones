package com.migestor.shared.domain

enum class MeasurementDomain {
    PHYSICAL_EDUCATION,
    READING_FLUENCY,
    ORAL_PRESENTATION,
    LAB_PRACTICE,
    PROJECT_MILESTONE,
    CUSTOM,
}

data class AssessmentMeasurementDefinition(
    val id: String,
    val name: String,
    val domain: MeasurementDomain,
    val measurementKind: String,
    val unit: String,
    val higherIsBetter: Boolean,
    val protocol: String = "",
    val material: String = "",
    val attempts: Int = 1,
    val resultMode: String = "BEST",
    val trace: AuditTrace = AuditTrace(),
)

data class AssessmentMeasurementScale(
    val id: String,
    val definitionId: String,
    val name: String,
    val domain: MeasurementDomain,
    val direction: String,
    val ranges: List<AssessmentMeasurementScaleRange>,
    val trace: AuditTrace = AuditTrace(),
)

data class AssessmentMeasurementScaleRange(
    val id: String,
    val scaleId: String,
    val minValue: Double?,
    val maxValue: Double?,
    val score: Double,
    val label: String? = null,
    val sortOrder: Int = 0,
)

data class AssessmentMeasurementResult(
    val id: String,
    val definitionId: String,
    val domain: MeasurementDomain,
    val classId: Long,
    val studentId: Long,
    val rawValue: Double?,
    val rawText: String,
    val score: Double?,
    val observedAtEpochMs: Long,
    val trace: AuditTrace = AuditTrace(),
)

fun PhysicalTestDefinition.asAssessmentMeasurementDefinition(): AssessmentMeasurementDefinition =
    AssessmentMeasurementDefinition(
        id = id,
        name = name,
        domain = MeasurementDomain.PHYSICAL_EDUCATION,
        measurementKind = measurementKind.name,
        unit = unit,
        higherIsBetter = higherIsBetter,
        protocol = protocol,
        material = material,
        attempts = attempts,
        resultMode = resultMode.name,
        trace = trace,
    )

fun PhysicalTestScale.asAssessmentMeasurementScale(): AssessmentMeasurementScale =
    AssessmentMeasurementScale(
        id = id,
        definitionId = testId,
        name = name,
        domain = MeasurementDomain.PHYSICAL_EDUCATION,
        direction = direction.name,
        ranges = ranges.map { it.asAssessmentMeasurementScaleRange() },
        trace = trace,
    )

fun PhysicalTestScaleRange.asAssessmentMeasurementScaleRange(): AssessmentMeasurementScaleRange =
    AssessmentMeasurementScaleRange(
        id = id,
        scaleId = scaleId,
        minValue = minValue,
        maxValue = maxValue,
        score = score,
        label = label,
        sortOrder = sortOrder,
    )

fun PhysicalTestResult.asAssessmentMeasurementResult(): AssessmentMeasurementResult =
    AssessmentMeasurementResult(
        id = id,
        definitionId = testId,
        domain = MeasurementDomain.PHYSICAL_EDUCATION,
        classId = classId,
        studentId = studentId,
        rawValue = rawValue,
        rawText = rawText,
        score = score,
        observedAtEpochMs = observedAtEpochMs,
        trace = trace,
    )
