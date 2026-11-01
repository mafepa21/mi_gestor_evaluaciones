//
//  KmpBridge+NotebookClosing.swift
//  MiGestorKMP
//
//  Puente de «Revisar cierre»: calcula el informe desde el estado del Cuaderno
//  ya cargado. Solo lee: no guarda ni cambia ninguna nota.
//

import Foundation
import MiGestorKit

@MainActor
extension KmpBridge {
    /// Construye el informe de cierre del grupo abierto en el Cuaderno.
    /// Se llama una vez al abrir la hoja. Si no se pueden leer los códigos de
    /// criterio, el informe sale igual con el texto de reserva «Criterio N».
    func buildNotebookClosingReport(data: NotebookUiStateData) async throws -> NotebookClosingReport {
        let codes = await notebookCriterionCodes()
        return BuildNotebookClosingReportUseCase().build(
            columns: data.sheet.columns,
            rows: data.sheet.rows,
            criterionCodes: codes
        )
    }

    private func notebookCriterionCodes() async -> [KotlinLong: String] {
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
