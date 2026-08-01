import SwiftUI
import Foundation

enum WebSubmissionMailComposer {
    static func mailtoURL(recipient: String, subject: String, body: String) -> URL? {
        let cleanRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRecipient.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = cleanRecipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

/// Reparto de los correos de una tarea web.
///
/// La app mantiene el control del destinatario y del enlace. Hay dos salidas, y
/// las dos componen un mensaje por alumno: abrir el compositor de Mail para uno
/// solo, o dejar todo el grupo hecho de una vez. Nunca se envían varios enlaces
/// en un mismo correo ni se exponen las direcciones entre alumnos.
///
/// El mensaje se escribe una sola vez, como plantilla con huecos. Antes el texto
/// se regeneraba al cambiar de alumno, lo que borraba lo que el docente hubiera
/// redactado; ahora la plantilla se conserva y el hueco se rellena al preparar
/// cada correo.
struct WebSubmissionLinkEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let task: WebSubmissionTaskInfo
    let links: [WebPublishedStudentLink]

    @State private var selectedStudentId: Int64?
    @State private var subject: String
    @State private var bodyTemplate: String = WebSubmissionMailTemplate.defaultBody
    @State private var preparedStudentIds: Set<Int64> = []

    @State private var delivery: WebSubmissionMailDelivery = .drafts
    @State private var isDelivering = false
    @State private var deliveredCount = 0
    @State private var confirmingSend = false
    @State private var report: WebSubmissionBulkMailReport?

    init(task: WebSubmissionTaskInfo, links: [WebPublishedStudentLink]) {
        self.task = task
        self.links = links
        _selectedStudentId = State(initialValue: links.first?.studentId)
        _subject = State(initialValue: Self.defaultSubject(for: task))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header

                if links.isEmpty {
                    emptyState
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        recipientsList
                        editor
                    }
                    bulkBar
                }
            }
            .padding(24)
            .navigationTitle("Enviar enlaces")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .disabled(isDelivering)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 880, minHeight: 640)
        #endif
        .alert("Enviar \(deliverableCount) correos", isPresented: $confirmingSend) {
            Button("Enviar ahora", role: .destructive) {
                Task { await deliverAll() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(
                "Mail enviará un correo a cada alumno con su enlace personal. "
                + "Una vez enviados no se pueden retirar."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.title2.weight(.semibold))
            Text("Escribe el mensaje una vez. Prepáralo para un alumno o para todo el grupo.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Alumnado

    private var recipientsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alumnos")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(links) { link in
                        recipientRow(link)
                    }
                }
            }

            Text(rosterSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 280, maxWidth: 320, alignment: .topLeading)
    }

    private var rosterSummary: String {
        let partition = self.partition
        let conCorreo = partition.eligible.count
        let sinCorreo = partition.skipped.count
        if sinCorreo == 0 {
            return "\(conCorreo) con correo."
        }
        return "\(conCorreo) con correo · \(sinCorreo) sin correo utilizable."
    }

    private func recipientRow(_ link: WebPublishedStudentLink) -> some View {
        let selected = selectedStudentId == link.studentId
        let prepared = preparedStudentIds.contains(link.studentId)

        return Button {
            selectedStudentId = link.studentId
        } label: {
            HStack(spacing: 10) {
                Image(systemName: link.hasEmail ? "envelope" : "envelope.badge.exclamationmark")
                    .foregroundStyle(link.hasEmail ? Color.green : Color.orange)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(link.studentName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(link.email ?? "Sin correo en la ficha")
                        .font(.caption)
                        .foregroundStyle(link.hasEmail ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if prepared {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Correo ya preparado")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mensaje

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Asunto")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Asunto del correo", text: $subject)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Mensaje")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $bodyTemplate)
                    .font(.body)
                    .padding(8)
                    .frame(minHeight: 200)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                placeholderLegend
            }

            preview
            individualAction
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .disabled(isDelivering)
    }

    private var placeholderLegend: some View {
        HStack(spacing: 8) {
            ForEach(WebSubmissionMailTemplate.allPlaceholders, id: \.self) { placeholder in
                Text(placeholder)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            Text("se rellenan en cada correo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let link = selectedLink {
            VStack(alignment: .leading, spacing: 5) {
                Text("Vista previa · \(link.studentName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(renderedBody(for: link))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var individualAction: some View {
        if let link = selectedLink {
            HStack(spacing: 12) {
                Label("Enlace individual incluido", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    prepareInMail(link)
                } label: {
                    Label("Preparar solo este", systemImage: "envelope.open")
                }
                .disabled(!link.hasEmail || mailtoURL(for: link) == nil)
            }
        }
    }

    // MARK: - Reparto a todo el grupo

    @ViewBuilder
    private var bulkBar: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Al terminar", selection: $delivery) {
                        ForEach(WebSubmissionMailDelivery.allCases) { modo in
                            Text(modo.label).tag(modo)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)

                    Text(delivery.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    if delivery == .send {
                        confirmingSend = true
                    } else {
                        Task { await deliverAll() }
                    }
                } label: {
                    Label(bulkButtonTitle, systemImage: "envelope.badge")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDelivering || deliverableCount == 0)
            }

            if isDelivering {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(
                        value: Double(deliveredCount),
                        total: Double(max(deliverableCount, 1))
                    )
                    Text("Preparando \(deliveredCount) de \(deliverableCount) en Mail…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let report {
                reportSummary(report)
            }
        }
        #else
        EmptyView()
        #endif
    }

    private var bulkButtonTitle: String {
        let total = deliverableCount
        switch delivery {
        case .drafts:
            return total == 1 ? "Preparar 1 borrador" : "Preparar \(total) borradores"
        case .send:
            return total == 1 ? "Enviar 1 correo" : "Enviar \(total) correos"
        }
    }

    @ViewBuilder
    private func reportSummary(_ report: WebSubmissionBulkMailReport) -> some View {
        let ok = !report.permissionDenied && report.failures.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Label(report.summary, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(ok ? Color.green : Color.orange)

            if report.permissionDenied {
                Text(
                    "Concede el permiso en Ajustes del Sistema › Privacidad y seguridad › "
                    + "Automatización › Mi Gestor › Mail, y vuelve a intentarlo."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(report.failures.indices, id: \.self) { index in
                Text("\(report.failures[index].studentName): \(report.failures[index].reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !report.skipped.isEmpty {
                Text(
                    "Fuera del reparto: "
                    + report.skipped.map { "\($0.studentName) (\($0.reason.lowercased()))" }
                        .joined(separator: ", ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No se encontró la hoja privada de enlaces")
                .font(.headline)
            Text("Abre la carpeta de la tarea para comprobar que sigue en Documentos/EntregasWeb/.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Datos

    private var selectedLink: WebPublishedStudentLink? {
        guard let selectedStudentId else { return links.first }
        return links.first { $0.studentId == selectedStudentId } ?? links.first
    }

    /// Cuentas para la pantalla. No compone ningún texto, así que puede
    /// recalcularse en cada redibujo sin coste apreciable.
    private var partition: (eligible: [(link: WebPublishedStudentLink, address: String)], skipped: [WebSubmissionMailSkip]) {
        WebSubmissionBulkMailPlanner.split(links: links)
    }

    private var deliverableCount: Int { partition.eligible.count }

    /// Plan completo con los mensajes ya redactados. Solo se construye al
    /// repartir.
    private func buildPlan() -> WebSubmissionMailPlan {
        WebSubmissionBulkMailPlanner.plan(
            taskTitle: task.title,
            links: links,
            subject: subject,
            bodyTemplate: bodyTemplate
        )
    }

    private func renderedBody(for link: WebPublishedStudentLink) -> String {
        WebSubmissionMailTemplate.render(
            bodyTemplate,
            studentName: link.studentName,
            taskTitle: task.title,
            link: link.url.absoluteString
        )
    }

    // MARK: - Acciones

    private func prepareInMail(_ link: WebPublishedStudentLink) {
        guard let url = mailtoURL(for: link) else { return }
        openURL(url)
        preparedStudentIds.insert(link.studentId)
    }

    private func mailtoURL(for link: WebPublishedStudentLink) -> URL? {
        guard let email = link.email else { return nil }
        return WebSubmissionMailComposer.mailtoURL(
            recipient: email,
            subject: subject,
            body: renderedBody(for: link)
        )
    }

    @MainActor
    private func deliverAll() async {
        #if os(macOS)
        // El plan se congela antes de empezar: si el docente tocase el mensaje a
        // media tanda, la mitad del grupo recibiría un texto distinto.
        let planToDeliver = buildPlan()
        guard !planToDeliver.isEmpty else { return }

        isDelivering = true
        deliveredCount = 0
        report = nil

        let resultado = await WebSubmissionBulkMailer.deliver(
            plan: planToDeliver,
            delivery: delivery
        ) { done in
            deliveredCount = done
        }

        preparedStudentIds.formUnion(resultado.deliveredStudentIds)
        report = resultado
        isDelivering = false
        #endif
    }

    private static func defaultSubject(for task: WebSubmissionTaskInfo) -> String {
        "Enlace de entrega · \(task.title)"
    }
}
