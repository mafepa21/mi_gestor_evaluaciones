import SwiftUI

/// Vista desordenada: cada grupo es un montón de cuadernos apilados, algo torcidos
/// (siempre igual: el desorden sale del id de cada cuaderno). Tocar un montón lo
/// despliega (`PileFanView`). Los cuadernos sueltos quedan como portadas sueltas,
/// apenas giradas, que se abren con un toque y se pueden arrastrar a un montón.
@MainActor
struct PilesView: View {
    let sections: [LibrarySection]
    let groups: [NotebookGroup]
    let header: LibraryHeader
    let actions: LibraryActions

    /// Grupo del montón desplegado.
    @State private var expandedID: UUID?
    @State private var looseTargeted = false

    private let margin: CGFloat = 48
    private let spacing: CGFloat = Theme.shelfSpacing

    private var groupSections: [LibrarySection] { sections.filter { $0.group != nil } }
    private var looseNotebooks: [Notebook] { sections.first { $0.group == nil }?.notebooks ?? [] }

    var body: some View {
        GeometryReader { geo in
            let cols = max(2, Int((geo.size.width - margin * 2 + spacing) / (210 + spacing)))
            let cell = (geo.size.width - margin * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            // La portada es algo más estrecha que la celda: deja sitio al desorden.
            let coverWidth = max(80, (cell * 0.84).rounded())
            let coverSize = CGSize(width: coverWidth, height: (coverWidth / Theme.coverAspect).rounded())
            let columns = Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: cols)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    if groupSections.isEmpty {
                        looseGrid(columns: columns, coverSize: coverSize, includesNewGroup: true)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 44) {
                            ForEach(groupSections) { section in
                                PileCell(section: section,
                                         coverSize: coverSize,
                                         isExpanded: expandedID != nil && expandedID == section.group?.id,
                                         groups: groups,
                                         actions: actions) {
                                    expandedID = section.group?.id
                                }
                            }
                            newGroupSlot(coverSize)
                        }
                        Text("Sin grupo")
                            .font(Theme.Fonts.title)
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 8)
                        looseGrid(columns: columns, coverSize: coverSize, includesNewGroup: false)
                    }
                }
                .padding(.horizontal, margin)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .scrollDisabled(expandedID != nil)
            .accessibilityHidden(expandedID != nil)
            // El montón desplegado se dibuja encima de todo, partiendo de donde está el montón.
            .overlayPreferenceValue(PileAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let id = expandedID,
                       let section = groupSections.first(where: { $0.group?.id == id }) {
                        let fallback = CGRect(x: (proxy.size.width - coverSize.width) / 2,
                                              y: (proxy.size.height - coverSize.height) / 2,
                                              width: coverSize.width, height: coverSize.height)
                        PileFanView(section: section,
                                    origin: anchors[id].map { proxy[$0] } ?? fallback,
                                    pileCoverSize: coverSize,
                                    containerSize: proxy.size,
                                    groups: groups,
                                    actions: actions) {
                            expandedID = nil
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: groupSections.map(\.id)) { _, ids in
            // El grupo desplegado se ha borrado (o se ha ido por iCloud).
            if let e = expandedID, !ids.contains(e.uuidString) { expandedID = nil }
        }
    }

    /// Portadas sueltas. Es también el sitio donde soltar un cuaderno para sacarlo de su grupo.
    private func looseGrid(columns: [GridItem], coverSize: CGSize, includesNewGroup: Bool) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
            Button { actions.newNotebook(nil) } label: {
                VStack(spacing: 10) {
                    NewNotebookCoverView(size: coverSize)
                    Text(verbatim: " ").font(Theme.Fonts.caption)   // alinea con los pies de foto
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PressableButtonStyle())

            if includesNewGroup { newGroupSlot(coverSize) }

            ForEach(looseNotebooks) { notebook in
                LooseCover(notebook: notebook, coverSize: coverSize, groups: groups, actions: actions)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .opacity(looseTargeted ? 1 : 0)
        }
        .padding(-12)
        .dropDestination(for: String.self) { items, _ in
            actions.drop(items, into: nil)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { looseTargeted = targeted }
        }
    }

    /// Hueco discontinuo del tamaño de un montón: crear grupo.
    private func newGroupSlot(_ coverSize: CGSize) -> some View {
        Button { actions.newGroup(nil) } label: {
            VStack(spacing: 14) {
                VStack(spacing: coverSize.width * 0.05) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: max(14, coverSize.width * 0.15), weight: .light))
                    Text("Nuevo grupo")
                        .font(Theme.Fonts.serif(max(11, coverSize.width * 0.085)))
                }
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: coverSize.width, height: coverSize.height)
                .dashedSlot(cornerRadius: min(Theme.coverCornerRadius, coverSize.width * 0.045))
                // Alinea con el nombre y el recuento de los montones.
                VStack(spacing: 2) {
                    Text(verbatim: " ").font(Theme.Fonts.headline)
                    Text(verbatim: " ").font(Theme.Fonts.caption)
                }
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Nuevo grupo")
    }
}

