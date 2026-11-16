import Foundation

extension SdaTournamentStore {
    /// Guarda la nota en el torneo y la copia a la ficha (incidencias) de `studentIds`.
    /// La nota del torneo se guarda siempre primero; si falla alguna ficha devuelve un aviso.
    func addNote(_ note: TournamentNote, copyingToStudentIds studentIds: [Int64], bridge: KmpBridge) async -> String? {
        mutate { $0.addNote(note) }
        guard !studentIds.isEmpty else { return nil }
        let title = "Torneo · \(plan.name)"
        var created: [Int64] = []
        var failed = 0
        for studentId in studentIds {
            do {
                let id = try await bridge.createIncident(
                    classId: record.classId,
                    studentId: studentId,
                    title: title,
                    detail: note.incidentDetail,
                    severity: note.incidentSeverity
                )
                created.append(id)
            } catch {
                failed += 1
            }
        }
        if !created.isEmpty {
            mutate { $0.setIncidentIds(created, forNote: note.id) }
        }
        guard failed > 0 else { return nil }
        return failed == studentIds.count
            ? "La nota se guardó en el torneo, pero no en la ficha del alumnado."
            : "La nota se guardó en el torneo, pero no en la ficha de \(sdaPlural(failed, "alumno", "alumnos"))."
    }

    /// Borra la nota del torneo y las incidencias que se crearon con ella.
    func deleteNote(_ note: TournamentNote, bridge: KmpBridge) async -> String? {
        var failed = 0
        for incidentId in note.incidentIds {
            do { try await bridge.deleteIncident(id: incidentId) } catch { failed += 1 }
        }
        mutate { $0.removeNote(id: note.id) }
        return failed == 0 ? nil : "La nota se borró del torneo, pero no de todas las fichas."
    }

    /// Alumnos (ids numéricos) de los equipos con esos nombres.
    func studentIds(ofTeams names: [String]) -> [Int64] {
        let wanted = Set(names)
        var seen = Set<Int64>()
        return plan.teams
            .filter { wanted.contains($0.name) }
            .flatMap(\.studentIDs)
            .compactMap { Int64($0) }
            .filter { seen.insert($0).inserted }
    }
}
