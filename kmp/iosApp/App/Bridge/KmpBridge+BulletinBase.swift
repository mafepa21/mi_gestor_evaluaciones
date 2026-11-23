import Foundation
import MiGestorKit

// Recoge, para un grupo y un periodo, los datos de cada alumno que alimentan la base anónima
// del boletín. Solo lee: no escribe nada en la base de datos.
// No lee datos de inclusión ni de salud (adaptaciones, lesiones): quedan fuera a propósito.
extension KmpBridge {
    /// Clave de códigos «Alumno NN» del informe anónimo para el alumnado actual del grupo.
    func bulletinCodeKey(classId: Int64) async throws -> [Int: Int64] {
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        return BulletinBaseReportBuilder.codeNumbers(studentIds: students.map(\.id), classId: classId)
    }

    /// - Parameter fallbackPeriod: fechas a usar si el horario docente no tiene periodos de
    ///   evaluación. Si los tiene, se usan los suyos: así el informe y la IA ven el mismo trimestre.
    func buildBulletinBaseReport(
        classId: Int64,
        termLabel: String,
        period fallbackPeriod: (start: Date, end: Date)
    ) async throws -> BulletinBaseReport {
        guard let schoolClass = try await container.classesRepository.listClasses().first(where: { $0.id == classId }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "No se encontró la clase \(classId)."])
        }
        let students = try await container.classesRepository.listStudentsInClass(classId: classId)
        guard !students.isEmpty else {
            return BulletinBaseReportBuilder.build(
                className: schoolClass.name,
                classId: classId,
                termLabel: termLabel,
                students: [],
                evaluableColumnCount: 0,
                selfAssessmentCount: 0
            )
        }

        let termKey = TeacherTermNoteKeys.shared.fromLabel(label: termLabel)
        let evidenceUseCase = container.buildLomloeCommentEvidence
        let schedulePeriod = try? await evidenceUseCase.resolveTermPeriod(termKey: termKey)
        let period: (start: Date, end: Date) = schedulePeriod.map {
            (Date(timeIntervalSince1970: TimeInterval($0.startEpochMs) / 1000),
             Date(timeIntervalSince1970: TimeInterval($0.endEpochMs) / 1000))
        } ?? fallbackPeriod

        func inPeriod(_ date: Date) -> Bool { date >= period.start && date <= period.end }
        func date(_ instant: Instant) -> Date { Date(timeIntervalSince1970: TimeInterval(instant.epochSeconds)) }
        func date(epochMs: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000) }

        var inputs: [Int64: BulletinBaseStudentInput] = Dictionary(
            students.map { ($0.id, BulletinBaseStudentInput(studentId: $0.id, firstName: $0.firstName, lastName: $0.lastName)) },
            uniquingKeysWith: { first, _ in first }
        )

        // Asistencia y sus notas.
        let attendance = try await container.attendanceRepository.listAttendance(classId: classId)
        for record in attendance where inputs[record.studentId] != nil {
            let recordDate = date(record.date)
            guard inPeriod(recordDate) else { continue }
            switch NotebookAttendanceStatus.canonical(record.status) {
            case NotebookAttendanceStatus.present: inputs[record.studentId]?.attendance.present += 1
            case NotebookAttendanceStatus.absent: inputs[record.studentId]?.attendance.absent += 1
            case NotebookAttendanceStatus.late: inputs[record.studentId]?.attendance.late += 1
            case NotebookAttendanceStatus.justified: inputs[record.studentId]?.attendance.justified += 1
            case NotebookAttendanceStatus.noMaterial: inputs[record.studentId]?.attendance.noMaterial += 1
            case NotebookAttendanceStatus.exempt: inputs[record.studentId]?.attendance.exempt += 1
            default: inputs[record.studentId]?.attendance.other += 1
            }
            let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                inputs[record.studentId]?.observations.append(BulletinBaseObservation(date: recordDate, text: note))
            }
        }

        // Notas evaluables: cuentan para la media, no están ocultas y tienen valor de 0 a 10.
        // Así quedan fuera los datos brutos (metros, segundos…) y las columnas privadas.
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        let categories = try await container.notebookRepository.listColumnCategories(classId: classId, tabId: nil)
        let categoryNameById = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let evaluableTypes: Set<String> = ["NUMERIC", "RUBRIC", "CALCULATED"]
        let evaluableColumns = Dictionary(
            columns
                .filter { $0.countsTowardAverage && !$0.isHidden && evaluableTypes.contains($0.type.name) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var usedColumnIds = Set<String>()
        let grades = try await container.gradesRepository.listGradesForClass(classId: classId)
        for grade in grades {
            guard inputs[grade.studentId] != nil,
                  let column = evaluableColumns[grade.columnId],
                  let value = grade.value?.doubleValue,
                  (0...10).contains(value) else { continue }
            let gradeDate = column.dateEpochMs.map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000) }
                ?? date(grade.trace.updatedAt)
            guard inPeriod(gradeDate) else { continue }
            usedColumnIds.insert(column.id)
            inputs[grade.studentId]?.grades.append(
                BulletinBaseGrade(
                    category: column.categoryId.flatMap { categoryNameById[$0] },
                    title: column.title,
                    value: value,
                    weight: column.weight,
                    date: gradeDate
                )
            )
        }

        // Autoevaluaciones: instrumentos marcados como tal o con «autoeval» en el título.
        var usedSelfAssessmentIds = Set<String>()
        let selfAssessmentColumns = columns.filter {
            !$0.isHidden && ($0.instrumentKind.name == "SELF_ASSESSMENT" || $0.title.localizedCaseInsensitiveContains("autoeval"))
        }
        for column in selfAssessmentColumns {
            guard let detail = try? await container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id),
                  !detail.items.isEmpty else { continue }
            let itemById = Dictionary(detail.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let columnDate = column.dateEpochMs.map { Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000) }
            if let columnDate, !inPeriod(columnDate) { continue }

            var entries: [Int64: BulletinBaseSelfAssessment] = [:]
            var anyResponseInPeriod = false
            for student in students {
                let responses = (try? await container.notebookInstrumentsRepository.listResponsesForCell(
                    classId: classId,
                    studentId: student.id,
                    columnId: column.id
                )) ?? []
                if columnDate == nil, !responses.contains(where: { inPeriod(date($0.trace.updatedAt)) }) {
                    entries[student.id] = BulletinBaseSelfAssessment(title: column.title, scaleAverage: nil, openAnswers: [])
                    continue
                }
                anyResponseInPeriod = anyResponseInPeriod || !responses.isEmpty
                let ordered = responses.sorted { (itemById[$0.itemId]?.order ?? 0) < (itemById[$1.itemId]?.order ?? 0) }
                let scaleValues = ordered.compactMap { response -> Double? in
                    guard itemById[response.itemId]?.type.name == "SCALE_1_4" else { return nil }
                    return response.numberValue?.doubleValue
                }
                let openAnswers = ordered.compactMap { response -> String? in
                    guard itemById[response.itemId]?.type.name == "TEXT" else { return nil }
                    let text = response.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return text.isEmpty ? nil : text
                }
                entries[student.id] = BulletinBaseSelfAssessment(
                    title: column.title,
                    scaleAverage: scaleValues.isEmpty ? nil : scaleValues.reduce(0, +) / Double(scaleValues.count),
                    openAnswers: openAnswers
                )
            }
            // Si nadie respondió en este periodo, el instrumento no es de este trimestre: no se lista.
            guard columnDate != nil || anyResponseInPeriod else { continue }
            usedSelfAssessmentIds.insert(column.id)
            for (studentId, entry) in entries {
                inputs[studentId]?.selfAssessments.append(entry)
            }
        }

        // Incidencias.
        let incidents = try await container.incidentsRepository.listIncidents(classId: classId)
        for incident in incidents {
            guard let studentId = incident.studentId?.int64Value, inputs[studentId] != nil else { continue }
            let incidentDate = date(incident.date)
            guard inPeriod(incidentDate) else { continue }
            let detail = incident.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = detail.isEmpty ? incident.title : "\(incident.title): \(detail)"
            inputs[studentId]?.observations.append(BulletinBaseObservation(date: incidentDate, text: text))
        }

        // Notas individuales del diario de aula (sin el nombre guardado en la nota).
        let sessions = try await container.plannerRepository.listAllSessions().filter { $0.groupId == classId }
        let sessionsInPeriod = sessions.filter { inPeriod(self.date(from: $0)) }
        if !sessionsInPeriod.isEmpty {
            let sessionDateById = Dictionary(
                sessionsInPeriod.map { ($0.id, self.date(from: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
            let sessionIds = sessionsInPeriod.map { KotlinLong(value: $0.id) }
            for student in students {
                let aggregates = (try? await container.sessionJournalRepository.listJournalsWithStudentNotes(
                    planningSessionIds: sessionIds,
                    studentId: student.id
                )) ?? []
                for aggregate in aggregates {
                    let journalDate = sessionDateById[aggregate.journal.planningSessionId] ?? period.start
                    for note in aggregate.individualNotes where note.studentId?.int64Value == student.id {
                        let text = note.note.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        let tag = note.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                        inputs[student.id]?.observations.append(
                            BulletinBaseObservation(date: journalDate, text: tag.isEmpty ? text : "\(tag): \(text)")
                        )
                    }
                }
            }
        }

        // Rúbricas y notas del Cuaderno: la misma evidencia que usa la IA del dispositivo.
        // Las incidencias ya se leen arriba y los acuerdos de tutoría no salen en el texto anónimo.
        let evidence = (try? await evidenceUseCase.invokeForClass(
            classId: classId,
            termKey: termKey,
            maxCriterionResults: 12,
            maxObservations: 10
        )) ?? []
        for item in evidence {
            let studentId = item.studentId
            let studentEvidence = item.evidence
            guard inputs[studentId] != nil else { continue }
            inputs[studentId]?.criterionLevels = studentEvidence.criterionResults.map {
                BulletinBaseCriterionLevel(
                    criterion: $0.criterion,
                    level: $0.levelName,
                    descriptor: $0.levelDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    ratio: $0.maxPoints > 0 ? Double($0.points) / Double($0.maxPoints) : nil
                )
            }
            for observation in studentEvidence.observations where observation.source == .notebook {
                inputs[studentId]?.observations.append(
                    BulletinBaseObservation(
                        date: date(epochMs: observation.dateEpochMs),
                        text: "\(observation.title): \(observation.text)"
                    )
                )
            }
        }

        // Sellos del Cuaderno en el periodo, con su recuento.
        let columnById = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cells = (try? await container.notebookCellsRepository.listClassCells(classId: classId)) ?? []
        var stampCounts: [Int64: [String: Int]] = [:]
        for cell in cells where inputs[cell.studentId] != nil {
            // El sello se guarda en el icono de la celda: al leer de la base de datos la anotación no lo trae.
            guard let icon = cell.annotation?.icon ?? cell.iconValue,
                  let stamp = NotebookCellStampCatalog.item(for: icon) else { continue }
            let epochMs = cell.observedAtEpochMs?.int64Value
                ?? columnById[cell.columnId]?.dateEpochMs?.int64Value
                ?? cell.trace.updatedAt.toEpochMilliseconds()
            guard inPeriod(date(epochMs: epochMs)) else { continue }
            stampCounts[cell.studentId, default: [:]][stamp.title, default: 0] += 1
        }
        for (studentId, counts) in stampCounts {
            inputs[studentId]?.stamps = counts.map { BulletinBaseStampCount(title: $0.key, count: $0.value) }
        }

        // «Tu valoración» del trimestre.
        let teacherNotes = (try? await teacherTermNotes(classId: classId, termLabel: termLabel)) ?? [:]
        for (studentId, note) in teacherNotes {
            inputs[studentId]?.teacherNote = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }

        return BulletinBaseReportBuilder.build(
            className: schoolClass.name,
            classId: classId,
            termLabel: termLabel,
            students: students.compactMap { inputs[$0.id] },
            evaluableColumnCount: usedColumnIds.count,
            selfAssessmentCount: usedSelfAssessmentIds.count
        )
    }
}
