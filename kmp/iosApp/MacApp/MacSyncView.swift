import SwiftUI
import AppKit

struct MacSyncView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var commandCenter: MacCommandCenterCoordinator
    @State private var diagnosticFeedback: String?

    private var connectionSummary: SyncConnectionSummary {
        SyncConnectionSummary(serviceState: commandCenter.serviceState)
    }

    private var healthSummary: SyncHealthSummary {
        SyncHealthSummary(
            connection: connectionSummary,
            pendingChanges: bridge.syncPendingChanges,
            lastSyncAt: bridge.syncLastRunAt
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                pageHeader
                connectionSection
                pairingSection
                activitySection
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
                Image(systemName: connectionSummary.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(connectionSummary.tint)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(connectionSummary.title)
                            .font(.title3.weight(.semibold))
                        MacStatusPill(
                            label: healthSummary.title,
                            isActive: healthSummary.isHealthy,
                            tint: healthSummary.tint
                        )
                    }

                    Text(connectionSummary.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(healthSummary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: MacAppStyle.cardSpacing) {
                statusMetric("Host", connectionSummary.hostPort ?? "Sin host LAN", "network")
                statusMetric("Última actividad", bridge.syncLastRunAt.map(relativeTime) ?? "Sin sync registrada", "clock")
                statusMetric("Pendientes", "\(bridge.syncPendingChanges)", "arrow.up.circle")
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
                commandCenter.reconnect()
            } label: {
                Label("Reconectar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(commandCenter.serviceState == .starting)

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
                Label(commandCenter.serviceState == .stopped ? "Iniciar" : "Detener", systemImage: commandCenter.serviceState == .stopped ? "play.fill" : "stop.fill")
            }
            .buttonStyle(.bordered)

            Button {
                copyDiagnostic()
            } label: {
                Label("Copiar diagnóstico", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)

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
                        pairingMetric("Host", connectionSummary.hostPort ?? "—")
                    }

                    Text(commandCenter.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Actividad de sincronización")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: MacAppStyle.cardSpacing) {
                MacMetricCard(
                    label: "Cambios pendientes",
                    value: "\(bridge.syncPendingChanges)",
                    tint: bridge.syncPendingChanges > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint,
                    systemImage: "arrow.up.circle"
                )
                MacMetricCard(
                    label: "Última sync",
                    value: bridge.syncLastRunAt.map(shortTime) ?? "—",
                    systemImage: "clock"
                )
                MacMetricCard(
                    label: "Último estado",
                    value: connectionSummary.shortTitle,
                    tint: connectionSummary.tint,
                    systemImage: connectionSummary.systemImage
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                activityRow(title: "Último mensaje", value: commandCenter.statusMessage, systemImage: "text.bubble")
                Divider()
                activityRow(title: "Dispositivo", value: connectionSummary.deviceName ?? "Sin dispositivo conectado", systemImage: "ipad")
                Divider()
                discoveredPeers
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

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
    let isHealthy: Bool

    init(connection: SyncConnectionSummary, pendingChanges: Int, lastSyncAt: Date?) {
        switch connection {
        case .connected:
            if pendingChanges == 0 {
                title = "Sync estable"
                detail = "0 cambios pendientes · Última sync \(lastSyncAt.map(Self.relativeTime) ?? "sin registro todavía")"
                tint = MacAppStyle.successTint
                isHealthy = true
            } else {
                title = "Sync pendiente"
                detail = "\(pendingChanges) cambios esperan confirmación del iPad."
                tint = MacAppStyle.warningTint
                isHealthy = false
            }
        case .ready:
            title = "Preparado"
            detail = "Servicio activo, esperando confirmación de un dispositivo."
            tint = MacAppStyle.infoTint
            isHealthy = true
        case .starting:
            title = "Arrancando"
            detail = "El helper está preparando la conexión LAN."
            tint = MacAppStyle.infoTint
            isHealthy = false
        case .stopped:
            title = "Sin conexión"
            detail = "El servicio está detenido."
            tint = .secondary
            isHealthy = false
        case .networkError:
            title = "Red inestable"
            detail = "No se ha podido publicar una IP LAN válida."
            tint = MacAppStyle.dangerTint
            isHealthy = false
        case .failed:
            title = "Requiere atención"
            detail = "El helper no pudo iniciarse correctamente."
            tint = MacAppStyle.dangerTint
            isHealthy = false
        }
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
