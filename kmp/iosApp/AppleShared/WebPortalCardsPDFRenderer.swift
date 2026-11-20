import CoreGraphics
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Datos mínimos de una tarjeta QR imprimible para repartir en clase.
/// El nombre del alumno solo vive en el PDF local del docente; nunca viaja al servidor.
struct WebPortalCardItem: Identifiable, Equatable {
    let studentId: Int64
    let studentName: String
    let groupName: String
    let code: String
    let link: String
    let expiresAt: Date

    var id: Int64 { studentId }
}

/// Genera un PDF A4 vertical con 8 tarjetas recortables (2 × 4) por página.
/// Usa CoreGraphics + CoreImage de forma idéntica en macOS e iPadOS.
enum WebPortalCardsPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)
    static let columns = 2
    static let rows = 4
    static let cardsPerPage = columns * rows

    private static let marginX: CGFloat = 28
    private static let marginTop: CGFloat = 28
    private static let marginBottom: CGFloat = 28
    private static let headerHeight: CGFloat = 26
    private static let gridGap: CGFloat = 12

    static func pageCount(for cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return (cardCount + cardsPerPage - 1) / cardsPerPage
    }

    /// Renderiza el PDF completo. Devuelve `nil` si no hay tarjetas.
    static func render(
        cards: [WebPortalCardItem],
        groupName: String,
        generatedAt: Date = Date()
    ) -> Data? {
        guard !cards.isEmpty else { return nil }
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        let totalPages = pageCount(for: cards.count)
        let expiryFormatter = DateFormatter()
        expiryFormatter.locale = Locale(identifier: "es_ES")
        expiryFormatter.dateFormat = "d MMM yyyy"

        let shortExpiryFormatter = DateFormatter()
        shortExpiryFormatter.locale = Locale(identifier: "es_ES")
        shortExpiryFormatter.dateFormat = "d MMM"

        let gridTop = marginTop + headerHeight + 10
        let availableWidth = pageSize.width - marginX * 2
        let availableHeight = pageSize.height - gridTop - marginBottom
        let cardWidth = (availableWidth - gridGap * CGFloat(columns - 1)) / CGFloat(columns)
        let cardHeight = (availableHeight - gridGap * CGFloat(rows - 1)) / CGFloat(rows)

        for pageIndex in 0..<totalPages {
            let start = pageIndex * cardsPerPage
            let end = min(start + cardsPerPage, cards.count)
            let slice = Array(cards[start..<end])

            context.beginPDFPage(nil)
            context.saveGState()
            // Sistema de coordenadas arriba-izquierda para alinear textos y cajas con claridad.
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)

            // Fondo blanco de página
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: pageSize))

            let headerExpiry = slice.first.map { expiryFormatter.string(from: $0.expiresAt) }
                ?? expiryFormatter.string(from: generatedAt.addingTimeInterval(7 * 24 * 3600))
            drawHeader(
                in: context,
                groupName: groupName,
                page: pageIndex + 1,
                totalPages: totalPages,
                expiryText: headerExpiry
            )

            for (offset, card) in slice.enumerated() {
                let col = offset % columns
                let row = offset / columns
                let rect = CGRect(
                    x: marginX + CGFloat(col) * (cardWidth + gridGap),
                    y: gridTop + CGFloat(row) * (cardHeight + gridGap),
                    width: cardWidth,
                    height: cardHeight
                )
                drawCard(
                    card,
                    in: rect,
                    context: context,
                    expiryLabel: shortExpiryFormatter.string(from: card.expiresAt)
                )
            }

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    // MARK: - Dibujo de página y tarjeta

    private static func drawHeader(
        in context: CGContext,
        groupName: String,
        page: Int,
        totalPages: Int,
        expiryText: String
    ) {
        let leftRect = CGRect(x: marginX, y: marginTop, width: 320, height: 18)
        let rightRect = CGRect(x: pageSize.width - marginX - 240, y: marginTop, width: 240, height: 18)

        drawText(
            "Portal del alumnado · \(groupName)",
            in: leftRect,
            context: context,
            fontSize: 11,
            bold: true,
            color: (0.06, 0.24, 0.18)
        )
        drawText(
            "Página \(page) de \(totalPages) · Caduca el \(expiryText)",
            in: rightRect,
            context: context,
            fontSize: 9.5,
            bold: false,
            color: (0.36, 0.40, 0.37),
            alignment: .right
        )

        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.88, green: 0.90, blue: 0.88, alpha: 1))
        context.setLineWidth(0.75)
        let lineY = marginTop + headerHeight - 4
        context.move(to: CGPoint(x: marginX, y: lineY))
        context.addLine(to: CGPoint(x: pageSize.width - marginX, y: lineY))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawCard(
        _ card: WebPortalCardItem,
        in rect: CGRect,
        context: CGContext,
        expiryLabel: String
    ) {
        let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)

        // Fondo cálido de papel y línea discontinua de recorte
        context.saveGState()
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1))
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(CGColor(red: 0.72, green: 0.76, blue: 0.74, alpha: 1))
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.strokePath()
        context.restoreGState()

        let pad: CGFloat = 12
        let qrSize: CGFloat = 78
        let qrBox = CGRect(
            x: rect.maxX - pad - qrSize,
            y: rect.midY - qrSize / 2,
            width: qrSize,
            height: qrSize
        )

        // Marco del QR
        context.saveGState()
        let qrPath = CGPath(roundedRect: qrBox, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(qrPath)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillPath()
        context.addPath(qrPath)
        context.setStrokeColor(CGColor(red: 0.84, green: 0.87, blue: 0.85, alpha: 1))
        context.setLineWidth(0.75)
        context.strokePath()
        context.restoreGState()

        if let qrCG = makeQRCodeImage(for: card.link) {
            let inset = qrBox.insetBy(dx: 5, dy: 5)
            context.saveGState()
            context.interpolationQuality = .none
            // Invertir localmente el QR para dibujarlo recto en contexto volteado.
            context.translateBy(x: inset.minX, y: inset.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(qrCG, in: CGRect(origin: .zero, size: inset.size))
            context.restoreGState()
        }

        // Columna de texto
        let textX = rect.minX + pad
        let textW = qrBox.minX - textX - 10
        var cursorY = rect.minY + pad

        drawText(
            card.studentName,
            in: CGRect(x: textX, y: cursorY, width: textW, height: 18),
            context: context,
            fontSize: 12,
            bold: true,
            color: (0.06, 0.15, 0.11),
            singleLine: true
        )
        cursorY += 16

        drawText(
            "\(card.groupName) · Portal del alumnado",
            in: CGRect(x: textX, y: cursorY, width: textW, height: 13),
            context: context,
            fontSize: 8.5,
            bold: false,
            color: (0.35, 0.40, 0.37),
            singleLine: true
        )
        cursorY += 18

        // Pastilla con el código en monoespaciada
        let codePill = CGRect(x: textX, y: cursorY, width: min(textW, 134), height: 24)
        context.saveGState()
        let pillPath = CGPath(roundedRect: codePill, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(pillPath)
        context.setFillColor(CGColor(red: 0.93, green: 0.95, blue: 0.94, alpha: 1))
        context.fillPath()
        context.restoreGState()

        drawText(
            card.code,
            in: CGRect(x: codePill.minX + 6, y: codePill.minY + 4, width: codePill.width - 12, height: 18),
            context: context,
            fontSize: 13,
            bold: true,
            monospaced: true,
            color: (0.06, 0.24, 0.18),
            singleLine: true
        )
        cursorY += 30

        drawText(
            "1. Escanea el QR o entra en la web.\n2. Crea tu usuario sin usar tu nombre real.",
            in: CGRect(x: textX, y: cursorY, width: textW, height: 28),
            context: context,
            fontSize: 8.5,
            bold: false,
            color: (0.27, 0.33, 0.29)
        )

        drawText(
            "Un solo uso · Caduca el \(expiryLabel)",
            in: CGRect(x: textX, y: rect.maxY - pad - 13, width: textW, height: 13),
            context: context,
            fontSize: 8.2,
            bold: true,
            color: (0.54, 0.32, 0.10),
            singleLine: true
        )
    }

    private static func makeQRCodeImage(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
            return nil
        }
        return CIContext().createCGImage(output, from: output.extent)
    }

    private enum Alignment { case left, right }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        context: CGContext,
        fontSize: CGFloat,
        bold: Bool,
        monospaced: Bool = false,
        color: (CGFloat, CGFloat, CGFloat),
        alignment: Alignment = .left,
        singleLine: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment == .right ? .right : .left
        paragraph.lineBreakMode = singleLine ? .byTruncatingTail : .byWordWrapping
        paragraph.lineSpacing = 1.5

        #if os(macOS)
        let font: NSFont = if monospaced {
            .monospacedSystemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        } else {
            .systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        }
        let nsColor = NSColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor,
            .paragraphStyle: paragraph,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (text as NSString).draw(in: rect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        #else
        let font: UIFont = if monospaced {
            .monospacedSystemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        } else {
            .systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        }
        let uiColor = UIColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: uiColor,
            .paragraphStyle: paragraph,
        ]
        UIGraphicsPushContext(context)
        (text as NSString).draw(in: rect, withAttributes: attrs)
        UIGraphicsPopContext()
        #endif
    }
}

