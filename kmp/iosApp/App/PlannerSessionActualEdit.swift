import Foundation
import MiGestorKit

/// «Lo que hice»: el guion del plan ajustado a lo que se hizo de verdad en clase.
/// El plan nunca cambia: el resultado se guarda en el diario de la sesión
/// («Qué se ha hecho realmente» y «Adaptaciones»).
struct PlannerActualEditInput: Equatable {
    struct Block: Equatable, Identifiable {
        let id: String
        let title: String
        let minutes: Int?
        let detail: String
    }

    let title: String
    let meta: String
    let blocks: [Block]

    init(title: String, meta: String, blocks: [PlannerSessionReviewBlock]) {
        self.title = title
        self.meta = meta
        self.blocks = blocks.flatMap(\.steps)
            .filter { !$0.isCollection }
            .map { Block(id: $0.activityKey, title: $0.title, minutes: $0.minutes, detail: $0.detail) }
    }

    init(projection: PlannerSessionDetailProjection, title: String, meta: String) {
        self.init(title: title, meta: meta, blocks: projection.guideBlocks)
    }
}

struct PlannerActualEdit: Equatable {
    enum Status: Equatable {
        /// La IA todavía no ha revisado el bloque.
        case pending
        case unchanged
        case changed
        case skipped
        case added
        /// La IA falló: el bloque se queda como en el plan.
        case failed
    }

    struct Block: Equatable, Identifiable {
        let id: String
        var title: String
        let plannedMinutes: Int?
        let plannedDetail: String
        var minutes: Int?
        var detail: String
        var status: Status
        /// Qué cambió, en pocas palabras. Va a «Adaptaciones».
        var changeNote: String = ""

        var isChange: Bool { status == .changed || status == .skipped || status == .added }
    }

    struct Added: Equatable {
        let title: String
        let minutes: Int?
        let detail: String
        /// Título del bloque del plan tras el que va. Vacío o desconocido = al final.
        let afterTitle: String
    }

    var blocks: [Block]

    init(input: PlannerActualEditInput, status: Status = .pending) {
        blocks = input.blocks.map {
            Block(
                id: $0.id,
                title: $0.title,
                plannedMinutes: $0.minutes,
                plannedDetail: $0.detail,
                minutes: $0.minutes,
                detail: $0.detail,
                status: status
            )
        }
    }

    var hasChanges: Bool { blocks.contains(where: \.isChange) }
    var changeCount: Int { blocks.filter(\.isChange).count }

    mutating func apply(_ result: PlannerActualEditNormalizer.BlockResult, to id: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].status = result.status
        blocks[index].detail = result.detail
        blocks[index].minutes = result.minutes
        blocks[index].changeNote = result.changeNote
    }

    mutating func markFailed(_ id: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        revert(id)
        blocks[index].status = .failed
    }

    /// «Dejar como estaba»: vuelve al texto y los minutos del plan.
    mutating func revert(_ id: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        if blocks[index].status == .added {
            blocks.remove(at: index)
            return
        }
        blocks[index].detail = blocks[index].plannedDetail
        blocks[index].minutes = blocks[index].plannedMinutes
        blocks[index].changeNote = ""
        blocks[index].status = .unchanged
    }

    /// Edición a mano del texto de un bloque.
    mutating func edit(_ id: String, detail: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].detail = detail
        switch blocks[index].status {
        case .added, .skipped:
            return
        default:
            let differs = PlannerActualEditNormalizer.normalized(detail) != PlannerActualEditNormalizer.normalized(blocks[index].plannedDetail)
                || blocks[index].minutes != blocks[index].plannedMinutes
            blocks[index].status = differs ? .changed : .unchanged
            if !differs { blocks[index].changeNote = "" }
        }
    }

    /// Coloca cada actividad nueva tras el bloque del plan que nombra, o al final.
    mutating func insert(_ added: [Added]) {
        for (offset, item) in added.enumerated() {
            let block = Block(
                id: "added-\(offset)-\(item.title)",
                title: item.title,
                plannedMinutes: nil,
                plannedDetail: "",
                minutes: item.minutes,
                detail: item.detail,
                status: .added,
                changeNote: "añadida"
            )
            let key = PlannerActualEditNormalizer.normalized(item.afterTitle)
            if !key.isEmpty,
               let anchor = blocks.lastIndex(where: { $0.status != .added && PlannerActualEditNormalizer.normalized($0.title) == key }) {
                var position = anchor + 1
                while position < blocks.count, blocks[position].status == .added { position += 1 }
                blocks.insert(block, at: position)
            } else {
                blocks.append(block)
            }
        }
    }

    // MARK: Texto del diario

    /// «Qué estaba planificado»: el guion del plan.
    var plannedJournalText: String {
        blocks.filter { $0.status != .added }
            .map { Self.line(title: $0.title, minutes: $0.plannedMinutes, detail: $0.plannedDetail) }
            .joined(separator: "\n")
    }

    /// «Qué se ha hecho realmente»: los bloques finales, sin los que no se hicieron.
    var actualJournalText: String {
        blocks.filter { $0.status != .skipped }
            .map { Self.line(title: $0.title, minutes: $0.minutes, detail: $0.detail) }
            .joined(separator: "\n")
    }

    /// «Adaptaciones»: un cambio por línea.
    var adaptationsJournalText: String {
        blocks.filter(\.isChange)
            .map { "• \($0.title): \(Self.noteText(for: $0))." }
            .joined(separator: "\n")
    }

    static func noteText(for block: Block) -> String {
        let note = block.changeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        switch block.status {
        case .skipped: return "no se hizo"
        case .added: return "añadida"
        default:
            if let planned = block.plannedMinutes, let minutes = block.minutes, planned != minutes {
                return "\(planned) → \(minutes) min"
            }
            return "cambiada"
        }
    }

    private static func line(title: String, minutes: Int?, detail: String) -> String {
        let head = minutes.map { "\(title) (\($0) min)" } ?? title
        let body = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return body.isEmpty ? "• \(head)" : "• \(head): \(body)"
    }
}

