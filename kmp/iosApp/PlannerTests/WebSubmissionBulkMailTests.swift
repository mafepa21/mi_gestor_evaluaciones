import XCTest
@testable import MiGestorKMPMac

final class WebSubmissionBulkMailTests: XCTestCase {

    private func link(
        id: Int64,
        name: String,
        email: String?,
        alias: String = "alias"
    ) -> WebPublishedStudentLink {
        WebPublishedStudentLink(
            studentId: id,
            studentName: name,
            email: email,
            url: URL(string: "https://entregas.example/#f=form&a=\(alias)")!
        )
    }

    // MARK: - Plantilla

    func testRendersOnePlaceholderSetPerStudent() {
        let rendered = WebSubmissionMailTemplate.render(
            "Hola {{nombre}}, tarea «{{tarea}}»: {{enlace}}",
            studentName: "Ana García",
            taskTitle: "SA 1",
            link: "https://entregas.example/#f=form&a=alias-a"
        )

        XCTAssertEqual(
            rendered,
            "Hola Ana García, tarea «SA 1»: https://entregas.example/#f=form&a=alias-a"
        )
    }

    func testDefaultTemplateCarriesTheThreePlaceholders() {
        for placeholder in WebSubmissionMailTemplate.allPlaceholders {
            XCTAssertTrue(
                WebSubmissionMailTemplate.defaultBody.contains(placeholder),
                "La plantilla por defecto debería incluir \(placeholder)"
            )
        }
    }

    // MARK: - Plan

    func testPlanBuildsOneMessagePerStudentWithItsOwnLink() {
        let plan = WebSubmissionBulkMailPlanner.plan(
            taskTitle: "SA 1",
            links: [
                link(id: 1, name: "Ana", email: "ana@example.com", alias: "alias-a"),
                link(id: 2, name: "Luis", email: "luis@example.com", alias: "alias-b"),
            ],
            subject: "  Enlace de entrega  ",
            bodyTemplate: "{{nombre}} → {{enlace}}"
        )

        XCTAssertEqual(plan.messages.count, 2)
        XCTAssertTrue(plan.skipped.isEmpty)
        XCTAssertEqual(plan.messages.map(\.recipient), ["ana@example.com", "luis@example.com"])
        // El asunto se limpia una sola vez, igual para todos.
        XCTAssertEqual(Set(plan.messages.map(\.subject)), ["Enlace de entrega"])
        // Cada mensaje lleva su alias, nunca el del compañero.
        XCTAssertTrue(plan.messages[0].body.hasSuffix("a=alias-a"))
        XCTAssertTrue(plan.messages[1].body.hasSuffix("a=alias-b"))
        XCTAssertFalse(plan.messages[0].body.contains("alias-b"))
    }

    func testPlanSetsAsideStudentsWithoutUsableAddressWithoutBlockingTheRest() {
        let plan = WebSubmissionBulkMailPlanner.plan(
            taskTitle: "SA 1",
            links: [
                link(id: 1, name: "Ana", email: "ana@example.com"),
                link(id: 2, name: "Sin correo", email: nil),
                link(id: 3, name: "Vacío", email: "   "),
                link(id: 4, name: "Roto", email: "luis(arroba)example.com"),
                link(id: 5, name: "Con espacio", email: "lu is@example.com"),
            ],
            subject: "Asunto",
            bodyTemplate: "{{enlace}}"
        )

        XCTAssertEqual(plan.messages.map(\.studentId), [1])
        XCTAssertEqual(plan.skipped.map(\.studentId), [2, 3, 4, 5])
        XCTAssertEqual(plan.skipped[0].reason, "Sin correo en la ficha")
        XCTAssertEqual(plan.skipped[1].reason, "Sin correo en la ficha")
        XCTAssertEqual(plan.skipped[2].reason, "Correo con formato no válido")
    }

    func testPlanTrimsSurroundingWhitespaceFromAddress() {
        let plan = WebSubmissionBulkMailPlanner.plan(
            taskTitle: "SA 1",
            links: [link(id: 1, name: "Ana", email: "  ana@example.com \n")],
            subject: "Asunto",
            bodyTemplate: "{{enlace}}"
        )

        XCTAssertEqual(plan.messages.first?.recipient, "ana@example.com")
    }

