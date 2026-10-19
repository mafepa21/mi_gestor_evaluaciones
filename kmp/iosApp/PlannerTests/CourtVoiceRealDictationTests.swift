import XCTest
@testable import MiGestorKMPMac

/// Regresión con un dictado real de 9 minutos (evaluación de lanzamientos a portería, alumna a alumna),
/// transcrito en el dispositivo y anonimizado: todos los nombres son inventados. Conserva los errores del dictado.
@MainActor
final class CourtVoiceRealDictationTests: XCTestCase {

    private let roster: [CourtVoiceStudentDescriptor] = [
        ("Lucía", "Ferrer"), ("Noemí", "Gallardo"), ("Marta", "Vidal"), ("Marta", "Sanz"), ("Marta", "Benítez"),
        ("Rocío", "Navas"), ("Alba", "Prieto"), ("Daniela", "Ortiz"), ("Elena", "Ríos"), ("Inés", "Castro"),
        ("Sara", "Molina"), ("Valentina", "Gil"), ("Lorena", "Pardo"), ("Irene", "Soler"), ("Carmen", "Vega")
    ].enumerated().map { index, name in
        CourtVoiceStudentDescriptor(id: Int64(index + 1), firstName: name.0, lastName: name.1, fullName: "\(name.0) \(name.1)")
    }

    private var rubric: CourtVoiceInstrumentDescriptor {
        let levels: (String) -> [CourtVoiceCriterionLevel] = { prefix in
            ["Inicial", "En desarrollo", "Logrado", "Avanzado"].enumerated().map {
                CourtVoiceCriterionLevel(id: "\(prefix)_\($0.offset + 1)", name: $0.element, points: Double($0.offset + 1), detail: nil)
            }
        }
        return CourtVoiceInstrumentDescriptor(
            columnId: "col_tiro",
            title: "Rúbrica de lanzamiento a portería",
            source: .rubric(evaluationId: 1, rubricId: 1),
            criteria: [
                .init(id: "aproximacion", title: "Aproximación al balón", kind: .level, weight: 1, levels: levels("a")),
                .init(id: "apoyo", title: "Pie de apoyo", kind: .level, weight: 1, levels: levels("p")),
                .init(id: "postura", title: "Posición corporal y equilibrio", kind: .level, weight: 1, levels: levels("c")),
                .init(id: "gesto", title: "Gesto técnico amplio y coordinado", kind: .level, weight: 1, levels: levels("g")),
                .init(id: "superficie", title: "Superficie de golpeo", kind: .level, weight: 1, levels: levels("s")),
                .init(id: "direccion", title: "Dirección y potencia del tiro", kind: .level, weight: 1, levels: levels("d"))
            ]
        )
    }

