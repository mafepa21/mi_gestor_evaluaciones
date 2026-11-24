import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
import MiGestorKit

/// Hoja «Enviar notas al alumnado»: prepara un informe en PDF por alumno con la
/// Media de la pestaña activa del Cuaderno y lo abre en Mail, uno a uno.
/// Nada se envía sin que el docente pulse Enviar en Mail.
struct GradeReportDispatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let className: String
    let periodName: String
    let loadReports: () async -> [StudentGradeReport]
    /// Guarda el correo en la ficha del alumno.
    let saveStudentEmail: (_ studentId: Int64, _ email: String) async throws -> Void

    @AppStorage("gradeReport.subjectName") private var subjectName = ""

    @State private var reports: [StudentGradeReport] = []
    @State private var isLoading = true
    @State private var selectedId: Int64?
    @State private var narratives: [Int64: GradeReportNarrative] = [:]
    @State private var generatingIds: Set<Int64> = []
    @State private var statuses: [Int64: GradeReportMailOutcome] = [:]
    @State private var emailOverrides: [Int64: String] = [:]
    @State private var confirmTarget: StudentGradeReport?
    @State private var mailDraft: GradeReportMailDraft?
    @State private var emailEditorTarget: StudentGradeReport?
    @State private var emailEditorText = ""
    @State private var errorMessage: String?
    @State private var narrativeTask: Task<Void, Never>?
    @State private var compactPath: [Int64] = []
    @State private var isFolderPickerPresented = false
    @State private var batchTask: Task<Void, Never>?
    @State private var batchDone = 0
    @State private var batchTotal = 0
    @State private var batchSummary: GradeReportBatchSummary?

    private let aiService = AppleFoundationGradeReportService()

    var body: some View {
        NavigationStack(path: $compactPath) {
            content
                .navigationTitle("Enviar notas al alumnado")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(allSent ? "Todo enviado" : "Enviar siguiente") {
                            if let next = nextToSend { confirmTarget = next }
                        }
                        .disabled(nextToSend == nil || isBatchRunning)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isFolderPickerPresented = true
                        } label: {
                            Label("Guardar todos los PDF…", systemImage: "square.and.arrow.down.on.square")
                        }
                        .help("Guarda un PDF por alumno en la carpeta que elijas")
                        .disabled(isLoading || isBatchRunning || !reports.contains(where: { $0.hasGrades }))
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if isBatchRunning { batchProgressBar }
                }
                .navigationDestination(for: Int64.self) { id in
                    if let report = reports.first(where: { $0.studentId == id }) {
                        ScrollView { preview(for: report).padding(16) }
                            .navigationTitle(report.studentName)
                    }
                }
        }
        .task { await load() }
        .onDisappear {
            narrativeTask?.cancel()
            batchTask?.cancel()
        }
        .interactiveDismissDisabled(isBatchRunning)
        .fileImporter(isPresented: $isFolderPickerPresented, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): startBatch(into: url)
            case .failure: errorMessage = "No se pudo abrir esa carpeta. Elige otra."
            }
        }
        .alert(
            batchSummary?.title ?? "",
            isPresented: Binding(get: { batchSummary != nil }, set: { if !$0 { batchSummary = nil } }),
            presenting: batchSummary
        ) { summary in
#if os(macOS)
            if let folder = summary.folder {
                Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            }
#endif
            Button("Aceptar", role: .cancel) {}
        } message: { summary in
            Text(summary.message)
        }
        .alert(item: $confirmTarget) { report in
            Alert(
                title: Text("¿Enviar a \(report.studentName)?"),
                message: Text("Para: \(email(of: report) ?? "")\nAsunto: \(mailSubject)\n\nSe abrirá Mail con el informe en PDF. Nada se envía hasta que pulses Enviar en Mail."),
                primaryButton: .cancel(Text("Cancelar")),
                secondaryButton: .default(Text("Abrir Mail para \(report.firstName)")) { openMail(for: report) }
            )
        }
#if os(iOS)
        .sheet(item: $mailDraft) { draft in
            GradeReportMailComposeView(draft: draft) { outcome in
                mailDraft = nil
                finish(studentId: draft.studentId, outcome: outcome)
            }
            .ignoresSafeArea()
        }
