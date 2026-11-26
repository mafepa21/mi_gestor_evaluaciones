import Foundation
import MiGestorKit
import XCTest
@testable import MiGestorKMPMac

/// Exportar a Educamos: emparejamiento automático de columnas y SA, transposición 1-4 → 0-10 y nota final.
final class EducamosEvaluationMatchingTests: XCTestCase {
    private var zeroTrace: AuditTrace {
        let zero = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return AuditTrace(authorUserId: nil, createdAt: zero, updatedAt: zero, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
    }

    private func tab(_ id: String, _ title: String, parent: String? = nil, order: Int32 = 0) -> NotebookTab {
        NotebookTab(
            id: id,
            title: title,
            description: nil,
            order: order,
            parentTabId: parent,
            fixedColumnWidth: nil,
            trace: zeroTrace,
            weight: nil
        )
    }

    private func column(
        id: String,
        title: String,
        type: NotebookColumnType = .numeric,
        instrument: NotebookInstrumentKind = .custom,
        inputKind: NotebookCellInputKind = .numeric010,
        scaleKind: NotebookScaleKind = .tenPoint,
        tabIds: [String] = ["hockey"],
        evaluationId: Int64? = nil,
        weight: Double = 1.0,
        counts: Bool = true
    ) -> NotebookColumnDefinition {
        NotebookColumnDefinition(
            id: id,
            title: title,
            type: type,
            categoryKind: .evaluation,
            instrumentKind: instrument,
            inputKind: inputKind,
            evaluationId: evaluationId.map { KotlinLong(value: $0) },
            rubricId: nil,
            formula: nil,
            weight: weight,
            dateEpochMs: nil,
            unitOrSituation: nil,
            competencyCriteriaIds: [],
            scaleKind: scaleKind,
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: 0,
            widthDp: 120,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: counts,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: zeroTrace
        )
    }

    private lazy var tabs = [
        tab("ev1", "1.ª Evaluación"),
        tab("hockey", "Hockey", parent: "ev1"),
        tab("ultimate", "Ultimate", parent: "ev1", order: 1),
        tab("ev2", "2.ª Evaluación", order: 1),
        tab("salto", "Salto", parent: "ev2"),
        tab("asistencia", "Asistencia", order: 2)
    ]

    func testNormalizesEducamosPrefixes() {
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("SA2 Hockey"), "hockey")
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("S.A. 3: Disco volador"), "disco volador")
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("SA - Atletismo"), "atletismo")
        // Sin número ni signo detrás, «Sa» es parte del nombre.
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("Salto"), "salto")
    }

    func testProposesBlocksAndNeverAnEvaluation() {
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "SA2 Hockey", tabs: tabs)?.id, "hockey")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "Hock", tabs: tabs)?.id, "hockey")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "Ultim", tabs: tabs)?.id, "ultimate")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "SA4 Salto", tabs: tabs)?.id, "salto")
        XCTAssertNil(EducamosSATabMatcher.propose(shortName: "1.ª Evaluación", tabs: tabs))
        XCTAssertNil(EducamosSATabMatcher.propose(shortName: "SA9 Natación", tabs: tabs))
        XCTAssertFalse(EducamosSATabMatcher.candidateTabs(tabs).contains { $0.id == "ev1" || $0.id == "ev2" })
        XCTAssertEqual(EducamosSATabMatcher.displayTitle(tabs[1], tabs: tabs), "Hockey (1.ª Evaluación)")
        XCTAssertEqual(EducamosSATabMatcher.displayTitle(tabs[5], tabs: tabs), "Asistencia")
    }

    func testBilingualAndFullDescriptionSAMatching() {
        let bilingualTabs = [
            tab("ev1", "1.ª Evaluación"),
            tab("balonmano", "SA1: Balonmano", parent: "ev1"),
            tab("badminton", "SA2: Bádminton", parent: "ev1", order: 1)
        ]
        XCTAssertEqual(
            EducamosSATabMatcher.propose(shortName: "Hand", fullName: "Balonmano", tabs: bilingualTabs)?.id,
            "balonmano"
        )
        XCTAssertEqual(
            EducamosSATabMatcher.propose(shortName: "Hand", tabs: bilingualTabs)?.id,
            "balonmano"
        )
        XCTAssertEqual(
            EducamosSATabMatcher.propose(shortName: "BAd", fullName: "Badminton", tabs: bilingualTabs)?.id,
            "badminton"
        )
    }

    func testAutoMatchesColumnsWithinSAAndDoesNotStealFromUnmatchedSA() {
        let elements: [EducamosSMElement] = [
            // SA1 Béisbol (no existe en este Cuaderno)
            EducamosSMElement(columnIndex: 6, columnLetter: "G", shortName: "AUT", uuid: "u1", tipoColumna: 14, parentSAColumnLetter: "J"),
            EducamosSMElement(columnIndex: 7, columnLetter: "H", shortName: "CM", uuid: "u2", tipoColumna: 14, parentSAColumnLetter: "J"),
            EducamosSMElement(columnIndex: 8, columnLetter: "I", shortName: "TG", uuid: "u3", tipoColumna: 14, parentSAColumnLetter: "J"),
            EducamosSMElement(columnIndex: 9, columnLetter: "J", shortName: "Beis", uuid: "u4", tipoColumna: 15),
            // SA2 Hockey (sí existe en el Cuaderno)
            EducamosSMElement(columnIndex: 10, columnLetter: "K", shortName: "Seg", uuid: "u5", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 11, columnLetter: "L", shortName: "C.M.", uuid: "u6", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 12, columnLetter: "M", shortName: "T-T", uuid: "u7", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 13, columnLetter: "N", shortName: "A.H", uuid: "u8", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 14, columnLetter: "O", shortName: "Hock", uuid: "u9", tipoColumna: 15),
            EducamosSMElement(columnIndex: 15, columnLetter: "P", shortName: "Nota", uuid: nil, tipoColumna: 1)
        ]

        let columns: [NotebookColumnDefinition] = [
            column(
                id: "col_seg",
                title: "Rejilla Transversal de Seguridad con Implemento, Fair Play y Roles",
                type: .numeric,
                instrument: .dailyWork,
                inputKind: .structuredObservation,
                scaleKind: .fourLevel,
                tabIds: ["hockey"]
            ),
            column(
                id: "col_cm",
                title: "Rúbrica visual de técnica · Hockey",
                type: .rubric,
                instrument: .rubric,
                inputKind: .rubric,
                scaleKind: .tenPoint,
                tabIds: ["hockey"]
            ),
            column(
                id: "col_tt",
                title: "Rúbrica de Análisis Táctico en Mini-Liga y Valoración Crítica del Deporte",
                type: .rubric,
                instrument: .rubric,
                inputKind: .rubric,
                scaleKind: .tenPoint,
                tabIds: ["hockey"]
            ),
            column(
                id: "col_aut",
                title: "Autoevaluación",
                type: .text,
                instrument: .selfAssessment,
                inputKind: .structuredForm,
                scaleKind: .custom,
                tabIds: ["hockey"]
            )
        ]

        let resolved = EducamosColumnMatcher.matchElements(
            elements: elements,
            tabs: tabs,
            columns: columns,
            savedMapping: [:],
            excelEvaluation: "PRIMERA EVALUACIÓN",
            activeTabId: "hockey"
        )
        let byLetter = Dictionary(uniqueKeysWithValues: resolved.map { ($0.element.columnLetter, $0) })

        // Beis no está en el Cuaderno, así que sus columnas no roban la Autoevaluación ni las rúbricas de Hockey
        XCTAssertNil(byLetter["J"]?.appTab)
        XCTAssertNil(byLetter["G"]?.appColumn)
        XCTAssertNil(byLetter["H"]?.appColumn)
        XCTAssertNil(byLetter["I"]?.appColumn)

        // Hockey empareja su pestaña y sus 4 instrumentos 1 a 1 sin duplicados
        XCTAssertEqual(byLetter["O"]?.appTab?.id, "hockey")
        XCTAssertEqual(byLetter["K"]?.appColumn?.id, "col_seg")
        XCTAssertEqual(byLetter["L"]?.appColumn?.id, "col_cm")
        XCTAssertEqual(byLetter["M"]?.appColumn?.id, "col_tt")
        XCTAssertEqual(byLetter["N"]?.appColumn?.id, "col_aut")
    }

    func testTransposesTransversalObservationGridAndSelfAssessmentFromFourToTen() {
        let rejilla = column(
            id: "col_seg",
            title: "Rejilla Transversal de Seguridad",
            type: .numeric,
            instrument: .dailyWork,
            inputKind: .structuredObservation,
            scaleKind: .fourLevel
        )
        let autoeval = column(
            id: "col_aut",
            title: "Autoevaluación",
            type: .text,
            instrument: .selfAssessment,
            inputKind: .structuredForm,
            scaleKind: .custom
        )
        let checklist = column(
            id: "col_chk",
            title: "Checklist ponderada",
            type: .numeric,
            instrument: .checklist,
            inputKind: .structuredChecklist,
            scaleKind: .tenPoint
        )

        // En el Cuaderno (NotebookStructuredGrade) se transpone 1-4 -> 0-10 automáticamente
        XCTAssertEqual(NotebookStructuredGrade(value: 4.0, column: rejilla).value, 10.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 3.0, column: rejilla).value, 20.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 2.5, column: rejilla).value, 5.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 1.0, column: rejilla).value, 0.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 4.0, column: rejilla).scaleText, "/ 10")

        // En la exportación a Educamos (EducamosGradeExtractor) también sale sobre 10
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: rejilla, numericText: "4") ?? -1, 10.0, accuracy: 0.001)
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: rejilla, numericText: "3,4") ?? -1, 8.0, accuracy: 0.001)
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: autoeval, numericText: "3,5") ?? -1, 25.0 / 3.0, accuracy: 0.001)

        // Una checklist proporcional que ya nace sobre 10 (p. ej. 2,5 / 10) NO se reescala como nivel 1-4
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: checklist, numericText: "2,5") ?? -1, 2.5, accuracy: 0.001)
    }

    func testFinalGradeComesFromTheExcelEvaluation() {
        // El Excel es de la 1.ª evaluación aunque el Cuaderno esté abierto en un bloque de la 2.ª.
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "1ª Evaluación", activeTabId: "salto"), "ev1")
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "Segunda evaluación", activeTabId: nil), "ev2")
        // Sin trimestre reconocible: la evaluación de la pestaña abierta.
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "Final", activeTabId: "ultimate"), "ev1")
        XCTAssertNil(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "Final", activeTabId: "asistencia"))
    }

    func testPartialPolicyDefaultsToEmptyAndIsRememberedPerGroup() throws {
        let suite = "educamos-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(EducamosPartialGradePolicy.load(classId: 7, defaults: defaults), .leaveEmpty)
        EducamosPartialGradePolicy.exportPartial.save(classId: 7, defaults: defaults)
        XCTAssertEqual(EducamosPartialGradePolicy.load(classId: 7, defaults: defaults), .exportPartial)
        XCTAssertEqual(EducamosPartialGradePolicy.load(classId: 8, defaults: defaults), .leaveEmpty)
    }

    func testParsesValencianEducamosTemplateWithAlumnesAndClasseHeaders() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("educamos-valencian-\(UUID().uuidString)", isDirectory: true)
        let xlDir = tempRoot.appendingPathComponent("xl", isDirectory: true)
        let worksheetsDir = xlDir.appendingPathComponent("worksheets", isDirectory: true)
        try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sharedStrings = [
            "Modelo", "CuadernoCompetenciasItems", "Data", "26/11/2026",
            "ColegioId", "Col·legi", "COL·LEGI SAN JOSÉ",
            "CalendarioEscolarId", "058b1436-9fca-4b33-bd62-f86f122a5cb2", "Curs escolar", "2026-2027",
            "ClaseMateriaId", "c08e4745-e15f-4248-90f1-2bcc16971a6e", "Matèria", "Educació física",
            "EvaluacionId", "b439fcb2-6be8-47bd-9b56-b0c54e7e7d42", "Avaluació", "1ª Avaluació",
            "FicheroId", "c46ad041-0f8f-4ab4-a891-71141f7e73e7",
            "TipoColumna",
            "a5d9a6a4-9581-4223-a13d-07e4dc1932fe",
            "5dcad93b-8e7e-4227-bb4b-8f4763031509",
            "06108746-c83d-4f2a-bb0e-96d570c016c2",
            "PersonaId", "Alumnes", "Classe",
            "C.M.", "A.C.", "Col", "Nota", "Comentari del professor",
            "f98d35ff-dbde-41bd-8308-b47f00aa7bd4", "GARCIA LOPEZ, PAU", "1ESOA",
            "b874fdb9-801c-4a90-8b57-a7f200a446fe", "MARTINEZ SOLER, LAIA"
        ]
        let ssItems = sharedStrings.map { "<si><t>\($0)</t></si>" }.joined()
        let sharedStringsXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(ssItems)</sst>
        """
        try sharedStringsXML.write(to: xlDir.appendingPathComponent("sharedStrings.xml"), atomically: true, encoding: .utf8)

        let sheetXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="2"><c r="A2" t="s"><v>0</v></c><c t="s"><v>1</v></c><c t="s"><v>2</v></c><c/><c t="s"><v>3</v></c></row>
            <row r="3"><c r="A3" t="s"><v>4</v></c><c><v>1468</v></c><c t="s"><v>5</v></c><c/><c t="s"><v>6</v></c></row>
            <row r="4"><c r="A4" t="s"><v>7</v></c><c t="s"><v>8</v></c><c t="s"><v>9</v></c><c/><c t="s"><v>10</v></c></row>
            <row r="5"><c r="A5" t="s"><v>11</v></c><c t="s"><v>12</v></c><c t="s"><v>13</v></c><c/><c t="s"><v>14</v></c></row>
            <row r="6"><c r="A6" t="s"><v>15</v></c><c t="s"><v>16</v></c><c t="s"><v>17</v></c><c/><c t="s"><v>18</v></c></row>
            <row r="7"><c r="A7" t="s"><v>19</v></c><c t="s"><v>20</v></c></row>
            <row r="10"><c r="F10" t="s"><v>21</v></c><c><v>14</v></c><c><v>14</v></c><c><v>15</v></c><c><v>1</v></c><c><v>20</v></c></row>
            <row r="11"><c r="G11" t="s"><v>22</v></c><c t="s"><v>23</v></c><c t="s"><v>24</v></c><c/><c/></row>
            <row r="12"><c r="A12" t="s"><v>11</v></c><c t="s"><v>25</v></c><c t="s"><v>26</v></c><c/><c/><c t="s"><v>27</v></c><c t="s"><v>28</v></c><c t="s"><v>29</v></c><c t="s"><v>30</v></c><c t="s"><v>31</v></c><c t="s"><v>32</v></c></row>
            <row r="13"><c r="A13" t="s"><v>12</v></c><c t="s"><v>33</v></c><c><v>1</v></c><c t="s"><v>34</v></c><c/><c t="s"><v>35</v></c></row>
            <row r="14"><c r="A14" t="s"><v>12</v></c><c t="s"><v>36</v></c><c><v>2</v></c><c t="s"><v>37</v></c><c/><c t="s"><v>35</v></c></row>
          </sheetData>
        </worksheet>
        """
        try sheetXML.write(to: worksheetsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)

        let commentsXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <authors><author>educamos</author></authors>
          <commentList>
            <comment ref="G12" authorId="0"><text><r><t>Competència motriu</t></r></text></comment>
            <comment ref="H12" authorId="0"><text><r><t>Autoavaluació colpbol</t></r></text></comment>
            <comment ref="I12" authorId="0"><text><r><t>SA1: Colpbol</t></r></text></comment>
          </commentList>
        </comments>
        """
        try commentsXML.write(to: xlDir.appendingPathComponent("comments1.xml"), atomically: true, encoding: .utf8)

        let xlsxURL = tempRoot.appendingPathComponent("EFI1_1ESOA_1A.xlsx")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = tempRoot
        zipProcess.arguments = ["-qr", xlsxURL.path, "xl"]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        XCTAssertEqual(zipProcess.terminationStatus, 0)

        let template = try EducamosSMTemplateService.parse(from: xlsxURL)
        XCTAssertEqual(template.metadata.materia, "Educació física")
        XCTAssertEqual(template.metadata.evaluacion, "1ª Avaluació")
        XCTAssertEqual(template.students.count, 2)
        XCTAssertEqual(template.students[0].rowIndex, 13)
        XCTAssertEqual(template.students[0].rawName, "GARCIA LOPEZ, PAU")
        XCTAssertEqual(template.students[0].clase, "1ESOA")
        XCTAssertEqual(template.students[1].rowIndex, 14)
        XCTAssertEqual(template.students[1].rawName, "MARTINEZ SOLER, LAIA")

        XCTAssertEqual(template.instrumentElements.map(\.columnLetter), ["G", "H"])
        XCTAssertEqual(template.instrumentElements.map(\.fullName), ["Competència motriu", "Autoavaluació colpbol"])
        XCTAssertEqual(template.instrumentElements.map(\.parentSAColumnLetter), ["I", "I"])
        XCTAssertEqual(template.categoriaElements.map(\.columnLetter), ["I"])
        XCTAssertEqual(template.notaFinalElement?.columnLetter, "J")
        XCTAssertEqual(template.comentariosElement?.columnLetter, "K")
    }

    func testAutoMatchesValencianSelfAssessmentAndEvaluationTerms() {
        let valencianTabs = [
            tab("ev1", "1.ª Evaluación"),
            tab("colpbol", "SA1: Colpbol", parent: "ev1"),
            tab("ev2", "2.ª Evaluación", order: 1),
            tab("gim", "SA2: Hab. Gimnàstiques", parent: "ev2")
        ]
        let elements: [EducamosSMElement] = [
            EducamosSMElement(columnIndex: 7, columnLetter: "H", shortName: "A.C.", fullName: "Autoavaluació colpbol", uuid: "u1", tipoColumna: 14, parentSAColumnLetter: "I"),
            EducamosSMElement(columnIndex: 8, columnLetter: "I", shortName: "Col", fullName: "SA1: Colpbol", uuid: "u2", tipoColumna: 15)
        ]
        let columns: [NotebookColumnDefinition] = [
            column(
                id: "col_auto",
                title: "Autoavaluació",
                type: .text,
                instrument: .selfAssessment,
                inputKind: .structuredForm,
                scaleKind: .custom,
                tabIds: ["colpbol"]
            )
        ]

        let resolved = EducamosColumnMatcher.matchElements(
            elements: elements,
            tabs: valencianTabs,
            columns: columns,
            savedMapping: [:],
            excelEvaluation: "1ª Avaluació",
            activeTabId: "colpbol"
        )
        let byLetter = Dictionary(uniqueKeysWithValues: resolved.map { ($0.element.columnLetter, $0) })
        XCTAssertEqual(byLetter["I"]?.appTab?.id, "colpbol")
        XCTAssertEqual(byLetter["H"]?.appColumn?.id, "col_auto")
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: valencianTabs, excelEvaluation: "1ª Avaluació", activeTabId: nil), "ev1")
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: valencianTabs, excelEvaluation: "Segona avaluació", activeTabId: nil), "ev2")
    }
}
