import SwiftUI
import PencilKit

/// Convierte hojas en imágenes (miniaturas, reconocimiento de texto) y PDF.
@MainActor
enum PageRenderer {
    private static let size = PageGeometry.logicalSize

    static func drawing(of page: Page) -> PKDrawing? {
        guard !page.drawingData.isEmpty else { return nil }
        return try? PKDrawing(data: page.drawingData)
    }

    /// Tinta con fondo transparente, siempre en modo claro.
    static func inkImage(of page: Page, scale: CGFloat) -> UIImage? {
        guard let d = drawing(of: page), !d.bounds.isEmpty else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = d.image(from: CGRect(origin: .zero, size: size), scale: scale)
        }
        return image
    }

    /// Tinta sobre blanco: la mejor entrada para Vision.
    static func inkOnWhite(of page: Page) -> UIImage? {
        guard let ink = inkImage(of: page, scale: 1.5) else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let px = CGSize(width: size.width * 1.5, height: size.height * 1.5)
        return UIGraphicsImageRenderer(size: px, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: px))
            ink.draw(in: CGRect(origin: .zero, size: px))
        }
    }

    static func snapshotView(_ page: Page, style: PaperStyle, inkScale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            PaperBackground(style: style)
            StaticElementsLayer(page: page)
            if let ink = inkImage(of: page, scale: inkScale) {
                Image(uiImage: ink).resizable().frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    static func image(of page: Page, style: PaperStyle, pixelWidth: CGFloat) -> UIImage? {
        let scale = pixelWidth / size.width
        let renderer = ImageRenderer(content: snapshotView(page, style: style, inkScale: max(scale, 1)))
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Escribe un PDF (una hoja por página, cada una con su plantilla) y devuelve su URL temporal.
    static func writePDF(pages: [Page], notebook: Notebook?, name: String) async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFileName(name)).appendingPathExtension("pdf")
        var box = CGRect(origin: .zero, size: size)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for page in pages {
            pdf.beginPDFPage(nil)
            let style = page.style(in: notebook ?? page.notebook)
            let renderer = ImageRenderer(content: snapshotView(page, style: style, inkScale: 2))
            renderer.render { _, draw in draw(pdf) }
            pdf.endPDFPage()
            await Task.yield()
        }
        pdf.closePDF()
        return url
    }

    nonisolated static func safeFileName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Libreta" : cleaned
    }
}

/// Miniatura de una hoja con caché. `style` es el papel efectivo de esa hoja
/// (`page.style(in: notebook)`).
struct PageThumbnailView: View {
    let page: Page
    let style: PaperStyle
    let width: CGFloat

    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    private var signature: String {
        let elems = page.elementList.reduce(0.0) { $0 + $1.x + $1.y + $1.scale + $1.rotation + Double($1.text.count) }
        return "\(page.id)-\(page.drawingData.count)-\(page.elementList.count)-\(elems)-\(style.rawValue)-\(Int(width))"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                PaperBackground(style: style)
            }
        }
        .frame(width: width, height: width / Theme.pageAspect)
        .clipShape(RoundedRectangle(cornerRadius: Theme.pageCornerRadius * 0.75, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pageCornerRadius * 0.75, style: .continuous)
                .strokeBorder(Theme.paperEdgeLine.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: Theme.shadow, radius: max(2, width * 0.03), x: 0, y: max(1, width * 0.012))
        .task(id: signature) {
            let key = signature as NSString
            if let cached = Self.cache.object(forKey: key) { image = cached; return }
            if let rendered = PageRenderer.image(of: page, style: style, pixelWidth: width * 2) {
                Self.cache.setObject(rendered, forKey: key)
                image = rendered
            }
        }
    }
}
