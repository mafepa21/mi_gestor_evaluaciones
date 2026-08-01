import Foundation
import Security
import MiGestorKit

/// Almacén de la clave privada de cada formulario, y adaptador entre la tabla de
/// correspondencias de la base de datos y el `WebSubmissionImportService`.
///
/// Dos piezas, con una razón cada una:
///
///  - **`WebSubmissionKeychain`**: la clave privada X25519 vive en el llavero del
///    sistema, no en la base de datos. Si alguien copia o restaura el fichero de
///    la base de datos en otro dispositivo, las entregas pendientes siguen sin
///    poder abrirse. La base solo guarda una referencia (`private_key_ref`).
///  - **`WebSubmissionSnapshot`**: todo lo que hace falta para examinar un lote,
///    cargado de una vez. La alternativa era un resolutor asíncrono, pero eso
///    obligaría a que `examine` fuese `async` y a una consulta por entrega. Los
///    datos son pocos (un alias y un ítem por alumno y por pregunta), así que se
///    cargan en bloque y se resuelven en memoria.

// MARK: - Llavero

enum WebSubmissionKeychain {
    /// Prefijo de la referencia que se guarda en `web_form_instances.private_key_ref`.
    static let refPrefix = "llavero://entregas-web/"
    private static let service = "com.migestor.entregas-web"

    static func reference(for formInstanceId: String) -> String {
        refPrefix + formInstanceId
    }

    private static func account(from reference: String) -> String? {
        guard reference.hasPrefix(refPrefix) else { return nil }
        return String(reference.dropFirst(refPrefix.count))
    }

    /// Guarda la clave privada de 32 bytes. Sobrescribe si ya había una.
    @discardableResult
    static func save(privateKey: Data, reference: String) -> Bool {
        guard let cuenta = account(from: reference), privateKey.count == 32 else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cuenta,
        ]
        SecItemDelete(base as CFDictionary)
        var nuevo = base
        nuevo[kSecValueData as String] = privateKey
        // Sin sincronización con iCloud y solo accesible con el dispositivo
        // desbloqueado: es material de descifrado, no una preferencia.
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(nuevo as CFDictionary, nil) == errSecSuccess
    }

    static func load(reference: String) -> Data? {
        guard let cuenta = account(from: reference) else { return nil }
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cuenta,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data,
              datos.count == 32 else { return nil }
        return datos
    }

    @discardableResult
    static func delete(reference: String) -> Bool {
        guard let cuenta = account(from: reference) else { return false }
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cuenta,
        ]
        return SecItemDelete(consulta as CFDictionary) == errSecSuccess
    }
}

// MARK: - Snapshot

/// Todo lo que hace falta para examinar un lote de entregas de un formulario.
struct WebSubmissionSnapshot {
    let formInstanceId: String
    let classId: Int64
    let columnId: String
    let privateKeyRef: String
    let revoked: Bool
    let expiresAtEpochMs: Int64
    let title: String

    /// alias -> alumno.
    let studentIdByAlias: [String: Int64]
    /// `webItemId` -> `notebook_instrument_items.id`.
    let itemIdByWebItemId: [String: String]
    /// Nombre para mostrar en la previsualización.
    let studentNames: [Int64: String]
    /// Entregas ya vistas: `submissionId` -> momento de importación.
    let importedAtBySubmissionId: [String: Int64]
    /// Alumnado del grupo, para asignar a mano.
    let roster: [WebRosterEntry]
}

/// Resolutor síncrono sobre un snapshot ya cargado.
struct WebSubmissionSnapshotResolver: WebSubmissionContextResolver {
    let snapshotsByFormInstanceId: [String: WebSubmissionSnapshot]

    init(snapshot: WebSubmissionSnapshot) {
        self.snapshotsByFormInstanceId = [snapshot.formInstanceId: snapshot]
    }

    init(snapshots: [String: WebSubmissionSnapshot]) {
        self.snapshotsByFormInstanceId = snapshots
    }

    private func snapshot(for formInstanceId: String) -> WebSubmissionSnapshot? {
        snapshotsByFormInstanceId[formInstanceId]
    }

    func formInstance(formInstanceId: String) -> WebFormInstanceContext? {
        guard let snapshot = snapshot(for: formInstanceId) else { return nil }
        return WebFormInstanceContext(
            formInstanceId: snapshot.formInstanceId,
            classId: snapshot.classId,
            columnId: snapshot.columnId,
            privateKeyRef: snapshot.privateKeyRef,
            revoked: snapshot.revoked,
            expiresAtEpochMs: snapshot.expiresAtEpochMs
        )
    }

    func studentId(formInstanceId: String, alias: String) -> Int64? {
        snapshot(for: formInstanceId)?.studentIdByAlias[alias]
    }

    func studentName(studentId: Int64) -> String? {
        snapshotsByFormInstanceId.values
            .compactMap { $0.studentNames[studentId] }
            .first
    }

    func itemId(formInstanceId: String, webItemId: String) -> String? {
        snapshot(for: formInstanceId)?.itemIdByWebItemId[webItemId]
    }

    func alreadyImportedAtEpochMs(submissionId: String) -> Int64? {
        snapshotsByFormInstanceId.values
            .compactMap { $0.importedAtBySubmissionId[submissionId] }
            .first
    }

    func recipientPrivateKey(privateKeyRef: String) -> Data? {
        WebSubmissionKeychain.load(reference: privateKeyRef)
    }
}

// MARK: - Publicación