#endif
        .sheet(item: $emailEditorTarget) { report in
            emailEditor(for: report)
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Preparando informes")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if reports.allSatisfy({ !$0.hasGrades }) {
            ContentUnavailableView {
                Label("Aún no hay notas en esta evaluación", systemImage: "tray")
            } description: {
                Text("Cuando pongas notas en el Cuaderno, aquí podrás preparar el informe de cada alumno.")
            } actions: {
                Button("Volver al Cuaderno") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        } else if usesSplitLayout {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 340)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List {
                configSection
                studentsSection(navigates: true)
            }
        }
    }

    private var usesSplitLayout: Bool {
#if os(macOS)
        return !dynamicTypeSize.isAccessibilitySize
#else
        return horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
#endif
    }

    private var sidebar: some View {
        List(selection: $selectedId) {
            configSection
            studentsSection(navigates: false)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if allSent {
            ContentUnavailableView {
                Label("Has terminado", systemImage: "checkmark.circle.fill")
            } description: {
                Text(withoutEmailCount == 0
                     ? "Todos los informes están enviados."
                     : "Quedan \(withoutEmailCount) alumnos sin correo. Añade su correo o guarda su PDF para dárselo en mano.")
            }
        } else if let report = selectedReport {
            ScrollView {
                preview(for: report)
                    .padding(24)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.secondary.opacity(0.06))
        } else {
            ContentUnavailableView("Elige un alumno", systemImage: "person.crop.rectangle")
        }
    }

    private var configSection: some View {
        Section {
            LabeledContent("Evaluación", value: periodName)
            TextField("Asignatura", text: $subjectName, prompt: Text("Asignatura (p. ej. Educación Física)"))
        } footer: {
            Text("Para otra evaluación, cambia de pestaña en el Cuaderno. Las notas son las mismas que la columna Media.")
        }
    }

    private func studentsSection(navigates: Bool) -> some View {
        Section {
            ForEach(reports, id: \.studentId) { report in
                if navigates {
                    NavigationLink(value: report.studentId) { studentRow(report) }
                } else {
                    studentRow(report).tag(report.studentId)
                }
            }
        } header: {
            Text(summaryText)
        }
    }

    private func studentRow(_ report: StudentGradeReport) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.studentName)
                Text(rowSubtitle(report))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let final = report.finalGrade?.doubleValue {
                Text(GradeReportFormat.grade(final))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            statusChip(report)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(report))
    }

    @ViewBuilder
    private func statusChip(_ report: StudentGradeReport) -> some View {
        switch rowStatus(report) {
        case .sent:
            Label("Enviado", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).font(.caption.weight(.medium)).foregroundStyle(.green)
        case .opened:
            Label("En Mail", systemImage: "envelope.open")
                .labelStyle(.titleAndIcon).font(.caption.weight(.medium)).foregroundStyle(.green)
        case .noEmail:
            Label("Sin correo", systemImage: "exclamationmark.triangle")
                .labelStyle(.titleAndIcon).font(.caption.weight(.medium)).foregroundStyle(.primary)
        case .noGrades:
            Text("Sin notas").font(.caption).foregroundStyle(.secondary)
        case .ready:
            Text("Listo").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Vista previa

    @ViewBuilder
    private func preview(for report: StudentGradeReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            banners(for: report)
            GradeReportPreviewCard(
                report: report,
                className: className,
                subjectName: subjectName,
                periodName: periodName,
                narrative: narrativeBinding(for: report),
                isGenerating: generatingIds.contains(report.studentId),
                onRegenerate: { regenerate(report) }
            )
        }
    }

    @ViewBuilder
    private func banners(for report: StudentGradeReport) -> some View {
        if !report.hasGrades {
            GradeReportBanner(text: "\(report.firstName) aún no tiene notas que cuenten en la Media.", tint: .orange)
        } else if email(of: report) == nil {
            GradeReportBanner(text: "\(report.firstName) no tiene correo guardado.", tint: .orange) {
                Button("Añadir correo") {
                    emailEditorText = ""
                    emailEditorTarget = report
                }
                sharePDFButton(for: report, title: "Guardar PDF")
            }
        } else if !GradeReportMail.canComposeInApp {
            GradeReportBanner(text: "Este dispositivo no tiene una cuenta configurada en Mail.", tint: .red) {
                sharePDFButton(for: report, title: "Compartir PDF")
            }
        }
        if !aiService.isAIAvailable && report.hasGrades {
            GradeReportBanner(text: "Apple Intelligence no está activo. Los textos usan una plantilla; puedes editarlos.", tint: .orange)
        }
        if let errorMessage {
            GradeReportBanner(text: errorMessage, tint: .red)
        }
    }

    @ViewBuilder
    private func sharePDFButton(for report: StudentGradeReport, title: String) -> some View {
        ShareLink(
            item: GradeReportPDFFile(makeURL: { pdfURL(for: report) }),
            preview: SharePreview(StudentGradeReportPDFRenderer.fileName(for: report, periodName: periodName))
        ) { Text(title) }
    }

    private func emailEditor(for report: StudentGradeReport) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("correo@ejemplo.com", text: $emailEditorText)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
#if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
#endif
                } footer: {
                    Text("Se guarda en la ficha de \(report.studentName).")
                }
            }
            .navigationTitle("Correo de \(report.firstName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { emailEditorTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { saveEmail(for: report) }
                        .disabled(!isPlausibleEmail(emailEditorText))
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 380, minHeight: 200)
#else
        .presentationDetents([.medium])
