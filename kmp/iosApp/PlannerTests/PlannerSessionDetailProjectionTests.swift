import Foundation
import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

final class PlannerSessionDetailProjectionTests: XCTestCase {
    func testWeeklyPlanSeparatesBlocksRolesEvidenceAndSupportContext() throws {
        let sections = [
            LearningSituationSessionSectionDraft(
                title: "Block 1 (45')",
                lines: [
                    "0'-5' · Entry · Explain the challenge (Profesorado: Briefing breve.; Alumnado: Escucha y prepara el material.; Evidencia: Ticket de entrada.)",
                    "5'-20' · Practice · Reto cooperativo"
                ]
            ),
            LearningSituationSessionSectionDraft(title: "Break (15') — hidratación", lines: ["Hydration and material reset"]),
            LearningSituationSessionSectionDraft(
                title: "Block 2 (45')",
                lines: ["0'-10' · Cierre · Registro en el pasaporte (Teacher role: Circula.; Student role: Registra.)"]
            ),
            LearningSituationSessionSectionDraft(title: "Core CLIL routine", lines: ["Start · Today our focus is..."])
        ]
        let plan = try makePlan(
            material: "Conos, gomas, pasaporte — Saberes básicos: RPE, recuperación cardíaca",
            criteria: ["CE 1.2", "CE 3.2"],
            sections: sections
        )

        let projection = PlannerSessionDetailProjection(plan: plan)

        XCTAssertEqual(projection.timeline.count, 3)
        XCTAssertEqual(projection.timeline[0].durationLabel, "45'")
        XCTAssertEqual(projection.timeline[1].kind, .breakTime)
        XCTAssertEqual(projection.timeline[2].durationLabel, "45'")
        XCTAssertEqual(projection.timeline[0].steps.first?.phase, "Entry")
        XCTAssertEqual(projection.timeline[0].steps.first?.teacherRole, "Briefing breve.")
        XCTAssertEqual(projection.timeline[0].steps.first?.studentRole, "Escucha y prepara el material.")
        XCTAssertEqual(projection.timeline[0].steps.first?.evidence, "Ticket de entrada.")
        XCTAssertEqual(projection.materials, ["Conos", "gomas", "pasaporte"])
        XCTAssertEqual(projection.basicKnowledge, ["RPE", "recuperación cardíaca"])
        XCTAssertEqual(projection.supportSections.map(\.title), ["Core CLIL routine"])
    }

    func testLegacyFlatLinesRemainReadableWithoutStructuredRoleSuffix() throws {
        let plan = try makePlan(
            material: "Balones, conos",
            criteria: [],
            sections: [
                LearningSituationSessionSectionDraft(
                    title: "Desarrollo",
                    lines: ["10'-25' · Juego condicionado · El alumnado aplica la regla y el docente observa"]
                )
            ]
        )

        let projection = PlannerSessionDetailProjection(plan: plan)
        let step = try XCTUnwrap(projection.timeline.first?.steps.first)

        XCTAssertEqual(step.timeLabel, "10'-25'")
        XCTAssertEqual(step.phase, "Juego condicionado")
        XCTAssertEqual(step.activity, "El alumnado aplica la regla y el docente observa")
        XCTAssertNil(step.teacherRole)
        XCTAssertNil(step.studentRole)
    }

    func testV2ObjectPayloadProjectsQuickViewActivitiesAndAnnexes() throws {
        let activity = LearningSituationSessionActivityDraft(
            activityKey: "W01-L-03", plannedMinutes: 50, timeLabel: "25′–75′", phase: "Main",
            activity: "Jigsaw", purpose: "Build evidence", teacherActions: "Cue the transition.",
            prepares: "Activate prior learning.", consolidates: "Retrieve the evidence."
        )
        let payload = LearningSituationSessionDevelopmentPayload(
            organisation: "Groups of four", coreKnowledge: "FITT-PV", assessment: "Health Passport",
            sections: [], activities: [activity], guidingQuestions: ["What changed?"], closure: "Exit note"
        )
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        let plan = try makePlan(material: "Cones", criteria: ["CE 1.1"], sections: [])
            .withDevelopment(json)

        let projection = PlannerSessionDetailProjection(plan: plan)
        XCTAssertEqual(projection.activities.first?.activityKey, "W01-L-03")
        XCTAssertEqual(projection.activities.first?.prepares, "Activate prior learning.")
        XCTAssertEqual(projection.activities.first?.consolidates, "Retrieve the evidence.")
        XCTAssertEqual(projection.organisation, "Groups of four")
        XCTAssertEqual(projection.basicKnowledge, ["FITT-PV"])
        XCTAssertEqual(projection.guidingQuestions, ["What changed?"])
        XCTAssertEqual(projection.closure, "Exit note")
    }

