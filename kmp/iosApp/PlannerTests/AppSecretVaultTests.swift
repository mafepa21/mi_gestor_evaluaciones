import Foundation
import Security
import XCTest
@testable import MiGestorKMPMac

final class AppSecretVaultTests: XCTestCase {
    private final class MockKeychainBackend: AppSecretVaultKeychainBackend {
        var masterKey: Data?
        var forceMasterKeyResult: AppSecretVaultKeychainReadResult?
        var legacyItems: [String: Data] = [:]

        private(set) var masterKeyLoadCount = 0
        private(set) var masterKeySaveCount = 0
        private(set) var legacyLoadCount = 0
        private(set) var legacyDeleteCount = 0

        private func legacyKey(service: String, account: String) -> String {
            "\(service)::\(account)"
        }

        func loadMasterKey(service: String, account: String) -> AppSecretVaultKeychainReadResult {
            masterKeyLoadCount += 1
            if let forced = forceMasterKeyResult {
                return forced
            }
            if let masterKey {
                return .found(masterKey)
            }
            return .notFound
        }

        func saveMasterKey(_ key: Data, service: String, account: String, label: String) -> Bool {
            masterKeySaveCount += 1
            masterKey = key
            return true
        }

        func deleteMasterKey(service: String, account: String) -> Bool {
            let existed = masterKey != nil
            masterKey = nil
            return existed
        }

        func loadLegacyItem(service: String, account: String) -> Data? {
            legacyLoadCount += 1
            return legacyItems[legacyKey(service: service, account: account)]
        }

        func deleteLegacyItem(service: String, account: String) -> Bool {
            legacyDeleteCount += 1
            return legacyItems.removeValue(forKey: legacyKey(service: service, account: account)) != nil
        }

        func setLegacyItem(_ data: Data, service: String, account: String) {
            legacyItems[legacyKey(service: service, account: account)] = data
        }
    }

