import Foundation
import MiGestorKit

/// «Mis notas» del portal del alumnado (ticket fase 2, sección 4.1).
///
/// Arma el bloque `notas` del tablón con la misma fuente que el PDF de «Enviar notas al
/// alumnado» (`BuildStudentGradeReportsUseCase`), así valores, niveles y descriptores coinciden.
/// Solo sale una columna si cumple las tres a la vez:
///  1. cuenta en la media de la pestaña fijada (`averageExplanation`),
///  2. no está oculta ni archivada,
///  3. tiene su interruptor encendido en `WebPortalGradeSettings`.
/// Nunca salen observaciones, comentarios, Inclusión ni datos brutos: el informe no los lleva.
/// La media solo sale si TODAS las columnas que entran en ella se pueden ver y están encendidas.

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
    /// Alumnos sin nota a quienes la columna cuenta como 0 en la media.
    var zeroCount = 0
}

struct WebPortalGradeTab: Identifiable, Equatable {
    let id: String
    let title: String
}

struct WebPortalGradeOverview: Equatable {
    let classId: Int64
    let studentCount: Int
    let columns: [WebPortalGradeColumnRow]
    /// Pestañas del Cuaderno y la que se está usando para la media.
    var tabs: [WebPortalGradeTab] = []
    var tabId: String?
    /// Alguna columna que entra en la media está oculta o archivada: la media no se puede enseñar.
    var hasHiddenCounting = false
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
    /// Notas de celda por alumno y columna (`studentId -> [columnId: note]`).
    /// Solo se exportan si el docente activó explícitamente `mostrarComentarios`.
    var cellNotes: [Int64: [String: String]] = [:]
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
    /// Límites de texto de la web (`entregas-alumnado`).
    static let shortTextLimit = 160
    static let longTextLimit = 600

    // MARK: Pestaña

    /// Columnas y filas de la pestaña elegida, como las enseña el Cuaderno.
    struct Scope {
        let tabId: String?
        let tabs: [WebPortalGradeTab]
        /// Todas las columnas de la hoja (el PDF también las recibe todas).
        let allColumns: [NotebookColumnDefinition]
        /// Filas con la Media recalculada solo con las columnas de la pestaña.
        let rows: [NotebookRow]
    }

