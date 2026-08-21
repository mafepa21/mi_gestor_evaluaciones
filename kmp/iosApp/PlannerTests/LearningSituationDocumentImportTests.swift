import Foundation
import XCTest
@testable import MiGestorKMPMac

final class LearningSituationDocumentImportTests: XCTestCase {
    func testDevelopmentPayloadDecodesV1V2AndCorruptInputWithoutCrashing() throws {
        let section = LearningSituationSessionSectionDraft(title: "Bloque", lines: ["0'-10' · Entrada · Actividad"])
        let legacy = String(data: try JSONEncoder().encode([section]), encoding: .utf8)!
        let v1 = LearningSituationSessionDevelopmentPayload.decode(from: legacy)
        XCTAssertEqual(v1?.schemaVersion, 1)
        XCTAssertEqual(v1?.sections.first?.title, "Bloque")

        let legacyObject = #"{"schemaVersion":3,"sections":[{"id":"00000000-0000-0000-0000-000000000001","title":"Legacy block","lines":["Legacy line"]}],"activities":[{"id":"00000000-0000-0000-0000-000000000002","activityKey":"W01-L-01","activityType":"core","plannedMinutes":10,"timeLabel":"0'-10'","phase":"Entry","activity":"Legacy activity","studentInstructions":"Legacy instruction","studentActions":"Legacy output"}]}"#
        let v3 = LearningSituationSessionDevelopmentPayload.decode(from: legacyObject)
        XCTAssertEqual(v3?.schemaVersion, 3)
        XCTAssertEqual(v3?.activities.first?.activityKey, "W01-L-01")
        XCTAssertEqual(v3?.activities.first?.studentActions, "Legacy output")

        let activity = LearningSituationSessionActivityDraft(
            activityKey: "W01-L-03", plannedMinutes: 50, timeLabel: "25′–75′", phase: "Main",
            activity: "Training principles jigsaw", purpose: "Purpose", organisation: "Groups", setup: "Set-up",
            teacherActions: "Teacher narrative", studentInstructions: "Instructions",
            studentActions: "Student output", timingBreakdown: "Timing",
            clilFocus: "CLIL", evidence: "Evidence", materials: "Materials",
            adaptations: "Adaptations", slowGroupPlan: "If slow", fastGroupExtension: "If ahead"
        )
        let payload = LearningSituationSessionDevelopmentPayload(
            organisation: "Eight groups", coreKnowledge: "FITT-PV", assessment: "Health Passport",
            sections: [], activities: [activity], guidingQuestions: ["What changed?"], closure: "Exit note"
        )
        let v2JSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        XCTAssertTrue(v2JSON.contains("session-plan-v2"))
        XCTAssertTrue(v2JSON.contains("\"teacherNarrative\""))
        let v2 = LearningSituationSessionDevelopmentPayload.decode(from: v2JSON)
        XCTAssertEqual(v2?.activities.first?.activityKey, "W01-L-03")
        XCTAssertEqual(v2?.guidingQuestions, ["What changed?"])
        XCTAssertNil(LearningSituationSessionDevelopmentPayload.decode(from: "{not-json"))
    }