    private func makeTempVaultURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSecretVaultTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir.appendingPathComponent("secret-vault.enc")
    }

    func testSingleMasterKeyUnlocksMultipleServicesAcrossSessions() throws {
        let vaultURL = makeTempVaultURL()
        let backend = MockKeychainBackend()

        let writer = AppSecretVault(vaultURL: vaultURL, backend: backend)
        let portalKey = Data(repeating: 0xAA, count: 32)
        let formKey = Data(repeating: 0xBB, count: 32)

        XCTAssertTrue(writer.saveData(portalKey, service: "com.migestor.portal", account: "tablon-1"))
        XCTAssertTrue(writer.saveData(formKey, service: "com.migestor.entregas-web", account: "form-1"))
        XCTAssertTrue(writer.saveString("cuenta-secreta", service: "com.migestor.buzon", account: "cuenta"))
        XCTAssertEqual(backend.masterKeySaveCount, 1)

        // El fichero en disco debe estar cifrado y no contener los secretos en claro.
        let onDisk = try Data(contentsOf: vaultURL)
        XCTAssertNil(onDisk.range(of: Data("cuenta-secreta".utf8)))
        XCTAssertNil(onDisk.range(of: portalKey))

        // Nueva sesión (como al instalar una versión nueva): solo 1 lectura de clave maestra
        // para todos los secretos de todos los servicios.
        let reader = AppSecretVault(vaultURL: vaultURL, backend: backend)
        let loadsBefore = backend.masterKeyLoadCount

        XCTAssertEqual(reader.loadData(service: "com.migestor.portal", account: "tablon-1"), portalKey)
        XCTAssertEqual(reader.loadData(service: "com.migestor.entregas-web", account: "form-1"), formKey)
        XCTAssertEqual(reader.loadString(service: "com.migestor.buzon", account: "cuenta"), "cuenta-secreta")
        XCTAssertEqual(backend.masterKeyLoadCount - loadsBefore, 1)
    }

    func testUserDenialBlocksFurtherPromptsUntilExplicitRetry() {
        let vaultURL = makeTempVaultURL()
        let backend = MockKeychainBackend()

        let initial = AppSecretVault(vaultURL: vaultURL, backend: backend)
        XCTAssertTrue(initial.saveString("tok-1", service: "com.migestor.buzon", account: "cuenta"))
        backend.setLegacyItem(Data("legacy-should-not-be-read".utf8), service: "com.migestor.portal", account: "tablon-old")

        // Simulamos que el usuario pulsa «Denegar» en el diálogo del Llavero.
        backend.forceMasterKeyResult = .denied(errSecAuthFailed)
        let deniedSession = AppSecretVault(vaultURL: vaultURL, backend: backend)
        let loadsBefore = backend.masterKeyLoadCount
        let legacyBefore = backend.legacyLoadCount

        XCTAssertNil(deniedSession.loadString(service: "com.migestor.buzon", account: "cuenta"))
        XCTAssertTrue(deniedSession.isLockedByUserDenial)
        // Lecturas posteriores no deben volver a pedir la clave maestra ni caer al Llavero antiguo.
        XCTAssertNil(deniedSession.loadString(service: "com.migestor.buzon", account: "cuenta"))
        XCTAssertNil(deniedSession.loadData(service: "com.migestor.portal", account: "tablon-old"))
        XCTAssertEqual(backend.masterKeyLoadCount - loadsBefore, 1)
        XCTAssertEqual(backend.legacyLoadCount - legacyBefore, 0)

        // Si el usuario decide reintentar y acepta, todo se desbloquea de una vez.
        backend.forceMasterKeyResult = nil
        XCTAssertTrue(deniedSession.retryUnlock())
        XCTAssertFalse(deniedSession.isLockedByUserDenial)
        XCTAssertEqual(deniedSession.loadString(service: "com.migestor.buzon", account: "cuenta"), "tok-1")
    }

    func testLazyMigrationMovesLegacySecretIntoVaultAndDeletesOldEntry() {
        let vaultURL = makeTempVaultURL()
        let backend = MockKeychainBackend()
        let legacySecret = Data(repeating: 0x42, count: 32)
        backend.setLegacyItem(legacySecret, service: "com.migestor.portal", account: "tablon-migrado")

        let vault = AppSecretVault(vaultURL: vaultURL, backend: backend)
        XCTAssertEqual(vault.loadData(service: "com.migestor.portal", account: "tablon-migrado"), legacySecret)
        XCTAssertNil(backend.loadLegacyItem(service: "com.migestor.portal", account: "tablon-migrado"))

        // En una nueva sesión el secreto ya sale de la bóveda sin tocar el Llavero antiguo.
        let reloaded = AppSecretVault(vaultURL: vaultURL, backend: backend)
        let legacyLoadsBefore = backend.legacyLoadCount
        XCTAssertEqual(reloaded.loadData(service: "com.migestor.portal", account: "tablon-migrado"), legacySecret)
        XCTAssertEqual(backend.legacyLoadCount - legacyLoadsBefore, 0)
    }

    func testMissingMasterKeyNeverOverwritesExistingEncryptedVault() throws {
        let vaultURL = makeTempVaultURL()
        let backend = MockKeychainBackend()

        let vault = AppSecretVault(vaultURL: vaultURL, backend: backend)
        XCTAssertTrue(vault.saveString("valioso", service: "com.migestor.buzon", account: "cuenta"))
        let originalCiphertext = try Data(contentsOf: vaultURL)

        // Si desaparece la clave maestra pero el fichero existe, no debe destruirlo.
        backend.masterKey = nil
        let locked = AppSecretVault(vaultURL: vaultURL, backend: backend)
        XCTAssertNil(locked.loadString(service: "com.migestor.buzon", account: "cuenta"))
        XCTAssertFalse(locked.saveString("nuevo", service: "com.migestor.buzon", account: "otra"))
        XCTAssertEqual(try Data(contentsOf: vaultURL), originalCiphertext)
    }

    func testDeleteRemovesSecretFromVaultAndLegacyKeychain() {
        let vaultURL = makeTempVaultURL()
        let backend = MockKeychainBackend()
        let vault = AppSecretVault(vaultURL: vaultURL, backend: backend)

        XCTAssertTrue(vault.saveString("secret", service: "com.migestor.buzon", account: "lectura-1"))
        XCTAssertTrue(vault.delete(service: "com.migestor.buzon", account: "lectura-1"))
        XCTAssertNil(vault.loadString(service: "com.migestor.buzon", account: "lectura-1"))

        let reloaded = AppSecretVault(vaultURL: vaultURL, backend: backend)
        XCTAssertNil(reloaded.loadString(service: "com.migestor.buzon", account: "lectura-1"))
    }
}
