import Foundation
import MiGestorKit

extension KmpBridge {
    // MARK: - Reuniones de centro y actas (B-2)

    func meetings() async throws -> [MeetingSnapshot] {
        let rows = try await container.meetingRepository.listAll()
        return rows.compactMap(meetingSnapshot(from:))
    }

    func meeting(id: Int64) async throws -> MeetingSnapshot? {
        guard let row = try await container.meetingRepository.getById(id: id) else { return nil }
        return meetingSnapshot(from: row)
    }

    /// Acuerdos abiertos cuya fecha límite vence en o antes de `onOrBeforeIso`.
    func pendingMeetingAgreements(onOrBefore onOrBeforeIso: String) async throws -> [MeetingAgreementSnapshot] {
        let rows = try await container.meetingRepository.listPendingAgreements(onOrBeforeIso: onOrBeforeIso)
        return rows.map(meetingAgreementSnapshot(from:))
    }

    @discardableResult
    func saveMeeting(id: Int64? = nil, draft: MeetingDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.meetingRepository.saveMeeting(
            id: kotlinLong(id),
            title: draft.title,
            dateIso: draft.dateIso,
            type: kotlinMeetingType(draft.type),
            location: draft.location,
            attendees: draft.attendees,
            summary: draft.summary,
            isClosed: draft.isClosed,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "meetings",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "title": draft.title,
                "dateIso": draft.dateIso,
                "type": draft.type.rawValue,
                "location": draft.location,
                "attendees": draft.attendees,
                "summary": draft.summary,
                "isClosed": draft.isClosed
            ]
        )
        return savedId
    }

    func deleteMeeting(id: Int64) async throws {
        try await container.meetingRepository.deleteMeeting(id: id)
        enqueueLocalChange(
            entity: "meetings",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    @discardableResult
    func saveMeetingAgreement(id: Int64? = nil, draft: MeetingAgreementDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.meetingRepository.saveAgreement(
            id: kotlinLong(id),
            meetingId: draft.meetingId,
            description: draft.description,
            responsible: draft.responsible,
            dueIso: draft.dueIso,
            isDone: draft.isDone,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "meeting_agreements",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "meetingId": draft.meetingId,
                "description": draft.description,
                "responsible": draft.responsible,
                "dueIso": draft.dueIso ?? NSNull(),
                "isDone": draft.isDone
            ]
        )
        return savedId
    }

    func deleteMeetingAgreement(id: Int64) async throws {
        try await container.meetingRepository.deleteAgreement(id: id)
        enqueueLocalChange(
            entity: "meeting_agreements",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    /// `nil` si la fila trae un tipo que esta versión no conoce. Se descarta en
    /// vez de forzar un valor: mismo criterio que las tutorías.
    private func meetingSnapshot(from meeting: Meeting) -> MeetingSnapshot? {
        guard let type = MeetingTypeUI(rawValue: meeting.type.name) else { return nil }
        return MeetingSnapshot(
            id: meeting.id,
            title: meeting.title,
            dateIso: meeting.date.description(),
            type: type,
            location: meeting.location,
            attendees: meeting.attendees,
            summary: meeting.summary,
            isClosed: meeting.isClosed,
            agreements: meeting.agreements.map(meetingAgreementSnapshot(from:))
        )
    }

    private func meetingAgreementSnapshot(from agreement: MeetingAgreement) -> MeetingAgreementSnapshot {
        MeetingAgreementSnapshot(
            id: agreement.id,
            meetingId: agreement.meetingId,
            // `description_` con guion bajo: el nombre Kotlin `description` colisiona
            // con `-[NSObject description]`, y el puente lo renombra. Usar `.description`
            // devolvería el toString del objeto entero.
            description: agreement.description_,
            responsible: agreement.responsible,
            dueIso: agreement.due?.description(),
            isDone: agreement.isDone
        )
    }

    private func kotlinMeetingType(_ type: MeetingTypeUI) -> MeetingType {
        MeetingType.entries.first { $0.name == type.rawValue } ?? MeetingType.entries[0]
    }

    // MARK: - Plan pedagógico semanal (B-3)

    /// `nil` si aún no hay plan guardado para esa (clase, año, semana).
    func weekPlan(classId: Int64, year: Int, week: Int) async throws -> WeekPlanSnapshot? {
        guard let plan = try await container.plannerWeekPlanRepository.getPlan(
            classId: classId,
            year: Int32(year),
            week: Int32(week)
        ) else { return nil }
        return weekPlanSnapshot(from: plan)
    }

    @discardableResult
    func saveWeekPlan(id: Int64? = nil, draft: WeekPlanDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.plannerWeekPlanRepository.save(
            id: kotlinLong(id),
            classId: draft.classId,
            year: Int32(draft.year),
            week: Int32(draft.week),
            strategies: draft.strategyKeys,
            instruments: draft.instrumentKeys,
            notes: draft.notes,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "planner_week_plan",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "classId": draft.classId,
                "year": draft.year,
                "week": draft.week,
                "strategies": draft.strategyKeys,
                "instruments": draft.instrumentKeys,
                "notes": draft.notes
            ]
        )
        return savedId
    }

    private func weekPlanSnapshot(from plan: PlannerWeekPlan) -> WeekPlanSnapshot {
        WeekPlanSnapshot(
            id: plan.id,
            classId: plan.classId,
            year: Int(plan.year),
            week: Int(plan.week),
            strategyKeys: plan.strategies.map { String(describing: $0) },
            instrumentKeys: plan.instruments.map { String(describing: $0) },
            notes: plan.notes
        )
    }

}
