import SwiftUI
import MiGestorKit

struct PendingEvaluationPickerSheet: View {
    @ObservedObject var bridge: KmpBridge
    let item: AgendaItem
    @Environment(\.dismiss) private var dismiss
    @State private var navPath = NavigationPath()
    @State private var selectedTarget: AgendaNavigationTarget? = nil

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section {
                    ForEach(item.navigationTargets, id: \.id) { target in
                        Button {
                            selectedTarget = target
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(target.label)
                                            .font(.body.weight(.semibold))
                                        Text(item.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evaluaciones pendientes")
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Selecciona una rúbrica")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .sheet(item: $selectedTarget) { target in
            AgendaRubricEvaluationSheet(bridge: bridge, target: target)
                .onDisappear {
                    dismiss()
                }
        }
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
            .frame(minWidth: 980, minHeight: 700)
            .task(id: target.id) {
                guard !hasOpenedTarget else { return }
                hasOpenedTarget = true
                bridge.openAgendaNavigationTarget(target)
            }
            .onChange(of: bridge.rubricEvaluationState.rubricDetail != nil) { isVisible in
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
