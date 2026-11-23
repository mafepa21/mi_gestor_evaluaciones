import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

/// Hoja «Importar comentarios»: lee un Excel con un comentario por fila y lo guarda, por orden,
/// en la columna «Comentario de evaluación» de la pestaña activa del Cuaderno.
struct EvaluationCommentImportSheet: View {
    let data: NotebookUiStateData
    let bridge: KmpBridge
    let tabId: String?
    let tabTitle: String?

    private enum Step {
        case chooseFile
        case loading(fileName: String)
        case review
        case failed(String)
        case done(count: Int, columnTitle: String)
    }

    /// Destino del comentario: una columna de texto existente o la columna nueva.
    private static let newColumnTag = "__nueva__"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var step: Step = .chooseFile
    @State private var isFileImporterPresented = false
    @State private var fileName = ""
    @State private var table = EvaluationCommentTable(cellsByRow: [:])
    @State private var educamos: EvaluationCommentEducamosLayout?
    @State private var columnOptions: [EvaluationCommentColumnOption] = []
    @State private var selectedColumn: Int = 0
    @State private var skipHeader = false
    @State private var destination: String = Self.newColumnTag
    @State private var isReplaceConfirmationPresented = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var undoSnapshot: (columnId: String, values: [(studentId: Int64, text: String)])?
    @State private var loadTask: Task<Void, Never>?
    /// Columna con códigos «Alumno NN» del informe anónimo, si el archivo la trae.
    @State private var codeColumn: Int?
    @State private var codeKey: [Int: Int64]?

