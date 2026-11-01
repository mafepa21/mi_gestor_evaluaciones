import Foundation
import MiGestorKit

/// Reglas puras para colocar pruebas físicas en el cuaderno de un grupo.
enum PhysicalTestNotebookPlacement {
    static let internalBatteryPrefix = "pe_wizard_battery_"
    static let terms = ["1ª evaluación", "2ª evaluación", "3ª evaluación", "Evaluación final"]

    /// Id estable por prueba, grupo y evaluación: añadir dos veces lo mismo
    /// reutiliza la asignación en vez de duplicarla. Sin evaluación conserva el
    /// id que usaba el asistente.
    static func assignmentId(definitionId: String, classId: Int64, termLabel: String?) -> String {
        let base = "pe_wizard_assignment_\(definitionId)_\(classId)"
        guard let slug = termLabel.map(slug), !slug.isEmpty else { return base }
        return "\(base)_\(slug)"
    }

    static func slug(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
            .map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "_" }
            .joined()
            .split(separator: "_")
            .joined(separator: "_")
    }

    /// Las baterías de una sola prueba que crea el sistema no se enseñan.
    static func isUserBattery(_ battery: PhysicalTestBattery) -> Bool {
        !battery.id.hasPrefix(internalBatteryPrefix)
    }

    /// Edad habitual a mitad de curso en ESO y Bachillerato (1º ESO → 12).
    /// Solo se usa cuando el alumno no tiene fecha de nacimiento.
    static func typicalAge(course: Int?) -> Int? {
        guard let course, (1...6).contains(course) else { return nil }
        return 11 + course
    }

    /// Qué le falta a un alumno para que su baremo pueda resolverse.
    struct MissingData: Equatable {
        var withoutSex: [Student] = []
        var withoutBirthDate: [Student] = []

        var isEmpty: Bool { withoutSex.isEmpty && withoutBirthDate.isEmpty }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.withoutSex.map(\.id) == rhs.withoutSex.map(\.id) &&
                lhs.withoutBirthDate.map(\.id) == rhs.withoutBirthDate.map(\.id)
        }
    }

    /// Solo cuenta lo que importa: el sexo si algún baremo distingue sexo y la
    /// fecha de nacimiento si algún baremo va por edad.
    static func missingData(students: [Student], scales: [PhysicalTestScale]) -> MissingData {
        let needsSex = scales.contains { scale in
            let sex = scale.sex?.uppercased() ?? ""
            return !sex.isEmpty && sex != "UNSPECIFIED" && sex != "ALL" && sex != "TODOS"
        }
        let needsAge = scales.contains { $0.ageFrom != nil || $0.ageTo != nil }
        var result = MissingData()
        for student in students {
            if needsSex && student.sex == .unspecified { result.withoutSex.append(student) }
            if needsAge && student.birthDate == nil { result.withoutBirthDate.append(student) }
        }
        return result
    }
}
