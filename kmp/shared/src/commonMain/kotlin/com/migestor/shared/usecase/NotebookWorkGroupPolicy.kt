package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookWorkGroupMember

/**
 * Regla única de visibilidad de grupos de trabajo.
 *
 * Los grupos con SA se ven en toda la clase. Los grupos generales se ven
 * en la pestaña de evaluación actual y en sus hijas.
 */
object NotebookWorkGroupPolicy {
    const val MODE_NONE = "none"
    const val MODE_GENERAL = "general"
    const val MODE_SITUATION_PREFIX = "situation_"

    fun canonicalTabId(
        tabs: List<NotebookTab>,
        requestedTabId: String?,
        selectedTabId: String?,
    ): String? {
        val requested = requestedTabId?.takeIf { candidate -> tabs.any { it.id == candidate } }
        val selected = selectedTabId?.takeIf { candidate -> tabs.any { it.id == candidate } }
        val seed = requested ?: selected
        if (seed != null) {
            val seedTab = tabs.first { it.id == seed }
            return seedTab.parentTabId ?: seedTab.id
        }
        val roots = tabs.filter { it.parentTabId == null }.sortedWith(compareBy<NotebookTab> { it.order }.thenBy { it.id })
        return roots.firstOrNull()?.id ?: tabs.firstOrNull()?.id
    }

    fun tabFamilyIds(tabs: List<NotebookTab>, activeTabId: String?): Set<String> {
        if (tabs.isEmpty()) return emptySet()
        val canonical = canonicalTabId(tabs, activeTabId, activeTabId) ?: return tabs.map { it.id }.toSet()
        return buildSet {
            add(canonical)
            tabs.filter { it.parentTabId == canonical }.forEach { add(it.id) }
            tabs.firstOrNull { it.id == activeTabId }?.parentTabId?.let { parent ->
                add(parent)
                tabs.filter { it.parentTabId == parent }.forEach { add(it.id) }
            }
        }
    }

    fun groupsForManagement(
        groups: List<NotebookWorkGroup>,
        tabs: List<NotebookTab>,
        selectedTabId: String?,
    ): List<NotebookWorkGroup> {
        val family = tabFamilyIds(tabs, selectedTabId)
        val inFamily = groups.filter { family.isEmpty() || it.tabId in family }
        val saGroups = groups.filter { it.learningSituationId != null }
        return (inFamily + saGroups)
            .distinctBy { it.id }
            .sortedWith(compareBy<NotebookWorkGroup> { it.order }.thenBy { it.id })
    }

    fun activeGroups(
        groups: List<NotebookWorkGroup>,
        members: List<NotebookWorkGroupMember>,
        tabs: List<NotebookTab>,
        activeTabId: String?,
        mode: String,
    ): List<NotebookWorkGroup> {
        if (mode == MODE_NONE) return emptyList()
        val family = tabFamilyIds(tabs, activeTabId)
        val inFamily = groups.filter { family.isEmpty() || it.tabId in family }
        val hasMembers: (NotebookWorkGroup) -> Boolean = { group ->
            members.any { it.groupId == group.id }
        }

        val selected = if (mode.startsWith(MODE_SITUATION_PREFIX)) {
            val sitId = mode.removePrefix(MODE_SITUATION_PREFIX).toLongOrNull()
            val sitGroups = groups.filter { it.learningSituationId == sitId }
            sitGroups.ifEmpty { inFamily }
        } else {
            val candidates = inFamily.ifEmpty { groups }
            val filled = candidates.filter(hasMembers)
            filled.ifEmpty { candidates }
        }

        return selected.sortedWith(compareBy<NotebookWorkGroup> { it.order }.thenBy { it.id })
    }

    fun memberIds(
        group: NotebookWorkGroup,
        members: List<NotebookWorkGroupMember>,
    ): Set<Long> {
        return members.filter { it.groupId == group.id }.map { it.studentId }.toSet()
    }

    fun groupIdForStudent(
        studentId: Long,
        members: List<NotebookWorkGroupMember>,
        activeGroups: List<NotebookWorkGroup>,
    ): Long? {
        val activeIds = activeGroups.map { it.id }.toSet()
        return members.firstOrNull { member ->
            member.studentId == studentId && (activeIds.isEmpty() || member.groupId in activeIds)
        }?.groupId ?: members.firstOrNull { it.studentId == studentId }?.groupId
    }
}
