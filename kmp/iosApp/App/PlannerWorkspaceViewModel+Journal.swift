import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func loadJournalForSelectedSession() async {
        guard let bridge, let selectedSession else { return }
        autosaveTask?.cancel()
        do {
            let aggregate = try await bridge.plannerJournal(for: selectedSession)
            loadedAggregate = aggregate
            journalStore.loadedAggregate = aggregate
            replaceJournalDraft(PlannerJournalDraft(aggregate: aggregate))
            journalSaveState = .idle
            journalStore.journalSaveState = .idle
        } catch {
            loadedAggregate = nil
            journalStore.loadedAggregate = nil
            replaceJournalDraft(.empty)
            journalSaveState = .failed("No se pudo cargar el diario.")
            journalStore.journalSaveState = journalSaveState
        }
    }

    func scheduleAutosave() {
        guard !isHydratingDraft, selectedSession != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.saveJournal()
        }
    }

    func saveJournal() async {
        guard let bridge, let session = selectedSession else { return }
        autosaveTask?.cancel()
        journalSaveState = .saving
        let journalId = loadedAggregate?.journal.id ?? 0
        let status = computedStatus()
        let aggregate = SessionJournalAggregate(
            journal: SessionJournal(
                id: journalId,
                planningSessionId: session.id,
                teacherName: journalDraft.teacherName,
                scheduledSpace: journalDraft.scheduledSpace,
                usedSpace: journalDraft.usedSpace,
                unitLabel: journalDraft.unitLabel.isEmpty ? session.teachingUnitName : journalDraft.unitLabel,
                objectivePlanned: journalDraft.objectivePlanned,
                plannedText: journalDraft.plannedText,
                actualText: journalDraft.actualText,
                attainmentText: journalDraft.attainmentText,
                adaptationsText: journalDraft.adaptationsText,
                incidentsText: journalDraft.incidentsText,
                groupObservations: journalDraft.groupObservations,
                climateScore: Int32(journalDraft.climateScore),
                participationScore: Int32(journalDraft.participationScore),
                usefulTimeScore: Int32(journalDraft.usefulTimeScore),
                perceivedDifficultyScore: Int32(journalDraft.perceivedDifficultyScore),
                pedagogicalDecision: journalDraft.pedagogicalDecision,
                pendingTasksText: journalDraft.pendingTasksText,
                materialToPrepareText: journalDraft.materialToPrepareText,
                studentsToReviewText: journalDraft.studentsToReviewText,
                familyCommunicationText: journalDraft.familyCommunicationText,
                nextStepText: journalDraft.nextStepText,
                weatherText: journalDraft.weatherText,
                materialUsedText: journalDraft.materialUsedText,
                physicalIncidentsText: journalDraft.physicalIncidentsText,
                injuriesText: journalDraft.injuriesText,
                unequippedStudentsText: journalDraft.unequippedStudentsText,
                intensityScore: Int32(journalDraft.intensityScore),
                warmupMinutes: Int32(journalDraft.warmupMinutes),
                mainPartMinutes: Int32(journalDraft.mainPartMinutes),
                cooldownMinutes: Int32(journalDraft.cooldownMinutes),
                stationObservationsText: journalDraft.stationObservationsText,
                incidentTags: journalDraft.incidentTags,
                status: status
            ),
            individualNotes: journalDraft.notes.map {
                SessionJournalIndividualNote(
                    id: 0,
                    journalId: journalId,
                    studentId: $0.studentId.map { KotlinLong(value: $0) },
                    studentName: $0.studentName,
                    note: $0.note,
                    tag: $0.tag
                )
            },
            actions: journalDraft.actions.map {
                SessionJournalAction(
                    id: 0,
                    journalId: journalId,
                    title: $0.title,
                    detail: $0.detail,
                    isCompleted: $0.isCompleted
                )
            },
            media: journalDraft.media.map {
                SessionJournalMedia(
                    id: 0,
                    journalId: journalId,
                    type: $0.type,
                    uri: $0.uri,
                    transcript: $0.transcript,
                    caption: $0.caption
                )
            },
            links: journalDraft.links.map {
                SessionJournalLink(
                    id: 0,
                    journalId: journalId,
                    type: $0.type,
                    targetId: $0.targetId,
                    label: $0.label
                )
            }
        )

        do {
            _ = try await bridge.plannerSaveJournal(aggregate)
            loadedAggregate = try await bridge.plannerJournal(for: session)
            journalStore.loadedAggregate = loadedAggregate
            if let loadedAggregate {
                let refreshedDraft = PlannerJournalDraft(aggregate: loadedAggregate)
                if refreshedDraft != journalDraft {
                    replaceJournalDraft(refreshedDraft)
                }
            }
            let refreshedSummaries = (try? await bridge.plannerJournalSummaries(sessionIds: sessions.map(\.id))) ?? []
            journalSummaryBySessionId = Dictionary(uniqueKeysWithValues: refreshedSummaries.map { ($0.planningSessionId, $0) })
            journalStore.journalSummaryBySessionId = journalSummaryBySessionId
            journalSaveState = .saved(Date())
            journalStore.journalSaveState = journalSaveState
        } catch {
            journalSaveState = .failed(error.localizedDescription)
            journalStore.journalSaveState = journalSaveState
        }
    }

    func appendIncidentLink() async {
        guard let bridge, let session = selectedSession else { return }
        let title = journalDraft.incidentsText.nilIfBlank ?? "Incidencia de sesión"
        let detail = "Grupo \(session.groupName) · \(journalDraft.actualText.nilIfBlank ?? session.activities)"
        if let link = try? await bridge.plannerRegisterJournalIncident(session: session, title: title, detail: detail) {
            journalDraft.links.append(
                PlannerJournalDraftLink(
                    type: link.type,
                    targetId: link.targetId,
                    label: link.label
                )
            )
            if !journalDraft.incidentTags.contains("Incidencia") {
                journalDraft.incidentTags.append("Incidencia")
            }
        }
    }

    func appendTraceLink(type: SessionJournalLinkType, label: String) {
        journalDraft.links.append(
            PlannerJournalDraftLink(
                type: type,
                targetId: UUID().uuidString,
                label: label
            )
        )
    }

    func exportText() -> String {
        guard let session = selectedSession else { return "Sin sesión seleccionada" }
        return """
        Diario · \(session.teachingUnitName) · \(session.groupName)
        Objetivo previsto: \(journalDraft.objectivePlanned)
        Lo planificado: \(journalDraft.plannedText)
        Lo realizado: \(journalDraft.actualText)
        Participación: \(journalDraft.participationScore)/5
        Clima: \(journalDraft.climateScore)/5
        Tiempo útil: \(journalDraft.usefulTimeScore)/5
        Próximo paso: \(journalDraft.nextStepText)
        """
    }

    private func computedStatus() -> SessionJournalStatus {
        let importantFields = [
            journalDraft.actualText,
            journalDraft.plannedText,
            journalDraft.nextStepText,
            journalDraft.groupObservations
        ].joined()
        if importantFields.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && journalDraft.notes.isEmpty && journalDraft.actions.isEmpty {
            return .empty
        }
        let metricsReady = journalDraft.participationScore > 0 && journalDraft.climateScore > 0 && journalDraft.usefulTimeScore > 0
        let closingReady = !journalDraft.nextStepText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return metricsReady && closingReady ? .completed : .draft
    }

    private func replaceJournalDraft(_ draft: PlannerJournalDraft) {
        autosaveTask?.cancel()
        isHydratingDraft = true
        journalDraft = draft
        journalStore.journalDraft = draft
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.isHydratingDraft = false
        }
    }

    private static func isoWeeks(in year: Int) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let date = DateComponents(calendar: calendar, year: year, month: 12, day: 28).date ?? Date()
        return calendar.component(.weekOfYear, from: date)
    }

}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where !value.isEmpty: return value
        default: return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
