import SwiftUI
import MiGestorKit

struct PlannerDayView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    private var sessions: [PlanningSession] { vm.daySessions() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.dayHeaderLabel(for: vm.selectedDayForDayView))
                            .font(.title2.weight(.black))
                        Text(daySubtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.openComposer(day: vm.selectedDayForDayView, period: vm.visibleSlots.first?.period ?? 1)
                    } label: {
                        Label("Nueva sesión", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if sessions.isEmpty {
                    PlannerEmptyState(
                        title: "Sin sesiones este día",
                        systemImage: "calendar.badge.plus",
                        message: "Usa Nueva sesión o vuelve a Semana para concretar una franja."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sessions, id: \.id) { session in
                            PlannerDaySessionRow(
                                vm: vm,
                                session: session,
                                isCurrent: isCurrent(session),
                                isNext: session.id == nextSession?.id,
                                onOpen: { onOpenSession(session) },
                                onComplete: { Task { await vm.markCompleted(session) } }
                            )
                        }
                    }
                }
            }
            .padding(EvaluationDesign.screenPadding)
        }
    }

    private var daySubtitle: String {
        if let nextSession {
            return "Próxima: \(nextSession.groupName) · \(nextSession.startTime ?? vm.timeLabel(for: Int(nextSession.period)))"
        }
        return "\(sessions.count) sesiones planificadas"
    }

    private var nextSession: PlanningSession? {
        sessions.first { session in
            session.status != .completed && vm.summary(for: session.id)?.status != .completed
        }
    }

    private func isCurrent(_ session: PlanningSession) -> Bool {
        guard let start = session.startTime, let end = session.endTime else { return false }
        let current = IsoWeekHelper.shared.current()
        let currentWeek = Int(truncating: current.first ?? KotlinInt(value: Int32(PlannerCalendar.currentIsoWeek)))
        let currentYear = Int(truncating: current.second ?? KotlinInt(value: Int32(PlannerCalendar.currentIsoYear)))
        guard Int(session.weekNumber) == currentWeek, Int(session.year) == currentYear else { return false }
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale.current
        let today = ((calendar.component(.weekday, from: Date()) + 5) % 7) + 1
        guard Int(session.dayOfWeek) == today else { return false }
        let now = calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
        guard let startMinutes = minutes(from: start), let endMinutes = minutes(from: end) else { return false }
        return now >= startMinutes && now <= endMinutes
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}

private struct PlannerDaySessionRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    let isCurrent: Bool
    let isNext: Bool
    let onOpen: () -> Void
    let onComplete: () -> Void

    private var tint: Color { Color(hex: vm.classColorHex(for: session.groupId)) }
    private var stateTint: Color { vm.sessionStateTint(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange)
                    .font(.headline.monospacedDigit())
                Text(isCurrent ? "Ahora" : (isNext ? "Próxima" : ""))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? EvaluationDesign.success : EvaluationDesign.accent)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.groupName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                    Spacer()
                    Label(vm.sessionStateLabel(for: session), systemImage: vm.sessionStateIcon(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stateTint)
                }

                Text(session.teachingUnitName.nilIfBlank ?? "Sesión sin título")
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)

                if let objective = session.objectives.nilIfBlank ?? session.activities.nilIfBlank {
                    Text(objective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button("Abrir ficha", action: onOpen)
                        .buttonStyle(.borderedProminent)
                    Button("Impartida", action: onComplete)
                        .buttonStyle(.bordered)
                        .disabled(session.status == .completed)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isCurrent ? EvaluationDesign.success.opacity(0.55) : EvaluationDesign.border, lineWidth: isCurrent ? 1.5 : 1)
        }
    }

    private var timeRange: String {
        if let start = session.startTime, let end = session.endTime {
            return "\(start)-\(end)"
        }
        return vm.timeLabel(for: Int(session.period))
    }
}

struct PlannerEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
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
