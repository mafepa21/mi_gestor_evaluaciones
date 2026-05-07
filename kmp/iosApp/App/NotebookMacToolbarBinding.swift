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
    @Published var exportText: String?

    private var markAllPresentAction: (() -> Void)?
    private var attendanceQuickModeAction: (() -> Void)?
    private var undoAction: (() -> Void)?
    private var toggleInspectorAction: (() -> Void)?
    private var addColumnAction: (() -> Void)?
    private var organizationMenuAction: (() -> Void)?
    private var advancedMenuAction: (() -> Void)?
    private var summaryAction: (() -> Void)?
    private var refreshAction: (() -> Void)?

    func configure(
        canMarkAllPresent: Bool,
        canUndo: Bool,
        canToggleInspector: Bool,
        isAttendanceQuickMode: Bool,
        isInspectorPresented: Bool,
        addColumnAvailable: Bool,
        organizationMenuAvailable: Bool,
        exportText: String?,
        onMarkAllPresent: @escaping () -> Void,
        onToggleAttendanceQuickMode: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onAddColumn: @escaping () -> Void,
        onOpenOrganizationMenu: @escaping () -> Void,
        onOpenAdvancedMenu: @escaping () -> Void,
        onGenerateSummary: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.canMarkAllPresent = canMarkAllPresent
        self.canUndo = canUndo
        self.canToggleInspector = canToggleInspector
        self.isAttendanceQuickMode = isAttendanceQuickMode
        self.isInspectorPresented = isInspectorPresented
        self.addColumnAvailable = addColumnAvailable
        self.organizationMenuAvailable = organizationMenuAvailable
        self.exportText = exportText
        self.markAllPresentAction = onMarkAllPresent
        self.attendanceQuickModeAction = onToggleAttendanceQuickMode
        self.undoAction = onUndo
        self.toggleInspectorAction = onToggleInspector
        self.addColumnAction = onAddColumn
        self.organizationMenuAction = onOpenOrganizationMenu
        self.advancedMenuAction = onOpenAdvancedMenu
        self.summaryAction = onGenerateSummary
        self.refreshAction = onRefresh
    }

    func clear() {
        canMarkAllPresent = false
        canUndo = false
        canToggleInspector = false
        isAttendanceQuickMode = false
        isInspectorPresented = false
        addColumnAvailable = false
        organizationMenuAvailable = false
        exportText = nil
        markAllPresentAction = nil
        attendanceQuickModeAction = nil
        undoAction = nil
        toggleInspectorAction = nil
        addColumnAction = nil
        organizationMenuAction = nil
        advancedMenuAction = nil
        summaryAction = nil
        refreshAction = nil
    }

    func markAllPresent() { markAllPresentAction?() }
    func toggleAttendanceQuickMode() { attendanceQuickModeAction?() }
    func undo() { undoAction?() }
    func toggleInspector() { toggleInspectorAction?() }
    func addColumn() { addColumnAction?() }
    func openOrganizationMenu() { organizationMenuAction?() }
    func openAdvancedMenu() { advancedMenuAction?() }
    func generateSummary() { summaryAction?() }
    func refresh() { refreshAction?() }
}
