import SwiftUI
import MiGestorKit

/// Pantalla «Pruebas físicas»: crear pruebas, agruparlas en baterías y
/// añadirlas al cuaderno de cada grupo. Aquí no se mide: se mide en el Cuaderno.
struct PhysicalTestsHomeView: View {
    enum Section: String, CaseIterable, Identifiable {
        case tests = "Pruebas"
        case batteries = "Baterías"
        case groups = "Grupos"

        var id: String { rawValue }
    }

    @Binding var selectedClassId: Int64?
    let onOpenNotebook: (Int64) -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var section: Section = .tests
    @State private var snapshot = PhysicalTestsHomeSnapshot()
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTestId: String?
    @State private var selectedBatteryId: String?
    @State private var wizardRequest: PhysicalTestWizardRequest?
    @State private var addRequest: PhysicalAddToNotebookRequest?
    @State private var isCatalogPresented = false
    @State private var isNewBatteryPresented = false
    @State private var newBatteryName = ""
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.physicalHomeBackground)
        .task { await reload() }
        .sheet(item: $wizardRequest) { request in
            PhysicalTestSetupWizardSheet(
                bridge: bridge,
                initialClassId: nil,
                onSaved: { outcome in
                    selectedTestId = outcome.definitionId
                    Task { await reload() }
                },
                saveOnly: true,
                initialDefinitionId: request.definitionId
            )
        }
        .sheet(item: $addRequest) { request in
            PhysicalAddToNotebookSheet(
                snapshot: snapshot,
                initialClassId: request.classId ?? selectedClassId ?? snapshot.groups.first?.id,
                initialDefinitionIds: request.definitionIds,
                initialBatteryId: request.batteryId,
                onDone: { text in
                    message = text
                    Task { await reload() }
                }
            )
            .kmpBridgeEnvironment(bridge)
        }
        .sheet(isPresented: $isCatalogPresented) {
            PhysicalTestCatalogSheet(savedNames: Set(snapshot.definitions.map { $0.name.lowercased() })) { template in
                Task {
                    do {
                        selectedTestId = try await bridge.createPhysicalTest(from: template)
                        await reload()
                    } catch {
                        message = "No se pudo añadir «\(template.name)»."
                    }
                }
            }
        }
        .alert("Nueva batería", isPresented: $isNewBatteryPresented) {
            TextField("Nombre", text: $newBatteryName)
            Button("Cancelar", role: .cancel) { newBatteryName = "" }
            Button("Crear") { createBattery() }
                .disabled(newBatteryName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Después añádele las pruebas.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Vale", role: .cancel) {}
        }
    }

    // MARK: Cabecera

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text("Pruebas físicas").font(.title2.bold())
                Spacer(minLength: 16)
                sectionPicker.frame(maxWidth: 360)
                Spacer(minLength: 16)
                primaryButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pruebas físicas").font(.title2.bold())
                    Spacer()
                    primaryButton
                }
                sectionPicker
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var sectionPicker: some View {
        Picker("Sección", selection: $section) {
            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch section {
        case .tests:
            Menu {
                Button("Nueva prueba", systemImage: "plus") { wizardRequest = PhysicalTestWizardRequest(definitionId: nil) }
                Button("Desde el catálogo", systemImage: "books.vertical") { isCatalogPresented = true }
            } label: {
                Label("Nueva prueba", systemImage: "plus")
            } primaryAction: {
                wizardRequest = PhysicalTestWizardRequest(definitionId: nil)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
            .fixedSize()
        case .batteries:
            Button("Nueva batería", systemImage: "plus") { isNewBatteryPresented = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
        case .groups:
            Button("Añadir prueba", systemImage: "plus") {
                addRequest = PhysicalAddToNotebookRequest(classId: selectedClassId ?? snapshot.groups.first?.id)
            }
            .buttonStyle(.borderedProminent)
            .disabled(snapshot.groups.isEmpty)
        }
    }

    // MARK: Contenido

    @ViewBuilder
    private var content: some View {
        if isLoading && snapshot.definitions.isEmpty && snapshot.groups.isEmpty {
            ProgressView("Cargando pruebas…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView {
                Label("No se pudieron cargar las pruebas", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Reintentar") { Task { await reload() } }
            }
        } else {
            switch section {
            case .tests: testsSplit
            case .batteries:
                PhysicalBatteriesView(
                    snapshot: snapshot,
                    selectedBatteryId: $selectedBatteryId,
                    onAddToGroup: { battery in
                        addRequest = PhysicalAddToNotebookRequest(classId: selectedClassId, batteryId: battery.id)
                    },
                    onChanged: { Task { await reload() } }
                )
            case .groups:
                PhysicalGroupsView(
                    snapshot: snapshot,
                    selectedClassId: $selectedClassId,
                    onAdd: { classId in addRequest = PhysicalAddToNotebookRequest(classId: classId) },
                    onOpenNotebook: onOpenNotebook,
                    onChanged: { Task { await reload() } }
                )
            }
        }
    }

    private var testsSplit: some View {
        PhysicalListDetail(
            isCompact: horizontalSizeClass == .compact,
            selection: $selectedTestId,
            items: snapshot.definitions.map { definition in
                PhysicalListItem(
                    id: definition.id,
                    title: definition.name,
                    subtitle: "\(definition.capacityLabel) · \(definition.measurementLabel.lowercased())",
                    systemImage: definition.measurementKind == .time ? "stopwatch" : "ruler",
                    badge: snapshot.scales(for: definition.id).isEmpty ? .warning("Sin baremo") : .ok("Baremo")
                )
            },
            emptyTitle: "Aún no hay pruebas",
            emptyMessage: "Crea la primera o añádela desde el catálogo.",
            emptyAction: ("Nueva prueba", { wizardRequest = PhysicalTestWizardRequest(definitionId: nil) })
        ) { id in
            if let definition = snapshot.definitions.first(where: { $0.id == id }) {
                PhysicalTestDetail(
                    definition: definition,
                    scales: snapshot.scales(for: definition.id),
                    uses: snapshot.groups(using: definition.id),
                    onEditScale: { wizardRequest = PhysicalTestWizardRequest(definitionId: definition.id) },
                    onAddToGroup: { addRequest = PhysicalAddToNotebookRequest(classId: nil, definitionIds: [definition.id]) },
                    onOpenNotebook: onOpenNotebook
                )
            }
        }
    }

    // MARK: Acciones

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await bridge.loadPhysicalTestsHome()
            loadError = nil
            if selectedTestId == nil || !snapshot.definitions.contains(where: { $0.id == selectedTestId }) {
                selectedTestId = snapshot.definitions.first?.id
            }
            if selectedBatteryId == nil || !snapshot.batteries.contains(where: { $0.id == selectedBatteryId }) {
                selectedBatteryId = snapshot.batteries.first?.id
            }
        } catch {
            if snapshot.definitions.isEmpty && snapshot.groups.isEmpty {
                loadError = error.localizedDescription
            } else {
                message = PhysicalTestsReload.failure
            }
        }
    }

    private func createBattery() {
        let name = newBatteryName.trimmingCharacters(in: .whitespacesAndNewlines)
        newBatteryName = ""
        guard !name.isEmpty else { return }
        Task {
            do {
                try await bridge.savePhysicalBattery(id: nil, name: name, testIds: [])
                await reload()
                selectedBatteryId = snapshot.batteries.first { $0.name == name }?.id
            } catch {
                message = "No se pudo crear la batería."
            }
        }
    }
}

struct PhysicalTestWizardRequest: Identifiable {
    let id = UUID()
    let definitionId: String?
}

struct PhysicalAddToNotebookRequest: Identifiable {
    let id = UUID()
    var classId: Int64?
    var definitionIds: [String] = []
    var batteryId: String?
}

// MARK: - Lista y detalle

enum PhysicalListBadge: Equatable {
    case ok(String)
    case warning(String)
    case plain(String)
}

struct PhysicalListItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let badge: PhysicalListBadge?
}

