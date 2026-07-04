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
    var presentation: PlannerSessionDetailPresentation = .sheet
    var onClose: (() -> Void)? = nil

    @State private var linkedInstruments: [PlannerAssessmentInstrument] = []
    @State private var isLoadingInstruments = false
    @State private var detailedPlan: LearningSituationSessionPlan?
    @State private var sequenceVersion: LearningSituationSessionSequenceVersion?
    @State private var sourceDocumentURL: URL?

    private var tint: Color {
        Color(hex: session.teachingUnitColor)
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
        .task {
            await loadDetailedPlan()
            await loadLinkedInstruments()
        }
        .quickLookPreview($sourceDocumentURL)
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
                VStack(spacing: 16) {
                    if let detailedPlan {
                        teacherAtAGlanceSection(detailedPlan)
                        developmentTimeline(detailedPlan)
                        sourceDocumentSection(detailedPlan)
                    } else {
                        fallbackSessionSections
                    }
                    instrumentsSection
                }
                .padding(24)
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

    private func teacherAtAGlanceSection(_ plan: LearningSituationSessionPlan) -> some View {
        VStack(spacing: 16) {
            let objective = plan.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            if !objective.isEmpty {
                teacherCard(title: "Objetivo de hoy", icon: "target", text: objective, prominence: .hero)
            }

            let criteria = decodedCriteria(plan)
            let evidence = evidenceText(from: decodedDevelopment(plan))
            if !criteria.isEmpty || !evidence.isEmpty {
                evaluationCard(criteria: criteria, evidence: evidence)
            }

            let material = plan.material.trimmingCharacters(in: .whitespacesAndNewlines)
            if !material.isEmpty {
                materialCard(material)
            }

            let adaptations = decodedAdaptations(plan)
            if !adaptations.isEmpty {
                teacherCard(title: "Adaptaciones y contexto", icon: "person.crop.rectangle", text: adaptations.joined(separator: "\n"))
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func evaluationCard(criteria: [String], evidence: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Evaluación", systemImage: "checkmark.seal")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidencia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(evidence)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func materialCard(_ material: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Material preparado", systemImage: "shippingbox")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            WorkspaceFlowLayout(spacing: 8) {
                ForEach(materialItems(from: material), id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(EvaluationDesign.surfaceSoft, in: Capsule())
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func developmentTimeline(_ plan: LearningSituationSessionPlan) -> some View {
        let sections = timelineSections(from: decodedDevelopment(plan))
        return Group {
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Label("Desarrollo de la clase", systemImage: "list.bullet.rectangle.portrait")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(tint)
                        Spacer()
                        if plan.effectiveMinutes > 0 {
                            Text("\(plan.effectiveMinutes) min útiles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tint.opacity(0.10), in: Capsule())
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(sections) { section in
                            timelineBlock(section)
                        }
                    }
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
            }
        }
    }

    private func timelineBlock(_ section: LearningSituationSessionSectionDraft) -> some View {
        let marker = timelineMarker(from: section.title)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Capsule()
                    .fill(tint.opacity(0.16))
                    .frame(width: 2, height: 44)
            }
            .padding(.top, 8)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let marker {
                        Text(marker)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                    Text(cleanTimelineTitle(section.title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        timelineStep(line)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func timelineStep(_ line: String) -> some View {
        let parts = developmentLineParts(line)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(tint.opacity(0.72))
                .padding(.top, 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let title = parts.title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(parts.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func developmentLineParts(_ line: String) -> (title: String?, detail: String) {
        guard let separator = line.firstIndex(of: ":") else {
            return (nil, line)
        }
        let title = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !detail.isEmpty else { return (nil, line) }
        return (title, detail)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
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

    private func decodedCriteria(_ plan: LearningSituationSessionPlan) -> [String] {
        ((try? JSONDecoder().decode([String].self, from: Data(plan.criteriaJson.utf8))) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodedDevelopment(_ plan: LearningSituationSessionPlan) -> [LearningSituationSessionSectionDraft] {
        (try? JSONDecoder().decode([LearningSituationSessionSectionDraft].self, from: Data(plan.developmentJson.utf8))) ?? []
    }

    private func decodedAdaptations(_ plan: LearningSituationSessionPlan) -> [String] {
        ((try? JSONDecoder().decode([String].self, from: Data(plan.adaptationsJson.utf8))) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func evidenceText(from sections: [LearningSituationSessionSectionDraft]) -> String {
        sections
            .filter { isEvidenceSection($0) }
            .flatMap { section in
                section.lines.isEmpty ? [metadataValue(from: section.title) ?? section.title] : section.lines
            }
            .map { metadataValue(from: $0) ?? $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func timelineSections(from sections: [LearningSituationSessionSectionDraft]) -> [LearningSituationSessionSectionDraft] {
        sections.compactMap { section in
            guard !isEvidenceSection(section), !isMetadataLine(section.title) else { return nil }
            let filteredLines = section.lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isMetadataLine($0) }
            if filteredLines.isEmpty, !looksLikeTimelineTitle(section.title) { return nil }
            return LearningSituationSessionSectionDraft(title: section.title, lines: filteredLines)
        }
    }

    private func isEvidenceSection(_ section: LearningSituationSessionSectionDraft) -> Bool {
        let title = normalizedSessionText(section.title)
        return title.hasPrefix("evidencia") || title.hasPrefix("evidence")
    }

    private func isMetadataLine(_ text: String) -> Bool {
        let value = normalizedSessionText(text)
        return value.hasPrefix("objective:")
            || value.hasPrefix("objectives:")
            || value.hasPrefix("objetivo:")
            || value.hasPrefix("objetivos:")
            || value.hasPrefix("criterion:")
            || value.hasPrefix("criteria:")
            || value.hasPrefix("criterio:")
            || value.hasPrefix("criterios:")
            || value.hasPrefix("materials:")
            || value.hasPrefix("material:")
            || value.hasPrefix("materiales:")
            || value.hasPrefix("evidence:")
            || value.hasPrefix("evidencia:")
    }

    private func metadataValue(from text: String) -> String? {
        guard let separator = text.firstIndex(of: ":") else { return nil }
        let prefix = normalizedSessionText(String(text[..<separator]))
        guard ["evidence", "evidencia"].contains(prefix) else { return nil }
        return String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func materialItems(from material: String) -> [String] {
        let items = material
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        return items.isEmpty ? [material] : items
    }

    private func timelineMarker(from title: String) -> String? {
        if let range = title.range(of: #"^[0-9]{1,3}\s*(?:'|’|min)?\s*[-–—]\s*[0-9]{1,3}\s*(?:'|’|min)?"#, options: .regularExpression) {
            return String(title[range])
        }
        if let range = title.range(of: #"\([0-9]{1,3}\s*(?:'|’|min)\)"#, options: .regularExpression) {
            return String(title[range]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        }
        return nil
    }

    private func cleanTimelineTitle(_ title: String) -> String {
        var result = title
            .replacingOccurrences(of: #"^[0-9]{1,3}\s*(?:'|’|min)?\s*[-–—]\s*[0-9]{1,3}\s*(?:'|’|min)?\s*:?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = title }
        return result
    }

    private func looksLikeTimelineTitle(_ title: String) -> Bool {
        timelineMarker(from: title) != nil ||
            normalizedSessionText(title).hasPrefix("block ") ||
            normalizedSessionText(title).hasPrefix("bloque ") ||
            normalizedSessionText(title).hasPrefix("break") ||
            normalizedSessionText(title).hasPrefix("descanso")
    }

    private func normalizedSessionText(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadDetailedPlan() async {
        guard let planId = session.learningSituationSessionPlanId?.int64Value else { return }
        guard let plan = try? await bridge.learningSituationSessionPlan(id: planId) else { return }
        detailedPlan = plan
        sequenceVersion = try? await bridge.learningSituationSessionSequenceVersion(
            id: plan.sequenceVersionId,
            learningSituationId: plan.learningSituationId
        )
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
