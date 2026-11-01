import Foundation

/// Lee un baremo de condición física desde una hoja (.xlsx o .csv).
///
/// Formato: una fila por tramo con las columnas
/// `Curso · Sexo · Edad desde · Edad hasta · Marca desde · Marca hasta · Nota`.
/// Solo «Nota» y una de las dos marcas son obligatorias. Las filas se agrupan
/// por curso, sexo y edad; cada grupo acaba siendo un `PhysicalTestScale`.
///
/// No depende de KMP para poder probarlo sin base de datos.
enum PhysicalScaleSpreadsheetImport {
    struct Range: Hashable {
        var minValue: Double?
        var maxValue: Double?
        var score: Double
        /// Fila del archivo (1 = primera fila) para poder señalarla en los errores.
        var row: Int
    }

    struct Group: Hashable, Identifiable {
        var course: Int?
        var ageFrom: Int?
        var ageTo: Int?
        /// `FEMALE`, `MALE` o `nil` (vale para todo el alumnado).
        var sex: String?
        var ranges: [Range]

        var id: String { key }

        /// Clave estable para el id del baremo: reimportar sobrescribe el mismo grupo.
        var key: String {
            [
                course.map { "c\($0)" } ?? "call",
                sex.map { $0.lowercased() } ?? "sall",
                ageFrom.map { "a\($0)" } ?? "a",
                ageTo.map { "\($0)" } ?? ""
            ].joined(separator: "_")
        }

        var courseLabel: String {
            course.map { "\($0)º" } ?? "Todos los cursos"
        }

        var sexLabel: String {
            switch sex {
            case "FEMALE": return "Chicas"
            case "MALE": return "Chicos"
            default: return "Todos"
            }
        }

        var title: String {
            var parts = [courseLabel, sexLabel]
            switch (ageFrom, ageTo) {
            case let (from?, to?) where from == to: parts.append("\(from) años")
            case let (from?, to?): parts.append("\(from)-\(to) años")
            case let (from?, nil): parts.append("desde \(from) años")
            case let (nil, to?): parts.append("hasta \(to) años")
            default: break
            }
            return parts.joined(separator: " · ")
        }
    }

    struct Issue: Hashable, Identifiable {
        var row: Int?
        var message: String

        var id: String { "\(row ?? 0)-\(message)" }

        /// Frase completa, también para VoiceOver.
        var text: String {
            row.map { "Fila \($0): \(message)" } ?? message
        }
    }

    struct Result: Hashable {
        var groups: [Group]
        var errors: [Issue]
        var warnings: [Issue]

        var rangeCount: Int { groups.reduce(0) { $0 + $1.ranges.count } }
        var isValid: Bool { errors.isEmpty && !groups.isEmpty }
        var courses: [Int?] { Array(Set(groups.map(\.course))).sorted { ($0 ?? -1) < ($1 ?? -1) } }
        var sexes: [String?] {
            let order: [String?] = ["FEMALE", "MALE", nil]
            return order.filter { sex in groups.contains { $0.sex == sex } }
        }
    }

    // MARK: - Lectura

    static func parse(url: URL) throws -> Result {
        parse(rows: try AppleSpreadsheetReader.readRows(from: url))
    }

