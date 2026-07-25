import SwiftUI
import MiGestorKit

/// Fila plana para el borrado en lote, desacoplada de los tipos KMP
/// concretos (`SchoolClass`, `Subject`, `RubricDetail`, `LearningSituation`)
/// para que `BulkDeleteSection` no necesite genéricos ni protocolos extra.
struct DataManagementItem: Identifiable, Hashable {
    let id: Int64
    let title: String
    let subtitle: String?
}

/// Sección de Ajustes → Gestión de datos para un tipo de entidad: lista con
/// selección múltiple, borrado en lote con confirmación, y borrado
/// individual por swipe. Mismo patrón visual que el resto de "zonas de
/// riesgo" de Ajustes (`SettingsDangerZoneView`), pero pensado para vivir
/// varias veces en la misma pantalla (una por entidad).
struct BulkDeleteSection: View {
    let title: String
    let systemImage: String
    let items: [DataManagementItem]
    let emptyText: String
    let deleteWarning: String
    let onDeleteSelected: (Set<Int64>) async -> Void
    let onDeleteSingle: (Int64) async -> Void

    @State private var isSelectionMode = false
    @State private var selectedIds = Set<Int64>()
    @State private var pendingSingleDelete: DataManagementItem?
    @State private var showingBatchDeleteAlert = false
    @State private var isBusy = false

    var body: some View {
        Section {
            if items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    row(for: item)
                }
            }
        } header: {
            header
        } footer: {
            if !items.isEmpty {
                Text("\(items.count) en total\(selectedIds.isEmpty ? "" : " · \(selectedIds.count) seleccionada(s)")")
            }
        }
        .alert("Eliminar \(selectedIds.count) elemento(s)", isPresented: $showingBatchDeleteAlert) {
            Button("Eliminar", role: .destructive) {
                Task {
                    isBusy = true
                    await onDeleteSelected(selectedIds)
                    selectedIds.removeAll()
                    isSelectionMode = false
                    isBusy = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(deleteWarning)
        }
        .alert(
            "Eliminar",
            isPresented: Binding(
                get: { pendingSingleDelete != nil },
                set: { if !$0 { pendingSingleDelete = nil } }
            ),
            presenting: pendingSingleDelete
        ) { item in
            Button("Eliminar", role: .destructive) {
                Task {
                    isBusy = true
                    await onDeleteSingle(item.id)
                    isBusy = false
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text("¿Eliminar «\(item.title)»? \(deleteWarning)")
        }
    }

    private var header: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if isSelectionMode {
                Button("Eliminar (\(selectedIds.count))", role: .destructive) {
                    showingBatchDeleteAlert = true
                }
                .disabled(selectedIds.isEmpty || isBusy)
                Button("Cancelar") {
                    isSelectionMode = false
                    selectedIds.removeAll()
                }
            } else {
                Button("Seleccionar") {
                    isSelectionMode = true
                }
                .disabled(items.isEmpty)
            }
        }
    }

    private func row(for item: DataManagementItem) -> some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIds.contains(item.id) ? Color.accentColor : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelectionMode else { return }
            if selectedIds.contains(item.id) {
                selectedIds.remove(item.id)
            } else {
                selectedIds.insert(item.id)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelectionMode {
                Button(role: .destructive) {
                    pendingSingleDelete = item
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            }
        }
    }
}

/// Ajustes → Gestión de datos: borrado rápido y en lote de Cursos,
/// Asignaturas, Rúbricas y Situaciones de aprendizaje, separado de "Datos y
/// seguridad" (que es borrado nuclear de toda la app, una intención
/// distinta). No añade ningún método nuevo a `KmpBridge`: usa solo lo que
/// ya expone (`classes`, `subjects`, `rubrics`, `deleteClass`,
/// `deleteSubject`, `deleteRubric`, `learningSituations()`,
/// `deleteLearningSituation`).
struct DataManagementSettingsView: View {
    @EnvironmentObject var bridge: KmpBridge

    @State private var learningSituations: [LearningSituation] = []
    @State private var resultMessage: IdentifiableString?

