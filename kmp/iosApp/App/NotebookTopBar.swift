import SwiftUI
import MiGestorKit

enum NotebookStyle {
    static let outerPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let stackSpacing: CGFloat = 12
    static let controlSpacing: CGFloat = 8
    static let cardRadius: CGFloat = AppleDesignSystem.cardRadius
    static let innerRadius: CGFloat = AppleDesignSystem.controlRadius
    static let chipRadius: CGFloat = AppleDesignSystem.chipRadius
    static let compactChipRadius: CGFloat = 12
    static let actionHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = 44
    static let microSpacing: CGFloat = 4
    static let border = Color.black.opacity(0.06)
    static let softBorder = Color.black.opacity(0.04)
    static let shadow = Color.black.opacity(0.08)
    static let primaryTint = AppleDesignSystem.accent
    static let successTint = AppleDesignSystem.success
    static let warningTint = AppleDesignSystem.warning
    static let surface = appSecondarySystemBackgroundColor().opacity(0.92)
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

struct NotebookStatusBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: NotebookStyle.controlSpacing) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.10))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

struct NotebookPrimaryButton: View {
    let title: String
    let systemImage: String
    var tint: Color = NotebookStyle.primaryTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NotebookStyle.controlSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(contrastingTextColor(for: tint))
            .frame(minHeight: NotebookStyle.actionHeight)
            .padding(.horizontal, 20)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
                    .shadow(color: tint.opacity(0.22), radius: 10, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
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
            }
            .appOnChange(of: selectedExistingColumnId) { newValue in
                configuration = NotebookIndividualSummaryPreferences.load(columnId: newValue)
            }
        }
    }

    private var introCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NotebookStyle.primaryTint.opacity(0.14))
                            .frame(width: 52, height: 52)

                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(NotebookStyle.primaryTint)
                            .accessibilityLabel("Síntesis pedagógica")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(hasExistingSummary ? "Refina o actualiza la síntesis pedagógica del cuaderno." : "Genera una columna de síntesis pedagógica lista para cada alumno.")
                            .font(.title2.weight(.bold))
                        Text("Genera una síntesis pedagógica local a partir de las evidencias del cuaderno. Apple Intelligence se podrá usar más adelante como mejora opcional.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("La síntesis se guarda como texto editable, no impacta en la media y no depende de servicios externos ni de modelos locales de Apple.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var configurationCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surface, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configuración")
                    .font(.title3.weight(.bold))

                if hasExistingSummary {
                    Picker("Columna destino", selection: $selectedExistingColumnId) {
                        ForEach(summaryColumns, id: \.id) { column in
                            Text(column.title).tag(Optional(column.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 10) {
                    NotebookPill(label: configuration.evidenceSource.title, systemImage: "tray.full", active: false, tint: NotebookStyle.primaryTint, compact: true)
                    NotebookPill(label: configuration.length.title, systemImage: "text.alignleft", active: false, tint: NotebookStyle.primaryTint, compact: true)
                    NotebookPill(label: configuration.generationMode.title, systemImage: "arrow.trianglehead.2.clockwise.rotate.90", active: true, tint: NotebookStyle.primaryTint, compact: true)
                }

                Text("La configuración se toma de la columna creada desde “Síntesis pedagógica”. Si no existe ninguna, se usará la configuración por defecto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generationCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generación")
                    .font(.title3.weight(.bold))
                Text(targetSummaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let progressMessage {
                    Text(progressMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NotebookStyle.warningTint)
                }

                Button {
                    performGeneration()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    } else {
                        Label(ctaTitle, systemImage: "apple.intelligence")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || resolvedStudentIds.isEmpty)
            }
        }
    }

    private var targetSummaryText: String {
        let evidenceCount = studentIdsWithEvidence(in: resolvedIncludedColumnIds()).count
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

    private func studentIdsWithEvidence(in includedColumnIds: [String]) -> [Int64] {
        bridge.generateNotebookAICommentContexts(
            includedColumnIds: includedColumnIds,
            studentIds: resolvedStudentIds
        )
        .filter { context in
            hasUsableSummarySignal(context)
        }
        .map(\.studentId)
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

                let saved = await generateSummaryFromReportSystem(
                    studentId: studentId,
                    targetColumnId: targetColumnId,
                    termLabel: nil
                )

                if saved {
                    savedCount += 1
                } else {
                    skippedCount += 1
                }
            }

            isGenerating = false
            progressMessage = nil

            if savedCount > 0 {
                onComplete("Síntesis pedagógicas guardadas: \(savedCount). Omitidas: \(skippedCount).", .success)
                dismiss()
            } else {
                feedbackMessage = "No se ha podido generar ninguna síntesis. Revisa que el cuaderno tenga datos suficientes."
            }
        }
    }

    @MainActor
    private func generateSummaryFromReportSystem(
        studentId: Int64,
        targetColumnId: String,
        termLabel: String?
    ) async -> Bool {
        guard let data = notebookData else { return false }

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

            guard !text.isEmpty else { return false }

            try await bridge.saveNotebookAICommentDirect(
                classId: data.sheet.classId,
                studentId: studentId,
                columnId: targetColumnId,
                text: text
            )

            return true
        } catch {
            return false
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

struct NotebookTopBar: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var searchText: String
    @Binding var surfaceMode: NotebookSurfaceMode
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    let navigationDirection: NotebookNavigationDirection
    let isInspectorPresented: Bool
    let isAttendanceQuickMode: Bool
    let canMarkAllPresent: Bool
    let canUndo: Bool
    let onSelectClass: (Int64) -> Void
    let onOpenOrganizationMenu: () -> Void
    let onToggleInspector: () -> Void
    let onOpenAdvancedMenu: () -> Void
    let onOpenAddColumn: () -> Void
    let onNavigationDirectionChange: (NotebookNavigationDirection) -> Void
    let onToggleAttendanceQuickMode: () -> Void
    let onMarkAllPresent: () -> Void
    let onUndo: () -> Void
    var showsInlineActions: Bool = true
    var showsClassPicker: Bool = true

    private var selectedClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == bridge.notebookViewModel.currentClassId?.int64Value ?? 0 })
    }

    private var saveBadge: (text: String, icon: String, color: Color) {
        if bridge.notebookSaveState == .saved {
            return ("Guardado", "checkmark.circle.fill", .secondary)
        } else if bridge.notebookSaveState == .saving {
            return ("Guardando…", "arrow.triangle.2.circlepath", .secondary)
        } else if bridge.notebookSaveState == .unsaved {
            return ("Sin guardar", "circle.dotted", NotebookStyle.warningTint)
        }

        return ("Estado pendiente", "circle", .secondary)
    }

    var body: some View {
        Group {
        #if os(macOS)
            if showsInlineActions {
                regularTopBar(showAddColumnAction: true)
            } else {
                macContextTopBar
            }
        #else
            if horizontalSizeClass == .compact {
                compactTopBar
            } else {
                regularTopBar(showAddColumnAction: true)
            }
        #endif
        }
    }

    private var macContextTopBar: some View {
        HStack(spacing: 12) {
            if showsClassPicker {
                classPicker
            }

            Spacer(minLength: 0)

            saveStatusChip
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var compactTopBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if showsClassPicker {
                    classPicker
                }
                saveStatusCompactChip
                Spacer(minLength: 0)
                compactMenu
                addColumnButtonCompact
            }

            HStack(spacing: 8) {
                searchField
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func regularTopBar(showAddColumnAction: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if showsClassPicker {
                    classPicker
                }

                searchField

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    saveStatusChip
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    undoButton
                    quickAttendanceButton
                    organizationButton
                    inspectorButton
                    if showAddColumnAction {
                        addColumnButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            quickAttendanceBanner
        }
        .background(.bar)
        .animation(.easeInOut(duration: 0.22), value: isAttendanceQuickMode)
    }

    private var searchField: some View {
        TextField("Buscar alumno…", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180, maxWidth: 260)
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(canUndo ? .primary : .tertiary)
        .disabled(!canUndo)
        .keyboardShortcut("z", modifiers: .command)
        .help("Deshacer último cambio (⌘Z)")
        .accessibilityLabel("Deshacer último cambio")
    }

    private var quickAttendanceButton: some View {
        Button(action: onToggleAttendanceQuickMode) {
            Image(systemName: "bolt")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .background(isAttendanceQuickMode ? NotebookStyle.warningTint.opacity(0.15) : Color.secondary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isAttendanceQuickMode ? NotebookStyle.warningTint : .secondary)
        .help(isAttendanceQuickMode ? "Salir de asistencia rápida" : "Modo asistencia rápida")
        .accessibilityLabel("Modo asistencia rápida")
    }

    private var organizationButton: some View {
        Button(action: onOpenOrganizationMenu) {
            Image(systemName: "rectangle.3.group")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Columnas visibles")
        .accessibilityLabel("Columnas visibles")
    }

    private var inspectorButton: some View {
        Button(action: onToggleInspector) {
            Image(systemName: isInspectorPresented ? "sidebar.right" : "sidebar.squares.right")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .background(isInspectorPresented ? NotebookStyle.primaryTint.opacity(0.15) : Color.secondary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isInspectorPresented ? NotebookStyle.primaryTint : .secondary)
        .keyboardShortcut("i", modifiers: [.command, .option])
        .help("Mostrar/ocultar inspector (⌘⌥I)")
        .accessibilityLabel("Inspector")
    }

    private var addColumnButton: some View {
        Button(action: onOpenAddColumn) {
            Label("Nueva columna", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Añadir nueva columna de evaluación")
    }

    private var addColumnButtonCompact: some View {
        Button(action: onOpenAddColumn) {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nueva columna")
    }

    private var saveStatusCompactChip: some View {
        saveStatusIcon
            .font(.footnote.weight(.semibold))
            .foregroundStyle(saveBadge.color)
            .frame(width: 32, height: 32)
            .background(saveBadge.color.opacity(0.12), in: Circle())
            .help(saveBadge.text)
            .accessibilityLabel(saveBadge.text)
    }

    private var compactMenu: some View {
        Menu {
            Button(action: onUndo) {
                Label("Deshacer último cambio", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)

            Button(action: onToggleAttendanceQuickMode) {
                Label(
                    isAttendanceQuickMode ? "Salir de asistencia rápida" : "Asistencia rápida",
                    systemImage: "bolt.fill"
                )
            }

            Button(action: onOpenOrganizationMenu) {
                Label("Configurar columnas", systemImage: "rectangle.3.group")
            }

            Button(action: onToggleInspector) {
                Label(
                    isInspectorPresented ? "Ocultar inspector" : "Mostrar inspector",
                    systemImage: isInspectorPresented ? "sidebar.right" : "sidebar.squares.right"
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.08), in: Circle())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var quickAttendanceBanner: some View {
        if isAttendanceQuickMode {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(NotebookStyle.warningTint)
                Text("Modo asistencia rápida activo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotebookStyle.warningTint)
                Spacer(minLength: 0)
                if canMarkAllPresent {
                    Button("Marcar todos presentes") {
                        onMarkAllPresent()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotebookStyle.warningTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(NotebookStyle.warningTint.opacity(0.15), in: Capsule())
                    .buttonStyle(.plain)
                }

                Button("Salir") {
                    onToggleAttendanceQuickMode()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(NotebookStyle.warningTint.opacity(0.12))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var classPicker: some View {
        Menu {
            ForEach(bridge.classes, id: \.id) { schoolClass in
                Button {
                    onSelectClass(Int64(schoolClass.id))
                } label: {
                    HStack {
                        Text(schoolClass.name)
                        if schoolClass.id == selectedClass?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedClass?.name ?? "Seleccionar clase")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .fixedSize(horizontal: true, vertical: false)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotebookStyle.surfaceSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(NotebookStyle.softBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var saveStatusChip: some View {
        HStack(spacing: 6) {
            saveStatusIcon
            Text(saveBadge.text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(saveBadge.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(saveBadge.color.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(saveBadge.color.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: bridge.notebookSaveState)
    }

    @ViewBuilder
    private var saveStatusIcon: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            Image(systemName: saveBadge.icon)
                .symbolEffect(.rotate, isActive: bridge.notebookSaveState == .saving)
        } else {
            Image(systemName: saveBadge.icon)
                .rotationEffect(.degrees(bridge.notebookSaveState == .saving ? 360 : 0))
                .animation(
                    bridge.notebookSaveState == .saving
                        ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.2),
                    value: bridge.notebookSaveState
                )
        }
    }
}
