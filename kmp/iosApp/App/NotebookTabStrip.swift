import SwiftUI
import MiGestorKit

struct NotebookTabStrip: View {
    let tabs: [NotebookTab]
    let activeTabId: String?
    let onSelect: (String) -> Void
    let onCreateTab: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if tabs.isEmpty {
                Label("Organiza el cuaderno por temas", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button {
                    onCreateTab()
                } label: {
                    Label("Crear primera pestaña", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.id) { tab in
                            tabButton(tab: tab, isSelected: tab.id == activeTabId)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    onCreateTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.08), in: Circle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(NotebookScaleButtonStyle())
                .help("Nueva pestaña")
                .accessibilityLabel("Nueva pestaña")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func tabButton(tab: NotebookTab, isSelected: Bool) -> some View {
        Button {
            onSelect(tab.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.secondary.opacity(0.04))
                    .shadow(color: isSelected ? Color.accentColor.opacity(0.10) : Color.clear, radius: 4, x: 0, y: 2)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.28) : NotebookStyle.softBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .help("Abrir \(tab.title)")
    }
}

// MARK: - NotebookScaleButtonStyle
private struct NotebookScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
