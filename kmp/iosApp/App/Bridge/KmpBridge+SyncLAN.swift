import Foundation
import MiGestorKit
import Security
import CryptoKit

enum PlanningSessionSyncMerge {
    static func placement(previous: Int32, incoming: Int64?, keyPresent: Bool) -> Int32 {
        guard keyPresent, let incoming else { return previous }
        return Int32(incoming)
    }
}

enum SituationVersionSyncMerge {
    static func keptId(incoming: Int64, matched: Int64?) -> Int64 {
        if let matched, matched > 0 { return matched }
        return incoming
    }

    static func number(previous: Int32, incoming: Int32?, keyPresent: Bool) -> Int32 {
        if keyPresent, let incoming, incoming > 0 { return incoming }
        return previous
    }
}

enum LearningSituationSyncMerge {
    static func staysDraft(previousIsDraft: Bool, incoming: String?, keyPresent: Bool) -> Bool {
        guard keyPresent else { return previousIsDraft }
        return incoming == "DRAFT"
    }
}

enum TeachingUnitSyncMerge {
    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }
}

enum TeacherScheduleSyncMerge {
    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func dates(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func longId(previous: Int64, incoming: Int64?, keyPresent: Bool) -> Int64 {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }
}

enum PlannerEvaluationPeriodSyncMerge {
    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func dates(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func sortOrder(previous: Int32, incoming: Int64?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return Int32(incoming ?? Int64(previous))
    }
}

enum LearningSituationLinkSyncMerge {
    static func label(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func keptId(incoming: Int64, matched: Int64?) -> Int64 {
        if let matched, matched > 0 { return matched }
        return incoming
    }
}

enum WeeklySlotSyncMerge {
    struct ExistingSlot: Equatable {
        let id: Int64
        let dayOfWeek: Int
        let startTime: String
        let endTime: String
    }

    static func matchedId(
        incomingId: Int64,
        dayOfWeek: Int,
        startTime: String,
        endTime: String,
        existing: [ExistingSlot]
    ) -> Int64? {
        if incomingId > 0, let byId = existing.first(where: { $0.id == incomingId }) {
            return byId.id
        }
        return existing.first(where: {
            $0.dayOfWeek == dayOfWeek
                && $0.startTime == startTime
                && $0.endTime == endTime
        })?.id
    }

    static func keptId(incoming: Int64, matched: Int64?) -> Int64 {
        if let matched, matched > 0 { return matched }
        return incoming
    }
}

enum TeacherScheduleSlotSyncMerge {
    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming?.nilIfEmpty : previous
    }

    static func dayOfWeek(previous: Int32, incoming: Int64?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return Int32(incoming ?? Int64(previous))
    }

    static func longId(previous: Int64, incoming: Int64?, keyPresent: Bool) -> Int64 {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func optionalLongId(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        guard keyPresent else { return previous }
        return incoming.flatMap { $0 > 0 ? $0 : nil }
    }
}

enum InstrumentItemMerge {
    static func options(previous: [String], incoming: [String]?) -> [String] {
        incoming ?? previous
    }

    static func flag(previous: Bool, incoming: Bool?) -> Bool {
        incoming ?? previous
    }

    static func order(previous: Int, incoming: Int?) -> Int {
        incoming ?? previous
    }
}

enum InstrumentResponseMerge {
    static func replacing<T>(existing: [T]?, removeWhere: (T) -> Bool, incoming: T) -> [T]? {
        guard var kept = existing else { return nil }
        kept.removeAll(where: removeWhere)
        kept.append(incoming)
        return kept
    }

    static func removing<T>(existing: [T]?, removeWhere: (T) -> Bool) -> [T]? {
        guard var kept = existing else { return nil }
        kept.removeAll(where: removeWhere)
        return kept
    }
}

enum GradeSyncMerge {
    static func optionalDouble(previous: Double?, incoming: Double?, keyPresent: Bool) -> Double? {
        keyPresent ? incoming : previous
    }

    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }
}

enum AttendanceSyncMerge {
    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func flag(previous: Bool, incoming: Bool?, keyPresent: Bool) -> Bool {
        keyPresent ? (incoming ?? false) : previous
    }
}

enum IncidentSyncMerge {
    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func severity(previous: String?, incoming: String?, keyPresent: Bool) -> String {
        if keyPresent {
            return incoming ?? previous ?? "low"
        }
        return previous ?? "low"
    }
}

enum StudentSyncMerge {
    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func flag(previous: Bool, incoming: Bool?, keyPresent: Bool) -> Bool {
        keyPresent ? (incoming ?? false) : previous
    }

    static func value<T>(previous: T, incoming: T, keyPresent: Bool) -> T {
        keyPresent ? incoming : previous
    }

    static func optionalValue<T>(previous: T?, incoming: T?, keyPresent: Bool) -> T? {
        keyPresent ? incoming : previous
    }
}

enum NotebookCellSyncMerge {
    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func optionalBool(previous: Bool?, incoming: Bool?, keyPresent: Bool) -> Bool? {
        keyPresent ? incoming : previous
    }

    static func attachmentUris(previous: [String], incoming: [String]?, keyPresent: Bool) -> [String] {
        keyPresent ? (incoming ?? []) : previous
    }
}

enum CalendarEventSyncMerge {
    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func optionalClassId(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        guard keyPresent else { return previous }
        return incoming.flatMap { $0 > 0 ? $0 : nil }
    }
}

enum NotebookColumnSyncMerge {
    static func flag(previous: Bool, incoming: Bool?, keyPresent: Bool) -> Bool {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func optionalLong(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        keyPresent ? incoming : previous
    }

    static func weight(previous: Double, incoming: Double?, keyPresent: Bool) -> Double {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func order(previous: Int32, incoming: Int?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return incoming.map { Int32($0) } ?? previous
    }

    static func typeValue<T>(previous: T, incoming: T?, keyPresent: Bool) -> T {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }
}

enum NotebookTabSyncMerge {
    static func order(previous: Int32, incoming: Int?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return incoming.map { Int32($0) } ?? previous
    }

    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }
}

enum NotebookGroupSyncMerge {
    static func order(previous: Int32, incoming: Int?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return incoming.map { Int32($0) } ?? previous
    }

    static func optionalLong(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        keyPresent ? incoming : previous
    }
}

enum EvaluationSyncMerge {
    static func weight(previous: Double, incoming: Double?, keyPresent: Bool) -> Double {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func optionalLong(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        keyPresent ? incoming : previous
    }
}

enum RubricBundleSyncMerge {
    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func optionalLong(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        keyPresent ? incoming : previous
    }

    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func weight(previous: Double, incoming: Double?, keyPresent: Bool) -> Double {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func order(previous: Int32, incoming: Int?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return incoming.map { Int32($0) } ?? previous
    }

    /// Puntos del nivel: clave ausente conserva; presente con nil no inventa 0.
    static func points(previous: Int32, incoming: Int?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return incoming.map { Int32($0) } ?? previous
    }
}

/// Contrato del diario de sesión: clave ausente conserva texto/puntuación local.
/// El apply usa `SessionJournalSyncCodec.forLocalUpsert(..., existing:)` (decodeKeepingAbsent).
enum SessionJournalSyncMerge {
    static func text(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? "") : previous
    }

    static func score(previous: Int32, incoming: Int?, keyPresent: Bool) -> Int32 {
        guard keyPresent else { return previous }
        return incoming.map { Int32($0) } ?? previous
    }
}

enum AcademicYearSyncMerge {
    static func flag(previous: Bool, incoming: Bool?, keyPresent: Bool) -> Bool {
        keyPresent ? (incoming ?? false) : previous
    }

    static func status(previous: String, incoming: String?, keyPresent: Bool) -> String {
        keyPresent ? (incoming ?? previous) : previous
    }

    static func centerId(previous: Int64, incoming: Int64?, keyPresent: Bool) -> Int64 {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func epochMs(previous: Int64, incoming: Int64?, keyPresent: Bool) -> Int64 {
        guard keyPresent else { return previous }
        return incoming ?? previous
    }

    static func optionalEpochMs(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        keyPresent ? incoming : previous
    }
}

enum ClassSyncMerge {
    static func optionalText(previous: String?, incoming: String?, keyPresent: Bool) -> String? {
        keyPresent ? incoming : previous
    }

    static func optionalLong(previous: Int64?, incoming: Int64?, keyPresent: Bool) -> Int64? {
        keyPresent ? incoming : previous
    }
}

extension KmpBridge {
    func pairLanSync(
        host: String,
        pin: String,
        expectedServerId: String? = nil,
        expectedFingerprint: String? = nil
    ) async throws {
        guard !isPairingInFlight else {
            throw NSError(
                domain: "Sync",
                code: -207,
                userInfo: [NSLocalizedDescriptionKey: "Ya hay un emparejamiento LAN en curso."]
            )
        }

        let normalizedHost = LanSyncClient.normalizeHost(host)
        guard !normalizedHost.isEmpty else {
            throw NSError(
                domain: "Sync",
                code: -204,
                userInfo: [NSLocalizedDescriptionKey: "Introduce un host LAN válido para el desktop."]
            )
        }

        let previousToken = syncToken
        let previousHost = pairedSyncHost
        let previousServerId = pairedServerId
        let previousFingerprint = pairedServerFingerprint

        isPairingInFlight = true
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        defer {
            isPairingInFlight = false
        }

        let result: LanHandshakeResult
        do {
            result = try await runSyncOperationWithTimeout(seconds: 12) {
                try await self.lanSyncClient.handshake(
                    host: normalizedHost,
                    pin: pin,
                    deviceId: self.localDeviceId,
                    pinnedFingerprint: expectedFingerprint
                )
            }
        } catch {
            restartAutoSyncLoopIfPaired()
            throw error
        }
        if let expectedServerId, expectedServerId != result.serverId {
            restartAutoSyncLoopIfPaired()
            throw NSError(domain: "Sync", code: -203, userInfo: [NSLocalizedDescriptionKey: "Server ID no coincide con el esperado"])
        }

        syncToken = result.token
        pairedSyncHost = normalizedHost
        pairedServerId = result.serverId
        pairedServerFingerprint = result.certificateFingerprint

        do {
            try await runSyncOperationWithTimeout(seconds: 12) {
                try await self.performPullSync(
                    silent: true,
                    sinceEpochMsOverride: 0,
                    refreshAfterApply: false
                )
            }
            persistSyncSecrets()
            let now = Date()
            lastSuccessfulSyncAt = now
            lastFullPullAt = now
            publishSyncState {
                $0.syncStatusMessage = "Emparejado con \(normalizedHost)"
            }
            isPairingInFlight = false
            startAutoSyncLoop()
            startSyncEventListenerIfPaired()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncNow(reason: "pairing_refresh", forceFullPull: false, silent: true)
            }
        } catch {
            syncToken = previousToken
            pairedSyncHost = previousHost
            pairedServerId = previousServerId
            pairedServerFingerprint = previousFingerprint
            isPairingInFlight = false
            restartAutoSyncLoopIfPaired()
            throw NSError(
                domain: "Sync",
                code: -205,
                userInfo: [
                    NSLocalizedDescriptionKey: "El desktop respondió al emparejamiento, pero no al primer pull. Verifica que siga abierto y escuchando en la misma LAN. Detalle: \(error.localizedDescription)"
                ]
            )
        }
    }

    func unpairLanSync() async {
        if let host = pairedSyncHost, let token = syncToken {
            _ = try? await lanSyncClient.unpair(host: host, token: token, pinnedFingerprint: pairedServerFingerprint)
        }
        clearPersistedPairing()
        publishSyncState {
            $0.syncStatusMessage = "Desvinculado. Empareja de nuevo para reactivar la sync."
        }
    }

    func discoveredPeer(forHost host: String) -> LanDiscoveredPeer? {
        discoveredPeersByHost[host]
    }

    func runLanPullSync() async throws {
        try await performPullSync(silent: false)
    }

    func pullMissingSyncChanges() async {
        manualSyncTask?.cancel()
        let task = Task { @MainActor in
            publishSyncState {
                $0.syncStatusMessage = "Sincronizando…"
            }
            do {
                try await performPullSync(silent: false)
            } catch is CancellationError {
                publishSyncState {
                    $0.syncStatusMessage = SyncLanCancelAffordances.cancelledStatusMessage
                }
            } catch {
                publishSyncState {
                    $0.syncStatusMessage = "Pull manual fallido: \(error.localizedDescription)"
                }
            }
        }
        manualSyncTask = task
        await task.value
    }

    func pushPendingSyncChanges() async {
        manualSyncTask?.cancel()
        let task = Task { @MainActor in
            publishSyncState {
                $0.syncStatusMessage = "Sincronizando…"
            }
            do {
                try await performPushSync(silent: false)
            } catch is CancellationError {
                publishSyncState {
                    $0.syncStatusMessage = SyncLanCancelAffordances.cancelledStatusMessage
                }
            } catch {
                publishSyncState {
                    $0.syncStatusMessage = "Push manual fallido: \(error.localizedDescription)"
                }
            }
        }
        manualSyncTask = task
        await task.value
    }

    func cancelLanSync() {
        manualSyncTask?.cancel()
        publishSyncState {
            $0.syncStatusMessage = SyncLanCancelAffordances.cancelledStatusMessage
        }
    }

    func createLocalBackup(fileName: String = "mi_gestor_backup.sqlite") async throws -> BackupResult {
        try await container.backupService.createBackup(fileName: fileName)
    }

    func restoreLocalBackup(from path: String) async throws -> Bool {
        try await container.backupService.restoreBackup(backupPath: path).boolValue
    }

    func runLanPushSync() async throws {
        try await performPushSync(silent: false)
    }

    public enum SyncAdoptionSource: Equatable {
        case thisDevice
        case pairedMac
    }

    public enum SyncAdoptionOutcome {
        case needsRestart(backupHint: String?)
        case stagedOnMac
    }

    func fetchDatasetFingerprints() async throws -> (local: LanDatasetFingerprint, remote: LanDatasetFingerprint) {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -401, userInfo: [NSLocalizedDescriptionKey: "Dispositivo no emparejado."])
        }
        let remote = try await lanSyncClient.fingerprint(
            host: host,
            token: token,
            pinnedFingerprint: pairedServerFingerprint
        )
        let kmpLocal = try await container.computeDatasetFingerprint()
        let local = try JSONDecoder().decode(LanDatasetFingerprint.self, from: Data(kmpLocal.toJson().utf8))
        return (local, remote)
    }

    func checkSyncDivergence(force: Bool = false) async {
        guard pairedSyncHost != nil, syncToken != nil else { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastDivergenceCheckAt) < 60 {
            return
        }
        lastDivergenceCheckAt = now

        do {
            let (localFp, remoteFp) = try await fetchDatasetFingerprints()

            if localFp.schemaVersion != remoteFp.schemaVersion {
                let divergence = SyncDivergenceReport(
                    kind: .schemaMismatch(localVersion: localFp.schemaVersion, remoteVersion: remoteFp.schemaVersion),
                    localFingerprint: localFp,
                    remoteFingerprint: remoteFp,
                    divergentEntities: []
                )
                await MainActor.run {
                    self.syncDivergence = divergence
                }
                return
            }

            if localFp.digest != remoteFp.digest {
                var divergentEntities: [String] = []
                let allKeys = Set(localFp.countsByEntity.keys).union(remoteFp.countsByEntity.keys)
                for key in allKeys {
                    let localCount = localFp.countsByEntity[key] ?? 0
                    let remoteCount = remoteFp.countsByEntity[key] ?? 0
                    if localCount != remoteCount {
                        divergentEntities.append(key)
                    }
                }
                let divergence = SyncDivergenceReport(
                    kind: .datasetDifference,
                    localFingerprint: localFp,
                    remoteFingerprint: remoteFp,
                    divergentEntities: divergentEntities.sorted()
                )
                await MainActor.run {
                    self.syncDivergence = divergence
                }
            } else {
                await MainActor.run {
                    self.syncDivergence = nil
                }
            }
        } catch {
            print("[KmpBridge] Error al comprobar divergencia de sincronización: \(error)")
        }
    }

    func adoptDataset(from source: SyncAdoptionSource) async throws -> SyncAdoptionOutcome {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -401, userInfo: [NSLocalizedDescriptionKey: "Dispositivo no emparejado."])
        }

        guard let dbURL = getDatabaseURL() else {
            throw NSError(domain: "Sync", code: -500, userInfo: [NSLocalizedDescriptionKey: "No se pudo determinar el directorio de base de datos."])
        }
        let appSupportDir = dbURL.deletingLastPathComponent()

        switch source {
        case .pairedMac:
            let pendingDbURL = appSupportDir.appendingPathComponent("pending_adopt.db")
            let pendingJsonURL = appSupportDir.appendingPathComponent("pending_adopt.json")

            let (schemaVersion, digest) = try await lanSyncClient.downloadSnapshot(
                host: host,
                token: token,
                destinationURL: pendingDbURL,
                pinnedFingerprint: pairedServerFingerprint
            )

            let marker: [String: Any] = [
                "sourceDeviceId": pairedServerId ?? "mac",
                "schemaVersion": schemaVersion,
                "digest": digest,
                "stagedAtEpochMs": Int64(Date().timeIntervalSince1970 * 1000)
            ]
            let markerData = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted])
            try markerData.write(to: pendingJsonURL)

            await MainActor.run {
                self.clearLocalSyncTrackingState()
                self.syncDivergence = nil
            }

            return .needsRestart(backupHint: appSupportDir.appendingPathComponent("backups").path)

        case .thisDevice:
            let tempExportURL = FileManager.default.temporaryDirectory.appendingPathComponent("adopt_export_\(UUID().uuidString).db")
            defer {
                try? FileManager.default.removeItem(at: tempExportURL)
            }

            let exportSuccess = try container.exportConsistentDatabaseCopy(targetPath: tempExportURL.path)
            guard exportSuccess && FileManager.default.fileExists(atPath: tempExportURL.path) else {
                throw NSError(domain: "Sync", code: -500, userInfo: [NSLocalizedDescriptionKey: "No se pudo generar la copia consistente de la base de datos local."])
            }

            let kmpFp = try await container.computeDatasetFingerprint()
            try await lanSyncClient.uploadSnapshot(
                host: host,
                token: token,
                fileURL: tempExportURL,
                schemaVersion: kmpFp.schemaVersion,
                digest: kmpFp.digest,
                pinnedFingerprint: pairedServerFingerprint
            )

            await MainActor.run {
                self.clearLocalSyncTrackingState()
                self.syncDivergence = nil
            }

