import Foundation
import SQLite3

/// Lo que `AppleDriver.kt` deja escrito cuando tiene que renombrar la base de datos
/// activa porque no se pudo abrir tras reintentarlo (ver `rescueUnreadableDatabase`).
struct AppleDatabaseRescueMarker: Equatable {
    let backupPath: String
    let timestampEpochSeconds: Int64
    var reason: String

    var displayMessage: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateText = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampEpochSeconds)))
        return """
        MiGestor no pudo abrir tu base de datos al iniciar (\(dateText)) y arrancó con una \
        base vacía para no bloquear la app. Tu base anterior no se ha borrado: se guardó en

        \(backupPath)

        Motivo: \(reason)
        """
    }
}

/// Detecta el marcador de rescate que deja `AppleDriver.kt` en disco y ofrece a la
/// docente reintentar abrir la base renombrada o restaurar una copia de seguridad,
/// en vez de dejarla arrancar en silencio con una base vacía (docs/QUALITY_NORTH_STAR.md, I3).
@MainActor
final class AppleDatabaseRescueService: ObservableObject {
    @Published private(set) var pendingRescue: AppleDatabaseRescueMarker?
    @Published var isAlertPresented = false
    @Published private(set) var isWorking = false

    static let shared = AppleDatabaseRescueService()

    private let fileManager: FileManager
    private let databaseURL: URL
    private let markerURL: URL

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let dbPath = AppleBridgeBootstrap.current().databasePath
        self.databaseURL = URL(fileURLWithPath: dbPath)
        self.markerURL = URL(fileURLWithPath: dbPath + ".rescue_marker")
        checkForPendingRescue()
    }

    func checkForPendingRescue() {
        guard let data = try? Data(contentsOf: markerURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let backupPath = object["backupPath"] as? String,
              let reason = object["reason"] as? String else {
            pendingRescue = nil
            isAlertPresented = false
            return
        }
        let timestamp = (object["timestampEpochSeconds"] as? NSNumber)?.int64Value ?? 0
        pendingRescue = AppleDatabaseRescueMarker(
            backupPath: backupPath,
            timestampEpochSeconds: timestamp,
            reason: reason
        )
        isAlertPresented = true
    }

    /// Intenta reabrir la base renombrada: si abre sin problemas, la vuelve a poner
    /// como base activa (sustituyendo la vacía) y exige reiniciar la app para usarla,
    /// igual que hace `AppleBackupService.restoreBackup`.
    func retryRescuedDatabase() {
        guard let marker = pendingRescue else { return }
        isWorking = true
        defer { isWorking = false }

        let backupURL = URL(fileURLWithPath: marker.backupPath)
        guard fileManager.fileExists(atPath: backupURL.path), canOpenAsSQLiteDatabase(at: backupURL) else {
            updateReasonAndRepresent(
                "La base rescatada (\(marker.backupPath)) sigue sin poder abrirse. Restaura una copia de seguridad desde Copias de seguridad."
            )
            return
        }

        do {
            // El reemplazo es atómico: `removeItem` + `copyItem` dejaba la ruta de la
            // base activa sin fichero durante la copia, con el driver de SQLDelight
            // abierto sobre ella. Esa es la misma situación que hacía abortar el proceso
            // en el borrado total (`vnode unlinked while in use` → `SQLITE_IOERR`), y si
            // la copia fallaba a mitad dejaba a la docente sin base ninguna.
            let stagingURL = databaseURL
                .deletingLastPathComponent()
                .appendingPathComponent("rescue-\(UUID().uuidString).sqlite", isDirectory: false)
            try fileManager.copyItem(at: backupURL, to: stagingURL)
            defer { try? fileManager.removeItem(at: stagingURL) }

            for suffix in ["-wal", "-shm"] {
                let active = URL(fileURLWithPath: databaseURL.path + suffix)
                if fileManager.fileExists(atPath: active.path) {
                    try fileManager.removeItem(at: active)
                }
            }

            if fileManager.fileExists(atPath: databaseURL.path) {
                _ = try fileManager.replaceItemAt(databaseURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: databaseURL)
            }

            for suffix in ["-wal", "-shm"] {
                let source = URL(fileURLWithPath: marker.backupPath + suffix)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.copyItem(at: source, to: URL(fileURLWithPath: databaseURL.path + suffix))
                }
            }
            clearMarker()
            AppleBackupService.shared.needsRestart = true
        } catch {
            updateReasonAndRepresent("No se pudo restaurar la base rescatada: \(error.localizedDescription)")
        }
    }

    /// La docente decide seguir con la base nueva (vacía) y descarta el aviso.
    func continueWithEmptyDatabase() {
        clearMarker()
    }

    private func updateReasonAndRepresent(_ reason: String) {
        pendingRescue?.reason = reason
        // Un botón de alerta siempre cierra la alerta nativa; forzamos el ciclo
        // false -> true para que SwiftUI la vuelva a mostrar con el mensaje actualizado.
        isAlertPresented = false
        DispatchQueue.main.async { [weak self] in
            self?.isAlertPresented = true
        }
    }

    private func clearMarker() {
        try? fileManager.removeItem(at: markerURL)
        pendingRescue = nil
        isAlertPresented = false
    }

    private func canOpenAsSQLiteDatabase(at url: URL) -> Bool {
        var db: OpaquePointer?
        // sqlite3_open_v2 puede dejar un handle asignado incluso cuando devuelve un
        // error (no solo cuando devuelve SQLITE_OK), así que el defer que lo cierra
        // se registra antes de comprobar el resultado, no después.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return false
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
