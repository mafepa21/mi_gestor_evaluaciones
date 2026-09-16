//
//  KmpBridge+TypeConverters.swift
//  MiGestorKMP
//
//  Created for modularization of KmpBridge.
//

import Foundation
import MiGestorKit

extension KmpBridge {
    func kotlinLong(_ value: Int64?) -> KotlinLong? {
        value.map { KotlinLong(value: $0) }
    }

    func int64Value(_ raw: Any?) -> Int64? {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String { return Int64(value) }
        return nil
    }

    func positiveInt64Value(_ raw: Any?) -> Int64? {
        int64Value(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Float { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        if let value = raw as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func studentSex(from raw: Any?) -> StudentSex {
        let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch value {
        case "MALE", "M", "H", "HOMBRE", "MASCULINO":
            return .male
        case "FEMALE", "F", "MUJER", "FEMENINO":
            return .female
        default:
            return .unspecified
        }
    }

    func studentSexSource(from raw: Any?) -> StudentSexSource {
        let value = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch value {
        case "MANUAL":
            return .manual
        case "NAME_INFERRED", "NAMEINFERRED", "NOMBRE":
            return .nameInferred
        case "AI_INFERRED", "AIINFERRED", "IA":
            return .aiInferred
        case "IMPORTED":
            return .imported
        default:
            return .unknown
        }
    }

    func localDate(from raw: Any?) -> LocalDate? {
        guard let value = raw as? String else { return nil }
        let parts = value.split(separator: "-").compactMap { Int32($0) }
        guard parts.count == 3 else { return nil }
        return LocalDate(year: parts[0], monthNumber: parts[1], dayOfMonth: parts[2])
    }

    func longList(_ raw: Any?) -> [KotlinLong] {
        if let values = raw as? [Int64] {
            return values.map { KotlinLong(value: $0) }
        }
        if let values = raw as? [NSNumber] {
            return values.map { KotlinLong(value: $0.int64Value) }
        }
        if let csv = raw as? String {
            return csv
                .split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { KotlinLong(value: $0) }
        }
        return []
    }

    func notebookColumnType(from raw: String?) -> NotebookColumnType {
        switch raw?.uppercased() {
        case "TEXT":
            return .text
        case "ICON":
            return .icon
        case "CHECK":
            return .check
        case "ORDINAL":
            return .ordinal
        case "RUBRIC":
            return .rubric
        case "ATTENDANCE":
            return .attendance
        case "CALCULATED":
            return .calculated
        default:
            return .numeric
        }
    }

    func notebookCategoryKind(_ raw: String?) -> NotebookColumnCategoryKind {
        switch raw?.uppercased() {
        case "EVALUATION": return .evaluation
        case "FOLLOW_UP": return .followUp
        case "ATTENDANCE": return .attendance
        case "EXTRAS": return .extras
        case "PHYSICAL_EDUCATION": return .physicalEducation
        default: return .custom
        }
    }

    func notebookInstrumentKind(_ raw: String?) -> NotebookInstrumentKind {
        switch raw?.uppercased() {
        case "WRITTEN_TEST": return .writtenTest
        case "RUBRIC": return .rubric
        case "SYSTEMATIC_OBSERVATION": return .systematicObservation
        case "CHECKLIST": return .checklist
        case "OBSERVATION_SCALE": return .observationScale
        case "FINAL_PRODUCT": return .finalProduct
        case "DAILY_WORK": return .dailyWork
        case "TASK": return .task
        case "PARTICIPATION": return .participation
        case "PHYSICAL_TEST": return .physicalTest
        case "MULTIMEDIA_EVIDENCE": return .multimediaEvidence
        default: return .custom
        }
    }

    func notebookInputKind(_ raw: String?) -> NotebookCellInputKind {
        switch raw?.uppercased() {
        case "NUMERIC_0_10": return .numeric010
        case "NUMERIC_1_4": return .numeric14
        case "PERCENTAGE": return .percentage
        case "TIME": return .time
        case "REPETITIONS": return .repetitions
        case "DISTANCE": return .distance
        case "EXCELLENT_GOOD_PROGRESS": return .excellentGoodProgress
        case "YES_NO": return .yesNo
        case "ACHIEVED_PARTIAL_NOT_ACHIEVED": return .achievedPartialNotAchieved
        case "LETTER_ABCD": return .letterAbcd
        case "QUICK_SELECTOR": return .quickSelector
        case "RUBRIC": return .rubric
        case "CHECK": return .check
        case "SHORT_NOTE": return .shortNote
        case "EVIDENCE": return .evidence
        case "ATTENDANCE_STATUS": return .attendanceStatus
        case "CALCULATED": return .calculated
        case "STRUCTURED_CHECKLIST": return .structuredChecklist
        case "STRUCTURED_OBSERVATION": return .structuredObservation
        case "STRUCTURED_FORM": return .structuredForm
        case "STRUCTURED_QUIZ": return .structuredQuiz
        default: return .text
        }
    }

    func notebookScaleKind(_ raw: String?) -> NotebookScaleKind {
        switch raw?.uppercased() {
        case "TEN_POINT": return .tenPoint
        case "FOUR_LEVEL": return .fourLevel
        case "PERCENTAGE": return .percentage
        case "TIME": return .time
        case "DISTANCE": return .distance
        case "REPETITIONS": return .repetitions
        case "LETTER_ABCD": return .letterAbcd
        case "ACHIEVEMENT": return .achievement
        case "YES_NO": return .yesNo
        default: return .custom
        }
    }

    func notebookColumnVisibility(_ raw: String?) -> NotebookColumnVisibility {
        switch raw?.uppercased() {
        case "HIDDEN": return .hidden
        case "ARCHIVED": return .archived
        default: return .visible
        }
    }

    func notebookInstrumentTemplateKind(_ raw: String?) -> NotebookInstrumentTemplateKind {
        switch raw?.uppercased() {
        case "CHECKLIST": return .checklist
        case "OBSERVATION": return .observation
        case "QUIZ": return .quiz
        default: return .form
        }
    }

    func notebookInstrumentItemType(_ raw: String?) -> NotebookInstrumentItemType {
        switch raw?.uppercased() {
        case "CHECK": return .check
        case "CHOICE": return .choice
        case "NUMBER": return .number
        case "TEXT": return .text
        default: return .scale14
        }
    }

    func normalizeHexColor(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let validLength = hex.count == 3 || hex.count == 6
        guard validLength else { return nil }
        let isHex = hex.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789ABCDEFabcdef").contains(scalar)
        }
        guard isHex else { return nil }
        return "#\(hex.uppercased())"
    }

}
