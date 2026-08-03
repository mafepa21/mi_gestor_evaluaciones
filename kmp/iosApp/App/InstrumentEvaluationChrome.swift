import SwiftUI

/// Chrome compartido de las hojas de evaluación. El cristal orienta y contiene
/// acciones; las superficies donde se leen y puntúan datos siguen siendo sólidas.
enum InstrumentEvaluationChromeRole: Equatable {
    case header
    case context
    case action

    var cornerRadius: CGFloat {
        switch self {
        case .header: return 24
        case .context: return 16
        case .action: return 20
        }
    }

    var padding: CGFloat {
        switch self {
        case .header: return 16
        case .context: return 12
        case .action: return 12
        }
    }

    var tint: Color {
        switch self {
        case .header, .context: return .white
        case .action: return EvaluationDesign.accent
        }
    }
}

struct InstrumentEvaluationChromeSurface<Content: View>: View {
    let role: InstrumentEvaluationChromeRole
    let customPadding: CGFloat?
    @ViewBuilder let content: Content

    init(
        role: InstrumentEvaluationChromeRole,
        padding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.customPadding = padding
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: role.cornerRadius, style: .continuous)

        content
            .padding(customPadding ?? role.padding)
            .background {
                if #available(iOS 26.0, macOS 26.0, *) {
                    shape
                        .fill(Color.white.opacity(0.008))
                        .glassEffect(
                            .regular.tint(role.tint.opacity(role == .action ? 0.08 : 0.035)).interactive(),
                            in: shape
                        )
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                shape.stroke(
                    role == .action
                        ? EvaluationDesign.accent.opacity(0.18)
                        : EvaluationDesign.border.opacity(0.72),
                    lineWidth: 0.75
                )
            }
            .clipShape(shape)
            .shadow(
                color: role == .action ? EvaluationDesign.accent.opacity(0.12) : .black.opacity(0.04),
                radius: role == .action ? 12 : 8,
                y: role == .action ? 5 : 3
            )
    }
}

struct InstrumentEvaluationStatus: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InstrumentEvaluationMetadataItem: View {
    let label: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityElement(children: .combine)
    }
}

struct InstrumentEvaluationPrimaryButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .instrumentEvaluationGlassButton(isProminent: true)
    }
}

struct InstrumentEvaluationScaleControl: View {
    @Binding var selection: String
    let values: [String]
    let tint: Color

    init(
        selection: Binding<String>,
        values: [String] = ["", "1", "2", "3", "4"],
        tint: Color = NotebookStyle.primaryTint
    ) {
        self._selection = selection
        self.values = values
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let isSelected = selection == value
                Button {
                    selection = value
                } label: {
                    Text(value.isEmpty ? "—" : value)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? contrastingTextColor(for: value.isEmpty ? .secondary : tint) : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? (value.isEmpty ? Color.secondary.opacity(0.14) : tint) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.isEmpty ? "Sin respuesta" : "Nivel \(value)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(NotebookStyle.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.border, lineWidth: 0.75)
        }
    }
}

extension View {
    @ViewBuilder
    func instrumentEvaluationGlassButton(isProminent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isProminent {
                self
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .tint(EvaluationDesign.accent)
            } else {
                self
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
            }
        } else if isProminent {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
        }
    }
}
