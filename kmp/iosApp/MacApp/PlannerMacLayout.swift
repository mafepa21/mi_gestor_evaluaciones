import SwiftUI
import MiGestorKit

struct PlannerMacLayout: View {
    @ObservedObject var bridge: KmpBridge

    var body: some View {
        MacPlannerView(bridge: bridge)
    }
}
