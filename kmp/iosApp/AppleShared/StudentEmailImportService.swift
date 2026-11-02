//
//  StudentEmailImportService.swift
//  MiGestorKMP
//
//  Created for importing and matching student corporate emails from spreadsheet.
//

import Foundation
@preconcurrency import MiGestorKit

/// Estado de emparejamiento de un correo de la hoja de cálculo con un alumno en el sistema.
public enum StudentEmailMatchStatus: String, CaseIterable, Sendable {
    case matched = "Emparejado"
    case ambiguous = "Dudoso"
    case notFound = "No encontrado"
}

/// Representa una fila procesada del Excel de correos.
public struct StudentEmailRowMatch: Identifiable, Sendable {
    public let id: Int
    public let rowNumber: Int
    public let rawEmail: String
    public let rawCourse: String
    public let extractedFirstName: String
    public let extractedLastName: String
    public let status: StudentEmailMatchStatus
    public let matchedStudent: Student?
    public let matchedClassName: String?
    public let currentEmail: String?
    public let detail: String?

    public init(
        id: Int,
        rowNumber: Int,
        rawEmail: String,
        rawCourse: String,
        extractedFirstName: String,
        extractedLastName: String,
        status: StudentEmailMatchStatus,
        matchedStudent: Student?,
        matchedClassName: String?,
        currentEmail: String?,
        detail: String?
    ) {
        self.id = id
        self.rowNumber = rowNumber
        self.rawEmail = rawEmail
        self.rawCourse = rawCourse
        self.extractedFirstName = extractedFirstName
        self.extractedLastName = extractedLastName
        self.status = status
        self.matchedStudent = matchedStudent
        self.matchedClassName = matchedClassName
        self.currentEmail = currentEmail
        self.detail = detail
    }
}

/// Previsualización global de la importación de correos.
public struct AppleStudentEmailImportPreview: Identifiable, Sendable {
    public let id: UUID
    public let totalRows: Int
    public let matchedCount: Int
    public let notFoundCount: Int
    public let ambiguousCount: Int
    public let items: [StudentEmailRowMatch]

    public init(
        id: UUID = UUID(),
        totalRows: Int,
        matchedCount: Int,
        notFoundCount: Int,
        ambiguousCount: Int,
        items: [StudentEmailRowMatch]
    ) {
        self.id = id
        self.totalRows = totalRows
        self.matchedCount = matchedCount
        self.notFoundCount = notFoundCount
        self.ambiguousCount = ambiguousCount
        self.items = items
    }
}

public enum StudentEmailImportService {

    /// Extrae los componentes de nombre y apellidos a partir de un correo como:
    /// `a.nombre.apellido@dominio` o `a.nombre.apellido.2apellido@dominio`.
    /// Con tres o más trozos, los dos últimos son los apellidos (`a.juan.carlos.garcia.lopez`
    /// -> "Juan Carlos" / "Garcia Lopez").
    public static func parseEmailIdentity(email: String) -> (firstName: String, lastName: String, cleanEmail: String)? {
        guard let (segments, cleanEmail) = emailNameSegments(email: email) else { return nil }
        let primary = splitNameSegments(segments, surnameCount: min(2, segments.count - 1))
        return (primary.firstName, primary.lastName, cleanEmail)
    }

    /// Todas las formas razonables de partir el correo en nombre y apellidos, empezando por la principal.
    /// Cubre alumnado con un solo apellido (`a.juan.carlos.garcia`) y el reparto antiguo (nombre simple).
    public static func candidateEmailIdentities(email: String) -> [(firstName: String, lastName: String)] {
        guard let (segments, _) = emailNameSegments(email: email) else { return [] }
        guard segments.count > 1 else { return [splitNameSegments(segments, surnameCount: 0)] }

        var surnameCounts = [min(2, segments.count - 1), 1, segments.count - 1]
        var seen = Set<Int>()
        surnameCounts = surnameCounts.filter { seen.insert($0).inserted }
        return surnameCounts.map { splitNameSegments(segments, surnameCount: $0) }
    }

