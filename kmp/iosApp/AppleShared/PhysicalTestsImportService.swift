import Foundation
import CryptoKit

struct PhysicalTestsImportDraft: Identifiable {
    let id = UUID()
    let sourceFileName: String
    let sourceURL: URL
    let sha256: String
    let sizeBytes: Int64
    let purpose: String
    let learningSituation: PhysicalTestsImportLearningSituation
    let assignmentTemplate: PhysicalTestsImportAssignmentTemplate
    var testDefinitions: [PhysicalTestsImportDefinition]
    var referenceScales: [PhysicalTestsImportScale]
    let calibrationRequiredTestIds: [String]
    var warnings: [String]
    let sourceNotes: [String]

    var courseNumber: Int? {
        let digits = learningSituation.course.range(of: "\\d+", options: .regularExpression)
        return digits.flatMap { Int(learningSituation.course[$0]) }
    }

    var scoreIsDisabled: Bool {
        !assignmentTemplate.recordScore && !assignmentTemplate.scoreColumnMode
    }
}

struct PhysicalTestsImportLearningSituation: Codable {
    let number: Int
    let course: String
    let subject: String
}

struct PhysicalTestsImportAssignmentTemplate: Codable {
    let batteryId: String
    let batteryName: String
    let termLabel: String
    let rawColumnMode: Bool
    let scoreColumnMode: Bool
    let recordScore: Bool
    let countsTowardAverage: Bool
    let showRankings: Bool
}

struct PhysicalTestsImportDefinition: Codable, Identifiable {
    let id: String
    var name: String
    let capacity: String
    let measurementKind: String
    let unit: String
    let higherIsBetter: Bool
    let attempts: Int
    let resultMode: String
    let protocolText: String
    let plausibleMinimum: Double?
    let plausibleMaximum: Double?
    let decimals: Int

    enum CodingKeys: String, CodingKey {
        case id, name, capacity, measurementKind, unit, higherIsBetter, attempts, resultMode
        case protocolText = "protocol"
        case plausibleMinimum, plausibleMaximum, decimals
    }
}

struct PhysicalTestsImportScale: Codable, Identifiable {
    let id: String
    let testId: String
    var name: String
    let course: Int?
    let ageFrom: Int?
    let ageTo: Int?
    let sex: String?
    let direction: String
    let diagnosticReferenceOnly: Bool
    let scoring: PhysicalTestsImportScoring?
    let ranges: [PhysicalTestsImportScaleRange]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        testId = try container.decode(String.self, forKey: .testId)
        name = try container.decode(String.self, forKey: .name)
        course = try container.decodeIfPresent(Int.self, forKey: .course)
        ageFrom = try container.decodeIfPresent(Int.self, forKey: .ageFrom)
        ageTo = try container.decodeIfPresent(Int.self, forKey: .ageTo)
        sex = try container.decodeIfPresent(String.self, forKey: .sex)
        direction = try container.decode(String.self, forKey: .direction)
        diagnosticReferenceOnly = try container.decodeIfPresent(Bool.self, forKey: .diagnosticReferenceOnly) ?? false
        scoring = try container.decodeIfPresent(PhysicalTestsImportScoring.self, forKey: .scoring)
        ranges = try container.decodeIfPresent([PhysicalTestsImportScaleRange].self, forKey: .ranges) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, testId, name, course, ageFrom, ageTo, sex, direction
        case diagnosticReferenceOnly, scoring, ranges
    }
}

struct PhysicalTestsImportScoring: Codable {
    let mode: String
    let roundTo: Double?
    let points: [PhysicalTestsImportScorePoint]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(String.self, forKey: .mode)
        roundTo = try container.decodeIfPresent(Double.self, forKey: .roundTo)
        points = try container.decodeIfPresent([PhysicalTestsImportScorePoint].self, forKey: .points) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case mode, roundTo, points
    }
}

struct PhysicalTestsImportScorePoint: Codable {
    let id: String?
    let value: Double
    let score: Double
    let label: String?
    let sortOrder: Int?
}

struct PhysicalTestsImportScaleRange: Codable, Identifiable {
    let id: String
    let minValue: Double?
    let maxValue: Double?
    let score: Double
    let label: String?
    let sortOrder: Int
}

enum PhysicalTestsImportError: LocalizedError {
    case unreadableManifest
    case invalidManifest([String])

    var errorDescription: String? {
        switch self {
        case .unreadableManifest:
            return "No se ha podido leer el manifiesto JSON de pruebas físicas."
        case .invalidManifest(let issues):
            return "El manifiesto de pruebas físicas no es válido:\n\n" + issues.map { "• \($0)" }.joined(separator: "\n")
        }
    }
}

