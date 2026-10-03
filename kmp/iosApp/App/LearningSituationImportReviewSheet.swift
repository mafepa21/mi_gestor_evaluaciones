import SwiftUI
import MiGestorKit

/// Qué se está revisando: documentos nuevos (uno o varios) o la ficha de una situación.
enum LearningSituationImportReviewMode {
    case importDocuments
    case editSheet
}

/// Presentación única de «Revisar importación» / «Editar ficha». Un documento es un lote de 1.
struct LearningSituationImportReviewPresentation: Identifiable {
    let id = UUID()
    let mode: LearningSituationImportReviewMode
    let drafts: [LearningSituationImportDraft]
    let failures: [LearningSituationDocumentImportFailure]
}

/// Hoja única para revisar la importación de 1 o varios documentos Word y para editar la
/// ficha de una situación. Los grupos se eligen una vez y se aplican a todas.
struct LearningSituationImportReviewSheet: View {
    let mode: LearningSituationImportReviewMode
    let failures: [LearningSituationDocumentImportFailure]
    let classes: [SchoolClass]
    let onConfirm: ([LearningSituationImportDraft]) -> Void
    let onChooseOtherDocuments: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [LearningSituationImportDraft]
    @State private var isConfirming = false
    @State private var expandedDraftIds: Set<LearningSituationImportDraft.ID>
    @ScaledMetric(relativeTo: .body) private var minimumTapSize: CGFloat = 44

    init(
        presentation: LearningSituationImportReviewPresentation,
        classes: [SchoolClass],
        preselectedClassId: Int64?,
        onConfirm: @escaping ([LearningSituationImportDraft]) -> Void,
        onChooseOtherDocuments: @escaping () -> Void
    ) {
        mode = presentation.mode
        failures = presentation.failures
        self.classes = classes
        self.onConfirm = onConfirm
        self.onChooseOtherDocuments = onChooseOtherDocuments
        var initialDrafts = presentation.drafts
        // Al importar, el grupo con el que se trabaja en el módulo viene ya marcado.
        if presentation.mode == .importDocuments,
           let preselectedClassId,
           classes.contains(where: { $0.id == preselectedClassId }) {
            for index in initialDrafts.indices where initialDrafts[index].selectedClassIds.isEmpty {
                initialDrafts[index].selectedClassIds = [preselectedClassId]
            }
        }
        _drafts = State(initialValue: initialDrafts)
        // Con un solo documento la ficha se ve abierta; en lote, cerrada.
        _expandedDraftIds = State(initialValue: initialDrafts.count == 1 ? Set(initialDrafts.map(\.id)) : [])
    }

    private var isBatch: Bool { drafts.count > 1 }

    private var readyCount: Int { drafts.filter(isReady).count }

    private var canConfirm: Bool { !drafts.isEmpty && readyCount == drafts.count }

    private var navigationTitle: String {
        mode == .editSheet ? "Editar ficha" : "Revisar importación"
    }

    private var confirmTitle: String {
        switch mode {
        case .editSheet: return "Guardar"
        case .importDocuments: return isBatch ? "Importar \(drafts.count)" : "Importar"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if drafts.isEmpty {
                    allFailedSection
                } else {
                    groupsSection
                    if !failures.isEmpty {
                        failuresSection
                    }
                    draftsSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: Secciones

    private var allFailedSection: some View {
        Section {
            LearningSituationInlineNotice(
                kind: .error,
                message: "No se pudo leer ningún documento. Comprueba que son archivos .docx válidos."
            )
            ForEach(failures) { failure in
                failureRow(failure)
            }
            Button("Elegir otros documentos") {
                dismiss()
                onChooseOtherDocuments()
            }
            .frame(minHeight: minimumTapSize)
        }
    }

    private var groupsSection: some View {
        Section {
            if classes.isEmpty {
                Text("No hay grupos creados. Crea un grupo antes de importar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(classes, id: \.id) { schoolClass in
                    Toggle("\(schoolClass.name) · \(schoolClass.course)º", isOn: sharedClassBinding(schoolClass.id))
                }
            }
        } header: {
            Text(isBatch ? "Grupos (se aplican a todas)" : "Grupos")
        } footer: {
            if isBatch {
                Text("Marca un grupo para asignarlo a todas las situaciones. Puedes ajustarlo en cada una.")
            }
        }
    }

    private var failuresSection: some View {
        Section {
            LearningSituationInlineNotice(
                kind: .warning,
                message: failures.count == 1
                    ? "1 documento no se pudo leer. Se importarán los otros \(drafts.count)."
                    : "\(failures.count) documentos no se pudieron leer. Se importarán los otros \(drafts.count)."
            )
            ForEach(failures) { failure in
                failureRow(failure)
            }
        } header: {
            Text("Documentos con fallo")
        }
    }

    private var draftsSection: some View {
        Section {
            ForEach($drafts) { $draft in
                if isBatch {
                    DisclosureGroup(isExpanded: expandedBinding(draft.id)) {
                        draftFields($draft)
                    } label: {
                        draftSummaryRow(draft)
                    }
                } else {
                    draftSummaryRow(draft)
                    draftFields($draft)
                }
            }
        } header: {
            Text(isBatch ? "Situaciones detectadas" : "Ficha")
        }
    }

    // MARK: Filas

    private func draftSummaryRow(_ draft: LearningSituationImportDraft) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? "Sin título" : draft.title)
                    .font(.headline)
                Text(draftSummary(draft))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            readinessBadge(for: draft)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func draftFields(_ draft: Binding<LearningSituationImportDraft>) -> some View {
        TextField("Título", text: draft.title)
        TextField("Curso", text: draft.courseLabel)
        TextField("Materia", text: draft.subjectLabel)
        TextField("Trimestre", text: draft.termLabel)
        Stepper("Sesiones: \(draft.wrappedValue.sessionCount)", value: draft.sessionCount, in: 0...60)
        if isBatch && !classes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grupos de esta situación")
                    .font(.subheadline.weight(.semibold))
                ForEach(classes, id: \.id) { schoolClass in
                    Toggle(
                        "\(schoolClass.name) · \(schoolClass.course)º",
                        isOn: classBinding(for: draft, classId: schoolClass.id)
                    )
                }
            }
        }
        if !draft.wrappedValue.challenge.isEmpty {
            Text(draft.wrappedValue.challenge)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        ForEach(draft.wrappedValue.warnings, id: \.self) { warning in
            LearningSituationInlineNotice(kind: .warning, message: "\(warning) Puedes corregirlo después.")
        }
        if draft.wrappedValue.selectedClassIds.isEmpty {
            LearningSituationInlineNotice(kind: .info, message: "Elige al menos un grupo.")
        }
    }

    private func failureRow(_ failure: LearningSituationDocumentImportFailure) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.fileName)
                    .font(.subheadline.weight(.semibold))
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            statusLabel("Fallo", systemImage: "xmark.octagon.fill", tint: EvaluationDesign.danger)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func readinessBadge(for draft: LearningSituationImportDraft) -> some View {
        if !isReady(draft) {
            statusLabel("Falta grupo", systemImage: "exclamationmark.circle", tint: IOSAppStyle.warning)
        } else if !draft.warnings.isEmpty {
            statusLabel("Aviso", systemImage: "exclamationmark.triangle.fill", tint: IOSAppStyle.warning)
        } else {
            statusLabel("Lista", systemImage: "checkmark.circle.fill", tint: EvaluationDesign.success)
        }
    }

