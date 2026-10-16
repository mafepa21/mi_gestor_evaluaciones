import SwiftUI

/// Número de página discreto, como impreso al pie de la hoja.
///
/// Pensado para ir encima del papel (siempre claro), p. ej.
/// `.overlay(alignment: .bottom) { PageNumberLabel(number: n, alignment: .trailing).padding(14) }`.
/// Usa `.leading` en la hoja izquierda, `.trailing` en la derecha y `.center` en hoja única.
struct PageNumberLabel: View {
    let number: Int
    let alignment: HorizontalAlignment

    init(number: Int, alignment: HorizontalAlignment) {
        self.number = number
        self.alignment = alignment
    }

    var body: some View {
        let text: String = alignment == .center ? "– \(number) –" : String(number)
        Text(verbatim: text)
            .font(Theme.Fonts.pageNumber)
            .foregroundStyle(Theme.paperInkSecondary.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .allowsHitTesting(false)
            .accessibilityLabel(Text("Página \(number)"))
    }
}

#Preview("Números de página") {
    VStack(spacing: 12) {
        PageNumberLabel(number: 12, alignment: .leading)
        PageNumberLabel(number: 7, alignment: .center)
        PageNumberLabel(number: 13, alignment: .trailing)
    }
    .padding(20)
    .frame(width: 300)
    .background(Theme.paper)
}
