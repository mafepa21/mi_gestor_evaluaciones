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

/// Un par asignatura↔grupo tal y como aparece en un segmento de celda
/// (`CODIGO_ASIGNATURA:CODIGO_GRUPO`). Preserva el emparejamiento real de la
/// celda, que se perdía al acumular `subjectCodes` y `groupCodes` en arrays
/// independientes.
struct ImportedSlotAssignment: Hashable {
    let subjectCode: String
    let groupCode: String
}

struct ImportedScheduleSlot: Identifiable, Hashable {
    let id = UUID()
    let weekday: Int
    let startMinute: Int
    let endMinute: Int
    let rawText: String
    let kind: ImportedScheduleSlotKind
    let assignments: [ImportedSlotAssignment]
    let subjectName: String?

    var subjectCodes: [String] { stableUnique(assignments.map(\.subjectCode)) }
    var groupCodes: [String] { stableUnique(assignments.map(\.groupCode)) }

    /// Asignatura asociada a un grupo concreto de esta franja, cuando la
    /// celda mezcla varios pares asignatura↔grupo (ej. `EFI:1ESOA / MUS:2ESOB`).
    func subjectCode(forGroup groupCode: String) -> String? {
        assignments.first(where: { $0.groupCode == groupCode })?.subjectCode
    }

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

func stableUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values where !seen.contains(value) {
        seen.insert(value)
        result.append(value)
    }
    return result
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
