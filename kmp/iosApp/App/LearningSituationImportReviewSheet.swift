import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

struct LearningSituationBatchImportPresentation: Identifiable {
    let id = UUID()
    let drafts: [LearningSituationImportDraft]
    let failures: [LearningSituationDocumentImportFailure]
}

struct LearningSituationImportPreviewSheet: View {
    @State var draft: LearningSituationImportDraft
    let classes: [SchoolClass]
    let onConfirm: (LearningSituationImportDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ficha importada") {
                    TextField("Título", text: $draft.title)
                    TextField("Curso", text: $draft.courseLabel)
                    TextField("Materia", text: $draft.subjectLabel)
                    TextField("Trimestre", text: $draft.termLabel)
                    Stepper("Sesiones: \(draft.sessionCount)", value: $draft.sessionCount, in: 0...60)
                }
                Section("Asociar a grupos") {
                    ForEach(classes, id: \.id) { schoolClass in
                        Toggle("\(schoolClass.name) · \(schoolClass.course)º", isOn: Binding(
                            get: { draft.selectedClassIds.contains(schoolClass.id) },
                            set: { isOn in
                                if isOn { draft.selectedClassIds.insert(schoolClass.id) }
                                else { draft.selectedClassIds.remove(schoolClass.id) }
                            }
                        ))
                    }
                }
                Section("Contenido reconocido") {
                    Text("\(draft.criteria.count) criterios · \(draft.evaluationItems.count) elementos de evaluación")
                    if !draft.challenge.isEmpty { Text(draft.challenge).font(.footnote).foregroundStyle(.secondary) }
                }
                if !draft.warnings.isEmpty {
                    Section("Revisión necesaria") {
                        ForEach(draft.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                    }
                }
            }
            .navigationTitle("Revisar importación")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { onConfirm(draft) }
                        .disabled(draft.selectedClassIds.isEmpty || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 560)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

struct LearningSituationBatchImportPreviewSheet: View {
    @State private var drafts: [LearningSituationImportDraft]
    let failures: [LearningSituationDocumentImportFailure]
    let classes: [SchoolClass]
    let onConfirm: ([LearningSituationImportDraft]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        drafts: [LearningSituationImportDraft],
        failures: [LearningSituationDocumentImportFailure],
        classes: [SchoolClass],
        onConfirm: @escaping ([LearningSituationImportDraft]) -> Void
    ) {
        _drafts = State(initialValue: drafts)
        self.failures = failures
        self.classes = classes
        self.onConfirm = onConfirm
    }

    private var readyCount: Int {
        drafts.filter(canImport).count
    }

    private var canConfirm: Bool {
        readyCount == drafts.count && !drafts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resumen") {
                    Label(
                        "\(drafts.count) documentos listos para revisar",
                        systemImage: "doc.on.doc"
                    )
                    if !failures.isEmpty {
                        Text("\(failures.count) documento(s) no se han podido leer y no bloquearán los demás.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !failures.isEmpty {
                    Section("Documentos con errores") {
                        ForEach(failures) { failure in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.fileName)
                                    .font(.subheadline.weight(.semibold))
                                Text(failure.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Situaciones detectadas") {
                    ForEach($drafts) { $draft in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Título", text: $draft.title)
                                TextField("Curso", text: $draft.courseLabel)
                                TextField("Materia", text: $draft.subjectLabel)
                                TextField("Trimestre", text: $draft.termLabel)
                                Stepper("Sesiones: \(draft.sessionCount)", value: $draft.sessionCount, in: 0...60)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Asociar a grupos")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(classes, id: \.id) { schoolClass in
                                        Toggle(
                                            "\(schoolClass.name) · \(schoolClass.course)º",
                                            isOn: classBinding(for: $draft, classId: schoolClass.id)
                                        )
                                    }
                                }

                                Text("\(draft.criteria.count) criterios · \(draft.evaluationItems.count) elementos de evaluación")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                if !draft.warnings.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(draft.warnings, id: \.self) { warning in
                                            Label(warning, systemImage: "exclamationmark.triangle")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: canImport(draft) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(canImport(draft) ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(draft.sourceFileName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(draft.title.isEmpty ? "Sin título" : draft.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar situaciones")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar \(readyCount)") {
                        onConfirm(drafts)
                        dismiss()
                    }
                    .disabled(!canConfirm)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func canImport(_ draft: LearningSituationImportDraft) -> Bool {
        !draft.selectedClassIds.isEmpty
            && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
}