    func testPayloadNormalizerHidesLegacyIDsAndIDTitlesWithoutChangingActivityCount() throws {
        let payload = LearningSituationSessionDevelopmentPayload(
            schema: "legacy",
            schemaVersion: 1,
            sections: [LearningSituationSessionSectionDraft(
                title: "Bloque 1",
                lines: ["0'-10' · Entry · W01-L-01"]
            )],
            activities: [LearningSituationSessionActivityDraft(
                activityKey: "LEGACY-3-6",
                timeLabel: "0'-10'",
                phase: "Entry",
                activity: "LEGACY-unparsed-title"
            )]
        )

        let activities = PlannerSessionPlanPayloadNormalizer.activities(from: payload)
        XCTAssertEqual(activities.count, 1)
        XCTAssertFalse(activities[0].activityKey.hasPrefix("LEGACY-"))
        XCTAssertFalse(activities[0].activity.hasPrefix("LEGACY-"))
        XCTAssertFalse(activities[0].activity.hasPrefix("W01-L-"))

        let json = try XCTUnwrap(PlannerSessionPlanPayloadNormalizer.normalizedJSON(
            from: String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        ))
        let normalized = try XCTUnwrap(LearningSituationSessionDevelopmentPayload.decode(from: json))
        XCTAssertEqual(normalized.schema, "session-plan-v2")
        XCTAssertEqual(normalized.activities.count, 1)

        let contextual = LearningSituationSessionDevelopmentPayload(
            sections: [],
            activities: [LearningSituationSessionActivityDraft(
                activityKey: "W01-L-02",
                timeLabel: "0'-10'",
                activity: "Revisar W01-L-02 antes del cambio de parejas"
            )]
        )
        let contextualActivity = PlannerSessionPlanPayloadNormalizer.activities(from: contextual).first
        XCTAssertEqual(contextualActivity?.activity, "Revisar W01-L-02 antes del cambio de parejas")
    }

    func testLegacyActivityProjectionExcludesContextSectionsAndUsesStableKeys() {
        let sections = [
            LearningSituationSessionSectionDraft(title: "Bloque 1", lines: ["0'-10' · Entry · Preparación"]),
            LearningSituationSessionSectionDraft(title: "Evaluación", lines: ["Evidence collected"]),
            LearningSituationSessionSectionDraft(title: "Preguntas guía", lines: ["What changed?"]),
            LearningSituationSessionSectionDraft(title: "Cierre", lines: ["Exit note"]),
            LearningSituationSessionSectionDraft(title: "Adaptaciones", lines: ["Reduce distance."])
        ]

        let activities = PlannerSessionLegacyActivityProjection.executableActivities(from: sections)
        XCTAssertEqual(activities.map(\.activity), ["Preparación"])
        XCTAssertEqual(activities.map(\.activityKey), ["LEGACY-1-1"])

        let duplicateInput = [
            LearningSituationSessionActivityDraft(activityKey: "W01-L-01", timeLabel: "0'-5'", activity: "First"),
            LearningSituationSessionActivityDraft(activityKey: "W01-L-01", timeLabel: "5'-10'", activity: "Second"),
            LearningSituationSessionActivityDraft(timeLabel: "10'-15'", activity: "Fallback")
        ]
        XCTAssertEqual(
            PlannerSessionLegacyActivityProjection.stableActivities(duplicateInput).map(\.activityKey),
            ["W01-L-01", "W01-L-01#2", "LEGACY-3"]
        )
    }

