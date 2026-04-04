package com.migestor.shared.domain

enum class SessionJournalStatus {
    EMPTY,
    DRAFT,
    COMPLETED,
}

enum class SessionJournalDecision {
    NONE,
    REPEAT_SESSION,
    REINFORCE,
    ADVANCE,
}

enum class SessionJournalMediaType {
    PHOTO,
    AUDIO,
    TRANSCRIPT,
}

enum class SessionJournalLinkType {
    NOTEBOOK,
    ATTENDANCE,
    INCIDENT,
    FAMILY,
}

data class SessionJournal(
    val id: Long = 0,
    val planningSessionId: Long,
    val teacherName: String = "",
    val scheduledSpace: String = "",
    val usedSpace: String = "",
    val unitLabel: String = "",
    val objectivePlanned: String = "",
    val plannedText: String = "",
    val actualText: String = "",
    val attainmentText: String = "",
    val adaptationsText: String = "",
    val incidentsText: String = "",
    val groupObservations: String = "",
    val climateScore: Int = 0,
    val participationScore: Int = 0,
    val usefulTimeScore: Int = 0,
    val perceivedDifficultyScore: Int = 0,
    val pedagogicalDecision: SessionJournalDecision = SessionJournalDecision.NONE,
    val pendingTasksText: String = "",
    val materialToPrepareText: String = "",
    val studentsToReviewText: String = "",
    val familyCommunicationText: String = "",
    val nextStepText: String = "",
    val weatherText: String = "",
    val materialUsedText: String = "",
    val physicalIncidentsText: String = "",
    val injuriesText: String = "",
    val unequippedStudentsText: String = "",
    val intensityScore: Int = 0,
    val warmupMinutes: Int = 0,
    val mainPartMinutes: Int = 0,
    val cooldownMinutes: Int = 0,
    val stationObservationsText: String = "",
    val incidentTags: List<String> = emptyList(),
    val status: SessionJournalStatus = SessionJournalStatus.EMPTY,
)

data class SessionJournalEvaluation(
    val climateScore: Int = 0,
    val participationScore: Int = 0,
    val usefulTimeScore: Int = 0,
    val perceivedDifficultyScore: Int = 0,
    val intensityScore: Int = 0,
    val pedagogicalDecision: SessionJournalDecision = SessionJournalDecision.NONE,
)

data class SessionJournalIndividualNote(
    val id: Long = 0,
    val journalId: Long = 0,
    val studentId: Long? = null,
    val studentName: String = "",
    val note: String = "",
    val tag: String = "",
)

data class SessionJournalAction(
    val id: Long = 0,
    val journalId: Long = 0,
    val title: String,
    val detail: String = "",
    val isCompleted: Boolean = false,
)

data class SessionJournalMedia(
    val id: Long = 0,
    val journalId: Long = 0,
    val type: SessionJournalMediaType,
    val uri: String,
    val transcript: String = "",
    val caption: String = "",
)

data class SessionJournalLink(
    val id: Long = 0,
    val journalId: Long = 0,
    val type: SessionJournalLinkType,
    val targetId: String = "",
    val label: String = "",
)

data class SessionJournalAggregate(
    val journal: SessionJournal,
    val individualNotes: List<SessionJournalIndividualNote> = emptyList(),
    val actions: List<SessionJournalAction> = emptyList(),
    val media: List<SessionJournalMedia> = emptyList(),
    val links: List<SessionJournalLink> = emptyList(),
)

data class SessionJournalSummary(
    val planningSessionId: Long,
    val status: SessionJournalStatus = SessionJournalStatus.EMPTY,
    val participationScore: Int = 0,
    val climateScore: Int = 0,
    val usefulTimeScore: Int = 0,
    val usedSpace: String = "",
    val weatherText: String = "",
    val incidentTags: List<String> = emptyList(),
    val mediaCount: Int = 0,
)
