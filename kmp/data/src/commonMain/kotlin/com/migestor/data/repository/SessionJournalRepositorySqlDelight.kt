package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionJournal
import com.migestor.shared.domain.SessionJournalAction
import com.migestor.shared.domain.SessionJournalAggregate
import com.migestor.shared.domain.SessionJournalDecision
import com.migestor.shared.domain.SessionJournalIndividualNote
import com.migestor.shared.domain.SessionJournalLink
import com.migestor.shared.domain.SessionJournalLinkType
import com.migestor.shared.domain.SessionJournalMedia
import com.migestor.shared.domain.SessionJournalMediaType
import com.migestor.shared.domain.SessionJournalStatus
import com.migestor.shared.domain.SessionJournalSummary
import com.migestor.shared.repository.SessionJournalRepository

class SessionJournalRepositorySqlDelight(
    private val db: AppDatabase,
) : SessionJournalRepository {

    override suspend fun getOrCreateJournal(session: PlanningSession): SessionJournalAggregate {
        getJournalForSession(session.id)?.let { return it }
        val journal = SessionJournal(
            planningSessionId = session.id,
            scheduledSpace = "",
            usedSpace = "",
            unitLabel = session.teachingUnitName,
            objectivePlanned = session.objectives,
            plannedText = session.activities,
            actualText = "",
            status = SessionJournalStatus.EMPTY,
        )
        val aggregate = SessionJournalAggregate(journal = journal)
        val savedId = saveJournalAggregate(aggregate)
        return getJournalForSession(session.id)
            ?: aggregate.copy(journal = aggregate.journal.copy(id = savedId))
    }

    override suspend fun getJournalForSession(planningSessionId: Long): SessionJournalAggregate? {
        val row = db.plannerQueries.selectJournalBySession(planningSessionId).executeAsOneOrNull() ?: return null
        val journal = row.toDomain()
        return SessionJournalAggregate(
            journal = journal,
            individualNotes = db.plannerQueries.selectJournalIndividualNotes(journal.id).executeAsList().map { note ->
                SessionJournalIndividualNote(
                    id = note.id,
                    journalId = note.journal_id,
                    studentId = note.student_id,
                    studentName = note.student_name,
                    note = note.note,
                    tag = note.tag,
                )
            },
            actions = db.plannerQueries.selectJournalActions(journal.id).executeAsList().map { action ->
                SessionJournalAction(
                    id = action.id,
                    journalId = action.journal_id,
                    title = action.title,
                    detail = action.detail,
                    isCompleted = action.is_completed != 0L,
                )
            },
            media = db.plannerQueries.selectJournalMedia(journal.id).executeAsList().map { media ->
                SessionJournalMedia(
                    id = media.id,
                    journalId = media.journal_id,
                    type = media.type.toEnum(SessionJournalMediaType.PHOTO),
                    uri = media.uri,
                    transcript = media.transcript,
                    caption = media.caption,
                )
            },
            links = db.plannerQueries.selectJournalLinks(journal.id).executeAsList().map { link ->
                SessionJournalLink(
                    id = link.id,
                    journalId = link.journal_id,
                    type = link.type.toEnum(SessionJournalLinkType.NOTEBOOK),
                    targetId = link.target_id,
                    label = link.label,
                )
            }
        )
    }

    override suspend fun listSummariesForSessions(planningSessionIds: List<Long>): List<SessionJournalSummary> {
        if (planningSessionIds.isEmpty()) return emptyList()
        return db.plannerQueries.selectJournalSummariesBySessions(planningSessionIds)
            .executeAsList()
            .map { row ->
                SessionJournalSummary(
                    planningSessionId = row.planning_session_id,
                    status = row.status.toEnum(SessionJournalStatus.EMPTY),
                    participationScore = row.participation_score.toInt(),
                    climateScore = row.climate_score.toInt(),
                    usefulTimeScore = row.useful_time_score.toInt(),
                    usedSpace = row.used_space,
                    weatherText = row.weather_text,
                    incidentTags = row.incident_tags_csv.csvList(),
                    mediaCount = row.media_count.toInt(),
                )
            }
    }

    override suspend fun saveJournalAggregate(aggregate: SessionJournalAggregate): Long {
        return db.transactionWithResult {
            val journal = aggregate.journal
            db.plannerQueries.upsertJournal(
                id = journal.id.takeIf { it > 0 },
                planning_session_id = journal.planningSessionId,
                teacher_name = journal.teacherName,
                scheduled_space = journal.scheduledSpace,
                used_space = journal.usedSpace,
                unit_label = journal.unitLabel,
                objective_planned = journal.objectivePlanned,
                planned_text = journal.plannedText,
                actual_text = journal.actualText,
                attainment_text = journal.attainmentText,
                adaptations_text = journal.adaptationsText,
                incidents_text = journal.incidentsText,
                group_observations = journal.groupObservations,
                climate_score = journal.climateScore.toLong(),
                participation_score = journal.participationScore.toLong(),
                useful_time_score = journal.usefulTimeScore.toLong(),
                perceived_difficulty_score = journal.perceivedDifficultyScore.toLong(),
                pedagogical_decision = journal.pedagogicalDecision.name,
                pending_tasks_text = journal.pendingTasksText,
                material_to_prepare_text = journal.materialToPrepareText,
                students_to_review_text = journal.studentsToReviewText,
                family_communication_text = journal.familyCommunicationText,
                next_step_text = journal.nextStepText,
                weather_text = journal.weatherText,
                material_used_text = journal.materialUsedText,
                physical_incidents_text = journal.physicalIncidentsText,
                injuries_text = journal.injuriesText,
                unequipped_students_text = journal.unequippedStudentsText,
                intensity_score = journal.intensityScore.toLong(),
                warmup_minutes = journal.warmupMinutes.toLong(),
                main_part_minutes = journal.mainPartMinutes.toLong(),
                cooldown_minutes = journal.cooldownMinutes.toLong(),
                station_observations_text = journal.stationObservationsText,
                incident_tags_csv = journal.incidentTags.joinToString("|"),
                status = journal.status.name,
            )

            val journalId = db.plannerQueries.selectJournalBySession(journal.planningSessionId)
                .executeAsOne()
                .id

            db.plannerQueries.deleteJournalIndividualNotes(journalId)
            aggregate.individualNotes.forEach { note ->
                db.plannerQueries.insertJournalIndividualNote(
                    journal_id = journalId,
                    student_id = note.studentId,
                    student_name = note.studentName,
                    note = note.note,
                    tag = note.tag,
                )
            }

            db.plannerQueries.deleteJournalActions(journalId)
            aggregate.actions.forEach { action ->
                db.plannerQueries.insertJournalAction(
                    journal_id = journalId,
                    title = action.title,
                    detail = action.detail,
                    is_completed = if (action.isCompleted) 1L else 0L,
                )
            }

            db.plannerQueries.deleteJournalMedia(journalId)
            aggregate.media.forEach { media ->
                db.plannerQueries.insertJournalMedia(
                    journal_id = journalId,
                    type = media.type.name,
                    uri = media.uri,
                    transcript = media.transcript,
                    caption = media.caption,
                )
            }

            db.plannerQueries.deleteJournalLinks(journalId)
            aggregate.links.forEach { link ->
                db.plannerQueries.insertJournalLink(
                    journal_id = journalId,
                    type = link.type.name,
                    target_id = link.targetId,
                    label = link.label,
                )
            }

            journalId
        }
    }

    override suspend fun deleteJournalForSession(planningSessionId: Long) {
        db.plannerQueries.deleteJournalBySession(planningSessionId)
    }

    private fun com.migestor.data.db.Session_journal.toDomain(): SessionJournal {
        return SessionJournal(
            id = id,
            planningSessionId = planning_session_id,
            teacherName = teacher_name,
            scheduledSpace = scheduled_space,
            usedSpace = used_space,
            unitLabel = unit_label,
            objectivePlanned = objective_planned,
            plannedText = planned_text,
            actualText = actual_text,
            attainmentText = attainment_text,
            adaptationsText = adaptations_text,
            incidentsText = incidents_text,
            groupObservations = group_observations,
            climateScore = climate_score.toInt(),
            participationScore = participation_score.toInt(),
            usefulTimeScore = useful_time_score.toInt(),
            perceivedDifficultyScore = perceived_difficulty_score.toInt(),
            pedagogicalDecision = pedagogical_decision.toEnum(SessionJournalDecision.NONE),
            pendingTasksText = pending_tasks_text,
            materialToPrepareText = material_to_prepare_text,
            studentsToReviewText = students_to_review_text,
            familyCommunicationText = family_communication_text,
            nextStepText = next_step_text,
            weatherText = weather_text,
            materialUsedText = material_used_text,
            physicalIncidentsText = physical_incidents_text,
            injuriesText = injuries_text,
            unequippedStudentsText = unequipped_students_text,
            intensityScore = intensity_score.toInt(),
            warmupMinutes = warmup_minutes.toInt(),
            mainPartMinutes = main_part_minutes.toInt(),
            cooldownMinutes = cooldown_minutes.toInt(),
            stationObservationsText = station_observations_text,
            incidentTags = incident_tags_csv.csvList(),
            status = status.toEnum(SessionJournalStatus.EMPTY),
        )
    }

    private fun String.csvList(): List<String> = split("|").map { it.trim() }.filter { it.isNotEmpty() }

    private inline fun <reified T : Enum<T>> String.toEnum(fallback: T): T {
        return enumValues<T>().firstOrNull { it.name == this } ?: fallback
    }
}
