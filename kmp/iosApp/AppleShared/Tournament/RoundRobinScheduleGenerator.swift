import Foundation

struct ScheduledMatch: Identifiable, Hashable, Codable {
    let id: UUID
    let homeTeam: String
    let awayTeam: String
    let venueNumber: Int

    init(
        id: UUID = UUID(),
        homeTeam: String,
        awayTeam: String,
        venueNumber: Int
    ) {
        self.id = id
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.venueNumber = venueNumber
    }
}

enum ScheduledRoundStage: String, Codable, Hashable {
    case league
    case groupStage
    case knockout
}

struct ScheduledRound: Identifiable, Hashable, Codable {
    let id: UUID
    let number: Int
    let matches: [ScheduledMatch]
    let stage: ScheduledRoundStage

    init(
        id: UUID = UUID(),
        number: Int,
        matches: [ScheduledMatch],
        stage: ScheduledRoundStage = .league
    ) {
        self.id = id
        self.number = number
        self.matches = matches
        self.stage = stage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case matches
        case stage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        matches = try container.decode([ScheduledMatch].self, forKey: .matches)
        stage = try container.decodeIfPresent(ScheduledRoundStage.self, forKey: .stage) ?? .league
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(number, forKey: .number)
        try container.encode(matches, forKey: .matches)
        try container.encode(stage, forKey: .stage)
    }
}

enum ScheduleGenerationError: LocalizedError {
    case notEnoughTeams
    case noVenues
    case invalidGroupConfiguration

    var errorDescription: String? {
        switch self {
        case .notEnoughTeams:
            "Necesitas al menos dos equipos para generar una planificación."
        case .noVenues:
            "Necesitas al menos una pista o zona disponible."
        case .invalidGroupConfiguration:
            "La configuración de grupos no permite generar una fase eliminatoria válida."
        }
    }
}

struct RoundRobinScheduleGenerator {
    static func generate(
        teamNames: [String],
        venueCount: Int
    ) throws -> [ScheduledRound] {
        guard teamNames.count >= 2 else {
            throw ScheduleGenerationError.notEnoughTeams
        }
        guard venueCount > 0 else {
            throw ScheduleGenerationError.noVenues
        }

        var participants = teamNames
        if participants.count.isMultiple(of: 2) == false {
            participants.append("__bye__")
        }

        let roundCount = participants.count - 1
        let matchesPerRound = participants.count / 2
        var matches: [ScheduledMatch] = []

        for _ in 0..<roundCount {
            var logicalRoundMatches: [ScheduledMatch] = []

            for matchIndex in 0..<matchesPerRound {
                let first = participants[matchIndex]
                let second = participants[participants.count - 1 - matchIndex]

                guard first != "__bye__", second != "__bye__" else {
                    continue
                }

                logicalRoundMatches.append(
                    ScheduledMatch(
                        homeTeam: first,
                        awayTeam: second,
                        venueNumber: (matchIndex % venueCount) + 1
                    )
                )
            }

            matches.append(contentsOf: logicalRoundMatches)

            let rotating = Array(participants.dropFirst())
            let rotated = [rotating.last!] + Array(rotating.dropLast())
            participants = [participants[0]] + rotated
        }

        return BalancedScheduleGenerator.generate(
            matches: matches,
            teamNames: teamNames,
            venueCount: venueCount,
            stage: .league
        )
    }
}
