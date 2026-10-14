import CoreGraphics
import XCTest
@testable import MiGestorKMPMac

final class PlannerDaySheetPDFRendererTests: XCTestCase {
    private func entry(_ index: Int) -> PlannerDaySheetEntry {
        PlannerDaySheetEntry(
            time: "0\(8 + index % 2):30",
            group: "Grupo de prueba \(index)",
            title: "Sesión de prueba \(index): juegos cooperativos",
            objective: "Practicar la cooperación en pequeños grupos con reglas sencillas.",
            steps: [
                .init(minutes: 10, title: "Calentamiento por parejas"),
                .init(minutes: 25, title: "Circuito cooperativo en cuatro estaciones"),
                .init(minutes: 15, title: "Juego final con todo el grupo"),
                .init(minutes: nil, title: "Vuelta a la calma y reflexión")
            ],
            materials: ["Conos", "Petos de colores", "Pelotas blandas"],
            attention: ["Revisar la hidratación antes del circuito"]
        )
    }

    func testPagesGroupThreeSessionsPerSheet() {
        XCTAssertEqual(PlannerDaySheetPDFRenderer.pages(for: []).count, 0)
        XCTAssertEqual(PlannerDaySheetPDFRenderer.pages(for: (0..<1).map(entry)).map(\.count), [1])
        XCTAssertEqual(PlannerDaySheetPDFRenderer.pages(for: (0..<3).map(entry)).map(\.count), [3])
        XCTAssertEqual(PlannerDaySheetPDFRenderer.pages(for: (0..<4).map(entry)).map(\.count), [3, 1])
        XCTAssertEqual(PlannerDaySheetPDFRenderer.pages(for: (0..<7).map(entry)).map(\.count), [3, 3, 1])
    }

    func testColumnsFitInsideA3Landscape() {
        let page = CGRect(origin: .zero, size: PlannerDaySheetPDFRenderer.pageSize)
        let columns = (0..<3).map(PlannerDaySheetPDFRenderer.columnRect(index:))
        columns.forEach { XCTAssertTrue(page.contains($0)) }
        XCTAssertFalse(columns[0].intersects(columns[1]))
        XCTAssertFalse(columns[1].intersects(columns[2]))
    }

    func testRendersA3LandscapePages() throws {
        let data = try XCTUnwrap(PlannerDaySheetPDFRenderer.render(entries: (0..<4).map(entry), dayLabel: "Lunes de prueba"))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 2)
        let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 1191)
        XCTAssertEqual(box.height, 842)

        if let output = ProcessInfo.processInfo.environment["PLANNER_DAY_SHEET_SAMPLE"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
    }

    func testEmptyDayProducesNoPDF() {
        XCTAssertNil(PlannerDaySheetPDFRenderer.render(entries: [], dayLabel: "Vacío"))
    }
}
