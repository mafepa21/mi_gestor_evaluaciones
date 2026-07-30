#if DEBUG
import SwiftUI
import MiGestorKit

/// Banco de pruebas de las entregas del alumnado. **Solo DEBUG.**
///
/// Existe porque el circuito no se puede probar todavía de verdad: falta la parte
/// que publica un formulario, así que sin esto no hay ningún `formInstanceId`
/// registrado, ninguna clave en el llavero ni ninguna fila de alias contra la que
/// importar. Este banco monta ese estado a mano para poder ver el flujo completo
/// en Xcode antes de escribir la publicación.
///
/// Lo que hace "Preparar la prueba":
///   1. Crea una columna de instrumento en la primera clase, con los cinco tipos
///      de ítem reales (uno de cada).
///   2. Registra el formulario del fixture apuntando a esa columna.
///   3. Guarda la clave privada del fixture en el llavero.
///   4. Mapea los `webItemId` del fixture a los ítems recién creados.
///   5. Asigna el alias del fixture al primer alumno o alumna del grupo.
///   6. Escribe el sobre del fixture como `.mgsub` en Documentos, para poder
///      elegirlo en el selector de ficheros.
///
/// Cuando exista la publicación de formularios, este fichero se borra.
struct WebSubmissionTestBenchView: View {
    @EnvironmentObject private var bridge: KmpBridge

    @State private var log: [String] = []
    @State private var preparing = false
    @State private var snapshot: WebSubmissionSnapshot?
    @State private var importing = false
    @State private var outcome: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Entregas del alumnado (banco de pruebas)")
                .font(.headline)

            Text("Solo para desarrollo. Monta a mano el estado que aún no puede crear la app, porque falta la parte de publicar formularios.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    Task { await prepare() }
                } label: {
                    if preparing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("1. Preparar la prueba")
                    }
                }
                .disabled(preparing)

                if let snapshot {
                    WebSubmissionImportButton(
                        formTitle: snapshot.title,
                        manifest: Self.fixtureManifest,
                        service: WebSubmissionImportService(
                            resolver: WebSubmissionSnapshotResolver(snapshot: snapshot)
                        ),
                        roster: snapshot.roster,
                        isImporting: importing,
                        onConfirm: { decisiones in
                            Task { await confirm(decisiones, snapshot: snapshot) }
                        }
                    )
                }
            }

            if let outcome {
                Text(outcome)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if !log.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, linea in
                        Text(linea)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(appTertiarySystemFillColor(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Fixture

    private static var fixtureManifest: WebFormManifest {
        // Si esto falla, el fixture y los modelos del contrato se han desalineado,
        // y es mejor enterarse aquí que en la pantalla de importación.
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(
            WebFormManifest.self,
            from: Data(WebSubmissionFixture.manifestJSON.utf8)
        )
    }

    // MARK: - Preparar

    private func prepare() async {
        preparing = true
        log = []
        outcome = nil
        defer { preparing = false }

        do {
            let manifiesto = Self.fixtureManifest
            anotar("Manifiesto leído: \(manifiesto.items.count) ítems, \(Set(manifiesto.items.map(\.type)).count) tipos distintos.")

            let resultado = try await bridge.prepareWebSubmissionTestForm(
                formInstanceId: WebSubmissionFixture.formInstanceId,
                title: manifiesto.title,
                recipientPublicKey: manifiesto.recipientKey,
                publisherPublicKey: manifiesto.publisherKey,
                manifestJson: WebSubmissionFixture.manifestJSON,
                items: manifiesto.items.map { ($0.webItemId, $0.title, $0.type) },
                alias: WebSubmissionFixture.participantAlias
            )
            anotar("Clase \(resultado.classId), columna \(resultado.columnId).")
            anotar("Alias asignado a: \(resultado.studentName).")

            guard WebSubmissionKeychain.save(
                privateKey: Data(base64URLEncoded: WebSubmissionFixture.recipientPrivateKeyBase64URL) ?? Data(),
                reference: WebSubmissionKeychain.reference(for: WebSubmissionFixture.formInstanceId)
            ) else {
                anotar("NO se pudo guardar la clave en el llavero.")
                return
            }
            anotar("Clave privada guardada en el llavero.")

            let ruta = try escribirSobre()
            anotar("Sobre de prueba escrito en:")
            anotar(ruta.path)

            snapshot = await bridge.loadWebSubmissionSnapshot(
                formInstanceId: WebSubmissionFixture.formInstanceId
            )
            if snapshot == nil {
                anotar("El formulario no se pudo volver a leer de la base de datos.")
            } else {
                anotar("Listo. Pulsa el botón de importar y elige ese fichero.")
            }
        } catch {
            anotar("Error: \(error.localizedDescription)")
        }
    }

    /// Escribe el sobre del fixture en Documentos para poder elegirlo con el
    /// selector de ficheros, que es el camino real que usará el alumnado.
    private func escribirSobre() throws -> URL {
        let documentos = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destino = documentos.appendingPathComponent("prueba-entrega.mgsub")
        try Data(WebSubmissionFixture.envelopeJSON.utf8).write(to: destino)
        return destino
    }

    // MARK: - Importar

    private func confirm(_ decisiones: [WebSubmissionImportDecision], snapshot: WebSubmissionSnapshot) async {
        importing = true
        defer { importing = false }
        let resultado = await bridge.importWebSubmissions(
            decisiones,
            formInstanceId: snapshot.formInstanceId
        )
        outcome = resultado.summary
        anotar(resultado.summary)
        for fallo in resultado.failures {
            anotar("Falló \(fallo.studentName): \(fallo.reason)")
        }
        // Se recarga para que la segunda importación vea la entrega como repetida:
        // es la comprobación de idempotencia, y conviene poder verla en pantalla.
        self.snapshot = await bridge.loadWebSubmissionSnapshot(
            formInstanceId: snapshot.formInstanceId
        )
        anotar("Vuelve a importar el mismo fichero: debe salir como «Ya importadas».")
    }

    private func anotar(_ linea: String) {
        log.append(linea)
    }
}
#endif
