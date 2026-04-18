import SwiftUI
import AppKit
import Darwin

struct MacSettingsView: View {
    @ObservedObject var session: MacAppSessionController
    @State private var pairingCode = MacPairingCode.load()
    @State private var pairingFeedback: String?

    var body: some View {
        Form {
            Section("Bootstrap Apple") {
                LabeledContent("Plataforma", value: session.bootstrap.platformName)
                LabeledContent("Base de datos", value: session.bootstrap.databasePath)
                LabeledContent("Estado", value: session.bridge.status)
            }

            Section("Enlazar con iPhone") {
                HStack(alignment: .top, spacing: 20) {
                    QRCodeView(payload: pairingCode.payload, size: 148, padding: 14)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Escanea este QR desde el iPhone para iniciar el pairing local.")
                            .foregroundStyle(.secondary)

                        LabeledContent("Device ID", value: pairingCode.deviceId)
                        LabeledContent("Token", value: pairingCode.token)

                        Text(pairingCode.payload)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(3)

                        HStack(spacing: 12) {
                            Button("Copiar código") {
                                copyPairingCode()
                            }

                            Button("Regenerar") {
                                regeneratePairingCode()
                            }
                        }

                        if let pairingFeedback {
                            Text(pairingFeedback)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }

            Section("Shell") {
                Toggle("Mostrar inspector por defecto", isOn: $session.inspectorVisible)
            }

            Section("Cobertura v1") {
                ForEach(MacFeatureRegistry.all) { feature in
                    HStack {
                        Label(feature.title, systemImage: feature.systemImage)
                        Spacer()
                        Text(feature.source.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode.payload, forType: .string)
        pairingFeedback = "Código copiado al portapapeles."
    }

    private func regeneratePairingCode() {
        pairingCode = MacPairingCode.regenerated(from: pairingCode)
        pairingFeedback = "Se ha generado un nuevo token de enlace."
    }
}

private struct MacPairingCode {
    let deviceId: String
    let token: String

    var host: String { Self.localIPAddress() ?? "localhost" }

    var payload: String {
        var components = URLComponents()
        components.scheme = "migestor"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "pin", value: token),
            URLQueryItem(name: "sid", value: deviceId),
        ]
        return components.url?.absoluteString
            ?? "migestor://pair?host=\(host)&pin=\(token)&sid=\(deviceId)"
    }

    static func load(defaults: UserDefaults = .standard) -> MacPairingCode {
        let deviceIdKey = "mac_pairing_device_id"
        let tokenKey = "mac_pairing_token"

        let existingDeviceId = defaults.string(forKey: deviceIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceId = (existingDeviceId?.isEmpty == false) ? existingDeviceId! : UUID().uuidString.lowercased()

        let existingToken = defaults.string(forKey: tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (existingToken?.isEmpty == false) ? existingToken! : Self.makeToken()

        let code = MacPairingCode(deviceId: deviceId, token: token)
        code.persist(defaults: defaults)
        return code
    }

    static func regenerated(from existing: MacPairingCode, defaults: UserDefaults = .standard) -> MacPairingCode {
        let code = MacPairingCode(deviceId: existing.deviceId, token: makeToken())
        code.persist(defaults: defaults)
        return code
    }

    private func persist(defaults: UserDefaults) {
        defaults.set(deviceId, forKey: "mac_pairing_device_id")
        defaults.set(token, forKey: "mac_pairing_token")
    }

    private static func makeToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func localIPAddress() -> String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = current {
            let entry = interface.pointee
            defer { current = entry.ifa_next }

            guard let socketAddress = entry.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let interfaceName = String(cString: entry.ifa_name)
            guard interfaceName == "en0" else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            address = String(cString: hostBuffer)
            break
        }

        return address
    }
}
