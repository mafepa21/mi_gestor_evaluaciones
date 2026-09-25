//
//  KmpBridge+Students.swift
//  MiGestorKMP
//
//  Created for modularization of KmpBridge.
//

import Foundation
import Combine
import MiGestorKit
import SwiftUI

@MainActor
extension KmpBridge {
    func refreshClasses() async throws {
        try await refreshAcademicYears()
        let classes = try await container.classesRepository.listClasses()
        self.classes = classes
        // If notebook has no class selected, pick the first one
        if notebookViewModel.currentClassId == nil, let first = classes.first {
            selectClass(id: first.id)
        }
    }

    private func academicYearSnapshot(from year: AcademicYear) async throws -> AcademicYearSnapshot {
        let classCount = try await container.classesRepository.listClassesForAcademicYear(academicYearId: year.id).count
        let enrollmentCount = try await container.academicYearsRepository.enrollmentCount(academicYearId: year.id)
        return AcademicYearSnapshot(
            id: year.id,
            name: year.name,
            startDate: Date(timeIntervalSince1970: TimeInterval(year.startAt.toEpochMilliseconds()) / 1000),
            endDate: Date(timeIntervalSince1970: TimeInterval(year.endAt.toEpochMilliseconds()) / 1000),
            status: year.status.name,
            isActive: year.isActive,
            archivedAt: year.archivedAt.map { Date(timeIntervalSince1970: TimeInterval($0.toEpochMilliseconds()) / 1000) },
            classCount: classCount,
            enrollmentCount: enrollmentCount.int64Value
        )
    }

    func refreshAcademicYears() async throws {
        let years = try await container.academicYearsRepository.listAcademicYears()
        var snapshots: [AcademicYearSnapshot] = []
        for year in years {
            snapshots.append(try await academicYearSnapshot(from: year))
        }
        self.academicYears = snapshots
        self.activeAcademicYear = snapshots.first(where: \.isActive)
        self.archivedAcademicYears = snapshots.filter { !$0.isActive }
    }

    func refreshSubjects() async throws {
        subjects = try await container.subjectsRepository.listSubjects()
    }

    func ensureClassesLoaded() async {
        try? await refreshAcademicYears()
        if classes.isEmpty {
            try? await refreshClasses()
        }
        if subjects.isEmpty {
            try? await refreshSubjects()
        }
    }

    func refreshStudentsDirectory() async throws {
        if classes.isEmpty {
            try await refreshClasses()
        }
        let currentClasses = self.classes
        let currentSelectedClassId = selectedStudentsClassId

        let all = try await container.studentsRepository.listStudents()
        let resolvedClassId = currentSelectedClassId ?? currentClasses.first?.id
        
        let inClass: [Student]
        if let classId = resolvedClassId {
            inClass = try await container.classesRepository.listStudentsInClass(classId: classId)
        } else {
            inClass = []
        }

        self.allStudents = all
        if selectedStudentsClassId == nil {
            selectedStudentsClassId = resolvedClassId
        }
        self.studentsInClass = inClass
    }

    func selectStudentsClass(classId: Int64?) async {
        selectedStudentsClassId = classId
        do {
            if let classId {
                studentsInClass = try await container.classesRepository.listStudentsInClass(classId: classId)
            } else {
                studentsInClass = []
            }
        } catch {
            status = "Error cargando alumnos: \(error.localizedDescription)"
        }
    }

    func students(forClassId classId: Int64) async throws -> [Student] {
        try await container.classesRepository.listStudentsInClass(classId: classId)
    }

