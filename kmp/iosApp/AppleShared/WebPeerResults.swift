import Foundation

/// Resumen de una coevaluación para el docente: cuántas evaluaciones recibe cada
/// alumno, su media en cada criterio de escala 1-4 y las parejas que no casan.
///
/// La autoevaluación no entra aquí: el resumen y el correo hablan de lo que
/// dicen las parejas. La celda del Cuaderno sigue calculándose como siempre.
struct WebPeerResults {
    struct Criterion: Identifiable, Hashable {
        let webItemId: String
        let title: String
        var id: String { webItemId }
    }

    struct Row: Identifiable, Hashable {
        let studentId: Int64
        let name: String
        let email: String?
        let evaluationCount: Int
        /// Media 1-4 de cada criterio, en el orden de `criteria`. `nil` si nadie
        /// respondió ese criterio.
        let averages: [Double?]

        var id: Int64 { studentId }

        var overall: Double? {
            let valores = averages.compactMap { $0 }
            guard !valores.isEmpty else { return nil }
            return valores.reduce(0, +) / Double(valores.count)
        }
    }

    /// Alguien dice que evaluó a una persona que nunca le evaluó a él. Puede ser
    /// un nombre mal elegido o que la otra persona aún no haya enviado nada.
    struct Mismatch: Identifiable, Hashable {
        let evaluatorName: String
        let targetName: String
        /// La persona evaluada no ha enviado ninguna evaluación todavía.
        let targetHasNotSent: Bool
        var id: String { "\(evaluatorName)|\(targetName)" }
    }

    let title: String
    let groupName: String
    let locale: String
    let criteria: [Criterion]
    let rows: [Row]
    let mismatches: [Mismatch]
    let studentsWhoSent: Int
    let evaluationCount: Int

    struct RosterEntry {
        let id: Int64
        let name: String
        let email: String?
    }

    static func build(
        title: String,
        groupName: String,
        manifest: WebFormManifest,
        roster: [RosterEntry],
        evaluations: [WebPeerEvaluationStore.Evaluation],
        studentIdByAlias: [String: Int64]
    ) -> WebPeerResults {
        let criteria = manifest.items
            .filter { $0.type == .scale1To4 }
            .map { Criterion(webItemId: $0.webItemId, title: $0.title) }
        let names = Dictionary(roster.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        // Solo evaluaciones a otra persona, con evaluador conocido.
        let ajenas: [(evaluator: Int64, evaluation: WebPeerEvaluationStore.Evaluation)] = evaluations.compactMap { ev in
            guard let evaluador = studentIdByAlias[ev.evaluatorAlias], evaluador != ev.targetStudentId else { return nil }
            return (evaluador, ev)
        }

        let rows = roster.map { alumno -> Row in
            let recibidas = ajenas.filter { $0.evaluation.targetStudentId == alumno.id }.map(\.evaluation)
            let medias = criteria.map { criterio -> Double? in
                let valores = recibidas.compactMap { ev in
                    ev.answers.first { $0.webItemId == criterio.webItemId }?.numberValue
                }
                guard !valores.isEmpty else { return nil }
                return valores.reduce(0, +) / Double(valores.count)
            }
            return Row(studentId: alumno.id, name: alumno.name, email: alumno.email, evaluationCount: recibidas.count, averages: medias)
        }

        let evaluadores = Set(evaluations.compactMap { studentIdByAlias[$0.evaluatorAlias] })
        let parejas = Set(ajenas.map { Pair(from: $0.evaluator, to: $0.evaluation.targetStudentId) })
        let mismatches = parejas
            .filter { !parejas.contains(Pair(from: $0.to, to: $0.from)) }
            .map { par in
                Mismatch(
                    evaluatorName: names[par.from] ?? "Alumno \(par.from)",
                    targetName: names[par.to] ?? "Alumno \(par.to)",
                    targetHasNotSent: !evaluadores.contains(par.to)
                )
            }
            .sorted { ($0.evaluatorName, $0.targetName) < ($1.evaluatorName, $1.targetName) }

        return WebPeerResults(
            title: title,
            groupName: groupName,
            locale: manifest.locale,
            criteria: criteria,
            rows: rows,
            mismatches: mismatches,
            studentsWhoSent: evaluadores.count,
            evaluationCount: ajenas.count
        )
    }

    private struct Pair: Hashable {
        let from: Int64
        let to: Int64
    }
}

// MARK: - Correo de resultados

/// Texto del correo con la media de cada alumno. Nunca nombra a quien evaluó.
enum WebPeerResultsMail {
    static func subject(title: String, locale: String) -> String {
        locale == "es" ? "Tus resultados de la coevaluación · \(title)" : "Your peer review results · \(title)"
    }

