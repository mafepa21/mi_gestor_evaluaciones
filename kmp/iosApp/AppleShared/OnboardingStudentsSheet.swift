import SwiftUI
import UniformTypeIdentifiers

/// Alta de alumnado del paso 4 del onboarding, con los dos caminos a la misma
/// altura: importar el Excel del centro, o escribir los nombres a mano.
///
/// Existe porque hasta ahora la importación de alumnado solo tenía punto de
/// entrada en macOS (`MacStudentsView`); en iPad/iPhone no había forma de
/// llegar a `StudentImportSheet`. Ambos caminos terminan en esa misma hoja de
/// revisión, así que duplicidad de lógica: ninguna.
struct OnboardingStudentsSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    /// `true` abre directamente el selector de archivos; `false` deja el foco
    /// en el cuadro de nombres. Lo decide el botón que se pulsó en la lista.
    let startWithImport: Bool
    let onFinished: () -> Void

    @State private var isFileImporterPresented = false
    @State private var manualNames = ""
    @State private var preview: AppleStudentImportPreview?
    @State private var errorMessage: String?
    @State private var isParsing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    importCard
                    manualCard
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppleDesignSystem.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .background(appPageBackground(for: colorScheme))
        #if os(macOS)
        .frame(minWidth: 580, idealWidth: 640, minHeight: 520, idealHeight: 600)
        #endif
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.xlsx, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFile(result) }
        }
        .sheet(item: $preview) { preview in
            StudentImportSheet(preview: preview)
                .environmentObject(bridge)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 620)
                #endif
                .onDisappear { onFinished() }
        }
        .task {
            if startWithImport {
                isFileImporterPresented = true
            }
        }
    }

    // MARK: - Secciones

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Añadir alumnado")
                .font(.title2.weight(.bold))
            Text("Elige el camino que te venga mejor. En los dos casos podrás revisar la lista y el grupo destino antes de guardar nada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var importCard: some View {
        card(
            systemImage: "square.and.arrow.down",
            title: "Importar del Excel del centro",
            detail: "Vale el listado tal cual lo exporta el centro (.xlsx o .csv), con los alumnos numerados."
        ) {
            Button("Elegir archivo") { isFileImporterPresented = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var manualCard: some View {
        card(
            systemImage: "text.cursor",
            title: "Escribir los nombres",
            detail: "Un alumno por línea, apellidos primero. Ejemplo: García López Antonio."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $manualNames)
                    .font(.body)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(appMutedCardBackground(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppleDesignSystem.border, lineWidth: 1)
                            )
                    )
                    #if os(iOS)
                    .autocorrectionDisabled()
                    #endif

                HStack {
                    Text(manualCountLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Revisar lista") {
                        Task { await parseManualNames() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualLines.isEmpty || isParsing)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cerrar", action: onFinished)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(20)
    }

    private func card<Content: View>(
        systemImage: String,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(EvaluationDesign.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(EvaluationDesign.accent.opacity(0.12))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appCardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppleDesignSystem.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Lógica

    private var manualLines: [String] {
        manualNames
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var manualCountLabel: String {
        let count = manualLines.count
        if count == 0 { return "Sin nombres todavía" }
        return count == 1 ? "1 nombre" : "\(count) nombres"
    }

    @MainActor
    private func handleFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            preview = try await bridge.previewStudentImport(tsv: rows.tsvText)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func parseManualNames() async {
        isParsing = true
        defer { isParsing = false }
        do {
            preview = try await bridge.previewStudentImport(tsv: manualTsv())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// El parser compartido (`XlsxStudentImporter`) espera el formato del Excel
    /// del centro: ocho filas de cabecera y, a partir de ahí, `N.` + nombre. Se
    /// reproduce ese formato aquí en vez de tocar el parser en KMP, que es
    /// código compartido y protegido. Las filas de relleno nunca se ven.
    private func manualTsv() -> String {
        var lines: [String] = Array(repeating: "MiGestor", count: 8)
        for (index, name) in manualLines.enumerated() {
            lines.append("\(index + 1).\t\(name)")
        }
        return lines.joined(separator: "\n")
    }
}
