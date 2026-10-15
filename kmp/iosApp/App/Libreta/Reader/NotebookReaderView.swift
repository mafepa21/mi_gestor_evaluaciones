import SwiftUI
import SwiftData
import PhotosUI

/// Cuaderno abierto. Vertical: una hoja por pantalla. Apaisado: doble página.
/// Se pasa de hoja con el dedo, curvando el papel (`PageCurlView`); se escribe con el Apple Pencil.
/// Pasar más allá de la última hoja añade hojas nuevas.
@MainActor
struct NotebookReaderView: View {
    @Bindable var notebook: Notebook
    var startPage: Int? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var isReady = false
    @State private var firstVisiblePage = 0
    @State private var focusedPage = 0
    @State private var isLandscape = false
    @State private var fingerDrawing = false
    @State private var tools = ToolPickerHolder()
    @State private var indexer = PageIndexer()

    // Modo objetos (imágenes, texto, pegatinas)
    @State private var objectMode = false
    @State private var selected: PageElement?
    @State private var photoItem: PhotosPickerItem?
    @State private var showStickers = false
    @State private var editingElement: PageElement?
    @State private var editingText = ""

    // Hojas auxiliares
    @State private var showOverview = false
    @State private var showSearch = false
    @State private var showExport = false

    private let logicalSize = PageGeometry.logicalSize

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let pageSize = Self.pageSize(in: geo.size, landscape: landscape)

