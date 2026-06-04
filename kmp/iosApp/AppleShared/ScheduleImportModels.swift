import Foundation

struct ImportedSubjectLegend: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}

enum ImportedScheduleSlotKind: String, Hashable {
    case teaching
    case tutoring
    case breakTime
    case empty

    var label: String {
        switch self {
        case .teaching:
            return "Clase"
        case .tutoring:
            return "Tutoría"
        case .breakTime:
            return "Recreo"
        case .empty:
            return "Hueco vacío"
        }
    }
}

enum ScheduleEmptySlotImportMode: String, CaseIterable, Identifiable {
    case skip
    case keepVisible
    case guardDuty
    case coordination
    case meeting
    case preparation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skip:
            return "No importar"
        case .keepVisible:
            return "Mantener como hueco vacío visible"
        case .guardDuty:
            return "Convertir en guardia"
        case .coordination:
            return "Convertir en coordinación"
        case .meeting:
            return "Convertir en reunión"
        case .preparation:
            return "Convertir en preparación docente"
        }
    }
}

struct ImportedScheduleSlot: Identifiable, Hashable {
    let id = UUID()
    let weekday: Int
    let startMinute: Int
    let endMinute: Int
    let rawText: String
    let kind: ImportedScheduleSlotKind
    let subjectCodes: [String]
    let subjectName: String?
    let groupCodes: [String]

    var startTime: String { Self.timeString(from: startMinute) }
    var endTime: String { Self.timeString(from: endMinute) }
    var subjectCode: String? { subjectCodes.first }

    var displayTitle: String {
        switch kind {
        case .teaching, .tutoring:
            return subjectName ?? subjectCode ?? rawText
        case .breakTime:
            return "Recreo"
        case .empty:
            return "Hueco vacío"
        }
    }

    static func timeString(from minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

struct ScheduleImportPreview: Identifiable {
    let id = UUID()
    let sourceName: String
    let slots: [ImportedScheduleSlot]
    let subjectLegend: [ImportedSubjectLegend]
    let conflicts: [String]
    let warnings: [String]

    var teachingSlots: [ImportedScheduleSlot] {
        slots.filter { $0.kind == .teaching }
    }

    var tutoringSlots: [ImportedScheduleSlot] {
        slots.filter { $0.kind == .tutoring }
    }

    var breakSlots: [ImportedScheduleSlot] {
        slots.filter { $0.kind == .breakTime }
    }

    var emptyCandidates: [ImportedScheduleSlot] {
        slots.filter { $0.kind == .empty }
    }

    var groupCodes: [String] {
        Array(Set(slots.flatMap(\.groupCodes))).sorted()
    }

    var subjectNames: [String] {
        Array(Set(slots.compactMap(\.subjectName))).sorted()
    }

    var persistableSlots: [ImportedScheduleSlot] {
        slots.filter { $0.kind == .teaching || $0.kind == .tutoring }
    }
}
