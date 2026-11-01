import SwiftUI
import MiGestorKit

// MARK: - Grupos

struct PhysicalGroupsView: View {
    let snapshot: PhysicalTestsHomeSnapshot
    @Binding var selectedClassId: Int64?
    let onAdd: (Int64) -> Void
    let onOpenNotebook: (Int64) -> Void
    let onChanged: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var selection: Binding<String?> {
        Binding(
            get: { (selectedClassId ?? snapshot.groups.first?.id).map(String.init) },
            set: { selectedClassId = $0.flatMap(Int64.init) }
        )
    }

    var body: some View {
        PhysicalListDetail(
            isCompact: horizontalSizeClass == .compact,
            selection: selection,
            items: snapshot.groups.map { group in
                PhysicalListItem(
                    id: String(group.id),
                    title: group.schoolClass.name,
                    subtitle: "\(group.students.count) alumnos · " + (group.entries.isEmpty ? "sin pruebas" : group.entries.count == 1 ? "1 prueba" : "\(group.entries.count) pruebas"),
                    systemImage: "person.3",
                    badge: group.missing.isEmpty || group.entries.isEmpty ? nil : .warning("Faltan datos")
                )
            },
            emptyTitle: "Aún no tienes grupos",
            emptyMessage: "Crea un grupo para añadir pruebas a su cuaderno.",
            emptyAction: nil
        ) { id in
            if let group = snapshot.groups.first(where: { String($0.id) == id }) {
                PhysicalGroupDetail(
                    group: group,
                    onAdd: { onAdd(group.id) },
                    onOpenNotebook: { onOpenNotebook(group.id) },
                    onChanged: onChanged
                )
            }
        }
    }
}

struct PhysicalGroupDetail: View {
    let group: PhysicalGroupSummary
    let onAdd: () -> Void
    let onOpenNotebook: () -> Void
    let onChanged: () -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @State private var pendingRemoval: PhysicalGroupTestEntry?
    @State private var showsMissingNames = false
    @State private var errorText: String?

