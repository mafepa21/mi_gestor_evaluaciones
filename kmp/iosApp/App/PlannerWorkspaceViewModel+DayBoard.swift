import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func selectDayInDayView(_ day: Int) {
        dayViewSelectedDay = day
    }

    func goToPreviousDayInDayView() async {
        let days = visibleWeekdays.sorted()
        guard !days.isEmpty else { return }
        guard let currentIndex = days.firstIndex(of: selectedDayForDayView) else {
            dayViewSelectedDay = days.last
            return
        }
        if currentIndex > 0 {
            dayViewSelectedDay = days[currentIndex - 1]
        } else {
            await previousWeek()
            dayViewSelectedDay = visibleWeekdays.sorted().last
        }
    }

    func goToNextDayInDayView() async {
        let days = visibleWeekdays.sorted()
        guard !days.isEmpty else { return }
        guard let currentIndex = days.firstIndex(of: selectedDayForDayView) else {
            dayViewSelectedDay = days.first
            return
        }
        if currentIndex < days.count - 1 {
            dayViewSelectedDay = days[currentIndex + 1]
        } else {
            await nextWeek()
            dayViewSelectedDay = visibleWeekdays.sorted().first
        }
    }

    func goToTodayInDayView() async {
        dayViewSelectedDay = nil
        await goToCurrentWeek()
    }

    /// Observación rápida de grupo desde la vista Día (≤2 gestos: escribir + guardar),
    /// sin necesidad de abrir la ficha completa del diario. Carga el diario de la
    /// sesión si aún no era la seleccionada, añade el texto a `groupObservations`
    /// (respetando lo que ya hubiera) y guarda.
    func quickAddObservation(to session: PlanningSession, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if selectedSession?.id != session.id {
            await select(session: session)
        }
        let existing = journalDraft.groupObservations.trimmingCharacters(in: .whitespacesAndNewlines)
        journalDraft.groupObservations = existing.isEmpty ? trimmed : "\(existing)\n\(trimmed)"
        await saveJournal()
    }

    /// Pulso rápido de la sesión (clima/tiempo útil/dificultad), mismo criterio que
    /// `SessionJournalQuickPulseCard` en el diario completo, sin abrir esa pantalla.
    func quickSetPulse(to session: PlanningSession, climate: Int, usefulTime: Int, difficulty: Int) async {
        if selectedSession?.id != session.id {
            await select(session: session)
        }
        journalDraft.climateScore = climate
        journalDraft.usefulTimeScore = usefulTime
        journalDraft.perceivedDifficultyScore = difficulty
        await saveJournal()
    }

    /// Participación rápida de la sesión, mismo criterio que `SessionJournalQuickPulseCard`.
    func quickSetParticipation(to session: PlanningSession, value: Int) async {
        if selectedSession?.id != session.id {
            await select(session: session)
        }
        journalDraft.participationScore = value
        await saveJournal()
    }
}