/// Limpia la respuesta del modelo: nunca inventa un cambio que no aporta nada.
enum PlannerActualEditNormalizer {
    struct BlockResult: Equatable {
        let status: PlannerActualEdit.Status
        let detail: String
        let minutes: Int?
        let changeNote: String
    }

    static let maxMinutes = 240
    static let maxNoteLength = 80

    static func block(
        planned: PlannerActualEditInput.Block,
        wasSkipped: Bool,
        changed: Bool,
        detail: String,
        minutes: Int,
        changeNote: String
    ) -> BlockResult {
        let note = cleanNote(changeNote)
        if wasSkipped {
            return BlockResult(status: .skipped, detail: planned.detail, minutes: planned.minutes, changeNote: note.isEmpty ? "no se hizo" : note)
        }
        let newMinutes = (1...maxMinutes).contains(minutes) ? minutes : planned.minutes
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDetail = trimmed.isEmpty ? planned.detail : trimmed
        let detailChanged = normalized(newDetail) != normalized(planned.detail)
        let minutesChanged = newMinutes != planned.minutes
        guard changed, detailChanged || minutesChanged else {
            return BlockResult(status: .unchanged, detail: planned.detail, minutes: planned.minutes, changeNote: "")
        }
        return BlockResult(
            status: .changed,
            detail: detailChanged ? newDetail : planned.detail,
            minutes: newMinutes,
            changeNote: note
        )
    }

    static func added(title: String, minutes: Int, detail: String, afterTitle: String) -> PlannerActualEdit.Added? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        return PlannerActualEdit.Added(
            title: cleanTitle,
            minutes: (1...maxMinutes).contains(minutes) ? minutes : nil,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            afterTitle: afterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func cleanNote(_ note: String) -> String {
        var text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".;:".contains(last) { text.removeLast() }
        if text.count > maxNoteLength { text = String(text.prefix(maxNoteLength)) + "…" }
        guard let first = text.first else { return "" }
        return first.lowercased() + text.dropFirst()
    }

    /// Para comparar textos sin que cuenten mayúsculas, espacios ni puntos finales.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".;: "))
    }
}

extension SessionJournal {
    /// Copia del diario con lo realizado. «Qué estaba planificado» solo se rellena si estaba vacío.
    func withActual(plannedText newPlanned: String, actualText newActual: String, adaptationsText newAdaptations: String) -> SessionJournal {
        SessionJournal(
            id: id,
            planningSessionId: planningSessionId,
            teacherName: teacherName,
            scheduledSpace: scheduledSpace,
            usedSpace: usedSpace,
            unitLabel: unitLabel,
            objectivePlanned: objectivePlanned,
            plannedText: plannedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? newPlanned : plannedText,
            actualText: newActual,
            attainmentText: attainmentText,
            adaptationsText: newAdaptations,
            incidentsText: incidentsText,
            groupObservations: groupObservations,
            climateScore: climateScore,
            participationScore: participationScore,
            usefulTimeScore: usefulTimeScore,
            perceivedDifficultyScore: perceivedDifficultyScore,
            pedagogicalDecision: pedagogicalDecision,
            pendingTasksText: pendingTasksText,
            materialToPrepareText: materialToPrepareText,
            studentsToReviewText: studentsToReviewText,
            familyCommunicationText: familyCommunicationText,
            nextStepText: nextStepText,
            weatherText: weatherText,
            materialUsedText: materialUsedText,
            physicalIncidentsText: physicalIncidentsText,
            injuriesText: injuriesText,
            unequippedStudentsText: unequippedStudentsText,
            intensityScore: intensityScore,
            warmupMinutes: warmupMinutes,
            mainPartMinutes: mainPartMinutes,
            cooldownMinutes: cooldownMinutes,
            stationObservationsText: stationObservationsText,
            incidentTags: incidentTags,
            status: status
        )
    }
}
