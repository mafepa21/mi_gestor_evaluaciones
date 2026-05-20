import SwiftUI

struct SettingsDangerZoneView: View {
    @ObservedObject var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingWipeConfirmation = false
    @State private var confirmationText = ""
    @State private var errorText: String? = nil
    
    var body: some View {
        Form {
            Section("Acciones de Preferencias") {
                Button("Restablecer ajustes visuales") {
                    settings.resetVisualSettings()
                }
                
                Button("Limpiar caché de la app") {
                    clearAppCache()
                }
            }
            
            Section("Datos de Prueba") {
                Button("Eliminar datos de prueba") {
                    deleteTestData()
                }
            }
            
            Section("Zona de peligro crítico") {
                Button(role: .destructive) {
                    showingWipeConfirmation = true
                } label: {
                    Label("Borrar todos los datos", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Zona de Riesgo")
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
                    errorText = "El texto introducido no es correcto."
                }
            }
            Button("Cancelar", role: .cancel) {
                confirmationText = ""
            }
        } message: {
            Text("Esta acción eliminará de forma irreversible toda tu información, incluyendo clases, estudiantes, rúbricas y copias de seguridad locales. Escribe 'BORRAR' en mayúsculas para continuar.")
        }
        .alert(item: Binding(
            get: { errorText.map { IdentifiableString(value: $0) } },
            set: { errorText = $0?.value }
        )) { err in
            Alert(title: Text("Error"), message: Text(err.value), dismissButton: .default(Text("OK")))
        }
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
    
    private func deleteTestData() {
        // Safe removal of test entries or visual caches if any test database setup exists.
        // We will do a generic cache cleanup.
        clearAppCache()
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
        
        // Set needsRestart to force re-initialization or show restart screen
        AppleBackupService.shared.needsRestart = true
    }
}

struct IdentifiableString: Identifiable {
    var id: String { value }
    let value: String
}
