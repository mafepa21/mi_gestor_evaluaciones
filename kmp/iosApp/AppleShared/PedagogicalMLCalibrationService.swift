import Foundation
import Combine

/// Estado docente de un patrón o alerta detectada por Machine Learning.
public enum MLInsightStatus: String, Codable, CaseIterable, Sendable {
    case active = "active"
    case addressed = "addressed"
    case dismissed = "dismissed"

    public var title: String {
        switch self {
        case .active: return "Activa"
        case .addressed: return "Atendida"
        case .dismissed: return "Descartada"
        }
    }
}

/// Motivo pedagógico o contextual del descarte o resolución de una alerta.
public enum MLDismissalReason: String, Codable, CaseIterable, Sendable {
    case personalCircumstance = "personalCircumstance"
    case trackingStarted = "trackingStarted"
    case falsePositive = "falsePositive"
    case pedagogicalAgreement = "pedagogicalAgreement"
    case other = "other"

    public var title: String {
        switch self {
        case .personalCircumstance: return "Circunstancia personal / médica justificada"
        case .trackingStarted: return "Intervención o tutoría ya en curso"
        case .falsePositive: return "Evolución real adecuada (Falso positivo)"
        case .pedagogicalAgreement: return "Acuerdo de trabajo con el alumno"
        case .other: return "Otro motivo docente"
        }
    }

    public var shortBadge: String {
        switch self {
        case .personalCircumstance: return "Justificado"
        case .trackingStarted: return "En seguimiento"
        case .falsePositive: return "Revisado"
        case .pedagogicalAgreement: return "Acordado"
        case .other: return "Anotado"
        }
    }
}

/// Umbral de confianza configurable para calibrar la sensibilidad del Radar Docente.
public enum MLConfidenceThreshold: String, Codable, CaseIterable, Sendable {
    case sensitive = "sensitive"       // > 50%
    case balanced = "balanced"         // > 70% (Predeterminado)
    case conservative = "conservative" // > 85%

    public var title: String {
        switch self {
        case .sensitive: return "Sensible (>50%)"
        case .balanced: return "Equilibrado (>70%)"
        case .conservative: return "Conservador (>85%)"
        }
    }

    public var minimumConfidence: Double {
        switch self {
        case .sensitive: return 0.50
        case .balanced: return 0.70
        case .conservative: return 0.85
        }
    }

    public var description: String {
        switch self {
        case .sensitive: return "Muestra cualquier indicio temprano o sutil para máxima prevención."
        case .balanced: return "Equilibrio recomendado entre detección preventiva y precisión."
        case .conservative: return "Solo alerta ante patrones con certeza estadística alta."
        }
    }
}

/// Registro inmutable y privado de calibración docente para un alumno y patrón.
public struct MLCalibrationRecord: Codable, Hashable, Sendable {
    public let studentId: Int64
    public let classId: Int64
    public let patternType: String
    public var status: MLInsightStatus
    public var reason: MLDismissalReason?
    public var note: String?
    public let updatedAt: Date

    public init(
        studentId: Int64,
        classId: Int64,
        patternType: String,
        status: MLInsightStatus,
        reason: MLDismissalReason? = nil,
        note: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.studentId = studentId
        self.classId = classId
        self.patternType = patternType
        self.status = status
        self.reason = reason
        self.note = note
        self.updatedAt = updatedAt
    }
}

/// Servicio singleton on-device para la calibración continua y el feedback loop docente de Core ML.
/// Garantiza estricta privacidad y es seguro ante concurrencia entre hilos y la UI de SwiftUI.
public final class PedagogicalMLCalibrationService: ObservableObject, @unchecked Sendable {
    public static let shared = PedagogicalMLCalibrationService()

    private let lock = NSLock()
    private let userDefaultsKeyRecords = "pedagogical_ml_calibration_records_v1"
    private let userDefaultsKeyThreshold = "pedagogical_ml_confidence_threshold_v1"
    private let userDefaults: UserDefaults

    @Published public private(set) var threshold: MLConfidenceThreshold = .balanced
    @Published public private(set) var records: [String: MLCalibrationRecord] = [:]

    private var internalThreshold: MLConfidenceThreshold = .balanced
    private var internalRecords: [String: MLCalibrationRecord] = [:]

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        var loadedThreshold: MLConfidenceThreshold = .balanced
        if let rawThreshold = userDefaults.string(forKey: userDefaultsKeyThreshold),
           let savedThreshold = MLConfidenceThreshold(rawValue: rawThreshold) {
            loadedThreshold = savedThreshold
        }

