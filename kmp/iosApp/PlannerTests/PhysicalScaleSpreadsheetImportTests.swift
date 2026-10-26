import Foundation
import XCTest
@testable import MiGestorKMPMac

final class PhysicalScaleSpreadsheetImportTests: XCTestCase {
    func testTemplateParsesIntoTwoGroupsWithoutIssues() {
        let rows = PhysicalScaleSpreadsheetImport.templateCSV
            .split(whereSeparator: \.isNewline)
            .map { $0.split(separator: ";", omittingEmptySubsequences: false).map(String.init) }

        let result = PhysicalScaleSpreadsheetImport.parse(rows: rows)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.warnings.isEmpty, result.warnings.map(\.text).joined(separator: "\n"))
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.rangeCount, 10)
        XCTAssertEqual(result.groups.map(\.sex), ["FEMALE", "MALE"])
        XCTAssertEqual(result.groups.first?.course, 1)
        XCTAssertNil(result.groups.first?.ranges.last?.maxValue)
    }

    func testAcceptsHeaderAliasesUnitsAndDecimalComma() {
        let rows = [
            ["Baremo salto horizontal"],
            ["Género", "Mínimo (m)", "Máximo (m)", "Puntuación"],
            ["F", "1,20", "1,39", "5"],
            ["F", "1,40", "1,60", "7,5"]
        ]

        let result = PhysicalScaleSpreadsheetImport.parse(rows: rows)

        XCTAssertTrue(result.isValid, result.errors.map(\.text).joined(separator: "\n"))
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertNil(result.groups.first?.course)
        XCTAssertEqual(result.groups.first?.sex, "FEMALE")
        XCTAssertEqual(result.groups.first?.ranges.map(\.score), [5, 7.5])
        XCTAssertEqual(result.groups.first?.ranges.first?.minValue ?? 0, 1.2, accuracy: 0.0001)
    }

    func testReportsMissingScoreAndOverlapsByRow() {
        let rows = [
            ["Curso", "Sexo", "Desde", "Hasta", "Nota"],
            ["2º ESO", "", "0", "139", "4"],
            ["2º ESO", "", "140", "150", "6"],
            ["2º ESO", "", "145", "160", "8"],
            ["2º ESO", "", "161", "", ""]
        ]

        let result = PhysicalScaleSpreadsheetImport.parse(rows: rows)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.map(\.row), [4, 5])
        XCTAssertEqual(result.errors.last?.message, "falta la nota")
        XCTAssertTrue(result.errors.first?.message.contains("fila 3") == true)
    }

    func testWarnsAboutGapsWithoutBlocking() {
        let rows = [
            ["Desde", "Hasta", "Nota"],
            ["0", "159", "5"],
            ["161", "", "10"]
        ]

        let result = PhysicalScaleSpreadsheetImport.parse(rows: rows)

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.warnings.map(\.row), [3])
    }

    func testRejectsScoresOutsideTenPointRangeAndUnknownSex() {
        let rows = [
            ["Sexo", "Desde", "Hasta", "Nota"],
            ["Chica", "0", "10", "12"],
            ["Otro", "11", "20", "5"]
        ]

        let result = PhysicalScaleSpreadsheetImport.parse(rows: rows)

        XCTAssertEqual(result.errors.map(\.row), [2, 3])
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testMissingHeaderExplainsWhatIsExpected() {
        let result = PhysicalScaleSpreadsheetImport.parse(rows: [["Alumno", "Marca"], ["Ana", "12"]])

        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.errors.first?.row)
    }

    func testParsesTimesAndAgeSpans() {
        XCTAssertEqual(PhysicalScaleSpreadsheetImport.parseNumber("1:45"), 105)
        XCTAssertEqual(PhysicalScaleSpreadsheetImport.parseNumber("1'30,5") ?? 0, 90.5, accuracy: 0.0001)
        XCTAssertEqual(PhysicalScaleSpreadsheetImport.parseNumber("1.234,5") ?? 0, 1234.5, accuracy: 0.0001)

        let result = PhysicalScaleSpreadsheetImport.parse(rows: [
            ["Edad", "Desde", "Hasta", "Nota"],
            ["12-13", "0", "5", "3"]
        ])
        XCTAssertEqual(result.groups.first?.ageFrom, 12)
        XCTAssertEqual(result.groups.first?.ageTo, 13)
    }
}
