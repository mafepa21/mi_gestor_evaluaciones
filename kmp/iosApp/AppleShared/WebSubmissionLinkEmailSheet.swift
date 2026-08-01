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

/// Preparación individual de los correos de una tarea web.
///
/// La app mantiene el control del destinatario y del enlace. El último paso
/// abre el compositor de Mail con un mensaje individual; no se envían varios
/// enlaces en un mismo correo ni se exponen las direcciones entre alumnos.
struct WebSubmissionLinkEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let task: WebSubmissionTaskInfo
    let links: [WebPublishedStudentLink]

    @State private var selectedStudentId: Int64?
    @State private var subject: String
    @State private var bodyText: String
    @State private var preparedStudentIds: Set<Int64> = []

    init(task: WebSubmissionTaskInfo, links: [WebPublishedStudentLink]) {
        self.task = task
        self.links = links
        let first = links.first
        _selectedStudentId = State(initialValue: first?.studentId)
        _subject = State(initialValue: Self.defaultSubject(for: task))
        _bodyText = State(initialValue: Self.defaultBody(for: first, task: task))
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
                }
            }
            .padding(24)
            .navigationTitle("Enviar enlaces")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 860, minHeight: 560)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.title2.weight(.semibold))
            Text("Selecciona un alumno, revisa el mensaje y prepara su enlace individual en Mail.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

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
        }
        .frame(minWidth: 280, maxWidth: 320, alignment: .topLeading)
    }

    private func recipientRow(_ link: WebPublishedStudentLink) -> some View {
        let selected = selectedStudentId == link.studentId
        let prepared = preparedStudentIds.contains(link.studentId)

        return Button {
            select(link)
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
                        .help("Correo preparado en Mail")
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

    @ViewBuilder
    private var editor: some View {
        if let link = selectedLink {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Destinatario")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(link.email ?? "Sin correo configurado")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(link.hasEmail ? Color.primary : Color.orange)
                }

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
                    TextEditor(text: $bodyText)
                        .font(.body)
                        .padding(8)
                        .frame(minHeight: 250)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 12) {
                    Label("Enlace individual incluido", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        prepareInMail(link)
                    } label: {
                        Label(
                            preparedStudentIds.contains(link.studentId) ? "Volver a preparar" : "Preparar en Mail",
                            systemImage: "envelope.open"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!link.hasEmail || mailtoURL(for: link) == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("Selecciona un alumno", systemImage: "person.crop.circle.badge.plus")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    private var selectedLink: WebPublishedStudentLink? {
        guard let selectedStudentId else { return nil }
        return links.first { $0.studentId == selectedStudentId }
    }

    private func select(_ link: WebPublishedStudentLink) {
        selectedStudentId = link.studentId
        subject = Self.defaultSubject(for: task)
        bodyText = Self.defaultBody(for: link, task: task)
    }

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
            body: bodyText
        )
    }

    private static func defaultSubject(for task: WebSubmissionTaskInfo) -> String {
        "Enlace de entrega · \(task.title)"
    }

    private static func defaultBody(
        for link: WebPublishedStudentLink?,
        task: WebSubmissionTaskInfo
    ) -> String {
        guard let link else { return "" }
        return """
        Hola \(link.studentName),

        Aquí tienes tu enlace individual para la tarea «\(task.title)»:

        \(link.url.absoluteString)

        Cuando termines, utiliza el botón de enviar de la página.

        Un saludo.
        """
    }
}
