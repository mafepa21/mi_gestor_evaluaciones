import MiGestorKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Export Sheet

/// Hoja simplificada según Apple HIG para exportar las calificaciones del Cuaderno a Educamos SM.
///
/// Detecta automáticamente las columnas y pestañas del Cuaderno, transpone las escalas 1-4 a nota sobre 10
/// y oculta el ruido técnico para mostrar únicamente la información necesaria para exportar.
struct EducamosSMExportSheet: View {
    let data: NotebookUiStateData
    let bridge: KmpBridge
    /// Archivo generado: resumen («N notas y M comentarios») y dónde quedó. Lo usa «Cerrar evaluación».
    var onExported: ((String, URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var step: ExportStep = .selectFile
    @State private var template: EducamosSMTemplate?
    @State private var matchedColumns: [MatchedColumn] = []
    @State private var matchedStudents: [StudentMatch] = []
    @State private var totalGradesToExport: Int = 0
    @State private var totalCommentsToExport: Int = 0
    @State private var isFileImporterPresented = false
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var generatedFileURL: URL?
    @State private var savedToDownloadsPath: String?
    @State private var partialStudents: [EducamosPartialStudent] = []
    @State private var partialGradePolicy: EducamosPartialGradePolicy = .leaveEmpty
    @State private var partialPolicyLoaded = false
    @State private var showUnmatchedColumns = false
    @State private var showStudentDetails = false

    enum ExportStep {
        case selectFile
        case reviewMatching
        case export
    }

    struct MatchedColumn: Identifiable {
        let id: String // columnLetter ("G", "H", "I", "M"...)
        let educamosElement: EducamosSMElement
        var appColumn: NotebookColumnDefinition?
        let isCategorySA: Bool
        var appTab: NotebookTab?

        var appTabTitle: String? { appTab?.title }

        var isMatched: Bool {
            appColumn != nil || appTabTitle != nil || educamosElement.isNotaFinal
        }

        var sourceTitle: String {
            if let col = appColumn {
                return col.title
            } else if let tab = appTabTitle {
                return tab
            } else if educamosElement.isNotaFinal {
                return "Nota de evaluación"
            }
            return "No exportar"
        }
    }

    struct StudentGradeEntry: Identifiable {
        var id: String { columnLetter }
        let columnLetter: String
        let value: EducamosSMCellValue
        let displayLabel: String

        var isComment: Bool {
            if case .text = value { return true }
            return false
        }
    }

    struct StudentMatch: Identifiable {
        let id: String // PersonaId de Educamos
        let educamosStudent: EducamosSMStudent
        var appStudent: Student?
        var grades: [StudentGradeEntry] = []
        var matchedByOrder = false

        var hasMatch: Bool { appStudent != nil }
        var hasGrades: Bool { !grades.isEmpty }
        var hasComment: Bool { grades.contains { $0.isComment } }
        var numericGradeCount: Int { grades.filter { !$0.isComment }.count }
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
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.xlsx],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleFileImport(result) }
            }
        }
        .interactiveDismissDisabled(isProcessing)
        .appOnChange(of: errorMessage) { _ in
            if let errorMessage { AccessibilityNotification.Announcement(errorMessage).post() }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .selectFile, .reviewMatching: return "Exportar a Educamos"
        case .export: return "Archivo listo"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch step {
        case .selectFile:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
        case .reviewMatching:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .disabled(isProcessing)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await generateExport() }
                } label: {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Exportar")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerate)
                .accessibilityLabel(isProcessing ? "Exportando archivo" : "Exportar \(exportSummary)")
            }
        case .export:
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var canGenerate: Bool {
        (totalGradesToExport > 0 || totalCommentsToExport > 0) && !isProcessing
    }

    private func errorLabel(_ message: String) -> some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(EvaluationDesign.danger)
        }
        .font(.callout)
    }

    // MARK: - Step 1: Select file

    private var selectFileView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Plantilla de Educamos")
                    .font(.title3.weight(.semibold))

                Text("Selecciona el archivo .xlsx descargado de Educamos. Las columnas del Cuaderno se asocian solas y las escalas 1-4 se exportan sobre 10.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Seleccionar plantilla…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let errorMessage {
                errorLabel(errorMessage)
                    .frame(maxWidth: 400)
            }

            Spacer()
            Spacer()
        }
        .padding(32)
    }

    // MARK: - Step 2: Review matching (Apple HIG)

    private var orderMatchedCount: Int { matchedStudents.filter(\.matchedByOrder).count }
    private var unmatchedStudentCount: Int { matchedStudents.filter { !$0.hasMatch }.count }
    private var activeColumns: [MatchedColumn] { matchedColumns.filter(\.isMatched) }
    private var inactiveColumns: [MatchedColumn] { matchedColumns.filter { !$0.isMatched } }
    private var hasStudentIncidents: Bool { orderMatchedCount > 0 || unmatchedStudentCount > 0 }

    private var reviewMatchingView: some View {
        Form {
            if let errorMessage {
                Section { errorLabel(errorMessage) }
            }

            if let template {
                // 1. Cabecera compacta de contexto (1 fila en lugar de 6)
                Section {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(templateHeadline(template))
                                .font(.headline)
                            Text(templateSubtitle(template))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 8)

                        Button("Cambiar…") {
                            isFileImporterPresented = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isProcessing)
                    }
                    .padding(.vertical, 4)
                }

                // 2. Avisos accionables solo cuando requieren atención real
                if !partialStudents.isEmpty || hasStudentIncidents {
                    alertsSection
                }

                // 3. Columnas vinculadas automáticamente con el Cuaderno
                Section {
                    if activeColumns.isEmpty {
                        ForEach(matchedColumns) { col in
                            columnRow(col)
                        }
                    } else {
                        ForEach(activeColumns) { col in
                            columnRow(col)
                        }

                        if !inactiveColumns.isEmpty {
                            DisclosureGroup(
                                isExpanded: $showUnmatchedColumns
                            ) {
                                ForEach(inactiveColumns) { col in
                                    columnRow(col)
                                }
                            } label: {
                                Text(inactiveColumns.count == 1
                                     ? "1 columna de Educamos sin correspondencia"
                                     : "\(inactiveColumns.count) columnas de Educamos sin correspondencia")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Columnas a exportar")
                } footer: {
                    Text("Toca cualquier columna si quieres cambiar su correspondencia.")
                }

                // 4. Resumen compacto de exportación (sin volcar 30 filas por defecto)
                Section {
                    DisclosureGroup(isExpanded: $showStudentDetails) {
                        ForEach(matchedStudents) { match in
                            compactStudentRow(match)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: hasStudentIncidents ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(hasStudentIncidents ? .orange : EvaluationDesign.success)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Se exportarán \(exportSummary)")
                                    .font(.subheadline.weight(.medium))
                                Text("\(matchedStudents.filter(\.hasMatch).count) de \(matchedStudents.count) alumnos emparejados")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var alertsSection: some View {
        Section {
            if !partialStudents.isEmpty {
                Label {
                    Text(partialStudentsText)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Picker("Nota final incompleta", selection: $partialGradePolicy) {
                    ForEach(EducamosPartialGradePolicy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .appOnChange(of: partialGradePolicy) { policy in
                    policy.save(classId: data.sheet.classId)
                    if let template { buildStudentMatches(template: template) }
                }

                DisclosureGroup("Alumnos con bloques pendientes (\(partialStudents.count))") {
                    ForEach(partialStudents) { student in
                        LabeledContent(student.name) {
                            Text("Falta \(ListFormatter.localizedString(byJoining: student.missingBlocks))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
            }

            if orderMatchedCount > 0 {
                Label {
                    Text(orderMatchedCount == 1
                         ? "1 alumno emparejado por número de lista; revísalo abajo."
                         : "\(orderMatchedCount) alumnos emparejados por número de lista; revísalos abajo.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "list.number")
                        .foregroundStyle(.orange)
                }
            }

            if unmatchedStudentCount > 0 {
                Label {
                    Text(unmatchedStudentCount == 1
                         ? "1 alumno de Educamos no figura en este grupo."
                         : "\(unmatchedStudentCount) alumnos de Educamos no figuran en este grupo.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(EvaluationDesign.danger)
                }
            }
        }
    }

    private func templateHeadline(_ template: EducamosSMTemplate) -> String {
        let materia = template.metadata.materia.trimmingCharacters(in: .whitespacesAndNewlines)
        let eval = formattedEvaluationName(template.metadata.evaluacion)
        if materia.isEmpty { return eval }
        if eval.isEmpty { return materia }
        return "\(materia) · \(eval)"
    }

    private func templateSubtitle(_ template: EducamosSMTemplate) -> String {
        var parts: [String] = []
        let curso = template.metadata.cursoEscolar.trimmingCharacters(in: .whitespacesAndNewlines)
        if !curso.isEmpty { parts.append(curso) }
        parts.append("\(template.students.count) alumnos")
        return parts.joined(separator: " · ")
    }

    private func formattedEvaluationName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed == trimmed.uppercased() {
            return trimmed.lowercased().prefix(1).uppercased() + trimmed.lowercased().dropFirst()
        }
        return trimmed
    }

    private var partialStudentsText: String {
        let blocks = Set(partialStudents.flatMap(\.missingBlocks)).sorted()
        let names = ListFormatter.localizedString(byJoining: blocks)
        return partialStudents.count == 1
            ? "1 alumno sin notas en \(names)."
            : "\(partialStudents.count) alumnos sin notas en \(names)."
    }

    // MARK: - Filas limpias de columnas y alumnado

    private func columnRow(_ col: MatchedColumn) -> some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(col.educamosElement.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let code = col.educamosElement.secondaryCode {
                    Text(code)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if col.isCategorySA {
                    Text("SA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            columnSourceControl(col)
        }
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private func columnSourceControl(_ col: MatchedColumn) -> some View {
        if col.educamosElement.isInstrumento || col.educamosElement.isComentarios {
            columnPicker(for: col)
        } else if col.isCategorySA {
            tabPicker(for: col)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(EvaluationDesign.success)
                    .font(.footnote)
                    .accessibilityHidden(true)
                Text(col.sourceTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func tabPicker(for col: MatchedColumn) -> some View {
        let tabs = data.sheet.tabs
        let currentLabel = col.appTab.map { EducamosSATabMatcher.displayTitle($0, tabs: tabs) }
        return Menu {
            Button {
                chooseTab(nil, for: col)
            } label: {
                if col.appTab == nil {
                    Label("No exportar", systemImage: "checkmark")
                } else {
                    Text("No exportar")
                }
            }
            Divider()
            ForEach(EducamosSATabMatcher.candidateTabs(tabs), id: \.id) { tab in
                let title = EducamosSATabMatcher.displayTitle(tab, tabs: tabs)
                Button {
                    chooseTab(tab, for: col)
                } label: {
                    if tab.id == col.appTab?.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            pickerLabel(title: currentLabel, isMatched: col.appTab != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .help(currentLabel ?? "Sin pestaña asignada")
        .accessibilityLabel("Situación de aprendizaje para \(col.educamosElement.displayTitle)")
        .accessibilityValue(currentLabel ?? "No exportar")
    }

    private func columnPicker(for col: MatchedColumn) -> some View {
        Menu {
            Button {
                chooseColumn(nil, for: col)
            } label: {
                if col.appColumn == nil {
                    Label("No exportar", systemImage: "checkmark")
                } else {
                    Text("No exportar")
                }
            }

            Divider()

            ForEach(pickerColumns(for: col), id: \.id) { appCol in
                Button {
                    chooseColumn(appCol, for: col)
                } label: {
                    if appCol.id == col.appColumn?.id {
                        Label(appCol.title, systemImage: "checkmark")
                    } else {
                        Text(appCol.title)
                    }
                }
            }
        } label: {
            pickerLabel(title: col.appColumn?.title, isMatched: col.isMatched)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .help(col.appColumn?.title ?? "Sin columna asignada")
        .accessibilityLabel("Columna del Cuaderno para \(col.educamosElement.displayTitle)")
        .accessibilityValue(col.isMatched ? col.sourceTitle : "No exportar")
    }

    private func pickerLabel(title: String?, isMatched: Bool) -> some View {
        HStack(spacing: 6) {
            if isMatched, let title {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(EvaluationDesign.success)
                    .font(.footnote)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Elegir…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: 260, minHeight: 36, alignment: .trailing)
        .contentShape(Rectangle())
    }

    private func compactStudentRow(_ match: StudentMatch) -> some View {
        HStack(spacing: 12) {
            Text("\(match.educamosStudent.orderNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(studentDisplayName(match))
                    .font(.subheadline)
                    .lineLimit(1)

                if match.matchedByOrder, let student = match.appStudent {
                    Text("Por orden → \(student.lastName), \(student.firstName)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !match.hasMatch {
                    Text("Sin coincidencia en el grupo")
                        .font(.caption)
                        .foregroundStyle(EvaluationDesign.danger)
                }
            }

            Spacer(minLength: 8)

            if match.hasMatch {
                Text(studentSummaryBadge(match))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func studentDisplayName(_ match: StudentMatch) -> String {
        let raw = match.educamosStudent.rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty && raw != "\(match.educamosStudent.orderNumber)" {
            return raw
        }
        if let student = match.appStudent {
            return "\(student.lastName), \(student.firstName)"
        }
        return "Alumno \(match.educamosStudent.orderNumber)"
    }

    private func studentSummaryBadge(_ match: StudentMatch) -> String {
        let count = match.numericGradeCount
        if count == 0 && !match.hasComment { return "Sin notas" }
        var parts: [String] = []
        if count > 0 {
            parts.append(count == 1 ? "1 nota" : "\(count) notas")
        }
        if match.hasComment {
            parts.append("comentario")
        }
        return parts.joined(separator: " + ")
    }

    // MARK: - Step 3: Export result

    private var exportView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(EvaluationDesign.success)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Archivo generado")
                        .font(.title2.weight(.semibold))
                    Text("Se han escrito \(exportSummary) en la plantilla de Educamos.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                #if os(iOS) && !targetEnvironment(macCatalyst)
                Text("Usa «Compartir archivo» para guardarlo en Archivos o enviarlo al equipo donde abras Educamos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #endif

                if let savedPath = savedToDownloadsPath {
                    LabeledContent {
                        #if os(macOS)
                        Button("Mostrar en Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: savedPath)])
                        }
                        #endif
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Guardado en Descargas")
                                    .font(.subheadline.weight(.medium))
                                Text(URL(fileURLWithPath: savedPath).lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(EvaluationDesign.success)
                        }
                    }
                    .padding(16)
                    .background(EvaluationDesign.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    if let url = generatedFileURL {
                        Button {
                            saveToDownloads(sourceURL: url)
                        } label: {
                            Label("Guardar en Descargas", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    #endif
                }

                if let url = generatedFileURL {
                    ShareLink(item: url) {
                        Label("Compartir archivo", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let errorMessage { errorLabel(errorMessage) }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Al subirlo a Educamos")
                        .font(.subheadline.weight(.semibold))
                    Label("Súbelo en la misma evaluación de la que descargaste la plantilla.", systemImage: "1.circle")
                    Label("Conserva el archivo tal cual, sin reeditar su estructura en Excel.", systemImage: "2.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Data helpers

    private var filteredAppStudents: [Student] {
        data.sheet.rows.map(\.student)
    }

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
                showStudentDetails = hasStudentIncidents
                withAnimation { step = .reviewMatching }
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Elección manual recordada por grupo

    private var savedMappingKey: String {
        "educamos.sm.columnMapping.\(data.sheet.classId)"
    }

    private func savedMapping() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: savedMappingKey) as? [String: String] ?? [:]
    }

    private func chooseColumn(_ appColumn: NotebookColumnDefinition?, for col: MatchedColumn) {
        var mapping = savedMapping()
        mapping[EducamosColumnMatcher.mappingKey(for: col.educamosElement)] = appColumn?.id ?? ""
        UserDefaults.standard.set(mapping, forKey: savedMappingKey)

        guard let index = matchedColumns.firstIndex(where: { $0.id == col.id }) else { return }
        matchedColumns[index].appColumn = appColumn
        if let template {
            buildStudentMatches(template: template)
        }
    }

    private func chooseTab(_ tab: NotebookTab?, for col: MatchedColumn) {
        var mapping = savedMapping()
        mapping[EducamosColumnMatcher.mappingKey(for: col.educamosElement)] = tab.map { "tab:\($0.id)" } ?? ""
        UserDefaults.standard.set(mapping, forKey: savedMappingKey)

        guard let index = matchedColumns.firstIndex(where: { $0.id == col.id }) else { return }
        matchedColumns[index].appTab = tab
        if let template {
            buildStudentMatches(template: template)
        }
    }

    private func buildMatching(template: EducamosSMTemplate) {
        let resolved = EducamosColumnMatcher.matchElements(
            elements: template.elements,
            tabs: data.sheet.tabs,
            columns: data.sheet.columns,
            savedMapping: savedMapping(),
            excelEvaluation: template.metadata.evaluacion,
            activeTabId: bridge.selectedNotebookTabId
        )

        matchedColumns = resolved.map { item in
            MatchedColumn(
                id: item.element.columnLetter,
                educamosElement: item.element,
                appColumn: item.appColumn,
                isCategorySA: item.isCategorySA,
                appTab: item.appTab
            )
        }
        buildStudentMatches(template: template)
    }

    private func buildStudentMatches(template: EducamosSMTemplate) {
        let appStudents = filteredAppStudents
        let columnMatches = matchedColumns
        if !partialPolicyLoaded {
            partialGradePolicy = EducamosPartialGradePolicy.load(classId: data.sheet.classId)
            partialPolicyLoaded = true
        }
        let evaluationTabId = EducamosFinalGradeSource.evaluationTabId(
            tabs: data.sheet.tabs,
            excelEvaluation: template.metadata.evaluacion,
            activeTabId: bridge.selectedNotebookTabId
        )
        var partials: [EducamosPartialStudent] = []

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

            var matchedByOrder = false
            if matchedAppStudent == nil {
                let index = educamosStudent.orderNumber - 1
                if index >= 0 && index < appStudents.count {
                    matchedAppStudent = appStudents[index]
                    matchedByOrder = true
                }
            }

            var studentGrades: [StudentGradeEntry] = []

            if let student = matchedAppStudent {
                let tableRow = data.sheet.rows.first { $0.student.id == student.id }

                for colMatch in columnMatches {
                    let el = colMatch.educamosElement

                    // Comentario del profesor
                    if el.isComentarios {
                        if let appCol = colMatch.appColumn {
                            let text = bridge.cellText(studentId: student.id, columnId: appCol.id)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                studentGrades.append(StudentGradeEntry(
                                    columnLetter: el.columnLetter,
                                    value: .text(text),
                                    displayLabel: "Comentario"
                                ))
                            }
                        }
                    }
                    // A) Instrumento individual (transpuesto automáticamente sobre 10 si su escala es 1-4)
                    else if let appCol = colMatch.appColumn {
                        let rubricRaw: String = {
                            guard appCol.type == .rubric else { return "" }
                            let direct = bridge.rubricGradeText(studentId: student.id, column: appCol)
                            return !direct.isEmpty ? direct : bridge.rubricGradeOnTenText(studentId: student.id, column: appCol)
                        }()
                        let numericRaw = bridge.numericGradeText(studentId: student.id, columnId: appCol.id)

                        if let scoreOnTen = EducamosGradeExtractor.gradeOutOfTen(
                            row: tableRow,
                            column: appCol,
                            rubricText: rubricRaw,
                            numericText: numericRaw
                        ) {
                            studentGrades.append(StudentGradeEntry(
                                columnLetter: el.columnLetter,
                                value: .decimal(scoreOnTen),
                                displayLabel: "\(el.shortName): \(IosFormatting.decimal(scoreOnTen))"
                            ))
                        }
                    }
                    // B) Media de Situación de Aprendizaje (SA)
                    else if colMatch.isCategorySA, let saTab = colMatch.appTab {
                        let saAverage = tableRow.flatMap {
                            NotebookEvaluation.shared.tabAverage(row: $0, columns: data.sheet.columns, tabId: saTab.id, numericDrafts: [:])
                        }
                        if let avg = saAverage?.doubleValue {
                            studentGrades.append(StudentGradeEntry(
                                columnLetter: el.columnLetter,
                                value: .decimal(avg),
                                displayLabel: "\(el.shortName) (SA): \(IosFormatting.decimal(avg))"
                            ))
                        }
                    }
                    // C) Nota final de evaluación (entero 0-10)
                    else if el.isNotaFinal {
                        let evaluationExplanation = evaluationTabId.flatMap { evalId in
                            tableRow.flatMap {
                                NotebookEvaluation.shared.explain(row: $0, tabs: data.sheet.tabs, columns: data.sheet.columns, evaluationTabId: evalId, numericDrafts: [:])
                            }
                        }
                        if let explanation = evaluationExplanation, explanation.isPartial {
                            partials.append(EducamosPartialStudent(
                                id: student.id,
                                name: "\(student.lastName), \(student.firstName)",
                                missingBlocks: explanation.blocksWithoutGrades.map(\.title)
                            ))
                        }
                        let skipPartial = evaluationExplanation?.isPartial == true && partialGradePolicy == .leaveEmpty
                        let finalAverage = evaluationTabId == nil ? tableRow?.weightedAverage : evaluationExplanation?.average
                        if !skipPartial, let avg = finalAverage?.doubleValue {
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
                grades: studentGrades,
                matchedByOrder: matchedByOrder
            )
        }

        totalGradesToExport = matchedStudents.reduce(0) { $0 + $1.grades.filter { !$0.isComment }.count }
        totalCommentsToExport = matchedStudents.filter(\.hasComment).count
        partialStudents = partials
    }

    private func pickerColumns(for col: MatchedColumn) -> [NotebookColumnDefinition] {
        col.educamosElement.isComentarios
            ? EducamosColumnMatcher.selectableCommentColumns(in: data.sheet.columns)
            : EducamosColumnMatcher.selectableInstrumentColumns(in: data.sheet.columns)
    }

    private var exportSummary: String {
        let grades = totalGradesToExport == 1 ? "1 nota" : "\(totalGradesToExport) notas"
        guard totalCommentsToExport > 0 else { return grades }
        let comments = totalCommentsToExport == 1 ? "1 comentario" : "\(totalCommentsToExport) comentarios"
        return totalGradesToExport > 0 ? "\(grades) y \(comments)" : comments
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

            #if os(macOS) || targetEnvironment(macCatalyst)
            saveToDownloads(sourceURL: outputURL)
            #endif

            errorMessage = nil
            onExported?(exportSummary, savedToDownloadsPath.map { URL(fileURLWithPath: $0) } ?? outputURL)
            withAnimation { step = .export }
            AccessibilityNotification.Announcement("Archivo generado con \(exportSummary)").post()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveToDownloads(sourceURL: URL) {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            errorMessage = "No se encontró la carpeta Descargas. Usa «Compartir archivo»."
            return
        }
        let destURL = downloadsURL.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            withAnimation {
                savedToDownloadsPath = destURL.path
            }
        } catch {
            errorMessage = "No se pudo guardar en Descargas: \(error.localizedDescription). Usa «Compartir archivo»."
        }
    }
}
