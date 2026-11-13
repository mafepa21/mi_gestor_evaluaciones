import XCTest
@testable import MiGestorKMPMac

/// El prompt del Comentario LOMLOE conserva siempre los requisitos de salida,
/// aunque la evidencia nueva (issue #407) haga crecer el cuerpo.
final class LomloePromptAssemblyTests: XCTestCase {
    private let requirements = "Requisitos de salida\n- Usa 4 bloques integrados."

    func testSiCabeNoSeRecortaNada() {
        let prompt = AppleFoundationReportService.assemblePrompt(
            body: "  Valoración del docente\nMuy constante.  ",
            requirements: requirements,
            maxCharacters: 500
        )
        XCTAssertEqual(prompt, "Valoración del docente\nMuy constante.\n\n" + requirements)
    }

    func testSiNoCabeSeRecortaElCuerpoYNoLosRequisitos() {
        let body = "Valoración del docente: muy constante.\n" + String(repeating: "relleno ", count: 200)
        let prompt = AppleFoundationReportService.assemblePrompt(
            body: body,
            requirements: requirements,
            maxCharacters: 200
        )
        XCTAssertLessThanOrEqual(prompt.count, 200)
        XCTAssertTrue(prompt.hasSuffix(requirements))
        // Lo prioritario va al principio del cuerpo y sobrevive al recorte.
        XCTAssertTrue(prompt.hasPrefix("Valoración del docente: muy constante."))
        XCTAssertTrue(prompt.contains("...\n\nRequisitos de salida"))
    }

    func testElTopePorDefectoEsElDelPresupuestoDeIA() {
        let body = String(repeating: "x", count: AIContextBudget.maxPromptCharacters * 2)
        let prompt = AppleFoundationReportService.assemblePrompt(body: body, requirements: requirements)
        XCTAssertEqual(prompt.count, AIContextBudget.maxPromptCharacters)
        XCTAssertTrue(prompt.hasSuffix(requirements))
    }
}
