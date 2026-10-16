import SwiftUI

struct DataSecuritySettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @EnvironmentObject private var bridge: KmpBridge
    @StateObject private var backupService = AppleBackupService.shared

    @State private var showingCreateSheet = false
    @State private var backupNote = ""

    var body: some View {
        Form {
            Section {
                BackupStatusSummary(service: backupService) {
                    Button("Crear copia ahora") {
                        backupNote = ""
                        showingCreateSheet = true
                    }
                    .disabled(backupService.operationState == .creating)
                }
            }

            Section {
                Picker("Frecuencia", selection: $settings.backupFrequency) {
                    ForEach(BackupFrequency.allCases) { freq in
                        Text(freq.title).tag(freq)
                    }
                }

                Toggle(isOn: $settings.createEmergencyBackupBeforeRestore) {
                    Text("Copia previa al restaurar")
                    Text("Guarda tu estado actual antes de sustituirlo.")
                }
            } header: {
                Text("Copias automáticas")
            } footer: {
                Text("Las copias se guardan en este dispositivo. Para llevarlas a otro sitio, usa Exportar.")
            }

            Section {
                NavigationLink {
                    BackupCenterView()
                } label: {
                    LabeledContent {
                        Text(backupCountText)
                    } label: {
                        Label("Copias guardadas", systemImage: "externaldrive.badge.checkmark")
                    }
                }
            } header: {
                Text("Historial")
            } footer: {
                Text("Consulta, valida, exporta o restaura una copia anterior.")
            }

            Section {
                NavigationLink {
                    SettingsDangerZoneView(settings: settings)
                        .environmentObject(bridge)
                } label: {
                    Text("Zona de riesgo")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Restablece ajustes o borra datos. Siempre pide confirmación.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Datos y seguridad")
        .task {
            await backupService.scanBackups()
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateBackupSheet(isPresented: $showingCreateSheet, note: $backupNote) {
                let finalNote = backupNote.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await backupService.createBackup(note: finalNote.isEmpty ? nil : finalNote)
            }
        }
    }

    private var backupCountText: String {
        switch backupService.backups.count {
        case 0: return "Ninguna"
        default: return "\(backupService.backups.count)"
        }
    }
}
