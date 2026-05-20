import SwiftUI
import MiGestorKit

struct TeacherRadarInsightDraft: Identifiable, Hashable {
    enum Priority: String, CaseIterable {
        case high
        case medium
        case low
        case positive

        var title: String {
            switch self {
            case .high: return "Alta"
            case .medium: return "Media"
            case .low: return "Baja"
            case .positive: return "Reconocimiento"
            }
        }

        var tint: Color {
            switch self {
            case .high: return .red
            case .medium: return NotebookStyle.warningTint
            case .low: return .secondary
            case .positive: return NotebookStyle.successTint
            }
        }

        var systemImage: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "clock.badge.exclamationmark.fill"
            case .low: return "info.circle.fill"
            case .positive: return "sparkles"
            }
        }
    }

    let id: String
    let title: String
    let detail: String
    let priority: Priority
    let studentId: Int64?
    let classId: Int64?
    let suggestedAction: String
    let evidence: [String]
}

struct TeacherRadarStudentSnapshot: Identifiable, Hashable {
    let id: Int64
    let name: String
    let average: Double?
    let previousAverage: Double?
    let attendanceRate: Int?
    let evidenceCount: Int
    let missingRubricCount: Int
    let pendingCount: Int
    let isInjured: Bool
    let suggestedAction: String
    let risk: TeacherRadarInsightDraft.Priority
}

struct TeacherRadarGroupSummary: Hashable {
    let classId: Int64
    let className: String
    let studentCount: Int
    let rubricCompletionRate: Int
    let missingRubricStudentCount: Int
    let fallingPerformanceCount: Int
    let injuredCount: Int
    let suggestedAction: String
}

struct TeacherRadarSnapshot {
    let className: String
    let insights: [TeacherRadarInsightDraft]
    let students: [TeacherRadarStudentSnapshot]
    let groupSummary: TeacherRadarGroupSummary

    var highPriorityCount: Int { insights.filter { $0.priority == .high }.count }
    var mediumPriorityCount: Int { insights.filter { $0.priority == .medium }.count }
    var positiveCount: Int { insights.filter { $0.priority == .positive }.count }
    var actionInsights: [TeacherRadarInsightDraft] { Array(insights.filter { $0.priority != .positive }.prefix(5)) }
}

