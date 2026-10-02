import SwiftUI
import MiGestorKit

// MARK: - Presentation Helpers

enum TermBoardPresentationHelper {
    static func dayAbbreviation(_ day: Int) -> String {
        switch day {
        case 1: return "LUN"
        case 2: return "MAR"
        case 3: return "MIÉ"
        case 4: return "JUE"
        case 5: return "VIE"
        case 6: return "SÁB"
        default: return "DOM"
        }
    }

    static func dayOfMonth(_ date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        return "\(calendar.component(.day, from: date))"
    }

    static func monthAbbreviation(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.calendar = Calendar(identifier: .iso8601)
        return formatter.string(from: date).uppercased()
    }

    static func slotIsFree(_ slot: TermClassSlot) -> Bool {
        if case .free = slot.kind { return true }
        return false
    }

    static func slotIsPreview(_ slot: TermClassSlot) -> Bool {
        if case .preview = slot.kind { return true }
        return false
    }

    static func slotRowTint(_ slot: TermClassSlot) -> Color? {
        switch slot.kind {
        case .holiday: return Color.red.opacity(0.04)
        case .preview: return Color.purple.opacity(0.06)
        case .occupied: return nil
        case .free: return EvaluationDesign.success.opacity(0.03)
        case .schoolEvent: return Color.orange.opacity(0.04)
        }
    }
}

// MARK: - Week Slot Group

struct TermBoardWeekSlotGroup: Identifiable {
    var id: String { weekKey }
    let weekKey: String
    let weekTitle: String
    let dateRange: String
    let slots: [TermClassSlot]
}

// MARK: - Metrics Strip

struct TermBoardMetricsStrip: View {
    let metrics: TermCapacityMetrics
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                metricCard(
                    title: "Clases lectivas",
                    value: "\(metrics.totalLectivas)",
                    caption: "Reales en tu horario",
                    icon: "figure.run",
                    tint: EvaluationDesign.accent
                )

                metricCard(
                    title: "Festivos / Inhábiles",
                    value: "\(metrics.totalFestivos)",
                    caption: "Detectados y saltados",
                    icon: "calendar.badge.minus",
                    tint: metrics.totalFestivos > 0 ? Color.orange : Color.secondary
                )

                metricCard(
                    title: "Ocupadas por SAs",
                    value: "\(metrics.totalOcupadas)",
                    caption: "Programadas",
                    icon: "checkmark.circle.fill",
                    tint: EvaluationDesign.success
                )