    private var terms: [String] {
        var seen: [String] = []
        for entry in group.entries where !seen.contains(entry.termLabel) { seen.append(entry.termLabel) }
        return seen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    titleBlock
                    Spacer()
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    HStack { actionButtons }
                }
            }

            if !group.missing.isEmpty && !group.entries.isEmpty {
                missingBanner
            }

            if group.entries.isEmpty {
                PhysicalCard(title: "Pruebas en el cuaderno") {
                    Text("Este grupo aún no tiene pruebas. Pulsa «Añadir prueba».")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(terms, id: \.self) { term in
                    PhysicalCard(title: term) {
                        let entries = group.entries.filter { $0.termLabel == term }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            entryRow(entry)
                        }
                    }
                }
                Text("Las marcas se apuntan en el Cuaderno: toca la celda de la prueba.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
        .confirmationDialog(
            "¿Quitar «\(pendingRemoval?.definition.name ?? "")» del cuaderno?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { entry in
            Button("Quitar y borrar sus marcas", role: .destructive) { remove(entry) }
            Button("Cancelar", role: .cancel) {}
        } message: { entry in
            Text(entry.markedCount > 0
                 ? "Se borran sus columnas y las \(entry.markedCount) marcas apuntadas. La prueba sigue en tu lista."
                 : "Se borran sus columnas. La prueba sigue en tu lista.")
        }
        .alert(errorText ?? "", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Vale", role: .cancel) {}
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.schoolClass.name).font(.largeTitle.bold())
            Text("\(group.students.count) alumnos · \(group.schoolClass.course)º curso")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Abrir cuaderno", action: onOpenNotebook)
            .buttonStyle(.bordered)
        Button("Añadir prueba", systemImage: "plus", action: onAdd)
            .buttonStyle(.borderedProminent)
    }

    private var missingBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(missingTitle).font(.headline)
                    Text(missingDetail).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            DisclosureGroup(showsMissingNames ? "Ocultar alumnos" : "Ver alumnos", isExpanded: $showsMissingNames) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.missing.withoutSex, id: \.id) { student in
                        Text("\(student.fullName) · sin sexo")
                    }
                    ForEach(group.missing.withoutBirthDate, id: \.id) { student in
                        Text("\(student.fullName) · sin fecha de nacimiento")
                    }
                    Text("Complétalo en su ficha (Alumnado).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }

    private var missingTitle: String {
        var parts: [String] = []
        let sex = group.missing.withoutSex.count
        let birth = group.missing.withoutBirthDate.count
        if sex > 0 { parts.append(sex == 1 ? "1 alumno sin sexo" : "\(sex) alumnos sin sexo") }
        if birth > 0 { parts.append(birth == 1 ? "1 sin fecha de nacimiento" : "\(birth) sin fecha de nacimiento") }
        return parts.joined(separator: " y ")
    }

    private var missingDetail: String {
        var lines: [String] = []
        if !group.missing.withoutSex.isEmpty {
            lines.append("El baremo distingue chicas y chicos: sin ese dato no hay nota.")
        }
        if !group.missing.withoutBirthDate.isEmpty {
            lines.append("Sin fecha de nacimiento se usa la edad habitual del curso.")
        }
        return lines.joined(separator: " ")
    }

    private func entryRow(_ entry: PhysicalGroupTestEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.definition.measurementKind == .time ? "stopwatch" : "ruler")
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.definition.name)
                Text(entryDetail(entry)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.hasScale ? "\(entry.scoredCount) de \(group.students.count)" : "\(entry.markedCount) de \(group.students.count)")
                    .font(.headline)
                    .monospacedDigit()
                Text(entry.hasScale ? "con nota" : "con marca")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Abrir cuaderno", systemImage: "tablecells", action: onOpenNotebook)
                Button("Quitar del cuaderno", systemImage: "trash", role: .destructive) { pendingRemoval = entry }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Más opciones de \(entry.definition.name)")
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Abrir cuaderno", systemImage: "tablecells", action: onOpenNotebook)
            Button("Quitar del cuaderno", systemImage: "trash", role: .destructive) { pendingRemoval = entry }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Quitar del cuaderno") { pendingRemoval = entry }
    }

    private func entryDetail(_ entry: PhysicalGroupTestEntry) -> String {
        var parts = [entry.definition.measurementLabel]
        if let tab = entry.tabTitle { parts.append("pestaña «\(tab)»") }
        if !entry.hasScale {
            parts.append("sin baremo: solo marca")
        } else if entry.scoreCountsTowardAverage {
            parts.append("cuenta \(NotebookPhysicalMark.decimalText(entry.scoreWeight)) % en la media")
        } else {
            parts.append("no cuenta en la media")
        }
        return parts.joined(separator: " · ")
    }

    private func remove(_ entry: PhysicalGroupTestEntry) {
        pendingRemoval = nil
        Task {
            do {
                try await bridge.removePhysicalTestFromNotebook(entry)
                onChanged()
            } catch {
                errorText = "No se pudo quitar «\(entry.definition.name)» del cuaderno."
            }
        }
    }
}

// MARK: - Baterías

struct PhysicalBatteriesView: View {
    let snapshot: PhysicalTestsHomeSnapshot
    @Binding var selectedBatteryId: String?
    let onAddToGroup: (PhysicalTestBattery) -> Void
    let onChanged: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        PhysicalListDetail(
            isCompact: horizontalSizeClass == .compact,
            selection: $selectedBatteryId,
            items: snapshot.batteries.map { battery in
                PhysicalListItem(
                    id: battery.id,
                    title: battery.name,
                    subtitle: battery.testIds.count == 1 ? "1 prueba" : "\(battery.testIds.count) pruebas",
                    systemImage: "square.stack",
                    badge: nil
                )
            },
            emptyTitle: "Sin baterías",
            emptyMessage: "Una batería es un conjunto de pruebas para añadirlas de golpe a un grupo. Es opcional.",
            emptyAction: nil
        ) { id in
            if let battery = snapshot.batteries.first(where: { $0.id == id }) {
                PhysicalBatteryDetail(
                    battery: battery,
                    definitions: snapshot.definitions,
                    scalesByTest: snapshot.scalesByTest,
                    onAddToGroup: { onAddToGroup(battery) },
                    onChanged: onChanged
                )
                .id(battery.id)
            }
        }
    }
}

