import Foundation
import MiGestorKit

enum NotebookPhysicalMarkSaveOutcome: Equatable {
    case scored(Double)
    case noScale
    case cleared
    case invalid
}

extension KmpBridge {
    /// Guarda la marca de una prueba física desde el Cuaderno y, con el baremo del
    /// alumno, rellena la nota en su columna. Sin baremo, la nota se vacía para
    /// no dejar una nota vieja que ya no corresponde a la marca.
    @discardableResult
    func savePhysicalNotebookMark(
        student: Student,
        classId: Int64,
        pair: NotebookPhysicalColumnPair,
        text: String
    ) async -> NotebookPhysicalMarkSaveOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            saveColumnGrade(studentId: student.id, column: pair.raw, value: "")
            saveColumnGrade(studentId: student.id, column: pair.score, value: "")
            return .cleared
        }
        guard let stored = NotebookPhysicalMark.storedText(from: trimmed, kind: pair.kind),
              let rawValue = NotebookPhysicalMark.value(from: stored, kind: pair.kind) else {
            return .invalid
        }
        saveColumnGrade(studentId: student.id, column: pair.raw, value: stored)
        let score = await resolvePhysicalNotebookScore(
            classId: classId,
            student: student,
            columnId: pair.raw.id,
            rawValue: rawValue
        )
        guard let score else {
            saveColumnGrade(studentId: student.id, column: pair.score, value: "")
            return .noScale
        }
        saveColumnGrade(studentId: student.id, column: pair.score, value: NotebookPhysicalMark.decimalText(score))
        return .scored(score)
    }

    /// Aplica el plan de `NotebookPhysicalColumns.repairPlan`. Escribe directamente en
    /// el repositorio: pasar por `saveColumn` del ViewModel crearía evaluaciones nuevas.
    func applyPhysicalColumnRepairs(classId: Int64, columns: [NotebookColumnDefinition]) async throws {
        guard !columns.isEmpty else { return }
        for column in columns {
            try await container.notebookRepository.saveColumn(classId: classId, column: column)
        }
        scheduleNotebookSnapshotSync(forClassId: classId)
    }
}
