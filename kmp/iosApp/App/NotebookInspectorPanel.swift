import SwiftUI
import PhotosUI
import MiGestorKit

struct NotebookInspectorPanel: View {
    @ObservedObject var bridge: KmpBridge
    let data: NotebookUiStateData
    let rows: [NotebookTableRow]
    let currentClassId: Int64?
    let semanticIcons: [String]
    let auditEvents: [NotebookCellAuditEvent]
    @Binding var inspectorSelection: NotebookInspectorSelection?
    @Binding var isInspectorPresented: Bool
    @Binding var inspectorNoteDraft: String
    @Binding var inspectorIconDraft: String
    @Binding var inspectorAttachmentUris: [String]
    @Binding var selectedAttachmentPhoto: PhotosPickerItem?
    let displayValue: (NotebookTableRow, NotebookColumnDefinition) -> String
    let categoryTitle: (NotebookColumnDefinition, NotebookUiStateData) -> String
    let evidenceLabel: (PersistedNotebookCell?) -> String
    let formattedDate: (Int64?) -> String
    let evaluationTitle: (NotebookColumnDefinition) -> String
    let rubricTitle: (NotebookColumnDefinition) -> String
    let isSummaryColumn: (NotebookColumnDefinition) -> Bool
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onSelectStudent: (Int64) -> Void
    let onRegenerateSummary: (String) -> Void
    let onRegenerateAI: (NotebookAISheetRequest) -> Void
    let onSaveContext: () -> Void

    var body: some View {
        Group {
            if let selection = inspectorSelection,
               selection.isAverage,
               let item = rows.first(where: { $0.student.id == selection.studentId }) {
                inspector(for: item, column: nil, selection: selection)
            } else if let selection = inspectorSelection,
                      let item = rows.first(where: { $0.student.id == selection.studentId }),
                      let column = data.sheet.columns.first(where: { $0.id == selection.columnId }) {
                inspector(for: item, column: column, selection: selection)
            } else {
                NotebookStateCard(
                    systemImage: "sidebar.right",
                    title: "Inspector contextual",
                    message: "Selecciona una celda para ver alumno, columna, comentario, evidencia y peso."
                )
            }
        }
    }

    private func inspector(
        for item: NotebookTableRow,
        column: NotebookColumnDefinition?,
        selection: NotebookInspectorSelection
    ) -> some View {
        let persistedCell = column.map { selectedColumn in
            item.row.persistedCells.first(where: { $0.columnId == selectedColumn.id })
        } ?? nil
        let isAIColumn = column.map { bridge.isNotebookAICommentColumn($0) } ?? false
        let isSummaryColumn = column.map { isSummaryColumn($0) } ?? false

        return NotebookStudentInspector(
            bridge: bridge,
            classId: currentClassId,
            studentId: item.student.id,
            studentName: "\(item.student.firstName) \(item.student.lastName)",
            columnTitle: column?.title ?? "Media",
            valueText: column.map { displayValue(item, $0) } ?? averageValueText(for: item),
            categoryText: column.map { categoryTitle($0, data) } ?? "Resumen evaluativo",
            weightText: column.map { String(format: "%.1f", $0.weight) } ?? averageWeightText(for: item),
            typeText: column.map { "\($0.instrumentKind.name) · \($0.inputKind.name)" } ?? "Media ponderada",
            dateText: column.map { formattedDate($0.dateEpochMs?.int64Value) } ?? "Sin fecha",
            criteriaText: criteriaText(for: column),
            evidenceText: evidenceLabel(persistedCell),
            evaluationText: column.map { evaluationTitle($0) } ?? "Media del alumno",
            rubricText: column.map { rubricTitle($0) } ?? rubricSummaryText(for: item),
            semanticIcons: semanticIcons,
            aiSectionTitle: isAIColumn ? (isSummaryColumn ? "Síntesis pedagógica" : "Comentario IA") : nil,
            aiSectionOrigin: isAIColumn ? (isSummaryColumn ? "Columna de síntesis pedagógica editable" : "Columna de comentario IA editable") : nil,
            aiRegenerateTitle: isAIColumn ? (isSummaryColumn ? "Regenerar síntesis pedagógica" : "Regenerar comentario IA") : nil,
            averageExplanation: item.row.averageExplanation,
            pendingColumns: item.row.averageExplanation?.pendingCells ?? [],
            recentObservations: recentObservations(for: item),
            rubricSummaries: rubricSummaries(for: item),
            canOpenEvaluation: column?.evaluationId != nil,
            canOpenRubric: column?.rubricId != nil,
            showsAttendanceShortcut: column?.categoryKind == .attendance,
            noteDraft: $inspectorNoteDraft,
            iconDraft: $inspectorIconDraft,
            attachmentUris: $inspectorAttachmentUris,
            selectedAttachmentPhoto: $selectedAttachmentPhoto,
            onOpenStudent: {
                onSelectStudent(item.student.id)
                isInspectorPresented = false
                inspectorSelection = nil
                onOpenModule(.students, currentClassId, item.student.id)
            },
            onOpenEvaluation: {
                isInspectorPresented = false
                inspectorSelection = nil
                onOpenModule(.evaluationHub, currentClassId, item.student.id)
            },
            onOpenRubric: {
                if let column {
                    onOpenModule(
                        column.categoryKind == .physicalEducation ? .peRubrics : .rubrics,
                        currentClassId,
                        item.student.id
                    )
                }
            },
            onOpenAttendance: {
                onSelectStudent(item.student.id)
                isInspectorPresented = false
                inspectorSelection = nil
                onOpenModule(.attendance, currentClassId, item.student.id)
            },
            onRegenerateAI: {
                if let column {
                    if isSummaryColumn {
                        onRegenerateSummary(column.id)
                    } else {
                        onRegenerateAI(NotebookAISheetRequest(
                            mode: .selection,
                            studentIds: [item.student.id],
                            targetColumnId: column.id
                        ))
                    }
                }
            },
            onSaveContext: {
                if let column {
                    bridge.saveNotebookCellAnnotation(
                        studentId: item.student.id,
                        columnId: column.id,
                        note: inspectorNoteDraft,
                        iconValue: inspectorIconDraft,
                        attachmentUris: inspectorAttachmentUris
                    )
                    onSaveContext()
                }
            },
            onClose: {
                isInspectorPresented = false
                inspectorSelection = nil
            },
            auditEvents: auditEvents
        )
    }

