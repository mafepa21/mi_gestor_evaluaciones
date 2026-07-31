package com.migestor.shared.domain

enum class AssessmentInstrumentSourceKind {
    RUBRIC,
    OBSERVATION_GRID,
    CHECKLIST,
    TEACHER_OBSERVATION,
    SUBMISSION_CHECKLIST,

    /// Instrumentos mixtos que rellena el alumnado: rúbrica pequeña de 4 niveles que sí pondera
    /// (ítems `rub_<n>` en escala 1-4) más preguntas abiertas de reflexión que no puntúan
    /// (ítems `open_<n>`, tipo TEXT) y que revisa el profesorado.
    SELF_ASSESSMENT,
    PEER_ASSESSMENT,
}

enum class AssessmentInstrumentScoreStrategy {
    NONE,
    NUMERIC_0_TO_10,
    RUBRIC,
    CHECKLIST_ALL_OR_NOTHING,
    CHECKLIST_PROPORTIONAL,
    OBSERVATION_SCALE_1_TO_4,
    FORMULA,
}

data class AssessmentRubricDraft(
    val levels: List<AssessmentRubricLevelDraft>,
    val criteria: List<AssessmentRubricCriterionDraft>,
)

data class AssessmentRubricLevelDraft(
    val label: String,
    val points: Int,
)

data class AssessmentRubricCriterionDraft(
    val title: String,
    val descriptors: List<String>,
    val weight: Double,
)

data class AssessmentInstrumentItemDraft(
    val key: String,
    val title: String,
    val type: NotebookInstrumentItemType,
    val options: List<String> = emptyList(),
    val required: Boolean = true,
    val helpText: String? = null,
)

data class AssessmentInstrumentSpec(
    val title: String,
    val sourceKind: AssessmentInstrumentSourceKind,
    val columnType: NotebookColumnType,
    val instrumentKind: NotebookInstrumentKind,
    val inputKind: NotebookCellInputKind,
    val scaleKind: NotebookScaleKind,
    val weightPercent: Double,
    val countsTowardAverage: Boolean,
    val emptyCellPolicy: NotebookEmptyCellPolicy = NotebookEmptyCellPolicy.EXCLUDE_FROM_AVERAGE,
    val scoreStrategy: AssessmentInstrumentScoreStrategy,
    val rubricDraft: AssessmentRubricDraft? = null,
    val structuredItems: List<AssessmentInstrumentItemDraft> = emptyList(),
    val criterionLabels: List<String> = emptyList(),
    val formula: String? = null,
) {
    fun canMaterializeAverage(): Boolean =
        countsTowardAverage &&
            weightPercent > 0.0 &&
            scoreStrategy in materializableAverageStrategies
}

private val materializableAverageStrategies = setOf(
    AssessmentInstrumentScoreStrategy.NUMERIC_0_TO_10,
    AssessmentInstrumentScoreStrategy.RUBRIC,
    AssessmentInstrumentScoreStrategy.CHECKLIST_ALL_OR_NOTHING,
    // La checklist proporcional ya materializa nota (ítems marcados / total × 10) en
    // `NotebookInstrumentsRepositorySqlDelight.saveResponses`, así que puede computar en la media.
    AssessmentInstrumentScoreStrategy.CHECKLIST_PROPORTIONAL,
    AssessmentInstrumentScoreStrategy.OBSERVATION_SCALE_1_TO_4,
    AssessmentInstrumentScoreStrategy.FORMULA,
)

data class AssessmentInstrumentValidationIssue(
    val title: String,
    val message: String,
    val blocksMaterialization: Boolean,
)

fun AssessmentInstrumentSpec.validationIssues(): List<AssessmentInstrumentValidationIssue> {
    val cleanTitle = title.trim()
    val label = cleanTitle.ifEmpty { "Instrumento" }
    val issues = mutableListOf<AssessmentInstrumentValidationIssue>()
    if (cleanTitle.isEmpty()) {
        issues += AssessmentInstrumentValidationIssue(label, "El título es obligatorio.", true)
    }
    if (weightPercent < 0.0) {
        issues += AssessmentInstrumentValidationIssue(label, "El peso no puede ser negativo.", true)
    }
    if (countsTowardAverage && weightPercent <= 0.0) {
        issues += AssessmentInstrumentValidationIssue(label, "Un instrumento computable necesita peso mayor que 0.", true)
    }
    if (countsTowardAverage && scoreStrategy == AssessmentInstrumentScoreStrategy.NONE) {
        issues += AssessmentInstrumentValidationIssue(label, "Un instrumento computable necesita estrategia de puntuación.", true)
    }
    if (scoreStrategy == AssessmentInstrumentScoreStrategy.RUBRIC &&
        (rubricDraft == null || rubricDraft.criteria.isEmpty() || rubricDraft.levels.isEmpty())
    ) {
        issues += AssessmentInstrumentValidationIssue(label, "La rúbrica necesita criterios y niveles.", true)
    }
    if (scoreStrategy == AssessmentInstrumentScoreStrategy.OBSERVATION_SCALE_1_TO_4 &&
        scaleKind != NotebookScaleKind.FOUR_LEVEL
    ) {
        issues += AssessmentInstrumentValidationIssue(label, "La observación computable necesita escala 1-4.", true)
    }
    return issues
}
