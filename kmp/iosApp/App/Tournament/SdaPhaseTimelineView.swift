import SwiftUI

/// Línea de fases del torneo (Liguilla → Cuadro → Podio). Cada fase es un botón: al tocarla cambia
/// el contenido que hay debajo. La fase actual lleva la etiqueta «AHORA». La lógica vive en
/// `TournamentPhaseTimeline`.
struct SdaPhaseTimelineView: View {
    let timeline: TournamentPhaseTimeline
    @Binding var selection: TournamentPhaseKind

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: 8, alignment: .top)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(timeline.phases) { phase in
                SdaPhaseChip(phase: phase, isSelected: phase.kind == selection) {
                    selection = phase.kind
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fases del torneo")
    }
}

private struct SdaPhaseChip: View {
    let phase: TournamentPhase
    let isSelected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 28

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    dot
                    Spacer(minLength: 4)
                    if phase.isCurrent {
                        Text("AHORA")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(EvaluationDesign.accent, in: Capsule())
                    }
                }
                Text(phase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(phase.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if phase.kind != .podium {
                    progressBar
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background(
                isSelected ? EvaluationDesign.accent.opacity(0.10) : IOSAppStyle.cardBackground,
                in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous)
                    .stroke(
                        isSelected || phase.isCurrent ? EvaluationDesign.accent : IOSAppStyle.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Muestra esta fase.")
    }

    private var dot: some View {
        ZStack {
            Circle().fill(dotColor)
            if phase.isDone {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            } else if phase.kind == .podium {
                Image(systemName: "star.fill").font(.caption.weight(.bold)).foregroundStyle(phase.isCurrent ? .white : .secondary)
            } else {
                Text("\(phase.number)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(phase.isCurrent ? .white : .secondary)
            }
        }
        .frame(width: dotSize, height: dotSize)
        .accessibilityHidden(true)
    }

    private var dotColor: Color {
        if phase.isDone { return IOSAppStyle.success }
        if phase.isCurrent { return EvaluationDesign.accent }
        return IOSAppStyle.subtleFill
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IOSAppStyle.subtleFill)
                Capsule()
                    .fill(phase.isDone ? IOSAppStyle.success : EvaluationDesign.accent)
                    .frame(width: proxy.size.width * phase.progress)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var text = "Fase \(phase.number), \(phase.title). \(phase.detail)."
        if phase.isCurrent { text += " Es la fase actual." }
        if phase.isDone { text += " Terminada." }
        return text
    }
}
