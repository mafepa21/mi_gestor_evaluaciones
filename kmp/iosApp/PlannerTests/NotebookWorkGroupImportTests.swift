import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

final class NotebookWorkGroupImportTests: XCTestCase {

    private func makeStudent(id: Int64, firstName: String, lastName: String) -> Student {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
        return Student(
            id: id,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            isInjured: false,
            sex: .unspecified,
            sexSource: .unknown,
            birthDate: nil,
            trace: trace
        )
    }

    func testParseColumnMatrixGeneradorDeGrupos() throws {
        let students = [
            makeStudent(id: 1, firstName: "Alumno", lastName: "1"),
            makeStudent(id: 2, firstName: "Alumno", lastName: "2"),
            makeStudent(id: 3, firstName: "Alumno", lastName: "3"),
            makeStudent(id: 4, firstName: "Alumno", lastName: "4"),
            makeStudent(id: 5, firstName: "Alumno", lastName: "5"),
            makeStudent(id: 6, firstName: "Alumno", lastName: "6"),
            makeStudent(id: 7, firstName: "Alumno", lastName: "7"),
            makeStudent(id: 8, firstName: "Alumno", lastName: "8"),
            makeStudent(id: 9, firstName: "Alumno", lastName: "9"),
            makeStudent(id: 10, firstName: "Alumno", lastName: "10"),
            makeStudent(id: 11, firstName: "Alumno", lastName: "11"),
            makeStudent(id: 12, firstName: "Alumno", lastName: "12"),
            makeStudent(id: 13, firstName: "Alumno", lastName: "13"),
            makeStudent(id: 14, firstName: "Alumno", lastName: "14"),
            makeStudent(id: 15, firstName: "Alumno", lastName: "15"),
            makeStudent(id: 16, firstName: "Alumno", lastName: "16"),
            makeStudent(id: 17, firstName: "Alumno", lastName: "17"),
            makeStudent(id: 18, firstName: "Alumno", lastName: "18"),
            makeStudent(id: 19, firstName: "Alumno", lastName: "19"),
            makeStudent(id: 20, firstName: "Alumno", lastName: "20"),
            makeStudent(id: 21, firstName: "Alumno", lastName: "21"),
        ]

        let rows = [
            ["", "Grupo 1", "Grupo 2", "Grupo 3", "Grupo 4", "Grupo 5"],
            ["1.0", "Alumno 1", "Alumno 2", "Alumno 3", "Alumno 4", "Alumno 5"],
            ["2.0", "Alumno 6", "Alumno 7", "Alumno 8", "Alumno 9", "Alumno 10"],
            ["3.0", "Alumno 11", "Alumno 12", "Alumno 13", "Alumno 14", "Alumno 15"],
            ["4.0", "Alumno 16", "Alumno 17", "Alumno 18", "Alumno 19", "Alumno 20"],
            ["4.0", "Alumno 17", "Alumno 18", "Alumno 19", "Alumno 20", "Alumno 21"],
        ]

        let service = NotebookWorkGroupImportService()
        let preview = try service.preview(
            rows: rows,
            sourceName: "Generador_de_grupos.xlsx",
            classStudents: students
        )

        XCTAssertEqual(preview.groups.count, 5)
        XCTAssertEqual(preview.groups.map(\.name), ["Grupo 1", "Grupo 2", "Grupo 3", "Grupo 4", "Grupo 5"])

        let group1 = preview.groups[0]
        XCTAssertEqual(group1.members.count, 5)
        XCTAssertEqual(group1.members.map(\.rawName), ["Alumno 1", "Alumno 6", "Alumno 11", "Alumno 16", "Alumno 17"])
        XCTAssertTrue(group1.members.allSatisfy { $0.matchedStudentId != nil })

        XCTAssertEqual(preview.totalMatchedStudents, 25)
        XCTAssertEqual(preview.totalUnmatchedStudents, 0)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testParseTwoColumnList() throws {
        let students = [
            makeStudent(id: 101, firstName: "Lucía", lastName: "García"),
            makeStudent(id: 102, firstName: "Marcos", lastName: "Fernández")
        ]

        let rows = [
            ["Grupo", "Alumno"],
            ["Equipo Azul", "García, Lucía"],
            ["Equipo Rojo", "Fernandez Marcos"]
        ]

        let service = NotebookWorkGroupImportService()
        let preview = try service.preview(
            rows: rows,
            sourceName: "equipos.csv",
            classStudents: students
        )

        XCTAssertEqual(preview.groups.count, 2)
        XCTAssertEqual(preview.groups[0].name, "Equipo Azul")
        XCTAssertEqual(preview.groups[0].members.first?.matchedStudentId, 101)
        XCTAssertEqual(preview.groups[1].name, "Equipo Rojo")
        XCTAssertEqual(preview.groups[1].members.first?.matchedStudentId, 102)
    }

    func testNameLookupVariations() {
        let students = [
            makeStudent(id: 1, firstName: "María", lastName: "González López"),
            makeStudent(id: 2, firstName: "José Antonio", lastName: "Pérez Ruiz")
        ]
        let lookup = StudentNameLookup(students: students)

        // Variaciones con acentos y mayúsculas
        XCTAssertEqual(lookup.findStudent(for: "maria gonzalez lopez")?.id, 1)
        XCTAssertEqual(lookup.findStudent(for: "GONZALEZ LOPEZ, MARIA")?.id, 1)
        XCTAssertEqual(lookup.findStudent(for: "1. Perez Ruiz, Jose Antonio")?.id, 2)
        XCTAssertEqual(lookup.findStudent(for: "Jose Antonio Perez Ruiz")?.id, 2)
    }
}
