import Foundation
import MiGestorKit

/// Marca del docente para organizar grupos: «Fuerte» o «Necesita apoyo».
/// Espejo en Swift de `WorkGroupMark` (Kotlin), por su nombre guardado.
enum WorkGroupMarkUI: String, CaseIterable, Identifiable {
    case unmarked = "NONE"
    case strong = "STRONG"
    case support = "SUPPORT"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unmarked: return "Sin marca"
        case .strong: return "Fuerte"
        case .support: return "Necesita apoyo"
        }
    }

    /// Texto corto para VoiceOver y resúmenes («fuerte», «necesita apoyo»).
    var spokenTitle: String { title.lowercased() }

    var systemImage: String {
        switch self {
        case .unmarked: return "circle.dashed"
        case .strong: return "star.fill"
        case .support: return "hand.raised.fill"
        }
    }

    var kotlin: WorkGroupMark {
        WorkGroupMark.companion.fromStorage(raw: rawValue)
    }

    init(kotlin: WorkGroupMark) {
        self = WorkGroupMarkUI(rawValue: kotlin.name) ?? .unmarked
    }
}

extension Notification.Name {
    /// Cambiaron las marcas de grupo (en este equipo o por Sync LAN).
    static let workGroupMarksDidChange = Notification.Name("workGroupMarksDidChange")
}

/// Columnas elegidas para cada apartado, recordadas en este equipo por curso.
enum WorkGroupSkillSelectionStore {
    private static func key(classId: Int64, dimension: WorkGroupSkillDimension) -> String {
        "workGroupSkill.\(classId).\(dimension.name)"
    }

    /// `nil` si el docente aún no ha elegido nada para ese apartado en este curso.
    static func load(classId: Int64, dimension: WorkGroupSkillDimension) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key(classId: classId, dimension: dimension))
    }

    static func save(_ columnIds: [String], classId: Int64, dimension: WorkGroupSkillDimension) {
        UserDefaults.standard.set(columnIds, forKey: key(classId: classId, dimension: dimension))
    }
}

extension KmpBridge {

    // MARK: - Marcas Fuerte / Necesita apoyo (migración 52)

    /// Marcas del curso por id de alumno. Solo las que no son «sin marca».
    func workGroupMarks(classId: Int64) async throws -> [Int64: WorkGroupMarkUI] {
        let marks = try await container.studentGroupMarkRepository.listByClass(classId: classId)
        var result: [Int64: WorkGroupMarkUI] = [:]
        for mark in marks {
            let ui = WorkGroupMarkUI(kotlin: mark.mark)
            if ui != .unmarked { result[mark.studentId] = ui }
        }
        return result
    }

    /// Guarda la misma marca para varios alumnos y la encola para Sync LAN.
    func saveWorkGroupMark(_ mark: WorkGroupMarkUI, studentIds: [Int64], classId: Int64) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for studentId in studentIds {
            let saved = try await container.studentGroupMarkRepository.save(
                studentId: studentId,
                classId: classId,
                mark: mark.kotlin,
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId
            )
            enqueueLocalChange(
                entity: SchoolRecordsSync.companion.STUDENT_GROUP_MARKS,
                id: saved.syncId,
                updatedAtEpochMs: nowMs,
                payload: [
                    "studentId": studentId,
                    "classId": classId,
                    "mark": saved.mark.name
                ]
            )
        }
        NotificationCenter.default.post(name: .workGroupMarksDidChange, object: nil)
    }

    // MARK: - Notas por apartado (Técnica, Comportamiento, Liderazgo)

    /// Columnas del Cuaderno con nota que se pueden elegir para un apartado.
    func workGroupSkillCandidateColumns() -> [NotebookColumnDefinition] {
        notebookViewModel.workGroupSkillCandidateColumns()
    }

    /// Columnas elegidas para el apartado: lo recordado en este equipo o la sugerencia.
    /// Descarta ids de columnas que ya no existen.
    func workGroupSkillSelection(classId: Int64, dimension: WorkGroupSkillDimension) -> [String] {
        let available = Set(workGroupSkillCandidateColumns().map(\.id))
        let chosen = WorkGroupSkillSelectionStore.load(classId: classId, dimension: dimension)
            ?? notebookViewModel.workGroupSkillSuggestion(dimension: dimension)
        return chosen.filter { available.contains($0) }
    }

    /// `true` si la columna sale sugerida para ese apartado por su nombre o tipo.
    func workGroupSkillSuggests(_ columnId: String, dimension: WorkGroupSkillDimension) -> Bool {
        notebookViewModel.workGroupSkillSuggestion(dimension: dimension).contains(columnId)
    }

    /// Nota de 0 a 10 por alumno con esas columnas. Sin entrada si no tiene ninguna.
    func workGroupDimensionScores(columnIds: [String]) -> [Int64: Double] {
        guard !columnIds.isEmpty else { return [:] }
        // Lista y no Map: un Map<Long, …> de Kotlin rompe al recorrerlo en Swift.
        var result: [Int64: Double] = [:]
        for item in notebookViewModel.workGroupDimensionScoreList(columnIds: columnIds) {
            result[item.studentId] = item.score
        }
        return result
    }
}
