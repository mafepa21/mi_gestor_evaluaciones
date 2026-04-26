import SwiftUI

struct MacSyncView: View {
    @ObservedObject var bridge: KmpBridge
    @ObservedObject var commandCenter: MacCommandCenterCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                Text("Sincronización LAN")
                    .font(MacAppStyle.pageTitle)

                metricsRow
                commandCenterSection
                bridgeStatusSection
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: MacAppStyle.cardSpacing) {
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
                label: "Host vinculado",
                value: bridge.pairedSyncHost ?? "Sin vincular",
                tint: bridge.pairedSyncHost != nil ? MacAppStyle.successTint : .secondary,
                systemImage: "network"
            )
        }
    }

    private var commandCenterSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Centro de mando")
            VStack(alignment: .leading, spacing: 12) {
                commandCenterStatus
                Divider()
                commandCenterActions
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

    @ViewBuilder
    private var commandCenterStatus: some View {
        switch commandCenter.serviceState {
        case .stopped:
            HStack(spacing: 8) {
                Circle().fill(.secondary).frame(width: 8, height: 8)
                Text("Servicio detenido").font(.callout)
                Spacer()
            }
        case .starting:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Iniciando…").font(.callout)
                Spacer()
            }
        case let .running(host, port, pin, _, _):
            HStack(alignment: .top, spacing: 16) {
                if let payload = commandCenter.serviceState.pairingPayload {
                    QRCodeView(payload: payload, size: 96, padding: 8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listo para enlazar")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(MacAppStyle.successTint)
                    Text("PIN: \(pin)")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Text("\(host):\(port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Escanea el QR desde iPad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case let .connected(host, port, pin, _, _, deviceName):
            HStack(alignment: .top, spacing: 16) {
                if let payload = commandCenter.serviceState.pairingPayload {
                    QRCodeView(payload: payload, size: 96, padding: 8)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MacAppStyle.successTint)
                        Text("Conectado\(deviceName.map { " a \($0)" } ?? "")")
                            .font(.callout.weight(.semibold))
                    }
                    Text("PIN: \(pin)")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Text("\(host):\(port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case let .failed(message), let .networkError(message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MacAppStyle.dangerTint)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(MacAppStyle.dangerTint)
                Spacer()
            }
        }

        Text(commandCenter.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var commandCenterActions: some View {
        HStack(spacing: 8) {
            Button("Iniciar servicio") {
                commandCenter.startIfNeeded()
            }
            .buttonStyle(.bordered)
            .disabled(commandCenter.serviceState != .stopped)

            Button("Detener") {
                commandCenter.stop()
            }
            .buttonStyle(.bordered)
            .disabled(commandCenter.serviceState == .stopped)

            Button("Nuevo PIN") {
                commandCenter.restartForNewPin()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var bridgeStatusSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Peers descubiertos")
            if bridge.discoveredSyncHosts.isEmpty {
                Text("No hay hosts LAN descubiertos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bridge.discoveredSyncHosts.enumerated()), id: \.element) { index, host in
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.secondary)
                            Text(host)
                                .font(.callout)
                            Spacer()
                            if host == bridge.pairedSyncHost {
                                MacStatusPill(label: "Vinculado", isActive: true)
                            }
                        }
                        .padding(.vertical, 10)

                        if index < bridge.discoveredSyncHosts.count - 1 {
                            Divider()
                        }
                    }
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

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
