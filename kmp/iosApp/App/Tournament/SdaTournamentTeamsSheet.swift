import SwiftUI
import CoreGraphics
#if os(macOS)
import AppKit
import PDFKit
#else
import UIKit
#endif

// Hoja imprimible de equipos de un torneo (A4): título, tarjetas por equipo en dos columnas y
// «Primera ronda». La paginación es pura y determinista (alturas fijas) para poder probarla;
// la vista del PDF usa esas mismas medidas, así que lo calculado es lo que se dibuja.

// MARK: - Contenido

struct SdaTeamsSheetContent: Equatable {
    var title: String
    var subtitle: String
    var teams: [SdaResolvedTeam]
    var firstRound: SdaFirstRound?

    /// - Parameters:
    ///   - situationTitle: título de la SdA; `nil` en torneos migrados (solo de curso).
    static func make(
        plan: TournamentPlan,
        situationTitle: String?,
        className: String,
        teams: [SdaResolvedTeam]
    ) -> SdaTeamsSheetContent {
        let date = plan.startDate.formatted(
            Date.FormatStyle().day(.twoDigits).month(.twoDigits).year().locale(Locale(identifier: "es_ES"))
        )
        let parts = [
            situationTitle.map { "SdA «\($0)»" },
            className.isEmpty ? nil : className,
            date
        ].compactMap { $0 }
        return SdaTeamsSheetContent(
            title: plan.name,
            subtitle: parts.joined(separator: " · "),
            teams: teams,
            firstRound: plan.firstRoundSummary
        )
    }
}

// MARK: - Paginación

enum SdaTeamsSheetLayout {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 36
    static let columnGap: CGFloat = 10
    static let rowGap: CGFloat = 8
    static let cardPadding: CGFloat = 8
    static let cardTitleHeight: CGFloat = 20
    static let cardTitleGap: CGFloat = 4
    static let lineHeight: CGFloat = 15
    static let firstPageHeaderHeight: CGFloat = 60
    static let nextPageHeaderHeight: CGFloat = 24
    static let firstRoundGap: CGFloat = 12
    static let firstRoundTitleHeight: CGFloat = 28
    static let firstRoundLineHeight: CGFloat = 22

    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    static var contentHeight: CGFloat { pageSize.height - margin * 2 }
    static var cardWidth: CGFloat { (contentWidth - columnGap) / 2 }

    struct Page: Equatable {
        /// Filas de hasta dos equipos.
        var rows: [[SdaResolvedTeam]] = []
        var showsFirstRound = false
        var isFirst = false
    }

    static let memberFontSize: CGFloat = 12
    /// Un nombre largo pasa a dos líneas; nunca más, para que la tarjeta sea predecible.
    static let maxLinesPerMember = 2

    /// Hueco de la viñeta «•»: la segunda línea de un nombre largo queda alineada con la primera.
    static let bulletWidth: CGFloat = 10

    static var memberTextWidth: CGFloat { cardWidth - cardPadding * 2 - bulletWidth }

    /// Líneas que ocupa un nombre con la fuente de la tarjeta (1 o 2).
    static func lineCount(for name: String) -> Int {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: memberFontSize)
        #else
        let font = UIFont.systemFont(ofSize: memberFontSize)
        #endif
        let width = (name as NSString).size(withAttributes: [.font: font]).width
        // Margen del 4 % para no rozar el borde (la medida real de SwiftUI puede variar algo).
        let lines = Int((width * 1.04 / memberTextWidth).rounded(.up))
        return min(max(1, lines), maxLinesPerMember)
    }

    static func memberLinesHeight(for team: SdaResolvedTeam) -> CGFloat {
        guard !team.memberNames.isEmpty else { return lineHeight }
        let lines = team.memberNames.reduce(0) { $0 + lineCount(for: $1) }
        return lineHeight * CGFloat(lines)
    }

    static func cardHeight(for team: SdaResolvedTeam) -> CGFloat {
        cardPadding * 2 + cardTitleHeight + cardTitleGap + memberLinesHeight(for: team)
    }

    static func rowHeight(_ row: [SdaResolvedTeam]) -> CGFloat {
        row.map(cardHeight(for:)).max() ?? 0
    }

    static func firstRoundHeight(_ round: SdaFirstRound) -> CGFloat {
        let lines = round.matches.count + (round.resting.isEmpty ? 0 : 1)
        return firstRoundGap + firstRoundTitleHeight + firstRoundLineHeight * CGFloat(lines)
    }

    /// Reparte los equipos en páginas. La primera ronda va al final, en la última página que tenga sitio.
    static func paginate(teams: [SdaResolvedTeam], firstRound: SdaFirstRound?) -> [Page] {
        var pages = [Page(isFirst: true)]
        var used = firstPageHeaderHeight
        let rows = stride(from: 0, to: teams.count, by: 2).map { Array(teams[$0..<min($0 + 2, teams.count)]) }
        for row in rows {
            let height = rowHeight(row)
            let gap = pages[pages.count - 1].rows.isEmpty ? 0 : rowGap
            if used + gap + height > contentHeight, !pages[pages.count - 1].rows.isEmpty {
                pages.append(Page())
                used = nextPageHeaderHeight
                pages[pages.count - 1].rows.append(row)
                used += height
            } else {
                pages[pages.count - 1].rows.append(row)
                used += gap + height
            }
        }
        if let firstRound {
            let height = firstRoundHeight(firstRound)
            if used + height > contentHeight {
                pages.append(Page(showsFirstRound: true))
            } else {
                pages[pages.count - 1].showsFirstRound = true
            }
        }
        return pages
    }

    static func pageCount(teams: [SdaResolvedTeam], firstRound: SdaFirstRound?) -> Int {
        paginate(teams: teams, firstRound: firstRound).count
    }
}

