import SwiftUI
import MiGestorKit

/// Inscripción al torneo con un formulario de entregas web: crear el formulario,
/// enviar los enlaces por correo, importar las respuestas y formar las parejas.
///
/// La lógica (nombres, parejas, traducción de respuestas) vive en `TournamentRegistration`;
/// aquí solo se enseña y se guarda en el torneo con `store.mutate`.
struct SdaTournamentRegistrationSheet: View {
    @ObservedObject var store: SdaTournamentStore
    let className: String

    /// Referencia sin suscripción: esta vista solo llama acciones del bridge.
    @Environment(\.kmpBridgeReference) private var bridgeReference
    private var bridge: KmpBridge { bridgeReference! }
    @Environment(\.dismiss) private var dismiss
    @AppStorage("webSubmissions.baseURL") private var baseURL = "https://projectosef.alwaysdata.net"
    @AppStorage("webSubmissions.deliveryEmail") private var deliveryEmail = ""

    @State private var students: [Student] = []
    @State private var expiresAt = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var isPublishing = false
    @State private var manifestToUpload: String?
    @State private var showingMail = false
    @State private var showingPicker = false
    @State private var importMessage: String?
    @State private var errorMessage: String?
    @State private var pairing: TournamentPairingResult?
    @State private var isCollecting = false
    @State private var inboxFingerprint: String? = WebSubmissionInbox.accountKey.map(WebSubmissionInbox.fingerprint)
    @State private var isConfirmingCreate = false
    @State private var placementDraft: PlacementPlanInput?
    @State private var isShowingExtend = false
    @State private var newExpiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    private var registration: TournamentRegistration? { store.plan.registration }

