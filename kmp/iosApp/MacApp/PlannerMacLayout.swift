import SwiftUI
import MiGestorKit

struct PlannerMacLayout: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedSessionId: Int64?
    @Binding var inspectorSession: PlanningSession?
    var onToolbarActionsChange: (PlannerMacToolbarActions?) -> Void = { _ in }

    var body: some View {
        MacPlannerView(
            bridge: bridge,
            selectedSessionIdFromRoot: $selectedSessionId,
            inspectorSession: $inspectorSession,
            onToolbarActionsChange: onToolbarActionsChange
        )
    }
}
