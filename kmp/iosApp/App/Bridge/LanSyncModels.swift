import Foundation

struct LanSyncChange: Codable, Hashable {
    let entity: String
    let id: String
    let updatedAtEpochMs: Int64
    let deviceId: String
    let payload: String
    var op: String = "upsert"
    var schemaVersion: Int = 1
}

struct NotebookSyncCache: Codable {
    var entityIdsByScope: [String: [String]] = [:]
    /// Mapeo de ID de entidad a ID de dispositivo que la creó/posee.
    /// Esto evita que borremos localmente (en el sync queue) cosas que vienen de otro dispositivo.
    var deviceIdByEntityId: [String: String] = [:]
}

struct LanPullResult {
    let serverEpochMs: Int64
    let changes: [LanSyncChange]
    var changeCount: Int { changes.count }
}

struct LanSyncEvent: Codable {
    let serverEpochMs: Int64
    let entities: [String]
    let changes: [LanSyncChange]?
}

struct LanPushResult {
    let applied: Int
    let ignored: Int
    let failed: Int
    let serverEpochMs: Int64?
    let desktopAuthoritative: Bool
}

/// Reparte los cambios en paquetes que el helper del Mac acepta.
/// El helper rechaza con 413 cualquier cuerpo de más de 2 MB (`SYNC_BODY_LIMIT_BYTES`).
enum LanSyncPushBatcher {
    /// Tamaño objetivo: deja margen de sobra y evita que un paquete agote los 25 s del envío.
    static let targetBatchBytes = 1_000_000
    static let maxChangesPerBatch = 500
    /// Lo máximo que cabe en un envío: el límite del helper menos el sobre de la petición.
    static let hardRecordLimitBytes = 2 * 1024 * 1024 - 4 * 1024

    struct Plan {
        var batches: [[LanSyncChange]]
        /// Registros que no caben en ningún envío: se quedan sin mandar.
        var oversized: [LanSyncChange]
    }

    static func plan(
        _ changes: [LanSyncChange],
        targetBatchBytes: Int = LanSyncPushBatcher.targetBatchBytes,
        maxChangesPerBatch: Int = LanSyncPushBatcher.maxChangesPerBatch,
        hardRecordLimitBytes: Int = LanSyncPushBatcher.hardRecordLimitBytes
    ) throws -> Plan {
        let encoder = JSONEncoder()
        var plan = Plan(batches: [], oversized: [])
        var current: [LanSyncChange] = []
        var currentBytes = 0

        for change in changes {
            // +1 por la coma que separa los elementos del array JSON.
            let size = try encoder.encode(change).count + 1
            if size > hardRecordLimitBytes {
                plan.oversized.append(change)
                continue
            }
            if !current.isEmpty,
               currentBytes + size > targetBatchBytes || current.count >= maxChangesPerBatch {
                plan.batches.append(current)
                current = []
                currentBytes = 0
            }
            current.append(change)
            currentBytes += size
        }
        if !current.isEmpty {
            plan.batches.append(current)
        }
        return plan
    }
}

/// Resultado acumulado de un envío por paquetes.
struct LanSyncBatchedPushResult {
    var applied = 0
    var ignored = 0
    var failed = 0
    var desktopAuthoritative = false
    var sentTotal = 0
    var oversized: [LanSyncChange] = []
}

enum LanSyncBatchedPush {
    /// Manda los cambios paquete a paquete y avisa de cada paquete ya entregado, para
    /// que un corte a mitad de camino no obligue a repetir lo que el Mac ya tiene.
    ///
    /// - Parameter retryFailedBatches: reenvía una vez los paquetes con fallos. Los
    ///   cambios van por fecha, así que un hijo puede llegar antes que su padre. El Mac
    ///   resuelve por última modificación, así que reenviar no duplica nada.
    @MainActor
    static func run(
        changes: [LanSyncChange],
        retryFailedBatches: Bool,
        send: ([LanSyncChange]) async throws -> LanPushResult,
        onDelivered: ([LanSyncChange]) -> Void
    ) async throws -> LanSyncBatchedPushResult {
        let plan = try LanSyncPushBatcher.plan(changes)
        var result = LanSyncBatchedPushResult(oversized: plan.oversized)
        result.sentTotal = plan.batches.reduce(0) { $0 + $1.count }
        var failedBatches: [(batch: [LanSyncChange], failed: Int)] = []

        for (index, batch) in plan.batches.enumerated() {
            try Task.checkCancellation()
            let ack = try await send(batch)
            result.applied += ack.applied
            result.ignored += ack.ignored
            if ack.desktopAuthoritative {
                // El Mac manda: los cambios locales se descartan a propósito.
                result.desktopAuthoritative = true
                plan.batches[index...].forEach(onDelivered)
                result.failed = 0
                return result
            }
            if SyncLanPushPendingPolicy.shouldClearSentPending(
                failed: ack.failed,
                desktopAuthoritative: false
            ) {
                onDelivered(batch)
            } else {
                failedBatches.append((batch, ack.failed))
            }
        }

        for entry in failedBatches {
            guard retryFailedBatches else {
                result.failed += entry.failed
                continue
            }
            try Task.checkCancellation()
            let ack = try await send(entry.batch)
            result.applied += ack.applied
            result.ignored += ack.ignored
            result.failed += ack.failed
            if SyncLanPushPendingPolicy.shouldClearSentPending(
                failed: ack.failed,
                desktopAuthoritative: ack.desktopAuthoritative
            ) {
                onDelivered(entry.batch)
            }
        }
        return result
    }
}

