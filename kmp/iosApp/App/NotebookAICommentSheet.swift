import SwiftUI
import MiGestorKit

struct NotebookAICommentSheet: View {
    let bridge: KmpBridge
    let data: NotebookUiStateData
    let managedColumns: [NotebookColumnDefinition]
    let visibleColumns: [NotebookColumnDefinition]
    let selectedStudentIds: [Int64]
    let targetColumnId: String?
    let mode: NotebookAIFlowMode
    let onComplete: (String, NotebookToastStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var columnName = "Comentario IA"
    @State private var scope: NotebookAIColumnScope = .visibleColumns
    @State private var audience: AIReportAudience = .docente
    @State private var tone: AIReportTone = .claro
    @State private var onlyEmptyCells = true
    @State private var selectedExistingColumnId = ""
    @State private var isGenerating = false
    @State private var progressMessage: String?
    @State private var feedbackMessage: String?

    private let aiService = AppleFoundationContextualAIService()

    private var existingAIColumns: [NotebookColumnDefinition] {
        data.sheet.columns.filter(bridge.isNotebookAICommentColumn)
    }

    private var availability: AIContextualAvailabilityState {
        aiService.currentAvailability()
    }

    private var effectiveStudentIds: [Int64] {
        let ids = selectedStudentIds.isEmpty ? data.sheet.rows.map { $0.student.id } : selectedStudentIds
        return Array(Set(ids)).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    configCard
                    generationCard
                }
                .padding(24)
            }
            .background(EvaluationBackdrop())
            .navigationTitle(mode == .createColumn ? "Columna IA" : "Comentario IA")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                aiService.prewarm()
                if let targetColumnId {
                    selectedExistingColumnId = targetColumnId
                } else if let first = existingAIColumns.first {
                    selectedExistingColumnId = first.id
                }
            }
        }
    }

    private var configCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(mode == .createColumn ? "Crear columna persistida de comentario IA" : "Generar comentarios para selección")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Text(availability.message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(availability.isAvailable ? NotebookStyle.successTint : NotebookStyle.warningTint)

                if mode == .createColumn {
                    TextField("Nombre de columna", text: $columnName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } else if !existingAIColumns.isEmpty {
                    Picker("Columna destino", selection: $selectedExistingColumnId) {
                        ForEach(existingAIColumns, id: \.id) { column in
                            Text(column.title).tag(column.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker("Datos base", selection: $scope) {
                    ForEach(NotebookAIColumnScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Audiencia", selection: $audience) {
                    ForEach(AIReportAudience.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Tono", selection: $tone) {
                    ForEach(AIReportTone.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Rellenar solo celdas vacías", isOn: $onlyEmptyCells)

                Text("Los comentarios se guardarán como texto editable y no contarán para la media.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generationCard: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surface, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Generación")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Alumnado objetivo: \(effectiveStudentIds.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if let progressMessage {
                    Text(progressMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookStyle.warningTint)
                }

                HStack(spacing: 12) {
                    Button {
                        performGeneration()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(mode == .createColumn ? "Crear y generar" : "Generar comentarios", systemImage: "apple.intelligence")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || effectiveStudentIds.isEmpty || resolvedIncludedColumnIds().isEmpty)

                    if mode == .createColumn {
                        Button("Solo crear columna") {
                            if createColumnIfNeeded(forceNew: true) != nil {
                                onComplete("Columna IA creada. Puedes rellenarla manualmente o generar después.", .success)
                                dismiss()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func resolvedIncludedColumnIds() -> [String] {
        let columns: [NotebookColumnDefinition]
        switch scope {
        case .visibleColumns:
            columns = visibleColumns
        case .evaluableColumns:
            columns = managedColumns.filter { $0.countsTowardAverage || $0.categoryKind == .evaluation || $0.type == .rubric || $0.type == .numeric || $0.type == .calculated }
        case .allManagedColumns:
            columns = managedColumns
        }
        return columns.map(\.id)
    }

    private func createColumnIfNeeded(forceNew: Bool) -> String? {
        if !forceNew {
            if let targetColumnId, !targetColumnId.isEmpty {
                return targetColumnId
            }
            if !selectedExistingColumnId.isEmpty {
                return selectedExistingColumnId
            }
            if let existing = existingAIColumns.first {
                return existing.id
            }
        }
        return bridge.createNotebookAICommentColumn(name: columnName)
    }

    private func performGeneration() {
        let includedColumnIds = resolvedIncludedColumnIds()
        guard !includedColumnIds.isEmpty else {
            feedbackMessage = "Selecciona al menos una columna fuente con datos."
            return
        }

        isGenerating = true
        feedbackMessage = nil
        progressMessage = nil

        Task {
            var targetColumnId = createColumnIfNeeded(forceNew: mode == .createColumn)
            guard let resolvedColumnId = targetColumnId else {
                await MainActor.run {
                    feedbackMessage = "No se pudo crear o resolver la columna IA."
                    isGenerating = false
                }
                return
            }
            targetColumnId = resolvedColumnId

            if !availability.isAvailable {
                await MainActor.run {
                    onComplete("Columna IA creada, pero la generación local no está disponible en este dispositivo.", .warning)
                    isGenerating = false
                    dismiss()
                }
                return
            }

            let contexts = bridge.generateNotebookAICommentContexts(
                includedColumnIds: includedColumnIds,
                studentIds: effectiveStudentIds
            )

            if contexts.isEmpty {
                await MainActor.run {
                    feedbackMessage = "No hay suficiente contexto de cuaderno para generar comentarios."
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
                   let targetColumnId,
                   !bridge.cellText(studentId: context.studentId, columnId: targetColumnId).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    skippedCount += 1
                    continue
                }

                do {
                    let draft = try await aiService.generateNotebookComment(
                        from: context,
                        audience: audience,
                        tone: tone
                    )
                    if let targetColumnId {
                        bridge.saveNotebookAIComment(studentId: context.studentId, columnId: targetColumnId, text: draft.commentText)
                        savedCount += 1
                    }
                } catch {
                    skippedCount += 1
                }
            }

            await MainActor.run {
                onComplete(
                    "Comentarios IA guardados: \(savedCount). Omitidos: \(skippedCount).",
                    savedCount > 0 ? .success : .warning
                )
                isGenerating = false
                dismiss()
            }
        }
    }
}

