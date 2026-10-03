import SwiftUI
import MiGestorKit

// Detalle de la situación: cabecera, una sola acción principal («Programar»), lo que se
// creó (vínculos) por encima del documento, lectura curricular y documento original.
extension LearningSituationsWorkspaceView {
    @ViewBuilder
    var detailColumn: some View {
        if let situation = selectedSituation {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailHeader(for: situation)
                    actionRow(for: situation)
                    if let detailErrorMessage {
                        LearningSituationInlineNotice(
                            kind: .error,
                            message: detailErrorMessage,
                            actionTitle: "Reintentar"
                        ) {
                            Task { await reloadDetail() }
                        }
                    }
                    if isLoadingDetail {
                        LearningSituationCard(title: "Lo que se creó") {
                            LearningSituationSkeletonBlock(lines: 2)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cargando el contenido de la situación")
                    } else {
                        linkedSection
                    }
                    if !situation.challenge.isEmpty {
                        LearningSituationCard(title: "Reto") {
                            Text(situation.challenge)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !situation.finalProduct.isEmpty {
                        LearningSituationCard(title: "Producto final") {
                            Text(situation.finalProduct)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    curriculumSection(for: situation)
                    if isLoadingDetail {
                        LearningSituationCard(title: "Documento original") {
                            LearningSituationSkeletonBlock(lines: 2)
                        }
                        .accessibilityHidden(true)
                    } else {
                        documentSection
                    }
                }
                .padding(usesCompactLayout ? 16 : 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView {
                Label("Elige una situación", systemImage: "hand.point.left")
            } description: {
                Text("Verás aquí su contenido, vínculos y acciones.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Cabecera

    private func detailHeader(for situation: LearningSituation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LearningSituationFlowLayout(spacing: 8) {
                LearningSituationStatusBadge(status: situation.status)
                let subtitle = situationSubtitle(situation)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(situation.title)
                .font(.title.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Acciones

    func actionRow(for situation: LearningSituation) -> some View {
        LearningSituationFlowLayout(spacing: 8) {
            Button {
                scheduleSituation = situation
            } label: {
                Label("Programar", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                evaluationSituation = situation
            } label: {
                Label("Evaluar", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Menu {
                moreActionsMenu(for: situation)
            } label: {
                Label("Más acciones", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: minimumTapSize - 16)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Más acciones")
        }
    }

    @ViewBuilder
    private func moreActionsMenu(for situation: LearningSituation) -> some View {
        Button {
            if let decoded = draft(for: situation) {
                importTargetId = situation.id
                importDraft = decoded
            }
        } label: {
            Label("Editar ficha", systemImage: "square.and.pencil")
        }
        Button {
            startImport(targetId: situation.id)
        } label: {
            Label("Importar nueva versión", systemImage: "arrow.down.doc")
        }
        Button {
            duplicateSituation = situation
        } label: {
            Label("Duplicar…", systemImage: "plus.square.on.square")
        }
        Section("Estado") {
            ForEach(LearningSituationStatus.entries, id: \.self) { status in
                Button {
                    Task { await updateStatus(situation, to: status) }
                } label: {
                    if situation.status == status {
                        Label(LearningSituationStatusStyle.label(status), systemImage: "checkmark")
                    } else {
                        Text(LearningSituationStatusStyle.label(status))
                    }
                }
                .disabled(situation.status == status)
            }
        }
        Divider()
        Button(role: .destructive) {
            requestDelete([situation])
        } label: {
            Label("Eliminar…", systemImage: "trash")
        }
    }

    // MARK: Lo que se creó

    private var linkedSection: some View {
        LearningSituationCard(title: "Lo que se creó") {
            if resources.isEmpty {
                Text("Aún no se ha creado nada. Al programar o evaluar aparecerá aquí.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(resources.enumerated()), id: \.element.id) { index, resource in
                        if index > 0 { Divider() }
                        Button {
                            onOpenModule(destination(for: resource.kind), resource.classId?.int64Value, nil)
                        } label: {
                            HStack(spacing: 12) {
                                Label(resource.label.isEmpty ? resource.resourceId : resource.label, systemImage: icon(for: resource.kind))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text("Abrir")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(EvaluationDesign.accent)
                            }
                            .frame(maxWidth: .infinity, minHeight: minimumTapSize, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Abre \(moduleName(for: resource.kind))")
                    }
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

    private func moduleName(for kind: LearningSituationResourceKind) -> String {
        switch kind {
        case .teachingUnit, .planningSession: return "el Planner"
        case .evaluation: return "Evaluación"
        case .rubric: return "Rúbricas"
        default: return "el Cuaderno"
        }
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

    // MARK: Contenido curricular

    private func hasCurricularContent(_ draft: LearningSituationImportDraft) -> Bool {
        !draft.criteria.isEmpty
            || !draft.knowledge.isEmpty
            || !draft.methodology.isEmpty
            || !draft.inclusionMeasures.isEmpty
            || !(draft.documentTables ?? []).isEmpty
    }

    @ViewBuilder
    private func curriculumSection(for situation: LearningSituation) -> some View {
        if let draft = selectedDraft, hasCurricularContent(draft) {
            LearningSituationCard(title: "Contenido curricular") {
                VStack(alignment: .leading, spacing: 0) {
                    if !draft.criteria.isEmpty {
                        curriculumDisclosure(key: "criterios", title: "Criterios de evaluación (\(draft.criteria.count))") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(draft.criteria) { criterion in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(criterion.criterion)
                                            .font(.subheadline.weight(.semibold))
                                        if !criterion.evidence.isEmpty {
                                            Text(criterion.evidence)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    if !draft.knowledge.isEmpty {
                        curriculumDisclosure(key: "saberes", title: "Saberes básicos") {
                            bulletList(draft.knowledge)
                        }
                    }
                    if !draft.methodology.isEmpty {
                        curriculumDisclosure(key: "metodologia", title: "Metodología") {
                            bulletList(draft.methodology)
                        }
                    }
                    if !draft.inclusionMeasures.isEmpty {
                        curriculumDisclosure(key: "dua", title: "Diseño universal (DUA)") {
                            bulletList(draft.inclusionMeasures)
                        }
                    }
                    ForEach(draft.documentTables ?? []) { table in
                        curriculumDisclosure(key: "tabla-\(table.id)", title: table.title) {
                            documentTable(table)
                        }
                    }
                }
            }
        } else {
            LearningSituationCard(title: "Contenido curricular") {
                Text("Este documento no trae criterios ni saberes. Puedes importar una versión nueva del Word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Importar nueva versión") {
                    startImport(targetId: situation.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func curriculumDisclosure<Content: View>(
        key: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let body = content()
        return DisclosureGroup(isExpanded: Binding(
            get: { expandedCurriculumSections.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedCurriculumSections.insert(key)
                } else {
                    expandedCurriculumSections.remove(key)
                }
            }
        )) {
            body
                .padding(.bottom, 8)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: minimumTapSize, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
    }

    // MARK: Documento original

    private var documentSection: some View {
        LearningSituationCard(title: "Documento original") {
            if versions.isEmpty {
                Text("No hay documento guardado.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        if index > 0 { Divider() }
                        versionRow(version)
                    }
                }
            }
        }
    }

    private func versionRow(_ version: LearningSituationVersion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    versionTitle(version)
                    Spacer(minLength: 8)
                    versionShareLink(version)
                }
                VStack(alignment: .leading, spacing: 8) {
                    versionTitle(version)
                    versionShareLink(version)
                }
            }
            let warnings = decodeVersionWarnings(version.warningsJson)
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { warning in
                        Label {
                            Text(warning)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(IOSAppStyle.warning)
                        }
                    }
                }
            }
        }
    }

    private func versionTitle(_ version: LearningSituationVersion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(version.originalFileName)
                .font(.subheadline.weight(.semibold))
            Text("Versión \(version.versionNumber) · \(ByteCountFormatter.string(fromByteCount: version.sizeBytes, countStyle: .file))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func versionShareLink(_ version: LearningSituationVersion) -> some View {
        if let path = version.localPath {
            ShareLink(item: URL(fileURLWithPath: path)) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Compartir \(version.originalFileName)")
        }
    }

    func decodeVersionWarnings(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
}
