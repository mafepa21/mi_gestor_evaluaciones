import SwiftUI
import CoreImage.CIFilterBuiltins

/// Hoja «Portal del alumnado» de Entregas web (maqueta, estados L a R).
///
/// Un solo botón principal por estado. Los nombres salen al momento (son locales);
/// solo la columna «Cuenta» espera al servidor. Sin servidor no se preparan correos:
/// llevarían un código que el servidor no conoce.

struct WebPortalStudent: Identifiable, Equatable {
    let id: Int64
    let firstName: String
    let lastName: String
    let email: String?

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    var address: String? {
        let trimmed = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Hay un correo con el que Mail puede trabajar.
    var hasUsableEmail: Bool {
        address.map(WebSubmissionBulkMailPlanner.isPlausibleAddress) ?? false
    }
}

/// Código recién creado para enseñar en pantalla (solo vive en memoria).
struct WebPortalCodeCard: Identifiable {
    let id = UUID()
    let studentName: String
    let code: String
    let link: String
}

// MARK: - Modelo de la hoja

@MainActor
final class WebPortalViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var students: [WebPortalStudent] = []
    @Published private(set) var entries: [Int64: WebPortalEntry] = [:]
    @Published private(set) var serverStates: [String: WebPortalServerState] = [:]
    @Published private(set) var phase: Phase = .idle
    @Published var errorText: String?
    @Published var resultText: String?
    @Published private(set) var working = false
    @Published var card: WebPortalCodeCard?

    let baseURL: String
    let storeURL: URL
    var session: URLSession = .shared
    var iterations = WebPortalCrypto.pbkdf2Iterations
    /// Pide a la app que republique los tablones (en segundo plano).
    let republish: () -> Void

