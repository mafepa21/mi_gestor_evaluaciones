import SwiftUI
import MiGestorKit

/// Ajustes → Calendario de Apple: sincroniza la app con el calendario «Colegio» de la cuenta de Calendario.
struct AppleCalendarSettingsView: View {
    @EnvironmentObject var bridge: KmpBridge
    @AppStorage(AppleCalendarMirror.enabledKey) private var isEnabled = false
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Toggle("Sincronizar con Calendario de Apple", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in Task { await update(newValue) } }
                ))
                .disabled(isWorking)
            } footer: {
                Text("Los eventos del curso que están en «Colegio» aparecen en la app. Los eventos que creas o cambias en la app se guardan en «Colegio».")
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
            message = "Sincronización desactivada. Los eventos que ya están en Calendario de Apple no se borran."
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
            let created = try await bridge.backfillAppleCalendarLinks()
            bridge.reconcileAppleCalendarIfEnabled()
            message = created == 0
                ? "Calendario «Colegio» listo y sincronizado."
                : "Calendario «Colegio» listo. Se han copiado \(created) eventos que ya existían."
        } catch {
            message = "Calendario «Colegio» listo, pero no pude copiar los eventos que ya existían: \(error.localizedDescription)"
        }
    }
}
