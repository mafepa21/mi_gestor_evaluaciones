import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsDangerZoneView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var showingWipeConfirmation = false
    @State private var confirmationText = ""
    @State private var pendingAction: DangerZoneAction? = nil
    @State private var feedbackMessage: String? = nil

    var body: some View {
        Form {
            Section("Acciones de Preferencias") {
                Button("Restablecer ajustes visuales") {
                    pendingAction = .resetVisualSettings
                }

                Button("Limpiar caché de la app") {
                    pendingAction = .clearCache
                }
            }

            Section("Zona de peligro crítico") {
                Button(role: .destructive) {
                    confirmationText = ""
                    showingWipeConfirmation = true
                } label: {
                    Label("Borrar todos los datos", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Zona de Riesgo")
        .confirmationDialog(
            pendingAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirmar", role: .destructive) {
                performPendingAction()
            }
            Button("Cancelar", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingAction?.confirmationMessage ?? "")
        }
        .alert("¿Borrar definitivamente todo?", isPresented: $showingWipeConfirmation) {
            TextField("Escribe BORRAR", text: $confirmationText)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled(true)

            Button("Borrar Todo", role: .destructive) {
                if confirmationText == "BORRAR" {
                    wipeAllData()
                } else {
                    feedbackMessage = "El texto introducido no es correcto."
                }
                confirmationText = ""
            }
            Button("Cancelar", role: .cancel) {
                confirmationText = ""
            }
        } message: {
            Text("Esta acción eliminará de forma irreversible toda tu información, incluyendo clases, estudiantes, rúbricas y copias de seguridad locales. También se desvinculará la sincronización con otros dispositivos. Escribe 'BORRAR' en mayúsculas para continuar.")
        }
        .alert(item: Binding(
            get: { feedbackMessage.map { IdentifiableString(value: $0) } },
            set: { feedbackMessage = $0?.value }
        )) { message in
            Alert(title: Text("Aviso"), message: Text(message.value), dismissButton: .default(Text("OK")))
        }
    }

    private func performPendingAction() {
        guard let action = pendingAction else { return }
        switch action {
        case .resetVisualSettings:
            settings.resetVisualSettings()
        case .clearCache:
            clearAppCache()
        }
        pendingAction = nil
        feedbackMessage = action.successMessage
    }

    private func clearAppCache() {
        let fileManager = FileManager.default
        let cacheDirs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        for dir in cacheDirs {
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) {
                for file in contents {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }

    private func wipeAllData() {
        Task { @MainActor in
            await performWipe()
        }
    }

    /// Borrado total.
    ///
    /// Hasta 2026-07 esto borraba `desktop_mi_gestor_kmp.db`, `-wal` y `-shm` del disco
    /// mientras el driver de SQLDelight los tenía abiertos. macOS invalidaba entonces
    /// todos los descriptores del pool (`vnode unlinked while in use`), la siguiente
    /// consulta fallaba con `SQLITE_IOERR` y el proceso abortaba — crash real reportado
    /// por el usuario, parcheado dos veces por síntomas (cancelar tareas de fondo,
    /// guards de `needsRestart`) antes de atacar la causa.
    ///
    /// Ahora la base se **vacía por SQL** con la conexión que ya está abierta
    /// (`KmpContainer.wipeAllData()`): no se invalida ningún descriptor y no puede
    /// fallar por E/S. Solo se borran como ficheros las cosas que nadie tiene abiertas.
    @MainActor
    private func performWipe() async {
        let backupService = AppleBackupService.shared

        // 1. Parar el trabajo en segundo plano de este proceso (bucle de auto-sync,
        //    debounces de guardado, listener SSE).
        bridge.stopBackgroundSyncWork()

        // 2. Desemparejar antes de borrar. Sin esto el borrado no sobrevivía al
        //    reinicio: el dispositivo seguía emparejado y el primer pull volvía a
        //    traerse todos los datos desde el iPad, deshaciendo el borrado. Se hace
        //    antes de parar el helper porque avisa al servidor por red.
        await bridge.unpairLanSync()

        // 3. macOS: parar el helper de Sync LAN, que corre en un proceso aparte con su
        //    propia conexión SQLite al mismo fichero y sigue sirviendo /sync/pull.
        #if os(macOS)
        NotificationCenter.default.post(name: .appleCommandCenterStopRequested, object: nil)
        #endif

        // 4. Vaciar la base por SQL. Si falla, se avisa y no se borra nada más: es
        //    preferible dejarlo todo como estaba a borrar los adjuntos de unos datos
        //    que siguen ahí.
        do {
            try bridge.wipeAllDatabaseData()
        } catch {
            feedbackMessage = "No se pudieron borrar los datos: \(error.localizedDescription)"
            return
        }

        // 5. Ficheros que nadie tiene abiertos.
        let fileManager = FileManager.default
        var fileErrors: [String] = []

        func remove(_ url: URL, _ label: String) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                fileErrors.append(label)
            }
        }

        remove(backupService.backupsDirectoryURL, "copias de seguridad")
        remove(backupService.attachmentsURL, "adjuntos del cuaderno")
        // Los documentos de situaciones de aprendizaje se quedaban sin borrar pese a que
        // el diálogo promete eliminar "toda tu información".
        remove(backupService.learningSituationsURL, "documentos de situaciones de aprendizaje")

        // Bases apartadas por un arranque fallido (`<db>.backup_<epoch>`): son copias
        // completas de los datos de la docente y sobrevivían enteras al borrado total.
        backupService.scanQuarantinedDatabases()
        for quarantined in backupService.quarantinedDatabases {
            remove(quarantined.url, "bases apartadas")
            for suffix in ["-wal", "-shm"] {
                remove(URL(fileURLWithPath: quarantined.url.path + suffix), "bases apartadas")
            }
        }
        // Y el marcador que, si sobrevive, hace saltar la alerta de rescate en el
        // siguiente arranque ofreciendo restaurar una base que ya no existe.
        remove(URL(fileURLWithPath: backupService.databaseURL.path + ".rescue_marker"), "marcador de rescate")

        await backupService.scanBackups()

        if !fileErrors.isEmpty {
            let detail = Set(fileErrors).sorted().joined(separator: ", ")
            feedbackMessage = "Los datos se han borrado, pero no se pudieron eliminar algunos archivos: \(detail)."
        }

        // needsRestart es observado en la raíz de la app (iOS: AppleAppRootView, macOS: MacRootView)
        // para bloquear la UI con un aviso de reinicio. Sigue siendo necesario aunque la base
        // ya no se rompa: los cachés en memoria y los Flow ya suscritos conservan los datos
        // viejos (el vaciado por SQL no pasa por las queries generadas, así que no notifica
        // a sus listeners).
        backupService.needsRestart = true
        #if os(macOS)
        scheduleAutomaticRelaunch()
        #endif
    }

    #if os(macOS)
    /// En macOS sí se puede relanzar la app: `wipeAllData()` borra los ficheros
    /// en disco pero la conexión SQLite y el estado en memoria del proceso
    /// actual siguen siendo los antiguos, así que un reinicio manual era el
    /// único modo de ver los cambios reflejados. El retardo deja ver el aviso
    /// de `RestartRequiredOverlay` antes de que el proceso termine.
    ///
    /// iOS/iPadOS no tiene equivalente: Apple no permite que una app se
    /// autorelance (rechazado en App Review), así que ahí se mantiene el
    /// aviso de reinicio manual sin cambios.
    private func scheduleAutomaticRelaunch() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }
    #endif
}

private enum DangerZoneAction: String, Identifiable {
    case resetVisualSettings
    case clearCache

    var id: String { rawValue }

    var confirmationTitle: String {
        switch self {
        case .resetVisualSettings: return "¿Restablecer los ajustes visuales?"
        case .clearCache: return "¿Limpiar la caché de la app?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .resetVisualSettings: return "Se restaurará el aspecto por defecto de la app."
        case .clearCache: return "Se eliminarán los archivos temporales de la app. No afecta a tus datos."
        }
    }

    var successMessage: String {
        switch self {
        case .resetVisualSettings: return "Ajustes visuales restablecidos."
        case .clearCache: return "Caché eliminada."
        }
    }
}

struct IdentifiableString: Identifiable {
    var id: String { value }
    let value: String
}
