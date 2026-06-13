import SwiftUI
import MiGestorKit

struct NotebookMacLayout: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var toolbarActions: NotebookMacToolbarActions
    @ObservedObject var inspectorState: NotebookMacInspectorState
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?

    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let presentation: NotebookMacPresentation
    let onToggleInspectorColumn: (() -> Void)?

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    init(
        bridge: KmpBridge,
        layoutState: WorkspaceLayoutState,
        toolbarActions: NotebookMacToolbarActions,
        inspectorState: NotebookMacInspectorState,
        selectedClassId: Binding<Int64?>,
        selectedStudentId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void,
        presentation: NotebookMacPresentation,
        onToggleInspectorColumn: (() -> Void)? = nil
    ) {
        self.bridge = bridge
        self.layoutState = layoutState
        self.toolbarActions = toolbarActions
        self.inspectorState = inspectorState
        self._selectedClassId = selectedClassId
        self._selectedStudentId = selectedStudentId
        self.onOpenModule = onOpenModule
        self.presentation = presentation
        self.onToggleInspectorColumn = onToggleInspectorColumn
    }

    private var showsNotebookToolbar: Bool {
        presentation == .content || presentation == .full
    }

    @ViewBuilder
    var body: some View {
        notebookContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacAppStyle.pageBackground)
            .onAppear {
                searchText = layoutState.notebookSearchText
                
                // Auto-select the first class on load if none is selected
                let activeId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value
                if activeId == nil {
                    if let firstClass = sortedClasses.first {
                        selectedClassId = firstClass.id
                        selectedStudentId = nil
                        bridge.selectClass(id: firstClass.id)
                    }
                }
            }
    }

    private var notebookContent: some View {
        NotebookModuleView(
            bridge: bridge,
            selectedClassId: $selectedClassId,
            selectedStudentId: $selectedStudentId,
            onOpenModule: onOpenModule,
            toolbarMode: .hidden,
            macPresentation: presentation,
            macInspectorState: inspectorState,
            macToolbarActions: showsNotebookToolbar ? toolbarActions : nil
        )
        .environmentObject(layoutState)
        .navigationTitle(selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id })?.name } ?? "Cuaderno")
    }

    private var sortedClasses: [SchoolClass] {
        let uniqueClasses = Dictionary(grouping: bridge.classes, by: \.id)
            .compactMap { $0.value.first }
        return uniqueClasses.sorted {
            if $0.course != $1.course { return $0.course < $1.course }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

}
