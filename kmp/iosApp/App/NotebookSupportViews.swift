import SwiftUI
import MiGestorKit

struct FlexibleTagRow: View {
    let items: [String]
    let selected: String
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item.isEmpty ? "Sin icono" : item)
                        .font(.system(size: item.isEmpty ? 11 : 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected == item ? NotebookStyle.primaryTint.opacity(0.16) : NotebookStyle.surface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NotebookContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    init(_ title: String, systemImage: String, description: String) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}

struct NotebookStateCard<Accessory: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = NotebookStyle.primaryTint
    @ViewBuilder var accessory: Accessory

    init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = NotebookStyle.primaryTint,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 28) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    accessory
                }
                .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct NotebookAverageExplanationView: View {
    let studentName: String
    let explanation: NotebookAverageExplanation?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let explanation = explanation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !explanation.included.isEmpty {
                            sectionHeader(title: "Contribuyen a la media", icon: "plus.circle.fill", color: .green)
                            ForEach(explanation.included, id: \.columnId) { contribution in
                                contributionRow(contribution)
                            }
                        }

                        if !explanation.excluded.isEmpty {
                            sectionHeader(title: "Excluidos del cálculo", icon: "minus.circle.fill", color: .gray)
                            ForEach(explanation.excluded, id: \.columnId) { exclusion in
                                exclusionRow(exclusion)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                Text("No hay datos de cálculo disponibles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding(.vertical, 16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Media de \(studentName)")
                .font(.headline)
            if let average = explanation?.average {
                Text(String(format: "Resultado: %.2f", average.doubleValue))
                    .font(.title2.bold())
                    .foregroundStyle(NotebookStyle.primaryTint)
            } else {
                Text("Resultado: --")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func contributionRow(_ c: NotebookAverageContribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 13, weight: .medium))
                Text(String(format: "Peso: %.0f%%", c.weight * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f", c.value))
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(10)
        .background(NotebookStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func exclusionRow(_ e: NotebookAverageExclusion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(exclusionReasonText(e.reason))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer()
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(10)
        .background(NotebookStyle.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func exclusionReasonText(_ reason: NotebookAverageExclusionReason) -> String {
        switch reason {
        case .empty: return "Sin calificar"
        case .columnDoesNotCount: return "No cuenta para media"
        case .rawValueOnly: return "Dato informativo"
        case .lockedOrArchived: return "Bloqueado / Archivado"
        case .nonNumeric: return "Dato no numérico"
        default: return "Excluido"
        }
    }
}
