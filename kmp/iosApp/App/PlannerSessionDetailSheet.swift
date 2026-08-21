import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import QuickLook
import MiGestorKit

enum PlannerSessionDetailPresentation {
    /// Modal clásico (iPad, y Mac cuando no hay inspector disponible).
    case sheet
    /// Panel lateral persistente del inspector de macOS: sin `NavigationStack`
    /// ni tamaño de ventana propio, solo una cabecera compacta con cierre.
    case inspector
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

    @State private var linkedInstruments: [PlannerAssessmentInstrument] = []
    @State private var isLoadingInstruments = false
    @State private var detailedPlan: LearningSituationSessionPlan?
    @State private var sequenceVersion: LearningSituationSessionSequenceVersion?
    @State private var sourceDocumentURL: URL?
    @State private var renderedDocument: PlannerDocxRenderResult?
    @State private var isLoadingRenderedDocument = false
    @State private var isDeleteConfirmationPresented = false

    private var tint: Color {
        Color(hex: session.teachingUnitColor)
    }

    private var detailProjection: PlannerSessionDetailProjection? {
        guard let detailedPlan else { return nil }
        return PlannerSessionDetailProjection(plan: detailedPlan)
    }

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                NavigationStack {
                    detailContent
                        .navigationTitle("Sesión")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cerrar") {
                                    dismiss()
                                }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 760, idealWidth: 860, minHeight: 720, idealHeight: 820)
                #else
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            case .inspector:
                VStack(spacing: 0) {
                    inspectorHeader
                    detailContent
                }
            }
        }
        .task(id: session.id) {
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

    private var inspectorHeader: some View {
        HStack {
            Text("Sesión")
                .font(.headline.weight(.bold))
            Spacer()
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cerrar el inspector de la sesión")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            sessionBriefHeader
            quickActionBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let projection = detailProjection {
                        teacherAtAGlanceSection(projection)
                        developmentTimeline(projection)
                        supportSections(projection.supportSections)
                        renderedDocumentSection
                        if let detailedPlan {
                            sourceDocumentSection(detailedPlan)
                        }
                    } else {
                        fallbackSessionSections
                    }
                    instrumentsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

    private var sessionBriefHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        sessionChip(session.groupName, systemImage: "person.3.fill")
                        sessionChip("Planificada", systemImage: "checkmark.circle.fill")
                        if let detailedPlan {
                            sessionChip("Sesión \(detailedPlan.sessionNumber)", systemImage: "number")
                            sessionChip("\(detailedPlan.sessionType) · \(detailedPlan.effectiveMinutes) min", systemImage: "timer")
                        }
                    }
                    Text(detailedPlan?.title ?? session.teachingUnitName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(dateAndTimeLabel, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openSourceDocumentPreview()
                } label: {
                    Label("Ver DOCX", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(sourceDocumentFileURL == nil)
            }
        }
        .padding(24)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var quickActionBar: some View {
        HStack(spacing: 16) {
            Button(action: onOpenDiary) {
                Label("Abrir ejecución", systemImage: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .keyboardShortcut(.defaultAction)

            Button(action: onEdit) {
                Label("Editar", systemImage: "pencil")
                    .font(.headline.weight(.semibold))
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)

            if onCopyToNextWeek != nil {
                Button {
                    onCopyToNextWeek?()
                } label: {
                    Label("Duplicar", systemImage: "doc.on.doc")
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .help("Copiar esta sesión a la misma franja de la semana siguiente")
            }

            if onDelete != nil {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(EvaluationDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
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

    private func teacherAtAGlanceSection(_ projection: PlannerSessionDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !projection.objective.isEmpty {
                teacherCard(title: "Objetivo de hoy", icon: "target", text: projection.objective, prominence: .hero)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                summaryMetric(value: "\(projection.activityCount)", label: "momentos", icon: "list.number")
                summaryMetric(value: "\(projection.evidence.count)", label: "evidencias", icon: "checkmark.seal")
                summaryMetric(value: "\(projection.criteria.count)", label: "criterios", icon: "scope")
                if let detailedPlan, detailedPlan.effectiveMinutes > 0 {
                    summaryMetric(value: "\(detailedPlan.effectiveMinutes)′", label: "tiempo útil", icon: "timer")
                }
            }

            if !projection.criteria.isEmpty || !projection.evidence.isEmpty {
                evaluationCard(criteria: projection.criteria, evidence: projection.evidence)
            }

            if !projection.materials.isEmpty {
                materialCard(items: projection.materials, basicKnowledge: projection.basicKnowledge)
            } else if !projection.basicKnowledge.isEmpty {
                informationCard(title: "Saberes básicos", icon: "book.closed", lines: projection.basicKnowledge)
            }

            if !projection.adaptations.isEmpty {
                informationCard(title: "Adaptaciones y roles inclusivos", icon: "person.crop.rectangle.badge.plus", lines: projection.adaptations)
            }
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
        .padding(prominence == .hero ? 24 : 20)
        .plannerGlassPanel(prominence == .hero ? .hero : .content, cornerRadius: 20)
    }

    private func summaryMetric(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .plannerGlassPanel(.control, cornerRadius: 16)
    }

    private func evaluationCard(criteria: [String], evidence: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Qué observar y recoger", systemImage: "checkmark.seal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            if !criteria.isEmpty {
                WorkspaceFlowLayout(spacing: 8) {
                    ForEach(criteria, id: \.self) { criterion in
                        Text(criterion)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                }
            }
            if !evidence.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidencia prevista")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(evidence, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
    }

    private func materialCard(items: [String], basicKnowledge: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Material preparado", systemImage: "shippingbox")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            WorkspaceFlowLayout(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(EvaluationDesign.surfaceSoft, in: Capsule())
                }
            }
            if !basicKnowledge.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saberes básicos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(basicKnowledge.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
    }

    private func informationCard(title: String, icon: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
    }

    private func developmentTimeline(_ projection: PlannerSessionDetailProjection) -> some View {
        return Group {
            if !projection.timeline.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Guion de la clase", systemImage: "list.bullet.rectangle.portrait")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(tint)
                        Text("Sigue el orden, los roles y las evidencias sin volver al documento original.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        ForEach(projection.timeline) { block in
                            timelineBlock(block)
                        }
                    }
                }
                .padding(20)
                .plannerGlassPanel(.content, cornerRadius: 20)
            }
        }
    }

    private func timelineBlock(_ block: PlannerSessionTimelineBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: blockIcon(block.kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(block.kind == .breakTime ? .secondary : tint)
                Text(block.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let durationLabel = block.durationLabel {
                    Text(durationLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(block.kind == .breakTime ? .secondary : tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background((block.kind == .breakTime ? Color.secondary : tint).opacity(0.10), in: Capsule())
                }
            }

            if block.kind == .breakTime {
                Text(block.steps.map(\.activity).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(block.steps) { step in
                        timelineStep(step)
                    }
                }
            }
        }
        .padding(16)
        .background(block.kind == .breakTime ? EvaluationDesign.surfaceSoft : EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(block.kind == .breakTime ? EvaluationDesign.border : tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func timelineStep(_ step: PlannerSessionTimelineStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let timeLabel = step.timeLabel {
                    Text(timeLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(minWidth: 52, alignment: .leading)
                }
                if let phase = step.phase {
                    Text(phase)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Spacer(minLength: 0)
            }
            Text(step.activity)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                if let teacherRole = step.teacherRole {
                    roleLine("Profesorado", teacherRole, icon: "person.crop.circle.badge.checkmark")
                }
                if let studentRole = step.studentRole {
                    roleLine("Alumnado", studentRole, icon: "person.2")
                }
                if let evidence = step.evidence {
                    roleLine("Evidencia", evidence, icon: "checkmark.seal")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func roleLine(_ label: String, _ text: String, icon: String) -> some View {
        Label {
            Text("\(label): \(text)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    private func supportSections(_ sections: [PlannerSessionSupportSection]) -> some View {
        Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Contexto docente", systemImage: "note.text")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                    ForEach(sections) { section in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(section.lines, id: \.self) { line in
                                    Text(line)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label(section.title, systemImage: supportIcon(for: section.title))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .tint(tint)
                        if section.id != sections.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(20)
                .plannerGlassPanel(.content, cornerRadius: 20)
            }
        }
    }

    private func blockIcon(_ kind: PlannerSessionTimelineBlock.Kind) -> String {
        switch kind {
        case .activity: return "figure.run"
        case .breakTime: return "cup.and.saucer"
        case .prepare: return "arrow.down.right.and.arrow.up.left"
        case .consolidate: return "arrow.triangle.2.circlepath"
        }
    }

    private func supportIcon(for title: String) -> String {
        let value = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if value.contains("antes") || value.contains("before") || value.contains("prepar") { return "checklist" }
        if value.contains("espacio") || value.contains("space") || value.contains("rotac") { return "square.grid.2x2" }
        if value.contains("clil") || value.contains("vocab") || value.contains("language") { return "character.book.closed" }
        if value.contains("pregunta") || value.contains("guiding") { return "questionmark.bubble" }
        if value.contains("cierre") || value.contains("closure") { return "flag.checkered" }
        return "text.alignleft"
    }

    private func sourceDocumentSection(_ plan: LearningSituationSessionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                Button {
                    openSourceDocumentPreview()
                } label: {
                    Label("Ver documento", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(sourceDocumentFileURL == nil)
            }

            Text(sourceDocumentFileURL == nil ? "Documento original no disponible en este dispositivo." : "Abre una previsualización nativa para resolver dudas sin salir del planificador.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
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
            .padding(20)
            .plannerGlassPanel(.content, cornerRadius: 20)
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
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                }
                Text("Vista reconstruida del bloque de esta sesión, manteniendo el orden del documento original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PlannerDocxWebView(html: renderedDocument.html)
            }
            .padding(20)
            .plannerGlassPanel(.content, cornerRadius: 20)
        }
    }

    private var sourceDocumentFileURL: URL? {
        guard let path = sequenceVersion?.localPath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func openSourceDocumentPreview() {
        guard let url = sourceDocumentFileURL else { return }
        sourceDocumentURL = url
    }

    private var dateAndTimeLabel: String {
        if let startTime = session.startTime, let endTime = session.endTime {
            return "\(dateString) · \(startTime)-\(endTime)"
        }
        return "\(dateString) · Periodo \(session.period)"
    }

    private func sessionChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private enum TeacherCardProminence {
        case standard
        case hero
    }

    @MainActor
    private func loadDetailedPlan() async {
        renderedDocument = nil
        isLoadingRenderedDocument = false
        guard let planId = session.learningSituationSessionPlanId?.int64Value else { return }
        guard let plan = try? await bridge.learningSituationSessionPlan(id: planId) else { return }
        detailedPlan = plan
        let loadedSequenceVersion = try? await bridge.learningSituationSessionSequenceVersion(
            id: plan.sequenceVersionId,
            learningSituationId: plan.learningSituationId
        )
        sequenceVersion = loadedSequenceVersion

        guard let path = loadedSequenceVersion?.localPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sourceURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        isLoadingRenderedDocument = true
        let sourceLabel = plan.sourceLabel
        let sessionNumber = Int(plan.sessionNumber)
        renderedDocument = await Task.detached(priority: .userInitiated) {
            try? PlannerSessionDocxRenderer().render(
                from: sourceURL,
                sourceLabel: sourceLabel,
                sessionNumber: sessionNumber
            )
        }.value
        isLoadingRenderedDocument = false
    }
    
    private var instrumentsSection: some View {
        Group {
            if isLoadingInstruments {
                ProgressView()
                    .padding()
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
                                    .padding(8)
                                    .background(tint.opacity(0.1))
                                    .clipShape(Circle())
                                
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
                            .padding(12)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(EvaluationDesign.surfaceSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 1)
                )
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