    private let transcript = """
Lucía de técnica perfecta, posición corporal adecuada, pie de apoyo bueno, golpeo, coordinador y colocado hacia portería. Noemí.
Buen pie de apoyo, la posición corporal, un tanto desequilibrada, pero el golpeó con el interior es bueno
y la intenta colocar bien hacia un lado. Marta V.
Buen golpeo fuerte hacia el centro con el interior, posición incorporada equilibrada. Lleve apoyo igual un pelín lejos, pero... bien.
buen golpeo de Marta Uuro. Rocío.
Posición corporal, un tanto desequilibrada. Rocío. posición corporal, desequilibrada.
golpeo flojo, el pie de apoyo no está en buen lugar.
Marte, buen lanzamiento, posición corporal, firme y estable. Golpeado con el interior fuerte y colocado a un lado
Alba.
Buen lanzamiento, posición corporal adecuada se
bien. El golpeo es bueno. El pie de apoyo está a una distancia adecuada
y golpea con el interior con buena tensión, aunque el balón va al centro de la portería.
Daniela, segundo tiro lanzamiento con el interior con el empeño perdón
Lanza con buena técnica, coloca bien el pie de apoyo y el empeine chuta potente y levanta el balón.
Buen tiro. Marta S.
Hace buena aproximación, coordina bien los pasos. pero chuta más bien con la punta es que con el empeño.
one.
Marta B, primer lanzamiento
hace un lanzamiento con el interior, se aproxima y el pie de apoyo está firme, aunque la posición corporal es un poco antinatural y no sale todo equilibrada y y armónica.
El lanzamiento por el interior es bueno.
Elena R. hace lanzamiento con el empeine
te da apoyo bueno, un poco desequilibrado en el tiro y lanza demasiado con la puntera.
Inés C. lanzamiento de empeine, lanza piedra pollo bien, posición incorporar
un pelín desequilibrada, no es del todo coordinada Lanza bien con el empeño, aunque tiene tiende hacia la punta más que empeine.
Sara. Lanzamiento con el empeine coordina bien el pie de apoyo es bueno
la posición corporal es buena, se echa un poco hacia adelante con lo cual el balón no se le levanta, pero el golpeo es bueno.
Lucía.
Golpeo perfecto.
Marta V.
Golpeo
Golpeo de empeine muy bueno de Marta V. buena posición corporal, coloca bien y miotego.
Doemí, lanzamiento con el empeine. Bueno, bueno, la posición corporal ha sido buena y el pie de apoyo va bien. El golpeo no es del todo perfecto.
El golpeón no es limpio, pero.. el resto de factores elementos han sido buenos. Rocío lanzado un peine
posiciones de todo equilibrada, pide apoyo bien, lanza bien, aunque tiende un poco demasiado a la punta más que el empeño. Valentina.
Hace una buena aproximación. El pie de apoyo igu es a un pelín lejos del balón. No el gesto técnico no es el todo coordinado. y
lanzado demasiado por la punta. Marte tras con el empeine
Tiene apoyo bien, gestor no del todo
así de amplio y lanzó con la punta. Alba.
Hace una buena aproximación. El pie de polio, cual está un pelín lejos del balón.
El gesto podría ser un poco más amplio en la técnica de tiro, pero golpea bien con el empeine.
Daniela.
Marta B. lanzamiento de empeine, buena aproximación, gesto amplio y coordinado. Pide apoyo adecuado. golpeó con el empeine bueno, aunque no consigue afinar la puntería
y el balón se va fuera. Elena R.
lanz momento con el empeño la aproximación es bastante todo buena, se le ha apoyo un un pelín de con el balón
y lanza demasiado con la punta. demasiado de frente. Lorena.
Buen lanzamiento con el interior. Aproximación, una pie de apoyo firme.
texto coordinado y amplio. Y el golpeo con el interior es
Sirena.
El pie de apoyo está un poco retrasado al balón. El gesto está muy lento, pero le pega demasiado con la punta, ni con elón ni con el empeño.
Carmen.
Igual que Irene, muy frontal, se acerca la pelota y
hace el golpeo demasiado con la punta y el apoyo un poco alejado del balón. Lorena
repite el segundo lanzamiento igual que el primero. Irene en el segundo lanzamiento
Damas con el interior, pero el resto del gesto suual en el anterior.
Carmen, hace lanzamiento de interior. Ahora la aproximación es más buena, el que de apoyo mejor, gesto mejor y se
se golpea por el interior bastante bien.
Lorena, segundo lanzamiento por el interior, por gesto y buen golpe.
"""

    private func analyze() -> CourtVoiceCaptureDraft {
        let input = CourtVoiceCaptureInput(
            transcript: transcript,
            classId: 1,
            className: "1º ESO",
            students: roster,
            evaluableColumns: [CourtVoiceColumnDescriptor(id: "col_tiro", title: "Rúbrica de lanzamiento a portería", evaluationId: 1, columnType: "RUBRIC", inputKind: "RUBRIC", scaleKind: .fourLevel)]
        )
        let raw = AppleFoundationCourtVoiceService().parseWithRulesFallback(from: input, reason: "Dictado real anonimizado")
        return CourtVoiceCriteriaMatcher.attachSuggestions(to: raw, instruments: [rubric.columnId: rubric])
    }

