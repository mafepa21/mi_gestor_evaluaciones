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
                .init(minutes: 25, title: "Circuito cooperativo en cuatro estaciones", detail: "Grupos de cuatro rotan cada seis minutos. Cada estación tiene una tarjeta con la consigna y una variante más difícil."),
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

    func testShortDetailCutsLongTextAtAWord() {
        let long = String(repeating: "palabra ", count: 60)
        let short = PlannerDaySheetEntry.Step.shortDetail(long)
        XCTAssertLessThanOrEqual(short.count, PlannerDaySheetEntry.Step.maxDetailLength + 1)
        XCTAssertTrue(short.hasSuffix("palabra…"))
        XCTAssertEqual(PlannerDaySheetEntry.Step.shortDetail("Uno\nDos"), "Uno Dos")
    }

    func testMaterialKeepsCommasAndParenthesesTogether() {
        let material = "Cones, one racket per student (courts included). Court group (12 pairs; 2 pairs per court)\nWhistle — Saberes básicos: grips"
        XCTAssertEqual(PlannerDaySheetEntry.materialItems(material), [
            "Cones, one racket per student (courts included). Court group (12 pairs; 2 pairs per court)",
            "Whistle"
        ])
    }

    func testEmptyDayProducesNoPDF() {
        XCTAssertNil(PlannerDaySheetPDFRenderer.render(entries: [], dayLabel: "Vacío"))
    }

    // MARK: Guion de clase

    private static let sampleTeacherText = """
    «Split-Step Traffic Lights»: Whole group moves in the free space ...
    Muestra: Haz tú los tres colores mientras los nombras.
    Di: Green: run to the net.
    Di: Yellow: side steps.
    Di: Red: split step. Freeze!
    Comprueba: Red. Show me. → Hacen el split step.
    Comprueba: Green. Where do you go? → Señalan la red.
    Corrección: Soft touch.
    """

    func testReaderRecognisesAllLabels() {
        let text = """
        - **Muestra:** Demo corta
        • DI: One
        Di: Two
        Comprueba: Pregunta A -> Respuesta A
        Comprueba: Solo pregunta
        Regla: Una
        Regla: Dos
        Correccion: Sin tilde
        CORRECCIÓN: Con tilde
        Seguridad: Mirar alrededor
        Pizarra: net, split step
        """
        let labels = PlannerSessionClassScript.labels(in: text)
        XCTAssertEqual(labels.show, "Demo corta")
        XCTAssertEqual(labels.say, ["One", "Two"])
        XCTAssertEqual(labels.checks, [
            .init(question: "Pregunta A", answer: "Respuesta A"),
            .init(question: "Solo pregunta", answer: nil)
        ])
        XCTAssertEqual(labels.rules, ["Una", "Dos"])
        XCTAssertEqual(labels.corrections, ["Sin tilde", "Con tilde"])
        XCTAssertEqual(labels.safety, ["Mirar alrededor"])
        XCTAssertEqual(labels.board, "net, split step")
    }

    func testReaderKeepsOrderAndInnerColons() {
        let labels = PlannerSessionClassScript.labels(in: Self.sampleTeacherText)
        XCTAssertEqual(labels.say, ["Green: run to the net.", "Yellow: side steps.", "Red: split step. Freeze!"])
        XCTAssertEqual(labels.checks.map(\.answer), ["Hacen el split step.", "Señalan la red."])
        XCTAssertEqual(labels.checks.first?.question, "Red. Show me.")
    }

    func testReaderDoesNotTakeDiPrefixedWords() {
        let labels = PlannerSessionClassScript.labels(in: "Dibujo: un círculo\nDinámica: por parejas\nDirecciones: norte")
        XCTAssertTrue(labels.say.isEmpty)
        XCTAssertFalse(labels.hasActivityContent)
        XCTAssertNil(PlannerSessionClassScript.labelAndText(of: "Dibujo: x"))
        XCTAssertEqual(PlannerSessionClassScript.labelAndText(of: "Dí: x")?.label, "di")
    }

    func testSessionWithoutLabelsHasNoScriptAndKeepsBody() {
        let plain = entry(0)
        XCTAssertTrue(plain.script.isEmpty)
        let script = PlannerSessionClassScript(activities: [(title: "A", minutes: 5, teacherText: "Texto libre sin etiquetas")])
        XCTAssertTrue(script.isEmpty)
        XCTAssertEqual(PlannerDaySheetPDFRenderer.scriptPages(for: [plain]).count, 0)
        let withEmptyScript = PlannerDaySheetEntry(
            time: plain.time, group: plain.group, title: plain.title, objective: plain.objective,
            steps: plain.steps, materials: plain.materials, attention: plain.attention, script: script
        )
        XCTAssertEqual(
            PlannerDaySheetPDFRenderer.body(for: withEmptyScript).string,
            PlannerDaySheetPDFRenderer.body(for: plain).string
        )
        XCTAssertEqual(PlannerSessionClassScript.removingLabelLines(from: "Uno\nDos"), "Uno\nDos")
    }

    func testLabelLinesAreRemovedFromStepDetail() {
        let detail = PlannerSessionClassScript.removingLabelLines(from: Self.sampleTeacherText)
        XCTAssertEqual(detail, "«Split-Step Traffic Lights»: Whole group moves in the free space ...")
        let bulleted = PlannerSessionClassScript.removingLabelLines(from: "• Muestra: demo\n• Texto que se queda")
        XCTAssertEqual(bulleted, "• Texto que se queda")
    }

    func testScriptAddsExtraPagesOnlyForSessionsWithScript() throws {
        let script = PlannerSessionClassScript(activities: [
            (title: "Split-Step Traffic Lights", minutes: 10, teacherText: Self.sampleTeacherText + "\nPizarra: split step")
        ])
        XCTAssertEqual(script.board, "split step")
        XCTAssertEqual(script.activities.count, 1)
        let withScript = PlannerDaySheetEntry(
            time: "09:00", group: "1º BAC A", title: "Tenis", objective: "Objetivo",
            steps: [.init(minutes: 10, title: "Split-Step Traffic Lights", detail: "Whole group moves")],
            materials: [], attention: [], script: script
        )
        let entries = [entry(0), withScript]
        XCTAssertEqual(PlannerDaySheetPDFRenderer.scriptPages(for: entries).map(\.count), [1])

        let data = try XCTUnwrap(PlannerDaySheetPDFRenderer.render(entries: entries, dayLabel: "Lunes de prueba"))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 2)
        let box = try XCTUnwrap(document.page(at: 2)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 1191)

        let plain = try XCTUnwrap(PlannerDaySheetPDFRenderer.render(entries: [entry(0), entry(1)], dayLabel: "Lunes de prueba"))
        XCTAssertEqual(CGPDFDocument(CGDataProvider(data: plain as CFData)!)?.numberOfPages, 1)

        let body = PlannerDaySheetPDFRenderer.scriptBody(for: script).string
        XCTAssertTrue(body.contains("10′  Split-Step Traffic Lights"))
        XCTAssertTrue(body.contains("1. Green: run to the net."))
        XCTAssertTrue(body.contains("Red. Show me. → Hacen el split step."))

        if let output = ProcessInfo.processInfo.environment["PLANNER_DAY_SHEET_SCRIPT_SAMPLE"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
    }
}
