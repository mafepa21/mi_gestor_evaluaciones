import Foundation
import MiGestorKit

/// Fila de una prueba física en la pestaña «EF y seguimiento» del portal.
struct WebPortalPETestRow: Identifiable, Equatable {
    let id: String
    let name: String
    let capacityLabel: String
    let recordedStudents: Int
    let totalStudents: Int
    let assignmentCount: Int
}

struct WebPortalPEOverview: Equatable {
    let classId: Int64
    let studentCount: Int
    let tests: [WebPortalPETestRow]
    let hasAttendanceRecords: Bool
}

/// Construcción pura de los bloques `fisica` y `asistencia` del tablón v1 (fase 3C).
///
/// Reglas de privacidad estrictas:
///  - `fisica`: solo registros del propio alumno. Nunca medias de clase, rankings ni otros alumnos.
///  - `asistencia`: solo contadores y fecha + tipo de registros recientes. NUNCA `Attendance.note`,
///    `hasIncident` ni `followUpRequired`.
enum WebPortalPE {
    static let maxTests = 20
    static let maxAttemptsPerTest = 10
    static let maxRecentAttendance = 20

    struct TestMeta: Equatable {
        let id: String
        let name: String
        let capacityLabel: String
        let unit: String
        let higherIsBetter: Bool
    }

    struct TestRecord: Equatable {
        let testId: String
        let rawValue: Double?
        let rawText: String
        let score: Double?
        let observedAtEpochMs: Int64
    }

    struct AttendanceItem: Equatable {
        let dateEpochMs: Int64
        let status: String
    }

    static func capacityLabel(_ capacity: PhysicalCapacity) -> String {
        switch capacity {
        case .resistance: return "Resistencia"
        case .strength: return "Fuerza"
        case .speed: return "Velocidad"
        case .flexibility: return "Flexibilidad"
        case .coordination: return "Coordinación"
        case .agility: return "Agilidad"
        default: return "Condición física"
        }
    }

    /// Bloque `fisica` de un alumno concreto, o `nil` si no tiene ninguna prueba visible con registro.
    static func fisicaBlock(
        definitions: [String: TestMeta],
        records: [TestRecord],
        visibleTestIds: Set<String>,
        now: Date = Date(),
        timeZone: Foundation.TimeZone = .current
    ) -> [String: Any]? {
        guard !visibleTestIds.isEmpty else { return nil }
        let grouped = Dictionary(grouping: records.filter { visibleTestIds.contains($0.testId) }, by: \.testId)
        var testsOut: [[String: Any]] = []

        for testId in grouped.keys.sorted() {
            guard let meta = definitions[testId],
                  let rawList = grouped[testId],
                  !rawList.isEmpty else { continue }
            let sorted = rawList.sorted { $0.observedAtEpochMs < $1.observedAtEpochMs }
            let limitedAttempts = Array(sorted.suffix(maxAttemptsPerTest))
            guard let latest = limitedAttempts.last else { continue }

            func markText(for rec: TestRecord) -> String {
                let trimmed = rec.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return WebPortalGrades.clip(trimmed, 40) }
                if let val = rec.rawValue {
                    let formatted = formatNumber(val)
                    return meta.unit.isEmpty ? formatted : "\(formatted) \(meta.unit)"
                }
                return "—"
            }

            func entryDict(_ rec: TestRecord) -> [String: Any] {
                var d: [String: Any] = [
                    "fecha": WebPortalGrades.dayString(epochMs: rec.observedAtEpochMs, timeZone: timeZone),
                    "marca": markText(for: rec),
                ]
                if let val = rec.rawValue { d["valor"] = val }
                if let score = rec.score { d["nota"] = (score * 10).rounded() / 10 }
                return d
            }

            var item: [String: Any] = [
                "id": WebPortalGrades.clip(meta.id, 64),
                "nombre": WebPortalGrades.clip(meta.name, 80),
                "capacidad": WebPortalGrades.clip(meta.capacityLabel, 40),
                "unidad": WebPortalGrades.clip(meta.unit, 20),
                "mejorEsMayor": meta.higherIsBetter,
                "actual": entryDict(latest),
                "intentos": limitedAttempts.map(entryDict),
            ]

            if limitedAttempts.count >= 2, let first = limitedAttempts.first {
                item["anterior"] = entryDict(first)
                if let firstVal = first.rawValue, let lastVal = latest.rawValue {
                    let delta = lastVal - firstVal
                    if abs(delta) > 1e-6 {
                        let improved = meta.higherIsBetter ? (delta > 0) : (delta < 0)
                        let sign = delta > 0 ? "+" : "−"
                        let absFormatted = formatNumber(abs(delta))
                        let diffText = meta.unit.isEmpty ? "\(sign)\(absFormatted)" : "\(sign)\(absFormatted) \(meta.unit)"
                        item["diferencia"] = diffText
                        item["mejora"] = improved
                    }
                }
            }
            testsOut.append(item)
            if testsOut.count >= maxTests { break }
        }

