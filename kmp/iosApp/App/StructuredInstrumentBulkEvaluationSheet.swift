import SwiftUI
import MiGestorKit

/// Petición para evaluar en masa una columna de instrumento estructurado (lista de cotejo,
/// rejilla de observación) para todo el grupo visible del Cuaderno.
struct StructuredInstrumentBulkRequest: Identifiable {
    struct Student: Identifiable, Hashable {
        let id: Int64
        let name: String
    }

    let id: String
    let classId: Int64
    let columnId: String
    let title: String
    let students: [Student]
}

/// Hoja de evaluación masiva de una lista de cotejo: alumnos en filas e ítems en columnas.
/// Reutiliza la carga y el guardado por alumno del puente (`loadStructuredInstrumentEvaluation`
/// y `saveStructuredInstrumentEvaluation`), así que la nota que cuenta para la media se sigue
/// calculando en Kotlin al guardar. La nota de cada fila aquí es solo informativa y sigue la
/// misma regla que `ObservationGridInstrumentContent` (media de las sesiones respondidas).
/// Solo los ítems 1-4 y de casilla se editan aquí; el resto (texto, número, opción) se ve en
/// la hoja individual.
struct StructuredInstrumentBulkEvaluationSheet: View {
    let bridge: KmpBridge
    let request: StructuredInstrumentBulkRequest
    let onSaved: (_ studentIds: [Int64]) -> Void
    let onClose: () -> Void

    @State private var models: [Int64: StructuredInstrumentEvaluationModel] = [:]
    @State private var original: [Int64: [String]] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var failedStudentIds: [Int64] = []
    @State private var selectedGroupId: String = Self.allGroupsId
    @State private var applyAllItemIndex: Int?
    @State private var applyAllValue: String = "4"

