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
