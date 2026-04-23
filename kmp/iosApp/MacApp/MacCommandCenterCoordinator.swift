import Foundation
import AppKit

@MainActor
final class MacCommandCenterCoordinator: ObservableObject {
    @Published private(set) var statusMessage: String = "La sincronización LAN no está activa en este Mac."
    @Published private(set) var serviceState: ApplePairingServiceState = .stopped

    private let defaultPort = 8765
    private let invalidLanHosts = Set(["localhost", "127.0.0.1", ""])

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var observers: [NSObjectProtocol] = []
    private var shouldRestartAfterStop = false
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    private var isProcessRunning = false
    private var lastLifecycleState: HelperLifecycleState = .stopped
    private var lastFailureMessage: String?
    private var lastRunningSnapshot: RunningSnapshot?

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .appleCommandCenterStartRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startIfNeeded()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .appleCommandCenterStopRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .appleCommandCenterRegeneratePinRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restartForNewPin()
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startIfNeeded() {
        guard process?.isRunning != true else { return }

        print("[Pairing] start requested")
        lastFailureMessage = nil
        lastRunningSnapshot = nil
        lastLifecycleState = .starting
        clearHelperBuffers()
        updateState(.starting, message: "Arrancando servicio de enlace en este Mac.")

        guard let executableURL = resolveHelperExecutableURL() else {
            let message = "No se encontró el helper del centro de mando."
            print("[Pairing] failed: \(message)")
            lastFailureMessage = message
            lastLifecycleState = .failed
            updateState(.failed(message: message), message: message)
            return
        }

        terminateStaleHelperProcesses(executableURL: executableURL)

        let appSupportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MiGestor", isDirectory: true)

        if let appSupportDirectory {
            try? FileManager.default.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let launchedProcess = Process()
        launchedProcess.executableURL = executableURL
        var arguments = ["--sync-server-only"]
        if let appSupportDirectory {
            let databasePath = appSupportDirectory
                .appendingPathComponent("desktop_mi_gestor_kmp.db", isDirectory: false)
                .path
            arguments.append(contentsOf: ["--db-path", databasePath])
        }
        launchedProcess.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        launchedProcess.standardOutput = stdout
        launchedProcess.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consumeHelperChunk(chunk, isError: false)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consumeHelperChunk(chunk, isError: true)
            }
        }

        launchedProcess.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self else { return }
                print("[Pairing] helper terminated: \(terminatedProcess.terminationStatus)")
                self.isProcessRunning = false
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                self.process = nil
                self.clearHelperBuffers()

                if self.shouldRestartAfterStop {
                    self.shouldRestartAfterStop = false
                    self.startIfNeeded()
                    return
                }

                if case .failed = self.lastLifecycleState {
                    let message = self.lastFailureMessage ?? "El helper terminó inesperadamente."
                    self.updateState(.failed(message: message), message: message)
                    return
                }

                if terminatedProcess.terminationStatus != 0 {
                    let message = self.lastFailureMessage
                        ?? "El helper de enlace terminó con código \(terminatedProcess.terminationStatus)."
                    self.lastFailureMessage = message
                    self.lastLifecycleState = .failed
                    self.updateState(.failed(message: message), message: message)
                    return
                }

