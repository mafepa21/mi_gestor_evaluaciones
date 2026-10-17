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

    func testSQLiteValidationAcceptsOrphanReferencesAndCountsThem() throws {
        let databaseURL = workDirectory.appendingPathComponent("broken-fk.sqlite")
        try createDatabase(at: databaseURL, withBrokenForeignKey: true)

        XCTAssertEqual(try AppleSQLiteBackupValidator.validateDatabase(at: databaseURL), 1)
    }

    func testSQLiteValidationReportsZeroOrphansForIntactDatabase() throws {
        let databaseURL = workDirectory.appendingPathComponent("intact.sqlite")
        try createDatabase(at: databaseURL, withBrokenForeignKey: false)

        XCTAssertEqual(try AppleSQLiteBackupValidator.validateDatabase(at: databaseURL), 0)
    }

    func testMaterializedSnapshotIsSelfContainedAndValid() throws {
        let sourceURL = workDirectory.appendingPathComponent("source.sqlite")
        let destinationURL = workDirectory.appendingPathComponent("snapshot.sqlite")
        try createDatabase(at: sourceURL, withBrokenForeignKey: false)

        try AppleSQLiteBackupValidator.materializeSnapshot(from: sourceURL, to: destinationURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertNoThrow(try AppleSQLiteBackupValidator.validateDatabase(at: destinationURL))
    }

    func testValidationAndSnapshotWorkForWALDatabaseInReadOnlyFolder() throws {
        let packageURL = workDirectory.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let sourceURL = packageURL.appendingPathComponent("database.sqlite")
        try createDatabase(at: sourceURL, withBrokenForeignKey: false)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(sourceURL.path, &database), SQLITE_OK)
        try execute("PRAGMA journal_mode = WAL;", database: database!)
        sqlite3_close(database)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: packageURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: packageURL.path)
        }

        XCTAssertEqual(try AppleSQLiteBackupValidator.validateDatabase(at: sourceURL), 0)
        let destinationURL = workDirectory.appendingPathComponent("snapshot-ro.sqlite")
        XCTAssertNoThrow(try AppleSQLiteBackupValidator.materializeSnapshot(from: sourceURL, to: destinationURL))
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

    // MARK: - Libreta en la copia

    func testLibretaRoundTripRestoresStoreAndSupportFolder() throws {
        let fm = FileManager.default
        let live = LibretaStorage(directoryURL: workDirectory.appendingPathComponent("live", isDirectory: true))
        let package = workDirectory.appendingPathComponent("backup.migestorbackup", isDirectory: true)
        try fm.createDirectory(at: live.directoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try createLibretaStore(at: live.storeURL, notebooks: 3)
        try writeMarker("dibujo-original", in: live.supportURL)

        XCTAssertTrue(try LibretaBackupPackager.package(from: live, into: package))
        XCTAssertEqual(LibretaBackupPackager.notebookCount(in: LibretaBackupPackager.databaseURL(in: package)), 3)
        XCTAssertEqual(try readMarker(in: LibretaBackupPackager.supportURL(in: package)), "dibujo-original")

        // Cambia la Libreta activa después de la copia.
        try fm.removeItem(at: live.storeURL)
        try createLibretaStore(at: live.storeURL, notebooks: 7)
        try writeMarker("dibujo-nuevo", in: live.supportURL)

        let staged = try XCTUnwrap(LibretaBackupPackager.stageRestore(
            from: package,
            checksumKeys: [LibretaBackupPackager.databaseChecksumKey],
            to: live,
            transactionID: "test"
        ))
        try AppleBackupRestoreTransaction().commit(staged.operations)

        XCTAssertEqual(LibretaBackupPackager.notebookCount(in: live.storeURL), 3)
        XCTAssertEqual(try readMarker(in: live.supportURL), "dibujo-original")
        staged.stagedURLs.forEach { XCTAssertFalse(fm.fileExists(atPath: $0.path)) }
    }

    func testLibretaChecksumListHasOnlyFilesAndKeepsHiddenOnes() throws {
        let fm = FileManager.default
        let live = LibretaStorage(directoryURL: workDirectory.appendingPathComponent("live", isDirectory: true))
        let package = workDirectory.appendingPathComponent("backup.migestorbackup", isDirectory: true)
        try fm.createDirectory(at: live.directoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try createLibretaStore(at: live.storeURL, notebooks: 1)
        let external = live.supportURL.appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        try writeMarker("dibujo", in: external)
        try Data("oculto".utf8).write(to: external.appendingPathComponent(".oculto"))

        XCTAssertTrue(try LibretaBackupPackager.package(from: live, into: package))
        let paths = try LibretaBackupPackager.regularFileRelativePaths(in: LibretaBackupPackager.folderURL(in: package))

        XCTAssertEqual(paths, [
            "Libreta.sqlite",
            "support/_EXTERNAL_DATA/.oculto",
            "support/_EXTERNAL_DATA/marker.txt",
        ])
    }

    func testLibretaIsNotPackagedWhenThereIsNoStore() throws {
        let live = LibretaStorage(directoryURL: workDirectory.appendingPathComponent("empty", isDirectory: true))
        let package = workDirectory.appendingPathComponent("backup.migestorbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        XCTAssertFalse(try LibretaBackupPackager.package(from: live, into: package))
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibretaBackupPackager.folderURL(in: package).path))
    }

    func testRestoreWithoutLibretaLeavesCurrentLibretaUntouched() throws {
        let live = LibretaStorage(directoryURL: workDirectory.appendingPathComponent("live", isDirectory: true))
        let package = workDirectory.appendingPathComponent("old.migestorbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: live.directoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try createLibretaStore(at: live.storeURL, notebooks: 5)

        let staged = try LibretaBackupPackager.stageRestore(
            from: package,
            checksumKeys: ["database.sqlite", "manifest.json"],
            to: live,
            transactionID: "test"
        )

        XCTAssertNil(staged)
        XCTAssertEqual(LibretaBackupPackager.notebookCount(in: live.storeURL), 5)
    }

    func testOldSummaryWithoutLibretaCountStillDecodes() throws {
        let json = #"{"classCount":1,"studentCount":2,"notebookColumnCount":3,"rubricCount":4,"attendanceRecordCount":5}"#
        let summary = try JSONDecoder().decode(AppleBackupSummary.self, from: Data(json.utf8))
        XCTAssertNil(summary.libretaCount)
        XCTAssertEqual(summary.studentCount, 2)
    }

    /// Base con la forma mínima de Core Data: tabla `ZNOTEBOOK`.
    private func createLibretaStore(at url: URL, notebooks: Int) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { throw NSError(domain: "test", code: 2) }
        defer { sqlite3_close(database) }
        try execute("CREATE TABLE ZNOTEBOOK (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);", database: database)
        for index in 0..<notebooks {
            try execute("INSERT INTO ZNOTEBOOK(ZTITLE) VALUES ('Libreta \(index)');", database: database)
        }
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