#endif
    }

    // MARK: - Estado

    private enum RowStatus { case ready, sent, opened, noEmail, noGrades }

    private func rowStatus(_ report: StudentGradeReport) -> RowStatus {
        switch statuses[report.studentId] {
        case .sent: return .sent
        case .openedInMail: return .opened
        default: break
        }
        if !report.hasGrades { return .noGrades }
        if email(of: report) == nil { return .noEmail }
        return .ready
    }

    private func email(of report: StudentGradeReport) -> String? {
        emailOverrides[report.studentId] ?? report.email
    }

    private var selectedReport: StudentGradeReport? {
        reports.first { $0.studentId == selectedId }
    }

    private var pending: [StudentGradeReport] {
        reports.filter { rowStatus($0) == .ready }
    }

    private var nextToSend: StudentGradeReport? {
        if let selected = selectedReport, rowStatus(selected) == .ready { return selected }
        return pending.first
    }

    private var withoutEmailCount: Int {
        reports.filter { rowStatus($0) == .noEmail }.count
    }

    private var allSent: Bool {
        !isLoading && reports.contains(where: { $0.hasGrades }) && pending.isEmpty
    }

    private var summaryText: String {
        let done = reports.filter { [.sent, .opened].contains(rowStatus($0)) }.count
        var parts = ["\(pending.count) listos", "\(done) enviados"]
        if withoutEmailCount > 0 { parts.append("\(withoutEmailCount) sin correo") }
        return parts.joined(separator: " · ")
    }

    private func rowSubtitle(_ report: StudentGradeReport) -> String {
        switch rowStatus(report) {
        case .sent: return "Enviado"
        case .opened: return "Abierto en Mail"
        case .noEmail: return "Sin correo"
        case .noGrades: return "Sin notas"
        case .ready: return email(of: report) ?? ""
        }
    }

    private func accessibilityText(_ report: StudentGradeReport) -> String {
        var parts = [report.studentName]
        if let final = report.finalGrade?.doubleValue { parts.append("nota \(GradeReportFormat.grade(final))") }
        parts.append(rowSubtitle(report))
        return parts.joined(separator: ", ")
    }

    private var mailSubject: String {
        let subject = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "Tus notas · \(periodName)" : "Tus notas de \(subject) · \(periodName)"
    }

    private func mailBody(for report: StudentGradeReport) -> String {
        let subject = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectPart = subject.isEmpty ? "" : " en \(subject)"
        return """
        Hola, \(report.firstName):

        Te adjunto el informe con tus notas de \(periodName)\(subjectPart). Son provisionales: todavía no están publicadas en la plataforma educativa.

        Si ves algún error o tienes dudas, contéstame a este correo.

        Un saludo.
        """
    }

    private func narrativeBinding(for report: StudentGradeReport) -> Binding<GradeReportNarrative?> {
        Binding(
            get: { narratives[report.studentId] },
            set: { narratives[report.studentId] = $0 }
        )
    }

    // MARK: - Acciones

    private func load() async {
        aiService.prewarm()
        let loaded = await loadReports()
        reports = loaded
        selectedId = loaded.first(where: { $0.hasGrades && $0.hasEmail })?.studentId ?? loaded.first?.studentId
        isLoading = false
        narrativeTask = Task { await generateNarratives() }
    }

    /// Prepara los textos uno a uno, empezando por el alumno elegido.
    private func generateNarratives() async {
        let withGrades = reports.filter { $0.hasGrades }
        let ordered = withGrades.filter { $0.studentId == selectedId } + withGrades.filter { $0.studentId != selectedId }
        for report in ordered {
            if Task.isCancelled { return }
            if narratives[report.studentId] != nil { continue }
            generatingIds.insert(report.studentId)
            let narrative = await aiService.narrative(for: report, subjectName: subjectName)
            generatingIds.remove(report.studentId)
            if narratives[report.studentId] == nil {
                narratives[report.studentId] = narrative
            }
        }
    }

    // MARK: - Guardar todos

    private var isBatchRunning: Bool { batchTask != nil }

    private var batchProgressBar: some View {
        HStack(spacing: 16) {
            ProgressView(value: Double(batchDone), total: Double(max(batchTotal, 1)))
                .frame(maxWidth: 240)
            Text("Preparando \(batchDone) de \(batchTotal)")
                .monospacedDigit()
            Spacer(minLength: 8)
            Button("Cancelar") { batchTask?.cancel() }
        }
        .padding(16)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparando informes, \(batchDone) de \(batchTotal)")
    }

    /// Prepara los textos que falten y guarda un PDF por alumno con notas.
    /// Escribe al final: si se cancela antes, no queda ningún archivo a medias.
    private func startBatch(into parent: URL) {
        let targets = reports.filter { $0.hasGrades }
        guard !targets.isEmpty else { return }
        errorMessage = nil
        narrativeTask?.cancel()
        batchDone = 0
        batchTotal = targets.count
        batchTask = Task {
            defer {
                batchTask = nil
                // Retoma en segundo plano los textos que falten (p. ej. tras cancelar).
                narrativeTask = Task { await generateNarratives() }
            }
            for report in targets {
                if Task.isCancelled { break }
                if narratives[report.studentId] == nil {
                    generatingIds.insert(report.studentId)
                    let narrative = await aiService.narrative(for: report, subjectName: subjectName)
                    generatingIds.remove(report.studentId)
                    if narratives[report.studentId] == nil {
                        narratives[report.studentId] = narrative
                    }
                }
                batchDone += 1
            }
            if Task.isCancelled {
                batchSummary = .cancelled
                return
            }
            let items = targets.map {
                GradeReportBatchExporter.Item(
                    report: $0,
                    narrative: narratives[$0.studentId] ?? AppleFoundationGradeReportService.templateNarrative(for: $0)
                )
            }
            let accessing = parent.startAccessingSecurityScopedResource()
            defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
            do {
                let result = try GradeReportBatchExporter.export(
                    items: items,
                    context: .init(className: className, subjectName: subjectName, periodName: periodName),
                    into: parent
                )
                let skipped = reports.filter { !$0.hasGrades }.map(\.studentName)
                batchSummary = .saved(result, skippedNames: skipped)
                AccessibilityNotification.Announcement("Guardados \(result.savedFiles.count) informes").post()
            } catch {
                batchSummary = .failed
            }
        }
    }

    private func regenerate(_ report: StudentGradeReport) {
        guard !generatingIds.contains(report.studentId) else { return }
        generatingIds.insert(report.studentId)
        Task {
            let narrative = await aiService.narrative(for: report, subjectName: subjectName)
            narratives[report.studentId] = narrative
            generatingIds.remove(report.studentId)
        }
    }

    private func pdfURL(for report: StudentGradeReport) -> URL? {
        let narrative = narratives[report.studentId] ?? AppleFoundationGradeReportService.templateNarrative(for: report)
        return StudentGradeReportPDFRenderer.writeTemporaryFile(
            report: report,
            narrative: narrative,
            context: .init(className: className, subjectName: subjectName, periodName: periodName)
        )
    }

    private func openMail(for report: StudentGradeReport) {
        errorMessage = nil
        guard let recipient = email(of: report) else { return }
        guard GradeReportMail.canComposeInApp else {
            errorMessage = "No se puede abrir Mail en este dispositivo. Usa «Compartir PDF»."
            return
        }
        guard let url = pdfURL(for: report) else {
            errorMessage = "No se pudo crear el PDF de \(report.firstName). Prueba otra vez."
            return
        }
        let draft = GradeReportMailDraft(
            studentId: report.studentId,
            recipient: recipient,
            subject: mailSubject,
            body: mailBody(for: report),
            attachmentURL: url
        )
#if os(iOS)
        mailDraft = draft
#else
        GradeReportMail.composeInMail(draft) { outcome in
            finish(studentId: draft.studentId, outcome: outcome)
        }
#endif
    }

    private func finish(studentId: Int64, outcome: GradeReportMailOutcome) {
        switch outcome {
        case .sent, .openedInMail:
            statuses[studentId] = outcome
            let name = reports.first { $0.studentId == studentId }?.firstName ?? "el alumno"
            AccessibilityNotification.Announcement(outcome == .sent ? "Enviado a \(name)" : "Correo de \(name) abierto en Mail").post()
            if let next = pending.first { selectedId = next.studentId }
        case .failed:
            errorMessage = "Mail no pudo preparar el correo. Prueba otra vez o usa «Compartir PDF»."
        case .cancelled:
            break
        }
    }

    private func saveEmail(for report: StudentGradeReport) {
        let email = emailEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await saveStudentEmail(report.studentId, email)
                emailOverrides[report.studentId] = email
                emailEditorTarget = nil
            } catch {
                errorMessage = "No se pudo guardar el correo de \(report.firstName)."
                emailEditorTarget = nil
            }
        }
    }

    private func isPlausibleEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@"), !trimmed.contains(" ") else { return false }
        return at > trimmed.startIndex && trimmed[at...].contains(".")
    }
}

