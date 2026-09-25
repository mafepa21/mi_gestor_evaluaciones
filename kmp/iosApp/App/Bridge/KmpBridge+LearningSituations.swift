//
//  KmpBridge+LearningSituations.swift
//  MiGestorKMP
//
//  Created for modularization of KmpBridge.
//

import Foundation
import Combine
import MiGestorKit
import SwiftUI
import CryptoKit

@MainActor
extension KmpBridge {
    func loadTemplates(kind: ConfigTemplateKind? = nil) async throws -> [ConfigTemplate] {
        try await container.configurationTemplateRepository.listTemplates(kind: kind)
    }

    func loadTemplateVersions(templateId: Int64) async throws -> [ConfigTemplateVersion] {
        try await container.configurationTemplateRepository.listTemplateVersions(templateId: templateId)
    }

    func learningSituations() async throws -> [LearningSituation] {
        try await container.learningSituationsRepository.listSituations()
    }

    func deleteLearningSituation(id: Int64) async throws {
        try await container.learningSituationsRepository.deleteSituation(id: id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: ["id": id],
            op: "delete"
        )
    }

    func updateLearningSituationStatus(id: Int64, status: LearningSituationStatus) async throws {
        guard let situation = try await container.learningSituationsRepository.getSituation(id: id) else {
            throw NSError(domain: "LearningSituations", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se encontró la situación para actualizar su estado."])
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let updatedTrace = situation.trace.doCopy(
            authorUserId: situation.trace.authorUserId,
            createdAt: situation.trace.createdAt,
            updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            associatedGroupId: situation.trace.associatedGroupId,
            deviceId: localDeviceId,
            syncVersion: situation.trace.syncVersion + 1
        )
        let updated = situation.doCopy(
            id: situation.id,
            title: situation.title,
            stageLabel: situation.stageLabel,
            courseLabel: situation.courseLabel,
            subjectLabel: situation.subjectLabel,
            termLabel: situation.termLabel,
            centerLabel: situation.centerLabel,
            sessionCount: situation.sessionCount,
            challenge: situation.challenge,
            finalProduct: situation.finalProduct,
            payloadJson: situation.payloadJson,
            status: status,
            trace: updatedTrace
        )
        _ = try await container.learningSituationsRepository.saveSituation(situation: updated)
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": situation.id, "title": situation.title, "stageLabel": situation.stageLabel,
                "courseLabel": situation.courseLabel, "subjectLabel": situation.subjectLabel,
                "termLabel": situation.termLabel, "centerLabel": situation.centerLabel,
                "sessionCount": situation.sessionCount, "challenge": situation.challenge,
                "finalProduct": situation.finalProduct, "payloadJson": situation.payloadJson,
                "status": status.name
            ]
        )
    }

    func learningSituationVersions(id: Int64) async throws -> [LearningSituationVersion] {

        try await container.learningSituationsRepository.listVersions(learningSituationId: id)
    }

    func learningSituationClassLinks(id: Int64) async throws -> [LearningSituationClassLink] {
        try await container.learningSituationsRepository.listClassLinks(learningSituationId: id)
    }

    /// Bulk read used by the iPad/Mac Situaciones, Cuaderno and Planner surfaces.
    /// Keeping the aggregation at repository level avoids one SQLite round-trip per
    /// situation when a workspace is opened.
    func learningSituationClassLinksAll() async throws -> [LearningSituationClassLink] {
        try await container.learningSituationsRepository.listAllClassLinks()
    }

    func addLearningSituationClassLink(situationId: Int64, classId: Int64) async throws {
        let current = try await container.learningSituationsRepository.listClassLinks(learningSituationId: situationId)
        var classIds = Set(current.map { $0.classId })
        if !classIds.contains(classId) {
            classIds.insert(classId)
            try await container.learningSituationsRepository.replaceClassLinks(
                learningSituationId: situationId,
                classIds: Array(classIds).sorted().map { KotlinLong(value: $0) }
            )
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            enqueueLocalChange(
                entity: "learning_situation_class_link",
                id: "\(situationId)-\(classId)",
                updatedAtEpochMs: nowMs,
                payload: ["learningSituationId": situationId, "classId": classId]
            )
        }
    }

    func learningSituationResources(id: Int64) async throws -> [LearningSituationLinkedResource] {
        try await container.learningSituationsRepository.listLinkedResources(learningSituationId: id)
    }

    func learningSituationSessionPlan(id: Int64) async throws -> LearningSituationSessionPlan? {
        guard let plan = try await container.learningSituationsRepository.getSessionPlan(id: id) else { return nil }
        return try await repairPersistedSessionPlanIfNeeded(plan)
    }

    func learningSituationSessionPlans(sequenceVersionId: Int64) async throws -> [LearningSituationSessionPlan] {
        let plans = try await container.learningSituationsRepository.listSessionPlans(sequenceVersionId: sequenceVersionId)
        var repaired: [LearningSituationSessionPlan] = []
        repaired.reserveCapacity(plans.count)
        for plan in plans {
            repaired.append(try await repairPersistedSessionPlanIfNeeded(plan))
        }
        return repaired
    }

    /// Bulk read used by Planner sequence enrichment to avoid one query per session plan.
    func learningSituationSessionPlansAll() async throws -> [LearningSituationSessionPlan] {
        let plans = try await container.learningSituationsRepository.listAllSessionPlans()
        var repaired: [LearningSituationSessionPlan] = []
        repaired.reserveCapacity(plans.count)
        for plan in plans {
            repaired.append(try await repairPersistedSessionPlanIfNeeded(plan))
        }
        return repaired
    }

