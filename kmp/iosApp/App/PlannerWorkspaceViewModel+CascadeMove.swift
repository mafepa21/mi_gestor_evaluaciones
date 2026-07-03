import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func select(session: PlanningSession) async {
        selectedSession = session
        selectedGroupId = session.groupId
        dayViewSelectedDay = nil
        await loadJournalForSelectedSession()
    }

    func previewCascadeMove(sessionId: Int64, day: Int, period: Int) async throws -> SessionCascadeMovePreview {
        guard let bridge else { throw PlannerCascadeMoveError.bridgeUnavailable }
        return try await bridge.plannerPreviewCascadeMove(
            sourceSessionId: sessionId,
            targetWeekNumber: week,
            targetYear: year,
            targetDayOfWeek: day,
            targetPeriod: period
        )
    }

    func commitCascadeMove(sessionId: Int64, day: Int, period: Int) async throws -> SessionCascadeMoveResult {
        guard let bridge else { throw PlannerCascadeMoveError.bridgeUnavailable }
        let result = try await bridge.plannerCommitCascadeMove(
            sourceSessionId: sessionId,
            targetWeekNumber: week,
            targetYear: year,
            targetDayOfWeek: day,
            targetPeriod: period
        )
        lastCascadeMove = result
        await reloadSessionsOnly()
        return result
    }

    func restoreLastCascadeMove() async throws {
        guard let bridge, let lastCascadeMove else { return }
        _ = try await bridge.plannerRestoreCascadeMove(lastCascadeMove.previousPlacements)
        self.lastCascadeMove = nil
        await reloadSessionsOnly()
    }

}

private enum PlannerCascadeMoveError: LocalizedError {
    case bridgeUnavailable

    var errorDescription: String? { "El Planner todavía no está preparado." }
}

