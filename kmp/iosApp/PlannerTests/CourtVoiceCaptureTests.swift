import XCTest
@testable import MiGestorKMPMac

@MainActor
final class CourtVoiceCaptureTests: XCTestCase {

    private var sampleStudents: [CourtVoiceStudentDescriptor] {
        [
            CourtVoiceStudentDescriptor(id: 1, fullName: "Sofía García"),
            CourtVoiceStudentDescriptor(id: 2, fullName: "Mateo López"),
            CourtVoiceStudentDescriptor(id: 3, fullName: "Hugo Martínez"),
            CourtVoiceStudentDescriptor(id: 4, fullName: "Lucía Sánchez")
        ]
    }

    private var sampleColumns: [CourtVoiceColumnDescriptor] {
        [
            CourtVoiceColumnDescriptor(id: "col_badminton", title: "Progreso técnico Bádminton", evaluationId: 10),
            CourtVoiceColumnDescriptor(id: "col_fairplay", title: "Fair Play y Actitud", evaluationId: 11)
        ]
    }

    func testMultiStudentAttendanceAndObservationParsing() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Sofía y Mateo llegan 5 minutos tarde. Hugo muy participativo ayudando a recoger el material.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test local")

        XCTAssertEqual(draft.actions.count, 3)

        let sofiaAction = draft.actions.first(where: { $0.studentId == 1 })
        XCTAssertNotNil(sofiaAction)
        XCTAssertEqual(sofiaAction?.kind, .attendance)
        XCTAssertEqual(sofiaAction?.attendanceStatus, "TARDE")

        let mateoAction = draft.actions.first(where: { $0.studentId == 2 })
        XCTAssertNotNil(mateoAction)
        XCTAssertEqual(mateoAction?.kind, .attendance)
        XCTAssertEqual(mateoAction?.attendanceStatus, "TARDE")

        let hugoAction = draft.actions.first(where: { $0.studentId == 3 })
        XCTAssertNotNil(hugoAction)
        XCTAssertEqual(hugoAction?.kind, .observation)
        XCTAssertTrue(hugoAction?.note.localizedCaseInsensitiveContains("participativo") == true)
    }

    func testQuickEvaluationAndInjuryParsing() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Ponle un 8,5 en bádminton a Lucía por su golpeo de revés. Sofía tiene esguince de tobillo hoy.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test local")

        XCTAssertEqual(draft.actions.count, 2)

        let luciaEval = draft.actions.first(where: { $0.studentId == 4 })
        XCTAssertEqual(luciaEval?.kind, .quickEvaluation)
        XCTAssertEqual(luciaEval?.score, 8.5)
        XCTAssertEqual(luciaEval?.columnId, "col_badminton")

        let sofiaInjury = draft.actions.first(where: { $0.studentId == 1 })
        XCTAssertEqual(sofiaInjury?.kind, .injury)
        XCTAssertEqual(sofiaInjury?.markInjured, true)
    }

    func testNoMaterialAttendanceDetection() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Mateo viene sin material deportivo hoy.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test local")
        XCTAssertEqual(draft.actions.count, 1)
        XCTAssertEqual(draft.actions.first?.kind, .attendance)
        XCTAssertEqual(draft.actions.first?.attendanceStatus, "SIN_MATERIAL")
    }
}
