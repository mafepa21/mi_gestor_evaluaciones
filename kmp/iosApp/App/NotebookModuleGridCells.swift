import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    /// Cabecera plana integrada: sin chip flotante (fill/borde/sombra/cápsula
    /// propios). La identidad de la columna es una barra de 3pt pegada al borde
    /// inferior, del ancho completo de la columna, que conecta visualmente la
    /// cabecera con sus celdas. Columnas de sistema no llevan barra: su
    /// identidad ya la da la fila de cabecera (`.thinMaterial` + hairline).
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(isSystemColumn ? .footnote : NotebookGridStyle.columnTitle)
                .foregroundStyle(isSystemColumn ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(NotebookGridStyle.columnMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 52, alignment: .topLeading)
        .background(isHighlighted ? NotebookGridStyle.columnActiveWash : Color.clear)
        .overlay(alignment: .bottom) {
            if !isSystemColumn {
                // Columna activa → barra de acento (la identidad de "resaltada"
                // vive aquí, no en un flood de azul sobre las celdas). Con color
                // propio → tinte de la columna; en reposo → hairline neutro.
                Rectangle()
                    .fill(isHighlighted
                          ? Color.accentColor
                          : ((hasColumnColor || folderStyle) ? tint.opacity(0.9) : NotebookGridStyle.gridLineStrong))
                    .frame(height: 3)
            }
        }
    }

    func headerChip(for segment: NotebookDisplaySegment, data: NotebookUiStateData) -> some View {
        switch segment {
        case .fixed(let fixed):
            if fixed == .name {
                // Mismo tratamiento plano que `headerChip`: sin fill/sombra/borde
                // propios (antes tenía su propia caja, inconsistente con el resto
                // de cabeceras del sistema tras el rediseño de PR3).
                let chip = HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fixed.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(fixed.subtitle)
                            .font(NotebookGridStyle.columnMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    Spacer(minLength: 4)
                    
                    Menu {
                        Button {
                            groupByWorkGroupMode = "none"
                        } label: {
                            HStack {
                                Text("No agrupar")
                                if groupByWorkGroupMode == "none" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Button {
                            groupByWorkGroupMode = "general"
                        } label: {
                            HStack {
                                Text("Grupos generales")
                                if groupByWorkGroupMode == "general" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        if !classSituations.isEmpty {
                            Divider()
                            ForEach(classSituations, id: \.id) { situation in
                                Button {
                                    groupByWorkGroupMode = "situation_\(situation.id)"
                                } label: {
                                    HStack {
                                        Text("Grupos: \(situation.title)")
                                        if groupByWorkGroupMode == "situation_\(situation.id)" {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: groupByWorkGroup ? "person.2.fill" : "person.2")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(groupByWorkGroup ? NotebookStyle.primaryTint : .secondary)
                            .padding(6)
                            .background(Color.secondary.opacity(groupByWorkGroup ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Seleccionar modo de agrupación")
                    .accessibilityLabel("Modo de agrupación")
                    .accessibilityValue(groupByWorkGroup ? "Agrupado por grupo de trabajo" : "Sin agrupar")
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
                .frame(minHeight: 52, alignment: .topLeading)

                return AnyView(chip)
            }
            
            let chip = headerChip(
                title: fixed.title,
                subtitle: fixed.subtitle,
                width: resolvedFixedWidth(for: fixed),
                tint: tint(for: fixed),
                isSystemColumn: true
            )
            if fixed == .average {
                // La cabecera de Media es la única que abre un editor al
                // tocarla; sin un icono propio se veía idéntica a "Asistencia"
                // o "Seguimiento" y nadie descubría que era interactiva. El
                // subtítulo deja de ser un "Promedio" estático y refleja
                // cuántas columnas cuentan hoy, como recuerdo de que el peso
                // se configura aquí.
                let averageColumnCount = data.sheet.columns.filter(\.countsTowardAverage).count
                let averageSubtitle = averageColumnCount > 0
                    ? "Ponderada · \(averageColumnCount) col."
                    : "Sin columnas"
                return AnyView(
                    Button {
                        isAverageConfigurationPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fixed.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(averageSubtitle)
                                    .font(NotebookGridStyle.columnMeta)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NotebookStyle.primaryTint)
                                .padding(6)
                                .background(NotebookStyle.primaryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        .frame(width: resolvedFixedWidth(for: fixed), alignment: .leading)
                        .frame(minHeight: 52, alignment: .topLeading)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(NotebookStyle.primaryTint.opacity(0.9))
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Configurar media")
                    .accessibilityValue(averageSubtitle)
                    .help("Configurar cómo se calcula la media: \(averageSubtitle)")
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
                        isHighlighted: isColumnHighlighted(column)
                    )
                }
                .onTapGesture {
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        selectedColumnId = column.id
                        inspectorSelection = nil
                        focusedCellId = nil
                        activeChoiceCellId = nil
                    }
                }
                .contextMenu {
                    columnContextMenu(column, data: data)
                }
            )
        case .collapsedCategory(let category, let columns):
            return AnyView(
                Button {
                    setCategoryCollapsed(category, collapsed: false)
                } label: {
                    collapsedCategoryHeader(
                        category: category,
                        columns: columns,
                        width: segmentWidth(segment)
                    )
                }
                .buttonStyle(NotebookCategoryHeaderButtonStyle())
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
        let countText = categoryColumnCountText(columns)

        // Mismo tratamiento plano que `headerChip`: sin fill/sombra/borde propios,
        // ocupa el mismo slot de la fila de cabecera. La barra inferior en el
        // tinte de la categoría sustituye al color repartido por icono/texto.
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: isEmpty ? "folder" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(category.name)
                    .font(NotebookGridStyle.columnTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(isEmpty ? "Vacía" : "\(countText) · colapsada")
                .font(NotebookGridStyle.columnMeta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 52, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isEmpty {
                Rectangle()
                    .fill(categoryTint.opacity(0.9))
                    .frame(height: 3)
            }
        }
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
        if column.inputKind.isStructuredInstrument {
            switch column.inputKind {
            case .structuredChecklist:
                typeText = "Checklist"
            case .structuredObservation:
                typeText = "Observación"
            case .structuredForm:
                typeText = "Formulario"
            case .structuredQuiz:
                typeText = "Quiz"
            default:
                typeText = "Columna"
            }
        } else {
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
        }

        guard let weightBadge = columnWeightBadge(for: column) else { return typeText }
        return "\(typeText) · \(weightBadge)"
    }

    /// Hace visible en la cabecera lo que hasta ahora solo se veía abriendo
    /// "Configurar media": si la columna pesa distinto de ×1 o si está
    /// excluida del cálculo. Sin esto, una columna excluida era indistinguible
    /// de una que cuenta ×3 con solo mirar la rejilla.
    func columnWeightBadge(for column: NotebookColumnDefinition) -> String? {
        if !column.countsTowardAverage {
            return "no cuenta"
        }
        if column.weight == 1 {
            return nil
        }
        // D1: Si la columna proviene de una evaluación importada o tiene un peso
        // asignado (0,4 para 40 % o 55 para 55 %), mostramos "55%" o "40%" en la cabecera.
        if column.evaluationId != nil || (column.weight > 0 && column.weight != 1) {
            let percent = (column.weight > 0 && column.weight < 1) ? column.weight * 100 : column.weight
            let rounded = (percent * 10).rounded() / 10
            return rounded.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(rounded))%"
                : "\(String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ","))%"
        }
        if column.weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "×\(Int(column.weight))"
        }
        return "×\(IosFormatting.decimal(from: column.weight))"
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

    /// La columna está resaltada (menú de columna abierto o selección con foco en
    /// el inspector): mismo criterio que usa la cabecera (`headerChip(for:)`).
    func isColumnHighlighted(_ column: NotebookColumnDefinition) -> Bool {
        if selectedColumnId == column.id || highlightedColumnId == column.id { return true }
        // Solo se resalta por categoría cuando hay una categoría resaltada activa:
        // comparar dos `Optional` directamente daría `nil == nil == true`, marcando
        // como resaltada toda columna sin categoría en reposo (inunda el grid).
        guard let highlightedCategoryId else { return false }
        return highlightedCategoryId == column.categoryId
    }

    /// Fondo de celda: única técnica de separación de filas (zebra plana + wash de
    /// color de columna o de columna resaltada cuando aplica). La selección **no**
    /// se pinta aquí: la dibuja la celda editable interior como un chip elevado
    /// (superficie + sombra + anillo), para que se lea sobre un fondo limpio sin
    /// doble tinte de acento.
    func notebookColumnCellFill(for column: NotebookColumnDefinition, rowIndex: Int) -> Color {
        if isColumnHighlighted(column) {
            return NotebookGridStyle.columnActiveWash
        }
        if hasCustomColumnColor(column) {
            return displayTint(for: column).opacity(0.035)
        }
        return rowIndex.isMultiple(of: 2) ? NotebookGridStyle.zebra : Color.clear
    }

    @MainActor
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
            let formulaCellDisplay = formulaDisplay(for: item, column: column, data: data)
            let displaySnapshot = cellDisplaySnapshot(for: item, column: column, formulaDisplay: formulaCellDisplay)
            let cellActions = notebookCellActions()
            return AnyView(
                ZStack {
                    Rectangle()
                        .fill(notebookColumnCellFill(for: column, rowIndex: rowIndex))

                    NotebookEditableTableCell(
                        displaySnapshot: displaySnapshot,
                        actions: cellActions,
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
                        formulaDisplay: formulaCellDisplay,
                        isSelected: isCellSelected,
                        isAttendanceQuickMode: isAttendanceQuickMode,
                        reloadToken: rowReloadRevisions[item.student.id, default: 0],
                        onSelect: {
                            selectedColumnId = nil
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
                        onOpenStructuredInstrument: {
                            focusMode = .editing
                            structuredInstrumentRequest = StructuredInstrumentEvaluationRequest(
                                id: "\(data.sheet.classId)-\(item.student.id)-\(column.id)",
                                classId: data.sheet.classId,
                                studentId: item.student.id,
                                studentName: "\(item.student.firstName) \(item.student.lastName)",
                                columnId: column.id,
                                title: column.title
                            )
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
                            reloadNotebookRow(item.student.id)
                        },
                        onAttendanceSaved: {
                            Task { await refreshNotebookSignals() }
                        }
                    )
                }
                .frame(width: resolvedColumnWidth(for: column), height: notebookGridRowHeight)
                .contextMenu {
                    Button("Abrir inspector") {
                        selectedColumnId = nil
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
                            selectedColumnId = nil
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
                    setCategoryCollapsed(category, collapsed: false)
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(NotebookCategoryHeaderButtonStyle())
                .frame(width: segmentWidth(segment), height: notebookGridRowHeight)
                .contextMenu {
                    categoryContextMenu(category, data: data)
                }
                .help(total == 0 ? "Categoría vacía." : "Resumen de categoría colapsada: \(filled) de \(total) columnas con datos.")
                .accessibilityLabel(
                    "\(category.name), \(item.student.fullName), categoría colapsada"
                )
                .accessibilityValue(total == 0 ? "Vacía" : "\(filled) de \(total) columnas con datos")
            )
        }
    }

    @MainActor
    func cellDisplaySnapshot(
        for item: NotebookTableRow,
        column: NotebookColumnDefinition,
        formulaDisplay: NotebookFormulaCellDisplay?
    ) -> NotebookCellDisplaySnapshot {
        let persistedCell = item.row.persistedCells.first(where: { $0.columnId == column.id })

        switch column.type {
        case .numeric:
            return NotebookCellDisplaySnapshot(
                numericText: displayValue(for: item, column: column)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .check:
            return NotebookCellDisplaySnapshot(checkValue: displayValue(for: item, column: column) == "Sí")
        case .calculated:
            return NotebookCellDisplaySnapshot(
                calculatedText: formulaDisplay?.text ?? displayValue(for: item, column: column)
            )
        case .rubric:
            return NotebookCellDisplaySnapshot(
                rubricText: displayValue(for: item, column: column)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .attendance:
            return NotebookCellDisplaySnapshot(text: displayValue(for: item, column: column))
        default:
            return NotebookCellDisplaySnapshot(text: persistedCell?.textValue ?? persistedCell?.displayValue ?? "")
        }
    }

    @MainActor
    func notebookCellActions() -> NotebookCellActions {
        NotebookCellActions(
            flushPendingColumnGradeSave: { studentId, columnId in
                bridge.flushPendingColumnGradeSave(studentId: studentId, columnId: columnId)
            },
            saveColumnGrade: { studentId, column, value in
                bridge.saveColumnGrade(studentId: studentId, column: column, value: value)
            },
            saveColumnGradeDebounced: { studentId, column, value in
                bridge.saveColumnGradeDebounced(studentId: studentId, column: column, value: value)
            },
            saveAttendance: { studentId, classId, date, status in
                try? await bridge.saveAttendance(
                    studentId: studentId,
                    classId: classId,
                    on: date,
                    status: status
                )
            }
        )
    }

    func categoryFolderHeader(category: NotebookColumnCategory, data: NotebookUiStateData, width: CGFloat) -> some View {
        let categoryTint = tint(for: category)
        let allColumns = self.columns(in: category, data: data, includeHidden: true)
        let countText = categoryColumnCountText(allColumns)
        let statusText = categoryHiddenColumnCount(allColumns) > 0 ? "expandida · con ocultas" : "expandida"
        return Button {
            setCategoryCollapsed(category, collapsed: true)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(categoryTint)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(category.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(countText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(width: width, height: 32, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(NotebookCategoryHeaderButtonStyle())
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

private struct NotebookCategoryHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}
