import CoreGraphics
import Foundation
import SwiftUI

/// Color corporativo de la Fundación Educativa Madre Micaela (oliva/dorado del
/// logo). Se usa como acento del acta impresa.
private extension Color {
    static let actaBrand = Color(red: 0.541, green: 0.529, blue: 0.204) // ~#8A872E
    static let actaInk = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let actaMuted = Color(red: 0.42, green: 0.42, blue: 0.45)
    static let actaHairline = Color(red: 0.85, green: 0.85, blue: 0.82)
    static let actaDanger = Color(red: 0.78, green: 0.16, blue: 0.16)
    static let actaWarning = Color(red: 0.72, green: 0.45, blue: 0.05)
    static let actaDone = Color(red: 0.16, green: 0.5, blue: 0.24)
}

/// Página A4 del acta de una reunión, pensada para imprimir. Es una vista
/// autónoma (sin EnvironmentObject) para poder rasterizarla con `ImageRenderer`
/// fuera de la jerarquía de la app.
struct MeetingActaPage: View {
    let meeting: MeetingRow
    /// Encabezado institucional; por defecto, el nombre de la fundación.
    var centerName: String = "Fundación Educativa Madre Micaela"

    private var generatedOn: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Rectangle().fill(Color.actaBrand).frame(height: 2)

            metadata

            if !meeting.summary.isEmpty {
                sectionTitle("Acta de la reunión")
                Text(meeting.summary)
                    .font(.system(size: 11.5))
                    .foregroundColor(.actaInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sectionTitle("Acuerdos")
            if meeting.agreements.isEmpty {
                Text("No se registraron acuerdos en esta reunión.")
                    .font(.system(size: 11))
                    .foregroundColor(.actaMuted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(meeting.agreements.enumerated()), id: \.element.id) { index, agreement in
                        agreementRow(index: index + 1, agreement: agreement)
                    }
                }
            }

            Spacer(minLength: 12)
            footer
        }
        .padding(4)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("FundacionMicaelaLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text(centerName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.actaBrand)
                    .tracking(1.2)
                Text(meeting.displayTitle)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.actaInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(meeting.type.displayName) · \(meeting.dateDisplay)\(meeting.isClosed ? " · Reunión cerrada" : "")")
                    .font(.system(size: 11.5))
                    .foregroundColor(.actaMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow(label: "Tipo", value: meeting.type.displayName)
            metadataRow(label: "Fecha", value: meeting.dateDisplay)
            if !meeting.location.isEmpty {
                metadataRow(label: "Lugar", value: meeting.location)
            }
            if !meeting.attendees.isEmpty {
                metadataRow(label: "Asistentes", value: meeting.attendees)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.actaBrand.opacity(0.06))
        )
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.actaMuted)
                .tracking(0.8)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundColor(.actaInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5, weight: .bold))
            .foregroundColor(.actaBrand)
    }

    private func agreementRow(index: Int, agreement: MeetingAgreementRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(agreement.isDone ? Color.actaDone : Color.actaBrand))

            VStack(alignment: .leading, spacing: 3) {
                Text(agreement.description)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.actaInk)
                    .strikethrough(agreement.isDone, color: .actaMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if !agreement.responsible.isEmpty {
                        label("Responsable", agreement.responsible)
                    }
                    if let due = agreement.dueDisplay {
                        label("Fecha límite", due)
                    }
                    statusChip(agreement)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.actaBrand.opacity(0.035))
        )
    }

    private func label(_ caption: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(caption):")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.actaMuted)
            Text(value)
                .font(.system(size: 9.5))
                .foregroundColor(.actaInk)
        }
    }

    @ViewBuilder
    private func statusChip(_ agreement: MeetingAgreementRow) -> some View {
        let (text, color): (String, Color) = {
            if agreement.isDone { return ("Cumplido", .actaDone) }
            switch agreement.reviewStatus {
            case .overdue: return ("Vencido", .actaDanger)
            case .dueSoon: return ("Próximo", .actaWarning)
            case .none: return ("Pendiente", .actaMuted)
            }
        }()
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.5)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Color.actaHairline).frame(height: 1)
                .padding(.bottom, 4)
            Text("Documento generado por MiGestor · \(centerName)")
                .font(.system(size: 8.5))
                .foregroundColor(.actaMuted)
            Text("Generado el \(generatedOn)")
                .font(.system(size: 8.5))
                .foregroundColor(.actaMuted)
        }
    }
}

/// Exporta el acta de una reunión a PDF rasterizando `MeetingActaPage` con
/// `ImageRenderer` y paginando por franjas, para que el texto conserve su
/// tamaño en actas largas en vez de encogerse hasta caber en una sola hoja.
///
/// Deliberadamente NO reutiliza `PlannerReportPDFRenderer` (texto corrido con
/// `CTFramesetter`, sin logo ni tablas) ni `ScheduleGridPDFRenderer` (una sola
/// página escalada). Mismo espíritu que este último, pero multipágina.
@MainActor
enum MeetingActaPDFRenderer {
    /// A4 vertical a 72 dpi.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40
    /// Sobremuestreo para que el texto rasterizado quede nítido al imprimir.
    static let renderScale: CGFloat = 3

    static func render(acta: MeetingActaPage) -> Data? {
        let contentWidth = pageSize.width - margin * 2
        let renderer = ImageRenderer(content: acta.frame(width: contentWidth))
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
        renderer.scale = renderScale

        guard let cg = renderer.cgImage else { return nil }
        let imgWidthPx = CGFloat(cg.width)
        let imgHeightPx = CGFloat(cg.height)
        guard imgWidthPx > 0, imgHeightPx > 0 else { return nil }

        let totalHeightPt = imgHeightPx / renderScale
        let pageContentHeightPt = pageSize.height - margin * 2

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var yPt: CGFloat = 0
        while yPt < totalHeightPt - 0.5 {
            let sliceHeightPt = min(pageContentHeightPt, totalHeightPt - yPt)
            let cropPx = CGRect(x: 0, y: yPt * renderScale, width: imgWidthPx, height: sliceHeightPt * renderScale)
            guard let sliceCG = cg.cropping(to: cropPx) else { break }

            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: pageSize))
            // El origen del PDF está abajo a la izquierda; se sube la franja por su alto.
            let drawRect = CGRect(
                x: margin,
                y: pageSize.height - margin - sliceHeightPt,
                width: contentWidth,
                height: sliceHeightPt
            )
            ctx.draw(sliceCG, in: drawRect)
            ctx.endPDFPage()

            yPt += pageContentHeightPt
        }

        ctx.closePDF()
        return data as Data
    }

    /// Escribe el PDF en un fichero temporal y devuelve su URL, lista para
    /// `ShareLink`. Mismo patrón que los otros renderers.
    static func writeToTemporaryFile(acta: MeetingActaPage, suggestedName: String) -> URL? {
        guard let data = render(acta: acta) else { return nil }
        let safeName = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "acta" : safeName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
