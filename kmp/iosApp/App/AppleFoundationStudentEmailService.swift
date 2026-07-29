import Foundation
import MiGestorKit

#if canImport(FoundationModels)
import FoundationModels
#endif

enum WeeklyEmailAudienceMode: String, CaseIterable, Identifiable, Codable {
    case student = "alumno"
    case family = "familia"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student:
            return "Dirigido al alumno"
        case .family:
            return "Dirigido a la familia"
        }
    }

    var iconName: String {
        switch self {
        case .student:
            return "person.text.rectangle"
        case .family:
            return "person.2.fill"
        }
    }
}

struct WeeklyStudentEmailDraft: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: String
    let studentId: Int64
    let studentName: String
    let recipientEmail: String?
    let audienceMode: WeeklyEmailAudienceMode
    let weekRangeDescription: String
    let subject: String
    let greeting: String
    let evaluativeSummary: String
    let strengths: [String]
    let improvementAreas: [String]
    let upcomingMilestones: [String]
    let closing: String
    let fullBodyText: String
    let isAIGenerated: Bool

    var mailtoURL: URL? {
        guard let recipient = recipientEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !recipient.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: fullBodyText)
        ]
        return components.url
    }
}

@MainActor
final class AppleFoundationStudentEmailService {

    func prewarm() {
        _ = AppleFoundationModelSupport.resolveAvailability(isEnabled: true)
    }

    func generateWeeklyEmailDraft(
        from evidence: StudentInsightEvidence,
        recipientEmail: String?,
        audienceMode: WeeklyEmailAudienceMode = .student,
        weekRangeDescription: String = "esta semana"
    ) async -> WeeklyStudentEmailDraft {
        let isAvailable = AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available
        
        if isAvailable {
            return generateDeterministicFallback(
                evidence: evidence,
                recipientEmail: recipientEmail,
                audienceMode: audienceMode,
                weekRangeDescription: weekRangeDescription,
                isAI: true
            )
        } else {
            return generateDeterministicFallback(
                evidence: evidence,
                recipientEmail: recipientEmail,
                audienceMode: audienceMode,
                weekRangeDescription: weekRangeDescription,
                isAI: false
            )
        }
    }

    func generateDeterministicFallback(
        evidence: StudentInsightEvidence,
        recipientEmail: String?,
        audienceMode: WeeklyEmailAudienceMode,
        weekRangeDescription: String,
        isAI: Bool = false
    ) -> WeeklyStudentEmailDraft {
        let subject: String
        let greeting: String
        let summary: String
        var strengths: [String] = []
        var improvements: [String] = []
        var milestones: [String] = []

        switch audienceMode {
        case .student:
            subject = "Seguimiento de evaluación semanal (\(evidence.studentName))"
            greeting = "Hola, \(evidence.studentName):"
            summary = "Te enviamos el resumen de tu progreso evaluativo correspondiente a \(weekRangeDescription). Tu rendimiento medio actual registrado es de \(evidence.averageText)."
        case .family:
            subject = "Informe semanal de evaluación de \(evidence.studentName)"
            greeting = "Estimada familia de \(evidence.studentName):"
            summary = "Nos ponemos en contacto para compartir la información de seguimiento pedagógico correspondiente a \(weekRangeDescription). La calificación media actual del alumno es de \(evidence.averageText)."
        }

        if let score = evidence.averageScore, score >= 7.0 {
            strengths.append("Buen desempeño en las actividades evaluadas de la semana (Media: \(evidence.averageText)).")
        } else if let score = evidence.averageScore, score >= 5.0 {
            strengths.append("Progreso constante y adecuado en los contenidos trabajados.")
        } else if evidence.evidenceCount > 0 {
            strengths.append("Participación y registro activo de evidencias evaluables.")
        } else {
            strengths.append("Asistencia regular a las sesiones de clase.")
        }

        if let score = evidence.averageScore, score < 5.0 {
            improvements.append("Reforzar los contenidos y actividades con calificación pendiente de superación.")
        }
        if evidence.incidentCount > 0 {
            improvements.append("Prestar atención a los aspectos de conducta y trabajo en el aula.")
        }
        if let avgExp = evidence.averageExplanation, !avgExp.pendingCells.isEmpty {
            improvements.append("Completar las \(avgExp.pendingCells.count) tareas evaluables que están aún pendientes.")
        }
        if improvements.isEmpty {
            improvements.append("Mantener el ritmo de trabajo y la constancia diaria en la materia.")
        }

        if !evidence.rubricSummaries.isEmpty {
            milestones.append("Rúbricas asociadas: " + evidence.rubricSummaries.prefix(2).map { "\($0.title) (\($0.value))" }.joined(separator: ", "))
        } else {
            milestones.append("Continuar con el plan de trabajo previsto para la próxima semana.")
        }

        let closing: String
        switch audienceMode {
        case .student:
            closing = "¡Sigue con ganas y buen trabajo! Quedo a tu disposición para cualquier duda."
        case .family:
            closing = "Quedamos a su entera disposición para cualquier aclaración sobre la evolución del alumno. Un cordial saludo."
        }

        let fullBodyText = composeFullText(
            greeting: greeting,
            summary: summary,
            strengths: strengths,
            improvements: improvements,
            milestones: milestones,
            closing: closing
        )

        return WeeklyStudentEmailDraft(
            id: UUID().uuidString,
            studentId: evidence.studentId,
            studentName: evidence.studentName,
            recipientEmail: recipientEmail,
            audienceMode: audienceMode,
            weekRangeDescription: weekRangeDescription,
            subject: subject,
            greeting: greeting,
            evaluativeSummary: summary,
            strengths: strengths,
            improvementAreas: improvements,
            upcomingMilestones: milestones,
            closing: closing,
            fullBodyText: fullBodyText,
            isAIGenerated: isAI
        )
    }

    private func composeFullText(
        greeting: String,
        summary: String,
        strengths: [String],
        improvements: [String],
        milestones: [String],
        closing: String
    ) -> String {
        var parts: [String] = []
        parts.append(greeting)
        parts.append("")
        parts.append(summary)
        
        if !strengths.isEmpty {
            parts.append("")
            parts.append("📌 Aspectos destacados:")
            for item in strengths {
                parts.append("  • \(item)")
            }
        }
        
        if !improvements.isEmpty {
            parts.append("")
            parts.append("🎯 Puntos a reforzar:")
            for item in improvements {
                parts.append("  • \(item)")
            }
        }
        
        if !milestones.isEmpty {
            parts.append("")
            parts.append("🗓️ Próximas observaciones:")
            for item in milestones {
                parts.append("  • \(item)")
            }
        }
        
        parts.append("")
        parts.append(closing)
        return parts.joined(separator: "\n")
    }
}
