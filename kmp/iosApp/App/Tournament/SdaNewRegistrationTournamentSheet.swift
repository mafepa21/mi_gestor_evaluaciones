import SwiftUI
import MiGestorKit

/// Torneo desde cero, sin situación ni grupos: los equipos salen después de la inscripción
/// por formulario (`SdaTournamentRegistrationSheet`). Se guarda sin equipos ni calendario.
struct SdaNewRegistrationTournamentSheet: View {
    let classId: Int64
    let className: String
    let onCreated: (TournamentRecord) -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Torneo de futbolín"
    @State private var format: TournamentFormat = .roundRobin
    @State private var venueCount = 2
    @State private var matchMinutes = 8
    @State private var transitionMinutes = 2
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre del torneo", text: $name)
                        .frame(minHeight: 44)
                }
                Section {
                    Picker("Formato", selection: $format) {
                        ForEach(TournamentFormat.allCases) { option in
                            Text(option.shortTitle).tag(option)
                        }
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Formato")
                } footer: {
                    Text(format.shortSubtitle)
                }
                Section("Partidos") {
                    SdaStepperRow(title: "Pistas", value: $venueCount, range: 1...12, unit: "pistas")
                    SdaStepperRow(title: "Minutos por partido", value: $matchMinutes, range: 1...90, unit: "minutos")
                    SdaStepperRow(title: "Cambio entre partidos", value: $transitionMinutes, range: 0...15, unit: "minutos")
                }
                Section {
                    Label("Después envías el formulario a \(className) y los equipos salen de las parejas inscritas.", systemImage: "envelope")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section {
                        LearningSituationInlineNotice(kind: .error, message: errorMessage)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Torneo con inscripción")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { Task { await create() } }
                        .disabled(trimmedName.isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func create() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let plan = TournamentPlan(
                name: trimmedName,
                format: format,
                teams: [],
                venueCount: venueCount,
                matchDurationMinutes: matchMinutes,
                transitionMinutes: transitionMinutes
            )
            let record = try TournamentRecord(plan: plan, learningSituationId: nil, classId: classId, tabId: nil)
            let saved = try await bridge.saveTournament(record)
            onCreated(saved)
            dismiss()
        } catch {
            errorMessage = "No se pudo crear el torneo. Inténtalo de nuevo."
        }
    }
}
