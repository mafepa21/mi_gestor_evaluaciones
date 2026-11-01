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

/// Decisión del docente para un código de grupo del Excel que encaja con
/// varios grupos de la app.
enum ScheduleGroupChoice: Hashable {
    case existing(Int64)
    case createNew
}

/// Nombres visibles que distinguen grupos con el mismo nombre (p. ej. dos
/// "4º ESO A" de centros distintos). Los grupos de nombre único se quedan
/// como están; a los repetidos se les añade su descripción, curso escolar o
/// asignatura, y si aun así coinciden, un número de orden.
enum SchoolClassDisplayNames {
    struct Group {
        let id: Int64
        let name: String
        var description: String? = nil
        var academicYearName: String? = nil
        var subjectName: String? = nil
    }

    static func labels(for groups: [Group]) -> [Int64: String] {
        var result: [Int64: String] = [:]
        let byName = Dictionary(grouping: groups) { ScheduleImportCatalogResolver.normalizedKey($0.name) }
        for (_, sameName) in byName {
            guard sameName.count > 1 else {
                sameName.forEach { result[$0.id] = $0.name }
                continue
            }
            let ordered = sameName.sorted { $0.id < $1.id }
            let yearsDiffer = Set(ordered.map { $0.academicYearName ?? "" }).count > 1
            let subjectsDiffer = Set(ordered.map { $0.subjectName ?? "" }).count > 1
            var labels: [Int64: String] = [:]
            for group in ordered {
                var parts: [String] = []
                if let description = group.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    parts.append(description)
                }
                if yearsDiffer, let year = group.academicYearName, !year.isEmpty {
                    parts.append(year)
                }
                if subjectsDiffer, let subject = group.subjectName, !subject.isEmpty {
                    parts.append(subject)
                }
                labels[group.id] = ([group.name] + parts).joined(separator: " · ")
            }
            let repeated = Dictionary(grouping: ordered) { labels[$0.id] ?? $0.name }.filter { $0.value.count > 1 }
            for (_, collided) in repeated {
                for (index, group) in collided.enumerated() {
                    labels[group.id] = "\(labels[group.id] ?? group.name) · \(index + 1)"
                }
            }
            result.merge(labels) { _, new in new }
        }
        return result
    }
}

/// Reparto por días de las franjas de grupos que se llaman igual (p. ej. dos
/// «4º ESO A», uno por centro). Sirve para ver de un vistazo si un día quedó
/// en el grupo equivocado y pasar todas sus franjas al otro de una vez.
enum SameNameGroupScheduleDays {
    struct Slot {
        let id: Int64
        let groupId: Int64
        let day: Int
    }

    struct Family: Identifiable, Equatable {
        /// Ids de los grupos con el mismo nombre, ordenados.
        let groupIds: [Int64]
        /// Día (1 = lunes) → grupos que tienen franjas ese día.
        let groupIdsByDay: [Int: [Int64]]

        var id: String { groupIds.map(String.init).joined(separator: "-") }
        var days: [Int] { groupIdsByDay.keys.sorted() }
    }

    static func families(groups: [SchoolClassDisplayNames.Group], slots: [Slot]) -> [Family] {
        let byName = Dictionary(grouping: groups) { ScheduleImportCatalogResolver.normalizedKey($0.name) }
        return byName.values
            .filter { $0.count > 1 }
            .compactMap { sameName -> Family? in
                let ids = sameName.map(\.id).sorted()
                let idSet = Set(ids)
                var byDay: [Int: Set<Int64>] = [:]
                for slot in slots where idSet.contains(slot.groupId) {
                    byDay[slot.day, default: []].insert(slot.groupId)
                }
                guard !byDay.isEmpty else { return nil }
                return Family(groupIds: ids, groupIdsByDay: byDay.mapValues { $0.sorted() })
            }
            .sorted { $0.groupIds.first ?? 0 < $1.groupIds.first ?? 0 }
    }

    /// Ids de grupo que tienen franjas pero ya no existen, ordenados.
    static func orphanGroupIds(knownGroupIds: Set<Int64>, slots: [Slot]) -> [Int64] {
        Set(slots.map(\.groupId)).subtracting(knownGroupIds).sorted()
    }

