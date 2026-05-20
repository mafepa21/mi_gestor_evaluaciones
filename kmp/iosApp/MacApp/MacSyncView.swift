import SwiftUI
import AppKit

struct MacSyncView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    @State private var diagnosticFeedback: String?
    @State private var showsAdvancedDiagnostics = false

    private var connectionSummary: SyncConnectionSummary {
        SyncConnectionSummary(serviceState: commandCenter.serviceState)
    }

    private var healthSummary: SyncHealthSummary {
        SyncHealthSummary(
            connection: connectionSummary,
            pendingChanges: bridge.syncPendingChanges,
            lastSyncAt: bridge.syncLastRunAt,
            conflictCount: syncConflictCount
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                pageHeader
                connectionSection
                pairingSection
                advancedDiagnosticsSection
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync LAN")
                .font(MacAppStyle.pageTitle)
            Text("Centro operativo para enlazar, reconectar y supervisar la sincronización local.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Circle()
                    .fill(healthSummary.tint)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle()
                            .stroke(healthSummary.tint.opacity(0.24), lineWidth: 8)
                    }
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(healthSummary.title)
                            .font(.title3.weight(.semibold))
                        MacStatusPill(
                            label: healthSummary.visualStateLabel,
                            isActive: healthSummary.isAttentionState,
                            tint: healthSummary.tint
                        )
                    }

                    Text(healthSummary.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacAppStyle.cardSpacing) {
                statusMetric("Este dispositivo", currentDeviceName, "desktopcomputer")
                statusMetric("iPad conectado", connectionSummary.isConnected ? "Sí" : "No", "ipad")
                statusMetric("Última sincronización", bridge.syncLastRunAt.map(relativeTime) ?? "Sin registro", "clock")
                statusMetric("Cambios pendientes", "\(bridge.syncPendingChanges)", "arrow.up.circle")
                statusMetric("Conflictos", "\(syncConflictCount)", "exclamationmark.triangle")
            }

            commandCenterActions

            if let diagnosticFeedback {
                Text(diagnosticFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private func statusMetric(_ title: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(MacAppStyle.metricLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
    }

    private var commandCenterActions: some View {
        HStack(spacing: 8) {
            Button {
                connectIPad()
            } label: {
                Label("Conectar iPad", systemImage: "ipad.and.iphone")
            }
            .buttonStyle(.borderedProminent)
            .disabled(commandCenter.serviceState == .starting)

            Button {
                retrySync()
            } label: {
                Label("Reintentar sync", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(bridge.pairedSyncHost == nil)

            Button {
                showHistory()
            } label: {
                Label("Ver historial", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)

            Button {
                resolveConflicts()
            } label: {
                Label("Resolver conflictos", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.bordered)
            .disabled(syncConflictCount == 0)

            Button {
                copyPairingLink()
            } label: {
                Label("Copiar enlace de emparejamiento", systemImage: "link")
            }
            .buttonStyle(.bordered)
            .disabled(commandCenter.serviceState.pairingPayload == nil)

            Spacer()
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Emparejamiento")

            HStack(alignment: .center, spacing: 20) {
                if let payload = commandCenter.serviceState.pairingPayload {
                    QRCodeView(payload: payload, size: 150, padding: 12)
                } else {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .fill(MacAppStyle.subtleFill)
                        .frame(width: 174, height: 174)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: connectionSummary.placeholderImage)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(connectionSummary.placeholderText)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(connectionSummary.pairingTitle)
                        .font(.headline)
                    Text(connectionSummary.pairingDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        pairingMetric("PIN", commandCenter.serviceState.pairingPin ?? "—")
                        pairingMetric("Enlace", commandCenter.serviceState.pairingPayload == nil ? "No disponible" : "Disponible")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    private func pairingMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(MacAppStyle.metricLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
    }

    private var advancedDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(
                title: "Diagnóstico avanzado",
                action: { showsAdvancedDiagnostics.toggle() },
                actionLabel: showsAdvancedDiagnostics ? "Ocultar" : "Mostrar"
            )

            if showsAdvancedDiagnostics {
                VStack(alignment: .leading, spacing: 0) {
                    activityRow(title: "Último mensaje", value: commandCenter.statusMessage, systemImage: "text.bubble")
                    Divider()
                    activityRow(title: "Estado técnico", value: connectionSummary.shortTitle, systemImage: connectionSummary.systemImage)
                    Divider()
                    activityRow(title: "Host", value: connectionSummary.hostPort ?? "Sin host LAN", systemImage: "network")
                    Divider()
                    activityRow(title: "Dispositivo", value: connectionSummary.deviceName ?? "Sin dispositivo conectado", systemImage: "ipad")
                    Divider()
                    discoveredPeers
                    Divider()
                    HStack {
                        Button {
                            commandCenter.restartForNewPin()
                        } label: {
                            Label("Nuevo PIN", systemImage: "number.square")
                        }
                        .buttonStyle(.bordered)
                        .disabled(commandCenter.serviceState == .starting)

                        Button {
                            if commandCenter.serviceState == .stopped {
                                commandCenter.startIfNeeded()
                            } else {
                                commandCenter.stop()
                            }
                        } label: {
                            Label(commandCenter.serviceState == .stopped ? "Iniciar servicio" : "Detener servicio", systemImage: commandCenter.serviceState == .stopped ? "play.fill" : "stop.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            copyDiagnostic()
                        } label: {
                            Label("Copiar diagnóstico", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
    }

    private func activityRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var discoveredPeers: some View {
        if bridge.discoveredSyncHosts.isEmpty {
            activityRow(title: "Dispositivos detectados", value: "No hay hosts LAN descubiertos", systemImage: "desktopcomputer")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(bridge.discoveredSyncHosts.enumerated()), id: \.element) { index, host in
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(index == 0 ? "Dispositivos detectados" : "")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(host)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if host == bridge.pairedSyncHost {
                            MacStatusPill(label: "Vinculado", isActive: true)
                        }
                    }
                    .padding(.vertical, 11)

                    if index < bridge.discoveredSyncHosts.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func copyDiagnostic() {
        let lines = [
            "MiGestor Sync LAN",
            "Estado: \(connectionSummary.title)",
            "Salud: \(healthSummary.title)",
            "Host: \(connectionSummary.hostPort ?? "—")",
            "Dispositivo: \(connectionSummary.deviceName ?? "—")",
            "Pendientes: \(bridge.syncPendingChanges)",
            "Última sync: \(bridge.syncLastRunAt.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")",
            "Peers: \(bridge.discoveredSyncHosts.isEmpty ? "—" : bridge.discoveredSyncHosts.joined(separator: ", "))",
            "Mensaje: \(commandCenter.statusMessage)"
        ]

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        diagnosticFeedback = "Diagnóstico copiado al portapapeles."
    }

    private func connectIPad() {
        if commandCenter.serviceState == .stopped {
            commandCenter.startIfNeeded()
        } else {
            commandCenter.reconnect()
        }
        diagnosticFeedback = "Preparando enlace para el iPad."
    }

    private func retrySync() {
        Task {
            await bridge.pullMissingSyncChanges()
            diagnosticFeedback = "Sync reintentada."
        }
    }

    private func showHistory() {
        showsAdvancedDiagnostics = true
        diagnosticFeedback = bridge.syncLastRunAt.map { "Última sincronización: \($0.formatted(date: .abbreviated, time: .standard))." } ?? "Aún no hay historial de sincronización."
    }

    private func resolveConflicts() {
        showsAdvancedDiagnostics = true
        diagnosticFeedback = syncConflictCount == 0 ? "No hay conflictos pendientes." : "Revisa el diagnóstico avanzado para resolver el conflicto."
    }

    private func copyPairingLink() {
        guard let payload = commandCenter.serviceState.pairingPayload else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        diagnosticFeedback = "Enlace de emparejamiento copiado."
    }

    private var currentDeviceName: String {
        Host.current().localizedName ?? "Este Mac"
    }

    private var syncConflictCount: Int {
        let normalizedMessage = bridge.syncStatusMessage.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return normalizedMessage.contains("conflict") ? 1 : 0
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private enum SyncConnectionSummary {
    case stopped
    case starting
    case ready(host: String, port: Int)
    case connected(deviceName: String, host: String, port: Int)
    case networkError(String)
    case failed(String)

    init(serviceState: ApplePairingServiceState) {
        switch serviceState {
        case .stopped:
            self = .stopped
        case .starting:
            self = .starting
        case let .running(host, port, _, _, _):
            self = .ready(host: host, port: port)
        case let .connected(host, port, _, _, _, deviceName):
            self = .connected(deviceName: deviceName?.isEmpty == false ? deviceName! : "iPad", host: host, port: port)
        case let .networkError(message):
            self = .networkError(message)
        case let .failed(message):
            self = .failed(message)
        }
    }

    var title: String {
        switch self {
        case .stopped:
            return "Servicio detenido"
        case .starting:
            return "Iniciando servicio"
        case .ready:
            return "Preparado para enlazar"
        case let .connected(deviceName, _, _):
            return "Conectado a \(deviceName)"
        case .networkError:
            return "Error de red local"
        case .failed:
            return "Servicio no disponible"
        }
    }

    var shortTitle: String {
        switch self {
        case .stopped:
            return "Detenido"
        case .starting:
            return "Iniciando"
        case .ready:
            return "Preparado"
        case .connected:
            return "Conectado"
        case .networkError:
            return "Error de red"
        case .failed:
            return "Error"
        }
    }

    var subtitle: String {
        switch self {
        case .stopped:
            return "Inicia el servicio para aceptar enlaces desde iPhone o iPad."
        case .starting:
            return "Preparando el helper de red local y publicando el servicio."
        case let .ready(host, port):
            return "Escanea el QR desde el iPad para vincular este Mac · \(host):\(port)"
        case let .connected(_, host, port):
            return host.isEmpty ? "El iPad confirmó la conexión con este Mac." : "Sesión activa · \(host):\(port)"
        case let .networkError(message), let .failed(message):
            return message
        }
    }

    var pairingTitle: String {
        switch self {
        case .connected:
            return "Dispositivo enlazado"
        case .ready:
            return "Emparejar nuevo dispositivo"
        case .starting:
            return "Preparando emparejamiento"
        case .stopped:
            return "Servicio detenido"
        case .networkError, .failed:
            return "Emparejamiento no disponible"
        }
    }

    var pairingDetail: String {
        switch self {
        case .connected:
            return "El QR sigue disponible para repetir el enlace si cambias de dispositivo."
        case .ready:
            return "Escanea desde iPhone o iPad para vincular este Mac en la red local."
        case .starting:
            return "El QR aparecerá cuando el helper publique una IP LAN válida."
        case .stopped:
            return "Inicia Sync LAN para generar QR y PIN de emparejamiento."
        case .networkError:
            return "Revisa que el Mac esté conectado a una red local válida."
        case .failed:
            return "No se pudo preparar el helper de emparejamiento."
        }
    }

    var placeholderText: String {
        switch self {
        case .starting:
            return "Iniciando"
        case .networkError, .failed:
            return "Sin QR"
        default:
            return "QR inactivo"
        }
    }

    var placeholderImage: String {
        switch self {
        case .starting:
            return "hourglass"
        case .networkError, .failed:
            return "wifi.exclamationmark"
        default:
            return "qrcode"
        }
    }

    var hostPort: String? {
        switch self {
        case let .ready(host, port), let .connected(_, host, port):
            return host.isEmpty ? nil : "\(host):\(port)"
        case .stopped, .starting, .networkError, .failed:
            return nil
        }
    }

    var deviceName: String? {
        switch self {
        case let .connected(deviceName, _, _):
            return deviceName
        case .stopped, .starting, .ready, .networkError, .failed:
            return nil
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var tint: Color {
        switch self {
        case .connected, .ready:
            return MacAppStyle.successTint
        case .starting:
            return MacAppStyle.infoTint
        case .networkError, .failed:
            return MacAppStyle.dangerTint
        case .stopped:
            return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .ready:
            return "qrcode.viewfinder"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .networkError:
            return "wifi.exclamationmark"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .stopped:
            return "pause.circle"
        }
    }
}

private struct SyncHealthSummary {
    let title: String
    let detail: String
    let tint: Color
    let visualStateLabel: String
    let isAttentionState: Bool

    init(connection: SyncConnectionSummary, pendingChanges: Int, lastSyncAt: Date?, conflictCount: Int) {
        if conflictCount > 0 {
            title = "Conflicto de sincronización"
            detail = "\(conflictCount) conflicto requiere revisión antes de continuar."
            tint = MacAppStyle.dangerTint
            visualStateLabel = "Conflicto"
            isAttentionState = true
            return
        }

        switch connection {
        case .connected:
            if pendingChanges == 0 {
                title = "Sincronizado"
                detail = "0 cambios pendientes · Última sync \(lastSyncAt.map(Self.relativeTime) ?? "sin registro todavía")"
                tint = MacAppStyle.successTint
                visualStateLabel = "Verde"
                isAttentionState = true
            } else {
                title = "Cambios pendientes"
                detail = "\(pendingChanges) cambios esperan confirmación del iPad."
                tint = MacAppStyle.warningTint
                visualStateLabel = "Ámbar"
                isAttentionState = true
            }
        case .ready:
            title = "iPad no conectado"
            detail = "Este Mac está listo para emparejar, pero todavía no hay iPad conectado."
            tint = .secondary
            visualStateLabel = "Gris"
            isAttentionState = false
        case .starting:
            title = "Arrancando"
            detail = "Preparando la conexión LAN."
            tint = .secondary
            visualStateLabel = "Gris"
            isAttentionState = false
        case .stopped:
            title = "Sin conexión"
            detail = "El servicio está detenido."
            tint = .secondary
            visualStateLabel = "Gris"
            isAttentionState = false
        case .networkError:
            title = "Error de red local"
            detail = "No se ha podido publicar una IP LAN válida."
            tint = MacAppStyle.dangerTint
            visualStateLabel = "Rojo"
            isAttentionState = true
        case .failed:
            title = "Requiere atención"
            detail = "El helper no pudo iniciarse correctamente."
            tint = MacAppStyle.dangerTint
            visualStateLabel = "Rojo"
            isAttentionState = true
        }
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
