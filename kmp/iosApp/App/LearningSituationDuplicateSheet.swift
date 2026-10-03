import SwiftUI
import MiGestorKit

/// Duplicar una situación con los grupos ya elegidos (los de la original o el del módulo).
/// Se puede duplicar sin grupos y vincularlos después.
struct LearningSituationDuplicateSheet: View {
    let situation: LearningSituation
    let classes: [SchoolClass]
    let onConfirm: ([Int64]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassIds: Set<Int64>

    init(
        situation: LearningSituation,
        classes: [SchoolClass],
        initialClassIds: Set<Int64> = [],
        onConfirm: @escaping ([Int64]) -> Void
    ) {
        self.situation = situation
        self.classes = classes
        self.onConfirm = onConfirm
        _selectedClassIds = State(initialValue: initialClassIds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva situación") {
                    Text("\(situation.title) (copia)")
                        .font(.body.weight(.semibold))
                    Text("Se conserva el documento de origen. Podrás editar la copia después.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Grupos") {
                    if selectedClassIds.isEmpty {
                        LearningSituationInlineNotice(
                            kind: .info,
                            message: "Sin grupos. Podrás vincularlos después."
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                    ForEach(classes, id: \.id) { schoolClass in
                        Toggle(schoolClass.name, isOn: Binding(
                            get: { selectedClassIds.contains(schoolClass.id) },
                            set: { selected in
                                if selected { selectedClassIds.insert(schoolClass.id) }
                                else { selectedClassIds.remove(schoolClass.id) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Duplicar situación")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicar") { onConfirm(Array(selectedClassIds).sorted()) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
