import SwiftUI

/// Vista ordenada: cada grupo es una balda de madera con los cuadernos de pie (lomos).
///
/// - Toque en un lomo: abre el cuaderno.
/// - Hover (Apple Pencil que se acerca a la pantalla, trackpad o ratón): el cuaderno se
///   saca un poco de la balda y su portada flota junto a él.
/// - Pulsación larga: portada ampliada + menú (Abrir, Renombrar, Mover a grupo…).
/// - Arrastrar un lomo a otra balda lo cambia de grupo.
@MainActor
struct ShelfView: View {
    let sections: [LibrarySection]
    let groups: [NotebookGroup]
    let header: LibraryHeader
    let actions: LibraryActions

    @State private var hoveredID: UUID?

    /// Alto del lomo más alto.
    static let spineMaxHeight: CGFloat = 188
    /// Margen interior de la balda (los lomos no llegan al borde).
    static let plankInset: CGFloat = 18
    static let spineSpacing: CGFloat = 3
    private let margin: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let shelfWidth = max(240, geo.size.width - margin * 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    header
                    LazyVStack(alignment: .leading, spacing: 44) {
                        ForEach(sections) { section in
                            ShelfSectionView(section: section,
                                             label: section.group == nil && groups.isEmpty ? nil : section.title,
                                             width: shelfWidth,
                                             groups: groups,
                                             actions: actions,
                                             hoveredID: $hoveredID)
                        }
                        newGroupButton
                    }
                }
                .padding(.horizontal, margin)
                .padding(.top, 8)
                .padding(.bottom, 48)
                // Portada flotante del lomo sobre el que está el Pencil / puntero.
                .overlayPreferenceValue(SpineHoverKey.self) { hover in
                    GeometryReader { proxy in
                        if let hover {
                            SpineHoverCard(hover: hover, proxy: proxy)
                                .id(hover.id)
                                .transition(.opacity)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hover?.id)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var newGroupButton: some View {
        Button { actions.newGroup(nil) } label: {
            Label("Nuevo grupo", systemImage: "plus")
                .font(Theme.Fonts.serif(16))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .dashedSlot(cornerRadius: 8)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityHint("Crea una balda nueva para reunir cuadernos de un mismo tema")
    }
}

// MARK: - Medidas de los lomos

enum SpineMetrics {
    /// Grosor según el nº de hojas más un poco de variación estable; altura algo variable.
    static func size(for notebook: Notebook, maxHeight: CGFloat) -> CGSize {
        var r = StableRandom(notebook.id)
        let sheets = CGFloat(min(notebook.pageList.count, 160))
        let width = 26 + sheets * 0.14 + r.unit() * 10
        let height = maxHeight * (0.84 + r.unit() * 0.16)
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// Semilla estable para las vetas de una balda.
    static func plankSeed(_ sectionID: String, row: Int) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in sectionID.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h &+ UInt64(row) &* 0x9E3779B97F4A7C15
    }
}

// MARK: - Balda de un grupo

@MainActor
private struct ShelfSectionView: View {
    let section: LibrarySection
    /// Rótulo de la balda (`nil` cuando no hay grupos: no hace falta decir "Sueltos").
    let label: String?
    let width: CGFloat
    let groups: [NotebookGroup]
    let actions: LibraryActions
    @Binding var hoveredID: UUID?

    @State private var isTargeted = false

    private enum Item: Identifiable {
        case notebook(Notebook, CGSize)
        case add

        var id: String {
            switch self {
            case .notebook(let nb, _): nb.id.uuidString
            case .add: "add"
            }
        }

        var width: CGFloat {
            switch self {
            case .notebook(_, let size): size.width
            case .add: 40
            }
        }
    }

    /// Reparte los lomos en baldas que caben a lo ancho. En la balda el orden es estable
    /// (por fecha de creación), para que los cuadernos no cambien de sitio al abrirlos.
    private var rows: [[Item]] {
        let available = width - ShelfView.plankInset * 2
        let sorted = section.notebooks.sorted { $0.createdAt < $1.createdAt }
        let items = sorted.map { Item.notebook($0, SpineMetrics.size(for: $0, maxHeight: ShelfView.spineMaxHeight)) }
            + [Item.add]
        var rows: [[Item]] = [[]]
        var used: CGFloat = 0
        for item in items {
            if !rows[rows.count - 1].isEmpty, used + item.width > available {
                rows.append([])
                used = 0
            }
            rows[rows.count - 1].append(item)
            used += item.width + ShelfView.spineSpacing
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                shelfRow(row, index: index)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            actions.drop(items, into: section.group)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isTargeted = targeted }
        }
    }

    private func shelfRow(_ row: [Item], index: Int) -> some View {
        // Los lomos se apoyan sobre la cara superior de la balda.
        VStack(spacing: -ShelfPlank.topDepth * 0.6) {
            HStack(alignment: .bottom, spacing: ShelfView.spineSpacing) {
                ForEach(row) { item in
                    switch item {
                    case .notebook(let nb, let size):
                        ShelfSpine(notebook: nb, size: size, groups: groups, actions: actions,
                                   hoveredID: $hoveredID)
                    case .add:
                        addSlot
                    }
                }
                if section.notebooks.isEmpty {
                    Text(emptyHint)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.leading, 12)
                        .padding(.bottom, 14)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ShelfView.plankInset)
            .zIndex(1)

            ShelfPlank(seed: SpineMetrics.plankSeed(section.id, row: index), isHighlighted: isTargeted)
                .overlay(alignment: .bottomLeading) {
                    if index == 0, let label { tag(label) }
                }
        }
    }

    /// Hueco discontinuo al final de la balda: nuevo cuaderno en este grupo.
    private var addSlot: some View {
        Button { actions.newNotebook(section.group) } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 40, height: ShelfView.spineMaxHeight * 0.62)
                .dashedSlot(cornerRadius: 4)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.94))
        .padding(.leading, 6)
        .accessibilityLabel(section.group.map { "Nuevo cuaderno en \($0.displayName)" } ?? "Nuevo cuaderno")
    }

    /// Rótulo de papel clavado en el frente de la balda. En un grupo es un menú.
    @ViewBuilder
    private func tag(_ text: String) -> some View {
        // Nombres muy largos se recortan: el rótulo no debe tapar la balda.
        let shown = text.count > 36 ? String(text.prefix(35)) + "…" : text
        let content = HStack(spacing: 6) {
            Text(shown)
                .font(Theme.Fonts.serif(14, weight: .medium))
                .foregroundStyle(Theme.paperInk)
                .lineLimit(1)
            if section.group != nil {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.paperInkSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Theme.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(isTargeted ? Theme.accent : Theme.paperEdgeLine, lineWidth: isTargeted ? 1.5 : 0.5)
                }
                .shadow(color: Color.black.opacity(0.25), radius: 1.2, x: 0, y: 1)
        }
        .fixedSize()

        Group {
            if let group = section.group {
                Menu {
                    GroupMenuItems(group: group, groups: groups, actions: actions)
                } label: {
                    content
                }
                .menuIndicator(.hidden)
                .accessibilityLabel(Text(verbatim: "Grupo \(group.displayName)"))
                .accessibilityValue(Text(verbatim: countText))
                .accessibilityHint("Opciones del grupo")
            } else {
                content
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.leading, 26)
        .offset(y: 6)
    }

    private var emptyHint: String {
        if section.group != nil { return "Arrastra aquí cuadernos o crea uno nuevo" }
        return groups.isEmpty ? "Empieza tu primer cuaderno" : "Suelta aquí un cuaderno para sacarlo de su grupo"
    }

    private var countText: String {
        section.notebooks.count == 1 ? "1 cuaderno" : "\(section.notebooks.count) cuadernos"
    }
}

