import XCTest
@testable import MiGestorKMPMac

/// Emparejamiento por reglas de frases de pista con criterios de rúbricas y listas de cotejo (sin Apple Intelligence).
@MainActor
final class CourtVoiceCriteriaTests: XCTestCase {

    private func fourLevels(_ prefix: String) -> [CourtVoiceCriterionLevel] {
        ["Inicial", "En desarrollo", "Logrado", "Avanzado"].enumerated().map { index, name in
            CourtVoiceCriterionLevel(id: "\(prefix)_\(index + 1)", name: name, points: Double(index + 1), detail: "Descriptor \(name)")
        }
    }

    private var badmintonRubric: CourtVoiceInstrumentDescriptor {
        CourtVoiceInstrumentDescriptor(
            columnId: "col_badminton",
            title: "Rúbrica de bádminton: juego en pista",
            source: .rubric(evaluationId: 50, rubricId: 7),
            criteria: [
                .init(id: "11", title: "Ejecución técnica de golpeos", kind: .level, weight: 1, levels: fourLevels("11")),
                .init(id: "12", title: "Desplazamiento y colocación en pista", kind: .level, weight: 1, levels: fourLevels("12")),
                .init(id: "13", title: "Toma de decisiones táctica", kind: .level, weight: 1, levels: fourLevels("13")),
                .init(id: "14", title: "Juego limpio y respeto", kind: .level, weight: 1, levels: fourLevels("14"))
            ]
        )
    }

    private var warmUpChecklist: CourtVoiceInstrumentDescriptor {
        let check: (String, String) -> CourtVoiceCriterionDescriptor = { id, title in
            .init(id: id, title: title, kind: .check, weight: 1, levels: [.checkNo, .checkYes])
        }
        return CourtVoiceInstrumentDescriptor(
            columnId: "col_calentamiento",
            title: "Lista de cotejo: calentamiento autónomo",
            source: .template,
            criteria: [
                check("i1", "Inicia el calentamiento sin indicaciones"),
                check("i2", "Moviliza todas las articulaciones"),
                check("i3", "Aumenta la intensidad poco a poco"),
                check("i4", "Recoge y ordena el material")
            ]
        )
    }

    func testRubricPhraseSuggestsOnlyMentionedCriteria() {
        let proposals = CourtVoiceCriteriaMatcher.match(
            text: "Lucía ejecuta golpes técnicos adecuados y se mueve bien por la pista",
            instrument: badmintonRubric
        )
        let byId = Dictionary(uniqueKeysWithValues: proposals.map { ($0.id, $0) })

        XCTAssertTrue(byId["11"]?.isMentioned ?? false)
        XCTAssertEqual(byId["11"]?.suggestedLevel?.name, "Logrado")
        XCTAssertEqual(byId["11"]?.chosenLevelId, byId["11"]?.suggestedLevelId)

        XCTAssertTrue(byId["12"]?.isMentioned ?? false)
        XCTAssertEqual(byId["12"]?.suggestedLevel?.name, "Logrado")
        XCTAssertEqual(byId["12"]?.evidence, "se mueve bien por la pista")

        XCTAssertFalse(byId["13"]?.isMentioned ?? true, "Lo no dicho no se valora")
        XCTAssertNil(byId["13"]?.chosenLevelId)
        XCTAssertFalse(byId["14"]?.isMentioned ?? true)
        XCTAssertNil(byId["14"]?.chosenLevelId)

        XCTAssertEqual(proposals.previewScore, 7.5)
    }

    func testToneAndExplicitLevel() {
        let rubric = badmintonRubric
        let top = CourtVoiceCriteriaMatcher.match(text: "Hugo domina los golpeos", instrument: rubric).first { $0.id == "11" }
        XCTAssertEqual(top?.suggestedLevel?.name, "Avanzado")

        let partial = CourtVoiceCriteriaMatcher.match(text: "a Marcos le cuesta la colocación", instrument: rubric).first { $0.id == "12" }
        XCTAssertEqual(partial?.suggestedLevel?.name, "En desarrollo")

        let explicit = CourtVoiceCriteriaMatcher.match(text: "Elena un 2 en toma de decisiones", instrument: rubric).first { $0.id == "13" }
        XCTAssertEqual(explicit?.suggestedLevel?.name, "En desarrollo")

        let mentionedWithoutTone = CourtVoiceCriteriaMatcher.match(text: "Revisar el juego limpio de Hugo", instrument: rubric).first { $0.id == "14" }
        XCTAssertTrue(mentionedWithoutTone?.isMentioned ?? false)
        XCTAssertNil(mentionedWithoutTone?.suggestedLevelId, "Sin tono no se inventa nivel")
    }

