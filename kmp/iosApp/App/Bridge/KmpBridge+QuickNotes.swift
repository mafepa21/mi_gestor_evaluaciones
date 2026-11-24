import Foundation
import MiGestorKit

// Valorar más rápido: fichas propias del docente, valorar por ficha a varios alumnos
// y copiar «Tu valoración» del trimestre anterior. Todo escribe en «Tu valoración».
extension KmpBridge {
    /// Clave guardada de cada grupo de fichas.
    static func quickNoteGroupKey(_ group: QuickNoteGroup) -> String {
        switch group {
        case .strength: return "strength"
        case .improve: return "improve"
        case .guidance: return "guidance"
        }
    }

    static func quickNoteGroup(fromKey key: String) -> QuickNoteGroup? {
        QuickNoteGroup.allCases.first { quickNoteGroupKey($0) == key }
    }

    /// Fichas propias vivas (sin las borradas), por grupo.
    func quickNotePhrases() async -> [QuickNoteGroup: [QuickNotePhrase]] {
        let all = (try? await container.quickNotePhraseRepository.listAll()) ?? []
        var result: [QuickNoteGroup: [QuickNotePhrase]] = [:]
        for phrase in all where !phrase.isDeleted {
            guard let group = Self.quickNoteGroup(fromKey: phrase.group) else { continue }
            result[group, default: []].append(phrase)
        }
        return result
    }

    private func phraseTrace() -> AuditTrace {
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
    }

    /// Crea o cambia una ficha propia. El texto se limpia de comas y puntos.
    @discardableResult
    func saveQuickNotePhrase(id: String? = nil, group: QuickNoteGroup, text: String) async throws -> QuickNotePhrase? {
        let clean = QuickNoteCatalog.sanitize(text)
        guard !clean.isEmpty else { return nil }
        let phrase = QuickNotePhrase(
            id: id ?? "qnp_\(UUID().uuidString)",
            group: Self.quickNoteGroupKey(group),
            text: clean,
            order: 0,
            isDeleted: false,
            trace: phraseTrace()
        )
        try await container.quickNotePhraseRepository.save(phrase: phrase)
        return phrase
    }

    /// Borrado lógico: así el borrado llega también al otro dispositivo.
    func deleteQuickNotePhrase(_ phrase: QuickNotePhrase) async throws {
        try await container.quickNotePhraseRepository.save(phrase: QuickNotePhrase(
            id: phrase.id,
            group: phrase.group,
            text: phrase.text,
            order: phrase.order,
            isDeleted: true,
            trace: phraseTrace()
        ))
    }

    /// Añade una ficha a «Tu valoración» de cada alumno marcado y la quita de los demás
    /// que la tenían, sin tocar el resto de su valoración. Devuelve cuántos cambiaron.
    func applyQuickNoteChip(
        classId: Int64,
        termLabel: String,
        group: QuickNoteGroup,
        text: String,
        selectedStudentIds: Set<Int64>,
        allStudentIds: [Int64]
    ) async throws -> Int {
        let notes = try await teacherTermNotes(classId: classId, termLabel: termLabel)
        var changed = 0
        for studentId in allStudentIds {
            let current = notes[studentId] ?? ""
            var parts = QuickNoteComposer.decompose(current)
            var items = parts.selected[group] ?? []
            let has = items.contains(text)
            let wants = selectedStudentIds.contains(studentId)
            guard has != wants else { continue }
            if wants { items.append(text) } else { items.removeAll { $0 == text } }
            parts.selected[group] = items
            let updated = QuickNoteComposer.compose(selected: parts.selected, freeText: parts.freeText)
            _ = try await saveTeacherTermNote(studentId: studentId, classId: classId, termLabel: termLabel, text: updated)
            changed += 1
        }
        return changed
    }

    /// Copia «Tu valoración» de un trimestre a otro. Por defecto no pisa a quien ya tiene.
    /// Devuelve lo que había antes en los alumnos tocados, para poder deshacer.
    func copyTeacherTermNotes(
        classId: Int64,
        fromTerm: String,
        toTerm: String,
        studentIds: [Int64],
        replaceExisting: Bool
    ) async throws -> [(studentId: Int64, previous: String)] {
        let source = try await teacherTermNotes(classId: classId, termLabel: fromTerm)
        let target = try await teacherTermNotes(classId: classId, termLabel: toTerm)
        var previous: [(studentId: Int64, previous: String)] = []
        for studentId in studentIds {
            guard let text = source[studentId]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let existing = target[studentId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !existing.isEmpty && !replaceExisting { continue }
            if existing == text { continue }
            previous.append((studentId, target[studentId] ?? ""))
            _ = try await saveTeacherTermNote(studentId: studentId, classId: classId, termLabel: toTerm, text: text)
        }
        return previous
    }

    func restoreTeacherTermNotes(classId: Int64, termLabel: String, previous: [(studentId: Int64, previous: String)]) async throws {
        for item in previous {
            _ = try await saveTeacherTermNote(studentId: item.studentId, classId: classId, termLabel: termLabel, text: item.previous)
        }
    }
}