    func testSplitCountsMatchThePlanWithoutRenderingBodies() {
        let links = [
            link(id: 1, name: "Ana", email: "ana@example.com"),
            link(id: 2, name: "Sin correo", email: nil),
        ]
        let partition = WebSubmissionBulkMailPlanner.split(links: links)
        let plan = WebSubmissionBulkMailPlanner.plan(
            taskTitle: "SA 1",
            links: links,
            subject: "Asunto",
            bodyTemplate: "{{enlace}}"
        )

        XCTAssertEqual(partition.eligible.count, plan.messages.count)
        XCTAssertEqual(partition.skipped.map(\.studentId), plan.skipped.map(\.studentId))
    }

    // MARK: - Guion de Mail

    func testScriptEscapesQuotesBackslashesAndNewlines() {
        let escaped = WebSubmissionMailScript.escape("Ana \"La\" \\ García\nSegunda línea\r\nTercera")

        XCTAssertEqual(
            escaped,
            "Ana \\\"La\\\" \\\\ García\\nSegunda línea\\nTercera"
        )
        XCTAssertFalse(escaped.contains("\n"))
    }

    func testScriptClosesInjectedStringsSoANameCannotAlterTheScript() {
        let message = WebSubmissionMailMessage(
            studentId: 1,
            studentName: "Ana",
            recipient: "ana@example.com",
            // Un nombre así en la ficha cerraría el literal si no se escapase.
            subject: "\" & (do shell script \"whoami\") & \"",
            body: "cuerpo"
        )
        let source = WebSubmissionMailScript.source(for: message, delivery: .drafts)

        XCTAssertFalse(source.contains("do shell script \""))
        XCTAssertTrue(source.contains("\\\" & (do shell script \\\"whoami\\\") & \\\""))
    }

    func testScriptSavesDraftsAndSendsOnlyWhenAsked() {
        let message = WebSubmissionMailMessage(
            studentId: 1,
            studentName: "Ana",
            recipient: "ana@example.com",
            subject: "Asunto",
            body: "cuerpo"
        )

        let borrador = WebSubmissionMailScript.source(for: message, delivery: .drafts)
        XCTAssertTrue(borrador.contains("save nuevoMensaje"))
        XCTAssertFalse(borrador.contains("send nuevoMensaje"))

        let envio = WebSubmissionMailScript.source(for: message, delivery: .send)
        XCTAssertTrue(envio.contains("send nuevoMensaje"))
        XCTAssertFalse(envio.contains("save nuevoMensaje"))
    }

    func testScriptAddsExactlyOneRecipientPerMessage() {
        let message = WebSubmissionMailMessage(
            studentId: 1,
            studentName: "Ana",
            recipient: "ana@example.com",
            subject: "Asunto",
            body: "cuerpo"
        )
        let source = WebSubmissionMailScript.source(for: message, delivery: .drafts)

        XCTAssertEqual(source.components(separatedBy: "make new to recipient").count - 1, 1)
        XCTAssertFalse(source.contains("cc recipient"))
        XCTAssertFalse(source.contains("bcc recipient"))
    }

    // MARK: - Resumen

    func testReportSummaryNamesWhatWentOutAndWhatDidNot() {
        var report = WebSubmissionBulkMailReport(delivery: .drafts)
        report.deliveredStudentIds = [1, 2, 3]
        report.failures = [(studentName: "Luis", reason: "Mail devolvió el error -1728.")]
        report.skipped = [
            WebSubmissionMailSkip(studentId: 9, studentName: "Eva", reason: "Sin correo en la ficha")
        ]

        XCTAssertEqual(
            report.summary,
            "Se prepararon 3 correos. 1 falló. 1 alumno se quedó fuera por no tener correo utilizable."
        )
    }

    func testReportSummaryExplainsMissingPermission() {
        var report = WebSubmissionBulkMailReport(delivery: .send)
        report.permissionDenied = true

        XCTAssertTrue(report.summary.contains("permiso"))
    }
}
