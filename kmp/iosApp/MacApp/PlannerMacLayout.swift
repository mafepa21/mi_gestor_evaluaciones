import SwiftUI
import MiGestorKit

struct PlannerMacLayout: View {
    let bridge: KmpBridge
    let viewModel: PlannerWorkspaceViewModel
    @Binding var selectedSessionId: Int64?
    @Binding var inspectorSession: PlanningSession?
    var onToolbarActionsChange: (PlannerMacToolbarActions?) -> Void = { _ in }
    var onOpenDiaryDirect: (PlanningSession) -> Void = { _ in }

    var body: some View {
        MacPlannerView(
            bridge: bridge,
            vm: viewModel,
            selectedSessionIdFromRoot: $selectedSessionId,
            inspectorSession: $inspectorSession,
            onToolbarActionsChange: onToolbarActionsChange,
            onOpenDiaryDirect: onOpenDiaryDirect
        )
    }
}