    func testLegacyActivityProjectionRejectsUntimedProseAndKeepsTimedRows() {
        let sections = [
            LearningSituationSessionSectionDraft(
                title: "Block 1 (45')",
                lines: [
                    "Group organisation: Pairs",
                    "0'-10' · Entry · Timed warm-up",
                    "Teacher note: Check the first response."
                ]
            ),
            LearningSituationSessionSectionDraft(
                title: "PREPARES",
                lines: ["Activate prior knowledge before the long block."]
            ),
            LearningSituationSessionSectionDraft(
                title: "Additional notes",
                lines: [
                    "10'-20' · Practice · Timed relay",
                    "Assessment metadata: Health Passport"
                ]
            )
        ]

        let activities = PlannerSessionLegacyActivityProjection.executableActivities(from: sections)

        XCTAssertEqual(activities.map(\.activityKey), ["LEGACY-1-2", "LEGACY-3-1"])
        XCTAssertEqual(activities.map(\.timeLabel), ["0'-10'", "10'-20'"])
        XCTAssertEqual(activities.map(\.activity), ["Timed warm-up", "Timed relay"])
    }

    func testCLILChunksExtractedFromPayloadAndMarkdownSection() throws {
        let chunksDraft = LearningSituationCLILChunksDraft(
            teacherCues: ["Freeze on whistle!", "Low center of gravity!"],
            studentInteraction: ["I am open!", "Switch sides!"],
            debrief: ["How did communication help you recover?"]
        )
        let payload = LearningSituationSessionDevelopmentPayload(
            sections: [],
            activities: [],
            clilChunks: chunksDraft
        )
        let payloadJSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        let plan = try makePlan(
            material: "Conos",
            criteria: [],
            sections: []
        ).withDevelopment(payloadJSON)

        let projection = PlannerSessionDetailProjection(plan: plan)
        XCTAssertNotNil(projection.clilChunks)
        XCTAssertEqual(projection.clilChunks?.teacherCues.count, 2)
        XCTAssertEqual(projection.clilChunks?.studentInteraction.count, 2)
        XCTAssertEqual(projection.clilChunks?.debrief.count, 1)
        XCTAssertEqual(projection.clilChunks?.teacherCues.first, "Freeze on whistle!")
    }

    func testCLILChunksEmbeddedInLastNumberedPhaseAreExtractedAndStripped() throws {
        let text = """
        Semicircle talk about the thumb position.
        Recogida: Cooperative pack-up.
        Chunks Lingüísticos (CLIL) · Language Chunks
        Teacher Cues: "V-shape grip!", "Keep your racket up!"
        Student Interaction: "Nice lift!", "Switch hands now!"
        Debrief: "Why does the thumb position matter?" (CE 2.2)
        """
        let activity = LearningSituationSessionActivityDraft(
            activityKey: "SF-U01-A04", plannedMinutes: 4, timeLabel: "4 min", phase: "Reflection and record",
            activity: "Reflection and record", purpose: "", teacherActions: text
        )
        let payload = LearningSituationSessionDevelopmentPayload(sections: [], activities: [activity])
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        let plan = try makePlan(material: "Cones", criteria: [], sections: []).withDevelopment(json)

        let projection = PlannerSessionDetailProjection(plan: plan)
        XCTAssertEqual(projection.clilChunks?.teacherCues, ["V-shape grip!", "Keep your racket up!"])
        XCTAssertEqual(projection.clilChunks?.studentInteraction.count, 2)
        XCTAssertEqual(projection.clilChunks?.debrief.count, 1)
        let shown = projection.activities.first?.teacherActions ?? ""
        XCTAssertTrue(shown.contains("Semicircle talk"))
        XCTAssertTrue(shown.contains("Recogida"))
        XCTAssertFalse(shown.contains("Teacher Cues"))
        XCTAssertFalse(shown.contains("Chunks"))
    }

