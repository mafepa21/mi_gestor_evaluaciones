import Foundation
import MiGestorKit

// Lógica sin vistas de «Exportar a Educamos» con pestañas de evaluación (ADR 003):
// qué pestaña corresponde a cada SA, qué columna del Cuaderno corresponde a cada instrumento,
// extracción de nota siempre sobre 10, de qué evaluación sale la nota final y qué hacer
// con la nota de un alumno al que le falta un bloque.

enum EducamosSATabMatcher {
    /// Grupos de sinónimos habituales ES/EN en Situaciones de Aprendizaje de EF y materias comunes.
    private static let synonymGroups: [[String]] = [
        ["hand", "handball", "balonmano"],
        ["basket", "basketball", "baloncesto"],
        ["beis", "beisbol", "baseball", "bateo", "softbol", "softball"],
        ["hock", "hockey", "floorball", "stick"],
        ["bad", "badminton", "raqueta"],
        ["ultim", "ultimate", "frisbee", "disco volador"],
        ["voley", "voleibol", "volleyball"],
        ["fut", "futbol", "futsal", "football", "soccer"],
        ["acro", "acrosport", "gimnasia", "gimnasticas"],
        ["atle", "atletismo"],
        ["orient", "orientacion"],
        ["expres", "expresion", "coreografia", "danza"]
    ]

