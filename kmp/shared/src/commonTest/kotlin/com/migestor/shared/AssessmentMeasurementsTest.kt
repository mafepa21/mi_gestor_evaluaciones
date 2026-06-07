package com.migestor.shared

import com.migestor.shared.domain.MeasurementDomain
import com.migestor.shared.domain.PhysicalCapacity
import com.migestor.shared.domain.PhysicalMeasurementKind
import com.migestor.shared.domain.PhysicalResultMode
import com.migestor.shared.domain.PhysicalScaleDirection
import com.migestor.shared.domain.PhysicalTestDefinition
import com.migestor.shared.domain.PhysicalTestResult
import com.migestor.shared.domain.PhysicalTestScale
import com.migestor.shared.domain.PhysicalTestScaleRange
import com.migestor.shared.domain.asAssessmentMeasurementDefinition
import com.migestor.shared.domain.asAssessmentMeasurementResult
import com.migestor.shared.domain.asAssessmentMeasurementScale
import kotlin.test.Test
import kotlin.test.assertEquals

class AssessmentMeasurementsTest {
    @Test
    fun `physical definition maps to generic measurement definition`() {
        val physical = PhysicalTestDefinition(
            id = "navette",
            name = "Course Navette",
            capacity = PhysicalCapacity.RESISTANCE,
            measurementKind = PhysicalMeasurementKind.LEVEL,
            unit = "nivel",
            higherIsBetter = true,
            protocol = "Protocolo",
            material = "Audio",
            attempts = 2,
            resultMode = PhysicalResultMode.BEST,
        )

        val generic = physical.asAssessmentMeasurementDefinition()

        assertEquals("navette", generic.id)
        assertEquals("Course Navette", generic.name)
        assertEquals(MeasurementDomain.PHYSICAL_EDUCATION, generic.domain)
        assertEquals("LEVEL", generic.measurementKind)
        assertEquals("nivel", generic.unit)
        assertEquals(true, generic.higherIsBetter)
        assertEquals(2, generic.attempts)
    }

    @Test
    fun `physical scale and result keep scoring context`() {
        val scale = PhysicalTestScale(
            id = "scale-1",
            testId = "jump",
            name = "Salto horizontal",
            direction = PhysicalScaleDirection.HIGHER_IS_BETTER,
            ranges = listOf(
                PhysicalTestScaleRange(
                    id = "range-1",
                    scaleId = "scale-1",
                    minValue = 1.5,
                    maxValue = 2.0,
                    score = 7.0,
                    label = "Adecuado",
                    sortOrder = 1,
                )
            ),
        )
        val result = PhysicalTestResult(
            id = "result-1",
            assignmentId = "assignment-1",
            testId = "jump",
            classId = 1,
            studentId = 2,
            rawValue = 1.72,
            rawText = "1.72",
            score = 7.0,
            scaleId = "scale-1",
            observedAtEpochMs = 1000,
            rawColumnId = null,
            scoreColumnId = null,
        )

        val genericScale = scale.asAssessmentMeasurementScale()
        val genericResult = result.asAssessmentMeasurementResult()

        assertEquals(MeasurementDomain.PHYSICAL_EDUCATION, genericScale.domain)
        assertEquals("jump", genericScale.definitionId)
        assertEquals(1, genericScale.ranges.size)
        assertEquals("Adecuado", genericScale.ranges.first().label)
        assertEquals("jump", genericResult.definitionId)
        assertEquals(1.72, genericResult.rawValue)
        assertEquals(7.0, genericResult.score)
    }
}