    func testSessionPlansMatchDistinguishesRoutesOfTheSameDocument() throws {
        let stored = try makePlan(material: "Cones", criteria: [], sections: [])
        func draft(label: String, type: String, route: LearningSituationWeeklySequenceRoute?) -> LearningSituationSessionPlanDraft {
            LearningSituationSessionPlanDraft(
                sessionNumber: 1, sourceLabel: label, title: "t", sessionType: type, effectiveMinutes: 90,
                objective: "", criteria: [], material: "", development: [], adaptations: [], sequenceRoute: route
            )
        }
        // Misma ruta y mismas etiquetas: se reutiliza la versión guardada.
        XCTAssertTrue(KmpBridge.sessionPlansMatch(
            existing: [stored], draft: [draft(label: "Semana 1 · Bloque largo", type: "Bloque largo", route: .longFirst)]
        ))
        // Otra ruta del mismo archivo (etiqueta o tipo distintos): versión propia, sin sobrescribir.
        XCTAssertFalse(KmpBridge.sessionPlansMatch(
            existing: [stored], draft: [draft(label: "Encuentro E01 · SHORT", type: "SHORT", route: .shortFirst)]
        ))
        // Documentos sin rutas conservan el criterio histórico (mismo SHA).
        XCTAssertTrue(KmpBridge.sessionPlansMatch(
            existing: [stored], draft: [draft(label: "otra", type: "otro", route: nil)]
        ))
    }

