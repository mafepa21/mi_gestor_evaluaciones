import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

// Detalle de la situación: cabecera, acciones, contenido curricular, documento y vínculos.
extension LearningSituationsWorkspaceView {
    @ViewBuilder
    var detailColumn: some View {
        if let situation = selectedSituation {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(situation.subjectLabel.uppercased())
                                .font(.caption.bold())
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Spacer()
                            situationStatusBadge(situation.status)
                        }
                        Text(situation.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text([situation.courseLabel, situation.termLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                    actionRow(for: situation)
                    HStack(spacing: 12) {
                        situationMetric(title: "Sesiones", value: "\(situation.sessionCount)", icon: "calendar")
                        situationMetric(title: "Grupos", value: "\(classLinks.count)", icon: "person.3")
                        situationMetric(title: "Versiones", value: "\(versions.count)", icon: "doc.on.doc")
                    }
                    if !situation.challenge.isEmpty {
                        contentCard(title: "Reto", text: situation.challenge)
                    }
                    if !situation.finalProduct.isEmpty {
                        contentCard(title: "Producto final", text: situation.finalProduct)
                    }
                    if let draft = selectedDraft {
                        curriculumSection(draft)
                    }
                    documentSection
                    linkedSection
                }
                .padding(28)
            }
        } else {
            if situations.isEmpty {
                WorkspaceEmptyState(
                    title: "Situaciones de aprendizaje",
                    subtitle: "Importa un documento Word y asócialo a tus grupos para programar sesiones y preparar evaluación.",
                    systemImage: "doc.text.magnifyingglass",
                    actionTitle: "Importar situación"
                ) {
                    importTargetId = nil
                    isImporterPresented = true
                }
            } else if filteredSituations.isEmpty {
                WorkspaceEmptyState(
                    title: "Sin resultados",
                    subtitle: "No hay situaciones que coincidan con la búsqueda o los filtros activos.",
                    systemImage: "line.3.horizontal.decrease.circle",
                    actionTitle: "Limpiar filtros",
                    action: clearSituationFilters
                )
            } else {
                ContentUnavailableView(
                    "Selecciona una situación",
                    systemImage: "sidebar.left",
                    description: Text("El detalle y sus acciones aparecerán aquí.")
                )
            }
        }
    }

    func actionRow(for situation: LearningSituation) -> some View {
        HStack(spacing: 10) {
            Button {
                scheduleSituation = situation
            } label: {
                Label("Programar sesiones", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            Button {
                evaluationSituation = situation
            } label: {
                Label("Preparar evaluación", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
            Menu {
                Button("Editar") {
                    if let decoded = draft(for: situation) {
                        importTargetId = situation.id
                        importDraft = decoded
                    }
                }
                Button("Importar nueva versión") {
                    importTargetId = situation.id
                    isImporterPresented = true
                }
                Button("Duplicar y reasignar") {
                    duplicateSituation = situation
                }
                Divider()
                Menu("Estado") {
                    ForEach(LearningSituationStatus.entries, id: \.self) { status in
                        Button {
                            Task { await updateStatus(situation, to: status) }
                        } label: {
                            HStack {
                                Text(situationStatusLabel(status))
                                if situation.status == status {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    situationToDelete = situation
                    showingSingleDeleteAlert = true
                } label: {
                    Label("Eliminar situación", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }

            .buttonStyle(.bordered)
        }
    }

    var documentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documento fuente").font(.headline)
            ForEach(versions, id: \.id) { version in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Versión \(version.versionNumber) · \(version.originalFileName)")
                                .font(.subheadline.weight(.semibold))
                            Text(String(version.sha256.prefix(12)) + " · \(ByteCountFormatter.string(fromByteCount: version.sizeBytes, countStyle: .file))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let path = version.localPath {
                            ShareLink(item: URL(fileURLWithPath: path)) {
                                Label("Abrir", systemImage: "square.and.arrow.up")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    let warnings = decodeVersionWarnings(version.warningsJson)
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(warnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    func decodeVersionWarnings(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    var linkedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vínculos creados").font(.headline)
            if resources.isEmpty {
                Text("Todavía no se han creado sesiones ni instrumentos desde esta situación.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(resources, id: \.id) { resource in
                    Button {
                        onOpenModule(destination(for: resource.kind), resource.classId?.int64Value, nil)
                    } label: {
                        HStack {
                            Label(resource.label.isEmpty ? resource.resourceId : resource.label, systemImage: icon(for: resource.kind))
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    func destination(for kind: LearningSituationResourceKind) -> AppWorkspaceModule {
        switch kind {
        case .teachingUnit, .planningSession: return .planner
        case .evaluation: return .evaluationHub
        case .rubric: return .rubrics
        case .notebookColumn: return .notebook
        default: return .notebook
        }
    }

    func situationMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func contentCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func curriculumSection(_ draft: LearningSituationImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Desarrollo curricular").font(.headline)
            DisclosureGroup("Criterios y evidencias (\(draft.criteria.count))") {
                ForEach(draft.criteria) { criterion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(criterion.criterion).font(.subheadline.weight(.semibold))
                        if !criterion.evidence.isEmpty {
                            Text(criterion.evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
            if !draft.knowledge.isEmpty {
                DisclosureGroup("Saberes básicos") {
                    bulletList(draft.knowledge)
                }
            }
            if !draft.methodology.isEmpty {
                DisclosureGroup("Metodología") {
                    bulletList(draft.methodology)
                }
            }
            if !draft.inclusionMeasures.isEmpty {
                DisclosureGroup("Medidas DUA") {
                    bulletList(draft.inclusionMeasures)
                }
            }
            ForEach(draft.documentTables ?? []) { table in
                DisclosureGroup(table.title) {
                    documentTable(table)
                }
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Tabla del documento fuente (p.ej. secuenciación de sesiones o adaptaciones) que se
    /// mantiene como tabla real en vez de aplanarla en líneas sueltas.
    func documentTable(_ table: LearningSituationTableDraft) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    func icon(for kind: LearningSituationResourceKind) -> String {
        switch kind {
        case .teachingUnit: return "folder"
        case .planningSession: return "calendar"
        case .evaluation: return "checklist"
        case .rubric: return "list.clipboard"
        case .notebookColumn: return "tablecells"
        default: return "link"
        }
    }
}
