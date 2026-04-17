package com.migestor.shared.repository

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookConfig
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookWorkGroupMember
import com.migestor.shared.domain.NotebookTab
import kotlinx.coroutines.flow.Flow

interface NotebookConfigRepository {
    fun observeTabs(classId: Long): Flow<List<NotebookTab>>
    suspend fun listTabs(classId: Long): List<NotebookTab>
    suspend fun saveTab(classId: Long, tab: NotebookTab)
    suspend fun deleteTab(tabId: String)

    fun observeColumns(classId: Long): Flow<List<NotebookColumnDefinition>>
    suspend fun listColumns(classId: Long): List<NotebookColumnDefinition>
    suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition)
    suspend fun deleteColumn(columnId: String)

    fun observeColumnCategories(classId: Long, tabId: String? = null): Flow<List<NotebookColumnCategory>>
    suspend fun listColumnCategories(classId: Long, tabId: String? = null): List<NotebookColumnCategory>
    suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory)
    suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean = true)
    suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean)
    suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String)
    suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?)

    fun observeWorkGroups(classId: Long, tabId: String? = null): Flow<List<NotebookWorkGroup>>
    suspend fun listWorkGroups(classId: Long, tabId: String? = null): List<NotebookWorkGroup>
    suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long
    suspend fun deleteWorkGroup(groupId: Long)
    fun observeWorkGroupMembers(classId: Long, tabId: String? = null): Flow<List<NotebookWorkGroupMember>>
    suspend fun listWorkGroupMembers(classId: Long, tabId: String? = null): List<NotebookWorkGroupMember>
    suspend fun assignStudentsToWorkGroup(
        classId: Long,
        tabId: String,
        groupId: Long,
        studentIds: List<Long>,
    )
    suspend fun clearStudentsFromWorkGroup(
        classId: Long,
        tabId: String,
        studentIds: List<Long>,
    )
    suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long)
    suspend fun getNotebookConfig(classId: Long): NotebookConfig
}
