import SwiftUI

@MainActor
final class NotebookMacToolbarActions: ObservableObject {
    @Published var canMarkAllPresent = false
    @Published var canUndo = false
    @Published var canToggleInspector = false
    @Published var isAttendanceQuickMode = false
    @Published var isInspectorPresented = false
    @Published var addColumnAvailable = false
    @Published var organizationMenuAvailable = false
    @Published var groupManagementAvailable = false
    @Published var exportText: String?

    private var markAllPresentAction: (() -> Void)?
    private var attendanceQuickModeAction: (() -> Void)?
    private var undoAction: (() -> Void)?
    private var toggleInspectorAction: (() -> Void)?
    private var addColumnAction: (() -> Void)?
    private var organizationMenuAction: (() -> Void)?
    private var groupManagementAction: (() -> Void)?
    private var advancedMenuAction: (() -> Void)?
    private var summaryAction: (() -> Void)?
    private var refreshAction: (() -> Void)?

    private func publishDeferred(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            mutation()
        }
    }

    func configure(
        canMarkAllPresent: Bool,
        canUndo: Bool,
        canToggleInspector: Bool,
        isAttendanceQuickMode: Bool,
        isInspectorPresented: Bool,
        addColumnAvailable: Bool,
        organizationMenuAvailable: Bool,
        groupManagementAvailable: Bool,
        exportText: String?,
        onMarkAllPresent: @escaping () -> Void,
        onToggleAttendanceQuickMode: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onAddColumn: @escaping () -> Void,
        onOpenOrganizationMenu: @escaping () -> Void,
        onOpenGroupManagement: @escaping () -> Void,
        onOpenAdvancedMenu: @escaping () -> Void,
        onGenerateSummary: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        publishDeferred {
            self.canMarkAllPresent = canMarkAllPresent
            self.canUndo = canUndo
            self.canToggleInspector = canToggleInspector
            self.isAttendanceQuickMode = isAttendanceQuickMode
            self.isInspectorPresented = isInspectorPresented
            self.addColumnAvailable = addColumnAvailable
            self.organizationMenuAvailable = organizationMenuAvailable
            self.groupManagementAvailable = groupManagementAvailable
            self.exportText = exportText
            self.markAllPresentAction = onMarkAllPresent
            self.attendanceQuickModeAction = onToggleAttendanceQuickMode
            self.undoAction = onUndo
            self.toggleInspectorAction = onToggleInspector
            self.addColumnAction = onAddColumn
            self.organizationMenuAction = onOpenOrganizationMenu
            self.groupManagementAction = onOpenGroupManagement
            self.advancedMenuAction = onOpenAdvancedMenu
            self.summaryAction = onGenerateSummary
            self.refreshAction = onRefresh
        }
    }

    func clear() {
        publishDeferred {
            self.canMarkAllPresent = false
            self.canUndo = false
            self.canToggleInspector = false
            self.isAttendanceQuickMode = false
            self.isInspectorPresented = false
            self.addColumnAvailable = false
            self.organizationMenuAvailable = false
            self.groupManagementAvailable = false
            self.exportText = nil
            self.markAllPresentAction = nil
            self.attendanceQuickModeAction = nil
            self.undoAction = nil
            self.toggleInspectorAction = nil
            self.addColumnAction = nil
            self.organizationMenuAction = nil
            self.groupManagementAction = nil
            self.advancedMenuAction = nil
            self.summaryAction = nil
            self.refreshAction = nil
        }
    }

    func markAllPresent() { markAllPresentAction?() }
    func toggleAttendanceQuickMode() { attendanceQuickModeAction?() }
    func undo() { undoAction?() }
    func toggleInspector() { toggleInspectorAction?() }
    func addColumn() { addColumnAction?() }
    func openOrganizationMenu() { organizationMenuAction?() }
    func openGroupManagement() { groupManagementAction?() }
    func openAdvancedMenu() { advancedMenuAction?() }
    func generateSummary() { summaryAction?() }
    func refresh() { refreshAction?() }
}