    func testFormatCActivityMismatchWarnsAndKeepsQuickViewRows() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("Session 1 - Double (90 minutes) — Week 1"),
            .paragraph("Specific objective: Keep the task safe."),
            .paragraph("QUICK VIEW"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity", "Student output"],
                ["0′–10′", "W01-L-01", "setup", "10", "Entry", "Briefing", "Quick View output"]
            ]),
            .paragraph("ACTIVITY DETAILS"),
            .paragraph("Activity W01-L-01 — Briefing"),
            .paragraph("Purpose: First detail must win."),
            .paragraph("Activity W01-L-01 — Briefing duplicate"),
            .paragraph("Student output: Injected duplicate output."),
            .paragraph("Activity W01-L-99 — Unknown"),
            .paragraph("Purpose: Must not create a second row."),
            .paragraph("GUIDING QUESTIONS AND CLOSURE"),
            .paragraph("Ask one question."),
            .paragraph("Close with one evidence note.")
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks, data: Data("mismatch".utf8), url: URL(fileURLWithPath: "/tmp/format-c-mismatch.docx")
        )
        XCTAssertEqual(draft.plans.count, 1)
        XCTAssertEqual(draft.plans.first?.activities.map(\.activityKey), ["W01-L-01"])
        XCTAssertEqual(draft.plans.first?.activities.first?.purpose, "First detail must win.")
        XCTAssertEqual(draft.plans.first?.activities.first?.studentActions, "Quick View output")
        XCTAssertTrue(draft.warnings.contains { $0.contains("W01-L-99") })
        XCTAssertTrue(draft.warnings.contains { $0.contains("duplicado en ACTIVITY DETAILS") })
        XCTAssertEqual(draft.plans.first?.guidingQuestions, ["Ask one question."])
        XCTAssertEqual(draft.plans.first?.closure, "Close with one evidence note.")
    }

    func testFormatCAcceptsMultilineLabelsAndHeaderlessFichaTables() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("Session 1 - Double (90 minutes) — Week 1"),
            .paragraph("Specific objective"),
            .paragraph("Keep the task safe."),
            .table([
                ["Materials", "Cones and passports"],
                ["Group organisation", "Pairs"],
                ["Assessment", "Health Passport record"]
            ]),
            .paragraph("QUICK VIEW"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity", "Student output"],
                ["0′–10′", "W01-L-01", "setup", "10", "Entry", "Briefing", "One completed record"]
            ]),
            .paragraph("ACTIVITY DETAILS"),
            .paragraph("Activity W01-L-01"),
            .paragraph("Purpose"),
            .paragraph("Establish a safe baseline."),
            .paragraph("Instructions for students:"),
            .paragraph("Listen, record and swap roles.")
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks, data: Data("format-c-multiline".utf8), url: URL(fileURLWithPath: "/tmp/format-c-multiline.docx")
        )
        let plan = try XCTUnwrap(draft.plans.first)
        XCTAssertEqual(plan.objective, "Keep the task safe.")
        XCTAssertEqual(plan.material, "Cones and passports")
        XCTAssertEqual(plan.organisation, "Pairs")
        XCTAssertEqual(plan.assessment, "Health Passport record")
        XCTAssertEqual(plan.activities.first?.studentActions, "One completed record")
        XCTAssertEqual(plan.activities.first?.studentInstructions, "Listen, record and swap roles.")
        XCTAssertEqual(plan.activities.first?.purpose, "Establish a safe baseline.")
    }

    func testFormatCDuplicateSessionNumberKeepsFirstPlanAndWarns() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("Session 1 - Double (90 minutes) — First session"),
            .paragraph("QUICK VIEW"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity"],
                ["0′–10′", "W01-L-01", "setup", "10", "Entry", "First activity"]
            ]),
            .paragraph("Session 1 - Double (90 minutes) — Duplicate session"),
            .paragraph("QUICK VIEW"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity"],
                ["0′–10′", "W01-L-02", "setup", "10", "Entry", "Duplicate activity"]
            ])
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks, data: Data("duplicate-session".utf8), url: URL(fileURLWithPath: "/tmp/format-c-duplicate-session.docx")
        )

        XCTAssertEqual(draft.plans.count, 1)
        XCTAssertTrue(draft.plans.first?.title.contains("First session") == true)
        XCTAssertFalse(draft.plans.first?.title.contains("Duplicate session") == true)
        XCTAssertEqual(draft.plans.first?.activities.map(\.activityKey), ["W01-L-01"])
        XCTAssertTrue(draft.warnings.contains { $0.contains("sesión 1 aparece repetida") })
    }

    func testBatchPreviewKeepsEveryUnreadableFileAsAnIndependentFailure() {
        let urls = [
            URL(fileURLWithPath: "/tmp/primera-situacion.docx"),
            URL(fileURLWithPath: "/tmp/segunda-situacion.docx")
        ]

        let batch = LearningSituationDocumentImportService().preview(from: urls)

        XCTAssertTrue(batch.drafts.isEmpty)
        XCTAssertEqual(batch.failures.map(\.fileName), [
            "primera-situacion.docx",
            "segunda-situacion.docx"
        ])
        XCTAssertEqual(batch.failures.count, urls.count)
    }

    func testWeeklyTableImportsExecutableActivitiesAndClilFields() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("WEEK 1 - Cooperative challenge"),
            .paragraph("Objective: Build a safe cooperative routine."),
            .paragraph("LONG BLOCK (90 minutes)"),
            .table([
                ["Time", "Phase", "Activity", "Teacher instructions", "Student actions", "CLIL", "Evidence"],
                ["0-10", "Warm-up", "Traffic lights", "Model stop and go.", "Move and freeze.", "Use: stop, go, freeze.", "Safe response"]
            ]),
            .paragraph("SHORT BLOCK (30 minutes)"),
            .table([
                ["Time", "Phase", "Activity", "Teacher instructions", "Student actions", "CLIL", "Evidence"],
                ["0-30", "Practice", "Peer coaching", "Ask one open question.", "Give one feedback point.", "Sentence stem: I noticed...", "Peer note"]
            ])
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks,
            data: Data("fixture".utf8),
            url: URL(fileURLWithPath: "/tmp/weekly-session-fixture.docx")
        )

        XCTAssertEqual(draft.plans.count, 2)
        XCTAssertEqual(draft.plans[0].effectiveMinutes, 90)
        XCTAssertEqual(draft.plans[1].effectiveMinutes, 30)
        XCTAssertEqual(draft.plans[0].activities.first?.teacherActions, "Model stop and go.")
        XCTAssertEqual(draft.plans[0].activities.first?.clilFocus, "Use: stop, go, freeze.")
        XCTAssertEqual(draft.plans[1].activities.first?.evidence, "Peer note")
    }

    func testEnglishSessionHeadingImportsAsOnePlan() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("Session 1 - Double (90 minutes) — Week 1: training principles — Long block"),
            .table([
                ["Field", "Detail"],
                ["Specific objective", "Understand the training principles and record a safe baseline."],
                ["Criteria worked", "CE 1.1 · CE 1.2"],
                ["Materials needed", "Health Passport, cones and stopwatches"],
                ["Assessment", "Baseline record"]
            ]),
            .table([
                ["Time", "Phase", "Activity", "Organisation", "Student output", "Evidence"],
                ["0′–15′", "Entry", "Safety and readiness check", "Eight groups", "Agree roles and begin the record.", "Completed readiness check"]
            ])
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks,
            data: Data("english-session-heading".utf8),
            url: URL(fileURLWithPath: "/tmp/english-session-heading.docx")
        )

        XCTAssertEqual(draft.plans.count, 1)
        XCTAssertEqual(draft.plans.first?.sessionNumber, 1)
        XCTAssertEqual(draft.plans.first?.sessionType, "Doble")
        XCTAssertEqual(draft.plans.first?.effectiveMinutes, 90)
        XCTAssertEqual(draft.plans.first?.title, "Week 1: training principles — Long block")
        XCTAssertEqual(draft.plans.first?.objective, "Understand the training principles and record a safe baseline.")
        XCTAssertFalse(draft.plans.first?.development.isEmpty ?? true)
        XCTAssertTrue(draft.warnings.isEmpty)
    }

    func testQuickViewAndActivityDetailsMergeByStableActivityID() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("WEEK 1 - Building Health"),
            .paragraph("LONG BLOCK (90 effective minutes)"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity", "Organisation", "Student output", "Materials", "Evidence"],
                ["0′–20′", "W01-L-01", "core", "20", "Practice", "Partner diagnosis", "Pairs of two", "Complete the record.", "Health Passport", "Completed record"]
            ]),
            .paragraph("ACTIVITY DETAILS"),
            .paragraph("ACTIVITY W01-L-01"),
            .paragraph("Purpose: Establish a safe baseline."),
            .paragraph("Set-up: Place one sheet per pair before students enter."),
            .paragraph("Teacher instructions: Model the pulse count and check the first pair."),
            .paragraph("Instructions for students: Count, record and swap roles."),
            .paragraph("Timing breakdown: 5 minutes model, 12 minutes practice, 3 minutes check."),
            .paragraph("CLIL focus: Use the stem: Our evidence shows…"),
            .paragraph("If the group is slow: Keep the first test only."),
            .paragraph("SHORT BLOCK (30 effective minutes)"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity", "Organisation", "Student output", "Materials", "Evidence"],
                ["0′–30′", "W01-S-01", "closure", "30", "Closure", "Exit response", "Pairs", "Submit one sentence.", "Passport", "Exit ticket"]
            ])
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks,
            data: Data("quick-view-fixture".utf8),
            url: URL(fileURLWithPath: "/tmp/quick-view-fixture.docx")
        )

        XCTAssertEqual(draft.plans.count, 2)
        XCTAssertEqual(draft.plans[0].activities.map(\.activityKey), ["W01-L-01"])
        XCTAssertEqual(draft.plans[0].activities.first?.purpose, "Establish a safe baseline.")
        XCTAssertEqual(draft.plans[0].activities.first?.teacherActions, "Model the pulse count and check the first pair.")
        XCTAssertEqual(draft.plans[0].activities.first?.studentInstructions, "Count, record and swap roles.")
        XCTAssertEqual(draft.plans[0].activities.first?.studentActions, "Complete the record.")
        XCTAssertEqual(draft.plans[0].activities.first?.timingBreakdown, "5 minutes model, 12 minutes practice, 3 minutes check.")
        XCTAssertEqual(draft.plans[1].activities.map(\.activityKey), ["W01-S-01"])
        XCTAssertEqual(draft.plans[1].activities.first?.activity, "Exit response")
    }

    func testNarrativeActivityDetailsImportIntoOperationalFields() throws {
        let blocks: [WordDocumentBlock] = [
            .paragraph("WEEK 2 - Building Health"),
            .paragraph("LONG BLOCK (90 effective minutes)"),
            .table([
                ["Time", "Activity ID", "Type", "Minutes", "Phase", "Activity", "Organisation", "Teacher narrative", "Student narrative", "Transition cue", "Evidence"],
                ["0′–12′", "W02-L-01", "entry", "12", "Entry", "Arrival and readiness check", "Pairs", "Welcome the group at the door and explain why the first check protects the quality of the training data.", "Students enter, collect one passport per pair and quietly agree who records first.", "At minute 10, give the two-minute warning and ask pairs to leave the passport open on the floor.", "Completed readiness check"]
            ])
        ]

        let draft = try LearningSituationSessionSequenceDocumentImportService().preview(
            blocks: blocks,
            data: Data("narrative-fixture".utf8),
            url: URL(fileURLWithPath: "/tmp/narrative-fixture.docx")
        )

        let activity = try XCTUnwrap(draft.plans.first?.activities.first)
        XCTAssertEqual(activity.teacherActions, "Welcome the group at the door and explain why the first check protects the quality of the training data.")
        XCTAssertEqual(activity.studentActions, "Students enter, collect one passport per pair and quietly agree who records first.")
        XCTAssertEqual(activity.timingBreakdown, "At minute 10, give the two-minute warning and ask pairs to leave the passport open on the floor.")
    }

    func testActivityNavigatorKeepsTimelineAndMenuAtStableBoundaries() {
        var navigator = PlannerSessionActivityNavigator(activityKeys: ["W01-L-01", "W01-L-02", "W01-L-03"])

        XCTAssertEqual(navigator.selectedKey, "W01-L-01")
        XCTAssertFalse(navigator.canMovePrevious)
        XCTAssertTrue(navigator.canMoveNext)

        navigator.movePrevious()
        XCTAssertEqual(navigator.selectedKey, "W01-L-01")
        navigator.select("W01-L-02")
        navigator.moveNext()
        XCTAssertEqual(navigator.selectedKey, "W01-L-03")
        XCTAssertFalse(navigator.canMoveNext)
        navigator.moveNext()
        XCTAssertEqual(navigator.selectedKey, "W01-L-03")
        navigator.select("W01-L-01")
        XCTAssertEqual(navigator.selectedIndex, 0)
    }

    func testSessionDocxRendererKeepsTablesAndImagesInSessionOrder() throws {
        let docxURL = try makeMinimalDocx()
        defer { try? FileManager.default.removeItem(at: docxURL.deletingLastPathComponent()) }

        let result = try PlannerSessionDocxRenderer().render(
            from: docxURL,
            sourceLabel: "Sesión 1 - Acogida",
            sessionNumber: 1
        )

        XCTAssertEqual(result.tableCount, 1)
        XCTAssertEqual(result.imageCount, 1)
        XCTAssertTrue(result.html.contains("<h1>Sesión 1 - Acogida</h1>"))
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("data:image/png;base64,"))
        XCTAssertLessThan(result.html.range(of: "<h1>")!.lowerBound, result.html.range(of: "<table>")!.lowerBound)
    }

    func testSessionDocxRendererSelectsOnlyRequestedWeeklyBlock() throws {
        let docxURL = try makeWeeklyDocx()
        defer { try? FileManager.default.removeItem(at: docxURL.deletingLastPathComponent()) }

        let longResult = try PlannerSessionDocxRenderer().render(
            from: docxURL,
            sourceLabel: "WEEK 1 · BLOQUE LARGO (90′)",
            sessionNumber: 1
        )
        let shortResult = try PlannerSessionDocxRenderer().render(
            from: docxURL,
            sourceLabel: "WEEK 1 · BLOQUE CORTO (30′)",
            sessionNumber: 1
        )

        XCTAssertTrue(longResult.html.contains("Long-only activity"))
        XCTAssertFalse(longResult.html.contains("Short-only activity"))
        XCTAssertTrue(shortResult.html.contains("Short-only activity"))
        XCTAssertFalse(shortResult.html.contains("Long-only activity"))
    }

    private func makeMinimalDocx() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("planner-docx-\(UUID().uuidString)", isDirectory: true)
        let wordDirectory = root.appendingPathComponent("word", isDirectory: true)
        let relationshipsDirectory = wordDirectory.appendingPathComponent("_rels", isDirectory: true)
        let mediaDirectory = wordDirectory.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: relationshipsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let document = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Sesión 1 - Acogida</w:t></w:r></w:p>
            <w:p><w:r><w:t>Objetivo de la sesión.</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Actividad</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Tiempo</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Juego cooperativo</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>20 min</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            <w:p><w:r><w:drawing><wp:inline><a:graphic><a:graphicData><a:blip r:embed="rId1"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Sesión 2 - Continuidad</w:t></w:r></w:p>
            <w:p><w:r><w:t>Este contenido no debe aparecer.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let relationships = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="media/image1.png" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"/></Relationships>
        """
        try Data(document.utf8).write(to: wordDirectory.appendingPathComponent("document.xml"))
        try Data(relationships.utf8).write(to: relationshipsDirectory.appendingPathComponent("document.xml.rels"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: mediaDirectory.appendingPathComponent("image1.png"))

        let archiveURL = root.appendingPathComponent("session.docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", archiveURL.path, "word"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archiveURL
    }

    private func makeWeeklyDocx() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("planner-weekly-docx-\(UUID().uuidString)", isDirectory: true)
        let wordDirectory = root.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: wordDirectory, withIntermediateDirectories: true)
        let document = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
          <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>WEEK 1 - Sample week</w:t></w:r></w:p>
          <w:p><w:r><w:t>LONG BLOCK | 90 effective minutes</w:t></w:r></w:p>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Long-only activity</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
          <w:p><w:r><w:t>SHORT BLOCK | 30 effective minutes</w:t></w:r></w:p>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Short-only activity</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
          <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>WEEK 2 - Next week</w:t></w:r></w:p>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Next-week activity</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>
        """
        try Data(document.utf8).write(to: wordDirectory.appendingPathComponent("document.xml"))
        let archiveURL = root.appendingPathComponent("session.docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", archiveURL.path, "word"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archiveURL
    }
}