    private var periodTitle: String { tabTitle ?? "esta evaluación" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.xlsx, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            loadTask?.cancel()
            loadTask = Task { await handleFile(result) }
        }
        .onAppear { destination = defaultDestination }
        .onDisappear { loadTask?.cancel() }
        .interactiveDismissDisabled(isSaving)
        .appOnChange(of: saveError) { _ in
            if let saveError { AccessibilityNotification.Announcement(saveError).post() }
        }
    }

    private var navigationTitle: String {
        if case .review = step { return "Revisar comentarios" }
        return "Importar comentarios"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch step {
        case .done:
            ToolbarItem(placement: .confirmationAction) {
                Button("Hecho") { dismiss() }
            }
        case .review:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if plan.replaceCount > 0 {
                        isReplaceConfirmationPresented = true
                    } else {
                        Task { await importComments() }
                    }
                } label: {
                    Text("Importar (\(plan.importCount))")
                        .opacity(isSaving ? 0 : 1)
                        .overlay {
                            if isSaving { ProgressView().controlSize(.small) }
                        }
                }
                .disabled(plan.importCount == 0 || isSaving)
                .accessibilityLabel(isSaving ? "Guardando comentarios" : "Importar \(plan.importCount) comentarios")
            }
        default:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    loadTask?.cancel()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .chooseFile:
            chooseFileView
        case .loading(let name):
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Leyendo archivo")
                Text("Leyendo «\(name)»…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .review:
            reviewView
        case .failed(let message):
            ContentUnavailableView {
                Label("No se pudo leer el archivo", systemImage: "exclamationmark.triangle")
            } description: {
                Text("No se ha importado nada. \(message) Debe ser un .xlsx con al menos una columna de texto, un comentario por fila.")
            } actions: {
                Button("Elegir otro archivo") { isFileImporterPresented = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .done(let count, let columnTitle):
            ContentUnavailableView {
                Label(
                    count == 1 ? "1 comentario importado" : "\(count) comentarios importados",
                    systemImage: "checkmark.circle"
                )
            } description: {
                Text("Guardados en «\(columnTitle)» de \(periodTitle).")
            } actions: {
                Button("Deshacer") { Task { await undoImport() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(undoSnapshot == nil || isSaving)
                    .accessibilityHint("Restaura los comentarios que había antes de importar")
                if let saveError { errorLabel(saveError) }
            }
        }
    }

    // MARK: - Paso 1

    private var chooseFileView: some View {
        ContentUnavailableView {
            Label("Comentarios de \(periodTitle)", systemImage: "text.bubble")
        } description: {
            Text("Elige un Excel con un comentario por fila. La primera fila con comentario va al primer alumno del Cuaderno, la segunda al segundo, y así con todos. Sirve también el Excel de Educamos: la app encuentra sola su columna de comentarios.")
        } actions: {
            Button("Elegir archivo .xlsx") { isFileImporterPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if bridge.evaluationCommentColumn(in: data, tabId: tabId) == nil {
                Button("Solo añadir la columna") { Task { await addEmptyColumn() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSaving)
            }
            if let saveError { errorLabel(saveError) }
        }
    }

    /// Error visible: icono en rojo y texto en el color principal, para que se lea bien.
    private func errorLabel(_ message: String) -> some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Paso 2

    private var students: [EvaluationCommentStudent] {
        let columnId = destination == Self.newColumnTag ? nil : destination
        return data.sheet.rows.map { row in
            EvaluationCommentStudent(
                id: row.student.id,
                displayName: "\(row.student.lastName), \(row.student.firstName)",
                existingComment: columnId.map {
                    bridge.cellText(studentId: row.student.id, columnId: $0).trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? ""
            )
        }
    }

    private var plan: EvaluationCommentPlan {
        if let codeColumn, let codeKey {
            return EvaluationCommentImport.planByCode(
                table: table,
                codeColumn: codeColumn,
                commentColumn: selectedColumn,
                key: codeKey,
                students: students
            )
        }
        return EvaluationCommentImport.plan(
            table: table,
            educamos: educamos,
            column: selectedColumn,
            skipHeader: skipHeader,
            students: students
        )
    }

    private var destinationColumns: [NotebookColumnDefinition] {
        KmpBridge.commentCapableColumns(in: data.sheet.columns, tabId: tabId)
    }

    private var defaultDestination: String {
        bridge.evaluationCommentColumn(in: data, tabId: tabId)?.id ?? Self.newColumnTag
    }

    private var destinationTitle: String {
        destinationColumns.first { $0.id == destination }?.title ?? KmpBridge.evaluationCommentColumnTitle
    }

    private var reviewView: some View {
        let plan = plan
        return Form {
            if let saveError {
                Section { errorLabel(saveError) }
            }
            Section {
                LabeledContent("Archivo", value: fileName)
                Button("Cambiar archivo") { isFileImporterPresented = true }
                Picker("Columna", selection: $selectedColumn) {
                    ForEach(columnOptions) { option in
                        Text(option.label).tag(option.index)
                    }
                }
                .pickerStyle(.menu)
                if codeKey != nil {
                    LabeledContent("Emparejar", value: "Por código «Alumno NN»")
                } else if educamos == nil {
                    Toggle("La primera fila es un título", isOn: $skipHeader)
                }
                Picker("Destino", selection: $destination) {
                    if bridge.evaluationCommentColumn(in: data, tabId: tabId) == nil {
                        Text("\(KmpBridge.evaluationCommentColumnTitle) (nueva)").tag(Self.newColumnTag)
                    }
                    ForEach(destinationColumns, id: \.id) { column in
                        Text(column.title).tag(column.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Origen")
            } footer: {
                Text(originFooter)
            }

            if plan.countsDiffer || plan.replaceCount > 0 || plan.emptyCount > 0 || !plan.unknownCodes.isEmpty {
                Section("Avisos") {
                    if !plan.unknownCodes.isEmpty {
                        Label {
                            Text(unknownCodesMessage(plan.unknownCodes))
                        } icon: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                    if plan.countsDiffer {
                        Label {
                            Text(countMessage(plan))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    if plan.replaceCount > 0 {
                        Label {
                            Text(plan.replaceCount == 1
                                 ? "1 alumno ya tiene comentario. Se sustituirá por el del Excel."
                                 : "\(plan.replaceCount) alumnos ya tienen comentario. Se sustituirá por el del Excel.")
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                        }
                    }
                    if plan.emptyCount > 0 {
                        Label {
                            Text(plan.emptyCount == 1
                                 ? "1 alumno no tiene comentario en el Excel. Se queda como está."
                                 : "\(plan.emptyCount) alumnos no tienen comentario en el Excel. Se quedan como están.")
                        } icon: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ForEach(plan.entries) { entry in
                    EvaluationCommentPreviewRow(entry: entry)
                }
            } header: {
                Text("Alumno ← comentario")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            plan.replaceCount == 1 ? "¿Sustituir 1 comentario?" : "¿Sustituir \(plan.replaceCount) comentarios?",
            isPresented: $isReplaceConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sustituir e importar", role: .destructive) {
                Task { await importComments() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ya tienen comentario y se cambiará por el del Excel. Podrás deshacerlo justo después.")
        }
        .appOnChange(of: selectedColumn) { _ in
            if educamos == nil {
                skipHeader = EvaluationCommentImport.looksLikeHeader(table: table, column: selectedColumn)
            }
            announceCount()
        }
        .appOnChange(of: skipHeader) { _ in announceCount() }
        .appOnChange(of: destination) { _ in announceCount() }
    }

    private var originFooter: String {
        if codeKey != nil {
            return "Los códigos son los del informe «Base para boletín» de este grupo: cada comentario va a su alumno aunque el orden sea otro. Solo vale si el alumnado del grupo no ha cambiado desde que generaste el informe."
        }
        if educamos != nil {
            return "Archivo de Educamos: se usan sus filas de alumnado, en el mismo orden."
        }
        return "La app propone la columna con más texto. La primera fila con comentario va al primer alumno."
    }

    private func unknownCodesMessage(_ codes: [String]) -> String {
        let list = codes.prefix(4).joined(separator: ", ") + (codes.count > 4 ? "…" : "")
        return codes.count == 1
            ? "\(list) no existe en este grupo. No se importará."
            : "\(codes.count) códigos no existen en este grupo (\(list)). No se importarán."
    }

    private func countMessage(_ plan: EvaluationCommentPlan) -> String {
        let comments = plan.sourceCount == 1 ? "1 comentario" : "\(plan.sourceCount) comentarios"
        let pupils = plan.entries.count == 1 ? "1 alumno" : "\(plan.entries.count) alumnos"
        var text = "Hay \(comments) y \(pupils)."
        if plan.extraCount > 0 {
            text += plan.extraCount == 1 ? " El último no se importará." : " Los \(plan.extraCount) últimos no se importarán."
        }
        return text + " Revisa que el orden del Excel sea el mismo que el del Cuaderno."
    }

    private func announceCount() {
        let plan = plan
        var message = plan.importCount == 1 ? "Se importará 1 comentario" : "Se importarán \(plan.importCount) comentarios"
        if plan.replaceCount > 0 { message += ", \(plan.replaceCount) sustituirán al actual" }
        message += "."
        if plan.countsDiffer { message += " " + countMessage(plan) }
        if !plan.unknownCodes.isEmpty { message += " " + unknownCodesMessage(plan.unknownCodes) }
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - Acciones

    @MainActor
    private func handleFile(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result { step = .failed(error.localizedDescription) }
            return
        }
        saveError = nil
        fileName = url.lastPathComponent
        step = .loading(fileName: fileName)
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () -> (EvaluationCommentTable, EvaluationCommentEducamosLayout?) in
                let template = try? EducamosSMTemplateService.parse(from: url)
                let layout = template.flatMap { template -> EvaluationCommentEducamosLayout? in
                    guard let comments = template.comentariosElement, !template.students.isEmpty else { return nil }
                    return EvaluationCommentEducamosLayout(
                        studentRows: template.students.map(\.rowIndex),
                        commentsColumn: comments.columnIndex,
                        studentNames: template.students.map(\.rawName)
                    )
                }
                let table = try EvaluationCommentImport.readTable(
                    from: url,
                    sheetPath: layout == nil ? nil : template?.mainSheetPath
                )
                return (table, layout)
            }.value
            try Task.checkCancellation()
            let options = EvaluationCommentImport.columnOptions(table: loaded.0, educamos: loaded.1)
            guard !options.isEmpty,
                  let suggested = EvaluationCommentImport.suggestedColumn(table: loaded.0, educamos: loaded.1) else {
                throw EvaluationCommentImportError.noTextColumns
            }
            // Códigos del informe anónimo: se traduce cada «Alumno NN» con la clave del grupo.
            let detectedCodeColumn = loaded.1 == nil ? EvaluationCommentImport.codeColumn(table: loaded.0) : nil
            var key: [Int: Int64]?
            if detectedCodeColumn != nil {
                key = try await bridge.bulletinCodeKey(classId: data.sheet.classId)
                try Task.checkCancellation()
            }
            table = loaded.0
            educamos = loaded.1
            codeColumn = detectedCodeColumn
            codeKey = key
            columnOptions = options.contains { $0.index == suggested }
                ? options
                : options + [EvaluationCommentColumnOption(
                    index: suggested,
                    letter: EvaluationCommentImport.columnLetter(for: suggested),
                    title: "Comentarios (Educamos)",
                    filledCount: 0
                )]
            selectedColumn = suggested
            skipHeader = loaded.1 == nil && EvaluationCommentImport.looksLikeHeader(table: loaded.0, column: suggested)
            step = .review
            announceCount()
        } catch {
            step = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @MainActor
    private func resolveDestinationColumn() async throws -> NotebookColumnDefinition {
        if destination != Self.newColumnTag, let column = destinationColumns.first(where: { $0.id == destination }) {
            return column
        }
        return try await bridge.ensureEvaluationCommentColumn(classId: data.sheet.classId, tabId: tabId)
    }

    @MainActor
    private func importComments() async {
        let plan = plan
        let comments = plan.entries.compactMap { entry -> (studentId: Int64, text: String)? in
            guard entry.changes, let text = entry.newComment else { return nil }
            return (entry.student.id, text)
        }
        guard !comments.isEmpty else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let column = try await resolveDestinationColumn()
            let previous = try await bridge.saveEvaluationComments(
                classId: data.sheet.classId,
                columnId: column.id,
                comments: comments
            )
            undoSnapshot = (column.id, previous)
            registerUndo()
            let message = comments.count == 1 ? "1 comentario importado" : "\(comments.count) comentarios importados"
            AccessibilityNotification.Announcement(message).post()
            step = .done(count: comments.count, columnTitle: column.title)
        } catch {
            saveError = "No se pudieron guardar los comentarios: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func undoImport() async {
        guard let snapshot = undoSnapshot else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await bridge.saveEvaluationComments(
                classId: data.sheet.classId,
                columnId: snapshot.columnId,
                comments: snapshot.values
            )
            undoSnapshot = nil
            AccessibilityNotification.Announcement("Importación deshecha").post()
            dismiss()
        } catch {
            saveError = "No se pudo deshacer: \(error.localizedDescription)"
        }
    }

    /// ⌘Z también deshace la importación mientras la ventana siga abierta.
    private func registerUndo() {
        guard let undoManager, let snapshot = undoSnapshot else { return }
        let bridge = bridge
        let classId = data.sheet.classId
        undoManager.registerUndo(withTarget: bridge) { target in
            Task { @MainActor in
                try? await target.saveEvaluationComments(classId: classId, columnId: snapshot.columnId, comments: snapshot.values)
            }
        }
        undoManager.setActionName("Importar comentarios")
    }

    @MainActor
    private func addEmptyColumn() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await bridge.ensureEvaluationCommentColumn(classId: data.sheet.classId, tabId: tabId)
            bridge.refreshCurrentNotebook()
            dismiss()
        } catch {
            saveError = "No se pudo añadir la columna: \(error.localizedDescription)"
        }
    }
}

/// Una fila de la revisión. Con letra grande, el comentario pasa debajo del nombre.
private struct EvaluationCommentPreviewRow: View {
    let entry: EvaluationCommentPlan.Entry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                number
                nameBlock.frame(minWidth: 160, alignment: .leading)
                commentBlock.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                number
                VStack(alignment: .leading, spacing: 8) {
                    nameBlock
                    commentBlock
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(entry.newComment ?? "")
        .accessibilityHint(accessibilityHintText)
    }

    private var number: some View {
        Text("\(entry.position)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 24, alignment: .trailing)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.student.displayName)
            if let sourceName = entry.sourceName {
                Text("En el Excel: \(sourceName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var commentBlock: some View {
        if let comment = entry.newComment {
            VStack(alignment: .leading, spacing: 4) {
                if entry.replacesExisting {
                    Label {
                        Text("Sustituirá el comentario actual")
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                    }
                    .font(.footnote.weight(.semibold))
                } else if !entry.changes {
                    Label("Igual que el actual", systemImage: "checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(comment)
                    .lineLimit(3)
            }
        } else {
            Text("Sin comentario en el Excel: queda sin cambios")
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabelText: String {
        var parts = ["\(entry.position)", entry.student.displayName]
        if let sourceName = entry.sourceName { parts.append("en el Excel \(sourceName)") }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHintText: String {
        guard entry.newComment != nil else { return "Sin comentario en el Excel, queda sin cambios" }
        if entry.replacesExisting { return "Sustituirá el comentario actual" }
        if !entry.changes { return "Igual que el actual" }
        return "Comentario nuevo"
    }
}
