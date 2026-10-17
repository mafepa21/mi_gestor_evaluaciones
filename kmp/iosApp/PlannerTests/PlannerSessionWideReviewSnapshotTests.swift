import AppKit
import SwiftUI
import XCTest
@testable import MiGestorKMPMac

/// Captura del repaso ancho (carril + dos bloques en paralelo) con una sesión
/// inventada, para revisión visual. No compara píxeles.
@MainActor
final class PlannerSessionWideReviewSnapshotTests: XCTestCase {
    private func step(_ key: String, _ minutes: Int, _ offset: Int, _ phase: String, _ title: String, _ detail: String, main: Bool = false, clil: String? = nil) -> PlannerSessionReviewStep {
        PlannerSessionReviewStep(
            activityKey: key, minutes: minutes, startOffsetMinutes: offset, phase: phase, title: title,
            detail: detail, clil: clil, isMain: main, isCollection: false,
            extras: [.init(label: "Material", text: "Raquetas y volantes")]
        )
    }

    func testRenderWideReviewForReview() throws {
        let tint = Color.teal
        let first = [
            step("a1", 4, 0, "Explicación inicial", "Explicación inicial", "Repaso rápido de la clasificación provisional y reparto de pistas.", clil: "Every point counts"),
            step("a2", 4, 4, "Activación", "Tulip Tag", "Raquetas fuera. Tres o cuatro pillan con un cono; para salvarte, grita «Tulip!» y quédate quieto con brazos y piernas abiertos."),
            step("a3", 26, 8, "Actividad principal", "Decisive Pool Matches", "Partidos de grupo de 6 minutos. Las parejas árbitro suman puntos a favor y en contra. Al final, posiciones 1º a 6º de cada grupo.", main: true),
            step("a4", 6, 34, "Reflexión", "Reflexión", "Anunciar el cuadro final de cada nivel."),
        ]
        let second = [
            step("b1", 4, 40, "Explicación inicial", "Explicación inicial", "Cuadro final y pistas. Saludo antes y después de cada partido.", clil: "Championship round"),
            step("b2", 6, 44, "Activación", "Cops and Robbers", "Unos pocos policías pillan; quien es pillado hace saltos en la zona segura hasta que le choquen la mano."),
            step("b3", 24, 50, "Actividad principal", "Level Finals", "Semifinales, tercer puesto y finales en los tres niveles. Partidos de 7 minutos o 15 puntos; quien no juega, arbitra.", main: true),
            step("b4", 6, 74, "Reflexión", "Reflexión", "Entrega de hojas de arbitraje."),
        ]
        let view = HStack(alignment: .top, spacing: 0) {
            PlannerReviewBrief(
                objective: "Últimos partidos de grupo y finales de nivel con arbitraje riguroso.",
                setup: ["Mismos tres grupos y pistas", "Árbitros con la hoja de puntos", "Semis 1º v 4º y 2º v 3º"],
                attention: ["Burbuja de raqueta: un brazo de distancia"],
                tint: tint
            )
            .padding(24)
            .frame(width: PlannerSessionDetailLayoutPolicy.railWidth)
            Divider()
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    PlannerReviewBlockHeader(title: "U10 · Round Robin · 40 min", tint: tint)
                    ForEach(first) { PlannerReviewStepRow(step: $0, tint: tint, visualHTML: nil, isWide: true) { _ in } }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 16) {
                    PlannerReviewBlockHeader(title: "U11 · Level finals · 40 min · tras descanso 15'", tint: tint)
                    ForEach(second) { PlannerReviewStepRow(step: $0, tint: tint, visualHTML: nil, isWide: true) { _ in } }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(24)
        }
        .frame(width: 1_400)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("planner-wide-review.png")
        try png.write(to: url)
        print("CAPTURA \(url.path) alto=\(image.size.height)")
    }
}
