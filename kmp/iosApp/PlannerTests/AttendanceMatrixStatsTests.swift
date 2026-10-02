import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

@MainActor
final class AttendanceMatrixStatsTests: XCTestCase {

    func testAttendanceBoardModeIncludesMatrix() {
        XCTAssertTrue(AttendanceBoardMode.allCases.contains(.matrix))
        XCTAssertEqual(AttendanceBoardMode.matrix.rawValue, "Matriz")
        XCTAssertEqual(AttendanceBoardMode.matrix.systemImage, "tablecells")
    }

    func testStudentInitials() {
        let student1 = Student.mock(id: 1, firstName: "Carlos", lastName: "García")
        XCTAssertEqual(student1.initials, "CG")

        let student2 = Student.mock(id: 2, firstName: "María", lastName: "López")
        XCTAssertEqual(student2.initials, "ML")

        let studentEmpty = Student.mock(id: 3, firstName: "", lastName: "")
        XCTAssertEqual(studentEmpty.initials, "—")
    }

    func testAttendanceMatrixStudentStatsPerfectAttendance() {
        let student = Student.mock(id: 1, firstName: "Carlos", lastName: "García")
        let stats = AttendanceMatrixStudentStats(
            student: student,
            presentCount: 20,
            absentCount: 0,
            lateCount: 0,
            justifiedCount: 0,
            noMaterialCount: 0,
            exemptCount: 0,
            totalSessions: 20
        )

        XCTAssertEqual(stats.attendanceRate, 100)
        XCTAssertEqual(stats.attendanceRateColor, AppleDesignSystem.success)
    }

    func testAttendanceMatrixStudentStatsMixedAttendance() {
        let student = Student.mock(id: 2, firstName: "Elena", lastName: "Ruiz")
        // 16 presentes + 2 retrasos + 0 exentos = 18 asistidos sobre 20 sesiones = 90%
        let stats90 = AttendanceMatrixStudentStats(
            student: student,
            presentCount: 16,
            absentCount: 2,
            lateCount: 2,
            justifiedCount: 0,
            noMaterialCount: 0,
            exemptCount: 0,
            totalSessions: 20
        )
        XCTAssertEqual(stats90.attendanceRate, 90)
        XCTAssertEqual(stats90.attendanceRateColor, AppleDesignSystem.success)

        // 14 presentes + 2 retrasos = 16 asistidos sobre 20 = 80%
        let stats80 = AttendanceMatrixStudentStats(
            student: student,
            presentCount: 14,
            absentCount: 4,
            lateCount: 2,
            justifiedCount: 0,
            noMaterialCount: 0,
            exemptCount: 0,
            totalSessions: 20
        )
        XCTAssertEqual(stats80.attendanceRate, 80)
        XCTAssertEqual(stats80.attendanceRateColor, AppleDesignSystem.warning)

        // 10 presentes sobre 20 = 50%
        let stats50 = AttendanceMatrixStudentStats(
            student: student,
            presentCount: 10,
            absentCount: 10,
            lateCount: 0,
            justifiedCount: 0,
            noMaterialCount: 0,
            exemptCount: 0,
            totalSessions: 20
        )
        XCTAssertEqual(stats50.attendanceRate, 50)
        XCTAssertEqual(stats50.attendanceRateColor, AppleDesignSystem.danger)
    }

    func testAttendanceMatrixStudentStatsZeroSessionsSafe() {
        let student = Student.mock(id: 3, firstName: "Hugo", lastName: "Sanz")
        let stats = AttendanceMatrixStudentStats(
            student: student,
            presentCount: 0,
            absentCount: 0,
            lateCount: 0,
            justifiedCount: 0,
            noMaterialCount: 0,
            exemptCount: 0,
            totalSessions: 0
        )
        XCTAssertEqual(stats.attendanceRate, 100)
    }

    func testAttendanceMatrixRangeIntervals() {
        var comp = DateComponents()
        comp.year = 2026
        comp.month = 10
        comp.day = 15
        let calendar = Calendar.current
        let testDate = calendar.date(from: comp)!

        let monthRange = AttendanceMatrixRange.month.dateRange(relativeTo: testDate)
        XCTAssertEqual(calendar.component(.month, from: monthRange.start), 10)
        XCTAssertEqual(calendar.component(.day, from: monthRange.start), 1)

        let q1Range = AttendanceMatrixRange.quarter1.dateRange(relativeTo: testDate)
        XCTAssertEqual(calendar.component(.month, from: q1Range.start), 9)
        XCTAssertEqual(calendar.component(.day, from: q1Range.start), 1)
        XCTAssertEqual(calendar.component(.month, from: q1Range.end), 12)
        XCTAssertEqual(calendar.component(.day, from: q1Range.end), 22)

        let fullYearRange = AttendanceMatrixRange.fullYear.dateRange(relativeTo: testDate)
        XCTAssertEqual(calendar.component(.year, from: fullYearRange.start), 2026)
        XCTAssertEqual(calendar.component(.month, from: fullYearRange.start), 9)
        XCTAssertEqual(calendar.component(.year, from: fullYearRange.end), 2027)
        XCTAssertEqual(calendar.component(.month, from: fullYearRange.end), 6)
    }
}