struct PhysicalTestsImportService {
    func preview(from url: URL) throws -> PhysicalTestsImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PhysicalTestsImportError.unreadableManifest
        }
        return try preview(from: url, data: data)
    }

    func preview(from url: URL, data: Data) throws -> PhysicalTestsImportDraft {
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw PhysicalTestsImportError.unreadableManifest
        }

        var issues: [String] = []
        var warnings = manifest.warnings
        let validCapacities = Set(["RESISTANCE", "STRENGTH", "SPEED", "FLEXIBILITY", "COORDINATION", "AGILITY", "CUSTOM"])
        let validMeasurements = Set(["TIME", "DISTANCE", "REPETITIONS", "LEVEL", "SCORE"])
        let validResultModes = Set(["BEST", "AVERAGE", "LAST"])
        let validDirections = Set(["HIGHER_IS_BETTER", "LOWER_IS_BETTER"])
        let validScoringModes = Set(["STEP", "LINEAR"])
        let definitionIds = Set(manifest.testDefinitions.map(\.id))

        if manifest.format != "mi_gestor.physical-tests-import" {
            issues.append("El campo format no coincide con mi_gestor.physical-tests-import.")
        }
        if manifest.version != 1 && manifest.version != 2 {
            issues.append("Solo se admiten las versiones 1 y 2 del manifiesto.")
        }
        if manifest.purpose != "INITIAL_DIAGNOSTIC" {
            issues.append("El propósito \(manifest.purpose) no está soportado; se esperaba INITIAL_DIAGNOSTIC.")
        }
        if manifest.learningSituation.course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("learningSituation.course es obligatorio.")
        }
        if manifest.learningSituation.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("learningSituation.subject es obligatorio.")
        }
        if manifest.assignmentTemplate.batteryId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("assignmentTemplate.batteryId es obligatorio.")
        }
        if manifest.assignmentTemplate.batteryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("assignmentTemplate.batteryName es obligatorio.")
        }
        if !manifest.assignmentTemplate.recordScore && manifest.assignmentTemplate.scoreColumnMode {
            issues.append("scoreColumnMode debe ser false cuando recordScore es false.")
        }
        if manifest.testDefinitions.isEmpty {
            issues.append("Debe existir al menos una prueba en testDefinitions.")
        }
        if definitionIds.count != manifest.testDefinitions.count {
            issues.append("Los identificadores de testDefinitions deben ser únicos.")
        }

        for definition in manifest.testDefinitions {
            let label = definition.name.isEmpty ? definition.id : definition.name
            if definition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Hay una prueba sin id.")
            }
            if definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(definition.id): el nombre es obligatorio.")
            }
            if !validCapacities.contains(definition.capacity) {
                issues.append("\(label): capacity no reconocido (\(definition.capacity)).")
            }
            if !validMeasurements.contains(definition.measurementKind) {
                issues.append("\(label): measurementKind no reconocido (\(definition.measurementKind)).")
            }
            if definition.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(label): unit es obligatorio.")
            }
            if definition.attempts < 1 {
                issues.append("\(label): attempts debe ser mayor que cero.")
            }
            if !validResultModes.contains(definition.resultMode) {
                issues.append("\(label): resultMode no reconocido (\(definition.resultMode)).")
            }
            if let minimum = definition.plausibleMinimum,
               let maximum = definition.plausibleMaximum,
               minimum > maximum {
                issues.append("\(label): plausibleMinimum no puede superar plausibleMaximum.")
            }
            if !(0...6).contains(definition.decimals) {
                issues.append("\(label): decimals debe estar entre 0 y 6.")
            }
        }

        let scaleIds = Set(manifest.referenceScales.map(\.id))
        if scaleIds.count != manifest.referenceScales.count {
            issues.append("Los identificadores de referenceScales deben ser únicos.")
        }
        var rangeIds = Set<String>()
        for scale in manifest.referenceScales {
            let label = scale.name.isEmpty ? scale.id : scale.name
            if !definitionIds.contains(scale.testId) {
                issues.append("\(label): testId \(scale.testId) no existe en testDefinitions.")
            }
            if !validDirections.contains(scale.direction) {
                issues.append("\(label): direction no reconocido (\(scale.direction)).")
            }
            if let ageFrom = scale.ageFrom, let ageTo = scale.ageTo, ageFrom > ageTo {
                issues.append("\(label): ageFrom no puede superar ageTo.")
            }
            let scoringMode = scale.scoring?.mode.uppercased() ?? "STEP"
            if !validScoringModes.contains(scoringMode) {
                issues.append("\(label): scoring.mode no reconocido (\(scoringMode)).")
            }
            if manifest.version == 2 && scale.scoring == nil {
                issues.append("\(label): las escalas de la versión 2 deben declarar scoring.")
            }
            if let roundTo = scale.scoring?.roundTo,
               !roundTo.isFinite || roundTo <= 0 {
                issues.append("\(label): scoring.roundTo debe ser un número mayor que cero.")
            }
            if scoringMode == "LINEAR" {
                if scale.scoring?.points.count ?? 0 < 2 {
                    issues.append("\(label): una escala LINEAR debe tener al menos dos puntos.")
                }
                var previousValue: Double?
                for (index, point) in (scale.scoring?.points ?? []).enumerated() {
                    if !point.value.isFinite {
                        issues.append("\(label): el punto \(index + 1) tiene un valor no finito.")
                    }
                    if let previousValue, point.value <= previousValue {
                        issues.append("\(label): los puntos LINEAR deben estar ordenados y no repetirse.")
                    }
                    previousValue = point.value
                    if !point.score.isFinite || point.score < 0 || point.score > 10 {
                        issues.append("\(label): el punto \(index + 1) tiene una puntuación fuera de 0-10.")
                    }
                    let pointId = point.id ?? "\(scale.id)_point_\(index + 1)"
                    if !rangeIds.insert(pointId).inserted {
                        issues.append("El identificador de punto \(pointId) está repetido.")
                    }
                }
            } else if scale.ranges.isEmpty {
                issues.append("\(label): debe tener al menos un rango.")
            }
            if scoringMode == "STEP" && !(scale.scoring?.points.isEmpty ?? true) {
                issues.append("\(label): una escala STEP no puede declarar puntos LINEAR.")
            }
            for range in scale.ranges {
                if !rangeIds.insert(range.id).inserted {
                    issues.append("El identificador de rango \(range.id) está repetido.")
                }
                if let minimum = range.minValue,
                   let maximum = range.maxValue,
                   minimum > maximum {
                    issues.append("\(label): el rango \(range.id) tiene minValue mayor que maxValue.")
                }
                if !range.score.isFinite || range.score < 0 || range.score > 10 {
                    issues.append("\(label): el rango \(range.id) tiene una puntuación fuera de 0-10.")
                }
            }
            if let definition = manifest.testDefinitions.first(where: { $0.id == scale.testId }) {
                let expectedDirection = definition.higherIsBetter ? "HIGHER_IS_BETTER" : "LOWER_IS_BETTER"
                if scale.direction != expectedDirection {
                    warnings.append("La escala \(label) no coincide con la dirección declarada por la prueba \(definition.name).")
                }
            }
        }

        for testId in manifest.calibrationRequiredTestIds where !definitionIds.contains(testId) {
            issues.append("calibrationRequiredTestIds contiene una prueba inexistente: \(testId).")
        }
        let scaledTestIds = Set(manifest.referenceScales.map(\.testId))
        for testId in manifest.calibrationRequiredTestIds where !scaledTestIds.contains(testId) {
            warnings.append("\(testId) queda sin baremo automático hasta validar una escala para ese protocolo.")
        }

        guard issues.isEmpty else { throw PhysicalTestsImportError.invalidManifest(issues) }

        return PhysicalTestsImportDraft(
            sourceFileName: url.lastPathComponent,
            sourceURL: url,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(data.count),
            purpose: manifest.purpose,
            learningSituation: manifest.learningSituation,
            assignmentTemplate: manifest.assignmentTemplate,
            testDefinitions: manifest.testDefinitions,
            referenceScales: manifest.referenceScales,
            calibrationRequiredTestIds: manifest.calibrationRequiredTestIds,
            warnings: Array(NSOrderedSet(array: warnings)) as? [String] ?? warnings,
            sourceNotes: manifest.sourceNotes
        )
    }

    private struct Manifest: Codable {
        let format: String
        let version: Int
        let purpose: String
        let learningSituation: PhysicalTestsImportLearningSituation
        let assignmentTemplate: PhysicalTestsImportAssignmentTemplate
        let testDefinitions: [PhysicalTestsImportDefinition]
        let referenceScales: [PhysicalTestsImportScale]
        let calibrationRequiredTestIds: [String]
        let warnings: [String]
        let sourceNotes: [String]
    }
}