    private static let allGroupsId = "__todas__"

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(request.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar", action: onClose)
                            .instrumentEvaluationGlassButton()
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Label("Guardar", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .disabled(isSaving || changedStudentIds.isEmpty)
                        .instrumentEvaluationGlassButton(isProminent: true)
                    }
                }
        }
        .task { await load() }
        .confirmationDialog(
            applyAllTitle,
            isPresented: Binding(
                get: { applyAllItemIndex != nil },
                set: { if !$0 { applyAllItemIndex = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let index = applyAllItemIndex {
                Button("Solo a los vacíos") { applyToAll(itemIndex: index, overwrite: false) }
                Button("Sobrescribir a todos", role: .destructive) { applyToAll(itemIndex: index, overwrite: true) }
                Button("Cancelar", role: .cancel) {}
            }
        } message: {
            Text("Se pondrá «\(applyAllDisplayValue)». Los cambios no se guardan hasta pulsar Guardar.")
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Cargando alumnado…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            NotebookContentUnavailableView("No se pudo abrir la evaluación", systemImage: "exclamationmark.triangle", description: loadError)
        } else if request.students.isEmpty {
            NotebookContentUnavailableView("Este grupo no tiene alumnos", systemImage: "person.3", description: "Añade alumnado al grupo para evaluar en masa.")
        } else if templateItems.isEmpty {
            NotebookContentUnavailableView(
                "Sin plantilla",
                systemImage: "doc.badge.gearshape",
                description: "Esta columna todavía no tiene plantilla estructurada en este dispositivo. Si la importaste en otro, sincroniza con Sync LAN."
            )
        } else {
            VStack(spacing: 0) {
                if !failedStudentIds.isEmpty {
                    failureBanner
                }
                if let groups = sessionGroups {
                    sessionPicker(groups)
                }
                grid
                footer
            }
        }
    }

    private var failureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("No se pudieron guardar \(failedStudentIds.count) alumnos. Tus respuestas siguen aquí.")
                .font(.subheadline)
            Spacer()
            Button("Reintentar") { Task { await save() } }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    private func sessionPicker(_ groups: [ObservationSessionGroup]) -> some View {
        Picker("Sesión", selection: $selectedGroupId) {
            ForEach(groups) { group in
                Text(shortSessionLabel(group.label)).tag(group.id)
            }
            Text("Todas").tag(Self.allGroupsId)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    Text("Alumno")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 160, alignment: .leading)
                    ForEach(visibleItemIndices, id: \.self) { index in
                        columnHeader(index: index)
                    }
                    Text("Nota")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 70)
                }
                .padding(.vertical, 8)
                Divider()
                ForEach(request.students) { student in
                    GridRow {
                        Text(student.name)
                            .font(.body)
                            .lineLimit(2)
                            .frame(minWidth: 160, alignment: .leading)
                        ForEach(visibleItemIndices, id: \.self) { index in
                            itemControl(student: student, index: index)
                        }
                        gradeLabel(for: student)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func columnHeader(index: Int) -> some View {
        let item = templateItems[index]
        return VStack(alignment: .leading, spacing: 2) {
            Text(indicatorTitle(item.title))
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if isEditable(item) {
                Menu("Para todos…") {
                    ForEach(item.type == .check ? ["true", "false"] : ["4", "3", "2", "1"], id: \.self) { value in
                        Button(value == "true" ? "Sí" : value == "false" ? "No" : value) {
                            applyAllValue = value
                            applyAllItemIndex = index
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .frame(minHeight: 44)
                .accessibilityLabel("Poner a todos: \(indicatorTitle(item.title))")
            }
        }
        .frame(width: columnWidth(for: item), alignment: .leading)
    }

    @ViewBuilder
    private func itemControl(student: StructuredInstrumentBulkRequest.Student, index: Int) -> some View {
        let item = templateItems[index]
        switch item.type {
        case .scale14:
            // Celda `Equatable`: un toque solo redibuja la celda tocada, no todo el grid.
            StructuredBulkScaleCell(
                value: models[student.id]?.items[safe: index]?.numberValue ?? "",
                width: columnWidth(for: item),
                accessibilityText: "\(indicatorTitle(item.title)), \(student.name)",
                selection: numberBinding(studentId: student.id, index: index)
            )
            .equatable()
        case .check:
            StructuredBulkCheckCell(
                isOn: models[student.id]?.items[safe: index]?.boolValue ?? false,
                width: columnWidth(for: item),
                accessibilityText: "\(indicatorTitle(item.title)), \(student.name)",
                binding: boolBinding(studentId: student.id, index: index)
            )
            .equatable()
        default:
            Text(models[student.id]?.items[safe: index].map(readOnlyText) ?? "—")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: columnWidth(for: item))
                .help("Este tipo de pregunta se responde en la hoja individual")
        }
    }

    private func gradeLabel(for student: StructuredInstrumentBulkRequest.Student) -> some View {
        let grade = models[student.id].flatMap(previewGrade)
        return Group {
            if let grade {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(NotebookPhysicalMark.decimalText(grade))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                    Text("/ 4")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Nota \(NotebookPhysicalMark.decimalText(grade)) sobre 4")
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Sin nota")
            }
        }
        .frame(minWidth: 70)
    }

    private var footer: some View {
        HStack {
            Text("\(completeCount) de \(request.students.count) completos")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if !changedStudentIds.isEmpty {
                Text("\(changedStudentIds.count) sin guardar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Datos derivados

    /// Ítems de la plantilla, tomados del primer alumno cargado (todas las celdas de la columna
    /// comparten plantilla).
    private var templateItems: [StructuredInstrumentEvaluationItem] {
        request.students.lazy.compactMap { models[$0.id]?.items }.first ?? []
    }

    private var sessionGroups: [ObservationSessionGroup]? {
        observationSessionGroups(for: templateItems)
    }

    private var visibleItemIndices: [Int] {
        if let groups = sessionGroups,
           let group = groups.first(where: { $0.id == selectedGroupId }) {
            return group.itemIndices
        }
        return Array(templateItems.indices)
    }

    private var changedStudentIds: [Int64] {
        request.students.map(\.id).filter { id in
            guard let model = models[id] else { return false }
            return fingerprint(model) != original[id]
        }
    }

    private var completeCount: Int {
        request.students.filter { student in
            guard let model = models[student.id] else { return false }
            return model.items.filter(isEditable).allSatisfy { item in
                item.type == .check || !item.numberValue.isEmpty
            }
        }.count
    }

    private var applyAllTitle: String {
        guard let index = applyAllItemIndex, templateItems.indices.contains(index) else { return "" }
        return "Poner a todos: \(indicatorTitle(templateItems[index].title))"
    }

    private var applyAllDisplayValue: String {
        switch applyAllValue {
        case "true": return "Sí"
        case "false": return "No"
        default: return applyAllValue
        }
    }

    private func isEditable(_ item: StructuredInstrumentEvaluationItem) -> Bool {
        item.type == .scale14 || item.type == .check
    }

    private func columnWidth(for item: StructuredInstrumentEvaluationItem) -> CGFloat {
        item.type == .scale14 ? 240 : 120
    }

    private func indicatorTitle(_ title: String) -> String {
        guard let range = title.range(of: "·") else { return title }
        return String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// "M1 - S2, 3x3 con regla…" → "M1 - S2" para que el selector quepa en iPad.
    private func shortSessionLabel(_ label: String) -> String {
        let head = label.split(separator: ",", maxSplits: 1).first.map(String.init) ?? label
        return head.trimmingCharacters(in: .whitespaces)
    }

    private func readOnlyText(_ item: StructuredInstrumentEvaluationItem) -> String {
        let text = item.textValue.isEmpty ? item.numberValue : item.textValue
        return text.isEmpty ? "—" : text
    }

    private func fingerprint(_ model: StructuredInstrumentEvaluationModel) -> [String] {
        model.items.map { "\($0.numberValue)|\($0.boolValue)|\($0.textValue)" }
    }

    /// Misma regla que la hoja individual y que `deriveObservationGridScore` (Kotlin): media de
    /// indicadores por sesión y luego media de sesiones respondidas; sin sesiones, media directa.
    private func previewGrade(_ model: StructuredInstrumentEvaluationModel) -> Double? {
        func value(_ index: Int) -> Double? {
            guard model.items.indices.contains(index), model.items[index].type == .scale14 else { return nil }
            return Double(model.items[index].numberValue.replacingOccurrences(of: ",", with: "."))
        }
        if let groups = observationSessionGroups(for: model.items) {
            let sessionAverages = groups.compactMap { group -> Double? in
                let values = group.itemIndices.compactMap(value)
                return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
            return sessionAverages.isEmpty ? nil : sessionAverages.reduce(0, +) / Double(sessionAverages.count)
        }
        let values = model.items.indices.compactMap(value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Bindings

    private func numberBinding(studentId: Int64, index: Int) -> Binding<String> {
        Binding(
            get: { models[studentId]?.items[safe: index]?.numberValue ?? "" },
            set: { newValue in
                guard models[studentId]?.items.indices.contains(index) == true else { return }
                models[studentId]?.items[index].numberValue = newValue
            }
        )
    }

    private func boolBinding(studentId: Int64, index: Int) -> Binding<Bool> {
        Binding(
            get: { models[studentId]?.items[safe: index]?.boolValue ?? false },
            set: { newValue in
                guard models[studentId]?.items.indices.contains(index) == true else { return }
                models[studentId]?.items[index].boolValue = newValue
            }
        )
    }

    private func applyToAll(itemIndex: Int, overwrite: Bool) {
        for student in request.students {
            guard var model = models[student.id], model.items.indices.contains(itemIndex) else { continue }
            switch model.items[itemIndex].type {
            case .scale14:
                if overwrite || model.items[itemIndex].numberValue.isEmpty {
                    model.items[itemIndex].numberValue = applyAllValue
                }
            case .check:
                if overwrite || !model.items[itemIndex].boolValue {
                    model.items[itemIndex].boolValue = applyAllValue == "true"
                }
            default:
                break
            }
            models[student.id] = model
        }
        applyAllItemIndex = nil
    }

    // MARK: - Carga y guardado

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var loaded: [Int64: StructuredInstrumentEvaluationModel] = [:]
        do {
            for student in request.students {
                if let model = try await bridge.loadStructuredInstrumentEvaluation(
                    classId: request.classId,
                    studentId: student.id,
                    columnId: request.columnId
                ) {
                    loaded[student.id] = model
                }
            }
        } catch {
            loadError = error.localizedDescription
            return
        }
        models = loaded
        original = loaded.mapValues(fingerprint)
    }

    private func save() async {
        let targets = changedStudentIds
        guard !targets.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        var failed: [Int64] = []
        var saved: [Int64] = []
        for id in targets {
            guard let model = models[id] else { continue }
            do {
                try await bridge.saveStructuredInstrumentEvaluation(model)
                original[id] = fingerprint(model)
                saved.append(id)
            } catch {
                failed.append(id)
            }
        }
        failedStudentIds = failed
        if !saved.isEmpty { onSaved(saved) }
        if failed.isEmpty { onClose() }
    }
}

/// Celda 1-4 de la hoja masiva. Compara solo lo que pinta (valor, ancho, etiqueta);
/// el `Binding` lee y escribe el estado actual de la hoja, así que no queda viejo.
private struct StructuredBulkScaleCell: View, Equatable {
    let value: String
    let width: CGFloat
    let accessibilityText: String
    let selection: Binding<String>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value && lhs.width == rhs.width && lhs.accessibilityText == rhs.accessibilityText
    }

    var body: some View {
        InstrumentEvaluationScaleControl(selection: selection)
            .frame(width: width)
            .accessibilityLabel(accessibilityText)
    }
}

/// Casilla Sí/No de la hoja masiva. Mismo criterio que `StructuredBulkScaleCell`.
private struct StructuredBulkCheckCell: View, Equatable {
    let isOn: Bool
    let width: CGFloat
    let accessibilityText: String
    let binding: Binding<Bool>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isOn == rhs.isOn && lhs.width == rhs.width && lhs.accessibilityText == rhs.accessibilityText
    }

    var body: some View {
        Toggle(isOn: binding) { EmptyView() }
            .labelsHidden()
            .frame(width: width)
            .accessibilityLabel(accessibilityText)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