        guard !testsOut.isEmpty else { return nil }
        return [
            "actualizado": WebPortalGrades.isoString(now),
            "pruebas": testsOut,
        ]
    }

    /// Normaliza el estado de asistencia. `presente` devuelve `nil` (no se lista como incidencia).
    static func attendanceKind(for rawStatus: String) -> String? {
        let norm = rawStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
        switch norm {
        case "absent", "falta", "ausente", "unjustified":
            return "falta"
        case "late", "retraso", "tarde":
            return "retraso"
        case "excused", "justified", "justificada", "justificado":
            return "justificada"
        case "no_kit", "nokit", "sin_equipacion", "sin equipacion", "sin_ropa", "equipacion":
            return "sin_equipacion"
        default:
            return nil
        }
    }

    /// Bloque `asistencia` de un alumno concreto (solo contadores y fechas recientes, nunca notas privadas).
    static func asistenciaBlock(
        records: [AttendanceItem],
        now: Date = Date(),
        timeZone: Foundation.TimeZone = .current
    ) -> [String: Any]? {
        var faltas = 0
        var retrasos = 0
        var justificadas = 0
        var sinEquipacion = 0
        var events: [(epochMs: Int64, tipo: String)] = []

        for rec in records {
            guard let kind = attendanceKind(for: rec.status) else { continue }
            switch kind {
            case "falta": faltas += 1
            case "retraso": retrasos += 1
            case "justificada": justificadas += 1
            case "sin_equipacion": sinEquipacion += 1
            default: break
            }
            events.append((rec.dateEpochMs, kind))
        }

        let recent = events
            .sorted { $0.epochMs > $1.epochMs }
            .prefix(maxRecentAttendance)
            .map { event -> [String: Any] in
                [
                    "fecha": WebPortalGrades.dayString(epochMs: event.epochMs, timeZone: timeZone),
                    "tipo": event.tipo,
                ]
            }

        return [
            "actualizado": WebPortalGrades.isoString(now),
            "resumen": [
                "faltas": faltas,
                "retrasos": retrasos,
                "justificadas": justificadas,
                "sinEquipacion": sinEquipacion,
            ],
            "recientes": recent,
        ]
    }

    static func digest(fisica: [String: Any]?, asistencia: [String: Any]?) -> String {
        var wrapper: [String: Any] = [:]
        if var f = fisica {
            f.removeValue(forKey: "actualizado")
            wrapper["fisica"] = f
        }
        if var a = asistencia {
            a.removeValue(forKey: "actualizado")
            wrapper["asistencia"] = a
        }
        guard !wrapper.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return WebPortalCrypto.sha256Hex(text)
    }

    private static func formatNumber(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 2
        return fmt.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

// MARK: - Bloques por grupo y memoria de publicación

struct WebPortalPEBlocks {
    var known = Set<Int64>()
    var fisica: [Int64: [String: Any]] = [:]
    var asistencia: [Int64: [String: Any]] = [:]
    var readClassIds = Set<Int64>()
    var failedClassIds = Set<Int64>()
    var classIdsWithPE = Set<Int64>()

    func fisica(for studentId: Int64) -> [String: Any]? { fisica[studentId] }
    func asistencia(for studentId: Int64) -> [String: Any]? { asistencia[studentId] }
}

final class WebPortalPESummary {
    private var digests: [Int64: String] = [:]

    func hasChanged(studentId: Int64, fisica: [String: Any]?, asistencia: [String: Any]?) -> Bool {
        WebPortalPE.digest(fisica: fisica, asistencia: asistencia) != (digests[studentId] ?? "")
    }

    func record(studentId: Int64, fisica: [String: Any]?, asistencia: [String: Any]?) {
        let d = WebPortalPE.digest(fisica: fisica, asistencia: asistencia)
        if d.isEmpty { digests.removeValue(forKey: studentId) } else { digests[studentId] = d }
    }
}

// MARK: - Puente con KmpBridge (`suspend` en `@MainActor`)

extension KmpBridge {
    @MainActor
    func portalPEOverview(classId: Int64) async -> WebPortalPEOverview? {
        guard let students = try? await container.classesRepository.listStudentsInClass(classId: classId),
              let definitions = try? await container.physicalTestsRepository.listDefinitions(),
              let assignments = try? await container.physicalTestsRepository.listAssignmentsForClass(classId: classId) else {
            return nil
        }
        let defById = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        let batteries = (try? await container.physicalTestsRepository.listBatteries()) ?? []
        let batteryById = Dictionary(uniqueKeysWithValues: batteries.map { ($0.id, $0) })
        var studentsByTest: [String: Set<Int64>] = [:]
        var assignmentsByTest: [String: Set<String>] = [:]

        for assignment in assignments {
            if let battery = batteryById[assignment.batteryId] {
                for testId in battery.testIds {
                    assignmentsByTest[testId, default: []].insert(assignment.id)
                }
            }
            let results = (try? await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignment.id)) ?? []
            for res in results {
                assignmentsByTest[res.testId, default: []].insert(assignment.id)
                if res.rawValue != nil || !res.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    studentsByTest[res.testId, default: []].insert(res.studentId)
                }
            }
        }

        let rows: [WebPortalPETestRow] = assignmentsByTest.keys.compactMap { testId -> WebPortalPETestRow? in
            guard let def = defById[testId] else { return nil }
            return WebPortalPETestRow(
                id: def.id,
                name: def.name,
                capacityLabel: WebPortalPE.capacityLabel(def.capacity),
                recordedStudents: studentsByTest[testId]?.count ?? 0,
                totalStudents: students.count,
                assignmentCount: max(1, assignmentsByTest[testId]?.count ?? 1)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let attendance = (try? await container.attendanceRepository.listAttendance(classId: classId)) ?? []
        return WebPortalPEOverview(
            classId: classId,
            studentCount: students.count,
            tests: rows,
            hasAttendanceRecords: !attendance.isEmpty
        )
    }

    @MainActor
    func portalPEBlocks(extraClassIds: Set<Int64> = []) async -> WebPortalPEBlocks {
        var result = WebPortalPEBlocks()
        let settings = WebPortalPESettings.standardURL().map { WebPortalPESettings.load(fileURL: $0) } ?? WebPortalPESettings()
        let watcher = WebPortalPEWatcher.shared
        let classIds = settings.activeClassIds
            .union(watcher.publishedState.conEF)
            .union(watcher.publishedState.pendientes)
            .union(extraClassIds)
        guard !classIds.isEmpty else { return result }

        let definitionsList = (try? await container.physicalTestsRepository.listDefinitions()) ?? []
        let defsById: [String: WebPortalPE.TestMeta] = Dictionary(uniqueKeysWithValues: definitionsList.map { def in
            (
                def.id,
                WebPortalPE.TestMeta(
                    id: def.id,
                    name: def.name,
                    capacityLabel: WebPortalPE.capacityLabel(def.capacity),
                    unit: def.unit,
                    higherIsBetter: def.higherIsBetter
                )
            )
        })

        let now = Date()
        for classId in classIds.sorted() {
            let groupSettings = settings[classId]
            guard let students = try? await container.classesRepository.listStudentsInClass(classId: classId) else {
                result.failedClassIds.insert(classId)
                continue
            }
            result.readClassIds.insert(classId)
            for student in students { result.known.insert(student.id) }
            guard groupSettings.hasAnythingActive else { continue }

            var recordsByStudent: [Int64: [WebPortalPE.TestRecord]] = [:]
            if !groupSettings.visibleTestIds.isEmpty,
               let assignments = try? await container.physicalTestsRepository.listAssignmentsForClass(classId: classId) {
                for assignment in assignments {
                    let resList = (try? await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignment.id)) ?? []
                    for r in resList where groupSettings.visibleTestIds.contains(r.testId) {
                        recordsByStudent[r.studentId, default: []].append(WebPortalPE.TestRecord(
                            testId: r.testId,
                            rawValue: r.rawValue?.doubleValue,
                            rawText: r.rawText,
                            score: r.score?.doubleValue,
                            observedAtEpochMs: r.observedAtEpochMs
                        ))
                    }
                }
            }

            var attendanceByStudent: [Int64: [WebPortalPE.AttendanceItem]] = [:]
            if groupSettings.asistencia,
               let rows = try? await container.attendanceRepository.listAttendance(classId: classId) {
                for row in rows {
                    let epochMs = row.date.toEpochMilliseconds()
                    attendanceByStudent[row.studentId, default: []].append(
                        WebPortalPE.AttendanceItem(dateEpochMs: epochMs, status: row.status)
                    )
                }
            }

            var classHasAny = false
            for student in students {
                if !groupSettings.visibleTestIds.isEmpty,
                   let fBlock = WebPortalPE.fisicaBlock(
                    definitions: defsById,
                    records: recordsByStudent[student.id] ?? [],
                    visibleTestIds: groupSettings.visibleTestIds,
                    now: now
                   ) {
                    result.fisica[student.id] = fBlock
                    classHasAny = true
                }
                if groupSettings.asistencia,
                   let aBlock = WebPortalPE.asistenciaBlock(
                    records: attendanceByStudent[student.id] ?? [],
                    now: now
                   ) {
                    result.asistencia[student.id] = aBlock
                    classHasAny = true
                }
            }
            if classHasAny { result.classIdsWithPE.insert(classId) }
        }
        return result
    }

    @MainActor
    func schedulePortalPERepublish(classId: Int64, immediately: Bool) {
        let watcher = WebPortalPEWatcher.shared
        watcher.publish = { [weak self] id in
            guard let self else { return WebPortalGradesPublishStatus() }
            return await self.republishPortalBoards(
                formInstanceIds: nil,
                peClassIds: [id],
                onlyDynamicBlocks: true
            )
        }
        watcher.noteSettingsChange(classId: classId, immediately: immediately)
    }
}