/// Lista a la izquierda y detalle a la derecha; en pantallas estrechas, lista que navega al detalle.
struct PhysicalListDetail<Detail: View>: View {
    let isCompact: Bool
    @Binding var selection: String?
    let items: [PhysicalListItem]
    let emptyTitle: String
    let emptyMessage: String
    let emptyAction: (String, () -> Void)?
    @ViewBuilder let detail: (String) -> Detail

    @State private var searchText = ""

    private var filtered: [PhysicalListItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "figure.run")
            } description: {
                Text(emptyMessage)
            } actions: {
                if let emptyAction {
                    Button(emptyAction.0, action: emptyAction.1).buttonStyle(.borderedProminent)
                }
            }
        } else if isCompact {
            NavigationStack {
                List(filtered) { item in
                    NavigationLink { detail(item.id) } label: { PhysicalListRow(item: item) }
                }
                .searchable(text: $searchText, prompt: "Buscar")
            }
        } else {
            HStack(spacing: 0) {
                List(filtered, selection: $selection) { item in
                    PhysicalListRow(item: item).tag(item.id)
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Buscar")
                .frame(width: 320)
                Divider()
                ScrollView {
                    if let selection {
                        detail(selection)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct PhysicalListRow: View {
    let item: PhysicalListItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let badge = item.badge {
                PhysicalBadge(badge: badge)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct PhysicalBadge: View {
    let badge: PhysicalListBadge

    var body: some View {
        switch badge {
        case .ok(let text):
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .warning(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        case .plain(let text):
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detalle de una prueba

struct PhysicalTestDetail: View {
    let definition: PhysicalTestDefinition
    let scales: [PhysicalTestScale]
    let uses: [(group: PhysicalGroupSummary, entry: PhysicalGroupTestEntry)]
    let onEditScale: () -> Void
    let onAddToGroup: () -> Void
    let onOpenNotebook: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name).font(.largeTitle.bold())
                Text("\(definition.capacityLabel) · \(definition.measurementLabel.lowercased())")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            PhysicalCard(title: "Cómo se mide") {
                LabeledContent("Medida", value: measureText)
                Divider()
                LabeledContent("Mejor marca", value: definition.betterLabel)
                Divider()
                LabeledContent("Intentos", value: definition.attempts > 1 ? "\(definition.attempts) · se queda la mejor" : "1")
            }

            PhysicalCard(title: "Baremo", trailing: {
                Button(scales.isEmpty ? "Añadir baremo" : "Cambiar baremo", action: onEditScale)
            }) {
                if scales.isEmpty {
                    Label("Sin baremo: el Cuaderno guarda la marca pero no puede poner nota.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label(PhysicalScaleText.coverage(scales), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    ForEach(PhysicalScaleText.sorted(scales), id: \.id) { scale in
                        Divider()
                        PhysicalScaleRow(scale: scale, kind: definition.measurementKind)
                    }
                }
            }

            PhysicalCard(title: "En los cuadernos", trailing: {
                Button("Añadir a un grupo…", action: onAddToGroup)
            }) {
                if uses.isEmpty {
                    Text("Todavía no está en ningún cuaderno.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(uses.enumerated()), id: \.element.entry.id) { index, use in
                        if index > 0 { Divider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(use.group.schoolClass.name)
                                Text([use.entry.termLabel, use.entry.tabTitle].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Abrir cuaderno") { onOpenNotebook(use.group.schoolClass.id) }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
    }

    private var measureText: String {
        switch definition.measurementKind {
        case .time: return "Tiempo (min:s)"
        default: return "\(definition.measurementLabel) (\(definition.unit))"
        }
    }
}

struct PhysicalCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.physicalCardBackground))
        }
    }
}

extension PhysicalCard where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

struct PhysicalScaleRow: View {
    let scale: PhysicalTestScale
    let kind: PhysicalMeasurementKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PhysicalScaleText.who(scale)).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 4) { chips }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PhysicalScaleText.spoken(scale, kind: kind))
    }

    private var chips: some View {
        ForEach(PhysicalScaleText.ranges(scale), id: \.id) { range in
            HStack(spacing: 4) {
                Text(PhysicalScaleText.decimal(range.score)).fontWeight(.semibold)
                Text(PhysicalScaleText.span(range, kind: kind)).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }
}

/// Textos del baremo para la pantalla y para VoiceOver.
enum PhysicalScaleText {
    static func sorted(_ scales: [PhysicalTestScale]) -> [PhysicalTestScale] {
        scales.sorted {
            let lhs = ($0.course?.intValue ?? 0, $0.ageFrom?.intValue ?? 0, $0.sex ?? "")
            let rhs = ($1.course?.intValue ?? 0, $1.ageFrom?.intValue ?? 0, $1.sex ?? "")
            return lhs < rhs
        }
    }

    static func ranges(_ scale: PhysicalTestScale) -> [MiGestorKit.PhysicalTestScaleRange] {
        scale.ranges.sorted { $0.score > $1.score }
    }

    static func who(_ scale: PhysicalTestScale) -> String {
        var parts: [String] = []
        if let course = scale.course?.intValue { parts.append("\(course)º ESO") }
        if let from = scale.ageFrom?.intValue, let to = scale.ageTo?.intValue {
            parts.append(from == to ? "\(from) años" : "\(from)-\(to) años")
        } else if let from = scale.ageFrom?.intValue {
            parts.append("desde \(from) años")
        } else if let to = scale.ageTo?.intValue {
            parts.append("hasta \(to) años")
        }
        switch scale.sex?.uppercased() {
        case "FEMALE": parts.append("chicas")
        case "MALE": parts.append("chicos")
        default: break
        }
        return parts.isEmpty ? "Todo el alumnado" : parts.joined(separator: " · ")
    }

    static func coverage(_ scales: [PhysicalTestScale]) -> String {
        let courses = Set(scales.compactMap { $0.course?.intValue }).sorted()
        let sexes = Set(scales.compactMap { $0.sex?.uppercased() })
        var text = scales.count == 1 ? "1 tabla" : "\(scales.count) tablas"
        if let first = courses.first, let last = courses.last {
            text += first == last ? " · \(first)º ESO" : " · \(first)º a \(last)º ESO"
        }
        if sexes.contains("FEMALE") && sexes.contains("MALE") { text += " · chicas y chicos" }
        return text
    }

    static func decimal(_ value: Double) -> String {
        NotebookPhysicalMark.decimalText(value)
    }

    static func mark(_ value: Double, kind: PhysicalMeasurementKind) -> String {
        kind == .time
            ? NotebookPhysicalMark.compactTime(NotebookPhysicalMark.timeText(seconds: value))
            : decimal(value)
    }

    static func span(_ range: MiGestorKit.PhysicalTestScaleRange, kind: PhysicalMeasurementKind) -> String {
        switch (range.minValue?.doubleValue, range.maxValue?.doubleValue) {
        case let (min?, max?): return "\(mark(min, kind: kind))–\(mark(max, kind: kind))"
        case let (nil, max?): return "≤ \(mark(max, kind: kind))"
        case let (min?, nil): return "≥ \(mark(min, kind: kind))"
        default: return "cualquiera"
        }
    }

    static func spoken(_ scale: PhysicalTestScale, kind: PhysicalMeasurementKind) -> String {
        let parts = ranges(scale).map { "\(decimal($0.score)) puntos: \(span($0, kind: kind))" }
        return "\(who(scale)). " + parts.joined(separator: "; ")
    }
}

// MARK: - Catálogo

struct PhysicalTestCatalogSheet: View {
    let savedNames: Set<String>
    let onPick: (PhysicalTestTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PhysicalTestTemplate.defaults) { template in
                let saved = savedNames.contains(template.name.lowercased())
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).font(.headline)
                        Text("\(template.capacity.rawValue) · \(template.measurement.rawValue.lowercased()) · \(template.protocolText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 16)
                    if saved {
                        Text("Ya está").foregroundStyle(.secondary)
                    } else {
                        Button("Añadir") {
                            onPick(template)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Catálogo de pruebas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}

extension Color {
    static var physicalHomeBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var physicalCardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
