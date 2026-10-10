import SwiftUI

// MARK: - Repaso rápido del visor de sesión
//
// Vistas del guion de repaso: objetivo, montaje, atención, bloques y pasos. Solo estilos de
// texto del sistema (escalan con Dynamic Type) y objetivos táctiles de al menos 44 pt.

/// Tarjetas de cabecera: objetivo de la sesión, montaje y atención.
struct PlannerReviewBrief: View {
    let objective: String
    let setup: [String]
    let attention: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !objective.isEmpty {
                objectiveCard
            }
            if !setup.isEmpty || !attention.isEmpty {
                // Dos columnas si caben (≥ 560 pt); si no, una debajo de otra.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        if !setup.isEmpty { setupCard }
                        if !attention.isEmpty { attentionCard }
                    }
                    .frame(minWidth: 560, idealWidth: 560, maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
                        if !setup.isEmpty { setupCard }
                        if !attention.isEmpty { attentionCard }
                    }
                }
            }
        }
    }

    private var objectiveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Objetivo")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            Text(objective)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Montaje")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(setup.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .accessibilityHidden(true)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Atención", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.orange)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(attention.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Cabecera de un bloque del guion (`U01 · Título · 40 min`).
struct PlannerReviewBlockHeader: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Descanso legal entre los dos bloques de una sesión LONG.
struct PlannerReviewBreakRow: View {
    var body: some View {
        Label("Descanso legal · 15 min", systemImage: "cup.and.saucer.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// Un paso del guion: minutos, hora acumulada, tipo, título, descripción y consigna CLIL pegada.
struct PlannerReviewStepRow: View {
    let step: PlannerSessionReviewStep
    let tint: Color
    /// HTML del diagrama de la actividad (solo se pasa al paso principal).
    let visualHTML: String?
    /// Repaso ancho: texto completo sin «Ver más» y diagrama en miniatura.
    var isWide: Bool = false
    let onEnlargeVisual: (String) -> Void

    @State private var isExpanded = false
    @State private var isTruncated = false
    @ScaledMetric(relativeTo: .body) private var minutesColumnWidth: CGFloat = 72
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stacksVertically: Bool { dynamicTypeSize.isAccessibilitySize }
    private var canExpand: Bool { isExpanded || isTruncated || !step.extras.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            controls
        }
        .padding(.vertical, step.isMain ? 16 : 0)
        .padding(.horizontal, step.isMain ? 16 : 0)
        .background {
            if step.isMain {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.10))
            }
        }
        // El fondo del paso principal sobresale un poco para que el texto siga alineado.
        .padding(.horizontal, step.isMain ? -16 : 0)
    }

    // MARK: Resumen (un solo elemento de accesibilidad)

    private var summary: some View {
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            timeColumn
            textColumn
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let minutes = step.minutes {
                Text("\(minutes)'")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(step.isMain ? tint : Color.primary)
            }
            if !step.phase.isEmpty {
                Text(step.phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let offset = step.startOffsetMinutes {
                Text(PlannerSessionReviewStep.offsetLabel(offset))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: stacksVertically ? nil : minutesColumnWidth, alignment: .leading)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if !step.detail.isEmpty {
                PlannerReviewExpandableText(text: step.detail, isExpanded: isExpanded || isWide, isTruncated: $isTruncated)
            }
            if let clil = step.clil, !clil.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(clil)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
            }
            if isExpanded {
                ForEach(step.extras, id: \.label) { extra in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(extra.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(extra.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let visualHTML {
                if isWide {
                    visualThumbnail(visualHTML)
                } else {
                    PlannerDocxWebView(html: visualHTML, minHeight: 160, idealHeight: 200, maxHeight: 240)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Diagrama reducido (zoom 0,45) que se amplía al pulsarlo.
    private func visualThumbnail(_ html: String) -> some View {
        PlannerDocxWebView(html: html, minHeight: 170, idealHeight: 170, maxHeight: 170, pageZoom: 0.45)
            .frame(maxWidth: 320, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onEnlargeVisual(html) }
            }
            .help("Ampliar diagrama")
            .accessibilityHidden(true)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let minutes = step.minutes {
            parts.append(minutes == 1 ? "1 minuto" : "\(minutes) minutos")
        }
        if !step.phase.isEmpty { parts.append(step.phase) }
        if let offset = step.startOffsetMinutes {
            parts.append("desde \(PlannerSessionReviewStep.offsetLabel(offset))")
        }
        parts.append(step.title)
        if !step.detail.isEmpty { parts.append(step.detail) }
        if let clil = step.clil, !clil.isEmpty { parts.append("Consigna en inglés: \(clil)") }
        if isExpanded {
            parts.append(contentsOf: step.extras.map { "\($0.label): \($0.text)" })
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Controles

    @ViewBuilder
    private var controls: some View {
        if canExpand || visualHTML != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { controlButtons }
                VStack(alignment: .leading, spacing: 0) { controlButtons }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, stacksVertically ? 0 : minutesColumnWidth + 16)
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        Group {
            if canExpand {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Ver menos" : "Ver más")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .accessibilityLabel(isExpanded ? "Ver menos de \(step.title)" : "Ver más de \(step.title)")
            }
            if let visualHTML {
                Button {
                    onEnlargeVisual(visualHTML)
                } label: {
                    Label("Ampliar diagrama", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .accessibilityLabel("Ampliar el diagrama de \(step.title) a pantalla completa")
            }
        }
    }
}

/// Texto limitado a 4 líneas que detecta si se recorta, para no cortar nunca sin avisar («Ver más»).
private struct PlannerReviewExpandableText: View {
    let text: String
    let isExpanded: Bool
    @Binding var isTruncated: Bool

    private struct Heights: Equatable {
        var visible: CGFloat = 0
        var full: CGFloat = 0
    }

    private struct HeightsKey: PreferenceKey {
        static var defaultValue = Heights()
        static func reduce(value: inout Heights, nextValue: () -> Heights) {
            let next = nextValue()
            value.visible = max(value.visible, next.visible)
            value.full = max(value.full, next.full)
        }
    }

    var body: some View {
        Text(text)
            .font(.body)
            .lineLimit(isExpanded ? nil : 4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: HeightsKey.self, value: Heights(visible: proxy.size.height, full: 0))
            })
            .background(alignment: .topLeading) {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: HeightsKey.self, value: Heights(visible: 0, full: proxy.size.height))
                    })
            }
            .onPreferenceChange(HeightsKey.self) { heights in
                let truncated = heights.full > heights.visible + 1
                if truncated != isTruncated { isTruncated = truncated }
            }
    }
}

// MARK: - Estados

/// Marcador de carga que respeta «Reducir movimiento».
struct PlannerReviewSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            bar(fraction: 0.6, height: 24)
            bar(fraction: 1, height: 96)
            VStack(alignment: .leading, spacing: 16) {
                bar(fraction: 0.4, height: 16)
                bar(fraction: 1, height: 16)
                bar(fraction: 0.8, height: 16)
                bar(fraction: 1, height: 16)
                bar(fraction: 0.7, height: 16)
            }
        }
        .opacity(isDimmed ? 0.4 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { isDimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando la sesión")
    }

    private func bar(fraction: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(EvaluationDesign.surfaceSoft)
                        .frame(width: proxy.size.width * fraction)
                }
            }
    }
}

/// La sesión existe pero aún no tiene guion.
struct PlannerReviewEmptyState: View {
    let tint: Color
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Esta sesión aún no tiene guion")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(action: onEdit) {
                Text("Importar o crear desarrollo")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

/// No se pudo cargar la sesión (red o almacenamiento).
struct PlannerReviewErrorState: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text("No se pudo cargar la sesión. Revisa la conexión.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text("Reintentar")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
