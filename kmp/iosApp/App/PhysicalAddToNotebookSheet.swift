import SwiftUI
import MiGestorKit

/// Añade pruebas o baterías al cuaderno de un grupo. Cada prueba es una sola
/// columna «marca | nota»; lo que ya está en esa evaluación no se duplica.
struct PhysicalAddToNotebookSheet: View {
    let snapshot: PhysicalTestsHomeSnapshot
    let onDone: (String) -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var classId: Int64?
    @State private var term: String = PhysicalTestNotebookPlacement.terms[0]
    @State private var tabs: [NotebookTab] = []
    @State private var tabSelection = PhysicalAddToNotebookSheet.newTabTitle
    @State private var pickedTests: Set<String>
    @State private var pickedBatteries: Set<String>
    @State private var countsTowardAverage = true
    @State private var isSaving = false
    @State private var saveError: String?

    static let newTabTitle = "Condición física"

    init(
        snapshot: PhysicalTestsHomeSnapshot,
        initialClassId: Int64?,
        initialDefinitionIds: [String],
        initialBatteryId: String?,
        onDone: @escaping (String) -> Void
    ) {
        self.snapshot = snapshot
        self.onDone = onDone
        _classId = State(initialValue: initialClassId ?? snapshot.groups.first?.id)
        _pickedTests = State(initialValue: Set(initialDefinitionIds))
        _pickedBatteries = State(initialValue: initialBatteryId.map { [$0] } ?? [])
    }

    private var group: PhysicalGroupSummary? {
        snapshot.groups.first { $0.id == classId }
    }

    /// Pruebas elegidas, sueltas o dentro de baterías, sin repetir y en orden.
    private var selectedDefinitions: [PhysicalTestDefinition] {
        var ids: [String] = []
        for battery in snapshot.batteries where pickedBatteries.contains(battery.id) {
            for id in battery.testIds where !ids.contains(id) { ids.append(id) }
        }
        for definition in snapshot.definitions where pickedTests.contains(definition.id) && !ids.contains(definition.id) {
            ids.append(definition.id)
        }
        return ids.compactMap { id in snapshot.definitions.first { $0.id == id } }
    }

    private var alreadyThere: [PhysicalTestDefinition] {
        let entries = group?.entries ?? []
        return selectedDefinitions.filter { definition in
            entries.contains { $0.definition.id == definition.id && $0.assignment.termLabel == term }
        }
    }

    private var toAdd: [PhysicalTestDefinition] {
        let skip = Set(alreadyThere.map(\.id))
        return selectedDefinitions.filter { !skip.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dónde") {
                    Picker("Grupo", selection: $classId) {
                        ForEach(snapshot.groups) { group in
                            Text(group.schoolClass.name).tag(Optional(group.id))
                        }
                    }
                    Picker("Evaluación", selection: $term) {
                        ForEach(PhysicalTestNotebookPlacement.terms, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Pestaña del cuaderno", selection: $tabSelection) {
                        ForEach(tabs, id: \.id) { Text($0.title).tag($0.id) }
                        if !tabs.contains(where: { $0.title.caseInsensitiveCompare(Self.newTabTitle) == .orderedSame }) {
                            Text("Nueva: \(Self.newTabTitle)").tag(Self.newTabTitle)
                        }
                    }
                }

                Section("Pruebas") {
                    if snapshot.definitions.isEmpty {
                        Text("Aún no hay pruebas. Créalas en «Pruebas».").foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.definitions, id: \.id) { definition in
                        pickRow(
                            title: definition.name,
                            detail: definition.measurementLabel,
                            badge: snapshot.scales(for: definition.id).isEmpty ? .warning("Sin baremo") : .ok("Baremo"),
                            isOn: pickedTests.contains(definition.id)
                        ) { toggle(&pickedTests, definition.id) }
                    }
                }

                if !snapshot.batteries.isEmpty {
                    Section("Baterías") {
                        ForEach(snapshot.batteries, id: \.id) { battery in
                            pickRow(
                                title: battery.name,
                                detail: battery.testIds.count == 1 ? "1 prueba" : "\(battery.testIds.count) pruebas",
                                badge: nil,
                                isOn: pickedBatteries.contains(battery.id)
                            ) { toggle(&pickedBatteries, battery.id) }
                        }
                    }
                }

                Section {
                    Toggle("La nota cuenta para la media", isOn: $countsTowardAverage)
                } header: {
                    Text("Media")
                } footer: {
                    Text("El peso se ajusta después en «Editar media» del Cuaderno.")
                }

                Section {
                    summary
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Añadir al cuaderno")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().accessibilityLabel("Añadiendo")
                    } else {
                        Button("Añadir") { Task { await save() } }
                            .disabled(toAdd.isEmpty || classId == nil)
                    }
                }
            }
            .task(id: classId) { await loadTabs() }
        }
        .interactiveDismissDisabled(isSaving)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    @ViewBuilder
    private var summary: some View {
        let names = toAdd.map(\.name)
        VStack(alignment: .leading, spacing: 8) {
            if selectedDefinitions.isEmpty {
                Text("Elige al menos una prueba o batería.").foregroundStyle(.secondary)
            } else if names.isEmpty {
                Text("Todo lo elegido ya está en el cuaderno de \(group?.schoolClass.name ?? "este grupo") en la \(term).")
            } else {
                Text(names.count == 1 ? "Se creará 1 columna: \(names[0])." : "Se crearán \(names.count) columnas: \(names.joined(separator: ", ")).")
                    .font(.headline)
                Text("Cada una muestra «marca | nota». Se mide tocando la celda.")
                    .foregroundStyle(.secondary)
            }
            if !alreadyThere.isEmpty && !names.isEmpty {
                Text("Ya están y no se repiten: \(alreadyThere.map(\.name).joined(separator: ", ")).")
                    .foregroundStyle(.secondary)
            }
            let noScale = toAdd.filter { snapshot.scales(for: $0.id).isEmpty }.map(\.name)
            if !noScale.isEmpty {
                Label("\(noScale.joined(separator: ", ")) no tiene baremo: solo guardará la marca.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pickRow(title: String, detail: String, badge: PhysicalListBadge?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let badge { PhysicalBadge(badge: badge) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        AppleInteractionFeedback.play(.selection)
    }

    private func loadTabs() async {
        guard let classId else { tabs = []; return }
        tabs = (try? await bridge.listNotebookTabsForClass(classId: classId)) ?? []
        if tabs.contains(where: { $0.id == tabSelection }) { return }
        tabSelection = tabs.first { tab in
            tab.title.localizedCaseInsensitiveContains("condición") || tab.title.localizedCaseInsensitiveContains("física")
        }?.id ?? Self.newTabTitle
    }

    private func save() async {
        guard let classId, let group else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let outcome = try await bridge.addPhysicalTestsToNotebook(
                classId: classId,
                definitions: toAdd,
                termLabel: term,
                notebookTab: tabSelection,
                countsTowardAverage: countsTowardAverage,
                existing: group.entries
            )
            AppleInteractionFeedback.play(.success)
            let count = outcome.added.count
            onDone(count == 1
                   ? "Añadida «\(outcome.added[0])» al cuaderno de \(group.schoolClass.name)."
                   : "Añadidas \(count) pruebas al cuaderno de \(group.schoolClass.name).")
            dismiss()
        } catch {
            AppleInteractionFeedback.play(.error)
            saveError = "No se pudieron añadir: \(error.localizedDescription)"
        }
    }
}
