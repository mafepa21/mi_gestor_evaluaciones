import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func headerChip(
        title: String,
        subtitle: String,
        width: CGFloat,
        tint: Color,
        folderStyle: Bool = false,
        hasColumnColor: Bool = false,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Circle()
                    .fill(tint.opacity(folderStyle ? 0.8 : 0.5))
                    .frame(width: 6, height: 6)

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
                .fill(headerChipFill(tint: tint, folderStyle: folderStyle, hasColumnColor: hasColumnColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            headerChipStroke(tint: tint, folderStyle: folderStyle, hasColumnColor: hasColumnColor, isHighlighted: isHighlighted),
                            lineWidth: isHighlighted ? 1.4 : 0.6
                        )
                )
        )
    }

    func headerChipFill(tint: Color, folderStyle: Bool, hasColumnColor: Bool) -> Color {
        if hasColumnColor { return tint.opacity(0.18) }
        return folderStyle ? NotebookStyle.surfaceSoft.opacity(0.55) : Color.clear
    }

    func headerChipStroke(tint: Color, folderStyle: Bool, hasColumnColor: Bool, isHighlighted: Bool) -> Color {
        if isHighlighted { return tint.opacity(0.32) }
        if hasColumnColor { return tint.opacity(0.30) }
        return folderStyle ? NotebookStyle.softBorder.opacity(0.80) : Color.clear
    }

    func headerChip(for segment: NotebookDisplaySegment, data: NotebookUiStateData) -> some View {
        let visibleRows = filteredRows(data: data)
        switch segment {
        case .fixed(let fixed):
            let chip = headerChip(
                title: fixed.title,
                subtitle: fixed.subtitle,
                width: resolvedFixedWidth(for: fixed),
                tint: tint(for: fixed)
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
                    columnWidths[column.id] = newWidth
                } content: {
                    headerChip(
                        title: column.title,
                        subtitle: columnHeaderSubtitle(for: column, data: data, rows: visibleRows),
                        width: resolvedColumnWidth(for: column),
                        tint: displayTint(for: column),
                        folderStyle: column.categoryId != nil,
                        hasColumnColor: hasCustomColumnColor(column),
                        isHighlighted: highlightedCategoryId == column.categoryId
                    )
                }
                .contextMenu {
                    columnContextMenu(column, data: data)
                }
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                headerChip(
                    title: category.name,
                    subtitle: collapsedCategoryProgressText(columns: columns, rows: visibleRows),
                    width: 150,
                    tint: tint(for: category),
                    folderStyle: true,
                    isHighlighted: highlightedCategoryId == category.id
                )
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
            )
        }
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
        if hasCustomColumnColor(column) {
            return displayTint(for: column).opacity(isActive ? 0.20 : 0.10)
        }
        return rowIndex.isMultiple(of: 2) ? NotebookStyle.surfaceMuted.opacity(0.34) : Color.clear
    }

    func notebookColumnCellBorder(for column: NotebookColumnDefinition, isActive: Bool) -> Color {
        if isActive { return Color.accentColor.opacity(0.85) }
        if hasCustomColumnColor(column) { return displayTint(for: column).opacity(0.24) }
        return NotebookStyle.softBorder.opacity(0.45)
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
                            presentFormulaEditor(for: column)
                        },
                        onOpenRubricIndividual: {
                            openRubricIndividual(column: column, item: item)
                        },
                        onOpenRubricBulk: {
                            openRubricBulk(column: column, data: data)
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
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                Button {
                    bridge.toggleColumnCategory(id: category.id, collapsed: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("\(filledCellCount(item, columns: columns)) / \(columns.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint(for: category).opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .frame(width: 150, height: notebookGridRowHeight)
                .background(tint(for: category).opacity(0.08))
                .overlay(
                    Rectangle()
                        .stroke(NotebookStyle.softBorder.opacity(0.45), lineWidth: 0.5)
                )
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
            )
        }
    }

    func categoryFolderHeader(category: NotebookColumnCategory, columns: [NotebookColumnDefinition], rows: [NotebookTableRow], width: CGFloat) -> some View {
        let categoryTint = tint(for: category)
        let completed = completedCollapsedCategoryCount(columns, rows: rows)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: category.isCollapsed ? "folder.fill" : "folder.fill.badge.minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(categoryTint)
                    Text(category.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(columns.count)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(categoryTint)
                }

                Text(columns.isEmpty ? "Carpeta vacía lista para nuevas columnas" : "\(completed)/\(visibleColumnCount(columns)) con datos")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(spacing: 6) {
                Button {
                    openAddColumn(in: category)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)

                Menu {
                    categoryContextMenu(category, data: bridge.notebookState as? NotebookUiStateData)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(categoryTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.030))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(categoryTint.opacity(highlightedCategoryId == category.id ? 0.48 : 0.20), lineWidth: highlightedCategoryId == category.id ? 1.5 : 1)
                )
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(categoryTint.opacity(0.72))
                        .frame(width: min(108, width * 0.48), height: 4)
                        .offset(x: 12, y: 8)
                }
        )
        .contextMenu {
            categoryContextMenu(category, data: bridge.notebookState as? NotebookUiStateData)
        }
    }

    @ViewBuilder
    func columnContextMenu(_ column: NotebookColumnDefinition, data: NotebookUiStateData) -> some View {
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
        Button("Renombrar") {
            editingColumnId = column.id
            columnDraft = column.title
            isRenameColumnAlertPresented = true
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
        Button(column.isArchived ? "Restaurar" : (column.isTemporarilyHidden ? "Mostrar" : "Ocultar")) {
            if column.isArchived {
                setNotebookColumnVisibility(column, visibility: .visible)
            } else {
                toggleColumnVisibility(column)
            }
        }
        Button(column.isLocked ? "Desbloquear" : "Bloquear") {
            saveColumnMutation(column, isLocked: !column.isLocked)
            showToast(column.isLocked ? "Columna desbloqueada" : "Columna bloqueada")
        }
        Button(column.countsTowardAverage ? "No contar para media" : "Contar para media") {
            saveColumnMutation(column, countsTowardAverage: !column.countsTowardAverage)
            showToast(column.countsTowardAverage ? "Columna excluida de la media" : "Columna incluida en la media")
        }
        Button("Eliminar columna", role: .destructive) {
            presentDeleteColumnImpact(column)
        }
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
        Button(category.isCollapsed ? "Expandir" : "Colapsar") {
            bridge.toggleColumnCategory(id: category.id, collapsed: !category.isCollapsed)
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
