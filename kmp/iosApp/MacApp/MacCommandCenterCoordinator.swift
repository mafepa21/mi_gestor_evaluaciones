import Foundation
import AppKit

final class MacCommandCenterCoordinator: ObservableObject {
    @Published private(set) var statusMessage: String = "Centro de mando detenido"
    @Published private(set) var pairingPayload: String?
    @Published private(set) var pairingHost: String?
    @Published private(set) var pairingPin: String?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        stop()
    }

    func startIfNeeded() {
        if process?.isRunning == true { return }

        guard let executableURL = resolveHelperExecutableURL() else {
            statusMessage = "No se encontró el helper del centro de mando"
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--sync-server-only"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            Task { @MainActor in
                self?.consumeHelperMessage(text)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            Task { @MainActor in
                self?.consumeHelperMessage(text)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                self?.statusMessage = "Centro de mando detenido (\(terminatedProcess.terminationStatus))"
                self?.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stdoutPipe = nil
                self?.stderrPipe = nil
                self?.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            statusMessage = "Centro de mando macOS activo"
        } catch {
            statusMessage = "No se pudo iniciar el centro de mando: \(error.localizedDescription)"
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    var environmentState: AppleCommandCenterState {
        AppleCommandCenterState(
            statusMessage: statusMessage,
            pairingPayload: pairingPayload,
            pairingHost: pairingHost,
            pairingPin: pairingPin,
            isAvailable: true
        )
    }

    @MainActor
    private func consumeHelperMessage(_ text: String) {
        if let payload = extractValue(prefix: "[command-center] Pairing payload:", from: text) {
            pairingPayload = payload
            if let components = URLComponents(string: payload) {
                pairingHost = components.queryItems?.first(where: { $0.name == "host" })?.value
                pairingPin = components.queryItems?.first(where: { $0.name == "pin" })?.value
            }
        }

        if let hostLine = extractValue(prefix: "[command-center] Server ready at ", from: text) {
            statusMessage = "Centro de mando macOS activo · \(hostLine)"
        } else {
            statusMessage = text
        }
    }

    private func extractValue(prefix: String, from text: String) -> String? {
        guard text.hasPrefix(prefix) else { return nil }
        return text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveHelperExecutableURL() -> URL? {
        let fileManager = FileManager.default

        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("MiGestorCommandCenter.app/Contents/MacOS/MiGestorCommandCenter"),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        let iosAppDirectory = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
        let kmpDirectory = iosAppDirectory.deletingLastPathComponent()
        let devHelper = kmpDirectory
            .appendingPathComponent("commandCenterHelper/build/compose/binaries/main/app/MiGestorCommandCenter.app/Contents/MacOS/MiGestorCommandCenter")

        if fileManager.isExecutableFile(atPath: devHelper.path) {
            return devHelper
        }

        return nil
    }
}
