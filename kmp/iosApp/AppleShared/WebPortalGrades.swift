import Foundation
import MiGestorKit

/// «Mis notas» del portal del alumnado (ticket fase 2, sección 4.1).
///
/// Arma el bloque `notas` del tablón con la misma fuente que el PDF de «Enviar notas al
/// alumnado» (`BuildStudentGradeReportsUseCase`), así valores, niveles y descriptores coinciden.
/// Solo sale una columna si cumple las tres a la vez:
///  1. cuenta en la media de la pestaña activa (`averageExplanation`),
///  2. no está oculta ni archivada,
///  3. tiene su interruptor encendido en `WebPortalGradeSettings`.
/// Nunca salen observaciones, comentarios, Inclusión ni datos brutos: el informe no los lleva.

// MARK: - Valores sencillos (sin Kotlin) para la hoja y los tests

/// Una columna que cuenta en la media, tal como se ve en «Notas visibles».
struct WebPortalGradeColumnRow: Identifiable, Equatable {
    let id: String
    let title: String
    /// «Rúbrica», «Prueba física»…
    let typeLabel: String
    let weightPercent: Int
    /// Alumnos con nota en esta columna.
    let withGrade: Int
    let total: Int
}

struct WebPortalGradeOverview: Equatable {
    let classId: Int64
    let studentCount: Int
    let columns: [WebPortalGradeColumnRow]
}

/// Lo mínimo de una columna que el bloque `notas` necesita.
struct WebPortalGradeColumnMeta: Equatable {
    let id: String
    /// `rubrica`, `prueba_fisica`, `autoevaluacion`, `coevaluacion`, `prueba` o `nota`.
    let tipo: String
    let dateEpochMs: Int64?
}

/// Grupo y materia del bloque `notas`, más las columnas que pueden salir.
struct WebPortalGradeContext {
    let classId: Int64
    let groupName: String
    let subject: String?
    /// Solo columnas visibles (ni ocultas ni archivadas).
    let columns: [String: WebPortalGradeColumnMeta]
}

/// Informe completo de un grupo: contexto, informes por alumno y resumen para la hoja.
struct WebPortalGroupGrades {
    let context: WebPortalGradeContext
    let reports: [StudentGradeReport]
    let overview: WebPortalGradeOverview
    /// Todo el alumnado del grupo, tenga o no informe.
    let studentIds: [Int64]
}

enum WebPortalGrades {

    // MARK: Pestaña activa

    /// Columnas y filas de la pestaña activa, como las enseña el Cuaderno.
    struct Scope {
        let tabId: String?
        /// Todas las columnas de la hoja (el PDF también las recibe todas).
        let allColumns: [NotebookColumnDefinition]
        /// Filas con la Media recalculada solo con las columnas de la pestaña.
        let rows: [NotebookRow]
    }

    /// Misma regla que `NotebookViewModel.withActiveTabAverages`:
    /// pestaña = la recordada o la primera; columna de la pestaña si la lista o si es
    /// compartida sin pestañas. La Media se recalcula con `computeAverageExplanation`.
    static func scope(sheet: NotebookSheet, preferredTabId: String?) -> Scope {
        let tabs = sheet.tabs
        let tabId = preferredTabId.flatMap { wanted in tabs.contains { $0.id == wanted } ? wanted : nil } ?? tabs.first?.id
        let averageColumns: [NotebookColumnDefinition]
        if let tabId {
            averageColumns = sheet.columns.filter { $0.tabIds.contains(tabId) || ($0.sharedAcrossTabs && $0.tabIds.isEmpty) }
        } else {
            averageColumns = sheet.columns
        }
        let rows = sheet.rows.map { row -> NotebookRow in
            let explanation = row.computeAverageExplanation(
                columns: averageColumns,
                calculatedValuesByColumnId: [:],
                numericDrafts: [:]
            )
            return NotebookRow(
                student: row.student,
                cells: row.cells,
                weightedAverage: explanation?.average,
                averageExplanation: explanation,
                persistedCells: row.persistedCells,
                persistedGrades: row.persistedGrades
            )
        }
        return Scope(tabId: tabId, allColumns: sheet.columns, rows: rows)
    }

    // MARK: Columnas que pueden salir

    static func isShowable(_ column: NotebookColumnDefinition) -> Bool {
        !column.isHidden && column.visibility == .visible
    }

    static func tipo(of column: NotebookColumnDefinition) -> String {
        if column.type == .rubric || column.instrumentKind == .rubric { return "rubrica" }
        switch column.instrumentKind {
        case .physicalTest: return "prueba_fisica"
        case .selfAssessment: return "autoevaluacion"
        case .peerAssessment: return "coevaluacion"
        case .writtenTest: return "prueba"
        default: return "nota"
        }
    }

    static func typeLabel(forTipo tipo: String) -> String {
        switch tipo {
        case "rubrica": return "Rúbrica"
        case "prueba_fisica": return "Prueba física"
        case "autoevaluacion": return "Autoevaluación"
        case "coevaluacion": return "Coevaluación"
        case "prueba": return "Prueba escrita"
        default: return "Nota"
        }
    }

