import Foundation
import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

final class PhysicalTestNotebookPlacementTests: XCTestCase {
    func testAssignmentIdIsStablePerTestGroupAndTerm() {
        let plain = PhysicalTestNotebookPlacement.assignmentId(definitionId: "pe_km", classId: 4, termLabel: nil)
        let first = PhysicalTestNotebookPlacement.assignmentId(definitionId: "pe_km", classId: 4, termLabel: "1ª evaluación")
        let firstAgain = PhysicalTestNotebookPlacement.assignmentId(definitionId: "pe_km", classId: 4, termLabel: "1ª evaluación")
        let second = PhysicalTestNotebookPlacement.assignmentId(definitionId: "pe_km", classId: 4, termLabel: "2ª evaluación")

        XCTAssertEqual(plain, "pe_wizard_assignment_pe_km_4")
        XCTAssertEqual(first, firstAgain)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, "pe_wizard_assignment_pe_km_4_1_evaluacion")
    }

    func testTypicalAgeByCourse() {
        XCTAssertEqual(PhysicalTestNotebookPlacement.typicalAge(course: 1), 12)
        XCTAssertEqual(PhysicalTestNotebookPlacement.typicalAge(course: 2), 13)
        XCTAssertNil(PhysicalTestNotebookPlacement.typicalAge(course: nil))
        XCTAssertNil(PhysicalTestNotebookPlacement.typicalAge(course: 9))
    }

    func testMissingDataOnlyCountsWhatTheScaleNeeds() {
        let ana = student(1, sex: .female, born: true)
        let sinSexo = student(2, sex: .unspecified, born: true)
        let sinFecha = student(3, sex: .male, born: false)

        let bySex = PhysicalTestNotebookPlacement.missingData(
            students: [ana, sinSexo, sinFecha],
            scales: [scale(sex: "FEMALE", ageFrom: nil), scale(sex: "MALE", ageFrom: nil)]
        )
        XCTAssertEqual(bySex.withoutSex.map(\.id), [2])
        XCTAssertTrue(bySex.withoutBirthDate.isEmpty)

        let byAge = PhysicalTestNotebookPlacement.missingData(
            students: [ana, sinSexo, sinFecha],
            scales: [scale(sex: nil, ageFrom: 12)]
        )
        XCTAssertTrue(byAge.withoutSex.isEmpty)
        XCTAssertEqual(byAge.withoutBirthDate.map(\.id), [3])
    }

    func testInternalBatteriesAreHidden() {
        XCTAssertFalse(PhysicalTestNotebookPlacement.isUserBattery(battery("pe_wizard_battery_pe_km")))
        XCTAssertTrue(PhysicalTestNotebookPlacement.isUserBattery(battery("pe_battery_condicion_1")))
    }

    private var trace: AuditTrace {
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
    }

    private func student(_ id: Int64, sex: StudentSex, born: Bool) -> Student {
        Student(
            id: id,
            firstName: "Alumno",
            lastName: "\(id)",
            email: nil,
            photoPath: nil,
            isInjured: false,
            sex: sex,
            sexSource: .unknown,
            birthDate: born ? LocalDate(year: 2013, monthNumber: 3, dayOfMonth: 1) : nil,
            trace: trace
        )
    }

    private func scale(sex: String?, ageFrom: Int32?) -> PhysicalTestScale {
        PhysicalTestScale(
            id: UUID().uuidString,
            testId: "pe_km",
            name: "Baremo",
            course: nil,
            ageFrom: ageFrom.map { KotlinInt(value: $0) },
            ageTo: ageFrom.map { KotlinInt(value: $0 + 1) },
            sex: sex,
            batteryId: nil,
            direction: .lowerIsBetter,
            ranges: [],
            scoringMode: .step,
            scoreRoundTo: nil,
            trace: trace
        )
    }

    private func battery(_ id: String) -> PhysicalTestBattery {
        PhysicalTestBattery(
            id: id,
            name: "Batería",
            description: "",
            defaultCourse: nil,
            defaultAgeFrom: nil,
            defaultAgeTo: nil,
            testIds: [],
            trace: trace
        )
    }
}
