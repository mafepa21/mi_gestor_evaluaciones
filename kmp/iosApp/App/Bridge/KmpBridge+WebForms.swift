import Foundation
import MiGestorKit
import CryptoKit

extension KmpBridge {
    // MARK: - Publicación de formularios web

    /// Columnas del grupo que tienen una plantilla de instrumento y por tanto se
    /// pueden publicar. Se hace una consulta por columna, y está bien: son unas
    /// pocas decenas y esto corre una vez al abrir la pantalla, no por celda.
    func listPublishableWebForms(classId: Int64) async -> [WebPublishableInstrument] {
        guard let columnas = try? await container.notebookRepository
            .listNotebookVisibleColumns(classId: classId, tabId: nil) else { return [] }

        let publicados = (try? await container.webSubmissionsRepository
            .listFormInstancesForClass(classId: classId)) ?? []

        var salida: [WebPublishableInstrument] = []
        for columna in columnas {
            guard let detalle = try? await container.notebookInstrumentsRepository
                .getTemplateForColumn(columnId: columna.id),
                  !detalle.items.isEmpty else { continue }
            // Una pregunta de elección sin opciones no se puede responder, así que
            // el formulario entero sería inservible. Se detecta aquí para avisarlo
            // en la lista y no al pulsar Publicar.
            let sinOpciones = detalle.items.first {
                $0.type == .choice && $0.options.count < 2
            }
            let problema = sinOpciones.map {
                "«\($0.title)» es de elección y no tiene opciones. Edita el instrumento y añádelas."
            }

            salida.append(
                WebPublishableInstrument(
                    columnId: columna.id,
                    columnTitle: columna.title,
                    templateTitle: detalle.template_.title,
                    itemCount: detalle.items.count,
                    alreadyPublished: publicados.contains {
                        $0.columnId == columna.id && !$0.revoked
                    },
                    blockingIssue: problema
                )
            )
        }
        return salida
    }

    /// Formularios publicados de un grupo, del más reciente al más antiguo.
    func listWebFormInstances(classId: Int64) async throws -> [WebFormInstance] {
        try await container.webSubmissionsRepository.listFormInstancesForClass(classId: classId)
    }

    /// Resumen global para la bandeja de Entregas web del Mac.
    /// La tabla de correspondencias sigue siendo local; solo se agregan sus
    /// metadatos para presentar grupo, estado y actividad de importación.
    func listWebSubmissionTasks() async -> [WebSubmissionTaskInfo] {
        guard let instancias = try? await container.webSubmissionsRepository
            .listAllFormInstances() else { return [] }

        var titlesByColumnId: [String: String] = [:]
        for classId in Set(instancias.map(\.classId)) {
            let columnas = (try? await container.notebookRepository
                .listNotebookVisibleColumns(classId: classId, tabId: nil)) ?? []
            for columna in columnas {
                titlesByColumnId[columna.id] = columna.title
            }
        }

        let ahora = Int64(Date().timeIntervalSince1970 * 1000)
        var resultado: [WebSubmissionTaskInfo] = []
        for instancia in instancias {
            let ledger = (try? await container.webSubmissionsRepository
                .listLedgerForForm(formInstanceId: instancia.formInstanceId)) ?? []
            let importadas = ledger.filter { $0.status == "IMPORTED" }
                    let estado: WebSubmissionTaskStatus
                    if instancia.revoked {
                        estado = .revoked
            } else if instancia.expiresAtEpochMs <= ahora {
                estado = .expired
            } else {
                estado = .active
            }

            let nombreGrupo = classes.first(where: { $0.id == instancia.classId })?.name
                ?? "Grupo \(instancia.classId)"
            resultado.append(
                WebSubmissionTaskInfo(
                    formInstanceId: instancia.formInstanceId,
                    classId: instancia.classId,
                    groupName: nombreGrupo,
                    title: instancia.title,
                    columnTitle: titlesByColumnId[instancia.columnId] ?? instancia.columnId,
                    status: estado,
                    isArchived: instancia.archived,
                    expiresAtEpochMs: instancia.expiresAtEpochMs,
                    importedCount: importadas.count,
                    lastImportedAtEpochMs: importadas.map(\.importedAtEpochMs).max(),
                    mode: instancia.mode
                )
            )
        }

        let orden: [WebSubmissionTaskStatus: Int] = [.active: 0, .expired: 1, .revoked: 2]
        return resultado.sorted {
            if $0.isArchived != $1.isArchived {
                return !$0.isArchived
            }
            if $0.status != $1.status {
                return (orden[$0.status] ?? 9) < (orden[$1.status] ?? 9)
            }
            return $0.expiresAtEpochMs > $1.expiresAtEpochMs
        }
    }

