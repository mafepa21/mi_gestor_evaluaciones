import Foundation
import SQLite3
import XCTest
@testable import MiGestorKMPMac

final class AppleBackupIntegrityTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migestor-backup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory, FileManager.default.fileExists(atPath: workDirectory.path) {
            try FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testSQLiteValidationAcceptsAnIntactDatabase() throws {
        let databaseURL = workDirectory.appendingPathComponent("valid.sqlite")
        try createDatabase(at: databaseURL, withBrokenForeignKey: false)

        XCTAssertNoThrow(try AppleSQLiteBackupValidator.validateDatabase(at: databaseURL))
    }

    func testSQLiteValidationRejectsBrokenForeignKeys() throws {
        let databaseURL = workDirectory.appendingPathComponent("broken-fk.sqlite")
        try createDatabase(at: databaseURL, withBrokenForeignKey: true)

        XCTAssertThrowsError(try AppleSQLiteBackupValidator.validateDatabase(at: databaseURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("foreign_key_check"))
        }
    }

    func testMaterializedSnapshotIsSelfContainedAndValid() throws {
        let sourceURL = workDirectory.appendingPathComponent("source.sqlite")
        let destinationURL = workDirectory.appendingPathComponent("snapshot.sqlite")
        try createDatabase(at: sourceURL, withBrokenForeignKey: false)

        try AppleSQLiteBackupValidator.materializeSnapshot(from: sourceURL, to: destinationURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertNoThrow(try AppleSQLiteBackupValidator.validateDatabase(at: destinationURL))
    }

    func testRestoreTransactionRollsBackDatabaseAndDocumentsWhenLastStepFails() throws {
        let liveDatabase = workDirectory.appendingPathComponent("live.sqlite")
        let stagedDatabase = workDirectory.appendingPathComponent("staged.sqlite")
        try Data("old-db".utf8).write(to: liveDatabase)
        try Data("new-db".utf8).write(to: stagedDatabase)

        let liveAttachments = workDirectory.appendingPathComponent("attachments", isDirectory: true)
        let stagedAttachments = workDirectory.appendingPathComponent("staged-attachments", isDirectory: true)
        let liveLearning = workDirectory.appendingPathComponent("learning", isDirectory: true)
        let stagedLearning = workDirectory.appendingPathComponent("staged-learning", isDirectory: true)
        try writeMarker("old-attachment", in: liveAttachments)
        try writeMarker("new-attachment", in: stagedAttachments)
        try writeMarker("old-learning", in: liveLearning)
        try writeMarker("new-learning", in: stagedLearning)

        let transaction = AppleBackupRestoreTransaction { destination in
            if destination == liveLearning {
                throw NSError(domain: "test", code: 1)
            }
        }

        XCTAssertThrowsError(
            try transaction.commit([
                .replace(stagedURL: stagedDatabase, destinationURL: liveDatabase),
                .replace(stagedURL: stagedAttachments, destinationURL: liveAttachments),
                .replace(stagedURL: stagedLearning, destinationURL: liveLearning),
            ])
        )
        XCTAssertEqual(try String(contentsOf: liveDatabase, encoding: .utf8), "old-db")
        XCTAssertEqual(try readMarker(in: liveAttachments), "old-attachment")
        XCTAssertEqual(try readMarker(in: liveLearning), "old-learning")
    }

    private func createDatabase(at url: URL, withBrokenForeignKey: Bool) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { throw NSError(domain: "test", code: 2) }
        defer { sqlite3_close(database) }

        try execute("PRAGMA foreign_keys = OFF;", database: database)
        try execute("CREATE TABLE parent (id INTEGER PRIMARY KEY);", database: database)
        try execute(
            "CREATE TABLE child (id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL REFERENCES parent(id));",
            database: database
        )
        try execute("INSERT INTO parent(id) VALUES (1);", database: database)
        let parentID = withBrokenForeignKey ? 999 : 1
        try execute("INSERT INTO child(id, parent_id) VALUES (1, \(parentID));", database: database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func writeMarker(_ value: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(value.utf8).write(to: directory.appendingPathComponent("marker.txt"))
    }

    private func readMarker(in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent("marker.txt"), encoding: .utf8)
    }
}
