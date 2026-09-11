import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

@MainActor
final class DiaryTimelineProjectionTests: XCTestCase {

    func testDiaryViewModeCasesAndImages() {
        XCTAssertEqual(DiaryViewMode.allCases.count, 2)
        XCTAssertTrue(DiaryViewMode.allCases.contains(.week))
        XCTAssertTrue(DiaryViewMode.allCases.contains(.timeline))
        XCTAssertEqual(DiaryViewMode.week.rawValue, "Semanal")
        XCTAssertEqual(DiaryViewMode.timeline.rawValue, "Bitácora continua")
        XCTAssertEqual(DiaryViewMode.timeline.systemImage, "list.bullet.indent")
    }

    func testDiaryTimelineQuarterMatching() {
        var comp = DateComponents()
        comp.year = 2026
        let calendar = Calendar.current

        // 15 de Octubre 2026 -> 1er Trimestre
        comp.month = 10
        comp.day = 15
        let dateQ1 = calendar.date(from: comp)!
        XCTAssertTrue(DiaryTimelineQuarter.q1.matches(date: dateQ1))
        XCTAssertFalse(DiaryTimelineQuarter.q2.matches(date: dateQ1))
        XCTAssertFalse(DiaryTimelineQuarter.q3.matches(date: dateQ1))
        XCTAssertTrue(DiaryTimelineQuarter.all.matches(date: dateQ1))

        // 15 de Febrero 2027 -> 2º Trimestre
        comp.year = 2027
        comp.month = 2
        comp.day = 15
        let dateQ2 = calendar.date(from: comp)!
        XCTAssertFalse(DiaryTimelineQuarter.q1.matches(date: dateQ2))
        XCTAssertTrue(DiaryTimelineQuarter.q2.matches(date: dateQ2))
        XCTAssertFalse(DiaryTimelineQuarter.q3.matches(date: dateQ2))
        XCTAssertTrue(DiaryTimelineQuarter.all.matches(date: dateQ2))

        // 10 de Mayo 2027 -> 3er Trimestre
        comp.year = 2027
        comp.month = 5
        comp.day = 10
        let dateQ3 = calendar.date(from: comp)!
        XCTAssertFalse(DiaryTimelineQuarter.q1.matches(date: dateQ3))
        XCTAssertFalse(DiaryTimelineQuarter.q2.matches(date: dateQ3))
        XCTAssertTrue(DiaryTimelineQuarter.q3.matches(date: dateQ3))
        XCTAssertTrue(DiaryTimelineQuarter.all.matches(date: dateQ3))
    }

    func testDiaryTimelineEntryDateCalculation() {
        // Semana 38 del año 2026, día 2 (Martes) -> 15 de septiembre de 2026
        let session = PlanningSession(
            id: 201,
            teachingUnitId: 1,
            teachingUnitName: "Condición Física",
            teachingUnitColor: "#4A90D9",
            groupId: 10,
            groupName: "1º ESO A",
            dayOfWeek: 2, // Martes
            period: 1,
            weekNumber: 38,
            year: 2026,
            objectives: "Mejorar la resistencia aeróbica",
            activities: "Juego de persecución y carrera continua suave",
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: "08:05",
            endTime: "09:00",
            learningSituationSessionPlanId: nil,
            status: .planned
        )

        let calculatedDate = DiaryTimelineEntry.dateFor(session: session)
        let calendar = Calendar(identifier: .iso8601)

        XCTAssertEqual(calendar.component(.yearForWeekOfYear, from: calculatedDate), 2026)
        XCTAssertEqual(calendar.component(.weekOfYear, from: calculatedDate), 38)
        let dayOfWeek = ((calendar.component(.weekday, from: calculatedDate) + 5) % 7) + 1
        XCTAssertEqual(dayOfWeek, 2) // Martes
    }

    func testDiaryClassPDFRendererBuildsAttributedReportAndData() {
        let session1 = PlanningSession(
            id: 301,
            teachingUnitId: 1,
            teachingUnitName: "Atletismo",
            teachingUnitColor: "#4A90D9",
            groupId: 10,
            groupName: "1º ESO A",
            dayOfWeek: 1,
            period: 1,
            weekNumber: 38,
            year: 2026,
            objectives: "Técnica de carrera y salidas bajas",
            activities: "Juegos de reacción y relevos 4x50m",
            evaluation: "Observación directa",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: "08:05",
            endTime: "09:00",
            learningSituationSessionPlanId: nil,
            status: .planned
        )

        var comp = DateComponents()
        comp.year = 2026
        comp.month = 9
        comp.day = 14
        let testDate = Calendar.current.date(from: comp)!

        let entry = DiaryTimelineEntry(
            id: 301,
            session: session1,
            date: testDate,
            sessionIndex: 1,
            summary: nil
        )

        let options = DiaryClassPDFRenderer.RenderOptions(
            schoolName: "Colegio Sagrado Corazón",
            teacherName: "Mario Fernández",
            className: "1º ESO A - EF",
            academicYear: "2026-2027",
            periodTitle: "1.er Trimestre",
            includeReflections: true,
            includeIncidents: true,
            onlyCompleted: false
        )

        let attributedReport = DiaryClassPDFRenderer.buildAttributedReport(
            entries: [entry],
            aggregatesBySessionId: [:],
            options: options
        )

        XCTAssertGreaterThan(attributedReport.length, 100)
        let stringContent = attributedReport.string
        XCTAssertTrue(stringContent.contains("DIARIO DE AULA Y BITÁCORA DOCENTE"))
        XCTAssertTrue(stringContent.contains("1º ESO A - EF"))
        XCTAssertTrue(stringContent.localizedCaseInsensitiveContains("Colegio Sagrado Corazón"))
        XCTAssertTrue(stringContent.contains("Técnica de carrera"))

        // Renderizado a PDF
        let pdfData = DiaryClassPDFRenderer.renderPDF(attributedBody: attributedReport)
        XCTAssertNotNil(pdfData)
        XCTAssertGreaterThan(pdfData?.count ?? 0, 1000)

        // Verificación de cabecera PDF (%PDF-)
        if let pdfData {
            let headerString = String(decoding: pdfData.prefix(5), as: UTF8.self)
            XCTAssertTrue(headerString.hasPrefix("%PDF"))
        }

        // Escritura en archivo temporal
        let fileUrl = DiaryClassPDFRenderer.writeToTemporaryFile(
            entries: [entry],
            aggregatesBySessionId: [:],
            options: options
        )
        XCTAssertNotNil(fileUrl)
        if let fileUrl {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileUrl.path))
            try? FileManager.default.removeItem(at: fileUrl)
        }
    }
}