    /// Marca una tarea como revocada sin borrar su historial ni sus entregas.
    ///
    /// La revocación es local a este Mac: el manifiesto público ya desplegado
    /// no puede cambiarse desde la app porque su firma pertenece al formulario
    /// publicado. La bandeja deja de considerarlo activo y conserva la clave,
    /// alias y ledger para poder importar archivos válidos recibidos antes.
    func revokeWebForm(formInstanceId: String) async throws {
        guard let instance = try await container.webSubmissionsRepository
            .getFormInstance(formInstanceId: formInstanceId) else {
            throw NSError(
                domain: "WebSubmissions",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No se encontró la tarea web que se quiere revocar."]
            )
        }
        guard !instance.revoked else { return }
        try await container.webSubmissionsRepository.revokeFormInstance(
            formInstanceId: formInstanceId,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// Revoca varias tareas en una transacción del repositorio y conserva la
    /// información privada necesaria para importar entregas ya recibidas.
    func revokeWebForms(formInstanceIds: [String]) async throws {
        guard !formInstanceIds.isEmpty else { return }
        try await container.webSubmissionsRepository.revokeFormInstances(
            formInstanceIds: formInstanceIds,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// Archiva tareas solo en la bandeja local. No revoca el formulario web.
    func archiveWebForms(formInstanceIds: [String]) async throws {
        guard !formInstanceIds.isEmpty else { return }
        try await container.webSubmissionsRepository.archiveFormInstances(
            formInstanceIds: formInstanceIds,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    func restoreArchivedWebForms(formInstanceIds: [String]) async throws {
        guard !formInstanceIds.isEmpty else { return }
        try await container.webSubmissionsRepository.restoreArchivedFormInstances(
            formInstanceIds: formInstanceIds,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    struct WebPeerGroupInfo: Identifiable, Hashable {
        var id: Int64 { groupId }
        let groupId: Int64
        let groupName: String
        let studentIds: [Int64]
    }

    struct WebPeerDetectionResult: Hashable {
        let learningSituationId: Int64?
        let learningSituationTitle: String?
        let groups: [WebPeerGroupInfo]
        let assignedStudentCount: Int
        let unassignedStudentCount: Int
        let totalStudents: Int
    }

    /// Detecta la Situación de Aprendizaje vinculada a una columna y los grupos de trabajo asociados a ella.
    func detectPeerGroupsForColumn(classId: Int64, columnId: String) async -> WebPeerDetectionResult {
        let alumnado = (try? await container.classesRepository.listStudentsInClass(classId: classId)) ?? []
        let totalStudents = alumnado.count
        guard totalStudents > 0 else {
            return WebPeerDetectionResult(
                learningSituationId: nil,
                learningSituationTitle: nil,
                groups: [],
                assignedStudentCount: 0,
                unassignedStudentCount: 0,
                totalStudents: 0
            )
        }

        let snapshot = try? await container.notebookRepository.loadNotebookSnapshot(classId: classId)
        let colDef = snapshot?.columns.first(where: { $0.id == columnId })
        let tabs = snapshot?.tabs ?? []

        // 1. Buscar si hay una Situación de Aprendizaje asociada a la columna
        let situaciones = (try? await container.learningSituationsRepository.listSituations()) ?? []
        var detectedSituationId: Int64?
        var detectedSituationTitle: String?

        for sit in situaciones {
            let recursos = (try? await container.learningSituationsRepository.listLinkedResources(learningSituationId: sit.id)) ?? []
            if recursos.contains(where: { $0.resourceId == columnId }) {
                detectedSituationId = sit.id
                detectedSituationTitle = sit.title
                break
            }
        }

        // Si no se encontró por recurso enlazado, comprobar si coincide por el título de la unidad/situación en la columna
        if detectedSituationId == nil, let unit = colDef?.unitOrSituation?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            if let coincidencia = situaciones.first(where: { $0.title.localizedCaseInsensitiveCompare(unit) == .orderedSame }) {
                detectedSituationId = coincidencia.id
                detectedSituationTitle = coincidencia.title
            }
        }

        // 2. Cargar grupos y miembros de la clase
        let allGroups = (try? await container.notebookConfigRepository.listWorkGroups(classId: classId, tabId: nil)) ?? []
        let allMembers = (try? await container.notebookConfigRepository.listWorkGroupMembers(classId: classId, tabId: nil)) ?? []

        // 3. Resolución inclusiva de grupos:
        //    a) Grupos asignados a la SA vinculada
        //    b) Fallback: grupos de la pestaña de la columna (o familia de pestañas)
        //    c) Fallback: grupos generales de la clase
        var candidateGroups: [NotebookWorkGroup] = []
        if let situationId = detectedSituationId {
            let saGroups = allGroups.filter { $0.learningSituationId?.int64Value == situationId }
            if !saGroups.isEmpty {
                candidateGroups = saGroups
            }
        }

        if candidateGroups.isEmpty {
            let colTabIds = Set(colDef?.tabIds ?? [])
            let tabFamilies: Set<String> = Set(colTabIds.flatMap { tabId in
                NotebookWorkGroupPolicy.tabFamilyIds(tabs: tabs, activeTabId: tabId)
            })
            let relevantTabIds = tabFamilies.isEmpty ? colTabIds : tabFamilies

            let tabGroups = allGroups.filter { relevantTabIds.contains($0.tabId) }
            if !tabGroups.isEmpty {
                candidateGroups = tabGroups
            } else {
                candidateGroups = allGroups
            }
        }

        var detectedGroups: [WebPeerGroupInfo] = []
        var assignedStudentIds = Set<Int64>()

        for g in candidateGroups.sorted(by: { $0.order < $1.order }) {
            let memberIds = allMembers.filter { $0.groupId == g.id }.map { $0.studentId }
            if !memberIds.isEmpty {
                detectedGroups.append(WebPeerGroupInfo(groupId: g.id, groupName: g.name, studentIds: memberIds))
                for sId in memberIds {
                    assignedStudentIds.insert(sId)
                }
            }
        }

        let assignedCount = assignedStudentIds.count
        let unassignedCount = max(0, totalStudents - assignedCount)

        let titleToDisplay: String?
        if let detectedTitle = detectedSituationTitle {
            titleToDisplay = detectedTitle
        } else if let unit = colDef?.unitOrSituation?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            titleToDisplay = unit
        } else if let firstTabId = colDef?.tabIds.first, let tabTitle = tabs.first(where: { $0.id == firstTabId })?.title {
            titleToDisplay = "Grupos de «\(tabTitle)»"
        } else {
            titleToDisplay = "Grupos de trabajo del Cuaderno"
        }

        return WebPeerDetectionResult(
            learningSituationId: detectedSituationId,
            learningSituationTitle: titleToDisplay,
            groups: detectedGroups,
            assignedStudentCount: assignedCount,
            unassignedStudentCount: unassignedCount,
            totalStudents: totalStudents
        )
    }

    /// Publica un formulario: genera claves, construye y firma el manifiesto, lo
    /// guarda con sus alias y su mapa de ítems, mete la clave privada en el llavero
    /// y escribe los dos ficheros que necesita el docente.
    ///
    /// Si algo falla a mitad no se queda un formulario cojo: las escrituras de
    /// alias e ítems van en transacción, y la clave se guarda **antes** de anunciar
    /// el éxito, porque un formulario registrado sin clave en el llavero sería
    /// imposible de importar después.
    func publishWebForm(
        classId: Int64,
        columnId: String,
        baseURL: String,
        deliveryEmail: String?,
        expiresAt: Date,
        mode: String = "self"
    ) async throws -> WebPublishResult {
        guard let detalle = try await container.notebookInstrumentsRepository
            .getTemplateForColumn(columnId: columnId) else {
            throw NSError(
                domain: "WebSubmissions",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Esa columna no tiene un instrumento con apartados."]
            )
        }

        let alumnado = try await container.classesRepository.listStudentsInClass(classId: classId)
        guard !alumnado.isEmpty else {
            throw NSError(
                domain: "WebSubmissions",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "El grupo no tiene alumnado al que dar enlaces."]
            )
        }

        let items: [WebSubmissionPublisher.ItemToPublish] = detalle.items
            .sorted { $0.order < $1.order }
            .map { item in
                WebSubmissionPublisher.ItemToPublish(
                    itemId: item.id,
                    title: item.title,
                    type: Self.webItemType(from: item.type),
                    required: item.required,
                    options: item.options,
                    helpText: item.helpText,
                    // La plantilla del Cuaderno no guarda etiquetas por nivel; la
                    // PWA cae a 1-2-3-4, que es lo que se ve en el instrumento.
                    scaleLabels: nil,
                    sectionId: nil
                )
            }

        var peerTargetsToPublish: [WebSubmissionPublisher.PeerTargetToPublish] = []
        if mode == "peer" {
            let detection = await detectPeerGroupsForColumn(classId: classId, columnId: columnId)
            let studentNameMap = Dictionary(uniqueKeysWithValues: alumnado.map {
                ($0.id, "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces))
            })
            for group in detection.groups {
                for evaluatorId in group.studentIds {
                    // 1. Autoevaluación propia del alumno
                    peerTargetsToPublish.append(
                        WebSubmissionPublisher.PeerTargetToPublish(
                            evaluatorStudentId: evaluatorId,
                            targetStudentId: evaluatorId,
                            targetName: "Mi autoevaluación"
                        )
                    )
                    // 2. Coevaluación de sus compañeros de equipo
                    for targetId in group.studentIds where targetId != evaluatorId {
                        let targetName = studentNameMap[targetId] ?? "Compañero"
                        peerTargetsToPublish.append(
                            WebSubmissionPublisher.PeerTargetToPublish(
                                evaluatorStudentId: evaluatorId,
                                targetStudentId: targetId,
                                targetName: targetName
                            )
                        )
                    }
                }
            }
        }

        let publicado = try WebSubmissionPublisher.publish(
            title: detalle.template_.title,
            subtitle: nil,
            locale: "es",
            sections: [],
            items: items,
            students: alumnado.map {
                WebSubmissionPublisher.StudentToPublish(
                    id: $0.id,
                    name: "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces)
                )
            },
            baseURL: baseURL,
            deliveryEmail: deliveryEmail,
            expiresAtEpochMs: Int64(expiresAt.timeIntervalSince1970 * 1000),
            mode: mode,
            peerTargets: peerTargetsToPublish
        )

        // La clave primero: un formulario registrado sin clave en el llavero no se
        // podría importar nunca, y eso no se ve hasta que llega la primera entrega.
        guard WebSubmissionKeychain.save(
            privateKey: publicado.recipientPrivateKey,
            reference: WebSubmissionKeychain.reference(for: publicado.formInstanceId)
        ) else {
            throw NSError(
                domain: "WebSubmissions",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo guardar la clave en el llavero. No se ha publicado nada."]
            )
        }

        let ahora = Int64(Date().timeIntervalSince1970 * 1000)
        try await container.webSubmissionsRepository.saveFormInstance(
            instance: WebFormInstance(
                formInstanceId: publicado.formInstanceId,
                classId: classId,
                columnId: columnId,
                templateId: detalle.template_.id,
                title: detalle.template_.title,
                recipientPublicKey: publicado.recipientPublicKey,
                privateKeyRef: WebSubmissionKeychain.reference(for: publicado.formInstanceId),
                publisherPublicKey: publicado.publisherPublicKey,
                expiresAtEpochMs: publicado.expiresAtEpochMs,
                revoked: false,
                archived: false,
                manifestJson: publicado.manifestJSON,
                mode: publicado.mode,
                createdAtEpochMs: ahora,
                updatedAtEpochMs: ahora
            )
        )
        try await container.webSubmissionsRepository.saveItemMap(
            formInstanceId: publicado.formInstanceId,
            entries: publicado.itemMap.map {
                WebItemMapEntry(webItemId: $0.webItemId, itemId: $0.itemId, itemType: $0.itemType.rawValue)
            }
        )
        try await container.webSubmissionsRepository.saveAliases(
            formInstanceId: publicado.formInstanceId,
            entries: publicado.aliases.map {
                WebAliasEntry(alias: $0.alias, studentId: $0.studentId, createdAtEpochMs: ahora)
            }
        )
        if !publicado.peerTargets.isEmpty {
            try await container.webSubmissionsRepository.savePeerTargets(
                formInstanceId: publicado.formInstanceId,
                entries: publicado.peerTargets.map { pt in
                    WebPeerTargetEntry(
                        evaluatorAlias: pt.evaluatorAlias,
                        targetAlias: pt.targetAlias,
                        targetStudentId: pt.targetStudentId,
                        targetDisplayName: pt.targetName,
                        createdAtEpochMs: ahora
                    )
                }
            )
        }

        let carpeta = try Self.writePublishedFiles(publicado, title: detalle.template_.title)

        return WebPublishResult(
            formInstanceId: publicado.formInstanceId,
            title: detalle.template_.title,
            manifestPath: carpeta.manifest.path,
            linksPath: carpeta.links.path,
            folderPath: carpeta.folder.path,
            links: publicado.links.map {
                WebPublishedLink(studentId: $0.studentId, studentName: $0.studentName, url: $0.url)
            },
            linksText: WebSubmissionPublisher.linksText(for: publicado, title: detalle.template_.title)
        )
    }

    /// Escribe el manifiesto y la hoja de enlaces en Documentos.
    ///
    /// Dos ficheros separados porque tienen destinos y sensibilidad distintos: el
    /// manifiesto se sube a un sitio público, la hoja de enlaces **no** se sube a
    /// ninguna parte y se reparte en privado, uno a uno.
    private static func writePublishedFiles(
        _ form: WebSubmissionPublisher.PublishedForm,
        title: String
    ) throws -> (folder: URL, manifest: URL, links: URL) {
        let documentos = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let carpeta = documentos
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent(form.formInstanceId, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        // El fichero se llama como el formulario porque así es como lo busca la
        // web: `/manifiestos/<formInstanceId>.json`. Copiarlo tal cual a
        // `public/manifiestos/` es todo lo que hay que hacer, y así pueden convivir
        // varios formularios publicados sin pisarse.
        let manifiesto = carpeta.appendingPathComponent("\(form.formInstanceId).json")
        try Data(form.manifestJSON.utf8).write(to: manifiesto)

        let enlaces = carpeta.appendingPathComponent("enlaces-alumnado.txt")
        try Data(WebSubmissionPublisher.linksText(for: form, title: title).utf8)
            .write(to: enlaces, options: [.atomic])
        // La hoja de enlaces sí relaciona nombre y código: se deja solo para el
        // dueño del dispositivo.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: enlaces.path)

        return (folder: carpeta, manifest: manifiesto, links: enlaces)
    }

    private static func webItemType(from tipo: NotebookInstrumentItemType) -> WebManifestItemType {
        switch tipo {
        case .check: return .check
        case .text: return .text
        case .number: return .number
        case .scale14: return .scale1To4
        case .choice: return .choice
        default: return .text
        }
    }

    // MARK: - Entregas del alumnado hechas desde la web

    /// Carga de una vez todo lo que hace falta para examinar un lote de entregas.
    ///
    /// Se carga en bloque y no consulta a consulta a propósito: la alternativa era
    /// un resolutor asíncrono, que obligaría a que `examine` fuese `async` y a una
    /// consulta por entrega. Los datos son pocos (un alias por alumno, un ítem por
    /// pregunta), así que caben en memoria y el examen se queda síncrono y probable.
    ///
    /// Devuelve `nil` si el formulario no está registrado en este dispositivo, que
    /// es lo que pasa cuando el docente lo publicó desde otro Mac: la tabla de
    /// correspondencias no viaja por Sync LAN, y es deliberado.
    func loadWebSubmissionSnapshot(formInstanceId: String) async -> WebSubmissionSnapshot? {
        guard let instancia = try? await container.webSubmissionsRepository
            .getFormInstance(formInstanceId: formInstanceId) else { return nil }

        let alias = (try? await container.webSubmissionsRepository
            .listAliases(formInstanceId: formInstanceId)) ?? []
        let items = (try? await container.webSubmissionsRepository
            .listItemMap(formInstanceId: formInstanceId)) ?? []
        let registro = (try? await container.webSubmissionsRepository
            .listLedgerForForm(formInstanceId: formInstanceId)) ?? []
        let alumnado = (try? await container.classesRepository
            .listStudentsInClass(classId: instancia.classId)) ?? []
        let peerTargets = (try? await container.webSubmissionsRepository
            .listPeerTargets(formInstanceId: formInstanceId)) ?? []

        var studentIdByAlias: [String: Int64] = [:]
        for entrada in alias { studentIdByAlias[entrada.alias] = entrada.studentId }

        var itemIdByWebItemId: [String: String] = [:]
        for entrada in items { itemIdByWebItemId[entrada.webItemId] = entrada.itemId }

        var peerTargetMap: [String: Int64] = [:]
        for pt in peerTargets {
            peerTargetMap["\(pt.evaluatorAlias)|\(pt.targetAlias)"] = pt.targetStudentId
        }

        // Solo cuenta como duplicado lo que se importó de verdad. Una entrega
        // registrada como rechazada debe poder reintentarse: si el motivo era un
        // alias que faltaba, y el docente lo arregla, tiene que poder volver.
        var importedAt: [String: Int64] = [:]
        for entrada in registro where entrada.status == "IMPORTED" {
            importedAt[entrada.submissionId] = entrada.importedAtEpochMs
        }

        var nombres: [Int64: String] = [:]
        var roster: [WebRosterEntry] = []
        for alumno in alumnado {
            let nombre = "\(alumno.firstName) \(alumno.lastName)"
                .trimmingCharacters(in: .whitespaces)
            nombres[alumno.id] = nombre
            roster.append(WebRosterEntry(id: alumno.id, name: nombre))
        }
        roster.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return WebSubmissionSnapshot(
            formInstanceId: instancia.formInstanceId,
            classId: instancia.classId,
            columnId: instancia.columnId,
            privateKeyRef: instancia.privateKeyRef,
            revoked: instancia.revoked,
            expiresAtEpochMs: instancia.expiresAtEpochMs,
            title: instancia.title,
            studentIdByAlias: studentIdByAlias,
            itemIdByWebItemId: itemIdByWebItemId,
            studentNames: nombres,
            importedAtBySubmissionId: importedAt,
            roster: roster,
            mode: instancia.mode,
            peerTargetStudentIdByEvaluatorTarget: peerTargetMap
        )
    }

    /// Escribe las entregas aceptadas en el Cuaderno.
    ///
    /// **Pasa por `saveResponses`, nunca por SQL directo.** Es quien resume el
    /// estado de la celda (`0/7`, `Completo`), escribe `display_value`, deriva y
    /// guarda la nota, invalida el caché de la hoja y avisa a la interfaz. Un
    /// `INSERT` en `notebook_instrument_responses` dejaría la respuesta guardada
    /// pero sin nota y sin refrescar el Cuaderno.
    ///
    /// Para coevaluación con múltiples evaluaciones por alumno, agrupa las
    /// respuestas recibidas por celda e ítem y calcula la media aritmética simple
    /// de los valores numéricos/escalas antes de consolidar.
    func importWebSubmissions(
        _ decisions: [WebSubmissionImportDecision]
    ) async -> WebSubmissionImportOutcome {
        var resultado = WebSubmissionImportOutcome()
        let ahora = Int64(Date().timeIntervalSince1970 * 1000)
        let instant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: ahora)
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        struct TargetCellKey: Hashable {
            let classId: Int64
            let columnId: String
            let studentId: Int64
        }

        var decisionsByCell: [TargetCellKey: [WebSubmissionImportDecision]] = [:]
        for decision in decisions {
            let key = TargetCellKey(
                classId: decision.draft.classId,
                columnId: decision.draft.columnId,
                studentId: decision.studentId
            )
            decisionsByCell[key, default: []].append(decision)
        }

        for (cellKey, cellDecisions) in decisionsByCell {
            let primerBorrador = cellDecisions[0].draft
            let nombre = primerBorrador.studentName ?? "código \(primerBorrador.alias.prefix(6))"

            // Recolectar todas las respuestas agrupadas por itemId
            var answersByItemId: [String: [(answer: WebResolvedAnswer, draft: WebSubmissionDraft)]] = [:]
            for dec in cellDecisions {
                for ans in dec.draft.answers {
                    answersByItemId[ans.itemId, default: []].append((ans, dec.draft))
                }
            }

            var responses: [NotebookInstrumentResponse] = []
            for (itemId, answerPairs) in answersByItemId {
                guard !answerPairs.isEmpty else { continue }
                let itemType = answerPairs[0].answer.type

                var finalNumber: KotlinDouble?
                var finalText: String = ""
                var finalBool: KotlinBoolean?

                switch itemType {
                case .scale1To4, .number:
                    let numbers = answerPairs.compactMap { $0.answer.numberValue }
                    if !numbers.isEmpty {
                        let media = numbers.reduce(0.0, +) / Double(numbers.count)
                        finalNumber = KotlinDouble(value: media)
                        if media.truncatingRemainder(dividingBy: 1) == 0 {
                            finalText = String(Int(media))
                        } else {
                            finalText = String(format: "%.2f", media)
                        }
                    }
                case .check:
                    let bools = answerPairs.compactMap { $0.answer.boolValue }
                    if !bools.isEmpty {
                        let trues = bools.filter { $0 }.count
                        let majority = trues > (bools.count / 2)
                        finalBool = KotlinBoolean(value: majority)
                        finalText = majority ? "Sí" : "No"
                    }
                case .text, .choice:
                    let texts = answerPairs.compactMap { $0.answer.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if texts.count == 1 {
                        finalText = texts[0]
                    } else if texts.count > 1 {
                        finalText = texts.joined(separator: "\n")
                    }
                }

                responses.append(
                    NotebookInstrumentResponse(
                        classId: cellKey.classId,
                        studentId: cellKey.studentId,
                        columnId: cellKey.columnId,
                        itemId: itemId,
                        textValue: finalText,
                        boolValue: finalBool,
                        numberValue: finalNumber,
                        trace: AuditTrace(
                            authorUserId: nil,
                            createdAt: instant,
                            updatedAt: instant,
                            associatedGroupId: nil,
                            deviceId: nil,
                            syncVersion: 1
                        )
                    )
                )
            }

            do {
                _ = try await container.notebookInstrumentsRepository.saveResponses(
                    classId: cellKey.classId,
                    studentId: cellKey.studentId,
                    columnId: cellKey.columnId,
                    responses: responses,
                    updatedAtEpochMs: ahora,
                    deviceId: nil,
                    syncVersion: 1
                )

                // Registrar en el ledger cada una de las entregas que contribuyeron a esta celda
                for dec in cellDecisions {
                    let borrador = dec.draft
                    let clientEpoch = iso8601.date(from: borrador.clientSubmittedAt)
                        .map { Int64($0.timeIntervalSince1970 * 1000) } ?? ahora
                    try? await container.webSubmissionsRepository.recordLedgerEntry(
                        entry: WebLedgerEntry(
                            submissionId: borrador.submissionId,
                            formInstanceId: borrador.formInstanceId,
                            alias: borrador.alias,
                            studentId: KotlinLong(value: cellKey.studentId),
                            status: "IMPORTED",
                            rejectReason: nil,
                            answerCount: Int64(borrador.answers.count),
                            clientSubmittedAtEpochMs: clientEpoch,
                            importedAtEpochMs: ahora
                        )
                    )
                }
                resultado.imported += cellDecisions.count
            } catch {
                resultado.failures.append(
                    (studentName: nombre, reason: error.localizedDescription)
                )
            }
        }

        if resultado.imported > 0 {
            refreshCurrentNotebook()
        }

        return resultado
    }

#if DEBUG
    /// Monta a mano un formulario de prueba: columna con instrumento, plantilla con
    /// sus ítems, registro del formulario, mapa de ítems y un alias asignado.
    ///
    /// **Solo DEBUG y solo hasta que exista la publicación de formularios.** Sin
    /// esto el circuito no se puede ver funcionando, porque nada crea todavía un
    /// `formInstanceId` ni una fila de alias. Cuando la app sepa publicar, este
    /// método y `WebSubmissionTestBenchView` se borran juntos.
    func prepareWebSubmissionTestForm(
        formInstanceId: String,
        title: String,
        recipientPublicKey: String,
        publisherPublicKey: String?,
        manifestJson: String,
        items: [(webItemId: String, title: String, type: WebManifestItemType, options: [String])],
        alias: String
    ) async throws -> WebSubmissionTestFormResult {
        if classes.isEmpty { try await refreshClasses() }
        guard let clase = classes.first else {
            throw NSError(
                domain: "WebSubmissions",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Crea primero un grupo con alumnado."]
            )
        }
        let classId = clase.id

        let alumnado = try await container.classesRepository.listStudentsInClass(classId: classId)
        guard let primero = alumnado.first else {
            throw NSError(
                domain: "WebSubmissions",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "El grupo \(clase.name) no tiene alumnado."]
            )
        }

        let ahora = Int64(Date().timeIntervalSince1970 * 1000)
        let instant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: ahora)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: instant,
            updatedAt: instant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )

        // Columna estable por formulario: repetir la preparación no crea columnas
        // nuevas, y así se puede pulsar el botón varias veces sin ensuciar el
        // Cuaderno.
        let columnId = "COL_WEB_\(formInstanceId.prefix(8))"
        let tabs = try await container.notebookConfigRepository.listTabs(classId: classId)
        let tabIds = selectedNotebookTabId.map { [$0] } ?? tabs.first.map { [$0.id] } ?? []

        let column = NotebookColumnDefinition(
            id: columnId,
            title: "Entregas web (prueba)",
            type: .text,
            categoryKind: .evaluation,
            instrumentKind: .learningSituation,
            inputKind: .text,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: 0,
            dateEpochMs: KotlinLong(value: ahora),
            unitOrSituation: title,
            competencyCriteriaIds: [],
            scaleKind: .custom,
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: "0F766E",
            iconName: "tray.and.arrow.down",
            order: -1,
            widthDp: 160,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: false,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)

        let templateId = "template_\(columnId)"
        let plantillaItems: [NotebookInstrumentItem] = items.enumerated().map { indice, item in
            NotebookInstrumentItem(
                id: "item_\(columnId)_\(item.webItemId)",
                templateId: templateId,
                key: item.webItemId,
                title: item.title,
                type: Self.instrumentItemType(from: item.type),
                // Sin esto, una pregunta de elección se guardaba sin opciones y
                // luego el publicador la rechazaba con razón: no se puede elegir
                // entre nada.
                options: item.options,
                required: true,
                order: Int32(indice),
                helpText: nil,
                trace: trace
            )
        }
        try await container.notebookInstrumentsRepository.saveTemplate(
            template: NotebookInstrumentTemplate(
                id: templateId,
                classId: classId,
                columnId: columnId,
                evaluationId: nil,
                title: title,
                kind: .form,
                inputKind: .text,
                source: "WEB_TEST_BENCH",
                trace: trace
            ),
            items: plantillaItems
        )

        try await container.webSubmissionsRepository.saveFormInstance(
            instance: WebFormInstance(
                formInstanceId: formInstanceId,
                classId: classId,
                columnId: columnId,
                templateId: templateId,
                title: title,
                recipientPublicKey: recipientPublicKey,
                privateKeyRef: WebSubmissionKeychain.reference(for: formInstanceId),
                publisherPublicKey: publisherPublicKey,
                expiresAtEpochMs: ahora + 365 * 24 * 60 * 60 * 1000,
                revoked: false,
                archived: false,
                manifestJson: manifestJson,
                mode: "self",
                createdAtEpochMs: ahora,
                updatedAtEpochMs: ahora
            )
        )

        try await container.webSubmissionsRepository.saveItemMap(
            formInstanceId: formInstanceId,
            entries: items.map { item in
                WebItemMapEntry(
                    webItemId: item.webItemId,
                    itemId: "item_\(columnId)_\(item.webItemId)",
                    itemType: item.type.rawValue
                )
            }
        )

        try await container.webSubmissionsRepository.saveAliases(
            formInstanceId: formInstanceId,
            entries: [
                WebAliasEntry(alias: alias, studentId: primero.id, createdAtEpochMs: ahora)
            ]
        )

        refreshCurrentNotebook()

        return WebSubmissionTestFormResult(
            classId: classId,
            columnId: columnId,
            studentName: "\(primero.firstName) \(primero.lastName)".trimmingCharacters(in: .whitespaces)
        )
    }

    private static func instrumentItemType(from tipo: WebManifestItemType) -> NotebookInstrumentItemType {
        switch tipo {
        case .check: return .check
        case .text: return .text
        case .number: return .number
        case .scale1To4: return .scale14
        case .choice: return .choice
        }
    }
#endif

}
