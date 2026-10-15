import SwiftUI

/// Contenido visual de un objeto (sin gestos), compartido por la vista editable y el renderizado.
struct ElementContent: View {
    let element: PageElement

    private static let imageCache = NSCache<NSString, UIImage>()

    private var image: UIImage? {
        guard let data = element.imageData else { return nil }
        let key = "\(element.id)-\(data.count)" as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let ui = UIImage(data: data) else { return nil }
        Self.imageCache.setObject(ui, forKey: key)
        return ui
    }

    var body: some View {
        switch element.kind {
        case .image:
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: element.width, height: element.height)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
        case .text:
            Text(element.text)
                .font(.system(size: element.fontSize, design: .serif))
                .foregroundStyle(element.textColor)
                .multilineTextAlignment(.leading)
                .frame(width: element.width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        case .sticker:
            Text(element.text)
                .font(.system(size: element.fontSize))
                .minimumScaleFactor(0.1)
                .frame(width: element.width, height: element.height)
        }
    }
}

private extension View {
    /// Coloca el centro del objeto en (x, y) dentro de una capa centrada del tamaño de la hoja.
    func placed(_ e: PageElement, dx: Double = 0, dy: Double = 0,
                scale: Double = 1, angle: Double = 0) -> some View {
        let size = PageGeometry.logicalSize
        return self
            .scaleEffect(e.scale * scale)
            .rotationEffect(.radians(e.rotation + angle))
            .offset(x: e.x + dx - size.width / 2, y: e.y + dy - size.height / 2)
    }
}

/// Versión no interactiva (miniaturas, PDF).
struct StaticElementsLayer: View {
    let page: Page
    var body: some View {
        ZStack {
            ForEach(page.elementList) { e in
                ElementContent(element: e).placed(e)
            }
        }
        .frame(width: PageGeometry.logicalSize.width, height: PageGeometry.logicalSize.height)
    }
}

/// Capa editable: solo recibe toques cuando `interactive` (modo Objetos).
struct PageElementsLayer: View {
    let page: Page
    let interactive: Bool
    @Binding var selected: PageElement?
    let onEditText: (PageElement) -> Void

    var body: some View {
        ZStack {
            ForEach(page.elementList) { e in
                InteractiveElement(element: e,
                                   isSelected: selected?.id == e.id,
                                   showsHint: interactive,
                                   onSelect: { selected = e },
                                   onEditText: { onEditText(e) })
            }
        }
        .frame(width: PageGeometry.logicalSize.width, height: PageGeometry.logicalSize.height)
        .coordinateSpace(.named("pageLayer"))
        .allowsHitTesting(interactive)
    }
}

private struct InteractiveElement: View {
    @Bindable var element: PageElement
    let isSelected: Bool
    let showsHint: Bool
    let onSelect: () -> Void
    let onEditText: () -> Void

    @State private var drag: CGSize = .zero
    @State private var pinch: Double = 1
    @State private var twist: Angle = .zero

    var body: some View {
        ElementContent(element: element)
            .overlay {
                if isSelected {
                    SelectionOutline(scale: element.scale * pinch)
                } else if showsHint {
                    SelectableHint(scale: element.scale * pinch)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .placed(element, dx: drag.width, dy: drag.height, scale: pinch, angle: twist.radians)
            .onTapGesture(count: 2) { if element.kind == .text { onSelect(); onEditText() } }
            .onTapGesture { onSelect() }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("pageLayer"))
                    .onChanged { v in
                        if !isSelected { onSelect() }
                        drag = v.translation
                    }
                    .onEnded { v in
                        element.x += v.translation.width
                        element.y += v.translation.height
                        drag = .zero
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { pinch = Double($0.magnification) }
                    .onEnded { element.scale = min(max(element.scale * Double($0.magnification), 0.2), 6); pinch = 1 }
            )
            .simultaneousGesture(
                RotateGesture()
                    .onChanged { twist = $0.rotation }
                    .onEnded { element.rotation += $0.rotation.radians; twist = .zero }
            )
    }
}