            ZStack {
                Theme.readerBackground.ignoresSafeArea()
                SpreadBackdrop(color: CoverColor.from(notebook.coverColorRaw)).ignoresSafeArea()

                // Hasta tener tamaño real (el primer pase puede ser 0×0) no se monta el cuaderno.
                if isReady, pageSize.width >= 1, pageSize.height >= 1 {
                    book(landscape: landscape, pageSize: pageSize)
                }

                overlayControls
            }
            .onAppear {
                notebook.normalize()
                isLandscape = landscape
                let target = startPage ?? notebook.lastPageIndex
                goTo(target)
                indexer.indexPending(in: notebook)
                isReady = true
            }
            .onChange(of: landscape) { _, now in
                // `book` se recrea con el lomo nuevo y conserva `firstVisiblePage`.
                isLandscape = now
            }
        }
        .statusBarHidden()
        .onChange(of: photoItem) { _, item in Task { await addImage(from: item) } }
        .onChange(of: objectMode) { _, on in if !on { selected = nil } }
        .sheet(isPresented: $showOverview) {
            PageOverviewSheet(notebook: notebook, currentIndex: focusedPage,
                              onSelect: { goTo($0) }, onChanged: { pagesChanged() })
        }
        .sheet(isPresented: $showSearch) {
            NotebookSearchSheet(notebook: notebook, onSelect: { goTo($0) })
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(scope: .notebook(notebook, currentPage: page(at: focusedPage)))
        }
        .alert("Texto", isPresented: Binding(get: { editingElement != nil },
                                             set: { if !$0 { editingElement = nil } })) {
            TextField("Escribe aquí", text: $editingText, axis: .vertical)
            Button("Guardar") {
                if let e = editingElement, let p = e.page {
                    e.text = editingText
                    indexer.schedule(p)
                }
                editingElement = nil
            }
            Button("Cancelar", role: .cancel) { editingElement = nil }
        }
    }

    // MARK: - Hojas

    /// Tamaño de una hoja en pantalla. Siempre finito y >= 0 (en el primer pase el
    /// GeometryReader puede medir 0×0 y las restas saldrían negativas).
    nonisolated private static func pageSize(in size: CGSize, landscape: Bool) -> CGSize {
        let inset = Theme.backdropInset + 10
        // Deja sitio a las barras flotantes (arriba) sin que tapen el papel.
        let availW = max(0, size.width - inset * 2)
        let availH = max(0, size.height - inset * 2 - 72)
        let aspect = max(Theme.pageAspect, 0.01)
        let raw = min(landscape ? availW / 2 : availW, availH * aspect)
        guard raw.isFinite, raw > 0 else { return .zero }
        let w = raw.rounded(.down)
        return CGSize(width: w, height: (w / aspect).rounded(.down))
    }

    /// El cuaderno abierto: pila de hojas fija debajo y, encima, las hojas que se curvan.
    private func book(landscape: Bool, pageSize: CGSize) -> some View {
        // Se leen aquí (en `body`) para que cambiar la plantilla de una hoja, desde el
        // menú o desde las miniaturas, refresque las hojas visibles.
        _ = notebook.sortedPages.map(\.templateRaw)
        return ZStack {
            pageStack(landscape: landscape, pageSize: pageSize)
            PageCurlView(
                pageIDs: notebook.sortedPages.map(\.id),
                currentPage: firstVisiblePage,
                isLandscape: landscape,
                gesturesEnabled: !(fingerDrawing || objectMode),
                content: { index, side in
                    AnyView(pageView(at: index, pages: notebook.sortedPages, side: side, size: pageSize))
                },
                onPageChange: { pageTurned(to: $0) },
                onAppendPages: { appendPages() }
            )
            .frame(width: landscape ? pageSize.width * 2 : pageSize.width, height: pageSize.height)
            // El lomo de UIPageViewController no cambia en caliente: se reconstruye al girar.
            .id(landscape)
        }
    }

    /// Canto de hojas apiladas y sombra, fijos: no se curvan con la hoja.
    private func pageStack(landscape: Bool, pageSize: CGSize) -> some View {
        HStack(spacing: 0) {
            if landscape {
                let left = firstVisiblePage - firstVisiblePage % 2
                PageSheet(side: .left, style: style(at: left)) { Color.clear }
                    .frame(width: pageSize.width, height: pageSize.height)
                PageSheet(side: .right, style: style(at: left + 1)) { Color.clear }
                    .frame(width: pageSize.width, height: pageSize.height)
            } else {
                PageSheet(side: .single, style: style(at: firstVisiblePage)) { Color.clear }
                    .frame(width: pageSize.width, height: pageSize.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pageView(at index: Int, pages: [Page], side: PageSide, size: CGSize) -> some View {
        if index < pages.count {
            let page = pages[index]
            PageSheet(side: side, style: page.style(in: notebook), showsStack: false) {
                ZStack(alignment: .topLeading) {
                    PageElementsLayer(page: page, interactive: objectMode, selected: $selected,
                                      onEditText: { beginEditing($0) })
                    DrawingCanvas(page: page,
                                  fingerDrawing: fingerDrawing,
                                  isPrimary: index == focusedPage,
                                  objectMode: objectMode,
                                  tools: tools,
                                  onEdit: { pageEdited(page) })
                        .frame(width: logicalSize.width, height: logicalSize.height)
                        .allowsHitTesting(!objectMode)
                }
                .frame(width: logicalSize.width, height: logicalSize.height)
                .scaleEffect(size.width / logicalSize.width, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    focusedPage = index
                    if objectMode { selected = nil }
                })
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                PageNumberLabel(number: index + 1,
                                alignment: side == .left ? .leading : (side == .right ? .trailing : .center))
                    .padding(.bottom, 10)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: side == .left ? .topLeading : .topTrailing) {
                if page.isBookmarked {
                    BookmarkRibbon()
                        .frame(width: max(14, size.width * 0.03), height: max(44, size.width * 0.095))
                        .offset(y: -6)
                        .padding(.horizontal, size.width * 0.06)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { page.isBookmarked = false } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Quita el marcapáginas")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } else {
            // Hoja provisional al pasar más allá del final: se crea al completar el giro
            // (sin plantilla propia: papel del cuaderno).
            PageSheet(side: side, style: notebook.paperStyle, showsStack: false) { Color.clear }
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottom) {
                    PageNumberLabel(number: index + 1,
                                    alignment: side == .left ? .leading : (side == .right ? .trailing : .center))
                        .padding(.bottom, 10)
                        .padding(.horizontal, 20)
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: - Controles

    private var overlayControls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if objectMode {
                objectBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if fingerDrawing || objectMode {
                HStack {
                    stepButton("chevron.left", label: "Hoja anterior") { step(-1) }
                    Spacer()
                    stepButton("chevron.right", label: "Hoja siguiente") { step(1) }
                }
                .padding(.horizontal, 20).padding(.bottom, 14)
                .allowsHitTesting(true)
            }
        }
    }

    private var topBar: some View {
        let isBookmarked = page(at: focusedPage)?.isBookmarked == true
        return HStack(alignment: .center, spacing: 12) {
            FloatingBar {
                Button { dismiss() } label: { Label("Estantería", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarLabelButtonStyle())
                    .accessibilityLabel("Volver a la estantería")
                    .keyboardShortcut(.cancelAction)
                Text(notebook.title.isEmpty ? "Sin título" : notebook.title)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.trailing, 14)
            }
            .frame(maxWidth: 380, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            FloatingBar {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Buscar")
                Button { showOverview = true } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("Ver hojas")
                Button { withAnimation(.easeOut(duration: 0.2)) { toggleBookmark() } } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(ToolbarIconButtonStyle(isActive: isBookmarked))
                .accessibilityLabel("Marcapáginas")
                FloatingBarDivider()
                Button { withAnimation(.spring(duration: 0.3)) { objectMode.toggle() } } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(ToolbarIconButtonStyle(isActive: objectMode))
                .accessibilityLabel("Imágenes, texto y pegatinas")
                Menu {
                    Toggle("Dibujar también con el dedo", systemImage: "hand.draw", isOn: $fingerDrawing)
                    Button("Añadir hoja al final", systemImage: "plus.square") { addPageAtEnd() }
                    if let current = page(at: focusedPage) {
                        PageTemplateMenu(page: current, notebookStyle: notebook.paperStyle)
                    }
                    Divider()
                    Button("Exportar / compartir…", systemImage: "square.and.arrow.up") { showExport = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .toolbarIconChrome(isActive: fingerDrawing)
                }
                .accessibilityLabel("Más opciones")
            }
        }
        .buttonStyle(ToolbarIconButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var objectBar: some View {
        FloatingBar(spacing: 2) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Imagen", systemImage: "photo")
            }
            Button { addText() } label: { Label("Texto", systemImage: "textformat") }
            Button { showStickers = true } label: { Label("Pegatina", systemImage: "face.smiling") }
                .popover(isPresented: $showStickers) { StickerPicker { addSticker($0); showStickers = false } }

            if let e = selected {
                FloatingBarDivider()
                Group {
                    if e.kind == .text {
                        Button { beginEditing(e) } label: { Image(systemName: "pencil") }
                            .accessibilityLabel("Editar texto")
                        HStack(spacing: 0) {
                            ForEach(PageElement.colorChoices, id: \.self) { c in
                                Button { e.colorRaw = c } label: {
                                    ColorSwatch(color: PageElement.textColor(for: c),
                                                isSelected: e.colorRaw == c, diameter: 20)
                                }
                                .buttonStyle(PressableButtonStyle(scale: 0.9))
                                .accessibilityLabel(Self.colorName(c))
                            }
                        }
                        .padding(.horizontal, 4)
                        Button { e.fontSize = max(14, e.fontSize - 4) } label: { Image(systemName: "textformat.size.smaller") }
                            .accessibilityLabel("Texto más pequeño")
                        Button { e.fontSize = min(120, e.fontSize + 4) } label: { Image(systemName: "textformat.size.larger") }
                            .accessibilityLabel("Texto más grande")
                        FloatingBarDivider()
                    }
                    Button { bringToFront(e) } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                        .accessibilityLabel("Traer al frente")
                    Button { duplicate(e) } label: { Image(systemName: "plus.square.on.square") }
                        .accessibilityLabel("Duplicar")
                    Button(role: .destructive) { delete(e) } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.ribbon)
                    }
                    .accessibilityLabel("Eliminar")
                }
                .buttonStyle(ToolbarIconButtonStyle())
            }
            FloatingBarDivider()
            Button("Listo") { withAnimation(.spring(duration: 0.3)) { objectMode = false } }
                .buttonStyle(ToolbarPrimaryButtonStyle())
        }
        .buttonStyle(ToolbarLabelButtonStyle())
        .animation(.easeOut(duration: 0.2), value: selected?.id)
        .padding(.bottom, 12)
    }

    private static func colorName(_ raw: String) -> String {
        switch raw {
        case "red": "Rojo"
        case "blue": "Azul"
        case "green": "Verde"
        default: "Tinta"
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(FloatingCircleButtonStyle())
            .accessibilityLabel(label)
    }

    // MARK: - Lógica de hojas

    private func page(at index: Int) -> Page? {
        notebook.sortedPages.first { $0.index == index }
    }

    /// Papel efectivo de la hoja `index` (papel del cuaderno si aún no existe).
    private func style(at index: Int) -> PaperStyle {
        page(at: index)?.style(in: notebook) ?? notebook.paperStyle
    }

    /// Flechas (dibujar con el dedo / modo Objetos): pasan hoja con la misma curvatura.
    /// Desde la última hoja, crea hojas nuevas.
    private func step(_ delta: Int) {
        let perSpread = isLandscape ? 2 : 1
        let current = isLandscape ? firstVisiblePage - firstVisiblePage % 2 : firstVisiblePage
        let next = current + delta * perSpread
        guard next >= 0 else { return }
        if next >= notebook.pageList.count { appendPages() }
        goTo(next)
    }

    /// Salta a una hoja; `PageCurlView` la muestra con un giro de papel.
    private func goTo(_ index: Int) {
        let clamped = min(max(index, 0), max(notebook.pageList.count - 1, 0))
        firstVisiblePage = clamped
        focusedPage = clamped
        notebook.lastPageIndex = clamped
        selected = nil
    }

    /// Paso de hoja hecho con el dedo.
    private func pageTurned(to first: Int) {
        firstVisiblePage = first
        focusedPage = first
        notebook.lastPageIndex = first
        selected = nil
    }

    /// Añade hojas al final (`normalize` deja el total par y una en blanco al final).
    private func appendPages() {
        notebook.insertPage(after: notebook.pageList.count - 1)
    }

    private func pagesChanged() {
        goTo(min(focusedPage, notebook.pageList.count - 1))
    }

    private func addPageAtEnd() {
        let old = notebook.pageList.count
        appendPages()
        goTo(old)
    }

    private func toggleBookmark() {
        page(at: focusedPage)?.isBookmarked.toggle()
    }

    /// Siempre queda una hoja en blanco al final; el texto se reindexa para la búsqueda.
    private func pageEdited(_ page: Page) {
        notebook.normalize()
        indexer.schedule(page)
    }

    // MARK: - Objetos

    private func attach(_ element: PageElement) {
        guard let target = page(at: focusedPage) else { return }
        element.order = (target.elementList.last?.order ?? 0) + 1
        element.x = logicalSize.width / 2
        element.y = logicalSize.height / 2
        target.elements = (target.elements ?? []) + [element]
        notebook.normalize()
        selected = element
    }

    private func addText() {
        let e = PageElement(kind: .text)
        e.text = "Texto"
        e.width = 420
        e.fontSize = 40
        attach(e)
        beginEditing(e)
    }

    private func addSticker(_ emoji: String) {
        let e = PageElement(kind: .sticker)
        e.text = emoji
        e.width = 140; e.height = 140; e.fontSize = 110
        attach(e)
    }

    private func addImage(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        photoItem = nil
        // Reduce el tamaño para no inflar el cuaderno.
        let maxSide: CGFloat = 1600
        let ratio = min(1, maxSide / max(ui.size.width, ui.size.height))
        let target = CGSize(width: ui.size.width * ratio, height: ui.size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: target, format: format)
            .jpegData(withCompressionQuality: 0.85) { _ in ui.draw(in: CGRect(origin: .zero, size: target)) }

        let e = PageElement(kind: .image)
        e.imageData = jpeg
        let w: Double = 420
        e.width = w
        e.height = w * target.height / target.width
        attach(e)
    }

    private func beginEditing(_ e: PageElement) {
        editingText = e.text
        editingElement = e
    }

    private func bringToFront(_ e: PageElement) {
        e.order = (e.page?.elementList.last?.order ?? 0) + 1
    }

    private func duplicate(_ e: PageElement) {
        let c = PageElement(kind: e.kind)
        c.text = e.text; c.fontSize = e.fontSize; c.colorRaw = e.colorRaw
        c.width = e.width; c.height = e.height; c.imageData = e.imageData
        c.rotation = e.rotation; c.scale = e.scale
        attach(c)
        c.x = e.x + 40; c.y = e.y + 40
    }

    private func delete(_ e: PageElement) {
        let page = e.page
        selected = nil
        e.modelContext?.delete(e)
        if let page { indexer.schedule(page) }
    }
}

private struct StickerPicker: View {
    let onPick: (String) -> Void
    private let stickers = ["⭐️","🌟","✨","❤️","💡","✅","❗️","❓","📌","📎","🔥","🎯","🏆","👍","👀","🙂",
                            "📚","✏️","📝","📅","⏰","💬","🔔","🌱","☀️","🌈","🎵","🎨","🧠","🚀","⚠️","➡️"]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pegatinas")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.paperInk)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 6), count: 6), spacing: 6) {
                    ForEach(stickers, id: \.self) { s in
                        Button { onPick(s) } label: {
                            Text(s).font(.system(size: 32))
                                .frame(width: 52, height: 52)
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(StickerCellStyle())
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .frame(width: 380, height: 330)
        .presentationBackground(Theme.paper)
    }
}

private struct StickerCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.paperInk.opacity(configuration.isPressed ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
