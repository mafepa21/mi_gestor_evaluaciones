import SwiftUI

/// Publicar un formulario para que el alumnado lo rellene desde la web.
///
/// Patrón adaptativo canónico del proyecto: dos zonas con `ViewThatFits`, fallback
/// apilado que conserva todas las acciones, `presentationDetents` en iOS/iPadOS y
/// `frame` de tamaño mínimo solo bajo `#if os(macOS)`. Referencia:
/// `ScheduleImportPreviewSheet` y `WebSubmissionImportSheet`, su gemela de entrada.
///
/// La pantalla tiene dos estados y el segundo es el importante: después de publicar
/// hay que **hacer dos cosas con dos ficheros distintos**, y si eso no queda claro
/// el formulario no llega a funcionar. El manifiesto se sube a la web; la hoja de
/// enlaces no se sube a ninguna parte y se reparte en privado.
struct WebSubmissionPublishSheet: View {
    @Environment(\.dismiss) private var dismiss

    let classId: Int64
    let className: String
    let instruments: [WebPublishableInstrument]
    /// URL de la web donde está publicada la PWA.
    @Binding var baseURL: String
    let isPublishing: Bool
    let onPublish: (_ columnId: String, _ baseURL: String, _ expiresAt: Date) -> Void
    let result: WebPublishResult?

    @State private var selectedColumnId: String?
    @State private var expiresAt: Date = Calendar.current.date(byAdding: .month, value: 10, to: Date()) ?? Date()
    @State private var copiedLinks = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                Group {
                    if let result {
                        publishedContent(result)
                    } else {
                        setupContent
                    }
                }
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
        .onAppear {
            if selectedColumnId == nil {
                selectedColumnId = instruments.first(where: { !$0.alreadyPublished })?.columnId
                    ?? instruments.first?.columnId
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "paperplane")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.indigo)
                .frame(width: 48, height: 48)
                .background(.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result == nil ? "Publicar para el alumnado" : "Formulario publicado")
                    .font(.title2.weight(.bold))
                Text(className)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

    // MARK: - Antes de publicar

