import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

final class StudentEmailImportCourseTests: XCTestCase {

    private func makeTrace() -> AuditTrace {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
    }

    private func makeStudent(id: Int64, firstName: String, lastName: String) -> Student {
        Student(
            id: id,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            isInjured: false,
            sex: .unspecified,
            sexSource: .unknown,
            birthDate: nil,
            trace: makeTrace()
        )
    }

    private func makeClass(id: Int64, name: String, course: Int32) -> SchoolClass {
        SchoolClass(
            id: id,
            name: name,
            course: course,
            description: nil,
            centerId: nil,
            academicYearId: nil,
            stageCycleId: nil,
            subjectId: nil,
            trace: makeTrace()
        )
    }

    func testCourseKeyReadsPathAndDropsSchoolYear() {
        XCTAssertEqual(StudentEmailImportService.courseKey("/Alumnes/Batxillerat/1BACH 2026-27"), "1BAC")
        XCTAssertEqual(StudentEmailImportService.courseKey("/Alumnes/ESO/1ESO 2026-27"), "1ESO")
        XCTAssertEqual(StudentEmailImportService.courseKey("/Alumnes/ESO/4ESO 2026-27"), "4ESO")
        XCTAssertEqual(StudentEmailImportService.courseKey("1º ESO A"), "1ESOA")
    }

    func testCoursePathMatchesEveryGroupOfThatLevel() {
        let classes = [
            makeClass(id: 1, name: "1º BACH A", course: 1),
            makeClass(id: 2, name: "1BACB", course: 1),
            makeClass(id: 3, name: "2º BACH A", course: 2),
            makeClass(id: 4, name: "1º ESO A", course: 1),
            makeClass(id: 5, name: "2º ESO B", course: 2),
            makeClass(id: 6, name: "3º ESO A", course: 3),
            makeClass(id: 7, name: "4º ESO C", course: 4),
        ]
        func ids(_ course: String) -> [Int64] {
            StudentEmailImportService.matchingClasses(forCourse: course, in: classes).map(\.id)
        }

        XCTAssertEqual(ids("/Alumnes/Batxillerat/1BACH 2026-27"), [1, 2])
        XCTAssertEqual(ids("/Alumnes/Batxillerat/2BACH 2026-27"), [3])
        XCTAssertEqual(ids("/Alumnes/ESO/1ESO 2026-27"), [4])
        XCTAssertEqual(ids("/Alumnes/ESO/2ESO 2026-27"), [5])
        XCTAssertEqual(ids("/Alumnes/ESO/3ESO 2026-27"), [6])
        XCTAssertEqual(ids("/Alumnes/ESO/4ESO 2026-27"), [7])
    }

    func testEmailSplitsLastTwoSegmentsAsSurnames() {
        let identity = StudentEmailImportService.parseEmailIdentity(email: "a.juan.carlos.garcia.lopez@centro.test")
        XCTAssertEqual(identity?.firstName, "Juan Carlos")
        XCTAssertEqual(identity?.lastName, "Garcia Lopez")
    }

    func testPreviewFindsStudentInAnyGroupOfTheLevelByName() {
        let classA = makeClass(id: 1, name: "1º BACH A", course: 1)
        let classB = makeClass(id: 2, name: "1º BACH B", course: 1)
        let otherLevel = makeClass(id: 3, name: "2º BACH A", course: 2)
        let lucia = makeStudent(id: 10, firstName: "Lucía", lastName: "Pérez Gómez")
        let juanCarlos = makeStudent(id: 11, firstName: "Juan Carlos", lastName: "García López")
        let singleSurname = makeStudent(id: 12, firstName: "Ana María", lastName: "Ruiz")
        let luciaOtherLevel = makeStudent(id: 13, firstName: "Lucía", lastName: "Pérez Gómez")
        let studentsByClass: [Int64: [Student]] = [
            1: [lucia],
            2: [juanCarlos, singleSurname],
            3: [luciaOtherLevel],
        ]

        let rows = [
            ["Correo", "Unidad organizativa"],
            ["a.lucia.perez.gomez@centro.test", "/Alumnes/Batxillerat/1BACH 2026-27"],
            ["a.juan.carlos.garcia.lopez@centro.test", "/Alumnes/Batxillerat/1BACH 2026-27"],
            ["a.ana.maria.ruiz@centro.test", "/Alumnes/Batxillerat/1BACH 2026-27"],
        ]

        let preview = StudentEmailImportService.buildPreview(
            rows: rows,
            classes: [classA, classB, otherLevel],
            studentsByClass: studentsByClass,
            allStudents: [lucia, juanCarlos, singleSurname, luciaOtherLevel]
        )

        XCTAssertEqual(preview.totalRows, 3)
        XCTAssertEqual(preview.matchedCount, 3)
        XCTAssertEqual(preview.items[0].matchedStudent?.id, 10)
        XCTAssertEqual(preview.items[0].matchedClassName, "1º BACH A")
        XCTAssertEqual(preview.items[1].matchedStudent?.id, 11)
        XCTAssertEqual(preview.items[1].matchedClassName, "1º BACH B")
        XCTAssertEqual(preview.items[2].matchedStudent?.id, 12)
    }

    func testSameNameInTwoGroupsOfTheLevelIsAmbiguous() {
        let classA = makeClass(id: 1, name: "1º ESO A", course: 1)
        let classB = makeClass(id: 2, name: "1º ESO B", course: 1)
        let first = makeStudent(id: 20, firstName: "Pablo", lastName: "Martín Sanz")
        let second = makeStudent(id: 21, firstName: "Pablo", lastName: "Martín Sanz")

        let preview = StudentEmailImportService.buildPreview(
            rows: [["a.pablo.martin.sanz@centro.test", "/Alumnes/ESO/1ESO 2026-27"]],
            classes: [classA, classB],
            studentsByClass: [1: [first], 2: [second]],
            allStudents: [first, second]
        )

        XCTAssertEqual(preview.items.first?.status, .ambiguous)
    }
}
