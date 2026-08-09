import Foundation
import SQLite3

enum AppleSQLiteBackupValidator {
    static func validateDatabase(at url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        defer { sqlite3_close(database) }
        guard result == SQLITE_OK, let database else {
            throw validationError(
                code: 422,
                message: "SQLite no pudo abrir la base de datos para validar su integridad.",
                database: database
            )
        }

        try requireIntegrityCheck(database)
        try requireNoForeignKeyViolations(database)
    }

    /// Materializa una instantánea SQLite autocontenida. La API de backup aplica
    /// cualquier WAL del paquete de origen y evita instalar sidecars antiguos junto
    /// a la base activa.
    static func materializeSnapshot(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        let sourceResult = sqlite3_open_v2(
            sourceURL.path,
            &source,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        defer { sqlite3_close(source) }
        guard sourceResult == SQLITE_OK, let source else {
            throw validationError(
                code: 422,
                message: "SQLite no pudo abrir la base de datos de la copia.",
                database: source
            )
        }

        let destinationResult = sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        defer { sqlite3_close(destination) }
        guard destinationResult == SQLITE_OK, let destination else {
            throw validationError(
                code: 500,
                message: "SQLite no pudo crear la instantánea temporal de restauración.",
                database: destination
            )
        }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw validationError(
                code: 500,
                message: "SQLite no pudo iniciar la copia transaccional de restauración.",
                database: destination
            )
        }

        var attempts = 0
        var stepResult: Int32 = SQLITE_OK
        repeat {
            stepResult = sqlite3_backup_step(backup, 256)
            if stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
                attempts += 1
                sqlite3_sleep(25)
            }
        } while stepResult == SQLITE_OK || ((stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED) && attempts < 20)

        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw validationError(
                code: 500,
                message: "SQLite no pudo completar la instantánea temporal de restauración.",
                database: destination
            )
        }

        try validateDatabase(at: destinationURL)
    }

    private static func requireIntegrityCheck(_ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK else {
            throw validationError(
                code: 422,
                message: "No se pudo ejecutar PRAGMA integrity_check sobre la copia.",
                database: database
            )
        }
        defer { sqlite3_finalize(statement) }

        var rows: [String] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                rows.append(String(cString: value))
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw validationError(
                code: 422,
                message: "PRAGMA integrity_check no pudo completarse sobre la copia.",
                database: database
            )
        }
        guard rows == ["ok"] else {
            let detail = rows.prefix(3).joined(separator: "; ")
            throw validationError(
                code: 422,
                message: "PRAGMA integrity_check detectó una base dañada\(detail.isEmpty ? "." : ": \(detail)")",
                database: database
            )
        }
    }

    private static func requireNoForeignKeyViolations(_ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA foreign_key_check;", -1, &statement, nil) == SQLITE_OK else {
            throw validationError(
                code: 422,
                message: "No se pudo ejecutar PRAGMA foreign_key_check sobre la copia.",
                database: database
            )
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw validationError(
                code: 422,
                message: "PRAGMA foreign_key_check detectó referencias rotas en la copia.",
                database: database
            )
        }
    }

    private static func validationError(
        code: Int,
        message: String,
        database: OpaquePointer?
    ) -> NSError {
        let sqliteMessage: String?
        if let database {
            let candidate = String(cString: sqlite3_errmsg(database))
            sqliteMessage = candidate == "not an error" ? nil : candidate
        } else {
            sqliteMessage = nil
        }
        let description = sqliteMessage.map { "\(message) SQLite: \($0)" } ?? message
        return NSError(
            domain: "AppleBackupService",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

enum AppleBackupRestoreOperation {
    case replace(stagedURL: URL, destinationURL: URL)
    case remove(destinationURL: URL)

    var destinationURL: URL {
        switch self {
        case let .replace(_, destinationURL), let .remove(destinationURL):
            return destinationURL
        }
    }
}

/// Aplica el conjunto de base + evidencias + situaciones con rollback de
/// filesystem. Cada sustitución usa `replaceItemAt`, por lo que una ruta activa
/// nunca queda ausente durante su instalación.
final class AppleBackupRestoreTransaction {
    private enum AppliedOperation {
        case replaced(destinationURL: URL, rollbackURL: URL)
        case created(destinationURL: URL)
        case removed(destinationURL: URL, rollbackURL: URL)
    }

    private let fileManager: FileManager
    private let beforeApplying: ((URL) throws -> Void)?

    init(
        fileManager: FileManager = .default,
        beforeApplying: ((URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.beforeApplying = beforeApplying
    }

    func commit(_ operations: [AppleBackupRestoreOperation]) throws {
        var applied: [AppliedOperation] = []
        do {
            for operation in operations {
                try beforeApplying?(operation.destinationURL)
                switch operation {
                case let .replace(stagedURL, destinationURL):
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        let rollbackURL = uniqueRollbackURL(for: destinationURL)
                        _ = try fileManager.replaceItemAt(
                            destinationURL,
                            withItemAt: stagedURL,
                            backupItemName: rollbackURL.lastPathComponent,
                            options: [.withoutDeletingBackupItem]
                        )
                        guard fileManager.fileExists(atPath: rollbackURL.path) else {
                            throw transactionError("No se pudo conservar el elemento anterior para rollback: \(destinationURL.lastPathComponent).")
                        }
                        applied.append(.replaced(destinationURL: destinationURL, rollbackURL: rollbackURL))
                    } else {
                        try fileManager.moveItem(at: stagedURL, to: destinationURL)
                        applied.append(.created(destinationURL: destinationURL))
                    }

                case let .remove(destinationURL):
                    guard fileManager.fileExists(atPath: destinationURL.path) else { continue }
                    let rollbackURL = uniqueRollbackURL(for: destinationURL)
                    try fileManager.moveItem(at: destinationURL, to: rollbackURL)
                    applied.append(.removed(destinationURL: destinationURL, rollbackURL: rollbackURL))
                }
            }
        } catch {
            do {
                try rollback(applied.reversed())
            } catch let rollbackError {
                throw transactionError(
                    "La restauración falló y el rollback no pudo completarse: \(rollbackError.localizedDescription). Error inicial: \(error.localizedDescription)"
                )
            }
            throw error
        }

        cleanupRollbackItems(applied)
    }

    private func rollback(_ operations: ReversedCollection<[AppliedOperation]>) throws {
        for operation in operations {
            switch operation {
            case let .replaced(destinationURL, rollbackURL):
                if fileManager.fileExists(atPath: destinationURL.path) {
                    _ = try fileManager.replaceItemAt(destinationURL, withItemAt: rollbackURL)
                } else {
                    try fileManager.moveItem(at: rollbackURL, to: destinationURL)
                }
            case let .created(destinationURL):
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
            case let .removed(destinationURL, rollbackURL):
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: rollbackURL, to: destinationURL)
            }
        }
    }

    private func cleanupRollbackItems(_ operations: [AppliedOperation]) {
        for operation in operations {
            let rollbackURL: URL?
            switch operation {
            case let .replaced(_, url), let .removed(_, url): rollbackURL = url
            case .created: rollbackURL = nil
            }
            if let rollbackURL, fileManager.fileExists(atPath: rollbackURL.path) {
                try? fileManager.removeItem(at: rollbackURL)
            }
        }
    }

    private func uniqueRollbackURL(for destinationURL: URL) -> URL {
        destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".migestor-rollback-\(UUID().uuidString)-\(destinationURL.lastPathComponent)")
    }

    private func transactionError(_ message: String) -> NSError {
        NSError(
            domain: "AppleBackupService",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