    /// Columnas que cuentan en la media de algún alumno (con nota o a la espera de ella)
    /// y se pueden enseñar. Orden del Cuaderno.
    static func overview(classId: Int64, scope: Scope) -> WebPortalGradeOverview {
        var counted: [String: Int] = [:]
        var candidateIds = Set<String>()
        for row in scope.rows {
            guard let explanation = row.averageExplanation else { continue }
            for item in explanation.included {
                candidateIds.insert(item.columnId)
                counted[item.columnId, default: 0] += 1
            }
            for pending in explanation.pendingCells { candidateIds.insert(pending.columnId) }
        }
        let columns = scope.allColumns.filter { candidateIds.contains($0.id) && isShowable($0) }
        let totalWeight = columns.reduce(0.0) { $0 + $1.weight }
        let rows = columns.map { column -> WebPortalGradeColumnRow in
            WebPortalGradeColumnRow(
                id: column.id,
                title: column.title,
                typeLabel: typeLabel(forTipo: tipo(of: column)),
                weightPercent: totalWeight > 0 ? Int((column.weight / totalWeight * 100).rounded()) : 0,
                withGrade: counted[column.id] ?? 0,
                total: scope.rows.count
            )
        }
        return WebPortalGradeOverview(classId: classId, studentCount: scope.rows.count, columns: rows)
    }

    static func context(classId: Int64, groupName: String, subject: String?, scope: Scope) -> WebPortalGradeContext {
        var meta: [String: WebPortalGradeColumnMeta] = [:]
        for column in scope.allColumns where isShowable(column) {
            meta[column.id] = WebPortalGradeColumnMeta(
                id: column.id,
                tipo: tipo(of: column),
                dateEpochMs: column.dateEpochMs?.int64Value
            )
        }
        return WebPortalGradeContext(classId: classId, groupName: groupName, subject: subject, columns: meta)
    }

    // MARK: Carga (fuera del hilo principal)

    /// Hoja completa del grupo sin abrirlo en el Cuaderno. Usa la caché de hojas de Kotlin.
    static func loadGroup(
        container: KmpContainer,
        classId: Int64,
        groupName: String,
        subject: String?,
        preferredTabId: String?,
        withReports: Bool
    ) async -> WebPortalGroupGrades? {
        guard let sheet = try? await container.notebookRepository.loadNotebookSnapshot(classId: classId) else { return nil }
        let scope = scope(sheet: sheet, preferredTabId: preferredTabId)
        let reports = withReports
            ? await KmpBridge.makeGradeReports(container: container, classId: classId, columns: scope.allColumns, rows: scope.rows)
            : []
        return WebPortalGroupGrades(
            context: context(classId: classId, groupName: groupName, subject: subject, scope: scope),
            reports: reports,
            overview: overview(classId: classId, scope: scope),
            studentIds: scope.rows.map { $0.student.id }
        )
    }