    /// Franjas de la familia en `day` que no son ya de `targetGroupId`.
    static func slotsToReassign(in family: Family, day: Int, to targetGroupId: Int64, slots: [Slot]) -> [Slot] {
        let idSet = Set(family.groupIds)
        guard idSet.contains(targetGroupId) else { return [] }
        return slots.filter { $0.day == day && idSet.contains($0.groupId) && $0.groupId != targetGroupId }
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
        /// Códigos con varios grupos posibles: no se importan hasta elegir.
        var ambiguousCandidatesByCode: [String: [Int64]] = [:]
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
    ///
    /// Se empareja automáticamente solo cuando hay un único grupo con ese nombre exacto.
    /// Si hay varios candidatos (dos "4º ESO A" de centros distintos, o
    /// "4º ESO A" y "4º ESO A - Tavernes"), el código queda en
    /// `ambiguousCandidatesByCode` hasta que el docente elija en `choices`:
    /// antes se cogía el primero y las franjas de un centro acababan en el
    /// grupo del otro.
    func resolveGroups(
        preview: ScheduleImportPreview,
        existingGroups: [SchoolClass],
        choices: [String: ScheduleGroupChoice] = [:]
    ) -> GroupResolution {
        resolveGroups(
            groupCodes: preview.groupCodes,
            existingGroups: existingGroups.map { (id: $0.id, name: $0.name) },
            choices: choices
        )
    }

    func resolveGroups(
        groupCodes: [String],
        existingGroups: [(id: Int64, name: String)],
        choices: [String: ScheduleGroupChoice] = [:]
    ) -> GroupResolution {
        let existingIds = Set(existingGroups.map(\.id))
        var result = GroupResolution()
        for code in groupCodes {
            let displayName = ScheduleGroupNaming.displayName(forCode: code)
            let course = Int32(Int(code.prefix(1)) ?? 0)

            switch choices[code] {
            case .existing(let classId) where existingIds.contains(classId):
                result.matchedIdByCode[code] = classId
                continue
            case .createNew:
                result.toCreate.append((code: code, name: displayName, course: course))
                continue
            default:
                break
            }

            let candidates = Self.candidateGroups(forDisplayName: displayName, in: existingGroups)
            if candidates.exact.count == 1, candidates.related.isEmpty {
                result.matchedIdByCode[code] = candidates.exact[0]
            } else if candidates.exact.isEmpty, candidates.related.isEmpty {
                result.toCreate.append((code: code, name: displayName, course: course))
            } else {
                result.ambiguousCandidatesByCode[code] = candidates.exact + candidates.related
            }
        }
        return result
    }

    /// Grupos que pueden ser el del Excel: los de nombre exacto y los que
    /// empiezan por ese nombre seguido de un separador ("4º ESO A - Tavernes",
    /// "4º ESO A (Mislata)"), pero no "4º ESO AB".
    static func candidateGroups(
        forDisplayName displayName: String,
        in existingGroups: [(id: Int64, name: String)]
    ) -> (exact: [Int64], related: [Int64]) {
        let key = normalizedKey(displayName)
        guard !key.isEmpty else { return ([], []) }
        let separators: Set<Character> = [" ", "-", "(", "·", "/", ",", "_", "–"]
        var exact: [Int64] = []
        var related: [Int64] = []
        for group in existingGroups.sorted(by: { $0.id < $1.id }) {
            let name = normalizedKey(group.name)
            if name == key {
                exact.append(group.id)
            } else if name.hasPrefix(key), let next = name.dropFirst(key.count).first, separators.contains(next) {
                related.append(group.id)
            }
        }
        return (exact, related)
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

    /// Código del Excel que encaja con varios grupos: el docente elige uno
    /// de `candidates` o crear un grupo nuevo.
    struct GroupChoicePrompt: Identifiable, Hashable {
        struct Candidate: Identifiable, Hashable {
            let id: Int64
            let title: String
        }

        let id: String
        let title: String
        let candidates: [Candidate]
    }

    let groupsToCreate: [Item]
    let groupsReusedCount: Int
    let subjectsToCreate: [Item]
    let subjectsReusedCount: Int
    let warnings: [String]
    var groupChoicePrompts: [GroupChoicePrompt] = []

    static let empty = ScheduleImportCatalogPlan(
        groupsToCreate: [],
        groupsReusedCount: 0,
        subjectsToCreate: [],
        subjectsReusedCount: 0,
        warnings: []
    )

    /// `groupResolution` ya lleva aplicadas las elecciones del docente;
    /// `promptResolution` es la de sin elecciones, para que las preguntas
    /// sigan a la vista después de contestarlas.
    static func build(
        groupResolution: ScheduleImportCatalogResolver.GroupResolution,
        subjectResolution: ScheduleImportCatalogResolver.SubjectResolution,
        promptResolution: ScheduleImportCatalogResolver.GroupResolution? = nil,
        candidateTitle: (Int64) -> String = { "Grupo \($0)" }
    ) -> ScheduleImportCatalogPlan {
        let prompts = (promptResolution ?? groupResolution).ambiguousCandidatesByCode
            .map { code, ids in
                GroupChoicePrompt(
                    id: code,
                    title: ScheduleGroupNaming.displayName(forCode: code),
                    candidates: ids.map { GroupChoicePrompt.Candidate(id: $0, title: candidateTitle($0)) }
                )
            }
            .sorted { $0.id < $1.id }
        return ScheduleImportCatalogPlan(
            groupsToCreate: groupResolution.toCreate.map { Item(id: $0.code, title: $0.name) },
            groupsReusedCount: groupResolution.matchedIdByCode.count,
            subjectsToCreate: subjectResolution.toCreate.map { Item(id: $0.code, title: $0.name) },
            subjectsReusedCount: subjectResolution.matchedIdByCode.count,
            warnings: subjectResolution.warnings,
            groupChoicePrompts: prompts
        )
    }
}
