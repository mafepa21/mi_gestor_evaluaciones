import Foundation
import MiGestorKit

struct PhysicalTestsColumnCreationPolicy {
    @MainActor
    static func createNotebookColumns(
        bridge: KmpBridge,
        battery: PhysicalTestBattery,
        assignment: PhysicalTestAssignment,
        selectedAssignmentNotebookTabId: String?,
        scoreCountsTowardAverage: Bool
    ) async throws {
        let selectedClassId = assignment.classId
        bridge.selectClass(id: selectedClassId)
        guard let selectedAssignmentNotebookTabId else {
            throw NSError(domain: "PhysicalTestsColumnCreationPolicy", code: 422, userInfo: [NSLocalizedDescriptionKey: "Selecciona una pestaña del cuaderno para crear las columnas."])
        }
        bridge.setSelectedNotebookTab(id: selectedAssignmentNotebookTabId)
        let selectedTemplates = PhysicalTestTemplate.defaults.filter { battery.testIds.contains($0.id) }
        let categoryId = assignment.id
        bridge.saveColumnCategory(name: "\(battery.name) · \(assignment.termLabel ?? "Evaluación física")", categoryId: categoryId)
        
        let persistedLinks = (try? await bridge.listPhysicalNotebookLinksForAssignment(assignmentId: assignment.id)) ?? []

        for template in selectedTemplates {
            let existingLink = persistedLinks.first { $0.testId == template.id }
            var rawColumnId = existingLink?.rawColumnId
            var scoreColumnId = existingLink?.scoreColumnId
            
            if assignment.rawColumnMode && rawColumnId == nil {
                let title = rawColumnTitle(for: template)
                if let existingColumnId = existingNotebookPhysicalColumnId(bridge: bridge, title: title, categoryId: categoryId) {
                    rawColumnId = existingColumnId
                } else {
                    rawColumnId = try await bridge.createNotebookPhysicalColumnForClass(
                        classId: selectedClassId,
                        name: title,
                        categoryId: categoryId,
                        inputKind: template.measurement.inputKind,
                        unitOrSituation: rawColumnContext(for: template),
                        scaleKind: template.measurement.scaleKind,
                        iconName: "stopwatch.fill",
                        weight: 0,
                        countsTowardAverage: false,
                        dateEpochMs: assignment.dateEpochMs
                    )
                }
            }

            if assignment.scoreColumnMode && scoreColumnId == nil {
                let title = scoreColumnTitle(for: template)
                if let existingColumnId = existingNotebookPhysicalColumnId(bridge: bridge, title: title, categoryId: categoryId) {
                    scoreColumnId = existingColumnId
                } else {
                    scoreColumnId = try await bridge.createNotebookPhysicalColumnForClass(
                        classId: selectedClassId,
                        name: title,
                        categoryId: categoryId,
                        inputKind: .numeric010,
                        unitOrSituation: "Nota baremada",
                        scaleKind: .tenPoint,
                        iconName: "chart.bar.fill",
                        weight: 10,
                        countsTowardAverage: scoreCountsTowardAverage,
                        dateEpochMs: assignment.dateEpochMs
                    )
                }
            }
            
            if existingLink?.rawColumnId != rawColumnId || existingLink?.scoreColumnId != scoreColumnId {
                try await bridge.savePhysicalNotebookLink(
                    PhysicalTestNotebookLink(
                        assignmentId: assignment.id,
                        testId: template.id,
                        rawColumnId: rawColumnId,
                        scoreColumnId: scoreColumnId,
                        trace: auditTrace(classId: selectedClassId)
                    )
                )
            }
        }
    }

    static func rawColumnTitle(for template: PhysicalTestTemplate) -> String {
        "\(template.name) · \(rawColumnLabel(for: template))"
    }

    static func scoreColumnTitle(for template: PhysicalTestTemplate) -> String {
        "\(template.name) · Nota"
    }

    static func rawColumnContext(for template: PhysicalTestTemplate) -> String {
        "Dato bruto · \(template.unit)"
    }

    private static func rawColumnLabel(for template: PhysicalTestTemplate) -> String {
        switch template.measurement {
        case .level:
            return "Nivel"
        default:
            return "Marca"
        }
    }
    
    @MainActor
    private static func existingNotebookPhysicalColumnId(bridge: KmpBridge, title: String, categoryId: String) -> String? {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return nil }
        return data.sheet.columns.first { column in
            column.title == title &&
            column.categoryId == categoryId &&
            column.instrumentKind == .physicalTest
        }?.id
    }
    
    private static func auditTrace(classId: Int64) -> AuditTrace {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: KotlinLong(value: classId), deviceId: nil, syncVersion: 0)
    }
}
