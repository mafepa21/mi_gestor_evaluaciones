import SwiftUI

/// Montón desplegado: los cuadernos salen del montón (misma posición, giro y tamaño)
/// y se reparten en una rejilla centrada sobre la mesa difuminada. Cada uno lleva su
/// propio muelle con un pequeño retraso, así se "reparten" uno tras otro.
///
/// Tocar una portada la abre; tocar fuera o «×» pliega el montón. Con Reducir
/// movimiento no vuelan: la rejilla aparece y desaparece con un fundido.
@MainActor
struct PileFanView: View {
    let section: LibrarySection
    /// Marco del montón en el espacio de esta vista.
    let origin: CGRect
    /// Tamaño de las portadas en el montón.
    let pileCoverSize: CGSize
    let containerSize: CGSize
    let groups: [NotebookGroup]
    let actions: LibraryActions
    let onDismiss: () -> Void

    @State private var fanned = false
    @State private var isClosing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "fan-top"

    private enum Item: Identifiable {
        case notebook(Notebook)
        case add

        var id: String {
            switch self {
            case .notebook(let nb): nb.id.uuidString
            case .add: "add"
            }
        }
    }

    /// Los cuadernos (en el orden del montón: el de arriba primero) y el hueco "Nuevo cuaderno".
    private var items: [Item] { section.notebooks.map { Item.notebook($0) } + [Item.add] }

    private var countText: String {
        section.notebooks.count == 1 ? "1 cuaderno" : "\(section.notebooks.count) cuadernos"
    }

    var body: some View {
        let layout = FanLayout(count: items.count, container: containerSize)
        ZStack(alignment: .top) {
            // Velo: la mesa se difumina y se atenúa.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay { Theme.scrim }
                .opacity(fanned ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: fanned)
                .accessibilityHidden(true)

            ScrollViewReader { reader in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // Tocar fuera de las portadas pliega el montón.
                        Color.clear
                            .frame(width: layout.width, height: layout.contentHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { close(reader) }
                            .id(Self.topID)
                            .accessibilityHidden(true)

                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemView(item, index: index, layout: layout)
                        }
                    }
                    .frame(width: layout.width, height: layout.contentHeight)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(!fanned)
                .overlay(alignment: .top) { titleBar(reader) }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .allowsHitTesting(!isClosing)
        .onAppear {
            // Un fotograma idéntico al montón y, después, a repartir.
            DispatchQueue.main.async { fanned = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close(nil) }
    }

    // MARK: Piezas

    @ViewBuilder
    private func itemView(_ item: Item, index: Int, layout: FanLayout) -> some View {
        let collapsed = !fanned && !reduceMotion
        let pileScale = pileCoverSize.width / max(1, layout.coverSize.width)
        let pileCenter = CGPoint(x: origin.midX, y: origin.midY)
        let target = layout.center(of: index)
        switch item {
        case .notebook(let notebook):
            let jitter = PileJitter(id: notebook.id, depth: index, width: pileCoverSize.width)
            let inPile = CGPoint(x: pileCenter.x + jitter.offset.width, y: pileCenter.y + jitter.offset.height)
            coverButton(notebook, layout: layout)
                .scaleEffect(collapsed ? pileScale : 1)
                .rotationEffect(.degrees(collapsed ? jitter.rotation : jitter.fanRotation))
                .position(collapsed ? inPile : target)
                // Los que no se veían en el montón aparecen al salir.
                .opacity(reduceMotion ? (fanned ? 1 : 0) : (collapsed && index >= 4 ? 0 : 1))
                .zIndex(Double(items.count - index))
                .animation(animation(for: index), value: fanned)
        case .add:
            Button {
                onDismiss()
                actions.newNotebook(section.group)
            } label: {
                NewNotebookCoverView(size: layout.coverSize)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Nuevo cuaderno en este grupo")
            .scaleEffect(collapsed ? pileScale * 0.8 : 1)
            .position(collapsed ? pileCenter : target)
            .opacity(fanned ? 1 : 0)
            .animation(animation(for: index), value: fanned)
        }
    }

    private func coverButton(_ notebook: Notebook, layout: FanLayout) -> some View {
        Button {
            onDismiss()
            actions.open(notebook)
        } label: {
            NotebookCoverView(title: notebook.title,
                              color: CoverColor.from(notebook.coverColorRaw),
                              size: layout.coverSize)
        }
        .buttonStyle(PressableButtonStyle())
        .overlay(alignment: .bottom) {
            Text(notebook.libraryCaption)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.ink.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .offset(y: 26)
                .opacity(fanned ? 1 : 0)
                .accessibilityHidden(true)
        }
        .contextMenu {
            NotebookMenuItems(notebook: notebook, groups: groups, actions: actions)
        }
        .accessibilityValue(Text(verbatim: notebook.libraryCaption))
    }

    private func titleBar(_ reader: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: countText)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            FloatingBar {
                Button {
                    onDismiss()
                    actions.newNotebook(section.group)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuevo cuaderno en este grupo")
                if let group = section.group {
                    Menu {
                        GroupMenuItems(group: group, groups: groups, actions: actions,
                                       moveLabels: ("Mover antes", "Mover después"))
                    } label: {
                        Image(systemName: "ellipsis").toolbarIconChrome()
                    }
                    .accessibilityLabel("Opciones del grupo")
                }
                FloatingBarDivider()
                Button { close(reader) } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cerrar")
            }
            .buttonStyle(ToolbarIconButtonStyle())
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .opacity(fanned ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: fanned)
    }

    // MARK: Animación

    private func animation(for index: Int) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
        // Al abrir, uno tras otro; al cerrar, todos a la vez.
        let stagger = fanned ? Double(min(index, 10)) * 0.028 : 0
        return .spring(response: 0.5, dampingFraction: 0.8).delay(stagger)
    }

    private func close(_ reader: ScrollViewProxy?) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeOut(duration: 0.25)) { reader?.scrollTo(Self.topID, anchor: .top) }
        fanned = false
        let delay: Duration = .milliseconds(reduceMotion ? 220 : 500)
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            onDismiss()
        }
    }
}

