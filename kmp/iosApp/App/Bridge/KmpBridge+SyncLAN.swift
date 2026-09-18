import Foundation
import MiGestorKit
import Security
import CryptoKit

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
        do {
            try await performPullSync(silent: false)
        } catch {
            publishSyncState {
                $0.syncStatusMessage = "Pull manual fallido: \(error.localizedDescription)"
            }
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
                try await self.refreshClasses()
                guard !Task.isCancelled else { return }
                try await self.refreshStudentsDirectory()
                guard !Task.isCancelled else { return }
                try await self.refreshRubrics()
                guard !Task.isCancelled else { return }
                try await self.refreshRubricClassLinks()
                guard !Task.isCancelled else { return }
                try await self.refreshPlanning()
                guard !Task.isCancelled else { return }

                // Solo refrescar el cuaderno si alguno de los cambios sincronizados
                // afecta a entidades del cuaderno (grades, columnas, celdas, rúbricas).
                // Esto evita recargas innecesarias cuando solo cambian clases o alumnos.
                let notebookEntityTypes: Set<String> = [
                    "grade", "notebook_tab", "notebook_column", "notebook_column_category", "notebook_cell", "rubric_assessment", "student", "class", "class_roster", "evaluation", "notebook_group", "notebook_group_member", "notebook_instrument_template", "notebook_instrument_item", "notebook_instrument_response"
                ]
                let hasNotebookChangesFromRemote = capturedChanges.contains {
                    notebookEntityTypes.contains($0.entity) && $0.deviceId != capturedLocalDeviceId
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
        // Un round-trip exitoso significa que el servidor ya resolvió cada cambio
        // del lote (aplicado, ignorado por LWW o rechazado por payload inválido).
        // Reintentar un ignored/failed sin una edición local más reciente nunca
        // tendría éxito, así que soltamos siempre el snapshot enviado en vez de
        // condicionar a `applied > 0` — de lo contrario un lote totalmente
        // ignorado reintentaría para siempre y "pendientes" nunca bajaría a 0.
        // Solo quitamos las entradas que coinciden exactamente con lo enviado:
        // si el mismo entity/id se volvió a editar durante el `await`, la entrada
        // más nueva en la cola no será igual (Equatable) al snapshot y se conserva.
        pendingOutboundChanges.removeAll { sentChanges.contains($0) }
        persistPendingChanges()
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
            let statusMessage = ack.desktopAuthoritative
                ? "macOS prevalece; cambios locales descartados"
                : "Push OK (\(ack.applied) aplicados)"
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
        for (index, change) in orderedChanges.enumerated() {
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
            let payloadData = change.payload.data(using: .utf8) ?? Data()
            let payloadObject = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]

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
                    let name = payloadObject["name"] as? String,
                    let startEpochMs = int64Value(payloadObject["startEpochMs"]),
                    let endEpochMs = int64Value(payloadObject["endEpochMs"])
                else { continue }
                _ = try await container.academicYearsRepository.upsertAcademicYear(
                    id: yearId,
                    centerId: int64Value(payloadObject["centerId"]) ?? 1,
                    name: name,
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs,
                    status: payloadObject["status"] as? String ?? "ACTIVE",
                    isActive: payloadObject["isActive"] as? Bool ?? false,
                    archivedAtEpochMs: kotlinLong(positiveInt64Value(payloadObject["archivedAtEpochMs"])),
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
                _ = try await container.classesRepository.saveClass(
                    id: kotlinLong(classId > 0 ? classId : nil),
                    name: name,
                    course: Int32(course),
                    description: payloadObject["description"] as? String,
                    centerId: kotlinLong(positiveInt64Value(payloadObject["centerId"])),
                    academicYearId: kotlinLong(positiveInt64Value(payloadObject["academicYearId"])),
                    stageCycleId: kotlinLong(positiveInt64Value(payloadObject["stageCycleId"])),
                    subjectId: kotlinLong(positiveInt64Value(payloadObject["subjectId"])),
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
                _ = try await container.studentsRepository.saveStudent(
                    id: kotlinLong(studentId > 0 ? studentId : nil),
                    firstName: firstName,
                    lastName: lastName,
                    email: payloadObject["email"] as? String,
                    photoPath: payloadObject["photoPath"] as? String,
                    isInjured: payloadObject["isInjured"] as? Bool ?? false,
                    sex: studentSex(from: payloadObject["sex"]),
                    sexSource: studentSexSource(from: payloadObject["sexSource"]),
                    birthDate: localDate(from: payloadObject["birthDate"]),
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
                    let type = payloadObject["type"] as? String,
                    let weight = doubleValue(payloadObject["weight"])
                else { continue }
                let evaluationId = int64Value(payloadObject["id"]) ?? 0
                let rubricId = int64Value(payloadObject["rubricId"])
                _ = try await container.evaluationsRepository.saveEvaluation(
                    id: kotlinLong(evaluationId > 0 ? evaluationId : nil),
                    classId: classId,
                    code: code,
                    name: name,
                    type: type,
                    weight: weight,
                    formula: payloadObject["formula"] as? String,
                    rubricId: kotlinLong(rubricId),
                    description: payloadObject["description"] as? String,
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
                    try await container.gradesRepository.upsertGrade(
                        classId: classId,
                        studentId: studentId,
                        columnId: columnId,
                        evaluationId: kotlinLong(evaluationIdValue),
                        value: doubleValue(payloadObject["value"]).map { KotlinDouble(value: $0) },
                        evidence: payloadObject["evidence"] as? String,
                        evidencePath: payloadObject["evidencePath"] as? String,
                        rubricSelections: payloadObject["rubricSelections"] as? String,
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
                _ = try await container.weeklyTemplateRepository.insert(
                    slot: WeeklySlotTemplate(
                        id: int64Value(payloadObject["id"]) ?? 0,
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
                let order = payloadObject["order"] as? Int ?? 0
                let parentTabId = (payloadObject["parentTabId"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let description = (payloadObject["description"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
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
                        order: Int32(order),
                        parentTabId: parentTabId,
                        fixedColumnWidth: nil,
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
                let order = (payloadObject["order"] as? Int) ?? (int64Value(payloadObject["order"]).map { Int($0) }) ?? 0
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                let trace = AuditTrace(
                    authorUserId: nil,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    associatedGroupId: nil,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                _ = try await container.notebookRepository.saveWorkGroup(
                    classId: classId,
                    workGroup: NotebookWorkGroup(
                        id: groupId,
                        classId: classId,
                        tabId: tabId,
                        name: name,
                        order: Int32(order),
                        learningSituationId: nil,
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

                let type = notebookColumnType(
                    from: (payloadObject["type"] as? String) ?? (payloadObject["column_type"] as? String)
                )
                let evaluationIdValue = int64Value(payloadObject["evaluationId"]).flatMap { $0 > 0 ? $0 : nil }
                let rubricId = int64Value(payloadObject["rubricId"]).flatMap { $0 > 0 ? $0 : nil }
                
                let resolvedColumnId: String = {
                    if let evalId = evaluationIdValue, evalId > 0 { return "eval_\(evalId)" }
                    return payloadObject["id"] as? String ?? UUID().uuidString
                }()

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

                let sharedAcrossTabs = boolValue(payloadObject["sharedAcrossTabs"] ?? payloadObject["shared_across_tabs"]) ?? false
                let finalTabIds = sharedAcrossTabs ? existingTabs.map { $0.id } : resolvedTabIds
                let colorHex = normalizeHexColor(payloadObject["colorHex"] as? String)
                let formula = payloadObject["formula"] as? String
                let categoryIdRaw = (payloadObject["categoryId"] as? String) ?? (payloadObject["category_id"] as? String)
                let categoryId = categoryIdRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? categoryIdRaw : nil

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
                            weight: doubleValue(payloadObject["weight"]) ?? 1.0,
                            formula: payloadObject["formula"] as? String,
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

                try await container.notebookRepository.saveColumn(
                    classId: classId,
                    column: NotebookColumnDefinition(
                        id: resolvedColumnId,
                        title: title,
                        type: type,
                        categoryKind: notebookCategoryKind(payloadObject["categoryKind"] as? String),
                        instrumentKind: notebookInstrumentKind(payloadObject["instrumentKind"] as? String),
                        inputKind: notebookInputKind(payloadObject["inputKind"] as? String),
                        evaluationId: kotlinLong(evaluationIdValue),
                        rubricId: kotlinLong(rubricId),
                        formula: formula,
                        weight: doubleValue(payloadObject["weight"]) ?? 1.0,
                        dateEpochMs: kotlinLong(int64Value(payloadObject["dateEpochMs"] ?? payloadObject["date_epoch_ms"])),
                        unitOrSituation: payloadObject["unitOrSituation"] as? String ?? payloadObject["unit_name"] as? String,
                        competencyCriteriaIds: longList(payloadObject["competencyCriteriaIds"] ?? payloadObject["competency_criteria_ids_csv"]),
                        scaleKind: notebookScaleKind(payloadObject["scaleKind"] as? String),
                        tabIds: finalTabIds,
                        sessions: [],
                        sharedAcrossTabs: sharedAcrossTabs,
                        colorHex: colorHex,
                        iconName: payloadObject["iconName"] as? String ?? payloadObject["icon_name"] as? String,
                        order: Int32(payloadObject["order"] as? Int ?? -1),
                        widthDp: doubleValue(payloadObject["widthDp"] ?? payloadObject["width_dp"]) ?? 0.0,
                        categoryId: categoryId,
                        ordinalLevels: [],
                        availableIcons: [],
                        countsTowardAverage: boolValue(payloadObject["countsTowardAverage"] ?? payloadObject["counts_toward_average"]) ?? true,
                        isPinned: boolValue(payloadObject["isPinned"] ?? payloadObject["is_pinned"]) ?? false,
                        isHidden: boolValue(payloadObject["isHidden"] ?? payloadObject["is_hidden"]) ?? false,
                        visibility: notebookColumnVisibility(payloadObject["visibility"] as? String),
                        isLocked: boolValue(payloadObject["isLocked"] ?? payloadObject["is_locked"]) ?? false,
                        isTemplate: boolValue(payloadObject["isTemplate"] ?? payloadObject["is_template"]) ?? false,
                        emptyCellPolicy: .excludeFromAverage,
                        trace: trace
                    )
                )

            case "notebook_cell":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let studentId = int64Value(payloadObject["studentId"]),
                    let columnId = payloadObject["columnId"] as? String
                else { continue }

                let textValue = payloadObject["textValue"] as? String
                let boolValue = payloadObject["boolValue"] as? Bool
                let iconValue = payloadObject["iconValue"] as? String
                let ordinalValue = payloadObject["ordinalValue"] as? String
                let note = payloadObject["note"] as? String
                let colorHex = normalizeHexColor(payloadObject["colorHex"] as? String)
                let attachmentUris = (payloadObject["attachmentUris"] as? [String]) ?? []

                try await container.notebookRepository.saveCell(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    textValue: textValue?.isEmpty == true ? nil : textValue,
                    boolValue: boolValue.map { KotlinBoolean(value: $0) },
                    iconValue: iconValue?.isEmpty == true ? nil : iconValue,
                    ordinalValue: ordinalValue?.isEmpty == true ? nil : ordinalValue,
                    note: note?.isEmpty == true ? nil : note,
                    colorHex: colorHex?.isEmpty == true ? nil : colorHex,
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
                let existingItems = (try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: columnId))?.items ?? []
                try await container.notebookInstrumentsRepository.saveTemplate(template: template, items: existingItems)

            case "notebook_instrument_item":
                guard
                    let id = payloadObject["id"] as? String,
                    let templateId = payloadObject["templateId"] as? String,
                    let itemKey = payloadObject["itemKey"] as? String,
                    let title = payloadObject["title"] as? String
                else { continue }

                let itemTypeStr = (payloadObject["itemType"] as? String) ?? "scale14"
                let itemType = notebookInstrumentItemType(itemTypeStr)
                let optionsCsv = (payloadObject["optionsCsv"] as? String) ?? ""
                let options = optionsCsv.split(separator: "|").map(String.init).filter { !$0.isEmpty }
                let required = boolValue(payloadObject["required"]) ?? true
                let sortOrder = int64Value(payloadObject["sortOrder"]) ?? 0
                let helpText = payloadObject["helpText"] as? String
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)

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
                let targetColId = templateId.hasPrefix("template_") ? String(templateId.dropFirst(9)) : templateId
                if let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: targetColId) {
                    var items = detail.items.filter { $0.id != id }
                    items.append(item)
                    items.sort { $0.order < $1.order }
                    try await container.notebookInstrumentsRepository.saveTemplate(template: detail.template_, items: items)
                }

            case "notebook_instrument_response":
                guard
                    let classId = int64Value(payloadObject["classId"]),
                    let studentId = int64Value(payloadObject["studentId"]),
                    let columnId = payloadObject["columnId"] as? String,
                    let itemId = payloadObject["itemId"] as? String
                else { continue }

                let textValue = payloadObject["valueText"] as? String
                let boolVal = boolValue(payloadObject["valueBool"])
                let numValue = (payloadObject["valueNumber"] as? String) ?? ""

                var responses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(classId: classId, studentId: studentId, columnId: columnId)) ?? []
                responses.removeAll { $0.itemId == itemId }
                responses.append(NotebookInstrumentResponse(
                    classId: classId,
                    studentId: studentId,
                    columnId: columnId,
                    itemId: itemId,
                    textValue: textValue ?? "",
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
                ))
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
                let unit = TeachingUnit(
                    id: int64Value(payloadObject["id"]) ?? 0,
                    name: name,
                    description: payloadObject["description"] as? String ?? "",
                    colorHex: normalizeHexColor(payloadObject["colorHex"] as? String) ?? "#4A90D9",
                    groupId: kotlinLong(int64Value(payloadObject["groupId"])),
                    schoolClassId: kotlinLong(int64Value(payloadObject["schoolClassId"])),
                    startDate: nil,
                    endDate: nil
                )
                _ = try await container.plannerRepository.upsertTeachingUnit(unit: unit)

            case "learning_situation":
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSituation(
                    situation: LearningSituation(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        title: payloadObject["title"] as? String ?? "Situación",
                        stageLabel: payloadObject["stageLabel"] as? String ?? "",
                        courseLabel: payloadObject["courseLabel"] as? String ?? "",
                        subjectLabel: payloadObject["subjectLabel"] as? String ?? "",
                        termLabel: payloadObject["termLabel"] as? String ?? "",
                        centerLabel: payloadObject["centerLabel"] as? String ?? "",
                        sessionCount: Int32(int64Value(payloadObject["sessionCount"]) ?? 0),
                        challenge: payloadObject["challenge"] as? String ?? "",
                        finalProduct: payloadObject["finalProduct"] as? String ?? "",
                        payloadJson: payloadObject["payloadJson"] as? String ?? "{}",
                        status: (payloadObject["status"] as? String == "DRAFT") ? .draft : .active,
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_version":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let hash = payloadObject["sha256"] as? String else { continue }
                let localPath = await downloadLearningSituationDocumentIfNeeded(sha256: hash)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveVersion(
                    version: LearningSituationVersion(
                        id: 0,
                        learningSituationId: situationId,
                        versionNumber: Int32(int64Value(payloadObject["versionNumber"]) ?? 0),
                        originalFileName: payloadObject["originalFileName"] as? String ?? "\(hash).docx",
                        sha256: hash,
                        localPath: localPath,
                        sizeBytes: int64Value(payloadObject["sizeBytes"]) ?? 0,
                        payloadJson: payloadObject["payloadJson"] as? String ?? "{}",
                        warningsJson: payloadObject["warningsJson"] as? String ?? "[]",
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "learning_situation_sequence_version":
                guard let situationId = int64Value(payloadObject["learningSituationId"]),
                      let hash = payloadObject["sha256"] as? String else { continue }
                let localPath = await downloadLearningSituationDocumentIfNeeded(sha256: hash)
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSessionSequenceVersion(
                    version: LearningSituationSessionSequenceVersion(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        learningSituationId: situationId,
                        versionNumber: Int32(int64Value(payloadObject["versionNumber"]) ?? 0),
                        originalFileName: payloadObject["originalFileName"] as? String ?? "\(hash).docx",
                        sha256: hash,
                        localPath: localPath,
                        sizeBytes: int64Value(payloadObject["sizeBytes"]) ?? 0,
                        payloadJson: payloadObject["payloadJson"] as? String ?? "{}",
                        warningsJson: payloadObject["warningsJson"] as? String ?? "[]",
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
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveSessionPlan(
                    plan: LearningSituationSessionPlan(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        learningSituationId: situationId,
                        sequenceVersionId: sequenceVersionId,
                        sessionNumber: Int32(int64Value(payloadObject["sessionNumber"]) ?? 0),
                        sourceLabel: payloadObject["sourceLabel"] as? String ?? "",
                        title: title,
                        sessionType: payloadObject["sessionType"] as? String ?? "",
                        effectiveMinutes: Int32(int64Value(payloadObject["effectiveMinutes"]) ?? 0),
                        objective: payloadObject["objective"] as? String ?? "",
                        criteriaJson: payloadObject["criteriaJson"] as? String ?? "[]",
                        material: payloadObject["material"] as? String ?? "",
                        developmentJson: payloadObject["developmentJson"] as? String ?? "[]",
                        adaptationsJson: payloadObject["adaptationsJson"] as? String ?? "[]",
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
                      let kindName = payloadObject["kind"] as? String,
                      let resourceId = payloadObject["resourceId"] as? String else { continue }
                let kind: LearningSituationResourceKind
                switch kindName {
                case "TEACHING_UNIT": kind = .teachingUnit
                case "PLANNING_SESSION": kind = .planningSession
                case "EVALUATION": kind = .evaluation
                case "RUBRIC": kind = .rubric
                default: kind = .notebookColumn
                }
                let updatedAt = Instant.companion.fromEpochMilliseconds(epochMilliseconds: change.updatedAtEpochMs)
                _ = try await container.learningSituationsRepository.saveLinkedResource(
                    resource: LearningSituationLinkedResource(
                        id: 0,
                        learningSituationId: situationId,
                        kind: kind,
                        resourceId: resourceId,
                        classId: int64Value(payloadObject["classId"]).map { KotlinLong(value: $0) },
                        label: payloadObject["label"] as? String ?? "",
                        trace: AuditTrace(
                            authorUserId: nil, createdAt: updatedAt, updatedAt: updatedAt,
                            associatedGroupId: nil, deviceId: change.deviceId, syncVersion: 1
                        )
                    )
                )

            case "planning_session":
                let sessionId = int64Value(payloadObject["id"]) ?? 0
                let teachingUnitId = int64Value(payloadObject["teachingUnitId"]) ?? 0
                let dayOfWeek = payloadObject["dayOfWeek"] as? Int ?? 1
                let period = payloadObject["period"] as? Int ?? 1
                let weekNumber = payloadObject["weekNumber"] as? Int ?? 1
                let year = payloadObject["year"] as? Int ?? 2026
                let statusRaw = (payloadObject["status"] as? String ?? "PLANNED").uppercased()
                let status: SessionStatus
                switch statusRaw {
                case "IN_PROGRESS":
                    status = .inProgress
                case "COMPLETED":
                    status = .completed
                case "CANCELLED":
                    status = .cancelled
                default:
                    status = .planned
                }
                let session = PlanningSession(
                    id: sessionId,
                    teachingUnitId: teachingUnitId,
                    teachingUnitName: payloadObject["teachingUnitName"] as? String ?? "Unidad",
                    teachingUnitColor: payloadObject["teachingUnitColor"] as? String ?? "#4A90D9",
                    groupId: int64Value(payloadObject["groupId"]) ?? 0,
                    groupName: payloadObject["groupName"] as? String ?? "",
                    dayOfWeek: Int32(dayOfWeek),
                    period: Int32(period),
                    weekNumber: Int32(weekNumber),
                    year: Int32(year),
                    objectives: payloadObject["objectives"] as? String ?? "",
                    activities: payloadObject["activities"] as? String ?? "",
                    evaluation: payloadObject["evaluation"] as? String ?? "",
                    linkedAssessmentIdsCsv: payloadObject["linkedAssessmentIdsCsv"] as? String ?? "",
                    teacherScheduleSlotId: int64Value(payloadObject["teacherScheduleSlotId"]).map { KotlinLong(value: $0) },
                    startTime: payloadObject["startTime"] as? String,
                    endTime: payloadObject["endTime"] as? String,
                    learningSituationSessionPlanId: int64Value(payloadObject["learningSituationSessionPlanId"]).map { KotlinLong(value: $0) },
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
                let schedule = TeacherSchedule(
                    id: int64Value(payloadObject["id"]) ?? 0,
                    ownerUserId: int64Value(payloadObject["ownerUserId"]) ?? 1,
                    academicYearId: int64Value(payloadObject["academicYearId"]) ?? 1,
                    name: payloadObject["name"] as? String ?? "Agenda docente",
                    startDateIso: payloadObject["startDateIso"] as? String ?? "",
                    endDateIso: payloadObject["endDateIso"] as? String ?? "",
                    activeWeekdaysCsv: payloadObject["activeWeekdaysCsv"] as? String ?? "1,2,3,4,5",
                    trace: AuditTrace(
                        authorUserId: kotlinLong(int64Value(payloadObject["authorUserId"])),
                        createdAt: Instant.companion.fromEpochMilliseconds(
                            epochMilliseconds: int64Value(payloadObject["createdAtEpochMs"]) ?? change.updatedAtEpochMs
                        ),
                        updatedAt: updatedAt,
                        associatedGroupId: kotlinLong(int64Value(payloadObject["associatedGroupId"])),
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                )
                _ = try await container.teacherScheduleRepository.saveSchedule(schedule: schedule)

            case "teacher_schedule_slot":
                guard
                    let teacherScheduleId = int64Value(payloadObject["teacherScheduleId"]),
                    let schoolClassId = int64Value(payloadObject["schoolClassId"]),
                    let startTime = payloadObject["startTime"] as? String,
                    let endTime = payloadObject["endTime"] as? String
                else { continue }
                _ = try await container.teacherScheduleRepository.saveScheduleSlot(
                    slot: TeacherScheduleSlot(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        teacherScheduleId: teacherScheduleId,
                        schoolClassId: schoolClassId,
                        subjectLabel: payloadObject["subjectLabel"] as? String ?? "",
                        unitLabel: (payloadObject["unitLabel"] as? String)?.nilIfEmpty,
                        dayOfWeek: Int32(int64Value(payloadObject["dayOfWeek"]) ?? 1),
                        startTime: startTime,
                        endTime: endTime,
                        weeklyTemplateId: kotlinLong(int64Value(payloadObject["weeklyTemplateId"]))
                    )
                )

            case "planner_evaluation_period":
                guard
                    let teacherScheduleId = int64Value(payloadObject["teacherScheduleId"])
                else { continue }
                _ = try await container.teacherScheduleRepository.saveEvaluationPeriod(
                    period: PlannerEvaluationPeriod(
                        id: int64Value(payloadObject["id"]) ?? 0,
                        teacherScheduleId: teacherScheduleId,
                        name: payloadObject["name"] as? String ?? "",
                        startDateIso: payloadObject["startDateIso"] as? String ?? "",
                        endDateIso: payloadObject["endDateIso"] as? String ?? "",
                        sortOrder: Int32(int64Value(payloadObject["sortOrder"]) ?? 0)
                    )
                )

            case "rubric_bundle":
                guard let rubricName = payloadObject["name"] as? String else { continue }
                let rubricId = int64Value(payloadObject["rubricId"])
                let savedRubricId = try await container.rubricsRepository.saveRubric(
                    id: kotlinLong(rubricId),
                    name: rubricName,
                    description: payloadObject["description"] as? String,
                    classId: int64Value(payloadObject["classId"]).map { KotlinLong(value: $0) },
                    teachingUnitId: int64Value(payloadObject["teachingUnitId"]).map { KotlinLong(value: $0) },
                    createdAtEpochMs: change.updatedAtEpochMs,
                    updatedAtEpochMs: change.updatedAtEpochMs,
                    deviceId: change.deviceId,
                    syncVersion: 1
                )
                let criteria = payloadObject["criteria"] as? [[String: Any]] ?? []
                for criterion in criteria {
                    guard let criterionDescription = criterion["description"] as? String else { continue }
                    let criterionId = int64Value(criterion["id"])
                    let savedCriterionId = try await container.rubricsRepository.saveCriterion(
                        id: kotlinLong(criterionId),
                        rubricId: savedRubricId.int64Value,
                        description: criterionDescription,
                        weight: doubleValue(criterion["weight"]) ?? 1.0,
                        order: criterion["order"] as? Int32 ?? Int32(criterion["order"] as? Int ?? 0),
                        updatedAtEpochMs: change.updatedAtEpochMs,
                        deviceId: change.deviceId,
                        syncVersion: 1
                    )
                    let levels = criterion["levels"] as? [[String: Any]] ?? []
                    for level in levels {
                        guard let levelName = level["name"] as? String else { continue }
                        _ = try await container.rubricsRepository.saveLevel(
                            id: kotlinLong(int64Value(level["id"])),
                            criterionId: savedCriterionId.int64Value,
                            name: levelName,
                            points: level["points"] as? Int32 ?? Int32(level["points"] as? Int ?? 0),
                            description: level["description"] as? String,
                            order: level["order"] as? Int32 ?? Int32(level["order"] as? Int ?? 0),
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
                _ = try await container.attendanceRepository.saveAttendance(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    studentId: studentId,
                    classId: classId,
                    dateEpochMs: dateEpochMs,
                    status: status,
                    note: payloadObject["note"] as? String ?? "",
                    hasIncident: payloadObject["hasIncident"] as? Bool ?? false,
                    followUpRequired: payloadObject["followUpRequired"] as? Bool ?? false,
                    sessionId: kotlinLong(int64Value(payloadObject["sessionId"]).flatMap { $0 > 0 ? $0 : nil }),
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
                _ = try await container.incidentsRepository.saveIncident(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    classId: classId,
                    studentId: kotlinLong(int64Value(payloadObject["studentId"]).flatMap { $0 > 0 ? $0 : nil }),
                    title: title,
                    detail: payloadObject["detail"] as? String,
                    severity: payloadObject["severity"] as? String ?? "low",
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
                _ = try await container.calendarRepository.saveEvent(
                    id: kotlinLong(int64Value(payloadObject["id"]).flatMap { $0 > 0 ? $0 : nil }),
                    classId: kotlinLong(int64Value(payloadObject["classId"]).flatMap { $0 > 0 ? $0 : nil }),
                    title: title,
                    description: payloadObject["description"] as? String,
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
                continue
            }
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
                var responses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(classId: classId, studentId: studentId, columnId: columnId)) ?? []
                responses.removeAll { $0.itemId == itemId }
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

fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
