import AppKit
import SwiftUI
import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

/// Tabla de rúbrica (`RubricMatrixView`): cuándo se usa, reparto de columnas y
/// captura con datos inventados para revisar el aspecto.
@MainActor
final class RubricMatrixLayoutTests: XCTestCase {
    private let trace = AuditTrace(
        authorUserId: nil,
        createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
        updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
        associatedGroupId: nil,
        deviceId: nil,
        syncVersion: 0
    )

    private func criterion(_ id: Int64, _ text: String, levels: [(String, Int32, String)]) -> RubricCriterionWithLevels {
        RubricCriterionWithLevels(
            criterion: RubricCriterion(id: id, rubricId: 1, description: text, weight: 1, order: Int32(id), competencyId: nil, trace: trace),
            levels: levels.enumerated().map { index, level in
                RubricLevel(
                    id: id * 10 + Int64(index),
                    criterionId: id,
                    name: level.0,
                    points: level.1,
                    description: level.2,
                    order: Int32(index),
                    trace: trace
                )
            }
        )
    }

    private func sampleCriteria() -> [RubricCriterionWithLevels] {
        let names = ["Inicial", "Básico", "Adecuado", "Avanzado"]
        let texts = [
            ["No reconoce la causa del fallo o la atribuye solo a la suerte o al material.",
             "Nombra el error de forma genérica, sin aislar qué parte del gesto falla.",
             "Identifica con precisión el factor clave: empuñadura, punto de impacto, armado o pies.",
             "Relaciona la causa con el efecto en el volante y propone señales para detectarlo rápido."],
            ["No aplica correcciones o cambia de gesto sin método ni progresión.",
             "Corrige el gesto solo cuando el docente o la pareja le dictan el paso.",
             "Elige y ensaya con autonomía tareas de ajuste y anota su progreso.",
             "Diseña sus propias tareas de ajuste y lleva la corrección al juego real."],
            ["El gesto corregido aparece de forma aislada y se pierde con la presión.",
             "Mantiene el ajuste en ejercicios cerrados, pero no en el juego.",
             "Mantiene el ajuste en la mayoría de golpes del juego libre.",
             "Ejecuta el gesto ajustado de forma estable incluso en puntos decisivos."],
        ]
        let titles = [
            "Identificación y análisis del factor clave del error",
            "Aplicación y ensayo de estrategias de ajuste",
            "Consistencia y eficacia en la ejecución ajustada",
        ]
        return (0..<3).map { c in
            criterion(Int64(c + 1), titles[c], levels: (0..<4).map { (names[$0], Int32($0 + 1), texts[c][$0]) })
        }
    }

    func testEligibleOnlyWhenAllCriteriaShareLevelCount() {
        let criteria = sampleCriteria()
        XCTAssertTrue(RubricMatrixView.isEligible(criteria))

        let uneven = criteria + [criterion(9, "Otro", levels: [("Sí", 1, ""), ("No", 0, ""), ("A veces", 1, "")])]
        XCTAssertFalse(RubricMatrixView.isEligible(uneven))
        XCTAssertFalse(RubricMatrixView.isEligible([]))

        // Mac e iPad horizontal: tabla. iPad vertical (768 pt): tarjetas.
        XCTAssertTrue(RubricMatrixView.fits(criteria, in: 1_180))
        XCTAssertTrue(RubricMatrixView.fits(criteria, in: 1_024))
        XCTAssertFalse(RubricMatrixView.fits(criteria, in: 768))
    }

    func testRowLayoutSplitsLevelColumnsEvenly() {
        let layout = RubricMatrixRowLayout(leadingWidth: 200, spacing: 8)
        let widths = layout.columnWidths(total: 1_032, count: 5)
        XCTAssertEqual(widths.first, 200)
        XCTAssertEqual(Set(widths.dropFirst()), [200])
        XCTAssertEqual(widths.reduce(0, +) + 8 * 4, 1_032, accuracy: 0.001)
    }

    /// Captura en `$TMPDIR/rubric-matrix-*.png` para revisión visual (no compara píxeles).
    func testRenderSnapshotsForReview() throws {
        let criteria = sampleCriteria()
        let selected: [Int64: Int64] = [1: 12, 2: 21]
        for hides in [false, true] {
            let view = RubricMatrixView(
                criteria: criteria,
                totalWeight: 3,
                selectedLevelIds: selected,
                activeCriterionId: 3,
                hidesDescriptions: hides,
                onActivate: { _ in },
                onSelectLevel: { _, _ in }
            )
            .padding(24)
            .frame(width: 1_240)
            .background(Color.white)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertLessThan(image.size.height, hides ? 360 : 620, "La tabla de 3 × 4 debe caber sin scroll")
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rubric-matrix-\(hides ? "compacta" : "textos").png")
            try png.write(to: url)
            print("CAPTURA \(url.path) alto=\(image.size.height)")
        }
    }
}
