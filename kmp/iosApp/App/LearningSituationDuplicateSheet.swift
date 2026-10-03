import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

struct LearningSituationDuplicateSheet: View {
    let situation: LearningSituation
    let classes: [SchoolClass]
    let onConfirm: ([Int64]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassIds: Set<Int64> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva situación") {
                    Text(situation.title)
                    Text("Se conservará el documento de origen y podrás editar la copia después.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Asignar a grupos") {
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
            .navigationTitle("Duplicar y reasignar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicar") { onConfirm(Array(selectedClassIds).sorted()) }
                        .disabled(selectedClassIds.isEmpty)
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