/// Una columna del Cuaderno con instrumento, candidata a publicarse.
struct WebPublishableInstrument: Identifiable, Hashable {
    var id: String { columnId }
    let columnId: String
    let columnTitle: String
    let templateTitle: String
    let itemCount: Int
    /// Ya tiene un formulario vivo. Publicar otro reparte códigos nuevos y deja
    /// los enlaces antiguos sin resolver, así que conviene avisar.
    let alreadyPublished: Bool
    /// Por qué NO se puede publicar, si es que no se puede. Se calcula al listar
    /// para poder avisar en la lista: descubrirlo al pulsar Publicar, después de
    /// haber elegido fecha y dirección, es la peor forma de enterarse.
    let blockingIssue: String?

    var canPublish: Bool { blockingIssue == nil }
}

struct WebPublishedLink: Identifiable, Hashable {
    var id: Int64 { studentId }
    let studentId: Int64
    let studentName: String
    let url: String
}

struct WebPublishResult {
    let formInstanceId: String
    let title: String
    let manifestPath: String
    let linksPath: String
    let folderPath: String
    let links: [WebPublishedLink]
    let linksText: String
}

enum WebSubmissionTaskStatus: String, CaseIterable, Hashable {
    case active
    case expired
    case revoked

    var label: String {
        switch self {
        case .active: return "Activa"
        case .expired: return "Caducada"
        case .revoked: return "Revocada"
        }
    }
}

/// Metadatos que la bandeja necesita para agrupar formularios publicados.
/// El mapa privado y las claves siguen viviendo en `WebSubmissionSnapshot`.
struct WebSubmissionTaskInfo: Identifiable, Hashable {
    var id: String { formInstanceId }
    let formInstanceId: String
    let classId: Int64
    let groupName: String
    let title: String
    let columnTitle: String
    let status: WebSubmissionTaskStatus
    let isArchived: Bool
    let expiresAtEpochMs: Int64
    let importedCount: Int
    let lastImportedAtEpochMs: Int64?

    var statusLabel: String { status.label }
    var displayTitle: String {
        "\(groupName) · \(title)"
    }

    var managementLabel: String {
        isArchived ? "Archivada" : status.label
    }
}

/// Enlace privado de un alumno dentro de una tarea web.
///
/// El enlace no se guarda en la base de datos pública ni se sincroniza: se
/// reconstruye desde la hoja privada que se escribió al publicar el formulario
/// y se cruza con el correo actual de la ficha del alumno.
struct WebPublishedStudentLink: Identifiable, Hashable {
    let studentId: Int64
    let studentName: String
    let email: String?
    let url: URL

    var id: Int64 { studentId }

    var hasEmail: Bool {
        guard let email else { return false }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Lee la hoja privada de enlaces creada al publicar una tarea.
///
/// La hoja de texto mantiene el formato cómodo para el docente. El alias del
/// fragmento (`a=`) permite recuperar el `studentId` sin confiar en el nombre
/// visible, que puede repetirse en un grupo.
enum WebSubmissionPrivateLinksStore {
    static func folderURL(for formInstanceId: String) -> URL? {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return documents
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent(formInstanceId, isDirectory: true)
    }

    static func readLinks(
        formInstanceId: String,
        snapshot: WebSubmissionSnapshot,
        students: [Student]
    ) -> [WebPublishedStudentLink] {
        guard let folder = folderURL(for: formInstanceId),
              let text = try? String(
                  contentsOf: folder.appendingPathComponent("enlaces-alumnado.txt"),
                  encoding: .utf8
              ) else { return [] }

        let studentsById = Dictionary(
            students.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [WebPublishedStudentLink] = []
        var seenStudentIds = Set<Int64>()

        for line in text.split(whereSeparator: \.isNewline) {
            guard let urlStart = line.range(of: "http://") ?? line.range(of: "https://") else {
                continue
            }
            let urlText = String(line[urlStart.lowerBound...]).trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: urlText),
                  let fragment = url.fragment else { continue }

            let fragmentValues = Dictionary(
                fragment.split(separator: "&").compactMap { field -> (String, String)? in
                    let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return nil }
                    return (parts[0], parts[1])
                },
                uniquingKeysWith: { first, _ in first }
            )
            guard fragmentValues["f"] == formInstanceId,
                  let alias = fragmentValues["a"],
                  let studentId = snapshot.studentIdByAlias[alias],
                  seenStudentIds.insert(studentId).inserted else { continue }

            let student = studentsById[studentId]
            result.append(
                WebPublishedStudentLink(
                    studentId: studentId,
                    studentName: snapshot.studentNames[studentId]
                        ?? student.map { "\($0.firstName) \($0.lastName)" }
                        ?? "Alumno \(studentId)",
                    email: student?.email,
                    url: url
                )
            )
        }

        return result.sorted {
            $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending
        }
    }
}

#if DEBUG
/// Lo que devuelve el banco de pruebas al montar un formulario a mano.
/// Se borra cuando exista la publicación de formularios de verdad.
struct WebSubmissionTestFormResult {
    let classId: Int64
    let columnId: String
    let studentName: String
}
#endif

// MARK: - Resultado de importar

struct WebSubmissionImportOutcome {
    var imported: Int = 0
    var failures: [(studentName: String, reason: String)] = []

    var isFullySuccessful: Bool { failures.isEmpty }

    /// Resumen en una línea para enseñar al docente al terminar.
    var summary: String {
        if failures.isEmpty {
            return imported == 1
                ? "Se ha importado 1 entrega."
                : "Se han importado \(imported) entregas."
        }
        if imported == 0 {
            return "No se ha podido importar ninguna entrega."
        }
        return "Se han importado \(imported) entregas y \(failures.count) han fallado."
    }
}
