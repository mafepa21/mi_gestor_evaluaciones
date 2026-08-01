import Foundation

/// Reparto masivo de los enlaces de una tarea web: un correo por alumno,
/// preparados de una sola vez desde el Mac.
///
/// Tres decisiones que conviene tener presentes:
///
///  - **Un mensaje por alumno, siempre.** Nunca se agrupan varios destinatarios
///    en un mismo correo. Cada enlace lleva el alias personal de su dueño, así
///    que un envío conjunto expondría a la vez las direcciones del grupo y los
///    enlaces ajenos.
///  - **Mail hace el envío, no la app.** Se automatiza la cuenta que el docente
///    ya tiene configurada en su Mac. La app no guarda contraseñas, no habla con
///    ningún servidor SMTP y no manda direcciones por SyncLAN.
///  - **La plantilla se resuelve aquí, no en el guion.** El texto se compone y se
///    escapa en Swift; al AppleScript solo llega una cadena literal ya cerrada.
///    Un nombre con comillas o un salto de línea no puede alterar el guion.

// MARK: - Modo de reparto

enum WebSubmissionMailDelivery: String, CaseIterable, Identifiable {
    /// Deja cada mensaje en Borradores para revisarlo antes de enviar.
    case drafts
    /// Envía cada mensaje en cuanto se crea.
    case send

    var id: String { rawValue }

    var label: String {
        switch self {
        case .drafts: return "Borradores"
        case .send: return "Enviar"
        }
    }

    var explanation: String {
        switch self {
        case .drafts:
            return "Mail crea los mensajes en Borradores. Nada sale hasta que los envíes tú."
        case .send:
            return "Mail envía cada mensaje según se crea. No hay vuelta atrás."
        }
    }
}

// MARK: - Plantilla

/// Sustitución de los huecos de la plantilla del cuerpo del correo.
///
/// Los huecos van en español y con dobles llaves para que se distingan del texto
/// normal aunque el docente escriba el mensaje entero de su puño y letra.
enum WebSubmissionMailTemplate {
    static let namePlaceholder = "{{nombre}}"
    static let taskPlaceholder = "{{tarea}}"
    static let linkPlaceholder = "{{enlace}}"

    static let allPlaceholders = [namePlaceholder, taskPlaceholder, linkPlaceholder]

    static func render(
        _ template: String,
        studentName: String,
        taskTitle: String,
        link: String
    ) -> String {
        template
            .replacingOccurrences(of: namePlaceholder, with: studentName)
            .replacingOccurrences(of: taskPlaceholder, with: taskTitle)
            .replacingOccurrences(of: linkPlaceholder, with: link)
    }

    /// Plantilla por defecto. Es la misma redacción de siempre, con los huecos
    /// donde antes había texto ya sustituido.
    static let defaultBody = """
    Hola \(namePlaceholder),

    Aquí tienes tu enlace individual para la tarea «\(taskPlaceholder)»:

    \(linkPlaceholder)

    Cuando termines, utiliza el botón de enviar de la página.

    Un saludo.
    """
}

// MARK: - Plan

/// Un correo ya compuesto, listo para entregar a Mail.
struct WebSubmissionMailMessage: Identifiable, Hashable {
    let studentId: Int64
    let studentName: String
    let recipient: String
    let subject: String
    let body: String

    var id: Int64 { studentId }
}

/// Alumno que se queda fuera del reparto, y por qué.
struct WebSubmissionMailSkip: Identifiable, Hashable {
    let studentId: Int64
    let studentName: String
    let reason: String

    var id: Int64 { studentId }
}

/// Qué se va a mandar y qué no, calculado antes de tocar Mail.
struct WebSubmissionMailPlan {
    let messages: [WebSubmissionMailMessage]
    let skipped: [WebSubmissionMailSkip]

    var isEmpty: Bool { messages.isEmpty }
}

