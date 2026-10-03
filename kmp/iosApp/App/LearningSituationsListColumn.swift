import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

// Columna de lista: búsqueda, filtros, filas y selección múltiple.
extension LearningSituationsWorkspaceView {
    var masterColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Situaciones")
                    .font(.title2.bold())
                Spacer()
                if isSelectionMode {
                    Button(role: .destructive) {
                        showingBatchDeleteAlert = true
                    } label: {
                        Text("Eliminar (\(selectedSituationIds.count))")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(selectedSituationIds.isEmpty)

                    Button("Cancelar") {
                        isSelectionMode = false
                        selectedSituationIds.removeAll()
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isSelectionMode = true
                        selectedSituationIds.removeAll()
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .help("Seleccionar múltiples")

                    Button {
                        importTargetId = nil
                        isImporterPresented = true
                    } label: {
                        Label("Importar", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Importar situación de aprendizaje")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar situación", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                WorkspaceCompactStat(title: "Situaciones", value: "\(filteredSituations.count)", tint: EvaluationDesign.accent)
                WorkspaceCompactStat(title: "Materias", value: "\(availableSubjects.count)", tint: IOSAppStyle.warning)
                WorkspaceCompactStat(title: "Trimestres", value: "\(availableTerms.count)", tint: EvaluationDesign.success)
            }

            situationFiltersMenu
            if isSelectionMode {
                Text("\(selectedSituationIds.count) seleccionadas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            }
            .padding(24)

            if filteredSituations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: situations.isEmpty ? "doc.badge.plus" : "line.3.horizontal.decrease.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(situations.isEmpty ? "Aún no hay situaciones" : "Ninguna coincide con los filtros")
                        .font(.headline)
                    if situations.isEmpty {
                        Button("Importar situación") {
                            importTargetId = nil
                            isImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Limpiar filtros", action: clearSituationFilters)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if isSelectionMode {
                List(filteredSituations, id: \.id, selection: $selectedSituationIds) { situation in
                    situationRow(for: situation)
                        .tag(situation.id)
                }
                .listStyle(.plain)
            } else {
                List(filteredSituations, id: \.id, selection: $selectedSituationId) { situation in
                    situationRow(for: situation)
                        .tag(situation.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                situationToDelete = situation
                                showingSingleDeleteAlert = true
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.plain)
            }

        }
        .background(appMutedCardBackground(for: colorScheme))
    }

    var situationFiltersMenu: some View {
        Menu {
            Picker("Grupo", selection: $classFilter) {
                Text("Todos los grupos").tag(nil as Int64?)
                ForEach(bridge.classes, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Materia", selection: $subjectFilter) {
                Text("Todas las materias").tag("")
                ForEach(availableSubjects, id: \.self) { Text($0).tag($0) }
            }
            Picker("Trimestre", selection: $termFilter) {
                Text("Todos los trimestres").tag("")
                ForEach(availableTerms, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Label("Filtrar", systemImage: "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    func situationRow(for situation: LearningSituation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                Text(situation.title).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                situationStatusBadge(situation.status)
            }
            Text([situation.courseLabel, situation.subjectLabel, situation.termLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if situation.sessionCount > 0 {
                Label("\(situation.sessionCount) sesiones", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
    }
}
