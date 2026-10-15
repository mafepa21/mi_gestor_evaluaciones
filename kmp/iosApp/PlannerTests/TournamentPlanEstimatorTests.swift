import XCTest
@testable import MiGestorKMPMac

final class TournamentPlanEstimatorTests: XCTestCase {
    private func estimate(
        format: TournamentFormat,
        teamCount: Int,
        groupCount: Int = 0,
        qualifiedTeamsPerGroup: Int = 2,
        venueCount: Int = 2,
        matchDurationMinutes: Int = 8,
        transitionMinutes: Int = 2
    ) -> TournamentPlanEstimate? {
        TournamentPlanEstimator.estimate(
            format: format,
            teamCount: teamCount,
            groupCount: groupCount,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup,
            venueCount: venueCount,
            matchDurationMinutes: matchDurationMinutes,
            transitionMinutes: transitionMinutes
        )
    }

    private func generatedRounds(
        format: TournamentFormat,
        teamCount: Int,
        venueCount: Int,
        groupCount: Int? = nil,
        qualifiedTeamsPerGroup: Int = 2
    ) throws -> [ScheduledRound] {
        try TournamentScheduleGenerator.generate(
            format: format,
            teamNames: TournamentPlan.defaultTeamNames(count: teamCount),
            venueCount: venueCount,
            groupCount: groupCount,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup
        )
    }

    func testRoundRobinEstimateMatchesGenerator() throws {
        let rounds = try generatedRounds(format: .roundRobin, teamCount: 6, venueCount: 2)
        let estimate = try XCTUnwrap(
            estimate(format: .roundRobin, teamCount: 6, venueCount: 2)
        )

        XCTAssertEqual(estimate.matchCount, rounds.flatMap(\.matches).count)
        XCTAssertEqual(estimate.roundCount, rounds.count)
        XCTAssertEqual(estimate.estimatedDurationMinutes, rounds.count * 10)
    }

    func testKnockoutEstimatePacksRoundsByVenue() throws {
        let oneVenueRounds = try generatedRounds(format: .knockout, teamCount: 8, venueCount: 1)
        let oneVenue = try XCTUnwrap(
            estimate(format: .knockout, teamCount: 8, venueCount: 1, matchDurationMinutes: 10, transitionMinutes: 0)
        )

        XCTAssertEqual(oneVenue.matchCount, oneVenueRounds.flatMap(\.matches).count)
        XCTAssertEqual(oneVenue.roundCount, oneVenueRounds.count)
        XCTAssertGreaterThan(oneVenue.roundCount, 3)
        XCTAssertEqual(oneVenue.estimatedDurationMinutes, oneVenueRounds.count * 10)

        let fourVenueRounds = try generatedRounds(format: .knockout, teamCount: 8, venueCount: 4)
        let fourVenues = try XCTUnwrap(
            estimate(format: .knockout, teamCount: 8, venueCount: 4, matchDurationMinutes: 10, transitionMinutes: 0)
        )

        XCTAssertEqual(fourVenues.roundCount, fourVenueRounds.count)
        XCTAssertEqual(fourVenues.matchCount, fourVenueRounds.flatMap(\.matches).count)
        XCTAssertLessThan(fourVenues.roundCount, oneVenue.roundCount)
    }

    func testGroupStageKnockoutEstimateCoversBothPhases() throws {
        let rounds = try generatedRounds(
            format: .groupStageKnockout,
            teamCount: 8,
            venueCount: 2,
            groupCount: 2,
            qualifiedTeamsPerGroup: 2
        )
        let estimate = try XCTUnwrap(
            estimate(
                format: .groupStageKnockout,
                teamCount: 8,
                groupCount: 2,
                qualifiedTeamsPerGroup: 2,
                venueCount: 2
            )
        )

        XCTAssertEqual(estimate.matchCount, rounds.flatMap(\.matches).count)
        XCTAssertEqual(estimate.roundCount, rounds.count)
    }

    func testGroupStageUsesConfiguredQualifiers() throws {
        let oneQualifierRounds = try generatedRounds(
            format: .groupStageKnockout,
            teamCount: 8,
            venueCount: 2,
            groupCount: 4,
            qualifiedTeamsPerGroup: 1
        )
        let twoQualifierRounds = try generatedRounds(
            format: .groupStageKnockout,
            teamCount: 8,
            venueCount: 2,
            groupCount: 4,
            qualifiedTeamsPerGroup: 2
        )
        let oneQualifier = try XCTUnwrap(
            estimate(
                format: .groupStageKnockout,
                teamCount: 8,
                groupCount: 4,
                qualifiedTeamsPerGroup: 1,
                venueCount: 2
            )
        )
        let twoQualifiers = try XCTUnwrap(
            estimate(
                format: .groupStageKnockout,
                teamCount: 8,
                groupCount: 4,
                qualifiedTeamsPerGroup: 2,
                venueCount: 2
            )
        )

        XCTAssertEqual(oneQualifier.matchCount, oneQualifierRounds.flatMap(\.matches).count)
        XCTAssertEqual(twoQualifiers.matchCount, twoQualifierRounds.flatMap(\.matches).count)
        XCTAssertLessThan(oneQualifier.matchCount, twoQualifiers.matchCount)
    }

    func testInvalidInputsReturnNoEstimate() {
        XCTAssertNil(estimate(format: .roundRobin, teamCount: 1))
        XCTAssertNil(estimate(format: .roundRobin, teamCount: 0))
        XCTAssertNil(
            estimate(format: .roundRobin, teamCount: 8, venueCount: 0)
        )
    }

    func testDurationTextIsUserFacing() throws {
        let rounds = try generatedRounds(format: .knockout, teamCount: 4, venueCount: 1)
        let estimate = try XCTUnwrap(
            estimate(format: .knockout, teamCount: 4, venueCount: 1, matchDurationMinutes: 10, transitionMinutes: 0)
        )

        XCTAssertEqual(estimate.estimatedDurationMinutes, rounds.count * 10)
        XCTAssertFalse(estimate.durationText.isEmpty)
    }
}
