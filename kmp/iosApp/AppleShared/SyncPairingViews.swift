import SwiftUI
import MiGestorKit
#if canImport(VisionKit)
import VisionKit
#endif

#if os(macOS)
struct MacCommandCenterPairingCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let commandCenterState: AppleCommandCenterState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enlazar iPhone o iPad")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text(headlineText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 24) {
                Group {
                    if commandCenterState.serviceState.showsPairingCode,
                       let payload = commandCenterState.pairingPayload,
                       !payload.isEmpty {
                        QRCodeView(payload: payload, size: 176, padding: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 208, height: 208)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: placeholderSymbol)
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    Text(placeholderText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    statusBadge

                    if let host = commandCenterState.pairingHost,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "Host", value: host)
                    }
                    if let port = commandCenterState.pairingPort,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "Puerto", value: "\(port)")
                    }
                    if let pin = commandCenterState.pairingPin,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "PIN", value: pin)
                    }
                    if let payload = commandCenterState.pairingPayload,
                       !payload.isEmpty,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "Payload", value: payload)
                    }
                    Text(commandCenterState.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(primaryActionTitle) {
                            NotificationCenter.default.post(
                                name: primaryActionNotification,
                                object: nil
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Regenerar PIN") {
                            NotificationCenter.default.post(
                                name: .appleCommandCenterRegeneratePinRequested,
                                object: nil
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(commandCenterState.serviceState == .starting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(24)
    }

    @ViewBuilder
    private func commandMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private var headlineText: String {
        switch commandCenterState.serviceState {
        case .stopped:
            return "La sincronización LAN no está activa en este Mac."
        case .starting:
            return "Arrancando servicio de enlace en la red local."
        case .running:
            return "Escanea este QR desde el iPad para enlazar."
        case .networkError:
            return "Error de red local. Revisa la red de este Mac antes de enlazar."
        case .connected:
            return "iPad conectado a este Mac. Puedes volver a escanear el QR si necesitas reconectar."
        case .failed:
            return "No se pudo preparar el servicio de enlace en este Mac."
        }
    }

    private var placeholderText: String {
        switch commandCenterState.serviceState {
        case .starting:
            return "Arrancando servicio"
        case .networkError:
            return "Error de red local"
        case .failed:
            return "Servicio no disponible"
        case .connected, .running, .stopped:
            return "Sin código disponible"
        }
    }

    private var placeholderSymbol: String {
        switch commandCenterState.serviceState {
        case .networkError, .failed:
            return "wifi.exclamationmark"
        case .starting:
            return "bolt.horizontal.circle"
        case .connected, .running, .stopped:
            return "qrcode"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(badgeText)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.16), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeText: String {
        switch commandCenterState.serviceState {
        case .stopped:
            return "Servicio detenido"
        case .starting:
            return "Arrancando servicio"
        case .running:
            return "Listo para enlazar"
        case .networkError:
            return "Error de red local"
        case .connected:
            return "Conectado a iPad"
        case .failed:
            return "Servicio no disponible"
        }
    }

    private var badgeColor: Color {
        switch commandCenterState.serviceState {
        case .running, .connected:
            return .green
        case .starting:
            return .orange
        case .networkError, .failed:
            return .red
        case .stopped:
            return .secondary
        }
    }

    private var primaryActionTitle: String {
        switch commandCenterState.serviceState {
        case .stopped, .failed:
            return "Activar enlace"
        case .starting, .running, .networkError, .connected:
            return "Detener enlace"
        }
    }

    private var primaryActionNotification: Notification.Name {
        switch commandCenterState.serviceState {
        case .stopped, .failed:
            return .appleCommandCenterStartRequested
        case .starting, .running, .networkError, .connected:
            return .appleCommandCenterStopRequested
        }
    }
}
#endif

struct SyncLanCard: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedHost: String = ""
    @State private var selectedPort: String = "8765"
    @State private var pin: String = ""
    @State private var showingQrScanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Sincronización LAN", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(bridge.syncStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if bridge.pairedSyncHost != nil {
                HStack(spacing: 10) {
                    Text("Vinculado con \(bridge.pairedSyncHost ?? "-")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Desvincular") {
                        Task {
                            await bridge.unpairLanSync()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    TextField("Host desktop (ej. migestor.local)", text: $selectedHost)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Puerto", text: $selectedPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 80)
                    TextField("PIN", text: $pin)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 90)
                    Button {
                        showingQrScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    Button("Emparejar") {
                        Task {
                            let normalizedHost = selectedHost.trimmingCharacters(in: .whitespacesAndNewlines)
                            let normalizedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !normalizedHost.isEmpty else {
                                bridge.syncStatusMessage = "Introduce un host LAN válido del Mac."
                                return
                            }
                            guard let port = Int(selectedPort), (1...65535).contains(port) else {
                                bridge.syncStatusMessage = "El puerto de enlace no es válido."
                                return
                            }
                            guard port == 8765 else {
                                bridge.syncStatusMessage = "Esta compilación del iPad usa el puerto 8765 para enlazar con el Mac."
                                return
                            }
                            guard !normalizedPin.isEmpty else {
                                bridge.syncStatusMessage = "Introduce el PIN de enlace."
                                return
                            }

                            do {
                                let hostToUse = normalizedHost.isEmpty ? bridge.discoveredSyncHosts.first ?? "" : normalizedHost
                                let peer = bridge.discoveredPeer(forHost: hostToUse)
                                try await bridge.pairLanSync(
                                    host: hostToUse,
                                    pin: normalizedPin,
                                    expectedServerId: peer?.serverId,
                                    expectedFingerprint: peer?.fingerprint
                                )
                                selectedHost = hostToUse
                            } catch {
                                bridge.syncStatusMessage = "Error emparejando: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAttemptPairing)
                }
            }

            if !bridge.discoveredSyncHosts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bridge.discoveredSyncHosts, id: \.self) { host in
                            Button(host) { selectedHost = host }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Pull") {
                    Task {
                        do {
                            try await bridge.runLanPullSync()
                        } catch {
                            bridge.syncStatusMessage = "Error pull: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(bridge.pairedSyncHost == nil)

                Button("Push") {
                    Task {
                        do {
                            try await bridge.runLanPushSync()
                        } catch {
                            bridge.syncStatusMessage = "Error push: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(bridge.pairedSyncHost == nil)

                Spacer()
                Text("Pendientes: \(bridge.syncPendingChanges)")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(20)
        .sheet(isPresented: $showingQrScanner) {
            LanQrScannerSheet { payload in
                guard let parsed = parseSyncPayload(payload) else {
                    bridge.syncStatusMessage = "QR no válido para sincronización"
                    return
                }
                selectedHost = parsed.host
                selectedPort = "\(parsed.port)"
                pin = parsed.pin
                Task {
                    do {
                        guard parsed.port == 8765 else {
                            bridge.syncStatusMessage = "Este QR usa un puerto no compatible con esta compilación del iPad."
                            return
                        }
                        try await bridge.pairLanSync(
                            host: parsed.host,
                            pin: parsed.pin,
                            expectedServerId: parsed.serverId,
                            expectedFingerprint: parsed.fingerprint
                        )
                    } catch {
                        bridge.syncStatusMessage = "Error emparejando: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private var canAttemptPairing: Bool {
        let normalizedHost = selectedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty,
              let port = Int(selectedPort),
              (1...65535).contains(port),
              !normalizedPin.isEmpty else {
            return false
        }
        return true
    }

    private func parseSyncPayload(_ payload: String) -> (host: String, port: Int, pin: String, serverId: String?, fingerprint: String?)? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        if let components = URLComponents(string: text),
           let queryItems = components.queryItems,
           let host = queryItems.first(where: { $0.name.lowercased() == "host" })?.value,
           let portValue = queryItems.first(where: { $0.name.lowercased() == "port" })?.value,
           let port = Int(portValue),
           let pin = queryItems.first(where: { $0.name.lowercased() == "pin" })?.value,
           !host.isEmpty, !pin.isEmpty, (1...65535).contains(port) {
            let sid = queryItems.first(where: { $0.name.lowercased() == "sid" })?.value
            let fp = queryItems.first(where: { $0.name.lowercased() == "fp" })?.value
            return (host, port, pin, sid, fp)
        }

        if text.hasPrefix("{"),
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let host = object["host"] as? String,
           let port = (object["port"] as? Int) ?? ((object["port"] as? String).flatMap(Int.init)),
           let pin = object["pin"] as? String,
           !host.isEmpty, !pin.isEmpty, (1...65535).contains(port) {
            return (host, port, pin, object["sid"] as? String, object["fp"] as? String)
        }

        if text.contains("host="), text.contains("port="), text.contains("pin=") {
            let normalized = text.replacingOccurrences(of: " ", with: "&")
            if let components = URLComponents(string: "migestor://sync?\(normalized)"),
               let queryItems = components.queryItems,
               let host = queryItems.first(where: { $0.name.lowercased() == "host" })?.value,
               let portValue = queryItems.first(where: { $0.name.lowercased() == "port" })?.value,
               let port = Int(portValue),
               let pin = queryItems.first(where: { $0.name.lowercased() == "pin" })?.value {
                let sid = queryItems.first(where: { $0.name.lowercased() == "sid" })?.value
                let fp = queryItems.first(where: { $0.name.lowercased() == "fp" })?.value
                if !host.isEmpty, !pin.isEmpty, (1...65535).contains(port) {
                    return (host, port, pin, sid, fp)
                }
            }
        }

        return nil
    }
}

struct LanQrScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPayload: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
#if os(iOS) && canImport(VisionKit)
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    LanQrScannerView { payload in
                        onPayload(payload)
                        dismiss()
                    }
                } else {
                    Text("El escáner QR no está disponible en este dispositivo.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
#else
                Text("El escáner QR no está disponible en esta compilación.")
                    .foregroundStyle(.secondary)
                    .padding()
#endif
            }
            .navigationTitle("Escanear QR")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

#if os(iOS) && canImport(VisionKit)
struct LanQrScannerView: UIViewControllerRepresentable {
    let onFoundCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFoundCode: onFoundCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFoundCode: (String) -> Void
        private var didHandleCode = false

        init(onFoundCode: @escaping (String) -> Void) {
            self.onFoundCode = onFoundCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didHandleCode else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    didHandleCode = true
                    onFoundCode(payload)
                    return
                }
            }
        }
    }
}
#endif