    private static func emailNameSegments(email: String) -> (segments: [String], cleanEmail: String)? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else { return nil }

        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }

        let userPart = String(parts[0])
        var segments = userPart.split(separator: ".", omittingEmptySubsequences: true).map(String.init)

        // Descartar prefijo "a" común en correos de alumnos (ej: "a.mario.fernandez")
        if let first = segments.first, first == "a" {
            segments.removeFirst()
        }

        guard !segments.isEmpty else { return nil }
        return (segments, trimmed)
    }

    private static func splitNameSegments(_ segments: [String], surnameCount: Int) -> (firstName: String, lastName: String) {
        let nameCount = segments.count - surnameCount
        let firstName = segments.prefix(nameCount).map { $0.capitalized }.joined(separator: " ")
        let lastName = segments.suffix(surnameCount).map { $0.capitalized }.joined(separator: " ")
        return (firstName, lastName)
    }

    /// Normaliza un texto para comparaciones diacríticas y fonéticas seguras
    public static func normalizeString(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// Compara dos conjuntos de tokens de nombres/apellidos con flexibilidad (ej: "Antonio Jesús" coincide con "antonio")
    public static func matchScore(
        extractedFirst: String,
        extractedLast: String,
        candidateFirst: String,
        candidateLast: String
    ) -> Double {
        let normExtFirst = normalizeString(extractedFirst)
        let normExtLast = normalizeString(extractedLast)
        let normCandFirst = normalizeString(candidateFirst)
        let normCandLast = normalizeString(candidateLast)

        // Exact match completo
        if normExtFirst == normCandFirst && normExtLast == normCandLast {
            return 1.0
        }

        let extFirstTokens = Set(normExtFirst.split(separator: " ").map(String.init))
        let extLastTokens = Set(normExtLast.split(separator: " ").map(String.init))
        let candFirstTokens = Set(normCandFirst.split(separator: " ").map(String.init))
        let candLastTokens = Set(normCandLast.split(separator: " ").map(String.init))

        // Si los apellidos no coinciden en ningún token principal, no es match
        if !normExtLast.isEmpty && !normCandLast.isEmpty {
            let lastIntersection = extLastTokens.intersection(candLastTokens)
            if lastIntersection.isEmpty {
                // Verificar si por azar el primer apellido vino en el primer nombre o viceversa
                let cross1 = extFirstTokens.intersection(candLastTokens)
                let cross2 = extLastTokens.intersection(candFirstTokens)
                if cross1.isEmpty || cross2.isEmpty {
                    return 0.0
                }
            }
        }

        // Token match de nombre
        let firstIntersection = extFirstTokens.intersection(candFirstTokens)
        let lastIntersection = extLastTokens.intersection(candLastTokens)

        var score = 0.0
        if !extFirstTokens.isEmpty && !firstIntersection.isEmpty {
            score += 0.5 * (Double(firstIntersection.count) / Double(max(extFirstTokens.count, candFirstTokens.count)))
        }
        if !extLastTokens.isEmpty && !lastIntersection.isEmpty {
            score += 0.5 * (Double(lastIntersection.count) / Double(max(extLastTokens.count, candLastTokens.count)))
        }

        return score
    }

    /// Normaliza el nombre del curso de la hoja para compararlo con las clases
    public static func normalizeClassName(_ name: String) -> String {
        var normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .uppercased()
            .replacingOccurrences(of: "BATXILLERAT", with: "BAC")
            .replacingOccurrences(of: "BACHILLERATO", with: "BAC")
            .replacingOccurrences(of: "BACH", with: "BAC")
            .replacingOccurrences(of: "º", with: "")
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "PRIMARIA", with: "PRI")
            .replacingOccurrences(of: "SECUNDARIA", with: "ESO")

        normalized = normalized.replacingOccurrences(
            of: #"[\(\)\[\]\-–—_/\\.]+"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convierte el curso de la hoja en una clave compacta de nivel: "/Alumnes/Batxillerat/1BACH 2026-27"
    /// -> "1BAC", "1º ESO A" -> "1ESOA". Se queda con el último trozo de la ruta y quita el año escolar.
    public static func courseKey(_ rawCourse: String) -> String {
        let lastSegment = rawCourse
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? rawCourse
        let withoutSchoolYear = lastSegment.replacingOccurrences(
            of: #"\b\d{4}\s*[-/]\s*\d{2,4}\b"#,
            with: " ",
            options: .regularExpression
        )
        return compactClassKey(withoutSchoolYear)
    }

    private static func compactClassKey(_ name: String) -> String {
        normalizeClassName(name).replacingOccurrences(of: " ", with: "")
    }

    /// Clases que encajan con el curso de la hoja. Si la hoja no distingue grupo (1BACH),
    /// devuelve todos los grupos de ese nivel (1º BACH A, 1º BACH B…).
    public static func matchingClasses(forCourse rawCourse: String, in classes: [SchoolClass]) -> [SchoolClass] {
        let key = courseKey(rawCourse)
        guard !key.isEmpty else { return [] }
        return classes.filter { schoolClass in
            let classKey = compactClassKey(schoolClass.name)
            guard !classKey.isEmpty else { return false }
            return classKey == key || classKey.contains(key) || key.contains(classKey)
        }
    }

    /// Procesa filas de hoja de cálculo y genera la previsualización de emparejamiento.
    public static func buildPreview(
        rows: [[String]],
        classes: [SchoolClass],
        studentsByClass: [Int64: [Student]],
        allStudents: [Student]
    ) -> AppleStudentEmailImportPreview {
        var matches: [StudentEmailRowMatch] = []
        var rowNumber = 0

        for row in rows {
            rowNumber += 1
            guard row.count >= 1 else { continue }
            let colA = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let colB = row.count > 1 ? row[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

            // Ignorar cabeceras o filas vacías
            if colA.isEmpty || colA.localizedCaseInsensitiveContains("correo") || colA.localizedCaseInsensitiveContains("listado") {
                continue
            }

            guard let identity = parseEmailIdentity(email: colA) else {
                continue
            }

            let cleanEmail = identity.cleanEmail
            let extractedFirst = identity.firstName
            let extractedLast = identity.lastName
            let nameVariants = candidateEmailIdentities(email: colA)

            // 1. Identificar las clases del nivel según la columna B (puede haber varios grupos)
            let targetClasses = colB.isEmpty ? [] : matchingClasses(forCourse: colB, in: classes)

            // 2. Determinar el grupo de búsqueda de alumnos: todos los grupos del nivel
            var searchPool: [Student] = []
            var seenStudentIds = Set<Int64>()
            for targetClass in targetClasses {
                for student in studentsByClass[targetClass.id] ?? [] where seenStudentIds.insert(student.id).inserted {
                    searchPool.append(student)
                }
            }
            if searchPool.isEmpty {
                searchPool = allStudents
            }

            // 3. Evaluar emparejamiento contra el searchPool; el nombre del correo decide
            var scoredCandidates: [(student: Student, score: Double)] = []
            for candidate in searchPool {
                let score = nameVariants.map { variant in
                    matchScore(
                        extractedFirst: variant.firstName,
                        extractedLast: variant.lastName,
                        candidateFirst: candidate.firstName,
                        candidateLast: candidate.lastName
                    )
                }.max() ?? 0
                if score >= 0.5 {
                    scoredCandidates.append((candidate, score))
                }
            }

            scoredCandidates.sort { $0.score > $1.score }

            let matchStatus: StudentEmailMatchStatus
            let matchedStudent: Student?
            let detail: String?

            if let best = scoredCandidates.first, best.score >= 0.75 {
                // Verificar si hay empate o ambigüedad
                if scoredCandidates.count > 1 && abs(scoredCandidates[0].score - scoredCandidates[1].score) < 0.1 {
                    matchStatus = .ambiguous
                    matchedStudent = best.student
                    detail = "Ambigüedad con \(scoredCandidates[1].student.fullName)"
                } else {
                    matchStatus = .matched
                    matchedStudent = best.student
                    if let existingEmail = best.student.email, !existingEmail.isEmpty {
                        detail = "Reemplaza: \(existingEmail)"
                    } else {
                        detail = "Nuevo correo asignado"
                    }
                }
            } else if let best = scoredCandidates.first, best.score >= 0.5 {
                matchStatus = .ambiguous
                matchedStudent = best.student
                detail = "Coincidencia parcial (revisar)"
            } else {
                matchStatus = .notFound
                matchedStudent = nil
                detail = targetClasses.isEmpty
                    ? "No encontrado en la app"
                    : "No encontrado en \(targetClasses.map(\.name).joined(separator: ", "))"
            }

            // Grupo real del alumno emparejado (el curso de la hoja puede abarcar varios)
            let matchedClassName: String?
            if let matchedStudent {
                matchedClassName = targetClasses.first(where: { schoolClass in
                    (studentsByClass[schoolClass.id] ?? []).contains(where: { $0.id == matchedStudent.id })
                })?.name
            } else {
                matchedClassName = targetClasses.count == 1 ? targetClasses[0].name : nil
            }

            let item = StudentEmailRowMatch(
                id: rowNumber,
                rowNumber: rowNumber,
                rawEmail: cleanEmail,
                rawCourse: colB,
                extractedFirstName: extractedFirst,
                extractedLastName: extractedLast,
                status: matchStatus,
                matchedStudent: matchedStudent,
                matchedClassName: matchedClassName,
                currentEmail: matchedStudent?.email,
                detail: detail
            )
            matches.append(item)
        }

        let matchedCount = matches.filter { $0.status == .matched }.count
        let ambiguousCount = matches.filter { $0.status == .ambiguous }.count
        let notFoundCount = matches.filter { $0.status == .notFound }.count

        return AppleStudentEmailImportPreview(
            totalRows: matches.count,
            matchedCount: matchedCount,
            notFoundCount: notFoundCount,
            ambiguousCount: ambiguousCount,
            items: matches
        )
    }
}