    private func averageValueText(for item: NotebookTableRow) -> String {
        guard let average = item.row.weightedAverage else { return "Sin media" }
        return IosFormatting.decimal(from: average)
    }

    private func averageWeightText(for item: NotebookTableRow) -> String {
        guard let explanation = item.row.averageExplanation else { return "0.0" }
        return IosFormatting.decimal(from: explanation.totalIncludedWeight)
    }

    private func rubricSummaryText(for item: NotebookTableRow) -> String {
        let count = rubricSummaries(for: item).count
        return count == 1 ? "1 rúbrica asociada" : "\(count) rúbricas asociadas"
    }

    private func criteriaText(for column: NotebookColumnDefinition?) -> String {
        guard let column, !column.competencyCriteriaIds.isEmpty else { return "Sin criterio" }
        return column.competencyCriteriaIds.map(String.init).joined(separator: ", ")
    }

    private func recentObservations(for item: NotebookTableRow) -> [NotebookInspectorObservation] {
        item.row.persistedCells
            .compactMap { cell -> NotebookInspectorObservation? in
                guard let annotation = cell.annotation else { return nil }
                let note = annotation.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let attachmentCount = annotation.attachmentUris.count
                let icon = annotation.icon ?? cell.iconValue ?? ""
                guard !note.isEmpty || attachmentCount > 0 || !icon.isEmpty else { return nil }
                let title = data.sheet.columns.first(where: { $0.id == cell.columnId })?.title ?? cell.columnId
                return NotebookInspectorObservation(
                    id: cell.columnId,
                    columnTitle: title,
                    note: note.isEmpty ? "Observación sin texto" : note,
                    icon: icon,
                    attachmentCount: attachmentCount
                )
            }
            .prefix(3)
            .map { $0 }
    }

    private func rubricSummaries(for item: NotebookTableRow) -> [NotebookInspectorRubricSummary] {
        data.sheet.columns
            .filter { $0.rubricId != nil }
            .prefix(4)
            .map { column in
                let value = displayValue(item, column)
                return NotebookInspectorRubricSummary(
                    id: column.id,
                    title: column.title,
                    value: value.isEmpty ? "Pendiente" : value,
                    isPending: value.isEmpty || value == "Sin valor"
                )
            }
    }
}
