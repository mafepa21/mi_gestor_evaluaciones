import CoreGraphics
import Foundation
import SwiftUI

/// Exporta el horario a PDF rasterizando la propia vista SwiftUI con
/// `ImageRenderer`.
///
/// Deliberadamente NO reutiliza `PlannerReportPDFRenderer`: aquel pagina un
/// `NSAttributedString` con `CTFramesetter`, que es texto corrido y no sabe
/// dibujar una tabla. Con `ImageRenderer` el PDF es literalmente la rejilla que
/// se ve en pantalla, así que no puede desincronizarse de ella.
@MainActor
enum ScheduleGridPDFRenderer {
    /// A4 apaisado a 72 dpi: un horario es más ancho que alto.
    static let pageSize = CGSize(width: 842, height: 595)
    static let margin: CGFloat = 36

    static func render(page: some View) -> Data? {
        let renderer = ImageRenderer(content: page)
        // Se propone el ancho útil y se deja crecer el alto: la rejilla decide
        // cuánto ocupa y después se escala si no cabe.
        renderer.proposedSize = ProposedViewSize(width: pageSize.width - margin * 2, height: nil)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var rendered = false
        renderer.render { size, draw in
            guard size.width > 0, size.height > 0 else { return }
            context.beginPDFPage(nil)

            // Escala solo hacia abajo: un horario corto no se agranda hasta
            // llenar la hoja, que quedaría desproporcionado.
            let availableHeight = pageSize.height - margin * 2
            let scale = min(1, availableHeight / size.height)

            // `draw` dibuja la vista con su origen en el origen del contexto y
            // el PDF tiene el origen abajo a la izquierda: hay que subir la
            // vista por su alto ya escalado.
            context.translateBy(x: margin, y: pageSize.height - margin - size.height * scale)
            context.scaleBy(x: scale, y: scale)
            draw(context)

            context.endPDFPage()
            rendered = true
        }

        guard rendered else { return nil }
        context.closePDF()
        return data as Data
    }

    /// Escribe el PDF en un fichero temporal único y devuelve su URL, lista para
    /// `ShareLink`. Mismo patrón que `PlannerReportPDFRenderer.writeToTemporaryFile`.
    static func writeToTemporaryFile(page: some View, suggestedName: String) -> URL? {
        guard let data = render(page: page) else { return nil }
        let safeName = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "horario" : safeName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