// MARK: - Lomo

@MainActor
private struct ShelfSpine: View {
    let notebook: Notebook
    let size: CGSize
    let groups: [NotebookGroup]
    let actions: LibraryActions
    @Binding var hoveredID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHovered: Bool { hoveredID == notebook.id }
    private var color: CoverColor { CoverColor.from(notebook.coverColorRaw) }

    var body: some View {
        Button {
            hoveredID = nil
            actions.open(notebook)
        } label: {
            NotebookSpineView(title: notebook.title, color: color, size: size)
        }
        .buttonStyle(PressableButtonStyle())
        // "Sacar" el cuaderno de la balda: sube y proyecta más sombra.
        .offset(y: isHovered && !reduceMotion ? -SpineHoverCard.lift : 0)
        .shadow(color: Theme.shadow.opacity(isHovered ? 0.9 : 0), radius: 8, x: 0, y: 6)
        .anchorPreference(key: SpineHoverKey.self, value: .bounds) { anchor in
            isHovered ? SpineHover(id: notebook.id, title: notebook.title, color: color,
                                   caption: notebook.libraryCaption, anchor: anchor) : nil
        }
        .onHover { inside in
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75)) {
                if inside {
                    hoveredID = notebook.id
                } else if hoveredID == notebook.id {
                    hoveredID = nil
                }
            }
        }
        .draggable(notebook.dragPayload) {
            NotebookSpineView(title: notebook.title, color: color, size: size)
        }
        .contextMenu {
            NotebookMenuItems(notebook: notebook, groups: groups, actions: actions)
        } preview: {
            NotebookCoverView(title: notebook.title, color: color,
                              size: CGSize(width: 260, height: 260 / Theme.coverAspect))
                .padding(12)
                .background(Theme.desk)
        }
        .zIndex(isHovered ? 1 : 0)
        .accessibilityLabel(Text(verbatim: "Cuaderno \(notebook.title.isEmpty ? "Sin título" : notebook.title)"))
        .accessibilityValue(Text(verbatim: notebook.libraryCaption))
        .accessibilityHint("Mantén pulsado para ver la portada y más opciones")
    }
}

