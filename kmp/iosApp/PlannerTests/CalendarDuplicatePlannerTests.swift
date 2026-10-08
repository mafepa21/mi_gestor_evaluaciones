import Foundation
import XCTest
@testable import MiGestorKMPMac

final class CalendarDuplicatePlannerTests: XCTestCase {
    private func event(
        _ id: Int64,
        title: String = "Viaje a Toledo · 2º ESO B",
        start: Int64 = 1_792_000_000_000,
        end: Int64 = 1_792_086_399_000,
        classId: Int64? = 7,
        linked: Bool = false
    ) -> CalendarDuplicateCandidate {
        CalendarDuplicateCandidate(id: id, title: title, startMs: start, endMs: end, classId: classId, isLinked: linked)
    }

    func testEventosIgualesSeConservaUno() {
        let ids = CalendarDuplicatePlanner.eventIdsToRemove([event(1), event(2), event(3)])
        XCTAssertEqual(ids, [2, 3])
    }

    func testSinRepetidosNoBorraNada() {
        let ids = CalendarDuplicatePlanner.eventIdsToRemove([event(1), event(2, start: 1_792_200_000_000)])
        XCTAssertEqual(ids, [])
    }

    func testSeConservaElQueTieneGrupo() {
        let ids = CalendarDuplicatePlanner.eventIdsToRemove([event(1, classId: nil), event(2, classId: 7)])
        XCTAssertEqual(ids, [1])
    }

    func testSeConservaElEnlazadoSiTienenElMismoGrupo() {
        let ids = CalendarDuplicatePlanner.eventIdsToRemove([event(1, linked: false), event(2, linked: true)])
        XCTAssertEqual(ids, [1])
    }

    func testTitulosDistintosDelMismoDiaNoSonRepetidos() {
        let ids = CalendarDuplicatePlanner.eventIdsToRemove([
            event(1, title: "Viaje a Toledo · 2º ESO A"),
            event(2, title: "Viaje a Toledo · 2º ESO B")
        ])
        XCTAssertEqual(ids, [])
    }

    func testPeriodosRepetidosSeConservaElMasAntiguo() {
        let periods = [
            EvaluationPeriodDuplicateCandidate(id: 5, name: "3ª Evaluación", startDateIso: "2027-03-08", endDateIso: "2027-06-04", scheduleId: 1),
            EvaluationPeriodDuplicateCandidate(id: 9, name: "3ª Evaluación", startDateIso: "2027-03-08", endDateIso: "2027-06-04", scheduleId: 1),
            EvaluationPeriodDuplicateCandidate(id: 6, name: "2ª Evaluación", startDateIso: "2026-11-30", endDateIso: "2027-03-05", scheduleId: 1)
        ]
        XCTAssertEqual(CalendarDuplicatePlanner.periodIdsToRemove(periods), [9])
    }
}