    func testChecklistMarksOnlyWhatWasSaid() {
        let proposals = CourtVoiceCriteriaMatcher.match(
            text: "Marcos hace el calentamiento él solo pero no recoge el material",
            instrument: warmUpChecklist
        )
        let byId = Dictionary(uniqueKeysWithValues: proposals.map { ($0.id, $0) })
        XCTAssertEqual(byId["i1"]?.chosenLevelId, "si")
        XCTAssertEqual(byId["i4"]?.chosenLevelId, "no")
        XCTAssertNil(byId["i2"]?.chosenLevelId, "Lo no dicho queda sin marcar, nunca en No")
        XCTAssertNil(byId["i3"]?.chosenLevelId)
    }

    func testVaguePhraseFindsNoCriterion() {
        let proposals = CourtVoiceCriteriaMatcher.match(text: "Hugo hoy muy bien en el partido", instrument: badmintonRubric)
        XCTAssertFalse(proposals.contains(where: \.isMentioned))
        XCTAssertFalse(proposals.hasChosenLevel)
        XCTAssertNil(CourtVoiceCriteriaMatcher.bestInstrument(text: "Hugo hoy muy bien en el partido", instruments: [badmintonRubric, warmUpChecklist]))
    }

    func testObservationGetsSuggestionAndEvaluationBecomesReady() {
        let observation = CourtVoiceProposedAction(
            kind: .observation,
            studentId: 1,
            studentName: "Lucía Ferrer",
            note: "Ejecuta golpes técnicos adecuados y se mueve bien por la pista",
            sourceExcerpt: "Lucía ejecuta golpes técnicos adecuados y se mueve bien por la pista"
        )
        var evaluation = CourtVoiceProposedAction(
            isSelected: false,
            kind: .quickEvaluation,
            studentId: 2,
            studentName: "Marcos Vidal",
            columnId: "col_badminton",
            columnTitle: "Rúbrica de bádminton",
            sourceExcerpt: "Marcos golpeos excelentes"
        )
        XCTAssertFalse(evaluation.isReadyToApply)

        let draft = CourtVoiceCaptureDraft(rawTranscript: "", className: "1º ESO", actions: [observation, evaluation], confidenceNote: "")
        let enriched = CourtVoiceCriteriaMatcher.attachSuggestions(
            to: draft,
            instruments: [badmintonRubric.columnId: badmintonRubric, warmUpChecklist.columnId: warmUpChecklist]
        )

        let obs = enriched.actions[0]
        XCTAssertEqual(obs.kind, .observation, "La observación se conserva")
        XCTAssertEqual(obs.criteriaColumnId, "col_badminton")
        XCTAssertEqual(obs.criterionProposals?.filter(\.isMentioned).count, 2)

        evaluation = enriched.actions[1]
        XCTAssertEqual(evaluation.criteriaColumnId, "col_badminton")
        XCTAssertTrue(evaluation.hasChosenCriteria)
        XCTAssertTrue(evaluation.isReadyToApply)
        XCTAssertTrue(evaluation.isSelected)
    }

    func testModelMergeKeepsTeacherChoiceAndRejectsUnknownIds() {
        var proposals = CourtVoiceCriteriaMatcher.match(text: "Lucía ejecuta golpes técnicos adecuados", instrument: badmintonRubric)
        let index = proposals.firstIndex { $0.id == "11" }!
        proposals[index].chosenLevelId = "11_4"

        let merged = CourtVoiceCriteriaModelRefiner.merge(
            [("11", "Inicial", "golpes"), ("13", "Avanzado", "elige bien"), ("999", "Logrado", "x")],
            into: proposals
        )
        XCTAssertEqual(merged.first { $0.id == "11" }?.chosenLevelId, "11_4", "No pisa lo que el docente cambió")
        XCTAssertEqual(merged.first { $0.id == "13" }?.chosenLevelId, "13_4")
        XCTAssertEqual(merged.count, proposals.count)
    }
}