    private static let checkedKey = "webPortal.comprobadoEl"
    var lastChecked: Date? {
        let value = UserDefaults.standard.double(forKey: Self.checkedKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    init(baseURL: String, storeURL: URL, republish: @escaping () -> Void) {
        self.baseURL = baseURL
        self.storeURL = storeURL
        self.republish = republish
    }

    private var client: WebPortalClient {
        WebPortalClient(url: WebPortalClient.url(baseURL: baseURL), session: session)
    }

    // MARK: Estado

    func status(of student: WebPortalStudent) -> WebPortalAccountStatus {
        let entry = entries[student.id]
        if phase == .loading, entry != nil, serverStates[entry!.portalId] == nil { return .desconocido }
        return WebPortalAccountStatus.resolve(
            hasEmail: student.hasUsableEmail,
            entry: entry,
            server: entry.flatMap { serverStates[$0.portalId] }
        )
    }

    /// Hay una invitación nueva esperando además de una cuenta activa.
    func hasPendingCodeOnTopOfAccount(_ student: WebPortalStudent) -> Bool {
        guard let entry = entries[student.id], case .cuenta(let pending)? = serverStates[entry.portalId] else { return false }
        return pending
    }

    var hasAnyInvitation: Bool { students.contains { entries[$0.id] != nil } }

    func count(of status: WebPortalAccountStatus) -> Int { students.filter { self.status(of: $0) == status }.count }
    var activeCount: Int { count(of: .activada) }
    var pendingCount: Int { count(of: .pendiente) + count(of: .caducado) }
    var noEmailCount: Int { count(of: .sinCorreo) }

    /// «Enviar» cubre a quien tiene correo y aún no tiene cuenta activa.
    var sendTargets: [WebPortalStudent] {
        students.filter {
            guard $0.hasUsableEmail else { return false }
            switch status(of: $0) {
            case .sinInvitar, .pendiente, .caducado, .sinCuenta: return true
            default: return false
            }
        }
    }

    // MARK: Carga

    func load(students: [WebPortalStudent]) async {
        self.students = students.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        await refresh()
    }

    func refresh() async {
        entries = WebPortalStore(fileURL: storeURL).entries
        let ids = students.compactMap { entries[$0.id]?.portalId }
        errorText = nil
        guard !ids.isEmpty else { phase = .loaded; return }
        guard let accountKey = WebSubmissionInbox.accountKey else {
            phase = .failed
            errorText = WebSubmissionInbox.InboxError.noAccountKey.localizedDescription
            return
        }
        phase = .loading
        do {
            let states = try await client.state(portalIds: ids, accountKey: accountKey)
            serverStates = states
            WebPortalInviter.recordStates(states, storeURL: storeURL)
            entries = WebPortalStore(fileURL: storeURL).entries
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.checkedKey)
            phase = .loaded
        } catch {
            phase = .failed
            errorText = "No se pudo hablar con el servidor. El estado puede no estar al día."
        }
    }

    // MARK: Acciones

    /// Crea invitaciones nuevas y devuelve los códigos. Si el servidor falla no devuelve
    /// nada: nunca se prepara un correo con un código que el servidor no conoce.
    private func invite(_ targets: [WebPortalStudent]) async -> [WebPortalInvitation]? {
        guard let accountKey = WebSubmissionInbox.accountKey else {
            errorText = WebSubmissionInbox.InboxError.noAccountKey.localizedDescription
            return nil
        }
        working = true
        defer { working = false }
        do {
            let result = try await WebPortalInviter.invite(
                studentIds: targets.map(\.id),
                storeURL: storeURL,
                client: client,
                accountKey: accountKey,
                iterations: iterations
            )
            entries = WebPortalStore(fileURL: storeURL).entries
            republish()
            return result
        } catch {
            errorText = "No se pudo crear la invitación: \(error.localizedDescription) No se ha preparado ningún correo."
            return nil
        }
    }

    /// Muestra el código de un alumno en pantalla (para quien no tiene correo).
    func showCode(for student: WebPortalStudent) async {
        errorText = nil
        guard let invitation = await invite([student]).flatMap(\.first) else { return }
        card = WebPortalCodeCard(
            studentName: student.fullName,
            code: WebPortalCrypto.displayCode(invitation.code),
            link: WebPortalClient.inviteLink(baseURL: baseURL, code: invitation.code)
        )
        await refresh()
    }

    func closeAccount(of student: WebPortalStudent) async {
        errorText = nil
        guard let accountKey = WebSubmissionInbox.accountKey else {
            errorText = WebSubmissionInbox.InboxError.noAccountKey.localizedDescription
            return
        }
        working = true
        defer { working = false }
        do {
            try await WebPortalInviter.close(studentIds: [student.id], storeURL: storeURL, client: client, accountKey: accountKey)
            resultText = "Cuenta de \(student.fullName) cerrada."
        } catch {
            errorText = "No se pudo cerrar la cuenta: \(error.localizedDescription)"
        }
        await refresh()
    }

    #if os(macOS)
    static let mailSubject = "Tu acceso al portal del alumnado"

    static func mailBody(name: String, link: String, code: String, expires: Date) -> String {
        let day = expires.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es")))
        return """
        Hola, \(name):

        Desde ahora verás aquí tus autoevaluaciones, coevaluaciones y tareas. Pulsa el enlace para crear tu cuenta:

        \(link)

        Si el enlace no funciona, entra en la web del portal y escribe este código: \(code)

        Caduca el \(day). Sirve una sola vez. Si no has pedido esto, avisa a tu docente.
        """
    }

    /// Invita y deja un correo por alumno en Borradores de Mail.
    func sendEmails(to targets: [WebPortalStudent]) async {
        errorText = nil
        resultText = nil
        guard !targets.isEmpty, let invitations = await invite(targets) else { return }
        let byId = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        let fallback = Date().addingTimeInterval(7 * 24 * 3600)
        let messages = invitations.compactMap { invitation -> WebSubmissionMailMessage? in
            guard let student = byId[invitation.studentId], let address = student.address else { return nil }
            return WebSubmissionMailMessage(
                studentId: student.id,
                studentName: student.fullName,
                recipient: address,
                subject: Self.mailSubject,
                body: Self.mailBody(
                    name: student.firstName,
                    link: WebPortalClient.inviteLink(baseURL: baseURL, code: invitation.code),
                    code: WebPortalCrypto.displayCode(invitation.code),
                    expires: invitation.expires ?? fallback
                )
            )
        }
        working = true
        let report = await WebSubmissionBulkMailer.deliver(
            plan: WebSubmissionMailPlan(messages: messages, skipped: []),
            delivery: .drafts
        )
        working = false
        resultText = report.summary
        if !report.failures.isEmpty {
            errorText = "Algún correo no se preparó. Usa «Enviar código nuevo…» en esa fila."
        }
        await refresh()
    }
    #endif
}

// MARK: - Hoja

struct WebPortalSheet: View {
    struct PortalGroup: Identifiable, Hashable {
        let id: Int64
        let name: String
    }

