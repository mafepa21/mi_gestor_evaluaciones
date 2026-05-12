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

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

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
        .toolbar {
            if showsNotebookToolbar {
                notebookToolbar
            }
        }
        .onAppear {
            searchText = layoutState.notebookSearchText
        }
        .modifier(NotebookMacSearchModifier(
            isEnabled: showsNotebookToolbar,
            searchText: Binding(
                get: { searchText },
                set: { newValue in
                    searchText = newValue
                    layoutState.setNotebookSearchText(newValue)
                }
            ),
            isSearchFocused: $isSearchFocused
        ))
    }

    private var notebookContent: some View {
        NotebookModuleView(
            bridge: bridge,
            selectedClassId: $selectedClassId,
            selectedStudentId: $selectedStudentId,
            onOpenModule: onOpenModule,
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

    @ToolbarContentBuilder
    private var notebookToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { toolbarActions.isAttendanceQuickMode },
                set: { _ in toolbarActions.toggleAttendanceQuickMode() }
            )) {
                Label("Pase rápido", systemImage: "checklist")
            }
            .disabled(!toolbarActions.canMarkAllPresent)

            Button {
                toolbarActions.markAllPresent()
            } label: {
                Label("Todos presentes", systemImage: "person.3.sequence.fill")
            }
            .disabled(!toolbarActions.canMarkAllPresent)

            Button {
                toolbarActions.undo()
            } label: {
                Label("Deshacer", systemImage: "arrow.uturn.backward")
            }
            .disabled(!toolbarActions.canUndo)

            Button {
                toolbarActions.addColumn()
            } label: {
                Label("Añadir columna", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(!toolbarActions.addColumnAvailable)

            Button {
                toolbarActions.openOrganizationMenu()
            } label: {
                Label("Organizar", systemImage: "slider.horizontal.3")
            }

            Button {
                toolbarActions.generateSummary()
            } label: {
                Label("Resumen IA", systemImage: "sparkles")
            }

            ShareLink(item: toolbarActions.exportText ?? "") {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
            .disabled((toolbarActions.exportText ?? "").isEmpty)
        }
    }
}

private struct NotebookMacSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: "Buscar alumno..."
                )
                .searchFocused(isSearchFocused)
        } else {
            content
        }
    }
}
