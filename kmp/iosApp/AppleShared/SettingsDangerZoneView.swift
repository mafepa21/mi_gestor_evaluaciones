import SwiftUI

struct SettingsDangerZoneView: View {
    @ObservedObject var settings: AppSettingsStore
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
            Text("Esta acción eliminará de forma irreversible toda tu información, incluyendo clases, estudiantes, rúbricas y copias de seguridad locales. Escribe 'BORRAR' en mayúsculas para continuar.")
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
        let fileManager = FileManager.default
        let dbPath = AppleBridgeBootstrap.current().databasePath
        let dbURL = URL(fileURLWithPath: dbPath)
        let appDataURL = dbURL.deletingLastPathComponent()

        // Delete database sidecars
        for suffix in ["", "-wal", "-shm"] {
            let path = dbPath + suffix
            if fileManager.fileExists(atPath: path) {
                try? fileManager.removeItem(atPath: path)
            }
        }

        // Delete backups
        let backupsDir = appDataURL.appendingPathComponent("backups", isDirectory: true)
        if fileManager.fileExists(atPath: backupsDir.path) {
            try? fileManager.removeItem(at: backupsDir)
        }

        // Delete attachments
        let attachmentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("NotebookEvidence", isDirectory: true) ?? appDataURL.appendingPathComponent("NotebookEvidence")
        if fileManager.fileExists(atPath: attachmentsDir.path) {
            try? fileManager.removeItem(at: attachmentsDir)
        }

        // needsRestart es observado en la raíz de la app (iOS: AppleAppRootView, macOS: MacRootView)
        // para bloquear la UI con un aviso de reinicio en lugar de dejar datos en memoria obsoletos.
        AppleBackupService.shared.needsRestart = true
    }
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
