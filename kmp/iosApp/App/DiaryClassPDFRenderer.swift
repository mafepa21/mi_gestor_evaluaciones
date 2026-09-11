import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import MiGestorKit

/// Renderizador de informes en PDF paginados del Diario de Aula usando Core Text + Core Graphics.
/// Compatible tanto en iPadOS como en macOS Native sin dependencias de UIKit ni AppKit.
enum DiaryClassPDFRenderer {
    /// A4 vertical a 72 dpi.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 44

    struct RenderOptions {
        var schoolName: String = "Centro Educativo"
        var teacherName: String = "Profesorado de Educación Física"
        var className: String
        var academicYear: String = "2026-2027"
        var periodTitle: String = "Todo el curso"
        var includeReflections: Bool = true
        var includeIncidents: Bool = true
        var onlyCompleted: Bool = false
    }

    /// Construye el documento como `NSAttributedString` con tipografía y jerarquía editorial.
    static func buildAttributedReport(
        entries: [DiaryTimelineEntry],
        aggregatesBySessionId: [Int64: SessionJournalAggregate],
        options: RenderOptions
    ) -> NSAttributedString {
        let fullString = NSMutableAttributedString()

        let pStyleCenter = NSMutableParagraphStyle()
        pStyleCenter.alignment = .center
        pStyleCenter.paragraphSpacing = 4

        let pStyleLeft = NSMutableParagraphStyle()
        pStyleLeft.alignment = .left
        pStyleLeft.paragraphSpacing = 6

        let pStyleHeading = NSMutableParagraphStyle()
        pStyleHeading.alignment = .left
        pStyleHeading.paragraphSpacing = 4
        pStyleHeading.paragraphSpacingBefore = 12

        let pStyleSessionHeader = NSMutableParagraphStyle()
        pStyleSessionHeader.alignment = .left
        pStyleSessionHeader.paragraphSpacing = 3
        pStyleSessionHeader.paragraphSpacingBefore = 14

        // 1. Cabecera Institucional
        let institutionAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil),
            .foregroundColor: CGColor(gray: 0.35, alpha: 1.0),
            .paragraphStyle: pStyleCenter
        ]
        fullString.append(NSAttributedString(string: "\(options.schoolName.uppercased())\n", attributes: institutionAttrs))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 18, nil),
            .foregroundColor: CGColor(gray: 0.1, alpha: 1.0),
            .paragraphStyle: pStyleCenter
        ]
        fullString.append(NSAttributedString(string: "DIARIO DE AULA Y BITÁCORA DOCENTE\n", attributes: titleAttrs))

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 11, nil),
            .foregroundColor: CGColor(gray: 0.3, alpha: 1.0),
            .paragraphStyle: pStyleCenter
        ]
        fullString.append(NSAttributedString(string: "Curso: \(options.className)  ·  Año Académico: \(options.academicYear)  ·  Periodo: \(options.periodTitle)\n\n", attributes: subAttrs))

        // 2. Resumen Métrico
        let completedCount = entries.filter(\.isCompleted).count
        let incidentsCount = entries.filter(\.hasIncidents).count
        let metricsText = "Total de sesiones: \(entries.count)    |    Sesiones completadas: \(completedCount)    |    Sesiones con incidencias: \(incidentsCount)\n"
        let metricsAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
            .foregroundColor: CGColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 1.0),
            .paragraphStyle: pStyleCenter
        ]
        fullString.append(NSAttributedString(string: metricsText, attributes: metricsAttrs))

        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 8, nil),
            .foregroundColor: CGColor(gray: 0.7, alpha: 1.0),
            .paragraphStyle: pStyleCenter
        ]
        fullString.append(NSAttributedString(string: "_____________________________________________________________________________________\n\n", attributes: separatorAttrs))

        // 3. Formateador de Fechas
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        dateFormatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy"

        // 4. Listado Cronológico de Sesiones
        for entry in entries {
            if options.onlyCompleted && !entry.isCompleted {
                continue
            }

            let session = entry.session
            let dateStr = dateFormatter.string(from: entry.date).capitalized
            let timeStr = session.startTime != nil && session.endTime != nil ? " (\(session.startTime!) - \(session.endTime!))" : ""

            // Encabezado de Sesión
            let sessionHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil),
                .foregroundColor: CGColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 1.0),
                .paragraphStyle: pStyleSessionHeader
            ]
            fullString.append(NSAttributedString(string: "Sesión #\(entry.sessionIndex)  —  \(dateStr)\(timeStr)\n", attributes: sessionHeaderAttrs))

            // Unidad Didáctica
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                .foregroundColor: CGColor(gray: 0.3, alpha: 1.0),
                .paragraphStyle: pStyleLeft
            ]
            fullString.append(NSAttributedString(string: "Unidad Didáctica: \(session.teachingUnitName)\n", attributes: unitAttrs))

            // Objetivos
            if !session.objectives.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let objLabelAttrs: [NSAttributedString.Key: Any] = [
                    .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                    .foregroundColor: CGColor(gray: 0.2, alpha: 1.0),
                    .paragraphStyle: pStyleLeft
                ]
                let objBodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
                    .foregroundColor: CGColor(gray: 0.25, alpha: 1.0),
                    .paragraphStyle: pStyleLeft
                ]
                let objPart = NSMutableAttributedString(string: "• Objetivos previstos: ", attributes: objLabelAttrs)
                objPart.append(NSAttributedString(string: "\(session.objectives)\n", attributes: objBodyAttrs))
                fullString.append(objPart)
            }

            // Actividades
            if !session.activities.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let actLabelAttrs: [NSAttributedString.Key: Any] = [
                    .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                    .foregroundColor: CGColor(gray: 0.2, alpha: 1.0),
                    .paragraphStyle: pStyleLeft
                ]
                let actBodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
                    .foregroundColor: CGColor(gray: 0.25, alpha: 1.0),
                    .paragraphStyle: pStyleLeft
                ]
                let actPart = NSMutableAttributedString(string: "• Actividades programadas: ", attributes: actLabelAttrs)
                actPart.append(NSAttributedString(string: "\(session.activities)\n", attributes: actBodyAttrs))
                fullString.append(actPart)
            }

            // Datos enriquecidos del Diario si existen
            if let aggregate = aggregatesBySessionId[session.id] {
                let journal = aggregate.journal

                // Desarrollo real / Reflexión
                if options.includeReflections && !journal.actualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let devLabelAttrs: [NSAttributedString.Key: Any] = [
                        .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                        .foregroundColor: CGColor(red: 0.05, green: 0.45, blue: 0.2, alpha: 1.0),
                        .paragraphStyle: pStyleLeft
                    ]
                    let devBodyAttrs: [NSAttributedString.Key: Any] = [
                        .font: CTFontCreateWithName("Helvetica-Oblique" as CFString, 9.5, nil),
                        .foregroundColor: CGColor(gray: 0.2, alpha: 1.0),
                        .paragraphStyle: pStyleLeft
                    ]
                    let devPart = NSMutableAttributedString(string: "✓ Desarrollo y notas de clase: ", attributes: devLabelAttrs)
                    devPart.append(NSAttributedString(string: "\(journal.actualText)\n", attributes: devBodyAttrs))
                    fullString.append(devPart)
                }

                // Decisión pedagógica
                let decisionLabel = journal.pedagogicalDecision.label
                if options.includeReflections && !decisionLabel.isEmpty {
                    let decLabelAttrs: [NSAttributedString.Key: Any] = [
                        .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                        .foregroundColor: CGColor(red: 0.5, green: 0.3, blue: 0.05, alpha: 1.0),
                        .paragraphStyle: pStyleLeft
                    ]
                    let decBodyAttrs: [NSAttributedString.Key: Any] = [
                        .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
                        .foregroundColor: CGColor(gray: 0.2, alpha: 1.0),
                        .paragraphStyle: pStyleLeft
                    ]
                    let decPart = NSMutableAttributedString(string: "→ Decisión pedagógica: ", attributes: decLabelAttrs)
                    decPart.append(NSAttributedString(string: "\(decisionLabel)\n", attributes: decBodyAttrs))
                    fullString.append(decPart)
                }

                // Incidencias o adaptaciones
                let combined = [journal.incidentsText, journal.adaptationsText]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " | ")
                if options.includeIncidents && !combined.isEmpty {
                    let incLabelAttrs: [NSAttributedString.Key: Any] = [
                        .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                        .foregroundColor: CGColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1.0),
                        .paragraphStyle: pStyleLeft
                    ]
                    let incBodyAttrs: [NSAttributedString.Key: Any] = [
                        .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
                        .foregroundColor: CGColor(gray: 0.2, alpha: 1.0),
                        .paragraphStyle: pStyleLeft
                    ]
                    let incPart = NSMutableAttributedString(string: "⚠ Incidencias / Medidas: ", attributes: incLabelAttrs)
                    incPart.append(NSAttributedString(string: "\(combined)\n", attributes: incBodyAttrs))
                    fullString.append(incPart)
                }
            }

            // Separador suave entre sesiones
            let lineAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 6, nil),
                .foregroundColor: CGColor(gray: 0.85, alpha: 1.0),
                .paragraphStyle: pStyleLeft
            ]
            fullString.append(NSAttributedString(string: "----------------------------------------------------------------------------------------------------------------------------\n", attributes: lineAttrs))
        }

        return fullString
    }

    /// Renderiza el contenido paginado a `Data` en formato PDF.
    static func renderPDF(attributedBody: NSAttributedString) -> Data? {
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
        let maxPages = 300

        while location < totalLength && pageCount < maxPages {
            context.beginPDFPage(nil)

            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(location, 0), path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()

            if visibleRange.length <= 0 {
                break
            }
            location += visibleRange.length
            pageCount += 1
        }

        context.closePDF()
        return data as Data
    }

    /// Escribe el PDF en un archivo temporal y devuelve su URL.
    static func writeToTemporaryFile(
        entries: [DiaryTimelineEntry],
        aggregatesBySessionId: [Int64: SessionJournalAggregate],
        options: RenderOptions
    ) -> URL? {
        let attributedReport = buildAttributedReport(
            entries: entries,
            aggregatesBySessionId: aggregatesBySessionId,
            options: options
        )
        guard let pdfData = renderPDF(attributedBody: attributedReport) else { return nil }

        let safeClassName = options.className
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "Diario_Aula_\(safeClassName)_\(UUID().uuidString.prefix(6)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try pdfData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
