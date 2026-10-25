import Foundation

// Pasaporte por paradas (`mode: "passport"` en el manifiesto).
//
// El alumnado rellena las paradas cuando quiere y envía por partes. Cada envío
// lleva TODO lo que tiene en su móvil, pero puede faltar algo (otro móvil, una
// parada borrada después de enviar). Por eso aquí se junta: una respuesta nueva
// sustituye a la anterior del mismo ítem y nunca se borra lo ya recibido.

/// Cómo se reparten en paradas los apartados de un instrumento.
///
/// El instrumento del Cuaderno no tiene secciones, así que la parada sale del
/// título: «Parada 1 · Mi mejor reto de hoy» va a la parada «Parada 1». Apartados
/// SEGUIDOS con el mismo prefijo forman una parada. Si algún apartado no lleva
/// prefijo, no se adivina nada: todo va en una sola parada.
enum WebPassportSections {
    struct Stop: Equatable {
        let sectionId: String
        let title: String
        /// Índices de los apartados de esta parada, en el orden del instrumento.
        let itemIndexes: [Int]
    }

    struct Split: Equatable {
        let stops: [Stop]
        /// Título de cada apartado sin el prefijo de parada, en el mismo orden.
        let itemTitles: [String]
    }

    static let separator = " · "

    static func split(titles: [String], fallbackTitle: String) -> Split {
        let partes = titles.map { titulo -> (prefijo: String, resto: String)? in
            guard let rango = titulo.range(of: separator) else { return nil }
            let prefijo = titulo[..<rango.lowerBound].trimmingCharacters(in: .whitespaces)
            let resto = titulo[rango.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !prefijo.isEmpty, !resto.isEmpty else { return nil }
            return (prefijo, resto)
        }
        guard !titles.isEmpty, partes.allSatisfy({ $0 != nil }) else {
            return Split(
                stops: titles.isEmpty ? [] : [Stop(sectionId: "p1", title: fallbackTitle, itemIndexes: Array(titles.indices))],
                itemTitles: titles
            )
        }

        var stops: [Stop] = []
        for (indice, parte) in partes.enumerated() {
            guard let parte else { continue }
            if let ultima = stops.last, ultima.title == parte.prefijo {
                stops[stops.count - 1] = Stop(
                    sectionId: ultima.sectionId,
                    title: ultima.title,
                    itemIndexes: ultima.itemIndexes + [indice]
                )
            } else {
                stops.append(Stop(sectionId: "p\(stops.count + 1)", title: parte.prefijo, itemIndexes: [indice]))
            }
        }
        return Split(stops: stops, itemTitles: partes.map { $0?.resto ?? "" })
    }
}

/// Pasaportes recibidos de un formulario, guardados en este Mac.
///
/// Vive junto a la hoja privada de enlaces (`EntregasWeb/<formulario>/`) y, como
/// ella y `WebPeerEvaluationStore`, no viaja por Sync LAN.
struct WebPassportStore {
    struct StoredAnswer: Codable, Equatable {
        let answer: WebResolvedAnswer
        let sectionId: String?
        let clientSubmittedAt: String
    }

    struct StudentRecord: Codable, Equatable {
        /// `itemId` -> última respuesta recibida.
        var answers: [String: StoredAnswer] = [:]
        /// Parada -> envío en el que cambió por última vez.
        var sectionChangedAt: [String: String] = [:]
        /// Parada -> cuándo la miró el docente en la ficha.
        var sectionSeenAt: [String: String] = [:]
        var lastSubmittedAt: String = ""
    }

    let fileURL: URL
    private(set) var students: [String: StudentRecord] = [:]

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: StudentRecord].self, from: data) {
            students = stored
        }
    }

    static func forForm(_ formInstanceId: String) -> WebPassportStore? {
        WebSubmissionPrivateLinksStore.folderURL(for: formInstanceId).map {
            WebPassportStore(fileURL: $0.appendingPathComponent("pasaporte.json"))
        }
    }

    func record(for studentId: Int64) -> StudentRecord? { students[String(studentId)] }

    /// Junta un envío. Cada respuesta sustituye a la guardada del mismo ítem salvo
    /// que la guardada sea de un envío posterior; lo que el envío no trae se queda.
    mutating func merge(
        studentId: Int64,
        clientSubmittedAt: String,
        answers: [WebResolvedAnswer],
        sectionIdByWebItemId: [String: String]
    ) {
        var registro = students[String(studentId)] ?? StudentRecord()
        for respuesta in answers {
            if let previa = registro.answers[respuesta.itemId], previa.clientSubmittedAt > clientSubmittedAt { continue }
            let seccion = sectionIdByWebItemId[respuesta.webItemId]
            let cambia = registro.answers[respuesta.itemId]?.answer != respuesta
            registro.answers[respuesta.itemId] = StoredAnswer(
                answer: respuesta,
                sectionId: seccion,
                clientSubmittedAt: clientSubmittedAt
            )
            if cambia, let seccion, (registro.sectionChangedAt[seccion] ?? "") < clientSubmittedAt {
                registro.sectionChangedAt[seccion] = clientSubmittedAt
            }
        }
        if registro.lastSubmittedAt < clientSubmittedAt { registro.lastSubmittedAt = clientSubmittedAt }
        students[String(studentId)] = registro
    }

    /// Todas las respuestas juntas de un alumno: es lo que va a la celda.
    func mergedAnswers(for studentId: Int64) -> [WebResolvedAnswer] {
        (record(for: studentId)?.answers.values.map(\.answer) ?? []).sorted { $0.itemId < $1.itemId }
    }

    /// El docente ha mirado las paradas de este alumno: dejan de salir como nuevas.
    /// Se guarda la misma marca del envío visto, no la hora del Mac: así un reloj
    /// adelantado en el móvil no deja una parada «nueva» para siempre.
    mutating func markSeen(studentId: Int64) {
        guard var registro = students[String(studentId)] else { return }
        registro.sectionSeenAt = registro.sectionChangedAt
        students[String(studentId)] = registro
    }

    func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(students).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

