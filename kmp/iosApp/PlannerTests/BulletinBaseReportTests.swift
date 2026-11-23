import Foundation
import XCTest
@testable import MiGestorKMPMac

/// Base anónima para el boletín: ningún nombre del grupo puede salir en el texto exportable.
/// Todos los datos son inventados.
final class BulletinBaseReportTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_788_000_000)

    private func makeStudents() -> [BulletinBaseStudentInput] {
        var lucia = BulletinBaseStudentInput(studentId: 11, firstName: "Lucía", lastName: "Prueba Uno")
        lucia.attendance = BulletinBaseAttendance(present: 9, absent: 0, late: 1, justified: 1, other: 0)
        lucia.grades = (0..<4).map { index in
            BulletinBaseGrade(
                category: "Condición física",
                title: "Test \(index + 1)",
                value: 6 + Double(index),
                weight: 1,
                date: start.addingTimeInterval(Double(index) * day)
            )
        }
        lucia.selfAssessments = [
            BulletinBaseSelfAssessment(
                title: "Autoevaluación voleibol",
                scaleAverage: 3.4,
                openAnswers: ["He ayudado a mateo prueba dos con el saque. Mi correo es lucia.p@example.com"]
            )
        ]
        lucia.observations = [
            BulletinBaseObservation(date: start, text: "Trabaja muy bien con Nora y con MATEO."),
            BulletinBaseObservation(date: start.addingTimeInterval(day), text: "Llamar a casa: 612 345 678. Nació el 03/04/2013.")
        ]

        var mateo = BulletinBaseStudentInput(studentId: 22, firstName: "Mateo", lastName: "Prueba Dos")
        mateo.attendance = BulletinBaseAttendance(present: 2, absent: 1, late: 0, justified: 0, other: 0)
        mateo.grades = [BulletinBaseGrade(category: nil, title: "Rúbrica voleibol", value: 5.75, weight: 2, date: start)]
        mateo.observations = [BulletinBaseObservation(date: start, text: "Prueba Uno le explica las reglas; Lucía es su pareja.")]

        let nora = BulletinBaseStudentInput(studentId: 33, firstName: "Nora", lastName: "Ejemplo Tres")
        return [lucia, mateo, nora]
    }

    private func build() -> BulletinBaseReport {
        BulletinBaseReportBuilder.build(
            className: "2º ESO B",
            classId: 7,
            termLabel: "1er Trimestre",
            students: makeStudents(),
            evaluableColumnCount: 5,
            selfAssessmentCount: 1,
            generatedAt: start
        )
    }

    func testExportedTextContainsNoStudentNamesOrContactData() {
        let text = BulletinBaseTextScrubber.fold(build().text)
        for forbidden in ["lucia", "mateo", "nora", "prueba uno", "prueba dos", "ejemplo tres", "example.com", "612 345 678", "03/04/2013"] {
            XCTAssertFalse(text.contains(forbidden), "El texto exportable contiene «\(forbidden)»")
        }
        XCTAssertTrue(text.contains("[correo]"))
        XCTAssertTrue(text.contains("[telefono]"))
        XCTAssertTrue(text.contains("[fecha]"))
    }

    func testKeyMapsEveryCodeAndStaysOutOfText() {
        let report = build()
        XCTAssertEqual(report.key.count, 3)
        XCTAssertEqual(Set(report.key.map(\.studentName)), ["Lucía Prueba Uno", "Mateo Prueba Dos", "Nora Ejemplo Tres"])
        for entry in report.key {
            XCTAssertTrue(report.text.contains("═══ \(entry.code)"), "Falta la ficha de \(entry.code)")
            XCTAssertFalse(report.text.contains(entry.studentName))
        }
    }

    func testNamesInFreeTextBecomeTheRightCode() {
        let report = build()
        let codeByName = Dictionary(uniqueKeysWithValues: report.key.map { ($0.studentName, $0.code) })
        let mateoCode = codeByName["Mateo Prueba Dos"]!
        let noraCode = codeByName["Nora Ejemplo Tres"]!
        XCTAssertTrue(report.text.contains("He ayudado a \(mateoCode) con el saque"))
        XCTAssertTrue(report.text.contains("Trabaja muy bien con \(noraCode) y con \(mateoCode)."))
    }

    func testSharedSurnameWordIsMaskedWithoutGuessingWho() {
        // «Prueba» lo comparten dos alumnos: se tapa sin atribuirlo a ninguno.
        let scrubber = BulletinBaseTextScrubber(replacements: [
            (code: "Alumno 01", firstName: "Lucía", lastName: "Prueba Uno"),
            (code: "Alumno 02", firstName: "Mateo", lastName: "Prueba Dos")
        ])
        XCTAssertEqual(scrubber.scrub("Habla con Prueba mañana"), "Habla con [nombre] mañana")
        XCTAssertEqual(scrubber.scrub("lucía prueba uno ayuda"), "Alumno 01 ayuda")
        // Las palabras que solo contienen un nombre dentro no se tocan.
        XCTAssertEqual(scrubber.scrub("Lucíana analiza"), "Lucíana analiza")
    }

    func testQualitativeBlocksAreAddedWithoutNames() {
        var students = makeStudents()
        students[0].criterionLevels = [
            BulletinBaseCriterionLevel(criterion: "Resistencia", level: "Avanzado", descriptor: "Mantiene el ritmo todo el test", ratio: 1)
        ]
        students[0].stamps = [
            BulletinBaseStampCount(title: "Superación", count: 1),
            BulletinBaseStampCount(title: "Cooperación", count: 3)
        ]
        students[0].teacherNote = "Fortaleza: Coopera con Mateo. A mejorar: velocidad."
        let report = BulletinBaseReportBuilder.build(
            className: "2º ESO B",
            classId: 7,
            termLabel: "1er Trimestre",
            students: students,
            evaluableColumnCount: 5,
            selfAssessmentCount: 1,
            generatedAt: start
        )
        let codeByName = Dictionary(uniqueKeysWithValues: report.key.map { ($0.studentName, $0.code) })
        let mateo = codeByName["Mateo Prueba Dos"]!
        XCTAssertTrue(report.text.contains("Rúbricas (nivel logrado):\n  · Resistencia: Avanzado — «Mantiene el ritmo todo el test»"))
        XCTAssertTrue(report.text.contains("Sellos: Cooperación ×3 · Superación ×1"))
        XCTAssertTrue(report.text.contains("Valoración del docente: Fortaleza: Coopera con \(mateo). A mejorar: velocidad."))
        XCTAssertFalse(BulletinBaseTextScrubber.fold(report.text).contains("mateo"))
        // Los datos por alumno quedan para la app, fuera del texto.
        XCTAssertEqual(report.inputsByStudent[11]?.stamps.count, 2)
        XCTAssertEqual(report.lowDataStudentIds, [22, 33])
    }

    func testNoMaterialAndExemptCountAsPresentAndAreShown() {
        // 8 presentes, 1 sin material, 1 exento: el 100 % vino a clase.
        let attendance = BulletinBaseAttendance(present: 8, absent: 0, late: 0, justified: 0, noMaterial: 1, exempt: 1, other: 0)
        XCTAssertEqual(attendance.presenceRate, 100)
        XCTAssertEqual(
            BulletinBaseReportBuilder.attendanceLine(attendance),
            "Asistencia: 100 % presente · 0 faltas · 0 retrasos · 1 día sin material · 1 día exento"
        )
        // Un estado desconocido no cuenta como falta.
        let unknown = BulletinBaseAttendance(present: 4, other: 1)
        XCTAssertEqual(unknown.presenceRate, 100)
    }

    func testCodesAreStableBetweenBuilds() {
        let first = build()
        let second = build()
        XCTAssertEqual(first.key, second.key)
        XCTAssertEqual(first.key.map(\.code), ["Alumno 01", "Alumno 02", "Alumno 03"])
    }

    func testStudentBlocksSummariseEachSource() {
        let report = build()
        let codeByName = Dictionary(uniqueKeysWithValues: report.key.map { ($0.studentName, $0.code) })
        let lucia = codeByName["Lucía Prueba Uno"]!
        let nora = codeByName["Nora Ejemplo Tres"]!
        XCTAssertTrue(report.text.contains("Asistencia: 91 % presente · 1 falta (1 justificada) · 1 retraso"))
        XCTAssertTrue(report.text.contains("Notas: media 7,5 · tendencia: sube"))
        XCTAssertTrue(report.text.contains("Autoevaluación (Autoevaluación voleibol): media 3,4 / 4"))
        XCTAssertTrue(report.text.contains("Notas: media 5,8 (1 nota)"))
        XCTAssertTrue(report.text.contains("Asistencia: sin registros en el periodo"))
        XCTAssertEqual(Set(report.lowDataCodes), Set([codeByName["Mateo Prueba Dos"]!, nora]))
        XCTAssertFalse(report.lowDataCodes.contains(lucia))
    }
}
