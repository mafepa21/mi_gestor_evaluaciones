import CoreGraphics
import CoreText
import Foundation

/// Renderiza un `NSAttributedString` ya maquetado como PDF paginado usando
/// Core Text + Core Graphics puro (sin AppKit ni UIKit), para que el mismo
/// código sirva igual en iPadOS y en Mac. Patrón estándar de Apple para
/// paginar texto con `CTFramesetter` sobre un `CGContext` de PDF.
enum PlannerReportPDFRenderer {
    /// A4 a 72dpi.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 48

    static func render(_ attributedBody: NSAttributedString) -> Data? {
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { return nil }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )
        let path = CGPath(rect: textRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedBody as CFAttributedString)
        let totalLength = attributedBody.length

        var location = 0
        var pageCount = 0
        // Límite de seguridad: un informe de un curso entero no debería superar esto.
        while location < totalLength && pageCount < 200 {
            context.beginPDFPage(nil)

            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(location, 0), path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()

            if visibleRange.length <= 0 {
                // No cupo ni una línea en la página (contenido demasiado ancho/alto):
                // evita un bucle infinito y corta el informe aquí.
                break
            }
            location += visibleRange.length
            pageCount += 1
        }

        context.closePDF()
        return data as Data
    }

    /// Escribe el PDF a un fichero temporal único y devuelve su URL, lista para
    /// `ShareLink`. El llamador es responsable de limpiarlo cuando ya no haga falta.
    static func writeToTemporaryFile(_ attributedBody: NSAttributedString, suggestedName: String) -> URL? {
        guard let data = render(attributedBody) else { return nil }
        let safeName = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "informe-planner" : safeName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
