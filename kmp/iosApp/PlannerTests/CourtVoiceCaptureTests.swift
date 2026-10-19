import XCTest
@testable import MiGestorKMPMac

@MainActor
final class CourtVoiceCaptureTests: XCTestCase {

    private var sampleStudents: [CourtVoiceStudentDescriptor] {
        [
            CourtVoiceStudentDescriptor(id: 1, firstName: "Sofía", lastName: "García", fullName: "Sofía García"),
            CourtVoiceStudentDescriptor(id: 2, firstName: "Mateo", lastName: "López", fullName: "Mateo López"),
            CourtVoiceStudentDescriptor(id: 3, firstName: "Hugo", lastName: "Martínez", fullName: "Hugo Martínez"),
            CourtVoiceStudentDescriptor(id: 4, firstName: "Lucía", lastName: "Sánchez", fullName: "Lucía Sánchez"),
            CourtVoiceStudentDescriptor(id: 5, firstName: "Izan", lastName: "Navarro", fullName: "Izan Navarro"),
            CourtVoiceStudentDescriptor(id: 6, firstName: "Marcos", lastName: "Ruiz", fullName: "Marcos Ruiz"),
            CourtVoiceStudentDescriptor(id: 7, firstName: "Elena", lastName: "Gómez", fullName: "Elena Gómez")
        ]
    }

    private var sampleColumns: [CourtVoiceColumnDescriptor] {
        [
            CourtVoiceColumnDescriptor(id: "col_badminton", title: "Progreso técnico Bádminton", evaluationId: 10),
            CourtVoiceColumnDescriptor(id: "col_fairplay", title: "Fair Play y Actitud", evaluationId: 11),
            CourtVoiceColumnDescriptor(id: "col_saque", title: "Rúbrica de Saque", evaluationId: 12),
            CourtVoiceColumnDescriptor(
                id: "col_resistencia",
                title: "Test de Resistencia Course Navette",
                evaluationId: 13,
                scaleKind: .repetitions
            ),
            CourtVoiceColumnDescriptor(
                id: "col_velocidad",
                title: "Prueba Velocidad 50m",
                evaluationId: 14,
                scaleKind: .time
            )
        ]
    }

    func testMultiStudentAttendanceAndObservationParsing() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Sofía y Mateo llegan 5 minutos tarde. Hugo muy participativo ayudando a recoger el material.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test local")

        XCTAssertEqual(draft.actions.count, 3)

        let sofiaAction = draft.actions.first(where: { $0.studentId == 1 })
        XCTAssertNotNil(sofiaAction)
        XCTAssertEqual(sofiaAction?.kind, .attendance)
        XCTAssertEqual(sofiaAction?.attendanceStatus, "TARDE")

        let mateoAction = draft.actions.first(where: { $0.studentId == 2 })
        XCTAssertNotNil(mateoAction)
        XCTAssertEqual(mateoAction?.kind, .attendance)
        XCTAssertEqual(mateoAction?.attendanceStatus, "TARDE")

