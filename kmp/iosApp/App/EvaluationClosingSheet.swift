import SwiftUI
import MiGestorKit
#if canImport(AppKit) && os(macOS)
import AppKit
#endif

/// «Cerrar evaluación»: un recorrido de 4 pasos para terminar el trimestre de una pestaña
/// del Cuaderno (Notas → Comentarios → Excel de Educamos → Subir a Educamos).
/// Reutiliza las hojas que ya existen; no cambia notas por sí misma. iPad, iPhone y Mac.
struct EvaluationClosingSheet: View {
    let data: NotebookUiStateData
    let bridge: KmpBridge
    let className: String
    let tabId: String?
    let tabTitle: String?
    let contextText: String
    let loadClosingReport: () async throws -> NotebookClosingReport
    /// Aviso de notas tocado: quien abre la hoja lleva el foco a esa celda al cerrarse.
    let onSelectIssue: (NotebookClosingTarget) -> Void

    enum Step: Hashable {
        case notes
        case comments
        case upload
    }

    enum Presented: Identifiable {
        case deviceAI
        case anonymousText
        case importComments
        case educamos
        case quickNote(studentId: Int64)

        var id: String {
            switch self {
            case .deviceAI: return "ia"
            case .anonymousText: return "anonimo"
            case .importComments: return "importar"
            case .educamos: return "educamos"
            case .quickNote(let id): return "valoracion-\(id)"
            }
        }
    }

    struct Snapshot {
        var issueCount = 0
        var hasCountingColumns = true
        var students: [(id: Int64, name: String)] = []
        var commentByStudent: [Int64: String] = [:]
        var bulletin: BulletinBaseReport?

        var withComment: Int { students.filter { !(commentByStudent[$0.id] ?? "").isEmpty }.count }
        var lowDataIds: Set<Int64> { bulletin?.lowDataStudentIds ?? [] }
    }

    private enum Phase {
        case loading
        case loaded(Snapshot)
        case failed
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var term: EvaluationClosingTerm
    @State private var phase: Phase = .loading
    @State private var loadAttempt = 0
    @State private var record: EvaluationClosingRecord
    @State private var presented: Presented?

    init(
        data: NotebookUiStateData,
        bridge: KmpBridge,
        className: String,
        tabId: String?,
        tabTitle: String?,
        contextText: String,
        loadClosingReport: @escaping () async throws -> NotebookClosingReport,
        onSelectIssue: @escaping (NotebookClosingTarget) -> Void
    ) {
        self.data = data
        self.bridge = bridge
        self.className = className
        self.tabId = tabId
        self.tabTitle = tabTitle
        self.contextText = contextText
        self.loadClosingReport = loadClosingReport
        self.onSelectIssue = onSelectIssue
        _term = State(initialValue: EvaluationClosingTerm.from(tabTitle: tabTitle) ?? .current())
        _record = State(initialValue: EvaluationClosingStore.load(classId: data.sheet.classId, tabId: tabId))
    }

