import Foundation
import SQLite3
import XCTest
@testable import MiGestorKMPMac

final class AppleBackupRetentionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func entry(_ name: String, daysAgo: Double, emergency: Bool = false) -> AppleBackupService.RetentionEntry {
        AppleBackupService.RetentionEntry(
            url: URL(fileURLWithPath: "/tmp/backups/\(name).migestorbackup", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400),
            note: emergency ? "Copia de seguridad de emergencia previa a restauración de x" : nil
        )
    }

    private func victims(_ entries: [AppleBackupService.RetentionEntry], protecting: Set<URL> = []) -> [String] {
        AppleBackupService.retentionVictims(entries: entries, protecting: protecting, calendar: calendar)
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    func testKeepsEverythingUnderTheLimits() {
        let entries = (0..<7).map { entry("d\($0)", daysAgo: Double($0)) }
        XCTAssertTrue(victims(entries).isEmpty)
    }

    func testDailyCopiesKeepSevenDaysPlusFourWeeks() {
        let entries = (0..<60).map { entry("d\($0)", daysAgo: Double($0)) }
        let removed = Set(victims(entries))
        let kept = entries.map { $0.url.deletingPathExtension().lastPathComponent }.filter { !removed.contains($0) }
        XCTAssertEqual(kept.count, 7 + 4)
        XCTAssertEqual(Array(kept.prefix(7)), (0..<7).map { "d\($0)" })
        // Las 4 semanales son de semanas distintas y anteriores a las recientes.
        let weekly = entries.filter { kept.dropFirst(7).contains($0.url.deletingPathExtension().lastPathComponent) }
        let weeks = Set(weekly.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.createdAt)?.start })
        XCTAssertEqual(weeks.count, 4)
        XCTAssertFalse(kept.contains("d40"))
    }

    func testEmergencyCopiesDoNotPushOutNormalOnes() {
        // 7 copias normales y luego 6 restauraciones seguidas.
        let normals = (0..<7).map { entry("n\($0)", daysAgo: Double($0) + 1) }
        let emergencies = (0..<6).map { entry("e\($0)", daysAgo: Double($0) * 0.01, emergency: true) }
        let removed = victims(normals + emergencies)
        XCTAssertTrue(removed.allSatisfy { $0.hasPrefix("e") }, "Solo salen copias de emergencia")
        // Se quedan las 5 más recientes (regla antigua), que aquí son todas de emergencia.
        XCTAssertEqual(Set(removed), ["e5"])
    }

    func testEmergencyQuotaAppliesOnceTheyAreOlder() {
        let emergencies = (0..<4).map { entry("e\($0)", daysAgo: 10 + Double($0), emergency: true) }
        let normals = (0..<7).map { entry("n\($0)", daysAgo: Double($0)) }
        XCTAssertEqual(Set(victims(normals + emergencies)), ["e2", "e3"])
    }

    func testNewRuleNeverRemovesWhatTheOldRuleKept() {
        // El caso real: casi todo eran copias de emergencia.
        let entries = (0..<5).map { entry("e\($0)", daysAgo: Double($0) * 0.01, emergency: true) }
            + [entry("n0", daysAgo: 1)]
        XCTAssertTrue(victims(entries).isEmpty)
    }

    func testRetentionNeverRemovesProtectedBackup() {
        let entries = (0..<60).map { entry("d\($0)", daysAgo: Double($0)) }
        let restoring = entries[59].url
        XCTAssertFalse(victims(entries, protecting: [restoring]).contains("d59"))
    }

    func testRetentionOrdersByManifestDateNotFolderOrder() {
        // Una copia importada hoy pero creada hace 3 días cuenta como de hace 3 días.
        var entries = (0..<7).map { entry("d\($0)", daysAgo: Double($0) * 0.1) }
        entries.insert(entry("importada", daysAgo: 3), at: 0)
        entries.append(entry("vieja", daysAgo: 3.5))
        let removed = victims(entries)
        XCTAssertTrue(removed.contains("vieja"))
        XCTAssertFalse(removed.contains("d0"))
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

    /// Regresión: la instantánea de una base en modo WAL fallaba al validarse en solo
    /// lectura («unable to open database file» sobre el -wal inexistente).
    func testSnapshotOfWALDatabaseValidates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migestor-wal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("database.sqlite")
        let destinationURL = directory.appendingPathComponent("restore.sqlite")

        var source: OpaquePointer?
        XCTAssertEqual(sqlite3_open(sourceURL.path, &source), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(source, "PRAGMA journal_mode = WAL; CREATE TABLE t(x); INSERT INTO t VALUES (1);", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_close(source) }

        XCTAssertNoThrow(try AppleSQLiteBackupValidator.materializeSnapshot(from: sourceURL, to: destinationURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path + "-wal"))
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
