import SwiftUI

// MARK: - Grabaciones guardadas de Voz de Pista

/// Lista de dictados guardados de una clase: elegir varios y analizarlos juntos, o borrarlos.
struct CourtVoiceRecordingsSheet: View {
    let className: String
    let recordings: [CourtVoiceRecording]
    let onAnalyze: ([CourtVoiceRecording]) -> Void
    let onDelete: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var isConfirmingDelete = false

    private var selected: [CourtVoiceRecording] {
        recordings.filter { selection.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView {
                        Label("Aún no hay grabaciones de esta clase", systemImage: "mic")
                    } description: {
                        Text("Pulsa el micrófono y elige «Solo guardar» para dictar en pista sin parar a revisar.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(recordings) { recording in
                                row(recording)
                                    #if os(iOS)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            onDelete([recording.id])
                                            selection.remove(recording.id)
                                        } label: {
                                            Label("Borrar", systemImage: "trash")
                                        }
                                    }
                                    #endif
                            }
                        } header: {
                            Text(className)
                        } footer: {
                            Text("Las grabaciones nunca salen de este dispositivo, no van a la copia de iCloud y se borran solas al aplicar sus acciones.")
                        }
                    }
                }
            }
            .navigationTitle("Grabaciones")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if !recordings.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(selection.count == recordings.count ? "Ninguna" : "Seleccionar todo") {
                            selection = selection.count == recordings.count ? [] : Set(recordings.map(\.id))
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.count == 1 ? "Analizar 1 grabación" : "Analizar \(selection.count) grabaciones") {
                        onAnalyze(selected)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
                if !selection.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Borrar", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .confirmationDialog(
                selection.count == 1 ? "¿Borrar 1 grabación?" : "¿Borrar \(selection.count) grabaciones?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Borrar", role: .destructive) {
                    onDelete(selection)
                    selection = []
                }
            } message: {
                Text("No se puede deshacer.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func row(_ recording: CourtVoiceRecording) -> some View {
        let isSelected = selection.contains(recording.id)
        return Button {
            if isSelected { selection.remove(recording.id) } else { selection.insert(recording.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? EvaluationDesign.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title).font(.body.weight(.semibold))
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened)
                         + (recording.transcript != nil ? " · ya transcrita" : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Self.durationText(recording.duration))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Toca para incluirla al analizar")
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
