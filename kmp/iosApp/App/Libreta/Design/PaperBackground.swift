import SwiftUI

/// Papel de una hoja: fondo crema + rayado / cuadrícula / puntos / liso, o una
/// plantilla impresa (semana, tareas, Cornell, pentagrama).
///
/// Todo se calcula en proporción al ancho, así que la misma hoja se ve igual en
/// miniatura, en vertical o en la doble página. Las dos hojas de una doble página
/// (mismo tamaño) quedan con las líneas alineadas.
struct PaperBackground: View {
    let style: PaperStyle

    init(style: PaperStyle) {
        self.style = style
    }

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.paper))
            guard size.width > 4, size.height > 4 else { return }

            let lineWidth = max(0.5, size.width * 0.0011)
            switch style {
            case .ruled: Self.drawRuled(&ctx, size: size, lineWidth: lineWidth)
            case .grid: Self.drawGrid(&ctx, size: size, lineWidth: lineWidth)
            case .dotted: Self.drawDots(&ctx, size: size)
            case .blank: break
            case .weekly: Self.drawWeekly(&ctx, size: size, lineWidth: lineWidth)
            case .todo: Self.drawTodo(&ctx, size: size, lineWidth: lineWidth)
            case .cornell: Self.drawCornell(&ctx, size: size, lineWidth: lineWidth)
            case .staff: Self.drawStaff(&ctx, size: size, lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Métricas públicas (útiles para alinear contenido con las líneas)

    /// Separación entre renglones del rayado para un ancho de hoja dado.
    static func ruleSpacing(forWidth width: CGFloat) -> CGFloat { width / 24 }
    /// Lado del cuadro de la cuadrícula.
    static func gridSpacing(forWidth width: CGFloat) -> CGFloat { width / 32 }
    /// Separación entre puntos.
    static func dotSpacing(forWidth width: CGFloat) -> CGFloat { width / 30 }

    // MARK: Dibujo

    private static func drawRuled(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let spacing = ruleSpacing(forWidth: size.width)
        let top = spacing * 3
        let bottom = size.height - spacing * 0.8

        var lines = Path()
        var y = top
        while y <= bottom {
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        ctx.stroke(lines, with: .color(Theme.ruleInk.opacity(0.7)), lineWidth: lineWidth)

        // Margen rojo suave.
        let marginX = spacing * 2.6
        var margin = Path()
        margin.move(to: CGPoint(x: marginX, y: 0))
        margin.addLine(to: CGPoint(x: marginX, y: size.height))
        ctx.stroke(margin, with: .color(Theme.marginInk.opacity(0.55)), lineWidth: lineWidth * 1.1)
    }

    private static func drawGrid(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let spacing = gridSpacing(forWidth: size.width)
        // Centrada, para que los bordes queden simétricos.
        let startX = (size.width - (size.width / spacing).rounded(.down) * spacing) / 2
        let startY = (size.height - (size.height / spacing).rounded(.down) * spacing) / 2

        var grid = Path()
        var x = startX
        while x <= size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y = startY
        while y <= size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        ctx.stroke(grid, with: .color(Theme.gridInk.opacity(0.5)), lineWidth: lineWidth * 0.9)
    }

    private static func drawDots(_ ctx: inout GraphicsContext, size: CGSize) {
        let spacing = dotSpacing(forWidth: size.width)
        let r = max(0.8, size.width * 0.0017)
        let startX = (size.width - (size.width / spacing).rounded(.down) * spacing) / 2
        let startY = (size.height - (size.height / spacing).rounded(.down) * spacing) / 2

        var dots = Path()
        var y = startY
        while y <= size.height {
            var x = startX
            while x <= size.width {
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += spacing
            }
            y += spacing
        }
        ctx.fill(dots, with: .color(Theme.dotInk.opacity(0.65)))
    }

    // MARK: - Plantillas
    //
    // Mismo lenguaje que los papeles básicos: líneas finas en `ruleInk`, estructura
    // apenas más marcada, rótulos serif pequeños en `paperInkSecondary` y un único
    // trazo corto terracota en la cabecera. Todo en proporción al ancho; los rótulos
    // desaparecen cuando serían ilegibles y los renglones interiores cuando se
    // amontonarían (muestras de papel diminutas).

    /// Margen lateral de las plantillas.
    private static func templateMargin(_ w: CGFloat) -> CGFloat { w * 0.07 }
    /// Margen inferior (deja sitio al número de hoja).
    private static func templateBottom(_ w: CGFloat) -> CGFloat { w * 0.085 }
    /// Separación mínima (en puntos) para dibujar renglones interiores.
    private static let minInnerSpacing: CGFloat = 2.5

    private static func hLine(_ path: inout Path, _ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat) {
        path.move(to: CGPoint(x: x0, y: y))
        path.addLine(to: CGPoint(x: x1, y: y))
    }

    private static func vLine(_ path: inout Path, _ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
        path.move(to: CGPoint(x: x, y: y0))
        path.addLine(to: CGPoint(x: x, y: y1))
    }

    /// Rótulo impreso (serif). No se dibuja si sería una mancha ilegible.
    private static func label(_ ctx: inout GraphicsContext, _ string: String, at point: CGPoint,
                              anchor: UnitPoint, size: CGFloat, weight: Font.Weight = .regular,
                              italic: Bool = false, color: Color = Theme.paperInkSecondary) {
        guard size >= 3.5 else { return }
        var font = Theme.Fonts.serif(size, weight: weight)
        if italic { font = font.italic() }
        ctx.draw(Text(string).font(font).foregroundStyle(color), at: point, anchor: anchor)
    }

    /// Cabecera común: rótulo a la izquierda, campos pequeños a la derecha y una
    /// línea de escritura con un trazo corto terracota. Devuelve la y de esa línea
    /// (coincide con el primer renglón del rayado).
    @discardableResult
    private static func drawHeader(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat,
                                   title: String, fields: [String] = []) -> CGFloat {
        let w = size.width
        let mx = templateMargin(w)
        let y = ruleSpacing(forWidth: w) * 3

        var line = Path()
        hLine(&line, mx, w - mx, y)
        // Separadores cortos de los campos.
        let fieldWidth = w * 0.2
        for i in fields.indices {
            let x = w - mx - fieldWidth * CGFloat(fields.count - i)
            vLine(&line, x - w * 0.014, y - w * 0.026, y)
        }
        ctx.stroke(line, with: .color(Theme.ruleInk.opacity(0.9)), lineWidth: lineWidth * 1.1)

        var accent = Path()
        hLine(&accent, mx, mx + w * 0.07, y)
        ctx.stroke(accent, with: .color(Theme.paperAccent.opacity(0.7)), lineWidth: lineWidth * 2.2)

        label(&ctx, title, at: CGPoint(x: mx, y: y - w * 0.012), anchor: .bottomLeading,
              size: w * 0.034, color: Theme.paperInk.opacity(0.62))
        for (i, field) in fields.enumerated() {
            let x = w - mx - fieldWidth * CGFloat(fields.count - i)
            label(&ctx, field, at: CGPoint(x: x, y: y - w * 0.009), anchor: .bottomLeading,
                  size: w * 0.019, italic: true)
        }
        return y
    }

    /// Semana: Lunes…Jueves a la izquierda, Viernes…Domingo y Notas a la derecha.
    /// Cada día: filete superior, rótulo, círculo para el número del día y renglones.
    private static func drawWeekly(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let w = size.width
        let mx = templateMargin(w)
        let top = drawHeader(&ctx, size: size, lineWidth: lineWidth,
                             title: "Semana", fields: ["del", "al"]) + w * 0.04
        let bottom = size.height - templateBottom(w)
        let colGap = w * 0.045
        let rowGap = w * 0.024
        let colW = (w - mx * 2 - colGap) / 2
        let rowH = (bottom - top - rowGap * 3) / 4
        guard colW > 0, rowH > 0 else { return }

        let s = w / 26
        let days = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo", "Notas"]
        var rules = Path(), lines = Path(), circles = Path()
        for (i, day) in days.enumerated() {
            let x = mx + CGFloat(i / 4) * (colW + colGap)
            let y = top + CGFloat(i % 4) * (rowH + rowGap)
            let isNotes = i == 7
            hLine(&rules, x, x + colW, y)

            let labelY = y + s * 0.62
            label(&ctx, day, at: CGPoint(x: x, y: labelY), anchor: .leading, size: w * 0.021,
                  italic: isNotes,
                  color: i == 6 ? Theme.paperAccent.opacity(0.8) : Theme.paperInkSecondary)
            if !isNotes {
                let r = w * 0.015
                circles.addEllipse(in: CGRect(x: x + colW - r * 2, y: labelY - r, width: r * 2, height: r * 2))
            }
            if s >= minInnerSpacing {
                var ly = y + s * 1.7
                while ly <= y + rowH - s * 0.15 {
                    hLine(&lines, x, x + colW, ly)
                    ly += s
                }
            }
        }
        ctx.stroke(lines, with: .color(Theme.ruleInk.opacity(0.5)), lineWidth: lineWidth * 0.9)
        ctx.stroke(circles, with: .color(Theme.ruleInk.opacity(0.75)), lineWidth: lineWidth * 0.9)
        ctx.stroke(rules, with: .color(Theme.ruleInk.opacity(0.95)), lineWidth: lineWidth * 1.2)
    }

    /// Tareas: renglones anchos con casilla cuadrada y, abajo, una zona de notas punteada.
    private static func drawTodo(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let w = size.width
        let mx = templateMargin(w)
        let headerY = drawHeader(&ctx, size: size, lineWidth: lineWidth, title: "Tareas", fields: ["Fecha"])
        let bottom = size.height - templateBottom(w)
        let notesTop = bottom - w * 0.3
        let s = w / 19
        let box = s * 0.42

        var lines = Path(), boxes = Path()
        var y = headerY + s * 1.3
        while y <= notesTop - s * 0.7 {
            boxes.addRoundedRect(in: CGRect(x: mx, y: y - s * 0.18 - box, width: box, height: box),
                                 cornerSize: CGSize(width: box * 0.22, height: box * 0.22))
            hLine(&lines, mx + box + s * 0.4, w - mx, y)
            y += s
        }
        ctx.stroke(lines, with: .color(Theme.ruleInk.opacity(0.65)), lineWidth: lineWidth)
        ctx.stroke(boxes, with: .color(Theme.ruleInk.opacity(0.95)), lineWidth: lineWidth * 1.15)

        // Notas
        var rule = Path()
        hLine(&rule, mx, w - mx, notesTop)
        ctx.stroke(rule, with: .color(Theme.ruleInk.opacity(0.95)), lineWidth: lineWidth * 1.2)
        label(&ctx, "Notas", at: CGPoint(x: mx, y: notesTop + w * 0.026), anchor: .leading,
              size: w * 0.021, italic: true)

        let d = dotSpacing(forWidth: w)
        guard d >= minInnerSpacing else { return }
        let r = max(0.7, w * 0.0015)
        var dots = Path()
        var dy = notesTop + w * 0.065
        while dy <= bottom {
            var dx = mx
            while dx <= w - mx + 0.5 {
                dots.addEllipse(in: CGRect(x: dx - r, y: dy - r, width: r * 2, height: r * 2))
                dx += d
            }
            dy += d
        }
        ctx.fill(dots, with: .color(Theme.dotInk.opacity(0.55)))
    }

    /// Cornell: columna de pistas a la izquierda, notas a la derecha y franja de
    /// resumen abajo. Renglones de lado a lado como el rayado; divisiones en el rojo
    /// suave del margen.
    private static func drawCornell(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let w = size.width
        let mx = templateMargin(w)
        let headerY = drawHeader(&ctx, size: size, lineWidth: lineWidth, title: "Tema", fields: ["Fecha"])
        let bottom = size.height - templateBottom(w)
        let s = ruleSpacing(forWidth: w)
        let cueX = w * 0.3
        let summaryTop = bottom - w * 0.27

        var lines = Path()
        var y = headerY + s * 1.5
        while y <= summaryTop - s * 0.5 {
            hLine(&lines, 0, w, y)
            y += s
        }
        y = summaryTop + s * 1.5
        while y <= bottom {
            hLine(&lines, 0, w, y)
            y += s
        }
        ctx.stroke(lines, with: .color(Theme.ruleInk.opacity(0.6)), lineWidth: lineWidth)

        var dividers = Path()
        vLine(&dividers, cueX, headerY, summaryTop)
        hLine(&dividers, 0, w, summaryTop)
        ctx.stroke(dividers, with: .color(Theme.marginInk.opacity(0.55)), lineWidth: lineWidth * 1.1)

        let labelSize = w * 0.019
        let labelY = headerY + s * 0.75
        label(&ctx, "Pistas", at: CGPoint(x: mx, y: labelY), anchor: .leading, size: labelSize, italic: true)
        label(&ctx, "Notas", at: CGPoint(x: cueX + w * 0.03, y: labelY), anchor: .leading,
              size: labelSize, italic: true)
        label(&ctx, "Resumen", at: CGPoint(x: mx, y: summaryTop + s * 0.75), anchor: .leading,
              size: labelSize, italic: true)
    }

    /// Pentagrama: nueve pentagramas repartidos por igual, con barra inicial y final.
    private static func drawStaff(_ ctx: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let w = size.width
        let mx = templateMargin(w)
        let top = drawHeader(&ctx, size: size, lineWidth: lineWidth, title: "Título") + w * 0.075
        let bottom = size.height - templateBottom(w) - w * 0.01
        let gap = w * 0.0125              // entre líneas de un pentagrama
        let staffHeight = gap * 4
        let count = 9
        let pitch = (bottom - top - staffHeight) / CGFloat(count - 1)
        guard pitch > staffHeight else { return }

        var lines = Path(), bars = Path()
        for i in 0..<count {
            let y0 = top + CGFloat(i) * pitch
            for k in 0..<5 { hLine(&lines, mx, w - mx, y0 + gap * CGFloat(k)) }
            vLine(&bars, mx, y0, y0 + staffHeight)
            vLine(&bars, w - mx, y0, y0 + staffHeight)
        }
        ctx.stroke(lines, with: .color(Theme.ruleInk.opacity(0.8)), lineWidth: lineWidth * 0.95)
        ctx.stroke(bars, with: .color(Theme.ruleInk.opacity(0.85)), lineWidth: lineWidth * 1.1)
    }
}

#Preview("Papeles") {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(220), spacing: 16), count: 4), spacing: 16) {
        ForEach(PaperStyle.allCases) { style in
            VStack {
                PaperBackground(style: style)
                    .aspectRatio(Theme.pageAspect, contentMode: .fit)
                    .frame(width: 220)
                    .shadow(color: Theme.shadow, radius: 4, y: 2)
                Text(style.label).font(Theme.Fonts.caption)
            }
        }
    }
    .padding(30)
    .background(Theme.desk)
}

#Preview("Plantillas en miniatura") {
    HStack(spacing: 14) {
        ForEach([PaperStyle.weekly, .todo, .cornell, .staff]) { style in
            PaperBackground(style: style)
                .frame(width: 120, height: 120 / Theme.pageAspect)
                .shadow(color: Theme.shadow, radius: 2, y: 1)
        }
    }
    .padding(30)
    .background(Theme.desk)
}