    private var classId: Int64 { data.sheet.classId }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cerrar evaluación")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hecho") { dismiss() }
                    }
                }
                .navigationDestination(for: Step.self) { step in
                    destination(for: step)
                }
        }
        .task(id: LoadKey(term: term, attempt: loadAttempt)) { await load() }
        .sheet(item: $presented, onDismiss: reloadAfterChild) { item in
            presentedView(item)
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    private struct LoadKey: Equatable {
        let term: EvaluationClosingTerm
        let attempt: Int
    }

    // MARK: - Resumen

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Revisando el grupo…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("No se pudo revisar el grupo", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Tus notas y comentarios no han cambiado. Prueba otra vez.")
            } actions: {
                Button("Reintentar") { loadAttempt += 1 }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let snapshot):
            summaryList(snapshot)
        }
    }

    private func summaryList(_ snapshot: Snapshot) -> some View {
        let notes = EvaluationClosingSteps.notes(issueCount: snapshot.issueCount, hasCountingColumns: snapshot.hasCountingColumns)
        let comments = EvaluationClosingSteps.comments(withComment: snapshot.withComment, total: snapshot.students.count)
        let excel = EvaluationClosingSteps.excel(record)
        let upload = EvaluationClosingSteps.upload(record)
        let allDone = notes.isDone && comments.isDone && excel.isDone && upload.isDone
        return List {
            Section {
                termPicker
            } header: {
                Text(contextText + (tabTitle.map { " · pestaña \($0)" } ?? ""))
                    .textCase(nil)
            }

            Section {
                NavigationLink(value: Step.notes) {
                    stepRow(number: 1, title: "Notas", detail: notesDetail(snapshot), symbol: "number", state: notes)
                }
                NavigationLink(value: Step.comments) {
                    stepRow(number: 2, title: "Comentarios", detail: commentsDetail(snapshot), symbol: "text.bubble", state: comments)
                }
                Button {
                    presented = .educamos
                } label: {
                    stepRow(number: 3, title: "Excel de Educamos", detail: excelDetail, symbol: "doc.badge.arrow.up", state: excel, opensSheet: true)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Abre la exportación a Educamos")
                NavigationLink(value: Step.upload) {
                    stepRow(number: 4, title: "Subir a Educamos", detail: "Pasos para terminar en la web de Educamos", symbol: "arrow.up.circle", state: upload)
                }
            } footer: {
                Text("Puedes hacerlos en cualquier orden. Nada se envía a ningún sitio hasta que subas el archivo tú.")
            }

            if allDone {
                Section {
                    Label("Evaluación cerrada", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var termPicker: some View {
        let picker = Picker("Trimestre", selection: $term) {
            ForEach(EvaluationClosingTerm.allCases) { item in
                Text(item.shortLabel).tag(item).accessibilityLabel(item.rawValue)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private func stepRow(
        number: Int,
        title: String,
        detail: String,
        symbol: String,
        state: EvaluationClosingStepState,
        opensSheet: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            // Con letra muy grande el estado pasa debajo para no aplastar el título.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    stepTexts(number: number, title: title, detail: detail)
                    stateLabel(state)
                }
                Spacer(minLength: 0)
            } else {
                stepTexts(number: number, title: title, detail: detail)
                Spacer(minLength: 8)
                stateLabel(state)
            }
            if opensSheet {
                // Abre una hoja, no navega: por eso no lleva la flecha de los otros pasos.
                Image(systemName: "arrow.up.forward.app")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paso \(number) de 4, \(title)")
        .accessibilityValue("\(state.text). \(detail)")
    }

    private func stepTexts(number: Int, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number) · \(title)")
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stateLabel(_ state: EvaluationClosingStepState) -> some View {
        let symbol: String
        let tint: Color
        switch state {
        case .done: symbol = "checkmark.circle.fill"; tint = .green
        case .attention: symbol = "exclamationmark.circle.fill"; tint = .orange
        case .pending: symbol = "circle"; tint = .secondary
        }
        return Label {
            Text(state.text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.subheadline)
    }

    private func notesDetail(_ snapshot: Snapshot) -> String {
        guard snapshot.hasCountingColumns else { return "Este grupo no tiene columnas que cuenten para la Media" }
        return snapshot.issueCount == 0 ? "Todas las notas que cuentan están puestas" : "Notas vacías, columnas ocultas o criterios sin nota"
    }

    private func commentsDetail(_ snapshot: Snapshot) -> String {
        var text = "\(snapshot.withComment) de \(snapshot.students.count) alumnos"
        let low = snapshot.lowDataIds.count
        if low > 0 { text += low == 1 ? " · 1 con pocos datos" : " · \(low) con pocos datos" }
        return text
    }

    private var excelDetail: String {
        guard let date = record.exportDate else { return "Rellena notas y comentarios en la plantilla" }
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return [("Generado " + when), record.exportSummary].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Pasos

    @ViewBuilder
    private func destination(for step: Step) -> some View {
        switch step {
        case .notes:
            NotebookClosingReviewSheet(
                contextText: contextText,
                loadReport: loadClosingReport,
                onSelect: onSelectIssue,
                embedded: true,
                onFinish: { dismiss() }
            )
        case .comments:
            if case .loaded(let snapshot) = phase {
                EvaluationClosingCommentsView(
                    snapshot: snapshot,
                    deviceAIAvailability: AppleAIOrchestrator().availability(),
                    onDeviceAI: { presented = .deviceAI },
                    onAnonymousText: { presented = .anonymousText },
                    onImport: { presented = .importComments },
                    onStudent: { presented = .quickNote(studentId: $0) }
                )
            }
        case .upload:
            EvaluationClosingUploadView(record: $record) { updated in
                EvaluationClosingStore.save(updated, classId: classId, tabId: tabId)
            }
        }
    }

    @ViewBuilder
    private func presentedView(_ item: Presented) -> some View {
        switch item {
        case .deviceAI:
            BulkLOMLOEGenerationSheet(
                bridge: bridge,
                classId: classId,
                termLabel: term.rawValue,
                audience: .familia,
                tone: .formal,
                preferredTabId: tabId
            )
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 640)
            #else
            .presentationDetents([.large])
            #endif
        case .anonymousText:
            NavigationStack {
                BulletinBaseReportView(
                    bridge: bridge,
                    classId: classId,
                    className: className,
                    termLabel: term.rawValue,
                    reloadToken: 0
                )
                .navigationTitle("Base para boletín")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hecho") { presented = nil }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 680, minHeight: 640)
            #else
            .presentationDetents([.large])
            #endif
        case .importComments:
            EvaluationCommentImportSheet(
                data: liveData,
                bridge: bridge,
                tabId: tabId,
                tabTitle: tabTitle
            )
            #if os(macOS)
            .frame(width: 600, height: 680)
            #else
            .presentationDetents([.large])
            #endif
        case .educamos:
            EducamosSMExportSheet(data: liveData, bridge: bridge) { summary, fileURL in
                record.exportDate = Date()
                record.exportSummary = summary
                record.exportFilePath = fileURL.path
                EvaluationClosingStore.save(record, classId: classId, tabId: tabId)
            }
            #if os(macOS)
            .frame(width: 560, height: 640)
            #else
            .presentationDetents([.large])
            #endif
        case .quickNote(let studentId):
            if case .loaded(let snapshot) = phase {
                QuickTermNoteSheet(
                    bridge: bridge,
                    classId: classId,
                    studentId: studentId,
                    studentName: snapshot.students.first { $0.id == studentId }?.name ?? "",
                    termLabel: term.rawValue,
                    chips: QuickNoteCatalog.chips(for: snapshot.bulletin?.inputsByStudent[studentId])
                )
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                #endif
            }
        }
    }

    // MARK: - Carga

    /// Estado del Cuaderno más reciente: tras importar o generar comentarios la hoja los ve.
    private var liveData: NotebookUiStateData {
        (bridge.notebookState as? NotebookUiStateData) ?? data
    }

    private func reloadAfterChild() {
        record = EvaluationClosingStore.load(classId: classId, tabId: tabId)
        loadAttempt += 1
    }

    @MainActor
    private func load() async {
        if case .loaded = phase {} else { phase = .loading }
        do {
            let report = try await loadClosingReport()
            let bulletin = try? await bridge.buildBulletinBaseReport(
                classId: classId,
                termLabel: term.rawValue,
                period: BulletinBaseReportView.period(for: term.rawValue)
            )
            guard !Task.isCancelled else { return }
            let current = liveData
            let commentColumn = KmpBridge.evaluationCommentColumn(in: current.sheet.columns, tabId: tabId)
            var snapshot = Snapshot()
            snapshot.issueCount = report.issues.count
            snapshot.hasCountingColumns = report.hasCountingColumns
            snapshot.students = current.sheet.rows.map { ($0.student.id, "\($0.student.lastName), \($0.student.firstName)") }
            if let commentColumn {
                for row in current.sheet.rows {
                    let text = bridge.cellText(studentId: row.student.id, columnId: commentColumn.id)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { snapshot.commentByStudent[row.student.id] = text }
                }
            }
            snapshot.bulletin = bulletin
            phase = .loaded(snapshot)
            AccessibilityNotification.Announcement("Evaluación revisada").post()
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
            AccessibilityNotification.Announcement("No se pudo revisar el grupo").post()
        }
    }
}

// MARK: - Paso 2: Comentarios

struct EvaluationClosingCommentsView: View {
    let snapshot: EvaluationClosingSheet.Snapshot
    let deviceAIAvailability: AppleAIAvailability
    let onDeviceAI: () -> Void
    let onAnonymousText: () -> Void
    let onImport: () -> Void
    let onStudent: (Int64) -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case missing = "Sin comentario"
        case lowData = "Pocos datos"
        case all = "Todos"
        var id: String { rawValue }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filter: Filter = .missing

    private var students: [(id: Int64, name: String)] {
        switch filter {
        case .missing: return snapshot.students.filter { (snapshot.commentByStudent[$0.id] ?? "").isEmpty }
        case .lowData: return snapshot.students.filter { snapshot.lowDataIds.contains($0.id) }
        case .all: return snapshot.students
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onDeviceAI) {
                        Label("Redactar con la IA del dispositivo", systemImage: "apple.intelligence")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!deviceAIAvailability.isAvailable)
                    .accessibilityHint(deviceAIAvailability.isAvailable ? "" : deviceAIAvailability.message)
                    Text(deviceAIAvailability.isAvailable
                         ? "Usa notas, rúbricas, sellos y tu valoración. Lo guarda en «Comentario de evaluación» para que lo revises."
                         : "No disponible: \(deviceAIAvailability.message)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                Button(action: onAnonymousText) {
                    actionRow("Preparar texto anónimo para otra IA", detail: "Abre «Base para boletín» con este grupo y trimestre")
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                Button(action: onImport) {
                    actionRow("Importar comentarios…", detail: "Desde un Excel, por orden o por código «Alumno NN»")
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            }

            Section {
                filterPicker
                if students.isEmpty {
                    Text(filter == .missing ? "Todos tienen comentario." : "No hay alumnos en esta lista.")
                        .foregroundStyle(.secondary)
                }
                ForEach(students, id: \.id) { student in
                    Button {
                        onStudent(student.id)
                    } label: {
                        studentRow(student)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Abre la valoración rápida")
                }
            } header: {
                Text("Alumnos · \(students.count)")
            } footer: {
                Text("«Tu valoración» es privada: solo la usa la IA para redactar. No se exporta a Educamos.")
            }
        }
        .navigationTitle("Comentarios")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var filterPicker: some View {
        let picker = Picker("Mostrar", selection: $filter) {
            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private func actionRow(_ title: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func studentRow(_ student: (id: Int64, name: String)) -> some View {
        let comment = snapshot.commentByStudent[student.id] ?? ""
        let lowData = snapshot.lowDataIds.contains(student.id)
        let note = snapshot.bulletin?.inputsByStudent[student.id]?.teacherNote
        var detail = comment.isEmpty ? "Sin comentario" : "Con comentario"
        if lowData { detail += " · pocos datos" }
        detail += note == nil ? " · sin valoración" : " · valorado"
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.name).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(note == nil ? "Valorar" : "Editar")
                .font(.subheadline)
                .foregroundStyle(.tint)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paso 4: Subir a Educamos

struct EvaluationClosingUploadView: View {
    @Binding var record: EvaluationClosingRecord
    let onChange: (EvaluationClosingRecord) -> Void

    private var fileURL: URL? {
        guard let path = record.exportFilePath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        Form {
            Section("Archivo") {
                if let date = record.exportDate {
                    LabeledContent("Generado", value: date.formatted(date: .abbreviated, time: .shortened))
                    if let summary = record.exportSummary {
                        LabeledContent("Contenido", value: summary)
                    }
                    if let fileURL {
                        LabeledContent("Nombre", value: fileURL.lastPathComponent)
                        #if os(macOS)
                        Button("Mostrar en Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        }
                        #else
                        ShareLink(item: fileURL) {
                            Label("Compartir archivo", systemImage: "square.and.arrow.up")
                        }
                        #endif
                    } else {
                        Text("El archivo ya no está en este dispositivo. Vuelve a generarlo en el paso 3.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Aún no has generado el Excel de Educamos. Hazlo en el paso 3.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Pasos en Educamos") {
                Label("Abre la misma evaluación de la que descargaste la plantilla.", systemImage: "1.circle")
                Label("Sube este archivo sin cambiarle el nombre ni abrirlo en Excel.", systemImage: "2.circle")
                Label("Comprueba en Educamos que cada alumno tiene su nota y su comentario.", systemImage: "3.circle")
            }

            Section {
                Toggle("Ya lo he subido a Educamos", isOn: Binding(
                    get: { record.isUploaded },
                    set: { isOn in
                        record.uploadedDate = isOn ? Date() : nil
                        onChange(record)
                    }
                ))
            } footer: {
                Text("Marca la evaluación como cerrada en este grupo y dispositivo. La app no puede comprobar si Educamos lo aceptó: es solo tu recordatorio.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Subir a Educamos")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
