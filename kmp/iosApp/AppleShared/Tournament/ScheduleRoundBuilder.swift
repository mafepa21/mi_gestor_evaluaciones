import Foundation

enum ScheduleRoundBuilder {
    static func split(
        matches: [ScheduledMatch],
        venueCount: Int,
        startingNumber: Int,
        stage: ScheduledRoundStage = .league
    ) -> [ScheduledRound] {
        guard venueCount > 0, !matches.isEmpty else { return [] }

        return stride(from: 0, to: matches.count, by: venueCount).enumerated().map { offset, startIndex in
            let endIndex = min(startIndex + venueCount, matches.count)
            return ScheduledRound(
                number: startingNumber + offset,
                matches: Array(matches[startIndex..<endIndex]),
                stage: stage
            )
        }
    }
}