    /// Misma regla que `NotebookViewModel.withActiveTabAverages`:
    /// pestaña = la pedida o la primera; columna de la pestaña si la lista o si es
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
        return Scope(
            tabId: tabId,
            tabs: tabs.map { WebPortalGradeTab(id: $0.id, title: $0.title) },
            allColumns: sheet.columns,
            rows: rows
        )
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
        let candidates = scope.allColumns.filter { candidateIds.contains($0.id) }
        let columns = candidates.filter { isShowable($0) }
        let totalWeight = columns.reduce(0.0) { $0 + $1.weight }
        let rows = columns.map { column -> WebPortalGradeColumnRow in
            // Sin nota pero con política «cuenta como 0»: entra en la media con un 0.
            var zeros = 0
            if column.emptyCellPolicy == .countAsZero {
                for row in scope.rows where row.averageExplanation?.included.contains(where: { $0.columnId == column.id }) == true {
                    if row.gradeValueFor(column: column, calculatedValuesByColumnId: [:], numericDrafts: [:]) == nil { zeros += 1 }
                }
            }
            return WebPortalGradeColumnRow(
                id: column.id,
                title: column.title,
                typeLabel: typeLabel(forTipo: tipo(of: column)),
                weightPercent: totalWeight > 0 ? Int((column.weight / totalWeight * 100).rounded()) : 0,
                withGrade: max(0, (counted[column.id] ?? 0) - zeros),
                total: scope.rows.count,
                zeroCount: zeros
            )
        }
        return WebPortalGradeOverview(
            classId: classId,
            studentCount: scope.rows.count,
            columns: rows,
            tabs: scope.tabs,
            tabId: scope.tabId,
            hasHiddenCounting: candidates.contains { !isShowable($0) }
        )
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
        var cellNotes: [Int64: [String: String]] = [:]
        for row in scope.rows {
            var perColumn: [String: String] = [:]
            for cell in row.persistedCells {
                guard meta[cell.columnId] != nil,
                      let raw = cell.annotation?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { continue }
                perColumn[cell.columnId] = raw
            }
            if !perColumn.isEmpty {
                cellNotes[row.student.id] = perColumn
            }
        }
        return WebPortalGradeContext(
            classId: classId,
            groupName: groupName,
            subject: subject,
            columns: meta,
            cellNotes: cellNotes
        )
    }

    // MARK: Carga (`suspend` de Kotlin en `@MainActor`; cálculos en segundo plano)

    /// Hoja completa del grupo sin abrirlo en el Cuaderno. Usa la caché de hojas de Kotlin.
    /// `loadNotebookSnapshot` y `makeGradeReports` invocan funciones `suspend` de Kotlin, que
    /// Kotlin/Native exige lanzar desde `@MainActor` (el repositorio ya salta a `Dispatchers.Default`).
    @MainActor
    static func loadGroup(
        container: KmpContainer,
        classId: Int64,
        groupName: String,
        subject: String?,
        preferredTabId: String?,
        withReports: Bool
    ) async -> WebPortalGroupGrades? {
        guard let sheet = try? await container.notebookRepository.loadNotebookSnapshot(classId: classId) else { return nil }
        let prepared = await Task.detached(priority: .utility) {
            let scope = WebPortalGrades.scope(sheet: sheet, preferredTabId: preferredTabId)
            return (
                scope: scope,
                context: WebPortalGrades.context(classId: classId, groupName: groupName, subject: subject, scope: scope),
                overview: WebPortalGrades.overview(classId: classId, scope: scope),
                studentIds: scope.rows.map { $0.student.id }
            )
        }.value
        let reports = withReports
            ? await KmpBridge.makeGradeReports(
                container: container,
                classId: classId,
                columns: prepared.scope.allColumns,
                rows: prepared.scope.rows
            )
            : []
        return WebPortalGroupGrades(
            context: prepared.context,
            reports: reports,
            overview: prepared.overview,
            studentIds: prepared.studentIds
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

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }

    /// La media solo sale si todas las columnas que entran en ella son visibles y están encendidas.
    static func mediaAllowed(report: StudentGradeReport, context: WebPortalGradeContext, settings: WebPortalGroupGradeSettings) -> Bool {
        report.instruments.allSatisfy { context.columns[$0.columnId] != nil && settings.isVisible(columnId: $0.columnId) }
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
                "titulo": clip(instrument.title, shortTextLimit),
                "tipo": meta.tipo,
                "valor": instrument.value,
                "nivel": instrument.level.label,
            ]
            if let ms = meta.dateEpochMs { item["fecha"] = dayString(epochMs: ms, timeZone: timeZone) }
            if let rubric = report.rubrics.first(where: { $0.columnId == instrument.columnId }) {
                item["rubrica"] = rubric.criteria.map { criterion -> [String: Any] in
                    var entry: [String: Any] = [
                        "criterio": clip(criterion.name, shortTextLimit),
                        "nivel": clip(criterion.levelName, shortTextLimit),
                        "posicion": Int(criterion.levelPosition),
                        "de": Int(criterion.levelCount),
                    ]
                    if let description = criterion.levelDescription, !description.isEmpty {
                        entry["descripcion"] = clip(description, longTextLimit)
                    }
                    return entry
                }
            }
            if settings.mostrarComentarios,
               let comment = context.cellNotes[report.studentId]?[instrument.columnId],
               !comment.isEmpty {
                item["comentario"] = clip(comment, longTextLimit)
            }
            activities.append(item)
        }
        guard !activities.isEmpty else { return nil }

        var subject: [String: Any] = ["grupo": clip(context.groupName, shortTextLimit), "actividades": activities]
        // Sin asignatura se omite: nunca se inventa un texto.
        if let name = context.subject, !name.isEmpty { subject["materia"] = clip(name, shortTextLimit) }
        // La media es `finalGrade` del informe, sin recalcular: la misma del Cuaderno y del PDF.
        if settings.media, mediaAllowed(report: report, context: context, settings: settings),
           let grade = report.finalGrade, let level = report.finalLevel {
            subject["media"] = ["valor": grade.doubleValue, "nivel": level.label] as [String: Any]
        }
        return [
            "provisional": true,
            "actualizado": isoString(now),
            "materias": [subject],
        ]
    }

    /// Une los bloques de dos grupos del mismo alumno sin pisar ninguno.
    static func merge(_ first: [String: Any], _ second: [String: Any]) -> [String: Any] {
        var result = first
        result["materias"] = (first["materias"] as? [[String: Any]] ?? []) + (second["materias"] as? [[String: Any]] ?? [])
        return result
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

/// Bloque `notas` de cada alumno de los grupos leídos.
struct WebPortalGradeBlocks {
    /// Alumnado de los grupos que hay que tener en cuenta (con o sin bloque). Incluye el
    /// de los grupos que no se pudieron leer: a esos se les retira todo y se reintenta.
    var known = Set<Int64>()
    /// Solo quien tiene algo que enseñar.
    var notas: [Int64: [String: Any]] = [:]
    /// Grupos que no se pudieron leer.
    var failedClassIds = Set<Int64>()
    /// Grupos leídos en los que alguien tiene notas visibles.
    var classIdsWithNotes = Set<Int64>()
    /// Grupos leídos.
    var readClassIds = Set<Int64>()

    /// Lo que debe llevar el tablón de un alumno. Quien no está en `known` (su grupo no se
    /// consideró) no lleva notas: nunca se reutiliza un bloque viejo.
    func notas(for studentId: Int64) -> [String: Any]? {
        known.contains(studentId) ? notas[studentId] : nil
    }

    mutating func add(_ other: WebPortalGradeBlocks) {
        known.formUnion(other.known)
        for (studentId, block) in other.notas {
            notas[studentId] = notas[studentId].map { WebPortalGrades.merge($0, block) } ?? block
        }
        failedClassIds.formUnion(other.failedClassIds)
        classIdsWithNotes.formUnion(other.classIdsWithNotes)
        readClassIds.formUnion(other.readClassIds)
    }
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
        result.readClassIds = [group.context.classId]
        for report in group.reports {
            if let block = notasBlock(report: report, context: group.context, settings: settings, now: now, timeZone: timeZone) {
                result.notas[report.studentId] = block
                result.classIdsWithNotes.insert(group.context.classId)
            }
        }
        return result
    }
}