    func createAcademicYear(
        name: String,
        startDate: Date,
        endDate: Date,
        copyGroupsFrom sourceAcademicYearId: Int64?,
        promoteStudents: Bool
    ) async throws -> Int64 {
        let sourceClasses: [SchoolClass]
        if let sourceAcademicYearId {
            sourceClasses = try await container.classesRepository.listClassesForAcademicYear(academicYearId: sourceAcademicYearId)
        } else {
            sourceClasses = []
        }

        let targetYearId = try await container.academicYearsRepository.createAcademicYear(
            name: name,
            startEpochMs: Int64(startDate.timeIntervalSince1970 * 1000),
            endEpochMs: Int64(endDate.timeIntervalSince1970 * 1000),
            centerId: nil,
            makeActive: true
        ).int64Value

        var classMapping: [Int64: Int64] = [:]
        for sourceClass in sourceClasses {
            let targetClassId = try await container.classesRepository.saveClass(
                id: nil,
                name: sourceClass.name,
                course: sourceClass.course,
                description: sourceClass.description_,
                centerId: sourceClass.centerId,
                academicYearId: KotlinLong(value: targetYearId),
                stageCycleId: sourceClass.stageCycleId,
                subjectId: sourceClass.subjectId,
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
            classMapping[sourceClass.id] = targetClassId
        }

        if promoteStudents {
            var targetClasses = try await container.classesRepository.listClassesForAcademicYear(academicYearId: targetYearId)
            
            for sourceClass in sourceClasses {
                let students = try await container.classesRepository.listStudentsInClass(classId: sourceClass.id)
                guard !students.isEmpty else { continue }
                guard let targetPlan = promotedStudentTargetClass(from: sourceClass) else { continue }
                let targetClass = try await ensurePromotionTargetClass(
                    targetPlan,
                    sourceClass: sourceClass,
                    targetYearId: targetYearId,
                    targetClasses: &targetClasses
                )
                for student in students {
                    try await container.classesRepository.promoteStudentToClass(
                        sourceClassId: sourceClass.id,
                        targetClassId: targetClass.id,
                        studentId: student.id,
                        promotionStatus: PromotionStatus.promoted.name
                    )
                }
            }
        }

        try await refreshAcademicYears()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        try await enqueueAcademicYearSnapshots()
        enqueueClassSnapshots()
        try await enqueueRosterSnapshotsForClasses(classes)
        selectedStudentsClassId = classes.first?.id
        status = promoteStudents ? "Curso escolar creado con alumnado promocionado." : "Curso escolar creado."
        return targetYearId
    }

    func setActiveAcademicYear(id: Int64) async throws {
        try await container.academicYearsRepository.setActiveAcademicYear(academicYearId: id)
        selectedStudentsClassId = nil
        try await refreshAcademicYears()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        try await enqueueAcademicYearSnapshots()
        status = "Curso escolar activo actualizado."
    }

    func archiveAcademicYear(id: Int64) async throws {
        guard activeAcademicYear?.id != id else {
            status = "Activa otro curso escolar antes de archivar el curso actual."
            return
        }
        try await container.academicYearsRepository.archiveAcademicYear(academicYearId: id)
        try await refreshAcademicYears()
        try await refreshClasses()
        try await enqueueAcademicYearSnapshots()
        status = "Curso escolar archivado."
    }

    func deleteArchivedAcademicYear(id: Int64) async throws {
        guard activeAcademicYear?.id != id else {
            status = "No se puede eliminar el curso escolar activo."
            return
        }
        try await container.academicYearsRepository.deleteArchivedAcademicYear(academicYearId: id)
        try await refreshAcademicYears()
        try await refreshClasses()
        try await refreshStudentsDirectory()
        enqueueLocalChange(
            entity: "academic_year",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
        status = "Curso escolar archivado eliminado."
    }

    private func enqueueAcademicYearSnapshots() async throws {
        let years = try await container.academicYearsRepository.listAcademicYears()
        for year in years {
            enqueueLocalChange(
                entity: "academic_year",
                id: "\(year.id)",
                updatedAtEpochMs: year.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": year.id,
                    "centerId": year.centerId,
                    "name": year.name,
                    "startEpochMs": year.startAt.toEpochMilliseconds(),
                    "endEpochMs": year.endAt.toEpochMilliseconds(),
                    "status": year.status.name,
                    "isActive": year.isActive,
                    "archivedAtEpochMs": year.archivedAt?.toEpochMilliseconds() ?? 0
                ]
            )
        }
    }

    private func enqueueClassSnapshots() {
        for schoolClass in classes {
            enqueueLocalChange(
                entity: "class",
                id: "\(schoolClass.id)",
                updatedAtEpochMs: schoolClass.trace.updatedAt.toEpochMilliseconds(),
                payload: [
                    "id": schoolClass.id,
                    "name": schoolClass.name,
                    "course": Int(schoolClass.course),
                    "description": schoolClass.description_ ?? NSNull(),
                    "centerId": schoolClass.centerId?.int64Value ?? 0,
                    "academicYearId": schoolClass.academicYearId?.int64Value ?? 0,
                    "stageCycleId": schoolClass.stageCycleId?.int64Value ?? 0,
                    "subjectId": schoolClass.subjectId?.int64Value ?? 0
                ]
            )
        }
    }

    private func enqueueRosterSnapshotsForClasses(_ schoolClasses: [SchoolClass]) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for schoolClass in schoolClasses {
            let studentIds = try await container.classesRepository
                .listStudentsInClass(classId: schoolClass.id)
                .map { $0.id }
                .sorted()
            enqueueLocalChange(
                entity: "class_roster",
                id: "\(schoolClass.id)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "classId": schoolClass.id,
                    "studentIds": studentIds
                ]
            )
        }
    }

    func archivedAcademicYearExportText(id: Int64) async throws -> String {
        let years = try await container.academicYearsRepository.listAcademicYears()
        guard let year = years.first(where: { $0.id == id }) else {
            throw NSError(domain: "KmpBridge", code: -90, userInfo: [NSLocalizedDescriptionKey: "Curso escolar no encontrado."])
        }

        let classes = try await container.classesRepository.listClassesForAcademicYear(academicYearId: id)
        var lines: [String] = [
            "Curso escolar: \(year.name)",
            "Estado: \(year.status.name)",
            "Inicio: \(Date(timeIntervalSince1970: TimeInterval(year.startAt.toEpochMilliseconds()) / 1000).formatted(.dateTime.day().month().year()))",
            "Fin: \(Date(timeIntervalSince1970: TimeInterval(year.endAt.toEpochMilliseconds()) / 1000).formatted(.dateTime.day().month().year()))",
            "Grupos: \(classes.count)",
            ""
        ]

        for schoolClass in classes {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: schoolClass.id)
            let grades = try await container.gradesRepository.listGradesForClass(classId: schoolClass.id)
            let notebookCells = try await container.notebookCellsRepository.listClassCells(classId: schoolClass.id)
            let attendance = try await container.attendanceRepository.listAttendance(classId: schoolClass.id)
            let incidents = try await container.incidentsRepository.listIncidents(classId: schoolClass.id)
            let physicalAssignments = try await container.physicalTestsRepository.listAssignmentsForClass(classId: schoolClass.id)
            var physicalResultsCount = 0
            for assignment in physicalAssignments {
                physicalResultsCount += try await container.physicalTestsRepository.listResultsForAssignment(assignmentId: assignment.id).count
            }
            let subject = schoolClass.subjectId.flatMap { subjectId in
                subjects.first(where: { $0.id == subjectId.int64Value })?.name
            } ?? "Sin asignatura"
            lines.append("## \(schoolClass.name) · Curso \(schoolClass.course) · \(subject)")
            lines.append("Matriculas: \(roster.count)")
            lines.append("Evaluaciones: \(evaluations.count)")
            lines.append("Calificaciones: \(grades.count)")
            lines.append("Celdas de cuaderno: \(notebookCells.count)")
            lines.append("Registros de asistencia: \(attendance.count)")
            lines.append("Incidencias: \(incidents.count)")
            lines.append("Pruebas fisicas: \(physicalAssignments.count) asignaciones · \(physicalResultsCount) resultados")
            if roster.isEmpty {
                lines.append("- Sin alumnado matriculado")
            } else {
                for student in roster.sorted(by: { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }) {
                    lines.append("- \(student.fullName)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private struct PromotionTargetClassPlan {
        let name: String
        let course: Int32
    }

    private func ensurePromotionTargetClass(
        _ plan: PromotionTargetClassPlan,
        sourceClass: SchoolClass,
        targetYearId: Int64,
        targetClasses: inout [SchoolClass]
    ) async throws -> SchoolClass {
        if let existing = targetClasses.first(where: { promotionClassNamesEquivalent($0.name, plan.name) }) {
            return existing
        }
        let targetClassId = try await container.classesRepository.saveClass(
            id: nil,
            name: plan.name,
            course: plan.course,
            description: sourceClass.description_,
            centerId: sourceClass.centerId,
            academicYearId: KotlinLong(value: targetYearId),
            stageCycleId: sourceClass.stageCycleId,
            subjectId: sourceClass.subjectId,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        let refreshed = try await container.classesRepository.listClassesForAcademicYear(academicYearId: targetYearId)
        targetClasses = refreshed
        guard let created = refreshed.first(where: { $0.id == targetClassId }) else {
            throw NSError(
                domain: "KmpBridge",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el grupo destino de promoción."]
            )
        }
        return created
    }

    private func promotedStudentTargetClass(from sourceClass: SchoolClass) -> PromotionTargetClassPlan? {
        let sourceName = sourceClass.name
        let levelsMap: [(course: Int, stage: String, target: String?, targetCourse: Int32?)] = [
            (1, "ESO", "2º ESO", 2),
            (2, "ESO", "3º ESO", 3),
            (3, "ESO", "4º ESO", 4),
            (4, "ESO", "1º BAC", 1),
            (1, "BAC", nil, nil),
            (2, "BAC", nil, nil),
        ]
        for level in levelsMap {
            if let suffix = promotionSuffix(from: sourceName, course: level.course, stage: level.stage) {
                guard let target = level.target, let course = level.targetCourse else { return nil }
                return PromotionTargetClassPlan(name: target + suffix, course: course)
            }
        }
        return nil
    }

    private func promotionSuffix(from sourceName: String, course: Int, stage: String) -> String? {
        let stagePattern = stage == "BAC" ? "(?:BAC|BACH|BACHILLERATO)" : stage
        let pattern = #"^\s*\#(course)\s*(?:º|°)?\s*\#(stagePattern)\b\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let fullRange = NSRange(sourceName.startIndex..<sourceName.endIndex, in: sourceName)
        guard let match = regex.firstMatch(in: sourceName, range: fullRange),
              match.range.location == 0,
              let suffixStart = Range(match.range, in: sourceName)?.upperBound else {
            return nil
        }
        let rawSuffix = String(sourceName[suffixStart...])
        return normalizedPromotionSuffix(rawSuffix)
    }

    private func normalizedPromotionSuffix(_ suffix: String) -> String {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let letter = singleGroupLetter(in: trimmed) {
            return " \(letter)"
        }
        return trimmed.hasPrefix("-") ? " \(trimmed)" : " \(trimmed)"
    }

    private func singleGroupLetter(in suffix: String) -> String? {
        let pattern = #"^(?:[\(\[]\s*)?([A-Za-z])(?:\s*[\)\]])?$|^[-–—]\s*([A-Za-z])$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(suffix.startIndex..<suffix.endIndex, in: suffix)
        guard let match = regex.firstMatch(in: suffix, range: range) else { return nil }
        for index in 1..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: suffix) {
                return String(suffix[swiftRange]).uppercased()
            }
        }
        return nil
    }

    private func promotionClassNamesEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        normalizedPromotionClassName(lhs) == normalizedPromotionClassName(rhs)
    }

    private func normalizedPromotionClassName(_ name: String) -> String {
        var normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .replacingOccurrences(of: "BACHILLERATO", with: "BAC")
            .replacingOccurrences(of: "BACH", with: "BAC")
            .replacingOccurrences(of: "º", with: "")
            .replacingOccurrences(of: "°", with: "")
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


    func previewStudentImport(tsv: String) async throws -> AppleStudentImportPreview {
        let preview = appleImportFacade.previewStudentsFromTsv(text: tsv)
        let existingStudents = try await container.studentsRepository.listStudents()
        let existingByFullName = Dictionary(
            existingStudents.map { (normalizedStudentName(firstName: $0.firstName, lastName: $0.lastName), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingLastNames = Set(existingStudents.map { normalizedNamePart($0.lastName) }.filter { !$0.isEmpty })
        let students = preview.students.map { student in
            let normalizedFullName = normalizedStudentName(firstName: student.firstName, lastName: student.lastName)
            let normalizedLastName = normalizedNamePart(student.lastName)
            let duplicateStatus: AppleStudentDuplicateStatus
            let duplicateDetail: String?
            let existingStudentId: Int64?
            if let existingStudent = existingByFullName[normalizedFullName] {
                duplicateStatus = .alreadyExists
                duplicateDetail = existingStudent.fullName
                existingStudentId = existingStudent.id
            } else if !normalizedLastName.isEmpty && existingLastNames.contains(normalizedLastName) {
                duplicateStatus = .possibleDuplicate
                duplicateDetail = "Coinciden apellidos"
                existingStudentId = nil
            } else {
                duplicateStatus = .new
                duplicateDetail = nil
                existingStudentId = nil
            }
            return AppleParsedStudent(
                id: Int(student.rowNumber),
                rowNumber: Int(student.rowNumber),
                fullName: student.fullName,
                firstName: student.firstName,
                lastName: student.lastName,
                duplicateStatus: duplicateStatus,
                duplicateDetail: duplicateDetail,
                existingStudentId: existingStudentId
            )
        }

        guard !students.isEmpty else {
            throw NSError(domain: "KmpBridge", code: -60, userInfo: [NSLocalizedDescriptionKey: "No se encontraron alumnos en el archivo."])
        }

        let applePreview = AppleStudentImportPreview(
            className: preview.className,
            course: preview.course,
            students: students
        )
        studentImportPreview = applePreview
        return applePreview
    }

    func confirmStudentImport(selectedRows: [Int], targetClassId: Int64?, omitDuplicates: Bool = true) async throws {
        guard let preview = studentImportPreview else {
            throw NSError(domain: "KmpBridge", code: -61, userInfo: [NSLocalizedDescriptionKey: "No hay una previsualización de importación activa."])
        }

        let selectedRowSet = Set(selectedRows)
        let studentsToProcess = preview.students.filter { student in
            selectedRowSet.contains(student.rowNumber) && (!omitDuplicates || student.duplicateStatus == .new)
        }
        guard !studentsToProcess.isEmpty else {
            throw NSError(domain: "KmpBridge", code: -62, userInfo: [NSLocalizedDescriptionKey: "Selecciona al menos un alumno para importar."])
        }

        isImportingStudents = true
        defer { isImportingStudents = false }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var studentIdsToEnroll: [Int64] = []

        for student in studentsToProcess {
            if let existingId = student.existingStudentId {
                // Alumno ya existente en la base de datos: no lo duplicamos, usamos su id existente
                studentIdsToEnroll.append(existingId)
            } else {
                let studentId = try await container.studentsRepository.saveStudent(
                    id: nil,
                    firstName: student.firstName,
                    lastName: student.lastName,
                    email: nil,
                    photoPath: nil,
                    isInjured: false,
                    sex: .unspecified,
                    sexSource: .imported,
                    birthDate: nil,
                    updatedAtEpochMs: nowMs,
                    deviceId: localDeviceId,
                    syncVersion: 1
                ).int64Value
                studentIdsToEnroll.append(studentId)

                enqueueLocalChange(
                    entity: "student",
                    id: "\(studentId)",
                    updatedAtEpochMs: nowMs,
                    payload: [
                        "id": studentId,
                        "firstName": student.firstName,
                        "lastName": student.lastName,
                        "email": NSNull(),
                        "photoPath": NSNull(),
                        "isInjured": false,
                        "sex": StudentSex.unspecified.name,
                        "sexSource": StudentSexSource.imported.name,
                        "birthDate": NSNull()
                    ]
                )
            }
        }

        if let targetClassId {
            for studentId in studentIdsToEnroll {
                try await container.classesRepository.addStudentToClass(classId: targetClassId, studentId: studentId)
            }
            enqueueRosterSnapshot(forClassId: targetClassId, updatedAtEpochMs: nowMs)
            selectedStudentsClassId = targetClassId
            await selectStudentsClass(classId: targetClassId)
        }

        studentImportPreview = nil
        try await refreshStudentsDirectory()
        try await refreshDashboard()
    }

    private func normalizedStudentName(firstName: String, lastName: String) -> String {
        normalizedNamePart([firstName, lastName].joined(separator: " "))
    }

    private func normalizedNamePart(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }


    func createClass(name: String, course: Int32, subjectId: Int64? = nil) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let classId = try await container.saveClass.invoke(
            id: nil,
            name: name,
            course: course,
            description: nil,
            centerId: nil,
            academicYearId: kotlinLong(activeAcademicYear?.id),
            stageCycleId: nil,
            subjectId: kotlinLong(subjectId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await refreshClasses()
        selectedStudentsClassId = classId.int64Value
        try await refreshStudentsDirectory()
        enqueueLocalChange(
            entity: "class",
            id: "\(classId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": classId.int64Value,
                "name": name,
                "course": Int(course),
                "description": NSNull(),
                "centerId": NSNull(),
                "academicYearId": activeAcademicYear?.id ?? 0,
                "stageCycleId": NSNull(),
                "subjectId": subjectId.map { NSNumber(value: $0) } ?? NSNull()
            ]
        )
        return classId.int64Value
    }

    func updateClass(
        id: Int64,
        name: String,
        course: Int32,
        description: String?,
        centerId: Int64?,
        academicYearId: Int64?,
        stageCycleId: Int64?,
        subjectId: Int64?
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.saveClass.invoke(
            id: kotlinLong(id),
            name: name,
            course: course,
            description: description,
            centerId: kotlinLong(centerId),
            academicYearId: kotlinLong(academicYearId),
            stageCycleId: kotlinLong(stageCycleId),
            subjectId: kotlinLong(subjectId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await refreshClasses()
        if selectedStudentsClassId == id {
            try await refreshStudentsDirectory()
        }
        enqueueLocalChange(
            entity: "class",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "name": name,
                "course": Int(course),
                "description": description ?? NSNull(),
                "centerId": centerId.map { NSNumber(value: $0) } ?? NSNull(),
                "academicYearId": academicYearId.map { NSNumber(value: $0) } ?? NSNull(),
                "stageCycleId": stageCycleId.map { NSNumber(value: $0) } ?? NSNull(),
                "subjectId": subjectId.map { NSNumber(value: $0) } ?? NSNull()
            ]
        )
    }

    func deleteClass(id: Int64) async throws {
        try await container.classesRepository.deleteClass(classId: id)
        try await refreshClasses()
        if selectedStudentsClassId == id {
            selectedStudentsClassId = classes.first?.id
            try await refreshStudentsDirectory()
        }
        enqueueLocalChange(
            entity: "class",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": id
            ],
            op: "delete"
        )
    }

    func saveSubject(id: Int64? = nil, code: String, name: String, stageCycleId: Int64? = nil) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let subjectId = try await container.saveSubject.invoke(
            id: kotlinLong(id),
            code: code,
            name: name,
            stageCycleId: kotlinLong(stageCycleId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await refreshSubjects()
        enqueueLocalChange(
            entity: "subject",
            id: "\(subjectId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": subjectId.int64Value,
                "code": code,
                "name": name,
                "stageCycleId": stageCycleId.map { NSNumber(value: $0) } ?? NSNull()
            ]
        )
        return subjectId.int64Value
    }

    func deleteSubject(id: Int64) async throws {
        try await container.subjectsRepository.deleteSubject(subjectId: id)
        try await refreshSubjects()
        try await refreshClasses()
    }

    func createStudentAndAssignToClass(firstName: String, lastName: String, classId: Int64) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sexResolution: (sex: StudentSex, source: StudentSexSource) = (.unspecified, .unknown)
        let studentId = try await container.saveStudent.invoke(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            sex: sexResolution.sex,
            sexSource: sexResolution.source,
            birthDate: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId.int64Value)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(studentId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": studentId.int64Value,
                "firstName": firstName,
                "lastName": lastName,
                "email": NSNull(),
                "photoPath": NSNull(),
                "isInjured": false,
                "sex": sexResolution.sex.name,
                "sexSource": sexResolution.source.name,
                "birthDate": NSNull()
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
    }

    func createStudentInSelectedClass(
        firstName: String,
        lastName: String,
        isInjured: Bool = false,
        sex: StudentSex? = nil,
        sexSource: StudentSexSource? = nil,
        birthDate: LocalDate? = nil
    ) async throws {
        guard let classId = selectedStudentsClassId else {
            throw NSError(domain: "KMP", code: -20, userInfo: [NSLocalizedDescriptionKey: "Selecciona una clase primero"])
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sexResolution = await resolvedStudentSex(firstName: firstName, lastName: lastName, sex: sex, sexSource: sexSource)
        let studentId = try await container.studentsRepository.saveStudent(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: nil,
            photoPath: nil,
            isInjured: isInjured,
            sex: sexResolution.sex,
            sexSource: sexResolution.source,
            birthDate: birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        let newStudentId = studentId.int64Value
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: newStudentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(newStudentId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": newStudentId,
                "firstName": firstName,
                "lastName": lastName,
                "email": NSNull(),
                "photoPath": NSNull(),
                "isInjured": isInjured,
                "sex": sexResolution.sex.name,
                "sexSource": sexResolution.source.name,
                "birthDate": birthDate == nil ? NSNull() : birthDate!.description()
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
    }

    func createMacStudent(
        firstName: String,
        lastName: String,
        email: String?,
        isInjured: Bool,
        classId: Int64
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sexResolution = await resolvedStudentSex(firstName: firstName, lastName: lastName, sex: nil, sexSource: nil)
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let studentId = try await container.studentsRepository.saveStudent(
            id: nil,
            firstName: firstName,
            lastName: lastName,
            email: normalizedEmail,
            photoPath: nil,
            isInjured: isInjured,
            sex: sexResolution.sex,
            sexSource: sexResolution.source,
            birthDate: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(studentId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": studentId,
                "firstName": firstName,
                "lastName": lastName,
                "email": normalizedEmail ?? NSNull(),
                "photoPath": NSNull(),
                "isInjured": isInjured,
                "sex": sexResolution.sex.name,
                "sexSource": sexResolution.source.name,
                "birthDate": NSNull()
            ]
        )
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
        return studentId
    }

    func updateMacStudent(
        student: Student,
        firstName: String,
        lastName: String,
        email: String?,
        isInjured: Bool
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: firstName,
            lastName: lastName,
            email: normalizedEmail,
            photoPath: student.photoPath,
            isInjured: isInjured,
            sex: student.sex,
            sexSource: student.sexSource,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": firstName,
                "lastName": lastName,
                "email": normalizedEmail ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": isInjured,
                "sex": student.sex.name,
                "sexSource": student.sexSource.name,
                "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
            ]
        )
    }

    func updateStudentFull(
        student: Student,
        firstName: String,
        lastName: String,
        email: String?,
        isInjured: Bool,
        sex: StudentSex,
        birthDate: LocalDate?
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let sexSource: StudentSexSource = (sex == student.sex)
            ? student.sexSource
            : (sex == .unspecified ? StudentSexSource.unknown : StudentSexSource.manual)

        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: firstName,
            lastName: lastName,
            email: normalizedEmail,
            photoPath: student.photoPath,
            isInjured: isInjured,
            sex: sex,
            sexSource: sexSource,
            birthDate: birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": firstName,
                "lastName": lastName,
                "email": normalizedEmail ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": isInjured,
                "sex": sex.name,
                "sexSource": sexSource.name,
                "birthDate": birthDate == nil ? NSNull() : birthDate!.description()
            ]
        )
    }

    func updateStudentInjuryStatus(
        studentId: Int64,
        isInjured: Bool,
        classId: Int64?
    ) async throws {
        guard let student = try await container.studentsRepository.listStudents().first(where: { $0.id == studentId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró el alumno \(studentId)."])
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: student.firstName,
            lastName: student.lastName,
            email: student.email,
            photoPath: student.photoPath,
            isInjured: isInjured,
            sex: student.sex,
            sexSource: student.sexSource,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": student.firstName,
                "lastName": student.lastName,
                "email": student.email ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": isInjured,
                "sex": student.sex.name,
                "sexSource": student.sexSource.name,
                "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
            ]
        )

        if let classId {
            enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: nowMs)
        }
    }

    private func resolvedStudentSex(
        firstName: String,
        lastName: String,
        sex: StudentSex?,
        sexSource: StudentSexSource?
    ) async -> (sex: StudentSex, source: StudentSexSource) {
        if let sex, sex != .unspecified {
            return (sex, sexSource ?? .manual)
        }
        return (.unspecified, .unknown)
    }

    func updateStudentSex(_ student: Student, sex: StudentSex) async throws {
        try await updateStudentSex(
            student,
            sex: sex,
            source: sex == .unspecified ? .unknown : .manual
        )
    }

    /// Persists a sex value while keeping its provenance explicit for sync and audit.
    /// Name-based inference is deliberately guarded here as well as in the UI, so a
    /// stale suggestion cannot overwrite a value that has since been entered/imported.
    func updateStudentSex(
        _ student: Student,
        sex: StudentSex,
        source: StudentSexSource
    ) async throws {
        try await persistStudentSex(student, sex: sex, source: source, refreshDirectory: true)
    }

    func applyStudentSexInference(_ assignments: [StudentSexInferenceAssignment]) async throws {
        var appliedCount = 0
        for assignment in assignments {
            guard assignment.sex != .unspecified else { continue }
            guard let current = try await container.studentsRepository.getStudent(studentId: assignment.student.id),
                  current.sex == .unspecified,
                  current.sexSource == .unknown else { continue }

            try await persistStudentSex(
                current,
                sex: assignment.sex,
                source: .nameInferred,
                refreshDirectory: false
            )
            appliedCount += 1
        }

        if appliedCount > 0 {
            try await refreshStudentsDirectory()
            try await refreshDashboard()
        }
    }

    private func persistStudentSex(
        _ student: Student,
        sex: StudentSex,
        source: StudentSexSource,
        refreshDirectory: Bool
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let persistedSource = sex == .unspecified ? StudentSexSource.unknown : source
        _ = try await container.studentsRepository.saveStudent(
            id: KotlinLong(value: student.id),
            firstName: student.firstName,
            lastName: student.lastName,
            email: student.email,
            photoPath: student.photoPath,
            isInjured: student.isInjured,
            sex: sex,
            sexSource: persistedSource,
            birthDate: student.birthDate,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: student.trace.syncVersion + 1
        )
        if refreshDirectory {
            try await refreshStudentsDirectory()
            try await refreshDashboard()
        }
        enqueueLocalChange(
            entity: "student",
            id: "\(student.id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": student.id,
                "firstName": student.firstName,
                "lastName": student.lastName,
                "email": student.email ?? NSNull(),
                "photoPath": student.photoPath ?? NSNull(),
                "isInjured": student.isInjured,
                "sex": sex.name,
                "sexSource": persistedSource.name,
                "birthDate": student.birthDate == nil ? NSNull() : student.birthDate!.description()
            ]
        )
    }

    func evaluations(for classId: Int64) async throws -> [Evaluation] {
        try await container.evaluationsRepository.listClassEvaluations(classId: classId)
    }

    func incidents(for classId: Int64) async throws -> [Incident] {
        try await container.incidentsRepository.listIncidents(classId: classId)
            .sorted { lhs, rhs in
                lhs.date.epochSeconds > rhs.date.epochSeconds
            }
    }

    func attendanceRecords(for classId: Int64, on date: Date) async throws -> [AttendanceRecordSnapshot] {
        let rows = try await container.attendanceRepository.listAttendanceByDate(
            classId: classId,
            dateEpochMs: startOfDayEpochMs(for: date)
        )
        return rows.map(attendanceSnapshot(from:))
    }

    func attendanceHistory(for classId: Int64, days: Int = 14) async throws -> [AttendanceRecordSnapshot] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let rows = try await container.attendanceRepository.getAttendanceForClassBetweenDates(
            classId: classId,
            startDateMs: startOfDayEpochMs(for: start),
            endDateMs: startOfDayEpochMs(for: end)
        )
        return rows.map(attendanceSnapshot(from:))
    }

    func attendanceHistory(for classId: Int64, from startDate: Date, to endDate: Date) async throws -> [AttendanceRecordSnapshot] {
        let rows = try await container.attendanceRepository.getAttendanceForClassBetweenDates(
            classId: classId,
            startDateMs: startOfDayEpochMs(for: startDate),
            endDateMs: startOfDayEpochMs(for: endDate)
        )
        return rows.map(attendanceSnapshot(from:))
    }

    func attendanceOverview(for classIds: [Int64], from startDate: Date, to endDate: Date) async throws -> [AttendanceClassOverview] {
        var overviews: [AttendanceClassOverview] = []
        let todayEpochMs = startOfDayEpochMs(for: Date())
        for classId in classIds {
            guard let schoolClass = classes.first(where: { $0.id == classId }) else { continue }
            let students = try await container.classesRepository.listStudentsInClass(classId: classId)
            let history = try await container.attendanceRepository.getAttendanceForClassBetweenDates(
                classId: classId,
                startDateMs: startOfDayEpochMs(for: startDate),
                endDateMs: startOfDayEpochMs(for: endDate)
            )
            let todayRecords = try await container.attendanceRepository.listAttendanceByDate(
                classId: classId,
                dateEpochMs: todayEpochMs
            )
            let present = history.filter { $0.status.uppercased().contains("PRESENT") }.count
            let absent = history.filter { $0.status.uppercased().contains("AUS") }.count
            let late = history.filter {
                let status = $0.status.uppercased()
                return status.contains("TARD") || status.contains("RETR")
            }.count
            let attendanceRate = history.isEmpty ? 0 : Int((Double(present) / Double(history.count)) * 100.0)
            overviews.append(
                AttendanceClassOverview(
                    id: classId,
                    schoolClass: schoolClass,
                    studentCount: students.count,
                    presentCount: present,
                    absentCount: absent,
                    lateCount: late,
                    pendingTodayCount: max(students.count - todayRecords.count, 0),
                    attendanceRate: attendanceRate
                )
            )
        }
        return overviews.sorted { $0.schoolClass.name.localizedCaseInsensitiveCompare($1.schoolClass.name) == .orderedAscending }
    }

    func attendanceSessions(for classId: Int64, on date: Date) async throws -> [AttendanceSessionSnapshot] {
        let calendar = Calendar(identifier: .iso8601)
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
        let weekday = isoWeekday(from: date)
        let sessions = try await plannerListSessions(weekNumber: weekOfYear, year: yearForWeek, classId: classId)
            .filter { Int($0.dayOfWeek) == weekday }
            .sorted { $0.period < $1.period }
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(
            summaries.map { ($0.planningSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions.map { session in
            AttendanceSessionSnapshot(
                id: session.id,
                session: session,
                journalSummary: summariesById[session.id]
            )
        }
    }

    func diarySessions(weekNumber: Int, year: Int, classId: Int64?) async throws -> [DiarySessionSnapshot] {
        let sessions = try await plannerListSessions(weekNumber: weekNumber, year: year, classId: classId)
        let summaries = try await plannerJournalSummaries(sessionIds: sessions.map(\.id))
        let summariesById = Dictionary(
            summaries.map { ($0.planningSessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions
            .sorted {
                if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                return $0.dayOfWeek < $1.dayOfWeek
            }
            .map { session in
                DiarySessionSnapshot(
                    id: session.id,
                    session: session,
                    journalSummary: summariesById[session.id]
                )
            }
    }

    /// `note`/`hasIncident`/`followUpRequired` son `nil` por defecto (no `""`/`false`)
    /// a proposito: la mayoria de llamadas solo cambian el `status` (toque rapido
    /// de asistencia) y no deben borrar una observacion o incidencia ya guardada
    /// ese dia. `nil` conserva el valor existente; un valor explicito lo sustituye.
    func saveAttendance(
        studentId: Int64,
        classId: Int64,
        on date: Date,
        status: String,
        note: String? = nil,
        hasIncident: Bool? = nil,
        followUpRequired: Bool? = nil,
        sessionId: Int64? = nil
    ) async throws {
        let dateEpochMs = startOfDayEpochMs(for: date)
        let existingRecords = try await container.attendanceRepository.listAttendanceByDate(classId: classId, dateEpochMs: dateEpochMs)
        let linkedSessionId = sessionId
        let existing = existingRecords.first { record in
            record.studentId == studentId && record.sessionId?.int64Value == linkedSessionId
        } ?? existingRecords.first { record in
            record.studentId == studentId
        }
        let resolvedNote = note ?? existing?.note ?? ""
        let resolvedHasIncident = hasIncident ?? existing?.hasIncident ?? false
        let resolvedFollowUpRequired = followUpRequired ?? existing?.followUpRequired ?? resolvedHasIncident
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.attendanceRepository.saveAttendance(
            id: kotlinLong(existing?.id),
            studentId: studentId,
            classId: classId,
            dateEpochMs: dateEpochMs,
            status: status,
            note: resolvedNote,
            hasIncident: resolvedHasIncident,
            followUpRequired: resolvedFollowUpRequired,
            sessionId: kotlinLong(linkedSessionId),
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "attendance",
            id: "\(classId)-\(studentId)-\(dateEpochMs)",
            updatedAtEpochMs: nowMs,
            payload: [
                "studentId": studentId,
                "classId": classId,
                "dateEpochMs": dateEpochMs,
                "status": status,
                "note": resolvedNote,
                "hasIncident": resolvedHasIncident,
                "followUpRequired": resolvedFollowUpRequired,
                "sessionId": linkedSessionId ?? NSNull()
            ]
        )
    }

    /// Medidas de respuesta educativa Nivel III/IV (Decreto 104/2018 + Orden 20/2019, CV).
    /// El docente de aula consulta e implementa; nunca redacta aquí el informe
    /// sociopsicopedagógico ni el PAP, solo referencia el documento oficial.
    func supportMeasures(for studentId: Int64) async throws -> [SupportMeasureSnapshot] {
        let rows = try await container.studentSupportMeasureRepository.listByStudent(studentId: studentId)
        return rows.compactMap(supportMeasureSnapshot(from:))
    }

    func activeSupportMeasureStudentIds() async throws -> Set<Int64> {
        let ids = try await container.studentSupportMeasureRepository.listActiveStudentIds()
        return Set(ids.map { $0.int64Value })
    }

    @discardableResult
    func saveSupportMeasure(id: Int64? = nil, draft: SupportMeasureDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.studentSupportMeasureRepository.save(
            id: kotlinLong(id),
            studentId: draft.studentId,
            level: kotlinSupportMeasureLevel(draft.level),
            measureType: kotlinSupportMeasureType(draft.measureType),
            startDateIso: draft.startDateIso,
            endDateIso: nil,
            responsible: draft.responsible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.responsible,
            intensity: draft.intensity.map(kotlinSupportMeasureIntensity(_:)),
            followUpNotes: draft.followUpNotes,
            documentRef: draft.documentRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.documentRef,
            reviewDueIso: draft.reviewDueIso,
            isActive: true,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "student_support_measures",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "studentId": draft.studentId,
                "level": draft.level.rawValue,
                "measureType": draft.measureType.rawValue,
                "startDateIso": draft.startDateIso,
                "responsible": draft.responsible,
                "intensity": draft.intensity?.rawValue ?? NSNull(),
                "followUpNotes": draft.followUpNotes,
                "documentRef": draft.documentRef,
                "reviewDueIso": draft.reviewDueIso ?? NSNull(),
                "isActive": true
            ]
        )
        return savedId
    }

    func retireSupportMeasure(id: Int64, endDateIso: String) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try await container.studentSupportMeasureRepository.retire(
            id: id,
            endDateIso: endDateIso,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId
        )
        enqueueLocalChange(
            entity: "student_support_measures",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "endDateIso": endDateIso,
                "isActive": false
            ]
        )
    }

    func deleteSupportMeasure(id: Int64) async throws {
        try await container.studentSupportMeasureRepository.delete(id: id)
        enqueueLocalChange(
            entity: "student_support_measures",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    func tutoringSessions(for studentId: Int64) async throws -> [TutoringSessionSnapshot] {
        let rows = try await container.studentTutoringSessionRepository.listByStudent(studentId: studentId)
        return rows.compactMap(tutoringSessionSnapshot(from:))
    }

    /// Seguimientos abiertos cuya revisión vence en o antes de `onOrBeforeIso`.
    func pendingTutoringReviews(onOrBefore onOrBeforeIso: String) async throws -> [TutoringSessionSnapshot] {
        let rows = try await container.studentTutoringSessionRepository.listPendingReviews(onOrBeforeIso: onOrBeforeIso)
        return rows.compactMap(tutoringSessionSnapshot(from:))
    }

    @discardableResult
    func saveTutoringSession(id: Int64? = nil, draft: TutoringSessionDraft) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.studentTutoringSessionRepository.save(
            id: kotlinLong(id),
            studentId: draft.studentId,
            dateIso: draft.dateIso,
            channel: kotlinTutoringChannel(draft.channel),
            attendees: draft.attendees,
            topics: draft.topics,
            agreements: draft.agreements,
            reviewDueIso: draft.reviewDueIso,
            isClosed: draft.isClosed,
            createdAtEpochMs: id == nil ? nowMs : 0,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        enqueueLocalChange(
            entity: "student_tutoring_sessions",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "studentId": draft.studentId,
                "dateIso": draft.dateIso,
                "channel": draft.channel.rawValue,
                "attendees": draft.attendees,
                "topics": draft.topics,
                "agreements": draft.agreements,
                "reviewDueIso": draft.reviewDueIso ?? NSNull(),
                "isClosed": draft.isClosed
            ]
        )
        return savedId
    }

    func deleteTutoringSession(id: Int64) async throws {
        try await container.studentTutoringSessionRepository.delete(id: id)
        enqueueLocalChange(
            entity: "student_tutoring_sessions",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    /// `nil` si la fila trae un canal que esta version no conoce. Se descarta en
    /// vez de forzar un valor: mismo criterio que las medidas de apoyo.
    private func tutoringSessionSnapshot(from session: StudentTutoringSession) -> TutoringSessionSnapshot? {
        guard let channel = TutoringChannelUI(rawValue: session.channel.name) else { return nil }
        return TutoringSessionSnapshot(
            id: session.id,
            studentId: session.studentId,
            dateIso: session.date.description(),
            channel: channel,
            attendees: session.attendees,
            topics: session.topics,
            agreements: session.agreements,
            reviewDueIso: session.reviewDue?.description(),
            isClosed: session.isClosed
        )
    }

    private func kotlinTutoringChannel(_ channel: TutoringChannelUI) -> TutoringChannel {
        TutoringChannel.entries.first { $0.name == channel.rawValue } ?? TutoringChannel.entries[0]
    }

    private func supportMeasureSnapshot(from measure: StudentSupportMeasure) -> SupportMeasureSnapshot? {
        guard
            let level = SupportMeasureLevelUI(rawValue: measure.level.name),
            let measureType = SupportMeasureTypeUI(rawValue: measure.measureType.name)
        else { return nil }
        return SupportMeasureSnapshot(
            id: measure.id,
            studentId: measure.studentId,
            level: level,
            measureType: measureType,
            startDateIso: measure.startDate.description(),
            endDateIso: measure.endDate?.description(),
            responsible: measure.responsible,
            intensity: measure.intensity.flatMap { SupportMeasureIntensityUI(rawValue: $0.name) },
            followUpNotes: measure.followUpNotes,
            documentRef: measure.documentRef,
            reviewDueIso: measure.reviewDue?.description(),
            isActive: measure.isActive
        )
    }

    private func kotlinSupportMeasureLevel(_ level: SupportMeasureLevelUI) -> SupportMeasureLevel {
        SupportMeasureLevel.entries.first { $0.name == level.rawValue } ?? SupportMeasureLevel.entries[0]
    }

    private func kotlinSupportMeasureType(_ type: SupportMeasureTypeUI) -> SupportMeasureType {
        SupportMeasureType.entries.first { $0.name == type.rawValue } ?? SupportMeasureType.entries[0]
    }

    private func kotlinSupportMeasureIntensity(_ intensity: SupportMeasureIntensityUI) -> SupportMeasureIntensity {
        SupportMeasureIntensity.entries.first { $0.name == intensity.rawValue } ?? SupportMeasureIntensity.entries[0]
    }

    func saveAttendanceBatch(records drafts: [AttendanceDraft]) async throws {
        guard !drafts.isEmpty else { return }

        var existingByKey: [String: Attendance_] = [:]
        let groupedDrafts = Dictionary(grouping: drafts) { draft in
            "\(draft.classId)-\(startOfDayEpochMs(for: draft.date))"
        }

        for (_, grouped) in groupedDrafts {
            guard let sample = grouped.first else { continue }
            let dateEpochMs = startOfDayEpochMs(for: sample.date)
            let existingRecords = try await container.attendanceRepository.listAttendanceByDate(
                classId: sample.classId,
                dateEpochMs: dateEpochMs
            )
            for record in existingRecords {
                let sessionKey = record.sessionId.map { String($0.int64Value) } ?? "none"
                existingByKey["\(record.classId)-\(record.studentId)-\(dateEpochMs)-\(sessionKey)"] = record
                existingByKey["\(record.classId)-\(record.studentId)-\(dateEpochMs)-any"] = record
            }
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for draft in drafts {
            let dateEpochMs = startOfDayEpochMs(for: draft.date)
            let sessionKey = draft.sessionId.map(String.init) ?? "none"
            let existing = existingByKey["\(draft.classId)-\(draft.studentId)-\(dateEpochMs)-\(sessionKey)"]
                ?? existingByKey["\(draft.classId)-\(draft.studentId)-\(dateEpochMs)-any"]
            _ = try await container.attendanceRepository.saveAttendance(
                id: kotlinLong(existing?.id),
                studentId: draft.studentId,
                classId: draft.classId,
                dateEpochMs: dateEpochMs,
                status: draft.status,
                note: draft.note,
                hasIncident: draft.hasIncident,
                followUpRequired: draft.followUpRequired ?? draft.hasIncident,
                sessionId: kotlinLong(draft.sessionId),
                updatedAtEpochMs: nowMs,
                deviceId: localDeviceId,
                syncVersion: (existing?.trace.syncVersion ?? 0) + 1
            )
            enqueueLocalChange(
                entity: "attendance",
                id: "\(draft.classId)-\(draft.studentId)-\(dateEpochMs)",
                updatedAtEpochMs: nowMs,
                payload: [
                    "studentId": draft.studentId,
                    "classId": draft.classId,
                    "dateEpochMs": dateEpochMs,
                    "status": draft.status,
                    "note": draft.note,
                    "hasIncident": draft.hasIncident,
                    "followUpRequired": draft.followUpRequired ?? draft.hasIncident,
                    "sessionId": draft.sessionId ?? NSNull()
                ]
            )
        }
    }

    func repeatLatestAttendancePattern(classId: Int64, targetDate: Date) async throws -> Int {
        let targetDay = startOfDayEpochMs(for: targetDate)
        let history = try await container.attendanceRepository.listAttendance(classId: classId)
            .map(attendanceSnapshot(from:))
            .sorted { lhs, rhs in lhs.date > rhs.date }

        let sourceDate = history
            .map { startOfDayEpochMs(for: $0.date) }
            .first(where: { $0 < targetDay })

        guard let sourceDate else { return 0 }

        let sourceRecords = try await container.attendanceRepository.listAttendanceByDate(classId: classId, dateEpochMs: sourceDate)
        var applied = 0
        for record in sourceRecords {
            try await saveAttendance(
                studentId: record.studentId,
                classId: classId,
                on: targetDate,
                status: record.status,
                note: record.note,
                hasIncident: record.hasIncident
            )
            applied += 1
        }
        return applied
    }

    func createIncident(
        classId: Int64,
        studentId: Int64?,
        title: String,
        detail: String,
        severity: String = "medium"
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let incidentId = try await container.incidentsRepository.saveIncident(
            id: nil,
            classId: classId,
            studentId: kotlinLong(studentId),
            title: title,
            detail: detail,
            severity: severity,
            dateEpochMs: nowMs,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "incident",
            id: "\(incidentId.int64Value)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": incidentId.int64Value,
                "classId": classId,
                "studentId": studentId ?? NSNull(),
                "title": title,
                "detail": detail,
                "severity": severity,
                "dateEpochMs": nowMs
            ]
        )
        return incidentId.int64Value
    }

    func updateIncident(
        id: Int64,
        classId: Int64,
        studentId: Int64?,
        title: String,
        detail: String,
        severity: String,
        dateEpochMs: Int64
    ) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        _ = try await container.incidentsRepository.saveIncident(
            id: KotlinLong(value: id),
            classId: classId,
            studentId: kotlinLong(studentId),
            title: title,
            detail: detail,
            severity: severity,
            dateEpochMs: dateEpochMs,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        enqueueLocalChange(
            entity: "incident",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "classId": classId,
                "studentId": studentId ?? NSNull(),
                "title": title,
                "detail": detail,
                "severity": severity,
                "dateEpochMs": dateEpochMs
            ]
        )
    }

    func deleteIncident(id: Int64) async throws {
        try await container.incidentsRepository.deleteIncident(id: id)
        enqueueLocalChange(
            entity: "incident",
            id: "\(id)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": id],
            op: "delete"
        )
    }

    func loadCourseSummary(classId: Int64) async throws -> CourseInspectorSnapshot {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let attendance = try await attendanceHistory(for: classId, days: 21)
        let todayAttendance = try await attendanceRecords(for: classId, on: Date())
        let evaluations = try await evaluations(for: classId)
        let classIncidents = try await incidents(for: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        let weeklySlots = container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
        let values = grades.compactMap { $0.value?.doubleValue }
        let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
        let attendanceRate: Int
        if attendance.isEmpty {
            attendanceRate = 0
        } else {
            let presentCount = attendance.filter { $0.status.uppercased().contains("PRESENT") }.count
            attendanceRate = Int((Double(presentCount) / Double(attendance.count)) * 100.0)
        }
        return CourseInspectorSnapshot(
            schoolClass: schoolClass,
            studentCount: students.count,
            injuredStudentCount: students.filter(\.isInjured).count,
            attendanceRate: attendanceRate,
            todayPresentCount: todayAttendance.filter { $0.status.uppercased().contains("PRESENT") }.count,
            todayAbsentCount: todayAttendance.filter { $0.status.uppercased().contains("AUS") }.count,
            todayLateCount: todayAttendance.filter { $0.status.uppercased().contains("TARD") || $0.status.uppercased().contains("RETR") }.count,
            evaluationCount: evaluations.count,
            incidentCount: classIncidents.count,
            severeIncidentCount: classIncidents.filter { $0.severity.lowercased() == "high" || $0.severity.lowercased() == "critical" }.count,
            weeklySlotCount: weeklySlots.count,
            averageScore: average
            ,
            rosterPreview: Array(students.prefix(8)),
            activeEvaluationNames: Array(evaluations.map(\.name).prefix(5))
        )
    }

    func loadStudentProfile(studentId: Int64, classId: Int64?) async throws -> StudentProfileSnapshot {
        guard let student = try await container.studentsRepository.listStudents().first(where: { $0.id == studentId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró el alumno \(studentId)."])
        }
        let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId })
        let attendanceData: [AttendanceRecordSnapshot]
        let evaluationsData: [Evaluation]
        let gradesData: [Grade]
        let incidentsData: [Incident]
        let journalAggregates: [SessionJournalAggregate]
        let journalDateByJournalId: [Int64: Date]

        if let classId {
            attendanceData = try await container.attendanceRepository.listAttendance(classId: classId)
                .map(attendanceSnapshot(from:))
                .filter { $0.studentId == studentId }
            evaluationsData = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
            gradesData = try await container.gradesRepository.listGradesForClass(classId: classId)
                .filter { $0.studentId == studentId }
            incidentsData = try await container.incidentsRepository.listIncidents(classId: classId)
                .filter { $0.studentId?.int64Value == studentId }
            let sessions = try await container.plannerRepository.listAllSessions()
                .filter { $0.groupId == classId }
            let sessionDateById = Dictionary(
                sessions.map { session in
                    (session.id, self.date(from: session))
                },
                uniquingKeysWith: { first, _ in first }
            )
            var collectedAggregates: [SessionJournalAggregate] = []
            for session in sessions {
                let aggregate = try await self.container.sessionJournalRepository.getJournalForSession(
                    planningSessionId: session.id
                )
                if let aggregate,
                   aggregate.individualNotes.contains(where: { $0.studentId?.int64Value == studentId }) {
                    collectedAggregates.append(aggregate)
                }
            }
            journalAggregates = collectedAggregates
            journalDateByJournalId = Dictionary(
                journalAggregates.map { aggregate in
                    let sessionDate = sessionDateById[aggregate.journal.planningSessionId] ?? Date.distantPast
                    return (aggregate.journal.id, sessionDate)
                },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            attendanceData = []
            evaluationsData = []
            gradesData = []
            incidentsData = []
            journalAggregates = []
            journalDateByJournalId = [:]
        }

        let presentCount = attendanceData.filter { $0.status.uppercased().contains("PRESENT") }.count
        let attendanceRate = attendanceData.isEmpty ? 0 : Int((Double(presentCount) / Double(attendanceData.count)) * 100.0)
        let averageScore: Double = {
            let values = gradesData.compactMap { $0.value?.doubleValue }
            guard !values.isEmpty else { return 0.0 }
            return values.reduce(0, +) / Double(values.count)
        }()
        let evidenceCount = gradesData.filter {
            !($0.evidence?.isEmpty ?? true) || !($0.evidencePath?.isEmpty ?? true)
        }.count
        let studentJournalNotes = journalAggregates.flatMap { aggregate in
            aggregate.individualNotes.filter { $0.studentId?.int64Value == studentId }
        }
        let familyCommunications = journalAggregates
            .map(\.journal.familyCommunicationText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let adaptations = journalAggregates
            .map(\.journal.adaptationsText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var timeline: [StudentTimelineEntry] = attendanceData.prefix(8).map {
            StudentTimelineEntry(
                date: $0.date,
                title: "Asistencia · \($0.status.capitalized)",
                subtitle: $0.note.isEmpty ? "Registro diario" : $0.note,
                kind: .attendance
            )
        }

        timeline.append(contentsOf: incidentsData.prefix(6).map {
            StudentTimelineEntry(
                date: Date(timeIntervalSince1970: TimeInterval($0.date.epochSeconds)),
                title: $0.title,
                subtitle: $0.detail ?? "Incidencia registrada",
                kind: .incident
            )
        })

        let evaluationsById = Dictionary(
            evaluationsData.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        timeline.append(contentsOf: gradesData.prefix(8).map { grade in
            let evaluationName = grade.evaluationId.flatMap { evaluationsById[$0.int64Value]?.name } ?? grade.columnId
            let subtitle: String
            if let value = grade.value {
                subtitle = String(format: "Nota %.1f", value.doubleValue)
            } else {
                subtitle = "Sin nota"
            }
            return StudentTimelineEntry(
                date: Date(timeIntervalSince1970: TimeInterval(grade.trace.updatedAt.epochSeconds)),
                title: "Evaluación · \(evaluationName)",
                subtitle: subtitle,
                kind: .evaluation
            )
        })

        timeline.append(contentsOf: studentJournalNotes.prefix(6).map { note in
            StudentTimelineEntry(
                date: journalDateByJournalId[note.journalId] ?? Date.distantPast,
                title: note.tag.isEmpty ? "Diario de aula" : "Diario · \(note.tag)",
                subtitle: note.note,
                kind: .incident
            )
        })

        timeline.sort { $0.date > $1.date }

        return StudentProfileSnapshot(
            student: student,
            schoolClass: schoolClass,
            attendanceRate: attendanceRate,
            averageScore: averageScore,
            incidentCount: incidentsData.count,
            followUpCount: attendanceData.filter(\.followUpRequired).count,
            instrumentsCount: gradesData.count,
            evidenceCount: evidenceCount,
            familyCommunicationCount: familyCommunications.count,
            journalSessionCount: journalAggregates.count,
            journalNoteCount: studentJournalNotes.count,
            adaptationsSummary: adaptations.first,
            familyCommunicationSummary: familyCommunications.first,
            latestAttendanceStatus: attendanceData.sorted { $0.date > $1.date }.first?.status,
            evaluationTitles: Array(evaluationsData.map(\.name).prefix(6)),
            recentAttendance: Array(attendanceData.sorted { $0.date > $1.date }.prefix(8)),
            incidents: incidentsData.sorted { $0.date.epochSeconds > $1.date.epochSeconds },
            evaluations: evaluationsData,
            timeline: timeline
        )
    }

    // Audit debt: this aggregates business data for the Mac roster. Keep it as a bridge shim
    // until an equivalent KMP use case can own the query and row-shaping logic.
    func loadMacStudentRows(classId: Int64?) async throws -> [MacStudentRowSnapshot] {
        let allClasses = try await container.classesRepository.listClasses()
        let classesToScan = classId.map { selectedClassId in
            allClasses.filter { $0.id == selectedClassId }
        } ?? allClasses
        let allStudents = try await container.studentsRepository.listStudents()
        let allStudentsById = Dictionary(allStudents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var studentsById: [Int64: Student] = [:]
        var membershipsByStudentId: [Int64: [MacStudentClassMembership]] = [:]
        var attendanceByStudentId: [Int64: [AttendanceRecordSnapshot]] = [:]
        var incidentsByStudentId: [Int64: [Incident]] = [:]
        var averageValuesByStudentId: [Int64: [Double]] = [:]
        var workGroupByStudentClassKey: [String: String] = [:]

        for schoolClass in classesToScan {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            roster.forEach { student in
                studentsById[student.id] = student
                membershipsByStudentId[student.id, default: []].append(
                    MacStudentClassMembership(id: schoolClass.id, className: schoolClass.name)
                )
            }

            let attendance = try await container.attendanceRepository.listAttendance(classId: schoolClass.id)
                .map(attendanceSnapshot(from:))
            for record in attendance {
                attendanceByStudentId[record.studentId, default: []].append(record)
            }

            let incidents = try await container.incidentsRepository.listIncidents(classId: schoolClass.id)
            for incident in incidents {
                guard let studentId = incident.studentId?.int64Value else { continue }
                incidentsByStudentId[studentId, default: []].append(incident)
            }

            if let notebookSheet = try? await container.notebookRepository.loadNotebookSnapshot(classId: schoolClass.id) {
                for row in notebookSheet.rows {
                    if let average = row.weightedAverage?.doubleValue {
                        averageValuesByStudentId[row.student.id, default: []].append(average)
                    }
                }
            }

            let groups = try await container.notebookRepository.listWorkGroups(classId: schoolClass.id, tabId: nil)
            let groupNames = Dictionary(
                groups.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
            let members = try await container.notebookRepository.listWorkGroupMembers(classId: schoolClass.id, tabId: nil)
            for member in members {
                let key = macStudentClassKey(studentId: member.studentId, classId: schoolClass.id)
                if workGroupByStudentClassKey[key] == nil {
                    workGroupByStudentClassKey[key] = groupNames[member.groupId]
                }
            }
        }

        if classId == nil {
            for student in allStudents where studentsById[student.id] == nil {
                studentsById[student.id] = student
            }
        }

        var rows: [MacStudentRowSnapshot] = []
        for student in studentsById.values.sorted(by: { lhs, rhs in
            let lhsName = "\(lhs.lastName) \(lhs.firstName)"
            let rhsName = "\(rhs.lastName) \(rhs.firstName)"
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }) {
            let memberships = (membershipsByStudentId[student.id] ?? [])
                .sorted { $0.className.localizedCaseInsensitiveCompare($1.className) == .orderedAscending }
            let primaryMembership = classId.flatMap { selectedClassId in
                memberships.first(where: { $0.id == selectedClassId })
            } ?? memberships.first
            let attendance = attendanceByStudentId[student.id, default: []]
            let incidents = incidentsByStudentId[student.id, default: []]
            let followUpCount = attendance.filter(\.followUpRequired).count
            let incidentCount = incidents.count
            let isFollowUp = student.isInjured || followUpCount > 0 || incidentCount > 0
            let followUpLabel: String
            if student.isInjured {
                followUpLabel = "Lesión"
            } else if followUpCount > 0 {
                followUpLabel = "Seguimiento"
            } else if incidentCount > 0 {
                followUpLabel = "Incidencias"
            } else {
                followUpLabel = "Normal"
            }

            let latestAttendance = attendance.sorted { $0.date > $1.date }.first
            let averageValues = averageValuesByStudentId[student.id, default: []]
            // TODO(KMP): expose an official cross-class student average when "Todas" spans memberships.
            let averageScore = averageValues.isEmpty ? nil : averageValues.reduce(0, +) / Double(averageValues.count)
            let latestObservation = latestObservationText(attendance: attendance, incidents: incidents)
            let workGroupKey = primaryMembership.map { macStudentClassKey(studentId: student.id, classId: $0.id) }
            rows.append(
                MacStudentRowSnapshot(
                    id: student.id,
                    student: allStudentsById[student.id] ?? student,
                    classId: primaryMembership?.id,
                    className: primaryMembership?.className ?? "Sin clase",
                    allClassMemberships: memberships,
                    followUpLabel: followUpLabel,
                    recentAttendanceLabel: latestAttendance?.status ?? "Sin registro",
                    averageText: averageScore.map { IosFormatting.decimal($0) } ?? "--",
                    incidentCount: incidentCount,
                    lastObservationText: latestObservation,
                    isInjured: student.isInjured,
                    isFollowUp: isFollowUp,
                    workGroupName: workGroupKey.flatMap { workGroupByStudentClassKey[$0] } ?? "Sin grupo"
                )
            )
        }
        return rows
    }

    private func macStudentClassKey(studentId: Int64, classId: Int64) -> String {
        "\(studentId)|\(classId)"
    }

    // Audit debt: quick-note persistence belongs in shared domain logic once a KMP use case exists.
    func saveQuickStudentNote(studentId: Int64, classId: Int64?, note: String) async throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let classId else {
            throw NSError(domain: "KmpBridge", code: -4101, userInfo: [NSLocalizedDescriptionKey: "Selecciona una clase para guardar notas rápidas."])
        }
        guard let student = try await container.studentsRepository.listStudents().first(where: { $0.id == studentId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró el alumno \(studentId)."])
        }
        let now = Date()
        let sessions = try await container.plannerRepository.listAllSessions()
            .filter { $0.groupId == classId }
            .sorted { date(from: $0) > date(from: $1) }
        guard let session = sessions.first(where: { date(from: $0) <= now }) else {
            throw NSError(domain: "KmpBridge", code: -4102, userInfo: [NSLocalizedDescriptionKey: "No hay sesiones pasadas o de hoy donde guardar la nota rápida."])
        }

        let aggregate = try await container.sessionJournalRepository.getOrCreateJournal(session: session)
        let journalId = aggregate.journal.id
        let quickNote = SessionJournalIndividualNote(
            id: 0,
            journalId: journalId,
            studentId: KotlinLong(value: studentId),
            studentName: student.fullName,
            note: trimmed,
            tag: "nota rápida"
        )
        let updatedAggregate = SessionJournalAggregate(
            journal: aggregate.journal,
            individualNotes: aggregate.individualNotes + [quickNote],
            actions: aggregate.actions,
            media: aggregate.media,
            links: aggregate.links
        )
        _ = try await container.sessionJournalRepository.saveJournalAggregate(aggregate: updatedAggregate)
        if let stored = try await container.sessionJournalRepository.getJournalForSession(
            planningSessionId: aggregate.journal.planningSessionId
        ) {
            enqueueSavedJournal(stored)
        } else {
            enqueueSavedJournal(updatedAggregate)
        }
        status = "Nota rápida guardada para \(student.fullName)"
    }

    // Audit debt: presentation summary rules should move beside StudentProfileSnapshot creation in KMP.
    private func latestObservationText(from profile: StudentProfileSnapshot?) -> String {
        guard let profile else { return "Sin observaciones" }
        if let attendanceNote = profile.recentAttendance.first(where: { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.note {
            return attendanceNote
        }
        if let incident = profile.incidents.first {
            return incident.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? incident.detail ?? incident.title
                : incident.title
        }
        if let timelineEntry = profile.timeline.first, timelineEntry.subtitle != "Registro diario" {
            return timelineEntry.subtitle
        }
        return "Sin observaciones"
    }

    private func latestObservationText(attendance: [AttendanceRecordSnapshot], incidents: [Incident]) -> String {
        let recentAttendance = attendance.sorted { $0.date > $1.date }
        if let attendanceNote = recentAttendance.first(where: { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.note {
            return attendanceNote
        }
        if let incident = incidents.sorted(by: { $0.date.epochSeconds > $1.date.epochSeconds }).first {
            return incident.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? incident.detail ?? incident.title
                : incident.title
        }
        return "Sin observaciones"
    }

    func buildReportPreview(
        classId: Int64,
        studentId: Int64? = nil,
        kind: ReportKind = .groupOverview,
        termLabel: String? = nil
    ) async throws -> ReportPreviewPayload {
        let context = try await buildReportGenerationContext(classId: classId, studentId: studentId, kind: kind, termLabel: termLabel)
        return ReportPreviewPayload(
            classId: context.classId,
            className: context.className,
            previewText: context.classicReportText,
            generatedAt: Date()
        )
    }

    func buildReportGenerationContext(
        classId: Int64,
        studentId: Int64? = nil,
        kind: ReportKind,
        termLabel: String? = nil
    ) async throws -> ReportGenerationContext {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }

        let trends = try? await getAITrendsAndMetrics(classId: classId, studentId: studentId)

        let resolvedCourseLabel = courseLabel(for: schoolClass)

        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        let evaluations = try await evaluations(for: classId)
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        let groupedGrades = Dictionary(grouping: grades, by: \.studentId)
        let rubricCount = Set(evaluations.compactMap { $0.rubricId?.int64Value }).count
        let rows = students.map { student -> String in
            let values = groupedGrades[student.id, default: []].compactMap { $0.value?.doubleValue }
            let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
            return "\(student.lastName), \(student.firstName): \(IosFormatting.decimal(from: average))"
        }
        let bytes = try await container.reportService.exportNotebookReport(
            request: NotebookReportRequest(className: schoolClass.name, rows: rows)
        )
        let classicText = String(data: data(from: bytes), encoding: .utf8) ?? "Vista previa no disponible para este informe."

        switch kind {
        case .groupOverview:
            let summary = try await loadCourseSummary(classId: classId)
            let strengths = compactSuggestions(
                summary.averageScore >= 7.0 ? "El grupo mantiene una media global sólida en el cuaderno." : nil,
                summary.attendanceRate >= 90 ? "La asistencia reciente sostiene una dinámica estable." : nil,
                summary.severeIncidentCount == 0 && summary.incidentCount <= 2 ? "La convivencia está contenida y sin alertas graves." : nil,
                summary.evaluationCount >= 3 ? "Hay variedad suficiente de instrumentos para argumentar el informe." : nil
            )
            let needsAttention = compactSuggestions(
                summary.studentCount == 0 ? "Todavía no hay alumnado asociado al grupo." : nil,
                summary.averageScore > 0 && summary.averageScore < 5.0 ? "La media del grupo pide refuerzo pedagógico." : nil,
                (1..<85).contains(summary.attendanceRate) ? "La asistencia reciente está por debajo del umbral deseable." : nil,
                summary.severeIncidentCount > 0 ? "Existen incidencias graves que conviene contextualizar con cuidado." : nil
            )
            let actions = compactSuggestions(
                (1..<85).contains(summary.attendanceRate) ? "Planificar seguimiento específico de asistencia para el alumnado con más ausencias." : nil,
                summary.averageScore > 0 && summary.averageScore < 5.0 ? "Revisar instrumentos y preparar refuerzo para la próxima unidad." : nil,
                summary.evaluationCount < 2 ? "Añadir más evidencias evaluativas antes de emitir conclusiones firmes." : nil
            )
            let facts = [
                "Alumnado total: \(summary.studentCount).",
                "Media global registrada: \(IosFormatting.decimal(from: summary.averageScore)).",
                "Asistencia reciente estimada: \(summary.attendanceRate)%.",
                "Evaluaciones activas: \(summary.evaluationCount) y rúbricas vinculadas: \(rubricCount).",
                "Incidencias registradas: \(summary.incidentCount), graves: \(summary.severeIncidentCount).",
                summary.activeEvaluationNames.isEmpty ? "No hay instrumentos activos destacados." : "Instrumentos activos destacados: \(summary.activeEvaluationNames.joined(separator: ", "))."
            ]
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: nil,
                studentName: nil,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: summary.averageScore,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "docente",
                summary: "Síntesis global del grupo con foco en rendimiento, asistencia y clima.",
                metrics: [
                    ReportMetric(title: "Alumnado", value: "\(summary.studentCount)", systemImage: "person.3.fill"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: summary.averageScore), systemImage: "sum"),
                    ReportMetric(title: "Asistencia", value: "\(summary.attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Incidencias", value: "\(summary.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                ],
                factLines: facts,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: summary.rosterPreview.isEmpty ? [] : ["Muestra de roster: \(summary.rosterPreview.map(\.fullName).joined(separator: ", "))."],
                classicReportText: classicText,
                hasEnoughData: summary.studentCount > 0,
                dataQualityNote: summary.evaluationCount == 0 ? "No hay evaluaciones registradas todavía; el relato debe ser prudente." : nil,
                trends: trends
            )

        case .studentSummary:
            guard let studentId else {
                return ReportGenerationContext(
                    classId: classId,
                    className: schoolClass.name,
                    studentId: nil,
                    studentName: nil,
                    kind: kind,
                    reportTitle: kind.title,
                    courseLabel: resolvedCourseLabel,
                    termLabel: termLabel,
                    numericScore: nil,
                    curriculumReferences: [],
                    promptDirectives: [],
                    audienceHint: "tutoria",
                    summary: "Hace falta seleccionar un alumno para construir este informe.",
                    metrics: [],
                    factLines: ["No se ha seleccionado alumnado para el informe individual."],
                    strengths: [],
                    needsAttention: ["Selecciona un alumno antes de generar el borrador con IA."],
                    recommendedActions: [],
                    supportNotes: [],
                    classicReportText: classicText,
                    hasEnoughData: false,
                    dataQualityNote: "El informe individual requiere selección de alumno.",
                    trends: nil
                )
            }
            let profile = try await loadStudentProfile(studentId: studentId, classId: classId)
            let strengths = compactSuggestions(
                profile.averageScore >= 7.0 ? "Mantiene un rendimiento medio sólido en los instrumentos registrados." : nil,
                profile.attendanceRate >= 90 ? "Sostiene una asistencia alta en el periodo analizado." : nil,
                profile.incidentCount == 0 ? "No presenta incidencias registradas en el grupo." : nil,
                profile.evidenceCount > 0 ? "Cuenta con evidencias adjuntas que apoyan la valoración." : nil
            )
            let needsAttention = compactSuggestions(
                profile.instrumentsCount == 0 ? "No hay todavía instrumentos suficientes para una valoración cerrada." : nil,
                profile.averageScore > 0 && profile.averageScore < 5.0 ? "El rendimiento registrado está por debajo del nivel esperado." : nil,
                (1..<85).contains(profile.attendanceRate) ? "La asistencia necesita seguimiento." : nil,
                profile.incidentCount > 0 ? "Existen incidencias registradas que conviene contextualizar pedagógicamente." : nil,
                profile.followUpCount > 0 ? "Hay registros de seguimiento en asistencia que requieren continuidad." : nil
            )
            let actions = compactSuggestions(
                profile.averageScore > 0 && profile.averageScore < 5.0 ? "Proponer refuerzo específico en los instrumentos con peor resultado." : nil,
                (1..<85).contains(profile.attendanceRate) ? "Acordar rutina de seguimiento de asistencia con tutoría y familia." : nil,
                profile.familyCommunicationCount == 0 ? "Preparar una comunicación breve a familia si el caso lo requiere." : nil,
                profile.evaluationTitles.isEmpty ? "Recoger nuevas evidencias antes del siguiente informe." : nil
            )
            let facts = compactSuggestions(
                "Alumno: \(profile.student.fullName).",
                "Asistencia estimada: \(profile.attendanceRate)%.",
                profile.averageScore > 0 ? "Media registrada: \(IosFormatting.decimal(from: profile.averageScore))." : "Sin media consolidada todavía.",
                "Incidencias registradas: \(profile.incidentCount).",
                "Seguimientos activos: \(profile.followUpCount).",
                profile.latestAttendanceStatus == nil ? nil : "Último estado de asistencia: \(profile.latestAttendanceStatus ?? "").",
                profile.evaluationTitles.isEmpty ? "No hay evaluaciones vinculadas todavía." : "Instrumentos presentes: \(profile.evaluationTitles.joined(separator: ", "))."
            )
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: studentId,
                studentName: profile.student.fullName,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: profile.averageScore > 0 ? profile.averageScore : nil,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "tutoria",
                summary: "Síntesis individual centrada en seguimiento, evidencias y próximos pasos.",
                metrics: [
                    ReportMetric(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum"),
                    ReportMetric(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill"),
                    ReportMetric(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                ],
                factLines: facts,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: compactSuggestions(
                    profile.adaptationsSummary,
                    profile.familyCommunicationSummary,
                    profile.timeline.first.map { "Último hito registrado: \($0.title). \($0.subtitle)" }
                ),
                classicReportText: classicText,
                hasEnoughData: profile.instrumentsCount > 0 || profile.journalNoteCount > 0 || profile.incidentCount > 0,
                dataQualityNote: profile.instrumentsCount == 0 ? "Hay poca evidencia evaluativa registrada; conviene evitar conclusiones fuertes." : nil,
                trends: trends
            )

        case .evaluationDigest:
            let values = grades.compactMap { $0.value?.doubleValue }
            let average = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
            let evaluationsWithRubric = evaluations.filter { $0.rubricId != nil }.count
            let strengths = compactSuggestions(
                evaluations.count >= 3 ? "Existe una base suficiente de instrumentos activos para describir el proceso evaluativo." : nil,
                evaluationsWithRubric > 0 ? "Hay rúbricas vinculadas que ayudan a justificar criterios y niveles." : nil,
                !values.isEmpty ? "Ya existen calificaciones registradas sobre las que redactar el digest." : nil
            )
            let needsAttention = compactSuggestions(
                evaluations.isEmpty ? "No hay instrumentos evaluativos creados en este grupo." : nil,
                evaluationsWithRubric == 0 && !evaluations.isEmpty ? "Ninguna evaluación está enlazada a una rúbrica." : nil,
                values.isEmpty ? "Todavía no hay calificaciones registradas para sintetizar resultados." : nil
            )
            let actions = compactSuggestions(
                evaluationsWithRubric == 0 && !evaluations.isEmpty ? "Valorar vincular rúbricas a los instrumentos más relevantes." : nil,
                values.isEmpty ? "Registrar evidencias antes de compartir un resumen valorativo." : nil,
                evaluations.count < 2 ? "Diversificar instrumentos si se necesita una foto más completa del aprendizaje." : nil
            )
            let factLines = [
                "Instrumentos activos: \(evaluations.count).",
                "Rúbricas vinculadas: \(evaluationsWithRubric) de \(evaluations.count).",
                values.isEmpty ? "No hay notas registradas todavía." : "Media agregada de calificaciones: \(IosFormatting.decimal(from: average)).",
                evaluations.isEmpty ? "Sin nombres de instrumentos disponibles." : "Instrumentos destacados: \(evaluations.prefix(6).map(\.name).joined(separator: ", "))."
            ]
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: nil,
                studentName: nil,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: average > 0 ? average : nil,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "docente",
                summary: "Lectura narrativa de instrumentos, pesos, rúbricas y evidencias disponibles.",
                metrics: [
                    ReportMetric(title: "Instrumentos", value: "\(evaluations.count)", systemImage: "chart.bar.doc.horizontal"),
                    ReportMetric(title: "Rúbricas", value: "\(evaluationsWithRubric)", systemImage: "checklist"),
                    ReportMetric(title: "Notas", value: "\(values.count)", systemImage: "number"),
                    ReportMetric(title: "Media", value: IosFormatting.decimal(from: average), systemImage: "sum")
                ],
                factLines: factLines,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: evaluations.prefix(4).map { "\($0.name) · peso \(IosFormatting.decimal(from: $0.weight)) · tipo \($0.type)" },
                classicReportText: classicText,
                hasEnoughData: !evaluations.isEmpty,
                dataQualityNote: values.isEmpty ? "Hay estructura evaluativa, pero faltan calificaciones para una síntesis más sólida." : nil,
                trends: trends
            )

        case .operationsSnapshot:
            let attendance = try await attendanceHistory(for: classId, days: 14)
            let incidents = try await incidents(for: classId)
            let sessions = try await container.plannerRepository.listAllSessions()
                .filter { $0.groupId == classId }
                .sorted { lhs, rhs in
                    if lhs.year == rhs.year, lhs.weekNumber == rhs.weekNumber {
                        if lhs.dayOfWeek == rhs.dayOfWeek { return lhs.period > rhs.period }
                        return lhs.dayOfWeek > rhs.dayOfWeek
                    }
                    if lhs.year == rhs.year { return lhs.weekNumber > rhs.weekNumber }
                    return lhs.year > rhs.year
                }
            var journalSummaries: [SessionJournalSummary] = []
            if !sessions.isEmpty {
                journalSummaries = try await plannerJournalSummaries(sessionIds: Array(sessions.prefix(8).map(\.id)))
            }
            let presentCount = attendance.filter { $0.status.uppercased().contains("PRESENT") }.count
            let attendanceRate = attendance.isEmpty ? 0 : Int((Double(presentCount) / Double(attendance.count)) * 100.0)
            let climateValues = journalSummaries.map(\.climateScore).filter { $0 > 0 }
            let climateAverage = climateValues.isEmpty ? 0.0 : Double(climateValues.reduce(0, +)) / Double(climateValues.count)
            let strengths = compactSuggestions(
                attendanceRate >= 90 ? "La asistencia reciente favorece una operativa estable." : nil,
                incidents.prefix(5).isEmpty ? "No hay incidencias recientes relevantes en el grupo." : nil,
                climateAverage >= 4.0 ? "El clima de aula registrado en diarios es positivo." : nil
            )
            let needsAttention = compactSuggestions(
                (1..<85).contains(attendanceRate) ? "La asistencia reciente pide vigilancia operativa." : nil,
                incidents.prefix(5).count >= 3 ? "Se acumulan varias incidencias recientes." : nil,
                climateAverage > 0 && climateAverage < 3.0 ? "El clima de aula reportado es frágil." : nil,
                journalSummaries.isEmpty ? "No hay diarios recientes suficientes para sostener el resumen operativo." : nil
            )
            let actions = compactSuggestions(
                (1..<85).contains(attendanceRate) ? "Revisar alumnado con ausencias o retrasos repetidos." : nil,
                incidents.prefix(5).count >= 3 ? "Agrupar incidencias por patrón y definir seguimiento corto." : nil,
                journalSummaries.isEmpty ? "Completar diarios de sesión para enriquecer el seguimiento semanal." : nil
            )
            let factLines = compactSuggestions(
                "Asistencia reciente estimada: \(attendanceRate)%.",
                "Incidencias en histórico reciente: \(incidents.prefix(8).count).",
                journalSummaries.isEmpty ? "Sin diarios recientes disponibles." : "Diarios recientes consultados: \(journalSummaries.count).",
                climateAverage > 0 ? "Clima medio registrado: \(IosFormatting.decimal(from: climateAverage))." : "Sin puntuación media de clima disponible.",
                incidents.first.map { "Última incidencia: \($0.title)." }
            )
            let supportNotes = compactSuggestions(
                incidents.first?.detail,
                journalSummaries.first.map { "Última sesión con incidencia: etiquetas \($0.incidentTags.joined(separator: ", "))" }
            )
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: nil,
                studentName: nil,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: climateAverage > 0 ? climateAverage : nil,
                curriculumReferences: [],
                promptDirectives: [],
                audienceHint: "docente",
                summary: "Resumen semanal de operativa, asistencia, incidencias y señales del diario.",
                metrics: [
                    ReportMetric(title: "Asistencia", value: "\(attendanceRate)%", systemImage: "checklist.checked"),
                    ReportMetric(title: "Incidencias", value: "\(incidents.prefix(8).count)", systemImage: "exclamationmark.bubble.fill"),
                    ReportMetric(title: "Diarios", value: "\(journalSummaries.count)", systemImage: "doc.text.fill"),
                    ReportMetric(title: "Clima", value: IosFormatting.decimal(from: climateAverage), systemImage: "sun.max.fill")
                ],
                factLines: factLines,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: actions,
                supportNotes: supportNotes,
                classicReportText: classicText,
                hasEnoughData: !attendance.isEmpty || !incidents.isEmpty || !journalSummaries.isEmpty,
                dataQualityNote: journalSummaries.isEmpty ? "El resumen operativo se apoya más en asistencia e incidencias que en diarios completos." : nil,
                trends: trends
            )

        case .lomloeEvaluationComment:
            guard let studentId else {
                return ReportGenerationContext(
                    classId: classId,
                    className: schoolClass.name,
                    studentId: nil,
                    studentName: nil,
                    kind: kind,
                    reportTitle: kind.title,
                    courseLabel: resolvedCourseLabel,
                    termLabel: termLabel,
                    numericScore: nil,
                    curriculumReferences: ["CE1", "CE2", "CE3", "CE4", "CE5"],
                    promptDirectives: ["Comentario breve, personalizado, competencial y listo para informe trimestral."],
                    audienceHint: "familia",
                    summary: "Hace falta seleccionar un alumno para generar el comentario LOMLOE.",
                    metrics: [],
                    factLines: ["Selecciona un alumno para generar el comentario de evaluación."],
                    strengths: [],
                    needsAttention: ["El comentario LOMLOE requiere un alumno concreto."],
                    recommendedActions: [],
                    supportNotes: [],
                    classicReportText: "Selecciona un alumno para generar el comentario LOMLOE.",
                    hasEnoughData: false,
                    dataQualityNote: "El comentario LOMLOE es individual y requiere selección de alumno.",
                    trends: nil
                )
            }
            let profile = try await loadStudentProfile(studentId: studentId, classId: classId)
            let numericScore = profile.averageScore > 0 ? profile.averageScore : nil
            let performanceBand: String = {
                guard let numericScore else { return "Sin calificación consolidada" }
                switch numericScore {
                case ..<5: return "Insuficiente"
                case 5..<6: return "Suficiente"
                case 6..<7: return "Bien"
                case 7..<9: return "Notable"
                default: return "Sobresaliente"
                }
            }()
            let curriculumReferences = inferredCurriculumReferences(for: profile)
            let strengths = compactSuggestions(
                profile.averageScore >= 7.0 ? "Ha alcanzado satisfactoriamente buena parte de los criterios trabajados." : nil,
                profile.attendanceRate >= 90 ? "Mantiene una asistencia que favorece la continuidad del aprendizaje." : nil,
                profile.incidentCount == 0 ? "Participa sin incidencias relevantes en el periodo observado." : nil,
                profile.evidenceCount > 0 ? "Existen evidencias registradas que respaldan su progreso." : nil
            )
            let needsAttention = compactSuggestions(
                numericScore == nil ? "La valoración debe ser prudente porque la evidencia numérica todavía es limitada." : nil,
                numericScore != nil && numericScore! < 5.0 ? "Varios criterios siguen en desarrollo y requieren refuerzo guiado." : nil,
                (1..<85).contains(profile.attendanceRate) ? "La continuidad en la asistencia condiciona parte del progreso." : nil,
                profile.evaluationTitles.isEmpty ? "Conviene ampliar instrumentos y evidencias antes del siguiente informe." : nil
            )
            let recommendedActions = compactSuggestions(
                numericScore != nil && numericScore! < 5.0 ? "Reforzar de forma progresiva los criterios prioritarios del siguiente periodo." : nil,
                profile.adaptationsSummary == nil && profile.followUpCount > 0 ? "Mantener seguimiento cercano y propuestas de mejora concretas." : nil,
                "Se recomienda seguir consolidando hábitos de participación, autonomía y transferencia a nuevas situaciones motrices."
            )
            let facts = compactSuggestions(
                "Alumno: \(profile.student.fullName).",
                "Curso: \(resolvedCourseLabel).",
                termLabel.map { "Trimestre: \($0)." },
                numericScore.map { "Calificación orientativa interna: \(IosFormatting.decimal(from: $0)) (\(performanceBand))." },
                "Asistencia estimada: \(profile.attendanceRate)%.",
                profile.evaluationTitles.isEmpty ? "No hay instrumentos específicos nombrados." : "Instrumentos trabajados: \(profile.evaluationTitles.joined(separator: ", ")).",
                "Referencias curriculares sugeridas: \(curriculumReferences.joined(separator: ", "))."
            )
            let supportNotes = compactSuggestions(
                profile.adaptationsSummary.map { "Adaptaciones o apoyos: \($0)" },
                profile.familyCommunicationSummary.map { "Comunicación familia: \($0)" },
                profile.timeline.first.map { "Última evidencia relevante: \($0.title). \($0.subtitle)" }
            )
            let classicCommentShell = """
            ---
            COMENTARIO DE EVALUACIÓN — \(profile.student.fullName) | \(resolvedCourseLabel) | \(termLabel ?? "Trimestre")

            Comentario pendiente de generación IA local. Usa el botón “Generar borrador” para crear el texto final en formato LOMLOE.
            ---
            """
            return ReportGenerationContext(
                classId: classId,
                className: schoolClass.name,
                studentId: studentId,
                studentName: profile.student.fullName,
                kind: kind,
                reportTitle: kind.title,
                courseLabel: resolvedCourseLabel,
                termLabel: termLabel,
                numericScore: numericScore,
                curriculumReferences: curriculumReferences,
                promptDirectives: [
                    "Aplicar estructura de 4 bloques breve para comentario trimestral LOMLOE.",
                    "No mencionar la nota numérica en el texto final.",
                    "Mencionar al menos una competencia específica CE1-CE5.",
                    "Tono positivo, específico y listo para copiar en el informe."
                ],
                audienceHint: "familia",
                summary: "Comentario cualitativo trimestral de Educación Física, breve, competencial y listo para informe.",
                metrics: [
                    ReportMetric(title: "Curso", value: resolvedCourseLabel, systemImage: "graduationcap.fill"),
                    ReportMetric(title: "Trimestre", value: termLabel ?? "Sin definir", systemImage: "calendar"),
                    ReportMetric(title: "Nota guía", value: numericScore.map { IosFormatting.decimal(from: $0) } ?? "Sin nota", systemImage: "number"),
                    ReportMetric(title: "CE", value: curriculumReferences.joined(separator: ", "), systemImage: "list.bullet.clipboard")
                ],
                factLines: facts,
                strengths: strengths,
                needsAttention: needsAttention,
                recommendedActions: recommendedActions,
                supportNotes: supportNotes,
                classicReportText: classicCommentShell,
                hasEnoughData: numericScore != nil || !profile.evaluationTitles.isEmpty || !profile.timeline.isEmpty,
                dataQualityNote: numericScore == nil ? "Si hay poca nota numérica, el comentario debe apoyarse en evidencias, actitud y progreso observado." : nil,
                trends: trends
            )
        }
    }


    func removeStudentFromSelectedClass(studentId: Int64) async throws {
        guard let classId = selectedStudentsClassId else { return }
        try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: studentId)
        try await refreshStudentsDirectory()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func deleteStudentEverywhere(studentId: Int64) async throws {
        try await container.studentsRepository.deleteStudent(studentId: studentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueLocalChange(
            entity: "student_deleted",
            id: "\(studentId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["id": studentId]
        )
    }

    func assignStudentToClass(studentId: Int64, classId: Int64) async throws {
        try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId)
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func assignStudentsToClass(studentIds: [Int64], classId: Int64) async throws {
        for studentId in studentIds {
            try await container.classesRepository.addStudentToClass(classId: classId, studentId: studentId)
        }
        try await refreshStudentsDirectory()
        try await refreshDashboard()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func removeStudentsFromClass(studentIds: [Int64], classId: Int64) async throws {
        for studentId in studentIds {
            try await container.classesRepository.removeStudentFromClass(classId: classId, studentId: studentId)
        }
        try await refreshStudentsDirectory()
        enqueueRosterSnapshot(forClassId: classId, updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func deleteStudentsEverywhere(studentIds: [Int64]) async throws {
        let nowEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        for studentId in studentIds {
            try await container.studentsRepository.deleteStudent(studentId: studentId)
            enqueueLocalChange(
                entity: "student_deleted",
                id: "\(studentId)",
                updatedAtEpochMs: nowEpochMs,
                payload: ["id": studentId]
            )
        }
        try await refreshStudentsDirectory()
        try await refreshDashboard()
    }

    func listClassesForStudent(studentId: Int64) async throws -> [SchoolClass] {
        let allClasses = try await container.classesRepository.listClasses()
        var matched: [SchoolClass] = []
        for schoolClass in allClasses {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            if roster.contains(where: { $0.id == studentId }) {
                matched.append(schoolClass)
            }
        }
        return matched
    }

    func unassignedStudentIds() async throws -> Set<Int64> {
        let allClasses = try await container.classesRepository.listClasses()
        var assignedIds = Set<Int64>()
        for schoolClass in allClasses {
            let roster = try await container.classesRepository.listStudentsInClass(classId: schoolClass.id)
            for student in roster {
                assignedIds.insert(student.id)
            }
        }
        let allStudents = try await container.studentsRepository.listStudents()
        return Set(allStudents.map(\.id)).subtracting(assignedIds)
    }

    private static let stableDayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // Extrae año/mes/día con la zona horaria local (respeta el día que el usuario
    // quiso decir) pero ancla el epoch resultante a UTC, para que el mismo día
    // civil siempre produzca el mismo valor aunque cambie la zona horaria del
    // dispositivo (viajes, cambios de huso) entre una escritura y la siguiente.
    private func startOfDayEpochMs(for date: Date) -> Int64 {
        let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let stableDate = Self.stableDayCalendar.date(from: dayComponents) ?? date
        return Int64(stableDate.timeIntervalSince1970 * 1000)
    }

    private func startOfDayEpochMs(forEpochSeconds epochSeconds: Int64) -> Int64 {
        startOfDayEpochMs(for: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    private func attendanceSnapshot(from row: Attendance_) -> AttendanceRecordSnapshot {
        AttendanceRecordSnapshot(
            id: row.id,
            studentId: row.studentId,
            classId: row.classId,
            date: Date(timeIntervalSince1970: TimeInterval(row.date.epochSeconds)),
            status: row.status,
            note: row.note,
            hasIncident: row.hasIncident,
            followUpRequired: row.followUpRequired,
            sessionId: row.sessionId?.int64Value
        )
    }

    func compactSuggestions(_ values: String?...) -> [String] {
        values.compactMap {
            guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
    }

    func courseLabel(for schoolClass: SchoolClass) -> String {
        let lowercasedName = schoolClass.name.lowercased()
        if lowercasedName.contains("bach") || lowercasedName.contains("bac") || lowercasedName.contains("bto") || lowercasedName.contains("bat") {
            return "\(schoolClass.course)º Bachillerato"
        }
        if lowercasedName.contains("prim") || lowercasedName.contains("pri") {
            return "\(schoolClass.course)º Primaria"
        }
        if lowercasedName.contains("eso") || (1...4).contains(schoolClass.course) {
            return "\(schoolClass.course)º ESO"
        }
        return "\(schoolClass.course)º"
    }

    private func inferredCurriculumReferences(for profile: StudentProfileSnapshot) -> [String] {
        var references: [String] = []
        if profile.attendanceRate > 0 {
            references.append("CE1")
        }
        if !profile.evaluationTitles.isEmpty || profile.averageScore > 0 {
            references.append("CE2")
        }
        if profile.evidenceCount > 0 {
            references.append("CE3")
        }
        if profile.timeline.contains(where: { $0.title.localizedCaseInsensitiveContains("salida") || $0.title.localizedCaseInsensitiveContains("entorno") }) {
            references.append("CE4")
        }
        if profile.incidentCount == 0 || profile.followUpCount > 0 {
            references.append("CE5")
        }
        let source = references.isEmpty ? ["CE1", "CE2", "CE5"] : references
        var seen = Set<String>()
        return source.filter { seen.insert($0).inserted }
    }

    private func data(from byteArray: KotlinByteArray) -> Data {
        var buffer = Data(capacity: Int(byteArray.size))
        for index in 0..<Int(byteArray.size) {
            let value = UInt8(bitPattern: byteArray.get(index: Int32(index)))
            buffer.append(value)
        }
        return buffer
    }

    private func isoWeekday(from date: Date) -> Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: date)
        switch weekday {
        case 1: return 7
        default: return weekday - 1
        }
    }

}
