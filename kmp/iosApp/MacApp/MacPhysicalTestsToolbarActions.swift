import Foundation

@MainActor
final class MacPhysicalTestsToolbarActions: ObservableObject {
    @Published var canUseClassActions = false

    private var newBatteryAction: (() -> Void)?
    private var captureAction: (() -> Void)?
    private var createColumnsAction: (() -> Void)?
    private var refreshAction: (() -> Void)?

    func configure(
        canUseClassActions: Bool,
        onNewBattery: @escaping () -> Void,
        onCapture: @escaping () -> Void,
        onCreateColumns: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.canUseClassActions = canUseClassActions
        self.newBatteryAction = onNewBattery
        self.captureAction = onCapture
        self.createColumnsAction = onCreateColumns
        self.refreshAction = onRefresh
    }

    func newBattery() {
        newBatteryAction?()
    }

    func capture() {
        captureAction?()
    }

    func createColumns() {
        createColumnsAction?()
    }

    func refresh() {
        refreshAction?()
    }
}
