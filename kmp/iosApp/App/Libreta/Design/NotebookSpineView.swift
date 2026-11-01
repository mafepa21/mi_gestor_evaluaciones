import SwiftUI

/// Lomo de un cuaderno de pie en la estantería.
///
/// Tela del color de la tapa con volumen (más oscura en los cantos), dos cabezadas
/// cosidas arriba y abajo y el título en serif, en vertical (se lee de abajo arriba,
/// como en los libros europeos). Ocupa exactamente `size`.
struct NotebookSpineView: View {
    let title: String
    let color: CoverColor
    let size: CGSize

    init(title: String, color: CoverColor, size: CGSize) {
        self.title = title
        self.color = color
        self.size = size
    }

    private var radius: CGFloat { min(3, size.width * 0.08) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    var body: some View {
        ZStack {
            // Tela con volumen: el lomo es redondeado, la luz le da en el primer tercio.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: color.shade(0.34), location: 0),
                        .init(color: color.tint(0.07), location: 0.3),
                        .init(color: color.color, location: 0.58),
                        .init(color: color.shade(0.30), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            WeaveTexture(
                seed: color.seed,
                step: max(1.8, size.width * 0.06),
                lightOpacity: color.isLight ? 0.10 : 0.05,
                darkOpacity: color.isLight ? 0.05 : 0.07,
                speckleDensity: 1.0 / 80.0,
                speckleOpacity: 0.07
            )

            headbands
            titleText
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(Color.black.opacity(0.22), lineWidth: 0.5))
        .compositingGroup()
        .shadow(color: Theme.shadow, radius: 1.6, x: 1, y: 1)
    }

    /// Dos filetes cosidos cerca de cada extremo.
    private var headbands: some View {
        VStack(spacing: 0) {
            band.padding(.top, size.height * 0.07)
            Spacer(minLength: 0)
            band.padding(.bottom, size.height * 0.07)
        }
        .frame(width: size.width, height: size.height)
    }

    private var band: some View {
        VStack(spacing: 2) {
            Rectangle().frame(height: 0.8)
            Rectangle().frame(height: 0.8)
        }
        .foregroundStyle(color.stitch)
    }

    /// Título girado 90° (de abajo arriba). Se maqueta en un marco "tumbado"
    /// (alto × ancho) y se gira dentro del marco real del lomo.
    private var titleText: some View {
        let isEmpty = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let inset = size.height * 0.15
        return Text(isEmpty ? "Sin título" : title)
            .font(Theme.Fonts.serif(min(15, max(9, size.width * 0.38)), weight: .medium))
            .foregroundStyle(color.isLight ? Theme.paperInk : Theme.paper.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .truncationMode(.tail)
            .frame(width: max(1, size.height - inset * 2), height: size.width)
            .rotationEffect(.degrees(-90))
            .frame(width: size.width, height: size.height)
    }
}

#Preview("Lomos") {
    HStack(alignment: .bottom, spacing: 3) {
        ForEach(Array(CoverColor.allCases.enumerated()), id: \.element) { i, c in
            NotebookSpineView(title: i == 2 ? "Ideas y bocetos para el verano" : c.label,
                              color: c,
                              size: CGSize(width: 28 + CGFloat(i % 3) * 7, height: 170 + CGFloat(i % 4) * 6))
        }
    }
    .padding(40)
    .background(ShelfBackground())
}