        var loadedRecords: [String: MLCalibrationRecord] = [:]
        if let data = userDefaults.data(forKey: userDefaultsKeyRecords) {
            do {
                let decoded = try JSONDecoder().decode([String: MLCalibrationRecord].self, from: data)
                loadedRecords = decoded
            } catch {
                loadedRecords = [:]
            }
        }

        self.internalThreshold = loadedThreshold
        self.internalRecords = loadedRecords
        self.threshold = loadedThreshold
        self.records = loadedRecords
    }

    // MARK: - Clave de Registro Compuesta

    private func recordKey(classId: Int64, studentId: Int64, patternType: String) -> String {
        "\(classId)_\(studentId)_\(patternType)"
    }

    // MARK: - Consultas Seguras ante Concurrencia

    /// Indica si una señal detectada debe silenciarse u ocultarse según el umbral o el feedback docente previo.
    public func isSignalSuppressed(
        studentId: Int64,
        classId: Int64,
        patternType: EducationalPatternType,
        confidence: Double
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // 1. Filtrado por umbral de confianza configurado
        if confidence < internalThreshold.minimumConfidence {
            return true
        }

        // 2. Filtrado por estado de calibración previo
        let key = recordKey(classId: classId, studentId: studentId, patternType: patternType.rawValue)
        guard let record = internalRecords[key] else {
            return false
        }

        // Si fue marcada como atendida o descartada, se suprime de las alertas activas
        return record.status == .addressed || record.status == .dismissed
    }

    /// Obtiene el registro de calibración docente si existe.
    public func record(for studentId: Int64, classId: Int64, patternType: EducationalPatternType) -> MLCalibrationRecord? {
        lock.lock()
        defer { lock.unlock() }
        let key = recordKey(classId: classId, studentId: studentId, patternType: patternType.rawValue)
        return internalRecords[key]
    }

    // MARK: - Mutaciones con Persistencia Local y Despacho a MainActor

    /// Actualiza el estado de una alerta (atendida o descartada con motivo).
    public func setStatus(
        studentId: Int64,
        classId: Int64,
        patternType: EducationalPatternType,
        status: MLInsightStatus,
        reason: MLDismissalReason? = nil,
        note: String? = nil
    ) {
        let key = recordKey(classId: classId, studentId: studentId, patternType: patternType.rawValue)
        let record = MLCalibrationRecord(
            studentId: studentId,
            classId: classId,
            patternType: patternType.rawValue,
            status: status,
            reason: reason,
            note: note,
            updatedAt: Date()
        )

        lock.lock()
        internalRecords[key] = record
        let recordsToSave = internalRecords
        lock.unlock()

        persistRecords(recordsToSave)

        if Thread.isMainThread {
            self.records = recordsToSave
        } else {
            DispatchQueue.main.async {
                self.records = recordsToSave
            }
        }
    }

    /// Reactiva una alerta previa eliminando el descarte.
    public func reactivateSignal(
        studentId: Int64,
        classId: Int64,
        patternType: EducationalPatternType
    ) {
        let key = recordKey(classId: classId, studentId: studentId, patternType: patternType.rawValue)

        lock.lock()
        internalRecords.removeValue(forKey: key)
        let recordsToSave = internalRecords
        lock.unlock()

        persistRecords(recordsToSave)

        if Thread.isMainThread {
            self.records = recordsToSave
        } else {
            DispatchQueue.main.async {
                self.records = recordsToSave
            }
        }
    }

    /// Ajusta la sensibilidad del motor en el Radar Docente.
    public func setConfidenceThreshold(_ newThreshold: MLConfidenceThreshold) {
        lock.lock()
        internalThreshold = newThreshold
        lock.unlock()

        userDefaults.set(newThreshold.rawValue, forKey: userDefaultsKeyThreshold)

        if Thread.isMainThread {
            self.threshold = newThreshold
        } else {
            DispatchQueue.main.async {
                self.threshold = newThreshold
            }
        }
    }

    // MARK: - Persistencia

    private func persistRecords(_ recordsToSave: [String: MLCalibrationRecord]) {
        do {
            let data = try JSONEncoder().encode(recordsToSave)
            userDefaults.set(data, forKey: userDefaultsKeyRecords)
        } catch {
            // Manejo silencioso defensivo
        }
    }
}
