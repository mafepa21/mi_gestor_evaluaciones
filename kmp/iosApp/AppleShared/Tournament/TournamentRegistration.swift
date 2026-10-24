import Foundation

/// Inscripción a un torneo con el formulario de entregas web.
///
/// El docente publica un formulario de tres preguntas para el curso del torneo
/// (¿participas?, ¿con quién?, nombre del equipo), lo reparte por correo y, cuando
/// llegan los ficheros `.mgsub`, los importa aquí. De las respuestas salen las parejas.
///
/// Todo vive dentro del propio torneo (`config_json`), no en las tablas de entregas
/// web: esas tablas cuelgan de una columna del Cuaderno, y una inscripción no es una
/// nota. Así un torneo y su formulario van juntos y dos torneos nunca comparten inscritos.
///
/// Lo único que no viaja con el torneo es la clave privada, que se queda en el
/// llavero del dispositivo que publicó (`WebSubmissionKeychain`).
struct TournamentRegistration: Equatable, Codable, Sendable {
    var formInstanceId: String
    var privateKeyRef: String
    var expiresAtEpochMs: Int64
    /// Manifiesto firmado tal cual se publicó. Hace falta para validar las respuestas.
    var manifestJSON: String
    /// alias del enlace -> id del alumno.
    var studentIdByAlias: [String: String]
    /// Enlace personal de cada alumno, para volver a enviarlo.
    var linkByStudentId: [String: String]
    /// `webItemId` aleatorio del manifiesto -> una de las tres claves de abajo.
    var itemIdByWebItemId: [String: String]
    /// Texto de la opción de pareja -> id del alumno. Es la lista que ve el alumnado.
    var studentIdByPartnerOption: [String: String]
    /// Respuestas ya importadas, por alumno. Importar otra vez sustituye la anterior.
    var entries: [String: TournamentRegistrationEntry] = [:]
    /// `submissionId` ya vistos, para no importar dos veces el mismo fichero.
    var importedSubmissionIds: [String] = []
    /// Buzón donde la web deposita las respuestas, si se publicó con él. La clave de
    /// lectura no va aquí: está en el llavero (`WebSubmissionInbox.readTokenName`).
    var inboxURL: String?

    static let yesOption = "Sí, me apunto"
    static let noOption = "No"
    static let participateItemId = "participa"
    static let partnerItemId = "pareja"
    static let teamNameItemId = "equipo"

    static let noPartnerOption = "Sin pareja, que me asigne la app"
}

/// Lo que respondió un alumno.
struct TournamentRegistrationEntry: Equatable, Codable, Sendable {
    var studentId: String
    var participates: Bool
    /// `nil` si no eligió pareja.
    var partnerStudentId: String?
    var teamName: String?
}

// MARK: - Nombres de la lista

