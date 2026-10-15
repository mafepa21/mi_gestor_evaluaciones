import Foundation
import SQLite3
#if canImport(UIKit)
import UIKit
#endif

/// Dónde guarda la Libreta (solo iPad) su base SwiftData.
///
/// SwiftData usa SQLite por debajo: `Libreta.store` con sus `-wal`/`-shm`, y una
/// carpeta oculta `.Libreta_SUPPORT` donde Core Data deja los datos grandes marcados
/// como `.externalStorage` (dibujos e imágenes). Ese nombre lo decide Core Data:
/// si no existe, simplemente no hay nada que copiar.
struct LibretaStorage {
    let directoryURL: URL

    var storeURL: URL { directoryURL.appendingPathComponent("Libreta.store") }
    var walURL: URL { URL(fileURLWithPath: storeURL.path + "-wal") }
    var shmURL: URL { URL(fileURLWithPath: storeURL.path + "-shm") }
    var supportURL: URL { directoryURL.appendingPathComponent(".Libreta_SUPPORT", isDirectory: true) }

    /// La de verdad: Application Support de la app (la misma ruta que SwiftData usa por defecto).
    static var standard: LibretaStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return LibretaStorage(directoryURL: base)
    }

    /// Solo el iPad tiene Libreta: ni el Mac ni el iPhone guardan o restauran libretas.
    static var isSupportedOnThisPlatform: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
}

/// Mete la Libreta en un paquete de copia de Seguridad y la saca al restaurar.
///
/// En el paquete va en `libreta/`:
/// - `Libreta.sqlite`: instantánea coherente (API de copia de SQLite, integra el WAL);
/// - `support/`: copia de `.Libreta_SUPPORT` (sin punto, para que entre en los checksums).
enum LibretaBackupPackager {
    static let folderName = "libreta"
    static let databaseFileName = "Libreta.sqlite"
    static let supportFolderName = "support"
    /// Clave de la base en `checksums.json`. Si no está, la copia no trae libretas.
    static let databaseChecksumKey = "\(folderName)/\(databaseFileName)"

    static func folderURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(folderName, isDirectory: true)
    }

    static func databaseURL(in packageURL: URL) -> URL {
        folderURL(in: packageURL).appendingPathComponent(databaseFileName)
    }

    static func supportURL(in packageURL: URL) -> URL {
        folderURL(in: packageURL).appendingPathComponent(supportFolderName, isDirectory: true)
    }

    /// Copia la Libreta al paquete. Devuelve `false` (y no crea nada) si no hay Libreta.
    @discardableResult
    static func package(
        from storage: LibretaStorage,
        into packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: storage.storeURL.path) else { return false }
        let folder = folderURL(in: packageURL)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // Primero los dibujos e imágenes y después la base: si se guarda algo entre medias,
        // la base no puede citar un fichero que no se haya copiado (como mucho sobra uno).
        let support = supportURL(in: packageURL)
        if fileManager.fileExists(atPath: storage.supportURL.path) {
            try fileManager.copyItem(at: storage.supportURL, to: support)
        } else {
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        }

        let destination = databaseURL(in: packageURL)
        try AppleSQLiteBackupValidator.materializeSnapshot(from: storage.storeURL, to: destination)
        try AppleSQLiteBackupValidator.validateDatabase(at: destination)
        return true
    }

    /// Ficheros normales (no carpetas) bajo `libreta/`, ocultos incluidos, relativos a `root`.
    /// Son los que entran en `checksums.json`: una carpeta no tiene suma de control.
    static func regularFileRelativePaths(in root: URL, fileManager: FileManager = .default) throws -> [String] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var paths: [String] = []
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            paths.append(String(path.dropFirst(rootPath.count)))
        }
        return paths.sorted()
    }

    /// Número de libretas en una base de la Libreta (tabla `ZNOTEBOOK` de Core Data).
    static func notebookCount(in databaseURL: URL) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZNOTEBOOK;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Prepara la restauración sin tocar la Libreta activa.
    ///
    /// Devuelve las operaciones para la misma transacción que el resto de la copia, o `nil`
    /// si la copia no trae libretas: en ese caso las libretas actuales no se tocan.
    static func stageRestore(
        from packageURL: URL,
        checksumKeys: Set<String>,
        to storage: LibretaStorage,
        transactionID: String,
        fileManager: FileManager = .default
    ) throws -> (operations: [AppleBackupRestoreOperation], stagedURLs: [URL])? {
        let packagedDatabase = databaseURL(in: packageURL)
        guard checksumKeys.contains(databaseChecksumKey),
              fileManager.fileExists(atPath: packagedDatabase.path) else { return nil }

        try AppleSQLiteBackupValidator.validateDatabase(at: packagedDatabase)
        try fileManager.createDirectory(at: storage.directoryURL, withIntermediateDirectories: true)

        let stagedStore = storage.directoryURL
            .appendingPathComponent("restore-\(transactionID)-Libreta.store")
        let stagedSupport = storage.directoryURL
            .appendingPathComponent(".restore-\(transactionID)-Libreta_SUPPORT", isDirectory: true)
        let stagedURLs = [stagedStore, stagedSupport]

        do {
            try AppleSQLiteBackupValidator.materializeSnapshot(from: packagedDatabase, to: stagedStore)
            let packagedSupport = supportURL(in: packageURL)
            if fileManager.fileExists(atPath: packagedSupport.path) {
                try rejectSymbolicLinks(in: packagedSupport, fileManager: fileManager)
                try fileManager.copyItem(at: packagedSupport, to: stagedSupport)
            } else {
                try fileManager.createDirectory(at: stagedSupport, withIntermediateDirectories: true)
            }
        } catch {
            stagedURLs.forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }

        return (
            operations: [
                .replace(stagedURL: stagedStore, destinationURL: storage.storeURL),
                .remove(destinationURL: storage.walURL),
                .remove(destinationURL: storage.shmURL),
                .replace(stagedURL: stagedSupport, destinationURL: storage.supportURL),
            ],
            stagedURLs: stagedURLs
        )
    }

    private static func rejectSymbolicLinks(in folder: URL, fileManager: FileManager) throws {
        let items = [folder] + (fileManager.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
        for item in items where (try? fileManager.destinationOfSymbolicLink(atPath: item.path)) != nil {
            throw NSError(
                domain: "AppleBackupService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "La copia de la Libreta contiene un enlace simbólico no permitido: \(item.lastPathComponent)"]
            )
        }
    }
}