    let groups: [PortalGroup]
    @State var classId: Int64
    let loadStudents: (Int64) async -> [WebPortalStudent]
    @StateObject private var model: WebPortalViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection = Set<Int64>()
    @State private var closing: WebPortalStudent?
    @State private var showingPreview = false
    @State private var previewTargets: [WebPortalStudent] = []

    init(
        groups: [PortalGroup],
        classId: Int64,
        model: @autoclosure @escaping () -> WebPortalViewModel,
        loadStudents: @escaping (Int64) async -> [WebPortalStudent]
    ) {
        self.groups = groups
        self._classId = State(initialValue: classId)
        self._model = StateObject(wrappedValue: model())
        self.loadStudents = loadStudents
    }

    private var groupName: String { groups.first { $0.id == classId }?.name ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error = model.errorText { errorBanner(error) }
            if let result = model.resultText {
                Label(result, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }
            content
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 460)
        .task(id: classId) {
            selection = []
            await model.load(students: await loadStudents(classId))
        }
        .alert(
            "¿Cerrar la cuenta de \(closing?.fullName ?? "")?",
            isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
            presenting: closing
        ) { student in
            // Cancelar es la acción por defecto: cerrar una cuenta no se deshace.
            Button("Cancelar", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Cerrar cuenta", role: .destructive) {
                Task { await model.closeAccount(of: student) }
            }
        } message: { _ in
            Text("Ya no podrá entrar con su usuario. Sus entregas ya recibidas no se tocan. Podrás mandarle un código nuevo.")
        }
        .sheet(item: $model.card) { card in
            WebPortalCodeCardView(card: card)
        }
        #if os(macOS)
        .sheet(isPresented: $showingPreview) {
            WebPortalMailPreview(
                targets: previewTargets,
                baseURL: model.baseURL,
                onCancel: { showingPreview = false },
                onConfirm: {
                    showingPreview = false
                    Task { await model.sendEmails(to: previewTargets) }
                }
            )
        }
        #endif
    }

