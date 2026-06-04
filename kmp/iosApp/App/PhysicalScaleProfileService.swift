import Foundation

enum PhysicalScalePrecision: Hashable {
    case integer
    case half
    case oneDecimal
    case twoDecimals
    case fiveCentimeters
    case fiftyMeters

    var adjustmentStep: Double {
        switch self {
        case .integer: return 1
        case .half: return 0.5
        case .oneDecimal: return 0.1
        case .twoDecimals: return 0.01
        case .fiveCentimeters: return 0.05
        case .fiftyMeters: return 50
        }
    }

    var boundaryStep: Double {
        switch self {
        case .fiftyMeters:
            return 1
        default:
            return adjustmentStep
        }
    }

    var promptLabel: String {
        switch self {
        case .integer: return "entero"
        case .half: return "0.5"
        case .oneDecimal: return "un decimal"
        case .twoDecimals: return "dos decimales"
        case .fiveCentimeters: return "0.05 m"
        case .fiftyMeters: return "50 m"
        }
    }
}

struct PhysicalScaleProfile: Hashable {
    var testId: String
    var family: String
    var unit: String
    var higherIsBetter: Bool
    var precision: PhysicalScalePrecision
    var baseAgeBand: ClosedRange<Int>
    var baseRanges: [PhysicalScaleRecommendedRange]
    var youngerAdjustment: Double
    var olderAdjustment: Double
    var seniorAdjustment: Double
    var initialAdjustment: Double
    var finalAdjustment: Double
    var progressAdjustment: Double
    var objectiveAdjustment: Double
}

enum PhysicalScaleProfileCatalog {
    static let safetyWarnings = [
        "Baremo orientativo",
        "Revisión docente necesaria",
        "No usar como baremo oficial sin adaptación al grupo"
    ]

    static func profile(for testId: String, objective: String) -> PhysicalScaleProfile? {
        guard var profile = profiles[testId] else { return nil }
        profile.objectiveAdjustment = objectiveAdjustment(for: objective, profile: profile)
        return profile
    }

    static func seedRanges(for input: PhysicalScaleRecommendationInput) -> [PhysicalScaleRecommendedRange] {
        guard let profile = profile(for: input.testId, objective: input.objective) else {
            return fallbackRanges(higherIsBetter: input.directionLabel.localizedCaseInsensitiveContains("mayor"))
        }
        let middleAge = averageAge(from: input.ageFrom, to: input.ageTo)
        let adjustment = ageAdjustment(for: middleAge, profile: profile) +
            sexAdjustment(for: input.sex, profile: profile) +
            profile.objectiveAdjustment
        return profile.baseRanges.map { range in
            PhysicalScaleRecommendedRange(
                minValue: adjusted(range.minValue, by: adjustment, precision: profile.precision),
                maxValue: adjusted(range.maxValue, by: adjustment, precision: profile.precision),
                score: range.score,
                label: label(for: range, adjustment: adjustment, profile: profile)
            )
        }
    }

