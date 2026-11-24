import Foundation
import MiGestorKit

// Lógica sin vistas de «Exportar a Educamos» con pestañas de evaluación (ADR 003):
// qué pestaña corresponde a cada SA, de qué evaluación sale la nota final y qué hacer
// con la nota de un alumno al que le falta un bloque.

enum EducamosSATabMatcher {
    /// «SA2 Hockey», «SA 2 - Hockey», «S.A. 2: Hockey» → «hockey». Sin tildes ni mayúsculas.
    /// El prefijo exige número o signo detrás: «Salto» no pierde su «Sa».
    static func normalizedName(_ text: String) -> String {
        var value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: #"^s\.?\s*a\.?\s*(\d+|[-:.·])\s*[-:.·]?\s*"#, options: .regularExpression),
           range.upperBound < value.endIndex {
            value = String(value[range.upperBound...])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pestañas que pueden ser una SA: bloques y pestañas sueltas, nunca una evaluación (su
    /// media es la nota final, no la de una SA).
    static func candidateTabs(_ tabs: [NotebookTab]) -> [NotebookTab] {
        let evaluation = NotebookEvaluation.shared
        return tabs
            .filter { !evaluation.isEvaluationTab(tabs: tabs, tabId: $0.id) }
            .sorted { ($0.parentTabId ?? "", $0.order, $0.id) < ($1.parentTabId ?? "", $1.order, $1.id) }
    }

    /// Propuesta por nombre: igual tras normalizar; si no, uno contiene al otro.
    static func propose(shortName: String, tabs: [NotebookTab]) -> NotebookTab? {
        let wanted = normalizedName(shortName)
        guard !wanted.isEmpty else { return nil }
        let candidates = candidateTabs(tabs)
        return candidates.first { normalizedName($0.title) == wanted }
            ?? candidates.first { tab in
                let title = normalizedName(tab.title)
                return !title.isEmpty && (title.contains(wanted) || wanted.contains(title))
            }
    }

    /// «Hockey (1.ª Evaluación)» para un bloque; el título tal cual para una pestaña suelta.
    static func displayTitle(_ tab: NotebookTab, tabs: [NotebookTab]) -> String {
        guard let parentId = tab.parentTabId, let parent = tabs.first(where: { $0.id == parentId }) else { return tab.title }
        return "\(tab.title) (\(parent.title))"
    }
}

enum EducamosFinalGradeSource {
    /// Evaluación cuya nota va a «Nota final»: la del mismo trimestre que el Excel
    /// («1ª Evaluación» → 1.ª Evaluación); si no se reconoce, la de la pestaña abierta.
    static func evaluationTabId(tabs: [NotebookTab], excelEvaluation: String, activeTabId: String?) -> String? {
        let evaluation = NotebookEvaluation.shared
        let roots = tabs.filter { evaluation.isEvaluationTab(tabs: tabs, tabId: $0.id) }
        if let term = EvaluationClosingTerm.from(tabTitle: excelEvaluation),
           let match = roots.first(where: { EvaluationClosingTerm.from(tabTitle: $0.title) == term }) {
            return match.id
        }
        return evaluation.evaluationTabId(tabs: tabs, tabId: activeTabId)
    }
}

/// Qué se escribe en «Nota final» de un alumno al que le falta un bloque.
enum EducamosPartialGradePolicy: String, CaseIterable, Identifiable {
    /// Por defecto: no subir una nota incompleta sin querer.
    case leaveEmpty
    case exportPartial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leaveEmpty: return "Dejarla vacía"
        case .exportPartial: return "Exportar la nota parcial"
        }
    }

    private static func key(classId: Int64) -> String { "educamos.sm.partialFinalGrade.\(classId)" }

    static func load(classId: Int64, defaults: UserDefaults = .standard) -> EducamosPartialGradePolicy {
        defaults.string(forKey: key(classId: classId)).flatMap(EducamosPartialGradePolicy.init(rawValue:)) ?? .leaveEmpty
    }

    func save(classId: Int64, defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key(classId: classId))
    }
}

/// Alumno al que le falta al menos un bloque con peso.
struct EducamosPartialStudent: Identifiable, Equatable {
    let id: Int64
    let name: String
    let missingBlocks: [String]
}
