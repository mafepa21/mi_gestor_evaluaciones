import Foundation
import MiGestorKit
import Combine

struct StructuredInstrumentEvaluationModel: Identifiable {
    let id: String
    let classId: Int64
    let studentId: Int64
    let columnId: String
    let title: String
    let kind: NotebookInstrumentTemplateKind
    let criterionLabel: String?
    let criterionStatements: [CriterionStatement]
    var items: [StructuredInstrumentEvaluationItem]
}

struct StructuredInstrumentEvaluationItem: Identifiable {
    let id: String
    /// Clave de la plantilla (`rub_<n>`, `open_<n>`, `obs_s<N>_i<M>`, `chkp_<n>`…). Es la que
    /// distingue las dos partes de una autoevaluación/coevaluación al pintarla.
    let key: String
    let title: String
    let type: NotebookInstrumentItemType
    let options: [String]
    /// Texto de ayuda de la plantilla. En los instrumentos de autoevaluación/coevaluación lleva
    /// los cuatro descriptores del indicador, que son los que explican qué significa cada nivel.
    let helpText: String?
    var textValue: String
    var boolValue: Bool
    var numberValue: String
}

enum IosFormatting {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func decimal(_ value: Double?) -> String {
        guard let value else { return "--" }
        return decimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func decimal(_ value: KotlinDouble?) -> String {
        decimal(value?.doubleValue)
    }

    static func decimal(_ value: NSNumber?) -> String {
        decimal(value?.doubleValue)
    }

    static func decimal(from value: Any?) -> String {
        guard let value else { return "--" }
        if let value = value as? Double {
            return decimal(value)
        }
        if let value = value as? Float {
            return decimal(Double(value))
        }
        if let value = value as? NSNumber {
            return decimal(value)
        }
        if let value = value as? KotlinDouble {
            return decimal(value)
        }
        return "--"
    }

    static func scoreOutOfTen(from value: Any?) -> String {
        let text = decimal(from: value)
        return text == "--" ? "Sin dato" : "\(text) / 10"
    }
}

struct PlannerAssessmentInstrument: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case evaluation
        case rubric
    }

    let kind: Kind
    let rawId: Int64
    let title: String
    let subtitle: String
    let classId: Int64
    let teachingUnitId: Int64?
    let evaluationId: Int64?
    let rubricId: Int64?
    let resolvedEvaluationId: Int64?
    let groupTitle: String
    let isRecommendedForCurrentSA: Bool

    var id: String { "\(kind.rawValue):\(rawId)" }
}

struct PlannerSessionSaveResult {
    let sessionId: Int64
    let teachingUnitId: Int64
    let teachingUnitName: String
    let evaluationSummary: String
    let linkedAssessmentIdsCsv: String
}

struct NotebookCreatedColumnResult {
    let column: NotebookColumnDefinition
    let category: NotebookColumnCategory?
}

struct RubricEvaluationAdvanceSummary {
    let evaluatedCount: Int
    let remainingCount: Int
}

enum RubricEvaluationAdvanceResult {
    case openedNext(studentId: Int64, remainingCount: Int)
    case completed(RubricEvaluationAdvanceSummary)
    case closed
}

@MainActor
final class RubricEvaluationCoordinator: ObservableObject {
    struct Context {
        let columnId: String
        let rubricId: Int64
        let classId: Int64
        let evaluationId: Int64
        let studentIds: [Int64]
        var currentStudentId: Int64
    }

    @Published private(set) var context: Context?
    @Published private(set) var lastSummary: RubricEvaluationAdvanceSummary?

    var isActive: Bool { context != nil }
    var currentStudentId: Int64? { context?.currentStudentId }

    func start(
        columnId: String,
        rubricId: Int64,
        classId: Int64,
        evaluationId: Int64,
        studentIds: [Int64],
        currentStudentId: Int64
    ) {
        let orderedIds = normalizedStudentIds(studentIds, currentStudentId: currentStudentId)
        context = Context(
            columnId: columnId,
            rubricId: rubricId,
            classId: classId,
            evaluationId: evaluationId,
            studentIds: orderedIds,
            currentStudentId: currentStudentId
        )
        lastSummary = nil
    }

    func advance(visibleStudentIds: [Int64]? = nil) -> Int64? {
        guard var context else { return nil }
        let orderedIds = normalizedStudentIds(
            visibleStudentIds?.filter { context.studentIds.contains($0) } ?? context.studentIds,
            currentStudentId: context.currentStudentId
        )
        guard let currentIndex = orderedIds.firstIndex(of: context.currentStudentId) else {
            finish(evaluatedCount: completedCount(in: orderedIds, currentStudentId: context.currentStudentId), remainingCount: 0)
            return nil
        }
        let remainingIds = orderedIds.dropFirst(currentIndex + 1)
        guard let nextStudentId = remainingIds.first else {
            finish(evaluatedCount: orderedIds.count, remainingCount: 0)
            return nil
        }
        context.currentStudentId = nextStudentId
        self.context = context
        lastSummary = RubricEvaluationAdvanceSummary(
            evaluatedCount: currentIndex + 1,
            remainingCount: remainingIds.count
        )
        return nextStudentId
    }

    func finish(evaluatedCount: Int? = nil, remainingCount: Int = 0) {
        let completed = evaluatedCount ?? context?.studentIds.count ?? 0
        lastSummary = RubricEvaluationAdvanceSummary(evaluatedCount: completed, remainingCount: remainingCount)
        context = nil
    }

    func reset() {
        context = nil
        lastSummary = nil
    }

    private func normalizedStudentIds(_ studentIds: [Int64], currentStudentId: Int64) -> [Int64] {
        var seen = Set<Int64>()
        var ordered = studentIds.filter { seen.insert($0).inserted }
        if !ordered.contains(currentStudentId) {
            ordered.insert(currentStudentId, at: 0)
        }
        return ordered
    }

    private func completedCount(in orderedIds: [Int64], currentStudentId: Int64) -> Int {
        guard let index = orderedIds.firstIndex(of: currentStudentId) else { return 0 }
        return index + 1
    }
}
