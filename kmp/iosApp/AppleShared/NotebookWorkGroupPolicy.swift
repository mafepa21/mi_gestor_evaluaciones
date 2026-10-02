import Foundation
import MiGestorKit

enum NotebookWorkGroupPolicy {
    static let modeNone = "none"
    static let modeGeneral = "general"
    static let situationPrefix = "situation_"

    static func canonicalTabId(
        tabs: [NotebookTab],
        requestedTabId: String?,
        selectedTabId: String?
    ) -> String? {
        let requested = requestedTabId.flatMap { candidate in
            tabs.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        let selected = selectedTabId.flatMap { candidate in
            tabs.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        if let seed = requested ?? selected, let seedTab = tabs.first(where: { $0.id == seed }) {
            return seedTab.parentTabId ?? seedTab.id
        }
        let roots = tabs.filter { $0.parentTabId == nil }.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
        return roots.first?.id ?? tabs.first?.id
    }

    static func tabFamilyIds(tabs: [NotebookTab], activeTabId: String?) -> Set<String> {
        guard !tabs.isEmpty else { return [] }
        guard let canonical = canonicalTabId(tabs: tabs, requestedTabId: activeTabId, selectedTabId: activeTabId) else {
            return Set(tabs.map(\.id))
        }
        var family: Set<String> = [canonical]
        tabs.filter { $0.parentTabId == canonical }.forEach { family.insert($0.id) }
        if let selected = tabs.first(where: { $0.id == activeTabId }), let parent = selected.parentTabId {
            family.insert(parent)
            tabs.filter { $0.parentTabId == parent }.forEach { family.insert($0.id) }
        }
        return family
    }

    static func groupsForManagement(
        groups: [NotebookWorkGroup],
        tabs: [NotebookTab],
        selectedTabId: String?
    ) -> [NotebookWorkGroup] {
        let family = tabFamilyIds(tabs: tabs, activeTabId: selectedTabId)
        let inFamily = groups.filter { family.isEmpty || family.contains($0.tabId) }
        let saGroups = groups.filter { $0.learningSituationId != nil }
        var seen = Set<Int64>()
        return (inFamily + saGroups).filter { group in
            seen.insert(group.id).inserted
        }.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    static func activeGroups(
        groups: [NotebookWorkGroup],
        members: [NotebookWorkGroupMember],
        tabs: [NotebookTab],
        activeTabId: String?,
        mode: String
    ) -> [NotebookWorkGroup] {
        guard mode != modeNone else { return [] }
        let family = tabFamilyIds(tabs: tabs, activeTabId: activeTabId)
        let inFamily = groups.filter { family.isEmpty || family.contains($0.tabId) }
        let hasMembers: (NotebookWorkGroup) -> Bool = { group in
            members.contains { $0.groupId == group.id }
        }

        let selected: [NotebookWorkGroup]
        if mode.hasPrefix(situationPrefix),
           let sitId = Int64(mode.dropFirst(situationPrefix.count)) {
            let sitGroups = groups.filter { $0.learningSituationId?.int64Value == sitId }
            selected = sitGroups.isEmpty ? inFamily : sitGroups
        } else {
            let candidates = inFamily.isEmpty ? groups : inFamily
            let filled = candidates.filter(hasMembers)
            selected = filled.isEmpty ? candidates : filled
        }

        return selected.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    static func memberIds(
        group: NotebookWorkGroup,
        members: [NotebookWorkGroupMember]
    ) -> Set<Int64> {
        Set(members.filter { $0.groupId == group.id }.map(\.studentId))
    }

    static func groupIdForStudent(
        studentId: Int64,
        members: [NotebookWorkGroupMember],
        activeGroups: [NotebookWorkGroup]
    ) -> Int64? {
        let activeIds = Set(activeGroups.map(\.id))
        return members.first(where: { member in
            member.studentId == studentId && (activeIds.isEmpty || activeIds.contains(member.groupId))
        })?.groupId ?? members.first(where: { $0.studentId == studentId })?.groupId
    }
}
