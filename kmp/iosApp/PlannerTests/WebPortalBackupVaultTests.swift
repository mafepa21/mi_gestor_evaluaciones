import Foundation
import XCTest
@testable import MiGestorKMPMac

final class WebPortalBackupVaultTests: XCTestCase {
    private var workDir: URL!
    private var sourceService: String!
    private var targetService: String!
    private var createdPortalIds: [String] = []

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migestor-portal-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        sourceService = "com.migestor.portal.test.src.\(UUID().uuidString)"
        targetService = "com.migestor.portal.test.dst.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        let srcDummy = workDir.appendingPathComponent("src/alumnos.json")
        let dstDummy = workDir.appendingPathComponent("dst/alumnos.json")
        let srcStore = WebPortalStore(fileURL: srcDummy, keychainService: sourceService)
        let dstStore = WebPortalStore(fileURL: dstDummy, keychainService: targetService)
        for pid in createdPortalIds {
            srcStore.deleteTablonKey(portalId: pid)
            srcStore.deletePendingKey(portalId: pid)
            dstStore.deleteTablonKey(portalId: pid)
            dstStore.deletePendingKey(portalId: pid)
        }
        if let workDir, FileManager.default.fileExists(atPath: workDir.path) {
            try FileManager.default.removeItem(at: workDir)
        }
    }

    func testCaptureYRestoreRoundTripEnCarpetaYLlavero() throws {
        let srcDir = workDir.appendingPathComponent("src", isDirectory: true)
        let dstDir = workDir.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let portalId = "pid-\(UUID().uuidString.prefix(8))"
        createdPortalIds.append(portalId)
        let keyA = Data(repeating: 0xAB, count: 32)
        let keyPending = Data(repeating: 0xCD, count: 32)

        let srcAlumnos = srcDir.appendingPathComponent("alumnos.json")
        var srcStore = WebPortalStore(fileURL: srcAlumnos, keychainService: sourceService)
        srcStore.set(WebPortalEntry(
            portalId: portalId,
            estadoConocido: WebPortalAccountStatus.activada.rawValue,
            invitadoEl: nil,
            ultimaVersion: 7
        ), for: 42)
        try srcStore.save()
        XCTAssertTrue(srcStore.saveTablonKey(keyA, portalId: portalId))
        XCTAssertTrue(srcStore.savePendingKey(keyPending, portalId: portalId))

        let notasRaw = Data("{\"version\":1,\"grupos\":{}}".utf8)
        let torneosRaw = Data("{\"version\":1,\"grupos\":{}}".utf8)
        try notasRaw.write(to: srcDir.appendingPathComponent("notas-visibles.json"))
        try torneosRaw.write(to: srcDir.appendingPathComponent("torneos-visibles.json"))

        let vault = try XCTUnwrap(WebPortalBackupVault.capture(
            portalDirectory: srcDir,
            keychainService: sourceService,
            readAccountKey: { "clave-cuenta-secreta-43" }
        ))
        XCTAssertEqual(vault.summary.accountCount, 1)
        XCTAssertEqual(vault.summary.keyCount, 1)
        XCTAssertTrue(vault.summary.hasAccountKey)

        var restoredAccountKey: String?
        let restoredKeys = try vault.restore(
            to: dstDir,
            keychainService: targetService,
            writeAccountKey: {
                restoredAccountKey = $0
                return true
            }
        )

        XCTAssertEqual(restoredKeys, 1)
        XCTAssertEqual(restoredAccountKey, "clave-cuenta-secreta-43")

        let dstStore = WebPortalStore(
            fileURL: dstDir.appendingPathComponent("alumnos.json"),
            keychainService: targetService
        )
        XCTAssertEqual(dstStore[42]?.portalId, portalId)
        XCTAssertEqual(dstStore.tablonKey(portalId: portalId), keyA)
        XCTAssertEqual(dstStore.pendingKey(portalId: portalId), keyPending)
        XCTAssertEqual(try Data(contentsOf: dstDir.appendingPathComponent("notas-visibles.json")), notasRaw)
        XCTAssertEqual(try Data(contentsOf: dstDir.appendingPathComponent("torneos-visibles.json")), torneosRaw)
    }

    func testContenedorCifradoEmpaquetaYExtraeSinDejarTextoClaroEnDisco() throws {
        let packageDir = workDir.appendingPathComponent("sample.migestorbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        try Data("manifest".utf8).write(to: packageDir.appendingPathComponent("manifest.json"))

        let vault = WebPortalBackupVault(
            alumnosJSON: Data("{}".utf8),
            notasVisiblesJSON: nil,
            torneosVisiblesJSON: nil,
            keys: [.init(portalId: "p1", tablonKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(), pendingKeyBase64: nil)],
            accountKey: "cuenta-demo"
        )
        let archiveURL = workDir.appendingPathComponent("backup.zip")
        let encryptedURL = workDir.appendingPathComponent("backup.migestorbackupx")
        let decryptedURL = workDir.appendingPathComponent("decrypted.zip")
        let extractedDir = workDir.appendingPathComponent("extracted.migestorbackup", isDirectory: true)

        try AppleBackupPackageArchive.createArchive(
            packageURL: packageDir,
            archiveURL: archiveURL,
            extraEntries: [WebPortalBackupVault.archiveEntryName: try vault.encodedData()]
        )
        // El paquete origen `.migestorbackup` nunca recibe el fichero en texto claro.
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent(WebPortalBackupVault.archiveEntryName).path))

        let fastConfig = AppleEncryptedBackupConfiguration(
            iterations: 1,
            chunkSize: ApplePortableBackupLimits.minimumChunkBytes,
            minimumAcceptedIterations: 1,
            maximumAcceptedIterations: 10,
            maximumArchiveBytes: 2 * 1_024 * 1_024
        )
        try AppleEncryptedBackupContainer.encrypt(
            plaintextURL: archiveURL,
            destinationURL: encryptedURL,
            password: "contraseña-larga-segura",
            configuration: fastConfig
        )
        try AppleEncryptedBackupContainer.decrypt(
            encryptedURL: encryptedURL,
            destinationURL: decryptedURL,
            password: "contraseña-larga-segura",
            configuration: fastConfig
        )
        try AppleBackupPackageArchive.extractArchive(archiveURL: decryptedURL, destinationURL: extractedDir)

        let extractedVault = try WebPortalBackupVault.extractAndStrip(
            in: extractedDir,
            format: .encryptedV1
        )
        XCTAssertEqual(extractedVault, vault)
        // Tras `extractAndStrip`, nunca queda `portal-vault.json` en disco dentro de la copia local.
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent(WebPortalBackupVault.archiveEntryName).path))
    }

    func testCopiaLegacyIgnoraYBorraPortalVault() throws {
        let legacyDir = workDir.appendingPathComponent("legacy.migestorbackup", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let fakeVault = WebPortalBackupVault(
            alumnosJSON: nil,
            notasVisiblesJSON: nil,
            torneosVisiblesJSON: nil,
            keys: [],
            accountKey: "no-debe-importarse"
        )
        let vaultFile = legacyDir.appendingPathComponent(WebPortalBackupVault.archiveEntryName)
        try fakeVault.encodedData().write(to: vaultFile)

        let extracted = try WebPortalBackupVault.extractAndStrip(
            in: legacyDir,
            format: .legacyPackage
        )
        XCTAssertNil(extracted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultFile.path))
    }
}
