import MiGestorKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Sheet

/// Sheet que guía al docente para exportar las notas del cuaderno al formato Educamos SM.
///
/// Flujo: Importar plantilla → Revisar matching alumnos → Generar y compartir xlsx.
struct EducamosSMExportSheet: View {
    let data: NotebookUiStateData
    let bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var step: ExportStep = .selectFile
    @State private var template: EducamosSMTemplate?
    @State private var matchedStudents: [StudentMatch] = []
    @State private var isFileImporterPresented = false
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var generatedFileURL: URL?

    enum ExportStep {
        case selectFile
        case reviewMatching
        case export
    }

    struct StudentMatch: Identifiable {
        let id: String // PersonaId de Educamos
        let educamosStudent: EducamosSMStudent
        var appStudent: Student?
        var notaFinal: Int?

        var hasMatch: Bool { appStudent != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectFile:
                    selectFileView
                case .reviewMatching:
                    reviewMatchingView
                case .export:
                    exportView
                }
            }
            .navigationTitle("Exportar a Educamos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.xlsx],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleFileImport(result) }
            }
        }
    }

    // MARK: - Step 1: Select file

    private var selectFileView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Exportar notas a Educamos SM")
                    .font(.headline)

                Text("Selecciona el archivo .xlsx que has descargado de Educamos para rellenar las notas automáticamente con las medias del cuaderno.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Seleccionar archivo de Educamos", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Step 2: Review matching

    private var reviewMatchingView: some View {
        List {
            if let template {
                Section {
                    LabeledContent("Materia", value: template.metadata.materia)
                    LabeledContent("Evaluación", value: template.metadata.evaluacion)
                    LabeledContent("Curso", value: template.metadata.cursoEscolar)
                    LabeledContent("Alumnos Educamos", value: "\(template.students.count)")
                    LabeledContent("Alumnos cuaderno", value: "\(filteredAppStudents.count)")
                } header: {
                    Text("Plantilla Educamos")
                }

                Section {
                    ForEach(matchedStudents) { match in
                        HStack {
                            // Número de orden
                            Text("\(match.educamosStudent.orderNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            // Nombre del alumno de la app
                            if let student = match.appStudent {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(student.lastName), \(student.firstName)")
                                        .font(.body)
                                    if let nota = match.notaFinal {
                                        Text("Nota: \(nota)")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    } else {
                                        Text("Sin nota")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            } else {
                                Text("Sin asignar")
                                    .foregroundStyle(.red)
                            }

                            Spacer()

                            // Indicador de estado
                            Image(systemName: match.hasMatch ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(match.hasMatch ? .green : .red)
                        }
                    }
                } header: {
                    Text("Matching de alumnos")
                } footer: {
                    let matchCount = matchedStudents.filter(\.hasMatch).count
                    let withGrade = matchedStudents.filter { $0.notaFinal != nil }.count
                    Text("\(matchCount) alumnos emparejados · \(withGrade) con nota")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                let matchCount = matchedStudents.filter(\.hasMatch).count
                let withGrade = matchedStudents.filter { $0.notaFinal != nil }.count

                Button {
                    Task { await generateExport() }
                } label: {
                    if isProcessing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            "Generar archivo (\(withGrade) notas)",
                            systemImage: "doc.badge.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(withGrade == 0 || isProcessing)
            }
            .padding()
            .background(.bar)
        }
    }

    // MARK: - Step 3: Export result

    private var exportView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Archivo generado")
                    .font(.headline)

                let withGrade = matchedStudents.filter { $0.notaFinal != nil }.count
                Text("\(withGrade) notas rellenadas en el archivo de Educamos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let url = generatedFileURL {
                ShareLink(item: url) {
                    Label("Compartir archivo", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
            }

            Button {
                dismiss()
            } label: {
                Text("Cerrar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Data helpers

    /// Alumnos de la app filtrados por el grupo actual del cuaderno.
    private var filteredAppStudents: [Student] {
        data.sheet.rows.map(\.student)
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorMessage = "No se ha seleccionado ningún archivo."
                return
            }

            do {
                let parsed = try EducamosSMTemplateService.parse(from: url)
                template = parsed
                buildMatching(template: parsed)
                withAnimation { step = .reviewMatching }
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Empareja alumnos de Educamos con alumnos de la app por número de orden.
    private func buildMatching(template: EducamosSMTemplate) {
        let appStudents = filteredAppStudents

        matchedStudents = template.students.map { educamosStudent in
            // Matching por número de orden (1-based)
            let index = educamosStudent.orderNumber - 1
            let appStudent = index >= 0 && index < appStudents.count ? appStudents[index] : nil

            // Calcular nota final redondeada
            var notaFinal: Int?
            if let student = appStudent {
                let row = data.sheet.rows.first { $0.student.id == student.id }
                if let avg = row?.weightedAverage?.doubleValue {
                    notaFinal = max(0, min(10, Int(avg.rounded())))
                }
            }

            return StudentMatch(
                id: educamosStudent.personaId,
                educamosStudent: educamosStudent,
                appStudent: appStudent,
                notaFinal: notaFinal
            )
        }
    }

    private func generateExport() async {
        guard let template else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Construir la lista de celdas a rellenar
            var cellWrites: [EducamosSMXlsxWriter.CellWrite] = []

            for match in matchedStudents {
                guard match.hasMatch else { continue }
                let row = match.educamosStudent.rowIndex

                // Nota final
                if let nota = match.notaFinal,
                   let notaElement = template.notaFinalElement {
                    let cellRef = "\(notaElement.columnLetter)\(row)"
                    cellWrites.append(.init(
                        cellReference: cellRef,
                        value: .numeric(nota)
                    ))
                }

                // Comentarios (si hay observaciones en la app)
                // Por ahora dejamos vacío — se puede expandir en fases futuras
            }

            let outputURL = try EducamosSMXlsxWriter.fillGrades(
                template: template,
                cells: cellWrites
            )

            generatedFileURL = outputURL
            withAnimation { step = .export }

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