            return .stagedOnMac
        }
    }

    private func clearLocalSyncTrackingState() {
        UserDefaults.standard.removeObject(forKey: "sync.pending.changes.v2")
        UserDefaults.standard.removeObject(forKey: "sync.last.cursor")
        UserDefaults.standard.removeObject(forKey: "sync.notebook.cache.v1")
        pendingOutboundChanges.removeAll()
        syncPendingChanges = 0
    }

    private func performPullSync(silent: Bool, sinceEpochMsOverride: Int64? = nil) async throws {
        try await performPullSync(
            silent: silent,
            sinceEpochMsOverride: sinceEpochMsOverride,
            refreshAfterApply: true
        )
    }

    private func performPullSync(
        silent: Bool,
        sinceEpochMsOverride: Int64? = nil,
        refreshAfterApply: Bool
    ) async throws {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -40, userInfo: [NSLocalizedDescriptionKey: "No hay emparejamiento activo"])
        }

        let cursor = sinceEpochMsOverride ?? lastSyncCursorEpochMs
        if !silent {
            publishSyncState {
                $0.syncStatusMessage = "Sincronizando…"
            }
        }
        try Task.checkCancellation()
        let pull: LanPullResult
        do {
            pull = try await lanSyncClient.pull(
                host: host,
                token: token,
                sinceEpochMs: cursor,
                deviceId: localDeviceId,
                pinnedFingerprint: pairedServerFingerprint
            )
        } catch {
            guard recoverHostAfterNetworkChange(previousHost: host), let reboundHost = pairedSyncHost else {
                throw error
            }
            pull = try await lanSyncClient.pull(
                host: reboundHost,
                token: token,
                sinceEpochMs: cursor,
                deviceId: localDeviceId,
                pinnedFingerprint: pairedServerFingerprint
            )
        }

        try Task.checkCancellation()
        try await applyIncomingLanChanges(
            pull.changes,
            serverEpochMs: pull.serverEpochMs,
            refreshAfterApply: refreshAfterApply
        )
        if !silent {
            publishSyncState {
                $0.syncStatusMessage = "Pull OK (\(pull.changeCount) cambios)"
            }
        }
    }

    private func applySyncEvent(_ event: LanSyncEvent) async {
        guard let changes = event.changes, !changes.isEmpty else {
            await syncNow(reason: "sse_event", forceFullPull: false, silent: true)
            return
        }
        do {
            try await applyIncomingLanChanges(
                changes,
                serverEpochMs: event.serverEpochMs,
                refreshAfterApply: true
            )
            publishSyncState {
                $0.syncStatusMessage = "Evento LAN OK (\(changes.count) cambios)"
            }
        } catch {
            await syncNow(reason: "sse_event_fallback", forceFullPull: false, silent: true)
        }
    }

    private func applyIncomingLanChanges(
        _ changes: [LanSyncChange],
        serverEpochMs: Int64,
        refreshAfterApply: Bool
    ) async throws {
        guard !changes.isEmpty else {
            lastSyncCursorEpochMs = serverEpochMs
            UserDefaults.standard.set(lastSyncCursorEpochMs, forKey: "sync.last.cursor")
            publishSyncState {
                $0.syncLastRunAt = Date()
            }
            return
        }

        try await applyPulledChanges(changes)
        lastSyncCursorEpochMs = serverEpochMs
        UserDefaults.standard.set(lastSyncCursorEpochMs, forKey: "sync.last.cursor")
        let pendingChangesCount = pendingOutboundChanges.count
        publishSyncState {
            $0.syncPendingChanges = pendingChangesCount
            $0.syncLastRunAt = Date()
        }

        guard refreshAfterApply else { return }

        // Ejecutamos los refreshes en una Task de utilidad para no bloquear el
        // MainActor run loop durante las queries encadenadas. Esto evita que la UI
        // se congele cuando el servidor LAN tarda o no está disponible.
        let capturedChanges = changes
        let capturedLocalDeviceId = localDeviceId
        postSyncRefreshTask?.cancel()
        postSyncRefreshTask = Task(priority: .utility) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.refreshDashboard()
                guard !Task.isCancelled else { return }
                let entities = Set(capturedChanges.map(\.entity))
                let plan = LanSyncRefreshPlan.steps(entities: entities)
                if plan.classes {
                    try await self.refreshClasses()
                    guard !Task.isCancelled else { return }
                }
                if plan.students {
                    try await self.refreshStudentsDirectory()
                    guard !Task.isCancelled else { return }
                }
                if plan.rubrics {
                    try await self.refreshRubrics()
                    guard !Task.isCancelled else { return }
                    try await self.refreshRubricClassLinks()
                    guard !Task.isCancelled else { return }
                }
                if plan.planning {
                    try await self.refreshPlanning()
                    guard !Task.isCancelled else { return }
                }
                let hasNotebookChangesFromRemote = capturedChanges.contains {
                    plan.notebookEntities.contains($0.entity) && $0.deviceId != capturedLocalDeviceId
                }
                if hasNotebookChangesFromRemote {
                    self.refreshCurrentNotebook()
                }
            } catch {
                self.publishSyncState {
                    $0.syncStatusMessage = "Error al refrescar datos tras sincronizar: \(error.localizedDescription)"
                }
                print("No se pudieron refrescar los datos tras aplicar cambios LAN: \(error.localizedDescription)")
            }
        }
    }

    private func performPushSync(silent: Bool) async throws {
        guard let host = pairedSyncHost, let token = syncToken else {
            throw NSError(domain: "Sync", code: -41, userInfo: [NSLocalizedDescriptionKey: "No hay emparejamiento activo"])
        }
        guard !pendingOutboundChanges.isEmpty else {
            if !silent {
                publishSyncState {
                    $0.syncStatusMessage = "No hay cambios pendientes"
                }
            }
            return
        }

        if !silent {
            publishSyncState {
                $0.syncStatusMessage = "Sincronizando…"
            }
        }
        try Task.checkCancellation()

        // Snapshot lo que vamos a enviar. Los cambios que se encolen mientras la
        // petición de red está en curso (el `await`) no deben perderse cuando
        // limpiemos la cola al recibir la respuesta.
        let sentChanges = pendingOutboundChanges

        let ack: LanPushResult
        do {
            ack = try await lanSyncClient.push(
                host: host,
                token: token,
                deviceId: localDeviceId,
                changes: sentChanges,
                lastKnownServerEpochMs: lastSyncCursorEpochMs,
                pinnedFingerprint: pairedServerFingerprint
            )
        } catch {
            try Task.checkCancellation()
            guard recoverHostAfterNetworkChange(previousHost: host), let reboundHost = pairedSyncHost else {
                throw error
            }
            ack = try await lanSyncClient.push(
                host: reboundHost,
                token: token,
                deviceId: localDeviceId,
                changes: sentChanges,
                lastKnownServerEpochMs: lastSyncCursorEpochMs,
                pinnedFingerprint: pairedServerFingerprint
            )
        }
        try Task.checkCancellation()
        // Si hubo fallos, el lote enviado sigue pendiente para el siguiente sync.
        // Sin IDs por cambio en el ack, no podemos soltar solo los aplicados.
        // Si failed == 0 (aplicados o ignorados por LWW) o el Mac manda, sí
        // soltamos el snapshot enviado. Solo quitamos entradas iguales a lo
        // enviado: una edición más nueva durante el await no es Equatable y se
        // conserva.
        if SyncLanPushPendingPolicy.shouldClearSentPending(
            failed: ack.failed,
            desktopAuthoritative: ack.desktopAuthoritative
        ) {
            pendingOutboundChanges.removeAll { sentChanges.contains($0) }
            persistPendingChanges()
        }
        if ack.desktopAuthoritative {
            try await performPullSync(
                silent: true,
                sinceEpochMsOverride: 0
            )
        }
        let pendingChangesCount = pendingOutboundChanges.count
        publishSyncState {
            $0.syncPendingChanges = pendingChangesCount
            $0.syncLastRunAt = Date()
        }
        if !silent {
            let statusMessage = SyncLanPushCloseCopy.statusMessage(
                applied: ack.applied,
                failed: ack.failed,
                sentTotal: sentChanges.count,
                desktopAuthoritative: ack.desktopAuthoritative
            )
            publishSyncState {
                $0.syncStatusMessage = statusMessage
            }
        }
    }


    func publishSyncState(_ update: @escaping @MainActor (KmpBridge) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            update(self)
        }
    }

    func setSyncStatusMessage(_ message: String) {
        publishSyncState {
            $0.syncStatusMessage = message
        }
    }

    func persistPendingChanges() {
        pendingChangesPersistenceTask?.cancel()
        let snapshot = pendingOutboundChanges
        pendingChangesPersistenceTask = Task.detached(priority: .utility) {
            guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(encoded, forKey: "sync.pending.changes.v2")
        }
    }

    func invalidateNotebookCellValueIndexCache() {
        cachedNotebookStateIdentity = nil
        cachedNotebookCellValueIndex = nil
    }

    func scheduleEditedNotebookValueSync(classId: Int64, studentId: Int64, column: NotebookColumnDefinition, value: String) {
        if !NotebookSyncScope.sendsOnlyEditedCell(column.type) {
            scheduleGradeSnapshotSync(forClassId: classId)
            return
        }
        pendingGradeSnapshotTask?.cancel()
        pendingGradeSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self.enqueueEditedNotebookValue(classId: classId, studentId: studentId, column: column, value: value)
            self.persistPendingChanges()
            self.triggerAutoSyncSoon(delayNanoseconds: 900_000_000)
        }
    }

    private func enqueueEditedNotebookValue(classId: Int64, studentId: Int64, column: NotebookColumnDefinition, value: String) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let id = "\(classId)-\(studentId)-\(column.id)"
        if column.type == .numeric {
            enqueueLocalChange(
                entity: "grade",
                id: id,
                updatedAtEpochMs: nowMs,
                payload: [
                    "classId": classId,
                    "studentId": studentId,
                    "columnId": column.id,
                    "evaluationId": column.evaluationId?.int64Value ?? 0,
                    "value": Double(value.replacingOccurrences(of: ",", with: ".")) ?? NSNull()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
            return
        }
        var payload: [String: Any] = [
            "classId": classId,
            "studentId": studentId,
            "columnId": column.id
        ]
        switch column.type {
        case .text, .attendance:
            payload["textValue"] = value
        case .check:
            payload["boolValue"] = value == "true"
        case .icon:
            payload["iconValue"] = value
        case .ordinal:
            payload["ordinalValue"] = value
        default:
            break
        }
        enqueueLocalChange(
            entity: "notebook_cell",
            id: id,
            updatedAtEpochMs: nowMs,
            payload: payload,
            shouldPersist: false,
            shouldScheduleAutoSync: false
        )
    }

    func scheduleGradeSnapshotSync(forClassId classId: Int64) {
        pendingGradeSnapshotTask?.cancel()
        pendingGradeSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            try? await self.enqueueNotebookSnapshot(forClassId: classId)
        }
    }

    func scheduleNotebookSnapshotSync(forClassId classId: Int64) {
        notebookSnapshotDebounceTask?.cancel()
        notebookSnapshotDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            try? await self.enqueueNotebookSnapshot(forClassId: classId)
        }
    }

    private func enqueueNotebookSnapshot(forClassId classId: Int64) async throws {
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        let columnCategories = try await container.notebookConfigRepository.listColumnCategories(classId: classId, tabId: nil)
        let workGroups = try await container.notebookConfigRepository.listWorkGroups(classId: classId, tabId: nil)
        let workGroupMembers = try await container.notebookConfigRepository.listWorkGroupMembers(classId: classId, tabId: nil)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        let cells = try await container.notebookCellsRepository.listClassCells(classId: classId)
        let rubricEvaluations = evaluations.filter { $0.rubricId?.int64Value ?? 0 > 0 }

        students.forEach { student in
            notebookSyncCache.deviceIdByEntityId["\(student.id)"] = student.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "student",
                id: "\(student.id)",
                updatedAtEpochMs: student.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": student.id,
                    "firstName": student.firstName,
                    "lastName": student.lastName,
                    "email": student.email ?? NSNull(),
                    "photoPath": student.photoPath ?? NSNull(),
                    "isInjured": student.isInjured,
                    "sex": student.sex.name,
                    "sexSource": student.sexSource.name,
                    "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        enqueueLocalChange(
            entity: "class_roster",
            id: "\(classId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "classId": classId,
                "studentIds": students.map(\.id).sorted()
            ],
            shouldPersist: false,
            shouldScheduleAutoSync: false
        )

        evaluations.forEach { evaluation in
            notebookSyncCache.deviceIdByEntityId["\(evaluation.id)"] = evaluation.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "evaluation",
                id: "\(evaluation.id)",
                updatedAtEpochMs: evaluation.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": evaluation.id,
                    "classId": evaluation.classId,
                    "code": evaluation.code,
                    "name": evaluation.name,
                    "type": evaluation.type,
                    "weight": evaluation.weight,
                    "formula": evaluation.formula ?? "",
                    "rubricId": evaluation.rubricId?.int64Value ?? 0,
                    // `description` a secas es el `description` de NSObject (el toString del
                    // objeto Kotlin, "Evaluation(id=…, code=…)"); el campo real del dominio se
                    // expone en Swift como `description_`. Enviar el primero sincronizaba ese
                    // volcado como si fuera la descripción del criterio de evaluación.
                    "description": evaluation.description_ ?? ""
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        tabs.forEach { tab in
            notebookSyncCache.deviceIdByEntityId[tab.id] = tab.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_tab",
                id: tab.id,
                updatedAtEpochMs: tab.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": tab.id,
                    "classId": classId,
                    "title": tab.title,
                    "description": tab.description,
                    "order": Int(tab.order),
                    "parentTabId": tab.parentTabId ?? ""
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        workGroups.forEach { group in
            let groupId = "\(group.id)"
            notebookSyncCache.deviceIdByEntityId[groupId] = group.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_group",
                id: groupId,
                updatedAtEpochMs: group.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": group.id,
                    "classId": classId,
                    "tabId": group.tabId,
                    "name": group.name,
                    "order": Int(group.order)
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        workGroupMembers.forEach { member in
            let memberId = "\(member.classId)|\(member.tabId)|\(member.groupId)|\(member.studentId)"
            notebookSyncCache.deviceIdByEntityId[memberId] = member.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_group_member",
                id: memberId,
                updatedAtEpochMs: member.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "classId": member.classId,
                    "tabId": member.tabId,
                    "groupId": member.groupId,
                    "studentId": member.studentId
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        columnCategories.forEach { category in
            notebookSyncCache.deviceIdByEntityId[category.id] = category.trace.deviceId ?? localDeviceId
            enqueueLocalChange(
                entity: "notebook_column_category",
                id: category.id,
                updatedAtEpochMs: category.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": category.id,
                    "classId": category.classId,
                    "tabId": category.tabId,
                    "name": category.name,
                    "order": Int(category.order),
                    "isCollapsed": category.isCollapsed
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        columns.forEach { column in
            notebookSyncCache.deviceIdByEntityId[column.id] = column.trace.deviceId ?? localDeviceId
            let tabTitlesById = Dictionary(
                tabs.map { ($0.id, $0.title) },
                uniquingKeysWith: { first, _ in first }
            )
            let tabTitlesCsv = column.tabIds.compactMap { tabTitlesById[$0] }.joined(separator: ",")
            enqueueLocalChange(
                entity: "notebook_column",
                id: column.id,
                updatedAtEpochMs: column.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": column.id,
                    "classId": classId,
                    "title": column.title,
                    "type": column.type.name,
                    "column_type": column.type.name,
                    "evaluationId": column.evaluationId?.int64Value ?? 0,
                    "rubricId": column.rubricId?.int64Value ?? 0,
                    "formula": column.formula ?? "",
                    "weight": column.weight,
                    "tabIdsCsv": column.tabIds.joined(separator: ","),
                    "tab_ids_csv": column.tabIds.joined(separator: ","),
                    "tabTitlesCsv": tabTitlesCsv,
                    "tab_titles_csv": tabTitlesCsv,
                    "categoryId": column.categoryId ?? "",
                    "category_id": column.categoryId ?? "",
                    "sharedAcrossTabs": column.sharedAcrossTabs,
                    "shared_across_tabs": column.sharedAcrossTabs,
                    "colorHex": column.colorHex ?? "",
                    "categoryKind": column.categoryKind.name,
                    "instrumentKind": column.instrumentKind.name,
                    "inputKind": column.inputKind.name,
                    "scaleKind": column.scaleKind.name,
                    "dateEpochMs": column.dateEpochMs?.int64Value ?? 0,
                    "unitOrSituation": column.unitOrSituation ?? "",
                    "competencyCriteriaIds": column.competencyCriteriaIds.map { "\($0)" }.joined(separator: ","),
                    "iconName": column.iconName ?? "",
                    "order": Int(column.order),
                    "widthDp": column.widthDp,
                    "countsTowardAverage": column.countsTowardAverage,
                    "isPinned": column.isPinned,
                    "isHidden": column.isHidden,
                    "visibility": column.visibility.name,
                    "isLocked": column.isLocked,
                    "isTemplate": column.isTemplate
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        grades.forEach { grade in
            enqueueLocalChange(
                entity: "grade",
                id: "\(grade.classId)-\(grade.studentId)-\(grade.columnId)",
                updatedAtEpochMs: grade.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "classId": grade.classId,
                    "studentId": grade.studentId,
                    "columnId": grade.columnId,
                    "evaluationId": grade.evaluationId?.int64Value ?? 0,
                    "value": grade.value ?? NSNull(),
                    "evidence": grade.evidence ?? NSNull(),
                    "evidencePath": grade.evidencePath ?? NSNull(),
                    "rubricSelections": grade.rubricSelections ?? NSNull()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        cells.forEach { cell in
            enqueueLocalChange(
                entity: "notebook_cell",
                id: "\(cell.classId)-\(cell.studentId)-\(cell.columnId)",
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000), // cells no tienen trace todavía
                payload: [
                    "classId": cell.classId,
                    "studentId": cell.studentId,
                    "columnId": cell.columnId,
                    "textValue": cell.textValue ?? NSNull(),
                    "boolValue": cell.boolValue?.boolValue ?? NSNull(),
                    "iconValue": cell.iconValue ?? NSNull(),
                    "ordinalValue": cell.ordinalValue ?? NSNull(),
                    "note": cell.annotation?.note ?? NSNull(),
                    "colorHex": cell.annotation?.colorHex ?? NSNull(),
                    "attachmentUris": cell.annotation?.attachmentUris ?? []
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
        }

        // Instrumentos estructurados (plantilla, sus ítems y las respuestas por alumno). Sin esto
        // el dispositivo donde se importa la situación de aprendizaje se queda la rejilla para sí:
        // el resto solo recibe la columna, abre la celda y ve "Sin plantilla". `KmpBridge` y
        // `SqlDelightSyncAdapter` ya sabían aplicar estas tres entidades al recibirlas, pero nadie
        // las emitía.
        for column in columns where column.inputKind.isStructuredInstrument {
            guard let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id) else {
                continue
            }
            let template = detail.template_
            enqueueLocalChange(
                entity: "notebook_instrument_template",
                id: template.id,
                updatedAtEpochMs: template.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": template.id,
                    "classId": template.classId,
                    "columnId": template.columnId,
                    "evaluationId": template.evaluationId?.int64Value ?? 0,
                    "title": template.title,
                    "kind": template.kind.name,
                    "inputKind": template.inputKind.name,
                    "source": template.source ?? "",
                    "createdAtEpochMs": template.trace.createdAt.toEpochMilliseconds()
                ],
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
            detail.items.forEach { item in
                enqueueLocalChange(
                    entity: "notebook_instrument_item",
                    id: item.id,
                    updatedAtEpochMs: item.trace.updatedAt.toEpochMilliseconds(),
                    payload: [
                        "id": item.id,
                        "templateId": item.templateId,
                        "itemKey": item.key,
                        "title": item.title,
                        "itemType": item.type.name,
                        "optionsCsv": item.options.joined(separator: "|"),
                        "required": item.required,
                        "sortOrder": Int(item.order),
                        "helpText": item.helpText ?? ""
                    ],
                    shouldPersist: false,
                    shouldScheduleAutoSync: false
                )
            }
            for student in students {
                let studentResponses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(
                    classId: classId,
                    studentId: student.id,
                    columnId: column.id
                )) ?? []
                studentResponses.forEach { response in
                    enqueueLocalChange(
                        entity: "notebook_instrument_response",
                        id: "\(response.classId)-\(response.studentId)-\(response.columnId)-\(response.itemId)",
                        updatedAtEpochMs: response.trace.updatedAt.toEpochMilliseconds(),
                        payload: [
                            "classId": response.classId,
                            "studentId": response.studentId,
                            "columnId": response.columnId,
                            "itemId": response.itemId,
                            "valueText": response.textValue ?? "",
                            "valueBool": response.boolValue?.boolValue ?? false,
                            "valueNumber": response.numberValue.map { plainStructuredNumberString($0.doubleValue) } ?? ""
                        ],
                        shouldPersist: false,
                        shouldScheduleAutoSync: false
                    )
                }
            }
        }

        for evaluation in rubricEvaluations {
            for student in students {
                let assessments = try await container.rubricsRepository.listRubricAssessments(
                    studentId: student.id,
                    evaluationId: evaluation.id
                )
                assessments.forEach { assessment in
                    enqueueLocalChange(
                        entity: "rubric_assessment",
                        id: "\(assessment.studentId)-\(assessment.evaluationId)-\(assessment.criterionId)",
                        updatedAtEpochMs: assessment.trace.updatedAt.toEpochMilliseconds(),
                        payload: [
                            "studentId": assessment.studentId,
                            "evaluationId": assessment.evaluationId,
                            "criterionId": assessment.criterionId,
                            "levelId": assessment.levelId
                        ],
                        shouldPersist: false,
                        shouldScheduleAutoSync: false
                    )
                }
            }
        }

        enqueueNotebookDeletes(
            entity: "evaluation",
            classId: classId,
            currentIds: Set(evaluations.map { "\($0.id)" }),
            payloadForId: { id in ["id": Int64(id) ?? 0] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_tab",
            classId: classId,
            currentIds: Set(tabs.map(\.id)),
            payloadForId: { id in ["id": id] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_group",
            classId: classId,
            currentIds: Set(workGroups.map { "group-\($0.id)" }),
            payloadForId: { id in ["id": Int64(id.replacingOccurrences(of: "group-", with: "")) ?? 0] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_group_member",
            classId: classId,
            currentIds: Set(workGroupMembers.map { "group-member-\($0.classId)-\($0.tabId)-\($0.groupId)-\($0.studentId)" }),
            payloadForId: { id in
                let parts = id.replacingOccurrences(of: "group-member-", with: "").split(separator: "-").map(String.init)
                return [
                    "classId": Int64(parts[safe: 0] ?? "") ?? 0,
                    "tabId": parts[safe: 1] ?? "",
                    "groupId": Int64(parts[safe: 2] ?? "") ?? 0,
                    "studentId": Int64(parts[safe: 3] ?? "") ?? 0
                ]
            }
        )
        enqueueNotebookDeletes(
            entity: "notebook_column",
            classId: classId,
            currentIds: Set(columns.map(\.id)),
            payloadForId: { id in ["id": id] }
        )
        enqueueNotebookDeletes(
            entity: "notebook_column_category",
            classId: classId,
            currentIds: Set(columnCategories.map(\.id)),
            payloadForId: { id in ["id": id, "classId": classId] }
        )
        
        // Persistencia final de todos los cambios del snapshot
        persistPendingChanges()
        triggerAutoSyncSoon(delayNanoseconds: 900_000_000)
    }

    private func enqueueNotebookDeletes(
        entity: String,
        classId: Int64,
        currentIds: Set<String>,
        payloadForId: (String) -> [String: Any]
    ) {
        let scopeKey = notebookSyncScopeKey(classId: classId, entity: entity)
        let previousIds = Set(notebookSyncCache.entityIdsByScope[scopeKey] ?? [])
        
        // SEGURIDAD: Si currentIds está vacío pero antes teníamos datos para esta clase,
        // es probable que sea un error de carga de snapshot. Evitamos borrar todo.
        if currentIds.isEmpty && !previousIds.isEmpty {
            return
        }

        let deletedIds = previousIds.subtracting(currentIds)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        deletedIds.forEach { deletedId in
            // SEGURIDAD: Solo encolamos el borrado si nosotros éramos los dueños de este ID
            // O si no tenemos registro de quién lo creó (fallback conservador).
            // Esto evita que iOS mande a borrar columnas de Desktop solo porque no las ve en "algunos" snapshots.
            let ownerId = notebookSyncCache.deviceIdByEntityId[deletedId]
            if let ownerId = ownerId, ownerId != localDeviceId {
                // El dueño es otro dispositivo, no lo borramos nosotros del sync queue local.
                return
            }

            // SEGURIDAD ADICIONAL: Si el deletedId empieza por COL_ pero tenemos un eval_ equivalente en currentIds,
            // no lo mandamos a borrar como 'delete' porque es una migración local controlada por el repositorio KMP.
            if deletedId.hasPrefix("COL_") {
                // Posible ID antiguo, lo dejamos que el repositorio KMP lo gestione
                return
            }

            enqueueLocalChange(
                entity: entity,
                id: deletedId,
                updatedAtEpochMs: nowMs,
                payload: payloadForId(deletedId),
                op: "delete",
                shouldPersist: false,
                shouldScheduleAutoSync: false
            )
            
            // Limpiar el dueño ya que se ha borrado
            notebookSyncCache.deviceIdByEntityId.removeValue(forKey: deletedId)
        }

        notebookSyncCache.entityIdsByScope[scopeKey] = Array(currentIds).sorted()
        persistNotebookSyncCache()
    }

    private func notebookSyncScopeKey(classId: Int64, entity: String) -> String {
        "\(classId)|\(entity)"
    }

    private func persistNotebookSyncCache() {
        if let encoded = try? JSONEncoder().encode(notebookSyncCache) {
            UserDefaults.standard.set(encoded, forKey: "sync.notebook.cache.v1")
        }
    }

    private func applyPulledChanges(_ changes: [LanSyncChange]) async throws {
        let orderedChanges = orderedPulledChanges(changes)
        let applyTotal = orderedChanges.count
        var failedCount = 0
        // Parseo JSON fuera de MainActor; las suspend de KMP siguen en MainActor.
        let payloadStrings = orderedChanges.map(\.payload)
        let parsedPayloads = await Task.detached(priority: .utility) {
            payloadStrings.map { LanSyncPayloadParser.dictionary(from: $0) }
        }.value
        for (index, change) in orderedChanges.enumerated() {
            let hechos = index + 1
            if SyncLanApplyProgressCopy.shouldPublishProgress(hechos: hechos, total: applyTotal) {
                publishSyncState {
                    $0.syncStatusMessage = SyncLanApplyProgressCopy.statusMessage(
                        hechos: hechos,
                        total: applyTotal
                    )
                }
            }
            if index.isMultiple(of: 25) {
                await Task.yield()
            }
            // El servidor ya filtra los cambios propios del dispositivo que pide el
            // pull (ver /sync/pull en LocalSyncServer.kt), pero mantenemos esta
            // comprobación como red de seguridad por si el peer aún no tiene ese
            // filtro (versión anterior del Mac) — reaplicar nuestro propio cambio
            // es, en el mejor caso, trabajo desperdiciado y, en el peor, un pull
            // completo periódico reprocesando toda la base de datos local.
            if change.deviceId == localDeviceId {
                continue
            }
            do {
            let payloadObject = parsedPayloads[index]

            if change.op == "delete" {
                try await applyDeletedChange(change: change, payloadObject: payloadObject)
                // Deja un tombstone: si el otro dispositivo empuja más tarde un upsert
                // fechado ANTES de este borrado, no debe resucitar la entidad (ver el
                // chequeo simétrico justo antes del switch de abajo).
                try? await container.syncTombstoneRepository.recordTombstone(
                    entity: change.entity,
                    entityId: change.id,
                    deletedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId
                )
                continue
            }

            // Un upsert fechado antes (o igual) que el último borrado conocido de esta
            // misma entidad no debe resucitarla: el borrado es más reciente y gana LWW.
            let isBlockedByTombstone = (try? await container.syncTombstoneRepository.isDeletedAtOrAfter(
                entity: change.entity,
                entityId: change.id,
                updatedAtEpochMs: change.updatedAtEpochMs
            ))?.boolValue ?? false
            if isBlockedByTombstone {
                continue
            }

            switch change.entity {
            case "academic_year":
                guard
                    let yearId = int64Value(payloadObject["id"]),
                    let name = payloadObject["name"] as? String
                else { continue }
                let existing: AcademicYear?
                do {
                    existing = try await container.academicYearsRepository.listAcademicYears()
                        .first { $0.id == yearId }
                } catch {
                    continue
                }
                let startKeyPresent = payloadObject.keys.contains("startEpochMs")
                let endKeyPresent = payloadObject.keys.contains("endEpochMs")
                let centerKeyPresent = payloadObject.keys.contains("centerId")
                let statusKeyPresent = payloadObject.keys.contains("status")
                let isActiveKeyPresent = payloadObject.keys.contains("isActive")
                let archivedKeyPresent = payloadObject.keys.contains("archivedAtEpochMs")
                let needsPrevious =
                    !startKeyPresent || !endKeyPresent || !centerKeyPresent
                    || !statusKeyPresent || !isActiveKeyPresent || !archivedKeyPresent
                // Sin lectura local no se inventan isActive/status/centro/fechas.
                if needsPrevious, existing == nil {
                    continue
                }
                let startEpochMs = AcademicYearSyncMerge.epochMs(
                    previous: existing?.startAt.toEpochMilliseconds() ?? 0,
                    incoming: int64Value(payloadObject["startEpochMs"]),
                    keyPresent: startKeyPresent
                )
                let endEpochMs = AcademicYearSyncMerge.epochMs(
                    previous: existing?.endAt.toEpochMilliseconds() ?? 0,
                    incoming: int64Value(payloadObject["endEpochMs"]),
                    keyPresent: endKeyPresent
                )
                guard startEpochMs > 0, endEpochMs > 0 else { continue }
                let centerId = AcademicYearSyncMerge.centerId(
                    previous: existing?.centerId ?? 1,
                    incoming: int64Value(payloadObject["centerId"]),
                    keyPresent: centerKeyPresent
                )
                let status = AcademicYearSyncMerge.status(
                    previous: existing?.status.name ?? "ACTIVE",
                    incoming: payloadObject["status"] as? String,
                    keyPresent: statusKeyPresent
                )
                let isActive = AcademicYearSyncMerge.flag(
                    previous: existing?.isActive ?? false,
                    incoming: payloadObject["isActive"] as? Bool,
                    keyPresent: isActiveKeyPresent
                )
                let archivedAtEpochMs = AcademicYearSyncMerge.optionalEpochMs(
                    previous: existing?.archivedAt?.toEpochMilliseconds(),
                    incoming: positiveInt64Value(payloadObject["archivedAtEpochMs"]),
                    keyPresent: archivedKeyPresent
                )
                _ = try await container.academicYearsRepository.upsertAcademicYear(
                    id: yearId,
                    centerId: centerId,
                    name: name,
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs,
                    status: status,
                    isActive: isActive,
                    archivedAtEpochMs: kotlinLong(archivedAtEpochMs),
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "class":
                guard
                    let name = payloadObject["name"] as? String,
                    let course = payloadObject["course"] as? Int
                else { continue }
                let classId = int64Value(payloadObject["id"]) ?? 0
                let existing: SchoolClass?
                if classId > 0 {
                    do {
                        existing = try await container.classesRepository.listClasses()
                            .first { $0.id == classId }
                    } catch {
                        continue
                    }
                } else {
                    existing = nil
                }
                let descriptionKeyPresent = payloadObject.keys.contains("description")
                let centerKeyPresent = payloadObject.keys.contains("centerId")
                let academicYearKeyPresent = payloadObject.keys.contains("academicYearId")
                let stageCycleKeyPresent = payloadObject.keys.contains("stageCycleId")
                let subjectKeyPresent = payloadObject.keys.contains("subjectId")
                let needsPrevious =
                    !descriptionKeyPresent || !centerKeyPresent || !academicYearKeyPresent
                    || !stageCycleKeyPresent || !subjectKeyPresent
                // Sin lectura local no se inventan description/centro/año/ciclo/materia.
                if needsPrevious, existing == nil {
                    continue
                }
                let description = ClassSyncMerge.optionalText(
                    previous: existing?.description_,
                    incoming: payloadObject["description"] as? String,
                    keyPresent: descriptionKeyPresent
                )
                let centerId = ClassSyncMerge.optionalLong(
                    previous: existing?.centerId?.int64Value,
                    incoming: positiveInt64Value(payloadObject["centerId"]),
                    keyPresent: centerKeyPresent
                )
                let academicYearId = ClassSyncMerge.optionalLong(
                    previous: existing?.academicYearId?.int64Value,
                    incoming: positiveInt64Value(payloadObject["academicYearId"]),
                    keyPresent: academicYearKeyPresent
                )
                let stageCycleId = ClassSyncMerge.optionalLong(
                    previous: existing?.stageCycleId?.int64Value,
                    incoming: positiveInt64Value(payloadObject["stageCycleId"]),
                    keyPresent: stageCycleKeyPresent
                )
                let subjectId = ClassSyncMerge.optionalLong(
                    previous: existing?.subjectId?.int64Value,
                    incoming: positiveInt64Value(payloadObject["subjectId"]),
                    keyPresent: subjectKeyPresent
                )
                _ = try await container.classesRepository.saveClass(
                    id: kotlinLong(classId > 0 ? classId : nil),
                    name: name,
                    course: Int32(course),
                    description: description,
                    centerId: kotlinLong(centerId),
                    academicYearId: kotlinLong(academicYearId),
                    stageCycleId: kotlinLong(stageCycleId),
                    subjectId: kotlinLong(subjectId),
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "student":
                guard
                    let firstName = payloadObject["firstName"] as? String,
                    let lastName = payloadObject["lastName"] as? String
                else { continue }
                let studentId = int64Value(payloadObject["id"]) ?? 0
                let existing: Student?
                do {
                    if studentId > 0 {
                        existing = try await container.studentsRepository.getStudent(studentId: studentId)
                    } else {
                        existing = nil
                    }
                } catch {
                    continue
                }
                let email = StudentSyncMerge.optionalText(
                    previous: existing?.email,
                    incoming: payloadObject["email"] as? String,
                    keyPresent: payloadObject.keys.contains("email")
                )
                let photoPath = StudentSyncMerge.optionalText(
                    previous: existing?.photoPath,
                    incoming: payloadObject["photoPath"] as? String,
                    keyPresent: payloadObject.keys.contains("photoPath")
                )
                let isInjured = StudentSyncMerge.flag(
                    previous: existing?.isInjured ?? false,
                    incoming: payloadObject["isInjured"] as? Bool,
                    keyPresent: payloadObject.keys.contains("isInjured")
                )
                let sex = StudentSyncMerge.value(
                    previous: existing?.sex ?? .unspecified,
                    incoming: studentSex(from: payloadObject["sex"]),
                    keyPresent: payloadObject.keys.contains("sex")
                )
                let sexSource = StudentSyncMerge.value(
                    previous: existing?.sexSource ?? .unknown,
                    incoming: studentSexSource(from: payloadObject["sexSource"]),
                    keyPresent: payloadObject.keys.contains("sexSource")
                )
                let birthDate = StudentSyncMerge.optionalValue(
                    previous: existing?.birthDate,
                    incoming: localDate(from: payloadObject["birthDate"]),
                    keyPresent: payloadObject.keys.contains("birthDate")
                )
                _ = try await container.studentsRepository.saveStudent(
                    id: kotlinLong(studentId > 0 ? studentId : nil),
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    photoPath: photoPath,
                    isInjured: isInjured,
                    sex: sex,
                    sexSource: sexSource,
                    birthDate: birthDate,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "student_deleted":
                let studentId = int64Value(payloadObject["id"]) ?? 0
                if studentId > 0 {
                    try await container.studentsRepository.deleteStudent(studentId: studentId)
                }

            case "class_roster":
                let classId = int64Value(payloadObject["classId"]) ?? 0
                guard classId > 0 else { continue }
                let rawStudentIds = payloadObject["studentIds"] as? [Any] ?? []
                let remoteIds = Set(rawStudentIds.compactMap { int64Value($0) })
                let localIds = Set(try await container.classesRepository.listStudentsInClass(classId: classId).map { $0.id })
                for id in remoteIds.subtracting(localIds) {
                    // Añadir siempre es seguro (ver razonamiento equivalente en
                    // SqlDelightSyncAdapter.applyIncomingChangesLww, misma entidad).
                    try await container.classesRepository.addStudentToClass(classId: classId, studentId: id)
                }
                for id in localIds.subtracting(remoteIds) {
                    // Solo dar de baja si este snapshot es al menos tan reciente como
                    // la última alta/baja local conocida para ESTE alumno: evita que un
                    // snapshot de roster desactualizado borre a alguien recién añadido.
                    let localEnrollmentAt = (try await container.classesRepository.latestEnrollmentUpdatedAt(classId: classId, studentId: id))?.int64Value
                    if localEnrollmentAt == nil || change.updatedAtEpochMs >= localEnrollmentAt! {
                        try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: id)
                    }
                }

            case "evaluation":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let code = payloadObject["code"] as? String,
                    let name = payloadObject["name"] as? String,
                    let type = payloadObject["type"] as? String
                else { continue }
                let evaluationId = int64Value(payloadObject["id"]) ?? 0
                let existing: Evaluation?
                if evaluationId > 0 {
                    do {
                        existing = try await container.evaluationsRepository.getEvaluation(evaluationId: evaluationId)
                    } catch {
                        continue
                    }
                } else {
                    existing = nil
                }
                let weightKeyPresent = payloadObject.keys.contains("weight")
                let formulaKeyPresent = payloadObject.keys.contains("formula")
                let rubricKeyPresent = payloadObject.keys.contains("rubricId")
                let descriptionKeyPresent = payloadObject.keys.contains("description")
                let needsPrevious =
                    !weightKeyPresent || !formulaKeyPresent || !rubricKeyPresent || !descriptionKeyPresent
                // Sin lectura local no se puede conservar weight/formula/rubricId/description.
                if needsPrevious, existing == nil {
                    continue
                }
                let weight = EvaluationSyncMerge.weight(
                    previous: existing?.weight ?? 1.0,
                    incoming: doubleValue(payloadObject["weight"]),
                    keyPresent: weightKeyPresent
                )
                let formula = EvaluationSyncMerge.optionalText(
                    previous: existing?.formula,
                    incoming: payloadObject["formula"] as? String,
                    keyPresent: formulaKeyPresent
                )
                let rubricId = EvaluationSyncMerge.optionalLong(
                    previous: existing?.rubricId?.int64Value,
                    incoming: int64Value(payloadObject["rubricId"]).flatMap { $0 > 0 ? $0 : nil },
                    keyPresent: rubricKeyPresent
                )
                let description = EvaluationSyncMerge.optionalText(
                    previous: existing?.description_,
                    incoming: payloadObject["description"] as? String,
                    keyPresent: descriptionKeyPresent
                )
                _ = try await container.evaluationsRepository.saveEvaluation(
                    id: kotlinLong(evaluationId > 0 ? evaluationId : nil),
                    classId: classId,
                    code: code,
                    name: name,
                    type: type,
                    weight: weight,
                    formula: formula,
                    rubricId: kotlinLong(rubricId),
                    description: description,
                    authorUserId: nil,
                    createdAtEpochMs: change.updatedAtEpochMs,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "grade":
                let classId = int64Value(payloadObject["classId"]) ?? 0
                let studentId = int64Value(payloadObject["studentId"]) ?? 0
                let receivedColumnId = payloadObject["columnId"] as? String
                let evaluationIdValue = int64Value(payloadObject["evaluationId"])
                
                // Forzar ID estandarizado si tiene evaluación
                let columnId: String
                if let evalId = evaluationIdValue, evalId > 0 {
                    columnId = "eval_\(evalId)"
                } else if let col = receivedColumnId, !col.isEmpty {
                    columnId = col
                } else {
                    columnId = "eval_0"
                }

                if classId > 0, studentId > 0 {
                    let existing: Grade?
                    do {
                        existing = try await container.gradesRepository
                            .listGradesForStudentInClass(studentId: studentId, classId: classId)
                            .first(where: { $0.columnId == columnId })
                    } catch {
                        continue
                    }
                    let value = GradeSyncMerge.optionalDouble(
                        previous: existing?.value?.doubleValue,
                        incoming: doubleValue(payloadObject["value"]),
                        keyPresent: payloadObject.keys.contains("value")
                    )
                    let evidence = GradeSyncMerge.optionalText(
                        previous: existing?.evidence,
                        incoming: payloadObject["evidence"] as? String,
                        keyPresent: payloadObject.keys.contains("evidence")
                    )
                    let evidencePath = GradeSyncMerge.optionalText(
                        previous: existing?.evidencePath,
                        incoming: payloadObject["evidencePath"] as? String,
                        keyPresent: payloadObject.keys.contains("evidencePath")
                    )
                    let rubricSelections = GradeSyncMerge.optionalText(
                        previous: existing?.rubricSelections,
                        incoming: payloadObject["rubricSelections"] as? String,
                        keyPresent: payloadObject.keys.contains("rubricSelections")
                    )
                    try await container.gradesRepository.upsertGrade(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId,
                        evaluationId: kotlinLong(evaluationIdValue),
                        value: value.map { KotlinDouble(value: $0) },
                        evidence: evidence,
                        evidencePath: evidencePath,
                        rubricSelections: rubricSelections,
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                }

            case "weekly_slot":
                guard
                    let classId = int64Value(payloadObject["schoolClassId"] ?? payloadObject["classId"]),
                    let dayOfWeek = int64Value(payloadObject["dayOfWeek"]).map(Int.init),
                    let startTime = payloadObject["startTime"] as? String,
                    let endTime = payloadObject["endTime"] as? String
                else { continue }
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existingSlots = container.weeklyTemplateRepository
                    .getSlotsForClass(schoolClassId: classId)
                    .map {
                        WeeklySlotSyncMerge.ExistingSlot(
                            id: $0.id,
                            dayOfWeek: Int($0.dayOfWeek),
                            startTime: $0.startTime,
                            endTime: $0.endTime
                        )
                    }
                let matchedId = WeeklySlotSyncMerge.matchedId(
                    incomingId: incomingId,
                    dayOfWeek: dayOfWeek,
                    startTime: startTime,
                    endTime: endTime,
                    existing: existingSlots
                )
                let resolvedId = WeeklySlotSyncMerge.keptId(incoming: incomingId, matched: matchedId)
                // Sin id remoto ni franja local (grupo/día/horas), no inventar una copia.
                guard resolvedId > 0 else { continue }
                _ = try await container.weeklyTemplateRepository.insert(
                    slot: WeeklySlotTemplate(
                        id: resolvedId,
                        schoolClassId: classId,
                        dayOfWeek: Int32(dayOfWeek),
                        startTime: startTime,
                        endTime: endTime
                    )
                )

            case "notebook_tab":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let tabId = payloadObject["id"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }
                let existing: NotebookTab?
                do {
                    existing = try await container.notebookConfigRepository.listTabs(classId: classId)
                        .first { $0.id == tabId }
                } catch {
                    continue
                }
                let orderKeyPresent = payloadObject.keys.contains("order")
                let parentKeyPresent = payloadObject.keys.contains("parentTabId")
                let descriptionKeyPresent = payloadObject.keys.contains("description")
                let needsPrevious = !orderKeyPresent || !parentKeyPresent || !descriptionKeyPresent
                // Sin lectura local no se inventan order/parentTabId/description.
                if needsPrevious, existing == nil {
                    continue
                }
                let incomingOrder = (payloadObject["order"] as? Int)
                    ?? (int64Value(payloadObject["order"]).map { Int($0) })
                let incomingParent = (payloadObject["parentTabId"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let incomingDescription = (payloadObject["description"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let order = NotebookTabSyncMerge.order(
                    previous: existing?.order ?? 0,
                    incoming: incomingOrder,
                    keyPresent: orderKeyPresent
                )
                let parentTabId = NotebookTabSyncMerge.optionalText(
                    previous: existing?.parentTabId,
                    incoming: incomingParent,
                    keyPresent: parentKeyPresent
                )
                let description = NotebookTabSyncMerge.optionalText(
                    previous: existing?.description,
                    incoming: incomingDescription,
                    keyPresent: descriptionKeyPresent
                )
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                try await container.notebookRepository.saveTab(
                    classId: classId,
                    tab: NotebookTab(
                        id: tabId,
                        title: title,
                        description: description,
                        order: order,
                        parentTabId: parentTabId,
                        fixedColumnWidth: existing?.fixedColumnWidth,
                        trace: trace
                    )
                )

            case "notebook_group":
                guard
                    let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]),
                    let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String),
                    let name = payloadObject["name"] as? String
                else { continue }
                let groupId = int64Value(payloadObject["id"]) ?? int64Value(payloadObject["group_id"]) ?? 0
                let existing: NotebookWorkGroup?
                do {
                    existing = try await container.notebookConfigRepository.listWorkGroups(classId: classId, tabId: nil)
                        .first { $0.id == groupId }
                } catch {
                    continue
                }
                let orderKeyPresent = payloadObject.keys.contains("order")
                let situationKeyPresent = payloadObject.keys.contains("learningSituationId")
                    || payloadObject.keys.contains("learning_situation_id")
                let needsPrevious = !orderKeyPresent || !situationKeyPresent
                // Sin lectura local no se inventan order/learningSituationId.
                if needsPrevious, existing == nil {
                    continue
                }
                let incomingOrder = (payloadObject["order"] as? Int)
                    ?? (int64Value(payloadObject["order"]).map { Int($0) })
                let incomingSituation = int64Value(payloadObject["learningSituationId"])
                    ?? int64Value(payloadObject["learning_situation_id"])
                let order = NotebookGroupSyncMerge.order(
                    previous: existing?.order ?? 0,
                    incoming: incomingOrder,
                    keyPresent: orderKeyPresent
                )
                let learningSituationId = NotebookGroupSyncMerge.optionalLong(
                    previous: existing?.learningSituationId?.int64Value,
                    incoming: incomingSituation,
                    keyPresent: situationKeyPresent
                )
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1,
                )
                _ = try await container.notebookRepository.saveWorkGroup(
                    classId: classId,
                    workGroup: NotebookWorkGroup(
                        id: groupId,
                        classId: classId,
                        tabId: tabId,
                        name: name,
                        order: order,
                        learningSituationId: learningSituationId.map { KotlinLong(value: $0) },
                        trace: trace
                    )
                )

            case "notebook_group_member":
                guard
                    let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]),
                    let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String),
                    let groupId = int64Value(payloadObject["groupId"]) ?? int64Value(payloadObject["group_id"]),
                    let studentId = int64Value(payloadObject["studentId"]) ?? int64Value(payloadObject["student_id"])
                else { continue }
                try await container.notebookConfigRepository.assignStudentsToWorkGroup(
                    classId: classId,
                    tabId: tabId,
                    groupId: groupId,
                    studentIds: [KotlinLong(value: studentId)]
                )

            case "notebook_column_category":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let id = payloadObject["id"] as? String,
                    let tabId = payloadObject["tabId"] as? String,
                    let name = payloadObject["name"] as? String
                else { continue }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                try await container.notebookRepository.saveColumnCategory(
                    classId: classId,
                    category: NotebookColumnCategory(
                        id: id,
                        classId: classId,
                        tabId: tabId,
                        name: name,
                        order: Int32(payloadObject["order"] as? Int ?? 0),
                        isCollapsed: boolValue(payloadObject["isCollapsed"] ?? payloadObject["is_collapsed"]) ?? false,
                        trace: trace
                    )
                )

            case "notebook_column":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let _ = payloadObject["id"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let evaluationIdValue = int64Value(payloadObject["evaluationId"]).flatMap { $0 > 0 ? $0 : nil }
                let rubricId = int64Value(payloadObject["rubricId"]).flatMap { $0 > 0 ? $0 : nil }

                let resolvedColumnId: String = {
                    if let evalId = evaluationIdValue, evalId > 0 { return "eval_\(evalId)" }
                    return payloadObject["id"] as? String ?? UUID().uuidString
                }()

                let existing: NotebookColumnDefinition?
                do {
                    existing = try await container.notebookConfigRepository.listColumns(classId: classId)
                        .first { $0.id == resolvedColumnId }
                } catch {
                    continue
                }

                let typeKeyPresent = payloadObject.keys.contains("type") || payloadObject.keys.contains("column_type")
                let incomingTypeRaw = (payloadObject["type"] as? String) ?? (payloadObject["column_type"] as? String)
                let type = NotebookColumnSyncMerge.typeValue(
                    previous: existing?.type ?? .numeric,
                    incoming: incomingTypeRaw.map { notebookColumnType(from: $0) },
                    keyPresent: typeKeyPresent
                )

                let tabKeysPresent = payloadObject.keys.contains("tabIdsCsv")
                    || payloadObject.keys.contains("tab_ids_csv")
                    || payloadObject.keys.contains("tabIds")
                    || payloadObject.keys.contains("tab_ids")
                let sharedKeyPresent = payloadObject.keys.contains("sharedAcrossTabs")
                    || payloadObject.keys.contains("shared_across_tabs")

                let rawTabIds: [String] = {
                    if let csv = payloadObject["tabIdsCsv"] as? String {
                        return csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } else if let csv = payloadObject["tab_ids_csv"] as? String {
                        return csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } else if let arr = (payloadObject["tabIdsCsv"] ?? payloadObject["tabIds"]) as? [String] {
                        return arr
                    } else if let arr = (payloadObject["tab_ids_csv"] ?? payloadObject["tab_ids"]) as? [String] {
                        return arr
                    } else {
                        return []
                    }
                }()

                let existingTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
                let incomingTitles = parseDelimitedStringList(payloadObject["tabTitlesCsv"] ?? payloadObject["tab_titles_csv"])
                let resolvedTabIds = resolveNotebookColumnTabIds(
                    rawTabIds: rawTabIds,
                    incomingTitles: incomingTitles,
                    existingTabs: existingTabs
                )

                let sharedAcrossTabs = NotebookColumnSyncMerge.flag(
                    previous: existing?.sharedAcrossTabs ?? false,
                    incoming: boolValue(payloadObject["sharedAcrossTabs"] ?? payloadObject["shared_across_tabs"]),
                    keyPresent: sharedKeyPresent
                )
                let finalTabIds: [String] = {
                    if sharedAcrossTabs { return existingTabs.map { $0.id } }
                    if tabKeysPresent { return resolvedTabIds }
                    return existing?.tabIds ?? resolvedTabIds
                }()
                let colorHex = NotebookColumnSyncMerge.optionalText(
                    previous: existing?.colorHex,
                    incoming: normalizeHexColor(payloadObject["colorHex"] as? String),
                    keyPresent: payloadObject.keys.contains("colorHex")
                )
                let formula = NotebookColumnSyncMerge.optionalText(
                    previous: existing?.formula,
                    incoming: payloadObject["formula"] as? String,
                    keyPresent: payloadObject.keys.contains("formula")
                )
                let categoryIdRaw = (payloadObject["categoryId"] as? String) ?? (payloadObject["category_id"] as? String)
                let categoryIdIncoming = categoryIdRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? categoryIdRaw : nil
                let categoryId = NotebookColumnSyncMerge.optionalText(
                    previous: existing?.categoryId,
                    incoming: categoryIdIncoming,
                    keyPresent: payloadObject.keys.contains("categoryId") || payloadObject.keys.contains("category_id")
                )

                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

                // Evita perder columnas sincronizadas por FK cuando la evaluación aún no
                // ha llegado en este pull (desfase de cursores u orden de cambios).
                if let evalId = evaluationIdValue {
                    let existingEval = try await container.evaluationsRepository.getEvaluation(evaluationId: evalId)
                    if existingEval == nil {
                        let payloadType = (payloadObject["type"] as? String) ?? (payloadObject["column_type"] as? String) ?? "Evaluación"
                        _ = try await container.evaluationsRepository.saveEvaluation(
                            id: KotlinLong(value: evalId),
                            classId: classId,
                            code: "SYNC_\(evalId)",
                            name: title,
                            type: payloadType,
                            weight: NotebookColumnSyncMerge.weight(
                                previous: existing?.weight ?? 1.0,
                                incoming: doubleValue(payloadObject["weight"]),
                                keyPresent: payloadObject.keys.contains("weight")
                            ),
                            formula: formula,
                            rubricId: kotlinLong(rubricId),
                            description: nil,
                            authorUserId: nil,
                            createdAtEpochMs: change.updatedAtEpochMs,
                            updatedAtEpochMs: change.updatedAtEpochMs,
                            associatedGroupId: nil,
                            deviceId: change.deviceId,
                            syncVersion: 1
                        )
                    }
                }

                let mergedEvaluationId = NotebookColumnSyncMerge.optionalLong(
                    previous: existing?.evaluationId?.int64Value,
                    incoming: evaluationIdValue,
                    keyPresent: payloadObject.keys.contains("evaluationId")
                )
                let mergedRubricId = NotebookColumnSyncMerge.optionalLong(
                    previous: existing?.rubricId?.int64Value,
                    incoming: rubricId,
                    keyPresent: payloadObject.keys.contains("rubricId")
                )

                try await container.notebookRepository.saveColumn(
                    classId: classId,
                    column: NotebookColumnDefinition(
                        id: resolvedColumnId,
                        title: title,
                        type: type,
                        categoryKind: NotebookColumnSyncMerge.typeValue(
                            previous: existing?.categoryKind ?? .custom,
                            incoming: payloadObject.keys.contains("categoryKind")
                                ? notebookCategoryKind(payloadObject["categoryKind"] as? String)
                                : nil,
                            keyPresent: payloadObject.keys.contains("categoryKind")
                        ),
                        instrumentKind: NotebookColumnSyncMerge.typeValue(
                            previous: existing?.instrumentKind ?? .custom,
                            incoming: payloadObject.keys.contains("instrumentKind")
                                ? notebookInstrumentKind(payloadObject["instrumentKind"] as? String)
                                : nil,
                            keyPresent: payloadObject.keys.contains("instrumentKind")
                        ),
                        inputKind: NotebookColumnSyncMerge.typeValue(
                            previous: existing?.inputKind ?? .text,
                            incoming: payloadObject.keys.contains("inputKind")
                                ? notebookInputKind(payloadObject["inputKind"] as? String)
                                : nil,
                            keyPresent: payloadObject.keys.contains("inputKind")
                        ),
                        evaluationId: kotlinLong(mergedEvaluationId),
                        rubricId: kotlinLong(mergedRubricId),
                        formula: formula,
                        weight: NotebookColumnSyncMerge.weight(
                            previous: existing?.weight ?? 1.0,
                            incoming: doubleValue(payloadObject["weight"]),
                            keyPresent: payloadObject.keys.contains("weight")
                        ),
                        dateEpochMs: kotlinLong(
                            NotebookColumnSyncMerge.optionalLong(
                                previous: existing?.dateEpochMs?.int64Value,
                                incoming: int64Value(payloadObject["dateEpochMs"] ?? payloadObject["date_epoch_ms"]),
                                keyPresent: payloadObject.keys.contains("dateEpochMs") || payloadObject.keys.contains("date_epoch_ms")
                            )
                        ),
                        unitOrSituation: NotebookColumnSyncMerge.optionalText(
                            previous: existing?.unitOrSituation,
                            incoming: (payloadObject["unitOrSituation"] as? String) ?? (payloadObject["unit_name"] as? String),
                            keyPresent: payloadObject.keys.contains("unitOrSituation") || payloadObject.keys.contains("unit_name")
                        ),
                        competencyCriteriaIds: payloadObject.keys.contains("competencyCriteriaIds") || payloadObject.keys.contains("competency_criteria_ids_csv")
                            ? longList(payloadObject["competencyCriteriaIds"] ?? payloadObject["competency_criteria_ids_csv"])
                            : (existing?.competencyCriteriaIds ?? []),
                        scaleKind: NotebookColumnSyncMerge.typeValue(
                            previous: existing?.scaleKind ?? .custom,
                            incoming: payloadObject.keys.contains("scaleKind")
                                ? notebookScaleKind(payloadObject["scaleKind"] as? String)
                                : nil,
                            keyPresent: payloadObject.keys.contains("scaleKind")
                        ),
                        tabIds: finalTabIds,
                        sessions: existing?.sessions ?? [],
                        sharedAcrossTabs: sharedAcrossTabs,
                        colorHex: colorHex,
                        iconName: NotebookColumnSyncMerge.optionalText(
                            previous: existing?.iconName,
                            incoming: (payloadObject["iconName"] as? String) ?? (payloadObject["icon_name"] as? String),
                            keyPresent: payloadObject.keys.contains("iconName") || payloadObject.keys.contains("icon_name")
                        ),
                        order: NotebookColumnSyncMerge.order(
                            previous: existing?.order ?? -1,
                            incoming: payloadObject["order"] as? Int,
                            keyPresent: payloadObject.keys.contains("order")
                        ),
                        widthDp: NotebookColumnSyncMerge.weight(
                            previous: existing?.widthDp ?? 0.0,
                            incoming: doubleValue(payloadObject["widthDp"] ?? payloadObject["width_dp"]),
                            keyPresent: payloadObject.keys.contains("widthDp") || payloadObject.keys.contains("width_dp")
                        ),
                        categoryId: categoryId,
                        ordinalLevels: existing?.ordinalLevels ?? [],
                        availableIcons: existing?.availableIcons ?? [],
                        countsTowardAverage: NotebookColumnSyncMerge.flag(
                            previous: existing?.countsTowardAverage ?? true,
                            incoming: boolValue(payloadObject["countsTowardAverage"] ?? payloadObject["counts_toward_average"]),
                            keyPresent: payloadObject.keys.contains("countsTowardAverage") || payloadObject.keys.contains("counts_toward_average")
                        ),
                        isPinned: NotebookColumnSyncMerge.flag(
                            previous: existing?.isPinned ?? false,
                            incoming: boolValue(payloadObject["isPinned"] ?? payloadObject["is_pinned"]),
                            keyPresent: payloadObject.keys.contains("isPinned") || payloadObject.keys.contains("is_pinned")
                        ),
                        isHidden: NotebookColumnSyncMerge.flag(
                            previous: existing?.isHidden ?? false,
                            incoming: boolValue(payloadObject["isHidden"] ?? payloadObject["is_hidden"]),
                            keyPresent: payloadObject.keys.contains("isHidden") || payloadObject.keys.contains("is_hidden")
                        ),
                        visibility: NotebookColumnSyncMerge.typeValue(
                            previous: existing?.visibility ?? .visible,
                            incoming: payloadObject.keys.contains("visibility")
                                ? notebookColumnVisibility(payloadObject["visibility"] as? String)
                                : nil,
                            keyPresent: payloadObject.keys.contains("visibility")
                        ),
                        isLocked: NotebookColumnSyncMerge.flag(
                            previous: existing?.isLocked ?? false,
                            incoming: boolValue(payloadObject["isLocked"] ?? payloadObject["is_locked"]),
                            keyPresent: payloadObject.keys.contains("isLocked") || payloadObject.keys.contains("is_locked")
                        ),
                        isTemplate: NotebookColumnSyncMerge.flag(
                            previous: existing?.isTemplate ?? false,
                            incoming: boolValue(payloadObject["isTemplate"] ?? payloadObject["is_template"]),
                            keyPresent: payloadObject.keys.contains("isTemplate") || payloadObject.keys.contains("is_template")
                        ),
                        emptyCellPolicy: existing?.emptyCellPolicy ?? .excludeFromAverage,
                        trace: trace
                    )
                )

            case "notebook_cell":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let studentId = int64Value(payloadObject["studentId"]),
                    let columnId = payloadObject["columnId"] as? String
                else { continue }

                let existing: PersistedNotebookCell?
                do {
                    existing = try await container.notebookCellsRepository.listClassCells(classId: classId)
                        .first { $0.studentId == studentId && $0.columnId == columnId }
                } catch {
                    continue
                }

                let textValue = NotebookCellSyncMerge.optionalText(
                    previous: existing?.textValue,
                    incoming: payloadObject["textValue"] as? String,
                    keyPresent: payloadObject.keys.contains("textValue")
                )
                let boolValue = NotebookCellSyncMerge.optionalBool(
                    previous: existing?.boolValue?.boolValue,
                    incoming: payloadObject["boolValue"] as? Bool,
                    keyPresent: payloadObject.keys.contains("boolValue")
                )
                let iconValue = NotebookCellSyncMerge.optionalText(
                    previous: existing?.iconValue,
                    incoming: payloadObject["iconValue"] as? String,
                    keyPresent: payloadObject.keys.contains("iconValue")
                )
                let ordinalValue = NotebookCellSyncMerge.optionalText(
                    previous: existing?.ordinalValue,
                    incoming: payloadObject["ordinalValue"] as? String,
                    keyPresent: payloadObject.keys.contains("ordinalValue")
                )
                let note = NotebookCellSyncMerge.optionalText(
                    previous: existing?.annotation?.note,
                    incoming: payloadObject["note"] as? String,
                    keyPresent: payloadObject.keys.contains("note")
                )
                let colorHex = NotebookCellSyncMerge.optionalText(
                    previous: existing?.annotation?.colorHex,
                    incoming: normalizeHexColor(payloadObject["colorHex"] as? String),
                    keyPresent: payloadObject.keys.contains("colorHex")
                )
                let attachmentUris = NotebookCellSyncMerge.attachmentUris(
                    previous: existing?.annotation?.attachmentUris ?? [],
                    incoming: payloadObject["attachmentUris"] as? [String],
                    keyPresent: payloadObject.keys.contains("attachmentUris")
                )

                try await container.notebookRepository.saveCell(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    textValue: textValue,
                    boolValue: boolValue.map { KotlinBoolean(value: $0) },
                    iconValue: iconValue,
                    ordinalValue: ordinalValue,
                    note: note,
                    colorHex: colorHex,
                    attachmentUris: attachmentUris,
                    authorUserId: nil,
                    associatedGroupId: nil
                )

            case "notebook_instrument_template":
                guard
                    let id = payloadObject["id"] as? String,
                    let classId = int64Value(payloadObject["classId"]),
                    let columnId = payloadObject["columnId"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let kindStr = (payloadObject["kind"] as? String) ?? "observation"
                let inputKindStr = (payloadObject["inputKind"] as? String) ?? "structuredObservation"
                let kind = notebookInstrumentTemplateKind(kindStr)
                let inputKind = notebookInputKind(inputKindStr)
                let evaluationId = int64Value(payloadObject["evaluationId"]).flatMap { $0 > 0 ? KotlinLong(value: $0) : nil }
                let source = payloadObject["source"] as? String
                let createdAtMs = int64Value(payloadObject["createdAtEpochMs"]) ?? change.updatedAtEpochMs
                let createdAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: createdAtMs)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)

                let template = NotebookInstrumentTemplate(
                    id: id,
                    classId: classId,
                    columnId: columnId,
                    evaluationId: evaluationId,
                    title: title,
                    kind: kind,
                    inputKind: inputKind,
                    source: source,
                    trace: AuditTrace(
                        authorUserId: nil,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        associatedGroupId: KotlinLong(value: classId),
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                let existingItems: [NotebookInstrumentItem]
                do {
                    existingItems = try await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId)?.items ?? []
                } catch {
                    continue
                }
                try await container.notebookInstrumentsRepository.saveTemplate(template: template, items: existingItems)

            case "notebook_instrument_item":
                guard
                    let id = payloadObject["id"] as? String,
                    let templateId = payloadObject["templateId"] as? String,
                    let itemKey = payloadObject["itemKey"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let targetColId = templateId.hasPrefix("template_") ? String(templateId.dropFirst(9)) : templateId
                let detail: NotebookInstrumentDetail
                do {
                    guard let loaded = try await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: targetColId) else {
                        continue
                    }
                    detail = loaded
                } catch {
                    continue
                }
                let previous = detail.items.first { $0.id == id }
                let itemType = payloadObject.keys.contains("itemType")
                    ? notebookInstrumentItemType((payloadObject["itemType"] as? String) ?? "scale14")
                    : (previous?.type ?? notebookInstrumentItemType("scale14"))
                let options = InstrumentItemMerge.options(
                    previous: previous?.options ?? [],
                    incoming: payloadObject.keys.contains("optionsCsv")
                        ? ((payloadObject["optionsCsv"] as? String) ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty }
                        : nil
                )
                let required = InstrumentItemMerge.flag(
                    previous: previous?.required ?? true,
                    incoming: payloadObject.keys.contains("required") ? boolValue(payloadObject["required"]) : nil
                )
                let sortOrder = InstrumentItemMerge.order(
                    previous: Int(previous?.order ?? 0),
                    incoming: payloadObject.keys.contains("sortOrder") ? int64Value(payloadObject["sortOrder"]).map(Int.init) : nil
                )
                let helpText = payloadObject.keys.contains("helpText")
                    ? payloadObject["helpText"] as? String
                    : previous?.helpText

                let item = NotebookInstrumentItem(
                    id: id,
                    templateId: templateId,
                    key: itemKey,
                    title: title,
                    type: itemType,
                    options: options,
                    required: required,
                    order: Int32(sortOrder),
                    helpText: helpText?.isEmpty == true ? nil : helpText,
                    trace: AuditTrace(
                        authorUserId: nil,
                        createdAt: updatedAt,
                        updatedAt: updatedAt,
                        associatedGroupId: nil,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                var items = detail.items.filter { $0.id != id }
                items.append(item)
                items.sort { $0.order < $1.order }
                try await container.notebookInstrumentsRepository.saveTemplate(template: detail.template_, items: items)

            case "notebook_instrument_response":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let studentId = int64Value(payloadObject["studentId"]),
                    let columnId = payloadObject["columnId"] as? String,
                    let itemId = payloadObject["itemId"] as? String
                else { continue }

                let loadedResponses: [NotebookInstrumentResponse]
                do {
                    loadedResponses = try await container.notebookInstrumentsRepository.listResponsesForCell(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId
                    )
                } catch {
                    continue
                }
                let previous = loadedResponses.first { $0.itemId == itemId }
                let textValue = payloadObject.keys.contains("valueText")
                    ? (payloadObject["valueText"] as? String ?? "")
                    : (previous?.textValue ?? "")
                let boolVal = payloadObject.keys.contains("valueBool")
                    ? boolValue(payloadObject["valueBool"])
                    : previous?.boolValue?.boolValue
                let numValue = payloadObject.keys.contains("valueNumber")
                    ? ((payloadObject["valueNumber"] as? String) ?? "")
                    : (previous?.numberValue?.doubleValue).map { String($0) } ?? ""

                guard let responses = InstrumentResponseMerge.replacing(
                    existing: loadedResponses,
                    removeWhere: { $0.itemId == itemId },
                    incoming: NotebookInstrumentResponse(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    itemId: itemId,
                    textValue: textValue,
                    boolValue: boolVal.map { KotlinBoolean(value: $0) },
                    numberValue: numValue.isEmpty ? nil : KotlinDouble(value: Double(numValue) ?? 0.0),
                    trace: AuditTrace(
                        authorUserId: nil,
                        createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs),
                        updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs),
                        associatedGroupId: nil,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                ) else { continue }
                _ = try await container.notebookInstrumentsRepository.saveResponses(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    responses: responses,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "teaching_unit":
                guard let name = payloadObject["name"] as? String else { continue }
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existingUnits: [TeachingUnit]
                do {
                    existingUnits = try await container.plannerRepository.listAllTeachingUnits()
                } catch {
                    continue
                }
                let existing = existingUnits.first { $0.id == incomingId }
                let unit = TeachingUnit(
                    id: incomingId,
                    name: name,
                    description: TeachingUnitSyncMerge.text(
                        previous: existing?.description_ ?? "",
                        incoming: payloadObject["description"] as? String,
                        keyPresent: payloadObject.keys.contains("description")
                    ),
                    colorHex: payloadObject.keys.contains("colorHex")
                        ? (normalizeHexColor(payloadObject["colorHex"] as? String) ?? existing?.colorHex ?? "#4A90D9")
                        : (existing?.colorHex ?? "#4A90D9"),
                    groupId: payloadObject.keys.contains("groupId")
                        ? kotlinLong(int64Value(payloadObject["groupId"]))
                        : existing?.groupId,
                    schoolClassId: payloadObject.keys.contains("schoolClassId")
                        ? kotlinLong(int64Value(payloadObject["schoolClassId"]))
                        : existing?.schoolClassId,
                    startDate: payloadObject.keys.contains("startDate")
                        ? localDate(from: payloadObject["startDate"])
                        : existing?.startDate,
                    endDate: payloadObject.keys.contains("endDate")
                        ? localDate(from: payloadObject["endDate"])
                        : existing?.endDate
                )
                _ = try await container.plannerRepository.upsertTeachingUnit(unit: unit)

            case "learning_situation":
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existing: LearningSituation?
                if incomingId > 0 {
                    do {
                        existing = try await container.learningSituationsRepository.getSituation(id: incomingId)
                    } catch {
                        continue
                    }
                } else {
                    existing = nil
                }
                func kept(_ key: String, previous: String) -> String {
                    TeachingUnitSyncMerge.text(
                        previous: previous,
                        incoming: payloadObject[key] as? String,
                        keyPresent: payloadObject.keys.contains(key)
                    )
                }
                let sessionCount = payloadObject.keys.contains("sessionCount")
                    ? Int32(int64Value(payloadObject["sessionCount"]) ?? Int64(existing?.sessionCount ?? 0))
                    : (existing?.sessionCount ?? 0)
                let isDraft = LearningSituationSyncMerge.staysDraft(
                    previousIsDraft: existing?.status == .draft,
                    incoming: payloadObject["status"] as? String,
                    keyPresent: payloadObject.keys.contains("status")
                )
                _ = try await container.learningSituationsRepository.saveSituation(
                    situation: LearningSituation(
                        id: incomingId,
                        title: kept("title", previous: existing?.title ?? "Situación"),
                        stageLabel: kept("stageLabel", previous: existing?.stageLabel ?? ""),
                        courseLabel: kept("courseLabel", previous: existing?.courseLabel ?? ""),
                        subjectLabel: kept("subjectLabel", previous: existing?.subjectLabel ?? ""),
                        termLabel: kept("termLabel", previous: existing?.termLabel ?? ""),
                        centerLabel: kept("centerLabel", previous: existing?.centerLabel ?? ""),
                        sessionCount: sessionCount,
                        challenge: kept("challenge", previous: existing?.challenge ?? ""),
                        finalProduct: kept("finalProduct", previous: existing?.finalProduct ?? ""),
                        payloadJson: kept("payloadJson", previous: existing?.payloadJson ?? "{}"),
                        status: isDraft ? .draft : .active,
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_version":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let hash = payloadObject["sha256"] as? String else { continue }
                let existingVersions: [LearningSituationVersion]
                do {
                    existingVersions = try await container.learningSituationsRepository.listVersions(learningSituationId: situationId)
                } catch {
                    continue
                }
                let incomingVersionId = int64Value(payloadObject["id"]) ?? 0
                let existing = existingVersions.first { $0.id == incomingVersionId && incomingVersionId > 0 }
                    ?? existingVersions.first { $0.sha256 == hash }
                let downloadedPath = await downloadLearningSituationDocumentIfNeeded(sha256: hash)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveVersion(
                    version: LearningSituationVersion(
                        id: SituationVersionSyncMerge.keptId(incoming: incomingVersionId, matched: existing?.id),
                        learningSituationId: situationId,
                        versionNumber: SituationVersionSyncMerge.number(
                            previous: existing?.versionNumber ?? 0,
                            incoming: int64Value(payloadObject["versionNumber"]).map(Int32.init),
                            keyPresent: payloadObject.keys.contains("versionNumber")
                        ),
                        originalFileName: TeachingUnitSyncMerge.text(
                            previous: existing?.originalFileName ?? "\(hash).docx",
                            incoming: payloadObject["originalFileName"] as? String,
                            keyPresent: payloadObject.keys.contains("originalFileName")
                        ),
                        sha256: hash,
                        localPath: (downloadedPath?.isEmpty == false) ? downloadedPath : existing?.localPath,
                        sizeBytes: payloadObject.keys.contains("sizeBytes")
                            ? (int64Value(payloadObject["sizeBytes"]) ?? existing?.sizeBytes ?? 0)
                            : (existing?.sizeBytes ?? 0),
                        payloadJson: TeachingUnitSyncMerge.text(
                            previous: existing?.payloadJson ?? "{}",
                            incoming: payloadObject["payloadJson"] as? String,
                            keyPresent: payloadObject.keys.contains("payloadJson")
                        ),
                        warningsJson: TeachingUnitSyncMerge.text(
                            previous: existing?.warningsJson ?? "[]",
                            incoming: payloadObject["warningsJson"] as? String,
                            keyPresent: payloadObject.keys.contains("warningsJson")
                        ),
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_sequence_version":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let hash = payloadObject["sha256"] as? String else { continue }
                let existingVersions: [LearningSituationSessionSequenceVersion]
                do {
                    existingVersions = try await container.learningSituationsRepository.listSessionSequenceVersions(learningSituationId: situationId)
                } catch {
                    continue
                }
                let incomingVersionId = int64Value(payloadObject["id"]) ?? 0
                let existing = existingVersions.first { $0.id == incomingVersionId && incomingVersionId > 0 }
                    ?? existingVersions.first { $0.sha256 == hash }
                let downloadedPath = await downloadLearningSituationDocumentIfNeeded(sha256: hash)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSessionSequenceVersion(
                    version: LearningSituationSessionSequenceVersion(
                        id: SituationVersionSyncMerge.keptId(incoming: incomingVersionId, matched: existing?.id),
                        learningSituationId: situationId,
                        versionNumber: SituationVersionSyncMerge.number(
                            previous: existing?.versionNumber ?? 0,
                            incoming: int64Value(payloadObject["versionNumber"]).map(Int32.init),
                            keyPresent: payloadObject.keys.contains("versionNumber")
                        ),
                        originalFileName: TeachingUnitSyncMerge.text(
                            previous: existing?.originalFileName ?? "\(hash).docx",
                            incoming: payloadObject["originalFileName"] as? String,
                            keyPresent: payloadObject.keys.contains("originalFileName")
                        ),
                        sha256: hash,
                        localPath: (downloadedPath?.isEmpty == false) ? downloadedPath : existing?.localPath,
                        sizeBytes: payloadObject.keys.contains("sizeBytes")
                            ? (int64Value(payloadObject["sizeBytes"]) ?? existing?.sizeBytes ?? 0)
                            : (existing?.sizeBytes ?? 0),
                        payloadJson: TeachingUnitSyncMerge.text(
                            previous: existing?.payloadJson ?? "{}",
                            incoming: payloadObject["payloadJson"] as? String,
                            keyPresent: payloadObject.keys.contains("payloadJson")
                        ),
                        warningsJson: TeachingUnitSyncMerge.text(
                            previous: existing?.warningsJson ?? "[]",
                            incoming: payloadObject["warningsJson"] as? String,
                            keyPresent: payloadObject.keys.contains("warningsJson")
                        ),
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_session_plan":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let sequenceVersionId = int64Value(payloadObject["sequenceVersionId"]),
                      let title = payloadObject["title"] as? String else { continue }
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existing: LearningSituationSessionPlan?
                if incomingId > 0 {
                    do {
                        existing = try await container.learningSituationsRepository.getSessionPlan(id: incomingId)
                    } catch {
                        continue
                    }
                } else {
                    existing = nil
                }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSessionPlan(
                    plan: LearningSituationSessionPlan(
                        id: incomingId,
                        learningSituationId: situationId,
                        sequenceVersionId: sequenceVersionId,
                        sessionNumber: SituationVersionSyncMerge.number(
                            previous: existing?.sessionNumber ?? 0,
                            incoming: int64Value(payloadObject["sessionNumber"]).map(Int32.init),
                            keyPresent: payloadObject.keys.contains("sessionNumber")
                        ),
                        sourceLabel: TeachingUnitSyncMerge.text(
                            previous: existing?.sourceLabel ?? "",
                            incoming: payloadObject["sourceLabel"] as? String,
                            keyPresent: payloadObject.keys.contains("sourceLabel")
                        ),
                        title: title,
                        sessionType: TeachingUnitSyncMerge.text(
                            previous: existing?.sessionType ?? "",
                            incoming: payloadObject["sessionType"] as? String,
                            keyPresent: payloadObject.keys.contains("sessionType")
                        ),
                        effectiveMinutes: SituationVersionSyncMerge.number(
                            previous: existing?.effectiveMinutes ?? 0,
                            incoming: int64Value(payloadObject["effectiveMinutes"]).map(Int32.init),
                            keyPresent: payloadObject.keys.contains("effectiveMinutes")
                        ),
                        objective: TeachingUnitSyncMerge.text(
                            previous: existing?.objective ?? "",
                            incoming: payloadObject["objective"] as? String,
                            keyPresent: payloadObject.keys.contains("objective")
                        ),
                        criteriaJson: TeachingUnitSyncMerge.text(
                            previous: existing?.criteriaJson ?? "[]",
                            incoming: payloadObject["criteriaJson"] as? String,
                            keyPresent: payloadObject.keys.contains("criteriaJson")
                        ),
                        material: TeachingUnitSyncMerge.text(
                            previous: existing?.material ?? "",
                            incoming: payloadObject["material"] as? String,
                            keyPresent: payloadObject.keys.contains("material")
                        ),
                        developmentJson: TeachingUnitSyncMerge.text(
                            previous: existing?.developmentJson ?? "[]",
                            incoming: payloadObject["developmentJson"] as? String,
                            keyPresent: payloadObject.keys.contains("developmentJson")
                        ),
                        adaptationsJson: TeachingUnitSyncMerge.text(
                            previous: existing?.adaptationsJson ?? "[]",
                            incoming: payloadObject["adaptationsJson"] as? String,
                            keyPresent: payloadObject.keys.contains("adaptationsJson")
                        ),
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_class_link":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let classId = int64Value(payloadObject["classId"]) else { continue }
                let current = try await container.learningSituationsRepository.listClassLinks(learningSituationId: situationId)
                let classIds = Set(current.map(\.classId) + [classId])
                try await container.learningSituationsRepository.replaceClassLinks(
                    learningSituationId: situationId,
                    classIds: Array(classIds).map { KotlinLong(value: $0) }
                )

            case "learning_situation_link":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let resourceId = payloadObject["resourceId"] as? String else { continue }
                let existing: LearningSituationLinkedResource?
                do {
                    existing = try await container.learningSituationsRepository
                        .listLinkedResources(learningSituationId: situationId)
                        .first(where: { $0.resourceId == resourceId })
                } catch {
                    continue
                }
                let kind: LearningSituationResourceKind
                if payloadObject.keys.contains("kind"), let kindName = payloadObject["kind"] as? String {
                    switch kindName {
                    case "TEACHING_UNIT": kind = .teachingUnit
                    case "PLANNING_SESSION": kind = .planningSession
                    case "EVALUATION": kind = .evaluation
                    case "RUBRIC": kind = .rubric
                    default: kind = .notebookColumn
                    }
                } else if let previous = existing?.kind {
                    kind = previous
                } else {
                    continue
                }
                let classId: KotlinLong?
                if payloadObject.keys.contains("classId") {
                    classId = int64Value(payloadObject["classId"]).map { KotlinLong(value: $0) }
                } else {
                    classId = existing?.classId
                }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveLinkedResource(
                    resource: LearningSituationLinkedResource(
                        id: LearningSituationLinkSyncMerge.keptId(
                            incoming: int64Value(payloadObject["id"]) ?? 0,
                            matched: existing?.id
                        ),
                        learningSituationId: situationId,
                        kind: kind,
                        resourceId: resourceId,
                        classId: classId,
                        label: LearningSituationLinkSyncMerge.label(
                            previous: existing?.label ?? "",
                            incoming: payloadObject["label"] as? String,
                            keyPresent: payloadObject.keys.contains("label")
                        ),
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "planning_session":
                let sessionId = int64Value(payloadObject["id"]) ?? 0
                let existingSession: PlanningSession?
                if sessionId > 0 {
                    do {
                        existingSession = try await container.plannerRepository.getSession(id: sessionId)
                    } catch {
                        continue
                    }
                } else {
                    existingSession = nil
                }
                let teachingUnitId = payloadObject.keys.contains("teachingUnitId")
                    ? (int64Value(payloadObject["teachingUnitId"]) ?? existingSession?.teachingUnitId ?? 0)
                    : (existingSession?.teachingUnitId ?? 0)
                let dayOfWeek = PlanningSessionSyncMerge.placement(
                    previous: existingSession?.dayOfWeek ?? 1,
                    incoming: int64Value(payloadObject["dayOfWeek"]),
                    keyPresent: payloadObject.keys.contains("dayOfWeek")
                )
                let period = PlanningSessionSyncMerge.placement(
                    previous: existingSession?.period ?? 1,
                    incoming: int64Value(payloadObject["period"]),
                    keyPresent: payloadObject.keys.contains("period")
                )
                let weekNumber = PlanningSessionSyncMerge.placement(
                    previous: existingSession?.weekNumber ?? 1,
                    incoming: int64Value(payloadObject["weekNumber"]),
                    keyPresent: payloadObject.keys.contains("weekNumber")
                )
                let year = PlanningSessionSyncMerge.placement(
                    previous: existingSession?.year ?? 2026,
                    incoming: int64Value(payloadObject["year"]),
                    keyPresent: payloadObject.keys.contains("year")
                )
                let status: SessionStatus
                if payloadObject.keys.contains("status"), let statusRaw = payloadObject["status"] as? String {
                    switch statusRaw.uppercased() {
                    case "IN_PROGRESS":
                        status = .inProgress
                    case "COMPLETED":
                        status = .completed
                    case "CANCELLED":
                        status = .cancelled
                    default:
                        status = .planned
                    }
                } else {
                    status = existingSession?.status ?? .planned
                }
                func keptString(_ key: String, current: String) -> String {
                    guard payloadObject.keys.contains(key) else { return current }
                    return payloadObject[key] as? String ?? ""
                }
                func keptOptionalString(_ key: String, current: String?) -> String? {
                    guard payloadObject.keys.contains(key) else { return current }
                    return payloadObject[key] as? String
                }
                func keptOptionalLong(_ key: String, current: KotlinLong?) -> KotlinLong? {
                    guard payloadObject.keys.contains(key) else { return current }
                    guard let value = int64Value(payloadObject[key]), value > 0 else { return nil }
                    return KotlinLong(value: value)
                }
                let session = PlanningSession(
                    id: sessionId,
                    teachingUnitId: teachingUnitId,
                    teachingUnitName: payloadObject["teachingUnitName"] as? String ?? existingSession?.teachingUnitName ?? "Unidad",
                    teachingUnitColor: payloadObject["teachingUnitColor"] as? String ?? existingSession?.teachingUnitColor ?? "#4A90D9",
                    groupId: int64Value(payloadObject["groupId"]) ?? existingSession?.groupId ?? 0,
                    groupName: payloadObject["groupName"] as? String ?? existingSession?.groupName ?? "",
                    dayOfWeek: Int32(dayOfWeek),
                    period: Int32(period),
                    weekNumber: Int32(weekNumber),
                    year: Int32(year),
                    objectives: keptString("objectives", current: existingSession?.objectives ?? ""),
                    activities: keptString("activities", current: existingSession?.activities ?? ""),
                    evaluation: keptString("evaluation", current: existingSession?.evaluation ?? ""),
                    linkedAssessmentIdsCsv: keptString("linkedAssessmentIdsCsv", current: existingSession?.linkedAssessmentIdsCsv ?? ""),
                    teacherScheduleSlotId: keptOptionalLong("teacherScheduleSlotId", current: existingSession?.teacherScheduleSlotId),
                    startTime: keptOptionalString("startTime", current: existingSession?.startTime),
                    endTime: keptOptionalString("endTime", current: existingSession?.endTime),
                    learningSituationSessionPlanId: keptOptionalLong(
                        "learningSituationSessionPlanId",
                        current: existingSession?.learningSituationSessionPlanId
                    ),
                    status: status
                )
                do {
                    _ = try await container.plannerRepository.upsertSession(session: session)
                } catch {
                    print("LAN Sync: upsertSession failed for planning_session \(change.id): \(error)")
                    continue
                }

            case "teacher_schedule":
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existing: TeacherSchedule?
                if incomingId > 0 {
                    do {
                        let primary = try await container.teacherScheduleRepository.getOrCreatePrimarySchedule()
                        existing = primary.id == incomingId ? primary : nil
                    } catch {
                        continue
                    }
                } else {
                    existing = nil
                }
                let schedule = TeacherSchedule(
                    id: incomingId,
                    ownerUserId: TeacherScheduleSyncMerge.longId(
                        previous: existing?.ownerUserId ?? 1,
                        incoming: int64Value(payloadObject["ownerUserId"]),
                        keyPresent: payloadObject.keys.contains("ownerUserId")
                    ),
                    academicYearId: TeacherScheduleSyncMerge.longId(
                        previous: existing?.academicYearId ?? 1,
                        incoming: int64Value(payloadObject["academicYearId"]),
                        keyPresent: payloadObject.keys.contains("academicYearId")
                    ),
                    name: TeacherScheduleSyncMerge.text(
                        previous: existing?.name ?? "Agenda docente",
                        incoming: payloadObject["name"] as? String,
                        keyPresent: payloadObject.keys.contains("name")
                    ),
                    startDateIso: TeacherScheduleSyncMerge.dates(
                        previous: existing?.startDateIso ?? "",
                        incoming: payloadObject["startDateIso"] as? String,
                        keyPresent: payloadObject.keys.contains("startDateIso")
                    ),
                    endDateIso: TeacherScheduleSyncMerge.dates(
                        previous: existing?.endDateIso ?? "",
                        incoming: payloadObject["endDateIso"] as? String,
                        keyPresent: payloadObject.keys.contains("endDateIso")
                    ),
                    activeWeekdaysCsv: TeacherScheduleSyncMerge.text(
                        previous: existing?.activeWeekdaysCsv ?? "1,2,3,4,5",
                        incoming: payloadObject["activeWeekdaysCsv"] as? String,
                        keyPresent: payloadObject.keys.contains("activeWeekdaysCsv")
                    ),
                    trace: AuditTrace(
                        authorUserId: payloadObject.keys.contains("authorUserId")
                            ? kotlinLong(int64Value(payloadObject["authorUserId"]))
                            : existing?.trace.authorUserId,
                        createdAt: Instant.companion.fromEpochMilliseconds(
                            epochMilliseconds: payloadObject.keys.contains("createdAtEpochMs")
                                ? (int64Value(payloadObject["createdAtEpochMs"]) ?? change.updatedAtEpochMs)
                                : (existing?.trace.createdAt.toEpochMilliseconds() ?? change.updatedAtEpochMs)
                        ),
                        updatedAt: updatedAt,
                        associatedGroupId: payloadObject.keys.contains("associatedGroupId")
                            ? kotlinLong(int64Value(payloadObject["associatedGroupId"]))
                            : existing?.trace.associatedGroupId,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                do {
                    _ = try await container.teacherScheduleRepository.saveSchedule(schedule: schedule)
                } catch {
                    print("LAN Sync: saveSchedule failed for teacher_schedule \(change.id): \(error)")
                    continue
                }

            case "teacher_schedule_slot":
                guard let teacherScheduleId = int64Value(payloadObject["teacherScheduleId"]) else { continue }
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existing: TeacherScheduleSlot?
                if incomingId > 0 {
                    do {
                        existing = try await container.teacherScheduleRepository.getScheduleSlot(slotId: incomingId)
                    } catch {
                        continue
                    }
                    if existing == nil {
                        let canCreateFromPayload =
                            payloadObject.keys.contains("schoolClassId")
                            && payloadObject.keys.contains("dayOfWeek")
                            && payloadObject.keys.contains("subjectLabel")
                            && payloadObject.keys.contains("startTime")
                            && payloadObject.keys.contains("endTime")
                        if !canCreateFromPayload { continue }
                    }
                } else {
                    existing = nil
                }
                let startTime: String
                if payloadObject.keys.contains("startTime") {
                    guard let incomingStart = payloadObject["startTime"] as? String else { continue }
                    startTime = incomingStart
                } else if let previousStart = existing?.startTime {
                    startTime = previousStart
                } else {
                    continue
                }
                let endTime: String
                if payloadObject.keys.contains("endTime") {
                    guard let incomingEnd = payloadObject["endTime"] as? String else { continue }
                    endTime = incomingEnd
                } else if let previousEnd = existing?.endTime {
                    endTime = previousEnd
                } else {
                    continue
                }
                let schoolClassId = TeacherScheduleSlotSyncMerge.longId(
                    previous: existing?.schoolClassId ?? 0,
                    incoming: int64Value(payloadObject["schoolClassId"]),
                    keyPresent: payloadObject.keys.contains("schoolClassId")
                )
                guard schoolClassId > 0 else { continue }
                _ = try await container.teacherScheduleRepository.saveScheduleSlot(
                    slot: TeacherScheduleSlot(
                        id: incomingId,
                        teacherScheduleId: teacherScheduleId,
                        schoolClassId: schoolClassId,
                        subjectLabel: TeacherScheduleSlotSyncMerge.text(
                            previous: existing?.subjectLabel ?? "",
                            incoming: payloadObject["subjectLabel"] as? String,
                            keyPresent: payloadObject.keys.contains("subjectLabel")
                        ),
                        unitLabel: TeacherScheduleSlotSyncMerge.optionalText(
                            previous: existing?.unitLabel,
                            incoming: payloadObject["unitLabel"] as? String,
                            keyPresent: payloadObject.keys.contains("unitLabel")
                        ),
                        dayOfWeek: TeacherScheduleSlotSyncMerge.dayOfWeek(
                            previous: existing?.dayOfWeek ?? 1,
                            incoming: int64Value(payloadObject["dayOfWeek"]),
                            keyPresent: payloadObject.keys.contains("dayOfWeek")
                        ),
                        startTime: startTime,
                        endTime: endTime,
                        weeklyTemplateId: kotlinLong(
                            TeacherScheduleSlotSyncMerge.optionalLongId(
                                previous: existing?.weeklyTemplateId?.int64Value,
                                incoming: int64Value(payloadObject["weeklyTemplateId"]),
                                keyPresent: payloadObject.keys.contains("weeklyTemplateId")
                            )
                        )
                    )
                )

            case "planner_evaluation_period":
                guard
                    let teacherScheduleId = int64Value(payloadObject["teacherScheduleId"])
                else { continue }
                let incomingId = int64Value(payloadObject["id"]) ?? 0
                let existing: PlannerEvaluationPeriod?
                if incomingId > 0 {
                    do {
                        existing = try await container.teacherScheduleRepository
                            .listEvaluationPeriods(scheduleId: teacherScheduleId)
                            .first(where: { $0.id == incomingId })
                    } catch {
                        continue
                    }
                } else {
                    existing = nil
                }
                _ = try await container.teacherScheduleRepository.saveEvaluationPeriod(
                    period: PlannerEvaluationPeriod(
                        id: incomingId,
                        teacherScheduleId: teacherScheduleId,
                        name: PlannerEvaluationPeriodSyncMerge.text(
                            previous: existing?.name ?? "",
                            incoming: payloadObject["name"] as? String,
                            keyPresent: payloadObject.keys.contains("name")
                        ),
                        startDateIso: PlannerEvaluationPeriodSyncMerge.dates(
                            previous: existing?.startDateIso ?? "",
                            incoming: payloadObject["startDateIso"] as? String,
                            keyPresent: payloadObject.keys.contains("startDateIso")
                        ),
                        endDateIso: PlannerEvaluationPeriodSyncMerge.dates(
                            previous: existing?.endDateIso ?? "",
                            incoming: payloadObject["endDateIso"] as? String,
                            keyPresent: payloadObject.keys.contains("endDateIso")
                        ),
                        sortOrder: PlannerEvaluationPeriodSyncMerge.sortOrder(
                            previous: existing?.sortOrder ?? 0,
                            incoming: int64Value(payloadObject["sortOrder"]),
                            keyPresent: payloadObject.keys.contains("sortOrder")
                        )
                    )
                )

            case "rubric_bundle":
                guard let rubricName = payloadObject["name"] as? String else { continue }
                let rubricId = int64Value(payloadObject["rubricId"]).flatMap { $0 > 0 ? $0 : nil }
                let descriptionKeyPresent = payloadObject.keys.contains("description")
                let classIdKeyPresent = payloadObject.keys.contains("classId")
                let teachingUnitIdKeyPresent = payloadObject.keys.contains("teachingUnitId")
                let criteria = payloadObject["criteria"] as? [[String: Any]] ?? []
                let criteriaNeedPrevious = criteria.contains { criterion in
                    !criterion.keys.contains("weight")
                        || !criterion.keys.contains("description")
                        || !criterion.keys.contains("order")
                        || {
                            let levels = criterion["levels"] as? [[String: Any]] ?? []
                            return levels.contains { level in
                                !level.keys.contains("points")
                                    || !level.keys.contains("description")
                                    || !level.keys.contains("order")
                            }
                        }()
                }
                let needsPrevious =
                    !descriptionKeyPresent
                    || !classIdKeyPresent
                    || !teachingUnitIdKeyPresent
                    || criteriaNeedPrevious
                let existingDetail: RubricDetail?
                if let rubricId {
                    do {
                        existingDetail = try await container.rubricsRepository.getRubricDetail(rubricId: rubricId)
                    } catch {
                        continue
                    }
                } else {
                    existingDetail = nil
                }
                // Sin lectura local no se puede conservar description/classId/teachingUnitId,
                // peso/orden de criterios ni points/order/description de niveles.
                if needsPrevious, existingDetail == nil {
                    continue
                }
                let existing = existingDetail?.rubric
                let description = RubricBundleSyncMerge.optionalText(
                    previous: existing?.description_,
                    incoming: payloadObject["description"] as? String,
                    keyPresent: descriptionKeyPresent
                )
                let classId = RubricBundleSyncMerge.optionalLong(
                    previous: existing?.classId?.int64Value,
                    incoming: int64Value(payloadObject["classId"]).flatMap { $0 > 0 ? $0 : nil },
                    keyPresent: classIdKeyPresent
                )
                let teachingUnitId = RubricBundleSyncMerge.optionalLong(
                    previous: existing?.teachingUnitId?.int64Value,
                    incoming: int64Value(payloadObject["teachingUnitId"]).flatMap { $0 > 0 ? $0 : nil },
                    keyPresent: teachingUnitIdKeyPresent
                )
                let savedRubricId = try await container.rubricsRepository.saveRubric(
                    id: kotlinLong(rubricId),
                    name: rubricName,
                    description: description,
                    classId: classId.map { KotlinLong(value: $0) },
                    teachingUnitId: teachingUnitId.map { KotlinLong(value: $0) },
                    createdAtEpochMs: change.updatedAtEpochMs,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                for criterion in criteria {
                    let criterionId = int64Value(criterion["id"]).flatMap { $0 > 0 ? $0 : nil }
                    let existingCriterion = existingDetail?.criteria
                        .first { $0.criterion.id == criterionId }?
                        .criterion
                    let criterionDescriptionKeyPresent = criterion.keys.contains("description")
                    let weightKeyPresent = criterion.keys.contains("weight")
                    let orderKeyPresent = criterion.keys.contains("order")
                    if !criterionDescriptionKeyPresent, existingCriterion == nil {
                        continue
                    }
                    let criterionDescription = RubricBundleSyncMerge.text(
                        previous: existingCriterion?.description_ ?? "",
                        incoming: criterion["description"] as? String,
                        keyPresent: criterionDescriptionKeyPresent
                    )
                    let incomingOrder: Int? = {
                        if let value = criterion["order"] as? Int { return value }
                        if let value = criterion["order"] as? Int32 { return Int(value) }
                        return nil
                    }()
                    let savedCriterionId = try await container.rubricsRepository.saveCriterion(
                        id: kotlinLong(criterionId),
                        rubricId: savedRubricId.int64Value,
                        description: criterionDescription,
                        weight: RubricBundleSyncMerge.weight(
                            previous: existingCriterion?.weight ?? 1.0,
                            incoming: doubleValue(criterion["weight"]),
                            keyPresent: weightKeyPresent
                        ),
                        order: RubricBundleSyncMerge.order(
                            previous: existingCriterion.map { Int32($0.order) } ?? 0,
                            incoming: incomingOrder,
                            keyPresent: orderKeyPresent
                        ),
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                    let levels = criterion["levels"] as? [[String: Any]] ?? []
                    let existingLevels = existingDetail?.criteria
                        .first { $0.criterion.id == criterionId }?
                        .levels ?? []
                    for level in levels {
                        guard let levelName = level["name"] as? String else { continue }
                        let levelId = int64Value(level["id"]).flatMap { $0 > 0 ? $0 : nil }
                        let existingLevel = existingLevels.first { $0.id == levelId }
                        let pointsKeyPresent = level.keys.contains("points")
                        let levelDescriptionKeyPresent = level.keys.contains("description")
                        let levelOrderKeyPresent = level.keys.contains("order")
                        if (!pointsKeyPresent || !levelDescriptionKeyPresent || !levelOrderKeyPresent),
                           existingLevel == nil {
                            continue
                        }
                        let incomingPoints: Int? = {
                            if let value = level["points"] as? Int { return value }
                            if let value = level["points"] as? Int32 { return Int(value) }
                            return nil
                        }()
                        let incomingLevelOrder: Int? = {
                            if let value = level["order"] as? Int { return value }
                            if let value = level["order"] as? Int32 { return Int(value) }
                            return nil
                        }()
                        _ = try await container.rubricsRepository.saveLevel(
                            id: kotlinLong(levelId),
                            criterionId: savedCriterionId.int64Value,
                            name: levelName,
                            points: RubricBundleSyncMerge.points(
                                previous: existingLevel.map { Int32($0.points) } ?? 0,
                                incoming: incomingPoints,
                                keyPresent: pointsKeyPresent
                            ),
                            description: RubricBundleSyncMerge.optionalText(
                                previous: existingLevel?.description_,
                                incoming: level["description"] as? String,
                                keyPresent: levelDescriptionKeyPresent
                            ),
                            order: RubricBundleSyncMerge.order(
                                previous: existingLevel.map { Int32($0.order) } ?? 0,
                                incoming: incomingLevelOrder,
                                keyPresent: levelOrderKeyPresent
                            ),
                            updatedAtEpochMs: change.updatedAtEpochMs,
                            deviceId: change.deviceId,
                            syncVersion: 1
                        )
                    }
                }

            case "attendance":
                guard
                    let studentId = int64Value(payloadObject["studentId"]),
                    let classId = int64Value(payloadObject["classId"]),
                    let dateEpochMs = int64Value(payloadObject["dateEpochMs"]),
                    let status = payloadObject["status"] as? String
                else { continue }
                let sessionIdValue = int64Value(payloadObject["sessionId"]).flatMap { $0 > 0 ? $0 : nil }
                let existing: Attendance_?
                do {
                    let records = try await container.attendanceRepository.listAttendanceByDate(
                        classId: classId,
                        dateEpochMs: dateEpochMs
                    )
                    existing = records.first { record in
                        record.studentId == studentId && record.sessionId?.int64Value == sessionIdValue
                    } ?? records.first { record in
                        record.studentId == studentId
                    }
                } catch {
                    continue
                }
                let note = AttendanceSyncMerge.text(
                    previous: existing?.note ?? "",
                    incoming: payloadObject["note"] as? String,
                    keyPresent: payloadObject.keys.contains("note")
                )
                let hasIncident = AttendanceSyncMerge.flag(
                    previous: existing?.hasIncident ?? false,
                    incoming: payloadObject["hasIncident"] as? Bool,
                    keyPresent: payloadObject.keys.contains("hasIncident")
                )
                let followUpRequired = AttendanceSyncMerge.flag(
                    previous: existing?.followUpRequired ?? false,
                    incoming: payloadObject["followUpRequired"] as? Bool,
                    keyPresent: payloadObject.keys.contains("followUpRequired")
                )
                _ = try await container.attendanceRepository.saveAttendance(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    studentId: studentId,
                    classId: classId,
                    dateEpochMs: dateEpochMs,
                    status: status,
                    note: note,
                    hasIncident: hasIncident,
                    followUpRequired: followUpRequired,
                    sessionId: kotlinLong(sessionIdValue),
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "incident":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let title = payloadObject["title"] as? String,
                    let dateEpochMs = int64Value(payloadObject["dateEpochMs"])
                else { continue }
                let incomingId = int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }
                let existing: Incident?
                do {
                    if let incomingId {
                        existing = try await container.incidentsRepository.listIncidents(classId: classId)
                            .first { $0.id == incomingId }
                    } else {
                        existing = nil
                    }
                } catch {
                    continue
                }
                let detail = IncidentSyncMerge.optionalText(
                    previous: existing?.detail,
                    incoming: payloadObject["detail"] as? String,
                    keyPresent: payloadObject.keys.contains("detail")
                )
                let severity = IncidentSyncMerge.severity(
                    previous: existing?.severity,
                    incoming: payloadObject["severity"] as? String,
                    keyPresent: payloadObject.keys.contains("severity")
                )
                _ = try await container.incidentsRepository.saveIncident(
                    id: kotlinLong(incomingId),
                    classId: classId,
                    studentId: kotlinLong(int64Value(payloadObject["studentId"]).flatMap { $0 > 0 ? $0 : nil }),
                    title: title,
                    detail: detail,
                    severity: severity,
                    dateEpochMs: dateEpochMs,
                    authorUserId: nil,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "calendar_event":
                guard
                    let title = payloadObject["title"] as? String,
                    let startEpochMs = int64Value(payloadObject["startEpochMs"]),
                    let endEpochMs = int64Value(payloadObject["endEpochMs"])
                else { continue }
                let incomingId = int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }
                let existing: CalendarEvent?
                do {
                    if let incomingId {
                        existing = try await container.calendarRepository.listEvents(classId: nil)
                            .first { $0.id == incomingId }
                    } else {
                        existing = nil
                    }
                } catch {
                    continue
                }
                let description = CalendarEventSyncMerge.optionalText(
                    previous: existing?.description_,
                    incoming: payloadObject["description"] as? String,
                    keyPresent: payloadObject.keys.contains("description")
                )
                let classId = CalendarEventSyncMerge.optionalClassId(
                    previous: existing?.classId?.int64Value,
                    incoming: int64Value(payloadObject["classId"]),
                    keyPresent: payloadObject.keys.contains("classId")
                )
                _ = try await container.calendarRepository.saveEvent(
                    id: kotlinLong(incomingId),
                    classId: kotlinLong(classId),
                    title: title,
                    description: description,
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs,
                    externalProvider: payloadObject["externalProvider"] as? String,
                    externalId: payloadObject["externalId"] as? String,
                    authorUserId: nil,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )

            case "rubric_assessment":
                guard
                    let studentId = int64Value(payloadObject["studentId"]),
                    let evaluationId = int64Value(payloadObject["evaluationId"]),
                    let criterionId = int64Value(payloadObject["criterionId"]),
                    let levelId = int64Value(payloadObject["levelId"])
                else { continue }
                let resolvedScore = try await container.rubricsRepository.saveRubricAssessment(
                    studentId: studentId,
                    evaluationId: evaluationId,
                    criterionId: criterionId,
                    levelId: levelId,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                if let evaluation = try await container.evaluationsRepository.getEvaluation(evaluationId: evaluationId),
                   let classId = int64Value(evaluation.classId),
                   classId > 0 {
                    let columnId = try await container.notebookRepository.getColumnIdForEvaluation(evaluationId: evaluationId) ?? "eval_\(evaluationId)"
                    let allAssessments = try await container.rubricsRepository.listRubricAssessments(
                        studentId: studentId,
                        evaluationId: evaluationId
                    )
                    let selections = allAssessments
                        .map { "\($0.criterionId):\($0.levelId)" }
                        .sorted()
                        .joined(separator: ",")
                    try await container.notebookRepository.upsertGrade(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId,
                        evaluationId: kotlinLong(evaluationId),
                        numericValue: resolvedScore?.doubleValue ?? 0.0,
                        rubricSelections: selections.isEmpty ? nil : selections,
                        evidence: nil,
                        createdAtEpochMs: change.updatedAtEpochMs,
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                }

            case "session_journal":
                guard let planningSessionId = SessionJournalSyncCodec.shared.planningSessionId(payload: change.payload)?.int64Value,
                      planningSessionId > 0 else { continue }
                let existingJournal = try await container.sessionJournalRepository.getJournalForSession(
                    planningSessionId: planningSessionId
                )
                // Sin existing, un payload parcial vaciaría textos/puntuaciones del diario.
                guard let toSave = SessionJournalSyncCodec.shared.forLocalUpsert(
                    payload: change.payload,
                    localJournalId: existingJournal?.journal.id ?? 0,
                    existing: existingJournal
                ) else { continue }
                _ = try await container.sessionJournalRepository.saveJournalAggregate(aggregate: toSave)

            default:
                continue
            }
            // Si llegamos aquí, el upsert se aplicó (o quedó fuera antes de tiempo por
            // un guard interno). Retirar el tombstone es seguro/idempotente en ambos
            // casos: ya no bloquea futuros upserts legítimos de esta misma entidad.
            try? await container.syncTombstoneRepository.clearTombstone(entity: change.entity, entityId: change.id)
            } catch {
                // No abortar el pull completo por un único cambio defectuoso
                // (p.ej. entidad fuera de orden o payload parcial).
                failedCount += 1
                continue
            }
        }
        guard SyncLanApplyCloseCopy.isSuccessfulClose(failedCount: failedCount) else {
            let message = SyncLanApplyCloseCopy.failureStatusMessage(
                failedCount: failedCount,
                total: applyTotal
            )
            publishSyncState {
                $0.syncStatusMessage = message
            }
            throw NSError(
                domain: "Sync",
                code: -42,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func applyDeletedChange(change: LanSyncChange, payloadObject: [String: Any]) async throws {
        switch change.entity {
        case "academic_year":
            let yearId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if yearId > 0 {
                try? await container.academicYearsRepository.deleteArchivedAcademicYear(academicYearId: yearId)
            }
        case "student_deleted", "student":
            let studentId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if studentId > 0 {
                try await container.studentsRepository.deleteStudent(studentId: studentId)
            }
        case "evaluation":
            let evaluationId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if evaluationId > 0 {
                try await container.evaluationsRepository.deleteEvaluation(evaluationId: evaluationId)
            }
        case "weekly_slot":
            let slotId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if slotId > 0 {
                try await container.weeklyTemplateRepository.delete(slotId: slotId)
            }
        case "notebook_tab":
            let tabId = (payloadObject["id"] as? String) ?? change.id
            if !tabId.isEmpty {
                try await container.notebookRepository.deleteTab(tabId: tabId)
            }
        case "notebook_group":
            let groupId = int64Value(payloadObject["id"]) ?? Int64(change.id.replacingOccurrences(of: "group-", with: "")) ?? 0
            if groupId > 0 {
                try await container.notebookRepository.deleteWorkGroup(groupId: groupId)
            }
        case "notebook_group_member":
            // Formato "classId|tabId|groupId|studentId" o tombstone "group-member-classId-tabId-groupId-studentId".
            let rawId = change.id.hasPrefix("group-member-")
                ? String(change.id.dropFirst("group-member-".count))
                : change.id
            let idParts: [String] = rawId.contains("|")
                ? rawId.split(separator: "|").map(String.init)
                : rawId.split(separator: "-").map(String.init)
            guard
                let classId = int64Value(payloadObject["classId"]) ?? int64Value(payloadObject["class_id"]) ?? idParts[safe: 0].flatMap(Int64.init),
                let tabId = (payloadObject["tabId"] as? String) ?? (payloadObject["tab_id"] as? String) ?? idParts[safe: 1],
                let studentId = int64Value(payloadObject["studentId"]) ?? int64Value(payloadObject["student_id"]) ?? idParts[safe: 3].flatMap(Int64.init)
            else { break }
            try await container.notebookConfigRepository.clearStudentsFromWorkGroup(
                classId: classId,
                tabId: tabId,
                studentIds: [KotlinLong(value: studentId)]
            )
        case "notebook_column":
            let columnId = (payloadObject["id"] as? String) ?? change.id
            if !columnId.isEmpty {
                try await container.notebookRepository.deleteColumn(columnId: columnId)
            }
        case "notebook_instrument_template":
            let templateId = (payloadObject["id"] as? String) ?? change.id
            let columnId = templateId.hasPrefix("template_") ? String(templateId.dropFirst(9)) : templateId
            if let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId) {
                try await container.notebookInstrumentsRepository.saveTemplate(template: detail.template_, items: [])
            }
        case "notebook_instrument_response":
            if let classId = int64Value(payloadObject["classId"]),
               let studentId = int64Value(payloadObject["studentId"]),
               let columnId = payloadObject["columnId"] as? String,
               let itemId = payloadObject["itemId"] as? String {
                let loadedResponses: [NotebookInstrumentResponse]
                do {
                    loadedResponses = try await container.notebookInstrumentsRepository.listResponsesForCell(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId
                    )
                } catch {
                    break
                }
                guard let responses = InstrumentResponseMerge.removing(
                    existing: loadedResponses,
                    removeWhere: { $0.itemId == itemId }
                ) else { break }
                _ = try await container.notebookInstrumentsRepository.saveResponses(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    responses: responses,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
            }
        case "notebook_column_category":
            let categoryId = (payloadObject["id"] as? String) ?? change.id
            let classId = int64Value(payloadObject["classId"]) ?? notebookViewModel.currentClassId?.int64Value ?? 0
            if classId > 0 && !categoryId.isEmpty {
                let preserveColumns = (payloadObject["preserveColumns"] as? Bool) ?? true
                try await container.notebookRepository.deleteColumnCategory(classId: classId, categoryId: categoryId, preserveColumns: preserveColumns)
            }
        case "rubric_bundle":
            let rubricId = int64Value(payloadObject["rubricId"]) ?? Int64(change.id) ?? 0
            if rubricId > 0 {
                try await container.rubricsRepository.deleteRubric(rubricId: rubricId)
            }
        case "planning_session":
            let sessionId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if sessionId > 0 {
                try await container.plannerRepository.deleteSession(sessionId: sessionId)
            }
        case "session_journal":
            let planningSessionId = int64Value(payloadObject["planningSessionId"]) ?? Int64(change.id) ?? 0
            if planningSessionId > 0 {
                try await container.sessionJournalRepository.deleteJournalForSession(planningSessionId: planningSessionId)
            }
        case "teaching_unit":
            let unitId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if unitId > 0 {
                _ = try await container.plannerRepository.deleteTeachingUnit(unitId: unitId)
            }
        case "teacher_schedule_slot":
            let slotId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if slotId > 0 {
                try await container.teacherScheduleRepository.deleteScheduleSlot(slotId: slotId)
            }
        case "planner_evaluation_period":
            let periodId = int64Value(payloadObject["id"]) ?? Int64(change.id) ?? 0
            if periodId > 0 {
                try await container.teacherScheduleRepository.deleteEvaluationPeriod(periodId: periodId)
            }
        default:
            break
        }
    }

    private func orderedPulledChanges(_ changes: [LanSyncChange]) -> [LanSyncChange] {
        changes.sorted { lhs, rhs in
            let lhsPriority = syncApplyPriority(for: lhs.entity)
            let rhsPriority = syncApplyPriority(for: rhs.entity)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.updatedAtEpochMs != rhs.updatedAtEpochMs {
                return lhs.updatedAtEpochMs < rhs.updatedAtEpochMs
            }
            return lhs.id < rhs.id
        }
    }

    private func resolveNotebookColumnTabIds(
        rawTabIds: [String],
        incomingTitles: [String],
        existingTabs: [NotebookTab]
    ) -> [String] {
        guard !existingTabs.isEmpty else { return [] }

        let tabsById = Dictionary(
            existingTabs.map { ($0.id.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        var tabsByTitle: [String: String] = [:]
        for tab in existingTabs {
            let key = tab.title.lowercased()
            if tabsByTitle[key] == nil {
                tabsByTitle[key] = tab.id
            }
        }
        let candidateCount = max(rawTabIds.count, incomingTitles.count)
        var resolvedTabIds: [String] = []

        for index in 0..<candidateCount {
            if index < rawTabIds.count,
               let exactId = tabsById[rawTabIds[index].lowercased()] {
                appendResolvedTabId(exactId, into: &resolvedTabIds)
                continue
            }

            guard index < incomingTitles.count else { continue }
            if let matchingTabId = tabsByTitle[incomingTitles[index].lowercased()] {
                appendResolvedTabId(matchingTabId, into: &resolvedTabIds)
            }
        }

        return resolvedTabIds
    }

    private func appendResolvedTabId(_ tabId: String, into resolvedTabIds: inout [String]) {
        guard !resolvedTabIds.contains(tabId) else { return }
        resolvedTabIds.append(tabId)
    }

    private func parseDelimitedStringList(_ value: Any?) -> [String] {
        if let csv = value as? String {
            return csv
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else if let arr = value as? [String] {
            return arr
        } else {
            return []
        }
    }

    private func syncApplyPriority(for entity: String) -> Int {
        switch entity {
        case "academic_year":
            return 0
        case "class", "student", "rubric_bundle", "teaching_unit", "calendar_event", "teacher_schedule", "learning_situation":
            return 1
        case "evaluation", "weekly_slot", "teacher_schedule_slot", "planner_evaluation_period", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_group", "notebook_group_member", "learning_situation_version", "learning_situation_class_link", "learning_situation_link", "notebook_instrument_template":
            return 2
        case "class_roster", "attendance", "incident", "notebook_instrument_item":
            return 3
        case "grade", "notebook_cell", "rubric_assessment", "planning_session", "notebook_instrument_response":
            return 4
        case "session_journal":
            return 5
        case "student_deleted":
            return 5
        default:
            return 5
        }
    }


    func loadOrCreateLocalDeviceId() -> String {
        if let existingSecure = syncSecureStore.loadString(key: "sync.device.id"), !existingSecure.isEmpty {
            return existingSecure
        }
        if let legacy = UserDefaults.standard.string(forKey: "sync.device.id"), !legacy.isEmpty {
            syncSecureStore.saveString(legacy, key: "sync.device.id")
            UserDefaults.standard.removeObject(forKey: "sync.device.id")
            return legacy
        }
        let id = "ios-\(UUID().uuidString.prefix(8))"
        syncSecureStore.saveString(id, key: "sync.device.id")
        return id
    }

    func migrateLegacySyncSecretsFromUserDefaults() {
        if let legacyToken = UserDefaults.standard.string(forKey: "sync.token"), !legacyToken.isEmpty {
            syncSecureStore.saveString(legacyToken, key: "sync.token")
            UserDefaults.standard.removeObject(forKey: "sync.token")
        }
        if let legacyHost = UserDefaults.standard.string(forKey: "sync.host"), !legacyHost.isEmpty {
            syncSecureStore.saveString(legacyHost, key: "sync.host")
            UserDefaults.standard.removeObject(forKey: "sync.host")
        }
    }

    private func persistSyncSecrets() {
        if let token = syncToken {
            syncSecureStore.saveString(token, key: "sync.token")
        }
        if let host = pairedSyncHost {
            syncSecureStore.saveString(host, key: "sync.host")
        }
        if let sid = pairedServerId {
            syncSecureStore.saveString(sid, key: "sync.server.id")
        }
        if let fingerprint = pairedServerFingerprint {
            syncSecureStore.saveString(fingerprint, key: "sync.server.fingerprint")
        }
    }

    private func clearPersistedPairing() {
        syncToken = nil
        pairedSyncHost = nil
        pairedServerId = nil
        pairedServerFingerprint = nil
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        pendingChangesPersistenceTask?.cancel()
        pendingChangesPersistenceTask = nil
        syncEventListener.stop()
        syncSecureStore.delete(key: "sync.token")
        syncSecureStore.delete(key: "sync.host")
        syncSecureStore.delete(key: "sync.server.id")
        syncSecureStore.delete(key: "sync.server.fingerprint")
        // El cursor pertenece al servidor con el que estábamos emparejados; un Mac
        // distinto tiene su propio reloj/epoch y no debe heredar este valor.
        // (Los cambios pendientes de envío SÍ se conservan: son ediciones locales
        // reales aún no sincronizadas y deben llegar al próximo dispositivo emparejado.)
        lastSyncCursorEpochMs = 0
        UserDefaults.standard.removeObject(forKey: "sync.last.cursor")
    }

    func rebindPairedHostIfNeeded() {
        _ = recoverHostAfterNetworkChange(previousHost: pairedSyncHost)
    }

    private func recoverHostAfterNetworkChange(previousHost: String?) -> Bool {
        guard let matched = bestDiscoveredPeerForRecovery() else { return false }
        let previous = previousHost ?? pairedSyncHost
        var changed = false

        if pairedSyncHost != matched.host {
            pairedSyncHost = matched.host
            publishSyncState {
                $0.syncStatusMessage = "Host actualizado automáticamente: \(matched.host)"
            }
            changed = true
        }
        if (pairedServerId == nil || pairedServerId?.isEmpty == true), !matched.serverId.isEmpty {
            pairedServerId = matched.serverId
            changed = true
        }
        if (pairedServerFingerprint == nil || pairedServerFingerprint?.isEmpty == true), !matched.fingerprint.isEmpty {
            pairedServerFingerprint = matched.fingerprint
            changed = true
        }

        if changed {
            persistSyncSecrets()
            startSyncEventListenerIfPaired()
        }

        return changed && previous != matched.host
    }

    private func bestDiscoveredPeerForRecovery() -> LanDiscoveredPeer? {
        if let sid = pairedServerId, !sid.isEmpty,
           let byServerId = discoveredPeersByHost.values.first(where: { $0.serverId == sid }) {
            return byServerId
        }
        if let fingerprint = pairedServerFingerprint, !fingerprint.isEmpty,
           let byFingerprint = discoveredPeersByHost.values.first(where: { $0.fingerprint == fingerprint }) {
            return byFingerprint
        }
        return nil
    }

    nonisolated static func deduplicateDiscoveredPeers(_ peers: [LanDiscoveredPeer]) -> [LanDiscoveredPeer] {
        var peersByHost: [String: LanDiscoveredPeer] = [:]
        for peer in peers {
            if let existing = peersByHost[peer.host] {
                peersByHost[peer.host] = preferredDiscoveredPeer(existing, peer)
            } else {
                peersByHost[peer.host] = peer
            }
        }
        return peersByHost.values.sorted { lhs, rhs in
            if lhs.host == rhs.host {
                return lhs.identityScore > rhs.identityScore
            }
            return lhs.host < rhs.host
        }
    }

    nonisolated static func preferredDiscoveredPeer(_ lhs: LanDiscoveredPeer, _ rhs: LanDiscoveredPeer) -> LanDiscoveredPeer {
        if lhs.identityScore != rhs.identityScore {
            return lhs.identityScore >= rhs.identityScore ? lhs : rhs
        }
        if lhs.scheme != rhs.scheme {
            return lhs.scheme == "https" ? lhs : rhs
        }
        return lhs
    }

    func startAutoSyncLoop() {
        guard pairedSyncHost != nil, syncToken != nil else {
            autoSyncLoopTask?.cancel()
            autoSyncLoopTask = nil
            return
        }
        if let autoSyncLoopTask, !autoSyncLoopTask.isCancelled {
            return
        }
        autoSyncLoopTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.autoSyncLoopTask?.isCancelled ?? true {
                        self.autoSyncLoopTask = nil
                    }
                }
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.nextAutoSyncIntervalNanoseconds())
                    guard self.isAppInForeground else { continue }
                    guard self.pairedSyncHost != nil, self.syncToken != nil else { continue }
                    guard !AppleBackupService.shared.needsRestart else { continue }
                    #if os(macOS)
                    await self.checkLocalDbFileModification()
                    #endif
                    await self.syncNow(reason: "periodic", forceFullPull: false, silent: true)
                } catch {
                    // Evitamos romper el bucle por errores transitorios de red.
                }
            }
        }
    }

    private func restartAutoSyncLoopIfPaired() {
        guard pairedSyncHost != nil, syncToken != nil else {
            autoSyncLoopTask?.cancel()
            autoSyncLoopTask = nil
            localChangesNotifyTask?.cancel()
            localChangesNotifyTask = nil
            pendingLocalSseChanges.removeAll()
            syncEventListener.stop()
            return
        }
        startAutoSyncLoop()
        startSyncEventListenerIfPaired()
    }

    func startSyncEventListenerIfPaired() {
        guard let host = pairedSyncHost, let token = syncToken else {
            syncEventListener.stop()
            return
        }
        syncEventListener.start(
            host: host,
            token: token,
            pinnedFingerprint: pairedServerFingerprint
        ) { [weak self] event in
            guard let self else { return }
            guard let event else {
                await self.syncNow(reason: "sse_event", forceFullPull: false, silent: true)
                return
            }
            await self.applySyncEvent(event)
        }
    }

    // MARK: - Helper lifecycle notifications (macOS only)

    /// Called by MacCommandCenterCoordinator (via Notification) when the helper process
    /// has published a valid LAN IP address. At that point it is safe to start the
    /// event listener and trigger an initial sync.
    func notifyHelperReady(host: String, port: Int) {
        #if os(macOS)
        let normalizedHost = LanSyncClient.normalizeHost(host)
        guard !normalizedHost.isEmpty else { return }
        print("[Sync] helper ready at \(normalizedHost):\(port) — starting listener")
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = nil
        pendingLocalSseChanges.removeAll()
        syncNeedsAnotherPass = false
        syncEventListener.stop()
        pairedSyncHost = normalizedHost
        startSyncEventListenerIfPaired()
        startAutoSyncLoop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "helper_ready", forceFullPull: true, silent: true)
        }
        #endif
    }

    /// Called by MacCommandCenterCoordinator (via Notification) when the helper process
    /// has stopped. Stops the event listener and periodic sync loop without clearing
    /// the paired state, so the UI remains accurate.
    func notifyHelperStopped() {
        #if os(macOS)
        print("[Sync] helper stopped — suspending listener")
        syncEventListener.stop()
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = nil
        pendingLocalSseChanges.removeAll()
        syncNeedsAnotherPass = false
        pairedSyncHost = nil
        #endif
    }

    /// Detiene todo el trabajo en segundo plano que pueda tocar la base de
    /// datos: el bucle de auto-sync, los debounces de guardado (cambios
    /// locales, notas del cuaderno, snapshot de calificaciones) y el
    /// listener de eventos de sync. Se llama antes de cualquier operación
    /// que borre o sustituya los ficheros de la base de datos en disco
    /// (p.ej. el borrado nuclear de Ajustes → Zona de Riesgo): sin esto,
    /// una tarea en curso puede intentar leer/escribir un fichero que
    /// acaba de desaparecer y lanzar una excepción Kotlin que no está
    /// declarada `@Throws` en el contrato, y el runtime de Kotlin/Native
    /// la trata como fatal (aborta el proceso) en vez de propagarla como
    /// error de Swift capturable.
    func stopBackgroundSyncWork() {
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = nil
        pendingChangesPersistenceTask?.cancel()
        pendingChangesPersistenceTask = nil
        notebookSnapshotDebounceTask?.cancel()
        notebookSnapshotDebounceTask = nil
        pendingGradeSnapshotTask?.cancel()
        pendingGradeSnapshotTask = nil
        columnGradeSaveDebounceTask?.cancel()
        columnGradeSaveDebounceTask = nil
        pendingDebouncedColumnGrade = nil
        postSyncRefreshTask?.cancel()
        postSyncRefreshTask = nil
        syncEventListener.stop()
    }

    /// Vacía todas las tablas de la base con la conexión que ya está abierta.
    ///
    /// Existe para que el borrado total (`SettingsDangerZoneView`) deje de eliminar el
    /// fichero SQLite del disco por debajo del driver: eso invalidaba los descriptores
    /// del pool y abortaba el proceso. El contenedor es privado, así que la vista no
    /// puede llegar a él sin abrir un driver nuevo por su cuenta.
    func wipeAllDatabaseData() throws {
        try container.wipeAllData()
    }

    func wipeSelectiveDatabaseData(categories: Set<WipeCategory>) throws {
        try container.wipeSelectiveData(categories: categories)
    }

    /// Ruta de la base de datos activa. Se pide al bootstrap, que a su vez la pide al
    /// módulo que abre el driver: es la única fuente de verdad. Reconstruirla a mano aquí
    /// ya produjo dos rutas divergentes (macOS apuntaba a un fichero fantasma, e iOS a
    /// "MiGestor/" cuando su directorio real es "MiGestorKMPiOS/").
    private func getDatabaseURL() -> URL? {
        URL(fileURLWithPath: appleBootstrap.databasePath)
    }

    private func checkLocalDbFileModification() async {
        guard !AppleBackupService.shared.needsRestart else { return }
        guard let dbURL = getDatabaseURL() else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbURL.path)
            guard let modificationDate = attributes[.modificationDate] as? Date else { return }
            
            let isFirstCheck = lastCheckedDbModificationDate == .distantPast
            if isFirstCheck {
                lastCheckedDbModificationDate = modificationDate
                return
            }
            
            if modificationDate > lastCheckedDbModificationDate {
                let timeSinceLocalMutation = Date().timeIntervalSince(lastLocalMutationAt)
                if timeSinceLocalMutation > 1.5 {
                    await MainActor.run {
                        self.refreshCurrentNotebook()
                        Task(priority: .utility) { [weak self] in
                            guard let self else { return }
                            try? await self.refreshDashboard()
                            try? await self.refreshClasses()
                            try? await self.refreshStudentsDirectory()
                            try? await self.refreshRubrics()
                            try? await self.refreshRubricClassLinks()
                            try? await self.refreshPlanning()
                        }
                    }
                }
                lastCheckedDbModificationDate = modificationDate
            }
        } catch {
            // El archivo no existe o no se puede leer
        }
    }

    func triggerAutoSyncSoon(delayNanoseconds: UInt64 = 250_000_000) {
        guard pairedSyncHost != nil, syncToken != nil else { return }
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
                await self.syncNow(reason: "debounced_local_change", forceFullPull: false, silent: true)
            } catch {
                self.publishSyncState {
                    $0.syncStatusMessage = "Auto-sync pendiente (reconectando...)"
                }
            }
        }
    }

    func onAppDidBecomeActive() {
        isAppInForeground = true
        restartAutoSyncLoopIfPaired()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "foreground", forceFullPull: true, silent: true)
        }
    }

    func onAppDidEnterBackground() {
        isAppInForeground = false
        autoSyncDebounceTask?.cancel()
        autoSyncDebounceTask = nil
        autoSyncLoopTask?.cancel()
        autoSyncLoopTask = nil
        syncEventListener.stop()
        if NotebookColumnGradeSave.shouldPersistNow(.enterBackground) {
            flushAnyPendingColumnGradeSave()
        }
        // Cerrar la ventana justo después de "Borrar todos los datos" dispara
        // esta transición de scenePhase (macOS pasa a `.background` al perder
        // el último foco), y sin este guard se lanzaba un `Task` nuevo que
        // `stopBackgroundSyncWork()` no puede cancelar porque todavía no
        // existe en ese momento — mismo crash que la propia siembra de
        // fondo: `syncNow` toca repositorios Kotlin no declarados `@Throws`
        // sobre un fichero de base de datos que acaba de desaparecer.
        guard !AppleBackupService.shared.needsRestart else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(reason: "background_flush", forceFullPull: false, silent: true)
        }
    }

    func syncNow(reason: String, forceFullPull: Bool, silent: Bool) async {
        // Red de seguridad centralizada: `syncNow` tiene varios puntos de
        // entrada (arranque, primer plano, segundo plano, bucle de
        // auto-sync, listener SSE, helper listo...). Tras un borrado
        // nuclear (`needsRestart == true`) ninguno de ellos debe tocar la
        // base de datos, así que el guard vive aquí en vez de repetirlo en
        // cada llamante.
        guard !AppleBackupService.shared.needsRestart else { return }
        guard pairedSyncHost != nil, syncToken != nil else { return }
        guard !isPairingInFlight else { return }
        let now = Date()
        let latencyCriticalReason = reason == "sse_event" || reason == "debounced_local_change" || reason == "background_flush"

        if silent,
           !forceFullPull,
           !latencyCriticalReason,
           pendingOutboundChanges.isEmpty,
           now.timeIntervalSince(lastSuccessfulSyncAt) < 1.5,
           now.timeIntervalSince(lastSilentSyncAttemptAt) < 1.5 {
            return
        }

        if silent {
            lastSilentSyncAttemptAt = now
        }

        if isSyncInFlight {
            syncNeedsAnotherPass = true
            return
        }

        isSyncInFlight = true
        defer { isSyncInFlight = false }

        var shouldRunAnotherPass = false
        repeat {
            syncNeedsAnotherPass = false
            do {
                if !pendingOutboundChanges.isEmpty {
                    try await performPushSync(silent: true)
                }

                let now = Date()
                let shouldForceFullPull = forceFullPull || now.timeIntervalSince(lastFullPullAt) > 180
                try await performPullSync(
                    silent: true,
                    sinceEpochMsOverride: shouldForceFullPull ? 0 : nil
                )
                if shouldForceFullPull {
                    lastFullPullAt = now
                }
                lastSuccessfulSyncAt = now

                if pendingOutboundChanges.isEmpty {
                    Task { [weak self] in
                        await self?.checkSyncDivergence()
                    }
                }

                if !silent {
                    publishSyncState {
                        $0.syncStatusMessage = "Sincronizado (\(reason))"
                    }
                }
            } catch {
                if !silent {
                    let statusMessage = "Sync fallido (\(reason)): \(error.localizedDescription)"
                    publishSyncState {
                        $0.syncStatusMessage = statusMessage
                    }
                } else {
                    publishSyncState {
                        $0.syncStatusMessage = "Auto-sync pendiente (reconectando...)"
                    }
                }
            }

            shouldRunAnotherPass = syncNeedsAnotherPass
        } while shouldRunAnotherPass
    }

    private func nextAutoSyncIntervalNanoseconds() -> UInt64 {
        if !isAppInForeground {
            return 60_000_000_000 // 60s si está en background y la tarea aún no se detuvo
        }
        if !pendingOutboundChanges.isEmpty {
            return 1_200_000_000 // 1.2s para vaciar cambios pendientes
        }

        // Si el stream SSE está activamente conectado y recibiendo eventos en tiempo real,
        // no hacemos sondeo agresivo HTTP: solo un latido de seguridad cada 5 minutos.
        if syncEventListener.isConnected {
            return 300_000_000_000 // 5 minutos
        }

        // Si SSE está desconectado o en fallback, usamos intervalos adaptativos
        let now = Date()
        if now.timeIntervalSince(lastLocalMutationAt) < 10 {
            return 3_000_000_000 // 3s si hubo mutación local reciente
        }
        if now.timeIntervalSince(lastSuccessfulSyncAt) > 30 {
            return 15_000_000_000 // 15s si lleva tiempo sin sincronizar
        }
        return 30_000_000_000 // 30s en reposo sin SSE
    }

    private func runSyncOperationWithTimeout<T>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw NSError(
                    domain: "Sync",
                    code: -206,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Tiempo de espera agotado. Comprueba que la app macOS esté abierta y en la misma red."
                    ]
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

enum NotebookSyncScope {
    static func sendsOnlyEditedCell(_ type: NotebookColumnType) -> Bool {
        switch type {
        case .numeric, .text, .check, .icon, .ordinal, .attendance:
            return true
        default:
            return false
        }
    }
}

enum LanSyncRefreshPlan {
    struct Steps: Equatable {
        var classes = false
        var students = false
        var rubrics = false
        var planning = false
        var notebookEntities: Set<String> = []
    }

    static func steps(entities: Set<String>) -> Steps {
        let notebookEntities: Set<String> = [
            "grade", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_cell",
            "rubric_assessment", "student", "class", "class_roster", "evaluation", "notebook_group",
            "notebook_group_member", "notebook_instrument_template", "notebook_instrument_item",
            "notebook_instrument_response"
        ]
        return Steps(
            classes: !entities.isDisjoint(with: ["class", "academic_year"]),
            students: !entities.isDisjoint(with: ["student", "class_roster", "class"]),
            rubrics: !entities.isDisjoint(with: ["rubric_bundle", "rubric_assessment"]),
            planning: !entities.isDisjoint(with: [
                "planning_session", "teaching_unit", "teacher_schedule", "teacher_schedule_slot",
                "planner_evaluation_period", "session_journal", "calendar_event", "weekly_slot"
            ]),
            notebookEntities: notebookEntities
        )
    }
}

fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
