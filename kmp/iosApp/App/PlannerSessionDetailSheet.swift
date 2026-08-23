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

private enum PlannerSessionDetailSection: String, CaseIterable, Identifiable {
    case activity
    case annexes

    var id: Self { self }

    var label: String {
        switch self {
        case .activity: return "Actividad"
        case .annexes: return "Anexos"
        }
    }

    var icon: String {
        switch self {
        case .activity: return "timeline.selection"
        case .annexes: return "paperclip"
        }
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

private struct PlannerSessionRunSheetRow: View {
    let index: Int
    let activity: LearningSituationSessionActivityDraft
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    private var hasEvidence: Bool {
        !activity.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if !activity.timeLabel.isEmpty {
                            Text(activity.timeLabel)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(isSelected ? tint : .secondary)
                        }
                        if !activity.phase.isEmpty {
                            Text(activity.phase.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(activity.activity)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if hasEvidence {
                    Image(systemName: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityLabel("Tiene evidencia definida")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isSelected ? 9 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(isSelected ? tint.opacity(0.10) : EvaluationDesign.surface)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? tint : Color.clear)
                    .frame(width: 3)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(height: 1)
                    .padding(.leading, 36)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("Actividad \(index + 1): \(activity.activity)")
        .accessibilityValue(isSelected ? "Seleccionada" : "No seleccionada")
        .accessibilityHint("Abre el detalle de esta actividad")
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
    @State private var selectedSection: PlannerSessionDetailSection = .activity
    @State private var selectedActivityKey: String?

    private var tint: Color {
        Color(hex: session.teachingUnitColor)
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
            selectedSection = .activity
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

    @ViewBuilder
    private var detailContent: some View {
        switch presentation {
        case .sheet:
            GeometryReader { proxy in
                let layout = PlannerSessionDetailLayoutPolicy.layout(for: proxy.size.width)
                switch layout {
                case .regular:
                    regularSheetContent
                case .compact:
                    compactSheetContent
                }
            }
        case .inspector:
            inspectorContent
        }
    }

    /// The macOS inspector remains a compact map. The full operating diary belongs to the
    /// sheet, so selecting a session never turns the narrow rail into a second document view.
    private var inspectorContent: some View {
        VStack(spacing: 0) {
            sessionHeader(layout: .compact)
            ScrollView {
                runSheetContent
                    .padding(16)
            }
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

    /// Regular iPad/macOS sheet: the left side is an operational run sheet and the right side
    /// is the selected activity or its annexes.
    private var regularSheetContent: some View {
        VStack(spacing: 0) {
            sessionHeader(layout: .regular)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    runSheetContent
                        .padding(16)
                }
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 380, alignment: .topLeading)
                .background(EvaluationDesign.surface)

                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    regularDetailControls
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if selectedSection == .annexes {
                                annexesContent
                            } else {
                                regularActivityDetailContent
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 500, idealWidth: 680, maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

    /// Compact iPhone/iPad fallback: the run sheet stays above the detail tabs so the
    /// selected activity remains anchored to an operational sequence.
    private var compactSheetContent: some View {
        VStack(spacing: 0) {
            sessionHeader(layout: .compact)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    runSheetContent
                    detailSectionPicker
                    if selectedSection == .annexes {
                        annexesContent
                            .padding(.horizontal, 16)
                    } else {
                        compactActivityNavigation
                            .padding(.horizontal, 16)
                        activityDetailContent
                            .padding(.horizontal, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }

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
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(height: 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sessionHeaderMetadata
                sessionHeaderActions(expandsPrimaryAction: true)
            }
            .padding(16)
            .background(EvaluationDesign.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(height: 1)
            }
        }
    }

    private var sessionHeaderMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detailedPlan?.title ?? session.teachingUnitName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            WorkspaceFlowLayout(spacing: 12) {
                Label(dateAndTimeLabel, systemImage: "calendar")
                Label(session.groupName, systemImage: "person.3.fill")
                PlannerStatusBadge(label: "Planificada", systemImage: "checkmark.circle.fill", tint: tint)
                if let detailedPlan {
                    headerMetadataItem("Sesión \(detailedPlan.sessionNumber)")
                    headerMetadataItem(sessionTypeLabel(for: detailedPlan))
                    headerMetadataItem("\(detailedPlan.effectiveMinutes) min efectivos")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sesión \(detailedPlan?.title ?? session.teachingUnitName)")
        .accessibilityValue(sessionAccessibilityMetadata)
    }

    private func headerMetadataItem(_ value: String) -> some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func sessionTypeLabel(for plan: LearningSituationSessionPlan) -> String {
        PlannerSessionDetailSessionType.label(for: plan.sessionType)
    }

    private var sessionAccessibilityMetadata: String {
        var values = [session.groupName, "Planificada", dateAndTimeLabel]
        if let detailedPlan {
            values.append("Sesión \(detailedPlan.sessionNumber)")
            values.append("\(detailedPlan.sessionType), \(detailedPlan.effectiveMinutes) minutos")
        }
        return values.joined(separator: ", ")
    }

    private func sessionHeaderActions(expandsPrimaryAction: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onOpenDiary) {
                Label("Abrir ejecución", systemImage: "play.rectangle.fill")
                    .font(.headline.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: expandsPrimaryAction ? .infinity : nil)
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
                    .frame(width: 32, height: 32)
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
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Más acciones de la sesión")
    }

    @ViewBuilder
    private var runSheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Guion de la sesión", systemImage: "list.number")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                if let detailedPlan {
                    Text("\(decodedActivities(detailedPlan).count) actividades")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            Text("Selecciona una actividad para abrir su ficha operativa.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            if let detailedPlan {
                let activities = decodedActivities(detailedPlan)
                if activities.isEmpty {
                    runSheetEmptyState(
                        "Esta sesión no tiene actividades seleccionables. El detalle contextual sigue disponible en Anexos."
                    )
                } else {
                    let keys = activities.enumerated().map { activityIdentity($0.element, index: $0.offset) }
                    let activeKey = selectedActivityKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys[0]
                    ForEach(Array(activities.enumerated()), id: \.element.activityKey) { index, activity in
                        let key = activityIdentity(activity, index: index)
                        PlannerSessionRunSheetRow(
                            index: index,
                            activity: activity,
                            isSelected: key == activeKey,
                            tint: tint
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedActivityKey = key
                                selectedSection = .activity
                            }
                        }
                    }
                    .onAppear {
                        if selectedActivityKey == nil || !keys.contains(selectedActivityKey!) {
                            selectedActivityKey = keys.first
                        }
                    }
                }
            } else {
                let activities = session.activities.trimmingCharacters(in: .whitespacesAndNewlines)
                runSheetEmptyState(
                    activities.isEmpty
                        ? "Esta sesión no tiene una ficha operativa importada."
                        : activities
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runSheetEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    private func closeSessionDetail() {
        switch presentation {
        case .sheet:
            dismiss()
        case .inspector:
            onClose?()
        }
    }

    private var detailSectionPicker: some View {
        sessionTabs
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var regularDetailControls: some View {
        VStack(spacing: 0) {
            sessionTabs
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, selectedSection == .annexes ? 8 : 4)

            if selectedSection != .annexes {
                regularActivityNavigation
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(EvaluationDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
    }

    private var sessionTabs: some View {
        HStack(spacing: 20) {
            ForEach(PlannerSessionDetailSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedSection = section
                    }
                } label: {
                    Label(section.label, systemImage: section.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSection == section ? .primary : .secondary)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selectedSection == section ? tint : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .accessibilityLabel(section.label)
                .accessibilityValue(selectedSection == section ? "Seleccionado" : "No seleccionado")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var regularActivityNavigation: some View {
        if let detailedPlan {
            let activities = decodedActivities(detailedPlan)
            let keys = activities.enumerated().map { activityIdentity($0.element, index: $0.offset) }
            if !keys.isEmpty {
                let selectedKey = selectedActivityKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys[0]
                let selectedIndex = keys.firstIndex(of: selectedKey) ?? 0
                HStack(spacing: 8) {
                    activityNavigationButton(
                        title: "Anterior",
                        systemImage: "chevron.left",
                        isDisabled: selectedIndex == 0
                    ) {
                        moveActivityPrevious(in: keys)
                    }

                    Text("Actividad \(selectedIndex + 1) de \(keys.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Actividad seleccionada")
                        .accessibilityValue("\(selectedIndex + 1) de \(keys.count)")

                    activityNavigationButton(
                        title: "Siguiente",
                        systemImage: "chevron.right",
                        isDisabled: selectedIndex == keys.count - 1
                    ) {
                        moveActivityNext(in: keys)
                    }
                }
                .onAppear {
                    if selectedActivityKey == nil || !keys.contains(selectedActivityKey!) {
                        selectedActivityKey = keys.first
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var compactActivityNavigation: some View {
        if let detailedPlan {
            let activities = decodedActivities(detailedPlan)
            let keys = activities.enumerated().map { activityIdentity($0.element, index: $0.offset) }
            if !keys.isEmpty {
                let selectedKey = selectedActivityKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys[0]
                let selectedIndex = keys.firstIndex(of: selectedKey) ?? 0
                HStack(spacing: 8) {
                    activityNavigationButton(
                        title: "Anterior",
                        systemImage: "chevron.left",
                        isDisabled: selectedIndex == 0
                    ) {
                        moveActivityPrevious(in: keys)
                    }
                    Text("Actividad \(selectedIndex + 1) de \(keys.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    activityNavigationButton(
                        title: "Siguiente",
                        systemImage: "chevron.right",
                        isDisabled: selectedIndex == keys.count - 1
                    ) {
                        moveActivityNext(in: keys)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func activityNavigationButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isDisabled ? .tertiary : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .keyboardShortcut(systemImage == "chevron.left" ? .leftArrow : .rightArrow, modifiers: .command)
        .accessibilityLabel(title == "Anterior" ? "Actividad anterior" : "Actividad siguiente")
    }

    @ViewBuilder
    private var activityDetailContent: some View {
        if let detailedPlan {
            let activities = decodedActivities(detailedPlan)
            if activities.isEmpty {
                teacherCard(
                    title: "Detalle de actividades",
                    icon: "list.number",
                    text: "Esta ficha no tiene actividades seleccionables. Revisa los Anexos para consultar el contenido contextual o el documento original."
                )
            } else {
                let keys = activities.enumerated().map { activityIdentity($0.element, index: $0.offset) }
                let selectedKey = selectedActivityKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first!
                let selectedIndex = keys.firstIndex(of: selectedKey) ?? 0
                activityDetailCard(activities[selectedIndex], index: selectedIndex)
                    .onAppear {
                        if selectedActivityKey == nil || !keys.contains(selectedActivityKey!) {
                            selectedActivityKey = keys.first
                        }
                    }
            }
        } else {
            if session.learningSituationSessionPlanId == nil {
                fallbackSessionSections
            } else {
                teacherCard(
                    title: "Detalle de actividades",
                    icon: "list.number",
                    text: "Cargando la ficha operativa de la sesión…"
                )
            }
        }
    }

    @ViewBuilder
    private var regularActivityDetailContent: some View {
        activityDetailContent
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

    private func activityDetailCard(_ activity: LearningSituationSessionActivityDraft, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(activity.activityKey.isEmpty ? "Actividad \(index + 1)" : activity.activityKey)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                if !activity.activityType.isEmpty {
                    Text(activity.activityType.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let plannedMinutes = activity.plannedMinutes {
                    Text("· \(plannedMinutes) min")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(activity.activity)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.top, 8)

            if !activity.timeLabel.isEmpty || !activity.phase.isEmpty {
                Text([activity.timeLabel, activity.phase].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                activityDetailSection("Propósito", activity.purpose)
                activityDetailSection("Organización y preparación", [activity.organisation, activity.setup].filter { !$0.isEmpty }.joined(separator: "\n"))
                activityDetailSection("Profesorado", activity.teacherActions)
                activityDetailSection("Alumnado", [activity.studentInstructions, activity.studentActions].filter { !$0.isEmpty }.joined(separator: "\n"))
                activityDetailSection("Temporización y transiciones", activity.timingBreakdown)
                activityDetailSection("CLIL", activity.clilFocus)
                activityDetailSection("Evidencia", activity.evidence)
                activityDetailSection("Material", activity.materials)
                activityDetailSection("Adaptaciones", activity.adaptations)
                activityDetailSection("Si el grupo va lento", activity.slowGroupPlan)
                activityDetailSection("Extensión si termina antes", activity.fastGroupExtension)
                activityDetailSection("Continuidad LONG", [activity.prepares, activity.consolidates].filter { !$0.isEmpty }.joined(separator: "\n"))
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detalle de actividad \(activity.activityKey.isEmpty ? "\(index + 1)" : activity.activityKey)")
    }

    private func activityIdentity(_ activity: LearningSituationSessionActivityDraft, index: Int) -> String {
        activity.activityKey.isEmpty ? "Actividad \(index + 1)" : activity.activityKey
    }

    private func moveActivityPrevious(in keys: [String]) {
        var navigator = PlannerSessionActivityNavigator(activityKeys: keys, selectedKey: selectedActivityKey)
        navigator.movePrevious()
        selectedActivityKey = navigator.selectedKey
        selectedSection = .activity
    }

    private func moveActivityNext(in keys: [String]) {
        var navigator = PlannerSessionActivityNavigator(activityKeys: keys, selectedKey: selectedActivityKey)
        navigator.moveNext()
        selectedActivityKey = navigator.selectedKey
        selectedSection = .activity
    }

    @ViewBuilder
    private func activityDetailSection(_ label: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(trimmed)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EvaluationDesign.border)
                    .frame(height: 1)
            }
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

    private func decodedActivities(_ plan: LearningSituationSessionPlan) -> [LearningSituationSessionActivityDraft] {
        let payload = LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)
        return payload.map(PlannerSessionPlanPayloadNormalizer.activities(from:)) ?? []
    }

    private func decodedGuidingQuestions(_ plan: LearningSituationSessionPlan) -> [String] {
        LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)?.guidingQuestions ?? []
    }

    private func decodedClosure(_ plan: LearningSituationSessionPlan) -> String {
        LearningSituationSessionDevelopmentPayload.decode(from: plan.developmentJson)?.closure ?? ""
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
        _ = await bridge.ensureLearningSituationSessionSequenceDocument(version: loadedSequenceVersion)
        // Re-evaluate the computed URL after a metadata-first sync has downloaded the
        // binary into the hash-addressed document store.
        sequenceVersion = loadedSequenceVersion

        guard let sourceURL = resolvedSourceDocumentURL(for: loadedSequenceVersion) else { return }

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
