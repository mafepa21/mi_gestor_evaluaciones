package com.migestor.shared.viewmodel

import com.migestor.shared.domain.Rubric
import com.migestor.shared.domain.RubricCriterion
import com.migestor.shared.domain.RubricCriterionWithLevels
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.domain.RubricLevel
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class RubricEvaluationViewModelTest {

    private val testRubricId = 1L

    @Test
    fun `calculates total score with criterion weights when provided`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = listOf(
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 1, rubricId = testRubricId, description = "C1", weight = 3.0, order = 0),
                    levels = (1L..10L).map { levelId ->
                        RubricLevel(id = 10 + levelId, criterionId = 1, name = "L1.$levelId", points = 0, order = levelId.toInt())
                    }
                ),
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 2, rubricId = testRubricId, description = "C2", weight = 1.0, order = 1),
                    levels = (1L..2L).map { levelId ->
                        RubricLevel(id = 20 + levelId, criterionId = 2, name = "L2.$levelId", points = 0, order = levelId.toInt())
                    }
                )
            )
        )

        assertEquals(8.75, rubricDetail.calculateScore(mapOf(1L to 20L, 2L to 21L)))
        assertEquals(10.0, rubricDetail.calculateScore(mapOf(1L to 20L, 2L to 22L)))
    }

    @Test
    fun `partial rubric score is scaled over evaluated criteria only`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = (1L..4L).map { criterionId ->
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = criterionId, rubricId = testRubricId, description = "C$criterionId", weight = 1.0, order = criterionId.toInt()),
                    levels = listOf(
                        RubricLevel(id = criterionId * 10 + 1, criterionId = criterionId, name = "Inicial", points = 1, order = 1),
                        RubricLevel(id = criterionId * 10 + 2, criterionId = criterionId, name = "Excelente", points = 4, order = 2)
                    )
                )
            }
        )

        assertEquals(10.0, rubricDetail.calculateScore(mapOf(1L to 12L, 2L to 22L, 3L to 32L)))
    }

    @Test
    fun `calculates user example 3 criteria 4 levels each`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = (1L..3L).map { criterionId ->
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = criterionId, rubricId = testRubricId, description = "C$criterionId", weight = 1.0, order = criterionId.toInt()),
                    levels = (1L..4L).map { levelId ->
                        RubricLevel(id = criterionId * 10 + levelId, criterionId = criterionId, name = "L$criterionId.$levelId", points = 0, order = levelId.toInt())
                    }
                )
            }
        )

        assertEquals(10.0, rubricDetail.calculateScore(mapOf(1L to 14L, 2L to 24L, 3L to 34L)))
        assertEquals(5.0, rubricDetail.calculateScore(mapOf(1L to 12L, 2L to 23L, 3L to 31L)))
    }
}
