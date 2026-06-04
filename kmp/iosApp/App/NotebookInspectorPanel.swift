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
        column: NotebookColumnDefinition,
        selection: NotebookInspectorSelection
    ) -> some View {
        let persistedCell = item.row.persistedCells.first(where: { $0.columnId == selection.columnId })
        let isAIColumn = bridge.isNotebookAICommentColumn(column)
        let isSummaryColumn = isSummaryColumn(column)

        return NotebookStudentInspector(
            studentName: "\(item.student.firstName) \(item.student.lastName)",
            columnTitle: column.title,
            valueText: displayValue(item, column),
            categoryText: categoryTitle(column, data),
            weightText: String(format: "%.1f", column.weight),
            typeText: "\(column.instrumentKind.name) · \(column.inputKind.name)",
            dateText: formattedDate(column.dateEpochMs?.int64Value),
            criteriaText: column.competencyCriteriaIds.isEmpty ? "Sin criterio" : column.competencyCriteriaIds.map(String.init).joined(separator: ", "),
            evidenceText: evidenceLabel(persistedCell),
            evaluationText: evaluationTitle(column),
            rubricText: rubricTitle(column),
            semanticIcons: semanticIcons,
            aiSectionTitle: isAIColumn ? (isSummaryColumn ? "Síntesis pedagógica" : "Comentario IA") : nil,
            aiSectionOrigin: isAIColumn ? (isSummaryColumn ? "Columna de síntesis pedagógica editable" : "Columna de comentario IA editable") : nil,
            aiRegenerateTitle: isAIColumn ? (isSummaryColumn ? "Regenerar síntesis pedagógica" : "Regenerar comentario IA") : nil,
            canOpenEvaluation: column.evaluationId != nil,
            canOpenRubric: column.rubricId != nil,
            showsAttendanceShortcut: column.categoryKind == .attendance,
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
                onOpenModule(
                    column.categoryKind == .physicalEducation ? .peRubrics : .rubrics,
                    currentClassId,
                    item.student.id
                )
            },
            onOpenAttendance: {
                onSelectStudent(item.student.id)
                isInspectorPresented = false
                inspectorSelection = nil
                onOpenModule(.attendance, currentClassId, item.student.id)
            },
            onRegenerateAI: {
                if isSummaryColumn {
                    onRegenerateSummary(column.id)
                } else {
                    onRegenerateAI(NotebookAISheetRequest(
                        mode: .selection,
                        studentIds: [item.student.id],
                        targetColumnId: column.id
                    ))
                }
            },
            onSaveContext: {
                bridge.saveNotebookCellAnnotation(
                    studentId: item.student.id,
                    columnId: column.id,
                    note: inspectorNoteDraft,
                    iconValue: inspectorIconDraft,
                    attachmentUris: inspectorAttachmentUris
                )
                onSaveContext()
            },
            onClose: {
                isInspectorPresented = false
                inspectorSelection = nil
            },
            auditEvents: auditEvents
        )
    }
}
