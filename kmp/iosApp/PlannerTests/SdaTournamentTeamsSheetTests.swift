import XCTest
import PDFKit
@testable import MiGestorKMPMac

/// Integrantes de los equipos del torneo y hoja imprimible A4.
@MainActor
final class SdaTournamentTeamsSheetTests: XCTestCase {
    private func resolved(_ name: String, members: Int) -> SdaResolvedTeam {
        SdaResolvedTeam(id: name, name: name, memberNames: (1...max(members, 1)).prefix(members).map { "Alumno \($0)" })
    }

    private func round(_ pairs: [(String, String)]) -> SdaFirstRound {
        SdaFirstRound(
            title: "Primera ronda",
            matches: pairs.enumerated().map { SdaFirstRound.Match(venue: $0.offset + 1, text: "\($0.element.0) – \($0.element.1)") },
            resting: []
        )
    }

    func testResolverUsaLosIdsDelTorneoYOrdenaPorNombre() {
        let teams = [TournamentPlanTeam(id: "1", name: "Halcones", studentIDs: ["3", "1", "99", "2"])]
        let students: [(id: String, name: String)] = [("1", "Carla"), ("2", "Ana"), ("3", "Bruno"), ("4", "Otro")]
        let result = SdaTournamentRoster.resolve(teams: teams, students: students)
        XCTAssertEqual(result.first?.memberNames, ["Ana", "Bruno", "Carla", "Alumno no encontrado"])
        XCTAssertEqual(result.first?.countText, "4 alumnos")
    }

    func testEquipoVacio() {
        let result = SdaTournamentRoster.resolve(teams: [TournamentPlanTeam(id: "1", name: "Zorros")], students: [])
        XCTAssertEqual(result.first?.memberNames, [])
        XCTAssertEqual(result.first?.countText, "Sin alumnos")
    }

    func testOchoEquiposDeSeisCabenEnUnaPaginaConPrimeraRonda() {
        let teams = (1...8).map { resolved("Equipo \($0)", members: 6) }
        let first = round([("Equipo 1", "Equipo 2"), ("Equipo 3", "Equipo 4"), ("Equipo 5", "Equipo 6"), ("Equipo 7", "Equipo 8")])
        let pages = SdaTeamsSheetLayout.paginate(teams: teams, firstRound: first)
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(pages[0].showsFirstRound)
    }

    func testDoceEquiposNecesitanVariasPaginasYLaPrimeraRondaVaAlFinal() {
        let teams = (1...12).map { resolved("Equipo \($0)", members: 6) }
        let first = round([("Equipo 1", "Equipo 2")])
        let pages = SdaTeamsSheetLayout.paginate(teams: teams, firstRound: first)
        XCTAssertGreaterThanOrEqual(pages.count, 2)
        XCTAssertEqual(pages.filter(\.showsFirstRound).count, 1)
        XCTAssertTrue(pages.last?.showsFirstRound ?? false)
        XCTAssertEqual(pages.flatMap(\.rows).flatMap { $0 }.count, 12)
    }

    func testElPDFTieneLasPaginasCalculadasYTamanoA4() throws {
        for count in [8, 12] {
            let teams = (1...count).map { resolved("Equipo \($0)", members: 6) }
            let first = round([("Equipo 1", "Equipo 2"), ("Equipo 3", "Equipo 4")])
            let content = SdaTeamsSheetContent(title: "Liga", subtitle: "SdA «Red» · 1º ESO A · 14/10/2026", teams: teams, firstRound: first)
            let expected = SdaTeamsSheetLayout.pageCount(teams: teams, firstRound: first)
            let data = try XCTUnwrap(SdaTeamsSheetPDF.render(content))
            let document = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertEqual(document.pageCount, expected, "\(count) equipos")
            let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
            XCTAssertEqual(box.width, 595, accuracy: 0.5)
            XCTAssertEqual(box.height, 842, accuracy: 0.5)
        }
    }

    func testPrimeraRondaDeLiguillaEsLaDeGrupos() throws {
        var plan = TournamentPlan(name: "Prueba", format: .groupStageKnockout, teamCount: 6, groupCount: 2, venueCount: 2)
        let rounds = try TournamentScheduleGenerator.generate(
            format: plan.format,
            teamNames: plan.teamNames,
            venueCount: plan.venueCount,
            groupCount: plan.groupCount,
            qualifiedTeamsPerGroup: plan.qualifiedTeamsPerGroup
        )
        plan.persistSchedule(rounds)
        let first = try XCTUnwrap(plan.firstRoundSummary)
        XCTAssertEqual(first.title, "Primera ronda de grupos")
        XCTAssertFalse(first.matches.isEmpty)
    }
}
