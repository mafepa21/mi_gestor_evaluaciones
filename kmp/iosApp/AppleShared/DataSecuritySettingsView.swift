import SwiftUI

struct DataSecuritySettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject private var bridge: KmpBridge
    
    var body: some View {
        Form {
            Section("Copias de Seguridad") {
                Picker("Frecuencia de backups", selection: $settings.backupFrequency) {
                    ForEach(BackupFrequency.allCases) { freq in
                        Text(freq.title).tag(freq)
                    }
                }
                
                Toggle("Backup de emergencia antes de restaurar", isOn: $settings.createEmergencyBackupBeforeRestore)
            }
            
            Section("Historial y Restauración") {
                NavigationLink {
                    BackupCenterView()
                } label: {
                    Label("Ver y gestionar backups", systemImage: "externaldrive.badge.checkmark")
                }
            }
            
            Section("Zona de riesgo") {
                NavigationLink {
                    SettingsDangerZoneView(settings: settings)
                        .environmentObject(bridge)
                } label: {
                    Label("Acciones destructivas", systemImage: "exclamationmark.shield")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Datos y Seguridad")
    }
}
