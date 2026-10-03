import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

struct LearningSituationAssessmentImportPreviewSheet: View {
    let draft: LearningSituationAssessmentImportDraft
    let cancel: () -> Void
    let confirm: (LearningSituationAssessmentImportDraft) -> Void
    @State private var editableDraft: LearningSituationAssessmentImportDraft
    @State private var selectedInstrumentId: UUID?

    init(
        draft: LearningSituationAssessmentImportDraft,
        cancel: @escaping () -> Void,
        confirm: @escaping (LearningSituationAssessmentImportDraft) -> Void
    ) {
        self.draft = draft
        self.cancel = cancel
        self.confirm = confirm
        _editableDraft = State(initialValue: draft)
        _selectedInstrumentId = State(initialValue: draft.instruments.first?.id)
    }

    private var selectedCount: Int {
        editableDraft.instruments.filter(\.isSelected).count
    }

    private var selectedInstruments: [AssessmentInstrumentDraft] {
        editableDraft.instruments.filter(\.isSelected)
    }

    private var averageCount: Int {
        selectedInstruments.filter(\.countsTowardAverage).count
    }

    private var auxiliaryCount: Int {
        selectedInstruments.count - averageCount
    }

    private var weightedTotal: Double {
        selectedInstruments
            .filter(\.countsTowardAverage)
            .compactMap(\.weightPercent)
            .reduce(0, +)
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if selectedCount == 0 {
            errors.append("Selecciona al menos un instrumento.")
        }
        for instrument in selectedInstruments {
            let title = instrument.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                errors.append("Hay un instrumento seleccionado sin título.")
            }
            if let weight = instrument.weightPercent, weight < 0 {
                errors.append("\(title.isEmpty ? "Instrumento" : title): el peso no puede ser negativo.")
            }
            if instrument.countsTowardAverage && (instrument.weightPercent ?? 0) <= 0 {
                errors.append("\(title): marca peso mayor que 0 o desactiva la media.")
            }
            if instrument.kind == .rubric && (instrument.rubric?.criteria.isEmpty ?? true) {
                errors.append("\(title): la rúbrica no tiene criterios.")
            }
            if instrument.kind.isStudentAuthored && (instrument.rubric?.criteria.isEmpty ?? true) {
                errors.append("\(title): la autoevaluación necesita una tabla de rúbrica con indicadores.")
            }
            if instrument.countsTowardAverage && instrument.scoreStrategy == .none {
                errors.append("\(title): elige una estrategia de puntuación.")
            }
            if instrument.countsTowardAverage &&
                instrument.scoreStrategy == .checklistProportional &&
                instrument.checklistItems.isEmpty {
                errors.append("\(title): la checklist proporcional necesita ítems para calcular la nota.")
            }
            if instrument.countsTowardAverage &&
                instrument.scoreStrategy == .observationScale1To4 &&
                !hasObservationScale1To4(instrument) {
                errors.append("\(title): la observación necesita escala 1-4.")
            }
        }
        return errors
    }

    private var canConfirm: Bool {
        validationErrors.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                ScrollView {
                    reviewContent(isWide: proxy.size.width >= 760)
                        .padding(24)
                }
                .background(appSecondarySystemBackgroundColor().opacity(0.35))
            }

            footer
        }
        .background(IOSAppStyle.pageBackground)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 620)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            ensureSelectedInstrument()
        }
    }

    private var selectedIndex: Int? {
        guard let selectedInstrumentId,
              let index = editableDraft.instruments.firstIndex(where: { $0.id == selectedInstrumentId }) else {
            return editableDraft.instruments.indices.first
        }
        return index
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(NotebookStyle.primaryTint)
                .frame(width: 48, height: 48)
                .background(NotebookStyle.primaryTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Revisar instrumentos")
                    .font(.title2.weight(.bold))
                Text(draft.sourceFileName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Cerrar revisión de instrumentos")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func reviewContent(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            metricsStrip

            if isWide {
                HStack(alignment: .top, spacing: 24) {
                    instrumentList
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                    detailPanel
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    instrumentList
                    detailPanel
                }
            }

            gradingFormulaPanel

            diagnosticsPanel
        }
    }

    // D2: la fórmula de calificación final del documento ("Nota SA = Rúbrica... (40%) +
    // Rejilla... (35%) + ...") se parseaba (`gradingFormula`) pero no se mostraba en ningún
    // sitio; el docente no tenía forma de contrastarla con los instrumentos detectados salvo
    // leyendo el DOCX aparte. Se enseña junto al resumen de pesos de la hoja de revisión.
    @ViewBuilder
    private var gradingFormulaPanel: some View {
        if let gradingFormula = editableDraft.gradingFormula, !gradingFormula.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Fórmula de calificación del documento", systemImage: "function")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(gradingFormula)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var metricsStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                previewMetric("Detectados", value: "\(editableDraft.instruments.count)")
                previewMetric("Seleccionados", value: "\(selectedCount)")
                previewMetric("Computan", value: "\(averageCount)")
                previewMetric("Auxiliares", value: "\(auxiliaryCount)")
                previewMetric("Peso", value: "\(Int(weightedTotal.rounded()))%")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], alignment: .leading, spacing: 16) {
                previewMetric("Detectados", value: "\(editableDraft.instruments.count)")
                previewMetric("Seleccionados", value: "\(selectedCount)")
                previewMetric("Computan", value: "\(averageCount)")
                previewMetric("Auxiliares", value: "\(auxiliaryCount)")
                previewMetric("Peso", value: "\(Int(weightedTotal.rounded()))%")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var instrumentList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Instrumentos detectados")
                    .font(.headline)
                Spacer()
                Button(selectedCount == editableDraft.instruments.count ? "Deseleccionar" : "Seleccionar todos") {
                    let shouldSelectAll = selectedCount != editableDraft.instruments.count
                    for index in editableDraft.instruments.indices {
                        editableDraft.instruments[index].isSelected = shouldSelectAll
                    }
                    ensureSelectedInstrument()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                ForEach(Array(editableDraft.instruments.indices), id: \.self) { index in
                    instrumentRow(index: index)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Detalle")
                    .font(.headline)
                Spacer()
                if let selectedIndex {
                    Text(editableDraft.instruments[selectedIndex].isSelected ? "Incluido" : "Excluido")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(editableDraft.instruments[selectedIndex].isSelected ? NotebookStyle.successTint : .secondary)
                }
            }

            if let selectedIndex {
                editor(for: selectedIndex)
            } else {
                NotebookContentUnavailableView(
                    "Sin instrumentos",
                    systemImage: "doc.text",
                    description: "No se han detectado instrumentos editables en este DOCX."
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var diagnosticsPanel: some View {
        if !validationErrors.isEmpty || !editableDraft.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !validationErrors.isEmpty {
                    diagnosticsGroup(
                        title: "Revisión necesaria",
                        icon: "xmark.octagon.fill",
                        tint: NotebookStyle.warningTint,
                        items: validationErrors
                    )
                }

                if !editableDraft.warnings.isEmpty {
                    diagnosticsGroup(
                        title: "Avisos del documento",
                        icon: "exclamationmark.triangle.fill",
                        tint: NotebookStyle.warningTint,
                        items: editableDraft.warnings
                    )
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label(footerMessage, systemImage: canConfirm ? "checkmark.circle.fill" : "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canConfirm ? NotebookStyle.successTint : .secondary)
                .lineLimit(2)

            Spacer()

            Button("Cancelar", action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button {
                confirm(editableDraft)
            } label: {
                Label("Usar seleccionados", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConfirm)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var footerMessage: String {
        if canConfirm {
            return "\(selectedCount) instrumentos listos para crear en el cuaderno."
        }
        return validationErrors.first ?? "Revisa la selección antes de continuar."
    }

    private func previewMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func instrumentRow(index: Int) -> some View {
        let instrument = editableDraft.instruments[index]
        let isActive = instrument.id == selectedInstrumentId
        let itemCount = detailCount(for: instrument)

        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $editableDraft.instruments[index].isSelected)
                .labelsHidden()
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .accessibilityLabel("Incluir \(instrument.title.isEmpty ? "instrumento sin título" : instrument.title)")

            VStack(alignment: .leading, spacing: 8) {
                Text(instrument.title.isEmpty ? "Sin título" : instrument.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                instrumentTags(for: instrument, itemCount: itemCount)
            }

            Spacer(minLength: 8)

            Image(systemName: isActive ? "slider.horizontal.3" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? NotebookStyle.primaryTint : .secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(isActive ? NotebookStyle.primaryTint.opacity(0.10) : NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? NotebookStyle.primaryTint.opacity(0.45) : NotebookStyle.softBorder.opacity(0.75), lineWidth: 1)
        }
        .onTapGesture {
            selectedInstrumentId = instrument.id
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
    }

    private func editor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Incluir este instrumento", isOn: $editableDraft.instruments[index].isSelected)
                .toggleStyle(.switch)
                .tint(NotebookStyle.primaryTint)

            VStack(alignment: .leading, spacing: 8) {
                Text("Título")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Título", text: $editableDraft.instruments[index].title)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                pickerField(title: "Tipo") {
                    Picker("Tipo", selection: kindBinding(for: index)) {
                        ForEach(AssessmentInstrumentKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Peso")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Peso %", text: weightBinding(for: index))
                        .textFieldStyle(.roundedBorder)
                        .appKeyboardType(.decimalPad)
                }
                .frame(maxWidth: 160)
            }

            Toggle("Cuenta para la media", isOn: $editableDraft.instruments[index].countsTowardAverage)
                .toggleStyle(.switch)
                .tint(NotebookStyle.primaryTint)

            HStack(spacing: 16) {
                pickerField(title: "Estrategia") {
                    Picker("Estrategia", selection: $editableDraft.instruments[index].scoreStrategy) {
                        ForEach(AssessmentInstrumentScoreStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.label).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)
                }

                pickerField(title: "Vacías") {
                    Picker("Vacías", selection: $editableDraft.instruments[index].emptyCellPolicy) {
                        ForEach(AssessmentInstrumentEmptyCellPolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let note = editableDraft.instruments[index].note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Anotaciones de contexto", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.top, 8)
            }

            if editableDraft.instruments[index].kind == .rubric,
               let rubric = editableDraft.instruments[index].rubric {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estructura de Rúbrica").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(rubric.criteria, id: \.title) { criterion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(criterion.title)
                                .font(.caption.weight(.bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(criterion.descriptors.enumerated()), id: \.offset) { levelIndex, desc in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(levelIndex < rubric.levels.count ? rubric.levels[levelIndex].label : "Nivel \(levelIndex + 1)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(NotebookStyle.primaryTint)
                                            Text(desc)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 120, alignment: .leading)
                                        .padding(6)
                                        .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            
            if editableDraft.instruments[index].kind == .quizQuestions,
               !editableDraft.instruments[index].quizQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preguntas Detectadas (\(editableDraft.instruments[index].quizQuestions.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(editableDraft.instruments[index].quizQuestions.enumerated()), id: \.offset) { qIndex, question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(qIndex + 1). \(question.questionText)")
                                .font(.caption.weight(.semibold))
                            if !question.options.isEmpty {
                                Text("Opciones: " + question.options.joined(separator: " / "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Respuesta abierta / rellenar hueco")
                                    .font(.system(size: 10).italic())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if (editableDraft.instruments[index].kind == .checklist || editableDraft.instruments[index].kind == .submissionChecklist),
               !editableDraft.instruments[index].checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Items de Checklist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(editableDraft.instruments[index].checklistItems, id: \.title) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(.caption)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            Text(subtitle(for: editableDraft.instruments[index]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func pickerField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instrumentTag(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NotebookStyle.surfaceSoft, in: Capsule(style: .continuous))
    }

    private func instrumentTags(for instrument: AssessmentInstrumentDraft, itemCount: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
            instrumentTag(instrument.kind.label, icon: "rectangle.grid.1x2")
            instrumentTag(instrument.countsTowardAverage ? "Cuenta" : "Auxiliar", icon: instrument.countsTowardAverage ? "sum" : "paperclip")
            instrumentTag(instrument.weightPercent.map { "\(Int($0.rounded()))%" } ?? "Sin peso", icon: "percent")
            if itemCount > 0 {
                instrumentTag("\(itemCount) items", icon: "checklist")
            }
        }
    }

    private func diagnosticsGroup(title: String, icon: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ensureSelectedInstrument() {
        if let selectedInstrumentId,
           editableDraft.instruments.contains(where: { $0.id == selectedInstrumentId }) {
            return
        }
        selectedInstrumentId = editableDraft.instruments.first?.id
    }

    private func detailCount(for instrument: AssessmentInstrumentDraft) -> Int {
        if instrument.kind == .quizQuestions {
            return instrument.quizQuestions.count
        }
        return instrument.rubric?.criteria.count ?? instrument.checklistItems.count + instrument.observationFields.count
    }

    private func kindBinding(for index: Int) -> Binding<AssessmentInstrumentKind> {
        Binding {
            editableDraft.instruments[index].kind
        } set: { newKind in
            editableDraft.instruments[index].kind = newKind
            let strategy = defaultScoreStrategy(for: editableDraft.instruments[index])
            editableDraft.instruments[index].scoreStrategy = strategy
            editableDraft.instruments[index].countsTowardAverage = strategy != .none &&
                (editableDraft.instruments[index].weightPercent ?? 0) > 0
        }
    }

    private func weightBinding(for index: Int) -> Binding<String> {
        Binding {
            guard let weight = editableDraft.instruments[index].weightPercent else { return "" }
            if weight.rounded() == weight {
                return String(Int(weight))
            }
            return String(weight)
        } set: { newValue in
            let normalized = newValue.replacingOccurrences(of: ",", with: ".")
            editableDraft.instruments[index].weightPercent = Double(normalized)
            if (editableDraft.instruments[index].weightPercent ?? 0) <= 0 {
                editableDraft.instruments[index].countsTowardAverage = false
            }
        }
    }

    private func defaultScoreStrategy(for instrument: AssessmentInstrumentDraft) -> AssessmentInstrumentScoreStrategy {
        guard (instrument.weightPercent ?? 0) > 0 else { return .none }
        switch instrument.kind {
        case .rubric:
            return .rubric
        case .observationGrid:
            return hasObservationScale1To4(instrument) ? .observationScale1To4 : .none
        case .selfAssessment, .peerAssessment:
            // La rúbrica que rellena el alumnado se responde en escala 1-4 y su nota se deriva
            // igual que la de una rejilla de observación.
            return .observationScale1To4
        case .checklist, .submissionChecklist, .teacherObservation:
            return .none
        case .quizQuestions:
            return .quizPercentCorrect
        }
    }

    private func hasObservationScale1To4(_ instrument: AssessmentInstrumentDraft) -> Bool {
        // En un instrumento de autoevaluación/coevaluación los indicadores 1-4 no viven en
        // `observationFields` sino en la tabla de rúbrica (`rubric.criteria`), que es de donde
        // salen los ítems `rub_<n>` en escala 1-4. Sin este caso, la validación del import
        // bloqueaba con "la observación necesita escala 1-4" un instrumento que sí la tiene.
        if instrument.kind.isStudentAuthored {
            return !(instrument.rubric?.criteria.isEmpty ?? true)
        }
        return instrument.observationFields.contains { field in
            guard let scale = field.scaleLabel else { return false }
            return scale.contains("1") && scale.contains("4")
        }
    }

    private func subtitle(for instrument: AssessmentInstrumentDraft) -> String {
        var parts = [instrument.kind.label]
        if let criterion = instrument.criterionLabel, !criterion.isEmpty { parts.append(criterion) }
        if instrument.countsTowardAverage {
            parts.append("Cuenta")
        } else {
            parts.append("No cuenta")
        }
        parts.append(instrument.weightPercent.map { "\(Int($0.rounded()))%" } ?? "Auxiliar")
        parts.append(instrument.scoreStrategy.label)
        parts.append(instrument.emptyCellPolicy.label)
        let detailCount = instrument.rubric?.criteria.count ?? instrument.checklistItems.count + instrument.quizQuestions.count + instrument.observationFields.count
        if detailCount > 0 { parts.append("\(detailCount) items") }
        return parts.joined(separator: " · ")
    }
}
