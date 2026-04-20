import SwiftUI
import MiGestorKit

enum NotebookStyle {
    static let outerPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let stackSpacing: CGFloat = 12
    static let controlSpacing: CGFloat = 8
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 14
    static let chipRadius: CGFloat = 16
    static let compactChipRadius: CGFloat = 12
    static let actionHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = 44
    static let microSpacing: CGFloat = 4
    static let border = Color.black.opacity(0.06)
    static let softBorder = Color.black.opacity(0.04)
    static let shadow = Color.black.opacity(0.08)
    static let primaryTint = EvaluationDesign.accent
    static let successTint = EvaluationDesign.success
    static let warningTint = Color(red: 0.86, green: 0.52, blue: 0.12)
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
    @State private var selectedExistingColumnId = ""
    @State private var configuration = NotebookIndividualSummaryConfiguration()
    @State private var isGenerating = false
    @State private var progressMessage: String?
    @State private var feedbackMessage: String?

    private let aiService = AppleFoundationContextualAIService()

    private var notebookData: NotebookUiStateData? {
        bridge.notebookState as? NotebookUiStateData
    }

    private var summaryColumns: [NotebookColumnDefinition] {
        guard let data = notebookData else { return [] }
        return data.sheet.columns.filter { isNotebookIndividualSummaryColumn($0) }
    }

    private var availability: AIContextualAvailabilityState {
        aiService.currentAvailability()
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
                aiService.prewarm()
                if let initialTargetColumnId,
                   summaryColumns.contains(where: { $0.id == initialTargetColumnId }) {
                    selectedExistingColumnId = initialTargetColumnId
                    configuration = NotebookIndividualSummaryPreferences.load(columnId: initialTargetColumnId)
                } else if let first = summaryColumns.first {
                    selectedExistingColumnId = first.id
                    configuration = NotebookIndividualSummaryPreferences.load(columnId: first.id)
                }
            }
            .onChange(of: selectedExistingColumnId) { newValue in
                configuration = NotebookIndividualSummaryPreferences.load(columnId: newValue.isEmpty ? nil : newValue)
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
                        Text(availability.message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(availability.isAvailable ? NotebookStyle.successTint : NotebookStyle.warningTint)
                    }
                }