enum TeacherRadarBuilder {
    static func build(data: NotebookUiStateData, className: String) -> TeacherRadarSnapshot {
        let rows = data.sheet.rows.map { row in NotebookTableRow(student: row.student, row: row, groupName: "") }
        let columns = data.sheet.columns.filter { !$0.isHidden }
        let rubricColumns = columns.filter { $0.type == .rubric || $0.rubricId != nil }
        let requiredColumns = columns.filter { $0.type == .rubric || $0.rubricId != nil || $0.countsTowardAverage }
        let classId = data.sheet.classId
        var insights: [TeacherRadarInsightDraft] = []
        var studentSnapshots: [TeacherRadarStudentSnapshot] = []

        for item in rows {
            let average = item.row.weightedAverage?.doubleValue
            let previousAverage = previousAverageEstimate(for: item, columns: columns)
            let attendanceRate = attendanceRateEstimate(for: item)
            let evidenceCount = evidenceCount(for: item)
            let missingRubrics = missingRubricCount(for: item, rubricColumns: rubricColumns)
            let pending = pendingRequiredCount(for: item, requiredColumns: requiredColumns)
            let falling = average.map { current in previousAverage.map { current + 0.5 < $0 } ?? false } ?? false
            let improved = average.map { current in previousAverage.map { current - $0 > 1.0 } ?? false } ?? false
            let studentName = "\(item.student.firstName) \(item.student.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)

            if let average, average < 5, let attendanceRate, attendanceRate < 80 {
                insights.append(.init(
                    id: "student-\(item.student.id)-high-risk",
                    title: "\(studentName): media < 5 y asistencia < 80%",
                    detail: "Concurren rendimiento bajo y asistencia baja.",
                    priority: .high,
                    studentId: item.student.id,
                    classId: classId,
                    suggestedAction: "Revisar hoy una evidencia concreta y acordar seguimiento.",
                    evidence: ["Media: \(IosFormatting.decimal(from: average)).", "Asistencia estimada: \(attendanceRate)%."]
                ))
            } else if (average.map { (5.0...6.0).contains($0) } ?? false) || falling || pending > 0 {
                insights.append(.init(
                    id: "student-\(item.student.id)-medium-risk",
                    title: "\(studentName): seguimiento necesario",
                    detail: falling ? "La tendencia estimada desciende respecto a evidencias anteriores." : "Hay rendimiento frágil o tareas pendientes.",
                    priority: .medium,
                    studentId: item.student.id,
                    classId: classId,
                    suggestedAction: "Observar un criterio específico en la próxima sesión.",
                    evidence: [
                        average.map { "Media: \(IosFormatting.decimal(from: $0))." } ?? "Sin media consolidada.",
                        "Pendientes: \(pending)."
                    ]
                ))
            }

            if evidenceCount < 3 {
                insights.append(.init(
                    id: "student-\(item.student.id)-evidence-gap",
                    title: "\(studentName): \(3 - evidenceCount) evidencias por revisar",
                    detail: "El cuaderno tiene menos de 3 evidencias asociadas para este alumno.",
                    priority: evidenceCount == 0 ? .high : .medium,
                    studentId: item.student.id,
                    classId: classId,
                    suggestedAction: "Registrar una evidencia observable durante la sesión.",
                    evidence: ["Evidencias actuales: \(evidenceCount)/3."]
                ))
            }

            if missingRubrics > 0 {
                insights.append(.init(
                    id: "student-\(item.student.id)-rubric-gap",
                    title: "\(studentName): rúbrica incompleta",
                    detail: "Quedan criterios de rúbrica sin completar.",
                    priority: .medium,
                    studentId: item.student.id,
                    classId: classId,
                    suggestedAction: "Completar la rúbrica pendiente antes del próximo corte.",
                    evidence: ["Rúbricas pendientes: \(missingRubrics)."]
                ))
            }

            if improved && (attendanceRate ?? 100) >= 90 {
                insights.append(.init(
                    id: "student-\(item.student.id)-positive",
                    title: "\(studentName): progreso destacable",
                    detail: "La mejora supera 1 punto respecto a la estimación anterior.",
                    priority: .positive,
                    studentId: item.student.id,
                    classId: classId,
                    suggestedAction: "Dar feedback positivo y mantener el seguimiento.",
                    evidence: ["Media: \(IosFormatting.decimal(from: previousAverage ?? 0)) -> \(IosFormatting.decimal(from: average ?? 0))."]
                ))
            }

            let risk: TeacherRadarInsightDraft.Priority = {
                if average.map({ $0 < 5 }) == true || evidenceCount == 0 { return .high }
                if missingRubrics > 0 || pending > 0 || falling { return .medium }
                if improved { return .positive }
                return .low
            }()

            studentSnapshots.append(.init(
                id: item.student.id,
                name: studentName,
                average: average,
                previousAverage: previousAverage,
                attendanceRate: attendanceRate,
                evidenceCount: evidenceCount,
                missingRubricCount: missingRubrics,
                pendingCount: pending,
                isInjured: item.student.isInjured,
                suggestedAction: suggestedStudentAction(risk: risk, missingRubrics: missingRubrics, evidenceCount: evidenceCount),
                risk: risk
            ))
        }

        let missingRubricStudents = studentSnapshots.filter { $0.missingRubricCount > 0 }.count
        let fallingCount = studentSnapshots.filter { snapshot in
            guard let current = snapshot.average, let previous = snapshot.previousAverage else { return false }
            return current + 0.5 < previous
        }.count
        let injuredCount = studentSnapshots.filter(\.isInjured).count
        let totalRubricCells = max(1, rubricColumns.count * max(1, rows.count))
        let missingRubricCells = studentSnapshots.map(\.missingRubricCount).reduce(0, +)
        let completion = Int(((Double(totalRubricCells - missingRubricCells) / Double(totalRubricCells)) * 100).rounded())
        if missingRubricStudents > 0 {
            insights.append(.init(
                id: "class-\(classId)-rubrics",
                title: "\(className): rúbricas incompletas en \(missingRubricStudents) alumnos",
                detail: "La cobertura de rúbricas no está completa.",
                priority: .high,
                studentId: nil,
                classId: classId,
                suggestedAction: "Planificar una sesión con observación específica de los criterios pendientes.",
                evidence: ["Completado: \(completion)%."]
            ))
        }

        let summary = TeacherRadarGroupSummary(
            classId: classId,
            className: className,
            studentCount: rows.count,
            rubricCompletionRate: completion,
            missingRubricStudentCount: missingRubricStudents,
            fallingPerformanceCount: fallingCount,
            injuredCount: injuredCount,
            suggestedAction: missingRubricStudents > 0
                ? "Planificar observación específica de rúbricas pendientes."
                : "Mantener recogida de evidencias y revisar reconocimientos positivos."
        )

        return TeacherRadarSnapshot(
            className: className,
            insights: insights.sorted { lhs, rhs in
                priorityRank(lhs.priority) == priorityRank(rhs.priority)
                    ? lhs.title < rhs.title
                    : priorityRank(lhs.priority) < priorityRank(rhs.priority)
            },
            students: studentSnapshots.sorted { priorityRank($0.risk) < priorityRank($1.risk) },
            groupSummary: summary
        )
    }