    /// Repara planes históricos sin cambiar sus IDs ni exigir borrar la planificación.
    /// Primero se recupera el DOCX original (incluida la descarga metadata-first por hash).
    /// Si el binario aún no está disponible, se deja el registro intacto: la proyección v2
    /// puede representar el plan mientras tanto, pero no se persiste un v2 incompleto que
    /// impida recuperar PREPARES/CONSOLIDATES cuando llegue el documento.
    private func repairPersistedSessionPlanIfNeeded(
        _ plan: LearningSituationSessionPlan
    ) async throws -> LearningSituationSessionPlan {
        let versions = try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: plan.learningSituationId)
        let version = versions.first { $0.id == plan.sequenceVersionId }
        let payload = LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)
        let expectedHash = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedHash = payload?.sourceDocumentSHA256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSyntheticProjection = payload?.activities.contains { activity in
            let key = activity.activityKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return key.hasPrefix("LEGACY-") || key.hasPrefix("ACTIVIDAD ")
        } ?? false
        let alreadyCanonical = payload?.schema == "session-plan-v2"
            && plan.developmentJson.contains("\"prepares\":")
            && plan.developmentJson.contains("\"consolidates\":")
            && !hasSyntheticProjection
            && (expectedHash.isEmpty || storedHash == expectedHash)
        guard !alreadyCanonical else { return plan }

        if let sourceURL = await ensureLearningSituationSessionSequenceDocument(version: version),
           let repairedJSON = await canonicalDevelopmentJSON(
               from: sourceURL,
               sessionNumber: Int(plan.sessionNumber),
               sourceSHA256: expectedHash.isEmpty ? nil : expectedHash
           ) {
            return try await persistDerivedDevelopmentJSON(repairedJSON, for: plan)
        }

        return plan
    }

    private nonisolated static func canonicalDevelopmentJSON(
        for draft: LearningSituationSessionPlanDraft,
        sourceSHA256: String? = nil
    ) -> String? {
        let payload = LearningSituationSessionDevelopmentPayload(
            organisation: draft.organisation,
            coreKnowledge: draft.coreKnowledge,
            assessment: draft.assessment,
            sections: draft.development,
            activities: draft.activities,
            guidingQuestions: draft.guidingQuestions,
            closure: draft.closure,
            visuals: draft.visuals,
            sequenceRoute: draft.sequenceRoute,
            sourceDocumentSHA256: sourceSHA256
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func canonicalDevelopmentJSON(
        from sourceURL: URL,
        sessionNumber: Int,
        sourceSHA256: String?
    ) async -> String? {
        let trimmedSourceHash = sourceSHA256?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = trimmedSourceHash?.isEmpty == false ? trimmedSourceHash! : sourceURL.path
        if let cached = sessionPlanJSONCacheBySource[cacheKey]?[sessionNumber] {
            return cached
        }

        let result: String? = await Task.detached(priority: .utility) { () -> String? in
            guard let imported = try? LearningSituationSessionSequenceDocumentImportService().preview(from: sourceURL),
                  let draft = imported.plans.first(where: { $0.sessionNumber == sessionNumber }) else {
                return nil
            }
            return KmpBridge.canonicalDevelopmentJSON(for: draft, sourceSHA256: sourceSHA256)
        }.value
        if let result {
            var plans = sessionPlanJSONCacheBySource[cacheKey] ?? [:]
            plans[sessionNumber] = result
            sessionPlanJSONCacheBySource[cacheKey] = plans
        }
        return result
    }

    private func persistDerivedDevelopmentJSON(
        _ repairedJSON: String,
        for plan: LearningSituationSessionPlan
    ) async throws -> LearningSituationSessionPlan {
        guard repairedJSON != plan.developmentJson,
              !semanticallyEquivalentDevelopmentJSON(plan.developmentJson, repairedJSON) else {
            return plan
        }
        let repairedPlan = LearningSituationSessionPlan(
            id: plan.id,
            learningSituationId: plan.learningSituationId,
            sequenceVersionId: plan.sequenceVersionId,
            sessionNumber: plan.sessionNumber,
            sourceLabel: plan.sourceLabel,
            title: plan.title,
            sessionType: plan.sessionType,
            effectiveMinutes: plan.effectiveMinutes,
            objective: plan.objective,
            criteriaJson: plan.criteriaJson,
            material: plan.material,
            developmentJson: repairedJSON,
            adaptationsJson: plan.adaptationsJson,
            trace: plan.trace
        )
        _ = try await container.learningSituationsRepository.saveSessionPlan(plan: repairedPlan)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation_session_plan",
            id: "\(plan.learningSituationId)-\(plan.sequenceVersionId)-\(plan.sessionNumber)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": plan.id, "learningSituationId": plan.learningSituationId,
                "sequenceVersionId": plan.sequenceVersionId, "sessionNumber": plan.sessionNumber,
                "sourceLabel": plan.sourceLabel, "title": plan.title,
                "sessionType": plan.sessionType, "effectiveMinutes": plan.effectiveMinutes,
                "objective": plan.objective, "criteriaJson": plan.criteriaJson,
                "material": plan.material, "developmentJson": repairedJSON,
                "adaptationsJson": plan.adaptationsJson
            ]
        )
        return repairedPlan
    }

    /// Los drafts del importador llevan UUIDs de UI que se regeneran al volver a leer el mismo
    /// DOCX. No deben provocar una escritura ni una notificación de sync si el contenido docente
    /// y la procedencia son iguales.
    private func semanticallyEquivalentDevelopmentJSON(_ lhs: String, _ rhs: String) -> Bool {
        func canonicalData(_ json: String) -> Data? {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            func removingRuntimeIDs(_ value: Any) -> Any {
                if let dictionary = value as? [String: Any] {
                    var result: [String: Any] = [:]
                    for (key, nested) in dictionary {
                        if key == "id", let string = nested as? String, UUID(uuidString: string) != nil {
                            continue
                        }
                        result[key] = removingRuntimeIDs(nested)
                    }
                    return result
                }
                if let array = value as? [Any] {
                    return array.map(removingRuntimeIDs)
                }
                return value
            }
            return try? JSONSerialization.data(
                withJSONObject: removingRuntimeIDs(object),
                options: [.sortedKeys]
            )
        }
        guard let lhsData = canonicalData(lhs), let rhsData = canonicalData(rhs) else { return false }
        return lhsData == rhsData
    }

    private func localSequenceSourceURL(_ version: LearningSituationSessionSequenceVersion?) -> URL? {
        if let path = version?.localPath,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: path)
            if let expectedHash = version?.sha256,
               !expectedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let data = try? Data(contentsOf: url) {
                let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if actualHash == expectedHash { return url }
            }
        }
        guard let sha256 = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha256.isEmpty else { return nil }
        let url = LearningSituationDocumentStore().directoryURL
            .appendingPathComponent("\(sha256).docx")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actualHash == sha256 ? url : nil
    }

    /// Exposición de solo lectura para que el Planner pueda representar la última
    /// secuencia teórica incluso antes de que exista una sesión en el calendario.
    func learningSituationSessionSequenceVersions(
        learningSituationId: Int64
    ) async throws -> [LearningSituationSessionSequenceVersion] {
        try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: learningSituationId)
    }

    /// Bulk read used by Planner sequence enrichment to avoid one query per situation.
    func learningSituationSessionSequenceVersionsAll() async throws -> [LearningSituationSessionSequenceVersion] {
        try await container.learningSituationsRepository.listAllSessionSequenceVersions()
    }

    func learningSituationSessionSequenceVersion(id: Int64, learningSituationId: Int64) async throws -> LearningSituationSessionSequenceVersion? {
        try await container.learningSituationsRepository
            .listSessionSequenceVersions(learningSituationId: learningSituationId)
            .first { $0.id == id }
    }

    /// Makes the original DOCX available to the Planner when the metadata arrived by
    /// sync before the binary did. The download is cache-by-hash and is safe to repeat.
    func ensureLearningSituationSessionSequenceDocument(
        version: LearningSituationSessionSequenceVersion?
    ) async -> URL? {
        if let localURL = localSequenceSourceURL(version) { return localURL }
        guard let sha256 = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha256.isEmpty,
              let path = await downloadLearningSituationDocumentIfNeeded(sha256: sha256) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func confirmLearningSituationImport(
        draft: LearningSituationImportDraft,
        existingSituationId: Int64? = nil
    ) async throws -> Int64 {
        guard !draft.selectedClassIds.isEmpty else {
            throw NSError(domain: "LearningSituations", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un grupo antes de guardar."])
        }
        let storedURL = try LearningSituationDocumentStore().persistSourceDocument(from: draft.sourceURL, sha256: draft.sha256)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            associatedGroupId: nil,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let situationId = try await container.learningSituationsRepository.saveSituation(
            situation: LearningSituation(
                id: existingSituationId ?? 0,
                title: draft.title,
                stageLabel: draft.stageLabel,
                courseLabel: draft.courseLabel,
                subjectLabel: draft.subjectLabel,
                termLabel: draft.termLabel,
                centerLabel: draft.centerLabel,
                sessionCount: Int32(draft.sessionCount),
                challenge: draft.challenge,
                finalProduct: draft.finalProduct,
                payloadJson: draft.payloadJSON,
                status: .active,
                trace: trace
            )
        ).int64Value
        let warningJSON = (try? JSONEncoder().encode(draft.warnings))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        _ = try await container.learningSituationsRepository.saveVersion(
            version: LearningSituationVersion(
                id: 0,
                learningSituationId: situationId,
                versionNumber: 0,
                originalFileName: draft.sourceFileName,
                sha256: draft.sha256,
                localPath: storedURL.path,
                sizeBytes: draft.sizeBytes,
                payloadJson: draft.payloadJSON,
                warningsJson: warningJSON,
                trace: trace
            )
        )
        let acceptedVersionNumber = try await container.learningSituationsRepository
            .listVersions(learningSituationId: situationId)
            .first?.versionNumber ?? 1
        try await container.learningSituationsRepository.replaceClassLinks(
            learningSituationId: situationId,
            classIds: draft.selectedClassIds.sorted().map { KotlinLong(value: $0) }
        )
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(situationId)",
            updatedAtEpochMs: nowMs,
            payload: learningSituationSyncPayload(id: situationId, draft: draft)
        )
        enqueueLocalChange(
            entity: "learning_situation_version",
            id: "\(situationId)-\(draft.sha256)",
            updatedAtEpochMs: nowMs,
            payload: [
                "learningSituationId": situationId,
                "versionNumber": acceptedVersionNumber,
                "originalFileName": draft.sourceFileName,
                "sha256": draft.sha256,
                "sizeBytes": draft.sizeBytes,
                "payloadJson": draft.payloadJSON,
                "warningsJson": warningJSON
            ]
        )
        for classId in draft.selectedClassIds {
            enqueueLocalChange(
                entity: "learning_situation_class_link",
                id: "\(situationId)-\(classId)",
                updatedAtEpochMs: nowMs,
                payload: ["learningSituationId": situationId, "classId": classId]
            )
        }
        try await uploadLearningSituationDocumentIfPaired(at: storedURL, sha256: draft.sha256)
        return situationId
    }

    func duplicateLearningSituation(_ source: LearningSituation, classIds: [Int64]) async throws -> Int64 {
        let versions = try await learningSituationVersions(id: source.id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs),
            associatedGroupId: nil,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let newId = try await container.learningSituationsRepository.saveSituation(
            situation: LearningSituation(
                id: 0,
                title: "\(source.title) (copia)",
                stageLabel: source.stageLabel,
                courseLabel: source.courseLabel,
                subjectLabel: source.subjectLabel,
                termLabel: source.termLabel,
                centerLabel: source.centerLabel,
                sessionCount: source.sessionCount,
                challenge: source.challenge,
                finalProduct: source.finalProduct,
                payloadJson: source.payloadJson,
                status: .draft,
                trace: trace
            )
        ).int64Value
        if let latest = versions.first {
            _ = try await container.learningSituationsRepository.saveVersion(
                version: LearningSituationVersion(
                    id: 0,
                    learningSituationId: newId,
                    versionNumber: 0,
                    originalFileName: latest.originalFileName,
                    sha256: latest.sha256,
                    localPath: latest.localPath,
                    sizeBytes: latest.sizeBytes,
                    payloadJson: latest.payloadJson,
                    warningsJson: latest.warningsJson,
                    trace: trace
                )
            )
            enqueueLocalChange(
                entity: "learning_situation_version",
                id: "\(newId)-\(latest.sha256)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "learningSituationId": newId,
                    "versionNumber": 1,
                    "originalFileName": latest.originalFileName,
                    "sha256": latest.sha256,
                    "sizeBytes": latest.sizeBytes,
                    "payloadJson": latest.payloadJson,
                    "warningsJson": latest.warningsJson
                ]
            )
        }
        try await container.learningSituationsRepository.replaceClassLinks(
            learningSituationId: newId,
            classIds: classIds.map { KotlinLong(value: $0) }
        )
        enqueueLocalChange(
            entity: "learning_situation",
            id: "\(newId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": newId, "title": "\(source.title) (copia)", "stageLabel": source.stageLabel,
                "courseLabel": source.courseLabel, "subjectLabel": source.subjectLabel,
                "termLabel": source.termLabel, "centerLabel": source.centerLabel,
                "sessionCount": source.sessionCount, "challenge": source.challenge,
                "finalProduct": source.finalProduct, "payloadJson": source.payloadJson,
                "status": "DRAFT"
            ]
        )
        for classId in classIds {
            enqueueLocalChange(
                entity: "learning_situation_class_link",
                id: "\(newId)-\(classId)",
                updatedAtEpochMs: nowMs,
                payload: ["learningSituationId": newId, "classId": classId]
            )
        }
        return newId
    }

    func programLearningSituationSessions(
        situation: LearningSituation,
        classId: Int64,
        groupName: String,
        scheduledSlots: [LearningSituationScheduledSlot],
        sequenceDraft: LearningSituationSessionSequenceImportDraft? = nil
    ) async throws {
        guard !scheduledSlots.isEmpty else { return }
        guard !LearningSituationScheduleProjection.hasDuplicateDestinations(scheduledSlots) else {
            throw NSError(
                domain: "LearningSituations",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No se puede programar más de una sesión en la misma fecha y franja. Revisa la previsualización."
                ]
            )
        }
        let detailedPlanIds: [Int: Int64]
        if let sequenceDraft {
            detailedPlanIds = try await persistSessionSequence(situation: situation, draft: sequenceDraft)
        } else {
            detailedPlanIds = [:]
        }
        let orderedDraftPlans = sequenceDraft?.plans.sorted { $0.sessionNumber < $1.sessionNumber } ?? []
        let unitId = try await ensureTeachingUnitForLearningSituation(situation: situation, classId: classId)
        let calendar = Calendar(identifier: .iso8601)
        for (index, slot) in scheduledSlots.enumerated() {
            let detailedDraft: LearningSituationSessionPlanDraft?
            if let planSessionNumber = slot.planSessionNumber {
                detailedDraft = orderedDraftPlans.first(where: { $0.sessionNumber == planSessionNumber })
            } else {
                detailedDraft = index < orderedDraftPlans.count ? orderedDraftPlans[index] : nil
            }
            let components = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear, .weekday], from: slot.date)
            let weekday = ((components.weekday ?? 2) + 5) % 7 + 1
            let weekNumber = components.weekOfYear ?? 1
            let year = components.yearForWeekOfYear ?? Calendar.current.component(.year, from: slot.date)
            let existingSessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
            for (destinationIndex, destination) in slot.destinationSlots.enumerated() {
                let occupiedSession = existingSessions.first {
                    Int($0.dayOfWeek) == weekday && Int($0.period) == destination.period
                }
                let sessionId = try await plannerUpsertSession(
                    id: occupiedSession?.id ?? 0,
                    teachingUnitId: unitId,
                    teachingUnitName: situation.title,
                    teachingUnitColor: plannerCourseColor(for: classId),
                    groupId: classId,
                    groupName: groupName,
                    dayOfWeek: weekday,
                    period: destination.period,
                    weekNumber: weekNumber,
                    year: year,
                    objectives: detailedDraft?.objective ?? situation.challenge,
                    activities: detailedDraft?.developmentSummary ?? "Sesión vinculada a \(situation.title)",
                    evaluation: detailedDraft?.criteria.joined(separator: ", ") ?? "",
                    teacherScheduleSlotId: destination.teacherScheduleSlotId,
                    startTime: destination.startTime.isEmpty ? slot.startTime : destination.startTime,
                    endTime: destination.endTime.isEmpty ? slot.endTime : destination.endTime,
                    learningSituationSessionPlanId: detailedDraft.flatMap { detailedPlanIds[$0.sessionNumber] },
                    status: .planned
                )
                let resourceLabel = destinationIndex == 0 ? slot.label : "\(slot.label) · continuación"
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .planningSession,
                    resourceId: "\(sessionId)",
                    classId: classId,
                    label: resourceLabel,
                    trace: situation.trace
                )
            }
        }
    }

    private func persistSessionSequence(
        situation: LearningSituation,
        draft: LearningSituationSessionSequenceImportDraft
    ) async throws -> [Int: Int64] {
        let existingVersions = try await container.learningSituationsRepository.listSessionSequenceVersions(learningSituationId: situation.id)
        if let identicalVersion = existingVersions.first(where: { $0.sha256 == draft.sha256 }) {
            let existingPlans = try await container.learningSituationsRepository.listSessionPlans(sequenceVersionId: identicalVersion.id)
            for existingPlan in existingPlans {
                guard let importedPlan = draft.plans.first(where: { $0.sessionNumber == Int(existingPlan.sessionNumber) }),
                      let developmentJSON = Self.canonicalDevelopmentJSON(
                          for: importedPlan,
                          sourceSHA256: draft.sha256
                      ) else { continue }
                _ = try await persistDerivedDevelopmentJSON(developmentJSON, for: existingPlan)
            }
            return Dictionary(
                existingPlans.map { (Int($0.sessionNumber), $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        let storedURL = try LearningSituationDocumentStore().persistSourceDocument(from: draft.sourceURL, sha256: draft.sha256)
        let warningsJSON = String(data: try JSONEncoder().encode(draft.warnings), encoding: .utf8) ?? "[]"
        let versionNumber = Int32((existingVersions.first?.versionNumber ?? 0) + 1)
        let versionId = try await container.learningSituationsRepository.saveSessionSequenceVersion(
            version: LearningSituationSessionSequenceVersion(
                id: 0,
                learningSituationId: situation.id,
                versionNumber: versionNumber,
                originalFileName: draft.sourceFileName,
                sha256: draft.sha256,
                localPath: storedURL.path,
                sizeBytes: draft.sizeBytes,
                payloadJson: draft.payloadJSON,
                warningsJson: warningsJSON,
                trace: situation.trace
            )
        ).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation_sequence_version",
            id: "\(situation.id)-\(versionNumber)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": versionId, "learningSituationId": situation.id, "versionNumber": versionNumber,
                "originalFileName": draft.sourceFileName, "sha256": draft.sha256,
                "sizeBytes": draft.sizeBytes, "payloadJson": draft.payloadJSON,
                "warningsJson": warningsJSON
            ]
        )
        var planIds: [Int: Int64] = [:]
        for plan in draft.plans {
            let criteriaJSON = String(data: try JSONEncoder().encode(plan.criteria), encoding: .utf8) ?? "[]"
            let developmentPayload = LearningSituationSessionDevelopmentPayload(
                organisation: plan.organisation,
                coreKnowledge: plan.coreKnowledge,
                assessment: plan.assessment,
                sections: plan.development,
                activities: plan.activities,
                guidingQuestions: plan.guidingQuestions,
                closure: plan.closure,
                visuals: plan.visuals,
                sequenceRoute: plan.sequenceRoute,
                sourceDocumentSHA256: draft.sha256
            )
            let developmentJSON = String(data: try JSONEncoder().encode(developmentPayload), encoding: .utf8) ?? "{}"
            let adaptationsJSON = String(data: try JSONEncoder().encode(plan.adaptations), encoding: .utf8) ?? "[]"
            let planId = try await container.learningSituationsRepository.saveSessionPlan(
                plan: LearningSituationSessionPlan(
                    id: 0,
                    learningSituationId: situation.id,
                    sequenceVersionId: versionId,
                    sessionNumber: Int32(plan.sessionNumber),
                    sourceLabel: plan.sourceLabel,
                    title: plan.title,
                    sessionType: plan.sessionType,
                    effectiveMinutes: Int32(plan.effectiveMinutes),
                    objective: plan.objective,
                    criteriaJson: criteriaJSON,
                    material: plan.material,
                    developmentJson: developmentJSON,
                    adaptationsJson: adaptationsJSON,
                    trace: situation.trace
                )
            ).int64Value
            planIds[plan.sessionNumber] = planId
            enqueueLocalChange(
                entity: "learning_situation_session_plan",
                id: "\(situation.id)-\(versionId)-\(plan.sessionNumber)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "id": planId, "learningSituationId": situation.id, "sequenceVersionId": versionId,
                    "sessionNumber": plan.sessionNumber, "sourceLabel": plan.sourceLabel,
                    "title": plan.title, "sessionType": plan.sessionType,
                    "effectiveMinutes": plan.effectiveMinutes, "objective": plan.objective,
                    "criteriaJson": criteriaJSON, "material": plan.material,
                    "developmentJson": developmentJSON, "adaptationsJson": adaptationsJSON
                ]
            )
        }
        try await uploadLearningSituationDocumentIfPaired(at: storedURL, sha256: draft.sha256)
        return planIds
    }

    func materializeLearningSituationEvaluations(
        situation: LearningSituation,
        classId: Int64,
        proposals: [LearningSituationEvaluationDraft],
        targetTabId: String? = nil
    ) async throws {
        for (index, proposal) in proposals.filter(\.isSelected).enumerated() {
            let code = "SA\(situation.id)-E\(index + 1)"
            let evaluationId = try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: code,
                name: proposal.title,
                type: "Situación de aprendizaje",
                weight: (proposal.weightPercent ?? 0) / 100.0,
                formula: nil,
                rubricId: proposal.rubricId.map { KotlinLong(value: $0) },
                description: situation.title,
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            try await ensureNotebookColumnForEvaluation(classId: classId, evaluationId: evaluationId, title: proposal.title, rubricId: proposal.rubricId, targetTabId: targetTabId)
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: proposal.title,
                trace: situation.trace
            )
        }
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
    }

    func materializeLearningSituationPhysicalTests(
        situation: LearningSituation,
        classId: Int64,
        draft: PhysicalTestsImportDraft,
        targetTabId: String? = nil
    ) async throws {
        guard !draft.testDefinitions.isEmpty else {
            throw NSError(
                domain: "LearningSituations",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "El manifiesto no contiene pruebas físicas."]
            )
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let trace = physicalImportTrace(classId: classId, epochMs: nowMs)
        let assignmentTemplate = draft.assignmentTemplate
        let assignmentId = "pe_assignment_sa\(situation.id)_\(classId)_\(assignmentTemplate.batteryId)"
        let scoreColumnMode = assignmentTemplate.scoreColumnMode && assignmentTemplate.recordScore
        // SaveEvaluationUseCase requires a positive weight. Diagnostic imports
        // remain excluded from the notebook average through their raw columns.
        let physicalEvaluationWeight = 1.0
        let tabId = try await resolveNotebookTargetTabId(classId: classId, preferredTabId: targetTabId)

        var evaluationsByCode = Dictionary(
            (try await container.evaluationsRepository.listClassEvaluations(classId: classId)).map { ($0.code, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        for definition in draft.testDefinitions {
            try await container.physicalTestsRepository.saveDefinition(
                definition: PhysicalTestDefinition(
                    id: definition.id,
                    name: definition.name,
                    capacity: importedPhysicalCapacity(definition.capacity),
                    measurementKind: importedPhysicalMeasurement(definition.measurementKind),
                    unit: definition.unit,
                    higherIsBetter: definition.higherIsBetter,
                    protocol: definition.protocolText,
                    material: "",
                    attempts: Int32(definition.attempts),
                    resultMode: importedPhysicalResultMode(definition.resultMode),
                    trace: trace
                )
            )
        }

        try await container.physicalTestsRepository.saveBattery(
            battery: PhysicalTestBattery(
                id: assignmentTemplate.batteryId,
                name: assignmentTemplate.batteryName,
                description: "Importada desde \(draft.sourceFileName) · \(draft.purpose)",
                defaultCourse: draft.courseNumber.map { KotlinInt(value: Int32($0)) },
                defaultAgeFrom: draft.referenceScales.compactMap(\.ageFrom).min().map { KotlinInt(value: Int32($0)) },
                defaultAgeTo: draft.referenceScales.compactMap(\.ageTo).max().map { KotlinInt(value: Int32($0)) },
                testIds: draft.testDefinitions.map(\.id),
                trace: trace
            )
        )

        for scale in draft.referenceScales {
            let isLinear = scale.scoring?.mode.uppercased() == "LINEAR"
            let persistedRanges: [MiGestorKit.PhysicalTestScaleRange] = isLinear
                ? (scale.scoring?.points ?? []).enumerated().map { index, point in
                    MiGestorKit.PhysicalTestScaleRange(
                        id: point.id ?? "\(scale.id)_point_\(index + 1)",
                        scaleId: scale.id,
                        minValue: KotlinDouble(value: point.value),
                        maxValue: nil,
                        score: point.score,
                        label: scaleLabelOrNil(point.label),
                        sortOrder: Int32(point.sortOrder ?? index)
                    )
                }
                : scale.ranges.map { range in
                    MiGestorKit.PhysicalTestScaleRange(
                        id: range.id,
                        scaleId: scale.id,
                        minValue: range.minValue.map { KotlinDouble(value: $0) },
                        maxValue: range.maxValue.map { KotlinDouble(value: $0) },
                        score: range.score,
                        label: scaleLabelOrNil(range.label),
                        sortOrder: Int32(range.sortOrder)
                    )
                }
            try await container.physicalTestsRepository.saveScale(
                scale: PhysicalTestScale(
                    id: scale.id,
                    testId: scale.testId,
                    name: scale.name,
                    course: scale.course.map { KotlinInt(value: Int32($0)) },
                    ageFrom: scale.ageFrom.map { KotlinInt(value: Int32($0)) },
                    ageTo: scale.ageTo.map { KotlinInt(value: Int32($0)) },
                    sex: scaleLabelOrNil(scale.canonicalSex),
                    batteryId: assignmentTemplate.batteryId,
                    direction: scale.direction == "LOWER_IS_BETTER" ? .lowerIsBetter : .higherIsBetter,
                    ranges: persistedRanges,
                    scoringMode: isLinear ? .linear : .step,
                    scoreRoundTo: scale.scoring?.roundTo.map { KotlinDouble(value: $0) },
                    trace: trace
                )
            )
        }

        let assignment = PhysicalTestAssignment(
            id: assignmentId,
            batteryId: assignmentTemplate.batteryId,
            classId: classId,
            course: draft.courseNumber.map { KotlinInt(value: Int32($0)) },
            ageFrom: draft.referenceScales.compactMap(\.ageFrom).min().map { KotlinInt(value: Int32($0)) },
            ageTo: draft.referenceScales.compactMap(\.ageTo).max().map { KotlinInt(value: Int32($0)) },
            termLabel: scaleLabelOrNil(assignmentTemplate.termLabel),
            dateEpochMs: nowMs,
            rawColumnMode: assignmentTemplate.rawColumnMode,
            scoreColumnMode: scoreColumnMode,
            trace: trace
        )
        try await container.physicalTestsRepository.assignBatteryToClass(assignment: assignment)

        let categories = try await container.notebookRepository.listColumnCategories(classId: classId, tabId: tabId)
        if !categories.contains(where: { $0.id == assignmentId }) {
            let categoryOrder = (categories.map(\.order).max() ?? -1) + 1
            try await container.notebookRepository.saveColumnCategory(
                classId: classId,
                category: NotebookColumnCategory(
                    id: assignmentId,
                    classId: classId,
                    tabId: tabId,
                    name: "\(assignmentTemplate.batteryName) · \(assignmentTemplate.termLabel)",
                    order: categoryOrder,
                    isCollapsed: false,
                    trace: trace
                )
            )
        }

        let existingLinks = try await container.physicalTestsRepository.listNotebookLinksForAssignment(assignmentId: assignmentId)
        let existingColumns = try await container.notebookConfigRepository.listColumns(classId: classId)

        for definition in draft.testDefinitions {
            let code = "EF_\(definition.id.uppercased())"
            let evaluationId: Int64
            if let existingEvaluationId = evaluationsByCode[code] {
                evaluationId = existingEvaluationId
            } else {
                evaluationId = try await createPhysicalTest(
                    classId: classId,
                    code: code,
                    name: definition.name,
                    kind: definition.measurementKind,
                    weight: physicalEvaluationWeight,
                    description: definition.protocolText
                )
                evaluationsByCode[code] = evaluationId
            }

            let existingLink = existingLinks.first { $0.testId == definition.id }
            let rawTitle = "\(definition.name) · Marca"
            let scoreTitle = "\(definition.name) · Nota"
            let rawColumnId: String?
            if assignmentTemplate.rawColumnMode {
                if let existingColumnId = existingLink?.rawColumnId
                    ?? existingColumns.first(where: { $0.title == rawTitle && $0.categoryId == assignmentId })?.id {
                    rawColumnId = existingColumnId
                } else {
                    rawColumnId = try await createNotebookPhysicalColumnForClass(
                        classId: classId,
                        name: rawTitle,
                        categoryId: assignmentId,
                        inputKind: importedPhysicalInputKind(definition.measurementKind),
                        unitOrSituation: "Dato bruto · \(definition.unit)",
                        scaleKind: importedPhysicalScaleKind(definition.measurementKind),
                        iconName: "stopwatch.fill",
                        weight: 0,
                        countsTowardAverage: false,
                        dateEpochMs: nowMs,
                        targetTabId: tabId
                    )
                }
            } else {
                rawColumnId = nil
            }

            let scoreColumnId: String?
            if scoreColumnMode {
                if let existingColumnId = existingLink?.scoreColumnId
                    ?? existingColumns.first(where: { $0.title == scoreTitle && $0.categoryId == assignmentId })?.id {
                    scoreColumnId = existingColumnId
                } else {
                    scoreColumnId = try await createNotebookPhysicalColumnForClass(
                        classId: classId,
                        name: scoreTitle,
                        categoryId: assignmentId,
                        inputKind: .numeric010,
                        unitOrSituation: "Nota baremada",
                        scaleKind: .tenPoint,
                        iconName: "chart.bar.fill",
                        weight: 10,
                        countsTowardAverage: assignmentTemplate.countsTowardAverage && assignmentTemplate.recordScore,
                        dateEpochMs: nowMs,
                        targetTabId: tabId
                    )
                }
            } else {
                scoreColumnId = nil
            }

            if existingLink?.rawColumnId != rawColumnId || existingLink?.scoreColumnId != scoreColumnId {
                try await container.physicalTestsRepository.saveNotebookLink(
                    link: PhysicalTestNotebookLink(
                        assignmentId: assignmentId,
                        testId: definition.id,
                        rawColumnId: rawColumnId,
                        scoreColumnId: scoreColumnId,
                        trace: trace
                    )
                )
            }

            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: definition.name,
                trace: situation.trace
            )
            if let rawColumnId {
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .notebookColumn,
                    resourceId: rawColumnId,
                    classId: classId,
                    label: definition.name,
                    trace: situation.trace
                )
            }
            if let scoreColumnId {
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .notebookColumn,
                    resourceId: scoreColumnId,
                    classId: classId,
                    label: "\(definition.name) · Nota",
                    trace: situation.trace
                )
            }
        }

        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
    }

    private func physicalImportTrace(classId: Int64, epochMs: Int64) -> AuditTrace {
        let instant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: epochMs)
        return AuditTrace(
            authorUserId: nil,
            createdAt: instant,
            updatedAt: instant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 1
        )
    }

    private func scaleLabelOrNil(_ value: String?) -> String? {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
    }

    private func importedPhysicalCapacity(_ value: String) -> PhysicalCapacity {
        switch value {
        case "RESISTANCE": return .resistance
        case "STRENGTH": return .strength
        case "SPEED": return .speed
        case "FLEXIBILITY": return .flexibility
        case "COORDINATION": return .coordination
        case "AGILITY": return .agility
        default: return .custom
        }
    }

    private func importedPhysicalMeasurement(_ value: String) -> PhysicalMeasurementKind {
        switch value {
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        case "LEVEL": return .level
        default: return .score
        }
    }

    private func importedPhysicalResultMode(_ value: String) -> PhysicalResultMode {
        switch value {
        case "AVERAGE": return .average
        case "LAST": return .last
        default: return .best
        }
    }

    private func importedPhysicalInputKind(_ value: String) -> NotebookCellInputKind {
        switch value {
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        default: return .numeric010
        }
    }

    private func importedPhysicalScaleKind(_ value: String) -> NotebookScaleKind {
        switch value {
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        default: return .tenPoint
        }
    }

    func materializeLearningSituationAssessmentInstruments(
        situation: LearningSituation,
        classId: Int64,
        draft: LearningSituationAssessmentImportDraft,
        targetTabId: String? = nil
    ) async throws {
        let selectedInstruments = draft.instruments.filter(\.isSelected)
        guard !selectedInstruments.isEmpty else {
            throw NSError(domain: "LearningSituations", code: 2, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un instrumento."])
        }

        try await repairLearningSituationAssessmentInstrumentImportIfNeeded(classId: classId)

        let existingInstrumentTitles = try await existingLearningSituationAssessmentTitles(
            situationId: situation.id,
            classId: classId
        )
        let instrumentsToCreate = selectedInstruments.filter { instrument in
            !existingInstrumentTitles.contains(normalizedAssessmentInstrumentTitle(instrument.title))
        }
        guard !instrumentsToCreate.isEmpty else { return }

        let teachingUnitId = try await ensureTeachingUnitForLearningSituation(situation: situation, classId: classId)

        for (index, instrument) in instrumentsToCreate.enumerated() {
            let rubricId = try await saveAssessmentInstrumentRubricIfNeeded(
                instrument: instrument,
                classId: classId,
                teachingUnitId: teachingUnitId,
                sourceFileName: draft.sourceFileName
            )
            let evaluationId = try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: "SA\(situation.id)-I\(index + 1)",
                name: instrument.title,
                type: instrument.kind.label,
                weight: (instrument.weightPercent ?? 0) / 100.0,
                formula: nil,
                rubricId: rubricId.map { KotlinLong(value: $0) },
                // El texto real del criterio de evaluacion (buscado por titulo del instrumento en
                // el catalogo de 1r de Batxillerat - EF) es lo que se enseña en el Cuaderno como
                // "Criterio: X". La nota generica de importacion solo se usa cuando el instrumento
                // no esta en ese catalogo (otra materia/curso, o titulo editado a mano).
                description: EvaluationCriteriaReference.shared.criterionStatement(instrumentTitle: instrument.title)
                    ?? "Instrumento importado desde \(draft.sourceFileName) para \(situation.title)",
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            let columnId = try await ensureNotebookColumnForAssessmentInstrument(
                classId: classId,
                evaluationId: evaluationId,
                title: instrument.title,
                rubricId: rubricId,
                instrument: instrument,
                situationTitle: situation.title,
                targetTabId: targetTabId
            )
            if rubricId == nil {
                try await saveAssessmentInstrumentTemplateIfNeeded(
                    instrument: instrument,
                    classId: classId,
                    evaluationId: evaluationId,
                    columnId: columnId,
                    sourceFileName: draft.sourceFileName
                )
            }
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .evaluation,
                resourceId: "\(evaluationId)",
                classId: classId,
                label: instrument.title,
                trace: situation.trace
            )
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .notebookColumn,
                resourceId: columnId,
                classId: classId,
                label: instrument.title,
                trace: situation.trace
            )
            if let rubricId {
                try await saveLearningSituationLinkedResource(
                    situationId: situation.id,
                    kind: .rubric,
                    resourceId: "\(rubricId)",
                    classId: classId,
                    label: "Rubrica · \(instrument.title)",
                    trace: situation.trace
                )
            }
        }
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
    }

    private func existingLearningSituationAssessmentTitles(
        situationId: Int64,
        classId: Int64
    ) async throws -> Set<String> {
        let resources = try await container.learningSituationsRepository.listLinkedResources(learningSituationId: situationId)
        let liveColumnIds = Set(try await container.notebookConfigRepository.listColumns(classId: classId).map(\.id))
        return Set(resources.compactMap { resource in
            guard resource.classId?.int64Value == classId else { return nil }
            guard resource.kind == .notebookColumn else { return nil }
            guard liveColumnIds.contains(resource.resourceId) else { return nil }
            return normalizedAssessmentInstrumentTitle(resource.label)
        })
    }

    private func normalizedAssessmentInstrumentTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    func learningSituationNotebookTabs(for classId: Int64) async throws -> [NotebookTab] {
        try await container.notebookConfigRepository.listTabs(classId: classId)
    }

    func fetchNotebookTabs(for classId: Int64) async throws -> [NotebookTab] {
        try await container.notebookConfigRepository.listTabs(classId: classId)
    }

    func fetchNotebookColumns(for classId: Int64) async throws -> [NotebookColumnDefinition] {
        try await container.notebookConfigRepository.listColumns(classId: classId)
    }

    func clearNotebookForClass(classId: Int64) async throws {
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        for col in columns {
            deleteColumn(id: col.id, evaluationId: col.evaluationId?.int64Value)
        }
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        for tab in tabs {
            deleteTab(id: tab.id)
        }
    }


    func ensureTeachingUnitForLearningSituation(
        situation: LearningSituation,
        classId: Int64
    ) async throws -> Int64 {
        let linkedResources = try await container.learningSituationsRepository.listLinkedResources(learningSituationId: situation.id)
        if let existingResource = linkedResources.first(where: {
            $0.kind == .teachingUnit && ($0.classId == nil || $0.classId?.int64Value == classId)
        }),
           let unitId = Int64(existingResource.resourceId) {
            return unitId
        }

        let existingUnits = try await container.plannerRepository.listAllTeachingUnits()
        if let found = existingUnits.first(where: {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ==
            situation.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) &&
            ($0.schoolClassId?.int64Value == classId || $0.groupId?.int64Value == classId)
        }) {
            try await saveLearningSituationLinkedResource(
                situationId: situation.id,
                kind: .teachingUnit,
                resourceId: "\(found.id)",
                classId: classId,
                label: situation.title,
                trace: situation.trace
            )
            return found.id
        }

        let unit = TeachingUnit(
            id: 0,
            name: situation.title,
            description: "Situación de aprendizaje: \(situation.challenge)",
            colorHex: plannerCourseColor(for: classId),
            groupId: KotlinLong(value: classId),
            schoolClassId: KotlinLong(value: classId),
            startDate: nil,
            endDate: nil
        )
        let unitId = try await container.plannerRepository.upsertTeachingUnit(unit: unit).int64Value
        try await saveLearningSituationLinkedResource(
            situationId: situation.id,
            kind: .teachingUnit,
            resourceId: "\(unitId)",
            classId: classId,
            label: situation.title,
            trace: situation.trace
        )
        return unitId
    }

    func repairLearningSituationAssessmentInstrumentImportIfNeeded(classId: Int64) async throws {
        let repairedLevels = try await repairAssessmentInstrumentRubricLevelPoints(classId: classId)
        let repairedColumns = try await repairAssessmentInstrumentNotebookColumns(classId: classId)
        let repairedEvaluations = try await repairAssessmentInstrumentEvaluations(classId: classId)
        let repairedTemplates = try await repairStructuredAssessmentInstrumentTemplates(classId: classId)
        let repairedRubricUnits = try await repairAssessmentInstrumentRubricTeachingUnits(classId: classId)
        let repairedDescriptions = try await repairCorruptedEvaluationDescriptions(classId: classId)
        let repairedCriteria = try await repairAssessmentInstrumentCriterionDescriptions(classId: classId)
        if repairedLevels || repairedColumns || repairedEvaluations || repairedTemplates || repairedRubricUnits || repairedDescriptions || repairedCriteria {
            refreshCurrentNotebook()
            scheduleNotebookSnapshotSync(forClassId: classId)
        }
    }

    private func repairAssessmentInstrumentRubricTeachingUnits(classId: Int64) async throws -> Bool {
        let allSituations = try await container.learningSituationsRepository.listSituations()
        var situations: [LearningSituation] = []
        for candidate in allSituations {
            let links = try await container.learningSituationsRepository.listClassLinks(learningSituationId: candidate.id)
            if links.contains(where: { $0.classId == classId }) {
                situations.append(candidate)
            }
        }
        guard !situations.isEmpty else { return false }

        let rubrics = try await container.rubricsRepository.listRubrics()
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        for situation in situations {
            let teachingUnitId = try await ensureTeachingUnitForLearningSituation(situation: situation, classId: classId)
            let linkedResources = try await container.learningSituationsRepository.listLinkedResources(learningSituationId: situation.id)

            for resource in linkedResources where resource.kind == .rubric {
                guard let rubricId = Int64(resource.resourceId),
                      let detail = rubrics.first(where: { $0.rubric.id == rubricId }),
                      detail.rubric.teachingUnitId?.int64Value != teachingUnitId else { continue }

                _ = try await container.rubricsRepository.saveRubric(
                    id: KotlinLong(value: detail.rubric.id),
                    name: detail.rubric.name,
                    description: detail.rubric.description,
                    classId: detail.rubric.classId ?? KotlinLong(value: classId),
                    teachingUnitId: KotlinLong(value: teachingUnitId),
                    createdAtEpochMs: detail.rubric.trace.createdAt.toEpochMilliseconds(),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: detail.rubric.trace.syncVersion
                )
                didRepair = true
            }

            for resource in linkedResources where resource.kind == .evaluation {
                guard let evaluationId = Int64(resource.resourceId),
                      let ev = evaluations.first(where: { $0.id == evaluationId }),
                      let rubricId = ev.rubricId?.int64Value,
                      let detail = rubrics.first(where: { $0.rubric.id == rubricId }),
                      detail.rubric.teachingUnitId?.int64Value != teachingUnitId else { continue }

                _ = try await container.rubricsRepository.saveRubric(
                    id: KotlinLong(value: detail.rubric.id),
                    name: detail.rubric.name,
                    description: detail.rubric.description,
                    classId: detail.rubric.classId ?? KotlinLong(value: classId),
                    teachingUnitId: KotlinLong(value: teachingUnitId),
                    createdAtEpochMs: detail.rubric.trace.createdAt.toEpochMilliseconds(),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: detail.rubric.trace.syncVersion
                )
                didRepair = true
            }
        }

        if didRepair {
            try? await refreshRubrics()
            try? await refreshRubricClassLinks()
        }
        return didRepair
    }

    private func saveAssessmentInstrumentRubricIfNeeded(
        instrument: AssessmentInstrumentDraft,
        classId: Int64,
        teachingUnitId: Int64? = nil,
        sourceFileName: String
    ) async throws -> Int64? {
        guard instrument.kind == .rubric else { return nil }
        guard let rubric = instrument.rubric, !rubric.criteria.isEmpty, !rubric.levels.isEmpty else {
            return nil
        }
        let existingRubrics = try await container.rubricsRepository.listRubrics()
        if let matching = existingRubrics.first(where: {
            $0.rubric.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ==
            instrument.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }) {
            return matching.rubric.id
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rubricId = try await container.rubricsRepository.saveRubric(
            id: nil,
            name: instrument.title,
            description: "Importada desde \(sourceFileName)",
            classId: KotlinLong(value: classId),
            teachingUnitId: teachingUnitId.map { KotlinLong(value: $0) },
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value

        for (criterionIndex, criterion) in rubric.criteria.enumerated() {
            let criterionId = try await container.rubricsRepository.saveCriterion(
                id: nil,
                rubricId: rubricId,
                description: criterion.title,
                weight: criterion.weight,
                order: Int32(criterionIndex),
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            for (levelIndex, level) in rubric.levels.enumerated() {
                let description = levelIndex < criterion.descriptors.count
                    ? criterion.descriptors[levelIndex].nilIfBlank
                    : nil
                _ = try await container.rubricsRepository.saveLevel(
                    id: nil,
                    criterionId: criterionId,
                    name: level.label,
                    points: Int32(level.points),
                    description: description,
                    order: Int32(levelIndex),
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: 1
                )
            }
        }
        try? await refreshRubrics()
        try? await refreshRubricClassLinks()
        return rubricId
    }

    private func saveAssessmentInstrumentTemplateIfNeeded(
        instrument: AssessmentInstrumentDraft,
        classId: Int64,
        evaluationId: Int64,
        columnId: String,
        sourceFileName: String
    ) async throws {
        let items = assessmentInstrumentItems(for: instrument, columnId: columnId)
        guard !items.isEmpty else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let template = NotebookInstrumentTemplate(
            id: "template_\(columnId)",
            classId: classId,
            columnId: columnId,
            evaluationId: KotlinLong(value: evaluationId),
            title: instrument.title,
            kind: templateKind(for: instrument.kind),
            inputKind: structuredInputKind(for: instrument.kind),
            source: sourceFileName,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: nowInstant,
                updatedAt: nowInstant,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            )
        )
        try await container.notebookInstrumentsRepository.saveTemplate(template: template, items: items)
    }
    private func ensureNotebookColumnForAssessmentInstrument(
        classId: Int64,
        evaluationId: Int64,
        title: String,
        rubricId: Int64?,
        instrument: AssessmentInstrumentDraft,
        situationTitle: String,
        targetTabId: String?
    ) async throws -> String {
        if let existingColumnId = try await container.notebookRepository.getColumnIdForEvaluation(evaluationId: evaluationId) {
            return existingColumnId
        }
        let targetTabId = try await resolveNotebookTargetTabId(classId: classId, preferredTabId: targetTabId)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let resolvedWeight = instrument.weightPercent ?? 0
        let columnId = "eval_\(evaluationId)"
        let column = NotebookColumnDefinition(
            id: columnId,
            title: title,
            type: notebookColumnType(for: instrument, rubricId: rubricId),
            categoryKind: .evaluation,
            instrumentKind: notebookInstrumentKind(for: instrument.kind),
            inputKind: notebookInputKind(for: instrument, rubricId: rubricId),
            evaluationId: KotlinLong(value: evaluationId),
            rubricId: rubricId.map { KotlinLong(value: $0) },
            formula: nil,
            weight: resolvedWeight,
            dateEpochMs: nil,
            unitOrSituation: situationTitle,
            competencyCriteriaIds: [],
            scaleKind: notebookScaleKind(for: instrument, rubricId: rubricId),
            tabIds: [targetTabId],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: -1,
            widthDp: 132,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: instrument.countsTowardAverage &&
                resolvedWeight > 0 &&
                canMaterializeAverage(for: instrument.scoreStrategy),
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: notebookEmptyCellPolicy(for: instrument.emptyCellPolicy),
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: nowInstant,
                updatedAt: nowInstant,
                associatedGroupId: KotlinLong(value: classId),
                deviceId: localDeviceId,
                syncVersion: 1
            )
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        return columnId
    }

    func resolveNotebookTargetTabId(classId: Int64, preferredTabId: String?) async throws -> String {
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        if let preferredTabId, tabs.contains(where: { $0.id == preferredTabId }) {
            return preferredTabId
        }
        if let candidateTitle = preferredTabId?.trimmingCharacters(in: .whitespacesAndNewlines), !candidateTitle.isEmpty {
            if let match = tabs.first(where: { $0.title.caseInsensitiveCompare(candidateTitle) == .orderedSame }) {
                return match.id
            }
            let createdTitle = try await container.notebookRepository.createTab(classId: classId, tabName: candidateTitle)
            let refreshedTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
            return refreshedTabs.first(where: { $0.title.caseInsensitiveCompare(createdTitle) == .orderedSame })?.id ?? refreshedTabs.first?.id ?? "TAB_\(classId)"
        }
        if let first = tabs.first?.id {
            return first
        }
        let createdTitle = try await container.notebookRepository.createTab(classId: classId, tabName: "Evaluación")
        let refreshedTabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        return refreshedTabs.first(where: { $0.title == createdTitle })?.id ?? refreshedTabs.first?.id ?? "TAB_\(classId)"
    }

    private func templateKind(for kind: AssessmentInstrumentKind) -> NotebookInstrumentTemplateKind {
        switch kind {
        case .checklist, .submissionChecklist:
            return .checklist
        case .teacherObservation:
            return .observation
        case .observationGrid:
            return .form
        case .rubric:
            return .form
        case .quizQuestions:
            return .quiz
        case .selfAssessment, .peerAssessment:
            return .form
        }
    }

    private func structuredInputKind(for kind: AssessmentInstrumentKind) -> NotebookCellInputKind {
        switch kind {
        case .checklist, .submissionChecklist:
            return .structuredChecklist
        case .teacherObservation:
            return .structuredObservation
        case .observationGrid:
            return .structuredForm
        case .rubric:
            return .structuredForm
        case .quizQuestions:
            return .structuredQuiz
        case .selfAssessment, .peerAssessment:
            return .structuredForm
        }
    }

    private func assessmentInstrumentItems(for instrument: AssessmentInstrumentDraft, columnId: String) -> [NotebookInstrumentItem] {
        let normalizedTitle = instrument.title.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalizedTitle == "daily workout log" {
            var specs: [(String, String, NotebookInstrumentItemType, [String])] = []
            for index in 1...4 {
                specs.append(("exercise_\(index)_level", "Ejercicio \(index) · Nivel", .text, []))
                specs.append(("exercise_\(index)_volume", "Ejercicio \(index) · Volumen / reps", .text, []))
                specs.append(("exercise_\(index)_rpe", "Ejercicio \(index) · RPE 1-10", .number, []))
                specs.append(("exercise_\(index)_safe", "Ejercicio \(index) · Técnica segura", .choice, ["Yes", "No"]))
                specs.append(("exercise_\(index)_coach_note", "Ejercicio \(index) · Nota del coach", .text, []))
            }
            specs.append(("peak_hr", "Peak radial HR (6 seconds x 10)", .number, []))
            specs.append(("hr_after_1_min", "Radial HR after 1 minute", .number, []))
            specs.append(("net_recovery", "Net recovery", .number, []))
            specs.append(("coach_signature", "Coach signature", .text, []))
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        if normalizedTitle == "diagnostic record sheet - session 1" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("adapted_pushups", "Adapted push-ups 1'", .number, []),
                ("sit_and_reach", "Sit-and-reach", .text, []),
                ("resting_radial_hr", "Resting radial HR", .number, []),
                ("goal_chosen", "Goal chosen", .choice, ["Strength", "Cardio"]),
                ("initial_observation", "Initial observation", .text, []),
            ])
        }

        if normalizedTitle == "teacher observation grid ce 2.2 - execution and self-regulation" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("technique", "Technique", .scale14, []),
                ("rpe_target", "RPE target", .scale14, []),
                ("reliable_log", "Reliable log", .scale14, []),
                ("intensity_adjustment", "Intensity adjustment", .scale14, []),
                ("motor_engagement", "Motor engagement", .scale14, []),
                ("mark", "Mark", .number, []),
            ])
        }

        if normalizedTitle == "adjustment sheet - session 7" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("compared_data", "Compared data: HR / reps / RPE / recovery", .text, []),
                ("change_applied", "Change applied", .choice, ["+10% volume", "shorter rest", "level change", "other"]),
                ("reason", "Reason", .text, []),
                ("technique_safe", "Is technique still safe?", .choice, ["Yes", "Needs adaptation"]),
            ])
        }

        if normalizedTitle == "healthy habits quiz - session 8" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("hydration", "Best hydration option for normal PE", .choice, ["water", "energy drink", "soft drink"]),
                ("sleep", "Recommended sleep duration for teenagers", .text, []),
                ("protein_shakes", "Protein shakes are necessary for every active teenager", .choice, ["True", "False"]),
                ("water_estimate", "Estimate daily water for 60 kg: 60 / 30", .number, []),
                ("caffeine_effect", "A high-caffeine, high-sugar drink before PE may affect", .choice, ["sleep", "HR", "hydration habits", "all"]),
            ])
        }

        if normalizedTitle == "quiz de cierre del rol coach y pasaporte saludable" {
            return makeInstrumentItems(columnId: columnId, specs: [
                ("coach_registro", "He registrado tiempos, repeticiones o RPE de forma responsable.", .scale14, []),
                ("coach_seguridad", "He observado la técnica y he avisado con respeto ante riesgos o ajustes necesarios.", .scale14, []),
                ("coach_feedback", "He ofrecido un feedback concreto, respetuoso y útil a mi compañero/a.", .scale14, []),
                ("coach_cooperacion", "He cumplido mi rol y he colaborado para que ambos pudiéramos entrenar con seguridad.", .scale14, []),
                ("proximo_paso", "Identifico un ajuste realista para mejorar como deportista o como Coach.", .scale14, []),
                ("evidencia_feedback", "Describe el mejor feedback que diste o recibiste. ¿Qué ocurrió y por qué fue útil?", .text, []),
                ("compromiso", "¿Qué acción concreta aplicarás en tu próxima práctica?", .text, []),
            ])
        }

        // Instrumento mixto que rellena el alumnado: los indicadores de la rúbrica van con clave
        // `rub_<n>` y escala 1-4 (de ahí deriva la nota `NotebookInstrumentsRepositorySqlDelight`)
        // y las preguntas de reflexión con clave `open_<n>`, que no intervienen en la nota.
        if instrument.kind.isStudentAuthored {
            var specs: [(String, String, NotebookInstrumentItemType, [String])] = []
            var helpTextByKey: [String: String] = [:]
            for (index, criterion) in (instrument.rubric?.criteria ?? []).enumerated() {
                let key = "rub_\(index + 1)"
                specs.append((key, criterion.title, .scale14, []))
                // La plantilla del Cuaderno no guarda etiquetas por nivel, así que los cuatro
                // descriptores de la rúbrica viajan en el texto de ayuda: es lo que ve el
                // alumnado al responder, también en el formulario web publicado.
                let descriptors = zip(instrument.rubric?.levels ?? [], criterion.descriptors)
                    .map { level, descriptor in "\(level.label): \(descriptor)" }
                    .joined(separator: " · ")
                if !descriptors.isEmpty { helpTextByKey[key] = descriptors }
            }
            for (index, question) in instrument.quizQuestions.enumerated() {
                let itemType: NotebookInstrumentItemType = question.options.isEmpty ? .text : .choice
                specs.append(("open_\(index + 1)", question.questionText, itemType, question.options))
            }
            return makeInstrumentItems(columnId: columnId, specs: specs, helpTextByKey: helpTextByKey)
        }

        if !instrument.checklistItems.isEmpty {
            // La checklist ponderada usa el prefijo de clave `chkp_` para que
            // `NotebookInstrumentsRepositorySqlDelight.saveResponses` derive su nota
            // proporcional (ítems marcados / total × 10). Las checklists de requisito de
            // entrega y las de todo/nada mantienen `check_` y no generan nota automática.
            let keyPrefix = instrument.scoreStrategy == .checklistProportional ? "chkp" : "check"
            let specs = instrument.checklistItems.enumerated().map { index, item in
                ("\(keyPrefix)_\(index + 1)", item.title, NotebookInstrumentItemType.check, [] as [String])
            }
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        if !instrument.observationFields.isEmpty {
            let specs = instrument.observationFields.enumerated().map { index, field in
                (field.key ?? "field_\(index + 1)", field.title, NotebookInstrumentItemType.scale14, [] as [String])
            }
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        if !instrument.quizQuestions.isEmpty {
            let specs = instrument.quizQuestions.enumerated().map { index, question -> (String, String, NotebookInstrumentItemType, [String]) in
                let itemType: NotebookInstrumentItemType = question.options.isEmpty ? .text : .choice
                return ("question_\(index + 1)", question.questionText, itemType, question.options)
            }
            return makeInstrumentItems(columnId: columnId, specs: specs)
        }

        return []
    }

    private func makeInstrumentItems(
        columnId: String,
        specs: [(String, String, NotebookInstrumentItemType, [String])],
        helpTextByKey: [String: String] = [:]
    ) -> [NotebookInstrumentItem] {
        let templateId = "template_\(columnId)"
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        return specs.enumerated().map { index, spec in
            NotebookInstrumentItem(
                id: "\(templateId)_\(spec.0)",
                templateId: templateId,
                key: spec.0,
                title: spec.1,
                type: spec.2,
                options: spec.3,
                required: true,
                order: Int32(index),
                helpText: helpTextByKey[spec.0],
                trace: AuditTrace(
                    authorUserId: nil,
                    createdAt: nowInstant,
                    updatedAt: nowInstant,
                    associatedGroupId: nil,
                    deviceId: localDeviceId,
                    syncVersion: 1
                )
            )
        }
    }
    private func repairAssessmentInstrumentRubricLevelPoints(classId: Int64) async throws -> Bool {
        let targetNames: Set<String> = ["Plan Design Rubric", "Peer-Coaching Rubric"]
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let importedRubrics = try await container.rubricsRepository.listRubrics().filter { detail in
            targetNames.contains(detail.rubric.name) && detail.rubric.classId?.int64Value == classId
        }
        var didRepair = false
        for detail in importedRubrics {
            for criterion in detail.criteria {
                for level in criterion.levels {
                    let expectedPoints = level.order + 1
                    guard level.points != expectedPoints else { continue }
                    _ = try await container.rubricsRepository.saveLevel(
                        id: KotlinLong(value: level.id),
                        criterionId: level.criterionId,
                        name: level.name,
                        points: Int32(expectedPoints),
                        description: level.description,
                        order: Int32(level.order),
                        updatedAtEpochMs: nowMs,
                        deviceId: localDeviceId,
                        syncVersion: level.trace.syncVersion
                    )
                    didRepair = true
                }
            }
        }
        if didRepair {
            try? await refreshRubrics()
            try? await refreshRubricClassLinks()
        }
        return didRepair
    }

    private func repairAssessmentInstrumentNotebookColumns(classId: Int64) async throws -> Bool {
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        var didRepair = false

        for column in columns {
            // Rejilla de observación con nota derivada de respuestas 1-4 (ver
            // notebookInputKind/deriveObservationGridScore): ya está en el estado correcto
            // (numérica, computable) aunque tenga una plantilla estructurada asociada. Sin
            // este guard, la rama genérica de más abajo la degradaría a .text/.custom
            // (auxiliar sin nota) en cuanto detectara esa plantilla.
            if column.type == .numeric, column.scaleKind == .fourLevel {
                continue
            }

            var repairType = column.type
            var repairInstrumentKind = column.instrumentKind
            var repairInputKind = column.inputKind
            var repairScaleKind = column.scaleKind

            if let repair = assessmentInstrumentColumnRepair(for: column.title) {
                repairType = repair.type
                repairInstrumentKind = repair.instrumentKind
                repairInputKind = repair.inputKind
                repairScaleKind = repair.scaleKind
            } else if let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id) {
                repairType = .text
                repairScaleKind = .custom
                
                let templateInputKind = detail.template_.inputKind
                repairInputKind = templateInputKind
                
                switch detail.template_.kind {
                case .checklist:
                    repairInstrumentKind = .checklist
                case .observation:
                    repairInstrumentKind = .systematicObservation
                case .form:
                    if templateInputKind == NotebookCellInputKind.structuredQuiz {
                        repairInstrumentKind = .checklist
                    } else {
                        repairInstrumentKind = .dailyWork
                    }
                default:
                    break
                }
            }

            guard column.type != repairType ||
                    column.instrumentKind != repairInstrumentKind ||
                    column.inputKind != repairInputKind ||
                    column.scaleKind != repairScaleKind else {
                continue
            }

            let repaired = NotebookColumnDefinition(
                id: column.id,
                title: column.title,
                type: repairType,
                categoryKind: .evaluation,
                instrumentKind: repairInstrumentKind,
                inputKind: repairInputKind,
                evaluationId: column.evaluationId,
                rubricId: nil,
                formula: column.formula,
                weight: column.weight,
                dateEpochMs: column.dateEpochMs,
                unitOrSituation: column.unitOrSituation,
                competencyCriteriaIds: column.competencyCriteriaIds,
                scaleKind: repairScaleKind,
                tabIds: column.tabIds,
                sessions: column.sessions,
                sharedAcrossTabs: column.sharedAcrossTabs,
                colorHex: column.colorHex,
                iconName: column.iconName,
                order: Int32(column.order),
                widthDp: column.widthDp,
                categoryId: column.categoryId,
                ordinalLevels: column.ordinalLevels,
                availableIcons: column.availableIcons,
                countsTowardAverage: column.countsTowardAverage,
                isPinned: column.isPinned,
                isHidden: column.isHidden,
                visibility: column.visibility,
                isLocked: column.isLocked,
                isTemplate: column.isTemplate,
                emptyCellPolicy: column.emptyCellPolicy,
                trace: AuditTrace(
                    authorUserId: nil,
                    createdAt: column.trace.createdAt,
                    updatedAt: nowInstant,
                    associatedGroupId: KotlinLong(value: classId),
                    deviceId: localDeviceId,
                    syncVersion: column.trace.syncVersion
                )
            )
            try await container.notebookConfigRepository.saveColumn(classId: classId, column: repaired)
            didRepair = true
        }
        return didRepair
    }

    private func repairStructuredAssessmentInstrumentTemplates(classId: Int64) async throws -> Bool {
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        var didRepair = false

        for column in columns {
            guard let instrument = importedAssessmentInstrumentDraft(for: column.title) else { continue }
            let existing = try await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id)
            guard existing == nil else { continue }
            try await saveAssessmentInstrumentTemplateIfNeeded(
                instrument: instrument,
                classId: classId,
                evaluationId: column.evaluationId?.int64Value ?? 0,
                columnId: column.id,
                sourceFileName: "instrumentos_evaluacion.docx"
            )
            didRepair = true
        }

        return didRepair
    }

    private func importedAssessmentInstrumentDraft(for title: String) -> AssessmentInstrumentDraft? {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Daily Workout Log":
            return repairAssessmentInstrumentDraft(title: title, kind: .observationGrid, criterionLabel: "CE 2.2")
        case "Diagnostic Record Sheet - Session 1":
            return repairAssessmentInstrumentDraft(title: title, kind: .observationGrid)
        case "Plan Safety Checklist - Session 2":
            return repairAssessmentInstrumentDraft(
                title: title,
                kind: .checklist,
                checklistItems: [
                    ChecklistItemDraft(title: "The 4 exercises have bronze/silver/gold levels.", required: true),
                    ChecklistItemDraft(title: "Technique can be performed without pain or obvious risk.", required: true),
                    ChecklistItemDraft(title: "Target RPE stays between 5 and 7 for the main part.", required: true),
                    ChecklistItemDraft(title: "Warm-up and cool-down are included.", required: true),
                    ChecklistItemDraft(title: "Rest time allows safe technique.", required: true),
                    ChecklistItemDraft(title: "The teacher has reviewed any doubtful or risky plan.", required: true),
                ]
            )
        case "Teacher Observation Grid CE 2.2 - Execution and self-regulation":
            return repairAssessmentInstrumentDraft(title: title, kind: .teacherObservation, criterionLabel: "CE 2.2")
        case "Adjustment Sheet - Session 7":
            return repairAssessmentInstrumentDraft(title: title, kind: .checklist)
        case "Healthy Habits Quiz - Session 8":
            return repairAssessmentInstrumentDraft(title: title, kind: .checklist)
        case "Quiz de cierre del rol Coach y Pasaporte Saludable":
            return repairAssessmentInstrumentDraft(
                title: title,
                kind: .quizQuestions,
                criterionLabel: "CE 3.2",
                quizQuestions: [
                    QuizQuestionDraft(questionText: "He registrado tiempos, repeticiones o RPE de forma responsable.", options: []),
                    QuizQuestionDraft(questionText: "He observado la técnica y he avisado con respeto ante riesgos o ajustes necesarios.", options: []),
                    QuizQuestionDraft(questionText: "He ofrecido un feedback concreto, respetuoso y útil a mi compañero/a.", options: []),
                    QuizQuestionDraft(questionText: "He cumplido mi rol y he colaborado para que ambos pudiéramos entrenar con seguridad.", options: []),
                    QuizQuestionDraft(questionText: "Identifico un ajuste realista para mejorar como deportista o como Coach.", options: []),
                    QuizQuestionDraft(questionText: "Describe el mejor feedback que diste o recibiste. ¿Qué ocurrió y por qué fue útil?", options: []),
                    QuizQuestionDraft(questionText: "¿Qué acción concreta aplicarás en tu próxima práctica?", options: []),
                ]
            )
        case "Final Submission Checklist":
            return repairAssessmentInstrumentDraft(
                title: title,
                kind: .submissionChecklist,
                checklistItems: [
                    ChecklistItemDraft(title: "Baseline diagnosis complete.", required: true),
                    ChecklistItemDraft(title: "FITT-PV plan validated.", required: true),
                    ChecklistItemDraft(title: "Logs for S3, S4, S5, S6, S7 and S9.", required: true),
                    ChecklistItemDraft(title: "Session 7 adjustment explained.", required: true),
                    ChecklistItemDraft(title: "Habits quiz completed.", required: true),
                    ChecklistItemDraft(title: "Peer Coach assessment signed.", required: true),
                    ChecklistItemDraft(title: "Final self-assessment complete.", required: true),
                ]
            )
        default:
            return nil
        }
    }

    private func repairAssessmentInstrumentDraft(
        title: String,
        kind: AssessmentInstrumentKind,
        criterionLabel: String? = nil,
        checklistItems: [ChecklistItemDraft] = [],
        quizQuestions: [QuizQuestionDraft] = []
    ) -> AssessmentInstrumentDraft {
        AssessmentInstrumentDraft(
            title: title,
            kind: kind,
            criterionLabel: criterionLabel,
            weightPercent: nil,
            isSelected: true,
            countsTowardAverage: false,
            scoreStrategy: .none,
            rubric: nil,
            checklistItems: checklistItems,
            quizQuestions: quizQuestions
        )
    }

    private func repairAssessmentInstrumentEvaluations(classId: Int64) async throws -> Bool {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        var didRepair = false
        for evaluation in evaluations {
            let currentRubricId = evaluation.rubricId?.int64Value
            let targetRepair = assessmentInstrumentColumnRepair(for: evaluation.name)
            let shouldClearImportedRubric = targetRepair != nil && targetRepair?.type != .rubric && currentRubricId != nil
            let shouldClearZeroRubric = currentRubricId == 0
            guard shouldClearImportedRubric || shouldClearZeroRubric else { continue }
            _ = try await container.evaluationsRepository.saveEvaluation(
                id: KotlinLong(value: evaluation.id),
                classId: classId,
                code: evaluation.code,
                name: evaluation.name,
                type: evaluation.type,
                weight: evaluation.weight,
                formula: evaluation.formula,
                rubricId: nil,
                description: evaluation.description_,
                authorUserId: evaluation.trace.authorUserId,
                createdAtEpochMs: evaluation.trace.createdAt.toEpochMilliseconds(),
                updatedAtEpochMs: 0,
                associatedGroupId: evaluation.trace.associatedGroupId,
                deviceId: localDeviceId,
                syncVersion: evaluation.trace.syncVersion
            )
            didRepair = true
        }
        return didRepair
    }

    private struct AssessmentInstrumentColumnRepair {
        let type: NotebookColumnType
        let instrumentKind: NotebookInstrumentKind
        let inputKind: NotebookCellInputKind
        let scaleKind: NotebookScaleKind
    }

    private func assessmentInstrumentColumnRepair(for title: String) -> AssessmentInstrumentColumnRepair? {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Plan Design Rubric", "Peer-Coaching Rubric":
            return AssessmentInstrumentColumnRepair(type: .rubric, instrumentKind: .rubric, inputKind: .rubric, scaleKind: .tenPoint)
        case "Daily Workout Log", "Diagnostic Record Sheet - Session 1":
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .dailyWork, inputKind: .structuredForm, scaleKind: .custom)
        case "Plan Safety Checklist - Session 2", "Adjustment Sheet - Session 7", "Healthy Habits Quiz - Session 8":
            let inputKind: NotebookCellInputKind = title == "Healthy Habits Quiz - Session 8" ? .structuredQuiz : (title == "Adjustment Sheet - Session 7" ? .structuredForm : .structuredChecklist)
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .checklist, inputKind: inputKind, scaleKind: .custom)
        case "Final Submission Checklist":
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .finalProduct, inputKind: .structuredChecklist, scaleKind: .custom)
        case "Teacher Observation Grid CE 2.2 - Execution and self-regulation":
            return AssessmentInstrumentColumnRepair(type: .text, instrumentKind: .systematicObservation, inputKind: .structuredObservation, scaleKind: .custom)
        default:
            return nil
        }
    }

    private func notebookColumnType(for instrument: AssessmentInstrumentDraft, rubricId: Int64?) -> NotebookColumnType {
        if rubricId != nil { return .rubric }
        switch instrument.scoreStrategy {
        case .numeric0To10, .observationScale1To4:
            return .numeric
        case .checklistAllOrNothing:
            return .check
        case .rubric:
            return .numeric
        case .quizPercentCorrect:
            return .numeric
        // La checklist ponderada materializa nota 0-10 derivada de los ítems marcados, así que
        // su columna es numérica como la de la rejilla de observación (la entrada sigue siendo
        // la checklist estructurada).
        case .checklistProportional:
            return .numeric
        case .none:
            return .text
        }
    }

    private func canMaterializeAverage(for strategy: AssessmentInstrumentScoreStrategy) -> Bool {
        switch strategy {
        case .numeric0To10, .rubric, .checklistAllOrNothing, .observationScale1To4,
             .quizPercentCorrect, .checklistProportional:
            return true
        case .none:
            return false
        }
    }

    private func notebookInstrumentKind(for kind: AssessmentInstrumentKind) -> NotebookInstrumentKind {
        switch kind {
        case .rubric:
            return .rubric
        case .observationGrid:
            return .dailyWork
        case .checklist:
            return .checklist
        case .teacherObservation:
            return .systematicObservation
        case .submissionChecklist:
            return .finalProduct
        case .quizQuestions:
            return .writtenTest
        case .selfAssessment:
            return .selfAssessment
        case .peerAssessment:
            return .peerAssessment
        }
    }

    private func notebookInputKind(for instrument: AssessmentInstrumentDraft, rubricId: Int64?) -> NotebookCellInputKind {
        if rubricId != nil { return .rubric }
        switch instrument.scoreStrategy {
        case .numeric0To10:
            return .numeric010
        case .observationScale1To4:
            // La rejilla tiene una plantilla estructurada (sesiones × indicadores 1-4) con
            // nota derivada calculada en NotebookInstrumentsRepositorySqlDelight.saveResponses:
            // abre el sheet estructurado en vez de una casilla numérica manual. El tipo de
            // columna sigue siendo .numeric (ver notebookColumnType) para que cuente en la media.
            return .structuredObservation
        case .checklistAllOrNothing:
            return .check
        case .rubric:
            return .numeric010
        case .quizPercentCorrect:
            return .percentage
        case .checklistProportional, .none:
            break
        }
        switch instrument.kind {
        case .checklist, .submissionChecklist:
            return .structuredChecklist
        case .teacherObservation:
            return .structuredObservation
        case .observationGrid:
            return .structuredForm
        case .rubric:
            return .numeric010
        case .quizQuestions:
            return .structuredQuiz
        case .selfAssessment, .peerAssessment:
            return .structuredForm
        }
    }

    private func notebookScaleKind(for instrument: AssessmentInstrumentDraft, rubricId: Int64?) -> NotebookScaleKind {
        if rubricId != nil { return .tenPoint }
        switch instrument.scoreStrategy {
        case .numeric0To10, .rubric:
            return .tenPoint
        case .observationScale1To4:
            return .fourLevel
        case .checklistAllOrNothing:
            return .yesNo
        case .quizPercentCorrect:
            return .percentage
        // Nota derivada 0-10 (ítems marcados / total × 10).
        case .checklistProportional:
            return .tenPoint
        case .none:
            return .custom
        }
    }

    private func notebookEmptyCellPolicy(for policy: AssessmentInstrumentEmptyCellPolicy) -> NotebookEmptyCellPolicy {
        switch policy {
        case .excludeFromAverage:
            return .excludeFromAverage
        case .countAsZero:
            return .countAsZero
        }
    }

    private func saveLearningSituationLinkedResource(
        situationId: Int64,
        kind: LearningSituationResourceKind,
        resourceId: String,
        classId: Int64?,
        label: String,
        trace: AuditTrace
    ) async throws {
        _ = try await container.learningSituationsRepository.saveLinkedResource(
            resource: LearningSituationLinkedResource(
                id: 0,
                learningSituationId: situationId,
                kind: kind,
                resourceId: resourceId,
                classId: classId.map { KotlinLong(value: $0) },
                label: label,
                trace: trace
            )
        )
        enqueueLocalChange(
            entity: "learning_situation_link",
            id: "\(situationId)-\(kind.name)-\(resourceId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "learningSituationId": situationId,
                "kind": kind.name,
                "resourceId": resourceId,
                "classId": classId ?? NSNull(),
                "label": label
            ]
        )
    }

    private func learningSituationSyncPayload(id: Int64, draft: LearningSituationImportDraft) -> [String: Any] {
        [
            "id": id, "title": draft.title, "stageLabel": draft.stageLabel,
            "courseLabel": draft.courseLabel, "subjectLabel": draft.subjectLabel,
            "termLabel": draft.termLabel, "centerLabel": draft.centerLabel,
            "sessionCount": draft.sessionCount, "challenge": draft.challenge,
            "finalProduct": draft.finalProduct, "payloadJson": draft.payloadJSON,
            "status": "ACTIVE"
        ]
    }

    private func uploadLearningSituationDocumentIfPaired(at url: URL, sha256: String) async throws {
        guard let host = pairedSyncHost, let token = syncToken else { return }
        try await lanSyncClient.uploadDocument(
            host: host,
            token: token,
            sha256: sha256,
            fileURL: url,
            pinnedFingerprint: pairedServerFingerprint
        )
    }

    func downloadLearningSituationDocumentIfNeeded(sha256: String) async -> String? {
        let store = LearningSituationDocumentStore()
        let destination = store.directoryURL.appendingPathComponent("\(sha256).docx")
        if let existing = try? Data(contentsOf: destination) {
            let actualHash = SHA256.hash(data: existing).map { String(format: "%02x", $0) }.joined()
            if actualHash == sha256 { return destination.path }
        }
        guard let host = pairedSyncHost, let token = syncToken else { return nil }
        do {
            try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
            let data = try await lanSyncClient.downloadDocument(
                host: host,
                token: token,
                sha256: sha256,
                pinnedFingerprint: pairedServerFingerprint
            )
            let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualHash == sha256 else { return nil }
            try data.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            return nil
        }
    }
}
