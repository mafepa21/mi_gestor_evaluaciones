import SwiftUI
import MiGestorKit

enum NotebookStyle {
    static let outerPadding: CGFloat = IOSAppStyle.pagePadding
    static let sectionSpacing: CGFloat = IOSAppStyle.sectionSpacing
    static let stackSpacing: CGFloat = IOSAppStyle.cardSpacing
    static let controlSpacing: CGFloat = 8
    static let cardRadius: CGFloat = IOSAppStyle.cardRadius
    static let innerRadius: CGFloat = IOSAppStyle.innerRadius
    static let chipRadius: CGFloat = IOSAppStyle.controlRadius
    static let compactChipRadius: CGFloat = 12
    static let actionHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = 44
    static let microSpacing: CGFloat = 4
    static let border = IOSAppStyle.cardBorder
    static let softBorder = Color.primary.opacity(0.04)
    static let shadow = Color.black.opacity(0.04)
    static let primaryTint = IOSAppStyle.info
    static let successTint = IOSAppStyle.success
    static let warningTint = IOSAppStyle.warning
    static let surface = IOSAppStyle.cardBackground
    static let surfaceMuted = appTertiarySystemBackgroundColor().opacity(0.88)
    static let surfaceSoft = appSecondarySystemBackgroundColor().opacity(0.78)
    static let track = appTertiarySystemFillColor().opacity(0.55)
}

struct NotebookSurface<Content: View>: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    var cornerRadius: CGFloat = NotebookStyle.cardRadius
    var fill: Color = NotebookStyle.surface
    var padding: CGFloat = NotebookStyle.stackSpacing
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                adaptiveSurfaceBackground(
                    accessibilityFallback: uiFeatureFlags.accessibilitySurfaceFallback,
                    fill: fill,
                    cornerRadius: cornerRadius
                )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(NotebookStyle.border, lineWidth: 1)
                    )
                    .shadow(color: NotebookStyle.shadow.opacity(0.65), radius: 18, x: 0, y: 10)
            )
    }
}