                Text("La síntesis reutiliza la infraestructura IA del cuaderno, se guarda como texto editable y no impacta en la media.")
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
                            Text(column.title).tag(column.id)
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
                .disabled(isGenerating || resolvedStudentIds.isEmpty || resolvedIncludedColumnIds().isEmpty)
            }
        }
    }

    private var targetSummaryText: String {
        "\(resolvedStudentIds.count) alumnos preparados para síntesis individual."
    }

    private var resolvedStudentIds: [Int64] {
        guard let data = notebookData else { return [] }
        return data.sheet.rows.map { $0.student.id }
    }

    private func resolvedIncludedColumnIds() -> [String] {
        guard let data = notebookData else { return [] }
        let allColumns = data.sheet.columns.filter { !bridge.isNotebookAICommentColumn($0) }

        switch configuration.evidenceSource {
        case .visibleColumns:
            return allColumns.filter { !$0.isHidden }.map(\.id)
        case .evaluableColumns:
            return allColumns.filter {
                $0.countsTowardAverage ||
                $0.categoryKind == .evaluation ||
                $0.type == .rubric ||
                $0.type == .numeric ||
                $0.type == .calculated
            }.map(\.id)
        case .allManagedColumns:
            return allColumns.map(\.id)
        }
    }

    private func resolveTargetColumnId() -> String? {
        let mode = configuration.generationMode

        if mode == .createNewVersion || selectedExistingColumnId.isEmpty {
            let baseTitle = summaryColumns.first(where: { $0.id == selectedExistingColumnId })?.title
                ?? summaryColumns.first?.title
                ?? "Síntesis pedagógica"
            let resolvedTitle = mode == .createNewVersion ? "\(baseTitle) \(formattedRunStamp())" : baseTitle
            guard let newColumnId = bridge.createNotebookAICommentColumn(name: resolvedTitle),
                  let data = notebookData,
                  let createdColumn = data.sheet.columns.first(where: { $0.id == newColumnId }) else {
                return nil
            }

            let referenceColumn = summaryColumns.first(where: { $0.id == selectedExistingColumnId }) ?? summaryColumns.first
            let updatedColumn = NotebookColumnDefinition(
                id: createdColumn.id,
                title: createdColumn.title,
                type: createdColumn.type,
                categoryKind: referenceColumn?.categoryKind ?? .followUp,
                instrumentKind: createdColumn.instrumentKind,
                inputKind: createdColumn.inputKind,
                evaluationId: createdColumn.evaluationId,
                rubricId: createdColumn.rubricId,
                formula: createdColumn.formula,
                weight: 0,
                dateEpochMs: createdColumn.dateEpochMs,
                unitOrSituation: NotebookIndividualSummaryPreferences.marker,
                competencyCriteriaIds: createdColumn.competencyCriteriaIds,
                scaleKind: createdColumn.scaleKind,
                tabIds: createdColumn.tabIds,
                sessions: createdColumn.sessions,
                sharedAcrossTabs: createdColumn.sharedAcrossTabs,
                colorHex: createdColumn.colorHex,
                iconName: createdColumn.iconName,
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
                trace: createdColumn.trace
            )
            bridge.saveColumn(column: updatedColumn)
            NotebookIndividualSummaryPreferences.save(configuration, columnId: newColumnId)
            return newColumnId
        }

        return selectedExistingColumnId.isEmpty ? summaryColumns.first?.id : selectedExistingColumnId
    }

    private func performGeneration() {
        let includedColumnIds = resolvedIncludedColumnIds()
        guard !includedColumnIds.isEmpty else {
            feedbackMessage = "Selecciona al menos una fuente de evidencias con datos."
            return
        }

        guard let targetColumnId = resolveTargetColumnId() else {
            feedbackMessage = "No se pudo crear o resolver la columna de síntesis."
            return
        }

        let onlyEmptyCells = configuration.generationMode == .onlyEmptyCells
        isGenerating = true
        feedbackMessage = nil
        progressMessage = nil

        Task {
            if !availability.isAvailable {
                await MainActor.run {
                    feedbackMessage = availability.message
                    isGenerating = false
                }
                return
            }

            let contexts = bridge.generateNotebookAICommentContexts(
                includedColumnIds: includedColumnIds,
                studentIds: resolvedStudentIds
            )

            if contexts.isEmpty {
                await MainActor.run {
                    feedbackMessage = "No hay suficiente contexto de cuaderno para generar síntesis."
                    isGenerating = false
                }
                return
            }

            var savedCount = 0
            var skippedCount = 0

            for (index, context) in contexts.enumerated() {
                await MainActor.run {
                    progressMessage = "Generando \(index + 1) de \(contexts.count): \(context.studentName)"
                }

                if onlyEmptyCells,
                   !bridge.cellText(studentId: context.studentId, columnId: targetColumnId)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    skippedCount += 1
                    continue
                }

                do {
                    let draft = try await aiService.generateNotebookComment(
                        from: context,
                        audience: .docente,
                        tone: .claro
                    )
                    let text = notebookIndividualSummaryText(from: draft, length: configuration.length)
                    bridge.saveNotebookAIComment(studentId: context.studentId, columnId: targetColumnId, text: text)
                    savedCount += 1
                } catch {
                    skippedCount += 1
                }
            }

            await MainActor.run {
                onComplete(
                    "Síntesis guardadas: \(savedCount). Omitidas: \(skippedCount).",
                    savedCount > 0 ? .success : .warning
                )
                isGenerating = false
                dismiss()
            }
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
    let isInspectorPresented: Bool
    let onSelectClass: (Int64) -> Void
    let onOpenOrganizationMenu: () -> Void
    let onToggleInspector: () -> Void
    let onOpenAdvancedMenu: () -> Void
    let onOpenAddColumn: () -> Void
    var onGenerateSummaryFallback: (() -> Void)? = nil
    var exportText: String? = nil

    private var selectedClass: SchoolClass? {
        bridge.classes.first(where: { $0.id == bridge.notebookViewModel.currentClassId?.int64Value ?? 0 })
    }

    private var saveBadge: (text: String, icon: String, color: Color) {
        switch bridge.notebookSaveState {
        case .saved:
            return ("Guardado", "checkmark.circle.fill", .secondary)
        case .saving:
            return ("Guardando…", "arrow.triangle.2.circlepath", .secondary)
        default:
            return ("Sin guardar", "circle.dotted", NotebookStyle.warningTint)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            classPicker

            TextField("Buscar alumno…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 260)

            Spacer(minLength: 0)

            Picker("Vista", selection: $surfaceMode) {
                Label("Rejilla", systemImage: "rectangle.grid.2x2").tag(NotebookSurfaceMode.grid)
                Label("Plano", systemImage: "list.bullet").tag(NotebookSurfaceMode.seatingPlan)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 138)

            Spacer(minLength: 0)

            saveStatusChip

            Button(action: onOpenOrganizationMenu) {
                Image(systemName: "rectangle.3.group")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Columnas visibles")

            Button(action: onToggleInspector) {
                Image(systemName: isInspectorPresented ? "sidebar.right" : "sidebar.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isInspectorPresented ? NotebookStyle.primaryTint : .secondary)
            .help("Inspector")

            Menu {
                Button("Organizar columnas…", action: onOpenOrganizationMenu)
                Button("Opciones avanzadas…", action: onOpenAdvancedMenu)

                if let onGenerateSummaryFallback {
                    Divider()
                    Button("Generar síntesis…", action: onGenerateSummaryFallback)
                }

                if let exportText {
                    Divider()
                    ShareLink(item: exportText) {
                        Label("Exportar…", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.secondary)
            .help("Más opciones")

            Button(action: onOpenAddColumn) {
                Label("Nueva columna", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 160, alignment: .leading)
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
            Image(systemName: saveBadge.icon)
                .symbolEffect(.rotate, isActive: bridge.notebookSaveState == .saving)
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
}
