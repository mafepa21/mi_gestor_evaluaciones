import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Pantalla central: los cuadernos sobre la mesa, agrupados por tema.
/// Dos modos: «Estantería» (`ShelfView`, ordenada) y «Montones» (`PilesView`, desordenada).
@MainActor
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Notebook.lastOpenedAt, order: .reverse) private var notebooks: [Notebook]
    @Query(sort: [SortDescriptor(\NotebookGroup.sortOrder), SortDescriptor(\NotebookGroup.createdAt)])
    private var groups: [NotebookGroup]
    @AppStorage("libreta.libraryLayout") private var layout: LibraryLayout = .shelf

    @State private var openTarget: ReaderTarget?
    @State private var query = ""
    @State private var showingExport: ExportScope?
    @State private var exportingNotebook: Notebook?
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var newNotebook: NewNotebookRequest?
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var deleting: Notebook?
    @State private var groupDialog = GroupDialogState()

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEmptyLibrary: Bool { notebooks.isEmpty && groups.isEmpty }

    var body: some View {
        // Va dentro del panel de detalle de Mi Gestor: sin NavigationStack propio.
        // La barra y la búsqueda se suman a la barra superior de la app.
        content
            .navigationTitle(isSearching ? "Resultados" : "Libreta")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Buscar en tus notas")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Vista", selection: $layout) {
                        ForEach(LibraryLayout.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                    .disabled(isSearching || isEmptyLibrary)
                    .accessibilityLabel("Vista de la estantería")

                    Menu {
                        Button("Nuevo grupo", systemImage: "square.stack.3d.up") {
                            groupDialog.beginCreate(with: nil)
                        }
                        Divider()
                        Button("Copia de seguridad de todas las libretas…", systemImage: "archivebox") {
                            showingExport = .library(notebooks, groups: groups)
                        }
                        Button("Restaurar o traer de Cuadernos…", systemImage: "square.and.arrow.down") {
                            showingImporter = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Más opciones")

                    if !isEmptyLibrary {
                        Button {
                            newNotebook = NewNotebookRequest(groupID: nil)
                        } label: {
                            Label("Nueva libreta", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        .tint(Theme.accent)
        .sheet(item: Binding(get: { exportingNotebook.map { ExportItem(notebook: $0) } },
                             set: { if $0 == nil { exportingNotebook = nil } })) { item in
            ExportSheet(scope: .notebook(item.notebook, currentPage: nil))
        }
        .sheet(isPresented: Binding(get: { showingExport != nil }, set: { if !$0 { showingExport = nil } })) {
            if let scope = showingExport { ExportSheet(scope: scope) }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .data]) { result in
            restore(result)
        }
        .alert("Copia de seguridad", isPresented: Binding(get: { importMessage != nil },
                                                          set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importMessage ?? "") }
    }

    private var content: some View {
        Group {
            if isEmptyLibrary && !isSearching {
                LibretaEmptyView(
                    onNew: { newNotebook = NewNotebookRequest(groupID: nil) },
                    onImport: { showingImporter = true }
                )
            } else if isSearching {
                ScrollView {
                    PageSearchList(notebooks: notebooks, query: query, showNotebookTitle: true) { nb, index in
                        open(nb, page: index)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            } else {
                switch layout {
                case .shelf:
                    ShelfView(sections: sections, groups: groups, header: header, actions: actions)
                        .transition(.opacity)
                case .piles:
                    PilesView(sections: sections, groups: groups, header: header, actions: actions)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: layout)
        .background(ShelfBackground().ignoresSafeArea())
        .sheet(item: $newNotebook) { request in
            NewNotebookSheet(initialGroupID: request.groupID) { notebook, group in
                context.insert(notebook)
                notebook.pages = [Page(index: 0), Page(index: 1)]
                // La relación se fija después de insertar.
                notebook.group = group
                open(notebook, page: nil)
            }
        }
        .fullScreenCover(item: $openTarget) { target in
            NotebookReaderView(notebook: target.notebook, startPage: target.page)
        }
        .alert("Renombrar libreta", isPresented: Binding(get: { renaming != nil },
                                                          set: { if !$0 { renaming = nil } })) {
            TextField("Título", text: $renameText)
            Button("Guardar") {
                let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let nb = renaming, !t.isEmpty { nb.title = t }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("¿Eliminar esta libreta y todas sus hojas?",
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Eliminar libreta", role: .destructive) {
                if let nb = deleting { context.delete(nb) }
                deleting = nil
            }
            Button("Cancelar", role: .cancel) { deleting = nil }
        }
        .modifier(GroupDialogs(state: $groupDialog, groups: groups))
    }

    private var header: LibraryHeader {
        LibraryHeader(notebookCount: notebooks.count, groupCount: groups.count)
    }

    /// Un apartado por grupo (en su orden) y, al final, los sueltos. Un cuaderno cuyo grupo
    /// no está en la lista (p. ej. a medio sincronizar) se muestra suelto.
    private var sections: [LibrarySection] {
        let known = Set(groups.map(\.id))
        var byGroup: [UUID: [Notebook]] = [:]
        var loose: [Notebook] = []
        for nb in notebooks {
            if let gid = nb.group?.id, known.contains(gid) {
                byGroup[gid, default: []].append(nb)
            } else {
                loose.append(nb)
            }
        }
        return groups.map { LibrarySection(group: $0, notebooks: byGroup[$0.id] ?? []) }
            + [LibrarySection(group: nil, notebooks: loose)]
    }

    private var actions: LibraryActions {
        LibraryActions(
            open: { open($0, page: nil) },
            newNotebook: { newNotebook = NewNotebookRequest(groupID: $0?.id) },
            rename: { nb in
                renameText = nb.title
                renaming = nb
            },
            export: { exportingNotebook = $0 },
            delete: { deleting = $0 },
            move: { nb, group in move(nb, to: group) },
            moveByID: { id, group in
                guard let nb = notebooks.first(where: { $0.id == id }),
                      nb.group?.id != group?.id else { return false }
                move(nb, to: group)
                return true
            },
            newGroup: { groupDialog.beginCreate(with: $0) },
            renameGroup: { groupDialog.beginRename($0) },
            deleteGroup: { groupDialog.deleting = $0 },
            moveGroup: { group, delta in moveGroup(group, by: delta) }
        )
    }

    private func move(_ notebook: Notebook, to group: NotebookGroup?) {
        withAnimation(.spring(duration: 0.35)) { notebook.group = group }
    }

    private func moveGroup(_ group: NotebookGroup, by delta: Int) {
        var ordered = groups
        guard let i = ordered.firstIndex(where: { $0.id == group.id }),
              ordered.indices.contains(i + delta) else { return }
        ordered.swapAt(i, i + delta)
        withAnimation(.spring(duration: 0.35)) {
            // Renumera todo: así también se deshacen empates (p. ej. tras sincronizar).
            for (k, g) in ordered.enumerated() where g.sortOrder != k { g.sortOrder = k }
        }
    }

    private func open(_ notebook: Notebook, page: Int?) {
        notebook.lastOpenedAt = Date()
        // Espera a que se cierre la hoja de "nuevo cuaderno" si viene de ahí.
        DispatchQueue.main.async { openTarget = ReaderTarget(notebook: notebook, page: page) }
    }

    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let added = try Backup.restore(try Data(contentsOf: url), into: context)
            switch (added.notebooks, added.groups) {
            case (0, 0): importMessage = "No había libretas nuevas que añadir."
            case (let n, 0): importMessage = "Se han añadido \(n) libreta(s)."
            case (0, let g): importMessage = "Se han añadido \(g) grupo(s)."
            case (let n, let g): importMessage = "Se han añadido \(n) libreta(s) y \(g) grupo(s)."
            }
        } catch {
            importMessage = "No se pudo leer el archivo: \(error.localizedDescription)"
        }
    }
}

struct ReaderTarget: Identifiable {
    let id = UUID()
    let notebook: Notebook
    let page: Int?
}

/// Petición de "nuevo cuaderno", con el grupo en el que debe nacer.
private struct NewNotebookRequest: Identifiable {
    let id = UUID()
    let groupID: UUID?
}

private struct ExportItem: Identifiable, Equatable {
    let notebook: Notebook
    var id: UUID { notebook.id }
}