// MARK: - Lo que pinta la vista del docente

enum WebPassportStopStatus: Equatable {
    case empty
    case sent(at: String)
    /// Cambió después de la última vez que el docente miró la ficha.
    case updated(at: String)
}

struct WebPassportStopInfo: Identifiable, Equatable {
    var id: String { sectionId }
    let sectionId: String
    let title: String
}

struct WebPassportAnswerLine: Identifiable, Equatable {
    var id: String { itemId }
    let itemId: String
    let title: String
    let value: String
}

struct WebPassportStudentRow: Identifiable, Equatable {
    var id: Int64 { studentId }
    let studentId: Int64
    let name: String
    /// En el orden de `WebPassportProgress.stops`.
    let statuses: [WebPassportStopStatus]
    let lastSubmittedAt: String?
    /// Parada -> respuestas, para la ficha.
    let answersBySection: [String: [WebPassportAnswerLine]]
}

struct WebPassportProgress: Equatable {
    let formInstanceId: String
    let title: String
    let groupName: String
    let stops: [WebPassportStopInfo]
    let rows: [WebPassportStudentRow]

    func sentCount(stopIndex: Int) -> Int {
        rows.filter { $0.statuses.indices.contains(stopIndex) && $0.statuses[stopIndex] != .empty }.count
    }

    var startedCount: Int { rows.filter { $0.lastSubmittedAt != nil }.count }

    /// Arma la vista a partir del manifiesto publicado, el alumnado y lo recibido.
    static func build(
        formInstanceId: String,
        title: String,
        groupName: String,
        manifest: WebFormManifest,
        roster: [WebRosterEntry],
        store: WebPassportStore?
    ) -> WebPassportProgress {
        let stops = (manifest.sections ?? []).map { WebPassportStopInfo(sectionId: $0.sectionId, title: $0.title) }
        let ordenItems = Dictionary(uniqueKeysWithValues: manifest.items.enumerated().map { ($0.element.webItemId, $0.offset) })

        let rows = roster.map { alumno -> WebPassportStudentRow in
            let registro = store?.record(for: alumno.id)
            let statuses = stops.map { parada -> WebPassportStopStatus in
                guard let cambio = registro?.sectionChangedAt[parada.sectionId] else { return .empty }
                let vista = registro?.sectionSeenAt[parada.sectionId] ?? ""
                return vista < cambio ? .updated(at: cambio) : .sent(at: cambio)
            }
            var porSeccion: [String: [WebPassportAnswerLine]] = [:]
            for guardada in registro.map({ Array($0.answers.values) }) ?? [] {
                guard let seccion = guardada.sectionId else { continue }
                porSeccion[seccion, default: []].append(
                    WebPassportAnswerLine(
                        itemId: guardada.answer.itemId,
                        title: guardada.answer.title,
                        value: displayValue(guardada.answer)
                    )
                )
            }
            for (seccion, lineas) in porSeccion {
                porSeccion[seccion] = lineas.sorted {
                    (ordenItems[webItemId(of: $0, in: registro)] ?? 0) < (ordenItems[webItemId(of: $1, in: registro)] ?? 0)
                }
            }
            return WebPassportStudentRow(
                studentId: alumno.id,
                name: alumno.name,
                statuses: statuses,
                lastSubmittedAt: (registro?.lastSubmittedAt).flatMap { $0.isEmpty ? nil : $0 },
                answersBySection: porSeccion
            )
        }
        return WebPassportProgress(formInstanceId: formInstanceId, title: title, groupName: groupName, stops: stops, rows: rows)
    }

    private static func webItemId(of linea: WebPassportAnswerLine, in registro: WebPassportStore.StudentRecord?) -> String {
        registro?.answers[linea.itemId]?.answer.webItemId ?? ""
    }

    static func displayValue(_ respuesta: WebResolvedAnswer) -> String {
        switch respuesta.type {
        case .check:
            return respuesta.boolValue == true ? "Sí" : "No"
        case .number, .scale1To4:
            guard let numero = respuesta.numberValue else { return "" }
            return numero.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(numero)) : String(numero)
        case .text, .choice:
            return respuesta.textValue ?? ""
        }
    }
}
