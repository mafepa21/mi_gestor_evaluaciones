import SwiftUI

/// Dibujos de pista por nivel para las rúbricas visuales de la app.
///
/// El criterio solo guarda una clave (`rubric_criteria.visual_key`); los dibujos
/// viven aquí. Una clave desconocida no rompe nada: el criterio se pinta con texto.
/// Las escenas van de menos a más (0 = nivel con menos puntos) y se dibujan en un
/// lienzo de 160 × 96 puntos: campo visto desde arriba, se ataca hacia la derecha.
enum RubricVisuals {
    struct Option: Identifiable, Hashable {
        let key: String
        let title: String
        let summary: String
        var id: String { key }
    }

    static let options: [Option] = [
        Option(key: "hockey.dribble_flat_face", title: "Hockey · Conducción con la cara plana",
               summary: "Qué cara del stick toca la bola y si mantiene el control en el slalom."),
        Option(key: "hockey.push_flick", title: "Hockey · Pase push y flick",
               summary: "Si el pase raso llega y si el flick supera el obstáculo o la línea rival."),
        Option(key: "hockey.shot_on_goal", title: "Hockey · Tiro a portería",
               summary: "Fuera, al centro, a una esquina o con amago al portero."),
    ]

    static func isKnown(_ key: String?) -> Bool {
        guard let key else { return false }
        return options.contains { $0.key == key }
    }

    static func option(for key: String?) -> Option? {
        options.first { $0.key == key }
    }

    /// Escena para el puesto del nivel (0 = el de menos puntos). Nil si no hay dibujo.
    static func scene(key: String?, rank: Int) -> Scene? {
        guard let scenes = key.flatMap({ catalog[$0] }), scenes.indices.contains(rank) else { return nil }
        return scenes[rank]
    }

    // MARK: - Piezas

    enum Mark {
        /// Alumno evaluado (amarillo) o rival (gris).
        case player(CGPoint, isStudent: Bool)
        case ball(CGPoint)
        case cone(CGPoint)
        /// Trayectoria de la bola (blanca, continua) o del alumno (amarilla, discontinua).
        case shot(Path)
        case run(Path)
        case lob(Path)
        /// Falta o bola perdida: disco oscuro con aspa (no depende del rojo).
        case miss(CGPoint)
        case goal
        case target(CGRect)
        case post(CGRect)
        /// Cabeza del stick abajo a la derecha: cara plana (bien) o redondeada (mal).
        case stick(flatFace: Bool)
    }

    struct Scene {
        let marks: [Mark]
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func line(_ points: CGPoint...) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private static let cones: [Mark] = [.cone(p(46, 48)), .cone(p(66, 40)), .cone(p(86, 56)), .cone(p(106, 40))]
    private static var slalom: Path {
        var path = Path()
        path.move(to: p(14, 48))
        path.addCurve(to: p(46, 40), control1: p(30, 48), control2: p(36, 36))
        path.addCurve(to: p(70, 50), control1: p(56, 44), control2: p(60, 56))
        path.addCurve(to: p(96, 44), control1: p(80, 44), control2: p(84, 36))
        path.addCurve(to: p(128, 48), control1: p(108, 52), control2: p(116, 48))
        return path
    }
    private static var flick: Path {
        var path = Path()
        path.move(to: p(24, 48))
        path.addQuadCurve(to: p(112, 46), control: p(66, 18))
        return path
    }

