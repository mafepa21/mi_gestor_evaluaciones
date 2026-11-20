import Foundation
import XCTest
@testable import MiGestorKMPMac

final class WebPortalStudentPreviewTests: XCTestCase {
    func testParseBoardCompletoConTareasNotasYTorneos() throws {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let forms = [
            WebPortalFormEntry(
                title: "Autoevaluación Balonmano",
                context: "2º ESO B",
                mode: "self",
                expiresAt: now.addingTimeInterval(3600 * 48),
                url: "https://projectosef.alwaysdata.net/#f=1&a=abc",
                done: false
            ),
            WebPortalFormEntry(
                title: "Calentamiento inicial",
                context: "2º ESO B",
                mode: "self",
                expiresAt: now.addingTimeInterval(3600 * 48),
                url: "https://projectosef.alwaysdata.net/#f=2&a=abc",
                done: true
            ),
        ]
        let notas: [String: Any] = [
            "provisional": true,
            "actualizado": "2026-11-20T10:00:00Z",
            "materias": [[
                "grupo": "2º ESO B",
                "materia": "Educación Física",
                "media": ["valor": 8.4, "nivel": "Notable"],
                "actividades": [
                    ["titulo": "Juegos colectivos", "tipo": "rubrica", "valor": 8.8, "nivel": "Sobresaliente"],
                    ["titulo": "Test 1000m", "tipo": "prueba_fisica", "valor": 7.9],
                ],
            ]],
        ]
        let torneos: [String: Any] = [
            "actualizado": "2026-11-20T10:00:00Z",
            "lista": [[
                "id": "torneo-1",
                "titulo": "Liga de Bádminton",
                "estado": "en_curso",
                "miEquipo": ["numero": 2, "etiqueta": "Equipo 2", "resumen": "2º · 3G 1P"],
                "proximoPartido": ["fase": "Jornada 4", "local": "Equipo 2", "visitante": "Equipo 5"],
                "rondas": [[
                    "partidos": [[
                        "local": "Equipo 2",
                        "visitante": "Equipo 1",
                        "marcadorLocal": 21,
                        "marcadorVisitante": 16,
                        "esMio": true,
                    ]],
                ]],
            ]],
        ]

        let board = try WebPortalPublisher.buildBoard(
            portalId: "portal-ana",
            forms: forms,
            notas: notas,
            torneos: torneos,
            now: now
        )
        let preview = WebPortalStudentPreviewData.parse(
            boardData: board,
            studentName: "Ana García",
            groupName: "2º ESO B",
            accountStatus: .activada,
            hiddenGradeColumnCount: 3,
            hiddenTournamentCount: 1
        )

        XCTAssertFalse(preview.isCompletelyEmpty)
        XCTAssertEqual(preview.pendingTasks.count, 1)
        XCTAssertEqual(preview.pendingTasks.first?.title, "Autoevaluación Balonmano")
        XCTAssertEqual(preview.doneTasks.count, 1)
        XCTAssertEqual(preview.totalVisibleGrades, 2)
        XCTAssertEqual(preview.gradeSubjects.first?.averageValue, "8,4")
        XCTAssertEqual(preview.tournaments.count, 1)
        XCTAssertEqual(preview.tournaments.first?.myTeamLabel, "Equipo 2")
        XCTAssertEqual(preview.tournaments.first?.nextMatchSummary, "Jornada 4 · Equipo 2 vs Equipo 5")
        XCTAssertEqual(preview.tournaments.first?.recentResults, ["Equipo 2 21 – 16 Equipo 1"])
        XCTAssertEqual(preview.hiddenGradeColumnCount, 3)
        XCTAssertEqual(preview.hiddenTournamentCount, 1)
    }

    func testParseBoardVacioEsCompletelyEmpty() throws {
        let board = try WebPortalPublisher.buildBoard(
            portalId: "portal-hugo",
            forms: [],
            notas: nil,
            torneos: nil
        )
        let preview = WebPortalStudentPreviewData.parse(
            boardData: board,
            studentName: "Hugo Martín",
            groupName: "2º ESO B",
            accountStatus: .sinInvitar,
            hiddenGradeColumnCount: 6,
            hiddenTournamentCount: 1
        )

        XCTAssertTrue(preview.isCompletelyEmpty)
        XCTAssertEqual(preview.totalVisibleGrades, 0)
        XCTAssertTrue(preview.tournaments.isEmpty)
        XCTAssertEqual(preview.hiddenGradeColumnCount, 6)
    }

    func testParseBoardSinMediaNoMuestraMedia() throws {
        let notas: [String: Any] = [
            "provisional": true,
            "materias": [[
                "grupo": "2º ESO B",
                "actividades": [
                    ["titulo": "Plancha", "tipo": "prueba_fisica", "valor": 8.0],
                ],
            ]],
        ]
        let board = try WebPortalPublisher.buildBoard(
            portalId: "portal-sin-media",
            forms: [],
            notas: notas,
            torneos: nil
        )
        let preview = WebPortalStudentPreviewData.parse(
            boardData: board,
            studentName: "Lucía",
            groupName: "2º ESO B",
            accountStatus: .activada
        )

        XCTAssertEqual(preview.totalVisibleGrades, 1)
        XCTAssertNil(preview.gradeSubjects.first?.averageValue)
    }
}
