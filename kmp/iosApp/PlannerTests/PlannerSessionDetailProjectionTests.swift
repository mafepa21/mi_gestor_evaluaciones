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
            activity: "Jigsaw", purpose: "Build evidence", teacherActions: "Cue the transition."
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
        XCTAssertEqual(projection.organisation, "Groups of four")
        XCTAssertEqual(projection.basicKnowledge, ["FITT-PV"])
        XCTAssertEqual(projection.guidingQuestions, ["What changed?"])
        XCTAssertEqual(projection.closure, "Exit note")
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