/// Textos de los problemas que deja un envío por paquetes.
enum LanSyncBatchedPushCopy {
    static func oversizedMessage(_ oversized: [LanSyncChange]) -> String {
        let entities = Array(Set(oversized.map(\.entity))).sorted().joined(separator: ", ")
        return "\(oversized.count) registro(s) son demasiado grandes para enviarse (tipo: \(entities)). Siguen guardados en este dispositivo."
    }

    static func mergeFailedMessage(failed: Int, total: Int) -> String {
        "El Mac no pudo guardar \(failed) de \(total) registros. La fusión se ha detenido y este dispositivo conserva sus datos. Vuelve a intentarlo."
    }

    static func mergeBackupFailedMessage(_ reason: String) -> String {
        "No se ha fusionado nada porque no se pudo crear la copia de seguridad: \(reason)"
    }
}

struct LanHandshakeResult {
    let token: String
    let serverId: String
    let certificateFingerprint: String
}

struct LanHandshakeRequest: Codable {
    let pin: String
    let deviceId: String
}

struct LanHandshakeResponse: Codable {
    let token: String
    let serverId: String?
    let certificateFingerprint: String?
    let serverEpochMs: Int64?
}

struct LanPullResponse: Codable {
    let serverEpochMs: Int64
    let changes: [LanSyncChange]
}

struct LanPushRequest: Codable {
    let clientDeviceId: String
    let lastKnownServerEpochMs: Int64
    let changes: [LanSyncChange]
}

struct LanPushResponse: Codable {
    let applied: Int
    let conflictsResolvedByLww: Int?
    let serverEpochMs: Int64?
    let ignored: Int?
    let failed: Int?
    let desktopAuthoritative: Bool?
}

public struct LanDatasetFingerprint: Codable, Equatable {
    public let schemaVersion: Int64
    public let countsByEntity: [String: Int]
    public let digest: String
    public let computedAtEpochMs: Int64

    public init(schemaVersion: Int64, countsByEntity: [String: Int], digest: String, computedAtEpochMs: Int64) {
        self.schemaVersion = schemaVersion
        self.countsByEntity = countsByEntity
        self.digest = digest
        self.computedAtEpochMs = computedAtEpochMs
    }
}

public struct SyncDivergenceReport: Equatable {
    public enum DivergenceKind: Equatable {
        case datasetDifference
        case schemaMismatch(localVersion: Int64, remoteVersion: Int64)
    }

    public let kind: DivergenceKind
    public let localFingerprint: LanDatasetFingerprint
    public let remoteFingerprint: LanDatasetFingerprint
    public let divergentEntities: [String]

    public var isSchemaMismatch: Bool {
        if case .schemaMismatch = kind { return true }
        return false
    }

    public init(kind: DivergenceKind, localFingerprint: LanDatasetFingerprint, remoteFingerprint: LanDatasetFingerprint, divergentEntities: [String]) {
        self.kind = kind
        self.localFingerprint = localFingerprint
        self.remoteFingerprint = remoteFingerprint
        self.divergentEntities = divergentEntities
    }
}

struct LanDiscoveredPeer: Equatable {
    let host: String
    let serverId: String
    let fingerprint: String
    let scheme: String

    var identityScore: Int {
        var score = 0
        if !serverId.isEmpty { score += 2 }
        if !fingerprint.isEmpty { score += 2 }
        if scheme == "https" { score += 1 }
        return score
    }
}
