import SwiftUI
import MiGestorKit

struct PlannerWeekMiniatureLayout: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @Binding var selectedCell: PlannerCellKey?
    @Binding var selectedDay: Int?
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlannerWeekMiniatureGrid(
                vm: vm,
                selectedCell: $selectedCell,
                selectedDay: $selectedDay
            )
            .frame(height: gridHeight)
            .padding(.horizontal, EvaluationDesign.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider().opacity(0.16)

            PlannerWeekDetailPane(
                vm: vm,
                selectedCell: $selectedCell,
                selectedDay: $selectedDay,
                onOpenSession: onOpenSession
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gridHeight: CGFloat {
        let slotsCount = vm.weekRenderModel.visibleSlots.count
        guard slotsCount > 0 else { return 40 }
        let rowHeight: CGFloat = 36
        let spacing: CGFloat = 4
        return 40 + CGFloat(slotsCount) * (rowHeight + spacing) + spacing
    }
}
