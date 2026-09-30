import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import QuickLook
import CryptoKit
import MiGestorKit
#if os(macOS)
import AppKit
#endif

enum PlannerSessionDetailPresentation {
    /// Modal clásico (iPad, y Mac cuando no hay inspector disponible).
    case sheet
    /// Panel lateral persistente del inspector de macOS: sin `NavigationStack`
    /// ni tamaño de ventana propio, solo una cabecera compacta con cierre.
    case inspector
}

enum PlannerSessionDetailLayout: Equatable {
    case regular
    case compact
}

struct PlannerSessionDetailLayoutPolicy {
    /// Keeps two useful reading columns on full-size iPad landscape and macOS while
    /// falling back before either pane becomes cramped in portrait or split view.
    static let regularMinimumWidth: CGFloat = 900

    static func layout(for width: CGFloat) -> PlannerSessionDetailLayout {
        width >= regularMinimumWidth ? .regular : .compact
    }
}

enum PlannerSessionDetailSessionType {
    static func label(for rawValue: String) -> String {
        let normalized = rawValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if normalized.contains("simple") && normalized.contains("doble") {
            return "LONG / SHORT"
        }
        if normalized.contains("short") || normalized.contains("simple") || normalized.contains("corto") {
            return "SHORT"
        }
        if normalized.contains("long") || normalized.contains("double") || normalized.contains("doble") || normalized.contains("largo") {
            return "LONG"
        }
        return rawValue.uppercased()
    }
}