// MARK: - Vista de una página (siempre en claro)

struct SdaTeamsSheetPageView: View {
    let content: SdaTeamsSheetContent
    let page: SdaTeamsSheetLayout.Page
    let pageNumber: Int
    let pageCount: Int

    private typealias L = SdaTeamsSheetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.isFirst {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(content.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.33))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(height: L.firstPageHeaderHeight, alignment: .topLeading)
            } else if !page.rows.isEmpty {
                Text("\(content.title) (continuación)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.33))
                    .lineLimit(1)
                    .frame(height: L.nextPageHeaderHeight, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: L.rowGap) {
                ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: L.columnGap) {
                        ForEach(row) { team in
                            card(team, height: L.rowHeight(row))
                        }
                        if row.count == 1 {
                            Color.clear.frame(width: L.cardWidth)
                        }
                    }
                }
            }
            if page.showsFirstRound, let round = content.firstRound {
                firstRoundBlock(round)
            }
            Spacer(minLength: 0)
        }
        .padding(L.margin)
        .frame(width: L.pageSize.width, height: L.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .bottomTrailing) {
            if pageCount > 1 {
                Text("Página \(pageNumber) de \(pageCount)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.trailing, L.margin)
                    .padding(.bottom, 16)
            }
        }
        .foregroundColor(Color(white: 0.07))
        .environment(\.colorScheme, .light)
    }

    private func card(_ team: SdaResolvedTeam, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: L.cardTitleGap) {
            Text(team.name)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: L.cardTitleHeight, alignment: .leading)
            // Sin espaciado entre nombres: la altura calculada en `cardHeight` es exacta.
            VStack(alignment: .leading, spacing: 0) {
                if team.memberNames.isEmpty {
                    Text("Sin alumnos")
                        .font(.system(size: L.memberFontSize).italic())
                        .foregroundColor(Color(white: 0.4))
                        .frame(height: L.lineHeight, alignment: .leading)
                } else {
                    ForEach(Array(team.memberNames.enumerated()), id: \.offset) { _, name in
                        let lines = L.lineCount(for: name)
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("•")
                                .font(.system(size: L.memberFontSize, weight: .bold))
                                .frame(width: L.bulletWidth, alignment: .leading)
                            Text(name)
                                .font(.system(size: L.memberFontSize))
                                .lineLimit(lines)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: L.memberTextWidth, alignment: .topLeading)
                        }
                        .frame(height: L.lineHeight * CGFloat(lines), alignment: .topLeading)
                    }
                }
            }
        }
        .padding(L.cardPadding)
        .frame(width: L.cardWidth, height: height, alignment: .topLeading)
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.07), lineWidth: 2))
    }

    private func firstRoundBlock(_ round: SdaFirstRound) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(white: 0.07)).frame(height: 2)
            Text(round.title)
                .font(.system(size: 14, weight: .bold))
                .frame(height: L.firstRoundTitleHeight - 2, alignment: .center)
            ForEach(Array(round.matches.enumerated()), id: \.offset) { _, match in
                HStack(spacing: 12) {
                    Text("Pista \(match.venue)")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 60, alignment: .leading)
                    Text(match.text)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .frame(height: L.firstRoundLineHeight)
            }
            if !round.resting.isEmpty {
                Text("Descansan: \(round.resting.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.33))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: L.firstRoundLineHeight, alignment: .leading)
            }
        }
        .padding(.top, L.firstRoundGap)
    }
}

// MARK: - PDF

@MainActor
enum SdaTeamsSheetPDF {
    /// PDF A4 con una página por cada página de `paginate`. `nil` si no se pudo dibujar.
    static func render(_ content: SdaTeamsSheetContent) -> Data? {
        let pages = SdaTeamsSheetLayout.paginate(teams: content.teams, firstRound: content.firstRound)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: SdaTeamsSheetLayout.pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for (index, page) in pages.enumerated() {
            let view = SdaTeamsSheetPageView(content: content, page: page, pageNumber: index + 1, pageCount: pages.count)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(SdaTeamsSheetLayout.pageSize)
            var drawn = false
            renderer.render { size, draw in
                guard size.width > 0, size.height > 0 else { return }
                context.beginPDFPage(nil)
                // El PDF tiene el origen abajo a la izquierda: se baja la vista a la esquina superior.
                context.translateBy(x: 0, y: SdaTeamsSheetLayout.pageSize.height - size.height)
                draw(context)
                context.endPDFPage()
                drawn = true
            }
            guard drawn else { return nil }
        }
        context.closePDF()
        return data as Data
    }

    /// Escribe el PDF en un fichero temporal único, listo para `ShareLink`.
    static func writeToTemporaryFile(_ content: SdaTeamsSheetContent) -> URL? {
        guard let data = render(content) else { return nil }
        let safeName = content.title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Equipos \(safeName.isEmpty ? "torneo" : safeName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Impresión en Mac

#if os(macOS)
@MainActor
enum SdaTeamsSheetPrinter {
    /// Abre el panel de impresión del sistema (desde ahí también se guarda o comparte como PDF).
    static func printPDF(at url: URL) {
        guard let document = PDFDocument(url: url),
              let operation = document.printOperation(
                  for: NSPrintInfo.shared,
                  scalingMode: .pageScaleToFit,
                  autoRotate: false
              )
        else { return }
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
#endif
