package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookWorkGroupMember
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NotebookWorkGroupPolicyTest {
    private val tabs = listOf(
        NotebookTab(id = "ROOT", title = "1ª Evaluación", order = 0),
        NotebookTab(id = "CHILD", title = "Unidad 1", order = 0, parentTabId = "ROOT"),
        NotebookTab(id = "ROOT2", title = "2ª Evaluación", order = 1),
    )

    @Test
    fun `canonical tab uses the root of a child selection`() {
        val canonical = NotebookWorkGroupPolicy.canonicalTabId(
            tabs = tabs,
            requestedTabId = "CHILD",
            selectedTabId = "CHILD",
        )
        assertEquals("ROOT", canonical)
    }

    @Test
    fun `tab family includes root and children`() {
        val family = NotebookWorkGroupPolicy.tabFamilyIds(tabs, "CHILD")
        assertEquals(setOf("ROOT", "CHILD"), family)
    }

    @Test
    fun `situation mode ignores tab and keeps filled SA groups`() {
        val groups = listOf(
            group(1, "ROOT", "Vacío general", situationId = null),
            group(2, "ROOT2", "Equipo SA", situationId = 99L),
        )
        val members = listOf(member(2, 10L, "ROOT2"))
        val active = NotebookWorkGroupPolicy.activeGroups(
            groups = groups,
            members = members,
            tabs = tabs,
            activeTabId = "CHILD",
            mode = "situation_99",
        )
        assertEquals(listOf(2L), active.map { it.id })
    }

    @Test
    fun `general mode does not hide filled SA groups behind empty general groups`() {
        val groups = listOf(
            group(1, "ROOT", "Hueco", situationId = null),
            group(2, "ROOT", "Equipo SA", situationId = 7L),
        )
        val members = listOf(member(2, 10L, "ROOT"))
        val active = NotebookWorkGroupPolicy.activeGroups(
            groups = groups,
            members = members,
            tabs = tabs,
            activeTabId = "CHILD",
            mode = NotebookWorkGroupPolicy.MODE_GENERAL,
        )
        assertEquals(listOf(2L), active.map { it.id })
    }

    @Test
    fun `member lookup uses group id even if the member tab differs`() {
        val group = group(5, "ROOT", "Equipo", situationId = 1L)
        val members = listOf(member(5, 42L, "CHILD"))
        val ids = NotebookWorkGroupPolicy.memberIds(group, members)
        assertTrue(ids.contains(42L))
    }

    private fun group(
        id: Long,
        tabId: String,
        name: String,
        situationId: Long?,
    ) = NotebookWorkGroup(
        id = id,
        classId = 1L,
        tabId = tabId,
        name = name,
        order = id.toInt(),
        learningSituationId = situationId,
    )

    private fun member(groupId: Long, studentId: Long, tabId: String) = NotebookWorkGroupMember(
        classId = 1L,
        tabId = tabId,
        groupId = groupId,
        studentId = studentId,
    )
}