// MARK: - Selección de destinatarios

enum WebPortalCardsPDFScope: String, CaseIterable, Identifiable {
    case pendingOrUninvited
    case selected

    var id: String { rawValue }
}

enum WebPortalCardsTargetFilter {
    /// Alumnos sin cuenta activada (sin invitar, pendientes o caducados), con o sin correo.
    static func pendingOrUninvited(
        students: [WebPortalStudent],
        status: (WebPortalStudent) -> WebPortalAccountStatus
    ) -> [WebPortalStudent] {
        students.filter {
            switch status($0) {
            case .sinInvitar, .sinCorreo, .sinCuenta, .caducado, .pendiente:
                return true
            case .activada, .desconocido:
                return false
            }
        }
    }
}

// MARK: - Hoja de generación (Q1)

struct WebPortalCardsPDFSheet: View {
    let groupName: String
    let pendingTargets: [WebPortalStudent]
    let selectedTargets: [WebPortalStudent]
    let activeCountInSelected: Int
    let onGenerate: ([WebPortalStudent]) async -> Data?

    @Environment(\.dismiss) private var dismiss
    @State private var scope: WebPortalCardsPDFScope
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedURL: URL?
    #if os(iOS)
    @State private var showingShareSheet = false
    #endif

    init(
        groupName: String,
        pendingTargets: [WebPortalStudent],
        selectedTargets: [WebPortalStudent],
        activeCountInSelected: Int,
        onGenerate: @escaping ([WebPortalStudent]) async -> Data?
    ) {
        self.groupName = groupName
        self.pendingTargets = pendingTargets
        self.selectedTargets = selectedTargets
        self.activeCountInSelected = activeCountInSelected
        self.onGenerate = onGenerate
        _scope = State(initialValue: pendingTargets.isEmpty && !selectedTargets.isEmpty ? .selected : .pendingOrUninvited)
    }

