import Foundation

// Base anónima para comentarios del boletín.
//
// Este archivo no toca KMP ni la base de datos: recibe los datos ya leídos de cada alumno,
// les pone un código («Alumno 01»), borra nombres y datos de contacto de los textos libres
// y construye el texto que el docente copia para pegarlo en una IA externa.
// La clave código → nombre se devuelve aparte y nunca entra en `text`.

struct BulletinBaseAttendance: Equatable {
    var present = 0
    var absent = 0
    var late = 0
    var justified = 0
    var other = 0

    var total: Int { present + absent + late + justified + other }

    /// Porcentaje de sesiones con presencia (un retraso cuenta como presente).
    var presenceRate: Int? {
        guard total > 0 else { return nil }
        return Int((Double(present + late) / Double(total) * 100).rounded())
    }
}

struct BulletinBaseGrade: Equatable {
    let category: String?
    let title: String
    let value: Double
    let weight: Double
    let date: Date
}

struct BulletinBaseSelfAssessment: Equatable {
    let title: String
    /// Media de los ítems 1-4 respondidos; `nil` si no respondió ninguno.
    let scaleAverage: Double?
    let openAnswers: [String]

    var hasAnswers: Bool { scaleAverage != nil || !openAnswers.isEmpty }
}

struct BulletinBaseObservation: Equatable {
    let date: Date
    let text: String
}

struct BulletinBaseStudentInput: Equatable {
    let studentId: Int64
    let firstName: String
    let lastName: String
    var attendance = BulletinBaseAttendance()
    var grades: [BulletinBaseGrade] = []
    var selfAssessments: [BulletinBaseSelfAssessment] = []
    var observations: [BulletinBaseObservation] = []

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BulletinBaseKeyEntry: Identifiable, Equatable {
    let code: String
    let studentName: String
    var id: String { code }
}

struct BulletinBaseReport: Equatable {
    let className: String
    let termLabel: String
    /// Texto anónimo listo para copiar. Nunca contiene la clave.
    let text: String
    /// Clave solo para la pantalla. No se exporta.
    let key: [BulletinBaseKeyEntry]
    let lowDataCodes: [String]
    let evaluableColumnCount: Int
    let selfAssessmentCount: Int
    let generatedAt: Date

    var studentCount: Int { key.count }
}

enum BulletinBaseReportBuilder {
    static let minimumGrades = 3
    static let minimumAttendanceDays = 5
    static let maxObservationsPerStudent = 8
    static let maxObservationLength = 220

    static func build(
        className: String,
        classId: Int64,
        termLabel: String,
        students: [BulletinBaseStudentInput],
        evaluableColumnCount: Int,
        selfAssessmentCount: Int,
        generatedAt: Date = Date()
    ) -> BulletinBaseReport {
        let ordered = codeOrder(students: students, classId: classId)
        let width = max(2, String(ordered.count).count)
        let codes: [(code: String, student: BulletinBaseStudentInput)] = ordered.enumerated().map { index, student in
            (code(for: index + 1, width: width), student)
        }
        let scrubber = BulletinBaseTextScrubber(
            replacements: codes.map { (code: $0.code, firstName: $0.student.firstName, lastName: $0.student.lastName) }
        )

        var lines: [String] = []
        lines.append(contentsOf: instructions)
        lines.append("")
        lines.append("Grupo: \(scrubber.scrub(className)) · Periodo: \(termLabel) · Alumnado: \(codes.count)")

        var lowDataCodes: [String] = []
        for (code, student) in codes {
            let lowData = student.grades.count < minimumGrades || student.attendance.total < minimumAttendanceDays
            if lowData { lowDataCodes.append(code) }
            lines.append("")
            lines.append(contentsOf: studentBlock(code: code, student: student, lowData: lowData, scrubber: scrubber))
        }

        return BulletinBaseReport(
            className: className,
            termLabel: termLabel,
            text: lines.joined(separator: "\n"),
            key: codes.map { BulletinBaseKeyEntry(code: $0.code, studentName: $0.student.fullName) },
            lowDataCodes: lowDataCodes,
            evaluableColumnCount: evaluableColumnCount,
            selfAssessmentCount: selfAssessmentCount,
            generatedAt: generatedAt
        )
    }

    static let instructions: [String] = [
        "INSTRUCCIONES PARA LA IA",
        "Redacta un comentario de boletín (60-90 palabras) para cada alumno o alumna.",
        "Tono cercano y profesional, dirigido a la familia. Marco LOMLOE.",
        "Empieza por un logro, señala un aspecto a mejorar y da una orientación concreta.",
        "No inventes datos. Si una ficha dice «pocos datos», dilo con prudencia.",
        "Usa solo el código de cada ficha; no supongas su género ni su nombre."
    ]

    // MARK: - Orden y códigos

