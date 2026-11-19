import Foundation

/// Lo que el servidor dice de un portal (acción `estado`, contrato sección 2).
enum WebPortalServerState: Equatable {
    enum Invitacion: Equatable { case pendiente, caducada, ninguna }

    /// Hay cuenta, y la invitación nueva está sin canjear, caducada o no hay.
    case cuenta(invitacion: Invitacion)
    case invitacionPendiente
    case invitacionCaducada
    case ninguna
}

/// Resultado de publicar un tablón.
struct WebPortalPublishResult: Equatable {
    let portalId: String
    let ok: Bool
    /// `desconocido` o `version`.
    let reason: String?
}

/// Un alumno invitado: el código solo existe en memoria, nunca se guarda.
struct WebPortalInvitation: Equatable {
    let studentId: Int64
    let portalId: String
    /// 10 caracteres, sin guion.
    let code: String
    let expires: Date?
    /// La invitación sustituye a una anterior: se rotó `K_tablon`.
    let wasReinvite: Bool
}

/// Cliente de `buzon/portal.php`. Las acciones del docente llevan la misma clave de
/// cuenta que el buzón (`WebSubmissionInbox.accountKey`). `URLSession` inyectable.
struct WebPortalClient {
    let url: String
    var session: URLSession = .shared

    static let path = "/buzon/portal.php"
    /// Tope del servidor por llamada de invitar / estado.
    static let maxPerCall = 500

    static func url(baseURL: String) -> String {
        (baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL) + path
    }

    /// Enlace de alta: el código va tras `#`, nunca en la ruta ni en una petición.
    static func inviteLink(baseURL: String, code: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return "\(base)/#portal/alta=\(code)"
    }

    struct Invite {
        let portalId: String
        let inviteIdHash: String
        let pruebaHash: String
        let sobreAlta: WebPortalCrypto.Envelope
    }

    struct Board {
        let portalId: String
        let version: Int64
        let sobre: WebPortalCrypto.Envelope
    }

    /// Devuelve cuándo caducan las invitaciones (7 días).
    func invite(_ invites: [Invite], accountKey: String) async throws -> Date? {
        guard invites.count <= Self.maxPerCall else { throw WebSubmissionInbox.InboxError.server(400) }
        let body: [String: Any] = [
            "invitaciones": invites.map {
                [
                    "portalId": $0.portalId,
                    "inviteIdHash": $0.inviteIdHash,
                    "pruebaHash": $0.pruebaHash,
                    "sobreAlta": $0.sobreAlta.jsonObject,
                ] as [String: Any]
            },
        ]
        let data = try await post(action: "invitar", accountKey: accountKey, body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Self.date(from: json["caduca"])
    }

    func publish(_ boards: [Board], accountKey: String) async throws -> [WebPortalPublishResult] {
        guard !boards.isEmpty else { return [] }
        let body: [String: Any] = [
            "tablones": boards.map {
                ["portalId": $0.portalId, "version": $0.version, "sobre": $0.sobre.jsonObject] as [String: Any]
            },
        ]
        let data = try await post(action: "publicar", accountKey: accountKey, body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["resultados"] as? [[String: Any]] else { return [] }
        return results.compactMap {
            guard let id = $0["portalId"] as? String else { return nil }
            return WebPortalPublishResult(portalId: id, ok: ($0["ok"] as? Bool) ?? false, reason: $0["motivo"] as? String)
        }
    }

    /// Todos los portalId de una vez, no por grupo.
    func state(portalIds: [String], accountKey: String) async throws -> [String: WebPortalServerState] {
        var result: [String: WebPortalServerState] = [:]
        for chunk in stride(from: 0, to: portalIds.count, by: Self.maxPerCall).map({
            Array(portalIds[$0..<min($0 + Self.maxPerCall, portalIds.count)])
        }) {
            let data = try await post(action: "estado", accountKey: accountKey, body: ["portalIds": chunk])
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let states = json["estados"] as? [String: [String: Any]] else { continue }
            for (id, raw) in states {
                let hasAccount = (raw["cuenta"] as? Bool) ?? false
                let invitation = raw["invitacion"] as? String ?? "ninguna"
                switch (hasAccount, invitation) {
                case (true, _):
                    result[id] = .cuenta(invitacion: invitation == "pendiente" ? .pendiente : invitation == "caducada" ? .caducada : .ninguna)
                case (false, "pendiente"): result[id] = .invitacionPendiente
                case (false, "caducada"): result[id] = .invitacionCaducada
                default: result[id] = .ninguna
                }
            }
        }
        return result
    }

    @discardableResult
    func close(portalIds: [String], accountKey: String) async throws -> Int {
        let data = try await post(action: "cerrar", accountKey: accountKey, body: ["portalIds": portalIds])
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["cerradas"] as? Int) ?? 0
    }

    // MARK: - HTTP

    /// El servidor puede contar segundos o milisegundos, o dar una fecha ISO.
    static func date(from value: Any?) -> Date? {
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
        }
        if let text = value as? String { return ISO8601DateFormatter().date(from: text) }
        return nil
    }

