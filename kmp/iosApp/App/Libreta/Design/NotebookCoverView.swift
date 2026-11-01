import SwiftUI

/// Portada de un cuaderno cerrado, vista de frente sobre la mesa.
///
/// Tapa de tela con lomo encuadernado a la izquierda, costura, goma elástica opcional,
/// etiqueta de papel con el título y el canto de las hojas asomando a la derecha.
/// Ocupa exactamente `size`.
struct NotebookCoverView: View {
    let title: String
    let color: CoverColor
    let size: CGSize
    let showsElastic: Bool

    init(title: String, color: CoverColor, size: CGSize, showsElastic: Bool = true) {
        self.title = title
        self.color = color
        self.size = size
        self.showsElastic = showsElastic
    }

    // MARK: Geometría (todo proporcional a `size`)

    /// Cuánto asoma el bloque de hojas por la derecha.
    private var edge: CGFloat { max(2, size.width * 0.022) }
    private var coverW: CGFloat { max(1, size.width - edge) }
    private var coverH: CGFloat { max(1, size.height - edge * 0.7) }
    private var radius: CGFloat { min(Theme.coverCornerRadius, size.width * 0.045) }
    private var spineW: CGFloat { coverW * 0.09 }
    private var elasticW: CGFloat { max(3, coverW * 0.04) }
    private var elasticX: CGFloat { coverW * 0.84 }
    private var labelAreaStart: CGFloat { spineW }
    private var labelAreaEnd: CGFloat { showsElastic ? elasticX : coverW }
    private var labelW: CGFloat { (labelAreaEnd - labelAreaStart) * 0.8 }
    private var labelH: CGFloat { labelW * 0.5 }
    private var labelX: CGFloat { labelAreaStart + ((labelAreaEnd - labelAreaStart) - labelW) / 2 }
    private var labelY: CGFloat { coverH * 0.16 }

    private var coverShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radius * 0.35,
            bottomLeadingRadius: radius * 0.35,
            bottomTrailingRadius: radius,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageBlock
                .frame(width: coverW, height: coverH)
                .offset(x: edge, y: edge * 0.7)
            cover
                .frame(width: coverW, height: coverH)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: Theme.shadow, radius: size.width * 0.035, x: size.width * 0.01, y: size.width * 0.025)
        .shadow(color: Theme.shadow, radius: 0.8, x: 0, y: 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Libreta \(title)"))
    }

    // MARK: Piezas

    /// Canto de las hojas que asoma bajo la tapa.
    private var pageBlock: some View {
        let shape = RoundedRectangle(cornerRadius: radius * 0.6, style: .continuous)
        return shape
            .fill(Theme.paperEdge)
            .overlay(shape.stroke(Theme.paperEdgeLine, lineWidth: 0.5))
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            // Tela base con leve degradado de luz.
            coverShape.fill(
                LinearGradient(
                    colors: [color.tint(0.08), color.color, color.shade(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            WeaveTexture(
                seed: color.seed,
                step: max(1.8, size.width * 0.012),
                lightOpacity: color.isLight ? 0.10 : 0.05,
                darkOpacity: color.isLight ? 0.05 : 0.07,
                speckleDensity: 1.0 / 70.0,
                speckleOpacity: 0.07
            )

            // Brillo muy suave arriba a la izquierda.
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            spine
                .frame(width: spineW + 2, height: coverH)

            stitchLine
                .frame(width: 2, height: max(0, coverH - coverW * 0.05))
                .offset(x: spineW + coverW * 0.03 - 1, y: coverW * 0.025)

            label
                .offset(x: labelX, y: labelY)

            if showsElastic {
                elastic
                    .offset(x: elasticX)
            }
        }
        .frame(width: coverW, height: coverH, alignment: .topLeading)
        .clipShape(coverShape)
        .overlay(coverShape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        .overlay(coverShape.stroke(Color.black.opacity(0.18), lineWidth: 0.5))
    }

    /// Cinta del lomo, con la doblez marcada.
    private var spine: some View {
        HStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: color.shade(0.40), location: 0),
                    .init(color: color.shade(0.22), location: 0.45),
                    .init(color: color.shade(0.30), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle().fill(Color.black.opacity(0.28)).frame(width: 1)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
        }
    }

    private var stitchLine: some View {
        CoverVLine()
            .stroke(
                color.stitch,
                style: StrokeStyle(
                    lineWidth: max(0.6, coverW * 0.005),
                    lineCap: .round,
                    dash: [coverW * 0.022, coverW * 0.016]
                )
            )
    }

    /// Goma elástica vertical.
    private var elastic: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.08), Color(white: 0.26), Color(white: 0.10)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: elasticW, height: coverH)
            .shadow(color: Color.black.opacity(0.35), radius: elasticW * 0.35, x: elasticW * 0.3, y: 0)
    }

    /// Etiqueta de papel con el título.
    private var label: some View {
        let r = labelH * 0.12
        let isEmpty = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(Theme.paper)
            .overlay(
                RoundedRectangle(cornerRadius: r * 0.7, style: .continuous)
                    .inset(by: labelW * 0.035)
                    .stroke(color.color.opacity(0.45), lineWidth: max(0.5, labelW * 0.006))
            )
            .overlay(
                Text(isEmpty ? "Sin título" : title)
                    .font(Theme.Fonts.serif(max(8, labelW * 0.13), weight: .medium))
                    .foregroundStyle(isEmpty ? Theme.paperInkSecondary : Theme.paperInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, labelW * 0.09)
                    .padding(.vertical, labelH * 0.1)
            )
            .frame(width: labelW, height: labelH)
            .shadow(color: Color.black.opacity(0.22), radius: 1.2, x: 0, y: 0.8)
    }
}

/// Línea vertical centrada (para costuras).
fileprivate struct CoverVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

// MARK: - Nuevo cuaderno

/// Hueco con borde discontinuo para crear un cuaderno. Mismo tamaño que una portada.
struct NewNotebookCoverView: View {
    let size: CGSize

    init(size: CGSize) {
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(Theme.coverCornerRadius, size.width * 0.045), style: .continuous)
        ZStack {
            shape.fill(Theme.newSlotFill)
            shape.strokeBorder(
                Theme.inkSecondary.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
            )
            VStack(spacing: size.width * 0.05) {
                Image(systemName: "plus")
                    .font(.system(size: max(14, size.width * 0.16), weight: .light))
                Text("Nueva libreta")
                    .font(Theme.Fonts.serif(max(11, size.width * 0.085)))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(size.width * 0.08)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Nueva libreta"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#Preview("Portadas") {
    let size = CGSize(width: Theme.coverWidth, height: Theme.coverWidth / Theme.coverAspect)
    return ScrollView {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: size.width), spacing: Theme.shelfSpacing)],
            spacing: Theme.shelfSpacing
        ) {
            NewNotebookCoverView(size: size)
            ForEach(Array(CoverColor.allCases.enumerated()), id: \.element) { index, c in
                VStack(spacing: 10) {
                    NotebookCoverView(
                        title: index == 1 ? "Ideas y bocetos para el proyecto de verano" : c.label,
                        color: c,
                        size: size,
                        showsElastic: index % 3 != 2
                    )
                    Text(c.label)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(40)
    }
    .background(ShelfBackground())
}

#Preview("Nueva libreta") {
    NewNotebookCoverView(size: CGSize(width: 170, height: 236))
        .padding(40)
        .background(ShelfBackground())
}
