import CryptoKit
import Foundation
import XCTest
@testable import MiGestorKMPMac

final class AppleEncryptedBackupTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migestor-encrypted-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory, FileManager.default.fileExists(atPath: workDirectory.path) {
            try FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testPBKDF2SHA256MatchesKnownVector() throws {
        let key = try ApplePasswordKeyDerivation.deriveKey(
            password: "password",
            salt: Data("salt".utf8),
            iterations: 1
        )

        let actual = key.withUnsafeBytes { Data($0).hexString }
        XCTAssertEqual(actual, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    func testMultiChunkRoundTripAndRandomizedContainer() throws {
        let plaintext = Data((0..<(150 * 1_024)).map { UInt8($0 % 251) })
        let source = workDirectory.appendingPathComponent("source.zip")
        let first = workDirectory.appendingPathComponent("first.migestorbackupx")
        let second = workDirectory.appendingPathComponent("second.migestorbackupx")
        let restored = workDirectory.appendingPathComponent("restored.zip")
        try plaintext.write(to: source)

        try AppleEncryptedBackupContainer.encrypt(
            plaintextURL: source,
            destinationURL: first,
            password: "contraseña-de-prueba",
            configuration: testConfiguration
        )
        try AppleEncryptedBackupContainer.encrypt(
            plaintextURL: source,
            destinationURL: second,
            password: "contraseña-de-prueba",
            configuration: testConfiguration
        )
        try AppleEncryptedBackupContainer.decrypt(
            encryptedURL: first,
            destinationURL: restored,
            password: "contraseña-de-prueba",
            configuration: testConfiguration
        )

        XCTAssertEqual(try Data(contentsOf: restored), plaintext)
        XCTAssertNotEqual(try Data(contentsOf: first), try Data(contentsOf: second))
    }

    func testWrongPasswordUsesStableAuthenticationError() throws {
        let encrypted = try makeEncryptedFixture()
        let restored = workDirectory.appendingPathComponent("wrong-password.zip")

        XCTAssertThrowsError(
            try AppleEncryptedBackupContainer.decrypt(
                encryptedURL: encrypted,
                destinationURL: restored,
                password: "otra-contraseña",
                configuration: testConfiguration
            )
        ) { error in
            XCTAssertEqual(error as? AppleEncryptedBackupError, .authenticationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.path))
    }

    func testTamperingIsDetectedAndPartialOutputIsRemoved() throws {
        let encrypted = try makeEncryptedFixture()
        var bytes = try Data(contentsOf: encrypted)
        bytes[AppleEncryptedBackupHeader.encodedSize + 4 + 7] ^= 0xff
        try bytes.write(to: encrypted, options: .atomic)
        let restored = workDirectory.appendingPathComponent("tampered.zip")

        XCTAssertThrowsError(
            try AppleEncryptedBackupContainer.decrypt(
                encryptedURL: encrypted,
                destinationURL: restored,
                password: "contraseña-de-prueba",
                configuration: testConfiguration
            )
        ) { error in
            XCTAssertEqual(error as? AppleEncryptedBackupError, .authenticationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.path))
    }

    func testTruncationAndTrailingDataAreRejected() throws {
        let truncated = try makeEncryptedFixture(name: "truncated")
        var truncatedBytes = try Data(contentsOf: truncated)
        truncatedBytes.removeLast()
        try truncatedBytes.write(to: truncated, options: .atomic)
        XCTAssertThrowsError(
            try AppleEncryptedBackupContainer.decrypt(
                encryptedURL: truncated,
                destinationURL: workDirectory.appendingPathComponent("restored-truncated.zip"),
                password: "contraseña-de-prueba",
                configuration: testConfiguration
            )
        ) { error in
            XCTAssertEqual(error as? AppleEncryptedBackupError, .truncatedFile)
        }

        let extended = try makeEncryptedFixture(name: "extended")
        let handle = try FileHandle(forWritingTo: extended)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        XCTAssertThrowsError(
            try AppleEncryptedBackupContainer.decrypt(
                encryptedURL: extended,
                destinationURL: workDirectory.appendingPathComponent("restored-extended.zip"),
                password: "contraseña-de-prueba",
                configuration: testConfiguration
            )
        ) { error in
            XCTAssertEqual(error as? AppleEncryptedBackupError, .trailingData)
        }
    }

    func testPackageArchiveRoundTripIncludesHiddenFiles() throws {
        let package = workDirectory.appendingPathComponent("legacy.migestorbackup", isDirectory: true)
        let nested = package.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("database".utf8).write(to: package.appendingPathComponent("database.sqlite"))
        try Data("hidden".utf8).write(to: nested.appendingPathComponent(".evidence"))
        let archive = workDirectory.appendingPathComponent("package.zip")
        let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)

        try AppleBackupPackageArchive.createArchive(packageURL: package, archiveURL: archive)
        try AppleBackupPackageArchive.extractArchive(archiveURL: archive, destinationURL: extracted)

        XCTAssertEqual(
            try Data(contentsOf: extracted.appendingPathComponent("attachments/.evidence")),
            Data("hidden".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: extracted.appendingPathComponent("database.sqlite")),
            Data("database".utf8)
        )
    }

    func testUnsafeArchivePathsAreRejected() {
        for path in ["../database.sqlite", "/tmp/database.sqlite", "attachments\\evil", "./manifest.json", "attachments//evil"] {
            XCTAssertThrowsError(try AppleBackupPackageArchive.validateRelativePath(path))
        }
        XCTAssertNoThrow(try AppleBackupPackageArchive.validateRelativePath("attachments/evidence.pdf"))
    }

    func testLegacyAndEncryptedFormatsAreDetected() throws {
        let legacy = workDirectory.appendingPathComponent("backup.migestorbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        XCTAssertEqual(try ApplePortableBackupFormat.detect(at: legacy), .legacyPackage)

        let encrypted = try makeEncryptedFixture()
        XCTAssertEqual(try ApplePortableBackupFormat.detect(at: encrypted), .encryptedV1)
    }

    func testHeaderRejectsExcessiveKDFWorkBeforeDerivation() throws {
        let header = AppleEncryptedBackupHeader(
            iterations: testConfiguration.maximumAcceptedIterations + 1,
            chunkSize: testConfiguration.chunkSize,
            plaintextSize: 1,
            salt: Data(repeating: 1, count: 16),
            noncePrefix: Data(repeating: 2, count: 8)
        )
        XCTAssertThrowsError(try AppleEncryptedBackupHeader.decode(header.encoded(), configuration: testConfiguration)) { error in
            XCTAssertEqual(error as? AppleEncryptedBackupError, .invalidParameters)
        }

        let emptyHeader = AppleEncryptedBackupHeader(
            iterations: testConfiguration.iterations,
            chunkSize: testConfiguration.chunkSize,
            plaintextSize: 0,
            salt: Data(repeating: 1, count: 16),
            noncePrefix: Data(repeating: 2, count: 8)
        )
        XCTAssertThrowsError(try AppleEncryptedBackupHeader.decode(emptyHeader.encoded(), configuration: testConfiguration)) { error in
            XCTAssertEqual(error as? AppleEncryptedBackupError, .invalidParameters)
        }
    }

    private var testConfiguration: AppleEncryptedBackupConfiguration {
        AppleEncryptedBackupConfiguration(
            iterations: 1,
            chunkSize: ApplePortableBackupLimits.minimumChunkBytes,
            minimumAcceptedIterations: 1,
            maximumAcceptedIterations: 10,
            maximumArchiveBytes: 2 * 1_024 * 1_024
        )
    }

    private func makeEncryptedFixture(name: String = UUID().uuidString) throws -> URL {
        let source = workDirectory.appendingPathComponent("\(name).zip")
        let encrypted = workDirectory.appendingPathComponent("\(name).migestorbackupx")
        try Data((0..<(80 * 1_024)).map { UInt8($0 % 239) }).write(to: source)
        try AppleEncryptedBackupContainer.encrypt(
            plaintextURL: source,
            destinationURL: encrypted,
            password: "contraseña-de-prueba",
            configuration: testConfiguration
        )
        return encrypted
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