    private func post(action: String, accountKey: String, body: [String: Any]) async throws -> Data {
        guard let endpoint = URL(string: "\(url)?accion=\(action)"),
              endpoint.scheme?.lowercased() == "https" else { throw WebSubmissionInbox.InboxError.network }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accountKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebSubmissionInbox.InboxError.network
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw WebSubmissionInbox.InboxError.unauthorized }
        guard (200..<300).contains(code) else { throw WebSubmissionInbox.InboxError.server(code) }
        return data
    }
}

// MARK: - Invitar y cerrar

/// Orquesta invitar y cerrar: claves, servidor y almacén local, en ese orden.
///
/// Si el servidor falla no se toca nada en local ni se devuelve ningún código, así
/// que no puede salir un correo con un código que el servidor no conoce.
enum WebPortalInviter {
    enum InviteError: LocalizedError {
        case keychain
        var errorDescription: String? { "No se pudo guardar la llave del portal en el llavero." }
    }

    /// Crea (o renueva) la invitación de cada alumno. Reinvitar conserva el
    /// `portalId` y rota `K_tablon`; quien llama debe republicar los tablones.
    static func invite(
        studentIds: [Int64],
        storeURL: URL,
        keychainService: String = WebPortalStore.defaultKeychainService,
        client: WebPortalClient,
        accountKey: String,
        iterations: Int = WebPortalCrypto.pbkdf2Iterations,
        now: Date = Date()
    ) async throws -> [WebPortalInvitation] {
        let store = WebPortalStore(fileURL: storeURL, keychainService: keychainService)

        struct Prepared {
            let invitation: WebPortalInvitation
            let invite: WebPortalClient.Invite
            let tablonKey: Data
            /// Tiene cuenta activa: la llave nueva espera a que canjee el código.
            let keepsPending: Bool
        }
        var prepared: [Prepared] = []
        for studentId in studentIds {
            let existing = store[studentId]
            let portalId = try existing?.portalId ?? WebPortalCrypto.newPortalId()
            let tablonKey = try WebPortalCrypto.newTablonKey()
            let code = try WebPortalCrypto.generateCode()
            let keys = try WebPortalCrypto.deriveInvite(code: code, iterations: iterations)
            let sobre = try WebPortalCrypto.seal(tablonKey, key: keys.kAlta, context: .alta(portalId: portalId))
            prepared.append(Prepared(
                invitation: WebPortalInvitation(studentId: studentId, portalId: portalId, code: code, expires: nil, wasReinvite: existing != nil),
                invite: WebPortalClient.Invite(portalId: portalId, inviteIdHash: keys.inviteIdHash, pruebaHash: keys.pruebaHash, sobreAlta: sobre),
                tablonKey: tablonKey,
                keepsPending: existing?.estadoConocido == WebPortalAccountStatus.activada.rawValue
            ))
        }

        // Llaves nuevas al llavero ANTES de llamar al servidor. Si falla, no se llama.
        var written: [String] = []
        for item in prepared {
            guard store.savePendingKey(item.tablonKey, portalId: item.invitation.portalId) else {
                for id in written { store.deletePendingKey(portalId: id) }
                throw InviteError.keychain
            }
            written.append(item.invitation.portalId)
        }

        let expires: Date?
        do {
            expires = try await client.invite(prepared.map(\.invite), accountKey: accountKey)
        } catch {
            for id in written { store.deletePendingKey(portalId: id) }
            throw error
        }

        // Sin cuenta activa se rota ya. Con cuenta activa la llave espera a que canjee.
        for item in prepared where !item.keepsPending {
            if !store.promotePendingKey(portalId: item.invitation.portalId) { throw InviteError.keychain }
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        try WebPortalStore.mutate(fileURL: storeURL, keychainService: keychainService) { store in
            for item in prepared {
                let previous = store[item.invitation.studentId]
                store.set(
                    WebPortalEntry(
                        portalId: item.invitation.portalId,
                        estadoConocido: item.keepsPending ? WebPortalAccountStatus.activada.rawValue : WebPortalAccountStatus.pendiente.rawValue,
                        invitadoEl: nowMs,
                        ultimaVersion: previous?.ultimaVersion
                    ),
                    for: item.invitation.studentId
                )
            }
        }
        return prepared.map {
            WebPortalInvitation(
                studentId: $0.invitation.studentId,
                portalId: $0.invitation.portalId,
                code: $0.invitation.code,
                expires: expires,
                wasReinvite: $0.invitation.wasReinvite
            )
        }
    }

    /// Resuelve las llaves pendientes con lo que dice el servidor: si canjeó (cuenta
    /// y sin invitación) la pendiente pasa a ser la llave; si caducó, se descarta.
    /// Devuelve los alumnos cuya llave cambió: hay que republicar su tablón.
    @discardableResult
    static func resolvePending(
        states: [String: WebPortalServerState],
        storeURL: URL,
        keychainService: String = WebPortalStore.defaultKeychainService
    ) -> [Int64] {
        let store = WebPortalStore(fileURL: storeURL, keychainService: keychainService)
        var promoted: [Int64] = []
        for (studentId, entry) in store.entries where store.pendingKey(portalId: entry.portalId) != nil {
            switch states[entry.portalId] {
            case .cuenta(invitacion: .ninguna)?:
                if store.promotePendingKey(portalId: entry.portalId) { promoted.append(studentId) }
            case .cuenta(invitacion: .caducada)?, .invitacionCaducada?, WebPortalServerState.ninguna?:
                store.deletePendingKey(portalId: entry.portalId)
            default: break
            }
        }
        return promoted
    }

    /// Cierra la cuenta: el servidor borra todo y la app descarta `K_tablon`.
    static func close(
        studentIds: [Int64],
        storeURL: URL,
        keychainService: String = WebPortalStore.defaultKeychainService,
        client: WebPortalClient,
        accountKey: String
    ) async throws {
        let store = WebPortalStore(fileURL: storeURL, keychainService: keychainService)
        let entries = studentIds.compactMap { id in store[id].map { (id, $0) } }
        guard !entries.isEmpty else { return }
        try await client.close(portalIds: entries.map { $0.1.portalId }, accountKey: accountKey)
        for (_, entry) in entries { store.deleteTablonKey(portalId: entry.portalId) }
        try WebPortalStore.mutate(fileURL: storeURL, keychainService: keychainService) { store in
            for (id, _) in entries { store.remove(studentId: id) }
        }
    }

    /// Guarda en local lo que dijo el servidor (para «Último dato» sin red).
    static func recordStates(
        _ states: [String: WebPortalServerState],
        storeURL: URL,
        keychainService: String = WebPortalStore.defaultKeychainService
    ) {
        _ = try? WebPortalStore.mutate(fileURL: storeURL, keychainService: keychainService) { store in
            for (studentId, entry) in store.entries {
                guard let state = states[entry.portalId] else { continue }
                var updated = entry
                updated.estadoConocido = WebPortalAccountStatus.from(server: state).rawValue
                store.set(updated, for: studentId)
            }
        }
    }
}