extension KmpBridge {
    /// Informe de «Mis notas» de todos los grupos que importan: los que tienen alguna columna
    /// encendida, los pedidos, los que esperan publicación y los que ya publicaron notas
    /// (para retirarlas si ahora están apagados). El informe, los cálculos y el JSON van en
    /// segundo plano: el hilo principal solo espera.
    func portalGradeBlocks(extraClassIds: Set<Int64> = []) async -> WebPortalGradeBlocks {
        guard let url = WebPortalGradeSettings.standardURL() else { return WebPortalGradeBlocks() }
        let settings = WebPortalGradeSettings.load(fileURL: url)
        let watcher = WebPortalGradesWatcher.shared
        let wanted = settings.activeClassIds
            .union(extraClassIds)
            .union(watcher.debouncer.pendingClassIds)
            .union(watcher.publishedState.conNotas)
        guard !wanted.isEmpty else { return WebPortalGradeBlocks() }
        if subjects.isEmpty { try? await refreshSubjects() }

        var result = WebPortalGradeBlocks()
        for classId in wanted.sorted() {
            guard let schoolClass = classes.first(where: { $0.id == classId }) else { continue }
            let groupSettings = settings[classId]
            let subject = schoolClass.subjectId.flatMap { id in subjects.first { $0.id == id.int64Value }?.name }
            // La pestaña publicada es la fijada al encender la primera columna.
            let tab = groupSettings.pestana ?? restoredSelectedNotebookTab(forClassId: classId)
            let container = self.container
            let name = schoolClass.name
            let wantsReports = groupSettings.hasActiveColumns
            let group = await WebPortalGrades.loadGroup(
                container: container,
                classId: classId,
                groupName: name,
                subject: subject,
                preferredTabId: tab,
                withReports: wantsReports
            )
            guard let group else {
                // No se pudo leer: a su alumnado se le retira todo y se reintenta.
                var failed = WebPortalGradeBlocks()
                failed.failedClassIds = [classId]
                if let roster = try? await container.classesRepository.listStudentsInClass(classId: classId) {
                    failed.known = Set(roster.map(\.id))
                }
                result.add(failed)
                continue
            }
            let blocks = await Task.detached(priority: .utility) {
                WebPortalGrades.blocks(group: group, settings: groupSettings)
            }.value
            result.add(blocks)
        }
        return result
    }

    /// Para la hoja «Notas visibles»: columnas que cuentan en la media del grupo.
    func portalGradeOverview(classId: Int64, tabId: String?) async -> WebPortalGradeOverview? {
        let tab = tabId ?? restoredSelectedNotebookTab(forClassId: classId)
        let container = self.container
        let name = classes.first(where: { $0.id == classId })?.name ?? ""
        let group = await WebPortalGrades.loadGroup(
            container: container,
            classId: classId,
            groupName: name,
            subject: nil,
            preferredTabId: tab,
            withReports: false
        )
        return group?.overview
    }
}

// MARK: - Resumen para no subir duplicados

/// Lo último que se publicó de cada alumno, solo en memoria. Si el bloque `notas` no ha
/// cambiado, ese alumno no se vuelve a subir por culpa de las notas. Tras arrancar no se sabe
/// qué hay publicado: la primera pasada siempre publica.
struct WebPortalGradesSummary {
    private var published: [Int64: String] = [:]

    /// `true` si lo que toca publicar difiere de lo último publicado, o si aún no se sabe.
    func hasChanged(studentId: Int64, notas: [String: Any]?) -> Bool {
        published[studentId] != WebPortalGrades.digest(of: notas)
    }

    mutating func record(studentId: Int64, notas: [String: Any]?) {
        published[studentId] = WebPortalGrades.digest(of: notas)
    }
}
