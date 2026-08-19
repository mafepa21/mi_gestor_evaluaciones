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