    private func statusLabel(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .fixedSize()
    }

    // MARK: Pie

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                footerStatus
                Spacer(minLength: 8)
                confirmButton
            }
            VStack(alignment: .leading, spacing: 8) {
                footerStatus
                confirmButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footerStatus: some View {
        Text(footerMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var confirmButton: some View {
        Button(confirmTitle) {
            // Evita la doble pulsación mientras se guarda; se libera por si la importación falla.
            isConfirming = true
            onConfirm(drafts)
            if isBatch { dismiss() }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isConfirming = false
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!canConfirm || isConfirming)
    }

    private var footerMessage: String {
        if drafts.isEmpty { return "Nada que importar" }
        if drafts.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Falta el título de alguna situación"
        }
        if readyCount < drafts.count {
            return isBatch ? "\(readyCount) de \(drafts.count) listas · falta elegir grupo" : "Falta elegir un grupo"
        }
        let groupCount = Set(drafts.flatMap(\.selectedClassIds)).count
        let groupLabel = groupCount == 1 ? "1 grupo" : "\(groupCount) grupos"
        if mode == .editSheet { return "Lista para guardar · \(groupLabel)" }
        return isBatch ? "\(drafts.count) listas · \(groupLabel)" : "Lista para importar · \(groupLabel)"
    }

    // MARK: Lógica de presentación

    private func isReady(_ draft: LearningSituationImportDraft) -> Bool {
        !draft.selectedClassIds.isEmpty
            && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func draftSummary(_ draft: LearningSituationImportDraft) -> String {
        var parts = [draft.subjectLabel, draft.courseLabel, draft.termLabel].filter { !$0.isEmpty }
        parts.append(draft.sessionCount == 1 ? "1 sesión" : "\(draft.sessionCount) sesiones")
        parts.append(draft.criteria.count == 1 ? "1 criterio" : "\(draft.criteria.count) criterios")
        if isBatch && !draft.sourceFileName.isEmpty {
            parts.append(draft.sourceFileName)
        }
        return parts.joined(separator: " · ")
    }

    /// Marcado si el grupo está en todas; al cambiarlo se asigna o se quita en todas.
    private func sharedClassBinding(_ classId: Int64) -> Binding<Bool> {
        Binding(
            get: { !drafts.isEmpty && drafts.allSatisfy { $0.selectedClassIds.contains(classId) } },
            set: { isOn in
                for index in drafts.indices {
                    if isOn {
                        drafts[index].selectedClassIds.insert(classId)
                    } else {
                        drafts[index].selectedClassIds.remove(classId)
                    }
                }
            }
        )
    }

    private func classBinding(
        for draft: Binding<LearningSituationImportDraft>,
        classId: Int64
    ) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.selectedClassIds.contains(classId) },
            set: { isSelected in
                if isSelected {
                    draft.wrappedValue.selectedClassIds.insert(classId)
                } else {
                    draft.wrappedValue.selectedClassIds.remove(classId)
                }
            }
        )
    }

    private func expandedBinding(_ id: LearningSituationImportDraft.ID) -> Binding<Bool> {
        Binding(
            get: { expandedDraftIds.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedDraftIds.insert(id) } else { expandedDraftIds.remove(id) }
            }
        )
    }
}
