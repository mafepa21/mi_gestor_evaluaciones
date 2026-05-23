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
        Group {
            switch presentation {
            case .full:
                HSplitView {
                    classSidebar
                        .frame(minWidth: 208, idealWidth: 232, maxWidth: 280)

                    notebookContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .content, .inspector:
                notebookContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MacAppStyle.pageBackground)
        .onAppear {
            searchText = layoutState.notebookSearchText
        }
    }

    private var notebookContent: some View {
        NotebookModuleView(
            bridge: bridge,
            selectedClassId: $selectedClassId,
            selectedStudentId: $selectedStudentId,
            onOpenModule: onOpenModule,
            toolbarMode: .macWindowOwned,
            macPresentation: presentation,
            macInspectorState: inspectorState,
            macToolbarActions: showsNotebookToolbar ? toolbarActions : nil
        )
        .environmentObject(layoutState)
    }

    private var classSidebar: some View {
        List(selection: classSelection) {
            ForEach(groupedClasses, id: \.course) { group in
                Section("\(group.course)º") {
                    ForEach(group.classes, id: \.id) { schoolClass in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schoolClass.name)
                                .font(.callout.weight(.medium))
                            Text("Cuaderno de clase")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(schoolClass.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Clases")
    }

    private var classSelection: Binding<Int64?> {
        Binding(
            get: { selectedClassId ?? bridge.notebookViewModel.currentClassId?.int64Value },
            set: { newValue in
                guard let newValue else { return }
                selectedClassId = newValue
                selectedStudentId = nil
                bridge.selectClass(id: newValue)
            }
        )
    }

    private var groupedClasses: [(course: Int32, classes: [SchoolClass])] {
        Dictionary(grouping: bridge.classes, by: \.course)
            .map { course, classes in
                (
                    course: course,
                    classes: classes.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                )
            }
            .sorted { $0.course < $1.course }
    }

}
