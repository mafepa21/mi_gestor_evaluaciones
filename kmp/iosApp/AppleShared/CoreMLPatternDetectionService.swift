import Foundation
import CoreML

public enum EducationalPatternType: String, Codable, CaseIterable, Sendable {
    case steady = "steady"
    case silentDisengagement = "silent_disengagement"
    case bottleneckRisk = "bottleneck_risk"
    case evaluationAnomaly = "evaluation_anomaly"

    public var displayName: String {
        switch self {
        case .steady:
            return "Evolución favorable y estable"
        case .silentDisengagement:
            return "Desenganche silencioso"
        case .bottleneckRisk:
            return "Criterio cuello de botella"
        case .evaluationAnomaly:
            return "Anomalía de calificación"
        }
    }

    public var badgeTitle: String {
        switch self {
        case .steady:
            return "Evolución estable"
        case .silentDisengagement:
            return "Desenganche sutil"
        case .bottleneckRisk:
            return "Riesgo cuello de botella"
        case .evaluationAnomaly:
            return "Desviación atípica"
        }
    }

    public var systemImage: String {
        switch self {
        case .steady:
            return "checkmark.seal.fill"
        case .silentDisengagement:
            return "arrow.down.right.circle.fill"
        case .bottleneckRisk:
            return "exclamationmark.triangle.fill"
        case .evaluationAnomaly:
            return "waveform.path.ecg"
        }
    }

    public var isRisk: Bool {
        self != .steady
    }
}

public struct EducationalPatternSignal: Codable, Hashable, Sendable {
    public let patternType: EducationalPatternType
    public let confidence: Double
    public let summary: String
    public let keyFactors: [String]
    public let suggestedPreventiveAction: String
    public let isActionableRisk: Bool

    public init(
        patternType: EducationalPatternType,
        confidence: Double,
        summary: String,
        keyFactors: [String],
        suggestedPreventiveAction: String,
        isActionableRisk: Bool
    ) {
        self.patternType = patternType
        self.confidence = confidence
        self.summary = summary
        self.keyFactors = keyFactors
        self.suggestedPreventiveAction = suggestedPreventiveAction
        self.isActionableRisk = isActionableRisk
    }
}

public struct StudentFeatureVector: Sendable, Hashable {
    public let averageGrade: Double
    public let gradeDelta: Double
    public let attendanceRate: Double
    public let evaluableDayAbsenceRatio: Double
    public let pendingTaskRatio: Double
    public let rubricVariance: Double
    public let incidentCount: Double

    public init(
        averageGrade: Double,
        gradeDelta: Double,
        attendanceRate: Double,
        evaluableDayAbsenceRatio: Double,
        pendingTaskRatio: Double,
        rubricVariance: Double,
        incidentCount: Double
    ) {
        self.averageGrade = averageGrade
        self.gradeDelta = gradeDelta
        self.attendanceRate = attendanceRate
        self.evaluableDayAbsenceRatio = evaluableDayAbsenceRatio
        self.pendingTaskRatio = pendingTaskRatio
        self.rubricVariance = rubricVariance
        self.incidentCount = incidentCount
    }
}

public final class CoreMLPatternDetectionService: @unchecked Sendable {
    public static let shared = CoreMLPatternDetectionService()

    private let classifier: EducationalPatternsClassifier?

    private init() {
        let config = MLModelConfiguration()
        if let instance = try? EducationalPatternsClassifier(configuration: config) {
            self.classifier = instance
        } else if let modelURL = Bundle.main.url(forResource: "EducationalPatternsClassifier", withExtension: "mlmodelc"),
                  let model = try? MLModel(contentsOf: modelURL, configuration: config) {
            self.classifier = EducationalPatternsClassifier(model: model)
        } else {
            self.classifier = nil
        }
    }

    public func predict(vector: StudentFeatureVector) -> EducationalPatternSignal {
        if let classifier {
            do {
                let input = EducationalPatternsClassifierInput(
                    averageGrade: vector.averageGrade,
                    gradeDelta: vector.gradeDelta,
                    attendanceRate: vector.attendanceRate,
                    evaluableDayAbsenceRatio: vector.evaluableDayAbsenceRatio,
                    pendingTaskRatio: vector.pendingTaskRatio,
                    rubricVariance: vector.rubricVariance,
                    incidentCount: vector.incidentCount
                )
                let output = try classifier.prediction(input: input)
                let rawType = output.patternType
                let probabilities = output.patternTypeProbability
                let patternType = EducationalPatternType(rawValue: rawType) ?? .steady
                let confidence = probabilities[rawType] ?? 0.85

                return buildSignal(from: patternType, confidence: confidence, vector: vector)
            } catch {
                return fallbackDeterministicRule(vector: vector)
            }
        } else {
            return fallbackDeterministicRule(vector: vector)
        }
    }