    func testCLILChunksParsedFromMarkdownText() throws {
        let text = """
        ### Chunks Lingüísticos (CLIL / Pista bilingüe)
        - **Pautas de acción docente (Teacher Cues):** "Check scene safety first!", "Call 112 with exact location!"
        - **Comunicación en juego (Student Interaction):** "Is the scene safe?", "Calling 112 now!"
        - **Feedback y reflexión (Debrief):** "Why is scene safety non-negotiable?"
        """
        let parsed = LearningSituationDocumentImportService.parseCLILChunks(from: text)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.teacherCues.count, 2)
        XCTAssertEqual(parsed?.studentInteraction.count, 2)
        XCTAssertEqual(parsed?.debrief.count, 1)
        XCTAssertEqual(parsed?.teacherCues[0], "Check scene safety first!")
        XCTAssertEqual(parsed?.studentInteraction[1], "Calling 112 now!")
        XCTAssertEqual(parsed?.debrief[0], "Why is scene safety non-negotiable?")
    }

    // MARK: - Repaso rápido (guion por bloques)

    private func reviewActivity(
        _ key: String, segment: String, minutes: Int?, phase: String, title: String,
        teacher: String = "", purpose: String = "", organisation: String = "", adaptations: String = ""
    ) -> LearningSituationSessionActivityDraft {
        LearningSituationSessionActivityDraft(
            activityKey: key, plannedMinutes: minutes, timeLabel: minutes.map { "\($0) min" } ?? "",
            phase: phase, activity: title, purpose: purpose, organisation: organisation,
            teacherActions: teacher, adaptations: adaptations,
            segmentKey: segment, segmentTitle: "\(segment) · Título \(segment)"
        )
    }

    private func makeReviewPlan(
        activities: [LearningSituationSessionActivityDraft],
        organisation: String = "",
        objective: String? = nil
    ) throws -> LearningSituationSessionPlan {
        let payload = LearningSituationSessionDevelopmentPayload(organisation: organisation, sections: [], activities: activities)
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        var plan = try makePlan(material: "", criteria: [], sections: []).withDevelopment(json)
        if let objective { plan = plan.withObjective(objective) }
        return plan
    }

    private func longSessionActivities() -> [LearningSituationSessionActivityDraft] {
        [
            reviewActivity("W01-L-01", segment: "U01", minutes: 4, phase: "Explicación", title: "Demostración de agarres"),
            reviewActivity("W01-L-02", segment: "U01", minutes: 6, phase: "Calentamiento", title: "Keep-Up Trail"),
            reviewActivity("W01-L-03", segment: "U01", minutes: 24, phase: "Principal", title: "Control Ladder"),
            reviewActivity("W01-L-04", segment: "U01", minutes: 6, phase: "Reflexión", title: "Semicírculo"),
            reviewActivity("W01-L-05", segment: "U02", minutes: 4, phase: "Explicación", title: "Saque corto y largo")
        ]
    }

    func testLongSessionSplitsIntoTwoBlocksAndSecondFollowsBreak() throws {
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: longSessionActivities()))

        XCTAssertEqual(projection.guideBlocks.count, 2)
        XCTAssertFalse(projection.guideBlocks[0].precededByBreak)
        XCTAssertTrue(projection.guideBlocks[1].precededByBreak)
        XCTAssertEqual(projection.guideBlocks[0].label, "U01 · Título U01")
        XCTAssertEqual(projection.guideBlocks[0].totalMinutes, 40)
        XCTAssertEqual(projection.guideBlocks[1].totalMinutes, 4)
    }

    func testStartOffsetsAccumulateWithoutCountingBreak() throws {
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: longSessionActivities()))

        let offsets = projection.guideBlocks.flatMap(\.steps).map(\.startOffsetMinutes)
        XCTAssertEqual(offsets, [0, 4, 10, 34, 40])
        XCTAssertEqual(PlannerSessionReviewStep.offsetLabel(4), "00:04")
        XCTAssertEqual(PlannerSessionReviewStep.offsetLabel(75), "01:15")
    }

    func testMainStepIsTheLongestMainMomentOfEachBlock() throws {
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: longSessionActivities()))

        XCTAssertEqual(projection.guideBlocks[0].steps.map(\.isMain), [false, false, true, false])
        XCTAssertEqual(projection.guideBlocks[1].steps.map(\.isMain), [false])
    }

    func testCLILConsignaLeavesTeacherTextAndGoesToClil() throws {
        let activity = reviewActivity(
            "W01-L-01", segment: "U01", minutes: 4, phase: "Explicación", title: "Agarres",
            teacher: "Demuestra el agarre.\nConsigna CLIL: V-shape for forehand"
        )
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: [activity]))
        let step = try XCTUnwrap(projection.guideBlocks.first?.steps.first)

        XCTAssertEqual(step.detail, "Demuestra el agarre.")
        XCTAssertEqual(step.clil, "V-shape for forehand")
    }

    func testCollectionLineBecomesOwnStepWithoutTime() throws {
        let activity = reviewActivity(
            "W01-L-04", segment: "U01", minutes: 6, phase: "Reflexión", title: "Semicírculo",
            teacher: "Charla en semicírculo.\nRecogida: Recoger volantes y conos."
        )
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: [activity]))
        let steps = try XCTUnwrap(projection.guideBlocks.first?.steps)

        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].detail, "Charla en semicírculo.")
        XCTAssertTrue(steps[1].isCollection)
        XCTAssertEqual(steps[1].title, "Recoger volantes y conos.")
        XCTAssertNil(steps[1].startOffsetMinutes)
        XCTAssertNil(steps[1].minutes)
    }

    func testOwnCollectionActivityHasNoStartTimeAndDoesNotAdvanceOffsets() throws {
        let activities = [
            reviewActivity("W01-L-01", segment: "U01", minutes: 4, phase: "Explicación", title: "Saque"),
            reviewActivity("W01-L-02", segment: "U01", minutes: 2, phase: "Recogida", title: "Recoger volantes"),
            reviewActivity("W01-L-03", segment: "U02", minutes: 4, phase: "Explicación", title: "Saque largo")
        ]
        let steps = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: activities)).guideBlocks.flatMap(\.steps)

        XCTAssertEqual(steps.map(\.isCollection), [false, true, false])
        XCTAssertEqual(steps.map(\.startOffsetMinutes), [0, nil, 4])
    }

    func testSetupBulletsAreSplitDeduplicatedAndCapped() throws {
        let plan = try makeReviewPlan(
            activities: [reviewActivity("W01-L-01", segment: "U01", minutes: 4, phase: "Explicación", title: "A", organisation: "Pistas: 12 parejas")],
            organisation: "Pistas: 12 parejas; Zona libre: 5 parejas. Rotan al silbato\nCada pareja con su raqueta\nAros a 4 m\nConos en las esquinas del campo con una descripción muy larga que supera claramente los ochenta caracteres permitidos"
        )
        let projection = PlannerSessionDetailProjection(plan: plan)

        XCTAssertEqual(projection.setupBullets.count, 4)
        XCTAssertEqual(Array(projection.setupBullets.prefix(3)), ["Pistas: 12 parejas", "Zona libre: 5 parejas", "Rotan al silbato"])
        XCTAssertTrue(projection.setupBullets.allSatisfy { $0.count <= 81 })
        XCTAssertEqual(projection.setupAll.count, 6)
    }

    func testAttentionComesFromPlanAdaptationsActivityAndPurposeAndIsCapped() throws {
        let activity = reviewActivity(
            "W01-L-01", segment: "U01", minutes: 4, phase: "Explicación", title: "A",
            purpose: "Objetivo de la tarea. Atención especial: Evitar choques.",
            adaptations: "Burbuja de raqueta"
        )
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: [activity]))

        // La adaptación del plan viene de `makePlan` («Analista de datos»).
        XCTAssertEqual(projection.attentionNotes, ["Analista de datos", "Burbuja de raqueta", "Evitar choques"])

        let many = reviewActivity("W01-L-02", segment: "U01", minutes: 4, phase: "Explicación", title: "B", adaptations: "Uno\nDos\nTres\nCuatro")
        let capped = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: [many]))
        XCTAssertEqual(capped.attentionNotes.count, 3)
        XCTAssertEqual(capped.attentionAll.count, 5)
    }

    func testReviewObjectiveFallsBackToFirstActivityPurpose() throws {
        let activity = reviewActivity(
            "W01-L-01", segment: "U01", minutes: 4, phase: "Explicación", title: "A",
            purpose: "Sacar en diagonal a los aros. Atención especial: Sin golpear al cruzar."
        )
        let withoutObjective = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: [activity], objective: ""))
        XCTAssertEqual(withoutObjective.reviewObjective, "Sacar en diagonal a los aros.")

        let withObjective = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: [activity]))
        XCTAssertEqual(withObjective.reviewObjective, "Aplicar el reto con seguridad.")
    }

    func testEmptyPayloadProducesEmptyGuide() throws {
        let projection = PlannerSessionDetailProjection(plan: try makeReviewPlan(activities: []))

        XCTAssertTrue(projection.guideBlocks.isEmpty)
        XCTAssertTrue(projection.setupBullets.isEmpty)
    }

    private func makePlan(
        material: String,
        criteria: [String],
        sections: [LearningSituationSessionSectionDraft]
    ) throws -> LearningSituationSessionPlan {
        let criteriaJSON = String(data: try JSONEncoder().encode(criteria), encoding: .utf8)!
        let developmentJSON = String(data: try JSONEncoder().encode(sections), encoding: .utf8)!
        let adaptationsJSON = String(data: try JSONEncoder().encode(["Analista de datos"]), encoding: .utf8)!
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return LearningSituationSessionPlan(
            id: 1,
            learningSituationId: 2,
            sequenceVersionId: 3,
            sessionNumber: 1,
            sourceLabel: "Semana 1 · Bloque largo",
            title: "Reto de aula",
            sessionType: "Bloque largo",
            effectiveMinutes: 90,
            objective: "Aplicar el reto con seguridad.",
            criteriaJson: criteriaJSON,
            material: material,
            developmentJson: developmentJSON,
            adaptationsJson: adaptationsJSON,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: now,
                updatedAt: now,
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
        )
    }
}

