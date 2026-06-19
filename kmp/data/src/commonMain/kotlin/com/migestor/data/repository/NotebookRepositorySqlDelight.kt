package com.migestor.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import com.migestor.shared.usecase.BuildNotebookSheetUseCase
import com.migestor.shared.usecase.NotebookSheetMemoryCache
import com.migestor.shared.usecase.notebookSheetCacheKey
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

private fun notebookStudentSexOrDefault(value: String): StudentSex {
    return runCatching { StudentSex.valueOf(value) }.getOrDefault(StudentSex.UNSPECIFIED)
}

private fun notebookStudentSexSourceOrDefault(value: String): StudentSexSource {
    return runCatching { StudentSexSource.valueOf(value) }.getOrDefault(StudentSexSource.UNKNOWN)
}

private fun notebookLocalDateOrNull(value: String?): LocalDate? {
    return value?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
}

class NotebookRepositorySqlDelight(
    private val db: AppDatabase,
    private val studentsRepository: StudentsRepository,
    private val classesRepository: ClassesRepository,
    private val evaluationsRepository: EvaluationsRepository,
    private val notebookConfigRepository: NotebookConfigRepository,
    private val buildNotebookSheetUseCase: BuildNotebookSheetUseCase,
    private val gradesRepository: GradesRepository,
    private val notebookCellsRepository: NotebookCellsRepository,
    private val sheetCache: NotebookSheetMemoryCache = NotebookSheetMemoryCache(),
) : NotebookRepository {

    override suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet = withContext(Dispatchers.Default) {
        // 1. Cargar las 9 fuentes de datos en paralelo para minimizar latencia de DB.
        val students: List<Student>
        val evaluations: List<Evaluation>
        val tabs: List<NotebookTab>
        val columns: List<NotebookColumnDefinition>
        val columnCategories: List<NotebookColumnCategory>
        val groups: List<NotebookWorkGroup>
        val members: List<NotebookWorkGroupMember>
        val grades: List<Grade>
        val cells: List<PersistedNotebookCell>

        coroutineScope {
            val studentsD         = async { classesRepository.listStudentsInClass(classId) }
            val evaluationsD      = async { evaluationsRepository.listClassEvaluations(classId) }
            val tabsD             = async { notebookConfigRepository.listTabs(classId) }
            val columnsD          = async { notebookConfigRepository.listColumns(classId) }
            val columnCategoriesD = async { notebookConfigRepository.listColumnCategories(classId) }
            val groupsD           = async { notebookConfigRepository.listWorkGroups(classId) }
            val membersD          = async { notebookConfigRepository.listWorkGroupMembers(classId) }
            val gradesD           = async { gradesRepository.listGradesForClass(classId) }
            val cellsD            = async { notebookCellsRepository.listClassCells(classId) }
            students         = studentsD.await()
            evaluations      = evaluationsD.await()
            tabs             = tabsD.await()
            columns          = columnsD.await()
            columnCategories = columnCategoriesD.await()
            groups           = groupsD.await()
            members          = membersD.await()
            grades           = gradesD.await()
            cells            = cellsD.await()
        }

        // 2. Comprobar si el sheet ya está en caché con la misma clave de versión.
        val cacheKey = notebookSheetCacheKey(
            classId    = classId,
            students   = students,
            tabs       = tabs,
            columns    = columns,
            categories = columnCategories,
            groups     = groups,
            members    = members,
            grades     = grades,
            cells      = cells,
        )
        sheetCache.get(cacheKey)?.let { return@withContext it }

        // 3. Cache miss → construir el sheet completo y almacenarlo.
        val sheet = buildNotebookSheetUseCase.build(
            classId           = classId,
            evaluations       = evaluations,
            students          = students,
            tabs              = tabs,
            configuredColumns = columns,
            columnCategories  = columnCategories,
            workGroups        = groups,
            workGroupMembers  = members,
            persistedGrades   = grades,
            persistedCells    = cells,
        )
        sheetCache.put(cacheKey, sheet)
        sheet
    }

    override suspend fun loadNotebookSummary(classId: Long): NotebookSummary = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectNotebookSummary(classId).executeAsOne().let {
            NotebookSummary(
                classId = it.class_id,
                studentCount = it.student_count.toInt(),
                visibleColumnCount = it.visible_column_count.toInt(),
                pendingCellCount = it.pending_cell_count.toInt(),
                averageScore = it.average_score,
            )
        }
    }

    override suspend fun listNotebookVisibleColumns(
        classId: Long,
        tabId: String?,
    ): List<NotebookVisibleColumnSummary> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectNotebookVisibleColumns(classId, tabId).executeAsList().map {
            NotebookVisibleColumnSummary(
                id = it.id,
                title = it.title,
                type = NotebookColumnType.valueOf(it.type),
                evaluationId = it.evaluation_id,
                categoryId = it.category_id,
                order = it.sort_order.toInt(),
                widthDp = it.width_dp,
                isPinned = it.is_pinned == 1L,
            )
        }
    }

    override suspend fun listNotebookRowsPage(
        classId: Long,
        limit: Long,
        offset: Long,
    ): List<NotebookRowPageItem> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectNotebookRowsPage(
            classId = classId,
            limit = limit.coerceAtLeast(0),
            offset = offset.coerceAtLeast(0),
        ).executeAsList().map {
            NotebookRowPageItem(
                studentId = it.student_id,
                firstName = it.first_name,
                lastName = it.last_name,
                isInjured = it.is_injured != 0L,
                filledCellCount = it.filled_cell_count.toInt(),
                averageScore = it.average_score,
            )
        }
    }


    /** Invalida la caché de sheet para la clase indicada. Llamar tras cualquier mutación. */
    private fun invalidateCache(classId: Long) {
        sheetCache.invalidate(classId)
    }

    override fun observeStudentChanges(classId: Long): Flow<List<Student>> {
        return db.appDatabaseQueries
            .selectStudentsByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map { row ->
                    Student(
                        id = row.id,
                        firstName = row.first_name,
                        lastName = row.last_name,
                        email = row.email,
                        photoPath = row.photo_path,
                        isInjured = row.is_injured != 0L,
                        sex = notebookStudentSexOrDefault(row.sex),
                        sexSource = notebookStudentSexSourceOrDefault(row.sex_source),
                        birthDate = notebookLocalDateOrNull(row.birth_date_iso),
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                            deviceId = row.device_id,
                            syncVersion = row.sync_version
                        )
                    )
                }
            }
    }

    override fun observeGradesForClass(classId: Long): Flow<List<Grade>> {
        return gradesRepository.observeGradesForClass(classId)
    }

    override suspend fun addStudent(classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student = withContext(Dispatchers.Default) {
        invalidateCache(classId)
        val studentId = studentsRepository.saveStudent(
            firstName = firstName,
            lastName = lastName,
            isInjured = isInjured
        )
        classesRepository.addStudentToClass(classId, studentId)
        Student(id = studentId, firstName = firstName, lastName = lastName, isInjured = isInjured)
    }

    override suspend fun removeStudent(classId: Long, studentId: Long) {
        invalidateCache(classId)
        classesRepository.removeStudentFromClass(classId, studentId)
    }

    override suspend fun listStudentsInClass(classId: Long): List<Student> {
        return classesRepository.listStudentsInClass(classId)
    }

    override suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long {
        invalidateCache(classId)
        return gradesRepository.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = evaluationId,
            value = value
        )
    }

    override suspend fun saveTab(classId: Long, tab: NotebookTab) {
        invalidateCache(classId)
        notebookConfigRepository.saveTab(classId, tab)
    }

    override suspend fun deleteTab(tabId: String) {
        // tabId no incluye classId directamente; invalida toda la caché de forma conservadora.
        sheetCache.clear()
        notebookConfigRepository.deleteTab(tabId)
    }

    override suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition) {
        invalidateCache(classId)
        notebookConfigRepository.saveColumn(classId, column)
    }

    override suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>) {
        invalidateCache(classId)
        notebookConfigRepository.saveAverageConfiguration(classId, updates)
    }

    override suspend fun previewDeleteColumn(classId: Long, columnId: String): NotebookDeletionImpact = withContext(Dispatchers.Default) {
        val columnRow = db.appDatabaseQueries.selectColumnById(columnId).executeAsOneOrNull()
        val columnIds = columnIdsLinkedTo(columnId, columnRow?.evaluation_id)
        buildDeletionImpact(
            classId = classId,
            targetId = columnId,
            targetName = columnRow?.title ?: columnId,
            targetKind = NotebookDeletionTargetKind.COLUMN,
            targetColumnIds = columnIds,
        )
    }

    override suspend fun listWorkGroups(classId: Long, tabId: String?): List<NotebookWorkGroup> {
        return notebookConfigRepository.listWorkGroups(classId, tabId)
    }

    override suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long {
        return notebookConfigRepository.saveWorkGroup(classId, workGroup)
    }

    override suspend fun deleteWorkGroup(groupId: Long) {
        notebookConfigRepository.deleteWorkGroup(groupId)
    }

    override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<NotebookWorkGroupMember> {
        return notebookConfigRepository.listWorkGroupMembers(classId, tabId)
    }

    override suspend fun assignStudentsToWorkGroup(
        classId: Long,
        tabId: String,
        groupId: Long,
        studentIds: List<Long>,
    ) {
        notebookConfigRepository.assignStudentsToWorkGroup(classId, tabId, groupId, studentIds)
    }

    override suspend fun clearStudentsFromWorkGroup(
        classId: Long,
        tabId: String,
        studentIds: List<Long>,
    ) {
        notebookConfigRepository.clearStudentsFromWorkGroup(classId, tabId, studentIds)
    }

    override suspend fun deleteColumn(columnId: String) {
        val columnRow = db.appDatabaseQueries.selectColumnById(columnId).executeAsOneOrNull()
        if (columnRow?.is_locked == 1L) {
            println("NotebookRepositorySqlDelight.deleteColumn skipped locked columnId=$columnId")
            return
        }
        val evaluationIdFromId = columnId.takeIf { it.startsWith("eval_") }
            ?.removePrefix("eval_")
            ?.toLongOrNull()
        val evaluationId = columnRow?.evaluation_id ?: evaluationIdFromId
        if (evaluationId == null && columnId.startsWith("eval_")) {
            println("NotebookRepositorySqlDelight.deleteColumn could not resolve evaluationId for columnId=$columnId")
        }

        val columnIdsToDelete = columnIdsLinkedTo(columnId, evaluationId)

        val classId = columnRow?.class_id
        // Invalidar caché antes de eliminar datos.
        classId?.let { invalidateCache(it) } ?: sheetCache.clear()
        columnIdsToDelete.forEach { id ->
            if (classId != null) {
                db.appDatabaseQueries.deleteGradesByClassAndColumnId(classId, id)
            } else {
                db.appDatabaseQueries.deleteGradesByColumnId(id)
            }
            db.appDatabaseQueries.deleteNotebookCellsByColumnId(id)
            notebookConfigRepository.deleteColumn(id)
        }

        if (evaluationId != null && evaluationId > 0L) {
            evaluationsRepository.deleteEvaluation(evaluationId)
        }

        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun listColumnCategories(classId: Long, tabId: String?): List<NotebookColumnCategory> {
        return notebookConfigRepository.listColumnCategories(classId, tabId)
    }

    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) {
        invalidateCache(classId)
        notebookConfigRepository.saveColumnCategory(classId, category)
    }

    override suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): NotebookDeletionImpact = withContext(Dispatchers.Default) {
        val category = db.appDatabaseQueries.selectColumnCategoriesByClass(classId)
            .executeAsList()
            .firstOrNull { it.id == categoryId }
        val columnIds = db.appDatabaseQueries.selectColumnsByCategory(classId, categoryId)
            .executeAsList()
            .map { it.id }
            .toSet()
        buildDeletionImpact(
            classId = classId,
            targetId = categoryId,
            targetName = category?.name ?: categoryId,
            targetKind = NotebookDeletionTargetKind.CATEGORY,
            targetColumnIds = columnIds,
        )
    }

    override suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean) {
        if (!preserveColumns) {
            db.appDatabaseQueries.selectColumnsByCategory(classId, categoryId).executeAsList()
                .filter { it.is_locked != 1L }
                .forEach { row ->
                    deleteColumn(row.id)
            }
        }
        notebookConfigRepository.deleteColumnCategory(classId, categoryId, preserveColumns = preserveColumns)
    }

    override suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean) {
        invalidateCache(classId)
        notebookConfigRepository.toggleCategoryCollapsed(classId, categoryId, isCollapsed)
    }

    override suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String) {
        invalidateCache(classId)
        notebookConfigRepository.reorderCategory(classId, tabId, categoryId, targetCategoryId)
    }

    override suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?) {
        invalidateCache(classId)
        notebookConfigRepository.assignColumnToCategory(classId, columnId, categoryId)
    }

    override suspend fun deleteEvaluation(evaluationId: Long) {
        evaluationsRepository.deleteEvaluation(evaluationId)
    }

    override suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long) {
        notebookConfigRepository.duplicateConfigToClass(sourceClassId, targetClassId)
    }

    override suspend fun getTabNamesForClass(classId: Long): List<String> = withContext(Dispatchers.Default) {
        notebookConfigRepository.listTabs(classId).map { it.title }
    }

    override suspend fun createTab(classId: Long, tabName: String): String = withContext(Dispatchers.Default) {
        val tabId = "TAB_${Clock.System.now().toEpochMilliseconds()}"
        val tab = NotebookTab(id = tabId, title = tabName)
        notebookConfigRepository.saveTab(classId, tab)
        tabId
    }

    override suspend fun addColumnToTab(
        classId: Long,
        tabName: String,
        columnName: String,
        columnType: NotebookColumnType,
        rubricId: Long?
    ): String = withContext(Dispatchers.Default) {
        val tabs = notebookConfigRepository.listTabs(classId)
        val targetTab = tabs.find { it.title == tabName } ?: throw Exception("Tab not found")
        
        val columnId = "COL_${Clock.System.now().toEpochMilliseconds()}"
        
        var evaluationId: Long? = null
        if (columnType == NotebookColumnType.RUBRIC && rubricId != null) {
            evaluationId = evaluationsRepository.saveEvaluation(
                id = null,
                classId = classId,
                code = "RBC_${Clock.System.now().toEpochMilliseconds()}",
                name = columnName,
                type = "Rúbrica",
                weight = 1.0,
                formula = null,
                rubricId = rubricId,
                description = "Generada desde el cuaderno",
                authorUserId = null,
                createdAtEpochMs = 0,
                updatedAtEpochMs = 0,
                associatedGroupId = null,
                deviceId = null,
                syncVersion = 0
            )
        }

        val column = NotebookColumnDefinition(
            id = evaluationId?.let { "eval_$it" } ?: columnId,
            title = columnName,
            type = columnType,
            evaluationId = evaluationId,
            rubricId = if (columnType == NotebookColumnType.RUBRIC) rubricId else null,
            tabIds = listOf(targetTab.id)
        )
        notebookConfigRepository.saveColumn(classId, column)
        return@withContext evaluationId?.let { "eval_$it" } ?: columnId
    }

    override suspend fun getNotebookConfig(classId: Long): NotebookConfig = withContext(Dispatchers.Default) {
        val tabs = notebookConfigRepository.listTabs(classId)
        val columns = notebookConfigRepository.listColumns(classId)
        val columnCategories = notebookConfigRepository.listColumnCategories(classId)
        val workGroups = notebookConfigRepository.listWorkGroups(classId)
        val workGroupMembers = notebookConfigRepository.listWorkGroupMembers(classId)
        NotebookConfig(classId, tabs, columns, columnCategories, workGroups, workGroupMembers)
    }

    override suspend fun getColumnIdForEvaluation(evaluationId: Long): String? = withContext(Dispatchers.Default) {
        val evaluation = evaluationsRepository.getEvaluation(evaluationId) ?: return@withContext null
        val columns = notebookConfigRepository.listColumns(evaluation.classId)
        columns.find { it.evaluationId == evaluationId }?.id
    }

    override suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        numericValue: Double,
        rubricSelections: String?,
        evidence: String?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = withContext(Dispatchers.Default) {
        // 1. Find the evaluation associated with the column
        var evalId: Long? = evaluationId?.takeIf { it > 0L }
        
        val columnRow = db.appDatabaseQueries.selectColumnById(columnId).executeAsOneOrNull()
        if (evalId == null && columnRow != null) {
            evalId = columnRow.evaluation_id
        } else if (evalId == null && columnId.startsWith("eval_")) {
            // Handle generated columns (e.g. from BuildNotebookSheetUseCase)
            evalId = columnId.removePrefix("eval_").toLongOrNull()
        }

        // 2. Delegate to gradesRepository which handles the DB upsert correctly using columnId
        gradesRepository.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = evalId,
            value = numericValue,
            rubricSelections = rubricSelections,
            evidence = evidence,
            createdAtEpochMs = createdAtEpochMs,
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId,
            syncVersion = syncVersion
        )

        // 3. Notify refresh bus
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun saveCell(
        classId: Long,
        studentId: Long,
        columnId: String,
        textValue: String?,
        boolValue: Boolean?,
        iconValue: String?,
        ordinalValue: String?,
        note: String?,
        colorHex: String?,
        attachmentUris: List<String>,
        authorUserId: Long?,
        associatedGroupId: Long?
    ) {
        invalidateCache(classId)
        notebookCellsRepository.saveCell(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            textValue = textValue,
            boolValue = boolValue,
            iconValue = iconValue,
            ordinalValue = ordinalValue,
            note = note,
            colorHex = colorHex,
            attachmentUris = attachmentUris,
            authorUserId = authorUserId,
            associatedGroupId = associatedGroupId
        )
    }

    private fun columnIdsLinkedTo(columnId: String, evaluationId: Long?): Set<String> {
        return buildSet {
            add(columnId)
            val resolvedEvaluationId = evaluationId ?: columnId.takeIf { it.startsWith("eval_") }
                ?.removePrefix("eval_")
                ?.toLongOrNull()
            if (resolvedEvaluationId != null && resolvedEvaluationId > 0L) {
                add("eval_$resolvedEvaluationId")
                db.appDatabaseQueries.selectColumnsByEvaluation(resolvedEvaluationId)
                    .executeAsList()
                    .forEach { add(it.id) }
            }
        }
    }

    private fun buildDeletionImpact(
        classId: Long,
        targetId: String,
        targetName: String,
        targetKind: NotebookDeletionTargetKind,
        targetColumnIds: Set<String>,
    ): NotebookDeletionImpact {
        val allColumns = db.appDatabaseQueries.selectColumnsByClass(classId).executeAsList()
        val affectedColumns = allColumns.filter { it.id in targetColumnIds }
        val affectedColumnIds = affectedColumns.map { it.id }.toSet()
        val affectedGradeCount = affectedColumnIds.sumOf { columnId ->
            db.appDatabaseQueries.countGradesByClassAndColumn(classId, columnId).executeAsOne().toInt()
        }
        val affectedFormulaColumnCount = allColumns
            .filter { it.id !in affectedColumnIds && it.type == NotebookColumnType.CALCULATED.name }
            .count { row ->
                val formula = row.formula.orEmpty()
                affectedColumnIds.any { id -> formula.contains("[$id]") || formula.contains(id) }
            }
        val affectedAverageColumnCount = affectedColumns.count { row ->
            row.type == NotebookColumnType.NUMERIC.name ||
                row.type == NotebookColumnType.RUBRIC.name ||
                row.type == NotebookColumnType.CALCULATED.name
        }

        return NotebookDeletionImpact(
            targetId = targetId,
            targetName = targetName,
            targetKind = targetKind,
            affectedColumnCount = affectedColumns.size,
            affectedGradeCount = affectedGradeCount,
            affectedFormulaColumnCount = affectedFormulaColumnCount,
            affectedAverageColumnCount = affectedAverageColumnCount,
            hasLockedColumns = affectedColumns.any { it.is_locked == 1L },
        )
    }

    override suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade? = withContext(Dispatchers.Default) {
        val columnRow = db.appDatabaseQueries.selectColumnById(columnId).executeAsOneOrNull()

        if (columnRow != null) {
            val evalId = columnRow.evaluation_id
            val classId = columnRow.class_id
            val grades = gradesRepository.listGradesForStudentInClass(studentId, classId)

            evalId?.let { resolvedEvalId ->
                grades.firstOrNull { it.evaluationId == resolvedEvalId }?.let { return@withContext it }
            }
            return@withContext grades.firstOrNull { it.columnId == columnId }
        }

        if (!columnId.startsWith("eval_")) {
            return@withContext null
        }

        val evaluationId = columnId.removePrefix("eval_").toLongOrNull() ?: return@withContext null
        val evaluation = evaluationsRepository.getEvaluation(evaluationId) ?: return@withContext null

        gradesRepository.listGradesForStudentInClass(studentId, evaluation.classId).find {
            it.evaluationId == evaluationId || it.columnId == columnId
        }
    }

    override fun observeCellAudit(
        classId: Long,
        studentId: Long,
        columnId: String
    ): Flow<List<NotebookCellAuditEvent>> {
        return notebookCellsRepository.observeCellAudit(classId, studentId, columnId)
    }
}
