package com.migestor.shared.viewmodel

data class RubricEvaluationUsage(
    val classId: Long,
    val className: String,
    val evaluationId: Long,
    val evaluationName: String,
    val evaluationType: String,
    val weight: Double,
)

data class RubricUsageSummary(
    val rubricId: Long,
    val classCount: Int,
    val evaluationCount: Int,
    val linkedClassNames: List<String>,
    val evaluationUsages: List<RubricEvaluationUsage>,
) {
    val usageState: RubricUsageState
        get() = when (evaluationCount) {
            0 -> RubricUsageState.UNUSED
            1 -> RubricUsageState.SINGLE
            else -> RubricUsageState.MULTIPLE
        }
}

enum class RubricUsageState {
    UNUSED,
    SINGLE,
    MULTIPLE,
}

data class RubricBulkEvaluationTarget(
    val classId: Long,
    val evaluationId: Long,
    val rubricId: Long,
    val columnId: String? = null,
    val tabId: String? = null,
)

data class BulkEvaluationContextDialogState(
    val rubricId: Long,
    val rubricName: String,
    val options: List<RubricEvaluationUsage>,
)
