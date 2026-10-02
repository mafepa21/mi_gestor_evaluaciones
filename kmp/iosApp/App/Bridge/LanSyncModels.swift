import Foundation

struct LanSyncChange: Codable, Equatable {
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
