import Foundation
import XCTest
@testable import MiGestorKMPMac

final class LearningSituationDocumentImportTests: XCTestCase {
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
        XCTAssertEqual(draft.plans[0].activities.first?.timingBreakdown, "5 minutes model, 12 minutes practice, 3 minutes check.")
        XCTAssertEqual(draft.plans[1].activities.map(\.activityKey), ["W01-S-01"])
        XCTAssertEqual(draft.plans[1].activities.first?.activity, "Exit response")
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
