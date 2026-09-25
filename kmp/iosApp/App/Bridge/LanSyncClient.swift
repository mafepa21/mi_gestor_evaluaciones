import Foundation
import Security
import CryptoKit

final class LanSyncClient {
    static func normalizeHost(_ rawHost: String) -> String {
        var normalized = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "" }

        if let components = URLComponents(string: normalized), let host = components.host, !host.isEmpty {
            normalized = host
        } else {
            normalized = normalized
                .replacingOccurrences(of: "https://", with: "", options: [.caseInsensitive, .anchored])
                .replacingOccurrences(of: "http://", with: "", options: [.caseInsensitive, .anchored])
            if let slashIndex = normalized.firstIndex(of: "/") {
                normalized = String(normalized[..<slashIndex])
            }
            if let queryIndex = normalized.firstIndex(of: "?") {
                normalized = String(normalized[..<queryIndex])
            }
        }

        if normalized.hasPrefix("["),
           normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }

        if let colonIndex = normalized.lastIndex(of: ":"), !normalized.contains("::") {
            let suffix = normalized[normalized.index(after: colonIndex)...]
            if suffix.allSatisfy(\.isNumber) {
                normalized = String(normalized[..<colonIndex])
            }
        }

        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    func handshake(
        host: String,
        pin: String,
        deviceId: String,
        pinnedFingerprint: String?
    ) async throws -> LanHandshakeResult {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/handshake")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(
            LanHandshakeRequest(pin: pin, deviceId: deviceId)
        )
        print("🔗 LAN Sync: Intentando handshake con \(host) (deviceId: \(deviceId))")
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "handshake",
            host: host
        )
        
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -200, userInfo: [NSLocalizedDescriptionKey: "Respuesta no es HTTP"])
        }
        
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            print("❌ LAN Sync Handshake Fallido: HTTP \(http.statusCode) - \(body)")
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Handshake LAN fallido (\(http.statusCode)): \(body)"
            ])
        }
        let decoded = try JSONDecoder().decode(LanHandshakeResponse.self, from: data)
        let fingerprint = decoded.certificateFingerprint ?? pinnedFingerprint ?? ""
        return LanHandshakeResult(
            token: decoded.token,
            serverId: decoded.serverId ?? "",
            certificateFingerprint: fingerprint
        )
    }

    func pull(host: String, token: String, sinceEpochMs: Int64, deviceId: String, pinnedFingerprint: String?) async throws -> LanPullResult {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/pull", queryItems: [
            URLQueryItem(name: "since", value: "\(sinceEpochMs)"),
            URLQueryItem(name: "deviceId", value: deviceId)
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "pull",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -201, userInfo: [NSLocalizedDescriptionKey: "Pull LAN fallido: respuesta no HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Pull LAN fallido (\(http.statusCode)): \(body)"
            ])
        }
        let result = try JSONDecoder().decode(LanPullResponse.self, from: data)
        return LanPullResult(serverEpochMs: result.serverEpochMs, changes: result.changes)
    }

    func push(
        host: String,
        token: String,
        deviceId: String,
        changes: [LanSyncChange],
        lastKnownServerEpochMs: Int64,
        pinnedFingerprint: String?
    ) async throws -> LanPushResult {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/push")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            LanPushRequest(
                clientDeviceId: deviceId,
                lastKnownServerEpochMs: lastKnownServerEpochMs,
                changes: changes
            )
        )
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "push",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -202, userInfo: [NSLocalizedDescriptionKey: "Push LAN fallido: respuesta no HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Push LAN fallido (\(http.statusCode)): \(body)"
            ])
        }
        let decoded = try JSONDecoder().decode(LanPushResponse.self, from: data)
        return LanPushResult(
            applied: decoded.applied,
            ignored: decoded.ignored ?? 0,
            failed: decoded.failed ?? 0,
            serverEpochMs: decoded.serverEpochMs,
            desktopAuthoritative: decoded.desktopAuthoritative ?? false
        )
    }

    func notifyLocalChanges(
        host: String,
        changes: [LanSyncChange],
        pinnedFingerprint: String?
    ) async throws {
        guard !changes.isEmpty else { return }
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost.isEmpty ? "127.0.0.1" : normalizedHost, path: "/sync/local-changes")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try JSONEncoder().encode(changes)

        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "local-changes",
            host: host
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: -215, userInfo: [
                NSLocalizedDescriptionKey: "Notificación local LAN fallida: \(body)"
            ])
        }
    }

    func unpair(host: String, token: String, pinnedFingerprint: String?) async throws -> Bool {
        let normalizedHost = Self.normalizeHost(host)
        let url = try buildURL(host: normalizedHost, path: "/sync/unpair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (_, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "unpair",
            host: host
        )
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    func uploadDocument(host: String, token: String, sha256: String, fileURL: URL, pinnedFingerprint: String?) async throws {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/documents/\(sha256)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.openxmlformats-officedocument.wordprocessingml.document", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: fileURL)
        request.timeoutInterval = 45
        let (_, response) = try await executeDataTask(request: request, pinnedFingerprint: pinnedFingerprint, operation: "document-upload", host: host)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Sync", code: -211, userInfo: [NSLocalizedDescriptionKey: "No se pudo sincronizar el documento de la situación."])
        }
    }

    func downloadDocument(host: String, token: String, sha256: String, pinnedFingerprint: String?) async throws -> Data {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/documents/\(sha256)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        let (data, response) = try await executeDataTask(request: request, pinnedFingerprint: pinnedFingerprint, operation: "document-download", host: host)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Sync", code: -212, userInfo: [NSLocalizedDescriptionKey: "Documento no disponible en el dispositivo emparejado."])
        }
        return data
    }

    func fingerprint(
        host: String,
        token: String,
        pinnedFingerprint: String?
    ) async throws -> LanDatasetFingerprint {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/fingerprint")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "fingerprint",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -200, userInfo: [NSLocalizedDescriptionKey: "Respuesta no es HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Error al obtener huella remota (\(http.statusCode)): \(body)"
            ])
        }
        return try JSONDecoder().decode(LanDatasetFingerprint.self, from: data)
    }

    func downloadSnapshot(
        host: String,
        token: String,
        destinationURL: URL,
        pinnedFingerprint: String?
    ) async throws -> (schemaVersion: Int64, digest: String) {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/snapshot/db")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "downloadSnapshot",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -200, userInfo: [NSLocalizedDescriptionKey: "Respuesta no es HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Error al descargar snapshot (\(http.statusCode)): \(body)"
            ])
        }
        let schemaVersionStr = http.value(forHTTPHeaderField: "X-Schema-Version") ?? "0"
        let schemaVersion = Int64(schemaVersionStr) ?? 0
        let digest = http.value(forHTTPHeaderField: "X-Dataset-Digest") ?? ""
        try data.write(to: destinationURL, options: .atomic)
        return (schemaVersion, digest)
    }

    func uploadSnapshot(
        host: String,
        token: String,
        fileURL: URL,
        schemaVersion: Int64,
        digest: String,
        pinnedFingerprint: String?
    ) async throws {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/snapshot/db")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-sqlite3", forHTTPHeaderField: "Content-Type")
        request.setValue("\(schemaVersion)", forHTTPHeaderField: "X-Schema-Version")
        request.setValue(digest, forHTTPHeaderField: "X-Dataset-Digest")
        request.timeoutInterval = 90
        request.httpBody = try Data(contentsOf: fileURL)
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "uploadSnapshot",
            host: host
        )
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Sync", code: -200, userInfo: [NSLocalizedDescriptionKey: "Respuesta no es HTTP"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(sin cuerpo)"
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Error al enviar snapshot al servidor (\(http.statusCode)): \(body)"
            ])
        }
    }

    func fetchSnapshotStatus(
        host: String,
        token: String,
        pinnedFingerprint: String?
    ) async throws -> String {
        let url = try buildURL(host: Self.normalizeHost(host), path: "/sync/snapshot/status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await executeDataTask(
            request: request,
            pinnedFingerprint: pinnedFingerprint,
            operation: "snapshotStatus",
            host: host
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return "unknown"
        }
        struct StatusResp: Codable { let status: String }
        let resp = try? JSONDecoder().decode(StatusResp.self, from: data)
        return resp?.status ?? "unknown"
    }

    private func makeSession(pinnedFingerprint: String?) -> URLSession {
        let delegate = PinnedTLSDelegate(pinnedFingerprint: pinnedFingerprint)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    private func buildURL(
        host: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard !host.isEmpty else {
            throw NSError(
                domain: "Sync",
                code: -206,
                userInfo: [NSLocalizedDescriptionKey: "El host de sincronización está vacío o no es válido."]
            )
        }

        var components = URLComponents()
        components.scheme = "https"
        #if os(macOS)
        components.host = "127.0.0.1"
        #else
        components.host = host
        #endif
        components.port = 8765
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw NSError(
                domain: "Sync",
                code: -207,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo construir la URL de sincronización para '\(host)'."]
            )
        }
        return url
    }

    private func executeDataTask(
        request: URLRequest,
        pinnedFingerprint: String?,
        operation: String,
        host: String
    ) async throws -> (Data, URLResponse) {
        let session = makeSession(pinnedFingerprint: pinnedFingerprint)
        do {
            let result = try await session.data(for: request)
            session.finishTasksAndInvalidate()
            return result
        } catch let urlError as URLError {
            session.invalidateAndCancel()
            if urlError.code == .timedOut {
                throw NSError(
                    domain: "Sync",
                    code: -210,
                    userInfo: [NSLocalizedDescriptionKey: "La petición de \(operation) a \(host) superó el tiempo límite. Reintenta con la app desktop abierta y en la misma LAN."]
                )
            }
            if urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                throw NSError(
                    domain: "Sync",
                    code: -212,
                    userInfo: [NSLocalizedDescriptionKey: "No se pudo conectar con \(host):8765 para \(operation). Comprueba que el desktop siga abierto y que ese host sea el correcto."]
                )
            }
            if urlError.code == .cannotFindHost || urlError.code == .dnsLookupFailed {
                throw NSError(
                    domain: "Sync",
                    code: -213,
                    userInfo: [NSLocalizedDescriptionKey: "No se pudo resolver el host '\(host)'. Usa el nombre Bonjour o la IP actual del desktop."]
                )
            }
            if urlError.code == .serverCertificateUntrusted ||
                urlError.code == .serverCertificateHasBadDate ||
                urlError.code == .serverCertificateHasUnknownRoot ||
                urlError.code == .secureConnectionFailed {
                throw NSError(
                    domain: "Sync",
                    code: -214,
                    userInfo: [NSLocalizedDescriptionKey: "El certificado TLS del desktop no coincide con el esperado. Conviene desvincular y emparejar de nuevo."]
                )
            }
            throw NSError(
                domain: "Sync",
                code: -211,
                userInfo: [NSLocalizedDescriptionKey: "Error de red en \(operation) con \(host): \(urlError.localizedDescription)"]
            )
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }
}

final class IosKeychainStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func loadString(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveString(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class PinnedTLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pinnedFingerprint: String?

    init(pinnedFingerprint: String?) {
        self.pinnedFingerprint = pinnedFingerprint?.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificateChain.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let pinnedFingerprint, !pinnedFingerprint.isEmpty {
            let certData = SecCertificateCopyData(certificate) as Data
            let computed = SHA256.hash(data: certData).map { String(format: "%02x", $0) }.joined()
            guard computed == pinnedFingerprint else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
