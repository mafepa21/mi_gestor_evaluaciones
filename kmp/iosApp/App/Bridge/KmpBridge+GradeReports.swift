//
//  KmpBridge+GradeReports.swift
//  MiGestorKMP
//
//  Puente de «Enviar notas al alumnado»: arma el informe de cada alumno desde
//  el estado del Cuaderno ya cargado. Solo lee: no guarda ni cambia notas.
//

import Foundation
import MiGestorKit

@MainActor
extension KmpBridge {
    /// Construye los informes del grupo abierto con la Media de la pestaña activa.
    /// Si falla la lectura de rúbricas o criterios, el informe sale igual sin ese bloque.
    func buildStudentGradeReports(data: NotebookUiStateData) async -> [StudentGradeReport] {
        await buildStudentGradeReports(classId: data.sheet.classId, columns: data.sheet.columns, rows: data.sheet.rows)
    }

    /// Lo mismo desde columnas y filas sueltas (el portal «Mis notas» no abre el Cuaderno).
    /// Las filas ya traen la Media de la pestaña que toque. El PDF llega aquí por la otra sobrecarga.
    func buildStudentGradeReports(
        classId: Int64,
        columns: [NotebookColumnDefinition],
        rows: [NotebookRow]
    ) async -> [StudentGradeReport] {
        await Self.makeGradeReports(container: container, classId: classId, columns: columns, rows: rows)
    }

    /// Sin aislamiento de actor: se puede llamar fuera del hilo principal.
    nonisolated static func makeGradeReports(
        container: KmpContainer,
        classId: Int64,
        columns: [NotebookColumnDefinition],
        rows: [NotebookRow]
    ) async -> [StudentGradeReport] {
        let rubricColumns = columns.filter { $0.type == .rubric && $0.evaluationId != nil }

        var rubricsByColumn: [String: RubricDetail] = [:]
        var assessmentsByColumn: [String: [RubricAssessment]] = [:]
        if !rubricColumns.isEmpty {
            let evaluations = (try? await container.evaluationsRepository.listClassEvaluations(classId: classId)) ?? []
            let rubricIdByEvaluation = Dictionary(
                evaluations.compactMap { evaluation -> (Int64, Int64)? in
                    guard let rubricId = evaluation.rubricId?.int64Value else { return nil }
                    return (evaluation.id, rubricId)
                },
                uniquingKeysWith: { first, _ in first }
            )
            let rubrics = (try? await container.rubricsRepository.listRubrics()) ?? []
            let rubricsById = Dictionary(rubrics.map { ($0.rubric.id, $0) }, uniquingKeysWith: { first, _ in first })
            let studentIds = rows.map { KotlinLong(value: $0.student.id) }

            for column in rubricColumns {
                guard let evaluationId = column.evaluationId?.int64Value else { continue }
                let rubricId = column.rubricId?.int64Value ?? rubricIdByEvaluation[evaluationId]
                guard let rubricId, let rubric = rubricsById[rubricId] else { continue }
                rubricsByColumn[column.id] = rubric
                assessmentsByColumn[column.id] = (try? await container.rubricsRepository.listRubricAssessmentsForStudents(
                    studentIds: studentIds,
                    evaluationId: evaluationId
                )) ?? []
            }
        }

        return BuildStudentGradeReportsUseCase().build(
            columns: columns,
            rows: rows,
            rubricsByColumn: rubricsByColumn,
            assessmentsByColumn: assessmentsByColumn,
            criterionCodes: await gradeReportCriterionCodes(container: container)
        )
    }

    private nonisolated static func gradeReportCriterionCodes(container: KmpContainer) async -> [KotlinLong: String] {
        guard let criteria = try? await container.competenciesRepository.listCompetencies() else {
            return [:]
        }
        var codes: [KotlinLong: String] = [:]
        for criterion in criteria {
            codes[KotlinLong(value: criterion.id)] = criterion.code
        }
        return codes
    }
}
