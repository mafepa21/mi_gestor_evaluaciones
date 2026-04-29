import SwiftUI
import AppKit

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    let onOpenSync: () -> Void

    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @AppStorage("mac_reduce_motion") private var reduceMotion = false
    @AppStorage("mac_compact_density") private var compactDensity = false
    @AppStorage("mac_confirm_destructive_actions") private var confirmDestructiveActions = true
    @AppStorage("mac_ai_reports_enabled") private var aiReportsEnabled = true
    @AppStorage("mac_ai_notebook_summary_enabled") private var aiNotebookSummaryEnabled = true
    @AppStorage("mac_privacy_anonymize_diagnostics") private var anonymizeDiagnostics = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                pageHeader

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacAppStyle.cardSpacing) {
                    generalSection
                    appearanceSection
                    localDataSection
                    syncSection
                    localAISection
                    backupsSection
                    privacySection
                    diagnosticSection
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ajustes")
                .font(MacAppStyle.pageTitle)
            Text("Configura apariencia, datos locales, IA, seguridad y diagnóstico de la app.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        settingsCard(title: "General", systemImage: "slider.horizontal.3") {
            settingsRow("App", value: "MiGestor")
            settingsRow("Curso actual", value: "Último usado")
            settingsRow("Clase inicial", value: "Última clase abierta")
            Toggle("Mostrar inspector por defecto", isOn: $session.inspectorVisible)
            Toggle("Confirmar antes de borrar", isOn: $confirmDestructiveActions)
        }
    }

    private var appearanceSection: some View {
        settingsCard(title: "Apariencia", systemImage: "paintpalette") {
            Picker("Tema", selection: $themeModeRawValue) {
                ForEach(AppThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Densidad compacta", isOn: $compactDensity)
            Toggle("Reducir animaciones", isOn: $reduceMotion)
            settingsRow("Tablas", value: compactDensity ? "Compactas" : "Cómodas")
        }
    }

    private var localDataSection: some View {
        settingsCard(title: "Datos locales", systemImage: "externaldrive") {
            settingsRow("Estado", value: session.bridge.status)
            settingsRow("Base de datos", value: databaseFileName)
            settingsRow("Modo", value: "Local")

            HStack(spacing: 8) {
                Button {
                    revealDatabaseFolder()
                } label: {
                    Label("Ver ubicación", systemImage: "folder")
                }

                Button {
                    copyDatabasePath()
                } label: {
                    Label("Copiar ruta", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var syncSection: some View {
        settingsCard(title: "Sincronización", systemImage: "arrow.triangle.2.circlepath.circle") {
            settingsRow("Estado", value: syncStatusTitle)
            settingsRow("Última sync", value: session.bridge.syncLastRunAt.map(relativeTime) ?? "Sin registro")
            settingsRow("Cambios pendientes", value: "\(session.bridge.syncPendingChanges)")

            HStack(spacing: 8) {
                Button {
                    onOpenSync()
                } label: {
                    Label("Abrir Sync LAN", systemImage: "arrow.forward.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    commandCenter.reconnect()
                } label: {
                    Label("Reparar conexión", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
                .disabled(commandCenter.serviceState == .starting)
            }
        }
    }

    private var localAISection: some View {
        settingsCard(title: "IA local", systemImage: "sparkles") {
            settingsRow("Apple Foundation Models", value: "Modo local")
            Toggle("Usar IA para informes", isOn: $aiReportsEnabled)
            Toggle("Síntesis del cuaderno", isOn: $aiNotebookSummaryEnabled)
            settingsRow("Nivel de detalle", value: "Normal")
            settingsRow("Última ejecución", value: "Sin incidencias registradas")
        }
    }

    private var backupsSection: some View {
        settingsCard(title: "Copias de seguridad", systemImage: "externaldrive.badge.timemachine") {
            settingsRow("Última copia", value: "Pendiente de configurar")
            settingsRow("Copia automática", value: "Local")
            settingsRow("Ubicación", value: "Carpeta de la app")

            Button {
                session.selectedFeature = .backups
            } label: {
                Label("Abrir Backups", systemImage: "arrow.forward.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var privacySection: some View {
        settingsCard(title: "Privacidad", systemImage: "lock.shield") {
            settingsRow("Datos del alumnado", value: "Guardado local")
            settingsRow("Servicios externos", value: "No usados por defecto")
            Toggle("Anonimizar diagnósticos", isOn: $anonymizeDiagnostics)
            settingsRow("Informes IA", value: aiReportsEnabled ? "Permitidos localmente" : "Desactivados")
        }
    }

    private var diagnosticSection: some View {
        settingsCard(title: "Diagnóstico", systemImage: "stethoscope") {
            settingsRow("KMP", value: session.bridge.status)
            settingsRow("SQLDelight", value: databaseFileName)
            settingsRow("Helper Sync", value: syncStatusTitle)
            settingsRow("Plataforma", value: session.bootstrap.platformName)
            settingsRow("Cobertura v1", value: "\(MacFeatureRegistry.all.filter(\.enabledInV1).count)/\(MacFeatureRegistry.all.count) módulos")

            Button {
                copyDiagnostic()
            } label: {
                Label("Copiar diagnóstico", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
                .font(.callout)
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var databaseFileName: String {
        URL(fileURLWithPath: session.bootstrap.databasePath).lastPathComponent
    }

    private var syncStatusTitle: String {
        switch commandCenter.serviceState {
        case .stopped:
            return "Servicio detenido"
        case .starting:
            return "Iniciando"
        case .running:
            return "Preparado para enlazar"
        case let .connected(_, _, _, _, _, deviceName):
            return "Conectado a \(deviceName?.isEmpty == false ? deviceName! : "iPad")"
        case .networkError:
            return "Error de red"
        case .failed:
            return "Error del helper"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyDatabasePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.bootstrap.databasePath, forType: .string)
    }

    private func revealDatabaseFolder() {
        let url = URL(fileURLWithPath: session.bootstrap.databasePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyDiagnostic() {
        let lines = [
            "MiGestor macOS",
            "Plataforma: \(session.bootstrap.platformName)",
            "KMP: \(session.bridge.status)",
            "Base de datos: \(databaseFileName)",
            "Sync helper: \(syncStatusTitle)",
            "Pendientes sync: \(session.bridge.syncPendingChanges)",
            "Última sync: \(session.bridge.syncLastRunAt.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")",
            "Módulos v1: \(MacFeatureRegistry.all.filter(\.enabledInV1).count)/\(MacFeatureRegistry.all.count)"
        ]

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
