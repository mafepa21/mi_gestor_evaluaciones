import Foundation
import MiGestorKit

/// Deriva el nombre de un grupo a partir de su código de Excel
/// (`<dígitos><nivel><letra>`, p.ej. `1ESOA`, `1BACB`, `2FPA`). Centraliza la
/// única fuente de verdad para que la generación del nombre al crear un
/// grupo y el emparejamiento contra grupos ya existentes usen siempre el
/// mismo criterio — si divergen, la reimportación deja de ser idempotente.
enum ScheduleGroupNaming {
    static func displayName(forCode code: String) -> String {
        guard let firstLetterIndex = code.firstIndex(where: { $0.isLetter }) else { return code }
        let courseDigits = code[code.startIndex..<firstLetterIndex]
        guard !courseDigits.isEmpty, courseDigits.allSatisfy(\.isNumber) else { return code }

        let remainder = code[firstLetterIndex...]
        guard remainder.count >= 2, let letterSuffix = remainder.last, letterSuffix.isLetter else { return code }

        let levelToken = String(remainder.dropLast())
        guard !levelToken.isEmpty else { return code }
        let levelLabel = levelToken.count <= 3 ? levelToken.uppercased() : levelToken.capitalized
        return "\(courseDigits)º \(levelLabel) \(letterSuffix)"
    }
}

/// Resuelve, contra el catálogo actual de la app, qué grupos y asignaturas
/// detectados en un Excel de horario ya existen y cuáles hay que crear.
/// No depende de `KmpBridge` para poder probarse con datos planos.
struct ScheduleImportCatalogResolver {
    struct SubjectResolution {
        var matchedIdByCode: [String: Int64] = [:]
        var toCreate: [(code: String, name: String)] = []
        var warnings: [String] = []
    }

    struct GroupResolution {
        var matchedIdByCode: [String: Int64] = [:]
        var toCreate: [(code: String, name: String, course: Int32)] = []
    }

    static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Emparejamiento en cascada: (1) código normalizado exacto contra el
    /// catálogo, (2) nombre de la leyenda del Excel contra el nombre de una
    /// asignatura ya existente, (3) sin match, se crea. El nombre del
    /// catálogo existente nunca se sobrescribe con el de la leyenda.
    func resolveSubjects(preview: ScheduleImportPreview, existingSubjects: [KmpSubject]) -> SubjectResolution {
        let legendByCode = Dictionary(
            preview.subjectLegend.map { (Self.normalizedKey($0.code), $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let subjectByCode = Dictionary(
            existingSubjects.map { (Self.normalizedKey($0.code), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let subjectByName = Dictionary(
            existingSubjects.map { (Self.normalizedKey($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result = SubjectResolution()
        let codes = stableUnique(preview.persistableSlots.flatMap(\.subjectCodes))

        for code in codes {
            let key = Self.normalizedKey(code)
            guard !key.isEmpty else { continue }

            if let existing = subjectByCode[key] {
                result.matchedIdByCode[code] = existing.id
                continue
            }

            guard let legendName = legendByCode[key] else {
                // Sin entrada en la leyenda: es el centinela "Clase" que
                // resuelve el parser cuando no reconoce el código. No se
                // usa ese nombre; se crea con el código como nombre.
                result.toCreate.append((code: code, name: code))
                result.warnings.append("\(code) se crea sin nombre completo (no aparece en la leyenda del Excel). Renómbrala en Asignaturas.")
                continue
            }

            if let existing = subjectByName[Self.normalizedKey(legendName)] {
                result.matchedIdByCode[code] = existing.id
                if Self.normalizedKey(legendName) != Self.normalizedKey(existing.name) {
                    result.warnings.append("El Excel llama «\(legendName)» a \(code); en tu catálogo es «\(existing.name)». Se mantiene el del catálogo.")
                }
                continue
            }

            result.toCreate.append((code: code, name: legendName))
        }

        return result
    }

    /// Emparejamiento por nombre normalizado contra `ScheduleGroupNaming`,
    /// no por el código de Excel en sí (que no se persiste en ningún sitio):
    /// así se deduplican también los grupos que no encajan en el patrón
    /// "ESO" que usaba la detección anterior.
    func resolveGroups(preview: ScheduleImportPreview, existingGroups: [SchoolClass]) -> GroupResolution {
        let groupByName = Dictionary(
            existingGroups.map { (Self.normalizedKey($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result = GroupResolution()
        for code in preview.groupCodes {
            let displayName = ScheduleGroupNaming.displayName(forCode: code)
            if let existing = groupByName[Self.normalizedKey(displayName)] {
                result.matchedIdByCode[code] = existing.id
                continue
            }
            let course = Int32(Int(code.prefix(1)) ?? 0)
            result.toCreate.append((code: code, name: displayName, course: course))
        }
        return result
    }

    /// Códigos de asignatura por grupo, excluyendo tutoría: base para decidir
    /// si un grupo puede recibir automáticamente un `subjectId` único.
    func subjectCodesByGroup(preview: ScheduleImportPreview) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for slot in preview.persistableSlots where slot.kind != .tutoring {
            for assignment in slot.assignments {
                result[assignment.groupCode, default: []].insert(assignment.subjectCode)
            }
        }
        return result
    }
}

/// Resumen listo para pintar en `ScheduleImportPreviewSheet`: qué se creará
/// y qué se reutiliza del catálogo existente.
struct ScheduleImportCatalogPlan {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let groupsToCreate: [Item]
    let groupsReusedCount: Int
    let subjectsToCreate: [Item]
    let subjectsReusedCount: Int
    let warnings: [String]

    static let empty = ScheduleImportCatalogPlan(
        groupsToCreate: [],
        groupsReusedCount: 0,
        subjectsToCreate: [],
        subjectsReusedCount: 0,
        warnings: []
    )

    static func build(
        groupResolution: ScheduleImportCatalogResolver.GroupResolution,
        subjectResolution: ScheduleImportCatalogResolver.SubjectResolution
    ) -> ScheduleImportCatalogPlan {
        ScheduleImportCatalogPlan(
            groupsToCreate: groupResolution.toCreate.map { Item(id: $0.code, title: $0.name) },
            groupsReusedCount: groupResolution.matchedIdByCode.count,
            subjectsToCreate: subjectResolution.toCreate.map { Item(id: $0.code, title: $0.name) },
            subjectsReusedCount: subjectResolution.matchedIdByCode.count,
            warnings: subjectResolution.warnings
        )
    }
}