    private func buildSignal(from type: EducationalPatternType, confidence: Double, vector: StudentFeatureVector) -> EducationalPatternSignal {
        var factors: [String] = []

        switch type {
        case .silentDisengagement:
            if vector.evaluableDayAbsenceRatio > 0.20 {
                factors.append("Faltas concentradas en sesiones con rúbricas o tareas (\(Int(vector.evaluableDayAbsenceRatio * 100))%)")
            }
            if vector.pendingTaskRatio > 0.15 {
                factors.append("Acumulación de tareas o criterios pendientes (\(Int(vector.pendingTaskRatio * 100))%)")
            }
            if vector.gradeDelta < -0.4 {
                factors.append(String(format: "Pérdida progresiva de rendimiento (%.1f ptos vs. evaluaciones previas)", vector.gradeDelta))
            }
            if factors.isEmpty {
                factors.append("Desaceleración sutil respecto al ritmo habitual del grupo")
            }

            return EducationalPatternSignal(
                patternType: .silentDisengagement,
                confidence: confidence,
                summary: "La media actual parece aprobada, pero concurren faltas en días evaluables y retraso en entregas.",
                keyFactors: factors,
                suggestedPreventiveAction: "Acordar una meta corta y tangible en la próxima sesión práctica para reactivar el compromiso.",
                isActionableRisk: true
            )

        case .bottleneckRisk:
            if vector.rubricVariance > 1.8 {
                factors.append(String(format: "Alta dispersión entre criterios evaluados (varianza %.1f)", vector.rubricVariance))
            }
            if vector.averageGrade < 5.8 {
                factors.append(String(format: "Base competencial ajustada (media %.1f)", vector.averageGrade))
            }
            factors.append("Dificultad localizada en un saber básico o criterio procedimental inicial")

            return EducationalPatternSignal(
                patternType: .bottleneckRisk,
                confidence: confidence,
                summary: "Un criterio inicial fundamental muestra bajo dominio, lo que puede bloquear situaciones de aprendizaje siguientes.",
                keyFactors: factors,
                suggestedPreventiveAction: "Reforzar individualmente la consigna del criterio cuello de botella antes de avanzar en la unidad.",
                isActionableRisk: true
            )

        case .evaluationAnomaly:
            factors.append(String(format: "Discrepancia acusada en la calificación (salto/caída de %.1f ptos)", vector.gradeDelta))
            factors.append(String(format: "Asistencia normal (%.0f%%) sin incidencias que justifiquen el cambio", vector.attendanceRate))
            if vector.rubricVariance > 2.5 {
                factors.append(String(format: "Dispersión atípica entre instrumentos (varianza %.1f)", vector.rubricVariance))
            }

            return EducationalPatternSignal(
                patternType: .evaluationAnomaly,
                confidence: confidence,
                summary: "Desviación matemática acusada respecto a la curva habitual del alumno, sin relación con faltas ni retrasos.",
                keyFactors: factors,
                suggestedPreventiveAction: "Revisar los pesos del instrumento o la calibración de la rúbrica para descartar inconsistencias de registro.",
                isActionableRisk: true
            )

        case .steady:
            factors.append(String(format: "Asistencia consolidada (%.0f%%)", vector.attendanceRate))
            factors.append(String(format: "Rendimiento regular (media %.1f)", vector.averageGrade))
            if vector.gradeDelta >= 0.0 {
                factors.append("Tendencia positiva o estable")
            }

            return EducationalPatternSignal(
                patternType: .steady,
                confidence: confidence,
                summary: "Progresión académica regular y coherente con el histórico.",
                keyFactors: factors,
                suggestedPreventiveAction: "Mantener el seguimiento habitual.",
                isActionableRisk: false
            )
        }
    }

    private func fallbackDeterministicRule(vector: StudentFeatureVector) -> EducationalPatternSignal {
        if vector.averageGrade >= 5.0 && vector.averageGrade <= 6.8 &&
           (vector.evaluableDayAbsenceRatio > 0.22 || vector.pendingTaskRatio > 0.18) &&
           vector.gradeDelta < -0.5 {
            return buildSignal(from: .silentDisengagement, confidence: 0.88, vector: vector)
        } else if vector.rubricVariance > 2.0 && vector.averageGrade < 6.0 {
            return buildSignal(from: .bottleneckRisk, confidence: 0.84, vector: vector)
        } else if abs(vector.gradeDelta) > 1.8 && vector.attendanceRate >= 90.0 && vector.rubricVariance > 2.4 {
            return buildSignal(from: .evaluationAnomaly, confidence: 0.82, vector: vector)
        } else {
            return buildSignal(from: .steady, confidence: 0.90, vector: vector)
        }
    }
}
