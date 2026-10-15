import SwiftUI
import SwiftData

/// Estado de los diálogos de grupos (crear, renombrar, eliminar).
struct GroupDialogState {
    var isCreating = false
    /// Cuaderno que entra en el grupo que se va a crear (desde «Mover a grupo › Grupo nuevo…»).
    var pendingNotebook: Notebook?
    var renaming: NotebookGroup?
    var deleting: NotebookGroup?
    var text = ""

    mutating func beginCreate(with notebook: Notebook?) {
        pendingNotebook = notebook
        text = ""
        isCreating = true
    }

    mutating func beginRename(_ group: NotebookGroup) {
        text = group.name
        renaming = group
    }
}

/// Diálogos de gestión de grupos. Se aplican una vez en `LibraryView`.
@MainActor
struct GroupDialogs: ViewModifier {
    @Binding var state: GroupDialogState
    let groups: [NotebookGroup]
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .alert("Nuevo grupo", isPresented: $state.isCreating) {
                TextField("Nombre del grupo", text: $state.text)
                Button("Crear") { create() }
                Button("Cancelar", role: .cancel) { state.pendingNotebook = nil }
            } message: {
                if let nb = state.pendingNotebook {
                    Text(verbatim: "«\(nb.title.isEmpty ? "Sin título" : nb.title)» se guardará en el grupo nuevo.")
                } else {
                    Text("Reúne libretas de un mismo tema en una balda o un montón.")
                }
            }
            .alert("Renombrar grupo", isPresented: Binding(get: { state.renaming != nil },
                                                          set: { if !$0 { state.renaming = nil } })) {
                TextField("Nombre del grupo", text: $state.text)
                Button("Guardar") {
                    let t = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let g = state.renaming, !t.isEmpty { g.name = t }
                    state.renaming = nil
                }
                Button("Cancelar", role: .cancel) { state.renaming = nil }
            }
            .confirmationDialog(Text(verbatim: "¿Eliminar el grupo «\(state.deleting?.displayName ?? "")»?"),
                                isPresented: Binding(get: { state.deleting != nil },
                                                     set: { if !$0 { state.deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Eliminar grupo", role: .destructive) {
                    if let g = state.deleting { delete(g) }
                    state.deleting = nil
                }
                Button("Cancelar", role: .cancel) { state.deleting = nil }
            } message: {
                Text("Las libretas no se borran: pasan a «Sin grupo».")
            }
    }

    private func create() {
        let t = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = NotebookGroup(name: t.isEmpty ? "Grupo nuevo" : t,
                                  sortOrder: (groups.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(group)
        // La relación se fija después de insertar (SwiftData lo prefiere así).
        if let nb = state.pendingNotebook {
            withAnimation(.spring(duration: 0.35)) { nb.group = group }
        }
        state.pendingNotebook = nil
    }

    private func delete(_ group: NotebookGroup) {
        withAnimation(.spring(duration: 0.35)) {
            // `.nullify` ya lo haría; se hace explícito para que la vista se actualice al momento.
            for nb in group.notebookList { nb.group = nil }
            context.delete(group)
        }
    }
}