    static func normalizedTestId(_ value: String) -> String {
        value
            .replacingOccurrences(of: "EF_", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(ranges: [PhysicalScaleRecommendedRange], for input: PhysicalScaleRecommendationInput) -> Bool {
        guard let profile = profile(for: input.testId, objective: input.objective), ranges.count == 5 else { return false }
        guard profile.unit == input.unit || input.unit.isEmpty else { return false }
        let sorted = ranges.sorted { ($0.minValue ?? -.infinity) < ($1.minValue ?? -.infinity) }
        guard sorted.allSatisfy({ (0...10).contains($0.score) && ($0.minValue != nil || $0.maxValue != nil) }) else { return false }
        for pair in zip(sorted, sorted.dropFirst()) {
            guard let leftMax = pair.0.maxValue, let rightMin = pair.1.minValue else { continue }
            if rightMin < leftMax { return false }
            if rightMin - leftMax > profile.precision.boundaryStep + 0.000_001 { return false }
        }
        let scores = sorted.map(\.score)
        return profile.higherIsBetter ? scores == scores.sorted() : scores == scores.sorted(by: >)
    }

    static func profileSummary(for input: PhysicalScaleRecommendationInput) -> String {
        guard let profile = profile(for: input.testId, objective: input.objective) else {
            return "Sin perfil local específico; usa rangos seed conservadores."
        }
        return "\(profile.family) · unidad \(profile.unit) · precisión \(profile.precision.promptLabel) · \(profile.higherIsBetter ? "mayor es mejor" : "menor es mejor")"
    }

    private static let profiles: [String: PhysicalScaleProfile] = [
        "course_navette": .init(testId: "course_navette", family: "resistance_level", unit: "periodo", higherIsBetter: true, precision: .half, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: 2.5, score: 3, label: "< 3.0 periodos"),
            .init(minValue: 3.0, maxValue: 4.5, score: 5, label: "3.0-4.5 periodos"),
            .init(minValue: 5.0, maxValue: 6.5, score: 6.5, label: "5.0-6.5 periodos"),
            .init(minValue: 7.0, maxValue: 8.5, score: 8, label: "7.0-8.5 periodos"),
            .init(minValue: 9.0, maxValue: nil, score: 10, label: ">= 9.0 periodos")
        ], youngerAdjustment: -0.5, olderAdjustment: 0.5, seniorAdjustment: 1.0, initialAdjustment: -0.5, finalAdjustment: 0.5, progressAdjustment: -0.5, objectiveAdjustment: 0),
        "cooper": .init(testId: "cooper", family: "resistance_distance", unit: "m", higherIsBetter: true, precision: .fiftyMeters, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: 1399, score: 3, label: "< 1400 m"),
            .init(minValue: 1400, maxValue: 1699, score: 5, label: "1400-1699 m"),
            .init(minValue: 1700, maxValue: 1999, score: 6.5, label: "1700-1999 m"),
            .init(minValue: 2000, maxValue: 2299, score: 8, label: "2000-2299 m"),
            .init(minValue: 2300, maxValue: nil, score: 10, label: ">= 2300 m")
        ], youngerAdjustment: -200, olderAdjustment: 200, seniorAdjustment: 300, initialAdjustment: -100, finalAdjustment: 100, progressAdjustment: -100, objectiveAdjustment: 0),
        "horizontal_jump": .init(testId: "horizontal_jump", family: "strength_distance", unit: "m", higherIsBetter: true, precision: .fiveCentimeters, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: 1.19, score: 3, label: "< 1.20 m"),
            .init(minValue: 1.20, maxValue: 1.39, score: 5, label: "1.20-1.39 m"),
            .init(minValue: 1.40, maxValue: 1.59, score: 6.5, label: "1.40-1.59 m"),
            .init(minValue: 1.60, maxValue: 1.79, score: 8, label: "1.60-1.79 m"),
            .init(minValue: 1.80, maxValue: nil, score: 10, label: ">= 1.80 m")
        ], youngerAdjustment: -0.15, olderAdjustment: 0.15, seniorAdjustment: 0.25, initialAdjustment: -0.05, finalAdjustment: 0.05, progressAdjustment: -0.05, objectiveAdjustment: 0),
        "push_ups": .init(testId: "push_ups", family: "strength_repetitions", unit: "rep", higherIsBetter: true, precision: .integer, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: 4, score: 3, label: "0-4 rep"),
            .init(minValue: 5, maxValue: 9, score: 5, label: "5-9 rep"),
            .init(minValue: 10, maxValue: 14, score: 6.5, label: "10-14 rep"),
            .init(minValue: 15, maxValue: 20, score: 8, label: "15-20 rep"),
            .init(minValue: 21, maxValue: nil, score: 10, label: ">= 21 rep")
        ], youngerAdjustment: -4, olderAdjustment: 4, seniorAdjustment: 7, initialAdjustment: -2, finalAdjustment: 2, progressAdjustment: -2, objectiveAdjustment: 0),
        "sit_ups": .init(testId: "sit_ups", family: "strength_repetitions_30s", unit: "rep", higherIsBetter: true, precision: .integer, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: 9, score: 3, label: "0-9 rep"),
            .init(minValue: 10, maxValue: 14, score: 5, label: "10-14 rep"),
            .init(minValue: 15, maxValue: 19, score: 6.5, label: "15-19 rep"),
            .init(minValue: 20, maxValue: 25, score: 8, label: "20-25 rep"),
            .init(minValue: 26, maxValue: nil, score: 10, label: ">= 26 rep")
        ], youngerAdjustment: -3, olderAdjustment: 4, seniorAdjustment: 6, initialAdjustment: -2, finalAdjustment: 2, progressAdjustment: -2, objectiveAdjustment: 0),
        "speed_30m": .init(testId: "speed_30m", family: "speed_time", unit: "s", higherIsBetter: false, precision: .oneDecimal, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: 5.0, score: 10, label: "<= 5.0 s"),
            .init(minValue: 5.1, maxValue: 5.4, score: 8, label: "5.1-5.4 s"),
            .init(minValue: 5.5, maxValue: 5.9, score: 6.5, label: "5.5-5.9 s"),
            .init(minValue: 6.0, maxValue: 6.5, score: 5, label: "6.0-6.5 s"),
            .init(minValue: 6.6, maxValue: nil, score: 3, label: "> 6.5 s")
        ], youngerAdjustment: 0.3, olderAdjustment: -0.2, seniorAdjustment: -0.3, initialAdjustment: 0.1, finalAdjustment: -0.1, progressAdjustment: 0.1, objectiveAdjustment: 0),
        "sit_and_reach": .init(testId: "sit_and_reach", family: "flexibility_distance", unit: "cm", higherIsBetter: true, precision: .integer, baseAgeBand: 13...14, baseRanges: [
            .init(minValue: nil, maxValue: -1, score: 3, label: "< 0 cm"),
            .init(minValue: 0, maxValue: 4, score: 5, label: "0-4 cm"),
            .init(minValue: 5, maxValue: 9, score: 6.5, label: "5-9 cm"),
            .init(minValue: 10, maxValue: 14, score: 8, label: "10-14 cm"),
            .init(minValue: 15, maxValue: nil, score: 10, label: ">= 15 cm")
        ], youngerAdjustment: -2, olderAdjustment: 2, seniorAdjustment: 3, initialAdjustment: -1, finalAdjustment: 1, progressAdjustment: -1, objectiveAdjustment: 0)
    ]

    private static func ageAdjustment(for age: Int, profile: PhysicalScaleProfile) -> Double {
        if age <= 12 { return profile.youngerAdjustment }
        if (15...16).contains(age) { return profile.olderAdjustment }
        if age >= 17 { return profile.seniorAdjustment }
        return 0
    }

    private static func objectiveAdjustment(for objective: String, profile: PhysicalScaleProfile) -> Double {
        let normalized = objective.lowercased()
        if normalized.contains("final") {
            return profile.finalAdjustment
        } else if normalized.contains("progreso") {
            return profile.progressAdjustment
        } else if normalized.contains("inicial") {
            return profile.initialAdjustment
        } else {
            return 0
        }
    }

    private static func sexAdjustment(for sex: String, profile: PhysicalScaleProfile) -> Double {
        let normalized = sex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isMale = ["male", "hombre", "masculino", "m", "h"].contains(normalized)
        let isFemale = ["female", "mujer", "femenino", "f"].contains(normalized)
        guard isMale || isFemale else { return 0 }

        switch profile.family {
        case "speed_time":
            return isMale ? -0.2 : 0.2
        case "resistance_level":
            return isMale ? 0.5 : -0.5
        case "resistance_distance":
            return isMale ? 150 : -150
        case "strength_distance":
            return isMale ? 0.10 : -0.10
        case "strength_repetitions", "strength_repetitions_30s":
            return isMale ? 3 : -3
        case "flexibility_distance":
            return isMale ? -2 : 2
        default:
            return 0
        }
    }

    private static func averageAge(from ageFrom: Int?, to ageTo: Int?) -> Int {
        switch (ageFrom, ageTo) {
        case let (.some(from), .some(to)): return (from + to) / 2
        case let (.some(from), .none): return from
        case let (.none, .some(to)): return to
        default: return 13
        }
    }

    private static func adjusted(_ value: Double?, by adjustment: Double, precision: PhysicalScalePrecision) -> Double? {
        guard let value else { return nil }
        if precision == .fiftyMeters {
            return value + adjustment
        }
        let multiplier = 1 / precision.adjustmentStep
        return ((value + adjustment) * multiplier).rounded() / multiplier
    }

    private static func label(for range: PhysicalScaleRecommendedRange, adjustment: Double, profile: PhysicalScaleProfile) -> String {
        let minValue = adjusted(range.minValue, by: adjustment, precision: profile.precision)
        let maxValue = adjusted(range.maxValue, by: adjustment, precision: profile.precision)
        let minText = minValue.map { formatted($0, precision: profile.precision) }
        let maxText = maxValue.map { formatted($0, precision: profile.precision) }
        switch (minText, maxText) {
        case let (.some(min), .some(max)): return "\(min)-\(max) \(profile.unit)"
        case let (.none, .some(max)): return "<= \(max) \(profile.unit)"
        case let (.some(min), .none): return ">= \(min) \(profile.unit)"
        default: return range.label
        }
    }

    private static func formatted(_ value: Double, precision: PhysicalScalePrecision) -> String {
        switch precision {
        case .integer: return "\(Int(value.rounded()))"
        case .half: return String(format: "%.1f", value)
        case .oneDecimal: return String(format: "%.1f", value)
        case .twoDecimals: return String(format: "%.2f", value)
        case .fiveCentimeters: return String(format: "%.2f", value)
        case .fiftyMeters: return "\(Int(value.rounded()))"
        }
    }

    private static func fallbackRanges(higherIsBetter: Bool) -> [PhysicalScaleRecommendedRange] {
        let scores: [Double] = higherIsBetter ? [3, 5, 6.5, 8, 10] : [10, 8, 6.5, 5, 3]
        return [
            .init(minValue: nil, maxValue: 20, score: scores[0], label: "<= 20"),
            .init(minValue: 21, maxValue: 40, score: scores[1], label: "21-40"),
            .init(minValue: 41, maxValue: 60, score: scores[2], label: "41-60"),
            .init(minValue: 61, maxValue: 80, score: scores[3], label: "61-80"),
            .init(minValue: 81, maxValue: nil, score: scores[4], label: ">= 81")
        ]
    }
}