enum TournamentRegistrationNames {
    /// Nombre y primer apellido. Si dos coinciden, se añade la inicial del segundo
    /// apellido solo a esos. Si aún coinciden, un número al final.
    ///
    /// Se publica lo mínimo para que el alumnado se reconozca: la lista viaja en el
    /// formulario y la ve cualquiera que tenga un enlace del curso.
    static func optionLabels(
        for students: [(id: String, firstName: String, lastName: String)]
    ) -> [String: String] {
        func clean(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        func short(_ student: (id: String, firstName: String, lastName: String)) -> String {
            ([student.firstName.trimmingCharacters(in: .whitespaces)] + clean(student.lastName).prefix(1))
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        var labels: [String: String] = [:]
        let byShort = Dictionary(grouping: students, by: short)
        for (base, group) in byShort {
            guard group.count > 1 else {
                labels[group[0].id] = base
                continue
            }
            for student in group {
                let rest = clean(student.lastName).dropFirst()
                let initial = rest.first?.first.map { " \($0)." } ?? ""
                labels[student.id] = base + initial
            }
        }

        // Último recurso: dos alumnos con el mismo nombre completo.
        let repeated = Dictionary(grouping: labels, by: \.value).filter { $0.value.count > 1 }
        for (label, pairs) in repeated {
            for (index, pair) in pairs.sorted(by: { $0.key < $1.key }).enumerated() {
                labels[pair.key] = "\(label) (\(index + 1))"
            }
        }
        return labels
    }
}

// MARK: - Parejas

/// Resultado de emparejar. No escribe nada: es lo que se enseña en la vista previa.
struct TournamentPairingResult: Equatable, Sendable {
    struct Pair: Equatable, Sendable, Identifiable {
        var first: String
        var second: String
        var teamName: String?
        /// `true` si se eligieron el uno al otro; `false` si los juntó la app.
        var isMutual: Bool
        var id: String { first + "|" + second }
    }

    var pairs: [Pair]
    /// Inscrito sin pareja porque el número es impar.
    var leftOver: String?
    /// Del curso, pero no ha respondido.
    var notResponded: [String]
    /// Respondió que no participa.
    var declined: [String]
}

enum TournamentPairing {
    /// Reglas:
    ///  - Si A elige a B y B elige a A, pareja confirmada.
    ///  - Cualquier otro caso (B no responde, no participa o eligió a otro): A queda suelto.
    ///  - Los sueltos se emparejan al azar entre ellos.
    ///  - Con número impar, uno queda en `leftOver` para que decida el docente.
    static func pair<R: RandomNumberGenerator>(
        entries: [TournamentRegistrationEntry],
        rosterIds: [String],
        using generator: inout R
    ) -> TournamentPairingResult {
        let roster = Set(rosterIds)
        // Solo cuenta el alumnado del curso del torneo.
        let valid = entries.filter { roster.contains($0.studentId) }
        let byId = Dictionary(valid.map { ($0.studentId, $0) }, uniquingKeysWith: { _, last in last })
        let participants = valid.filter(\.participates).map(\.studentId).sorted()
        let participantSet = Set(participants)

        var pairs: [TournamentPairingResult.Pair] = []
        var paired = Set<String>()
        for id in participants where !paired.contains(id) {
            guard let partner = byId[id]?.partnerStudentId,
                  partner != id,
                  participantSet.contains(partner),
                  !paired.contains(partner),
                  byId[partner]?.partnerStudentId == id else { continue }
            paired.formUnion([id, partner])
            let name = [byId[id]?.teamName, byId[partner]?.teamName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            pairs.append(.init(first: id, second: partner, teamName: name, isMutual: true))
        }

        var loose = participants.filter { !paired.contains($0) }
        loose.shuffle(using: &generator)
        var leftOver: String?
        if loose.count % 2 == 1 { leftOver = loose.removeLast() }
        for index in stride(from: 0, to: loose.count, by: 2) {
            pairs.append(.init(first: loose[index], second: loose[index + 1], teamName: nil, isMutual: false))
        }

        let responded = Set(valid.map(\.studentId))
        return TournamentPairingResult(
            pairs: pairs,
            leftOver: leftOver,
            notResponded: rosterIds.filter { !responded.contains($0) },
            declined: valid.filter { !$0.participates }.map(\.studentId).sorted()
        )
    }

    static func pair(entries: [TournamentRegistrationEntry], rosterIds: [String]) -> TournamentPairingResult {
        var generator = SystemRandomNumberGenerator()
        return pair(entries: entries, rosterIds: rosterIds, using: &generator)
    }

    /// Equipos para el torneo. Sin nombre propio: "Ana y Bruno". Nombres repetidos: "… 2".
    static func teams(
        from pairs: [TournamentPairingResult.Pair],
        names: [String: String]
    ) -> [TournamentPlanTeam] {
        var used = Set<String>()
        return pairs.map { pair in
            let first = names[pair.first] ?? "Alumno"
            let second = names[pair.second] ?? "Alumno"
            let base = pair.teamName ?? "\(first) y \(second)"
            var name = base
            var counter = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(counter)"
                counter += 1
            }
            used.insert(name.lowercased())
            return TournamentPlanTeam(name: name, studentIDs: [pair.first, pair.second].sorted())
        }
    }
}

// MARK: - Respuestas importadas

extension TournamentRegistration {
    /// Traduce las respuestas de una entrega ya validada. `nil` si no es de este formulario.
    func entry(studentId: Int64, answers: [WebResolvedAnswer]) -> TournamentRegistrationEntry? {
        let id = String(studentId)
        guard studentIdByAlias.values.contains(id) else { return nil }
        func text(_ itemId: String) -> String? {
            answers.first { $0.itemId == itemId }?.textValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let participates = text(Self.participateItemId) == Self.yesOption
        // Elegirse a sí mismo cuenta como "sin pareja": la lista es la misma para todo el curso.
        let partner = text(Self.partnerItemId).flatMap { studentIdByPartnerOption[$0] }.flatMap { $0 == id ? nil : $0 }
        let teamName = text(Self.teamNameItemId).flatMap { $0.isEmpty ? nil : String($0.prefix(40)) }
        return TournamentRegistrationEntry(
            studentId: id,
            participates: participates,
            partnerStudentId: partner,
            teamName: teamName
        )
    }

    /// Lo que necesita `WebSubmissionImportService` para examinar las entregas.
    func snapshot(classId: Int64, title: String, studentNames: [Int64: String]) -> WebSubmissionSnapshot {
        WebSubmissionSnapshot(
            formInstanceId: formInstanceId,
            classId: classId,
            columnId: "",
            privateKeyRef: privateKeyRef,
            revoked: false,
            expiresAtEpochMs: expiresAtEpochMs,
            title: title,
            studentIdByAlias: studentIdByAlias.compactMapValues { Int64($0) },
            itemIdByWebItemId: itemIdByWebItemId,
            studentNames: studentNames,
            importedAtBySubmissionId: Dictionary(
                importedSubmissionIds.map { ($0, Int64(0)) },
                uniquingKeysWith: { first, _ in first }
            ),
            roster: []
        )
    }

    var manifest: WebFormManifest? {
        try? JSONDecoder().decode(WebFormManifest.self, from: Data(manifestJSON.utf8))
    }
}

// MARK: - Publicar

extension TournamentRegistration {
    struct Published {
        var registration: TournamentRegistration
        /// Carpeta con el manifiesto, por si hay que subirlo a la web a mano.
        var manifestPath: String
        var isSelfContained: Bool
    }

    /// Crea el formulario para el curso del torneo y guarda la clave en el llavero.
    ///
    /// Si este dispositivo tiene activado el buzón (`WebSubmissionInbox.accountKey`), el
    /// formulario se registra en él y la web envía las respuestas directas. Si el registro
    /// falla, no se publica nada: un enlace que apunta a un buzón que no lo conoce dejaría
    /// al alumnado con un error al entregar.
    static func publish(
        tournamentName: String,
        students: [(id: Int64, firstName: String, lastName: String)],
        baseURL: String,
        deliveryEmail: String?,
        expiresAt: Date,
        session: URLSession = .shared
    ) async throws -> Published {
        let labels = TournamentRegistrationNames.optionLabels(
            for: students.map { (id: String($0.id), firstName: $0.firstName, lastName: $0.lastName) }
        )
        let options = labels.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let inbox: (url: String, accountKey: String, depositToken: String, readToken: String)? =
            WebSubmissionInbox.accountKey.map {
                (WebSubmissionInbox.url(baseURL: baseURL), $0, WebSubmissionInbox.randomToken(), WebSubmissionInbox.randomToken())
            }

        let form = try WebSubmissionPublisher.publish(
            title: "Inscripción: \(tournamentName)",
            subtitle: "Si vas con pareja, elegidla los dos. Si no, la app te asigna una.",
            locale: "es",
            sections: [],
            items: [
                .init(itemId: participateItemId, title: "¿Quieres participar?", type: .choice, required: true,
                      options: [yesOption, noOption], helpText: nil, scaleLabels: nil, sectionId: nil),
                .init(itemId: partnerItemId, title: "¿Con quién quieres jugar?", type: .choice, required: true,
                      options: options + [noPartnerOption],
                      helpText: "Tu pareja tiene que elegirte a ti también.", scaleLabels: nil, sectionId: nil),
                .init(itemId: teamNameItemId, title: "Nombre del equipo (opcional)", type: .text, required: false,
                      options: [], helpText: nil, scaleLabels: nil, sectionId: nil),
            ],
            students: students.map {
                .init(id: $0.id, name: "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces))
            },
            baseURL: baseURL,
            deliveryEmail: deliveryEmail,
            expiresAtEpochMs: Int64(expiresAt.timeIntervalSince1970 * 1000),
            inboxPath: inbox == nil ? nil : WebSubmissionInbox.path,
            depositToken: inbox?.depositToken
        )

        if let inbox {
            try await WebSubmissionInboxClient(url: inbox.url, session: session).register(
                formInstanceId: form.formInstanceId,
                accountKey: inbox.accountKey,
                depositToken: inbox.depositToken,
                readToken: inbox.readToken,
                expiresAt: expiresAt,
                aliases: form.aliases.map(\.alias)
            )
            guard WebSubmissionInbox.saveToken(
                inbox.readToken,
                name: WebSubmissionInbox.readTokenName(formInstanceId: form.formInstanceId)
            ) else {
                throw NSError(
                    domain: "TournamentRegistration",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "No se pudo guardar la clave del buzón en el llavero."]
                )
            }
        }

        let reference = WebSubmissionKeychain.reference(for: form.formInstanceId)
        guard WebSubmissionKeychain.save(privateKey: form.recipientPrivateKey, reference: reference) else {
            throw NSError(
                domain: "TournamentRegistration",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo guardar la clave en el llavero. No se ha publicado nada."]
            )
        }

        // El manifiesto se deja en Documentos/EntregasWeb, como en el resto de entregas,
        // por si los enlaces no lo llevan dentro y hay que subirlo a la web.
        let folder = WebSubmissionPrivateLinksStore.folderURL(for: form.formInstanceId)
        var manifestPath = ""
        if let folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(form.formInstanceId).json")
            try Data(form.manifestJSON.utf8).write(to: file)
            manifestPath = file.path
        }

        var optionToStudent: [String: String] = [:]
        for (studentId, label) in labels { optionToStudent[label] = studentId }

        var registration = TournamentRegistration(
            formInstanceId: form.formInstanceId,
            privateKeyRef: reference,
            expiresAtEpochMs: form.expiresAtEpochMs,
            manifestJSON: form.manifestJSON,
            studentIdByAlias: Dictionary(
                form.aliases.map { ($0.alias, String($0.studentId)) },
                uniquingKeysWith: { first, _ in first }
            ),
            linkByStudentId: Dictionary(
                form.links.map { (String($0.studentId), $0.url) },
                uniquingKeysWith: { first, _ in first }
            ),
            itemIdByWebItemId: Dictionary(
                form.itemMap.map { ($0.webItemId, $0.itemId) },
                uniquingKeysWith: { first, _ in first }
            ),
            studentIdByPartnerOption: optionToStudent
        )
        registration.inboxURL = inbox?.url
        return Published(registration: registration, manifestPath: manifestPath, isSelfContained: form.isSelfContained)
    }

    /// Mete en la inscripción las entregas ya validadas. Devuelve cuántas son nuevas.
    @discardableResult
    mutating func absorb(_ drafts: [WebSubmissionDraft]) -> Int {
        var count = 0
        for draft in drafts where draft.formInstanceId == formInstanceId {
            guard let studentId = draft.studentId,
                  let entry = entry(studentId: studentId, answers: draft.answers) else { continue }
            entries[entry.studentId] = entry
            if !importedSubmissionIds.contains(draft.submissionId) {
                importedSubmissionIds.append(draft.submissionId)
            }
            count += 1
        }
        return count
    }
}
