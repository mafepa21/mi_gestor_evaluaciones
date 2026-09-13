import MiGestorKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Sheet

/// Sheet que guía al docente para exportar las notas del cuaderno al formato Educamos SM.
///
/// Flujo: Importar plantilla → Revisar matching de alumnos e instrumentos → Generar y compartir xlsx.
struct EducamosSMExportSheet: View {
    let data: NotebookUiStateData
    let bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var step: ExportStep = .selectFile
    @State private var template: EducamosSMTemplate?
    @State private var matchedColumns: [MatchedColumn] = []
    @State private var matchedStudents: [StudentMatch] = []
    @State private var totalGradesToExport: Int = 0
    @State private var isFileImporterPresented = false
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var generatedFileURL: URL?

    enum ExportStep {
        case selectFile
        case reviewMatching
        case export
    }

    struct MatchedColumn: Identifiable {
        let id: String // columnLetter ("G", "H", "I", "M"...)
        let educamosElement: EducamosSMElement
        let appColumn: NotebookColumnDefinition?
        let isCategorySA: Bool
        let appTabTitle: String?

        var isMatched: Bool {
            appColumn != nil || appTabTitle != nil || educamosElement.isNotaFinal
        }

        var sourceTitle: String {
            if let col = appColumn {
                return col.title
            } else if let tab = appTabTitle {
                return tab
            } else if educamosElement.isNotaFinal {
                return "Media evaluación"
            }
            return "-"
        }

        var kindDescription: String {
            if educamosElement.isNotaFinal {
                return "Nota final evaluación"
            } else if isCategorySA {
                return "Media Situación de Aprendizaje"
            } else {
                return "Instrumento de evaluación"
            }
        }
    }

    struct StudentGradeEntry: Identifiable {
        var id: String { columnLetter }
        let columnLetter: String
        let value: EducamosSMCellValue
        let displayLabel: String
    }

    struct StudentMatch: Identifiable {
        let id: String // PersonaId de Educamos
        let educamosStudent: EducamosSMStudent
        var appStudent: Student?
        var grades: [StudentGradeEntry] = []

        var hasMatch: Bool { appStudent != nil }
        var hasGrades: Bool { !grades.isEmpty }
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