    private static let catalog: [String: [Scene]] = [
        "hockey.dribble_flat_face": [
            Scene(marks: [.run(line(p(14, 48), p(40, 48))), .ball(p(42, 54)), .miss(p(58, 58)),
                          .player(p(14, 48), isStudent: true), .stick(flatFace: false)]),
            Scene(marks: [.run(line(p(14, 48), p(58, 48))), .ball(p(60, 48))] + cones +
                  [.miss(p(70, 44)), .player(p(14, 48), isStudent: true), .stick(flatFace: true)]),
            Scene(marks: [.run(slalom)] + cones +
                  [.ball(p(130, 48)), .player(p(14, 48), isStudent: true), .stick(flatFace: true)]),
            Scene(marks: [.run(slalom)] + cones +
                  [.player(p(122, 34), isStudent: false), .ball(p(132, 52)),
                   .player(p(124, 50), isStudent: true), .stick(flatFace: true)]),
        ],
        "hockey.push_flick": [
            Scene(marks: [.shot(line(p(24, 48), p(96, 20))), .miss(p(98, 18)),
                          .player(p(20, 48), isStudent: true), .player(p(120, 48), isStudent: false)]),
            Scene(marks: [.shot(line(p(24, 48), p(112, 64))), .ball(p(112, 64)),
                          .player(p(20, 48), isStudent: true), .player(p(120, 48), isStudent: true)]),
            Scene(marks: [.post(CGRect(x: 64, y: 42, width: 4, height: 12)),
                          .shot(line(p(24, 48), p(112, 48))), .lob(flick),
                          .player(p(20, 48), isStudent: true), .player(p(120, 48), isStudent: true)]),
            Scene(marks: [.shot(line(p(24, 48), p(118, 48))),
                          .player(p(62, 38), isStudent: false), .player(p(62, 58), isStudent: false),
                          .player(p(86, 28), isStudent: false),
                          .player(p(20, 48), isStudent: true), .player(p(124, 48), isStudent: true)]),
        ],
        "hockey.shot_on_goal": [
            Scene(marks: [.goal, .shot(line(p(104, 48), p(148, 16))), .miss(p(148, 14)),
                          .player(p(100, 48), isStudent: true)]),
            Scene(marks: [.goal, .shot(line(p(104, 48), p(142, 48))), .ball(p(142, 48)),
                          .player(p(148, 48), isStudent: false), .player(p(100, 48), isStudent: true)]),
            Scene(marks: [.goal, .target(CGRect(x: 146, y: 34, width: 8, height: 8)),
                          .target(CGRect(x: 146, y: 54, width: 8, height: 8)),
                          .player(p(148, 48), isStudent: false),
                          .shot(line(p(104, 48), p(150, 38))), .player(p(100, 48), isStudent: true)]),
            Scene(marks: [.goal, .target(CGRect(x: 146, y: 34, width: 8, height: 8)),
                          .target(CGRect(x: 146, y: 54, width: 8, height: 8)),
                          .run(line(p(148, 48), p(146, 38))), .player(p(146, 38), isStudent: false),
                          .shot(line(p(104, 48), p(150, 58))), .player(p(100, 48), isStudent: true)]),
        ],
    ]
}

/// Pinta una escena de `RubricVisuals`. La trayectoria se dibuja una vez al
/// aparecer, salvo con «Reducir movimiento», que muestra el dibujo final.
struct RubricVisualSceneView: View {
    let scene: RubricVisuals.Scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    static let canvasSize = CGSize(width: 160, height: 96)
    private static let pitch = Color(red: 0.12, green: 0.42, blue: 0.31)
    private static let student = Color(red: 1.0, green: 0.77, blue: 0.24)
    private static let rival = Color(red: 0.91, green: 0.92, blue: 0.94)
    private static let ink = Color(red: 0.08, green: 0.08, blue: 0.10)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.canvasSize.width, size.height / Self.canvasSize.height)
            context.scaleBy(x: scale, y: scale)
            drawPitch(in: &context)
            for mark in scene.marks { draw(mark, in: &context) }
        }
        .aspectRatio(Self.canvasSize, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            progress = 0
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { progress = 1 }
        }
    }

    private func drawPitch(in context: inout GraphicsContext) {
        let field = CGRect(origin: .zero, size: Self.canvasSize)
        context.fill(Path(field), with: .color(Self.pitch))
        context.stroke(Path(field.insetBy(dx: 6, dy: 6)), with: .color(.white.opacity(0.7)), lineWidth: 1.2)
        var half = Path()
        half.move(to: CGPoint(x: 80, y: 6))
        half.addLine(to: CGPoint(x: 80, y: 90))
        context.stroke(half, with: .color(.white.opacity(0.5)), lineWidth: 1)
    }

    private func draw(_ mark: RubricVisuals.Mark, in context: inout GraphicsContext) {
        switch mark {
        case let .player(center, isStudent):
            let circle = Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
            context.fill(circle, with: .color(isStudent ? Self.student : Self.rival))
            context.stroke(circle, with: .color(Self.ink), lineWidth: 1.4)
        case let .ball(center):
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)), with: .color(.white))
        case let .cone(center):
            var cone = Path()
            cone.move(to: CGPoint(x: center.x, y: center.y - 5))
            cone.addLine(to: CGPoint(x: center.x + 4, y: center.y + 3))
            cone.addLine(to: CGPoint(x: center.x - 4, y: center.y + 3))
            cone.closeSubpath()
            context.fill(cone, with: .color(.orange))
            context.stroke(cone, with: .color(Self.ink), lineWidth: 0.8)
        case let .shot(path):
            context.stroke(path.trimmedPath(from: 0, to: progress), with: .color(.white),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        case let .lob(path):
            context.stroke(path.trimmedPath(from: 0, to: progress), with: .color(.white),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
        case let .run(path):
            context.stroke(path.trimmedPath(from: 0, to: progress), with: .color(Self.student),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [3, 3]))
        case let .miss(center):
            context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(Self.ink))
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - 3, y: center.y - 3))
            cross.addLine(to: CGPoint(x: center.x + 3, y: center.y + 3))
            cross.move(to: CGPoint(x: center.x + 3, y: center.y - 3))
            cross.addLine(to: CGPoint(x: center.x - 3, y: center.y + 3))
            context.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        case .goal:
            context.stroke(Path(CGRect(x: 146, y: 34, width: 8, height: 28)), with: .color(.white), lineWidth: 2)
            var circle = Path()
            circle.addArc(center: CGPoint(x: 154, y: 48), radius: 34, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
            context.stroke(circle, with: .color(.white.opacity(0.6)), lineWidth: 1)
        case let .target(rect):
            context.fill(Path(rect), with: .color(.white.opacity(0.28)))
            context.stroke(Path(rect), with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case let .post(rect):
            context.fill(Path(rect), with: .color(.orange))
        case let .stick(flatFace):
            drawStick(flatFace: flatFace, in: &context)
        }
    }

    /// Cabeza del stick: la cara plana (izquierda) va marcada en amarillo cuando
    /// toca la bola; si toca con la redondeada, esa curva va marcada en oscuro con aspa.
    private func drawStick(flatFace: Bool, in context: inout GraphicsContext) {
        let wood = Color(red: 0.79, green: 0.65, blue: 0.42)
        context.fill(Path(CGRect(x: 136, y: 50, width: 4, height: 24)), with: .color(wood))
        var hook = Path()
        hook.move(to: CGPoint(x: 136, y: 74))
        hook.addQuadCurve(to: CGPoint(x: 148, y: 86), control: CGPoint(x: 136, y: 86))
        hook.addQuadCurve(to: CGPoint(x: 154, y: 79), control: CGPoint(x: 154, y: 86))
        context.stroke(hook, with: .color(wood), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        if flatFace {
            var face = Path()
            face.move(to: CGPoint(x: 134, y: 72))
            face.addLine(to: CGPoint(x: 134, y: 84))
            context.stroke(face, with: .color(Self.student), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        } else {
            var back = Path()
            back.move(to: CGPoint(x: 147, y: 89))
            back.addQuadCurve(to: CGPoint(x: 157, y: 79), control: CGPoint(x: 157, y: 89))
            context.stroke(back, with: .color(Self.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
