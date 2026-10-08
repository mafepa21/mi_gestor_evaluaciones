import SwiftUI
import MiGestorKit

/// Un evento de calendario que se crea o se edita. Sin `event`, es un evento nuevo.
struct PlannerCalendarEventDraft: Identifiable {
    let id = UUID()
    let event: CalendarEvent?
    let day: Date
}

/// Crear o editar un evento de calendario: un hito o un evento del curso.
/// Se guarda con el puente y, si la sincronización con «Colegio» está activa, también allí.
struct PlannerCalendarEventSheet: View {
    let bridge: KmpBridge
    let draft: PlannerCalendarEventDraft
    /// `true` si el evento se guardó o se borró. `false` si se canceló.
    let onFinish: (Bool) -> Void

    @AppStorage(AppleCalendarMirror.enabledKey) private var syncWithColegio = false
    @State private var title: String
    @State private var notes: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var confirmDelete = false

    init(bridge: KmpBridge, draft: PlannerCalendarEventDraft, onFinish: @escaping (Bool) -> Void) {
        self.bridge = bridge
        self.draft = draft
        self.onFinish = onFinish

        let calendar = Calendar.current
        if let event = draft.event {
            let start = Date(timeIntervalSince1970: Double(event.startAt.toEpochMilliseconds()) / 1000)
            let end = Date(timeIntervalSince1970: Double(event.endAt.toEpochMilliseconds()) / 1000)
            let allDay = calendar.startOfDay(for: start) == start && end.timeIntervalSince(start) >= 23 * 3600
            // Un día completo puede terminar a las 00:00 del día siguiente: se muestra como último día.
            let shownEnd = allDay && calendar.startOfDay(for: end) == end ? end.addingTimeInterval(-1) : end
            _title = State(initialValue: event.title)
            _notes = State(initialValue: event.description_ ?? "")
            _isAllDay = State(initialValue: allDay)
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: shownEnd)
        } else {
            let day = calendar.startOfDay(for: draft.day)
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _isAllDay = State(initialValue: true)
            _startDate = State(initialValue: day)
            _endDate = State(initialValue: day)
        }
    }

    private var isEditing: Bool { draft.event != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    private var pickerComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var syncFooter: String {
        syncWithColegio
            ? "Se guarda también en el calendario «Colegio» de tu cuenta."
            : "Solo se guarda en la app. Para copiarlo a «Colegio», activa Ajustes → Calendario de Apple."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $title)
                } footer: {
                    Text(syncFooter)
                }

                Section {
                    Toggle("Todo el día", isOn: $isAllDay)
                    DatePicker("Inicio", selection: $startDate, displayedComponents: pickerComponents)
                    DatePicker("Fin", selection: $endDate, displayedComponents: pickerComponents)
                }

                Section("Notas") {
                    TextField("Notas", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                if isEditing {
                    Section {
                        Button("Borrar evento", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Evento" : "Nuevo evento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onFinish(false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "¿Borrar este evento?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Borrar evento", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text("Si está copiado en «Colegio», también se borra allí.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }

    private func save() async {
        guard let range = eventRange() else {
            errorMessage = "La fecha de fin no puede ser anterior a la de inicio."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await bridge.plannerSaveCalendarEvent(
                id: draft.event?.id,
                classId: draft.event?.classId?.int64Value,
                title: trimmedTitle,
                description: trimmedNotes.isEmpty ? nil : trimmedNotes,
                startEpochMs: range.startMs,
                endEpochMs: range.endMs
            )
            onFinish(true)
        } catch {
            errorMessage = "No se pudo guardar el evento: \(error.localizedDescription)"
        }
    }

    private func delete() async {
        guard let event = draft.event else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await bridge.plannerDeleteCalendarEvent(id: event.id)
            onFinish(true)
        } catch {
            errorMessage = "No se pudo borrar el evento: \(error.localizedDescription)"
        }
    }

    /// Día completo: de las 00:00 del primer día a las 23:59:59 del último.
    /// Con hora: de la hora de inicio a la de fin.
    private func eventRange() -> (startMs: Int64, endMs: Int64)? {
        let calendar = Calendar.current
        if isAllDay {
            let firstDay = calendar.startOfDay(for: startDate)
            let lastDay = calendar.startOfDay(for: endDate)
            guard lastDay >= firstDay,
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
            return (Self.milliseconds(firstDay), Self.milliseconds(nextDay.addingTimeInterval(-1)))
        }
        guard endDate >= startDate else { return nil }
        return (Self.milliseconds(startDate), Self.milliseconds(endDate))
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
