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

/// Small, platform-independent state machine for the activity controls in the session card.
/// The UI uses Activity ID keys rather than titles or array indexes so reordering the document
/// cannot open the wrong activity.
struct PlannerSessionActivityNavigator: Equatable {
    let activityKeys: [String]
    private(set) var selectedKey: String?

    init(activityKeys: [String], selectedKey: String? = nil) {
        self.activityKeys = activityKeys
        self.selectedKey = activityKeys.contains(selectedKey ?? "") ? selectedKey : activityKeys.first
    }

    var selectedIndex: Int? {
        guard let selectedKey else { return nil }
        return activityKeys.firstIndex(of: selectedKey)
    }

    var canMovePrevious: Bool { (selectedIndex ?? 0) > 0 }
    var canMoveNext: Bool { (selectedIndex ?? -1) >= 0 && (selectedIndex ?? -1) < activityKeys.count - 1 }

    mutating func select(_ key: String) {
        guard activityKeys.contains(key) else { return }
        selectedKey = key
    }

    mutating func movePrevious() {
        guard let index = selectedIndex, index > 0 else { return }
        selectedKey = activityKeys[index - 1]
    }

    mutating func moveNext() {
        guard let index = selectedIndex, index + 1 < activityKeys.count else { return }
        selectedKey = activityKeys[index + 1]
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

    @State private var linkedInstruments: [PlannerAssessmentInstrument] = []
    @State private var isLoadingInstruments = false
    @State private var detailedPlan: LearningSituationSessionPlan?
    @State private var sequenceVersion: LearningSituationSessionSequenceVersion?
    @State private var sourceDocumentURL: URL?
    @State private var renderedDocument: PlannerDocxRenderResult?
    @State private var isLoadingRenderedDocument = false
    @State private var isDeleteConfirmationPresented = false
    @State private var selectedSection: PlannerSessionDetailSection = .summary
    @State private var selectedActivityKey: String?

    private enum PlannerSessionDetailSection: String, CaseIterable, Identifiable {
        case summary
        case activity
        case annexes

        var id: Self { self }
        var label: String {
            switch self {
            case .summary: return "Resumen"
            case .activity: return "Actividad"
            case .annexes: return "Anexos"
            }
        }
        var icon: String {
            switch self {
            case .summary: return "rectangle.inset.filled"
            case .activity: return "timeline.selection"
            case .annexes: return "paperclip"
            }
        }
    }

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
        .task(id: session.id) {
            selectedSection = .summary
            selectedActivityKey = nil
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

    @ViewBuilder
    private var detailContent: some View {
        switch presentation {
        case .sheet:
            ViewThatFits(in: .horizontal) {
                regularSheetContent
                compactSheetContent
            }
        case .inspector:
            inspectorContent
        }
    }

    /// The macOS inspector remains a compact map. The full operating diary belongs to the
    /// sheet, so selecting a session never turns the narrow rail into a second document view.
    private var inspectorContent: some View {
        VStack(spacing: 0) {
            sessionBriefHeader
            quickActionBar
            ScrollView {
                if let detailedPlan {
                    teacherAtAGlanceSection(detailedPlan)
                } else {
                    fallbackSessionSections
                }
            }
            .padding(16)
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

    /// Regular iPad/macOS sheet: the left side is the session map and the right side is
    /// deliberately only the selected activity. The map buttons update `selectedActivityKey`.
    private var regularSheetContent: some View {
        VStack(spacing: 0) {
            sessionBriefHeader
            quickActionBar
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let detailedPlan {
                            teacherAtAGlanceSection(detailedPlan)
                        } else {
                            fallbackSessionSections
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedSection = .annexes }
                        } label: {
                            Label("Anexos", systemImage: "paperclip")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(24)
                }
                .frame(idealWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)

                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(width: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedSection == .annexes {
                            annexesContent
                        } else {
                            regularActivityDetailContent
                        }
                    }
                    .padding(24)
                }
                .frame(idealWidth: 440, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            }
        }
        .frame(idealWidth: 820, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: false)
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

    /// Compact iPhone/iPad split fallback: all three modes remain reachable through the
    /// segmented control and the selected activity is shown progressively.
    private var compactSheetContent: some View {
        VStack(spacing: 0) {
            sessionBriefHeader
            quickActionBar
            detailSectionPicker
            ScrollView {
                VStack(spacing: 16) {
                    if selectedSection == .summary {
                        if let detailedPlan {
                            teacherAtAGlanceSection(detailedPlan)
                        } else {
                            fallbackSessionSections
                        }
                    } else if selectedSection == .activity {
                        activityDetailContent
                    } else {
                        annexesContent
                    }
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
                HStack(spacing: 8) {
                    if case .sheet = presentation {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                        .help("Cerrar la ficha de sesión")
                        .accessibilityLabel("Cerrar la ficha de sesión")
                    }
                }
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

    private var detailSectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(PlannerSessionDetailSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedSection = section
                    }
                } label: {
                    Label(section.label, systemImage: section.icon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selectedSection == section ? .white : .secondary)
                        .background(
                            selectedSection == section ? tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .accessibilityLabel(section.label)
            }
        }
        .padding(4)
        .frame(maxWidth: 440)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(EvaluationDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var activityDetailContent: some View {
        if let detailedPlan {
            let activities = decodedActivities(detailedPlan)
            if activities.isEmpty {
                teacherCard(
                    title: "Detalle de actividades",
                    icon: "list.number",
                    text: "Esta ficha todavía no tiene actividades con Activity ID. Reimporta el documento con el formato QUICK VIEW + ACTIVITY DETAILS para activar la vista operativa."
                )
            } else {
                activityNavigatorContent(activities, minutes: Int(detailedPlan.effectiveMinutes))
            }
        } else {
            teacherCard(
                title: "Detalle de actividades",
                icon: "list.number",
                text: "Cargando la ficha operativa de la sesión…"
            )
        }
    }

    @ViewBuilder
    private var regularActivityDetailContent: some View {
        if let detailedPlan {
            let activities = decodedActivities(detailedPlan)
            if activities.isEmpty {
                teacherCard(
                    title: "Actividad",
                    icon: "list.number",
                    text: "Esta sesión no tiene una actividad seleccionable."
                )
            } else {
                let keys = activities.enumerated().map { activityIdentity($0.element, index: $0.offset) }
                let selectedKey = selectedActivityKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first!
                let selectedIndex = keys.firstIndex(of: selectedKey) ?? 0
                VStack(alignment: .leading, spacing: 16) {
                    Label("Actividad seleccionada", systemImage: "timeline.selection")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                    activityDetailCard(activities[selectedIndex], index: selectedIndex)
                }
                .onAppear {
                    if selectedActivityKey == nil || !keys.contains(selectedActivityKey!) {
                        selectedActivityKey = keys.first
                    }
                }
            }
        } else {
            teacherCard(title: "Actividad", icon: "list.number", text: "Cargando la ficha operativa de la sesión…")
        }
    }

    private var quickActionBar: some View {
        HStack(spacing: 16) {
            Button(action: onOpenDiary) {
                Label("Abrir ejecución", systemImage: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .keyboardShortcut(.defaultAction)

            Spacer(minLength: 0)

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
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Más acciones de la sesión")
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

    private var annexesContent: some View {
        VStack(spacing: 16) {
            if let detailedPlan {
                if !decodedGuidingQuestions(detailedPlan).isEmpty {
                    teacherCard(
                        title: "Preguntas guía",
                        icon: "questionmark.bubble",
                        text: decodedGuidingQuestions(detailedPlan).joined(separator: "\n")
                    )
                }
                if !decodedClosure(detailedPlan).isEmpty {
                    teacherCard(title: "Cierre", icon: "flag.checkered", text: decodedClosure(detailedPlan))
                }
                sourceDocumentSection(detailedPlan)
                renderedDocumentSection
            }
            instrumentsSection
        }
    }

    private func teacherAtAGlanceSection(_ plan: LearningSituationSessionPlan) -> some View {
        let projection = PlannerSessionDetailProjection(plan: plan)
        return VStack(spacing: 16) {
            let objective = projection.objective.isEmpty
                ? plan.objective.trimmingCharacters(in: .whitespacesAndNewlines)
                : projection.objective
            if !objective.isEmpty {
                teacherCard(title: "Objetivo de hoy", icon: "target", text: objective, prominence: .hero)
            }

            developmentTimeline(plan)

            let criteria = projection.criteria.isEmpty ? decodedCriteria(plan) : projection.criteria
            let evidence = (projection.evidence + evidenceItems(from: plan))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, item in
                    if !result.contains(item) { result.append(item) }
                }
            if !criteria.isEmpty || !evidence.isEmpty {
                evaluationCard(criteria: criteria, evidence: evidence)
            }

            let material = projection.materials.isEmpty
                ? plan.material.trimmingCharacters(in: .whitespacesAndNewlines)
                : projection.materials.joined(separator: ", ")
            if !material.isEmpty {
                materialCard(material)
            }
            let organisation = projection.organisation.isEmpty ? "" : projection.organisation
            if !organisation.isEmpty {
                teacherCard(title: "Organización", icon: "person.3", text: organisation)
            }
            let assessment = projection.assessment.isEmpty ? "" : projection.assessment
            if !assessment.isEmpty && evidence.isEmpty {
                teacherCard(title: "Evaluación", icon: "checkmark.seal", text: assessment)
            }
            if !projection.basicKnowledge.isEmpty {
                teacherCard(
                    title: "Saberes básicos",
                    icon: "book.closed",
                    text: projection.basicKnowledge.joined(separator: "\n")
                )
            }

            let adaptations = projection.adaptations.isEmpty ? decodedAdaptations(plan) : projection.adaptations
            if !adaptations.isEmpty {
                teacherCard(title: "Adaptaciones y contexto", icon: "person.crop.rectangle", text: adaptations.joined(separator: "\n"))
            }
            if !projection.supportSections.isEmpty {
                supportContextCard(projection.supportSections)
            }
        }
    }

    private func supportContextCard(_ sections: [PlannerSessionSupportSection]) -> some View {
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
                    Label(section.title, systemImage: "text.alignleft")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .tint(tint)
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
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

    private func evaluationCard(criteria: [String], evidence: [String]) -> some View {
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidencia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(evidence, id: \.self) { item in
                        Label {
                            Text(item)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(tint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
    }

    private func activityNavigatorContent(_ activities: [LearningSituationSessionActivityDraft], minutes: Int) -> some View {
        let keys = activities.enumerated().map { activityIdentity($0.element, index: $0.offset) }
        let selectedKey = selectedActivityKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first!
        let selectedIndex = keys.firstIndex(of: selectedKey) ?? 0
        let selected = activities[selectedIndex]
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("Guion de la sesión", systemImage: "timeline.selection")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    if minutes > 0 {
                        Text("\(minutes) min útiles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                }
                Text("Selecciona una actividad para abrir su ficha operativa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(Array(activities.enumerated()), id: \.element.activityKey) { index, activity in
                        let key = activityIdentity(activity, index: index)
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedActivityKey = key
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 3) {
                                    Circle()
                                        .fill(key == selectedKey ? tint : tint.opacity(0.35))
                                        .frame(width: 10, height: 10)
                                    if index < activities.count - 1 {
                                        Rectangle()
                                            .fill(tint.opacity(0.18))
                                            .frame(width: 2, height: 24)
                                    }
                                }
                                .frame(width: 12)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text("Actividad \(index + 1)")
                                            .font(.caption.weight(.bold))
                                        if !activity.timeLabel.isEmpty {
                                            Text(activity.timeLabel)
                                                .font(.caption.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(key == selectedKey ? .white.opacity(0.9) : tint)
                                        }
                                    }
                                    Text(activity.activity)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(key == selectedKey ? .white.opacity(0.9) : .secondary)
                                    .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .foregroundStyle(key == selectedKey ? .white : .primary)
                            .background(
                                key == selectedKey ? tint : EvaluationDesign.surfaceSoft,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(key == selectedKey ? .isSelected : [])
                        .accessibilityLabel("Actividad \(index + 1): \(activity.activity)")
                        .accessibilityHint("Abre el detalle de esta actividad")
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        selectedActivityKey = keys[max(0, selectedIndex - 1)]
                    } label: {
                        Label("Anterior", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedIndex == 0)

                    Text("Actividad \(selectedIndex + 1) de \(activities.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    Button {
                        selectedActivityKey = keys[min(keys.count - 1, selectedIndex + 1)]
                    } label: {
                        Label("Siguiente", systemImage: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedIndex == activities.count - 1)
                }
            }
            .padding(20)
            .plannerGlassPanel(.content, cornerRadius: 20)

            activityDetailCard(selected, index: selectedIndex)
        }
        .onAppear {
            if selectedActivityKey == nil || !keys.contains(selectedActivityKey!) {
                selectedActivityKey = keys.first
            }
        }
    }

    private func activityDetailCard(_ activity: LearningSituationSessionActivityDraft, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(activity.activityKey.isEmpty ? "A\(index + 1)" : activity.activityKey)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.12), in: Capsule())
                if !activity.activityType.isEmpty {
                    Text(activity.activityType.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let plannedMinutes = activity.plannedMinutes {
                    Text("\(plannedMinutes) min")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            Text(activity.activity)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            if !activity.timeLabel.isEmpty || !activity.phase.isEmpty {
                Label([activity.timeLabel, activity.phase].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            activityDetailRow("Propósito", activity.purpose)
            activityDetailRow("Organización", activity.organisation)
            activityDetailRow("Preparación", activity.setup)
            activityDetailRow("Qué hace el profesor", activity.teacherActions)
            activityDetailRow("Qué se dice al alumnado", activity.studentInstructions)
            activityDetailRow("Qué hace el alumnado", activity.studentActions)
            activityDetailRow("Temporización y transiciones", activity.timingBreakdown)
            activityDetailRow("CLIL", activity.clilFocus)
            activityDetailRow("Evidencia que se recoge", activity.evidence)
            activityDetailRow("Materiales", activity.materials)
            activityDetailRow("Adaptaciones", activity.adaptations)
            activityDetailRow("Si el grupo va lento", activity.slowGroupPlan)
            activityDetailRow("Si el grupo termina antes", activity.fastGroupExtension)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .plannerGlassPanel(.hero, cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detalle de actividad \(activity.activityKey.isEmpty ? "\(index + 1)" : activity.activityKey)")
    }

    private func activityIdentity(_ activity: LearningSituationSessionActivityDraft, index: Int) -> String {
        activity.activityKey.isEmpty ? "LEGACY-\(index + 1)" : activity.activityKey
    }

    private func materialCard(_ material: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Material preparado", systemImage: "shippingbox")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(materialItems(from: material), id: \.self) { item in
                    Label(item, systemImage: "square")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
    }

    private func developmentTimeline(_ plan: LearningSituationSessionPlan) -> some View {
        let activities = decodedActivities(plan)
        let sections = timelineSections(from: decodedDevelopment(plan))
        return Group {
            if !activities.isEmpty {
                activityTimeline(activities, minutes: Int(plan.effectiveMinutes))
            } else if !sections.isEmpty {
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
                .plannerGlassPanel(.content, cornerRadius: 20)
            }
        }
    }

    private func activityTimeline(_ activities: [LearningSituationSessionActivityDraft], minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label("Guion de la clase", systemImage: "figure.run.square.stack")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                if minutes > 0 {
                    Text("\(minutes) min útiles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.10), in: Capsule())
                }
            }

            VStack(spacing: 12) {
                ForEach(Array(activities.enumerated()), id: \.element.activityKey) { index, activity in
                    Button {
                        selectedActivityKey = activityIdentity(activity, index: index)
                        selectedSection = .activity
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(tint)
                                .frame(width: 26, height: 26)
                                .background(tint.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    if !activity.timeLabel.isEmpty {
                                        Text(activity.timeLabel)
                                            .font(.caption.weight(.bold).monospacedDigit())
                                            .foregroundStyle(tint)
                                    }
                                    if !activity.phase.isEmpty {
                                        Text(activity.phase)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(activity.activity)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            if !activity.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(tint)
                                    .help("Tiene evidencia definida")
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Actividad \(index + 1): \(activity.activity)")
                    .accessibilityHint("Abre el detalle operativo de esta actividad")
                }
            }
        }
        .padding(20)
        .plannerGlassPanel(.content, cornerRadius: 20)
    }

    @ViewBuilder
    private func activityDetailRow(_ label: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(trimmed)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
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
        let parsed = PlannerSessionDetailProjection.parseStep(line)
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
                if let teacherRole = parsed.teacherRole {
                    timelineRoleLine("Profesorado", teacherRole)
                }
                if let studentRole = parsed.studentRole {
                    timelineRoleLine("Alumnado", studentRole)
                }
                if let evidence = parsed.evidence {
                    timelineRoleLine("Evidencia", evidence)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineRoleLine(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                if sourceDocumentFileURL != nil {
                    Button {
                        openSourceDocumentPreview()
                    } label: {
                        Label("Ver documento", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
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

    private func decodedCriteria(_ plan: LearningSituationSessionPlan) -> [String] {
        ((try? JSONDecoder().decode([String].self, from: Data(plan.criteriaJson.utf8))) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodedDevelopment(_ plan: LearningSituationSessionPlan) -> [LearningSituationSessionSectionDraft] {
        LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)?.sections ?? []
    }

    private func decodedActivities(_ plan: LearningSituationSessionPlan) -> [LearningSituationSessionActivityDraft] {
        let payload = LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)
        if let activities = payload?.activities, !activities.isEmpty {
            return PlannerSessionLegacyActivityProjection.stableActivities(activities)
        }
        // v1 had only sections/lines. Project executable timeline lines into synthetic rows;
        // evidence, questions, closure and adaptation prose must never become activities.
        return PlannerSessionLegacyActivityProjection.executableActivities(from: payload?.sections ?? [])
    }

    private func decodedAdaptations(_ plan: LearningSituationSessionPlan) -> [String] {
        ((try? JSONDecoder().decode([String].self, from: Data(plan.adaptationsJson.utf8))) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func decodedGuidingQuestions(_ plan: LearningSituationSessionPlan) -> [String] {
        LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)?.guidingQuestions ?? []
    }

    private func decodedClosure(_ plan: LearningSituationSessionPlan) -> String {
        LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)?.closure ?? ""
    }

    private func evidenceItems(from plan: LearningSituationSessionPlan) -> [String] {
        let sectionItems = decodedDevelopment(plan)
            .filter { isEvidenceSection($0) }
            .flatMap { section in
                section.lines.isEmpty ? [metadataValue(from: section.title) ?? section.title] : section.lines
            }
            .map { metadataValue(from: $0) ?? $0 }

        let activityItems = decodedActivities(plan).map(\.evidence)
        return (sectionItems + activityItems)
            .map { value in
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "^[•–—-]\\s*", with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) { result.append(item) }
            }
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
        renderedDocument = nil
        isLoadingRenderedDocument = false
        guard let planId = session.learningSituationSessionPlanId?.int64Value else { return }
        guard let plan = try? await bridge.learningSituationSessionPlan(id: planId) else { return }
        detailedPlan = plan
        selectedActivityKey = nil
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