    var body: some View {
        Form {
            BulkDeleteSection(
                title: "Cursos",
                systemImage: "person.3.fill",
                items: bridge.classes.map { schoolClass in
                    DataManagementItem(
                        id: schoolClass.id,
                        title: schoolClass.name,
                        subtitle: subjectName(forSubjectId: schoolClass.subjectId?.int64Value)
                    )
                },
                emptyText: "No hay cursos creados.",
                deleteWarning: "Se borrarán también su alumnado, asistencia, evaluaciones y notas asociadas. Esta acción no se puede deshacer.",
                onDeleteSelected: { ids in await deleteClasses(ids) },
                onDeleteSingle: { id in await deleteClasses([id]) }
            )

            BulkDeleteSection(
                title: "Asignaturas",
                systemImage: "books.vertical.fill",
                items: bridge.subjects.map { subject in
                    DataManagementItem(id: subject.id, title: subject.name, subtitle: subject.code)
                },
                emptyText: "No hay asignaturas creadas.",
                deleteWarning: "Los cursos que la usan quedarán sin asignatura asignada. Esta acción no se puede deshacer.",
                onDeleteSelected: { ids in await deleteSubjects(ids) },
                onDeleteSingle: { id in await deleteSubjects([id]) }
            )

            BulkDeleteSection(
                title: "Rúbricas",
                systemImage: "list.bullet.rectangle.fill",
                items: bridge.rubrics.map { detail in
                    DataManagementItem(id: detail.rubric.id, title: detail.rubric.name, subtitle: rubricSubtitle(for: detail.rubric.id))
                },
                emptyText: "No hay rúbricas creadas.",
                deleteWarning: "Las evaluaciones que la usan quedarán sin rúbrica asignada. Esta acción no se puede deshacer.",
                onDeleteSelected: { ids in await deleteRubrics(ids) },
                onDeleteSingle: { id in await deleteRubrics([id]) }
            )

            BulkDeleteSection(
                title: "Situaciones de aprendizaje",
                systemImage: "doc.text.fill",
                items: learningSituations.map { situation in
                    DataManagementItem(id: situation.id, title: situation.title, subtitle: situationSubtitle(for: situation))
                },
                emptyText: "No hay situaciones de aprendizaje creadas.",
                deleteWarning: "Esta acción no se puede deshacer.",
                onDeleteSelected: { ids in await deleteSituations(ids) },
                onDeleteSingle: { id in await deleteSituations([id]) }
            )
        }
        .navigationTitle("Gestión de datos")
        .task {
            await bridge.ensureClassesLoaded()
            try? await bridge.refreshRubrics()
            await reloadSituations()
        }
        .alert(item: $resultMessage) { message in
            Alert(title: Text("Aviso"), message: Text(message.value), dismissButton: .default(Text("OK")))
        }
    }

    private func subjectName(forSubjectId subjectId: Int64?) -> String {
        guard let subjectId, let subject = bridge.subjects.first(where: { $0.id == subjectId }) else {
            return "Sin asignatura"
        }
        return subject.name
    }

    private func rubricSubtitle(for rubricId: Int64) -> String {
        let linkedCount = bridge.rubricClassLinks[rubricId]?.count ?? 0
        return linkedCount == 0 ? "Sin vincular a ningún curso" : "Vinculada a \(linkedCount) curso(s)"
    }

    private func situationSubtitle(for situation: LearningSituation) -> String? {
        let parts = [situation.courseLabel, situation.subjectLabel].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func reloadSituations() async {
        learningSituations = (try? await bridge.learningSituations()) ?? []
    }

    private func deleteClasses(_ ids: Set<Int64>) async {
        var failed = 0
        for id in ids {
            do {
                try await bridge.deleteClass(id: id)
            } catch {
                failed += 1
            }
        }
        reportResult(deleted: ids.count - failed, failed: failed, entityPlural: "cursos")
    }

    private func deleteSubjects(_ ids: Set<Int64>) async {
        var failed = 0
        for id in ids {
            do {
                try await bridge.deleteSubject(id: id)
            } catch {
                failed += 1
            }
        }
        reportResult(deleted: ids.count - failed, failed: failed, entityPlural: "asignaturas")
    }

    /// `KmpBridge.deleteRubric(id:)` no es `async throws`: dispara un borrado
    /// en segundo plano en Kotlin que traga cualquier error internamente
    /// (`RubricsViewModel.deleteRubric`, fuera de alcance de esta tarea de
    /// UI). Se verifica el resultado real refrescando `bridge.rubrics` y
    /// comprobando cuáles de las seleccionadas siguen existiendo, en vez de
    /// asumir que el borrado siempre tuvo éxito.
    private func deleteRubrics(_ ids: Set<Int64>) async {
        for id in ids {
            bridge.deleteRubric(id: id)
        }
        try? await bridge.refreshRubrics()
        let stillPresent = Set(bridge.rubrics.map(\.rubric.id)).intersection(ids)
        reportResult(deleted: ids.count - stillPresent.count, failed: stillPresent.count, entityPlural: "rúbricas")
    }

    private func deleteSituations(_ ids: Set<Int64>) async {
        var failed = 0
        for id in ids {
            do {
                try await bridge.deleteLearningSituation(id: id)
            } catch {
                failed += 1
            }
        }
        await reloadSituations()
        reportResult(deleted: ids.count - failed, failed: failed, entityPlural: "situaciones de aprendizaje")
    }

    /// Solo interrumpe con un aviso cuando algo falló; el borrado exitoso es
    /// silencioso (la lista se refresca sola), igual que el resto de
    /// borrados de la app.
    private func reportResult(deleted: Int, failed: Int, entityPlural: String) {
        guard failed > 0 else { return }
        let total = deleted + failed
        if total == 1 {
            resultMessage = IdentifiableString(value: "No se pudo eliminar de \(entityPlural). Inténtalo de nuevo.")
        } else {
            resultMessage = IdentifiableString(value: "Se eliminaron \(deleted) de \(total) \(entityPlural). \(failed) no se pudieron eliminar.")
        }
    }
}
