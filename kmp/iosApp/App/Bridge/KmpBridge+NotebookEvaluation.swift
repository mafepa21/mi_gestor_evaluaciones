import Foundation
import MiGestorKit

// Pestaña de evaluación: crear evaluaciones, meter o sacar bloques y guardar pesos.
// Solo cambia pestañas (padre y peso); las notas y columnas no se tocan.
extension KmpBridge {
    private func nowTrace(from trace: AuditTrace? = nil) -> AuditTrace {
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
        return AuditTrace(
            authorUserId: trace?.authorUserId,
            createdAt: trace?.createdAt ?? now,
            updatedAt: now,
            associatedGroupId: trace?.associatedGroupId,
            deviceId: nil,
            syncVersion: trace?.syncVersion ?? 0
        )
    }

    private var currentTabs: [NotebookTab] {
        (notebookState as? NotebookUiStateData)?.sheet.tabs ?? []
    }

    /// Id de la evaluación elegida; si es nueva, la crea como pestaña raíz.
    func resolveEvaluationTab(_ placement: NotebookEvaluationPlacement) -> String? {
        switch placement {
        case .loose:
            return nil
        case .existing(let id):
            return id
        case .new(let title):
            if let existing = currentTabs.first(where: { $0.parentTabId == nil && $0.title == title }) {
                return existing.id
            }
            return createTab(title: title)
        }
    }

    /// Crea una pestaña dentro de una evaluación (o suelta) y devuelve su id.
    func createNotebookTab(title: String, placement: NotebookEvaluationPlacement, weight: Double?) -> String? {
        let parentId = resolveEvaluationTab(placement)
        return createTab(title: title, parentTabId: parentId, weight: parentId == nil ? nil : weight)
    }

    /// Mete o saca pestañas de sus evaluaciones. Al salir pierden el peso de bloque.
    func placeNotebookTabs(_ placements: [String: NotebookEvaluationPlacement]) {
        var resolved: [NotebookEvaluationPlacement: String?] = [:]
        for (tabId, placement) in placements {
            guard let tab = currentTabs.first(where: { $0.id == tabId }) else { continue }
            let parentId: String?
            if let cached = resolved[placement] {
                parentId = cached
            } else {
                parentId = resolveEvaluationTab(placement)
                resolved[placement] = parentId
            }
            guard parentId != tab.id else { continue }
            saveTab(tab: NotebookTab(
                id: tab.id,
                title: tab.title,
                description: tab.description,
                order: -1,
                parentTabId: parentId,
                fixedColumnWidth: tab.fixedColumnWidth,
                trace: nowTrace(from: tab.trace),
                weight: parentId == nil ? nil : tab.weight
            ))
        }
    }

    /// Guarda el peso de cada bloque (porcentajes; se reparten en proporción al calcular).
    func saveEvaluationBlockWeights(_ weights: [String: Double]) {
        for (tabId, weight) in weights {
            guard let tab = currentTabs.first(where: { $0.id == tabId }),
                  tab.weight?.doubleValue != weight else { continue }
            saveTab(tab: NotebookTab(
                id: tab.id,
                title: tab.title,
                description: tab.description,
                order: tab.order,
                parentTabId: tab.parentTabId,
                fixedColumnWidth: tab.fixedColumnWidth,
                trace: nowTrace(from: tab.trace),
                weight: KotlinDouble(value: weight)
            ))
        }
    }
}