/// PDF que se crea solo cuando el docente comparte (no en cada repintado).
struct GradeReportPDFFile: Transferable, @unchecked Sendable {
    let makeURL: () -> URL?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            let url = await MainActor.run { file.makeURL() }
            guard let url else { throw CocoaError(.fileWriteUnknown) }
            return SentTransferredFile(url)
        }
    }
}

/// Resumen que se enseña al terminar «Guardar todos los PDF».
struct GradeReportBatchSummary {
    let title: String
    let message: String
    let folder: URL?

    static let cancelled = GradeReportBatchSummary(
        title: "Guardado cancelado",
        message: "No se ha guardado ningún informe.",
        folder: nil
    )

    static let failed = GradeReportBatchSummary(
        title: "No se pudieron guardar",
        message: "No se pudo crear la carpeta en ese sitio. Prueba con otra carpeta.",
        folder: nil
    )

    static func saved(_ result: GradeReportBatchExporter.Result, skippedNames: [String]) -> GradeReportBatchSummary {
        let count = result.savedFiles.count
        var lines = [count == 1
            ? "Se ha guardado 1 informe en «\(result.folder.lastPathComponent)»."
            : "Se han guardado \(count) informes en «\(result.folder.lastPathComponent)»."]
        if !skippedNames.isEmpty {
            lines.append("Sin notas, no se guardan: \(skippedNames.joined(separator: ", ")).")
        }
        if !result.failedNames.isEmpty {
            lines.append("No se pudo guardar: \(result.failedNames.joined(separator: ", ")).")
        }
        return GradeReportBatchSummary(
            title: result.failedNames.isEmpty ? "Informes guardados" : "Guardado con avisos",
            message: lines.joined(separator: "\n"),
            folder: result.folder
        )
    }
}

