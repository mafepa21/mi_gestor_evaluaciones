import XCTest
@testable import MiGestorKMPMac

final class ScheduleImportTests: XCTestCase {
    func testCombinesComplementaryFilesBeforeSaving() throws {
        let service = ScheduleExcelImportService()
        let eso = try service.preview(
            rows: [
                ["Horas", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"],
                ["De 08:05 a 09:00", "EFI3 : 3ESOB", "", "", "", ""],
                ["Materias:", "EFI3: Educación Física", "", "", "", ""]
            ],
            sourceName: "ESO.xlsx"
        )
        let bachillerato = try service.preview(
            rows: [
                ["Horas", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"],
                ["De 08:05 a 09:00", "", "", "", "", "EFI1 : 1BAHA"],
                ["Materias:", "EFI1: Educación Física", "", "", "", ""]
            ],
            sourceName: "Bachillerato.xlsx"
        )

        let combined = service.combine([eso, bachillerato])

        XCTAssertEqual(combined.sourceName, "2 archivos combinados")
        XCTAssertEqual(combined.persistableSlots.count, 2)
        XCTAssertEqual(combined.groupCodes, ["1BAHA", "3ESOB"])
        XCTAssertTrue(combined.conflicts.isEmpty)
    }

    func testUnifiesExactDuplicatesAcrossFiles() throws {
        let service = ScheduleExcelImportService()
        let preview = try service.preview(
            rows: [
                ["Horas", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"],
                ["De 12:20 a 13:15", "", "", "", "", "EFI4 : 4ESOA"],
                ["Materias:", "EFI4: Educación Física", "", "", "", ""]
            ],
            sourceName: "Horario.xlsx"
        )

        let combined = service.combine([preview, preview])

        XCTAssertEqual(combined.persistableSlots.count, 1)
        XCTAssertTrue(combined.warnings.contains { $0.contains("idénticos") })
    }

    func testRejectsMoreThanThreeFiles() {
        let urls = (1...4).map { URL(fileURLWithPath: "/tmp/horario-\($0).xlsx") }

        XCTAssertThrowsError(try ScheduleExcelImportService().preview(from: urls)) { error in
            XCTAssertEqual(error.localizedDescription, "Puedes combinar un máximo de 3 archivos de horario.")
        }
    }
}
