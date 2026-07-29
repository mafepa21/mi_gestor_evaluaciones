import Foundation

#if DEBUG
enum AppleAIReadinessFixtures {
    static let studentInsight = StudentInsight(
        summary: "Lectura educativa de ejemplo basada en evidencias locales.",
        strengths: [
            "Entrega evidencias de forma regular.",
            "Mantiene una tendencia estable."
        ],
        improvementAreas: [
            "Cerrar actividades pendientes antes del siguiente corte."
        ],
        attendanceSignal: "Asistencia reciente sin incidencias.",
        performanceSignal: "Tendencia estable.",
        riskAnalysis: RiskAnalysis(
            severity: .moderate,
            causes: ["Hay columnas evaluables pendientes."],
            evidence: ["Media: 6,8", "Evidencias disponibles: 4"],
            confidence: 0.62,
            confidenceNote: "Fixture local para verificacion de contrato."
        ),
        recommendations: [
            "Revisar la proxima evidencia.",
            "Contrastar la lectura con rubricas asociadas."
        ],
        confidenceNote: "Fixture local para verificacion de contrato."
    )

    static let tutorMeetingSummary = TutorMeetingSummary(
        keyPoints: [
            "Media actual: 6,8.",
            "Evidencias disponibles: 4."
        ],
        concerns: [
            "Cerrar columnas pendientes antes de conclusiones finales."
        ],
        actions: [
            "Acordar una accion concreta y revisable."
        ],
        familyFacingSummary: "Resumen prudente de ejemplo basado en datos locales del cuaderno."
    )

    static let earlyWarning = EarlyWarning(
        severity: .moderate,
        causes: [
            "Columnas evaluables pendientes."
        ],
        evidence: [
            "Media: 6,8",
            "Evidencias disponibles: 4"
        ],
        recommendations: [
            "Revisar el caso en la proxima sesion de seguimiento."
        ],
        confidence: 1.4,
        confidenceNote: "Fixture local para confirmar clamp de confianza."
    )

    static let physicalProgressAnalysis = PhysicalProgressAnalysis(
        summary: "Analisis EF de ejemplo para validar render y contrato.",
        trend: "Estable",
        improvementPercentage: 4.5,
        strengths: ["Mejora en resistencia."],
        weaknesses: ["Faltan registros en una prueba."],
        recommendations: ["Completar medicion pendiente."],
        alerts: [],
        confidenceNote: "Fixture local para verificacion de contrato EF."
    )

    static let weeklyStudentEmail = WeeklyStudentEmailDraft(
        id: "fixture-email-1",
        studentId: 101,
        studentName: "Alumno Ejemplo",
        recipientEmail: "alumno@centro.test",
        audienceMode: .student,
        weekRangeDescription: "esta semana",
        subject: "Seguimiento de evaluación semanal (Alumno Ejemplo)",
        greeting: "Hola, Alumno Ejemplo:",
        evaluativeSummary: "Resumen de evaluación de prueba local para verificación de interfaz.",
        strengths: ["Participación constante en clase."],
        improvementAreas: ["Revisar entrega pendiente."],
        upcomingMilestones: ["Entrega de proyecto el viernes."],
        closing: "¡Sigue con buen trabajo!",
        fullBodyText: "Hola, Alumno Ejemplo:\n\nResumen de evaluación de prueba local.\n\n📌 Aspectos destacados:\n  • Participación constante en clase.\n\n🎯 Puntos a reforzar:\n  • Revisar entrega pendiente.\n\n¡Sigue con buen trabajo!",
        isAIGenerated: true
    )

    static var contractChecks: [String] {
        var checks: [String] = []
        checks.append(earlyWarning.confidence <= 1 ? "confidence.clamped.ok" : "confidence.clamped.failed")
        checks.append(studentInsight.recommendations.count <= 3 ? "student.recommendations.limit.ok" : "student.recommendations.limit.failed")
        checks.append(tutorMeetingSummary.actions.count <= 3 ? "tutor.actions.limit.ok" : "tutor.actions.limit.failed")
        checks.append(physicalProgressAnalysis.alerts.count <= 3 ? "physical.alerts.limit.ok" : "physical.alerts.limit.failed")
        checks.append(!weeklyStudentEmail.subject.isEmpty ? "weeklyEmail.subject.ok" : "weeklyEmail.subject.failed")
        return checks
    }
}
#endif
