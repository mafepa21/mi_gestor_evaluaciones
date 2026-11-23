import Foundation
import XCTest
import ZIPFoundation
@testable import MiGestorKMPMac

/// Importación de comentarios de evaluación y su exportación a Educamos. Datos inventados.
final class EvaluationCommentImportTests: XCTestCase {
    private let students = [
        EvaluationCommentStudent(id: 1, displayName: "Prueba Uno, Lucía", existingComment: ""),
        EvaluationCommentStudent(id: 2, displayName: "Prueba Dos, Mateo", existingComment: "Comentario antiguo"),
        EvaluationCommentStudent(id: 3, displayName: "Ejemplo Tres, Nora", existingComment: "")
    ]

    // MARK: - Excel sencillo

    func testFirstRowGoesToFirstStudentAndHeaderIsSkipped() {
        let table = EvaluationCommentTable(rows: [
            ["Comentarios"],
            ["Ha mostrado una gran implicación en condición física."],
            ["Progresa en voleibol cuando trabaja en grupos pequeños."],
            ["Trabaja con autonomía y aplica bien las normas."]
        ])
        XCTAssertTrue(EvaluationCommentImport.looksLikeHeader(table: table, column: 0))
        let plan = EvaluationCommentImport.plan(table: table, educamos: nil, column: 0, skipHeader: true, students: students)
        XCTAssertEqual(plan.entries.map(\.newComment), [
            "Ha mostrado una gran implicación en condición física.",
            "Progresa en voleibol cuando trabaja en grupos pequeños.",
            "Trabaja con autonomía y aplica bien las normas."
        ])
        XCTAssertEqual(plan.importCount, 3)
        XCTAssertEqual(plan.replaceCount, 1, "Mateo ya tenía comentario")
        XCTAssertFalse(plan.countsDiffer)
    }

    func testWithoutHeaderTheFirstCommentIsNotLost() {
        let table = EvaluationCommentTable(rows: [
            ["Ha mostrado una gran implicación en condición física."],
            ["Progresa en voleibol."]
        ])
        XCTAssertFalse(EvaluationCommentImport.looksLikeHeader(table: table, column: 0))
        let plan = EvaluationCommentImport.plan(table: table, educamos: nil, column: 0, skipHeader: false, students: students)
        XCTAssertEqual(plan.entries[0].newComment, "Ha mostrado una gran implicación en condición física.")
        XCTAssertNil(plan.entries[2].newComment)
        XCTAssertTrue(plan.countsDiffer)
    }

    func testEmptyRowDoesNotShiftTheNextStudents() {
        // Fila 3 vacía: Mateo se queda sin comentario y Nora recibe el de la fila 4.
        let table = EvaluationCommentTable(cellsByRow: [
            1: [0: "Comentarios"],
            2: [0: "Para Lucía, comentario largo de prueba."],
            4: [0: "Para Nora, comentario largo de prueba."]
        ])
        let plan = EvaluationCommentImport.plan(table: table, educamos: nil, column: 0, skipHeader: true, students: students)
        XCTAssertEqual(plan.entries[0].newComment, "Para Lucía, comentario largo de prueba.")
        XCTAssertNil(plan.entries[1].newComment)
        XCTAssertEqual(plan.entries[2].newComment, "Para Nora, comentario largo de prueba.")
        XCTAssertEqual(plan.emptyCount, 1)
        XCTAssertEqual(plan.replaceCount, 0, "Una fila vacía no borra el comentario actual")
    }

    func testExtraCommentsAreCountedNotImported() {
        let table = EvaluationCommentTable(rows: (1...5).map { ["Comentario número \($0) con texto suficiente."] })
        let plan = EvaluationCommentImport.plan(table: table, educamos: nil, column: 0, skipHeader: false, students: students)
        XCTAssertEqual(plan.sourceCount, 5)
        XCTAssertEqual(plan.extraCount, 2)
        XCTAssertEqual(plan.entries.count, 3)
    }