// MARK: - Portada al pasar por encima

struct SpineHover {
    let id: UUID
    let title: String
    let color: CoverColor
    let caption: String
    let anchor: Anchor<CGRect>
}

struct SpineHoverKey: PreferenceKey {
    static let defaultValue: SpineHover? = nil
    static func reduce(value: inout SpineHover?, nextValue: () -> SpineHover?) {
        value = value ?? nextValue()
    }
}

/// Portada flotante sobre el lomo (o a su lado si arriba no hay sitio).
private struct SpineHoverCard: View {
    let hover: SpineHover
    let proxy: GeometryProxy

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cuánto sube el lomo al sacarlo.
    static let lift: CGFloat = 16
    private let coverWidth: CGFloat = 150
    private let captionHeight: CGFloat = 34
    private let gap: CGFloat = 12

    var body: some View {
        let cover = CGSize(width: coverWidth, height: coverWidth / Theme.coverAspect)
        let total = CGSize(width: cover.width, height: cover.height + captionHeight)
        VStack(spacing: 8) {
            NotebookCoverView(title: hover.title, color: hover.color, size: cover)
            Text(verbatim: hover.caption)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .floatingSurface(Capsule(style: .continuous))
        }
        .frame(width: total.width, height: total.height, alignment: .top)
        // Crece desde el lomo (la escala va antes de `.position` para anclarla a la tarjeta).
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86, anchor: .bottom)
        .position(center(for: total))
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { appeared = true }
        }
    }

    private func center(for total: CGSize) -> CGPoint {
        let rect = proxy[hover.anchor]
        let bounds = proxy.size
        var c = CGPoint(x: rect.midX, y: rect.minY - Self.lift - gap - total.height / 2)
        if c.y - total.height / 2 < 0 {
            // Sin sitio encima (primera balda): a un lado del lomo.
            c.y = rect.midY - Self.lift / 2
            let right = rect.maxX + gap + total.width / 2
            c.x = right + total.width / 2 <= bounds.width ? right : rect.minX - gap - total.width / 2
        }
        c.x = min(max(c.x, total.width / 2 + 8), max(total.width / 2 + 8, bounds.width - total.width / 2 - 8))
        c.y = min(max(c.y, total.height / 2), max(total.height / 2, bounds.height - total.height / 2))
        return c
    }
}