    /// «SA2 Hockey», «SA 2 - Hockey», «S.A. 2: Hockey» → «hockey». Sin tildes ni mayúsculas.
    /// El prefijo exige número o signo detrás: «Salto» no pierde su «Sa».
    static func normalizedName(_ text: String) -> String {
        var value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: #"^(s\.?\s*a\.?|u\.?\s*d\.?)\s*(\d+|[-:.·])\s*[-:.·]?\s*"#, options: .regularExpression),
           range.upperBound < value.endIndex {
            value = String(value[range.upperBound...])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pestañas que pueden ser una SA: bloques y pestañas sueltas, nunca una evaluación (su
    /// media es la nota final, no la de una SA).
    static func candidateTabs(_ tabs: [NotebookTab]) -> [NotebookTab] {
        let evaluation = NotebookEvaluation.shared
        return tabs
            .filter { !evaluation.isEvaluationTab(tabs: tabs, tabId: $0.id) }
            .sorted { ($0.parentTabId ?? "", $0.order, $0.id) < ($1.parentTabId ?? "", $1.order, $1.id) }
    }

    /// Propuesta por nombre corto y/o descripción completa del Excel: igual tras normalizar,
    /// coincidencia de prefijo/palabra o sinónimo bilingüe de deporte/unidad.
    static func propose(
        shortName: String,
        fullName: String? = nil,
        tabs: [NotebookTab],
        excludingTabIds: Set<String> = []
    ) -> NotebookTab? {
        let candidates = candidateTabs(tabs).filter { !excludingTabIds.contains($0.id) }
        guard !candidates.isEmpty else { return nil }

        let queries = [fullName, Optional(shortName)]
            .compactMap { $0 }
            .map(normalizedName)
            .filter { !$0.isEmpty }

        guard !queries.isEmpty else { return nil }

        // 1. Coincidencia exacta
        for query in queries {
            if let exact = candidates.first(where: { normalizedName($0.title) == query }) {
                return exact
            }
        }

        // 2. Contención directa (mínimo 3 caracteres para evitar falsos positivos)
        for query in queries where query.count >= 3 {
            if let contained = candidates.first(where: { tab in
                let title = normalizedName(tab.title)
                return title.count >= 3 && (title.contains(query) || query.contains(title))
            }) {
                return contained
            }
        }

        // 3. Sinónimos bilingües habituales (p. ej. "Hand" <-> "Balonmano", "Beis" <-> "Béisbol")
        for query in queries {
            for group in synonymGroups where group.contains(where: { query == $0 || (query.count >= 4 && $0.hasPrefix(query)) }) {
                if let synMatch = candidates.first(where: { tab in
                    let titleWords = words(in: normalizedName(tab.title))
                    let fullTitle = normalizedName(tab.title)
                    return group.contains { syn in
                        fullTitle.contains(syn) || titleWords.contains(where: { $0.hasPrefix(syn) && syn.count >= 4 })
                    }
                }) {
                    return synMatch
                }
            }
        }

        return nil
    }

    /// «Hockey (1.ª Evaluación)» para un bloque; el título tal cual para una pestaña suelta.
    static func displayTitle(_ tab: NotebookTab, tabs: [NotebookTab]) -> String {
        guard let parentId = tab.parentTabId, let parent = tabs.first(where: { $0.id == parentId }) else { return tab.title }
        return "\(tab.title) (\(parent.title))"
    }

    private static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

// MARK: - Emparejamiento automático de columnas del Cuaderno

enum EducamosColumnMatcher {
    private static let stopWords: Set<String> = [
        "de", "del", "la", "las", "el", "los", "en", "y", "e", "o", "con", "sin",
        "por", "para", "a", "al", "un", "una", "su", "sus", "sa", "ud",
        "rubrica", "rejilla", "instrumento", "ficha", "lista", "cotejo", "prueba", "evaluacion"
    ]

    struct ResolvedElementMatch {
        let element: EducamosSMElement
        let appColumn: NotebookColumnDefinition?
        let appTab: NotebookTab?
        let isCategorySA: Bool
    }

    static func mappingKey(for element: EducamosSMElement) -> String {
        element.uuid ?? "name:\(element.shortName)"
    }

    /// Columnas elegibles manualmente para instrumentos (excluye ocultas, asistencia y texto libre sin nota).
    static func selectableInstrumentColumns(in columns: [NotebookColumnDefinition]) -> [NotebookColumnDefinition] {
        columns.filter { col in
            guard !col.isHidden else { return false }
            guard col.type != .attendance && col.categoryKind != .attendance else { return false }
            if col.type == .text && !col.inputKind.isStructuredInstrument {
                return false
            }
            return true
        }
    }

    /// Columnas elegibles para «Comentarios del profesor»: texto libre (no instrumentos estructurados).
    static func selectableCommentColumns(in columns: [NotebookColumnDefinition]) -> [NotebookColumnDefinition] {
        columns.filter { col in
            !col.isHidden && col.type == .text && !col.inputKind.isStructuredInstrument
        }
    }

    /// Detecta automáticamente las columnas y pestañas del Cuaderno a partir de la plantilla de Educamos,
    /// respetando la agrupación por Situación de Aprendizaje y evitando asignar la misma columna dos veces.
    static func matchElements(
        elements: [EducamosSMElement],
        tabs: [NotebookTab],
        columns: [NotebookColumnDefinition],
        savedMapping: [String: String],
        excelEvaluation: String,
        activeTabId: String?
    ) -> [ResolvedElementMatch] {
        let instrumentCandidates = selectableInstrumentColumns(in: columns)
        let commentCandidates = selectableCommentColumns(in: columns)
        let candidateTabs = EducamosSATabMatcher.candidateTabs(tabs)
        let evaluationTabId = EducamosFinalGradeSource.evaluationTabId(
            tabs: tabs,
            excelEvaluation: excelEvaluation,
            activeTabId: activeTabId
        )

        // 1. Resolver primero las categorías SA (tipo 15) para acotar sus instrumentos hijos
        var resolvedSATabByLetter: [String: NotebookTab] = [:]
        var usedAutoTabIds: Set<String> = []
        let hasSACategories = elements.contains(where: \.isCategoriaSA)

        for element in elements where element.isCategoriaSA {
            let key = mappingKey(for: element)
            if let savedValue = savedMapping[key],
               savedValue.isEmpty || candidateTabs.contains(where: { "tab:\($0.id)" == savedValue }) {
                if let tab = candidateTabs.first(where: { "tab:\($0.id)" == savedValue }) {
                    resolvedSATabByLetter[element.columnLetter] = tab
                    usedAutoTabIds.insert(tab.id)
                }
            } else if let proposed = EducamosSATabMatcher.propose(
                shortName: element.shortName,
                fullName: element.fullName,
                tabs: tabs,
                excludingTabIds: usedAutoTabIds
            ) {
                resolvedSATabByLetter[element.columnLetter] = proposed
                usedAutoTabIds.insert(proposed.id)
            }
        }

        let matchedSATabIds = Set(resolvedSATabByLetter.values.map(\.id))

        // Columnas que pertenecen al trimestre del Excel (si está organizado por evaluaciones)
        let evaluationScopedIds: Set<String>? = {
            guard let evalId = evaluationTabId else { return nil }
            let evalCols = NotebookEvaluation.shared.columnsForEvaluation(
                tabs: tabs,
                columns: instrumentCandidates,
                evaluationTabId: evalId
            )
            return evalCols.isEmpty ? nil : Set(evalCols.map(\.id))
        }()

        // 2. Respetar elecciones manuales de instrumentos antes del emparejamiento automático
        var resolvedInstrumentByLetter: [String: NotebookColumnDefinition?] = [:]
        var usedColumnIds: Set<String> = []

        for element in elements where element.isInstrumento {
            let key = mappingKey(for: element)
            if let savedId = savedMapping[key],
               savedId.isEmpty || instrumentCandidates.contains(where: { $0.id == savedId }) {
                let col = instrumentCandidates.first { $0.id == savedId }
                resolvedInstrumentByLetter[element.columnLetter] = col
                if let col {
                    usedColumnIds.insert(col.id)
                }
            }
        }

        // 3. Emparejar automáticamente los instrumentos restantes por puntuación descendente (1 a 1)
        let pendingInstruments = elements.filter {
            $0.isInstrumento && resolvedInstrumentByLetter[$0.columnLetter] == nil
        }

        struct CandidatePair {
            let elementLetter: String
            let column: NotebookColumnDefinition
            let score: Int
        }

        var scoredPairs: [CandidatePair] = []
        for element in pendingInstruments {
            let pool = candidatePool(
                for: element,
                allCandidates: instrumentCandidates,
                resolvedSATabByLetter: resolvedSATabByLetter,
                matchedSATabIds: matchedSATabIds,
                hasSACategories: hasSACategories,
                evaluationScopedIds: evaluationScopedIds
            )
            let parentTab = element.parentSAColumnLetter.flatMap { resolvedSATabByLetter[$0] }
            for col in pool where !usedColumnIds.contains(col.id) {
                let score = similarityScore(element: element, column: col, saTabTitle: parentTab?.title)
                if score >= 55 {
                    scoredPairs.append(CandidatePair(elementLetter: element.columnLetter, column: col, score: score))
                }
            }
        }

        scoredPairs.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.elementLetter < rhs.elementLetter
        }

        var autoAssignedLetters: Set<String> = []
        for pair in scoredPairs {
            guard !autoAssignedLetters.contains(pair.elementLetter),
                  !usedColumnIds.contains(pair.column.id) else { continue }
            resolvedInstrumentByLetter[pair.elementLetter] = pair.column
            autoAssignedLetters.insert(pair.elementLetter)
            usedColumnIds.insert(pair.column.id)
        }

        // 4. Construir resultado final manteniendo el orden de la plantilla de Educamos
        var results: [ResolvedElementMatch] = []
        for element in elements {
            if element.isInstrumento {
                let col = resolvedInstrumentByLetter[element.columnLetter] ?? nil
                results.append(ResolvedElementMatch(
                    element: element,
                    appColumn: col,
                    appTab: nil,
                    isCategorySA: false
                ))
            } else if element.isCategoriaSA {
                results.append(ResolvedElementMatch(
                    element: element,
                    appColumn: nil,
                    appTab: resolvedSATabByLetter[element.columnLetter],
                    isCategorySA: true
                ))
            } else if element.isComentarios {
                let matchedComment = resolveCommentColumn(
                    element: element,
                    candidates: commentCandidates,
                    savedMapping: savedMapping,
                    evaluationTabId: evaluationTabId,
                    activeTabId: activeTabId
                )
                results.append(ResolvedElementMatch(
                    element: element,
                    appColumn: matchedComment,
                    appTab: nil,
                    isCategorySA: false
                ))
            } else if element.isNotaFinal {
                results.append(ResolvedElementMatch(
                    element: element,
                    appColumn: nil,
                    appTab: nil,
                    isCategorySA: false
                ))
            }
        }

        return results
    }

    // MARK: - Pool y puntuación de similitud

    private static func candidatePool(
        for element: EducamosSMElement,
        allCandidates: [NotebookColumnDefinition],
        resolvedSATabByLetter: [String: NotebookTab],
        matchedSATabIds: Set<String>,
        hasSACategories: Bool,
        evaluationScopedIds: Set<String>?
    ) -> [NotebookColumnDefinition] {
        let basePool: [NotebookColumnDefinition] = {
            guard let scoped = evaluationScopedIds else { return allCandidates }
            let filtered = allCandidates.filter { scoped.contains($0.id) || $0.sharedAcrossTabs }
            return filtered.isEmpty ? allCandidates : filtered
        }()

        guard hasSACategories, let parentLetter = element.parentSAColumnLetter else {
            return basePool
        }

        if let saTab = resolvedSATabByLetter[parentLetter] {
            let tabColumns = basePool.filter { $0.tabIds.contains(saTab.id) || $0.sharedAcrossTabs }
            if !tabColumns.isEmpty {
                return tabColumns
            }
            // Si el docente no separó columnas en la subpestaña, usar las que no sean exclusivas de otra SA
            return basePool.filter { col in
                col.tabIds.isEmpty || !col.tabIds.allSatisfy { matchedSATabIds.contains($0) && $0 != saTab.id }
            }
        } else {
            // La SA de Educamos no existe en el Cuaderno (p. ej. SA1 Béisbol cuando solo existe SA2 Hockey):
            // nunca robar columnas que pertenecen a otra SA sí emparejada.
            guard !matchedSATabIds.isEmpty else { return basePool }
            return basePool.filter { col in
                col.tabIds.isEmpty || !col.tabIds.allSatisfy { matchedSATabIds.contains($0) }
            }
        }
    }

    static func similarityScore(
        element: EducamosSMElement,
        column: NotebookColumnDefinition,
        saTabTitle: String? = nil
    ) -> Int {
        let normColTitle = fold(column.title)
        let colTokens = tokens(column.title)
        let shortNorm = fold(element.shortName)
        let fullNorm = element.fullName.map(fold) ?? ""
        let shortClean = alphanumericOnly(shortNorm)

        var best = 0

        // 1. Coincidencia exacta por título o descripción completa
        if (!shortNorm.isEmpty && normColTitle == shortNorm) || (!fullNorm.isEmpty && normColTitle == fullNorm) {
            best = max(best, 100)
        }

        // 2. Contención directa con la descripción completa de Educamos
        if fullNorm.count >= 4, (normColTitle.contains(fullNorm) || fullNorm.contains(normColTitle)) {
            best = max(best, 90)
        }

        // 3. Coincidencia de palabras / prefijos (>= 3 letras) con nombre corto o descripción completa
        let queryTerms = (tokens(element.shortName) + (element.fullName.map(tokens) ?? []))
            .filter { $0.count >= 3 }
        for term in queryTerms {
            if colTokens.contains(term) {
                best = max(best, 84)
            } else if colTokens.contains(where: { $0.hasPrefix(term) || (term.count >= 4 && term.hasPrefix($0) && $0.count >= 4) }) {
                best = max(best, 78)
            }
        }

        // 4. Coincidencia por siglas / iniciales (p. ej. "CM" / "C.M." -> Competencia Motriz, "A.H" -> Autoevaluación Hockey)
        if shortClean.count >= 2 && shortClean.count <= 4 {
            let colInitials = initials(of: column.title)
            let colWithSAInitials = saTabTitle.map { initials(of: "\(column.title) \($0)") } ?? ""
            if colInitials == shortClean || colWithSAInitials == shortClean {
                best = max(best, 80)
            } else if colInitials.count >= 2 && colInitials.hasPrefix(shortClean) {
                best = max(best, 72)
            }
        }

        // 5. Semántica pedagógica habitual (autoevaluación, coevaluación, rejilla transversal, técnica/motriz, táctica)
        let combinedSignals = Set([shortClean] + tokens(element.shortName) + (element.fullName.map(tokens) ?? []))

        let isSelfSignal = combinedSignals.contains(where: {
            $0 == "aut" || $0 == "auto" || $0.hasPrefix("autoev")
        }) || (shortClean.hasPrefix("a") && shortClean.count == 2 && saTabTitle.map { fold($0).hasPrefix(String(shortClean.suffix(1))) } == true)

        if isSelfSignal && (column.instrumentKind == .selfAssessment || colTokens.contains(where: { $0.hasPrefix("autoev") })) {
            best = max(best, 86)
        }

        let isPeerSignal = combinedSignals.contains(where: { $0 == "coe" || $0.hasPrefix("coev") })
        if isPeerSignal && (column.instrumentKind == .peerAssessment || colTokens.contains(where: { $0.hasPrefix("coev") })) {
            best = max(best, 86)
        }

        let isObservationSignal = combinedSignals.contains(where: {
            $0 == "seg" || $0 == "rej" || $0 == "obs" || $0.hasPrefix("segur") || $0.hasPrefix("rejill") || $0.hasPrefix("observ") || $0.hasPrefix("conviv") || $0 == "fair"
        })
        if isObservationSignal && (
            column.inputKind == .structuredObservation
                || colTokens.contains(where: { $0.hasPrefix("rejill") || $0.hasPrefix("segur") || $0.hasPrefix("observ") || $0 == "fair" })
        ) {
            best = max(best, 76)
        }

        let isMotorTechSignal = combinedSignals.contains(where: {
            $0 == "cm" || $0 == "mo" || $0 == "mot" || $0 == "hab" || $0 == "tec"
                || $0.hasPrefix("motri") || $0.hasPrefix("tecnic") || $0.hasPrefix("habil") || $0.hasPrefix("ejecuc") || $0.hasPrefix("golp")
        })
        if isMotorTechSignal && colTokens.contains(where: {
            $0.hasPrefix("tecnic") || $0.hasPrefix("motri") || $0.hasPrefix("habil") || $0.hasPrefix("ejecuc")
                || $0.hasPrefix("circuit") || $0.hasPrefix("golp") || $0.hasPrefix("desempen")
        }) {
            best = max(best, 70)
        }

        let isTacticalSignal = combinedSignals.contains(where: {
            $0 == "tt" || $0 == "tg" || $0 == "tac"
                || $0.hasPrefix("tactic") || $0.hasPrefix("grup") || $0.hasPrefix("equip") || $0.hasPrefix("jueg")
        })
        if isTacticalSignal && colTokens.contains(where: {
            $0.hasPrefix("tactic") || $0.hasPrefix("liga") || $0.hasPrefix("jueg") || $0.hasPrefix("decision")
                || $0.hasPrefix("equip") || $0.hasPrefix("grup") || $0.hasPrefix("colectiv")
        }) {
            best = max(best, 70)
        }

        if best > 0, column.countsTowardAverage, column.weight > 0 {
            best += 6
        }

        return best
    }

    private static let evaluationCommentTitle = "Comentario de evaluación"

    private static func findExactCommentColumn(in columns: [NotebookColumnDefinition], tabId: String?) -> NotebookColumnDefinition? {
        columns.first { column in
            column.type == .text
                && column.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(evaluationCommentTitle) == .orderedSame
                && (tabId == nil || column.sharedAcrossTabs || column.tabIds.contains(tabId!))
        }
    }

    private static func resolveCommentColumn(
        element: EducamosSMElement,
        candidates: [NotebookColumnDefinition],
        savedMapping: [String: String],
        evaluationTabId: String?,
        activeTabId: String?
    ) -> NotebookColumnDefinition? {
        let key = mappingKey(for: element)
        if let savedId = savedMapping[key],
           savedId.isEmpty || candidates.contains(where: { $0.id == savedId }) {
            return candidates.first { $0.id == savedId }
        }
        if let evalId = evaluationTabId,
           let col = findExactCommentColumn(in: candidates, tabId: evalId) {
            return col
        }
        if let col = findExactCommentColumn(in: candidates, tabId: activeTabId)
            ?? findExactCommentColumn(in: candidates, tabId: nil) {
            return col
        }
        return candidates.first { col in
            let norm = fold(col.title)
            let matchesTab = evaluationTabId == nil || col.sharedAcrossTabs || col.tabIds.contains(evaluationTabId!)
            return matchesTab && (norm.contains("comentario") || norm.contains("sintesis") || norm.contains("observaciones"))
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func tokens(_ text: String) -> [String] {
        fold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private static func alphanumericOnly(_ text: String) -> String {
        fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private static func initials(of text: String) -> String {
        tokens(text).compactMap { $0.first.map(String.init) }.joined()
    }
}

// MARK: - Extracción de calificaciones siempre en escala 0-10

enum EducamosGradeExtractor {
    /// Extrae la calificación numérica sobre 10 de cualquier instrumento del Cuaderno,
    /// transponiendo automáticamente las rejillas transversales y escalas 1-4 (`(nivel − 1) / 3 × 10`).
    static func gradeOutOfTen(
        row: NotebookRow?,
        column: NotebookColumnDefinition,
        rubricText: String = "",
        numericText: String = ""
    ) -> Double? {
        // 1. Rúbricas (ya están calculadas sobre 10)
        if column.type == .rubric {
            if let parsed = parseGradeNumber(rubricText) {
                return clampZeroToTen(parsed)
            }
            if let persisted = persistedRawGrade(in: row, column: column) {
                return clampZeroToTen(persisted)
            }
            return nil
        }

        // 2. Instrumentos estructurados (rejillas transversales 1-4, autoevaluación 1-4, checklists 0-10)
        //    Funciona tanto si la columna es `.numeric` como si es `.text` con nota derivada.
        if column.inputKind.isStructuredInstrument {
            if let raw = parseGradeNumber(numericText) ?? persistedRawGrade(in: row, column: column) {
                return clampZeroToTen(NotebookStructuredGrade.rescaleIfNeeded(raw, column: column))
            }
            return nil
        }

        // 3. Columnas numéricas (incluidas las de escala 1-4 `FOUR_LEVEL`)
        if column.type == .numeric {
            guard column.inputKind != .time else { return nil }
            if let raw = parseGradeNumber(numericText) ?? persistedRawGrade(in: row, column: column) {
                return clampZeroToTen(NotebookStructuredGrade.rescaleIfNeeded(raw, column: column))
            }
            return nil
        }

        // 4. Columnas calculadas por fórmula
        if column.type == .calculated {
            if let kmpValue = row?.gradeValueFor(column: column, calculatedValuesByColumnId: [:], numericDrafts: [:])?.doubleValue {
                return clampZeroToTen(kmpValue)
            }
            if let raw = parseGradeNumber(numericText) ?? persistedRawGrade(in: row, column: column) {
                return clampZeroToTen(raw)
            }
            return nil
        }

        // 5. Casillas Sí/No (solo si el docente registró un valor explícito en la celda)
        if column.type == .check {
            if let checked = row?.persistedCells.first(where: { $0.columnId == column.id })?.boolValue?.boolValue {
                return checked ? 10.0 : 0.0
            }
            return nil
        }

        // 6. Columnas ordinales evaluables
        if let kmpValue = row?.gradeValueFor(column: column, calculatedValuesByColumnId: [:], numericDrafts: [:])?.doubleValue {
            return clampZeroToTen(kmpValue)
        }

        return nil
    }

    /// Parsea una calificación numérica admitiendo coma o punto decimal y sufijos como «/ 10».
    static func parseGradeNumber(_ raw: String) -> Double? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func persistedRawGrade(in row: NotebookRow?, column: NotebookColumnDefinition) -> Double? {
        guard let row else { return nil }
        if let direct = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
            return direct
        }
        if let evalId = column.evaluationId?.int64Value {
            if let byEvalGrade = row.persistedGrades.first(where: { $0.evaluationId?.int64Value == evalId })?.value?.doubleValue {
                return byEvalGrade
            }
            if let byCell = row.cells.first(where: { $0.evaluationId == evalId })?.value?.doubleValue {
                return byCell
            }
        }
        return nil
    }

    private static func clampZeroToTen(_ value: Double) -> Double {
        min(max(value, 0.0), 10.0)
    }
}

enum EducamosFinalGradeSource {
    /// Evaluación cuya nota va a «Nota final»: la del mismo trimestre que el Excel
    /// («1ª Evaluación» → 1.ª Evaluación); si no se reconoce, la de la pestaña abierta.
    static func evaluationTabId(tabs: [NotebookTab], excelEvaluation: String, activeTabId: String?) -> String? {
        let evaluation = NotebookEvaluation.shared
        let roots = tabs.filter { evaluation.isEvaluationTab(tabs: tabs, tabId: $0.id) }
        if let term = EvaluationClosingTerm.from(tabTitle: excelEvaluation),
           let match = roots.first(where: { EvaluationClosingTerm.from(tabTitle: $0.title) == term }) {
            return match.id
        }
        return evaluation.evaluationTabId(tabs: tabs, tabId: activeTabId)
    }
}

/// Qué se escribe en «Nota final» de un alumno al que le falta un bloque.
enum EducamosPartialGradePolicy: String, CaseIterable, Identifiable {
    /// Por defecto: no subir una nota incompleta sin querer.
    case leaveEmpty
    case exportPartial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leaveEmpty: return "Dejarla vacía"
        case .exportPartial: return "Exportar la nota parcial"
        }
    }

    private static func key(classId: Int64) -> String { "educamos.sm.partialFinalGrade.\(classId)" }

    static func load(classId: Int64, defaults: UserDefaults = .standard) -> EducamosPartialGradePolicy {
        defaults.string(forKey: key(classId: classId)).flatMap(EducamosPartialGradePolicy.init(rawValue:)) ?? .leaveEmpty
    }

    func save(classId: Int64, defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key(classId: classId))
    }
}

/// Alumno al que le falta al menos un bloque con peso.
struct EducamosPartialStudent: Identifiable, Equatable {
    let id: Int64
    let name: String
    let missingBlocks: [String]
}
