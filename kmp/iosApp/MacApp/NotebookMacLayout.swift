import SwiftUI
import MiGestorKit

struct NotebookMacLayout: View {
    let bridge: KmpBridge
    @ObservedObject var notebookStore: NotebookBridgeStore
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
    @SceneStorage("mac.notebook.lastSelectedClassId") private var lastSelectedClassIdRaw: Int = 0

    init(
        bridge: KmpBridge,
        notebookStore: NotebookBridgeStore,
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
        self.notebookStore = notebookStore
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

                // Si no hay clase activa, recuperar la última usada en el Cuaderno
                // antes de caer en la primera de la lista, para no "olvidar" la
                // selección del profesor entre lanzamientos de la app.
                let activeId = selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value
                if activeId == nil {
                    let rememberedId = lastSelectedClassIdRaw != 0 ? Int64(lastSelectedClassIdRaw) : nil
                    if let rememberedId, sortedClasses.contains(where: { $0.id == rememberedId }) {
                        selectedClassId = rememberedId
                        selectedStudentId = nil
                        bridge.selectClass(id: rememberedId)
                    } else if let firstClass = sortedClasses.first {
                        selectedClassId = firstClass.id
                        selectedStudentId = nil
                        bridge.selectClass(id: firstClass.id)
                    }
                }
            }
            .appOnChange(of: selectedClassId) { newValue in
                lastSelectedClassIdRaw = Int(newValue ?? 0)
            }
    }

    private var notebookContent: some View {
        NotebookModuleView(
            bridge: bridge,
            notebookStore: notebookStore,
            selectedClassId: $selectedClassId,
            selectedStudentId: $selectedStudentId,
            onOpenModule: onOpenModule,
            toolbarMode: .macShellOwned,
            macPresentation: presentation,
            macInspectorState: inspectorState,
            macToolbarActions: showsNotebookToolbar ? toolbarActions : nil
        )
        .environmentObject(layoutState)
        .navigationTitle(selectedClassId.flatMap { id in notebookStore.classes.first(where: { $0.id == id })?.name } ?? "Cuaderno")
    }

    private var sortedClasses: [SchoolClass] {
        let uniqueClasses = Dictionary(grouping: notebookStore.classes, by: \.id)
            .compactMap { $0.value.first }
        return uniqueClasses.sorted {
            if $0.course != $1.course { return $0.course < $1.course }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

}
