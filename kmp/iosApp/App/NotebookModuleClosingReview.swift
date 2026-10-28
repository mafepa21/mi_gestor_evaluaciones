import SwiftUI
import MiGestorKit

/// Apertura de «Revisar cierre» y salto desde un aviso hasta su celda.
/// La hoja solo lee; este archivo solo mueve el foco del grid, no cambia notas.
extension NotebookModuleView {
    func closingReviewContextText(data: NotebookUiStateData) -> String {
        let name = currentClass?.name ?? "Grupo"
        let count = data.sheet.rows.count
        return "\(name) · \(count == 1 ? "1 alumno" : "\(count) alumnos")"
    }

    /// Se llama al cerrarse la hoja: así el grid ya es visible y está medido.
    func goToPendingClosingTarget() {
        guard let target = pendingClosingTarget else { return }
        pendingClosingTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            switch target {
            case .hiddenColumns:
                isHiddenColumnsSheetPresented = true
            case .row(let studentId):
                focusClosingCell(studentId: studentId, columnId: nil, allowsTabSwitch: true)
            case .cell(let studentId, let columnId):
                focusClosingCell(studentId: studentId, columnId: columnId, allowsTabSwitch: true)
            }
        }
    }

    /// Lleva el grid a la celda (alumno + columna). Si no hay columna, a la fila del alumno
    /// (primera celda navegable). El grid no tiene desplazamiento horizontal programable,
    /// así que solo se garantiza el desplazamiento vertical a la fila.
    func focusClosingCell(studentId: Int64, columnId: String?, allowsTabSwitch: Bool) {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return }
        let column = columnId.flatMap { id in data.sheet.columns.first(where: { $0.id == id }) }
        if let column, column.isTemporarilyHidden {
            isHiddenColumnsSheetPresented = true
            return
        }

        let rows = filteredRows(data: data)
        guard let rowIndex = rows.firstIndex(where: { $0.student.id == studentId }) else {
            showToast("Ese alumno no se ve con la búsqueda o el filtro actual", style: .warning)
            return
        }

        let columns = navigableColumns(
            in: displaySegments(data: data).filter { !isFixedSegment($0) }
        )
        var target = column.flatMap { wanted in columns.first(where: { $0.id == wanted.id }) }

        // La columna puede estar en otra pestaña: se cambia de pestaña una sola vez.
        if column != nil, target == nil, allowsTabSwitch,
           let tabId = column?.tabIds.first {
            bridge.setSelectedNotebookTab(id: tabId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                focusClosingCell(studentId: studentId, columnId: columnId, allowsTabSwitch: false)
            }
            return
        }
        if column != nil, target == nil {
            showToast("La columna no está en esta vista", style: .warning)
        }
        if target == nil { target = columns.first }
        guard let target else { return }

        // Con la virtualización de filas hay que desplazar antes de enfocar.
        gridScrollProxy.scrollToRow?(rowIndex)

        #if os(macOS)
        applyKeyboardSelection(studentId: studentId, columnId: target.id)
        #else
        inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: target.id)
        focusedCellId = nil
        activeChoiceCellId = nil
        if column != nil, notebookClosingColumnAcceptsTyping(target) {
            let cellId = cellFocusId(studentId: studentId, columnId: target.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedCellId = cellId
            }
        }
        #endif

        let studentName = rows[rowIndex].student.fullName
        AccessibilityNotification.Announcement("Celda de \(studentName) en \(target.title)").post()
    }

    /// Mismas reglas que `navigateCell`: solo las celdas de escritura directa reciben el foco de teclado.
    private func notebookClosingColumnAcceptsTyping(_ column: NotebookColumnDefinition) -> Bool {
        if column.type == .ordinal || column.type == .attendance || column.categoryKind == .attendance {
            return false
        }
        return column.type != .calculated && column.type != .rubric && column.type != .check
    }
}