struct PlannerSessionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    let session: PlanningSession
    let onOpenDiary: () -> Void
    let onEdit: () -> Void
    var onDelete: (() -> Void)? = nil
    var onCopyToNextWeek: (() -> Void)? = nil
    var presentation: PlannerSessionDetailPresentation = .sheet
    var onClose: (() -> Void)? = nil

    @StateObject private var attachmentStore: PlannerSessionAttachmentStore

    init(
        session: PlanningSession,
        onOpenDiary: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onCopyToNextWeek: (() -> Void)? = nil,
        presentation: PlannerSessionDetailPresentation = .sheet,
        onClose: (() -> Void)? = nil
    ) {
        self.session = session
        self.onOpenDiary = onOpenDiary
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onCopyToNextWeek = onCopyToNextWeek
        self.presentation = presentation
        self.onClose = onClose
        _attachmentStore = StateObject(wrappedValue: PlannerSessionAttachmentStore(sessionId: session.id))
        _loadState = State(initialValue: session.learningSituationSessionPlanId == nil ? .empty : .loading)
    }

    @State private var linkedInstruments: [PlannerAssessmentInstrument] = []
    @State private var isLoadingInstruments = false
    @State private var detailedPlan: LearningSituationSessionPlan?
    @State private var sequenceVersion: LearningSituationSessionSequenceVersion?
    @State private var sourceDocumentURL: URL?
    @State private var renderedDocument: PlannerDocxRenderResult?
    @State private var renderedActivityVisuals: [String: String] = [:]
    @State private var isLoadingRenderedDocument = false
    @State private var isDeleteConfirmationPresented = false
    @State private var enlargedVisual: PlannerEnlargedVisual?
    @State private var isAnnexesExpanded = false
    /// Proyección de repaso rápido: se calcula una sola vez al cargar el plan.
    @State private var reviewProjection: PlannerSessionDetailProjection?
    @State private var loadState: LoadState

    enum LoadState: Equatable {
        case loading
        case loaded
        case empty
        case failed
    }

    private var tint: Color {
        Color(hex: session.teachingUnitColor)
    }

    /// Solo se muestra cuando la sesión ya no está simplemente «Planificada».
    private var sessionStatusBadge: (label: String, systemImage: String, tint: Color)? {
        switch session.status {
        case .completed:
            return ("Impartida", "checkmark.circle.fill", EvaluationDesign.success)
        case .cancelled:
            return ("Cancelada", "xmark.circle.fill", EvaluationDesign.danger)
        case .inProgress:
            return ("En curso", "play.circle.fill", EvaluationDesign.accent)
        default:
            return nil
        }
    }

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                detailContent
                #if os(macOS)
                .frame(minWidth: 900, idealWidth: 1_080, minHeight: 640, idealHeight: 800)
                #else
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            case .inspector:
                detailContent
            }
        }
        .task(id: session.id) {
            isAnnexesExpanded = false
            await loadDetailedPlan()
            await loadLinkedInstruments()
        }
        .quickLookPreview($sourceDocumentURL)
        .confirmationDialog(
            "Eliminar sesión",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Eliminar sesión", role: .destructive) {
                onDelete?()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará esta sesión planificada. Los diarios de sesiones ya impartidas no se ven afectados.")
        }
    }

    /// Un solo scroll con columna legible (~820 pt) en hoja iPad, hoja Mac e inspector Mac.
    @ViewBuilder
    private var detailContent: some View {
        switch presentation {
        case .sheet:
            GeometryReader { proxy in
                sheetContent(layout: PlannerSessionDetailLayoutPolicy.layout(for: proxy.size.width))
            }
        case .inspector:
            sheetContent(layout: .compact)
        }
    }

    private func sheetContent(layout: PlannerSessionDetailLayout) -> some View {
        VStack(spacing: 0) {
            sessionHeader(layout: layout)
            reviewScrollContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

    private var reviewScrollContent: some View {
        ScrollView {
            reviewBody
                .frame(maxWidth: 820, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, presentation == .inspector ? 16 : 24)
                .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $enlargedVisual) { visual in
            PlannerEnlargedVisualSheet(visual: visual)
        }
    }

    @ViewBuilder
    private var reviewBody: some View {
        switch loadState {
        case .loading:
            PlannerReviewSkeleton()
        case .failed:
            PlannerReviewErrorState {
                loadState = .loading
                Task { await loadDetailedPlan() }
            }
        case .loaded, .empty:
            loadedBody
        }
    }

    private var loadedBody: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let projection = reviewProjection {
                if !projection.guideBlocks.isEmpty {
                    PlannerSessionTimelineBar(
                        activities: projection.activities,
                        tint: tint,
                        effectiveMinutes: Int(detailedPlan?.effectiveMinutes ?? 0)
                    )
                }
                PlannerReviewBrief(
                    objective: projection.reviewObjective,
                    setup: projection.setupBullets,
                    attention: projection.attentionNotes,
                    tint: tint
                )
                guideContent(projection)
            }
            if loadState == .empty {
                if session.learningSituationSessionPlanId == nil {
                    fallbackSessionSections
                }
                PlannerReviewEmptyState(tint: tint, onEdit: onEdit)
            }
            annexesDisclosure
        }
    }

    // MARK: Guion por bloques

    private func guideContent(_ projection: PlannerSessionDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(Array(projection.guideBlocks.enumerated()), id: \.element.id) { index, block in
                VStack(alignment: .leading, spacing: 16) {
                    if block.precededByBreak {
                        PlannerReviewBreakRow()
                    }
                    if let title = blockTitle(block, index: index, total: projection.guideBlocks.count) {
                        PlannerReviewBlockHeader(title: title, tint: tint)
                    }
                    ForEach(block.steps) { step in
                        PlannerReviewStepRow(
                            step: step,
                            tint: tint,
                            visualHTML: step.isMain ? mainVisualHTML(for: step) : nil
                        ) { html in
                            enlargedVisual = PlannerEnlargedVisual(title: step.title, html: html)
                        }
                    }
                }
            }
        }
    }

    private func mainVisualHTML(for step: PlannerSessionReviewStep) -> String? {
        guard let html = renderedActivityVisuals[step.activityKey], !html.isEmpty else { return nil }
        return html
    }

    /// `U01 · Título · 40 min`. Sin etiqueta de segmento solo se titula si hay más de un bloque.
    private func blockTitle(_ block: PlannerSessionReviewBlock, index: Int, total: Int) -> String? {
        let base = block.label ?? (total > 1 ? "Bloque \(index + 1)" : nil)
        guard let base else { return nil }
        return block.totalMinutes > 0 ? "\(base) · \(block.totalMinutes) min" : base
    }

    // MARK: Cabecera

    @ViewBuilder
    private func sessionHeader(layout: PlannerSessionDetailLayout) -> some View {
        if layout == .regular {
            HStack(alignment: .center, spacing: 24) {
                sessionHeaderMetadata
                Spacer(minLength: 24)
                sessionHeaderActions(expandsPrimaryAction: false)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(EvaluationDesign.surface)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                sessionHeaderMetadata
                sessionHeaderActions(expandsPrimaryAction: true)
            }
            .padding(16)
            .background(EvaluationDesign.surface)
        }
    }

    private var sessionHeaderMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detailedPlan?.title ?? session.teachingUnitName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(headerMetaLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let badge = sessionStatusBadge {
                PlannerStatusBadge(label: badge.label, systemImage: badge.systemImage, tint: badge.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sesión \(detailedPlan?.title ?? session.teachingUnitName)")
        .accessibilityValue(sessionAccessibilityMetadata)
    }

    /// Fecha · hora · grupo · Sesión N · X min, en una sola línea de texto.
    private var headerMetaLine: String {
        var parts = [dateAndTimeLabel, session.groupName]
        if let detailedPlan {
            parts.append("Sesión \(detailedPlan.sessionNumber)")
            parts.append("\(detailedPlan.effectiveMinutes) min")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var sessionAccessibilityMetadata: String {
        var values = [session.groupName, dateAndTimeLabel]
        if let badge = sessionStatusBadge { values.insert(badge.label, at: 1) }
        if let detailedPlan {
            values.append("Sesión \(detailedPlan.sessionNumber)")
            values.append("\(detailedPlan.effectiveMinutes) minutos")
        }
        return values.joined(separator: ", ")
    }

    private func sessionHeaderActions(expandsPrimaryAction: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onOpenDiary) {
                Label("Abrir ejecución", systemImage: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(maxWidth: expandsPrimaryAction ? .infinity : nil, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Abrir ejecución de la sesión")

            sessionActionsMenu

            Button(action: closeSessionDetail) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Cerrar la ficha de sesión")
            .accessibilityLabel("Cerrar la ficha de sesión")
        }
    }

    private var sessionActionsMenu: some View {
        Menu {
            Button(action: onEdit) { Label("Editar", systemImage: "pencil") }
            if onCopyToNextWeek != nil {
                Button { onCopyToNextWeek?() } label: { Label("Duplicar", systemImage: "doc.on.doc") }
            }
            if sourceDocumentFileURL != nil {
                Button { openSourceDocumentPreview() } label: { Label("Ver DOCX", systemImage: "doc.text.magnifyingglass") }
            }
            if onDelete != nil {
                Button(role: .destructive) { isDeleteConfirmationPresented = true } label: { Label("Eliminar", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Más acciones de la sesión")
    }

    private func closeSessionDetail() {
        switch presentation {
        case .sheet:
            dismiss()
        case .inspector:
            onClose?()
        }
    }

    private var fallbackSessionSections: some View {
        VStack(spacing: 16) {
            let objText = session.objectives.trimmingCharacters(in: .whitespacesAndNewlines)
            if !objText.isEmpty {
                teacherCard(title: "Objetivo de hoy", icon: "target", text: objText, prominence: .hero)
            }

            let actText = session.activities.trimmingCharacters(in: .whitespacesAndNewlines)
            if !actText.isEmpty {
                teacherCard(title: "Actividades programadas", icon: "list.bullet.rectangle.portrait", text: actText)
            }

            let evalText = session.evaluation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !evalText.isEmpty {
                teacherCard(title: "Evaluación", icon: "checkmark.seal", text: evalText)
            }
        }
    }

    // MARK: Evidencia y trazabilidad (plegado)

    private var annexesDisclosure: some View {
        DisclosureGroup(isExpanded: $isAnnexesExpanded) {
            annexesContent
                .padding(.top, 16)
        } label: {
            Text("Evidencia y trazabilidad")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityHint("Muestra evidencias, criterios, documento original y adjuntos")
    }

    private var annexesContent: some View {
        VStack(spacing: 16) {
            PlannerSessionAttachmentGalleryView(store: attachmentStore, tint: tint)

            if let projection = reviewProjection {
                if let chunks = projection.clilChunks, !chunks.isEmpty {
                    PlannerSessionCLILChunksCard(chunks: chunks, tint: tint)
                }
                if !projection.evidence.isEmpty {
                    teacherCard(title: "Evidencias", icon: "checklist", text: projection.evidence.joined(separator: "\n"))
                }
                if !projection.criteria.isEmpty {
                    teacherCard(title: "Criterios de evaluación", icon: "checkmark.seal", text: projection.criteria.joined(separator: "\n"))
                }
                // Montaje y atención completos si el resumen de arriba recortó algo.
                if projection.setupAll != projection.setupBullets {
                    teacherCard(title: "Montaje completo", icon: "square.split.2x2", text: projection.setupAll.joined(separator: "\n"))
                }
                if projection.attentionAll != projection.attentionNotes {
                    teacherCard(title: "Atención completa", icon: "exclamationmark.triangle", text: projection.attentionAll.joined(separator: "\n"))
                }
                if !projection.guidingQuestions.isEmpty {
                    teacherCard(title: "Preguntas guía", icon: "questionmark.bubble", text: projection.guidingQuestions.joined(separator: "\n"))
                }
                if !projection.closure.isEmpty {
                    teacherCard(title: "Cierre", icon: "flag.checkered", text: projection.closure)
                }
            }
            if let detailedPlan {
                sourceDocumentSection(detailedPlan)
                renderedDocumentSection
            }
            instrumentsSection
        }
    }

    private func teacherCard(title: String, icon: String, text: String, prominence: TeacherCardProminence = .standard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(prominence == .hero ? .title3.weight(.semibold) : .body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, prominence == .hero ? 16 : 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private func sourceDocumentSection(_ plan: LearningSituationSessionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documento original")
                        .font(.headline.weight(.semibold))
                    Text(sequenceVersion?.originalFileName ?? plan.sourceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if sourceDocumentFileURL != nil {
                    Button {
                        openSourceDocumentPreview()
                    } label: {
                        Label("Ver documento", systemImage: "eye")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .buttonStyle(.plain)
                }
            }

            Label(
                sourceDocumentFileURL == nil
                    ? "Documento original no disponible en este dispositivo."
                    : "Abre una previsualización nativa para resolver dudas sin salir del planificador.",
                systemImage: sourceDocumentFileURL == nil ? "info.circle" : "checkmark.circle"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var renderedDocumentSection: some View {
        if isLoadingRenderedDocument {
            VStack(alignment: .leading, spacing: 12) {
                Label("Preparando el documento de sesión", systemImage: "doc.richtext")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Se están reconstruyendo las tablas e imágenes del DOCX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        } else if let renderedDocument {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label("Documento de sesión", systemImage: "doc.richtext")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    if !renderedDocument.featureSummary.isEmpty {
                        Text(renderedDocument.featureSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                Text("Vista reconstruida del bloque de esta sesión, manteniendo el orden del documento original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PlannerDocxWebView(html: renderedDocument.html)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(height: 1)
            }
        }
    }

    private var sourceDocumentFileURL: URL? {
        resolvedSourceDocumentURL(for: sequenceVersion)
    }

    private func openSourceDocumentPreview() {
        guard let url = sourceDocumentFileURL else { return }
#if os(macOS)
        // QuickLook is not consistently presented from a macOS inspector. Opening the
        // cached original through the system workspace keeps the visible button useful
        // while the sheet still uses QuickLook on iOS/iPadOS.
        _ = NSWorkspace.shared.open(url)
#else
        sourceDocumentURL = url
#endif
    }

    private var dateAndTimeLabel: String {
        if let startTime = session.startTime, let endTime = session.endTime {
            return "\(dateString) · \(startTime)-\(endTime)"
        }
        return "\(dateString) · Periodo \(session.period)"
    }

    private enum TeacherCardProminence {
        case standard
        case hero
    }

    @MainActor
    private func loadDetailedPlan() async {
        renderedDocument = nil
        renderedActivityVisuals = [:]
        isLoadingRenderedDocument = false
        reviewProjection = nil
        detailedPlan = nil
        sequenceVersion = nil
        guard let planId = session.learningSituationSessionPlanId?.int64Value else {
            detailedPlan = nil
            loadState = .empty
            return
        }
        loadState = .loading
        let plan: LearningSituationSessionPlan
        do {
            guard let loaded = try await bridge.learningSituationSessionPlan(id: planId) else {
                detailedPlan = nil
                loadState = .empty
                return
            }
            plan = loaded
        } catch {
            if Task.isCancelled { return }
            detailedPlan = nil
            loadState = .failed
            return
        }
        detailedPlan = plan
        let projection = PlannerSessionDetailProjection(plan: plan)
        reviewProjection = projection
        loadState = projection.guideBlocks.isEmpty ? .empty : .loaded
        let loadedSequenceVersion = try? await bridge.learningSituationSessionSequenceVersion(
            id: plan.sequenceVersionId,
            learningSituationId: plan.learningSituationId
        )
        sequenceVersion = loadedSequenceVersion
        _ = await bridge.ensureLearningSituationSessionSequenceDocument(version: loadedSequenceVersion)
        // Re-evaluate the computed URL after a metadata-first sync has downloaded the
        // binary into the hash-addressed document store.
        sequenceVersion = loadedSequenceVersion

        guard let sourceURL = resolvedSourceDocumentURL(for: loadedSequenceVersion) else { return }

        isLoadingRenderedDocument = true
        let sourceLabel = plan.sourceLabel
        let sessionNumber = Int(plan.sessionNumber)
        let payload = LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)
        let route = payload?.sequenceRoute
        let visualReferences = payload?.visuals ?? []
        let activityVisualReferences = (payload.map(PlannerSessionPlanPayloadNormalizer.activities(from:)) ?? [])
            .filter { !$0.visuals.isEmpty }
        renderedDocument = await Task.detached(priority: .userInitiated) {
            try? PlannerSessionDocxRenderer().render(
                from: sourceURL,
                sourceLabel: sourceLabel,
                sessionNumber: sessionNumber,
                route: route,
                visualReferences: visualReferences
            )
        }.value
        if !activityVisualReferences.isEmpty {
            renderedActivityVisuals = await Task.detached(priority: .userInitiated) {
                let renderer = PlannerSessionDocxRenderer()
                var rendered: [String: String] = [:]
                for activity in activityVisualReferences {
                    if let result = try? renderer.renderVisualReferences(
                        from: sourceURL,
                        references: activity.visuals
                    ), result.imageCount > 0 {
                        rendered[activity.activityKey] = result.html
                    }
                }
                return rendered
            }.value
        }
        isLoadingRenderedDocument = false
    }

    private func resolvedSourceDocumentURL(for version: LearningSituationSessionSequenceVersion?) -> URL? {
        guard let sha256 = version?.sha256.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha256.isEmpty else {
            guard let path = version?.localPath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let cachedURL = LearningSituationDocumentStore().directoryURL
            .appendingPathComponent("\(sha256).docx")
        guard let data = try? Data(contentsOf: cachedURL) else { return nil }
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actualHash == sha256 ? cachedURL : nil
    }
    
    private var instrumentsSection: some View {
        Group {
            if isLoadingInstruments {
                ProgressView()
                    .padding(.vertical, 12)
            } else if !linkedInstruments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.plaintext.fill")
                            .foregroundColor(tint)
                            .font(.headline)
                        Text("Evaluaciones enlazadas")
                            .font(.system(.headline, design: .rounded))
                            .bold()
                            .foregroundColor(.primary)
                    }
                    
                    VStack(spacing: 10) {
                        ForEach(linkedInstruments, id: \.id) { instrument in
                            HStack(spacing: 12) {
                                Image(systemName: instrument.kind == .rubric ? "tablecells" : "doc.text.magnifyingglass")
                                    .foregroundColor(tint)
                                    .font(.subheadline)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instrument.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(instrument.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(EvaluationDesign.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
    
    private var dateString: String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.yearForWeekOfYear = Int(session.year)
        components.weekOfYear = Int(session.weekNumber)
        components.weekday = Int(session.dayOfWeek) + 1
        
        guard let date = components.date else { return "" }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadLinkedInstruments() async {
        guard !session.linkedAssessmentIdsCsv.isEmpty else { return }
        isLoadingInstruments = true
        defer { isLoadingInstruments = false }
        
        do {
            let allInstruments = try await bridge.plannerAvailableAssessmentInstruments(
                classId: session.groupId,
                teachingUnitId: session.teachingUnitId == 0 ? nil : session.teachingUnitId
            )
            let linkedIds = Set(session.linkedAssessmentIdsCsv.split(separator: ",").map(String.init))
            linkedInstruments = allInstruments.filter { linkedIds.contains($0.id) }
        } catch {
            print("Error loading linked instruments: \(error)")
        }
    }
}
