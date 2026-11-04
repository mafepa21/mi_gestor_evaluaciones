import SwiftUI
import MiGestorKit

/// Criterio de rúbrica con dibujos por nivel (`visual_key`) y/o cronómetro
/// (`timing_config`). Los criterios sin nada de eso siguen en `RubricCriterionRow`.
///
/// El número de nivel y sus puntos ●●● se ven siempre, también con los textos
/// ocultos, para que el nivel no dependa solo del dibujo ni del color.
struct RubricVisualCriterionRow: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: RubricCriterionWithLevels
    var totalWeight: Double = 0
    let selectedLevelId: Int64?
    let measuredSeconds: Double?
    var hidesDescriptions: Bool = false
    var isActive: Bool = false
    var onActivate: () -> Void = {}
    let onSelectLevel: (Int64) -> Void
    /// Tiempo del cronómetro: el ViewModel pone el nivel según los cortes.
    var onMeasure: (Double) -> Void = { _ in }
    var onClearMeasure: () -> Void = {}

    @State private var selectionTick = 0

    /// Niveles de menos a más puntos: el puesto elige el dibujo.
    private var rankedLevels: [RubricLevel] {
        item.levels.sorted { ($0.points, $0.order) < ($1.points, $1.order) }
    }

    private var timing: RubricTiming? {
        RubricTiming.companion.parse(raw: item.criterion.timingConfig)
    }

    private var weightPercent: Int? {
        guard item.criterion.weight > 0, totalWeight > 0 else { return nil }
        let value = Int((item.criterion.weight / totalWeight * 100).rounded())
        return value > 0 ? value : nil
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let timing {
                RubricStopwatchPanel(
                    timing: timing,
                    levels: rankedLevels,
                    selectedLevelId: selectedLevelId,
                    measuredSeconds: measuredSeconds,
                    onMeasure: onMeasure,
                    onClear: onClearMeasure
                )
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(rankedLevels.enumerated()), id: \.element.id) { rank, level in
                        levelCard(level, rank: rank).frame(minWidth: 150)
                    }
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(rankedLevels.enumerated()), id: \.element.id) { rank, level in
                        levelCard(level, rank: rank)
                    }
                }
            }
        }
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: RubricsStyle.cardRadius, style: .continuous)
                .stroke(isActive ? EvaluationDesign.accent : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: RubricsStyle.cardRadius, style: .continuous))
        .onTapGesture(perform: onActivate)
        .accessibilityElement(children: .contain)
        .animation(uiFeatureFlags.interactionAnimation, value: selectedLevelId)
        .animation(uiFeatureFlags.interactionAnimation, value: isActive)
        .sensoryFeedback(.selection, trigger: selectionTick)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if timing != nil {
                Image(systemName: "stopwatch")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(item.criterion.description_)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let weightPercent {
                Text("\(weightPercent)%")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            Spacer(minLength: 0)
        }
    }

    private func levelCard(_ level: RubricLevel, rank: Int) -> some View {
        let isSelected = selectedLevelId == level.id
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Button {
            selectionTick += 1
            onSelectLevel(level.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let scene = RubricVisuals.scene(key: item.criterion.visualKey, rank: rank) {
                    RubricVisualSceneView(scene: scene)
                }
                HStack(spacing: 6) {
                    Text(RubricsStyle.cleanLevelTitle(level.name))
                        .font(.subheadline.weight(.bold))
                    Text(String(repeating: "●", count: rank + 1))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(EvaluationDesign.success)
                    }
                }
                if !hidesDescriptions, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                    .fill(isSelected ? EvaluationDesign.success.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                    .stroke(isSelected ? EvaluationDesign.success : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(description.isEmpty ? level.name : "\(level.name): \(description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Cronómetro de un criterio con cortes: al parar pone el nivel. Si ya había
/// un tiempo, pregunta antes de cambiarlo.
private struct RubricStopwatchPanel: View {
    let timing: RubricTiming
    let levels: [RubricLevel]
    let selectedLevelId: Int64?
    let measuredSeconds: Double?
    let onMeasure: (Double) -> Void
    let onClear: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 40
    @State private var startedAt: Date?
    @State private var pendingSeconds: Double?
    @State private var confirmingClear = false

    private var isRunning: Bool { startedAt != nil }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) { clock; scale }
            VStack(alignment: .leading, spacing: 12) { clock; scale }
        }
        .confirmationDialog(
            "¿Cambiar el tiempo?",
            isPresented: Binding(get: { pendingSeconds != nil }, set: { if !$0 { pendingSeconds = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingSeconds {
                Button("Usar \(Self.format(pendingSeconds))") { record(pendingSeconds) }
            }
            if let measuredSeconds {
                Button("Mantener \(Self.format(measuredSeconds))", role: .cancel) { pendingSeconds = nil }
            }
        } message: {
            if let measuredSeconds {
                Text("Ya había \(Self.format(measuredSeconds)).")
            }
        }
        .confirmationDialog("¿Borrar el tiempo?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Borrar tiempo", role: .destructive, action: onClear)
        } message: {
            Text("El nivel elegido se queda; puedes cambiarlo a mano.")
        }
    }

    private var clock: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(Self.format(displayedSeconds(at: context.date), compact: false))
                    .font(.system(size: clockSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cronómetro")
            .accessibilityValue(measuredSeconds.map { Self.format($0) } ?? "sin tiempo")

            HStack(spacing: 12) {
                Button(isRunning ? "Parar" : (measuredSeconds == nil ? "Empezar" : "Repetir"),
                       systemImage: isRunning ? "stop.fill" : "play.fill") {
                    isRunning ? stop() : start()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])

                if measuredSeconds != nil, !isRunning {
                    Button("Borrar", systemImage: "trash") { confirmingClear = true }
                        .buttonStyle(.bordered)
                        .padding(.leading, 8)
                }
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    /// Los cortes en lenguaje llano, de más a menos nivel; el que toca va marcado.
    private var scale: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(levels.enumerated().reversed()), id: \.element.id) { rank, level in
                HStack(spacing: 8) {
                    Text(RubricsStyle.cleanLevelTitle(level.name))
                        .font(.footnote.weight(.semibold))
                    Text(rangeText(rank: rank))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if level.id == selectedLevelId, measuredSeconds != nil {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(EvaluationDesign.success)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if measuredSeconds == nil, !isRunning {
                Text("Pulsa Empezar cuando salga el alumno.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rangeText(rank: Int) -> String {
        let cuts = timing.cuts.map { $0.doubleValue }
        // Puesto 0 = nivel más bajo. Con «menos es mejor», el más bajo es el más lento.
        let index = timing.lowerIsBetter ? cuts.count - rank : rank
        let low = index > 0 ? cuts[index - 1] : nil
        let high = index < cuts.count ? cuts[index] : nil
        switch (low, high) {
        case let (nil, high?): return "menos de \(Self.number(high)) s"
        case let (low?, nil): return "\(Self.number(low)) s o más"
        case let (low?, high?): return "de \(Self.number(low)) a \(Self.number(high)) s"
        default: return ""
        }
    }

    private func displayedSeconds(at date: Date) -> Double {
        if let startedAt { return date.timeIntervalSince(startedAt) }
        return measuredSeconds ?? 0
    }

    private func start() {
        startedAt = Date()
    }

    private func stop() {
        guard let startedAt else { return }
        let seconds = (Date().timeIntervalSince(startedAt) * 10).rounded() / 10
        self.startedAt = nil
        if let measuredSeconds, measuredSeconds != seconds {
            pendingSeconds = seconds
        } else {
            record(seconds)
        }
    }

    private func record(_ seconds: Double) {
        pendingSeconds = nil
        onMeasure(seconds)
        AccessibilityNotification.Announcement("\(Self.format(seconds))").post()
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "es_ES")))
    }

    static func format(_ seconds: Double, compact: Bool = true) -> String {
        if compact { return "\(number(seconds)) s" }
        let tenths = Int((seconds * 10).rounded(.down))
        return String(format: "%02d:%02d,%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}