// MARK: - Desorden estable

/// Giro y desplazamiento de un cuaderno en un montón. Sale del id del cuaderno, así que
/// no cambia entre redibujados. El de arriba (`depth` 0) está casi recto.
struct PileJitter {
    let rotation: Double
    let offset: CGSize
    /// Giro residual cuando el montón está desplegado (colocado a mano, no a máquina).
    let fanRotation: Double

    init(id: UUID, depth: Int, width: CGFloat) {
        var r = StableRandom(id)
        let spread: CGFloat = depth == 0 ? 0.3 : 1
        rotation = Double(r.signed() * 7 * spread)
        offset = CGSize(width: r.signed() * width * 0.07 * spread,
                        height: r.signed() * width * 0.035 * spread - CGFloat(min(depth, 3)) * width * 0.02)
        fanRotation = Double(r.signed() * 1.6)
    }
}

struct PileAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Montón

@MainActor
private struct PileCell: View {
    let section: LibrarySection
    let coverSize: CGSize
    let isExpanded: Bool
    let groups: [NotebookGroup]
    let actions: LibraryActions
    let onExpand: () -> Void

    @State private var isTargeted = false

    /// Cuadernos que se ven en el montón; el resto queda debajo.
    static let maxVisible = 4

    private var countText: String {
        switch section.notebooks.count {
        case 0: "Vacío"
        case 1: "1 libreta"
        default: "\(section.notebooks.count) libretas"
        }
    }

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: 14) {
                stack
                VStack(spacing: 2) {
                    Text(section.title)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(isTargeted ? Theme.accent : Theme.ink)
                        .lineLimit(1)
                    Text(verbatim: countText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: coverSize.width + 24)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            if let group = section.group {
                GroupMenuItems(group: group, groups: groups, actions: actions,
                               moveLabels: ("Mover antes", "Mover después"))
            }
        }
        .dropDestination(for: String.self) { items, _ in
            actions.drop(items, into: section.group)
        } isTargeted: { targeted in
            withAnimation(.spring(duration: 0.25)) { isTargeted = targeted }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Grupo \(section.title)"))
        .accessibilityValue(Text(verbatim: countText))
        .accessibilityHint("Toca para desplegar el montón")
        .accessibilityAddTraits(.isButton)
    }

    private var stack: some View {
        ZStack {
            if section.notebooks.isEmpty {
                // Hueco vacío con el nombre debajo.
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: max(14, coverSize.width * 0.14), weight: .light))
                    Text("Vacío")
                        .font(Theme.Fonts.serif(max(11, coverSize.width * 0.08)))
                }
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: coverSize.width, height: coverSize.height)
                .dashedSlot(cornerRadius: min(Theme.coverCornerRadius, coverSize.width * 0.045),
                            isHighlighted: isTargeted)
            } else {
                let visible = Array(section.notebooks.prefix(Self.maxVisible))
                // El primero (el más reciente) arriba: se dibuja el último.
                ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { depth, notebook in
                    let jitter = PileJitter(id: notebook.id, depth: depth, width: coverSize.width)
                    NotebookCoverView(title: notebook.title,
                                      color: CoverColor.from(notebook.coverColorRaw),
                                      size: coverSize)
                        .rotationEffect(.degrees(jitter.rotation))
                        .offset(jitter.offset)
                }
            }
        }
        .frame(width: coverSize.width, height: coverSize.height)
        .anchorPreference(key: PileAnchorKey.self, value: .bounds) { anchor in
            guard let id = section.group?.id else { return [:] }
            return [id: anchor]
        }
        .scaleEffect(isTargeted ? 1.05 : 1)
        // Mientras está desplegado, sus cuadernos están en `PileFanView`.
        .opacity(isExpanded ? 0 : 1)
    }
}

// MARK: - Cuaderno suelto

@MainActor
private struct LooseCover: View {
    let notebook: Notebook
    let coverSize: CGSize
    let groups: [NotebookGroup]
    let actions: LibraryActions

    /// Leve giro estable: sobre la mesa, no en una rejilla perfecta.
    private var tilt: Double {
        var r = StableRandom(notebook.id, salt: 7)
        return Double(r.signed() * 2.2)
    }

    var body: some View {
        let color = CoverColor.from(notebook.coverColorRaw)
        Button { actions.open(notebook) } label: {
            VStack(spacing: 10) {
                NotebookCoverView(title: notebook.title, color: color, size: coverSize)
                    .rotationEffect(.degrees(tilt))
                Text(notebook.libraryCaption)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .draggable(notebook.dragPayload) {
            NotebookCoverView(title: notebook.title, color: color,
                              size: CGSize(width: 110, height: 110 / Theme.coverAspect))
        }
        .contextMenu {
            NotebookMenuItems(notebook: notebook, groups: groups, actions: actions)
        }
    }
}
