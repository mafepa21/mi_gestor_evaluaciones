import CoreGraphics
import Foundation
import XCTest
@testable import MiGestorKMPMac

final class WebPortalCardsPDFRendererTests: XCTestCase {
    private func makeCards(count: Int) -> [WebPortalCardItem] {
        let expires = Date(timeIntervalSince1970: 1_796_000_000)
        return (1...count).map { i in
            WebPortalCardItem(
                studentId: Int64(i),
                studentName: "Alumno Prueba \(i)",
                groupName: "2º ESO B",
                code: String(format: "K7M4P-%05d", i),
                link: "https://projectosef.alwaysdata.net/#portal/alta=K7M4P\(String(format: "%05d", i))",
                expiresAt: expires
            )
        }
    }

    func testRenderVacioDevuelveNil() {
        XCTAssertNil(WebPortalCardsPDFRenderer.render(cards: [], groupName: "2º ESO B"))
        XCTAssertEqual(WebPortalCardsPDFRenderer.pageCount(for: 0), 0)
    }

    func testPaginacionA4YDimensiones() throws {
        let cases: [(cards: Int, expectedPages: Int)] = [
            (1, 1),
            (8, 1),
            (9, 2),
            (25, 4),
        ]
        for (count, expectedPages) in cases {
            let data = try XCTUnwrap(
                WebPortalCardsPDFRenderer.render(cards: makeCards(count: count), groupName: "2º ESO B")
            )
            XCTAssertFalse(data.isEmpty)
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            let document = try XCTUnwrap(CGPDFDocument(provider))
            XCTAssertEqual(document.numberOfPages, expectedPages, "Con \(count) tarjetas deberían salir \(expectedPages) páginas")
            let page = try XCTUnwrap(document.page(at: 1))
            let box = page.getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 595, accuracy: 0.5)
            XCTAssertEqual(box.height, 842, accuracy: 0.5)
        }
    }

    func testFiltroPendientesExcluyeActivadosYDesconocidos() {
        let students = [
            WebPortalStudent(id: 1, firstName: "Ana", lastName: "A", email: "a@a.es"),
            WebPortalStudent(id: 2, firstName: "Bruno", lastName: "B", email: nil),
            WebPortalStudent(id: 3, firstName: "Carla", lastName: "C", email: "c@c.es"),
            WebPortalStudent(id: 4, firstName: "Dani", lastName: "D", email: "d@d.es"),
            WebPortalStudent(id: 5, firstName: "Elena", lastName: "E", email: "e@e.es"),
        ]
        let statuses: [Int64: WebPortalAccountStatus] = [
            1: .activada,
            2: .sinCorreo,
            3: .sinInvitar,
            4: .caducado,
            5: .desconocido,
        ]
        let filtered = WebPortalCardsTargetFilter.pendingOrUninvited(students: students) {
            statuses[$0.id] ?? .sinInvitar
        }
        XCTAssertEqual(filtered.map(\.id), [2, 3, 4])
    }
}