    func testNoInventedStudentsAndAlmostNothingLost() {
        let draft = analyze()
        let fakeNames: Set<String> = ["Buen", "Hace", "Pide", "Ahora", "Damas", "Tiene", "Lanza", "Lleve", "Golpeado", "Posición", "Bueno"]
        XCTAssertFalse(draft.actions.contains { fakeNames.contains($0.studentName) }, "Ninguna palabra de la descripción se toma por alumna")
        XCTAssertTrue((24...32).contains(draft.actions.count), "Una acción por alumna e intento (\(draft.actions.count))")
        XCTAssertLessThanOrEqual(draft.unmatchedSegments.count, 2)
    }

    func testHeaderNameOwnsFollowingDescription() {
        let draft = analyze()
        let noemi = draft.actions.first { $0.studentId == 2 }
        XCTAssertTrue(noemi?.sourceExcerpt.contains("Buen pie de apoyo") ?? false, "«Noemí.» seguido de la descripción es un solo bloque")
        let rocio = draft.actions.filter { $0.studentId == 6 }
        XCTAssertEqual(rocio.count, 2, "«Rocío. … Rocío. …» seguido se une; el segundo lanzamiento es aparte")
    }

    func testSurnameInitialResolvesSameFirstName() {
        let draft = analyze()
        XCTAssertTrue(draft.actions.contains { $0.studentId == 3 && $0.sourceExcerpt.hasPrefix("Marta V") })
        XCTAssertTrue(draft.actions.contains { $0.studentId == 4 && $0.sourceExcerpt.hasPrefix("Marta S") })
        XCTAssertTrue(draft.actions.contains { $0.studentId == 5 && $0.sourceExcerpt.hasPrefix("Marta B") })
    }

    func testCriteriaAreSuggestedFromTechnicalDescription() {
        let draft = analyze()
        let lucia = draft.actions.first { $0.studentId == 1 }
        XCTAssertEqual(lucia?.kind, .quickEvaluation)
        XCTAssertEqual(lucia?.columnId, "col_tiro")
        let chosen = Set((lucia?.criterionProposals ?? []).filter { $0.chosenLevelId != nil }.map(\.id))
        XCTAssertTrue(chosen.isSuperset(of: ["apoyo", "postura"]), "«pie de apoyo bueno, posición corporal adecuada»")
        let evaluations = draft.actions.filter { $0.kind == .quickEvaluation && $0.hasChosenCriteria }
        XCTAssertGreaterThanOrEqual(evaluations.count, 20)
    }

    func testComparisonIsNotTheSubjectAndRepeatCopiesCriteria() {
        let draft = analyze()
        XCTAssertFalse(draft.actions.contains { $0.studentId == 14 && $0.sourceExcerpt.contains("Igual que Irene") },
                       "«Igual que Irene» describe a Carmen, no a Irene")
        let lorenaRepeat = draft.actions.first { $0.studentId == 13 && $0.sourceExcerpt.contains("igual que el primero") }
        XCTAssertEqual(lorenaRepeat?.kind, .quickEvaluation)
        XCTAssertTrue(lorenaRepeat?.hasChosenCriteria ?? false, "«Repite igual que el primero» copia los niveles de su primer lanzamiento")
    }

    func testDictationCorrections() {
        let fixed = CourtVoiceDictationCorrections.apply(CourtVoiceCriteriaMatcher.normalized("Pide apoyo bien, lanza con el empeño y posición incorporada"))
        XCTAssertTrue(fixed.contains("apoyo"))
        XCTAssertTrue(fixed.contains("empeine"))
        XCTAssertTrue(fixed.contains("posicion corporal"))
    }

    func testLongDictationIsChunkedForAppleIntelligence() {
        let input = CourtVoiceCaptureInput(transcript: transcript, classId: 1, className: "1º ESO", students: roster)
        let rules = AppleFoundationCourtVoiceService().parseWithRulesFallback(from: input, reason: "")
        let chunks = AppleFoundationCourtVoiceService.chunkTranscript(transcript, ruleActions: rules.actions)
        XCTAssertGreaterThanOrEqual(chunks.count, 4)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 1_200 }, "Cada trozo cabe en el contexto del modelo")
        XCTAssertEqual(AppleFoundationCourtVoiceService.chunkTranscript("Lucía un 8", ruleActions: []), ["Lucía un 8"])
    }
}
