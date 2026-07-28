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
    private var lastPublishedPairingPayload: String?
    private var stateUpdateGeneration = 0

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
        guard !AppleBackupService.shared.needsRestart else { return }
        guard process?.isRunning != true else { return }

        print("[Pairing] start requested")
        lastFailureMessage = nil
        lastRunningSnapshot = nil
        lastPublishedPairingPayload = nil
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
                // Un helper anterior (p. ej. terminado por terminateStaleHelperProcesses
                // o por stop()) puede seguir muriendo cuando ya arrancamos uno nuevo: su
                // terminationHandler se dispara en un Task posterior y, sin esta guarda,
                // desmontaría los pipes y el `process` del helper NUEVO que sí sigue vivo.
                guard let self, self.process === terminatedProcess else { return }
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
                NotificationCenter.default.post(name: .syncHelperStopped, object: nil)
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
        NotificationCenter.default.post(name: .syncHelperStopped, object: nil)
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

    func reconnect() {
        print("[Pairing] reconnect requested")
        lastFailureMessage = nil
        lastRunningSnapshot = nil
        lastLifecycleState = .starting
        clearHelperBuffers()
        updateState(.starting, message: "Reconectando servicio LAN...")

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
        stateUpdateGeneration += 1
        let generation = stateUpdateGeneration
        Task { @MainActor in
            await Task.yield()
            guard generation == stateUpdateGeneration else { return }
            serviceState = newState
            statusMessage = message
        }
    }

    /// Encuentra y termina cualquier instancia huérfana del helper de sincronización LAN
    /// antes de arrancar una nueva, para liberar el puerto 8765.
    ///
    /// Se combinan dos estrategias porque ninguna es suficiente por sí sola:
    /// - Coincidencia por ruta del ejecutable, usando solo el sufijo estable del bundle
    ///   (`MiGestorCommandCenter.app/Contents/MacOS/MiGestorCommandCenter`) y no la ruta
    ///   absoluta completa. En builds de desarrollo, Xcode regenera el hash de
    ///   DerivedData al reconstruir, así que un helper huérfano de un build anterior
    ///   tiene una ruta distinta a la del build actual y `pgrep -f <rutaCompleta>` nunca
    ///   lo encuentra: el proceso queda vivo para siempre reteniendo el puerto.
    /// - Búsqueda directa de quién escucha en el puerto 8765 (vía `lsof`), como red de
    ///   seguridad para cualquier caso no cubierto por la coincidencia de ruta.
    private func terminateStaleHelperProcesses(executableURL: URL) {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let activeChildPid = process?.processIdentifier

        var stalePids = Set<Int32>()
        stalePids.formUnion(pidsMatchingHelperExecutable(executableURL, currentPid: currentPid, activeChildPid: activeChildPid))
        stalePids.formUnion(pidsListeningOnPort(defaultPort, currentPid: currentPid, activeChildPid: activeChildPid))
        // El fallback por puerto no distingue qué proceso encontró, y `pgrep -f` empareja
        // contra el argv completo (podría coincidir con un paso de build que solo mencione
        // la ruta, p. ej. codesign/ditto). Verificamos vía `ps` que sea realmente el helper
        // antes de matar nada.
        stalePids = Set(stalePids.filter(isHelperProcess))

        guard !stalePids.isEmpty else { return }

        for pid in stalePids {
            sendSignal("-TERM", to: pid)
        }

        waitForPortToFree(defaultPort, timeout: 2.0, currentPid: currentPid, activeChildPid: activeChildPid)

        let stillListening = pidsListeningOnPort(defaultPort, currentPid: currentPid, activeChildPid: activeChildPid)
            .filter(isHelperProcess)
        guard !stillListening.isEmpty else { return }

        for pid in stillListening {
            sendSignal("-KILL", to: pid)
        }
        waitForPortToFree(defaultPort, timeout: 1.0, currentPid: currentPid, activeChildPid: activeChildPid)
    }

    /// Verifica vía `ps` que un PID candidato es realmente el helper de MiGestor antes de
    /// terminarlo. Sin esto, la búsqueda por puerto (que no filtra por identidad) o un
    /// `pgrep -f` con coincidencia accidental podrían matar un proceso ajeno al servicio
    /// de enlace.
    private func isHelperProcess(pid: Int32) -> Bool {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", "\(pid)", "-o", "comm="]

        let outputPipe = Pipe()
        ps.standardOutput = outputPipe
        ps.standardError = FileHandle.nullDevice

        do {
            try ps.run()
        } catch {
            return false
        }

        // Leer hasta EOF antes de esperar la salida del proceso: si se invirtiera el
        // orden y `ps` llegara a escribir más de lo que cabe en el buffer del pipe,
        // `waitUntilExit()` podría bloquearse esperando a un proceso a su vez bloqueado
        // escribiendo en un pipe lleno que nadie está drenando.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()

        guard ps.terminationStatus == 0,
              let commandName = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !commandName.isEmpty else {
            return false
        }

        return commandName.localizedCaseInsensitiveContains("MiGestorCommandCenter")
    }

    /// Últimos componentes de la ruta del ejecutable (bundle + binario), estables entre
    /// builds, usados como patrón de búsqueda en vez de la ruta absoluta completa.
    private func helperExecutableMatchPattern(for executableURL: URL) -> String {
        let components = executableURL.pathComponents
        return components.suffix(min(4, components.count)).joined(separator: "/")
    }

    private func pidsMatchingHelperExecutable(_ executableURL: URL, currentPid: Int32, activeChildPid: Int32?) -> [Int32] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", helperExecutableMatchPattern(for: executableURL)]

        let outputPipe = Pipe()
        pgrep.standardOutput = outputPipe
        pgrep.standardError = FileHandle.nullDevice

        do {
            try pgrep.run()
        } catch {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()

        guard pgrep.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return parsePids(from: output, currentPid: currentPid, activeChildPid: activeChildPid)
    }

    private func pidsListeningOnPort(_ port: Int, currentPid: Int32, activeChildPid: Int32?) -> [Int32] {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-b", "-w", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]

        let outputPipe = Pipe()
        lsof.standardOutput = outputPipe
        lsof.standardError = FileHandle.nullDevice

        do {
            try lsof.run()
        } catch {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return parsePids(from: output, currentPid: currentPid, activeChildPid: activeChildPid)
    }

    private func parsePids(from output: String, currentPid: Int32, activeChildPid: Int32?) -> [Int32] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { pidLine in Int32(pidLine.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { pid in pid > 0 && pid != currentPid && pid != activeChildPid }
    }

    private func sendSignal(_ signal: String, to pid: Int32) {
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/kill")
        killer.arguments = [signal, "\(pid)"]
        killer.standardOutput = FileHandle.nullDevice
        killer.standardError = FileHandle.nullDevice
        do {
            try killer.run()
            killer.waitUntilExit()
            print("[Pairing] sent \(signal) to stale helper pid \(pid)")
        } catch {
            print("[Pairing] failed to signal stale helper pid \(pid): \(error.localizedDescription)")
        }
    }

    private func waitForPortToFree(_ port: Int, timeout: TimeInterval, currentPid: Int32, activeChildPid: Int32?) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pidsListeningOnPort(port, currentPid: currentPid, activeChildPid: activeChildPid).isEmpty {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func friendlyLaunchMessage(for error: Error) -> String {
        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = translateKnownFailureMessage(rawMessage)
        if translated != rawMessage { return translated }
        return "No se pudo iniciar el servicio de enlace: \(rawMessage)"
    }

    /// Traduce mensajes de fallo conocidos (hoy, en inglés desde el proceso Java del
    /// helper) a texto en español. Los mensajes sin traducción conocida se devuelven tal
    /// cual, sin añadir un prefijo genérico: a diferencia de `friendlyLaunchMessage`, este
    /// texto puede llegar en cualquier momento del ciclo de vida del helper, no solo al
    /// arrancarlo, así que "No se pudo iniciar..." no siempre encajaría.
    private func translateKnownFailureMessage(_ rawMessage: String) -> String {
        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("address already in use") {
            return "El puerto 8765 ya está en uso por otro servicio de enlace. Cierra instancias antiguas de MiGestor e inténtalo de nuevo."
        }
        return trimmed
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

            guard snapshot.payload != lastPublishedPairingPayload else { return }
            lastPublishedPairingPayload = snapshot.payload
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
            // Notify KmpBridge that a valid LAN endpoint is now available.
            // KmpBridge subscribes to this notification to start the SSE listener
            // and the periodic sync loop, ensuring no requests go out to 127.0.0.1
            // before the helper process is ready.
            NotificationCenter.default.post(
                name: .syncHelperBecameReady,
                object: nil,
                userInfo: ["host": snapshot.host, "port": snapshot.port]
            )

        case let .networkError(message):
            lastLifecycleState = .networkError
            lastFailureMessage = message
            print("[Pairing] invalid LAN host: \(message)")
            updateState(.networkError(message: message), message: message)

        case let .connected(deviceName):
            promoteToConnected(deviceName: deviceName)

        case let .failed(message):
            let friendlyMessage = translateKnownFailureMessage(message)
            lastLifecycleState = .failed
            lastFailureMessage = friendlyMessage
            print("[Pairing] failed: \(message)")
            updateState(.failed(message: friendlyMessage), message: friendlyMessage)
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

private struct RunningSnapshot {
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
    /// Posted when the helper process publishes a valid LAN IP. UserInfo: ["host": String, "port": Int].
    static let syncHelperBecameReady = Notification.Name("syncHelperBecameReady")
    /// Posted when the helper process has stopped (cleanly or due to error).
    static let syncHelperStopped = Notification.Name("syncHelperStopped")
}
