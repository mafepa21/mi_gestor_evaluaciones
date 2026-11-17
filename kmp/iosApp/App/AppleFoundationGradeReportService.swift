import Foundation
import MiGestorKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Textos del informe de notas que no son números: lo que el alumno hace bien
/// y lo que puede mejorar. Siempre editables por el docente antes de enviar.
struct GradeReportNarrative: Equatable, Sendable {
    var strengths: String
    var improvements: String
    /// true si lo redactó la IA de Apple; false si es la plantilla.
    var isAI: Bool
}

/// Redacta los textos del informe de notas con la IA local de Apple.
/// La IA solo recibe datos ya calculados (notas, niveles, descriptores) y nunca
/// calcula: si no está disponible o falla, se usa una plantilla.
@MainActor
final class AppleFoundationGradeReportService {
    #if canImport(FoundationModels)
    private var sessionStorage: Any?
    #endif

    var isAIAvailable: Bool {
        AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available
    }

    func prewarm() {
        guard isAIAvailable else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            _ = consumeSession()
        }
        #endif
    }

    func narrative(for report: StudentGradeReport, subjectName: String) async -> GradeReportNarrative {
        guard report.hasGrades, isAIAvailable else {
            return Self.templateNarrative(for: report)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                // Sesión nueva por alumno: el contexto de uno no debe mezclarse con el siguiente.
                sessionStorage = nil
                let response = try await consumeSession().respond(
                    to: Self.prompt(for: report, subjectName: subjectName),
                    generating: GeneratedGradeReportNarrative.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.3)
                )
                let strengths = Self.bulletText(response.content.strengths)
                let improvements = Self.bulletText(response.content.improvements)
                guard !strengths.isEmpty, !improvements.isEmpty else {
                    return Self.templateNarrative(for: report)
                }
                return GradeReportNarrative(strengths: strengths, improvements: improvements, isAI: true)
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return Self.templateNarrative(for: report)
            }
        }
        #endif

        return Self.templateNarrative(for: report)
    }

    // MARK: - Plantilla

    nonisolated static func templateNarrative(for report: StudentGradeReport) -> GradeReportNarrative {
        var strengths: [String] = []
        var improvements: [String] = []

        if let best = report.bestInstrument {
            strengths.append("Tu mejor resultado ha sido en \(best.title) (\(GradeReportFormat.grade(best.value))).")
        }
        let topCriteria = report.rubrics
            .flatMap { $0.criteria }
            .filter { $0.levelCount > 1 && $0.levelPosition == $0.levelCount }
            .prefix(2)
        for criterion in topCriteria {
            strengths.append("Has llegado al nivel más alto en «\(criterion.name)».")
        }

        if let weakest = report.weakestInstrument, report.instruments.count > 1, weakest.columnId != report.bestInstrument?.columnId {
            improvements.append("Tu resultado más bajo ha sido en \(weakest.title) (\(GradeReportFormat.grade(weakest.value))). Repasa lo trabajado ahí.")
        }
        if !report.pendingTitles.isEmpty {
            improvements.append("Aún falta tu nota en: \(report.pendingTitles.joined(separator: ", ")).")
        }
        if strengths.isEmpty {
            strengths.append("Sigue trabajando con constancia en clase.")
        }
        if improvements.isEmpty {
            improvements.append("Mantén este nivel de trabajo en la próxima evaluación.")
        }
        return GradeReportNarrative(
            strengths: bulletText(strengths),
            improvements: bulletText(improvements),
            isAI: false
        )
    }

    // MARK: - Prompt

    private static func prompt(for report: StudentGradeReport, subjectName: String) -> String {
        var lines: [String] = []
        lines.append("Asignatura: \(subjectName)")
        lines.append("Alumno: \(report.firstName)")
        if let final = report.finalGrade?.doubleValue {
            lines.append("Nota final (ya calculada, no la cambies): \(GradeReportFormat.grade(final)) · \(report.finalLevel?.label ?? "")")
        }
        lines.append("Instrumentos:")
        for instrument in report.instruments {
            lines.append("- \(instrument.title): \(GradeReportFormat.grade(instrument.value)) (\(instrument.level.label)), peso \(GradeReportFormat.percent(instrument.weightPercent))")
        }
        for rubric in report.rubrics {
            lines.append("Rúbrica \(rubric.title):")
            for criterion in rubric.criteria {
                var line = "- \(criterion.name): \(criterion.levelName) (nivel \(criterion.levelPosition) de \(criterion.levelCount))"
                if let description = criterion.levelDescription { line += ". \(description)" }
                lines.append(line)
            }
        }
        if !report.pendingTitles.isEmpty {
            lines.append("Sin nota todavía: \(report.pendingTitles.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func bulletText(_ items: [String]) -> String {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { "• \($0.hasPrefix("•") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0)" }
            .joined(separator: "\n")
    }

    // MARK: - Sesión

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func consumeSession() -> LanguageModelSession {
        if let session = sessionStorage as? LanguageModelSession { return session }
        let session = LanguageModelSession(
            instructions: """
            Escribes la parte de comentarios de un informe de notas que un docente envía a su alumno de secundaria.
            Las notas y niveles ya están calculados: no los cambies, no calcules nada y no inventes datos.
            Habla de tú al alumno, en español de España, con frases cortas, claras y amables.
            Basa cada frase en un instrumento o criterio concreto de los datos.
            Da entre 1 y 3 frases en cada lista. No repitas la nota final.
            """
        )
        sessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedGradeReportNarrative {
        @Guide(description: "Entre 1 y 3 frases sobre lo que el alumno hace bien, cada una ligada a un instrumento o criterio.")
        let strengths: [String]
        @Guide(description: "Entre 1 y 3 frases con una mejora concreta y alcanzable, cada una ligada a un instrumento o criterio.")
        let improvements: [String]
    }
    #endif
}

/// Formato de números del informe: coma decimal y un decimal.
enum GradeReportFormat {
    static func grade(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) %"
        }
        return "\(grade(rounded)) %"
    }

    /// «6,5 × 30 % + 8,0 × 25 % = 7,5». Coincide con la Media porque usa sus mismos datos.
    static func calculation(for report: StudentGradeReport) -> String? {
        guard let final = report.finalGrade?.doubleValue, !report.instruments.isEmpty else { return nil }
        if report.instruments.count == 1 {
            return "Tu nota sale de un solo instrumento: \(report.instruments[0].title)."
        }
        let parts = report.instruments.map { "\(grade($0.value)) × \(percent($0.weightPercent))" }
        return "Cada instrumento cuenta según su peso. \(parts.joined(separator: " + ")) = \(grade(final))."
    }
}
