import Foundation
import MiGestorKit

// Columna «Comentario de evaluación» de cada pestaña de evaluación del Cuaderno y guardado
// de comentarios en bloque. Es una columna de texto normal: no cuenta para la media,
// se edita como cualquier celda y viaja por SyncLAN con el resto del Cuaderno.
extension KmpBridge {
    static let evaluationCommentColumnTitle = "Comentario de evaluación"

    /// Columna de comentario de la pestaña, si ya existe en el Cuaderno cargado.
    func evaluationCommentColumn(in data: NotebookUiStateData, tabId: String?) -> NotebookColumnDefinition? {
        Self.evaluationCommentColumn(in: data.sheet.columns, tabId: tabId)
    }

    static func evaluationCommentColumn(in columns: [NotebookColumnDefinition], tabId: String?) -> NotebookColumnDefinition? {
        columns.first { column in
            column.type == .text
                && column.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(evaluationCommentColumnTitle) == .orderedSame
                && (tabId == nil || column.sharedAcrossTabs || column.tabIds.contains(tabId!))
        }
    }

    /// Columnas de texto de la pestaña donde se pueden guardar comentarios.
    static func commentCapableColumns(in columns: [NotebookColumnDefinition], tabId: String?) -> [NotebookColumnDefinition] {
        columns.filter { column in
            column.type == .text && !column.isHidden
                && (tabId == nil || column.sharedAcrossTabs || column.tabIds.contains(tabId!))
        }
    }

    /// Devuelve la columna de comentario de la pestaña; la crea si no existe.
    func ensureEvaluationCommentColumn(classId: Int64, tabId: String?) async throws -> NotebookColumnDefinition {
        let existingColumns = try await container.notebookConfigRepository.listColumns(classId: classId)
        if let existing = Self.evaluationCommentColumn(in: existingColumns, tabId: tabId) {
            return existing
        }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMillis)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: nowInstant,
            updatedAt: nowInstant,
            associatedGroupId: KotlinLong(value: classId),
            deviceId: localDeviceId,
            syncVersion: 0
        )
        let column = NotebookColumnDefinition(
            id: "COL_EVAL_COMMENT_\(nowMillis)",
            title: Self.evaluationCommentColumnTitle,
            type: .text,
            categoryKind: .followUp,
            instrumentKind: .privateComment,
            inputKind: .text,
            evaluationId: nil,
            rubricId: nil,
            formula: nil,
            weight: 0,
            dateEpochMs: KotlinLong(value: nowMillis),
            unitOrSituation: nil,
            competencyCriteriaIds: [],
            scaleKind: .custom,
            tabIds: tabId.map { [$0] } ?? [],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: "text.bubble",
            order: -1,
            widthDp: 320,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: false,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: trace
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
        return column
    }

    /// Guarda varios comentarios de golpe y recarga el Cuaderno una sola vez.
    /// Devuelve el texto que había antes en cada celda, para poder deshacer.
    @discardableResult
    func saveEvaluationComments(
        classId: Int64,
        columnId: String,
        comments: [(studentId: Int64, text: String)]
    ) async throws -> [(studentId: Int64, text: String)] {
        let cells = try await container.notebookCellsRepository.listClassCells(classId: classId)
        let previousByStudent = Dictionary(
            cells.filter { $0.columnId == columnId }.map { ($0.studentId, $0.textValue ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        var previous: [(studentId: Int64, text: String)] = []
        for comment in comments {
            previous.append((comment.studentId, previousByStudent[comment.studentId] ?? ""))
            try await saveNotebookAICommentDirect(
                classId: classId,
                studentId: comment.studentId,
                columnId: columnId,
                text: comment.text
            )
        }
        invalidateNotebookCellValueIndexCache()
        refreshCurrentNotebook()
        scheduleNotebookSnapshotSync(forClassId: classId)
        return previous
    }
}
