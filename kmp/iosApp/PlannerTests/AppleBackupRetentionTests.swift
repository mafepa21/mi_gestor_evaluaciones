import Foundation
import XCTest
@testable import MiGestorKMPMac

final class AppleBackupRetentionTests: XCTestCase {
    private func entry(_ name: String, daysAgo: Double) -> (url: URL, createdAt: Date) {
        (
            URL(fileURLWithPath: "/tmp/backups/\(name).migestorbackup", isDirectory: true),
            Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400)
        )
    }

    func testRetentionKeepsNewestAndRemovesOldest() {
        let entries = (0..<6).map { entry("b\($0)", daysAgo: Double($0)) }
        let victims = AppleBackupService.retentionVictims(entries: entries, limit: 5, protecting: [])
        XCTAssertEqual(victims.map(\.lastPathComponent), ["b5.migestorbackup"])
    }

    func testRetentionNeverRemovesProtectedBackup() {
        let entries = (0..<6).map { entry("b\($0)", daysAgo: Double($0)) }
        let restoring = entries[5].url
        let victims = AppleBackupService.retentionVictims(entries: entries, limit: 5, protecting: [restoring])
        XCTAssertFalse(victims.contains(restoring))
        XCTAssertTrue(victims.isEmpty)
    }

    func testRetentionOrdersByManifestDateNotFolderOrder() {
        // Una copia importada hoy pero creada hace 30 días debe ser la primera en salir.
        var entries = (0..<5).map { entry("b\($0)", daysAgo: Double($0)) }
        entries.insert(entry("importada", daysAgo: 30), at: 0)
        let victims = AppleBackupService.retentionVictims(entries: entries, limit: 5, protecting: [])
        XCTAssertEqual(victims.map(\.lastPathComponent), ["importada.migestorbackup"])
    }

    func testRetentionLimitIsFive() {
        XCTAssertEqual(AppleBackupService.retentionLimit, 5)
    }

    func testNewerSchemaIsRejected() {
        XCTAssertFalse(AppleBackupService.isSchemaCompatible(backupSchemaVersion: 8, currentSchemaVersion: 7))
    }

    func testSameOrOlderSchemaIsAccepted() {
        XCTAssertTrue(AppleBackupService.isSchemaCompatible(backupSchemaVersion: 7, currentSchemaVersion: 7))
        XCTAssertTrue(AppleBackupService.isSchemaCompatible(backupSchemaVersion: 6, currentSchemaVersion: 7))
    }

    func testUnknownSchemaIsAccepted() {
        XCTAssertTrue(AppleBackupService.isSchemaCompatible(backupSchemaVersion: nil, currentSchemaVersion: 7))
        XCTAssertTrue(AppleBackupService.isSchemaCompatible(backupSchemaVersion: 7, currentSchemaVersion: nil))
    }
}

@MainActor
final class AppleAutomaticBackupScheduleTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    /// 16 oct 2026, 18:00 en Madrid.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 18))!
    }

    private func due(_ frequency: BackupFrequency, lastBackupHoursAgo: Double?, lastAttemptMinutesAgo: Double? = nil) -> Bool {
        AppleBackupService.isAutomaticBackupDue(
            frequency: frequency,
            lastBackupAt: lastBackupHoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
            lastAttemptAt: lastAttemptMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
            now: now,
            calendar: calendar
        )
    }

    func testManualNeverRuns() {
        XCTAssertFalse(due(.manual, lastBackupHoursAgo: nil))
        XCTAssertFalse(due(.manual, lastBackupHoursAgo: 24 * 30))
    }

    func testWithoutAnyBackupItRuns() {
        XCTAssertTrue(due(.daily, lastBackupHoursAgo: nil))
        XCTAssertTrue(due(.weekly, lastBackupHoursAgo: nil))
    }

    func testDailyRunsOncePerCalendarDay() {
        XCTAssertFalse(due(.daily, lastBackupHoursAgo: 2), "Ya hay copia hoy")
        XCTAssertTrue(due(.daily, lastBackupHoursAgo: 20), "La última es de ayer a las 22:00")
    }

    func testWeeklyWaitsSevenDays() {
        XCTAssertFalse(due(.weekly, lastBackupHoursAgo: 24 * 6))
        XCTAssertTrue(due(.weekly, lastBackupHoursAgo: 24 * 7))
    }

    func testRecentFailedAttemptIsNotRetried() {
        XCTAssertFalse(due(.daily, lastBackupHoursAgo: nil, lastAttemptMinutesAgo: 10))
        XCTAssertTrue(due(.daily, lastBackupHoursAgo: nil, lastAttemptMinutesAgo: 61))
    }

    func testFutureDatedBackupDoesNotBlockDaily() {
        // Reloj cambiado o copia importada con fecha futura: no cuenta como "hoy".
        XCTAssertFalse(due(.daily, lastBackupHoursAgo: -1), "Mismo día aunque sea una hora después")
        XCTAssertTrue(due(.daily, lastBackupHoursAgo: -30))
    }
}
