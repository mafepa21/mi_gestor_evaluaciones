package com.migestor.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnCategoryKind
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookConfig
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookWorkGroupMember
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.repository.NotebookConfigRepository
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Instant
import kotlinx.datetime.Clock

class NotebookConfigRepositorySqlDelight(
    private val db: AppDatabase,
) : NotebookConfigRepository {
    private fun String?.toLongIdList(): List<Long> {
        return this
            ?.split(",")
            ?.mapNotNull { it.trim().takeIf(String::isNotEmpty)?.toLongOrNull() }
            ?: emptyList()
    }

    private fun String?.toNotebookCategoryKind(): NotebookColumnCategoryKind {
        return runCatching { NotebookColumnCategoryKind.valueOf(this ?: "") }.getOrDefault(NotebookColumnCategoryKind.CUSTOM)
    }

    private fun String?.toNotebookInstrumentKind(): NotebookInstrumentKind {
        return runCatching { NotebookInstrumentKind.valueOf(this ?: "") }.getOrDefault(NotebookInstrumentKind.CUSTOM)
    }

    private fun String?.toNotebookInputKind(): NotebookCellInputKind {
        return runCatching { NotebookCellInputKind.valueOf(this ?: "") }.getOrDefault(NotebookCellInputKind.TEXT)
    }

    private fun String?.toNotebookScaleKind(): NotebookScaleKind {
        return runCatching { NotebookScaleKind.valueOf(this ?: "") }.getOrDefault(NotebookScaleKind.CUSTOM)
    }

    private fun String?.toNotebookVisibility(): NotebookColumnVisibility {
        return runCatching { NotebookColumnVisibility.valueOf(this ?: "") }.getOrDefault(NotebookColumnVisibility.VISIBLE)
    }

    override fun observeTabs(classId: Long): Flow<List<NotebookTab>> {
        return db.appDatabaseQueries
            .selectTabsByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    NotebookTab(
                        id = it.id,
                        title = it.title,
                        order = it.sort_order.toInt(),
                        parentTabId = it.parent_tab_id,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version
                        )
                    )
                }
            }
    }

    override suspend fun listTabs(classId: Long): List<NotebookTab> {
        return db.appDatabaseQueries.selectTabsByClass(classId).executeAsList().map {
            NotebookTab(
                id = it.id,
                title = it.title,
                order = it.sort_order.toInt(),
                parentTabId = it.parent_tab_id,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version
                )
            )
        }
    }

    override suspend fun saveTab(classId: Long, tab: NotebookTab) {
        val tabs = listTabs(classId)
        val siblingTabs = tabs.filter { it.parentTabId == tab.parentTabId && it.id != tab.id }
        val resolvedOrder = if (tab.order >= 0) tab.order else (siblingTabs.maxOfOrNull { it.order }?.plus(1) ?: 0)
        db.appDatabaseQueries.upsertTab(
            id = tab.id,
            class_id = classId,
            title = tab.title,
            parent_tab_id = tab.parentTabId,
            sort_order = resolvedOrder.toLong(),
            updated_at_epoch_ms = tab.trace.updatedAt.toEpochMilliseconds(),
            device_id = tab.trace.deviceId,
            sync_version = tab.trace.syncVersion
        )
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun deleteTab(tabId: String) {
        db.appDatabaseQueries.deleteTab(tabId)
    }

    override fun observeColumns(classId: Long): Flow<List<NotebookColumnDefinition>> {
        return db.appDatabaseQueries
            .selectColumnsByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map { row ->
                    NotebookColumnDefinition(
                        id = row.id,
                        title = row.title,
                        type = NotebookColumnType.valueOf(row.type),
                        categoryKind = row.category_kind.toNotebookCategoryKind(),
                        instrumentKind = row.instrument_kind.toNotebookInstrumentKind(),
                        inputKind = row.input_kind.toNotebookInputKind(),
                        evaluationId = row.evaluation_id,
                        formula = row.formula,
                        weight = row.weight,
                        dateEpochMs = row.date_epoch_ms,
                        unitOrSituation = row.unit_name,
                        competencyCriteriaIds = row.competency_criteria_ids_csv.toLongIdList(),
                        scaleKind = row.scale_kind.toNotebookScaleKind(),
                        tabIds = row.tab_ids_csv.split(",").filter { it.isNotEmpty() },
                        sharedAcrossTabs = row.shared_across_tabs == 1L,
                        colorHex = row.color_hex,
                        iconName = row.icon_name,
                        order = row.sort_order.toInt(),
                        widthDp = row.width_dp,
                        categoryId = row.category_id,
                        visibility = row.visibility.toNotebookVisibility(),
                        isLocked = row.is_locked == 1L,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                            deviceId = row.device_id,
                            syncVersion = row.sync_version
                        )
                    )
                }
            }
    }

    override suspend fun listColumns(classId: Long): List<NotebookColumnDefinition> {
        return db.appDatabaseQueries.selectColumnsByClass(classId).executeAsList().map { row ->
            NotebookColumnDefinition(
                id = row.id,
                title = row.title,
                type = NotebookColumnType.valueOf(row.type),
                categoryKind = row.category_kind.toNotebookCategoryKind(),
                instrumentKind = row.instrument_kind.toNotebookInstrumentKind(),
                inputKind = row.input_kind.toNotebookInputKind(),
                evaluationId = row.evaluation_id,
                formula = row.formula,
                weight = row.weight,
                dateEpochMs = row.date_epoch_ms,
                unitOrSituation = row.unit_name,
                competencyCriteriaIds = row.competency_criteria_ids_csv.toLongIdList(),
                scaleKind = row.scale_kind.toNotebookScaleKind(),
                tabIds = row.tab_ids_csv.split(",").filter { it.isNotEmpty() },
                sharedAcrossTabs = row.shared_across_tabs == 1L,
                colorHex = row.color_hex,
                iconName = row.icon_name,
                order = row.sort_order.toInt(),
                widthDp = row.width_dp,
                categoryId = row.category_id,
                visibility = row.visibility.toNotebookVisibility(),
                isLocked = row.is_locked == 1L,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version
                )
            )
        }
    }

    override suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition) {
        // Migración: Eliminar cualquier columna previa para esta evaluación que tenga un ID distinto al estandarizado
        column.evaluationId?.let { evalId ->
            if (evalId > 0) {
                val existing = db.appDatabaseQueries
                    .selectColumnsByClass(classId)
                    .executeAsList()
                    .filter { it.evaluation_id == evalId }
                existing.forEach { ext ->
                    if (ext.id != column.id) {
                        db.appDatabaseQueries.deleteColumn(ext.id)
                    }
                }
            }
        }

        val resolvedOrder = if (column.order >= 0) {
            column.order
        } else {
            db.appDatabaseQueries.selectColumnsByClass(classId).executeAsList()
                .map { it.sort_order.toInt() }
                .maxOrNull()
                ?.plus(1) ?: 0
        }

        db.appDatabaseQueries.upsertColumn(
            id = column.id,
            class_id = classId,
            title = column.title,
            type = column.type.name,
            category_kind = column.categoryKind.name,
            instrument_kind = column.instrumentKind.name,
            input_kind = column.inputKind.name,
            evaluation_id = column.evaluationId,
            formula = column.formula,
            weight = column.weight,
            date_epoch_ms = column.dateEpochMs,
            unit_name = column.unitOrSituation,
            competency_criteria_ids_csv = column.competencyCriteriaIds.joinToString(","),
            scale_kind = column.scaleKind.name,
            tab_ids_csv = column.tabIds.joinToString(","),
            shared_across_tabs = if (column.sharedAcrossTabs) 1L else 0L,
            color_hex = column.colorHex ?: "#FFFFFF",
            icon_name = column.iconName,
            sort_order = resolvedOrder.toLong(),
            width_dp = if (column.widthDp > 0.0) column.widthDp else 132.0,
            category_id = column.categoryId,
            visibility = column.visibility.name,
            is_locked = if (column.isLocked) 1L else 0L,
            updated_at_epoch_ms = column.trace.updatedAt.toEpochMilliseconds(),
            device_id = column.trace.deviceId,
            sync_version = column.trace.syncVersion
        )
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun deleteColumn(columnId: String) {
        db.appDatabaseQueries.deleteColumn(columnId)
    }

    override fun observeColumnCategories(classId: Long, tabId: String?): Flow<List<NotebookColumnCategory>> {
        val query = if (tabId == null) {
            db.appDatabaseQueries.selectColumnCategoriesByClass(classId)
        } else {
            db.appDatabaseQueries.selectColumnCategoriesByClassAndTab(classId, tabId)
        }
        return query.asFlow().mapToList(Dispatchers.Default).map { rows ->
            rows.map { row ->
                NotebookColumnCategory(
                    id = row.id,
                    classId = row.class_id,
                    tabId = row.tab_id,
                    name = row.name,
                    order = row.sort_order.toInt(),
                    isCollapsed = row.is_collapsed == 1L,
                    trace = AuditTrace(
                        updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                        deviceId = row.device_id,
                        syncVersion = row.sync_version
                    )
                )
            }
        }
    }

    override suspend fun listColumnCategories(classId: Long, tabId: String?): List<NotebookColumnCategory> {
        val rows = if (tabId == null) {
            db.appDatabaseQueries.selectColumnCategoriesByClass(classId).executeAsList()
        } else {
            db.appDatabaseQueries.selectColumnCategoriesByClassAndTab(classId, tabId).executeAsList()
        }
        return rows.map { row ->
            NotebookColumnCategory(
                id = row.id,
                classId = row.class_id,
                tabId = row.tab_id,
                name = row.name,
                order = row.sort_order.toInt(),
                isCollapsed = row.is_collapsed == 1L,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version
                )
            )
        }
    }

    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) {
        val categories = listColumnCategories(classId, category.tabId)
        val siblingCategories = categories.filter { it.id != category.id }
        val resolvedOrder = if (category.order >= 0) category.order else (siblingCategories.maxOfOrNull { it.order }?.plus(1) ?: 0)
        db.appDatabaseQueries.upsertColumnCategory(
            id = category.id,
            class_id = classId,
            tab_id = category.tabId,
            name = category.name,
            sort_order = resolvedOrder.toLong(),
            is_collapsed = if (category.isCollapsed) 1L else 0L,
            updated_at_epoch_ms = category.trace.updatedAt.toEpochMilliseconds(),
            device_id = category.trace.deviceId,
            sync_version = category.trace.syncVersion
        )
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun deleteColumnCategory(classId: Long, categoryId: String) {
        db.transaction {
            db.appDatabaseQueries.selectColumnsByClass(classId).executeAsList()
                .filter { it.category_id == categoryId }
                .forEach { row ->
                    db.appDatabaseQueries.upsertColumn(
                        id = row.id,
                        class_id = row.class_id,
                        title = row.title,
                        type = row.type,
                        category_kind = row.category_kind,
                        instrument_kind = row.instrument_kind,
                        input_kind = row.input_kind,
                        evaluation_id = row.evaluation_id,
                        formula = row.formula,
                        weight = row.weight,
                        date_epoch_ms = row.date_epoch_ms,
                        unit_name = row.unit_name,
                        competency_criteria_ids_csv = row.competency_criteria_ids_csv,
                        scale_kind = row.scale_kind,
                        tab_ids_csv = row.tab_ids_csv,
                        shared_across_tabs = row.shared_across_tabs,
                        color_hex = row.color_hex,
                        icon_name = row.icon_name,
                        sort_order = row.sort_order,
                        width_dp = row.width_dp,
                        category_id = null,
                        visibility = row.visibility,
                        is_locked = row.is_locked,
                        updated_at_epoch_ms = row.updated_at_epoch_ms,
                        device_id = row.device_id,
                        sync_version = row.sync_version
                    )
                }
            db.appDatabaseQueries.deleteColumnCategory(classId, categoryId)
        }
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean) {
        val current = db.appDatabaseQueries.selectColumnCategoriesByClass(classId).executeAsList()
            .firstOrNull { it.id == categoryId } ?: return
        db.appDatabaseQueries.upsertColumnCategory(
            id = current.id,
            class_id = current.class_id,
            tab_id = current.tab_id,
            name = current.name,
            sort_order = current.sort_order,
            is_collapsed = if (isCollapsed) 1L else 0L,
            updated_at_epoch_ms = Clock.System.now().toEpochMilliseconds(),
            device_id = current.device_id,
            sync_version = current.sync_version
        )
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String) {
        val categories = listColumnCategories(classId, tabId)
            .sortedWith(compareBy<NotebookColumnCategory> { it.order }.thenBy { it.id })
            .toMutableList()

        val fromIndex = categories.indexOfFirst { it.id == categoryId }
        val targetIndex = categories.indexOfFirst { it.id == targetCategoryId }
        if (fromIndex < 0 || targetIndex < 0 || fromIndex == targetIndex) return

        val moved = categories.removeAt(fromIndex)
        val adjustedTarget = if (fromIndex < targetIndex) targetIndex - 1 else targetIndex
        categories.add(adjustedTarget.coerceIn(0, categories.size), moved)

        categories.mapIndexed { index, category ->
            category.copy(order = index)
        }.forEach { updated ->
            saveColumnCategory(classId, updated)
        }
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?) {
        val row = db.appDatabaseQueries.selectColumnById(columnId).executeAsOneOrNull() ?: return
        db.appDatabaseQueries.upsertColumn(
            id = row.id,
            class_id = row.class_id,
            title = row.title,
            type = row.type,
            category_kind = row.category_kind,
            instrument_kind = row.instrument_kind,
            input_kind = row.input_kind,
            evaluation_id = row.evaluation_id,
            formula = row.formula,
            weight = row.weight,
            date_epoch_ms = row.date_epoch_ms,
            unit_name = row.unit_name,
            competency_criteria_ids_csv = row.competency_criteria_ids_csv,
            scale_kind = row.scale_kind,
            tab_ids_csv = row.tab_ids_csv,
            shared_across_tabs = row.shared_across_tabs,
            color_hex = row.color_hex,
            icon_name = row.icon_name,
            sort_order = row.sort_order,
            width_dp = row.width_dp,
            category_id = categoryId,
            visibility = row.visibility,
            is_locked = row.is_locked,
            updated_at_epoch_ms = Clock.System.now().toEpochMilliseconds(),
            device_id = row.device_id,
            sync_version = row.sync_version
        )
        NotebookRefreshBus.emitRefresh()
    }

    override fun observeWorkGroups(classId: Long, tabId: String?): Flow<List<NotebookWorkGroup>> {
        val query = if (tabId == null) {
            db.appDatabaseQueries.selectWorkGroupsByClass(classId)
        } else {
            db.appDatabaseQueries.selectWorkGroupsByClassAndTab(classId, tabId)
        }
        return query.asFlow().mapToList(Dispatchers.Default).map { rows ->
            rows.map { row ->
                NotebookWorkGroup(
                    id = row.id,
                    classId = row.class_id,
                    tabId = row.tab_id,
                    name = row.name,
                    order = row.sort_order.toInt(),
                    trace = AuditTrace(
                        updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                        deviceId = row.device_id,
                        syncVersion = row.sync_version,
                    )
                )
            }
        }
    }

    override suspend fun listWorkGroups(classId: Long, tabId: String?): List<NotebookWorkGroup> {
        val rows = if (tabId == null) {
            db.appDatabaseQueries.selectWorkGroupsByClass(classId).executeAsList()
        } else {
            db.appDatabaseQueries.selectWorkGroupsByClassAndTab(classId, tabId).executeAsList()
        }
        return rows.map { row ->
            NotebookWorkGroup(
                id = row.id,
                classId = row.class_id,
                tabId = row.tab_id,
                name = row.name,
                order = row.sort_order.toInt(),
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version,
                )
            )
        }
    }

    override suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long {
        val now = workGroup.trace.updatedAt.toEpochMilliseconds().takeIf { it > 0 } ?: Clock.System.now().toEpochMilliseconds()
        val uniqueName = resolveUniqueWorkGroupName(
            classId = classId,
            tabId = workGroup.tabId,
            groupId = workGroup.id.takeIf { it > 0L },
            desiredName = workGroup.name,
        )
        val savedId = db.transactionWithResult {
            if (workGroup.id > 0) {
                db.appDatabaseQueries.updateWorkGroup(
                    class_id = classId,
                    tab_id = workGroup.tabId,
                    name = uniqueName,
                    sort_order = workGroup.order.toLong(),
                    updated_at_epoch_ms = now,
                    device_id = workGroup.trace.deviceId,
                    sync_version = workGroup.trace.syncVersion,
                    id = workGroup.id,
                )
                workGroup.id
            } else {
                db.appDatabaseQueries.insertWorkGroup(
                    class_id = classId,
                    tab_id = workGroup.tabId,
                    name = uniqueName,
                    sort_order = workGroup.order.toLong(),
                    updated_at_epoch_ms = now,
                    device_id = workGroup.trace.deviceId,
                    sync_version = workGroup.trace.syncVersion,
                )
                db.appDatabaseQueries.lastInsertedId().executeAsOne()
            }
        }
        NotebookRefreshBus.emitRefresh()
        return savedId
    }

    private suspend fun resolveUniqueWorkGroupName(
        classId: Long,
        tabId: String,
        groupId: Long?,
        desiredName: String,
    ): String {
        val normalized = desiredName.trim()
        val existingNames = listWorkGroups(classId, tabId)
            .asSequence()
            .filter { it.id != groupId }
            .map { it.name.trim().lowercase() }
            .toSet()

        var candidate = normalized
        var suffix = 2
        while (candidate.lowercase() in existingNames) {
            candidate = "$normalized ($suffix)"
            suffix++
        }
        return candidate
    }

    override suspend fun deleteWorkGroup(groupId: Long) {
        db.appDatabaseQueries.deleteWorkGroup(groupId)
        NotebookRefreshBus.emitRefresh()
    }

    override fun observeWorkGroupMembers(classId: Long, tabId: String?): Flow<List<NotebookWorkGroupMember>> {
        val query = if (tabId == null) {
            db.appDatabaseQueries.selectWorkGroupMembersByClass(classId)
        } else {
            db.appDatabaseQueries.selectWorkGroupMembersByClassAndTab(classId, tabId)
        }
        return query.asFlow().mapToList(Dispatchers.Default).map { rows ->
            rows.map { row ->
                NotebookWorkGroupMember(
                    classId = row.class_id,
                    tabId = row.tab_id,
                    groupId = row.group_id,
                    studentId = row.student_id,
                    trace = AuditTrace(
                        updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                        deviceId = row.device_id,
                        syncVersion = row.sync_version,
                    )
                )
            }
        }
    }

    override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<NotebookWorkGroupMember> {
        val rows = if (tabId == null) {
            db.appDatabaseQueries.selectWorkGroupMembersByClass(classId).executeAsList()
        } else {
            db.appDatabaseQueries.selectWorkGroupMembersByClassAndTab(classId, tabId).executeAsList()
        }
        return rows.map { row ->
            NotebookWorkGroupMember(
                classId = row.class_id,
                tabId = row.tab_id,
                groupId = row.group_id,
                studentId = row.student_id,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version,
                )
            )
        }
    }

    override suspend fun assignStudentsToWorkGroup(
        classId: Long,
        tabId: String,
        groupId: Long,
        studentIds: List<Long>,
    ) {
        val now = Clock.System.now().toEpochMilliseconds()
        studentIds.forEach { studentId ->
            db.appDatabaseQueries.deleteWorkGroupMember(classId, tabId, studentId)
            db.appDatabaseQueries.upsertWorkGroupMember(
                class_id = classId,
                tab_id = tabId,
                group_id = groupId,
                student_id = studentId,
                updated_at_epoch_ms = now,
                device_id = null,
                sync_version = 0
            )
        }
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun clearStudentsFromWorkGroup(
        classId: Long,
        tabId: String,
        studentIds: List<Long>,
    ) {
        studentIds.forEach { studentId ->
            db.appDatabaseQueries.deleteWorkGroupMember(classId, tabId, studentId)
        }
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long) {
        val tabs = listTabs(sourceClassId)
        val columns = listColumns(sourceClassId)
        val columnCategories = listColumnCategories(sourceClassId)
        val groups = listWorkGroups(sourceClassId)
        val members = listWorkGroupMembers(sourceClassId)
        val evaluations = db.appDatabaseQueries.selectEvaluationsByClass(sourceClassId).executeAsList().map {
            Evaluation(
                id = it.id,
                classId = it.class_id,
                code = it.code,
                name = it.name,
                type = it.type,
                weight = it.weight,
                formula = it.formula,
                rubricId = it.rubric_id,
                description = it.description,
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    associatedGroupId = it.associated_group_id,
                    deviceId = it.device_id,
                    syncVersion = it.sync_version
                )
            )
        }
        val evaluationsById = evaluations.associateBy { it.id }

        // Map source tab IDs to new IDs to maintain associations in columns
        val tabIdMap = mutableMapOf<String, String>()
        val categoryIdMap = mutableMapOf<String, String>()
        val groupIdMap = mutableMapOf<Long, Long>()
        val evaluationIdMap = mutableMapOf<Long, Long>()

        val orderedTabs = tabs.sortedWith(
            compareBy<NotebookTab> { it.parentTabId != null }
                .thenBy { it.parentTabId ?: "" }
                .thenBy { it.order }
                .thenBy { it.id }
        )
        orderedTabs.forEachIndexed { index, tab ->
            val newId = "${tab.title.lowercase().replace(" ", "_")}_${Clock.System.now().toEpochMilliseconds()}_$index"
            tabIdMap[tab.id] = newId
        }

        orderedTabs.forEach { tab ->
            val newId = tabIdMap[tab.id] ?: return@forEach
            saveTab(
                targetClassId,
                tab.copy(
                    id = newId,
                    parentTabId = tab.parentTabId?.let { tabIdMap[it] },
                )
            )
        }

        val orderedCategories = columnCategories.sortedWith(
            compareBy<NotebookColumnCategory> { it.tabId }
                .thenBy { it.order }
                .thenBy { it.id }
        )
        orderedCategories.forEachIndexed { index, category ->
            val newCategoryId = "cat_${Clock.System.now().toEpochMilliseconds()}_$index"
            categoryIdMap[category.id] = newCategoryId
            val mappedTabId = tabIdMap[category.tabId] ?: return@forEachIndexed
            saveColumnCategory(
                targetClassId,
                category.copy(
                    id = newCategoryId,
                    classId = targetClassId,
                    tabId = mappedTabId
                )
            )
        }

        evaluations.forEach { evaluation ->
            val newEvaluationId = db.appDatabaseQueries.upsertEvaluation(
                null,
                targetClassId,
                evaluation.code,
                evaluation.name,
                evaluation.type,
                evaluation.weight,
                evaluation.formula,
                evaluation.rubricId,
                evaluation.description,
                evaluation.trace.authorUserId,
                evaluation.trace.createdAt.toEpochMilliseconds(),
                evaluation.trace.updatedAt.toEpochMilliseconds(),
                evaluation.trace.associatedGroupId,
                evaluation.trace.deviceId,
                evaluation.trace.syncVersion,
            ).let { _ -> db.appDatabaseQueries.lastInsertedId().executeAsOne() }
            evaluationIdMap[evaluation.id] = newEvaluationId

            db.appDatabaseQueries.selectEvaluationCompetencyLinks(evaluation.id).executeAsList().forEach { link ->
                db.appDatabaseQueries.upsertEvaluationCompetencyLink(
                    null,
                    newEvaluationId,
                    link.competency_id,
                    link.weight,
                    link.author_user_id,
                    link.created_at_epoch_ms,
                    link.updated_at_epoch_ms,
                    link.associated_group_id,
                    link.device_id,
                    link.sync_version,
                )
            }
        }

        groups.forEach { group ->
            val newTabId = tabIdMap[group.tabId] ?: return@forEach
            val newGroup = group.copy(
                id = 0,
                classId = targetClassId,
                tabId = newTabId,
            )
            val savedId = saveWorkGroup(targetClassId, newGroup)
            groupIdMap[group.id] = savedId
        }

        columns.forEachIndexed { index, col ->
            val newId = "${col.title.lowercase().replace(" ", "_")}_${Clock.System.now().toEpochMilliseconds()}_$index"
            val newTabIds = col.tabIds.mapNotNull { tabIdMap[it] }
            val sourceEvaluation = col.evaluationId?.let { evaluationsById[it] }
            val newEvaluationId = col.evaluationId?.let { evaluationIdMap[it] }
            saveColumn(targetClassId, col.copy(
                id = newId,
                tabIds = newTabIds,
                evaluationId = newEvaluationId,
                rubricId = sourceEvaluation?.rubricId ?: col.rubricId,
                categoryId = col.categoryId?.let { categoryIdMap[it] },
                type = if (newEvaluationId != null && sourceEvaluation?.rubricId != null) {
                    NotebookColumnType.RUBRIC
                } else {
                    col.type
                },
                order = col.order,
                widthDp = col.widthDp,
            ))
        }

        members.forEach { member ->
            val newTabId = tabIdMap[member.tabId] ?: return@forEach
            val newGroupId = groupIdMap[member.groupId] ?: return@forEach
            assignStudentsToWorkGroup(
                classId = targetClassId,
                tabId = newTabId,
                groupId = newGroupId,
                studentIds = listOf(member.studentId)
            )
        }
    }

    override suspend fun getNotebookConfig(classId: Long): NotebookConfig {
        return NotebookConfig(
            classId = classId,
            tabs = listTabs(classId),
            columns = listColumns(classId),
            columnCategories = listColumnCategories(classId),
            workGroups = listWorkGroups(classId),
            workGroupMembers = listWorkGroupMembers(classId),
        )
    }
}
