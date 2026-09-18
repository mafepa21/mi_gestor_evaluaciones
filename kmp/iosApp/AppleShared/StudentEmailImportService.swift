//
//  StudentEmailImportService.swift
//  MiGestorKMP
//
//  Created for importing and matching student corporate emails from spreadsheet.
//

import Foundation
import MiGestorKit

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
    /// `a.nombre.apellido@dominio` o `a.nombre.apellido.2apellido@dominio`
    public static func parseEmailIdentity(email: String) -> (firstName: String, lastName: String, cleanEmail: String)? {
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

        let firstName: String
        let lastName: String

        if segments.count == 1 {
            firstName = segments[0].capitalized
            lastName = ""
        } else if segments.count == 2 {
            firstName = segments[0].capitalized
            lastName = segments[1].capitalized
        } else {
            // Caso con 2 apellidos: ej: ["antonio", "garcia", "lopez"] -> firstName="Antonio", lastName="Garcia Lopez"
            firstName = segments[0].capitalized
            lastName = segments.dropFirst().map { $0.capitalized }.joined(separator: " ")
        }

        return (firstName, lastName, trimmed)
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

            // 1. Identificar la clase correspondiente según la columna B
            var targetClass: SchoolClass? = nil
            if !colB.isEmpty {
                let normCourse = normalizeClassName(colB)
                targetClass = classes.first(where: {
                    let normClassName = normalizeClassName($0.name)
                    return normClassName == normCourse ||
                           normClassName.contains(normCourse) ||
                           normCourse.contains(normClassName)
                })
            }

            // 2. Determinar el grupo de búsqueda de alumnos
            let searchPool: [Student]
            if let targetClass, let classStudents = studentsByClass[targetClass.id], !classStudents.isEmpty {
                searchPool = classStudents
            } else {
                searchPool = allStudents
            }

            // 3. Evaluar emparejamiento contra el searchPool
            var scoredCandidates: [(student: Student, score: Double)] = []
            for candidate in searchPool {
                let score = matchScore(
                    extractedFirst: extractedFirst,
                    extractedLast: extractedLast,
                    candidateFirst: candidate.firstName,
                    candidateLast: candidate.lastName
                )
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
                detail = targetClass != nil ? "No encontrado en \(targetClass!.name)" : "No encontrado en la app"
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
                matchedClassName: targetClass?.name,
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
