package com.migestor.shared.usecase

import com.migestor.shared.domain.AssessmentInstrumentScoreStrategy
import com.migestor.shared.domain.AssessmentInstrumentSpec
import com.migestor.shared.domain.AssessmentInstrumentValidationIssue
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.LearningSituationLinkedResource
import com.migestor.shared.domain.LearningSituationResourceKind
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookInstrumentItem
import com.migestor.shared.domain.NotebookInstrumentTemplate
import com.migestor.shared.domain.NotebookInstrumentTemplateKind
import com.migestor.shared.domain.validationIssues
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.LearningSituationsRepository
import com.migestor.shared.repository.NotebookInstrumentsRepository
import com.migestor.shared.repository.NotebookRepository
import com.migestor.shared.repository.RubricsRepository
import kotlinx.datetime.Clock

data class MaterializeLearningSituationAssessmentRequest(
    val situationId: Long,
    val situationTitle: String,
    val classId: Long,
    val targetTabId: String? = null,
    val sourceLabel: String,
    val deviceId: String? = null,
    val instruments: List<AssessmentInstrumentSpec>,
)

data class MaterializeLearningSituationAssessmentResult(
    val evaluationIds: List<Long>,
    val columnIds: List<String>,
    val rubricIds: List<Long>,
    val templateIds: List<String>,
    val issues: List<AssessmentInstrumentValidationIssue>,
)

