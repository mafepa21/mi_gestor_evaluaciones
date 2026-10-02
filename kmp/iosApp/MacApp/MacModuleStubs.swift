import SwiftUI
import AppKit
import MiGestorKit

// StudentSelectionStore moved to AppleViewCompatibility.swift (shared by iOS and macOS).

struct MacReportsView: View {
    private enum ReportTerm: String, CaseIterable, Identifiable {
        case first = "1er Trimestre"
        case second = "2º Trimestre"
        case third = "3er Trimestre"

        var id: String { rawValue }
    }

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case pdf = "PDF"
        case docx = "DOCX"

        var id: String { rawValue }
    }

    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    @State private var selectedReportKind: KmpBridge.ReportKind = .groupOverview
    @State private var selectedTerm: ReportTerm = .first
    @State private var selectedExportFormat: ExportFormat = .pdf
    @State private var includeFactLines = true
    @State private var includeRecommendations = true
    @State private var includeClassicAppendix = true
    @State private var reportContext: KmpBridge.ReportGenerationContext?
    @State private var preview: KmpBridge.ReportPreviewPayload?
    @State private var aiAvailability: AIReportAvailabilityState = .unavailable("Comprobando disponibilidad…")
    @State private var aiAudience: AIReportAudience = .docente
    @State private var aiTone: AIReportTone = .claro
    @State private var aiDraft: AIReportDraft?
    @State private var aiMetadata: AppleAIGenerationMetadata?
    @State private var editableDraftText = ""
    @State private var feedbackMessage: String?
    @State private var isLoadingContext = false
    @State private var isGeneratingDraft = false
    @State private var isExporting = false
    @State private var isWeeklyEmailSheetPresented = false
    @SceneStorage("mac.reports.exportPanelVisible") private var isExportPanelVisible = true

    private let reportService = AppleFoundationReportService()
    private let draftStore = MacReportDraftStore()

    private var selectedClass: SchoolClass? {
        guard let selectedClassId else { return nil }
        return bridge.classes.first(where: { $0.id == selectedClassId })
    }

    private var selectedStudent: Student? {
        guard let selectedStudentId else { return nil }
        return studentOptions.first(where: { $0.id == selectedStudentId })
    }

    private var studentOptions: [Student] {
        bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
    }

    private var requiresStudent: Bool {
        selectedReportKind.requiresStudentSelection
    }

    private var activeDraftKey: MacReportDraftKey? {
        guard let selectedClassId else { return nil }
        return MacReportDraftKey(
            classId: selectedClassId,
            reportKind: selectedReportKind.rawValue,
            period: selectedTerm.rawValue,
            studentId: selectedStudentId
        )
    }

    private var canGenerateAIDraft: Bool {
        guard !isGeneratingDraft else { return false }
        guard let reportContext, reportContext.hasEnoughData else { return false }
        return !requiresStudent || selectedStudentId != nil
    }

    private var canExport: Bool {
        selectedClassId != nil &&
        (!requiresStudent || selectedStudentId != nil) &&
        !consolidatedReportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var consolidatedReportText: String {
        let edited = editableDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !edited.isEmpty {
            return edited
        }

        guard let context = reportContext else {
            return "Selecciona un grupo para preparar el informe."
        }

        var sections: [String] = [
            context.reportTitle,
            context.className,
            context.studentName.map { "Alumno/a: \($0)" } ?? "Ámbito: grupo completo",
            "Periodo: \(context.termLabel ?? selectedTerm.rawValue)",
            "",
            context.summary
        ]

        if includeFactLines, !context.factLines.isEmpty {
            sections += ["", "Hechos verificables", context.factLines.map { "- \($0)" }.joined(separator: "\n")]
        }

        if includeRecommendations, !context.recommendedActions.isEmpty {
            sections += ["", "Próximos pasos", context.recommendedActions.map { "- \($0)" }.joined(separator: "\n")]
        }

        if includeClassicAppendix {
            sections += ["", "Vista clásica", preview?.previewText ?? context.classicReportText]
        }

        return sections.joined(separator: "\n")
    }

    var body: some View {
        GeometryReader { proxy in
            reportsLayout(isCompact: proxy.size.width < 1_200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppStyle.pageBackground)
        .sheet(isPresented: $isWeeklyEmailSheetPresented) {
            WeeklyStudentEmailWorkspaceView(classId: selectedClassId)
                .environmentObject(bridge)
        }
        .task {
            refreshAIAvailability()
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
            }
            await refreshWorkspace()
        }
        .appOnChange(of: selectedClassId) { _, _ in
            selectedStudentId = nil
            Task { await refreshWorkspace() }
        }
        .appOnChange(of: selectedReportKind) { _, newValue in
            if newValue == .lomloeEvaluationComment {
                aiAudience = .familia
                aiTone = .formal
            }
            if !newValue.requiresStudentSelection {
                selectedStudentId = nil
            }
            Task { await reloadReport() }
        }
        .appOnChange(of: selectedTerm) { _, _ in
            Task { await reloadReport() }
        }
        .appOnChange(of: selectedStudentId) { _, _ in
            Task { await reloadReport() }
        }
    }

    @ViewBuilder
    private func reportsLayout(isCompact: Bool) -> some View {
        if isCompact {
            HStack(spacing: 0) {
                reportsSidebar
                    .frame(minWidth: 224, idealWidth: 240, maxWidth: 280)

                Divider()

                reportsCenter(showsCompactExport: true)
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            HStack(spacing: 0) {
                reportsSidebar
                    .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)

                Divider()

                reportsCenter(showsCompactExport: false)
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                if isExportPanelVisible {
                    Divider()

                    reportsExportPanel
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                }
            }
        }
    }

    private var reportsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Informes")
                        .font(.title2.weight(.semibold))
                    Text("Generador de salidas docentes")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                MacReportPanelCard(title: "Grupo") {
                    Picker("Grupo", selection: $selectedClassId) {
                        Text("Seleccionar grupo").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                MacReportPanelCard(title: "Tipo de informe") {
                    ForEach(KmpBridge.ReportKind.allCases) { kind in
                        reportKindButton(kind)
                    }

                    Button {
                        isWeeklyEmailSheetPresented = true
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "envelope.sparkles")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Correos Semanales IA")
                                    .font(.subheadline.weight(.semibold))
                                Text("Borradores masivos para alumnos y familias")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                MacReportPanelCard(title: "Periodo") {
                    Picker("Periodo", selection: $selectedTerm) {
                        ForEach(ReportTerm.allCases) { term in
                            Text(term.rawValue).tag(term)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                MacReportPanelCard(title: "Alumnado") {
                    Picker("Alumno", selection: $selectedStudentId) {
                        Text(requiresStudent ? "Seleccionar alumno" : "Grupo completo").tag(Optional<Int64>.none)
                        ForEach(studentOptions, id: \.id) { student in
                            Text(student.fullName).tag(Optional(student.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Text(requiresStudent ? "Este informe necesita un alumno activo." : "Este informe se genera para el grupo completo.")
                        .font(.caption)
                        .foregroundStyle(requiresStudent && selectedStudentId == nil ? MacAppStyle.warningTint : .secondary)
                }

                MacReportPanelCard(title: "Filtros") {
                    Toggle("Incluir hechos verificables", isOn: $includeFactLines)
                    Toggle("Incluir próximos pasos", isOn: $includeRecommendations)
                    Toggle("Anexar vista clásica", isOn: $includeClassicAppendix)
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
        .background(MacAppStyle.cardBackground)
    }

    private func reportsCenter(showsCompactExport: Bool) -> some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            reportsHeader(showsCompactExport: showsCompactExport)

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if selectedClassId == nil {
                ContentUnavailableView(
                    "Selecciona un grupo",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Informes necesita un grupo para construir contexto, métricas y salidas docentes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requiresStudent && selectedStudentId == nil {
                ContentUnavailableView(
                    "Selecciona un alumno",
                    systemImage: "person.text.rectangle",
                    description: Text("Este tipo de informe es individual y necesita alumnado activo antes de generar preview o IA.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
                        metricsGrid
                        aiSummaryBlock
                        previewBlock
                    }
                    .padding(.bottom, MacAppStyle.pagePadding)
                }
            }
        }
        .padding(MacAppStyle.pagePadding)
    }

    private func reportsHeader(showsCompactExport: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedReportKind.title)
                    .font(MacAppStyle.pageTitle)
                Text(selectedClass?.name ?? "Selecciona un grupo para empezar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingContext {
                ProgressView()
                    .controlSize(.small)
            }
            MacStatusPill(
                label: aiAvailability.isAvailable ? "IA disponible" : "IA limitada",
                isActive: aiAvailability.isAvailable,
                tint: aiAvailability.isAvailable ? MacAppStyle.successTint : MacAppStyle.warningTint
            )
            if showsCompactExport {
                compactExportMenu
            } else {
                Button {
                    withAnimation(MacAppStyle.smallStateAnimation) {
                        isExportPanelVisible.toggle()
                    }
                } label: {
                    Label(
                        isExportPanelVisible ? "Ocultar exportación" : "Mostrar exportación",
                        systemImage: isExportPanelVisible ? "sidebar.trailing" : "sidebar.leading"
                    )
                }
                .buttonStyle(.bordered)
                .help(isExportPanelVisible ? "Ocultar panel de exportación" : "Mostrar panel de exportación")
            }
        }
    }

    private var compactExportMenu: some View {
        Menu {
            Button {
                Task { await export(format: .pdf) }
            } label: {
                Label("Exportar PDF", systemImage: "doc.richtext")
            }
            .disabled(!canExport || isExporting)

            Button {
                Task { await export(format: .docx) }
            } label: {
                Label("Exportar DOCX", systemImage: "doc.badge.gearshape")
            }
            .disabled(!canExport || isExporting)

            Divider()

            Button {
                copyReportText()
            } label: {
                Label("Copiar texto", systemImage: "doc.on.doc")
            }
            .disabled(!canExport)

            Button {
                saveDraft()
            } label: {
                Label("Guardar borrador", systemImage: "tray.and.arrow.down")
            }
            .disabled(activeDraftKey == nil || consolidatedReportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } label: {
            Label("Exportar", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .help("Exportar o guardar el informe")
    }

    @ViewBuilder
    private var metricsGrid: some View {
        if let reportContext {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                MacMetricCard(label: "Tipo", value: selectedReportKind.title, systemImage: selectedReportKind.systemImage)
                MacMetricCard(label: "Periodo", value: selectedTerm.rawValue, systemImage: "calendar")
                ForEach(reportContext.metrics) { metric in
                    MacMetricCard(label: metric.title, value: metric.value, systemImage: metric.systemImage)
                }
            }
        }
    }

    private var aiSummaryBlock: some View {
        MacReportPanelCard(title: "Bloque resumen IA") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reportContext?.summary ?? "Sin contexto cargado.")
                            .font(.headline)
                        Text(aiAvailability.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await generateAIDraft() }
                    } label: {
                        if isGeneratingDraft {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Generar borrador", systemImage: "apple.intelligence")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerateAIDraft)
                }

                HStack {
                    Picker("Audiencia", selection: $aiAudience) {
                        ForEach(AIReportAudience.allCases) { audience in
                            Text(audience.title).tag(audience)
                        }
                    }
                    Picker("Tono", selection: $aiTone) {
                        ForEach(AIReportTone.allCases) { tone in
                            Text(tone.title).tag(tone)
                        }
                    }
                }

                if let reportContext, !reportContext.factLines.isEmpty {
                    MacReportTextSection(title: "Hechos previos", lines: reportContext.factLines)
                }

                if let reportContext, let dataQualityNote = reportContext.dataQualityNote {
                    MacReportNotice(title: "Calidad de datos", message: dataQualityNote, tint: MacAppStyle.warningTint)
                }

                TextEditor(text: $editableDraftText)
                    .font(.system(size: 13))
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var previewBlock: some View {
        MacReportPanelCard(title: "Preview del informe") {
            VStack(alignment: .leading, spacing: 12) {
                Text(consolidatedReportText)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let reportContext {
                    if !reportContext.strengths.isEmpty {
                        MacReportTextSection(title: "Fortalezas detectadas", lines: reportContext.strengths)
                    }
                    if !reportContext.needsAttention.isEmpty {
                        MacReportTextSection(title: "Aspectos a vigilar", lines: reportContext.needsAttention)
                    }
                }
            }
        }
    }

    private var reportsExportPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Exportación")
                        .font(.title3.weight(.semibold))
                    Text("Salida final revisada")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                MacReportPanelCard(title: "Formato") {
                    Picker("Formato", selection: $selectedExportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                MacReportPanelCard(title: "Opciones") {
                    LabeledContent("Grupo") {
                        Text(selectedClass?.name ?? "Sin grupo")
                    }
                    LabeledContent("Destino") {
                        Text(selectedStudent?.fullName ?? "Grupo completo")
                    }
                    LabeledContent("Texto") {
                        Text("\(consolidatedReportText.count) caracteres")
                    }
                    LabeledContent("Borrador") {
                        Text(editableDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Preview" : "Editado")
                    }
                }

                MacReportPanelCard(title: "Acciones") {
                    VStack(spacing: 10) {
                        Button {
                            Task { await export(format: .pdf) }
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canExport || isExporting)

                        Button {
                            Task { await export(format: .docx) }
                        } label: {
                            Label("DOCX", systemImage: "doc.badge.gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canExport || isExporting)

                        Button {
                            copyReportText()
                        } label: {
                            Label("Copiar texto", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canExport)

                        Button {
                            saveDraft()
                        } label: {
                            Label("Guardar borrador", systemImage: "tray.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(activeDraftKey == nil || consolidatedReportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let reportContext {
                    MacReportPanelCard(title: "Métricas previas") {
                        ForEach(reportContext.metrics) { metric in
                            LabeledContent(metric.title) {
                                Text(metric.value)
                            }
                        }
                    }
                }
            }
            .padding(MacAppStyle.pagePadding)
        }
        .background(MacAppStyle.cardBackground)
    }

    private func reportKindButton(_ kind: KmpBridge.ReportKind) -> some View {
        Button {
            selectedReportKind = kind
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(selectedReportKind == kind ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                    Text(kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(selectedReportKind == kind ? Color.accentColor.opacity(0.12) : MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func refreshWorkspace() async {
        guard let selectedClassId else {
            reportContext = nil
            preview = nil
            return
        }
        bridge.selectClass(id: selectedClassId)
        await bridge.selectStudentsClass(classId: selectedClassId)
        if requiresStudent, selectedStudentId == nil {
            selectedStudentId = bridge.studentsInClass.first?.id
        }
        await reloadReport()
    }

    @MainActor
    private func reloadReport() async {
        guard let selectedClassId else {
            reportContext = nil
            preview = nil
            return
        }
        if requiresStudent && selectedStudentId == nil {
            reportContext = nil
            preview = nil
            editableDraftText = ""
            aiDraft = nil
            return
        }

        isLoadingContext = true
        feedbackMessage = nil
        aiDraft = nil
        defer { isLoadingContext = false }

        do {
            let termLabel = selectedTerm.rawValue
            let context = try await bridge.buildReportGenerationContext(
                classId: selectedClassId,
                studentId: selectedStudentId,
                kind: selectedReportKind,
                termLabel: termLabel
            )
            reportContext = context
            preview = try await bridge.buildReportPreview(
                classId: selectedClassId,
                studentId: selectedStudentId,
                kind: selectedReportKind,
                termLabel: termLabel
            )
            loadSavedDraftForCurrentSelection()
            if !context.hasEnoughData {
                feedbackMessage = context.dataQualityNote ?? "Hay pocos datos para redactar conclusiones firmes."
            }
        } catch {
            reportContext = nil
            preview = nil
            editableDraftText = ""
            feedbackMessage = "No se pudo preparar el informe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generateAIDraft() async {
        guard let reportContext else { return }

        isGeneratingDraft = true
        feedbackMessage = nil
        defer { isGeneratingDraft = false }

        do {
            let draft = try await reportService.generateDraft(
                from: reportContext,
                audience: aiAudience,
                tone: aiTone
            )

            aiDraft = draft
            aiMetadata = nil
            editableDraftText = draft.editableText(for: reportContext)

            feedbackMessage = aiAvailability.isAvailable
                ? "Borrador generado. Revísalo antes de exportar o compartir."
                : "Borrador por reglas preparado. Apple Intelligence no está disponible ahora mismo."
        } catch {
            feedbackMessage = "No se pudo preparar el borrador: \(error.localizedDescription)"
        }
    }

    private func refreshAIAvailability() {
        aiAvailability = reportService.currentAvailability()
    }

    private func loadSavedDraftForCurrentSelection() {
        guard let key = activeDraftKey else {
            editableDraftText = ""
            return
        }
        editableDraftText = draftStore.load(key: key)?.text ?? ""
    }

    private func saveDraft() {
        guard let key = activeDraftKey else { return }
        draftStore.save(
            text: consolidatedReportText,
            key: key,
            title: reportContext?.reportTitle ?? selectedReportKind.title
        )
        editableDraftText = consolidatedReportText
        feedbackMessage = "Borrador guardado localmente para esta combinación de informe."
    }

    private func copyReportText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(consolidatedReportText, forType: .string)
        feedbackMessage = "Texto copiado al portapapeles."
    }

    @MainActor
    private func export(format: ExportFormat) async {
        guard canExport else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let title = reportContext?.reportTitle ?? selectedReportKind.title
            let fileName = MacReportExportService.safeFileName(
                title: title,
                className: selectedClass?.name ?? "Grupo",
                studentName: selectedStudent?.fullName
            )
            let url = try MacReportExportService.destinationURL(
                suggestedFileName: fileName,
                fileExtension: format == .pdf ? "pdf" : "docx"
            )
            switch format {
            case .pdf:
                try MacReportExportService.writePDF(text: consolidatedReportText, title: title, to: url)
            case .docx:
                try MacReportExportService.writeDOCX(text: consolidatedReportText, title: title, to: url)
            }
            feedbackMessage = "\(format.rawValue) exportado en \(url.lastPathComponent)."
        } catch MacReportExportError.cancelled {
            feedbackMessage = "Exportación cancelada."
        } catch {
            feedbackMessage = "No se pudo exportar: \(error.localizedDescription)"
        }
    }
}
private struct MacReportPanelCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            content()
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacReportTextSection: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text("• \(line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacReportNotice: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MacReportDraftKey: Codable, Hashable {
    let classId: Int64
    let reportKind: String
    let period: String
    let studentId: Int64?

    var storageId: String {
        [
            "\(classId)",
            reportKind,
            period,
            studentId.map(String.init) ?? "group"
        ]
        .joined(separator: "::")
    }
}

private struct MacReportDraftRecord: Codable {
    let key: MacReportDraftKey
    let title: String
    let text: String
    let updatedAt: Date
}

private final class MacReportDraftStore {
    private let defaults = UserDefaults.standard
    private let prefix = "mac.reports.draft."

    func load(key: MacReportDraftKey) -> MacReportDraftRecord? {
        guard let data = defaults.data(forKey: prefix + key.storageId) else { return nil }
        return try? JSONDecoder().decode(MacReportDraftRecord.self, from: data)
    }

    func save(text: String, key: MacReportDraftKey, title: String) {
        let record = MacReportDraftRecord(key: key, title: title, text: text, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: prefix + key.storageId)
    }
}

private enum MacReportExportError: LocalizedError {
    case cancelled
    case documentBuildFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Exportación cancelada."
        case .documentBuildFailed:
            return "No se pudo construir el documento."
        }
    }
}

private enum MacReportExportService {
    static func destinationURL(suggestedFileName: String, fileExtension: String) throws -> URL {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(suggestedFileName).\(fileExtension)"
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let url = panel.url else {
            throw MacReportExportError.cancelled
        }
        return url
    }

    static func safeFileName(title: String, className: String, studentName: String?) -> String {
        let raw = [title, className, studentName].compactMap { $0 }.joined(separator: " - ")
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func writePDF(text: String, title: String, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 54
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSMutableAttributedString(string: "\(title)\n\n", attributes: titleAttributes)
        attributed.append(NSAttributedString(string: text, attributes: bodyAttributes))

        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: pageRect.width - margin * 2, height: pageRect.height - margin * 2))
        textView.textStorage?.setAttributedString(attributed)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = CGSize(width: pageRect.width - margin * 2, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        guard let container = textView.textContainer else {
            throw MacReportExportError.documentBuildFailed
        }
        textView.layoutManager?.ensureLayout(for: container)
        let usedHeight = (textView.layoutManager?.usedRect(for: container).height ?? pageRect.height) + margin
        textView.frame = CGRect(x: 0, y: 0, width: pageRect.width - margin * 2, height: max(usedHeight, pageRect.height - margin * 2))
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        try pdfData.write(to: url, options: .atomic)
    }

    static func writeDOCX(text: String, title: String, to url: URL) throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        \(paragraphXML(title, style: "Title"))
        \(text.components(separatedBy: .newlines).map { paragraphXML($0) }.joined())
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
        </w:body></w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
        """
        let core = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(xmlEscape(title))</dc:title><dc:creator>MiGestor</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">\(ISO8601DateFormatter().string(from: Date()))</dcterms:created></cp:coreProperties>
        """
        let archive = try MacReportZipArchive(files: [
            "[Content_Types].xml": Data(contentTypes.utf8),
            "_rels/.rels": Data(rels.utf8),
            "docProps/core.xml": Data(core.utf8),
            "word/document.xml": Data(documentXML.utf8)
        ]).data()
        try archive.write(to: url, options: .atomic)
    }

    private static func paragraphXML(_ text: String, style: String? = nil) -> String {
        let styleXML = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        let runXML = text.isEmpty
            ? "<w:r><w:t></w:t></w:r>"
            : "<w:r><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
        return "<w:p>\(styleXML)\(runXML)</w:p>"
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct MacReportZipArchive {
    let files: [String: Data]

    func data() throws -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for name in files.keys.sorted() {
            guard let content = files[name], let nameData = name.data(using: .utf8) else { continue }
            let crc = MacReportCRC32.checksum(content)
            let size = UInt32(content.count)
            let nameSize = UInt16(nameData.count)

            var local = Data()
            local.appendUInt32(0x04034b50)
            local.appendUInt16(20)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(nameSize)
            local.appendUInt16(0)
            local.append(nameData)
            local.append(content)
            output.append(local)

            var central = Data()
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(nameSize)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)
            centralDirectory.append(central)

            offset += UInt32(local.count)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(files.count))
        output.appendUInt16(UInt16(files.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)
        return output
    }
}

private enum MacReportCRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ])
    }
}
