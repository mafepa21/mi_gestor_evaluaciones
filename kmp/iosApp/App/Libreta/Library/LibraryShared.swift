import SwiftUI

// MARK: - Modo de la biblioteca

/// Cómo se colocan los cuadernos en la mesa. Se recuerda con `@AppStorage`.
enum LibraryLayout: String, CaseIterable, Identifiable {
    /// Ordenada: cada grupo es una balda con los cuadernos de pie (lomos).
    case shelf
    /// Desordenada: cada grupo es un montón que se despliega al tocarlo.
    case piles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shelf: "Estantería"
        case .piles: "Montones"
        }
    }
}

// MARK: - Secciones

/// Un grupo con sus cuadernos, o los cuadernos sueltos (`group == nil`).
struct LibrarySection: Identifiable {
    let group: NotebookGroup?
    /// Por última apertura (el más reciente primero).
    let notebooks: [Notebook]

    var id: String { group?.id.uuidString ?? "sueltos" }
    var title: String { group?.displayName ?? "Sin grupo" }
}

// MARK: - Acciones

/// Acciones de la biblioteca que comparten la estantería, los montones y los menús.
/// Las implementa `LibraryView` (que tiene el contexto y presenta hojas y diálogos).
struct LibraryActions {
    var open: (Notebook) -> Void
    /// Nuevo cuaderno; nace en el grupo indicado (`nil` = suelto).
    var newNotebook: (NotebookGroup?) -> Void
    var rename: (Notebook) -> Void
    var export: (Notebook) -> Void
    var delete: (Notebook) -> Void
    /// Mueve un cuaderno a un grupo (`nil` = sacarlo del grupo).
    var move: (Notebook, NotebookGroup?) -> Void
    /// Igual que `move`, a partir del id que llega al soltar un arrastre.
    /// Devuelve `false` si no había nada que mover.
    var moveByID: (UUID, NotebookGroup?) -> Bool
    /// Nuevo grupo; si se pasa un cuaderno, entra en él.
    var newGroup: (Notebook?) -> Void
    var renameGroup: (NotebookGroup) -> Void
    var deleteGroup: (NotebookGroup) -> Void
    /// Sube (-1) o baja (+1) un grupo en la biblioteca.
    var moveGroup: (NotebookGroup, Int) -> Void

    /// Maneja lo que se suelta sobre un grupo: el id de un cuaderno como texto.
    func drop(_ items: [String], into group: NotebookGroup?) -> Bool {
        guard let id = items.lazy.compactMap({ UUID(uuidString: $0) }).first else { return false }
        return moveByID(id, group)
    }
}

extension Notebook {
    /// Pie de foto: nº de hojas y última apertura (nunca el título, que ya está en la tapa).
    var libraryCaption: String {
        // Solo cuenta hojas (sin leer la tinta, que vive en almacenamiento externo).
        let count = pageList.count
        let sheets = count == 1 ? "1 hoja" : "\(count) hojas"
        let date = lastOpenedAt.formatted(.dateTime.day().month(.abbreviated))
        return "\(sheets) · \(date)"
    }

    /// Carga útil al arrastrar el cuaderno sobre un grupo.
    var dragPayload: String { id.uuidString }
}

// MARK: - Menús

/// Menú contextual de un cuaderno (portada o lomo).
@MainActor
struct NotebookMenuItems: View {
    let notebook: Notebook
    let groups: [NotebookGroup]
    let actions: LibraryActions
    @Environment(\.libretaClasses) private var classes

    var body: some View {
        Button("Abrir", systemImage: "book") { actions.open(notebook) }
        Button("Renombrar", systemImage: "pencil") { actions.rename(notebook) }
        Menu {
            ForEach(groups) { g in
                let isCurrent = notebook.group?.id == g.id
                Button {
                    if !isCurrent { actions.move(notebook, g) }
                } label: {
                    if isCurrent {
                        Label(g.displayName, systemImage: "checkmark")
                    } else {
                        Text(g.displayName)
                    }
                }
            }
            if !groups.isEmpty { Divider() }
            Button("Grupo nuevo…", systemImage: "plus") { actions.newGroup(notebook) }
            if notebook.group != nil {
                Button("Sacar del grupo", systemImage: "tray.and.arrow.up") { actions.move(notebook, nil) }
            }
        } label: {
            Label("Mover a grupo…", systemImage: "folder")
        }
        if !classes.isEmpty {
            classMenu
        }
        Button("Exportar…", systemImage: "square.and.arrow.up") { actions.export(notebook) }
        Divider()
        Button("Eliminar libreta", systemImage: "trash", role: .destructive) { actions.delete(notebook) }
    }
}

extension NotebookMenuItems {
    /// «Clase»: la clase de Mi Gestor a la que se liga la libreta (no la balda).
    private var classMenu: some View {
        let current = classes.name(for: notebook.linkedClassId)
        return Menu {
            Button {
                notebook.linkedClassId = nil
            } label: {
                if current == nil { Label("Ninguna", systemImage: "checkmark") } else { Text("Ninguna") }
            }
            Divider()
            ForEach(classes) { option in
                Button {
                    notebook.linkedClassId = option.id
                } label: {
                    if notebook.linkedClassId == option.id {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            Label(current.map { "Clase: \($0)" } ?? "Clase", systemImage: "person.2")
        }
    }
}

/// Menú de un grupo (rótulo de la balda, montón, cabecera del montón desplegado).
@MainActor
struct GroupMenuItems: View {
    let group: NotebookGroup
    let groups: [NotebookGroup]
    let actions: LibraryActions
    /// Textos de orden según la vista ("Subir"/"Bajar" en baldas, "Antes"/"Después" en montones).
    var moveLabels: (earlier: String, later: String) = ("Subir", "Bajar")

    var body: some View {
        let index = groups.firstIndex { $0.id == group.id }
        Button("Nueva libreta aquí", systemImage: "plus") { actions.newNotebook(group) }
        Button("Renombrar grupo", systemImage: "pencil") { actions.renameGroup(group) }
        if let index, index > 0 {
            Button(moveLabels.earlier, systemImage: "arrow.up") { actions.moveGroup(group, -1) }
        }
        if let index, index < groups.count - 1 {
            Button(moveLabels.later, systemImage: "arrow.down") { actions.moveGroup(group, 1) }
        }
        Divider()
        Button("Eliminar grupo…", systemImage: "trash", role: .destructive) { actions.deleteGroup(group) }
    }
}

// MARK: - Cabecera

/// Cabecera sobre la mesa: un recuento discreto.
struct LibraryHeader: View {
    let notebookCount: Int
    let groupCount: Int

    var body: some View {
        // El título «Libreta» ya está en la barra de la app: aquí solo el recuento.
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: subtitle)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var subtitle: String {
        if notebookCount == 0 && groupCount == 0 { return "Empieza tu primera libreta" }
        let nbs = notebookCount == 1 ? "1 libreta" : "\(notebookCount) libretas"
        switch groupCount {
        case 0: return nbs
        case 1: return "\(nbs) · 1 grupo"
        default: return "\(nbs) · \(groupCount) grupos"
        }
    }
}

// MARK: - Huecos discontinuos

extension View {
    /// Hueco de "crear algo": relleno tenue y borde discontinuo (como "Nuevo cuaderno").
    func dashedSlot(cornerRadius: CGFloat, isHighlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background { shape.fill(Theme.newSlotFill) }
            .overlay {
                shape.strokeBorder(isHighlighted ? Theme.accent : Theme.inkSecondary.opacity(0.55),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            }
            .contentShape(shape)
    }
}
