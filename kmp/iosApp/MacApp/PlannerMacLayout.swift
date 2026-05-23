import SwiftUI
import MiGestorKit

struct PlannerMacLayout: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedSessionId: Int64?

    var body: some View {
        MacPlannerView(bridge: bridge, selectedSessionIdFromRoot: $selectedSessionId)
    }
}