class MaterializeLearningSituationAssessmentUseCase(
    private val evaluationsRepository: EvaluationsRepository,
    private val notebookRepository: NotebookRepository,
    private val notebookInstrumentsRepository: NotebookInstrumentsRepository,
    private val rubricsRepository: RubricsRepository,
    private val learningSituationsRepository: LearningSituationsRepository,
) {
    suspend fun execute(
        request: MaterializeLearningSituationAssessmentRequest,
    ): MaterializeLearningSituationAssessmentResult {
        val issues = request.instruments.flatMap { it.validationIssues() }
        if (request.instruments.isEmpty()) {
            return MaterializeLearningSituationAssessmentResult(
                evaluationIds = emptyList(),
                columnIds = emptyList(),
                rubricIds = emptyList(),
                templateIds = emptyList(),
                issues = listOf(
                    AssessmentInstrumentValidationIssue(
                        title = request.situationTitle,
                        message = "Selecciona al menos un instrumento.",
                        blocksMaterialization = true,
                    )
                ),
            )
        }
        if (issues.any { it.blocksMaterialization }) {
            return MaterializeLearningSituationAssessmentResult(
                evaluationIds = emptyList(),
                columnIds = emptyList(),
                rubricIds = emptyList(),
                templateIds = emptyList(),
                issues = issues,
            )
        }

        val tabId = resolveTargetTabId(request.classId, request.targetTabId)
        val trace = AuditTrace(
            createdAt = Clock.System.now(),
            updatedAt = Clock.System.now(),
            associatedGroupId = request.classId,
            deviceId = request.deviceId,
            syncVersion = 1,
        )
        val evaluationIds = mutableListOf<Long>()
        val columnIds = mutableListOf<String>()
        val rubricIds = mutableListOf<Long>()
        val templateIds = mutableListOf<String>()

        request.instruments.forEachIndexed { index, spec ->
            val rubricId = saveRubricIfNeeded(request, spec, trace)?.also { rubricIds += it }
            val evaluationId = evaluationsRepository.saveEvaluation(
                id = null,
                classId = request.classId,
                code = "SA${request.situationId}-I${index + 1}",
                name = spec.title,
                type = spec.sourceKind.name,
                weight = spec.weightPercent / 100.0,
                formula = spec.formula,
                rubricId = rubricId,
                description = "Instrumento importado desde ${request.sourceLabel} para ${request.situationTitle}",
                associatedGroupId = request.classId,
                deviceId = request.deviceId,
                syncVersion = 1,
            )
            evaluationIds += evaluationId

            val columnId = "eval_$evaluationId"
            val column = spec.toNotebookColumnDefinition(
                columnId = columnId,
                evaluationId = evaluationId,
                rubricId = rubricId,
                tabId = tabId,
                situationTitle = request.situationTitle,
                trace = trace,
            )
            notebookRepository.saveColumn(request.classId, column)
            columnIds += columnId

            val templateId = saveTemplateIfNeeded(request, spec, columnId, evaluationId, trace)
            if (templateId != null) templateIds += templateId

            saveLinkedResource(request, LearningSituationResourceKind.EVALUATION, evaluationId.toString(), spec.title, trace)
            saveLinkedResource(request, LearningSituationResourceKind.NOTEBOOK_COLUMN, columnId, spec.title, trace)
            if (rubricId != null) {
                saveLinkedResource(request, LearningSituationResourceKind.RUBRIC, rubricId.toString(), "Rúbrica · ${spec.title}", trace)
            }
        }

        return MaterializeLearningSituationAssessmentResult(
            evaluationIds = evaluationIds,
            columnIds = columnIds,
            rubricIds = rubricIds,
            templateIds = templateIds,
            issues = issues,
        )
    }

    private suspend fun resolveTargetTabId(classId: Long, preferredTabId: String?): String {
        val currentTabs = notebookRepository.loadNotebookSnapshot(classId).tabs
        if (preferredTabId != null && currentTabs.any { it.id == preferredTabId }) return preferredTabId
        currentTabs.firstOrNull()?.let { return it.id }
        val createdTitle = notebookRepository.createTab(classId, "Evaluación")
        val refreshedTabs = notebookRepository.loadNotebookSnapshot(classId).tabs
        return refreshedTabs.firstOrNull { it.title == createdTitle }?.id
            ?: refreshedTabs.firstOrNull()?.id
            ?: "TAB_$classId"
    }

    private suspend fun saveRubricIfNeeded(
        request: MaterializeLearningSituationAssessmentRequest,
        spec: AssessmentInstrumentSpec,
        trace: AuditTrace,
    ): Long? {
        if (spec.scoreStrategy != AssessmentInstrumentScoreStrategy.RUBRIC) return null
        val draft = spec.rubricDraft ?: return null
        val rubricId = rubricsRepository.saveRubric(
            name = spec.title,
            description = "Importada desde ${request.sourceLabel}",
            classId = request.classId,
            createdAtEpochMs = trace.createdAt.toEpochMilliseconds(),
            updatedAtEpochMs = trace.updatedAt.toEpochMilliseconds(),
            deviceId = request.deviceId,
            syncVersion = trace.syncVersion,
        )
        draft.criteria.forEachIndexed { criterionIndex, criterion ->
            val criterionId = rubricsRepository.saveCriterion(
                rubricId = rubricId,
                description = criterion.title,
                weight = criterion.weight,
                order = criterionIndex,
                updatedAtEpochMs = trace.updatedAt.toEpochMilliseconds(),
                deviceId = request.deviceId,
                syncVersion = trace.syncVersion,
            )
            draft.levels.forEachIndexed { levelIndex, level ->
                rubricsRepository.saveLevel(
                    criterionId = criterionId,
                    name = level.label,
                    points = level.points,
                    description = criterion.descriptors.getOrNull(levelIndex),
                    order = levelIndex,
                    updatedAtEpochMs = trace.updatedAt.toEpochMilliseconds(),
                    deviceId = request.deviceId,
                    syncVersion = trace.syncVersion,
                )
            }
        }
        return rubricId
    }

    private fun AssessmentInstrumentSpec.toNotebookColumnDefinition(
        columnId: String,
        evaluationId: Long,
        rubricId: Long?,
        tabId: String,
        situationTitle: String,
        trace: AuditTrace,
    ): NotebookColumnDefinition =
        NotebookColumnDefinition(
            id = columnId,
            title = title,
            type = if (rubricId != null) NotebookColumnType.RUBRIC else columnType,
            categoryKind = com.migestor.shared.domain.NotebookColumnCategoryKind.EVALUATION,
            instrumentKind = instrumentKind,
            inputKind = if (rubricId != null) com.migestor.shared.domain.NotebookCellInputKind.RUBRIC else inputKind,
            evaluationId = evaluationId,
            rubricId = rubricId,
            formula = formula,
            weight = weightPercent,
            unitOrSituation = situationTitle,
            scaleKind = scaleKind,
            tabIds = listOf(tabId),
            widthDp = 132.0,
            countsTowardAverage = canMaterializeAverage(),
            emptyCellPolicy = emptyCellPolicy,
            trace = trace,
        )

    private suspend fun saveTemplateIfNeeded(
        request: MaterializeLearningSituationAssessmentRequest,
        spec: AssessmentInstrumentSpec,
        columnId: String,
        evaluationId: Long,
        trace: AuditTrace,
    ): String? {
        if (spec.structuredItems.isEmpty()) return null
        val templateId = "template_$columnId"
        val template = NotebookInstrumentTemplate(
            id = templateId,
            classId = request.classId,
            columnId = columnId,
            evaluationId = evaluationId,
            title = spec.title,
            kind = templateKindFor(spec),
            inputKind = spec.inputKind,
            source = request.sourceLabel,
            trace = trace,
        )
        val items = spec.structuredItems.mapIndexed { index, item ->
            NotebookInstrumentItem(
                id = "${templateId}_item_$index",
                templateId = templateId,
                key = item.key,
                title = item.title,
                type = item.type,
                options = item.options,
                required = item.required,
                order = index,
                helpText = item.helpText,
                trace = trace,
            )
        }
        notebookInstrumentsRepository.saveTemplate(template, items)
        return templateId
    }

    private fun templateKindFor(spec: AssessmentInstrumentSpec): NotebookInstrumentTemplateKind =
        when (spec.sourceKind) {
            com.migestor.shared.domain.AssessmentInstrumentSourceKind.CHECKLIST,
            com.migestor.shared.domain.AssessmentInstrumentSourceKind.SUBMISSION_CHECKLIST -> NotebookInstrumentTemplateKind.CHECKLIST
            com.migestor.shared.domain.AssessmentInstrumentSourceKind.TEACHER_OBSERVATION -> NotebookInstrumentTemplateKind.OBSERVATION
            com.migestor.shared.domain.AssessmentInstrumentSourceKind.OBSERVATION_GRID,
            com.migestor.shared.domain.AssessmentInstrumentSourceKind.RUBRIC -> NotebookInstrumentTemplateKind.FORM
        }

    private suspend fun saveLinkedResource(
        request: MaterializeLearningSituationAssessmentRequest,
        kind: LearningSituationResourceKind,
        resourceId: String,
        label: String,
        trace: AuditTrace,
    ) {
        learningSituationsRepository.saveLinkedResource(
            LearningSituationLinkedResource(
                learningSituationId = request.situationId,
                kind = kind,
                resourceId = resourceId,
                classId = request.classId,
                label = label,
                trace = trace,
            )
        )
    }
}