extension StudentGradeReport: @retroactive Identifiable {
    public var id: Int64 { studentId }
}

// MARK: - Piezas

/// Aviso corto encima de la vista previa, con acciones opcionales.
struct GradeReportBanner<Actions: View>: View {
    let text: String
    let tint: Color
    @ViewBuilder var actions: () -> Actions

    init(text: String, tint: Color, @ViewBuilder actions: @escaping () -> Actions) {
        self.text = text
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
                actions().buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                HStack(spacing: 8) { actions().buttonStyle(.bordered) }
            }
        }
        .font(.subheadline)
        .padding(16)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension GradeReportBanner where Actions == EmptyView {
    init(text: String, tint: Color) {
        self.init(text: text, tint: tint) { EmptyView() }
    }
}

/// Vista previa del informe: misma información y orden que el PDF.
struct GradeReportPreviewCard: View {
    let report: StudentGradeReport
    let className: String
    let subjectName: String
    let periodName: String
    @Binding var narrative: GradeReportNarrative?
    let isGenerating: Bool
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
            if !report.instruments.isEmpty { instruments }
            ForEach(report.rubrics, id: \.columnId) { rubric in rubricBlock(rubric) }
            if let calculation = GradeReportFormat.calculation(for: report) {
                block("Cómo se calcula tu nota") { Text(calculation) }
            }
            if report.hasGrades { narrativeBlocks }
            Text("Estas notas son provisionales. La nota oficial es la que se publique en la plataforma educativa del centro. Si ves un error, responde al correo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTA PROVISIONAL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange.opacity(0.5)))
                Text(report.studentName).font(.title2.weight(.bold))
                Text([className, subjectName, periodName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if let final = report.finalGrade?.doubleValue {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(GradeReportFormat.grade(final))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text(report.finalLevel?.label ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Nota final \(GradeReportFormat.grade(final)), \(report.finalLevel?.label ?? "")")
            }
        }
    }

    private var instruments: some View {
        block("Tus instrumentos") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Instrumento")
                    Text("Peso").gridColumnAlignment(.trailing)
                    Text("Nota").gridColumnAlignment(.trailing)
                    Text("Nivel").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(report.instruments, id: \.columnId) { instrument in
                    Divider()
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instrument.title)
                            if !instrument.criterionCodes.isEmpty {
                                Text(instrument.criterionCodes.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(GradeReportFormat.percent(instrument.weightPercent)).monospacedDigit()
                        Text(GradeReportFormat.grade(instrument.value)).monospacedDigit()
                        Text(instrument.level.label)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !report.pendingTitles.isEmpty {
                Text("Aún sin nota: \(report.pendingTitles.joined(separator: ", ")).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rubricBlock(_ rubric: GradeReportRubric) -> some View {
        block("Tu rúbrica: \(rubric.title)") {
            VStack(spacing: 8) {
                ForEach(rubric.criteria, id: \.criterionId) { criterion in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(criterion.name).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(criterion.levelName).font(.subheadline.weight(.semibold))
                            HStack(spacing: 4) {
                                ForEach(0..<Int(criterion.levelCount), id: \.self) { index in
                                    Circle()
                                        .fill(index < Int(criterion.levelPosition) ? Color.accentColor : Color.secondary.opacity(0.25))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .accessibilityHidden(true)
                        }
                        if let description = criterion.levelDescription {
                            Text(description).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(criterion.name): \(criterion.levelName), nivel \(criterion.levelPosition) de \(criterion.levelCount)")
                }
            }
        }
    }

    @ViewBuilder
    private var narrativeBlocks: some View {
        if let current = narrative {
            editableBlock("Lo que haces bien", isAI: current.isAI, text: Binding(
                get: { narrative?.strengths ?? "" },
                set: { narrative?.strengths = $0 }
            ))
            editableBlock("Lo que puedes mejorar", isAI: current.isAI, text: Binding(
                get: { narrative?.improvements ?? "" },
                set: { narrative?.improvements = $0 }
            ))
            Button {
                onRegenerate()
            } label: {
                Label(isGenerating ? "Redactando…" : "Regenerar texto", systemImage: "arrow.clockwise")
            }
            .disabled(isGenerating)
            .accessibilityHint("Pide otro texto. Las notas no cambian.")
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("Redactando los comentarios…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func editableBlock(_ title: String, isAI: Bool, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionTitle(title)
                Text(isAI ? "Redactado con IA de Apple · editable" : "Texto de plantilla · editable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: text)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Texto editable: \(title)")
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}
