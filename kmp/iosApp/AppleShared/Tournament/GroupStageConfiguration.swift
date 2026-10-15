import Foundation

struct GroupStageOption: Identifiable, Hashable {
    let groupCount: Int
    let groupSizes: [Int]

    var id: String {
        "\(groupCount)-\(groupSizes.map(String.init).joined(separator: "-"))"
    }

    var minimumGroupSize: Int {
        groupSizes.min() ?? 0
    }

    var title: String {
        let sizeRange = Set(groupSizes)
        if sizeRange.count == 1, let size = groupSizes.first {
            return "\(groupCount) \(groupCount == 1 ? "grupo" : "grupos") de \(size)"
        }

        let minimum = groupSizes.min() ?? 0
        let maximum = groupSizes.max() ?? 0
        return "\(groupCount) grupos de \(minimum)–\(maximum) equipos"
    }

    var detail: String {
        "Distribución: \(groupSizes.map(String.init).joined(separator: " + "))"
    }

    func totalQualified(teamsPerGroup: Int) -> Int {
        groupCount * teamsPerGroup
    }
}

enum GroupStageConfiguration {
    static let defaultGroupSize = 4
    static let maximumGroupCount = 16

    static func options(for teamCount: Int) -> [GroupStageOption] {
        guard teamCount >= 2 else { return [] }

        let maximumGroupCount = min(
            max(teamCount / 2, 1),
            Self.maximumGroupCount
        )

        return (1...maximumGroupCount)
            .map { makeOption(teamCount: teamCount, groupCount: $0) }
            .sorted { lhs, rhs in
                let preferredGroupCount = preferredGroupCount(for: teamCount)
                let lhsIsPreferred = lhs.groupCount == preferredGroupCount
                let rhsIsPreferred = rhs.groupCount == preferredGroupCount

                if lhsIsPreferred != rhsIsPreferred {
                    return lhsIsPreferred
                }

                let lhsDistance = distanceFromDefault(lhs, teamCount: teamCount)
                let rhsDistance = distanceFromDefault(rhs, teamCount: teamCount)

                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }

                return lhs.groupCount < rhs.groupCount
            }
    }

    static func defaultGroupCount(for teamCount: Int) -> Int {
        guard teamCount >= 2 else { return 0 }
        return preferredGroupCount(for: teamCount)
    }

    static func option(
        for groupCount: Int,
        teamCount: Int
    ) -> GroupStageOption? {
        options(for: teamCount).first { $0.groupCount == groupCount }
    }

    static func groups(
        teamNames: [String],
        groupCount: Int
    ) -> [[String]] {
        guard let option = option(for: groupCount, teamCount: teamNames.count) else {
            return []
        }

        var groups: [[String]] = []
        var nextTeamIndex = 0

        for size in option.groupSizes {
            let endIndex = min(nextTeamIndex + size, teamNames.count)
            groups.append(Array(teamNames[nextTeamIndex..<endIndex]))
            nextTeamIndex = endIndex
        }

        return groups
    }

    static func groupName(index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard alphabet.indices.contains(index) else {
            return "Grupo \(index + 1)"
        }
        return "Grupo \(alphabet[index])"
    }

    static func qualifiedParticipantNames(
        groupCount: Int,
        teamsPerGroup: Int
    ) -> [String] {
        if groupCount == 2 {
            var crossGroupParticipants: [String] = []
            for position in stride(from: 1, through: teamsPerGroup, by: 2) {
                crossGroupParticipants.append(
                    qualifiedParticipantName(position: position, groupIndex: 0)
                )

                if position + 1 <= teamsPerGroup {
                    crossGroupParticipants.append(
                        qualifiedParticipantName(position: position + 1, groupIndex: 1)
                    )
                    crossGroupParticipants.append(
                        qualifiedParticipantName(position: position, groupIndex: 1)
                    )
                    crossGroupParticipants.append(
                        qualifiedParticipantName(position: position + 1, groupIndex: 0)
                    )
                } else {
                    crossGroupParticipants.append(
                        qualifiedParticipantName(position: position, groupIndex: 1)
                    )
                }
            }
            return crossGroupParticipants
        }

        return (1...teamsPerGroup).flatMap { position in
            (0..<groupCount).map { groupIndex in
                qualifiedParticipantName(position: position, groupIndex: groupIndex)
            }
        }
    }

    static func minimumQualifiedTeamsPerGroup(
        groupCount: Int,
        teamCount: Int
    ) -> Int {
        groupCount == 1 && teamCount >= 2 ? 2 : 1
    }

    static func maximumQualifiedTeamsPerGroup(
        groupCount: Int,
        teamCount: Int
    ) -> Int {
        option(for: groupCount, teamCount: teamCount)?.minimumGroupSize ?? 1
    }

    static func qualifiedTeamCount(
        groupCount: Int,
        teamsPerGroup: Int
    ) -> Int {
        groupCount * teamsPerGroup
    }

    private static func makeOption(
        teamCount: Int,
        groupCount: Int
    ) -> GroupStageOption {
        let baseSize = teamCount / groupCount
        let remainder = teamCount % groupCount
        let groupSizes = (0..<groupCount).map { index in
            baseSize + (index < remainder ? 1 : 0)
        }

        return GroupStageOption(
            groupCount: groupCount,
            groupSizes: groupSizes
        )
    }

    private static func distanceFromDefault(
        _ option: GroupStageOption,
        teamCount: Int
    ) -> Double {
        abs(Double(teamCount) / Double(option.groupCount) - Double(defaultGroupSize))
    }

    private static func preferredGroupCount(for teamCount: Int) -> Int {
        max(1, (teamCount + defaultGroupSize - 1) / defaultGroupSize)
    }

    private static func qualifiedParticipantName(
        position: Int,
        groupIndex: Int
    ) -> String {
        "Clasificado \(position) \(groupName(index: groupIndex))"
    }
}