                metricCard(
                    title: metrics.simulationActive ? "Huecos tras SA" : "Huecos libres",
                    value: "\(metrics.simulationActive ? metrics.simulationRemainingFreeCount : metrics.totalLibres)",
                    caption: metrics.simulationActive ? "Disponibles libres" : "Para planificar",
                    icon: "plus.circle.dashed",
                    tint: (metrics.simulationActive ? metrics.simulationRemainingFreeCount : metrics.totalLibres) > 0 ? Color.blue : Color.secondary
                )
            }

            if metrics.simulationActive {
                simulationFeedbackBanner(metrics)
            }
        }
    }

    private func metricCard(title: String, value: String, caption: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plannerGlassPanel(.content, cornerRadius: 14)
    }

    private func simulationFeedbackBanner(_ metrics: TermCapacityMetrics) -> some View {
        HStack(spacing: 10) {
            if metrics.simulationOverflowCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alerta de calendario: \(metrics.simulationOverflowCount) sesiones caen fuera de plazo")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("La SA tiene \(metrics.simulationSessionCount) sesiones y sobrepasa la fecha límite. Compacta sesiones o adelanta el inicio.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            } else if metrics.simulationRemainingFreeCount > 0 {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.yellow)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encaje holgado: te quedan \(metrics.simulationRemainingFreeCount) clases libres antes de la evaluación")
                        .font(.subheadline.weight(.semibold))
                    Text("Puedes crear sesiones extra de refuerzo, coevaluación o torneos comodín en los huecos libres.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(EvaluationDesign.success)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encaje óptimo: la SA ocupa exactamente los huecos disponibles")
                        .font(.subheadline.weight(.semibold))
                    Text("Las \(metrics.simulationSessionCount) sesiones finalizan dentro del periodo de evaluación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            metrics.simulationOverflowCount > 0
                ? Color.orange.opacity(0.9)
                : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

// MARK: - Slots Timeline View

struct TermBoardTimelineView: View {
    let slots: [TermClassSlot]
    var onOpenSession: ((PlanningSession) -> Void)? = nil
    var onAddExtraSession: ((TermClassSlot) -> Void)? = nil
    var bottomPadding: CGFloat = 80

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 16) {
                ForEach(groupedSlotsByWeek, id: \.weekKey) { weekGroup in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(weekGroup.weekTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(weekGroup.dateRange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(weekGroup.slots) { slot in
                                slotRow(slot)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, EvaluationDesign.screenPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    private var groupedSlotsByWeek: [TermBoardWeekSlotGroup] {
        let calendar = Calendar(identifier: .iso8601)
        let grouped = Dictionary(grouping: slots) { slot in
            let week = calendar.component(.weekOfYear, from: slot.date)
            let year = calendar.component(.yearForWeekOfYear, from: slot.date)
            return "\(year)-W\(week)"
        }

        let sortedKeys = grouped.keys.sorted()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        dateFormatter.calendar = calendar

        return sortedKeys.compactMap { key -> TermBoardWeekSlotGroup? in
            guard let weekSlots = grouped[key]?.sorted(by: { $0.date < $1.date }),
                  let first = weekSlots.first,
                  let last = weekSlots.last else { return nil }
            let weekNum = calendar.component(.weekOfYear, from: first.date)
            let weekTitle = "Semana \(weekNum)"
            let range = "\(dateFormatter.string(from: first.date)) – \(dateFormatter.string(from: last.date))"
            return TermBoardWeekSlotGroup(weekKey: key, weekTitle: weekTitle, dateRange: range, slots: weekSlots)
        }
    }

    private func slotRow(_ slot: TermClassSlot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Day and time badge
            VStack(alignment: .center, spacing: 2) {
                Text(TermBoardPresentationHelper.dayAbbreviation(slot.dayOfWeek))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(TermBoardPresentationHelper.dayOfMonth(slot.date))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(TermBoardPresentationHelper.monthAbbreviation(slot.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(slot.startTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 54)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Main Content by Kind
            switch slot.kind {
            case .holiday(let name):
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.title3)
                        .foregroundStyle(Color.red.opacity(0.8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(Color.red.opacity(0.9))
                        Text("Día no lectivo / Festivo · No gasta clase lectiva")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

            case .schoolEvent(let title):
                HStack(spacing: 12) {
                    Image(systemName: "flag.badge.ellipsis")
                        .font(.title3)
                        .foregroundStyle(Color.orange.opacity(0.8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Color.orange.opacity(0.9))
                        Text("Actividad complementaria / Centro · No lectivo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

            case .occupied(let session):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let index = slot.lessonIndex {
                            Text("Clase #\(index)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EvaluationDesign.accentSoft, in: Capsule())
                                .foregroundStyle(EvaluationDesign.accent)
                        }

                        Text(session.teachingUnitName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer()

                        if !session.linkedAssessmentIdsCsv.isEmpty {
                            Label("Hito de evaluación", systemImage: "medal.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.orange)
                        }
                    }

                    if !session.objectives.isEmpty {
                        Text(session.objectives)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenSession?(session)
                }

            case .preview(let sessionNumber, let title, let objective, let hasEval, _):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let index = slot.lessonIndex {
                            Text("Clase #\(index)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.purple)
                        }

                        Text("Previsión: Sesión \(sessionNumber) · \(title)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.purple)
                            .lineLimit(1)

                        Spacer()

                        if slot.isAfterEvaluationDeadline {
                            Text("Fuera de plazo")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.red)
                        } else if hasEval {
                            Label("Evaluación prevista", systemImage: "pencil.and.ruler.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.orange)
                        }
                    }

                    if !objective.isEmpty {
                        Text(objective)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

            case .free:
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let index = slot.lessonIndex {
                            Text("Clase #\(index) · Hueco disponible")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.success)
                        } else {
                            Text("Hueco disponible")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.success)
                        }
                        Text("Horario lectivo sin contenido asignado")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let onAddExtra = onAddExtraSession {
                        Button {
                            onAddExtra(slot)
                        } label: {
                            Label("Crear sesión extra", systemImage: "plus")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(EvaluationDesign.success)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plannerGlassPanel(
            .content,
            cornerRadius: 14,
            tint: TermBoardPresentationHelper.slotRowTint(slot),
            isInteractive: TermBoardPresentationHelper.slotIsPreview(slot)
        )
        .overlay {
            if TermBoardPresentationHelper.slotIsFree(slot) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(EvaluationDesign.success.opacity(0.4))
            } else if TermBoardPresentationHelper.slotIsPreview(slot) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}
