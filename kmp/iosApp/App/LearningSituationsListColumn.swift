import SwiftUI
import MiGestorKit

// Columna de lista: barra propia, búsqueda, chips de filtro, filas, selección múltiple
// y estados (cargando, vacío, sin resultados, error en línea).
extension LearningSituationsWorkspaceView {
    var listColumn: some View {
        VStack(spacing: 0) {
            listHeaderBar
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                LearningSituationSearchField(text: $searchText, prompt: "Buscar situación")
                filterChips
                if isReadingImport {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Leyendo el documento…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: minimumTapSize)
                    .accessibilityElement(children: .combine)
                }
                if let listErrorMessage {
                    LearningSituationInlineNotice(
                        kind: .error,
                        message: listErrorMessage,
                        actionTitle: "Reintentar"
                    ) {
                        Task { await reload() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            listContent
        }
        .background(appCardBackground(for: colorScheme))
    }

    // MARK: Barra

    private var listHeaderBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                listHeaderLeading
                listHeaderTitle
                Spacer(minLength: 8)
                listHeaderActions
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    listHeaderLeading
                    listHeaderTitle
                }
                LearningSituationFlowLayout(spacing: 8) {
                    listHeaderActions
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: minimumTapSize + 8)
    }

    @ViewBuilder
    private var listHeaderLeading: some View {
        if isSelectionMode {
            Button("Hecho") {
                isSelectionMode = false
                selectedSituationIds.removeAll()
            }
            .buttonStyle(.borderless)
            .frame(minHeight: minimumTapSize)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var listHeaderTitle: some View {
        Text(listTitle)
            .font(.title3.weight(.bold))
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
    }

    private var listTitle: String {
        guard isSelectionMode else { return "Situaciones" }
        switch selectedSituationIds.count {
        case 0: return "Elige situaciones"
        case 1: return "1 seleccionada"
        default: return "\(selectedSituationIds.count) seleccionadas"
        }
    }

    @ViewBuilder
    private var listHeaderActions: some View {
        if isSelectionMode {
            Button("Archivar") {
                Task { await performBatchArchive() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(selectedSituationIds.isEmpty)

            Button("Eliminar", role: .destructive) {
                requestDelete(situations.filter { selectedSituationIds.contains($0.id) })
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(selectedSituationIds.isEmpty)
        } else {
            if !situations.isEmpty {
                Button("Seleccionar") {
                    selectedSituationIds.removeAll()
                    isSelectionMode = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                startImport(targetId: nil)
            } label: {
                Label("Importar", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Importar documento Word")
            .help("Importar uno o varios documentos Word")
        }
    }

    func startImport(targetId: Int64?) {
        importTargetId = targetId
        isImporterPresented = true
    }

    // MARK: Filtros

    private var filterChips: some View {
        LearningSituationFlowLayout(spacing: 8) {
            LearningSituationFilterChip(
                title: "Grupo",
                valueLabel: classFilter.flatMap { id in bridge.classes.first(where: { $0.id == id })?.name },
                onClear: { classFilter = nil }
            ) {
                Picker("Grupo", selection: $classFilter) {
                    Text("Todos los grupos").tag(nil as Int64?)
                    ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
            }

            if !availableSubjects.isEmpty {
                LearningSituationFilterChip(
                    title: "Materia",
                    valueLabel: subjectFilter.isEmpty ? nil : subjectFilter,
                    onClear: { subjectFilter = "" }
                ) {
                    Picker("Materia", selection: $subjectFilter) {
                        Text("Todas las materias").tag("")
                        ForEach(availableSubjects, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }

            if !availableTerms.isEmpty {
                LearningSituationFilterChip(
                    title: "Trimestre",
                    valueLabel: termFilter.isEmpty ? nil : termFilter,
                    onClear: { termFilter = "" }
                ) {
                    Picker("Trimestre", selection: $termFilter) {
                        Text("Todos los trimestres").tag("")
                        ForEach(availableTerms, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }

            if hasActiveQuery {
                Button("Limpiar", action: clearSituationFilters)
                    .buttonStyle(.borderless)
                    .frame(minHeight: minimumTapSize)
                    .accessibilityLabel("Limpiar búsqueda y filtros")
            }
        }
    }

    // MARK: Contenido

    @ViewBuilder
    private var listContent: some View {
        if isLoadingList && situations.isEmpty {
            List {
                Label("Cargando…", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cargando situaciones")
                ForEach(0..<4, id: \.self) { _ in
                    LearningSituationSkeletonRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .allowsHitTesting(false)
        } else if situations.isEmpty {
            ContentUnavailableView {
                Label("Aún no hay situaciones", systemImage: "doc.badge.plus")
            } description: {
                Text("Importa un documento Word para empezar.")
            } actions: {
                Button("Importar") { startImport(targetId: nil) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSituations.isEmpty {
            ContentUnavailableView {
                Label("Sin resultados", systemImage: "magnifyingglass")
            } description: {
                Text(emptyResultsDescription)
            } actions: {
                if hasActiveQuery {
                    Button("Limpiar filtros", action: clearSituationFilters)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else if archivedCount > 0 && !showsArchived {
                    Button("Mostrar archivadas") { showsArchived = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredSituations, id: \.id) { situation in
                    situationRow(for: situation)
                }
                archivedToggleRow
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyResultsDescription: String {
        if hasActiveQuery {
            return "Prueba con otro texto o quita filtros."
        }
        return "Todas tus situaciones están archivadas."
    }

    @ViewBuilder
    private var archivedToggleRow: some View {
        if archivedCount > 0 {
            Button {
                showsArchived.toggle()
            } label: {
                Text(showsArchived ? "Ocultar archivadas" : "Mostrar archivadas (\(archivedCount))")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: minimumTapSize, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: Fila

    func situationRow(for situation: LearningSituation) -> some View {
        let isChecked = selectedSituationIds.contains(situation.id)
        let isCurrent = !isSelectionMode && !usesCompactLayout && selectedSituationId == situation.id
        return Button {
            if isSelectionMode {
                if isChecked {
                    selectedSituationIds.remove(situation.id)
                } else {
                    selectedSituationIds.insert(situation.id)
                }
            } else {
                openSituation(situation)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isSelectionMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? EvaluationDesign.accent : Color.secondary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(situation.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    let subtitle = situationSubtitle(situation)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    LearningSituationStatusBadge(status: situation.status)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(EvaluationDesign.accent)
                        .accessibilityHidden(true)
                } else if usesCompactLayout && !isSelectionMode {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minimumTapSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            (isCurrent || (isSelectionMode && isChecked)) ? EvaluationDesign.accentSoft : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits((isCurrent || (isSelectionMode && isChecked)) ? .isSelected : [])
        .accessibilityHint(isSelectionMode ? "Marca o desmarca la situación" : "Abre el detalle")
        .contextMenu {
            if !isSelectionMode {
                situationContextMenu(for: situation)
            }
        }
    }

    func situationSubtitle(_ situation: LearningSituation) -> String {
        [situation.subjectLabel, situation.courseLabel, situation.termLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func situationContextMenu(for situation: LearningSituation) -> some View {
        Button {
            scheduleSituation = situation
        } label: {
            Label("Programar", systemImage: "calendar.badge.plus")
        }
        Button {
            evaluationSituation = situation
        } label: {
            Label("Evaluar", systemImage: "checklist")
        }
        Button {
            duplicateSituation = situation
        } label: {
            Label("Duplicar…", systemImage: "plus.square.on.square")
        }
        if situation.status == .archived {
            Button {
                Task { await updateStatus(situation, to: .active) }
            } label: {
                Label("Desarchivar", systemImage: "tray.and.arrow.up")
            }
        } else {
            Button {
                Task { await updateStatus(situation, to: .archived) }
            } label: {
                Label("Archivar", systemImage: "archivebox")
            }
        }
        Divider()
        Button(role: .destructive) {
            requestDelete([situation])
        } label: {
            Label("Eliminar", systemImage: "trash")
        }
    }
}