    /// Orden estable pero no alfabético: así el código no delata a nadie por su posición en la lista
    /// y no cambia al recargar el informe.
    static func codeOrder(students: [BulletinBaseStudentInput], classId: Int64) -> [BulletinBaseStudentInput] {
        students.sorted { lhs, rhs in
            let l = stableHash(classId: classId, studentId: lhs.studentId)
            let r = stableHash(classId: classId, studentId: rhs.studentId)
            return l == r ? lhs.studentId < rhs.studentId : l < r
        }
    }

    static func code(for number: Int, width: Int) -> String {
        let digits = String(number)
        return "Alumno " + String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    /// FNV-1a de 64 bits: determinista entre ejecuciones (a diferencia de `Hasher`).
    static func stableHash(classId: Int64, studentId: Int64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(classId)#\(studentId)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - Ficha de cada alumno

    static func studentBlock(
        code: String,
        student: BulletinBaseStudentInput,
        lowData: Bool,
        scrubber: BulletinBaseTextScrubber
    ) -> [String] {
        var lines = ["═══ \(code)\(lowData ? " · pocos datos" : "") ═══"]
        lines.append(attendanceLine(student.attendance))
        lines.append(contentsOf: gradeLines(student.grades, scrubber: scrubber))
        lines.append(contentsOf: selfAssessmentLines(student.selfAssessments, scrubber: scrubber))
        lines.append(contentsOf: observationLines(student.observations, scrubber: scrubber))
        return lines
    }

    static func attendanceLine(_ attendance: BulletinBaseAttendance) -> String {
        guard let rate = attendance.presenceRate else {
            return "Asistencia: sin registros en el periodo"
        }
        let missed = attendance.absent + attendance.justified
        var parts = ["\(rate) % presente"]
        if missed == 0 {
            parts.append("0 faltas")
        } else {
            let label = missed == 1 ? "falta" : "faltas"
            parts.append(attendance.justified > 0
                ? "\(missed) \(label) (\(attendance.justified) justificada\(attendance.justified == 1 ? "" : "s"))"
                : "\(missed) \(label)")
        }
        parts.append("\(attendance.late) retraso\(attendance.late == 1 ? "" : "s")")
        return "Asistencia: " + parts.joined(separator: " · ")
    }

    static func gradeLines(_ grades: [BulletinBaseGrade], scrubber: BulletinBaseTextScrubber) -> [String] {
        guard !grades.isEmpty else { return ["Notas: sin notas evaluables en el periodo"] }
        var header = "Notas: media \(decimal(weightedAverage(grades)))"
        if grades.count < minimumGrades {
            header += " (\(grades.count) nota\(grades.count == 1 ? "" : "s"))"
        } else if let trend = trend(grades) {
            header += " · tendencia: \(trend)"
        }
        var lines = [header]
        var order: [String] = []
        var byCategory: [String: [BulletinBaseGrade]] = [:]
        for grade in grades.sorted(by: { $0.date < $1.date }) {
            let category = grade.category.map(scrubber.scrub)?.nilIfBlank ?? "Sin categoría"
            if byCategory[category] == nil { order.append(category) }
            byCategory[category, default: []].append(grade)
        }
        for category in order {
            let items = (byCategory[category] ?? []).map { "\(scrubber.scrub($0.title)) \(decimal($0.value))" }
            lines.append("  · \(category): " + items.joined(separator: " · "))
        }
        return lines
    }

    static func selfAssessmentLines(
        _ selfAssessments: [BulletinBaseSelfAssessment],
        scrubber: BulletinBaseTextScrubber
    ) -> [String] {
        guard !selfAssessments.isEmpty else { return [] }
        var lines: [String] = []
        for item in selfAssessments {
            let title = scrubber.scrub(item.title)
            guard item.hasAnswers else {
                lines.append("Autoevaluación (\(title)): sin respuesta")
                continue
            }
            if let average = item.scaleAverage {
                lines.append("Autoevaluación (\(title)): media \(decimal(average)) / 4")
            } else {
                lines.append("Autoevaluación (\(title)): solo respuestas abiertas")
            }
            for answer in item.openAnswers {
                lines.append("  · «\(clip(scrubber.scrub(answer)))»")
            }
        }
        return lines
    }

    static func observationLines(
        _ observations: [BulletinBaseObservation],
        scrubber: BulletinBaseTextScrubber
    ) -> [String] {
        let recent = observations
            .sorted { $0.date > $1.date }
            .map { clip(scrubber.scrub($0.text)) }
            .filter { !$0.isEmpty }
        guard !recent.isEmpty else { return ["Observaciones: ninguna en el periodo"] }
        var seen = Set<String>()
        let unique = recent.filter { seen.insert($0.lowercased()).inserted }
        return ["Observaciones:"] + unique.prefix(maxObservationsPerStudent).map { "  · \($0)" }
    }

    // MARK: - Cálculos

    static func weightedAverage(_ grades: [BulletinBaseGrade]) -> Double {
        let totalWeight = grades.reduce(0) { $0 + max($1.weight, 0) }
        guard totalWeight > 0 else {
            return grades.reduce(0) { $0 + $1.value } / Double(grades.count)
        }
        return grades.reduce(0) { $0 + $1.value * max($1.weight, 0) } / totalWeight
    }

    /// Compara la primera mitad de las notas (por fecha) con la segunda.
    static func trend(_ grades: [BulletinBaseGrade]) -> String? {
        guard grades.count >= 4 else { return nil }
        let sorted = grades.sorted { $0.date < $1.date }
        let half = sorted.count / 2
        let first = sorted.prefix(half).map(\.value)
        let second = sorted.suffix(sorted.count - half).map(\.value)
        let delta = second.reduce(0, +) / Double(second.count) - first.reduce(0, +) / Double(first.count)
        if delta > 0.5 { return "sube" }
        if delta < -0.5 { return "baja" }
        return "estable"
    }

    static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    static func clip(_ text: String) -> String {
        let compact = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard compact.count > maxObservationLength else { return compact }
        return String(compact.prefix(maxObservationLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Quita de un texto libre los nombres del alumnado del grupo y los datos de contacto.
struct BulletinBaseTextScrubber {
    private struct Rule {
        let regex: NSRegularExpression
        let replacement: String
    }

    private let rules: [Rule]

    /// Palabras de nombre más cortas que esto no se sustituyen sueltas («de», «la», «Mª»).
    static let minimumTokenLength = 3

    init(replacements: [(code: String, firstName: String, lastName: String)]) {
        // Primero lo más largo (nombre completo), luego apellidos y nombres sueltos.
        var candidates: [(pattern: String, code: String)] = []
        var tokenOwners: [String: Set<String>] = [:]
        for entry in replacements {
            let first = entry.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last = entry.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            for phrase in [ "\(first) \(last)", "\(last), \(first)", "\(last) \(first)", first, last ]
            where phrase.count >= Self.minimumTokenLength && !phrase.hasPrefix(",") {
                candidates.append((phrase, entry.code))
            }
            for token in (first + " " + last).split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
            where token.count >= Self.minimumTokenLength {
                tokenOwners[Self.fold(token), default: []].insert(entry.code)
                candidates.append((token, entry.code))
            }
        }

        // Primero correos, teléfonos y fechas, para que un nombre dentro de un correo no deje el resto a la vista.
        var rules: [Rule] = []
        let fixed: [(String, String)] = [
            (#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, "[correo]"),
            (#"(?<!\d)(?:\+?\d{1,3}[\s.\-]?)?(?:\d[\s.\-]?){8,}\d(?!\d)"#, "[teléfono]"),
            (#"\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b"#, "[fecha]")
        ]
        for (pattern, replacement) in fixed {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                rules.append(Rule(regex: regex, replacement: replacement))
            }
        }

        var seen = Set<String>()
        for candidate in candidates.sorted(by: { $0.pattern.count > $1.pattern.count }) {
            let folded = Self.fold(candidate.pattern)
            guard seen.insert(folded).inserted else { continue }
            // Una palabra suelta que comparten varios alumnos («Martín») no se puede atribuir: se tapa sin código.
            let owners = tokenOwners[folded] ?? [candidate.code]
            let replacement = owners.count > 1 ? "[nombre]" : candidate.code
            guard let regex = Self.wordRegex(for: candidate.pattern) else { continue }
            rules.append(Rule(regex: regex, replacement: NSRegularExpression.escapedTemplate(for: replacement)))
        }

        self.rules = rules
    }

    func scrub(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.replacement)
        }
        return result
    }

    /// Sin tildes ni mayúsculas, para comparar nombres.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
    }

    /// Patrón que encuentra la palabra completa sin importar tildes ni mayúsculas.
    static func wordRegex(for phrase: String) -> NSRegularExpression? {
        var pattern = ""
        for character in phrase {
            if character == " " {
                pattern += #"\s+"#
                continue
            }
            let base = fold(String(character))
            let variants = Set([String(character), base] + (accentVariants[base] ?? []))
            if variants.count == 1 {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
            } else {
                pattern += "[" + variants.sorted().map { NSRegularExpression.escapedPattern(for: $0) }.joined() + "]"
            }
        }
        return try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])"# + pattern + #"(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive]
        )
    }

    private static let accentVariants: [String: [String]] = [
        "a": ["á", "à", "ä", "â"],
        "e": ["é", "è", "ë", "ê"],
        "i": ["í", "ì", "ï", "î"],
        "o": ["ó", "ò", "ö", "ô"],
        "u": ["ú", "ù", "ü", "û"],
        "n": ["ñ"],
        "c": ["ç"]
    ]
}
