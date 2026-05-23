import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func headerChip(
        title: String,
        subtitle: String,
        width: CGFloat,
        tint: Color,
        typeBadge: String? = nil,
        isSystemColumn: Bool = false,
        folderStyle: Bool = false,
        hasColumnColor: Bool = false,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(isSystemColumn ? .medium : .semibold))
                .foregroundStyle(isSystemColumn ? .secondary : .primary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: width)
        .frame(minHeight: 52, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(headerChipFill(tint: tint, folderStyle: folderStyle, hasColumnColor: hasColumnColor, isSystemColumn: isSystemColumn))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            headerChipStroke(tint: tint, folderStyle: folderStyle, hasColumnColor: hasColumnColor, isSystemColumn: isSystemColumn, isHighlighted: isHighlighted),
                            lineWidth: isHighlighted ? 1.4 : 0.6
                        )
                )
        )
        .overlay(alignment: .topLeading) {
            if !isSystemColumn {
                Capsule()
                    .fill(tint.opacity(hasColumnColor || folderStyle ? 0.65 : 0.28))
                    .frame(width: 42, height: 3)
                    .padding(.leading, 8)
                    .padding(.top, 6)
            }
        }
    }

    func headerChipFill(tint: Color, folderStyle: Bool, hasColumnColor: Bool, isSystemColumn: Bool) -> Color {
        if isSystemColumn { return NotebookStyle.surfaceSoft.opacity(0.50) }
        if hasColumnColor { return tint.opacity(0.055) }
        if folderStyle { return NotebookStyle.surfaceSoft.opacity(0.28) }
        return NotebookStyle.surfaceSoft.opacity(0.20)
    }

    func headerChipStroke(tint: Color, folderStyle: Bool, hasColumnColor: Bool, isSystemColumn: Bool, isHighlighted: Bool) -> Color {
        if isHighlighted { return tint.opacity(0.34) }
        if hasColumnColor { return tint.opacity(0.16) }
        if isSystemColumn { return NotebookStyle.softBorder.opacity(0.55) }
        if folderStyle { return tint.opacity(0.10) }
        return NotebookStyle.softBorder.opacity(0.35)
    }

    func headerChip(for segment: NotebookDisplaySegment, data: NotebookUiStateData) -> some View {
        switch segment {
        case .fixed(let fixed):
            let chip = headerChip(
                title: fixed.title,
                subtitle: fixed.subtitle,
                width: resolvedFixedWidth(for: fixed),
                tint: tint(for: fixed),
                isSystemColumn: true
            )
            if fixed == .average {
                return AnyView(
                    Button {
                        isAverageConfigurationPresented = true
                    } label: {
                        chip
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Configurar media")
                )
            }
            return AnyView(chip)
        case .column(let column):
            return AnyView(
                NotebookResizableHeader(
                    width: resolvedColumnWidth(for: column),
                    minWidth: 80,
                    maxWidth: 400
                ) { newWidth in
                    updateColumnWidth(column, width: newWidth)
                } content: {
                    headerChip(
                        title: column.title,
                        subtitle: columnHeaderMeta(for: column),
                        width: resolvedColumnWidth(for: column),
                        tint: displayTint(for: column),
                        folderStyle: column.categoryId != nil,
                        hasColumnColor: hasCustomColumnColor(column),
                        isHighlighted: highlightedColumnId == column.id || highlightedCategoryId == column.categoryId
                    )
                }
                .contextMenu {
                    columnContextMenu(column, data: data)
                }
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        setCategoryCollapsed(category, collapsed: false)
                    }
                } label: {
                    collapsedCategoryHeader(
                        category: category,
                        columns: columns,
                        width: segmentWidth(segment)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
            )
        }
    }

    func collapsedCategoryHeader(
        category: NotebookColumnCategory,
        columns: [NotebookColumnDefinition],
        width: CGFloat
    ) -> some View {
        let categoryTint = tint(for: category)
        let isEmpty = categoryVisibleColumnCount(columns) == 0 && categoryHiddenColumnCount(columns) == 0
        let statusText = isEmpty ? "Vacía" : categoryColumnCountText(columns)
        let countText = categoryColumnCountText(columns)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: isEmpty ? "folder" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(categoryTint)
                    .accessibilityHidden(true)

                Text(category.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                Text(countText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(categoryTint)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(isEmpty ? "vacía" : "colapsada")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isEmpty ? Color.secondary.opacity(0.65) : categoryTint.opacity(0.9))
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: width, height: 52, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NotebookStyle.surfaceSoft.opacity(isEmpty ? 0.22 : 0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEmpty ? NotebookStyle.softBorder.opacity(0.55) : categoryTint.opacity(0.24), lineWidth: 1)
        )
        .help("\(categoryAccessibilityState(isCollapsed: true, columns: columns)). Haz clic para abrir.")
        .accessibilityLabel("\(category.name). \(categoryAccessibilityState(isCollapsed: true, columns: columns)). Haz clic para abrir.")
    }

    func tint(for fixed: NotebookFixedColumn) -> Color {
        switch fixed {
        case .photo, .name, .group:
            return .secondary
        case .followUp:
            return NotebookStyle.successTint
        case .attendance:
            return NotebookStyle.warningTint
        case .average:
            return NotebookStyle.primaryTint
        }
    }

    func typeBadge(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric:
            return column.evaluationId == nil ? "NT" : "EV"
        case .rubric:
            return "RB"
        case .calculated:
            return "CF"
        case .attendance:
            return "AS"
        case .text:
            return isNotebookAICommentColumn(column) ? "AI" : "TX"
        case .check:
            return "OK"
        case .ordinal:
            return "OR"
        case .icon:
            return "IC"
        default:
            return "CL"
        }
    }

    func columnHeaderMeta(for column: NotebookColumnDefinition) -> String {
        let typeText: String
        switch column.type {
        case .numeric:
            if column.instrumentKind == .physicalTest {
                switch column.scaleKind {
                case .time:
                    typeText = "Tiempo"
                case .distance:
                    typeText = "Distancia"
                case .repetitions:
                    typeText = "Repeticiones"
                case .tenPoint:
                    typeText = "Nota baremada"
                default:
                    typeText = "Nota"
                }
            } else {
                typeText = "Nota"
            }
        case .rubric:
            typeText = "Rúbrica"
        case .check:
            typeText = "Lista"
        case .ordinal:
            typeText = "Nivel"
        case .text:
            typeText = "Texto"
        case .calculated:
            typeText = "Fórmula"
        default:
            typeText = "Columna"
        }

        return typeText
    }

    func displayTint(for column: NotebookColumnDefinition) -> Color {
        hasCustomColumnColor(column) ? Color(hex: column.colorHex ?? "") : tint(for: column)
    }

    func hasCustomColumnColor(_ column: NotebookColumnDefinition) -> Bool {
        guard let rawHex = column.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHex.isEmpty else {
            return false
        }
        let normalized = rawHex.replacingOccurrences(of: "#", with: "").uppercased()
        return normalized != "FFFFFF" && normalized != "FFFFFFFF"
    }

    func notebookColumnCellFill(for column: NotebookColumnDefinition, rowIndex: Int, isActive: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.10)
        }
        if hasCustomColumnColor(column) {
            return displayTint(for: column).opacity(0.035)
        }
        return rowIndex.isMultiple(of: 2) ? NotebookStyle.surfaceSoft.opacity(0.18) : Color.clear
    }

    func notebookColumnCellBorder(for column: NotebookColumnDefinition, isActive: Bool) -> Color {
        if isActive { return Color.accentColor.opacity(0.75) }
        if hasCustomColumnColor(column) { return displayTint(for: column).opacity(0.10) }
        return NotebookStyle.softBorder.opacity(0.26)
    }

    func rowCell(
        for segment: NotebookDisplaySegment,
        item: NotebookTableRow,
        data: NotebookUiStateData,
        rowIndex: Int,
        allRows: [NotebookTableRow],
        navigableSegments: [NotebookDisplaySegment]
    ) -> some View {
        switch segment {
        case .fixed(let fixed):
            return AnyView(fixedRowCell(for: fixed, item: item, data: data))
        case .column(let column):
            let isCellSelected = inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
            return AnyView(
                ZStack {
                    Rectangle()
                        .fill(notebookColumnCellFill(for: column, rowIndex: rowIndex, isActive: isCellSelected))

                    NotebookEditableTableCell(
                        bridge: bridge,
                        item: item,
                        column: column,
                        classId: data.sheet.classId,
                        width: resolvedColumnWidth(for: column),
                        tint: displayTint(for: column),
                        categoryTint: column.categoryId.flatMap { id in
                            data.sheet.columnCategories.first(where: { $0.id == id }).map { tint(for: $0) }
                        },
                        hasColumnColor: hasCustomColumnColor(column),
                        focusedCellId: $focusedCellId,
                        activeChoiceCellId: $activeChoiceCellId,
                        navigationDirection: navigationDirection,
                        formulaDisplay: formulaDisplay(for: item, column: column, data: data),
                        isSelected: isCellSelected,
                        isAttendanceQuickMode: isAttendanceQuickMode,
                        reloadToken: cellReloadRevision,
                        onSelect: {
                            inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                            if focusedCellId == nil && activeChoiceCellId == nil && !isInspectorPresented {
                                focusMode = .normal
                            }
                        },
                        onPrepareUndo: { previousValue, previousDisplayLabel in
                            recordCellUndo(
                                studentId: item.student.id,
                                column: column,
                                previousValue: previousValue,
                                previousDisplayLabel: previousDisplayLabel
                            )
                        },
                        onOpenFormula: {
                            focusMode = .editing
                            presentFormulaEditor(for: column)
                        },
                        onOpenRubricIndividual: {
                            focusMode = .editing
                            openRubricIndividual(column: column, item: item)
                        },
                        onOpenRubricBulk: {
                            focusMode = .editing
                            openRubricBulk(column: column, data: data)
                        },
                        onGenerateSummary: {
                            inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                            focusMode = .reviewing
                            notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: column.id)
                        },
                        onNavigate: { direction in
                            navigateCell(
                                from: item.student.id,
                                column: column,
                                direction: direction,
                                rows: allRows,
                                segments: navigableSegments
                            )
                        },
                        onCellSaved: {
                            cellReloadRevision += 1
                        },
                        onAttendanceSaved: {
                            Task { await refreshNotebookSignals() }
                        }
                    )
                }
                .frame(width: resolvedColumnWidth(for: column), height: notebookGridRowHeight)
                .overlay(
                    Rectangle()
                        .stroke(notebookColumnCellBorder(for: column, isActive: isCellSelected), lineWidth: isCellSelected ? 1.4 : 0.5)
                )
                .contextMenu {
                    Button("Abrir inspector") {
                        inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                        isInspectorPresented = true
                        focusMode = .reviewing
                    }

                    if column.type == .calculated {
                        Button("Editar fórmula…") {
                            focusMode = .editing
                            presentFormulaEditor(for: column)
                        }
                    }

                    if column.type == .rubric {
                        Button("Evaluar alumno…") {
                            focusMode = .editing
                            openRubricIndividual(column: column, item: item)
                        }
                        Button("Evaluar grupo…") {
                            focusMode = .editing
                            openRubricBulk(column: column, data: data)
                        }
                    }

                    if isNotebookIndividualSummaryColumn(column) {
                        Button(summaryActionTitle(for: column, data: data)) {
                            inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                            focusMode = .reviewing
                            notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: column.id)
                        }
                    }
                }
            )
        case .collapsedCategory(let category, let columns):
            let visibleColumns = columns.filter(\.isVisibleInGrid)
            let filled = filledCellCount(item, columns: visibleColumns)
            let total = visibleColumns.count
            let categoryTint = tint(for: category)

            return AnyView(
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        setCategoryCollapsed(category, collapsed: false)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(categoryTint.opacity(0.82))
                            .accessibilityHidden(true)

                        Text(total == 0 ? "Vacía" : "\(filled)/\(total)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(total == 0 ? .secondary : .primary)
                            .monospacedDigit()
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                        .padding(.horizontal, 12)
                        .frame(width: segmentWidth(segment), height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(categoryTint.opacity(0.055))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(categoryTint.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: segmentWidth(segment), height: notebookGridRowHeight)
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
                .help(total == 0 ? "Categoría vacía." : "Resumen de categoría colapsada: \(filled) de \(total) columnas con datos.")
            )
        }
    }

    func categoryFolderHeader(category: NotebookColumnCategory, data: NotebookUiStateData, width: CGFloat) -> some View {
        let categoryTint = tint(for: category)
        let allColumns = self.columns(in: category, data: data, includeHidden: true)
        let countText = categoryColumnCountText(allColumns)
        let statusText = categoryHiddenColumnCount(allColumns) > 0 ? "expandida · con ocultas" : "expandida"
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                setCategoryCollapsed(category, collapsed: true)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(categoryTint)
                    .accessibilityHidden(true)

                Text(category.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(countText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(categoryTint)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(width: width, height: 32, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotebookStyle.surfaceSoft.opacity(0.30))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(categoryTint.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            categoryContextMenu(category, data: bridge.notebookState as? NotebookUiStateData)
        }
        .help("\(categoryAccessibilityState(isCollapsed: false, columns: allColumns)). Haz clic para cerrar.")
        .accessibilityLabel("\(category.name). \(categoryAccessibilityState(isCollapsed: false, columns: allColumns)). Haz clic para cerrar.")
    }

    func categoryVisibleColumnCount(_ columns: [NotebookColumnDefinition]) -> Int {
        columns.filter(\.isVisibleInGrid).count
    }

    func categoryHiddenColumnCount(_ columns: [NotebookColumnDefinition]) -> Int {
        columns.filter(\.isTemporarilyHidden).count
    }

    func categoryColumnCountText(_ columns: [NotebookColumnDefinition]) -> String {
        let visibleCount = categoryVisibleColumnCount(columns)
        let hiddenCount = categoryHiddenColumnCount(columns)

        if visibleCount == 0 && hiddenCount == 0 {
            return "0"
        }

        if hiddenCount > 0 {
            let visibleText = visibleCount == 1 ? "1 visible" : "\(visibleCount) visibles"
            let hiddenText = hiddenCount == 1 ? "1 oculta" : "\(hiddenCount) ocultas"
            return "\(visibleText) · \(hiddenText)"
        }

        return visibleCount == 1 ? "1 columna" : "\(visibleCount) columnas"
    }

    func categoryAccessibilityState(isCollapsed: Bool, columns: [NotebookColumnDefinition]) -> String {
        let visibleCount = categoryVisibleColumnCount(columns)
        let hiddenCount = categoryHiddenColumnCount(columns)

        if visibleCount == 0 && hiddenCount == 0 {
            return "Categoría vacía"
        }

        let state = isCollapsed ? "Categoría colapsada" : "Categoría expandida"
        if hiddenCount > 0 {
            return "\(state), \(categoryColumnCountText(columns))"
        }
        return "\(state), \(categoryColumnCountText(columns))"
    }

    @ViewBuilder
    func columnContextMenu(_ column: NotebookColumnDefinition, data: NotebookUiStateData) -> some View {
        Button("Renombrar") {
            editingColumnId = column.id
            columnDraft = column.title
            isRenameColumnAlertPresented = true
        }
        Button("Duplicar estructura") {
            duplicateColumnStructure(column)
        }
        Button(column.isArchived ? "Restaurar" : (column.isTemporarilyHidden ? "Mostrar" : "Ocultar")) {
            if column.isArchived {
                setNotebookColumnVisibility(column, visibility: .visible)
            } else {
                toggleColumnVisibility(column)
            }
        }
        if column.canBeArchived {
            Button("Archivar") {
                setNotebookColumnVisibility(column, visibility: .archived)
            }
        }
        Button("Cambiar peso…") {
            isAverageConfigurationPresented = true
        }
        Button(column.countsTowardAverage ? "Excluir de media" : "Incluir en media") {
            saveColumnMutation(
                column,
                countsTowardAverage: !column.countsTowardAverage,
                weight: column.countsTowardAverage ? 0 : max(column.weight, 1)
            )
            showToast(column.countsTowardAverage ? "Columna excluida de la media" : "Columna incluida en la media")
            scheduleToolbarStateSyncIfLoaded()
        }
        Menu("Avanzado") {
            if isNotebookIndividualSummaryColumn(column) {
                Button(summaryActionTitle(for: column, data: data)) {
                    notebookSummarySheetRequest = NotebookSummarySheetRequest(targetColumnId: column.id)
                }
            }
            if column.type == .calculated {
                Button("Editar fórmula…") {
                    presentFormulaEditor(for: column)
                }
            }
            if column.type == .rubric {
                Button("Evaluar alumno…") {
                    let targetRow = inspectorSelection
                        .flatMap { selection in filteredRows(data: data).first { $0.student.id == selection.studentId } }
                        ?? filteredRows(data: data).first
                    if let targetRow {
                        openRubricIndividual(column: column, item: targetRow)
                    } else {
                        showToast("No hay alumnos disponibles para evaluar", style: .warning)
                    }
                }
                Button("Evaluar grupo…") {
                    openRubricBulk(column: column, data: data)
                }
            }
            Menu("Mover a categoría") {
                Button("Sin categoría") {
                    bridge.assignColumn(column.id, toCategory: nil)
                    showToast("Columna movida fuera de la carpeta")
                }
                ForEach(visibleCategories(data: data), id: \.id) { category in
                    Button(category.name) {
                        bridge.assignColumn(column.id, toCategory: category.id)
                        highlightedCategoryId = category.id
                        showToast("Columna movida a \(category.name)")
                    }
                }
            }
            Menu("Cambiar color") {
                ForEach(columnColorOptions, id: \.hex) { option in
                    Button(option.label) {
                        saveColumnMutation(column, colorHex: option.hex)
                        showToast("Color actualizado")
                    }
                }
            }
            Button(column.isLocked ? "Desbloquear" : "Bloquear") {
                saveColumnMutation(column, isLocked: !column.isLocked)
                showToast(column.isLocked ? "Columna desbloqueada" : "Columna bloqueada")
            }
        }
        Button("Eliminar columna", role: .destructive) {
            presentDeleteColumnImpact(column)
        }
    }

    func duplicateColumnStructure(_ column: NotebookColumnDefinition) {
        bridge.addColumn(
            name: "\(column.title) copia",
            type: column.type.name,
            weight: column.weight,
            formula: column.formula,
            rubricId: column.rubricId?.int64Value,
            categoryId: column.categoryId,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            dateEpochMs: column.dateEpochMs?.int64Value,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds.map(\.int64Value),
            scaleKind: column.scaleKind,
            iconName: column.iconName,
            countsTowardAverage: column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: column.isTemplate
        )
        showToast("Estructura de columna duplicada")
        scheduleToolbarStateSyncIfLoaded()
    }

    func summaryActionTitle(for column: NotebookColumnDefinition, data: NotebookUiStateData) -> String {
        let hasExistingText = filteredRows(data: data).contains { row in
            !bridge.cellText(studentId: row.student.id, columnId: column.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        return hasExistingText ? "Regenerar síntesis…" : "Generar síntesis…"
    }

    @ViewBuilder
    func categoryContextMenu(_ category: NotebookColumnCategory, data: NotebookUiStateData?) -> some View {
        Button("Renombrar categoría") {
            editingCategoryId = category.id
            categoryDraft = category.name
            isCreateCategoryAlertPresented = true
        }
        Button(isCategoryCollapsed(category) ? "Expandir" : "Colapsar") {
            setCategoryCollapsed(category, collapsed: !isCategoryCollapsed(category))
        }
        Button("Nueva columna dentro") {
            openAddColumn(in: category)
        }
        if let data {
            Menu("Mover columnas a") {
                ForEach(visibleCategories(data: data).filter { $0.id != category.id }, id: \.id) { target in
                    Button(target.name) {
                        columns(in: category, data: data, includeHidden: true).forEach { column in
                            bridge.assignColumn(column.id, toCategory: target.id)
                        }
                        highlightedCategoryId = target.id
                        showToast("Columnas movidas a \(target.name)")
                    }
                }
                Button("Sin categoría") {
                    columns(in: category, data: data, includeHidden: true).forEach { column in
                        bridge.assignColumn(column.id, toCategory: nil)
                    }
                    showToast("Columnas liberadas de la carpeta")
                }
            }
        }
        Button("Eliminar categoría", role: .destructive) {
            presentDeleteCategoryImpact(category)
        }
    }

}
