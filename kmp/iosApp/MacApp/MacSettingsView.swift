import SwiftUI
import AppKit
import MiGestorKit

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    @ObservedObject var backupStore: MacBackupStore
    let onOpenSync: () -> Void

    @State private var selectedSection: SettingsSection = .general
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @AppStorage("mac_reduce_motion") private var reduceMotion = false
    @AppStorage("mac_compact_density") private var compactDensity = false
    @AppStorage("mac_confirm_destructive_actions") private var confirmDestructiveActions = true
    @AppStorage("apple.foundation.models.localInference.enabled") private var appleFoundationModelsEnabled = AppleFoundationModelSupport.isLocalInferenceEnabled
    @AppStorage("reports.ai.enabled") private var aiReportsEnabled = true
    @AppStorage("contextual.ai.enabled") private var aiContextualEnabled = true
    @AppStorage("analytics.ai.enabled") private var aiAnalyticsEnabled = true
    @AppStorage("mac_privacy_anonymize_diagnostics") private var anonymizeDiagnostics = true
    @State private var aiDiagnosticSummary = "Pendiente de comprobar"
    @State private var aiLastFailure = "Sin fallos registrados"

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader
                    selectedSectionView
                }
                .padding(32)
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .task {
            refreshAIDiagnostics()
            await backupStore.loadBackups()
        }
        .appOnChange(of: appleFoundationModelsEnabled) { enabled in
            AppleFoundationModelSupport.setLocalInferenceEnabled(enabled)
            refreshAIDiagnostics()
        }
        .appOnChange(of: aiReportsEnabled) { _ in refreshAIDiagnostics() }
        .appOnChange(of: aiContextualEnabled) { _ in refreshAIDiagnostics() }
        .appOnChange(of: aiAnalyticsEnabled) { _ in refreshAIDiagnostics() }
    }

    private var settingsSidebar: some View {
        List(selection: $selectedSection) {
            ForEach(SettingsSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 188)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedSection.title)
                .font(MacAppStyle.pageTitle)
            Text(selectedSection.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selectedSection {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .localData:
            localDataSection
        case .sync:
            syncSection
        case .localAI:
            localAISection
            aiHistorySection
        case .privacy:
            privacySection
        case .diagnostic:
            diagnosticSection
        case .backups:
            backupsSection
        }
    }

    private var generalSection: some View {
        settingsCard(title: "General", systemImage: "slider.horizontal.3") {
            settingsRow("App", value: "MiGestor")
            settingsRow("Curso actual", value: currentSchoolYearText)
            configurableRow("Clase inicial", value: initialClassText) {
                session.selectedFeature = .students
            }
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
            settingsRow("Nombre", value: databaseFileName)
            settingsRow("Ruta", value: databasePathText)
            settingsRow("Tamaño", value: databaseSizeText)
            settingsRow("Última modificación", value: databaseLastModifiedText)
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
            HStack(spacing: 12) {
                Image(systemName: syncStatusImage)
                    .font(.title2)
                    .foregroundStyle(syncPendingChanges == 0 ? MacAppStyle.successTint : MacAppStyle.warningTint)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync LAN")
                        .font(.headline)
                    Text(syncSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            settingsRow("Estado", value: syncStatusTitle)
            settingsRow("Pendientes", value: "\(syncPendingChanges)")
            settingsRow("Última sync", value: session.bridge.syncLastRunAt.map(relativeTime) ?? "Sin registro")

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
            Toggle("Apple Foundation Models", isOn: $appleFoundationModelsEnabled)
            Toggle("Informes y comentarios LOMLOE", isOn: $aiReportsEnabled)
            Toggle("Cuaderno, síntesis y ayuda contextual", isOn: $aiContextualEnabled)
            Toggle("Analítica e insights", isOn: $aiAnalyticsEnabled)
            settingsRow("Estado real", value: aiDiagnosticSummary)
            settingsRow("Último fallo runtime", value: aiLastFailure)

            Button {
                AppleFoundationModelSupport.clearCachedAvailability()
                refreshAIDiagnostics()
            } label: {
                Label("Recomprobar IA local", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var aiHistorySection: some View {
        settingsCard(title: "Historial IA", systemImage: "clock.arrow.circlepath") {
            AppleAIHistoryPanel(bridge: session.bridge)
        }
    }

    private var backupsSection: some View {
        settingsCard(title: "Copias de seguridad", systemImage: "externaldrive.badge.timemachine") {
            if backupStore.operationState != .idle && backupStore.backups.isEmpty {
                ProgressView("Leyendo historial de backups")
                    .controlSize(.small)
            }

            settingsRow("Última copia", value: latestBackupDateText)
            settingsRow("Estado", value: latestBackupStatusText)
            settingsRow("Copias guardadas", value: "\(backupStore.backups.count)")
            settingsRow("Ubicación", value: backupStore.backupDirectoryURL.path)

            HStack(spacing: 8) {
                Button {
                    session.selectedFeature = .backups
                } label: {
                    Label("Abrir Backups", systemImage: "arrow.forward.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await backupStore.createBackup(note: "Creada desde Ajustes") }
                } label: {
                    Label("Crear ahora", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(backupStore.isCreatingBackup)
            }
        }
    }

    private var privacySection: some View {
        settingsCard(title: "Privacidad", systemImage: "lock.shield") {
            settingsRow("Datos del alumnado", value: "Guardados localmente en este Mac")
            settingsRow("IA local", value: appleFoundationModelsEnabled ? "Activada" : "Desactivada")
            settingsRow("Diagnósticos", value: "Anonimizados antes de copiar")
            settingsRow("Servicios externos", value: "No usados por defecto")
            Toggle("Anonimizar diagnósticos", isOn: $anonymizeDiagnostics)
        }
    }

    private var diagnosticSection: some View {
        settingsCard(title: "Diagnóstico técnico", systemImage: "stethoscope") {
            settingsRow("KMP", value: session.bridge.status)
            settingsRow("SQLDelight", value: databaseFileName)
            settingsRow("Helper Sync", value: syncStatusTitle)
            settingsRow("Plataforma", value: session.bootstrap.platformName)
            settingsRow("Módulos activos", value: "\(MacFeatureRegistry.all.filter(\.enabledInV1).count)/\(MacFeatureRegistry.all.count)")
            settingsRow("IA local", value: aiDiagnosticSummary)

            HStack(spacing: 8) {
                Button {
                    copyDiagnostic(anonymized: false)
                } label: {
                    Label("Copiar diagnóstico", systemImage: "doc.on.doc")
                }

                Button {
                    copyDiagnostic(anonymized: true)
                } label: {
                    Label("Copiar anonimizado", systemImage: "lock.doc")
                }

                Button {
                    openLogsFolder()
                } label: {
                    Label("Abrir logs", systemImage: "folder")
                }
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
        .frame(maxWidth: 760, alignment: .topLeading)
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

    private func configurableRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
            if value == "No configurado" {
                Button("Configurar", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var databaseFileName: String {
        URL(fileURLWithPath: session.bootstrap.databasePath).lastPathComponent
    }

    private var databaseURL: URL {
        URL(fileURLWithPath: session.bootstrap.databasePath)
    }

    private var databasePathText: String {
        session.bootstrap.databasePath.isEmpty ? "No configurado" : session.bootstrap.databasePath
    }

    private var databaseSizeText: String {
        guard let size = databaseAttributes[.size] as? NSNumber else { return "No disponible" }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private var databaseLastModifiedText: String {
        guard let date = databaseAttributes[.modificationDate] as? Date else { return "No disponible" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var databaseAttributes: [FileAttributeKey: Any] {
        (try? FileManager.default.attributesOfItem(atPath: session.bootstrap.databasePath)) ?? [:]
    }

    private var currentSchoolYearText: String {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let startYear = month >= 9 ? year : year - 1
        return "\(startYear)/\(startYear + 1)"
    }

    private var initialClassText: String {
        guard let schoolClass = selectedSchoolClass ?? session.bridge.classes.first else { return "No configurado" }
        return schoolClass.name
    }

    private var selectedSchoolClass: SchoolClass? {
        guard let selectedID = session.bridge.selectedStudentsClassId else { return nil }
        return session.bridge.classes.first { $0.id == selectedID }
    }

    private var syncPendingChanges: Int {
        session.bridge.syncPendingChanges
    }

    private var syncSummary: String {
        if syncPendingChanges == 0 {
            return "Sincronizado"
        }
        return "\(syncPendingChanges) cambio(s) pendientes"
    }

    private var syncStatusImage: String {
        syncPendingChanges == 0 ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
    }

    private var latestBackupDateText: String {
        backupStore.latestBackup?.createdAt.macBackupDateText ?? "No configurado"
    }

    private var latestBackupStatusText: String {
        backupStore.latestBackup?.verificationState.rawValue ?? "No configurado"
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
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    private func copyDiagnostic(anonymized: Bool) {
        let lines = [
            "MiGestor macOS",
            "Plataforma: \(session.bootstrap.platformName)",
            "KMP: \(session.bridge.status)",
            "SQLDelight: \(anonymized ? databaseFileName : session.bootstrap.databasePath)",
            "Sync helper: \(syncStatusTitle)",
            "IA local: \(aiDiagnosticSummary)",
            "IA último fallo: \(aiLastFailure)",
            "Pendientes sync: \(session.bridge.syncPendingChanges)",
            "Última sync: \(session.bridge.syncLastRunAt.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")",
            "Backups: \(backupStore.backups.count)",
            "Módulos activos: \(MacFeatureRegistry.all.filter(\.enabledInV1).count)/\(MacFeatureRegistry.all.count)"
        ]

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func openLogsFolder() {
        let logsURL = databaseURL.deletingLastPathComponent().appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logsURL])
    }

    private func refreshAIDiagnostics() {
        aiDiagnosticSummary = AppleFoundationModelSupport.diagnosticSummary()
        aiLastFailure = AppleFoundationModelSupport.lastRuntimeFailureKind ?? "Sin fallos registrados"
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case localData
    case sync
    case localAI
    case privacy
    case diagnostic
    case backups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Apariencia"
        case .localData: return "Datos locales"
        case .sync: return "Sincronización"
        case .localAI: return "IA local"
        case .privacy: return "Privacidad"
        case .diagnostic: return "Diagnóstico"
        case .backups: return "Backups"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Curso, clase inicial y preferencias de trabajo."
        case .appearance: return "Tema, densidad visual y movimiento."
        case .localData: return "Estado, ruta y metadatos de la base de datos local."
        case .sync: return "Resumen operativo de Sync LAN y acceso a reparación."
        case .localAI: return "Modelos locales, módulos con IA e historial."
        case .privacy: return "Tratamiento local de datos del alumnado y diagnósticos."
        case .diagnostic: return "Estado técnico de KMP, SQLDelight, Sync e IA local."
        case .backups: return "Historial real de copias locales y creación manual."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .localData: return "externaldrive"
        case .sync: return "arrow.triangle.2.circlepath.circle"
        case .localAI: return "sparkles"
        case .privacy: return "lock.shield"
        case .diagnostic: return "stethoscope"
        case .backups: return "externaldrive.badge.timemachine"
        }
    }
}