struct NotebookSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct NotebookIconButton: View {
    let systemImage: String
    let tint: Color
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: NotebookStyle.iconButtonSize, height: NotebookStyle.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                        .fill(tint.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                        .stroke(tint.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

struct NotebookPill: View {
    let label: String
    var systemImage: String? = nil
    var active: Bool = false
    var tint: Color = NotebookStyle.primaryTint
    var compact: Bool = false

    var body: some View {
        HStack(spacing: NotebookStyle.controlSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(label)
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(active ? contrastingTextColor(for: tint) : tint)
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
        .background(
            Capsule(style: .continuous)
                .fill(active ? tint : tint.opacity(0.10))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(active ? tint : tint.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct NotebookSummaryGenerationSheet: View {
    @ObservedObject var bridge: KmpBridge
    var initialTargetColumnId: String? = nil
    let onComplete: (String, NotebookToastStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedExistingColumnId: String?
    @State private var configuration = NotebookIndividualSummaryConfiguration()
    @State private var isGenerating = false
    @State private var progressMessage: String?
    @State private var feedbackMessage: String?
    @State private var idsWithEvidence: [Int64] = []

    private let reportService = AppleFoundationReportService()

    private var notebookData: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var summaryColumns: [NotebookColumnDefinition] {
        guard let data = notebookData else { return [] }
        return data.sheet.columns.filter { isNotebookIndividualSummaryColumn($0) }
    }

    private var hasExistingSummary: Bool {
        !summaryColumns.isEmpty
    }

    private var ctaTitle: String {
        hasExistingSummary ? "Regenerar síntesis" : "Generar síntesis"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introCard
                    configurationCard
                    generationCard
                }
                .padding(24)
            }
            .background(EvaluationBackdrop())
            .navigationTitle("Síntesis pedagógica")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                if let initialTargetColumnId,
                   summaryColumns.contains(where: { $0.id == initialTargetColumnId }) {
                    selectedExistingColumnId = initialTargetColumnId
                    configuration = NotebookIndividualSummaryPreferences.load(columnId: initialTargetColumnId)
                } else if let first = summaryColumns.first {
                    selectedExistingColumnId = first.id
                    configuration = NotebookIndividualSummaryPreferences.load(columnId: first.id)
                } else {
                    selectedExistingColumnId = nil
                }
                recalculateEvidence()
            }
            .appOnChange(of: selectedExistingColumnId) { newValue in
                configuration = NotebookIndividualSummaryPreferences.load(columnId: newValue)
                recalculateEvidence()
            }
            .appOnChange(of: configuration.evidenceSource) { _ in
                recalculateEvidence()
            }
        }
    }

    private var introCard: some View {
        PremiumCard.section(title: "Síntesis Inteligente", systemImage: "apple.intelligence") {
            VStack(alignment: .leading, spacing: 12) {
                Text(hasExistingSummary ? "Refina o actualiza la síntesis pedagógica del cuaderno." : "Genera una columna de síntesis pedagógica lista para cada alumno.")
                    .font(IOSAppStyle.cardTitle)
                Text("Genera una síntesis pedagógica local a partir de las evidencias del cuaderno. Apple Intelligence se podrá usar más adelante como mejora opcional.")
                    .font(IOSAppStyle.bodyText)
                    .foregroundStyle(.secondary)

                Text("La síntesis se guarda como texto editable, no impacta en la media y no depende de servicios externos ni de modelos locales de Apple.")
                    .font(IOSAppStyle.captionText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var configurationCard: some View {
        PremiumCard.section(title: "Configuración", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 16) {
                if hasExistingSummary {
                    Picker("Columna destino", selection: $selectedExistingColumnId) {
                        ForEach(summaryColumns, id: \.id) { column in
                            Text(column.title).tag(Optional(column.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 8) {
                    IOSStatusPill(label: configuration.evidenceSource.title, isActive: true)
                    IOSStatusPill(label: configuration.length.title, isActive: true)
                    IOSStatusPill(label: configuration.generationMode.title, isActive: true, tint: IOSAppStyle.warning)
                }

                Text("La configuración se toma de la columna creada desde “Síntesis pedagógica”. Si no existe ninguna, se usará la configuración por defecto.")
                    .font(IOSAppStyle.bodyText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generationCard: some View {
        PremiumCard.section(title: "Generación", systemImage: "play.fill") {
            VStack(alignment: .leading, spacing: 16) {
                Text(targetSummaryText)
                    .font(IOSAppStyle.bodyText)
                    .foregroundStyle(.secondary)

                if let progressMessage {
                    Text(progressMessage)
                        .font(IOSAppStyle.bodyText)
                        .foregroundStyle(IOSAppStyle.info)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(IOSAppStyle.bodyText)
                        .foregroundStyle(IOSAppStyle.warning)
                }

                if isGenerating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    PrimaryActionButton(
                        label: ctaTitle,
                        systemImage: "apple.intelligence",
                        tint: IOSAppStyle.info,
                        isEnabled: !resolvedStudentIds.isEmpty,
                        fullWidth: false
                    ) {
                        performGeneration()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var targetSummaryText: String {
        let evidenceCount = idsWithEvidence.count
        let totalCount = resolvedStudentIds.count
        if totalCount == 0 {
            return "No hay alumnos disponibles para generar síntesis."
        }
        if evidenceCount == totalCount {
            return "\(evidenceCount) alumnos con datos preparados para síntesis individual."
        }
        return "\(evidenceCount) alumnos con señales claras; se preparará una síntesis prudente para \(totalCount - evidenceCount) sin evidencias suficientes."
    }

    private var resolvedStudentIds: [Int64] {
        guard let data = notebookData else { return [] }
        return data.sheet.rows.map { $0.student.id }
    }

    private func recalculateEvidence() {
        Task {
            let cols = resolvedIncludedColumnIds()
            let contexts = await bridge.generateNotebookAICommentContexts(
                includedColumnIds: cols,
                studentIds: resolvedStudentIds
            )
            let filtered = contexts.filter { hasUsableSummarySignal($0) }.map(\.studentId)
            await MainActor.run {
                self.idsWithEvidence = filtered
            }
        }
    }

    private func hasUsableSummarySignal(_ context: KmpBridge.NotebookAICommentContext) -> Bool {
        if context.hasEnoughData { return true }
        if context.averageScore != nil { return true }
        if !context.relevantValues.isEmpty { return true }
        if context.followUpCount > 0 { return true }
        if context.incidentCount > 0 { return true }
        if context.evidenceCount > 0 { return true }
        if context.attendanceStatus != nil { return true }
        return false
    }

    private func resolvedIncludedColumnIds() -> [String] {
        guard let data = notebookData else { return [] }
        let allColumns = data.sheet.columns.filter { column in
            !bridge.isNotebookAICommentColumn(column)
        }

        switch configuration.evidenceSource {
        case .visibleColumns:
            return allColumns.filter(\.isVisibleInGrid).map(\.id)
        case .evaluableColumns:
            return allColumns.filter { column in
                guard column.type != .text,
                      column.inputKind != .evidence,
                      column.instrumentKind != .privateComment,
                      !bridge.isNotebookAICommentColumn(column) else {
                    return false
                }
                return column.countsTowardAverage ||
                    column.categoryKind == .evaluation ||
                    column.type == .rubric ||
                    column.type == .numeric ||
                    column.type == .calculated
            }.map(\.id)
        case .allManagedColumns:
            return allColumns.map(\.id)
        }
    }

    private func resolveTargetColumnId() -> String? {
        let mode = configuration.generationMode

        if mode == .createNewVersion || selectedExistingColumnId == nil {
            let baseTitle = summaryColumns.first(where: { $0.id == selectedExistingColumnId })?.title
                ?? summaryColumns.first?.title
                ?? "Síntesis pedagógica"
            let resolvedTitle = mode == .createNewVersion ? "\(baseTitle) \(formattedRunStamp())" : baseTitle
            guard let newColumnId = bridge.createNotebookAICommentColumn(name: resolvedTitle) else {
                return nil
            }

            // The SwiftUI/KMP snapshot can lag right after creation; generation can use the returned id immediately.
            NotebookIndividualSummaryPreferences.save(configuration, columnId: newColumnId)
            Task { @MainActor in
                await Task.yield()
                guard let data = notebookData,
                      let createdColumn = data.sheet.columns.first(where: { $0.id == newColumnId }) else {
                    return
                }

                let currentSummaryColumns = data.sheet.columns.filter { isNotebookIndividualSummaryColumn($0) }
                let referenceColumn = currentSummaryColumns.first(where: { $0.id == selectedExistingColumnId }) ?? currentSummaryColumns.first
                let updatedColumn = NotebookColumnDefinition(
                    id: createdColumn.id,
                    title: createdColumn.title,
                    type: .text,
                    categoryKind: referenceColumn?.categoryKind ?? .followUp,
                    instrumentKind: .privateComment,
                    inputKind: .text,
                    evaluationId: createdColumn.evaluationId,
                    rubricId: createdColumn.rubricId,
                    formula: createdColumn.formula,
                    weight: 0,
                    dateEpochMs: createdColumn.dateEpochMs,
                    unitOrSituation: NotebookIndividualSummaryPreferences.marker,
                    competencyCriteriaIds: createdColumn.competencyCriteriaIds,
                    scaleKind: .custom,
                    tabIds: createdColumn.tabIds,
                    sessions: createdColumn.sessions,
                    sharedAcrossTabs: createdColumn.sharedAcrossTabs,
                    colorHex: createdColumn.colorHex,
                    iconName: "apple.intelligence",
                    order: createdColumn.order,
                    widthDp: createdColumn.widthDp,
                    categoryId: referenceColumn?.categoryId,
                    ordinalLevels: createdColumn.ordinalLevels,
                    availableIcons: createdColumn.availableIcons,
                    countsTowardAverage: false,
                    isPinned: referenceColumn?.isPinned ?? false,
                    isHidden: false,
                    visibility: .visible,
                    isLocked: referenceColumn?.isLocked ?? false,
                    isTemplate: referenceColumn?.isTemplate ?? false,
                    emptyCellPolicy: referenceColumn?.emptyCellPolicy ?? createdColumn.emptyCellPolicy,
                    trace: createdColumn.trace
                )
                bridge.saveColumn(column: updatedColumn)
            }
            return newColumnId
        }

        return selectedExistingColumnId ?? summaryColumns.first?.id
    }

    private func performGeneration() {
        let studentIds = resolvedStudentIds
        guard !studentIds.isEmpty else {
            feedbackMessage = "No hay alumnado disponible para generar síntesis."
            return
        }

        guard let targetColumnId = resolveTargetColumnId() else {
            feedbackMessage = "No se pudo resolver la columna de síntesis."
            return
        }

        guard let classId = bridge.currentNotebookClassId else {
            feedbackMessage = "No se pudo resolver la clase actual para guardar la síntesis."
            return
        }

        let onlyEmptyCells = configuration.generationMode == .onlyEmptyCells
        isGenerating = true
        feedbackMessage = nil
        progressMessage = "Generando síntesis pedagógicas..."

        Task { @MainActor in
            var savedCount = 0
            var skippedCount = 0
            var fallbackCount = 0

            for (index, studentId) in studentIds.enumerated() {
                let studentName = notebookData?.sheet.rows.first(where: { $0.student.id == studentId })?.student.fullName ?? "alumno"
                progressMessage = "Generando \(index + 1) de \(studentIds.count): \(studentName)"

                let currentText = (try? await bridge.notebookTextCell(classId: classId, studentId: studentId, columnId: targetColumnId))
                    ?? bridge.cellText(studentId: studentId, columnId: targetColumnId)
                if onlyEmptyCells,
                   !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    skippedCount += 1
                    continue
                }

                let result = await generateSummaryFromReportSystem(
                    studentId: studentId,
                    targetColumnId: targetColumnId,
                    termLabel: nil
                )

                switch result {
                case .saved(let usedFallback):
                    savedCount += 1
                    if usedFallback { fallbackCount += 1 }
                case .skipped:
                    skippedCount += 1
                }
            }

            isGenerating = false
            progressMessage = nil

            if savedCount > 0 {
                let fallbackNote = fallbackCount > 0
                    ? " \(fallbackCount) generada\(fallbackCount == 1 ? "" : "s") por reglas locales (IA no disponible); revísalas."
                    : ""
                onComplete("Síntesis pedagógicas guardadas: \(savedCount). Omitidas: \(skippedCount).\(fallbackNote)", .success)
                dismiss()
            } else {
                feedbackMessage = "No se ha podido generar ninguna síntesis. Revisa que el cuaderno tenga datos suficientes."
            }
        }
    }

    private enum SummaryGenerationResult {
        case saved(usedFallback: Bool)
        case skipped
    }

    @MainActor
    private func generateSummaryFromReportSystem(
        studentId: Int64,
        targetColumnId: String,
        termLabel: String?
    ) async -> SummaryGenerationResult {
        guard let data = notebookData else { return .skipped }

        do {
            let context = try await bridge.buildReportGenerationContext(
                classId: data.sheet.classId,
                studentId: studentId,
                kind: .studentSummary,
                termLabel: termLabel
            )

            let draft = try await reportService.generateDraft(
                from: context,
                audience: .docente,
                tone: .claro
            )

            let text = compactNotebookSummary(from: draft, context: context, length: configuration.length)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { return .skipped }

            try await bridge.saveNotebookAICommentDirect(
                classId: data.sheet.classId,
                studentId: studentId,
                columnId: targetColumnId,
                text: text
            )

            return .saved(usedFallback: draft.appearsToBeRulesFallback)
        } catch {
            return .skipped
        }
    }

    private func compactNotebookSummary(
        from draft: AIReportDraft,
        context: KmpBridge.ReportGenerationContext,
        length: NotebookIndividualSummaryLength
    ) -> String {
        let teacher = draft.teacherNotesVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextSummary = context.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = teacher.isEmpty ? (summary.isEmpty ? contextSummary : summary) : teacher

        switch length {
        case .brief:
            let pieces = baseText
                .split(whereSeparator: { $0.isNewline })
                .flatMap { $0.split(separator: ".") }
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let selected = Array(pieces.prefix(2)).map { "\($0)." }
            return selected.isEmpty ? baseText : selected.joined(separator: " ")
        case .balanced:
            return baseText
        case .expanded:
            let strengths = draft.strengths.prefix(2).joined(separator: " ")
            let action = draft.recommendedActions.first ?? ""
            let strengthsText = strengths.isEmpty ? "" : "\nFortalezas observables: \(strengths)"
            let actionText = action.isEmpty ? "" : "\nPróximo paso sugerido: \(action)"
            return baseText + strengthsText + actionText
        }
    }

    private func formattedRunStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: .now)
    }
}


