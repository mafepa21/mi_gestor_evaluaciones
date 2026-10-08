import SwiftUI
import MiGestorKit

/// Ajustes → Calendario de Apple: activa la copia de los eventos de la app a un calendario «Colegio».
struct AppleCalendarSettingsView: View {
    @EnvironmentObject var bridge: KmpBridge
    @AppStorage(AppleCalendarMirror.enabledKey) private var isEnabled = false
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Toggle("Copiar eventos a Calendario de Apple", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in Task { await update(newValue) } }
                ))
                .disabled(isWorking)
            } footer: {
                Text("Los eventos que creas, cambias o borras en la app se copian a un calendario «Colegio» de tu cuenta de Calendario.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Calendario de Apple")
    }

    private func update(_ enable: Bool) async {
        guard enable else {
            isEnabled = false
            message = "Copia desactivada. Los eventos que ya están en Calendario de Apple no se borran."
            return
        }

        isWorking = true
        defer { isWorking = false }

        let mirror = AppleCalendarMirror.shared
        guard await mirror.requestAccess() else {
            isEnabled = false
            message = "Falta el permiso de Calendario. Puedes darlo en Ajustes del sistema, en Privacidad y seguridad, Calendarios."
            return
        }

        do {
            try mirror.prepareCalendar()
        } catch {
            isEnabled = false
            message = error.localizedDescription
            return
        }

        isEnabled = true
        do {
            let events = try await bridge.plannerAllCalendarEvents()
            let copied = mirror.mirrorMissing(events.map(AppleCalendarMirror.Item.init(event:)))
            message = copied == 0
                ? "Calendario «Colegio» listo."
                : "Calendario «Colegio» listo. Se han copiado \(copied) eventos que ya existían."
        } catch {
            message = "Calendario «Colegio» listo, pero no pude copiar los eventos que ya existían: \(error.localizedDescription)"
        }
    }
}

extension AppleCalendarMirror.Item {
    init(event: CalendarEvent) {
        self.init(
            localId: event.id,
            title: event.title,
            notes: event.description_,
            startMs: event.startAt.toEpochMilliseconds(),
            endMs: event.endAt.toEpochMilliseconds()
        )
    }
}