    private static func priorityRank(_ priority: TeacherRadarInsightDraft.Priority) -> Int {
        switch priority {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .positive: return 3
        }
    }

    private static func evidenceCount(for item: NotebookTableRow) -> Int {
        item.row.persistedGrades.filter { !($0.evidence ?? "").isEmpty || !($0.evidencePath ?? "").isEmpty }.count +
            item.row.persistedCells.map { $0.annotation?.attachmentUris.count ?? 0 }.reduce(0, +)
    }

    private static func attendanceRateEstimate(for item: NotebookTableRow) -> Int? {
        let cells = item.row.persistedCells.compactMap { $0.textValue ?? $0.displayValue }
        let attendanceValues = cells.map { NotebookAttendanceStatus.canonical($0) }.filter { !$0.isEmpty }
        guard !attendanceValues.isEmpty else { return nil }
        let present = attendanceValues.filter { $0 == NotebookAttendanceStatus.present || $0 == NotebookAttendanceStatus.justified }.count
        return Int((Double(present) / Double(attendanceValues.count) * 100).rounded())
    }

    private static func missingRubricCount(for item: NotebookTableRow, rubricColumns: [NotebookColumnDefinition]) -> Int {
        rubricColumns.filter { column in
            let grade = item.row.persistedGrades.first { $0.columnId == column.id || $0.evaluationId?.int64Value == column.evaluationId?.int64Value }
            return (grade?.rubricSelections ?? "").isEmpty && grade?.value == nil
        }.count
    }

    private static func pendingRequiredCount(for item: NotebookTableRow, requiredColumns: [NotebookColumnDefinition]) -> Int {
        requiredColumns.filter { column in
            let grade = item.row.persistedGrades.first { $0.columnId == column.id || $0.evaluationId?.int64Value == column.evaluationId?.int64Value }
            let cell = item.row.persistedCells.first { $0.columnId == column.id }
            let hasGrade = grade?.value != nil || !(grade?.rubricSelections ?? "").isEmpty
            let hasCell = !((cell?.displayValue ?? cell?.textValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            return !hasGrade && !hasCell
        }.count
    }

    private static func previousAverageEstimate(for item: NotebookTableRow, columns: [NotebookColumnDefinition]) -> Double? {
        let datedValues = item.row.persistedGrades.compactMap { grade -> (Int64, Double)? in
            guard let value = grade.value?.doubleValue else { return nil }
            let date = columns.first(where: { $0.id == grade.columnId || $0.evaluationId?.int64Value == grade.evaluationId?.int64Value })?.dateEpochMs?.int64Value ?? 0
            return (date, value)
        }.sorted { $0.0 < $1.0 }
        guard datedValues.count >= 2 else { return nil }
        let previousValues = datedValues.dropLast()
        return previousValues.map(\.1).reduce(0, +) / Double(previousValues.count)
    }

    private static func suggestedStudentAction(risk: TeacherRadarInsightDraft.Priority, missingRubrics: Int, evidenceCount: Int) -> String {
        if risk == .positive { return "Dar feedback positivo y mantener seguimiento." }
        if missingRubrics > 0 { return "Completar rúbrica pendiente con observación específica." }
        if evidenceCount < 3 { return "Recoger una evidencia observable en la próxima sesión." }
        if risk == .high { return "Revisar asistencia, media y evidencias hoy." }
        return "Mantener seguimiento ordinario."
    }
}

struct TeacherRadarCard: View {
    let snapshot: TeacherRadarSnapshot
    let onOpenDetail: () -> Void

    var body: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        NotebookSectionLabel(text: "Radar de hoy")
                        Text(snapshot.className)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                    }
                    Spacer()
                    Button(action: onOpenDetail) {
                        Image(systemName: "arrow.up.right")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .help("Abrir detalle del Radar")
                }

                HStack(spacing: 10) {
                    radarMetric("Alta", "\(snapshot.highPriorityCount)", .red)
                    radarMetric("Media", "\(snapshot.mediumPriorityCount)", NotebookStyle.warningTint)
                    radarMetric("Recon.", "\(snapshot.positiveCount)", NotebookStyle.successTint)
                }

                VStack(spacing: 8) {
                    ForEach(Array(snapshot.insights.prefix(4))) { insight in
                        TeacherRadarStudentInsightRow(insight: insight)
                    }
                }
            }
        }
    }

    private func radarMetric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
