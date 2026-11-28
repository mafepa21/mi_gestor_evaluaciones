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
        Option(key: "hockey.dribble_flat_face", title: "Hockey · Slalom de 4 conos con la cara plana",
               summary: "Salida y slalom estrecho (4 conos a 30 cm) usando solo la cara plana del stick."),
        Option(key: "hockey.push_flick", title: "Hockey · Pase push a la pared y control tras rebote",
               summary: "Pase raso firme contra la pared y recepción amortiguada tras el rebote."),
        Option(key: "hockey.shot_on_goal", title: "Hockey · Vuelta al slalom y parada en línea de inicio",
               summary: "Regreso en zigzag por los 4 conos y detención controlada antes de la línea de salida."),
        Option(key: "coop.motor_adaptability", title: "Retos cooperativos · Adaptación motriz",
               summary: "Equilibrio y apoyo del equipo sobre la colchoneta o el banco sin tocar el suelo."),
        Option(key: "coop.tactical_roles", title: "Retos cooperativos · Diseño táctico y liderazgo compartido",
               summary: "Aportación del alumno a la decisión del equipo y reparto de roles."),
        Option(key: "coop.inclusive_dialogue", title: "Retos cooperativos · Diálogo inclusivo",
               summary: "Círculo de diálogo donde todas las personas participan y los conflictos se resuelven."),
        Option(key: "coop.rally_execution", title: "Retos cooperativos · Ejecución del rally",
               summary: "Recorrido de tres estaciones con transiciones y penalizaciones hasta la meta."),
        Option(key: "coop.challenge_creation", title: "Retos cooperativos · Creación de un reto",
               summary: "Diseño de un reto con recorrido, reglas, seguridad y niveles de dificultad."),
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
        /// Pared de rebote (derecha) o línea de salida/llegada (izquierda).
        case wall
        case startLine
        /// Cabeza del stick abajo a la derecha: cara plana (bien) o redondeada (mal).
        case stick(flatFace: Bool)
        /// Colchoneta o banco (rectángulo claro con borde).
        case mat(CGRect)
        /// Contacto o cuerda entre personas (trazo blanco grueso, puede ser ondulado).
        case link(Path)
        /// Flecha de intención o aportación (de un punto a otro).
        case arrow(CGPoint, CGPoint)
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

    /// 4 conos muy juntos (~30 cm en pista) para el slalom de ida y vuelta.
    private static let cones: [Mark] = [.cone(p(52, 48)), .cone(p(68, 40)), .cone(p(84, 56)), .cone(p(100, 40))]
    private static var slalomOut: Path {
        var path = Path()
        path.move(to: p(18, 48))
        path.addCurve(to: p(52, 38), control1: p(34, 48), control2: p(42, 36))
        path.addCurve(to: p(68, 52), control1: p(58, 40), control2: p(62, 54))
        path.addCurve(to: p(84, 42), control1: p(74, 50), control2: p(78, 38))
        path.addCurve(to: p(118, 48), control1: p(92, 46), control2: p(106, 48))
        return path
    }
    private static var slalomBack: Path {
        var path = Path()
        path.move(to: p(124, 48))
        path.addCurve(to: p(100, 52), control1: p(114, 48), control2: p(106, 54))
        path.addCurve(to: p(84, 42), control1: p(94, 50), control2: p(90, 38))
        path.addCurve(to: p(68, 52), control1: p(78, 46), control2: p(74, 54))
        path.addCurve(to: p(28, 48), control1: p(56, 46), control2: p(40, 48))
        return path
    }
    private static var wallBounceGood: Path {
        var path = Path()
        path.move(to: p(96, 48))
        path.addLine(to: p(145, 44))
        path.addLine(to: p(108, 56))
        return path
    }
    private static var wallBounceFast: Path {
        var path = Path()
        path.move(to: p(96, 44))
        path.addLine(to: p(145, 48))
        path.addLine(to: p(104, 56))
        return path
    }

    // MARK: - Retos cooperativos

    private static let coopMat = CGRect(x: 48, y: 30, width: 72, height: 36)
    private static func wavy(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        let mid = p((a.x + b.x) / 2, (a.y + b.y) / 2)
        path.addQuadCurve(to: mid, control: p(mid.x - 4, mid.y - 8))
        path.addQuadCurve(to: b, control: p(mid.x + 4, mid.y + 8))
        return path
    }
    /// Círculo de 5 personas alrededor de (80, 48), radio 26; el índice 0 queda arriba.
    private static let circle5: [CGPoint] = [p(80, 22), p(104.7, 40), p(95.3, 69), p(64.7, 69), p(55.3, 40)]
    private static func others(_ points: [CGPoint]) -> [Mark] { points.map { Mark.player($0, isStudent: false) } }
    private static var circleLinks: [Mark] {
        circle5.indices.map { i in Mark.link(line(circle5[i], circle5[(i + 1) % circle5.count])) }
    }
    private static let rallyCones: [Mark] = [.cone(p(52, 48)), .cone(p(88, 48)), .cone(p(120, 48))]
    private static let finishZone: Mark = .target(CGRect(x: 134, y: 30, width: 16, height: 36))
    private static let coopCentre: Mark = .target(CGRect(x: 70, y: 40, width: 20, height: 16))

    private static let catalog: [String: [Scene]] = [
        "hockey.dribble_flat_face": [
            Scene(marks: [.startLine, .run(line(p(18, 48), p(44, 48))), .ball(p(46, 54)), .miss(p(60, 58)),
                          .player(p(18, 48), isStudent: true), .stick(flatFace: false)]),
            Scene(marks: [.startLine, .run(line(p(18, 48), p(62, 48))), .ball(p(64, 48))] + cones +
                  [.miss(p(74, 44)), .player(p(18, 48), isStudent: true), .stick(flatFace: true)]),
            Scene(marks: [.startLine, .run(slalomOut)] + cones +
                  [.ball(p(122, 48)), .player(p(18, 48), isStudent: true), .stick(flatFace: true)]),
            Scene(marks: [.startLine, .run(slalomOut)] + cones +
                  [.ball(p(124, 48)), .player(p(116, 48), isStudent: true), .stick(flatFace: true)]),
        ],
        "hockey.push_flick": [
            Scene(marks: [.wall, .shot(line(p(92, 48), p(134, 24))), .miss(p(134, 22)),
                          .player(p(88, 48), isStudent: true)]),
            Scene(marks: [.wall, .shot(line(p(92, 48), p(145, 46), p(116, 72))), .miss(p(116, 74)),
                          .player(p(88, 48), isStudent: true)]),
            Scene(marks: [.wall, .shot(wallBounceGood), .ball(p(108, 56)),
                          .player(p(100, 52), isStudent: true)]),
            Scene(marks: [.wall, .shot(wallBounceFast), .run(line(p(104, 56), p(82, 52))),
                          .ball(p(80, 52)), .player(p(96, 54), isStudent: true)]),
        ],
        "hockey.shot_on_goal": [
            Scene(marks: [.startLine] + cones +
                  [.run(line(p(124, 48), p(84, 34))), .miss(p(84, 32)),
                   .player(p(124, 48), isStudent: true)]),
            Scene(marks: [.startLine] + cones +
                  [.run(slalomBack), .shot(line(p(28, 48), p(10, 48))), .miss(p(10, 48)),
                   .player(p(26, 48), isStudent: true)]),
            Scene(marks: [.startLine, .target(CGRect(x: 20, y: 36, width: 14, height: 24))] + cones +
                  [.run(slalomBack), .ball(p(25, 48)), .player(p(32, 48), isStudent: true)]),
            Scene(marks: [.startLine, .target(CGRect(x: 20, y: 36, width: 14, height: 24))] + cones +
                  [.run(slalomBack), .ball(p(24, 48)), .player(p(28, 48), isStudent: true), .stick(flatFace: true)]),
        ],
        "coop.motor_adaptability": [
            Scene(marks: [.mat(coopMat)] + others([p(62, 42), p(82, 42), p(102, 42), p(82, 56)]) +
                  [.miss(p(34, 76)), .player(p(30, 66), isStudent: true)]),
            Scene(marks: [.mat(coopMat), .link(wavy(p(56, 62), p(66, 44)))] + others([p(66, 40), p(90, 40), p(108, 52)]) +
                  [.player(p(54, 62), isStudent: true)]),
            Scene(marks: [.mat(coopMat)] + others([p(62, 48), p(80, 48), p(98, 48)]) +
                  [.player(p(110, 48), isStudent: true)]),
            // Nivel 4: el alumno sostiene el equilibrio del grupo (enlaces visibles con cada compañero).
            Scene(marks: [.mat(coopMat),
                          .link(line(p(84, 40), p(60, 40))), .link(line(p(84, 40), p(108, 40))), .link(line(p(84, 40), p(84, 58)))] +
                  others([p(60, 40), p(108, 40), p(84, 58)]) +
                  [.player(p(84, 40), isStudent: true)]),
        ],
        "coop.tactical_roles": [
            Scene(marks: [coopCentre] + others([circle5[0], circle5[1], circle5[2], circle5[4]]) +
                  [.miss(p(30, 70)), .player(p(22, 80), isStudent: true)]),
            Scene(marks: [coopCentre] + others([circle5[0], circle5[1], circle5[2], circle5[4]]) +
                  [.player(p(24, 22), isStudent: true)]),
            Scene(marks: [coopCentre, .arrow(p(64, 62), p(76, 54))] + others([circle5[0], circle5[1], circle5[2], circle5[4]]) +
                  [.player(circle5[3], isStudent: true)]),
            Scene(marks: [coopCentre, .arrow(p(80, 44), p(80, 29)), .arrow(p(84, 48), p(97, 42)),
                          .arrow(p(84, 52), p(91, 62)), .arrow(p(76, 48), p(62, 44))] +
                  others([circle5[0], circle5[1], circle5[2], circle5[4]]) +
                  [.player(p(80, 48), isStudent: true)]),
        ],
        "coop.inclusive_dialogue": [
            Scene(marks: others([circle5[1], circle5[2], circle5[3]]) +
                  [.player(circle5[0], isStudent: true), .miss(p(132, 74)), .player(p(144, 80), isStudent: false)]),
            Scene(marks: others([circle5[1], circle5[2], circle5[3], p(20, 26)]) +
                  [.player(circle5[0], isStudent: true)]),
            Scene(marks: others(Array(circle5[1...])) + [.player(circle5[0], isStudent: true)]),
            Scene(marks: circleLinks + others(Array(circle5[1...])) + [.player(circle5[0], isStudent: true)]),
        ],
        "coop.rally_execution": [
            Scene(marks: [.startLine, finishZone] + rallyCones +
                  [.run(line(p(18, 48), p(84, 48))), .miss(p(40, 34)), .miss(p(66, 62)), .miss(p(100, 34)),
                   .player(p(90, 48), isStudent: true)]),
            Scene(marks: [.startLine, finishZone] + rallyCones +
                  [.run(line(p(18, 48), p(112, 48))), .miss(p(70, 34)), .miss(p(100, 62)),
                   .player(p(118, 48), isStudent: true)]),
            Scene(marks: [.startLine, finishZone] + rallyCones +
                  [.run(line(p(18, 48), p(140, 48))), .miss(p(70, 62)),
                   .player(p(142, 48), isStudent: true)]),
            Scene(marks: [.startLine, finishZone] + rallyCones +
                  [.run(line(p(18, 48), p(140, 48))), .player(p(142, 48), isStudent: true)]),
        ],
        "coop.challenge_creation": [
            Scene(marks: [.miss(p(84, 48)), .player(p(30, 48), isStudent: true)]),
            Scene(marks: [.cone(p(44, 24)), .cone(p(120, 30)), .cone(p(70, 74)), .cone(p(132, 72)),
                          .player(p(86, 50), isStudent: true)]),
            Scene(marks: [.startLine, .target(CGRect(x: 132, y: 34, width: 16, height: 28)),
                          .run(line(p(18, 48), p(50, 48), p(80, 62), p(110, 40), p(132, 48))),
                          .cone(p(50, 38)), .cone(p(80, 52)), .cone(p(110, 50)),
                          .player(p(18, 48), isStudent: true)]),
            Scene(marks: [.startLine, .target(CGRect(x: 132, y: 30, width: 16, height: 36)),
                          .run(line(p(18, 48), p(40, 30), p(132, 30))), .run(line(p(18, 48), p(40, 66), p(132, 66))),
                          .cone(p(70, 40)), .cone(p(100, 40)), .cone(p(70, 56)), .cone(p(100, 56)),
                          .player(p(86, 30), isStudent: true), .player(p(60, 66), isStudent: false),
                          .player(p(110, 66), isStudent: false)]),
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
        case .wall:
            let wallRect = CGRect(x: 146, y: 18, width: 6, height: 60)
            context.fill(Path(wallRect), with: .color(Self.rival))
            context.stroke(Path(wallRect), with: .color(Self.ink), lineWidth: 1.2)
        case .startLine:
            var linePath = Path()
            linePath.move(to: CGPoint(x: 18, y: 14))
            linePath.addLine(to: CGPoint(x: 18, y: 82))
            context.stroke(linePath, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
        case let .mat(rect):
            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white.opacity(0.35)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(.white), lineWidth: 1.4)
        case let .link(path):
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        case let .arrow(from, to):
            var shaft = Path()
            shaft.move(to: from)
            shaft.addLine(to: to)
            let angle = atan2(to.y - from.y, to.x - from.x)
            for delta in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                shaft.move(to: to)
                shaft.addLine(to: CGPoint(x: to.x + 6 * cos(angle + delta), y: to.y + 6 * sin(angle + delta)))
            }
            context.stroke(shaft, with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
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
