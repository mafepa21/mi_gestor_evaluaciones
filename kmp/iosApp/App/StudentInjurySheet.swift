import SwiftUI

/// Hoja «Lesión»: crear o editar una lesión con fechas (maqueta
/// `docs/maquetas/lesiones-con-fecha/mockup/index.html`, estados 1-4, 10 y 12).
/// Una sola tarea: hasta cuándo y qué hace en clase. Sin datos médicos.
struct StudentInjurySheet: View {
    let bridge: KmpBridge
    let studentId: Int64
    let studentName: String
    /// Lesión a editar; `nil` crea una nueva desde hoy.
    let existing: StudentInjurySnapshot?
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var startsOn: Date
    @State private var endsOn: Date
    @State private var hasNoEnd: Bool
    @State private var role: InjuryRoleUI
    @State private var proofDelivered: Bool
    @State private var note: String
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var confirmDelete = false

    init(
        bridge: KmpBridge,
        studentId: Int64,
        studentName: String,
        existing: StudentInjurySnapshot?,
        onFinished: @escaping () -> Void = {}
    ) {
        self.bridge = bridge
        self.studentId = studentId
        self.studentName = studentName
        self.existing = existing
        self.onFinished = onFinished
        let today = Calendar.current.startOfDay(for: Date())
        let start = existing?.startsOn ?? today
        _startsOn = State(initialValue: start)
        _endsOn = State(initialValue: existing?.endsOn
            ?? Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start)
        _hasNoEnd = State(initialValue: existing != nil && existing?.endsOn == nil)
        _role = State(initialValue: existing?.role ?? .none)
        _proofDelivered = State(initialValue: existing?.proofDelivered ?? false)
        _note = State(initialValue: existing?.note ?? "")
    }

    private static let noteLimit = 140

    private var endsBeforeStart: Bool {
        !hasNoEnd && Calendar.current.startOfDay(for: endsOn) < Calendar.current.startOfDay(for: startsOn)
    }

    private var canSave: Bool { !endsBeforeStart && !isSaving }

    private var datesFooter: String {
        if endsBeforeStart { return "«Hasta» no puede ser antes de «Desde»." }
        if hasNoEnd { return "Seguirá lesionado hasta que marques «Ha vuelto» en su ficha." }
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: endsOn) ?? endsOn
        return "El \(StudentInjuryText.shortDate(nextDay)) deja de estar lesionado solo y «Hoy» te avisa."
    }

    var body: some View {
        NavigationStack {
            Form {
                if saveFailed {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No se pudo guardar la lesión")
                                        .font(.headline)
                                    Text("Nada ha cambiado. Lo que has escrito sigue aquí.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                            Spacer(minLength: 8)
                            Button("Reintentar") { save() }
                                .buttonStyle(.bordered)
                                .disabled(!canSave)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    DatePicker("Desde", selection: $startsOn, displayedComponents: .date)
                    if !hasNoEnd {
                        DatePicker("Hasta", selection: $endsOn, displayedComponents: .date)
                            .foregroundStyle(endsBeforeStart ? Color.red : Color.primary)
                            .accessibilityHint(endsBeforeStart ? "«Hasta» no puede ser antes de «Desde»." : "")
                    }
                    Toggle("Sin fecha de fin", isOn: $hasNoEnd)
                } header: {
                    Text(studentName)
                } footer: {
                    Text(datesFooter)
                        .foregroundStyle(endsBeforeStart ? Color.red : Color.secondary)
                }

                Section {
                    Picker("Papel en clase", selection: $role) {
                        ForEach(InjuryRoleUI.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Justificante entregado", isOn: $proofDelivered)
                }

                Section {
                    TextField("Ej.: puede caminar, no correr", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Nota")
                } footer: {
                    Text("Sin diagnósticos ni datos médicos. \(note.count)/\(Self.noteLimit)")
                }

                if existing != nil {
                    Section {
                        Button("Eliminar lesión…", role: .destructive) { confirmDelete = true }
                            .confirmationDialog(
                                "¿Eliminar esta lesión?",
                                isPresented: $confirmDelete,
                                titleVisibility: .visible
                            ) {
                                Button("Eliminar", role: .destructive) { deleteExisting() }
                                Button("Cancelar", role: .cancel) {}
                            } message: {
                                Text("Úsalo solo si la pusiste por error. También desaparece de su historial.")
                            }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Lesión" : "Editar lesión")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
            .disabled(isSaving)
            .appOnChange(of: note) { newValue in
                if newValue.count > Self.noteLimit {
                    note = String(newValue.prefix(Self.noteLimit))
                }
            }
            .appOnChange(of: startsOn) { newValue in
                // «Hasta» acompaña a «Desde» si se queda atrás: no hay que corregirlo a mano.
                if endsOn < newValue { endsOn = newValue }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 440, idealHeight: 520)
        #endif
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await bridge.saveInjury(
                    id: existing?.id,
                    studentId: studentId,
                    startsOn: startsOn,
                    endsOn: hasNoEnd ? nil : endsOn,
                    role: role,
                    note: note,
                    proofDelivered: proofDelivered
                )
                AppleInteractionFeedback.play(.success)
                onFinished()
                dismiss()
            } catch {
                saveFailed = true
                AppleInteractionFeedback.play(.error)
                announce("No se pudo guardar la lesión. Nada ha cambiado.")
            }
            isSaving = false
        }
    }

    private func deleteExisting() {
        guard let id = existing?.id else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await bridge.deleteInjury(id: id)
                onFinished()
                dismiss()
            } catch {
                saveFailed = true
                announce("No se pudo eliminar la lesión.")
            }
            isSaving = false
        }
    }

    private func announce(_ message: String) {
        if #available(iOS 17.0, macOS 14.0, *) {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