    static func body(row: WebPeerResults.Row, criteria: [WebPeerResults.Criterion], locale: String, signature: String) -> String {
        let es = locale == "es"
        let nombre = firstName(row.name)
        let veces = row.evaluationCount
        var lineas: [String] = []
        lineas.append(es ? "Hola, \(nombre):" : "Hi \(nombre),")
        lineas.append("")
        if es {
            lineas.append("Tus parejas te evaluaron en \(veces) \(veces == 1 ? "partido" : "partidos"). Esta es la media, de 1 a 4:")
        } else {
            lineas.append("Your partners reviewed your play in \(veces) \(veces == 1 ? "match" : "matches"). This is the average, from 1 to 4:")
        }
        lineas.append("")
        for (criterio, media) in zip(criteria, row.averages) {
            lineas.append("\(criterio.title): \(media.map { format($0, locale: locale) } ?? "–")")
        }
        let conMedia = zip(criteria, row.averages).compactMap { c, m in m.map { (c.title, $0) } }
        if conMedia.count >= 2,
           let fuerte = conMedia.max(by: { $0.1 < $1.1 }),
           let flojo = conMedia.min(by: { $0.1 < $1.1 }),
           fuerte.1 > flojo.1 {
            lineas.append("")
            lineas.append(es
                ? "Tu punto fuerte: \(fuerte.0.lowercased()). Tu próxima meta: \(flojo.0.lowercased())."
                : "Your strongest point: \(fuerte.0.lowercased()). Next goal: \(flojo.0.lowercased()).")
        }
        lineas.append("")
        lineas.append(es
            ? "Es solo para que mejores: no cuenta para tu nota."
            : "This is feedback only. It does not count towards your grade.")
        if !signature.isEmpty {
            lineas.append("")
            lineas.append(signature)
        }
        return lineas.joined(separator: "\n")
    }

    /// A quién se le puede escribir y a quién no, con el motivo.
    static func plan(
        results: WebPeerResults,
        selected: Set<Int64>,
        signature: String
    ) -> WebSubmissionMailPlan {
        var mensajes: [WebSubmissionMailMessage] = []
        var fuera: [WebSubmissionMailSkip] = []
        for fila in results.rows where selected.contains(fila.studentId) {
            let correo = (fila.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if fila.evaluationCount == 0 {
                fuera.append(WebSubmissionMailSkip(studentId: fila.studentId, studentName: fila.name, reason: "Nadie le ha evaluado todavía."))
            } else if !WebSubmissionBulkMailPlanner.isPlausibleAddress(correo) {
                fuera.append(WebSubmissionMailSkip(studentId: fila.studentId, studentName: fila.name, reason: "No tiene correo en su ficha."))
            } else {
                mensajes.append(
                    WebSubmissionMailMessage(
                        studentId: fila.studentId,
                        studentName: fila.name,
                        recipient: correo,
                        subject: subject(title: results.title, locale: results.locale),
                        body: body(row: fila, criteria: results.criteria, locale: results.locale, signature: signature)
                    )
                )
            }
        }
        return WebSubmissionMailPlan(messages: mensajes, skipped: fuera)
    }

    static func format(_ value: Double, locale: String) -> String {
        let texto = String(format: "%.1f", value)
        return locale == "es" ? texto.replacingOccurrences(of: ".", with: ",") : texto
    }

    private static func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }
}