    var body: some View {
        NavigationStack {
            Form {
                if let registration {
                    sendSection(registration)
                    responsesSection(registration)
                    pairsSection
                    if store.plan.format == .leaguePlacement, let pairing {
                        placementPlan(pairCount: pairing.pairs.count)
                    }
                } else {
                    publishSection
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Inscripción")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .task {
            await loadStudents()
            await collectFromInbox()
        }
        .sheet(isPresented: $showingMail) {
            if let registration {
                WebSubmissionLinkEmailSheet(task: taskInfo(registration), links: links(registration))
            }
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.mgsub], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .confirmationDialog(
            "¿Crear los equipos?",
            isPresented: $isConfirmingCreate,
            titleVisibility: .visible
        ) {
            Button("Crear equipos y calendario") { createTeams() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(store.plan.savedSchedule.isEmpty
                 ? "Se crea el calendario con estas parejas."
                 : "Se sustituyen los equipos y se borran el calendario y los resultados actuales.")
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    // MARK: Crear el formulario

    @ViewBuilder
    private var publishSection: some View {
        Section {
            Text("Cada alumno de \(className) recibe un enlace. Elige si participa y con quién, de una lista con los nombres de su curso.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DatePicker("Plazo hasta", selection: $expiresAt, in: Date()..., displayedComponents: .date)
            TextField("Correo donde llegan las respuestas", text: $deliveryEmail)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
            Button {
                Task { await publish() }
            } label: {
                Label(isPublishing ? "Creando…" : "Crear formulario", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPublishing || students.count < 2 || baseURL.isEmpty)
        } header: {
            Text("Formulario de inscripción")
        } footer: {
            Text("La lista muestra nombre y primer apellido. Solo la ven quienes tienen un enlace de este curso.")
        }
        inboxSection
    }

    /// Envío directo: la web deja las respuestas en el buzón y la app las recoge sola.
    private var inboxSection: some View {
        Section {
            if let inboxFingerprint {
                Label("Activado en este dispositivo", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                DisclosureGroup("Huella para el servidor") {
                    Text(inboxFingerprint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } else {
                Button {
                    inboxFingerprint = WebSubmissionInbox.ensureAccountKey()
                    if inboxFingerprint == nil { errorMessage = "No se pudo guardar la clave del buzón en el llavero." }
                } label: {
                    Label("Activar envío directo", systemImage: "tray.and.arrow.down")
                        .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Envío directo")
        } footer: {
            Text("Con el envío directo, las respuestas llegan solas a la app. Sin él, el alumnado las manda por correo y tú importas los ficheros. La huella no es secreta: es lo que se instala en el servidor.")
        }
    }

    // MARK: Enviar

    private func sendSection(_ registration: TournamentRegistration) -> some View {
        Section("Enlaces") {
            Button {
                showingMail = true
            } label: {
                Label("Enviar enlaces por correo", systemImage: "envelope")
                    .frame(minHeight: 44)
            }
            if let manifestToUpload {
                Label("Sube este fichero a la web antes de enviar: \(manifestToUpload)", systemImage: "arrow.up.doc")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            let deadline = Date(timeIntervalSince1970: Double(registration.expiresAtEpochMs) / 1000)
            LabeledContent("Plazo") {
                Text(deadline.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(deadline < Date() ? .red : .secondary)
            }
            extendControls(registration)
        }
    }

    /// Ampliar plazo: el plazo va firmado en el enlace, así que se publica otro formulario
    /// solo para quien no ha respondido. Lo ya recibido se conserva.
    @ViewBuilder
    private func extendControls(_ registration: TournamentRegistration) -> some View {
        let pending = registration.pendingStudentIds(rosterIds: rosterIds)
        if isShowingExtend {
            DatePicker("Nuevo plazo", selection: $newExpiresAt, in: Date()..., displayedComponents: .date)
            Button {
                Task { await extend(registration, pending: pending) }
            } label: {
                Label(isPublishing ? "Creando…" : "Crear enlace nuevo para quien falta (\(pending.count))",
                      systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPublishing || pending.isEmpty || baseURL.isEmpty)
            Text("Quien ya respondió no recibe nada. Sus respuestas se conservan.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if !pending.isEmpty {
            Button {
                isShowingExtend = true
            } label: {
                Label("Ampliar plazo", systemImage: "calendar.badge.clock")
                    .frame(minHeight: 44)
            }
        }
    }

    // MARK: Respuestas

    private func responsesSection(_ registration: TournamentRegistration) -> some View {
        let result = currentPairing(registration)
        let participants = registration.entries.values.filter(\.participates).count
        return Section {
            if registration.inboxURL != nil {
                Button {
                    Task { await collectFromInbox() }
                } label: {
                    Label(isCollecting ? "Comprobando…" : "Comprobar respuestas nuevas", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
                .disabled(isCollecting)
            }
            Button {
                showingPicker = true
            } label: {
                Label(registration.inboxURL != nil ? "Importar ficheros del correo" : "Importar respuestas", systemImage: "tray.and.arrow.down")
                    .frame(minHeight: 44)
            }
            if let importMessage {
                Text(importMessage).font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Se apuntan", value: "\(participants)")
            LabeledContent("No participan", value: "\(result.declined.count)")
            if !result.notResponded.isEmpty {
                DisclosureGroup("Sin responder (\(result.notResponded.count))") {
                    ForEach(result.notResponded, id: \.self) { Text(name($0)) }
                }
            }
        } header: {
            Text("Respuestas")
        } footer: {
            Text("Guarda los ficheros .mgsub que llegan al correo y elígelos aquí. Puedes importar varias veces.")
        }
    }

    // MARK: Parejas

    @ViewBuilder
    private var pairsSection: some View {
        if let pairing {
            Section {
                ForEach(pairing.pairs) { pair in
                    HStack(spacing: 8) {
                        memberMenu(pair.first)
                        Text("y").foregroundStyle(.secondary)
                        memberMenu(pair.second)
                        Spacer(minLength: 8)
                        if pair.isMutual {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                                .accessibilityLabel("Se eligieron mutuamente")
                        } else {
                            Image(systemName: "shuffle")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Pareja asignada por la app")
                        }
                    }
                }
                if let leftOver = pairing.leftOver {
                    Label("\(name(leftOver)) se queda sin pareja. Cámbialo con alguien o déjalo fuera.", systemImage: "person.fill.questionmark")
                        .foregroundStyle(.orange)
                }
                Button {
                    if let registration { self.pairing = currentPairing(registration) }
                } label: {
                    Label("Volver a sortear las sueltas", systemImage: "shuffle")
                }
                Button {
                    isConfirmingCreate = true
                } label: {
                    Label("Crear equipos y calendario", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreateTeams(pairCount: pairing.pairs.count))
            } header: {
                Text("Parejas (\(pairing.pairs.count))")
            } footer: {
                if store.plan.format == .leaguePlacement, !canCreateTeams(pairCount: pairing.pairs.count) {
                    Text("Con estas parejas no da tiempo. Abajo tienes qué puedes cambiar.")
                } else {
                    Text("Toca un nombre para cambiarlo por otro inscrito.")
                }
            }
        } else if let registration, registration.entries.values.contains(where: \.participates) {
            Section {
                Button {
                    pairing = currentPairing(registration)
                } label: {
                    Label("Formar parejas", systemImage: "person.2")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text("Se respetan las parejas que se eligieron mutuamente. El resto se sortea.")
            }
        }
    }

    private func canCreateTeams(pairCount: Int) -> Bool {
        guard store.plan.format == .leaguePlacement else { return pairCount >= 2 }
        var input = placementInput
        input.teamCount = pairCount
        return PlacementPlanner.calculate(input)?.fits == true
    }

    /// Ajustes en curso. No se guardan hasta crear los equipos: el calendario que ya exista
    /// se hizo con los anteriores y cambiarlos sin regenerarlo descuadraría el cuadro.
    private var placementInput: PlacementPlanInput {
        placementDraft ?? store.plan.placementInput
    }

    private func placementBinding<Value>(_ keyPath: WritableKeyPath<PlacementPlanInput, Value>) -> Binding<Value> {
        Binding(
            get: { placementInput[keyPath: keyPath] },
            set: { value in
                var draft = placementInput
                draft[keyPath: keyPath] = value
                placementDraft = draft
            }
        )
    }

    /// Liguilla + puestos: se recalcula con las parejas que se han apuntado de verdad.
    private func placementPlan(pairCount: Int) -> some View {
        SdaPlacementPlanSections(
            fixedTeamCount: pairCount,
            matchMinutes: placementBinding(\.matchMinutes),
            totalMinutes: placementBinding(\.totalMinutes),
            venueCount: placementBinding(\.venueCount),
            transitionMinutes: placementBinding(\.transitionMinutes),
            placementRounds: placementBinding(\.placementRounds)
        )
    }

    /// Cambiar a un alumno por otro inscrito: si el otro ya está en una pareja, se intercambian.
    private func memberMenu(_ studentId: String) -> some View {
        Menu(name(studentId)) {
            ForEach(participantIds.filter { $0 != studentId }, id: \.self) { other in
                Button(name(other)) { swap(studentId, with: other) }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
    }

    private func swap(_ a: String, with b: String) {
        guard var result = pairing else { return }
        func replace(_ id: String) -> String { id == a ? b : (id == b ? a : id) }
        result.pairs = result.pairs.map { pair in
            var copy = pair
            copy.first = replace(pair.first)
            copy.second = replace(pair.second)
            if copy != pair { copy.isMutual = false; copy.teamName = nil }
            return copy
        }
        result.leftOver = result.leftOver.map(replace)
        pairing = result
    }

    // MARK: Datos

    private var rosterIds: [String] { students.map { String($0.id) } }

    private var participantIds: [String] {
        (registration?.entries.values.filter(\.participates).map(\.studentId) ?? [])
            .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }

    private func name(_ studentId: String) -> String {
        students.first { String($0.id) == studentId }.map { "\($0.firstName) \($0.lastName)" } ?? "Alumno"
    }

    private func currentPairing(_ registration: TournamentRegistration) -> TournamentPairingResult {
        TournamentPairing.pair(entries: Array(registration.entries.values), rosterIds: rosterIds)
    }

    private func loadStudents() async {
        do {
            students = try await bridge.students(forClassId: store.record.classId)
        } catch {
            errorMessage = "No se pudo cargar el alumnado del curso."
        }
    }

    private func taskInfo(_ registration: TournamentRegistration) -> WebSubmissionTaskInfo {
        WebSubmissionTaskInfo(
            formInstanceId: registration.formInstanceId,
            classId: store.record.classId,
            groupName: className,
            title: "Inscripción: \(store.plan.name)",
            columnTitle: store.plan.name,
            status: .active,
            isArchived: false,
            expiresAtEpochMs: registration.expiresAtEpochMs,
            importedCount: registration.entries.count,
            lastImportedAtEpochMs: nil
        )
    }

    private func links(_ registration: TournamentRegistration) -> [WebPublishedStudentLink] {
        students.compactMap { student in
            guard let text = registration.linkByStudentId[String(student.id)], let url = URL(string: text) else { return nil }
            return WebPublishedStudentLink(
                studentId: student.id,
                studentName: "\(student.firstName) \(student.lastName)",
                email: student.email,
                url: url
            )
        }
        .sorted { $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending }
    }

    // MARK: Acciones

    private func publish() async {
        errorMessage = nil
        isPublishing = true
        defer { isPublishing = false }
        do {
            let published = try await TournamentRegistration.publish(
                tournamentName: store.plan.name,
                students: students.map { (id: $0.id, firstName: $0.firstName, lastName: $0.lastName) },
                baseURL: baseURL,
                deliveryEmail: deliveryEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                expiresAt: expiresAt
            )
            store.mutate { $0.registration = published.registration }
            manifestToUpload = published.isSelfContained ? nil : published.manifestPath
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "No se pudo crear el formulario."
        }
    }

    /// Publica un formulario nuevo para quien falta. Si algo falla, el torneo queda como estaba.
    private func extend(_ current: TournamentRegistration, pending: [String]) async {
        errorMessage = nil
        isPublishing = true
        defer { isPublishing = false }
        do {
            let published = try await TournamentRegistration.publish(
                tournamentName: store.plan.name,
                students: students.map { (id: $0.id, firstName: $0.firstName, lastName: $0.lastName) },
                baseURL: baseURL,
                deliveryEmail: deliveryEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                expiresAt: newExpiresAt,
                linkStudentIds: Set(pending.compactMap { Int64($0) })
            )
            // Se parte de lo guardado ahora, por si entró alguna respuesta mientras se publicaba.
            let latest = registration ?? current
            store.mutate { $0.registration = latest.extended(with: published.registration) }
            manifestToUpload = published.isSelfContained ? nil : published.manifestPath
            isShowingExtend = false
            showingMail = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "No se pudo ampliar el plazo."
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        errorMessage = nil
        guard case .success(let urls) = result, var form = registration else { return }
        var files: [(name: String, data: Data)] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { files.append((name: url.lastPathComponent, data: data)) }
        }
        _ = importData(files, into: &form)
    }

    /// Valida y guarda unas entregas. Cada fichero se prueba con cada formulario (el actual
    /// y los de plazos anteriores). Devuelve la vista previa para saber qué se aceptó.
    private func importData(
        _ files: [(name: String, data: Data)],
        into form: inout TournamentRegistration
    ) -> WebSubmissionImportPreview {
        let names = Dictionary(
            students.map { ($0.id, "\($0.firstName) \($0.lastName)") },
            uniquingKeysWith: { first, _ in first }
        )
        var preview = WebSubmissionImportPreview()
        // Nombres únicos: con ellos se sabe qué ficheros rechazó un formulario para probar el siguiente.
        var remaining = files.enumerated().map { (name: "\($0.offset + 1). \($0.element.name)", data: $0.element.data) }
        for round in form.allForms {
            guard let manifest = round.manifest, !remaining.isEmpty else { continue }
            let snapshot = round.snapshot(classId: store.record.classId, title: store.plan.name, studentNames: names)
            let partial = WebSubmissionImportService(resolver: WebSubmissionSnapshotResolver(snapshot: snapshot))
                .preview(files: remaining, manifest: manifest)
            preview.drafts += partial.drafts
            preview.alreadyImported += partial.alreadyImported
            let rejected = Set(partial.rejections.map(\.fileName))
            remaining = remaining.filter { rejected.contains($0.name) }
            preview.rejections = partial.rejections
        }
        let added = form.absorb(preview.drafts)
        store.mutate { $0.registration = form }
        pairing = nil

        var parts = ["\(added) \(added == 1 ? "respuesta importada" : "respuestas importadas")"]
        if !preview.alreadyImported.isEmpty { parts.append("\(preview.alreadyImported.count) ya estaban") }
        if !preview.rejections.isEmpty { parts.append("\(preview.rejections.count) no son de este torneo o no se pueden leer") }
        importMessage = parts.joined(separator: " · ") + "."
        return preview
    }

    /// Recoge del buzón, importa y borra del servidor lo ya importado.
    /// Recorre el buzón de cada formulario (el actual y los de plazos anteriores).
    private func collectFromInbox() async {
        guard !isCollecting, let current = registration, !students.isEmpty else { return }
        let rounds = current.allForms.filter { $0.inboxURL != nil }
        guard !rounds.isEmpty else { return }
        isCollecting = true
        defer { isCollecting = false }
        var anyToken = false
        var anyNew = false
        for round in rounds {
            guard let url = round.inboxURL,
                  let readToken = WebSubmissionInbox.loadToken(
                    name: WebSubmissionInbox.readTokenName(formInstanceId: round.formInstanceId)
                  ) else { continue }
            anyToken = true
            let client = WebSubmissionInboxClient(url: url)
            do {
                let collected = try await client.collect(formInstanceId: round.formInstanceId, readToken: readToken)
                guard !collected.isEmpty, var form = registration else { continue }
                anyNew = true
                let preview = importData(
                    collected.map { (name: "buzón \($0.alias.prefix(6))", data: $0.data) },
                    into: &form
                )
                // Se borra lo que ya está en la app (nuevo o repetido). Lo rechazado se queda para revisarlo.
                let kept = Set(preview.drafts.map(\.submissionId) + preview.alreadyImported.map(\.submissionId))
                try await client.delete(
                    formInstanceId: round.formInstanceId,
                    readToken: readToken,
                    entries: collected.filter { kept.contains($0.submissionId) }.map { ($0.alias, $0.submissionId) }
                )
            } catch {
                importMessage = (error as? LocalizedError)?.errorDescription ?? "No se pudo comprobar el buzón."
                return
            }
        }
        if !anyToken {
            importMessage = "Las respuestas directas solo se recogen en el dispositivo que creó el formulario."
        } else if !anyNew {
            importMessage = "No hay respuestas nuevas."
        }
    }

    private func createTeams() {
        guard let pairing else { return }
        let names = Dictionary(
            students.map { (String($0.id), $0.firstName) },
            uniquingKeysWith: { first, _ in first }
        )
        let teams = TournamentPairing.teams(from: pairing.pairs, names: names)
        do {
            try store.mutateThrowing { plan in
                plan.replaceTeams(teams)
                if plan.format == .leaguePlacement, let draft = placementDraft {
                    plan.matchDurationMinutes = draft.matchMinutes
                    plan.transitionMinutes = draft.transitionMinutes
                    plan.venueCount = draft.venueCount
                    plan.totalTimeMinutes = draft.totalMinutes
                    plan.placementRounds = draft.placementRounds
                }
                plan.persistSchedule(try plan.generatedRounds())
            }
            dismiss()
        } catch {
            errorMessage = "No se pudo crear el calendario con estas parejas."
        }
    }
}
