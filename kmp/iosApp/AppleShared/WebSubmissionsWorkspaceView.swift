import SwiftUI
import MiGestorKit

/// Las dos mitades del circuito de entregas web, juntas: publicar un formulario y
/// recoger las entregas.
///
/// Van en la misma vista porque son el mismo trabajo visto desde los dos extremos,
/// y separarlas obligaría al docente a recordar en qué pantalla estaba cada cosa.
///
/// **Su sitio definitivo está sin decidir.** Hoy se muestra desde Ajustes →
/// Diagnóstico para poder usarla, pero eso es un aparcamiento, no una decisión: es
/// una función de trabajo diario, no una herramienta de soporte.
struct WebSubmissionsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge

    /// Se recuerda entre sesiones: la dirección de la web no cambia cada vez.
    @AppStorage("webSubmissions.baseURL") private var baseURL = "https://entregas-alumnado.vercel.app"
    /// También se recuerda: el correo de entrega no cambia de un formulario a otro.
    @AppStorage("webSubmissions.deliveryEmail") private var deliveryEmail = ""

    @State private var selectedClassId: Int64?
    @State private var instruments: [WebPublishableInstrument] = []
    @State private var loading = false

    @State private var showingPublish = false
    @State private var publishing = false
    @State private var publishResult: WebPublishResult?
    @State private var errorMessage: String?

    @State private var importSnapshot: WebSubmissionSnapshot?
    @State private var importManifest: WebFormManifest?
    @State private var importing = false
    @State private var importSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Entregas del alumnado por web")
                .font(.headline)

            Text("Publica un formulario, reparte los enlaces y recoge las respuestas en el Cuaderno.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            classPicker

            HStack(spacing: 12) {
                Button {
                    publishResult = nil
                    showingPublish = true
                } label: {
                    Label("Publicar un formulario", systemImage: "paperplane")
                }
                .disabled(selectedClassId == nil || loading)

                if let importSnapshot, let importManifest {
                    WebSubmissionImportButton(
                        formTitle: importSnapshot.title,
                        manifest: importManifest,
                        service: WebSubmissionImportService(
                            resolver: WebSubmissionSnapshotResolver(snapshot: importSnapshot)
                        ),
                        roster: importSnapshot.roster,
                        isImporting: importing,
                        onConfirm: { decisiones in
                            Task { await confirmImport(decisiones, snapshot: importSnapshot) }
                        }
                    )
                }

                if loading { ProgressView().controlSize(.small) }
            }

            if let importSummary {
                Text(importSummary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }

            publishedFormsList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: selectedClassId) { await reload() }
        .onAppear {
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
            }
        }
        .sheet(isPresented: $showingPublish) {
            WebSubmissionPublishSheet(
                classId: selectedClassId ?? 0,
                className: currentClassName,
                instruments: instruments,
                baseURL: $baseURL,
                deliveryEmail: $deliveryEmail,
                isPublishing: publishing,
                onPublish: { columnId, url, correo, caducidad in
                    Task {
                        await publish(
                            columnId: columnId,
                            baseURL: url,
                            deliveryEmail: correo,
                            expiresAt: caducidad
                        )
                    }
                },
                result: publishResult
            )
        }
        .alert(
            "No se pudo publicar",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in if !visible { errorMessage = nil } }
            )
        ) {
            Button("Entendido") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Grupo

    @ViewBuilder
    private var classPicker: some View {
        if bridge.classes.isEmpty {
            Text("Crea primero un grupo con alumnado.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Grupo", selection: Binding(
                get: { selectedClassId ?? bridge.classes.first?.id ?? 0 },
                set: { selectedClassId = $0 }
            )) {
                ForEach(bridge.classes, id: \.id) { clase in
                    Text(clase.name).tag(clase.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var currentClassName: String {
        bridge.classes.first(where: { $0.id == selectedClassId })?.name ?? "Grupo"
    }

    // MARK: - Formularios ya publicados

    @ViewBuilder
    private var publishedFormsList: some View {
        let publicados = instruments.filter(\.alreadyPublished)
        if !publicados.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Con formulario activo")
                    .font(.caption.weight(.bold))
                ForEach(publicados) { instrumento in
                    Text("· \(instrumento.templateTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(appTertiarySystemFillColor(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Acciones

    private func reload() async {
        guard let classId = selectedClassId else { return }
        loading = true
        defer { loading = false }

        instruments = await bridge.listPublishableWebForms(classId: classId)

        // Se prepara el importador con el formulario activo más reciente del grupo.
        // Si hay varios, gana el último publicado: es el que tiene los enlaces que
        // el alumnado está usando ahora.
        importSnapshot = nil
        importManifest = nil
        guard let instancias = try? await bridge.listWebFormInstances(classId: classId),
              let ultima = instancias.first(where: { !$0.revoked }) else { return }

        if let snapshot = await bridge.loadWebSubmissionSnapshot(formInstanceId: ultima.formInstanceId),
           let manifiesto = try? JSONDecoder().decode(
               WebFormManifest.self,
               from: Data(ultima.manifestJson.utf8)
           ) {
            importSnapshot = snapshot
            importManifest = manifiesto
        }
    }

    private func publish(
        columnId: String,
        baseURL url: String,
        deliveryEmail correo: String,
        expiresAt: Date
    ) async {
        guard let classId = selectedClassId else { return }
        publishing = true
        defer { publishing = false }
        do {
            publishResult = try await bridge.publishWebForm(
                classId: classId,
                columnId: columnId,
                baseURL: url,
                deliveryEmail: correoLimpio(correo),
                expiresAt: expiresAt
            )
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            showingPublish = false
        }
    }

    /// El campo vacío tiene que llegar como `nil` y no como cadena vacía: el
    /// manifiesto solo lleva `deliveryEmail` si de verdad hay un correo.
    private func correoLimpio(_ texto: String) -> String? {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return limpio.isEmpty ? nil : limpio
    }

    private func confirmImport(
        _ decisiones: [WebSubmissionImportDecision],
        snapshot: WebSubmissionSnapshot
    ) async {
        importing = true
        defer { importing = false }
        let resultado = await bridge.importWebSubmissions(
            decisiones,
            formInstanceId: snapshot.formInstanceId
        )
        importSummary = resultado.summary
        await reload()
    }
}
