import SwiftUI
import CoreTransferable

/// Texto del Cuaderno para «Exportar»/«Compartir», calculado solo al exportar.
///
/// `exportText(data:)` recorre todas las filas y columnas (y evalúa fórmulas): no se
/// calcula al pintar menús ni al sincronizar la barra, sino cuando el sistema pide
/// el contenido a `ShareLink`.
struct NotebookExportTextItem: Transferable {
    let makeText: @MainActor () -> String

    static var transferRepresentation: some TransferRepresentation {
        // Exportador síncrono (el asíncrono está obsoleto desde macOS 14). El texto lee
        // estado de SwiftUI y del puente: se calcula siempre en el hilo principal.
        ProxyRepresentation(exporting: { (item: NotebookExportTextItem) -> String in
            if Thread.isMainThread {
                return MainActor.assumeIsolated { item.makeText() }
            }
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { item.makeText() }
            }
        })
    }
}

@MainActor
final class NotebookMacToolbarActions: ObservableObject {
    @Published var canMarkAllPresent = false
    @Published var canUndo = false
    @Published var canToggleInspector = false
    @Published var isAttendanceQuickMode = false
    @Published var isInspectorPresented = false
    @Published var isQuickKeypadPresented = false
    @Published var addColumnAvailable = false
    @Published var organizationMenuAvailable = false
    @Published var groupManagementAvailable = false
    /// Solo indica si hay exportación; el texto se genera al exportar.
    @Published var isExportAvailable = false
    /// Sin publicar: cambiarlo no repinta nada.
    private(set) var exportTextProvider: (@MainActor () -> String)?

    private var markAllPresentAction: (() -> Void)?
    private var attendanceQuickModeAction: (() -> Void)?
    private var toggleQuickKeypadAction: (() -> Void)?
    private var undoAction: (() -> Void)?
    private var toggleInspectorAction: (() -> Void)?
    private var addColumnAction: (() -> Void)?
    private var organizationMenuAction: (() -> Void)?
    private var groupManagementAction: (() -> Void)?
    private var advancedMenuAction: (() -> Void)?
    private var summaryAction: (() -> Void)?
    private var refreshAction: (() -> Void)?
    private(set) var exportSMAction: (() -> Void)?

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
        isQuickKeypadPresented: Bool = false,
        addColumnAvailable: Bool,
        organizationMenuAvailable: Bool,
        groupManagementAvailable: Bool,
        exportTextProvider: (@MainActor () -> String)?,
        onMarkAllPresent: @escaping () -> Void,
        onToggleAttendanceQuickMode: @escaping () -> Void,
        onToggleQuickKeypad: (() -> Void)? = nil,
        onUndo: @escaping () -> Void,
        onToggleInspector: @escaping () -> Void,
        onAddColumn: @escaping () -> Void,
        onOpenOrganizationMenu: @escaping () -> Void,
        onOpenGroupManagement: @escaping () -> Void,
        onOpenAdvancedMenu: @escaping () -> Void,
        onGenerateSummary: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onExportSM: (() -> Void)? = nil
    ) {
        publishDeferred {
            self.canMarkAllPresent = canMarkAllPresent
            self.canUndo = canUndo
            self.canToggleInspector = canToggleInspector
            self.isAttendanceQuickMode = isAttendanceQuickMode
            self.isInspectorPresented = isInspectorPresented
            self.isQuickKeypadPresented = isQuickKeypadPresented
            self.addColumnAvailable = addColumnAvailable
            self.organizationMenuAvailable = organizationMenuAvailable
            self.groupManagementAvailable = groupManagementAvailable
            self.exportTextProvider = exportTextProvider
            let exportAvailable = exportTextProvider != nil
            if self.isExportAvailable != exportAvailable {
                self.isExportAvailable = exportAvailable
            }
            self.markAllPresentAction = onMarkAllPresent
            self.attendanceQuickModeAction = onToggleAttendanceQuickMode
            self.toggleQuickKeypadAction = onToggleQuickKeypad
            self.undoAction = onUndo
            self.toggleInspectorAction = onToggleInspector
            self.addColumnAction = onAddColumn
            self.organizationMenuAction = onOpenOrganizationMenu
            self.groupManagementAction = onOpenGroupManagement
            self.advancedMenuAction = onOpenAdvancedMenu
            self.summaryAction = onGenerateSummary
            self.refreshAction = onRefresh
            self.exportSMAction = onExportSM
        }
    }

    func clear() {
        publishDeferred {
            self.canMarkAllPresent = false
            self.canUndo = false
            self.canToggleInspector = false
            self.isAttendanceQuickMode = false
            self.isInspectorPresented = false
            self.isQuickKeypadPresented = false
            self.addColumnAvailable = false
            self.organizationMenuAvailable = false
            self.groupManagementAvailable = false
            self.exportTextProvider = nil
            self.isExportAvailable = false
            self.markAllPresentAction = nil
            self.attendanceQuickModeAction = nil
            self.toggleQuickKeypadAction = nil
            self.undoAction = nil
            self.toggleInspectorAction = nil
            self.addColumnAction = nil
            self.organizationMenuAction = nil
            self.groupManagementAction = nil
            self.advancedMenuAction = nil
            self.summaryAction = nil
            self.refreshAction = nil
            self.exportSMAction = nil
        }
    }

    func markAllPresent() { markAllPresentAction?() }
    func toggleAttendanceQuickMode() { attendanceQuickModeAction?() }
    func toggleQuickKeypad() { toggleQuickKeypadAction?() }
    func undo() { undoAction?() }
    func toggleInspector() { toggleInspectorAction?() }
    func addColumn() { addColumnAction?() }
    func openOrganizationMenu() { organizationMenuAction?() }
    func openGroupManagement() { groupManagementAction?() }
    func openAdvancedMenu() { advancedMenuAction?() }
    func generateSummary() { summaryAction?() }
    func refresh() { refreshAction?() }
    func exportSM() { exportSMAction?() }

    /// Elemento para `ShareLink`: el texto se pide al exportar, no al montar el menú.
    var exportItem: NotebookExportTextItem? {
        guard isExportAvailable, exportTextProvider != nil else { return nil }
        return NotebookExportTextItem { [weak self] in
            self?.exportTextProvider?() ?? ""
        }
    }
}