struct PhysicalBatteryDetail: View {
    let battery: PhysicalTestBattery
    let definitions: [PhysicalTestDefinition]
    let scalesByTest: [String: [PhysicalTestScale]]
    let onAddToGroup: () -> Void
    let onChanged: () -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @State private var testIds: [String] = []
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @State private var errorText: String?

    private var available: [PhysicalTestDefinition] {
        definitions.filter { !testIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    titleBlock
                    Spacer()
                    Button("Añadir a un grupo…", action: onAddToGroup)
                        .buttonStyle(.bordered)
                        .disabled(testIds.isEmpty)
                }
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    Button("Añadir a un grupo…", action: onAddToGroup)
                        .buttonStyle(.bordered)
                        .disabled(testIds.isEmpty)
                }
            }

            PhysicalCard(title: "Pruebas", trailing: {
                Menu("Añadir prueba…") {
                    ForEach(available, id: \.id) { definition in
                        Button(definition.name) { save(testIds + [definition.id]) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(available.isEmpty)
            }) {
                if testIds.isEmpty {
                    Text("Añade las pruebas que quieras medir juntas.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(testIds.enumerated()), id: \.element) { index, id in
                        if index > 0 { Divider() }
                        testRow(id: id, index: index)
                    }
                }
            }
        }
        .onAppear {
            testIds = battery.testIds
            nameDraft = battery.name
        }
        .alert("Cambiar nombre", isPresented: $isRenaming) {
            TextField("Nombre", text: $nameDraft)
            Button("Cancelar", role: .cancel) { nameDraft = battery.name }
            Button("Guardar") { save(testIds, name: nameDraft) }
                .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert(errorText ?? "", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Vale", role: .cancel) {}
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(battery.name).font(.largeTitle.bold())
                Button("Cambiar nombre", systemImage: "pencil") { isRenaming = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Text("Un conjunto para añadir varias pruebas de golpe a un grupo.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func testRow(id: String, index: Int) -> some View {
        let definition = definitions.first { $0.id == id }
        let hasScale = !(scalesByTest[id] ?? []).isEmpty
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition?.name ?? "Prueba borrada")
                PhysicalBadge(badge: hasScale ? .ok("Baremo") : .warning("Sin baremo"))
            }
            Spacer()
            Button("Subir", systemImage: "chevron.up") { move(index, by: -1) }
                .labelStyle(.iconOnly)
                .disabled(index == 0)
                .frame(minWidth: 44, minHeight: 44)
            Button("Bajar", systemImage: "chevron.down") { move(index, by: 1) }
                .labelStyle(.iconOnly)
                .disabled(index == testIds.count - 1)
                .frame(minWidth: 44, minHeight: 44)
            Button("Quitar de la batería", systemImage: "minus.circle", role: .destructive) {
                save(testIds.filter { $0 != id })
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
    }

    private func move(_ index: Int, by delta: Int) {
        var ids = testIds
        let target = index + delta
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        save(ids)
    }

    private func save(_ ids: [String], name: String? = nil) {
        let previous = testIds
        testIds = ids
        Task {
            do {
                try await bridge.savePhysicalBattery(
                    id: battery.id,
                    name: name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? battery.name,
                    testIds: ids
                )
                onChanged()
            } catch {
                testIds = previous
                errorText = "No se pudo guardar la batería."
            }
        }
    }
}