    func testSuggestsTheColumnWithMostTextAndIgnoresNumbers() {
        let table = EvaluationCommentTable(rows: [
            ["Nombre", "Nota", "Comentario"],
            ["Lucía", "8,5", "Ha mostrado una gran implicación en las sesiones."],
            ["Mateo", "6", "Progresa cuando trabaja en grupos pequeños."]
        ])
        let options = EvaluationCommentImport.columnOptions(table: table, educamos: nil)
        XCTAssertEqual(options.map(\.letter), ["A", "C"], "La columna de notas no es de texto")
        XCTAssertEqual(EvaluationCommentImport.suggestedColumn(table: table, educamos: nil), 2)
        XCTAssertEqual(options.last?.label, "C · Comentario")
    }

    func testColumnLetters() {
        XCTAssertEqual(EvaluationCommentImport.columnLetter(for: 0), "A")
        XCTAssertEqual(EvaluationCommentImport.columnLetter(for: 23), "X")
        XCTAssertEqual(EvaluationCommentImport.columnLetter(for: 26), "AA")
    }

    // MARK: - Códigos del informe anónimo

    func testCodeParsingAndColumnDetection() {
        XCTAssertEqual(EvaluationCommentImport.codeNumber("Alumno 07"), 7)
        XCTAssertEqual(EvaluationCommentImport.codeNumber(" alumno 7 "), 7)
        XCTAssertEqual(EvaluationCommentImport.codeNumber("ALUMNO 012"), 12)
        XCTAssertNil(EvaluationCommentImport.codeNumber("Alumno 07 es muy constante"))
        XCTAssertNil(EvaluationCommentImport.codeNumber("Lucía"))
        let table = EvaluationCommentTable(rows: [
            ["Código", "Comentario"],
            ["Alumno 02", "Texto largo para el segundo código."],
            ["Alumno 01", "Texto largo para el primer código."]
        ])
        XCTAssertEqual(EvaluationCommentImport.codeColumn(table: table), 0)
        XCTAssertEqual(EvaluationCommentImport.suggestedColumn(table: table, educamos: nil), 1)
        XCTAssertNil(EvaluationCommentImport.codeColumn(table: EvaluationCommentTable(rows: [["Comentario"], ["Uno."], ["Dos."]])))
    }

    func testCodesGoToTheStudentOfTheAnonymousReportKey() throws {
        // Mismo grupo que el informe «Base para boletín»: la clave debe ser idéntica.
        let classId: Int64 = 7
        let report = BulletinBaseReportBuilder.build(
            className: "2º ESO B",
            classId: classId,
            termLabel: "1er Trimestre",
            students: students.map {
                let parts = $0.displayName.components(separatedBy: ", ")
                return BulletinBaseStudentInput(studentId: $0.id, firstName: parts[1], lastName: parts[0])
            },
            evaluableColumnCount: 0,
            selfAssessmentCount: 0
        )
        let key = BulletinBaseReportBuilder.codeNumbers(studentIds: students.map(\.id), classId: classId)
        for entry in report.key {
            let number = try XCTUnwrap(EvaluationCommentImport.codeNumber(entry.code))
            let studentId = try XCTUnwrap(key[number])
            let student = try XCTUnwrap(students.first { $0.id == studentId })
            let parts = student.displayName.components(separatedBy: ", ")
            XCTAssertEqual(entry.studentName, "\(parts[1]) \(parts[0])", "\(entry.code) apunta a otro alumno")
        }

        // Excel en orden inverso y con un código que no existe.
        var rows: [[String]] = [["Código", "Comentario"]]
        for entry in report.key.reversed() {
            rows.append([entry.code, "Comentario para \(entry.studentName)."])
        }
        rows.append(["Alumno 09", "Este código no es del grupo."])
        let table = EvaluationCommentTable(rows: rows)
        let plan = EvaluationCommentImport.planByCode(
            table: table,
            codeColumn: 0,
            commentColumn: 1,
            key: key,
            students: students
        )
        XCTAssertTrue(plan.matchedByCode)
        XCTAssertFalse(plan.countsDiffer)
        XCTAssertEqual(plan.unknownCodes, ["Alumno 09"])
        for entry in plan.entries {
            let parts = entry.student.displayName.components(separatedBy: ", ")
            XCTAssertEqual(entry.newComment, "Comentario para \(parts[1]) \(parts[0]).")
            XCTAssertNotNil(entry.sourceName)
        }
    }