        let hugoAction = draft.actions.first(where: { $0.studentId == 3 })
        XCTAssertNotNil(hugoAction)
        XCTAssertEqual(hugoAction?.kind, .observation)
        XCTAssertTrue(hugoAction?.note.localizedCaseInsensitiveContains("participativo") == true)
    }

    func testQuickEvaluationAndInjuryParsing() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Ponle un 8,5 en bádminton a Lucía por su golpeo de revés. Sofía tiene esguince de tobillo hoy.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test local")

        XCTAssertEqual(draft.actions.count, 2)

        let luciaEval = draft.actions.first(where: { $0.studentId == 4 })
        XCTAssertEqual(luciaEval?.kind, .quickEvaluation)
        XCTAssertEqual(luciaEval?.score, 8.5)
        XCTAssertEqual(luciaEval?.columnId, "col_badminton")

        let sofiaInjury = draft.actions.first(where: { $0.studentId == 1 })
        XCTAssertEqual(sofiaInjury?.kind, .injury)
        XCTAssertEqual(sofiaInjury?.markInjured, true)
    }

    func testNoMaterialAttendanceDetection() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Mateo viene sin material deportivo hoy.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test local")
        XCTAssertEqual(draft.actions.count, 1)
        XCTAssertEqual(draft.actions.first?.kind, .attendance)
        XCTAssertEqual(draft.actions.first?.attendanceStatus, "SIN_MATERIAL")
    }

    // MARK: - Regresión Fallo 3: Separación de listas con comas e instrumentos heredados

    func testCommaSeparatedGradesAssignEachStudentOwnScore() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "En la rúbrica de saque, Lucía un 8, Marcos un 7, Elena notable",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test comas")
        XCTAssertEqual(draft.actions.count, 3)

        let lucia = draft.actions.first(where: { $0.studentId == 4 })
        XCTAssertEqual(lucia?.kind, .quickEvaluation)
        XCTAssertEqual(lucia?.score, 8.0)
        XCTAssertEqual(lucia?.columnId, "col_saque")

        let marcos = draft.actions.first(where: { $0.studentId == 6 })
        XCTAssertEqual(marcos?.kind, .quickEvaluation)
        XCTAssertEqual(marcos?.score, 7.0)
        XCTAssertEqual(marcos?.columnId, "col_saque")

        let elena = draft.actions.first(where: { $0.studentId == 7 })
        XCTAssertEqual(elena?.kind, .quickEvaluation)
        XCTAssertEqual(elena?.score, 8.0)
        XCTAssertEqual(elena?.columnId, "col_saque")
    }

    func testCommaSeparatedAttendanceAndObservationDoNotBleed() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Sofía y Mateo llegan tarde, Hugo muy participativo",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Test comas mixtas")
        XCTAssertEqual(draft.actions.count, 3)
        XCTAssertEqual(draft.actions.first(where: { $0.studentId == 1 })?.kind, .attendance)
        XCTAssertEqual(draft.actions.first(where: { $0.studentId == 2 })?.kind, .attendance)
        XCTAssertEqual(draft.actions.first(where: { $0.studentId == 3 })?.kind, .observation)
    }

    // MARK: - Regresión Fallos 4 y 5: No inventar notas ni usar la primera columna si no se reconoce

    func testMissingColumnLeavesColumnIdNilAndUnselected() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Ponle un 8,5 a Lucía hoy.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Sin columna")
        XCTAssertEqual(draft.actions.count, 1)
        let action = draft.actions.first
        XCTAssertEqual(action?.kind, .quickEvaluation)
        XCTAssertEqual(action?.score, 8.5)
        XCTAssertNil(action?.columnId)
        XCTAssertFalse(action?.isSelected ?? true)
        XCTAssertFalse(action?.isReadyToApply ?? true)
    }

    func testMissingScoreDoesNotInvent7Point5() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Evalúa a Marcos en la rúbrica de saque.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Sin nota")
        XCTAssertEqual(draft.actions.count, 1)
        let action = draft.actions.first
        XCTAssertEqual(action?.kind, .quickEvaluation)
        XCTAssertEqual(action?.columnId, "col_saque")
        XCTAssertNil(action?.score)
        XCTAssertFalse(action?.isSelected ?? true)
    }

    // MARK: - Regresión Fallo 7: Nombres ambiguos, apellidos, nombres compuestos y fonética

    func testAmbiguousFirstNameDoesNotPreselectOrDuplicate() {
        let service = AppleFoundationCourtVoiceService()
        let rosterWithTwoLucias = [
            CourtVoiceStudentDescriptor(id: 10, firstName: "Lucía", lastName: "Sánchez", fullName: "Lucía Sánchez"),
            CourtVoiceStudentDescriptor(id: 11, firstName: "Lucía", lastName: "Fernández", fullName: "Lucía Fernández"),
            CourtVoiceStudentDescriptor(id: 12, firstName: "María", lastName: "Pérez", fullName: "María Pérez"),
            CourtVoiceStudentDescriptor(id: 13, firstName: "María José", lastName: "Gómez", fullName: "María José Gómez")
        ]
        let input = CourtVoiceCaptureInput(
            transcript: "Lucía llega 5 minutos tarde. María José muy participativa.",
            classId: 101,
            className: "2º ESO B",
            students: rosterWithTwoLucias,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Ambigüedad")
        XCTAssertEqual(draft.actions.count, 2)

        let luciaAction = draft.actions.first
        XCTAssertNil(luciaAction?.studentId)
        XCTAssertFalse(luciaAction?.isSelected ?? true)
        XCTAssertEqual(luciaAction?.studentCandidates.count, 2)

        let mariaJoseAction = draft.actions.last
        XCTAssertEqual(mariaJoseAction?.studentId, 13)
        XCTAssertTrue(mariaJoseAction?.isSelected ?? false)
    }

    func testSurnameAndPhoneticStudentResolution() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "García llega tarde. Isan un 9 en bádminton. Ugo muy participativo.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Fonética y apellido")
        XCTAssertEqual(draft.actions.count, 3)
        XCTAssertEqual(draft.actions[0].studentId, 1) // García -> Sofía García
        XCTAssertEqual(draft.actions[1].studentId, 5) // Isan -> Izan Navarro
        XCTAssertEqual(draft.actions[1].score, 9.0)
        XCTAssertEqual(draft.actions[2].studentId, 3) // Ugo -> Hugo Martínez
    }

    // MARK: - Regresión Fallo 8: Límites de palabra y falsos positivos

    func testWordBoundariesAvoidFalsePositives() {
        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Sofía le falta técnica en el golpeo. Mateo trabajó bien esta tarde en grupos de 4. Hugo es un excelente compañero animando al equipo. Lucía salta con alta intensidad.",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Falsos positivos")
        XCTAssertEqual(draft.actions.count, 4)

        // "le falta técnica" NO es AUSENTE
        let sofia = draft.actions.first(where: { $0.studentId == 1 })
        XCTAssertEqual(sofia?.kind, .observation)

        // "esta tarde en grupos de 4" NO es TARDE ni nota 4
        let mateo = draft.actions.first(where: { $0.studentId == 2 })
        XCTAssertEqual(mateo?.kind, .observation)
        XCTAssertNil(mateo?.score)

        // "excelente compañero" NO es evaluación con 9.5
        let hugo = draft.actions.first(where: { $0.studentId == 3 })
        XCTAssertEqual(hugo?.kind, .observation)
        XCTAssertNil(hugo?.score)

        // "salta con alta intensidad" NO es retirar lesión
        let lucia = draft.actions.first(where: { $0.studentId == 4 })
        XCTAssertEqual(lucia?.kind, .observation)
    }

    // MARK: - Fase 2: Metadatos de columna, conversión de escalas, pruebas físicas, memoria de alumno y alias

    func testPhysicalTestRawMarksAndScaleConversion() {
        let service = AppleFoundationCourtVoiceService()
        let fourLevelCol = CourtVoiceColumnDescriptor(
            id: "col_rubrica_1_4",
            title: "Rúbrica Golpeo",
            evaluationId: 20,
            columnType: "NUMERIC",
            inputKind: "NUMERIC_1_4",
            scaleKind: .fourLevel
        )
        let ordinalCol = CourtVoiceColumnDescriptor(
            id: "col_ordinal",
            title: "Escala Participación",
            evaluationId: nil,
            columnType: "ORDINAL",
            inputKind: "EXCELLENT_GOOD_PROGRESS",
            scaleKind: .achievement,
            ordinalLevels: ["Excelente", "Bien", "En proceso", "No logrado"]
        )
        let cols = sampleColumns + [fourLevelCol, ordinalCol]

        let input = CourtVoiceCaptureInput(
            transcript: "Lucía 8,2 segundos en velocidad 50m; Mateo palier 7,5 en la navette; Hugo notable en rúbrica golpeo; Elena suficiente en escala participación",
            classId: 100,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: cols
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Pruebas físicas y escalas")
        XCTAssertEqual(draft.actions.count, 4)

        let lucia = draft.actions.first(where: { $0.studentId == 4 })
        XCTAssertEqual(lucia?.kind, .quickEvaluation)
        XCTAssertEqual(lucia?.columnId, "col_velocidad")
        XCTAssertEqual(lucia?.score, 8.2)
        XCTAssertEqual(lucia?.rawUnit, "s")

        let mateo = draft.actions.first(where: { $0.studentId == 2 })
        XCTAssertEqual(mateo?.kind, .quickEvaluation)
        XCTAssertEqual(mateo?.columnId, "col_resistencia")
        XCTAssertEqual(mateo?.score, 7.5)
        XCTAssertEqual(mateo?.rawUnit, "palier")

        let hugo = draft.actions.first(where: { $0.studentId == 3 })
        XCTAssertEqual(hugo?.columnId, "col_rubrica_1_4")
        XCTAssertEqual(hugo?.score, 3.0) // Notable (8.0) -> Nivel 3 en escala 1-4

        let elena = draft.actions.first(where: { $0.studentId == 7 })
        XCTAssertEqual(elena?.columnId, "col_ordinal")
        XCTAssertEqual(elena?.formattedScaleValue, "En proceso")
    }

    func testStudentMemoryContinuationAndLearnedAliases() {
        let classId: Int64 = 999
        CourtVoiceAliasStore.learnStudentAlias(mention: "Nacho", studentId: 6, classId: classId)

        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Nacho un 8 en bádminton. Además ayudó a recoger todo el material.",
            classId: classId,
            className: "1º BAC A",
            students: sampleStudents,
            evaluableColumns: sampleColumns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Memoria y alias")
        XCTAssertEqual(draft.actions.count, 2)

        // Primera frase resuelve "Nacho" -> Marcos Ruiz (id 6) por alias aprendido
        XCTAssertEqual(draft.actions[0].studentId, 6)
        XCTAssertEqual(draft.actions[0].kind, .quickEvaluation)
        XCTAssertEqual(draft.actions[0].score, 8.0)

        // Segunda frase ("Además ayudó a recoger...") hereda a Marcos Ruiz (id 6)
        XCTAssertEqual(draft.actions[1].studentId, 6)
        XCTAssertEqual(draft.actions[1].kind, .observation)
    }

    // MARK: - Regresión Audio Real: Pausas On-Device + Elipsis ("X también" / "Y no la ha completado")

    func testOnDeviceUtteranceAccumulationAcrossPauses() {
        var committed: [String] = []
        var current: String = ""

        // Simulamos cómo SFSpeechRecognizer con `requiresOnDeviceRecognition = true` emite parciales y luego reinicia `formattedString` tras cada pausa
        let callbacks = [
            "Ferran Abad ha completado",
            "Ferran Abad ha completado la rúbrica de autoevaluación",
            "Ignacio Alemán también",
            "Emma Ambel",
            "Emma Ambel también",
            "José Bautista también",
            "Nerea Cardo no la ha completado"
        ]

        for chunk in callbacks {
            CourtVoiceLiveRecognizer.mergeUtteranceUpdate(
                newText: chunk,
                currentUtterance: &current,
                committedUtterances: &committed
            )
        }

        let full = CourtVoiceLiveRecognizer.joinUtterances(committed: committed, current: current)
        XCTAssertTrue(full.contains("Ferran Abad ha completado la rúbrica de autoevaluación"))
        XCTAssertTrue(full.contains("Ignacio Alemán también"))
        XCTAssertTrue(full.contains("Emma Ambel también"))
        XCTAssertTrue(full.contains("José Bautista también"))
        XCTAssertTrue(full.contains("Nerea Cardo no la ha completado"))
    }

    func testEllipticalRubricCompletionList() {
        let roster: [CourtVoiceStudentDescriptor] = [
            .init(id: 101, firstName: "Ferran", lastName: "Abad", fullName: "Ferran Abad", isCurrentlyInjured: false),
            .init(id: 102, firstName: "Ignacio", lastName: "Alemán", fullName: "Ignacio Alemán", isCurrentlyInjured: false),
            .init(id: 103, firstName: "Emma", lastName: "Ambel", fullName: "Emma Ambel", isCurrentlyInjured: false),
            .init(id: 104, firstName: "José", lastName: "Bautista", fullName: "José Bautista", isCurrentlyInjured: false),
            .init(id: 105, firstName: "Nerea", lastName: "Cardo", fullName: "Nerea Cardo", isCurrentlyInjured: false)
        ]
        let columns: [CourtVoiceColumnDescriptor] = [
            .init(id: "col_autoeval", title: "Rúbrica de autoevaluación", evaluationId: 1, columnType: "CHECK", inputKind: "YES_NO", scaleKind: .yesNo)
        ]

        let service = AppleFoundationCourtVoiceService()
        let input = CourtVoiceCaptureInput(
            transcript: "Ferran Abad ha completado la rúbrica de autoevaluación. Ignacio Alemán también. Emma Ambel también. José Bautista también. Nerea Cardo no la ha completado",
            classId: 200,
            className: "1º BAC A",
            students: roster,
            evaluableColumns: columns
        )

        let draft = service.parseWithRulesFallback(from: input, reason: "Audio real autoevaluación")
        XCTAssertEqual(draft.actions.count, 5, "Debe generar una acción para cada uno de los 5 alumnos")

        for i in 0..<4 {
            XCTAssertEqual(draft.actions[i].kind, .quickEvaluation)
            XCTAssertEqual(draft.actions[i].columnId, "col_autoeval")
            XCTAssertEqual(draft.actions[i].score, 10.0)
            XCTAssertEqual(draft.actions[i].formattedScaleValue, "true")
            XCTAssertTrue(draft.actions[i].isSelected)
        }

        XCTAssertEqual(draft.actions[0].studentId, 101)
        XCTAssertEqual(draft.actions[1].studentId, 102)
        XCTAssertEqual(draft.actions[2].studentId, 103)
        XCTAssertEqual(draft.actions[3].studentId, 104)

        // Nerea Cardo: no la ha completado -> score 0.0 / false en la misma columna heredada
        XCTAssertEqual(draft.actions[4].studentId, 105)
        XCTAssertEqual(draft.actions[4].kind, .quickEvaluation)
        XCTAssertEqual(draft.actions[4].columnId, "col_autoeval")
        XCTAssertEqual(draft.actions[4].score, 0.0)
        XCTAssertEqual(draft.actions[4].formattedScaleValue, "false")
        XCTAssertTrue(draft.actions[4].isSelected)
    }
}