    // MARK: Bloque `notas` (4.1)

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// `yyyy-MM-dd` en la zona del docente.
    static func dayString(epochMs: Int64, timeZone: Foundation.TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Bloque `notas` de un alumno, o `nil` si no hay nada que enseñar (la web lo ve como N4).
    static func notasBlock(
        report: StudentGradeReport,
        context: WebPortalGradeContext,
        settings: WebPortalGroupGradeSettings,
        now: Date = Date(),
        timeZone: Foundation.TimeZone = .current
    ) -> [String: Any]? {
        var activities: [[String: Any]] = []
        for instrument in report.instruments {
            guard let meta = context.columns[instrument.columnId],
                  settings.isVisible(columnId: instrument.columnId) else { continue }
            var item: [String: Any] = [
                "titulo": instrument.title,
                "tipo": meta.tipo,
                "valor": instrument.value,
                "nivel": instrument.level.label,
            ]
            if let ms = meta.dateEpochMs { item["fecha"] = dayString(epochMs: ms, timeZone: timeZone) }
            if let rubric = report.rubrics.first(where: { $0.columnId == instrument.columnId }) {
                item["rubrica"] = rubric.criteria.map { criterion -> [String: Any] in
                    var entry: [String: Any] = [
                        "criterio": criterion.name,
                        "nivel": criterion.levelName,
                        "posicion": Int(criterion.levelPosition),
                        "de": Int(criterion.levelCount),
                    ]
                    if let description = criterion.levelDescription, !description.isEmpty {
                        entry["descripcion"] = description
                    }
                    return entry
                }
            }
            activities.append(item)
        }
        guard !activities.isEmpty else { return nil }

        var subject: [String: Any] = ["grupo": context.groupName, "actividades": activities]
        if let name = context.subject, !name.isEmpty { subject["materia"] = name }
        // La media es `finalGrade` del informe, sin recalcular: la misma del Cuaderno y del PDF.
        if settings.media, let grade = report.finalGrade, let level = report.finalLevel {
            subject["media"] = ["valor": grade.doubleValue, "nivel": level.label] as [String: Any]
        }
        return [
            "provisional": true,
            "actualizado": isoString(now),
            "materias": [subject],
        ]
    }

    /// Huella del bloque sin la fecha de actualización: sirve para no subir dos veces lo mismo.
    /// `nil` (sin notas) tiene su propia huella vacía.
    static func digest(of notas: [String: Any]?) -> String {
        guard var notas else { return "" }
        notas.removeValue(forKey: "actualizado")
        guard let data = try? JSONSerialization.data(withJSONObject: notas, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "?" }
        return WebPortalCrypto.sha256Hex(text)
    }
}

// MARK: - Bloques de varios grupos

/// Bloque `notas` de cada alumno de los grupos que se pudieron leer.
struct WebPortalGradeBlocks {
    /// Alumnado de los grupos leídos (con o sin bloque).
    var known = Set<Int64>()
    /// Solo quien tiene algo que enseñar.
    var notas: [Int64: [String: Any]] = [:]
}

extension WebPortalGrades {
    static func blocks(
        group: WebPortalGroupGrades,
        settings: WebPortalGroupGradeSettings,
        now: Date = Date(),
        timeZone: Foundation.TimeZone = .current
    ) -> WebPortalGradeBlocks {
        var result = WebPortalGradeBlocks()
        result.known = Set(group.studentIds)
        for report in group.reports {
            if let block = notasBlock(report: report, context: group.context, settings: settings, now: now, timeZone: timeZone) {
                result.notas[report.studentId] = block
            }
        }
        return result
    }
}

extension KmpBridge {
    /// Informe de «Mis notas» de los grupos pedidos (`nil`: los que tienen alguna columna encendida).
    /// El informe, los cálculos y el JSON van en segundo plano: el hilo principal solo espera.
    func portalGradeBlocks(classIds: Set<Int64>?) async -> WebPortalGradeBlocks {
        guard let url = WebPortalGradeSettings.standardURL() else { return WebPortalGradeBlocks() }
        let settings = WebPortalGradeSettings.load(fileURL: url)
        let wanted = classIds ?? settings.activeClassIds
        guard !wanted.isEmpty else { return WebPortalGradeBlocks() }
        if subjects.isEmpty { try? await refreshSubjects() }

        var result = WebPortalGradeBlocks()
        for classId in wanted.sorted() {
            guard let schoolClass = classes.first(where: { $0.id == classId }) else { continue }
            let groupSettings = settings[classId]
            let subject = schoolClass.subjectId.flatMap { id in subjects.first { $0.id == id.int64Value }?.name }
            let tab = restoredSelectedNotebookTab(forClassId: classId)
            let container = self.container
            let name = schoolClass.name
            let wantsReports = groupSettings.hasActiveColumns
            let group = await Task.detached(priority: .utility) {
                await WebPortalGrades.loadGroup(
                    container: container,
                    classId: classId,
                    groupName: name,
                    subject: subject,
                    preferredTabId: tab,
                    withReports: wantsReports
                )
            }.value
            guard let group else { continue }
            let blocks = await Task.detached(priority: .utility) {
                WebPortalGrades.blocks(group: group, settings: groupSettings)
            }.value
            result.known.formUnion(blocks.known)
            result.notas.merge(blocks.notas) { _, new in new }
        }
        return result
    }

    /// Para la hoja «Notas visibles»: columnas que cuentan en la media del grupo.
    func portalGradeOverview(classId: Int64) async -> WebPortalGradeOverview? {
        let tab = restoredSelectedNotebookTab(forClassId: classId)
        let container = self.container
        let name = classes.first(where: { $0.id == classId })?.name ?? ""
        let group = await Task.detached(priority: .utility) {
            await WebPortalGrades.loadGroup(
                container: container,
                classId: classId,
                groupName: name,
                subject: nil,
                preferredTabId: tab,
                withReports: false
            )
        }.value
        return group?.overview
    }
}

// MARK: - Resumen para no subir duplicados

/// Lo último que se publicó de cada alumno, solo en memoria. Si el bloque `notas` no ha
/// cambiado, ese alumno no se vuelve a subir por culpa de las notas.
struct WebPortalGradesSummary {
    private var published: [Int64: (digest: String, notas: [String: Any])] = [:]

    /// `true` si lo que toca publicar difiere de lo último publicado. Sin nada publicado antes,
    /// «sin notas» no es un cambio.
    func hasChanged(studentId: Int64, notas: [String: Any]?) -> Bool {
        (published[studentId]?.digest ?? "") != WebPortalGrades.digest(of: notas)
    }

    /// Último bloque publicado: sirve si un grupo no se pudo leer y hay que publicar otro
    /// motivo sin borrar las notas que ya se ven.
    func lastNotas(studentId: Int64) -> [String: Any]? { published[studentId]?.notas }

    mutating func record(studentId: Int64, notas: [String: Any]?) {
        if let notas { published[studentId] = (WebPortalGrades.digest(of: notas), notas) } else { published.removeValue(forKey: studentId) }
    }
}
