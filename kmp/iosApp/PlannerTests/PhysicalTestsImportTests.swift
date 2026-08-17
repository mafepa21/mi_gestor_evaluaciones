import Foundation
import XCTest
@testable import MiGestorKMPMac

final class PhysicalTestsImportTests: XCTestCase {
    func testPreviewAcceptsCustomDiagnosticTestsAndKeepsRawOnlyMode() throws {
        let json = #"{"format":"mi_gestor.physical-tests-import","version":1,"purpose":"INITIAL_DIAGNOSTIC","learningSituation":{"number":0,"course":"3º ESO","subject":"Educación Física"},"assignmentTemplate":{"batteryId":"sa0_3_initial_baseline_2026","batteryName":"SA 0 · Línea base inicial (3º ESO)","termLabel":"1ª evaluación · diagnóstico","rawColumnMode":true,"scoreColumnMode":false,"recordScore":false,"countsTowardAverage":false,"showRankings":false},"testDefinitions":[{"id":"police_agility_circuit","name":"Circuito de agilidad","capacity":"AGILITY","measurementKind":"TIME","unit":"s","higherIsBetter":false,"attempts":2,"resultMode":"BEST","protocol":"Registrar el menor tiempo válido.","plausibleMinimum":6,"plausibleMaximum":20,"decimals":2}],"referenceScales":[{"id":"agility_reference","testId":"police_agility_circuit","name":"Referencia inicial","course":3,"ageFrom":13,"ageTo":14,"sex":null,"direction":"LOWER_IS_BETTER","diagnosticReferenceOnly":true,"ranges":[{"id":"r1","minValue":null,"maxValue":9,"score":10,"label":"≤ 9 s","sortOrder":0}]}],"calibrationRequiredTestIds":[],"warnings":["Solo diagnóstico."],"sourceNotes":["Fixture anónima"]}"#

        let draft = try PhysicalTestsImportService().preview(
            from: URL(fileURLWithPath: "/tmp/pruebas.json"),
            data: Data(json.utf8)
        )

        XCTAssertEqual(draft.testDefinitions.map(\.id), ["police_agility_circuit"])
        XCTAssertEqual(draft.referenceScales.first?.testId, "police_agility_circuit")
        XCTAssertTrue(draft.assignmentTemplate.rawColumnMode)
        XCTAssertFalse(draft.assignmentTemplate.scoreColumnMode)
        XCTAssertFalse(draft.assignmentTemplate.recordScore)
        XCTAssertTrue(draft.scoreIsDisabled)
        XCTAssertEqual(draft.courseNumber, 3)
    }

    func testPreviewRejectsScoreColumnWhenRecordScoreIsDisabled() {
        let json = #"{"format":"mi_gestor.physical-tests-import","version":1,"purpose":"INITIAL_DIAGNOSTIC","learningSituation":{"number":0,"course":"3º ESO","subject":"Educación Física"},"assignmentTemplate":{"batteryId":"battery","batteryName":"Batería","termLabel":"Diagnóstico","rawColumnMode":true,"scoreColumnMode":true,"recordScore":false,"countsTowardAverage":false,"showRankings":false},"testDefinitions":[{"id":"test","name":"Prueba","capacity":"CUSTOM","measurementKind":"SCORE","unit":"u","higherIsBetter":true,"attempts":1,"resultMode":"LAST","protocol":"","plausibleMinimum":null,"plausibleMaximum":null,"decimals":0}],"referenceScales":[],"calibrationRequiredTestIds":[],"warnings":[],"sourceNotes":[]}"#

        XCTAssertThrowsError(
            try PhysicalTestsImportService().preview(
                from: URL(fileURLWithPath: "/tmp/pruebas-invalidas.json"),
                data: Data(json.utf8)
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("scoreColumnMode"))
        }
    }

    func testPreviewAcceptsLinearCalibrationPointsInVersionTwo() throws {
        let json = #"{"format":"mi_gestor.physical-tests-import","version":2,"purpose":"INITIAL_DIAGNOSTIC","learningSituation":{"number":0,"course":"3º ESO","subject":"Educación Física"},"assignmentTemplate":{"batteryId":"battery","batteryName":"Batería","termLabel":"Diagnóstico","rawColumnMode":true,"scoreColumnMode":false,"recordScore":false,"countsTowardAverage":false,"showRankings":false},"testDefinitions":[{"id":"jump","name":"Salto","capacity":"STRENGTH","measurementKind":"DISTANCE","unit":"cm","higherIsBetter":true,"attempts":1,"resultMode":"BEST","protocol":"","plausibleMinimum":0,"plausibleMaximum":300,"decimals":0}],"referenceScales":[{"id":"jump_scale","testId":"jump","name":"Salto gradual","course":3,"ageFrom":13,"ageTo":14,"sex":null,"direction":"HIGHER_IS_BETTER","diagnosticReferenceOnly":true,"scoring":{"mode":"LINEAR","roundTo":0.1,"points":[{"id":"p0","value":0,"score":0,"sortOrder":0},{"id":"p1","value":100,"score":5,"sortOrder":1},{"id":"p2","value":200,"score":10,"sortOrder":2}]}}],"calibrationRequiredTestIds":[],"warnings":[],"sourceNotes":[]}"#

        let draft = try PhysicalTestsImportService().preview(
            from: URL(fileURLWithPath: "/tmp/pruebas-lineales.json"),
            data: Data(json.utf8)
        )

        XCTAssertEqual(draft.referenceScales.first?.scoring?.mode, "LINEAR")
        XCTAssertEqual(draft.referenceScales.first?.scoring?.points.count, 3)
        XCTAssertTrue(draft.referenceScales.first?.ranges.isEmpty == true)
    }
}
