import SwiftUI
import UniformTypeIdentifiers

/// Previsualización de las entregas del alumnado hechas desde la PWA.
///
/// Patrón adaptativo canónico del proyecto (dos zonas con `ViewThatFits`, fallback
/// apilado, detents en iOS y frame solo en macOS), tomando como referencia
/// `ScheduleImportPreviewSheet`, que resuelve el mismo problema: revisar un lote
/// antes de escribirlo.
///
/// Reparte el lote en tres cubos, y el orden importa: primero lo que se va a
/// escribir, luego lo que necesita una decisión del docente, y al final lo que se
/// ignora. Nada se escribe hasta pulsar Importar.
struct WebSubmissionImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let formTitle: String
    let preview: WebSubmissionImportPreview
    /// Alumnado del grupo, para poder asignar a mano una entrega cuyo código no
    /// esté en la tabla de alias.
    let roster: [WebRosterEntry]
    let isImporting: Bool
    let onConfirm: ([WebSubmissionImportDecision]) -> Void
    /// Metadatos de cada formulario presente en un lote mixto.
    let taskInfoByFormInstanceId: [String: WebSubmissionTaskInfo]
    /// Roster aislado por formulario para que dos grupos puedan asignarse en el
    /// mismo lote sin mezclar alumnos.
    let rosterByFormInstanceId: [String: [WebRosterEntry]]

    /// Asignaciones manuales que ha hecho el docente, por `submissionId`.
    @State private var manualAssignments: [String: Int64] = [:]

    init(
        formTitle: String,
        preview: WebSubmissionImportPreview,
        roster: [WebRosterEntry],
        isImporting: Bool,
        onConfirm: @escaping ([WebSubmissionImportDecision]) -> Void,
        taskInfoByFormInstanceId: [String: WebSubmissionTaskInfo] = [:],
        rosterByFormInstanceId: [String: [WebRosterEntry]] = [:]
    ) {
        self.formTitle = formTitle
        self.preview = preview
        self.roster = roster
        self.isImporting = isImporting
        self.onConfirm = onConfirm
        self.taskInfoByFormInstanceId = taskInfoByFormInstanceId
        self.rosterByFormInstanceId = rosterByFormInstanceId
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                content
                    .padding(24)
            }

            Divider()
            footer
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 620)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Composición

    @ViewBuilder
    private var content: some View {
        ViewThatFits(in: .horizontal) {
            // Ancho regular: resumen a la izquierda, lote a la derecha.
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    writeTargetCard
                }
                // Ancho flexible en vez de fijo: mantiene la proporción de las dos
                // zonas sin reintroducir el ancho rígido que ya cortó controles en
                // la previsualización de horario.
                .frame(minWidth: 264, idealWidth: 304, maxWidth: 340, alignment: .topLeading)

                buckets
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 664, alignment: .topLeading)

            // Compacto: todo apilado, sin perder ninguna acción.
            VStack(alignment: .leading, spacing: 18) {
                summary
                writeTargetCard
                buckets
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.teal)
                .frame(width: 48, height: 48)
                .background(.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Entregas del alumnado")
                    .font(.title2.weight(.bold))
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: - Resumen

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    metricTiles
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 116), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    metricTiles
                }
            }

            if pendingAssignmentCount > 0 {
                Label(
                    "\(pendingAssignmentCount) entrega(s) sin asignar. Elige a quién pertenece cada una o quedarán fuera.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var metricTiles: some View {
        metric("Se importan", "\(readyDecisions.count)")
        metric("Sin asignar", "\(pendingAssignmentCount)")
        metric("Rechazadas", "\(preview.rejections.count)")
        metric("Repetidas", "\(preview.alreadyImported.count)")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dice exactamente qué se va a escribir y qué no. La nota no se escribe aquí:
    /// la deriva la app al guardar, y conviene que el docente lo sepa antes de
    /// pulsar, para que no busque una nota que aparecerá sola.
    @ViewBuilder
    private var writeTargetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qué se va a escribir")
                .font(.headline)

            Text("Las respuestas del alumnado en la columna de esta situación de aprendizaje.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("La nota la calcula la app al guardar, no viene del navegador.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !preview.alreadyImported.isEmpty {
                Text("Las repetidas se ignoran: ya se importaron antes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Los tres cubos

    @ViewBuilder
    private var buckets: some View {
        VStack(alignment: .leading, spacing: 20) {
            if preview.isEmpty {
                emptyState
            }

            if !preview.drafts.isEmpty {
                bucket(
                    title: "Listas para importar",
                    count: preview.drafts.count,
                    tint: .green
                ) {
                    ForEach(draftGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                            if let subtitle = group.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(group.drafts) { draft in
                                draftRow(draft)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !preview.rejections.isEmpty {
                bucket(
                    title: "No se pueden importar",
                    count: preview.rejections.count,
                    tint: .red
                ) {
                    ForEach(preview.rejections) { rejection in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rejection.fileName)
                                .font(.subheadline.weight(.semibold))
                            Text(rejection.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !preview.alreadyImported.isEmpty {
                bucket(
                    title: "Ya importadas",
                    count: preview.alreadyImported.count,
                    tint: .secondary
                ) {
                    ForEach(preview.alreadyImported) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.fileName)
                                .font(.subheadline.weight(.semibold))
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            Text(Self.shortDate(item.importedAtEpochMs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No hay nada que revisar")
                .font(.headline)
            Text("No se ha seleccionado ningún fichero de entrega.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func bucket<Content: View>(
        title: String,
        count: Int,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .layoutPriority(1)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.16), in: Capsule())
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Fila de una entrega

    @ViewBuilder
    private func draftRow(_ draft: WebSubmissionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Nombre y progreso en una fila que se puede comprimir: sin
            // `.fixedSize()` en horizontal, para que no desborde el sheet.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayName(for: draft))
                    .font(.subheadline.weight(.semibold))
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text("\(draft.requiredAnswered)/\(draft.requiredTotal)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(draft.requiredAnswered == draft.requiredTotal ? .green : .orange)
            }

            Text("\(draft.answers.count) respuesta(s) · código \(draft.alias.prefix(6))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.needsManualAssignment {
                assignmentPicker(for: draft)
            }

            if !draft.missingRequiredTitles.isEmpty {
                DisclosureGroup {
                    Text(draft.missingRequiredTitles.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text("\(draft.missingRequiredTitles.count) apartado(s) sin responder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Un código sin asignar no descarta la entrega: se pregunta. Tirar trabajo
    /// del alumnado por una fila que falta en la tabla de alias sería el peor
    /// comportamiento posible.
    private func assignmentPicker(for draft: WebSubmissionDraft) -> some View {
        Picker(
            "Asignar a",
            selection: Binding(
                get: { manualAssignments[draft.submissionId] ?? -1 },
                set: { nuevo in
                    if nuevo < 0 {
                        manualAssignments.removeValue(forKey: draft.submissionId)
                    } else {
                        manualAssignments[draft.submissionId] = nuevo
                    }
                }
            )
        ) {
            Text("Sin asignar").tag(Int64(-1))
            ForEach(availableRoster(for: draft)) { entry in
                Text(entry.name).tag(entry.id)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
    }

    /// Quita del selector al alumnado ya asignado a otra entrega del mismo lote:
    /// dos entregas no pueden ser de la misma persona, y la base de datos lo
    /// impide con un UNIQUE, así que es mejor no ofrecerlo que fallar al guardar.
    private func availableRoster(for draft: WebSubmissionDraft) -> [WebRosterEntry] {
        let tomados = Set(
            preview.drafts
                .filter { $0.formInstanceId == draft.formInstanceId && $0.submissionId != draft.submissionId }
                .compactMap { $0.studentId ?? manualAssignments[$0.submissionId] }
        )

        let roster = rosterByFormInstanceId[draft.formInstanceId] ?? self.roster
        return roster.filter { !tomados.contains($0.id) || manualAssignments[draft.submissionId] == $0.id }
    }

    private func displayName(for draft: WebSubmissionDraft) -> String {
        if let nombre = draft.studentName { return nombre }
        if let asignado = manualAssignments[draft.submissionId],
           let entry = (rosterByFormInstanceId[draft.formInstanceId] ?? roster)
            .first(where: { $0.id == asignado }) {
            return entry.name
        }
        return "Sin asignar"
    }

    private var headerSubtitle: String {
        if taskInfoByFormInstanceId.count == 1 {
            return taskInfoByFormInstanceId.values.first?.displayTitle ?? formTitle
        }
        if taskInfoByFormInstanceId.count > 1 {
            return "\(taskInfoByFormInstanceId.count) tareas de varios grupos"
        }
        return formTitle
    }

    private var draftGroups: [WebSubmissionDraftGroup] {
        Dictionary(grouping: preview.drafts, by: \.formInstanceId)
            .map { formInstanceId, drafts in
                let info = taskInfoByFormInstanceId[formInstanceId]
                return WebSubmissionDraftGroup(
                    id: formInstanceId,
                    title: info?.displayTitle ?? drafts.first?.formInstanceId ?? formTitle,
                    subtitle: info.map { "\($0.columnTitle) · \($0.statusLabel)" },
                    drafts: drafts
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Pie

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(readyDecisions.count) entrega(s) se importarán")
                    .font(.subheadline.weight(.semibold))
                if pendingAssignmentCount > 0 {
                    Text("\(pendingAssignmentCount) quedarán fuera por no estar asignadas")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)
                .disabled(isImporting)

            Button {
                onConfirm(readyDecisions)
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Importar")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isImporting || readyDecisions.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Derivados

    /// Solo se pueden importar las entregas con alumno resuelto: sin `studentId`
    /// no hay dónde escribir.
    private var readyDecisions: [WebSubmissionImportDecision] {
        preview.drafts.compactMap { draft in
            guard let studentId = draft.studentId ?? manualAssignments[draft.submissionId] else {
                return nil
            }
            return WebSubmissionImportDecision(draft: draft, studentId: studentId)
        }
    }

    private var pendingAssignmentCount: Int {
        preview.drafts.filter { draft in
            draft.studentId == nil && manualAssignments[draft.submissionId] == nil
        }
        .count
    }

    private static func shortDate(_ epochMs: Int64) -> String {
        let fecha = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        let formato = DateFormatter()
        formato.dateStyle = .short
        formato.timeStyle = .short
        return formato.string(from: fecha)
    }
}

// MARK: - Modelos de apoyo

struct WebRosterEntry: Identifiable, Hashable {
    let id: Int64
    let name: String
}

private struct WebSubmissionDraftGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let drafts: [WebSubmissionDraft]
}

/// Una entrega con su destinatario ya decidido. Es lo que sale del sheet hacia
/// quien vaya a llamar a `saveResponses`.
struct WebSubmissionImportDecision {
    let draft: WebSubmissionDraft
    let studentId: Int64
}

// MARK: - Selector de ficheros

/// Envoltura que abre el selector de `.mgsub`, examina lo elegido con
/// `WebSubmissionImportService` y presenta la previsualización.
///
/// Va aquí y no dentro del sheet para que el sheet siga siendo una vista tonta:
/// recibe un lote ya examinado y no sabe nada de ficheros ni de criptografía, lo
/// que permite previsualizarlo y probarlo sin tocar disco.
struct WebSubmissionImportButton: View {
    let formTitle: String
    let manifest: WebFormManifest
    let service: WebSubmissionImportService
    let roster: [WebRosterEntry]
    let isImporting: Bool
    let onConfirm: ([WebSubmissionImportDecision]) -> Void

    @State private var showingPicker = false
    @State private var preview: WebSubmissionImportPreview?
    @State private var readError: String?

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Importar entregas del alumnado", systemImage: "tray.and.arrow.down")
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.mgsub],
            allowsMultipleSelection: true
        ) { resultado in
            handle(resultado)
        }
        .sheet(item: $preview) { lote in
            WebSubmissionImportSheet(
                formTitle: formTitle,
                preview: lote,
                roster: roster,
                isImporting: isImporting,
                onConfirm: onConfirm
            )
        }
        // Binding calculado y no `.constant(...)`: con una constante, cerrar la
        // alerta no limpia el error y vuelve a saltar sola.
        .alert(
            "No se pudo leer",
            isPresented: Binding(
                get: { readError != nil },
                set: { visible in if !visible { readError = nil } }
            )
        ) {
            Button("Entendido") { readError = nil }
        } message: {
            Text(readError ?? "")
        }
    }

    private func handle(_ resultado: Result<[URL], Error>) {
        switch resultado {
        case .failure(let error):
            readError = error.localizedDescription
        case .success(let urls):
            var ficheros: [(name: String, data: Data)] = []
            for url in urls {
                // El selector devuelve URLs con alcance de seguridad: hay que
                // abrirlo y cerrarlo explícitamente o la lectura falla en iOS.
                let accediendo = url.startAccessingSecurityScopedResource()
                defer { if accediendo { url.stopAccessingSecurityScopedResource() } }
                guard let datos = try? Data(contentsOf: url) else { continue }
                ficheros.append((name: url.lastPathComponent, data: datos))
            }
            guard !ficheros.isEmpty else {
                readError = "No se pudo leer ninguno de los ficheros elegidos."
                return
            }
            preview = service.preview(files: ficheros, manifest: manifest)
        }
    }
}

/// Selector global de entregas. A diferencia del botón histórico, no está ligado
/// a un formulario: cada sobre decide su propio destino mediante `formInstanceId`.
struct WebSubmissionBatchImportButton: View {
    let taskInfoByFormInstanceId: [String: WebSubmissionTaskInfo]
    let manifestsByFormInstanceId: [String: WebFormManifest]
    let manifestJSONByFormInstanceId: [String: Data]
    let service: WebSubmissionImportService
    let rosterByFormInstanceId: [String: [WebRosterEntry]]
    let isImporting: Bool
    let onConfirm: ([WebSubmissionImportDecision]) -> Void

    @State private var showingPicker = false
    @State private var preview: WebSubmissionImportPreview?
    @State private var readError: String?

    init(
        taskInfoByFormInstanceId: [String: WebSubmissionTaskInfo],
        manifestsByFormInstanceId: [String: WebFormManifest],
        manifestJSONByFormInstanceId: [String: Data] = [:],
        service: WebSubmissionImportService,
        rosterByFormInstanceId: [String: [WebRosterEntry]],
        isImporting: Bool,
        onConfirm: @escaping ([WebSubmissionImportDecision]) -> Void
    ) {
        self.taskInfoByFormInstanceId = taskInfoByFormInstanceId
        self.manifestsByFormInstanceId = manifestsByFormInstanceId
        self.manifestJSONByFormInstanceId = manifestJSONByFormInstanceId
        self.service = service
        self.rosterByFormInstanceId = rosterByFormInstanceId
        self.isImporting = isImporting
        self.onConfirm = onConfirm
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Importar lote de entregas", systemImage: "tray.and.arrow.down")
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.mgsub],
            allowsMultipleSelection: true
        ) { resultado in
            handle(resultado)
        }
        .sheet(item: $preview) { lote in
            WebSubmissionImportSheet(
                formTitle: "Lote de entregas",
                preview: lote,
                roster: [],
                isImporting: isImporting,
                onConfirm: onConfirm,
                taskInfoByFormInstanceId: taskInfoByFormInstanceId,
                rosterByFormInstanceId: rosterByFormInstanceId
            )
        }
        .alert(
            "No se pudo leer",
            isPresented: Binding(
                get: { readError != nil },
                set: { visible in if !visible { readError = nil } }
            )
        ) {
            Button("Entendido") { readError = nil }
        } message: {
            Text(readError ?? "")
        }
    }

    private func handle(_ resultado: Result<[URL], Error>) {
        switch resultado {
        case .failure(let error):
            readError = error.localizedDescription
        case .success(let urls):
            var ficheros: [(name: String, data: Data)] = []
            for url in urls {
                let accediendo = url.startAccessingSecurityScopedResource()
                defer { if accediendo { url.stopAccessingSecurityScopedResource() } }
                guard let datos = try? Data(contentsOf: url) else { continue }
                ficheros.append((name: url.lastPathComponent, data: datos))
            }
            guard !ficheros.isEmpty else {
                readError = "No se pudo leer ninguno de los ficheros elegidos."
                return
            }
            preview = service.preview(
                files: ficheros,
                manifests: manifestsByFormInstanceId,
                manifestJSONByFormInstanceId: manifestJSONByFormInstanceId
            )
        }
    }
}

/// `WebSubmissionImportPreview` es un valor, no una entidad, así que se le da una
/// identidad efímera solo para poder presentarlo con `.sheet(item:)`.
extension WebSubmissionImportPreview: Identifiable {
    var id: String {
        let claves = drafts.map(\.submissionId)
            + rejections.map(\.fileName)
            + alreadyImported.map(\.submissionId)
        return claves.joined(separator: "|")
    }
}

// MARK: - Previsualizaciones

#if DEBUG
/// Datos de muestra. Están aquí y no en el sheet para que la vista siga sin saber
/// de dónde vienen los datos, y para poder ver los tres estados en Xcode sin
/// cablear nada con la base de datos.
enum WebSubmissionSheetSamples {
    static func answer(_ webItemId: String, _ title: String) -> WebResolvedAnswer {
        WebResolvedAnswer(
            itemId: "item-\(webItemId)",
            webItemId: webItemId,
            title: title,
            type: .text,
            textValue: "Respuesta de muestra",
            boolValue: nil,
            numberValue: nil
        )
    }

    static func draft(
        alias: String,
        studentId: Int64?,
        studentName: String?,
        answered: Int,
        total: Int,
        missing: [String] = []
    ) -> WebSubmissionDraft {
        WebSubmissionDraft(
            submissionId: "sub-\(alias)",
            formInstanceId: "form-sa2",
            alias: alias,
            studentId: studentId,
            studentName: studentName,
            classId: 7,
            columnId: "col-portafolio-sa2",
            clientSubmittedAt: "2026-07-30T09:15:00Z",
            answers: (0..<answered).map { answer("f\($0)", "Apartado \($0)") },
            requiredTotal: total,
            requiredAnswered: answered,
            missingRequiredTitles: missing
        )
    }

    static let roster: [WebRosterEntry] = [
        WebRosterEntry(id: 42, name: "Ana Ferrer"),
        WebRosterEntry(id: 43, name: "Bruno Gil"),
        WebRosterEntry(id: 44, name: "Carmen Ruiz"),
    ]

    /// Caso realista: dos resueltas, una sin asignar, una rechazada y una repetida.
    static let mixed: WebSubmissionImportPreview = {
        var lote = WebSubmissionImportPreview()
        lote.drafts = [
            draft(alias: "QragffpD_hfwuYPbQ5X1ZQ", studentId: 42, studentName: "Ana Ferrer", answered: 40, total: 40),
            draft(
                alias: "0uX2-1WH-OyGLIiiPQjPfw",
                studentId: 43,
                studentName: "Bruno Gil",
                answered: 31,
                total: 40,
                missing: ["S9 Serve: evidence of progress", "S10 My strongest shot now is", "S7 Did it help? Evidence"]
            ),
            draft(alias: "sIaWMFnPwM8Xcb2ebBaU4A", studentId: nil, studentName: nil, answered: 38, total: 40),
        ]
        lote.rejections = [
            WebSubmissionRejection(
                fileName: "pasaporte-3f9a12.mgsub",
                reason: "No se puede descifrar. O la clave no es la de este formulario, o el fichero ha sido manipulado."
            )
        ]
        lote.alreadyImported = [
            WebSubmissionAlreadyImported(
                fileName: "pasaporte-8b1c4d.mgsub",
                submissionId: "sub-repetida",
                importedAtEpochMs: 1_784_000_000_000
            )
        ]
        return lote
    }()

    static let allRejected: WebSubmissionImportPreview = {
        var lote = WebSubmissionImportPreview()
        lote.rejections = [
            WebSubmissionRejection(fileName: "a.mgsub", reason: "La respuesta s9_serve_initial no encaja con su tipo: la escala va de 1 a 4 y llegó 7"),
            WebSubmissionRejection(fileName: "b.mgsub", reason: "La entrega es de otro formulario (form-sa5); este es form-sa2."),
        ]
        return lote
    }()
}

struct WebSubmissionImportSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WebSubmissionImportSheet(
                formTitle: "Technical Progress Passport - Badminton Progress Lab",
                preview: WebSubmissionSheetSamples.mixed,
                roster: WebSubmissionSheetSamples.roster,
                isImporting: false,
                onConfirm: { _ in }
            )
            .previewDisplayName("Lote mixto")

            WebSubmissionImportSheet(
                formTitle: "Technical Progress Passport",
                preview: WebSubmissionSheetSamples.allRejected,
                roster: WebSubmissionSheetSamples.roster,
                isImporting: false,
                onConfirm: { _ in }
            )
            .previewDisplayName("Todo rechazado")

            WebSubmissionImportSheet(
                formTitle: "Technical Progress Passport",
                preview: WebSubmissionImportPreview(),
                roster: [],
                isImporting: false,
                onConfirm: { _ in }
            )
            .previewDisplayName("Vacío")
        }
    }
}
#endif