    static func parse(rows: [[String]]) -> Result {
        guard let header = findHeader(in: rows) else {
            return Result(
                groups: [],
                errors: [Issue(row: nil, message: "No encuentro las columnas «Marca desde», «Marca hasta» y «Nota». Usa la plantilla.")],
                warnings: []
            )
        }

        var errors: [Issue] = []
        var parsed: [(group: GroupKey, range: Range)] = []

        for index in (header.rowIndex + 1)..<rows.count {
            let cells = rows[index]
            let rowNumber = index + 1
            func cell(_ column: Column) -> String {
                guard let position = header.columns[column], position < cells.count else { return "" }
                return cells[position].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if Column.allCases.allSatisfy({ cell($0).isEmpty }) { continue }

            var rowErrors: [String] = []

            let course = parseCourse(cell(.course), errors: &rowErrors)
            let sex = parseSex(cell(.sex), errors: &rowErrors)
            var ageFrom = parseAge(cell(.ageFrom), label: "Edad desde", errors: &rowErrors)
            var ageTo = parseAge(cell(.ageTo), label: "Edad hasta", errors: &rowErrors)
            if ageFrom == nil, ageTo == nil, !cell(.age).isEmpty {
                (ageFrom, ageTo) = parseAgeSpan(cell(.age), errors: &rowErrors)
            }
            let minValue = parseMark(cell(.minValue), label: "Marca desde", errors: &rowErrors)
            let maxValue = parseMark(cell(.maxValue), label: "Marca hasta", errors: &rowErrors)
            let scoreText = cell(.score)
            let score = parseNumber(scoreText)

            if scoreText.isEmpty {
                rowErrors.append("falta la nota")
            } else if let score, !(0...10).contains(score) {
                rowErrors.append("la nota debe ir de 0 a 10")
            } else if score == nil {
                rowErrors.append("la nota «\(scoreText)» no es un número")
            }
            if cell(.minValue).isEmpty, cell(.maxValue).isEmpty {
                rowErrors.append("falta la marca")
            }
            if let minValue, let maxValue, minValue > maxValue {
                rowErrors.append("«Desde» es mayor que «Hasta»")
            }

            if rowErrors.isEmpty, let score {
                parsed.append((
                    GroupKey(course: course, ageFrom: ageFrom, ageTo: ageTo, sex: sex),
                    Range(minValue: minValue, maxValue: maxValue, score: score, row: rowNumber)
                ))
            } else {
                errors.append(contentsOf: rowErrors.map { Issue(row: rowNumber, message: $0) })
            }
        }

        var warnings: [Issue] = []
        var groupsByKey: [GroupKey: [Range]] = [:]
        var order: [GroupKey] = []
        for item in parsed {
            if groupsByKey[item.group] == nil { order.append(item.group) }
            groupsByKey[item.group, default: []].append(item.range)
        }

        let groups: [Group] = order.map { key in
            let ranges = (groupsByKey[key] ?? []).sorted { lhs, rhs in
                (lhs.minValue ?? -.infinity, lhs.row) < (rhs.minValue ?? -.infinity, rhs.row)
            }
            let group = Group(course: key.course, ageFrom: key.ageFrom, ageTo: key.ageTo, sex: key.sex, ranges: ranges)
            checkContinuity(group, errors: &errors, warnings: &warnings)
            return group
        }

        if groups.isEmpty, errors.isEmpty {
            errors.append(Issue(row: nil, message: "El archivo no tiene ningún tramo debajo de la cabecera."))
        }

        return Result(
            groups: groups.sorted { ($0.course ?? -1, $0.sex ?? "~", $0.ageFrom ?? -1) < ($1.course ?? -1, $1.sex ?? "~", $1.ageFrom ?? -1) },
            errors: errors.sorted { ($0.row ?? 0) < ($1.row ?? 0) },
            warnings: warnings
        )
    }

    // MARK: - Plantilla

    static let templateFileName = "plantilla_baremo_prueba_fisica.csv"

    /// CSV con punto y coma y coma decimal: es lo que abre bien el Excel en español.
    static let templateCSV = """
    Curso;Sexo;Edad desde;Edad hasta;Marca desde;Marca hasta;Nota
    1º ESO;Chica;;;0;99;2
    1º ESO;Chica;;;100;124;4
    1º ESO;Chica;;;125;144;5
    1º ESO;Chica;;;145;159;7
    1º ESO;Chica;;;160;;10
    1º ESO;Chico;;;0;109;2
    1º ESO;Chico;;;110;134;4
    1º ESO;Chico;;;135;154;5
    1º ESO;Chico;;;155;169;7
    1º ESO;Chico;;;170;;10

    """

    static func writeTemplate() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(templateFileName)
        // BOM para que Excel lea bien las tildes del CSV.
        try Data(("\u{FEFF}" + templateCSV).utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Cabecera

    private enum Column: CaseIterable {
        case course, sex, ageFrom, ageTo, age, minValue, maxValue, score
    }

    private struct GroupKey: Hashable {
        var course: Int?
        var ageFrom: Int?
        var ageTo: Int?
        var sex: String?
    }

    private struct Header {
        var rowIndex: Int
        var columns: [Column: Int]
    }

    /// Alias admitidos por columna, ya normalizados (sin tildes, en minúsculas).
    /// El orden importa: las edades se miran antes que «desde/hasta» sueltos.
    private static let aliases: [(Column, [String])] = [
        (.course, ["curso", "nivel educativo"]),
        (.sex, ["sexo", "genero"]),
        (.ageFrom, ["edad desde", "edad minima", "edad min", "edad de"]),
        (.ageTo, ["edad hasta", "edad maxima", "edad max", "edad a"]),
        (.age, ["edad", "edades"]),
        (.minValue, ["marca desde", "desde", "minimo", "min", "valor desde", "valor minimo", "marca minima", "de"]),
        (.maxValue, ["marca hasta", "hasta", "maximo", "max", "valor hasta", "valor maximo", "marca maxima", "a"]),
        (.score, ["nota", "puntuacion", "calificacion", "puntos", "score"])
    ]

    private static func findHeader(in rows: [[String]]) -> Header? {
        for (rowIndex, row) in rows.prefix(10).enumerated() {
            var columns: [Column: Int] = [:]
            for (position, raw) in row.enumerated() {
                let name = normalizedHeader(raw)
                guard !name.isEmpty else { continue }
                if let column = aliases.first(where: { columns[$0.0] == nil && $0.1.contains(name) })?.0 {
                    columns[column] = position
                }
            }
            if columns[.score] != nil, columns[.minValue] != nil || columns[.maxValue] != nil {
                return Header(rowIndex: rowIndex, columns: columns)
            }
        }
        return nil
    }

    private static func normalizedHeader(_ raw: String) -> String {
        // «Desde (cm)» → «desde»
        let withoutUnits = raw.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        return withoutUnits
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Celdas

    private static func parseCourse(_ text: String, errors: inout [String]) -> Int? {
        guard !text.isEmpty else { return nil }
        if isAllMarker(text) { return nil }
        guard let match = text.range(of: #"\d+"#, options: .regularExpression), let value = Int(text[match]) else {
            errors.append("el curso «\(text)» no tiene número")
            return nil
        }
        return value
    }

    private static func parseSex(_ text: String, errors: inout [String]) -> String? {
        let value = normalizedHeader(text)
        if value.isEmpty || isAllMarker(text) { return nil }
        if ["chica", "chicas", "f", "mujer", "mujeres", "femenino", "fem", "female", "nina", "ninas"].contains(value) {
            return "FEMALE"
        }
        if ["chico", "chicos", "m", "h", "v", "hombre", "hombres", "masculino", "masc", "male", "nino", "ninos", "varon"].contains(value) {
            return "MALE"
        }
        errors.append("no entiendo el sexo «\(text)» (usa Chica, Chico o déjalo vacío)")
        return nil
    }

    private static func isAllMarker(_ text: String) -> Bool {
        ["todos", "todas", "mixto", "ambos", "-", "*"].contains(normalizedHeader(text))
    }

    private static func parseAge(_ text: String, label: String, errors: inout [String]) -> Int? {
        guard !text.isEmpty else { return nil }
        guard let value = parseNumber(text), value >= 0, value == value.rounded() else {
            errors.append("«\(label)» debe ser un número entero")
            return nil
        }
        return Int(value)
    }

    /// Columna única «Edad»: «12» o «12-13».
    private static func parseAgeSpan(_ text: String, errors: inout [String]) -> (Int?, Int?) {
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == "–" || $0 == "/" }).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let ages = parts.compactMap { Int($0) }
        guard ages.count == parts.count, (1...2).contains(ages.count) else {
            errors.append("no entiendo la edad «\(text)» (usa 12 o 12-13)")
            return (nil, nil)
        }
        return (ages.first, ages.last)
    }

    private static func parseMark(_ text: String, label: String, errors: inout [String]) -> Double? {
        guard !text.isEmpty, !["∞", "-", "—", "+"].contains(text) else { return nil }
        guard let value = parseNumber(text) else {
            errors.append("«\(label)» «\(text)» no es un número")
            return nil
        }
        return value
    }

    /// Acepta coma o punto decimal y tiempos `1:45`, `1'45` o `1:45,5` (en segundos).
    static func parseNumber(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        let timeParts = cleaned.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "'" || $0 == "’" })
        if timeParts.count == 2,
           let minutes = Int(timeParts[0]),
           let seconds = Double(timeParts[1].replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\"", with: "")),
           seconds < 60 {
            return Double(minutes) * 60 + seconds
        }

        var normalized = cleaned
        if normalized.contains(","), normalized.contains(".") {
            // 1.234,5 → 1234.5
            normalized = normalized.replacingOccurrences(of: ".", with: "")
        }
        normalized = normalized.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    // MARK: - Tramos

    private static func checkContinuity(_ group: Group, errors: inout [Issue], warnings: inout [Issue]) {
        for (previous, current) in zip(group.ranges, group.ranges.dropFirst()) {
            guard let previousMax = previous.maxValue else {
                errors.append(Issue(row: current.row, message: "se pisa con la fila \(previous.row), que no tiene «Hasta»"))
                continue
            }
            guard let currentMin = current.minValue else {
                errors.append(Issue(row: current.row, message: "se pisa con la fila \(previous.row) (falta «Desde»)"))
                continue
            }
            if currentMin < previousMax {
                errors.append(Issue(
                    row: current.row,
                    message: "se pisa con la fila \(previous.row) (\(format(currentMin)) a \(format(previousMax)))"
                ))
                continue
            }
            // Un hueco del tamaño del último decimal escrito (99 → 100, 2,5 → 2,6) es lo normal.
            let step = pow(10, -Double(max(decimals(of: previousMax), decimals(of: currentMin))))
            if currentMin - previousMax > step + 0.000_001 {
                warnings.append(Issue(
                    row: current.row,
                    message: "hueco entre \(format(previousMax)) y \(format(currentMin)) en \(group.title). Esas marcas no tendrán nota."
                ))
            }
        }
    }

    private static func decimals(of value: Double) -> Int {
        for places in 0...4 {
            let scaled = value * pow(10, Double(places))
            if abs(scaled - scaled.rounded()) < 0.000_001 { return places }
        }
        return 4
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