/// Rejilla centrada del montón desplegado.
private struct FanLayout {
    static let margin: CGFloat = 40
    static let titleSpace: CGFloat = 112
    static let maxCoverWidth: CGFloat = 176
    static let hSpacing: CGFloat = 32
    /// Incluye el pie de foto bajo cada portada.
    static let vSpacing: CGFloat = 58

    let count: Int
    let width: CGFloat
    let columns: Int
    let coverSize: CGSize
    let top: CGFloat
    let contentHeight: CGFloat

    init(count: Int, container: CGSize) {
        let n = max(1, count)
        let fit = Int((container.width - Self.margin * 2 + Self.hSpacing) / (Self.maxCoverWidth + Self.hSpacing))
        let cols = max(1, min(n, max(2, fit)))
        let w = min(Self.maxCoverWidth,
                    (container.width - Self.margin * 2 - CGFloat(cols - 1) * Self.hSpacing) / CGFloat(cols))
        let size = CGSize(width: max(60, w.rounded()), height: max(60, w.rounded()) / Theme.coverAspect)
        let rows = (n + cols - 1) / cols
        let gridHeight = CGFloat(rows) * size.height + CGFloat(rows - 1) * Self.vSpacing
        let top = max(Self.titleSpace, (container.height - gridHeight) / 2)

        self.count = n
        self.width = container.width
        self.columns = cols
        self.coverSize = size
        self.top = top
        self.contentHeight = max(container.height, top + gridHeight + Self.vSpacing + 24)
    }

    func center(of index: Int) -> CGPoint {
        let row = index / columns
        let col = index % columns
        let inRow = min(columns, count - row * columns)
        let rowWidth = CGFloat(inRow) * coverSize.width + CGFloat(max(0, inRow - 1)) * Self.hSpacing
        let startX = (width - rowWidth) / 2
        return CGPoint(x: startX + CGFloat(col) * (coverSize.width + Self.hSpacing) + coverSize.width / 2,
                       y: top + CGFloat(row) * (coverSize.height + Self.vSpacing) + coverSize.height / 2)
    }
}
