import SwiftUI
import MiGestorKit

struct PendingEvaluationPickerSheet: View {
    @ObservedObject var bridge: KmpBridge
    let item: AgendaItem
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTarget: AgendaNavigationTarget? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(item.navigationTargets, id: \.id) { target in
                        targetRow(target)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .background(appSecondarySystemBackgroundColor().opacity(0.55))
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .appFullScreenCover(item: $selectedTarget) { target in
            AgendaRubricEvaluationSheet(bridge: bridge, target: target)
                .onDisappear {
                    dismiss()
                }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Selecciona una rúbrica")
                    .font(.title2.weight(.bold))
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func targetRow(_ target: AgendaNavigationTarget) -> some View {
        Button {
            selectedTarget = target
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appSecondarySystemBackgroundColor(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.secondary.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text("\(item.navigationTargets.count) destino(s) disponibles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cerrar") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}

extension AgendaNavigationTarget: @retroactive Identifiable {}

struct AgendaRubricEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    let target: AgendaNavigationTarget
    @Environment(\.dismiss) private var dismiss
    @State private var hasOpenedTarget = false
    @State private var hasRenderedDetail = false

    var body: some View {
        RubricEvaluationView()
            .environmentObject(bridge)
            #if os(macOS)
            .frame(minWidth: 980, minHeight: 700)
            #endif
            .task(id: target.id) {
                guard !hasOpenedTarget else { return }
                hasOpenedTarget = true
                bridge.openAgendaNavigationTarget(target)
            }
            .appOnChange(of: bridge.rubricEvaluationState.rubricDetail != nil) { isVisible in
                if isVisible {
                    hasRenderedDetail = true
                } else if hasRenderedDetail {
                    dismiss()
                }
            }
            .onDisappear {
                if bridge.rubricEvaluationState.rubricDetail != nil {
                    bridge.closeRubricEvaluation()
                }
            }
    }
}
