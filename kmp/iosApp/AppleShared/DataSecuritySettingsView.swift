import SwiftUI

struct DataSecuritySettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    /// Referencia sin suscripción: esta vista solo llama acciones del bridge.
    @Environment(\.kmpBridgeReference) private var bridgeReference
    private var bridge: KmpBridge { bridgeReference! }
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
            } header: {
                Text("Copias automáticas")
            } footer: {
                Text(automaticFooterText)
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
                        .kmpBridgeEnvironment(bridge)
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

    private var automaticFooterText: String {
        let schedule: String
        switch settings.backupFrequency {
        case .daily: schedule = "La app hace una copia al día, al abrirla o al salir de ella."
        case .weekly: schedule = "La app hace una copia cada semana, al abrirla o al salir de ella."
        case .manual: schedule = "La app no hará copias por su cuenta."
        }
        return "\(schedule) Antes de restaurar, siempre guarda una copia de lo que tienes. Las copias se quedan en este dispositivo: para llevarlas a otro sitio, usa Exportar."
    }

    private var backupCountText: String {
        switch backupService.backups.count {
        case 0: return "Ninguna"
        default: return "\(backupService.backups.count)"
        }
    }
}