    @ViewBuilder
    private var setupContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard
                    privacyCard
                }
                .frame(minWidth: 264, idealWidth: 304, maxWidth: 340, alignment: .topLeading)

                instrumentList
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 664, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 18) {
                settingsCard
                privacyCard
                instrumentList
            }
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajustes")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Dirección de la web")
                    .font(.caption.weight(.semibold))
                TextField("https://…", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .appKeyboardType(.url)
                    .appWritingToolsDisabled()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Deja de aceptar entregas el")
                    .font(.caption.weight(.semibold))
                DatePicker("", selection: $expiresAt, displayedComponents: .date)
                    .labelsHidden()
            }

            Text("Pasada esa fecha, la web se niega a aceptar entregas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Qué sale de este Mac")
                .font(.headline)

            label("Las preguntas y una clave pública", "checkmark", .green)
            label("Un código aleatorio por alumno", "checkmark", .green)
            label("Ningún nombre", "xmark", .secondary)
            label("Ningún dato de tu base", "xmark", .secondary)

            Text("La tabla que traduce cada código a una persona se queda aquí. Sin ella, las respuestas no se pueden atribuir a nadie.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func label(_ texto: String, _ icono: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icono)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(texto)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var instrumentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qué instrumento se publica")
                .font(.headline)

            if instruments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No hay ningún instrumento que publicar")
                        .font(.subheadline.weight(.semibold))
                    Text("Solo se pueden publicar columnas con apartados: checklist, observación, formulario o quiz. Importa los instrumentos de una situación de aprendizaje y vuelve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(instruments) { instrumento in
                    instrumentRow(instrumento)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func instrumentRow(_ instrumento: WebPublishableInstrument) -> some View {
        let seleccionado = selectedColumnId == instrumento.columnId
        return Button {
            selectedColumnId = instrumento.columnId
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: seleccionado ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(seleccionado ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(instrumento.templateTitle)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(instrumento.itemCount) apartado(s) · columna «\(instrumento.columnTitle)»")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if instrumento.alreadyPublished {
                        Text("Ya tiene un formulario activo. Publicar otro reparte códigos nuevos y los enlaces antiguos dejarán de funcionar.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Después de publicar

    @ViewBuilder
    private func publishedContent(_ result: WebPublishResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Los dos pasos van primero y numerados: sin hacerlos, el formulario
            // no funciona, y es donde más fácil es quedarse a medias.
            VStack(alignment: .leading, spacing: 12) {
                Text("Te quedan dos cosas por hacer")
                    .font(.headline)

                stepCard(
                    number: 1,
                    title: "Sube el manifiesto a la web",
                    detail: "Copia este fichero a `public/manifiestos/` del repo de la web y despliega. Se puede subir a un sitio público: solo lleva preguntas y una clave pública.",
                    path: result.manifestPath,
                    tint: .indigo
                )

                stepCard(
                    number: 2,
                    title: "Reparte los enlaces en privado",
                    detail: "Un enlace por alumno. Esta hoja SÍ relaciona nombre y código: no la subas a ningún sitio ni la mandes al grupo entero.",
                    path: result.linksPath,
                    tint: .orange
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Enlaces")
                        .font(.headline)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Button {
                        copyToClipboard(result.linksText)
                        copiedLinks = true
                    } label: {
                        Label(copiedLinks ? "Copiado" : "Copiar todos", systemImage: copiedLinks ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                ForEach(result.links) { enlace in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(enlace.studentName)
                            .font(.subheadline.weight(.semibold))
                        Text(enlace.url)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func stepCard(
        number: Int,
        title: String,
        detail: String,
        path: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .layoutPriority(1)
                    Button("Copiar ruta") { copyToClipboard(path) }
                        .buttonStyle(.borderless)
                        .font(.caption2.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pie

    private var footer: some View {
        HStack(spacing: 12) {
            if result == nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Se creará un código por alumno")
                        .font(.subheadline.weight(.semibold))
                    Text("Los códigos son distintos en cada formulario")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)
            } else {
                Text("Guardado. Puedes volver a abrir esta ventana para consultar los enlaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }

            Spacer(minLength: 8)

            if result == nil {
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                    .disabled(isPublishing)

                Button {
                    if let columnId = selectedColumnId {
                        onPublish(columnId, baseURL, expiresAt)
                    }
                } label: {
                    if isPublishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Publicar")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPublishing || selectedColumnId == nil || baseURL.isEmpty)
            } else {
                Button("Hecho") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func copyToClipboard(_ texto: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        #else
        UIPasteboard.general.string = texto
        #endif
    }
}

#if DEBUG
struct WebSubmissionPublishSheet_Previews: PreviewProvider {
    @State private static var url = "https://entregas-alumnado.vercel.app"

    static var previews: some View {
        Group {
            WebSubmissionPublishSheet(
                classId: 7,
                className: "1º Bachillerato A",
                instruments: [
                    WebPublishableInstrument(
                        columnId: "c1",
                        columnTitle: "Portafolio técnico",
                        templateTitle: "Rúbrica de portafolio técnico",
                        itemCount: 53,
                        alreadyPublished: false
                    ),
                    WebPublishableInstrument(
                        columnId: "c2",
                        columnTitle: "Fair play",
                        templateTitle: "Rejilla de observación de fair play",
                        itemCount: 8,
                        alreadyPublished: true
                    ),
                ],
                baseURL: .constant("https://entregas-alumnado.vercel.app"),
                isPublishing: false,
                onPublish: { _, _, _ in },
                result: nil
            )
            .previewDisplayName("Antes de publicar")

            WebSubmissionPublishSheet(
                classId: 7,
                className: "1º Bachillerato A",
                instruments: [],
                baseURL: .constant("https://entregas-alumnado.vercel.app"),
                isPublishing: false,
                onPublish: { _, _, _ in },
                result: WebPublishResult(
                    formInstanceId: "11111111-1111-4111-8111-111111111111",
                    title: "Rúbrica de portafolio técnico",
                    manifestPath: "/Users/tu/Documents/EntregasWeb/1111…/manifiesto.json",
                    linksPath: "/Users/tu/Documents/EntregasWeb/1111…/enlaces-alumnado.txt",
                    folderPath: "/Users/tu/Documents/EntregasWeb/1111…",
                    links: [
                        WebPublishedLink(studentId: 42, studentName: "Ana Ferrer", url: "https://entregas-alumnado.vercel.app/#a=QragffpD_hfwuYPbQ5X1ZQ"),
                        WebPublishedLink(studentId: 43, studentName: "Bruno Gil", url: "https://entregas-alumnado.vercel.app/#a=0uX2-1WH-OyGLIiiPQjPfw"),
                    ],
                    linksText: "Ana Ferrer  https://…"
                )
            )
            .previewDisplayName("Ya publicado")

            WebSubmissionPublishSheet(
                classId: 7,
                className: "1º Bachillerato B",
                instruments: [],
                baseURL: .constant("https://entregas-alumnado.vercel.app"),
                isPublishing: false,
                onPublish: { _, _, _ in },
                result: nil
            )
            .previewDisplayName("Sin instrumentos")
        }
    }
}
#endif