                Text("Selecciona el archivo .xlsx descargado de Educamos. La app completará las columnas de instrumentos, la media de la Situación de Aprendizaje y la nota final.")
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
                    ForEach(matchedColumns) { col in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("\(col.educamosElement.shortName)")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Columna \(col.id)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Text(col.kindDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if col.isMatched {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(col.sourceTitle)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                            } else {
                                Text("Sin columna en cuaderno")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Columnas detectadas")
                } footer: {
                    let matchedCount = matchedColumns.filter(\.isMatched).count
                    Text("\(matchedCount) de \(matchedColumns.count) columnas emparejadas con el cuaderno.")
                }

                Section {
                    ForEach(matchedStudents) { match in
                        HStack(spacing: 10) {
                            Text("\(match.educamosStudent.orderNumber)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 3) {
                                if !match.educamosStudent.rawName.isEmpty && match.educamosStudent.rawName != "\(match.educamosStudent.orderNumber)" {
                                    Text(match.educamosStudent.rawName)
                                        .font(.subheadline.weight(.medium))
                                }

                                if let student = match.appStudent {
                                    HStack(spacing: 4) {
                                        Text("\(student.lastName), \(student.firstName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !match.grades.isEmpty {
                                        Text(match.grades.map(\.displayLabel).joined(separator: " · "))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.blue)
                                    } else {
                                        Text("Sin calificaciones registradas")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                } else {
                                    Text("Sin coincidencia en el grupo")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            Image(systemName: match.hasMatch ? (match.hasGrades ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "xmark.circle")
                                .foregroundStyle(match.hasMatch ? (match.hasGrades ? .green : .orange) : .red)
                        }
                    }
                } header: {
                    Text("Matching de alumnos")
                } footer: {
                    let matchCount = matchedStudents.filter(\.hasMatch).count
                    let withGradesCount = matchedStudents.filter(\.hasGrades).count
                    Text("\(matchCount) alumnos emparejados · \(withGradesCount) con notas registradas (\(totalGradesToExport) calificaciones a escribir)")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    Task { await generateExport() }
                } label: {
                    if isProcessing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            "Generar archivo (\(totalGradesToExport) calificaciones)",
                            systemImage: "doc.badge.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(totalGradesToExport == 0 || isProcessing)
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
                Text("Archivo generado con éxito")
                    .font(.headline)

                Text("Se han rellenado \(totalGradesToExport) calificaciones en las columnas de instrumentos, Situación de Aprendizaje y nota final del archivo de Educamos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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

    /// Empareja columnas, pestañas de SA y alumnos de Educamos con los datos del cuaderno.
    private func buildMatching(template: EducamosSMTemplate) {
        let appStudents = filteredAppStudents

        // 1. Emparejar columnas e instrumentos
        var columnMatches: [MatchedColumn] = []

        for element in template.elements {
            if element.isInstrumento {
                // Buscar columna del cuaderno cuyo título coincida con el nombre corto
                let matchedCol = data.sheet.columns.first { col in
                    col.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare(element.shortName) == .orderedSame
                } ?? data.sheet.columns.first { col in
                    col.title.localizedCaseInsensitiveContains(element.shortName)
                }

                columnMatches.append(MatchedColumn(
                    id: element.columnLetter,
                    educamosElement: element,
                    appColumn: matchedCol,
                    isCategorySA: false,
                    appTabTitle: nil
                ))
            } else if element.isCategoriaSA {
                // Buscar pestaña (SA) cuyo título coincida con el nombre corto (ej. "Handball" <-> "Hand")
                let matchedTab = data.sheet.tabs.first { tab in
                    tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare(element.shortName) == .orderedSame
                } ?? data.sheet.tabs.first { tab in
                    tab.title.localizedCaseInsensitiveContains(element.shortName) ||
                    element.shortName.localizedCaseInsensitiveContains(tab.title)
                }

                columnMatches.append(MatchedColumn(
                    id: element.columnLetter,
                    educamosElement: element,
                    appColumn: nil,
                    isCategorySA: true,
                    appTabTitle: matchedTab?.title
                ))
            } else if element.isNotaFinal {
                columnMatches.append(MatchedColumn(
                    id: element.columnLetter,
                    educamosElement: element,
                    appColumn: nil,
                    isCategorySA: false,
                    appTabTitle: nil
                ))
            }
        }

        matchedColumns = columnMatches

        // 2. Emparejar alumnos
        matchedStudents = template.students.map { educamosStudent in
            var matchedAppStudent: Student? = nil

            let educamosTokens = Set(normalizedTokens(educamosStudent.rawName))
            if !educamosTokens.isEmpty {
                matchedAppStudent = appStudents.first { candidate in
                    let candidateTokens = Set(normalizedTokens("\(candidate.firstName) \(candidate.lastName)"))
                    return candidateTokens == educamosTokens
                }

                if matchedAppStudent == nil {
                    matchedAppStudent = appStudents.first { candidate in
                        let firstTokens = Set(normalizedTokens(candidate.firstName))
                        let lastTokens = Set(normalizedTokens(candidate.lastName))
                        return (firstTokens.isSubset(of: educamosTokens) && !lastTokens.intersection(educamosTokens).isEmpty)
                            || (lastTokens.isSubset(of: educamosTokens) && !firstTokens.intersection(educamosTokens).isEmpty)
                    }
                }
            }

            if matchedAppStudent == nil {
                let index = educamosStudent.orderNumber - 1
                if index >= 0 && index < appStudents.count {
                    matchedAppStudent = appStudents[index]
                }
            }

            // 3. Extraer calificaciones para las columnas emparejadas
            var studentGrades: [StudentGradeEntry] = []

            if let student = matchedAppStudent {
                let tableRow = data.sheet.rows.first { $0.student.id == student.id }

                for colMatch in columnMatches {
                    let el = colMatch.educamosElement

                    // A) Instrumento individual
                    if let appCol = colMatch.appColumn {
                        let raw: String = {
                            switch appCol.type {
                            case .rubric:
                                return bridge.rubricGradeOnTenText(studentId: student.id, column: appCol)
                            case .numeric, .calculated:
                                return bridge.numericGradeText(studentId: student.id, column: appCol)
                            default:
                                return bridge.cellText(studentId: student.id, columnId: appCol.id)
                            }
                        }()

                        if let num = NotebookFormulaDisplay.parseNumber(raw) {
                            studentGrades.append(StudentGradeEntry(
                                columnLetter: el.columnLetter,
                                value: .decimal(num),
                                displayLabel: "\(el.shortName): \(IosFormatting.decimal(num))"
                            ))
                        }
                    }
                    // B) Media de Situación de Aprendizaje (SA)
                    else if colMatch.isCategorySA && colMatch.appTabTitle != nil {
                        if let avg = tableRow?.weightedAverage?.doubleValue {
                            studentGrades.append(StudentGradeEntry(
                                columnLetter: el.columnLetter,
                                value: .decimal(avg),
                                displayLabel: "\(el.shortName) (SA): \(IosFormatting.decimal(avg))"
                            ))
                        }
                    }
                    // C) Nota final de evaluación (entero 0-10)
                    else if el.isNotaFinal {
                        if let avg = tableRow?.weightedAverage?.doubleValue {
                            let intGrade = max(0, min(10, Int(avg.rounded())))
                            studentGrades.append(StudentGradeEntry(
                                columnLetter: el.columnLetter,
                                value: .integer(intGrade),
                                displayLabel: "Nota: \(intGrade)"
                            ))
                        }
                    }
                }
            }

            return StudentMatch(
                id: educamosStudent.personaId,
                educamosStudent: educamosStudent,
                appStudent: matchedAppStudent,
                grades: studentGrades
            )
        }

        totalGradesToExport = matchedStudents.reduce(0) { $0 + $1.grades.count }
    }

    private func normalizedTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.uppercased() }
    }

    private func generateExport() async {
        guard let template else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            var cellWrites: [EducamosSMXlsxWriter.CellWrite] = []

            for match in matchedStudents {
                guard match.hasMatch else { continue }
                let row = match.educamosStudent.rowIndex

                for grade in match.grades {
                    let cellRef = "\(grade.columnLetter)\(row)"
                    cellWrites.append(.init(
                        cellReference: cellRef,
                        value: grade.value
                    ))
                }
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
