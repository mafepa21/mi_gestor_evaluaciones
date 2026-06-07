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

object ReadingFluencyMeasurements {
    const val WORDS_PER_MINUTE_DEFINITION_ID: String = "reading_fluency_words_per_minute"
    const val WORDS_PER_MINUTE_SCALE_ID: String = "reading_fluency_progress_scale"

    fun wordsPerMinuteDefinition(): AssessmentMeasurementDefinition =
        AssessmentMeasurementDefinition(
            id = WORDS_PER_MINUTE_DEFINITION_ID,
            name = "Fluidez lectora",
            domain = MeasurementDomain.READING_FLUENCY,
            measurementKind = "WORDS_PER_MINUTE",
            unit = "ppm",
            higherIsBetter = true,
            protocol = "Lectura cronometrada de un minuto con registro de palabras correctas por minuto.",
            material = "Texto graduado y cronómetro",
            attempts = 1,
            resultMode = "LATEST",
        )

    fun progressScale(): AssessmentMeasurementScale =
        AssessmentMeasurementScale(
            id = WORDS_PER_MINUTE_SCALE_ID,
            definitionId = WORDS_PER_MINUTE_DEFINITION_ID,
            name = "Progreso de fluidez lectora",
            domain = MeasurementDomain.READING_FLUENCY,
            direction = "HIGHER_IS_BETTER",
            ranges = listOf(
                AssessmentMeasurementScaleRange(
                    id = "reading_fluency_initial",
                    scaleId = WORDS_PER_MINUTE_SCALE_ID,
                    minValue = 0.0,
                    maxValue = 59.0,
                    score = 4.0,
                    label = "Inicial",
                    sortOrder = 0,
                ),
                AssessmentMeasurementScaleRange(
                    id = "reading_fluency_progress",
                    scaleId = WORDS_PER_MINUTE_SCALE_ID,
                    minValue = 60.0,
                    maxValue = 89.0,
                    score = 7.0,
                    label = "En progreso",
                    sortOrder = 1,
                ),
                AssessmentMeasurementScaleRange(
                    id = "reading_fluency_fluent",
                    scaleId = WORDS_PER_MINUTE_SCALE_ID,
                    minValue = 90.0,
                    maxValue = null,
                    score = 10.0,
                    label = "Fluida",
                    sortOrder = 2,
                ),
            ),
        )

    fun result(
        id: String,
        classId: Long,
        studentId: Long,
        wordsPerMinute: Double,
        observedAtEpochMs: Long,
        score: Double? = scoreForWordsPerMinute(wordsPerMinute),
    ): AssessmentMeasurementResult =
        AssessmentMeasurementResult(
            id = id,
            definitionId = WORDS_PER_MINUTE_DEFINITION_ID,
            domain = MeasurementDomain.READING_FLUENCY,
            classId = classId,
            studentId = studentId,
            rawValue = wordsPerMinute,
            rawText = wordsPerMinute.toString(),
            score = score,
            observedAtEpochMs = observedAtEpochMs,
        )

    fun scoreForWordsPerMinute(wordsPerMinute: Double): Double? {
        return progressScale().ranges
            .firstOrNull { range ->
                val aboveMin = range.minValue?.let { wordsPerMinute >= it } ?: true
                val belowMax = range.maxValue?.let { wordsPerMinute <= it } ?: true
                aboveMin && belowMax
            }
            ?.score
    }
}

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