    // MARK: - Plantilla de Educamos

    func testEducamosTemplateRoundTrip() throws {
        let url = try makeEducamosTemplate()
        let template = try EducamosSMTemplateService.parse(from: url)
        let comments = try XCTUnwrap(template.comentariosElement)
        XCTAssertEqual(comments.columnLetter, "H")
        XCTAssertEqual(template.students.map(\.rowIndex), [6, 7])

        // Importar desde la plantilla: usa sus filas de alumnado y su columna de comentarios.
        let layout = EvaluationCommentEducamosLayout(
            studentRows: template.students.map(\.rowIndex),
            commentsColumn: comments.columnIndex,
            studentNames: template.students.map(\.rawName)
        )
        let filledURL = try EducamosSMXlsxWriter.fillGrades(
            template: template,
            cells: [
                .init(cellReference: "G6", value: .decimal(8.5)),
                .init(cellReference: "H6", value: .text("Muy buen trimestre.\nSigue así & <cuida el material>")),
                .init(cellReference: "H7", value: .text("Progresa en voleibol."))
            ]
        )
        let table = try EvaluationCommentImport.readTable(from: filledURL, sheetPath: template.mainSheetPath)
        XCTAssertEqual(EvaluationCommentImport.suggestedColumn(table: table, educamos: layout), 7)
        let plan = EvaluationCommentImport.plan(
            table: table,
            educamos: layout,
            column: comments.columnIndex,
            skipHeader: false,
            students: Array(students.prefix(2))
        )
        XCTAssertEqual(plan.entries[0].newComment, "Muy buen trimestre.\nSigue así & <cuida el material>")
        XCTAssertEqual(plan.entries[0].sourceName, "Prueba Uno, Lucía")
        XCTAssertEqual(plan.entries[1].newComment, "Progresa en voleibol.")
        XCTAssertEqual(table.value(row: 6, column: 6), "8.5")

        // La plantilla sigue siendo legible tras escribir el comentario.
        let reparsed = try EducamosSMTemplateService.parse(from: filledURL)
        XCTAssertEqual(reparsed.students.count, 2)
    }

    // MARK: - Ayuda: plantilla mínima de Educamos (inventada)

    private func makeEducamosTemplate() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("educamos-comentarios-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("EFI2_PRUEBA_EVA1.xlsx")

        func cell(_ ref: String, _ text: String) -> String {
            "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(text)</t></is></c>"
        }
        let rows: [(Int, [String])] = [
            (1, [cell("A1", "Modelo"), cell("B1", "Cuaderno")]),
            (2, [cell("A2", "ClaseMateriaId"), cell("B2", "cm-1"), cell("D2", "Educación Física")]),
            (3, [cell("A3", "TipoColumna"), "<c r=\"G3\"><v>14</v></c>", "<c r=\"H3\"><v>20</v></c>"]),
            (4, [cell("G4", "uuid-g"), cell("H4", "uuid-h")]),
            (5, [cell("A5", "Alumnos"), cell("B5", "PersonaId"), cell("C5", "N"), cell("D5", "Nombre"),
                 cell("F5", "Clase"), cell("G5", "Circuito"), cell("H5", "Comentarios")]),
            (6, [cell("B6", "p-1"), "<c r=\"C6\"><v>1</v></c>", cell("D6", "Prueba Uno, Lucía"), cell("F6", "2ESOB")]),
            (7, [cell("B7", "p-2"), "<c r=\"C7\"><v>2</v></c>", cell("D7", "Prueba Dos, Mateo"), cell("F7", "2ESOB")])
        ]
        let sheetData = rows.map { "<row r=\"\($0.0)\">\($0.1.joined())</row>" }.joined()
        let files: [String: String] = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Cuaderno" sheetId="1" r:id="rId1"/></sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(sheetData)</sheetData></worksheet>
            """
        ]
        let archive = try Archive(url: url, accessMode: .create)
        for (path, content) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data[Int(position)..<min(Int(position) + size, data.count)]
            }
        }
        return url
    }
}