enum WebSubmissionBulkMailPlanner {
    /// Separa a quién se le puede escribir de quién se queda fuera, sin componer
    /// todavía ningún texto. La pantalla necesita estas cuentas en cada redibujo
    /// y componer el cuerpo de treinta correos por pulsación de tecla no sale
    /// gratis.
    ///
    /// Apartar es mejor que fallar: el resto del grupo no debería quedarse sin
    /// enlace porque a una ficha le falte el correo.
    static func split(
        links: [WebPublishedStudentLink]
    ) -> (eligible: [(link: WebPublishedStudentLink, address: String)], skipped: [WebSubmissionMailSkip]) {
        var eligible: [(link: WebPublishedStudentLink, address: String)] = []
        var skipped: [WebSubmissionMailSkip] = []

        for link in links {
            let address = (link.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if address.isEmpty {
                skipped.append(
                    WebSubmissionMailSkip(
                        studentId: link.studentId,
                        studentName: link.studentName,
                        reason: "Sin correo en la ficha"
                    )
                )
            } else if !isPlausibleAddress(address) {
                skipped.append(
                    WebSubmissionMailSkip(
                        studentId: link.studentId,
                        studentName: link.studentName,
                        reason: "Correo con formato no válido"
                    )
                )
            } else {
                eligible.append((link: link, address: address))
            }
        }

        return (eligible: eligible, skipped: skipped)
    }

    /// Compone un correo por alumno con la plantilla ya resuelta.
    static func plan(
        taskTitle: String,
        links: [WebPublishedStudentLink],
        subject: String,
        bodyTemplate: String
    ) -> WebSubmissionMailPlan {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let partition = split(links: links)

        let messages = partition.eligible.map { entry in
            WebSubmissionMailMessage(
                studentId: entry.link.studentId,
                studentName: entry.link.studentName,
                recipient: entry.address,
                subject: cleanSubject,
                body: WebSubmissionMailTemplate.render(
                    bodyTemplate,
                    studentName: entry.link.studentName,
                    taskTitle: taskTitle,
                    link: entry.link.url.absoluteString
                )
            )
        }

        return WebSubmissionMailPlan(messages: messages, skipped: partition.skipped)
    }

    /// Comprobación deliberadamente laxa: solo descarta lo que Mail rechazaría
    /// seguro. Validar direcciones a fondo con una expresión regular produce más
    /// falsos negativos que aciertos, y aquí un falso negativo deja a un alumno
    /// sin su enlace.
    static func isPlausibleAddress(_ address: String) -> Bool {
        guard !address.contains(where: \.isWhitespace) else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}

// MARK: - Resultado

struct WebSubmissionBulkMailReport {
    let delivery: WebSubmissionMailDelivery
    var deliveredStudentIds: [Int64] = []
    var failures: [(studentName: String, reason: String)] = []
    var skipped: [WebSubmissionMailSkip] = []
    /// El docente denegó el permiso de automatización, o aún no lo ha concedido.
    var permissionDenied = false

    var deliveredCount: Int { deliveredStudentIds.count }

    var summary: String {
        if permissionDenied {
            return "Mail no dio permiso a la app, así que no se preparó ningún correo."
        }

        let verb = delivery == .drafts ? "Se prepararon" : "Se enviaron"
        let noun = deliveredCount == 1 ? "correo" : "correos"
        var parts = ["\(verb) \(deliveredCount) \(noun)."]

        if !failures.isEmpty {
            parts.append(failures.count == 1 ? "1 falló." : "\(failures.count) fallaron.")
        }
        if !skipped.isEmpty {
            parts.append(
                skipped.count == 1
                    ? "1 alumno se quedó fuera por no tener correo utilizable."
                    : "\(skipped.count) alumnos se quedaron fuera por no tener correo utilizable."
            )
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Guion de Mail

#if os(macOS)

/// Construcción del AppleScript que crea un mensaje en Mail.
enum WebSubmissionMailScript {
    /// Escapa una cadena para meterla en un literal de AppleScript.
    ///
    /// La barra invertida va primero: si se escapase después, duplicaría las
    /// barras que introducen los otros reemplazos.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func source(
        for message: WebSubmissionMailMessage,
        delivery: WebSubmissionMailDelivery
    ) -> String {
        // `visible:false` evita que se abra una ventana por alumno. Con 30
        // enlaces, abrirlas dejaría el Mac inservible durante el reparto.
        let finalAction = delivery == .drafts ? "save nuevoMensaje" : "send nuevoMensaje"
        return """
        tell application "Mail"
            set nuevoMensaje to make new outgoing message with properties {subject:"\(escape(message.subject))", content:"\(escape(message.body))", visible:false}
            tell nuevoMensaje
                make new to recipient at end of to recipients with properties {address:"\(escape(message.recipient))"}
            end tell
            \(finalAction)
        end tell
        """
    }
}

/// Ejecuta el reparto contra Mail.
///
/// `NSAppleScript` no es seguro fuera del hilo principal, así que todo el
/// repartidor vive en el actor principal. Cada mensaje es un guion corto; entre
/// mensaje y mensaje se cede el hilo para que la barra de progreso avance y la
/// ventana siga respondiendo.
@MainActor
enum WebSubmissionBulkMailer {
    /// Cuántos correos seguidos antes de una pausa larga. Los servidores de
    /// centro suelen cortar las ráfagas, y una pausa corta sale más barata que
    /// un reparto a medias.
    static let batchSize = 10
    static let pauseBetweenBatches: Duration = .seconds(2)
    static let pauseBetweenMessages: Duration = .milliseconds(120)

    /// Número de error de Apple Events cuando el usuario no ha dado permiso de
    /// automatización sobre Mail.
    private static let notPermitted = -1743

    static func deliver(
        plan: WebSubmissionMailPlan,
        delivery: WebSubmissionMailDelivery,
        onProgress: (Int) -> Void = { _ in }
    ) async -> WebSubmissionBulkMailReport {
        var report = WebSubmissionBulkMailReport(delivery: delivery)
        report.skipped = plan.skipped

        for (index, message) in plan.messages.enumerated() {
            switch run(message: message, delivery: delivery) {
            case .success:
                report.deliveredStudentIds.append(message.studentId)
            case .permissionDenied:
                // Sin permiso no va a funcionar el siguiente tampoco. Se corta
                // aquí en vez de acumular el mismo fallo una vez por alumno.
                report.permissionDenied = true
                return report
            case .failure(let reason):
                report.failures.append((studentName: message.studentName, reason: reason))
            }

            onProgress(index + 1)

            let isLast = index == plan.messages.count - 1
            if !isLast {
                let endsBatch = (index + 1) % batchSize == 0
                try? await Task.sleep(for: endsBatch ? pauseBetweenBatches : pauseBetweenMessages)
            }
        }

        return report
    }

    private enum RunOutcome {
        case success
        case permissionDenied
        case failure(String)
    }

    private static func run(
        message: WebSubmissionMailMessage,
        delivery: WebSubmissionMailDelivery
    ) -> RunOutcome {
        guard let script = NSAppleScript(source: WebSubmissionMailScript.source(
            for: message,
            delivery: delivery
        )) else {
            return .failure("No se pudo construir el mensaje.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return .success }

        let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
        if number == notPermitted {
            return .permissionDenied
        }
        let described = (errorInfo[NSAppleScript.errorMessage] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(described?.isEmpty == false ? described! : "Mail devolvió el error \(number).")
    }
}

#endif