    private var activeTargets: [WebPortalStudent] {
        switch scope {
        case .pendingOrUninvited: return pendingTargets
        case .selected: return selectedTargets
        }
    }

    private var pages: Int { WebPortalCardsPDFRenderer.pageCount(for: activeTargets.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tarjetas QR imprimibles").font(.title3.weight(.bold))
                    Text("\(groupName) · 8 tarjetas recortables por página A4")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isGenerating)
            }

            VStack(spacing: 10) {
                scopeRow(
                    option: .pendingOrUninvited,
                    title: "Sin invitar y caducados (\(pendingTargets.count))",
                    subtitle: "Crea códigos nuevos solo para quienes aún no tienen cuenta activa. Recomendado.",
                    disabled: pendingTargets.isEmpty
                )
                if !selectedTargets.isEmpty {
                    let activeHint = activeCountInSelected > 0
                        ? "Incluye \(activeCountInSelected) con cuenta activa: seguirá funcionando hasta que canjeen el código nuevo."
                        : "Genera tarjetas solo para las filas marcadas en la tabla."
                    scopeRow(
                        option: .selected,
                        title: "Solo seleccionados (\(selectedTargets.count))",
                        subtitle: activeHint,
                        disabled: false
                    )
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Cada código sirve una sola vez y caduca en 7 días. El PDF contiene los nombres solo en tu dispositivo para repartirlos en clase; guárdalo o destrúyelo tras repartirlo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                if activeTargets.isEmpty {
                    Text("No hay alumnado pendiente en esta selección.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(pages) \(pages == 1 ? "página" : "páginas") A4 · \(activeTargets.count) \(activeTargets.count == 1 ? "tarjeta" : "tarjetas")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar") { dismiss() }
                    .disabled(isGenerating)
                Button(action: runGeneration) {
                    HStack(spacing: 6) {
                        if isGenerating { ProgressView().controlSize(.small) }
                        Text(isGenerating
                             ? "Generando PDF…"
                             : "Generar PDF (\(activeTargets.count) \(activeTargets.count == 1 ? "tarjeta" : "tarjetas"))")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(activeTargets.isEmpty || isGenerating)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 540)
        #else
        .frame(minWidth: 460)
        .sheet(isPresented: $showingShareSheet, onDismiss: cleanupTempFile) {
            if let generatedURL {
                ShareSheet(activityItems: [generatedURL])
            }
        }
        #endif
        .interactiveDismissDisabled(isGenerating)
    }

    private func scopeRow(
        option: WebPortalCardsPDFScope,
        title: String,
        subtitle: String,
        disabled: Bool
    ) -> some View {
        let isSelected = scope == option
        return Button {
            guard !disabled else { return }
            scope = option
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func runGeneration() {
        let targets = activeTargets
        guard !targets.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        Task {
            defer { isGenerating = false }
            guard let pdfData = await onGenerate(targets) else {
                errorMessage = "No se pudo generar el PDF. Comprueba la conexión con el servidor e inténtalo de nuevo."
                return
            }
            let safeGroup = groupName
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
                .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            let fileName = "Tarjetas_QR_Portal_\(safeGroup.isEmpty ? "Grupo" : safeGroup).pdf"
            #if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = fileName
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            do {
                try pdfData.write(to: destination, options: .atomic)
                NSWorkspace.shared.open(destination)
                dismiss()
            } catch {
                errorMessage = "No se pudo guardar el archivo: \(error.localizedDescription)"
            }
            #else
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString.prefix(6))_\(fileName)")
            do {
                try pdfData.write(to: url, options: .atomic)
                generatedURL = url
                showingShareSheet = true
            } catch {
                errorMessage = "No se pudo preparar el archivo: \(error.localizedDescription)"
            }
            #endif
        }
    }

    #if os(iOS)
    private func cleanupTempFile() {
        if let generatedURL { try? FileManager.default.removeItem(at: generatedURL) }
        generatedURL = nil
        dismiss()
    }
    #endif
}