private extension LearningSituationSessionPlan {
    func withDevelopment(_ developmentJSON: String) -> LearningSituationSessionPlan {
        LearningSituationSessionPlan(
            id: id,
            learningSituationId: learningSituationId,
            sequenceVersionId: sequenceVersionId,
            sessionNumber: sessionNumber,
            sourceLabel: sourceLabel,
            title: title,
            sessionType: sessionType,
            effectiveMinutes: effectiveMinutes,
            objective: objective,
            criteriaJson: criteriaJson,
            material: material,
            developmentJson: developmentJSON,
            adaptationsJson: adaptationsJson,
            trace: trace
        )
    }
}

private extension LearningSituationSessionPlan {
    func withObjective(_ newObjective: String) -> LearningSituationSessionPlan {
        LearningSituationSessionPlan(
            id: id,
            learningSituationId: learningSituationId,
            sequenceVersionId: sequenceVersionId,
            sessionNumber: sessionNumber,
            sourceLabel: sourceLabel,
            title: title,
            sessionType: sessionType,
            effectiveMinutes: effectiveMinutes,
            objective: newObjective,
            criteriaJson: criteriaJson,
            material: material,
            developmentJson: developmentJson,
            adaptationsJson: adaptationsJson,
            trace: trace
        )
    }
}