    // MARK: Partes

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Portal del alumnado").font(.title2.weight(.bold))
                Text(groupName).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if groups.count > 1 {
                Picker("Grupo", selection: $classId) {
                    ForEach(groups) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            Button("Cerrar") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            if model.phase == .failed {
                Button("Reintentar") { Task { await model.refresh() } }
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var content: some View {
        if model.students.isEmpty && model.phase != .idle {
            ContentUnavailableView("Este grupo no tiene alumnado", systemImage: "person.2")
        } else if !model.hasAnyInvitation && model.phase != .loading && model.phase != .idle {
            emptyInvite
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if model.phase == .loaded { summary }
                table
                footer
            }
        }
    }

    // L · Grupo sin invitar
    private var emptyInvite: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Aún no has invitado a este grupo").font(.title3.weight(.semibold))
            Text("Cada alumno recibe un correo con un código para crear su cuenta. Después verá en un solo sitio todo lo que publiques.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            #if os(macOS)
            Button("Invitar al grupo…") { askToSend() }
                .buttonStyle(.borderedProminent)
                .disabled(model.sendTargets.isEmpty || model.working)
            if model.noEmailCount > 0 {
                Text("\(model.noEmailCount) sin correo: no recibirán invitación.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            #else
            Text("Las invitaciones se preparan desde el Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // M · Con datos
    private var summary: some View {
        HStack(spacing: 18) {
            Label("\(model.activeCount) Activadas", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Label("\(model.pendingCount) Pendientes", systemImage: "clock.fill").foregroundStyle(.orange)
            Label("\(model.noEmailCount) Sin correo", systemImage: "envelope.badge.shield.half.filled").foregroundStyle(.secondary)
        }
        .font(.callout.weight(.semibold))
    }

    private var table: some View {
        Table(model.students, selection: $selection) {
            TableColumn("Alumno") { student in
                Text(student.fullName)
            }
            TableColumn("Correo") { student in
                Text(student.address ?? "Sin correo")
                    .foregroundStyle(.secondary)
            }
            TableColumn("Cuenta") { student in
                HStack {
                    statusView(for: student)
                    Spacer(minLength: 4)
                    Menu {
                        rowMenu(for: [student.id])
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Acciones de \(student.fullName)")
                }
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            rowMenu(for: Array(ids))
        }
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private func statusView(for student: WebPortalStudent) -> some View {
        let status = model.status(of: student)
        if status == .desconocido {
            ProgressView().controlSize(.small)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Label(status.label, systemImage: Self.icon(for: status))
                    .foregroundStyle(Self.color(for: status))
                if status == .activada, model.hasPendingCodeOnTopOfAccount(student) {
                    Text("Código nuevo sin canjear").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func color(for status: WebPortalAccountStatus) -> Color {
        switch status {
        case .activada: return .green
        case .pendiente: return .orange
        case .caducado: return .red
        case .sinCorreo, .sinInvitar, .sinCuenta, .desconocido: return .secondary
        }
    }

    static func icon(for status: WebPortalAccountStatus) -> String {
        switch status {
        case .activada: return "checkmark.circle.fill"
        case .pendiente: return "clock.fill"
        case .caducado: return "exclamationmark.circle.fill"
        case .sinCorreo: return "envelope.badge.shield.half.filled"
        case .sinInvitar, .sinCuenta: return "circle.dashed"
        case .desconocido: return "ellipsis.circle"
        }
    }

    // N · Menú de un alumno
    @ViewBuilder
    private func rowMenu(for ids: [Int64]) -> some View {
        let people = model.students.filter { ids.contains($0.id) }
        if let one = people.first, people.count == 1 {
            #if os(macOS)
            Button("Enviar código nuevo…") {
                previewTargets = [one]
                showingPreview = true
            }
            .disabled(!one.hasUsableEmail || !canSend)
            #endif
            Button("Mostrar su código…") { Task { await model.showCode(for: one) } }
                .disabled(!canSend)
            Divider()
            Button("Cerrar su cuenta…", role: .destructive) { closing = one }
                .disabled(model.entries[one.id] == nil)
        }
    }

    /// Sin servidor no se crean códigos.
    private var canSend: Bool { model.phase == .loaded && !model.working }

    private var footer: some View {
        HStack(spacing: 12) {
            footerStatus
            Spacer()
            #if os(macOS)
            let targets = model.sendTargets
            Button("Enviar \(targets.count) \(targets.count == 1 ? "correo" : "correos")…") { askToSend() }
                .buttonStyle(.borderedProminent)
                .disabled(targets.isEmpty || !canSend)
            #else
            Text("Los correos se preparan desde el Mac.").font(.footnote).foregroundStyle(.secondary)
            #endif
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Comprobando…") }
                .font(.footnote).foregroundStyle(.secondary)
        case .failed:
            Group {
                if let last = model.lastChecked {
                    Text("Último dato: \(last.formatted(.relative(presentation: .named))) · Enviar necesita conexión")
                } else {
                    Text("Enviar necesita conexión")
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
        default:
            if let last = model.lastChecked {
                Text("Comprobado \(last.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func askToSend() {
        previewTargets = model.sendTargets
        showingPreview = true
    }
}

// MARK: - O · Vista previa antes de enviar

#if os(macOS)
struct WebPortalMailPreview: View {
    let targets: [WebPortalStudent]
    let baseURL: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var sample: String {
        let first = targets.first
        return WebPortalViewModel.mailBody(
            name: first?.firstName ?? "Nombre",
            link: WebPortalClient.inviteLink(baseURL: baseURL, code: "XXXXXXXXXX"),
            code: "XXXXX-XXXXX",
            expires: Date().addingTimeInterval(7 * 24 * 3600)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preparar \(targets.count) \(targets.count == 1 ? "correo" : "correos")")
                .font(.title3.weight(.bold))
            Text("Así lo verá cada alumno. Cambian el nombre y el código.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                if let first = targets.first {
                    Text("Para: \(first.address ?? "")\(targets.count > 1 ? " y \(targets.count - 1) más" : "")")
                }
                Text("Asunto: \(WebPortalViewModel.mailSubject)")
                Divider()
                Text(sample).textSelection(.enabled)
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Text("Sin notas ni datos del alumno más allá del nombre de pila.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Text("Quedarán en Borradores de Mail").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Preparar correos", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(targets.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
#endif

// MARK: - Tarjeta con el código

struct WebPortalCodeCardView: View {
    let card: WebPortalCodeCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text(card.studentName).font(.title3.weight(.bold))
            if let qr = WebPortalQR.image(for: card.link) {
                qr.resizable()
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .accessibilityLabel("Código QR del enlace de alta")
            }
            Text(card.code)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .textSelection(.enabled)
            Text("Sirve una sola vez y caduca en 7 días. No uses tu nombre real al crear el usuario.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                ShareLink(item: card.link) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                Button("Listo") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 360)
    }
}

enum WebPortalQR {
    static func image(for text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}