                self.lastRunningSnapshot = nil
                self.lastLifecycleState = .stopped
                self.updateState(.stopped, message: "La sincronización LAN no está activa en este Mac.")
            }
        }

        do {
            try launchedProcess.run()
            process = launchedProcess
            stdoutPipe = stdout
            stderrPipe = stderr
            isProcessRunning = true
            print("[Pairing] helper launched")
        } catch {
            isProcessRunning = false
            let resolvedMessage = friendlyLaunchMessage(for: error)
            lastFailureMessage = resolvedMessage
            lastLifecycleState = .failed
            print("[Pairing] failed: \(resolvedMessage)")
            updateState(.failed(message: resolvedMessage), message: resolvedMessage)
        }
    }

    func stop() {
        shouldRestartAfterStop = false
        isProcessRunning = false
        lastFailureMessage = nil
        lastLifecycleState = .stopped
        lastRunningSnapshot = nil
        clearHelperBuffers()
        updateState(.stopped, message: "La sincronización LAN no está activa en este Mac.")
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    func restartForNewPin() {
        print("[Pairing] start requested")
        lastFailureMessage = nil
        lastRunningSnapshot = nil
        lastLifecycleState = .starting
        clearHelperBuffers()
        updateState(.starting, message: "Regenerando PIN de enlace...")

        guard process?.isRunning == true else {
            shouldRestartAfterStop = false
            startIfNeeded()
            return
        }

        shouldRestartAfterStop = true
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    var environmentState: AppleCommandCenterState {
        AppleCommandCenterState(
            statusMessage: statusMessage,
            serviceState: serviceState,
            isAvailable: true
        )
    }

    private func updateState(_ newState: ApplePairingServiceState, message: String) {
        guard serviceState != newState || statusMessage != message else { return }
        serviceState = newState
        statusMessage = message
    }

    private func terminateStaleHelperProcesses(executableURL: URL) {
        let executablePath = executableURL.path
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", executablePath]

        let outputPipe = Pipe()
        pgrep.standardOutput = outputPipe
        pgrep.standardError = Pipe()

        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }

        guard pgrep.terminationStatus == 0,
              let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return
        }

        let currentPid = ProcessInfo.processInfo.processIdentifier
        let activeChildPid = process?.processIdentifier
        let stalePids = output
            .split(whereSeparator: \.isNewline)
            .compactMap { pidLine in Int32(pidLine.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { pid in
                pid > 0 && pid != currentPid && pid != activeChildPid
            }

        guard !stalePids.isEmpty else { return }

        for pid in stalePids {
            let killer = Process()
            killer.executableURL = URL(fileURLWithPath: "/bin/kill")
            killer.arguments = ["-TERM", "\(pid)"]
            killer.standardOutput = Pipe()
            killer.standardError = Pipe()
            do {
                try killer.run()
                killer.waitUntilExit()
                print("[Pairing] terminated stale helper pid \(pid)")
            } catch {
                print("[Pairing] failed to terminate stale helper pid \(pid): \(error.localizedDescription)")
            }
        }

        Thread.sleep(forTimeInterval: 0.25)
    }

    private func friendlyLaunchMessage(for error: Error) -> String {
        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawMessage.localizedCaseInsensitiveContains("address already in use") {
            return "El puerto 8765 ya está en uso por otro servicio de enlace. Cierra instancias antiguas de MiGestor e inténtalo de nuevo."
        }
        return "No se pudo iniciar el servicio de enlace: \(rawMessage)"
    }

    private func clearHelperBuffers() {
        stdoutBuffer = ""
        stderrBuffer = ""
    }

    private func consumeHelperChunk(_ chunk: String, isError: Bool) {
        if isError {
            stderrBuffer += chunk
            flushHelperLines(from: &stderrBuffer)
        } else {
            stdoutBuffer += chunk
            flushHelperLines(from: &stdoutBuffer)
        }
    }

    private func flushHelperLines(from buffer: inout String) {
        let normalized = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let hasTrailingNewline = normalized.hasSuffix("\n")

        buffer = hasTrailingNewline ? "" : String(lines.last ?? "")

        for line in hasTrailingNewline ? lines[...] : lines.dropLast() {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            consumeHelperMessage(text)
        }
    }

    private func consumeHelperMessage(_ text: String) {
        guard !text.isEmpty else { return }
        if let event = HelperEvent.parse(from: text) {
            consumeHelperEvent(event)
            return
        }

        if text.contains("Handshake exitoso") {
            promoteToConnected(deviceName: nil)
            return
        }
    }

    private func consumeHelperEvent(_ event: HelperEvent) {
        switch event {
        case .starting:
            lastLifecycleState = .starting
            updateState(.starting, message: "Arrancando servicio de enlace en este Mac.")

        case let .running(snapshot):
            let normalizedHost = snapshot.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if invalidLanHosts.contains(normalizedHost) {
                print("[Pairing] invalid LAN host: \(snapshot.host)")
                lastLifecycleState = .networkError
                let message = "No se pudo resolver una IP LAN válida para este Mac."
                updateState(.networkError(message: message), message: message)
                return
            }

            if lastLifecycleState == .running, lastRunningSnapshot == snapshot {
                return
            }

            lastRunningSnapshot = snapshot
            lastLifecycleState = .running
            print("[Pairing] received payload: \(snapshot.payload)")
            print("[Pairing] published running state")
            updateState(
                .running(
                    host: snapshot.host,
                    port: snapshot.port,
                    pin: snapshot.pin,
                    sessionId: snapshot.sessionId,
                    fingerprint: snapshot.fingerprint
                ),
                message: "Escanea este QR desde el iPad para enlazar."
            )

        case let .networkError(message):
            lastLifecycleState = .networkError
            lastFailureMessage = message
            print("[Pairing] invalid LAN host: \(message)")
            updateState(.networkError(message: message), message: message)

        case let .connected(deviceName):
            promoteToConnected(deviceName: deviceName)

        case let .failed(message):
            lastLifecycleState = .failed
            lastFailureMessage = message
            print("[Pairing] failed: \(message)")
            updateState(.failed(message: message), message: message)
        }
    }

    private func promoteToConnected(deviceName: String?) {
        guard let lastRunningSnapshot else {
            lastLifecycleState = .connected
            updateState(.connected(host: "", port: defaultPort, pin: "", sessionId: "", fingerprint: nil, deviceName: deviceName), message: "Conectado a iPad.")
            return
        }

        lastLifecycleState = .connected
        updateState(
            .connected(
                host: lastRunningSnapshot.host,
                port: lastRunningSnapshot.port,
                pin: lastRunningSnapshot.pin,
                sessionId: lastRunningSnapshot.sessionId,
                fingerprint: lastRunningSnapshot.fingerprint,
                deviceName: deviceName
            ),
            message: "Conectado a iPad."
        )
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

private enum HelperLifecycleState {
    case stopped
    case starting
    case running
    case networkError
    case connected
    case failed
}

private struct RunningSnapshot: Equatable {
    let host: String
    let port: Int
    let pin: String
    let sessionId: String
    let fingerprint: String?

    var payload: String {
        var components = URLComponents()
        components.scheme = "migestor"
        components.host = "pair"
        var queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: "\(port)"),
            URLQueryItem(name: "pin", value: pin),
            URLQueryItem(name: "sid", value: sessionId),
        ]
        if let fingerprint, !fingerprint.isEmpty {
            queryItems.append(URLQueryItem(name: "fp", value: fingerprint))
        }
        components.queryItems = queryItems
        return components.url?.absoluteString
            ?? "migestor://pair?host=\(host)&port=\(port)&pin=\(pin)&sid=\(sessionId)"
    }
}

private enum HelperEvent {
    case starting
    case running(RunningSnapshot)
    case networkError(message: String)
    case connected(deviceName: String?)
    case failed(message: String)

    static func parse(from text: String) -> HelperEvent? {
        let prefix = "[command-center] State: "
        guard text.hasPrefix(prefix) else { return nil }

        let payload = String(text.dropFirst(prefix.count))
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let stateName = parts.first?.lowercased() else { return nil }

        switch stateName {
        case "starting":
            return .starting

        case "running":
            let values = Dictionary(uniqueKeysWithValues: parts.dropFirst().compactMap { segment -> (String, String)? in
                let pair = segment.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                return (pair[0].lowercased(), pair[1])
            })
            guard let host = values["host"],
                  let pin = values["pin"],
                  let sessionId = values["sid"],
                  let portString = values["port"],
                  let port = Int(portString) else {
                return nil
            }
            return .running(
                RunningSnapshot(
                    host: host,
                    port: port,
                    pin: pin,
                    sessionId: sessionId,
                    fingerprint: values["fp"]
                )
            )

        case "network_error":
            let message = parts.dropFirst().joined(separator: "|")
            return .networkError(message: message.isEmpty ? "No se pudo resolver una IP LAN válida para este Mac." : message)

        case "connected":
            let values = Dictionary(uniqueKeysWithValues: parts.dropFirst().compactMap { segment -> (String, String)? in
                let pair = segment.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                return (pair[0].lowercased(), pair[1])
            })
            return .connected(deviceName: values["device"])

        case "failed":
            let message = parts.dropFirst().joined(separator: "|")
            return .failed(message: message.isEmpty ? "El helper terminó con un error desconocido." : message)

        default:
            return nil
        }
    }
}

extension Notification.Name {
    static let appleCommandCenterStartRequested = Notification.Name("appleCommandCenterStartRequested")
    static let appleCommandCenterStopRequested = Notification.Name("appleCommandCenterStopRequested")
    static let appleCommandCenterRegeneratePinRequested = Notification.Name("appleCommandCenterRegeneratePinRequested")
}
