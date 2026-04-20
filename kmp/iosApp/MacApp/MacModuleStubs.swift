import SwiftUI
import AppKit
import MiGestorKit

struct MacStudentsView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?

    private var students: [Student] {
        selectedClassId == nil ? bridge.allStudents : bridge.studentsInClass
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack {
                Text("Alumnado")
                    .font(MacAppStyle.pageTitle)
                Spacer()
                if !bridge.classes.isEmpty {
                    Picker("Clase", selection: $selectedClassId) {
                        Text("Todas").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .frame(width: 220)
                }
            }

            if students.isEmpty {
                ContentUnavailableView(
                    "Sin alumnado",
                    systemImage: "person.3",
                    description: Text("No hay alumnos disponibles para la clase seleccionada.")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Nombre")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Estado")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, MacAppStyle.innerPadding)
                    .padding(.vertical, 10)
                    .background(MacAppStyle.subtleFill)

                    ForEach(Array(students.enumerated()), id: \.element.id) { index, student in
                        HStack {
                            Text("\(student.firstName) \(student.lastName)")
                            Spacer()
                            MacStatusPill(
                                label: student.isInjured ? "Seguimiento" : "Normal",
                                isActive: student.isInjured,
                                tint: student.isInjured ? MacAppStyle.warningTint : MacAppStyle.successTint
                            )
                        }
                        .padding(.horizontal, MacAppStyle.innerPadding)
                        .padding(.vertical, 10)

                        if index < students.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
        .task {
            if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId
            }
        }
        .task(id: selectedClassId) {
            await bridge.selectStudentsClass(classId: selectedClassId)
        }
    }
}

struct MacRubricsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var selectedRubricId: Int64?
    @State private var selectedFilterClassId: Int64?
    @State private var usageSummary: KmpBridge.RubricUsageSnapshot?
    @State private var usageLoading = false
    @State private var bulkOptions: [KmpBridge.RubricUsageSnapshot.EvaluationUsage] = []

    private var filteredRubrics: [RubricDetail] {
        bridge.rubrics.filter { rubric in
            guard let selectedFilterClassId else { return true }
            return rubric.rubric.classId?.int64Value == selectedFilterClassId
        }
    }

    private var selectedRubric: RubricDetail? {
        filteredRubrics.first(where: { $0.rubric.id == selectedRubricId }) ?? filteredRubrics.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rúbricas")
                        .font(MacAppStyle.pageTitle)
                    Text("Workspace Mac con banco, detalle e impacto evaluativo.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !bridge.classes.isEmpty {
                    Picker("Clase", selection: $selectedFilterClassId) {
                        Text("Todas").tag(Optional<Int64>.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(Optional(schoolClass.id))
                        }
                    }
                    .frame(width: 220)
                }
                Button {
                    bridge.resetRubricBuilder()
                } label: {
                    Label("Nueva rúbrica", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if bridge.rubrics.isEmpty {
                ContentUnavailableView(
                    "Sin rúbricas",
                    systemImage: "checklist",
                    description: Text("Aún no hay rúbricas cargadas en el bridge.")
                )
            } else {
                HStack(alignment: .top, spacing: MacAppStyle.sectionSpacing) {
                    rubricsTable
                        .frame(minWidth: 430, idealWidth: 520, maxWidth: 620)
                    rubricDetailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(MacAppStyle.pagePadding)
        .task {
            if selectedRubricId == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            await reloadUsageSummary()
        }
        .onChange(of: selectedFilterClassId) { newValue in
            bridge.setRubricFilterClass(newValue)
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: bridge.rubrics.count) { _ in
            if selectedRubric == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: selectedRubricId) { _ in
            Task { await reloadUsageSummary() }
        }
        .confirmationDialog(
            "Elegir evaluación masiva",
            isPresented: Binding(
                get: { !bulkOptions.isEmpty },
                set: { if !$0 { bulkOptions = [] } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(bulkOptions, id: \.evaluationId) { usage in
                Button("\(usage.className) · \(usage.evaluationName)") {
                    openBulkEvaluation(for: usage)
                }
            }
            Button("Cancelar", role: .cancel) {
                bulkOptions = []
            }
        } message: {
            Text("Selecciona la clase y evaluación que quieres abrir.")
        }
    }

    private var rubricsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nombre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Criterios")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Text("Uso")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.horizontal, MacAppStyle.innerPadding)
            .padding(.vertical, 10)
            .background(MacAppStyle.subtleFill)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRubrics, id: \.rubric.id) { rubric in
                        Button {
                            selectedRubricId = rubric.rubric.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rubric.rubric.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(className(for: rubric))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(rubric.criteria.count)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                MacStatusPill(
                                    label: usageLabel(for: rubric),
                                    isActive: usageCount(for: rubric) > 0,
                                    tint: usageCount(for: rubric) > 0 ? MacAppStyle.infoTint : .secondary
                                )
                                .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, MacAppStyle.innerPadding)
                            .padding(.vertical, 12)
                            .background(
                                selectedRubricId == rubric.rubric.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
            }
        }
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var rubricDetailPanel: some View {
        if let rubric = selectedRubric {
            ScrollView {
                VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rubric.rubric.name)
                            .font(.title2.weight(.semibold))
                        Text("\(className(for: rubric)) · \(formattedDate(for: rubric))")
                            .foregroundStyle(.secondary)
                        if let description = rubric.rubric.description_, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: MacAppStyle.cardSpacing) {
                        MacMetricCard(label: "Criterios", value: "\(rubric.criteria.count)", systemImage: "list.bullet.rectangle")
                        MacMetricCard(label: "Clases", value: "\(usageSummary?.classCount ?? 0)", systemImage: "rectangle.3.group")
                        MacMetricCard(label: "Evaluaciones", value: "\(usageSummary?.evaluationCount ?? 0)", systemImage: "chart.bar.doc.horizontal")
                        MacMetricCard(label: "Uso", value: usageLabel(for: rubric), systemImage: "checklist")
                    }

                    HStack(spacing: 12) {
                        Button {
                            openBulkEvaluationFlow(for: rubric)
                        } label: {
                            Label("Evaluación masiva", systemImage: "square.grid.3x3")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((usageSummary?.evaluationCount ?? 0) == 0)

                        Button {
                            bridge.loadRubricForEditing(rubric)
                        } label: {
                            Label("Abrir vista de edición", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            bridge.startAssignRubric(rubric.rubric)
                        } label: {
                            Label("Asignar a clase", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            bridge.deleteRubric(id: rubric.rubric.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Impacto evaluativo")
                            .font(MacAppStyle.sectionTitle)
                        if usageLoading {
                            ProgressView()
                        } else if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                            Text("Esta rúbrica está vinculada a \(usageSummary.evaluationCount) evaluación(es) en \(usageSummary.classCount) clase(s).")
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)

                            MacFlowLayout(spacing: 8) {
                                ForEach(usageSummary.linkedClassNames, id: \.self) { className in
                                    MacStatusPill(label: className, isActive: true, tint: MacAppStyle.infoTint)
                                }
                            }

                            VStack(spacing: 8) {
                                ForEach(usageSummary.evaluationUsages.prefix(6), id: \.evaluationId) { usage in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(usage.evaluationName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(usage.className) · \(usage.evaluationType) · Peso \(String(format: "%.1f", usage.weight))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(MacAppStyle.cardBackground)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                                            .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                                }
                            }
                        } else {
                            Text("Todavía no hay evaluaciones activas enlazadas a esta rúbrica.")
                                .font(MacAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Criterios y niveles")
                            .font(MacAppStyle.sectionTitle)
                        ForEach(rubric.criteria, id: \.criterion.id) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.criterion.description)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    MacStatusPill(
                                        label: "Peso \(Int(item.criterion.weight * 100))%",
                                        isActive: true,
                                        tint: MacAppStyle.infoTint
                                    )
                                }
                                MacFlowLayout(spacing: 8) {
                                    ForEach(item.levels.sorted(by: { $0.order < $1.order }), id: \.id) { level in
                                        MacStatusPill(
                                            label: "\(level.name) · \(level.points)",
                                            isActive: false,
                                            tint: MacAppStyle.infoTint
                                        )
                                    }
                                }
                            }
                            .padding(MacAppStyle.innerPadding)
                            .background(MacAppStyle.cardBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Selecciona una rúbrica",
                systemImage: "checklist",
                description: Text("El detalle mostrará criterios, niveles y acceso a evaluación masiva.")
            )
        }
    }

    @MainActor
    private func reloadUsageSummary() async {
        guard let rubricId = selectedRubric?.rubric.id else {
            usageSummary = nil
            return
        }
        usageLoading = true
        defer { usageLoading = false }
        usageSummary = try? await bridge.loadRubricUsage(rubricId: rubricId)
    }

    private func openBulkEvaluationFlow(for rubric: RubricDetail) {
        guard let usageSummary else { return }
        if usageSummary.evaluationUsages.count == 1, let only = usageSummary.evaluationUsages.first {
            openBulkEvaluation(for: only)
        } else {
            bulkOptions = usageSummary.evaluationUsages
        }
    }

    private func openBulkEvaluation(for usage: KmpBridge.RubricUsageSnapshot.EvaluationUsage) {
        bulkOptions = []
        bridge.startBulkRubricEvaluation(
            classId: usage.classId,
            evaluationId: usage.evaluationId,
            rubricId: selectedRubric?.rubric.id ?? usageSummary?.rubricId ?? 0,
            columnId: nil,
            tabId: nil
        )
    }

    private func usageCount(for rubric: RubricDetail) -> Int {
        if usageSummary?.rubricId == rubric.rubric.id {
            return usageSummary?.evaluationCount ?? 0
        }
        return (bridge.rubricClassLinks[rubric.rubric.id] ?? []).isEmpty ? 0 : 1
    }

    private func usageLabel(for rubric: RubricDetail) -> String {
        let count = usageCount(for: rubric)
        switch count {
        case 0: return "Sin uso"
        case 1: return "1 eval."
        default: return "\(count) evals."
        }
    }

    private func className(for rubric: RubricDetail) -> String {
        if let classId = rubric.rubric.classId?.int64Value,
           let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
            return schoolClass.name
        }
        return "Sin clase asociada"
    }

    private func formattedDate(for rubric: RubricDetail) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(rubric.rubric.trace.updatedAt.epochSeconds))
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct MacFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 800
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: maxWidth,
            height: currentY + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct MacReportsView: View {
    @ObservedObject var bridge: KmpBridge
    @State private var selectedClassId: Int64? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            Text("Informes")
                .font(MacAppStyle.pageTitle)

            HStack {
                Picker("Grupo", selection: $selectedClassId) {
                    Text("Seleccionar grupo").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .frame(width: 220)
                Spacer()
            }

            if selectedClassId == nil {
                ContentUnavailableView(
                    "Selecciona un grupo",
                    systemImage: "doc.text",
                    description: Text("Elige un grupo para acceder a los informes disponibles.")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stub funcional listo")
                        .font(.headline)
                    Text("El grupo ya queda fijado en la shell Mac. La siguiente iteración podrá colgar aquí el workspace completo de informes sin reabrir el routing.")
                        .font(MacAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }
                .padding(MacAppStyle.innerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
    }
}

struct MacPlannerView: View {
    @ObservedObject var bridge: KmpBridge
    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var activeSection: MacPlannerSection = .week
    @State private var selectedTableSessionId: Int64?
    @State private var showingScheduleSettings = false
    @State private var showingExportConfirmation = false
    @State private var transientMessage: String?
    @State private var isInspectorVisible = true
    @State private var inspectorWidth: CGFloat = 380

    var body: some View {
        GeometryReader { proxy in
            HSplitView {
                plannerSidebar
                    .frame(minWidth: 252, idealWidth: 272, maxWidth: 296)

                VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                    plannerHeader
                    if let transientMessage, !transientMessage.isEmpty {
                        MacPlannerBanner(message: transientMessage)
                    } else if !vm.bulkSummary.isEmpty {
                        MacPlannerBanner(message: vm.bulkSummary)
                    }
                    plannerCenterContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(MacAppStyle.pagePadding)
                .background(MacAppStyle.pageBackground)

                if shouldShowInspector(in: proxy.size.width) {
                    plannerInspector
                        .frame(minWidth: 320, idealWidth: inspectorWidth, maxWidth: 460)
                }
            }
        }
        .background(MacAppStyle.pageBackground)
        .task {
            await vm.bind(bridge: bridge)
        }
        .onChange(of: selectedTableSessionId) { newValue in
            guard let newValue,
                  let session = vm.filteredSessions.first(where: { $0.id == newValue }) ?? vm.sessions.first(where: { $0.id == newValue }) else { return }
            Task {
                await vm.select(session: session)
                isInspectorVisible = true
            }
        }
        .onChange(of: vm.selectedSession?.id) { newValue in
            selectedTableSessionId = newValue
        }
        .sheet(isPresented: $vm.showingComposer) {
            PlannerSessionComposerSheet(vm: vm)
                .frame(minWidth: 920, minHeight: 720)
        }
        .sheet(isPresented: $showingScheduleSettings, onDismiss: {
            Task { await vm.reloadAll() }
        }) {
            TeacherScheduleSettingsPanel(
                selectedClassId: Binding(
                    get: { vm.groupFilterId },
                    set: { vm.groupFilterId = $0 }
                )
            )
            .environmentObject(bridge)
            .frame(minWidth: 980, minHeight: 760)
        }
        .alert("Exportación copiada", isPresented: $showingExportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("El resumen actual de planificación se ha copiado al portapapeles.")
        }
    }

    private var plannerSidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Planificación")
                .font(MacAppStyle.pageTitle)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(MacPlannerSection.allCases) { section in
                    Button {
                        activeSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.callout.weight(activeSection == section ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(activeSection == section ? MacAppStyle.infoTint.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Filtros")
                    .font(MacAppStyle.sectionTitle)

                Picker("Grupo", selection: Binding(
                    get: { vm.groupFilterId },
                    set: { vm.groupFilterId = $0 }
                )) {
                    Text("Todos los grupos").tag(Optional<Int64>.none)
                    ForEach(vm.groups, id: \.id) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }

                TextField("Buscar sesión, unidad u objetivo", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: vm.searchText) { _ in
                        vm.applySearch()
                    }

                Picker("Estado", selection: $vm.sessionFilter) {
                    ForEach(PlannerSessionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Acciones")
                    .font(MacAppStyle.sectionTitle)

                Button("Nueva sesión") {
                    vm.openComposer()
                }
                .buttonStyle(.borderedProminent)

                Button("Copiar semana") {
                    Task { await copyFilteredWeek() }
                }
                .buttonStyle(.bordered)
                .disabled(displayedSessions.isEmpty)

                Button("Mover selección") {
                    Task { await moveFilteredSelection() }
                }
                .buttonStyle(.bordered)
                .disabled(displayedSessions.isEmpty)

                Button("Exportar") {
                    exportCurrentContext()
                }
                .buttonStyle(.bordered)

                Button("Configurar agenda") {
                    showingScheduleSettings = true
                }
                .buttonStyle(.bordered)
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(MacAppStyle.pagePadding)
        .background(MacAppStyle.cardBackground)
    }

    private var plannerHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeSection.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(vm.weekLabel) · \(vm.dateRangeLabel)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await vm.previousWeek() }
                } label: {
                    Image(systemName: "chevron.left")
                }

                Button {
                    Task { await vm.nextWeek() }
                } label: {
                    Image(systemName: "chevron.right")
                }

                Button(isInspectorVisible ? "Ocultar inspector" : "Mostrar inspector") {
                    isInspectorVisible.toggle()
                }
                .buttonStyle(.bordered)

                Button("Agenda") {
                    showingScheduleSettings = true
                }
                .buttonStyle(.bordered)

                Button("Nueva sesión") {
                    vm.openComposer()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var plannerCenterContent: some View {
        switch activeSection {
        case .week:
            MacPlannerWeekBoard(
                vm: vm,
                onSelectSession: { session in
                    Task {
                        await vm.select(session: session)
                        isInspectorVisible = true
                    }
                },
                onDoubleOpenSession: { session in
                    Task {
                        await vm.select(session: session)
                        isInspectorVisible = true
                    }
                }
            )
        case .sessions:
            MacPlannerSessionsTable(
                rows: displayedRows,
                selectedSessionId: $selectedTableSessionId
            )
        case .agenda:
            MacPlannerAgendaView(
                vm: vm,
                groupFilterId: vm.groupFilterId,
                onOpenSettings: { showingScheduleSettings = true }
            )
        }
    }

    private var plannerInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspector")
                        .font(MacAppStyle.sectionTitle)
                    Text(vm.selectedSession?.teachingUnitName ?? "Diario de sesión")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isInspectorVisible = false
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
            }
            .padding(MacAppStyle.innerPadding)

            Divider()

            PlannerJournalDetailPane(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MacAppStyle.cardBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MacAppStyle.cardBorder)
                .frame(width: 0.5)
        }
    }

    private var displayedSessions: [PlanningSession] {
        vm.filteredSessions
    }

    private var displayedRows: [MacPlannerSessionRow] {
        displayedSessions.map { session in
            MacPlannerSessionRow(
                session: session,
                dayLabel: vm.dayLabel(for: Int(session.dayOfWeek)),
                timeLabel: vm.timeLabel(for: Int(session.period)),
                sessionStatusLabel: session.status == .completed ? "Impartida" : "Planificada",
                diaryStatusLabel: diaryStatusLabel(for: session)
            )
        }
    }

    private func diaryStatusLabel(for session: PlanningSession) -> String {
        switch vm.summary(for: session.id)?.status {
        case .completed:
            return "Cerrado"
        case .draft:
            return "Borrador"
        case .empty, .none:
            return "Vacío"
        default:
            return "Vacío"
        }
    }

    private func shouldShowInspector(in totalWidth: CGFloat) -> Bool {
        isInspectorVisible && totalWidth >= 1180
    }

    private func copyFilteredWeek() async {
        guard !displayedSessions.isEmpty else { return }
        vm.selectedSessionIds = Set(displayedSessions.map(\.id))
        await vm.bulkCopyToNextWeek()
    }

    private func moveFilteredSelection() async {
        guard !displayedSessions.isEmpty else { return }
        vm.selectedSessionIds = Set(displayedSessions.map(\.id))
        await vm.bulkMoveOneDay()
    }

    private func exportCurrentContext() {
        let text: String
        if vm.selectedSession != nil {
            text = vm.exportText()
        } else {
            let sessionLines = displayedRows.map {
                "\($0.unit) · \($0.group) · \($0.day) · \($0.time) · \($0.sessionStatus) · \($0.diaryStatus)"
            }
            text = ([ "\(vm.weekLabel) · \(vm.dateRangeLabel)" ] + sessionLines).joined(separator: "\n")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        transientMessage = "Resumen exportado al portapapeles."
        showingExportConfirmation = true
    }
}

private enum MacPlannerSection: String, CaseIterable, Identifiable {
    case week
    case sessions
    case agenda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Semana"
        case .sessions: return "Sesiones"
        case .agenda: return "Agenda"
        }
    }

    var systemImage: String {
        switch self {
        case .week: return "calendar"
        case .sessions: return "tablecells"
        case .agenda: return "clock.badge.checkmark"
        }
    }
}

private struct MacPlannerSessionRow: Identifiable {
    let session: PlanningSession
    let dayLabel: String
    let timeLabel: String
    let sessionStatusLabel: String
    let diaryStatusLabel: String

    var id: Int64 { session.id }
    var unit: String { session.teachingUnitName }
    var group: String { session.groupName }
    var day: String { dayLabel }
    var time: String { timeLabel }
    var sessionStatus: String { sessionStatusLabel }
    var diaryStatus: String { diaryStatusLabel }
}

private struct MacPlannerBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MacAppStyle.successTint)
            Text(message)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.successTint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacPlannerSessionsTable: View {
    let rows: [MacPlannerSessionRow]
    @Binding var selectedSessionId: Int64?

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "Sin sesiones",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No hay sesiones que coincidan con los filtros actuales.")
            )
        } else {
            Table(rows, selection: $selectedSessionId) {
                TableColumn("Unidad") { row in
                    Text(row.unit)
                        .lineLimit(2)
                }
                .width(min: 180, ideal: 240)

                TableColumn("Grupo") { row in
                    Text(row.group)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Día") { row in
                    Text(row.day)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Franja") { row in
                    Text(row.time)
                }
                .width(min: 110, ideal: 120)

                TableColumn("Estado") { row in
                    Text(row.sessionStatus)
                }
                .width(min: 100, ideal: 110)

                TableColumn("Diario") { row in
                    Text(row.diaryStatus)
                }
                .width(min: 90, ideal: 100)
            }
        }
    }
}

private struct MacPlannerWeekBoard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onSelectSession: (PlanningSession) -> Void
    let onDoubleOpenSession: (PlanningSession) -> Void

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("Franja", width: 120)
                    ForEach(vm.visibleWeekdays, id: \.self) { day in
                        headerCell(vm.dayLabel(for: day), width: 250)
                    }
                }

                ForEach(vm.visibleSlots, id: \.period) { slot in
                    HStack(spacing: 0) {
                        VStack(spacing: 6) {
                            Text("P\(slot.period)")
                                .font(.caption.weight(.bold))
                            Text(slot.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120, height: 176)
                        .background(MacAppStyle.subtleFill)

                        ForEach(vm.visibleWeekdays, id: \.self) { day in
                            MacPlannerWeekCell(
                                entries: vm.entries(for: day, period: Int(slot.period)),
                                day: day,
                                period: Int(slot.period),
                                vm: vm,
                                onSelectSession: onSelectSession,
                                onDoubleOpenSession: onDoubleOpenSession
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .frame(width: width, height: 40)
            .background(MacAppStyle.subtleFill)
    }
}

private struct MacPlannerWeekCell: View {
    let entries: [PlannerWeekCellEntry]
    let day: Int
    let period: Int
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onSelectSession: (PlanningSession) -> Void
    let onDoubleOpenSession: (PlanningSession) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                    Text("Libre")
                        .font(.caption.weight(.bold))
                    Text("Doble clic para añadir sesión")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ForEach(entries.prefix(3)) { entry in
                    MacPlannerWeekEntryRow(
                        entry: entry,
                        vm: vm,
                        onSelectSession: onSelectSession,
                        onDoubleOpenSession: onDoubleOpenSession
                    )
                }

                if entries.count > 3 {
                    Text("+\(entries.count - 3) más")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 250, height: 176, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovering ? MacAppStyle.infoTint.opacity(0.08) : MacAppStyle.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovering ? MacAppStyle.infoTint.opacity(0.45) : MacAppStyle.cardBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            if entries.isEmpty {
                vm.openComposer(day: day, period: period)
            }
        }
    }
}

private struct MacPlannerWeekEntryRow: View {
    let entry: PlannerWeekCellEntry
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onSelectSession: (PlanningSession) -> Void
    let onDoubleOpenSession: (PlanningSession) -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(tint)
                    .frame(width: 8, height: 20)
                Text(entry.className)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if entry.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MacAppStyle.successTint)
                }
            }

            Text(entry.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(entry.preview)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(entry.kind == .session ? 0.12 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .contextMenu {
            if let session = resolvedSession {
                Button("Abrir diario") {
                    onDoubleOpenSession(session)
                }
                Button("Editar") {
                    vm.openComposer(for: session)
                }
                Button("Duplicar próxima semana") {
                    Task {
                        vm.selectedSessionIds = [session.id]
                        await vm.bulkCopyToNextWeek()
                    }
                }
                Button("Marcar impartida") {
                    Task {
                        await vm.markCompleted(session)
                    }
                }
            }
        }
        .onTapGesture {
            if let session = resolvedSession {
                onSelectSession(session)
            }
        }
        .onTapGesture(count: 2) {
            if let session = resolvedSession {
                onDoubleOpenSession(session)
            } else {
                vm.openComposer(day: entry.dayOfWeek, period: entry.period)
                vm.composerDraft.groupId = entry.classId
            }
        }
    }

    private var resolvedSession: PlanningSession? {
        guard let sessionId = entry.sessionId else { return nil }
        return vm.sessions.first(where: { $0.id == sessionId })
    }
}

private struct MacPlannerAgendaView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let groupFilterId: Int64?
    let onOpenSettings: () -> Void

    private var filteredScheduleSlots: [TeacherScheduleSlot] {
        vm.effectiveScheduleSlots.filter { slot in
            guard let groupFilterId else { return true }
            return slot.schoolClassId == groupFilterId
        }
    }

    private var filteredForecastRows: [PlannerSessionForecast] {
        vm.forecastRows.filter { row in
            guard let groupFilterId else { return true }
            return row.schoolClassId?.int64Value == groupFilterId
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MacMetricCard(label: "Agenda", value: vm.scheduleName, tint: .blue, systemImage: "calendar")
                    MacMetricCard(label: "Curso", value: "\(vm.scheduleStartDate) - \(vm.scheduleEndDate)", tint: .indigo, systemImage: "clock")
                    MacMetricCard(label: "Franjas", value: "\(filteredScheduleSlots.count)", tint: .teal, systemImage: "square.grid.3x3")
                    MacMetricCard(label: "Evaluaciones", value: "\(vm.evaluationPeriods.count)", tint: .orange, systemImage: "chart.bar")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Días lectivos")
                            .font(MacAppStyle.sectionTitle)
                        Spacer()
                        Button("Abrir configuración", action: onOpenSettings)
                            .buttonStyle(.borderedProminent)
                    }

                    Text(vm.activeWeekdaySummary)
                        .font(MacAppStyle.bodyText)
                        .foregroundStyle(.secondary)
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Franjas persistentes")
                        .font(MacAppStyle.sectionTitle)

                    if filteredScheduleSlots.isEmpty {
                        Text("Todavía no hay franjas definidas para los filtros activos.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredScheduleSlots, id: \.id) { slot in
                            HStack(spacing: 12) {
                                Text(vm.dayLabel(for: Int(slot.dayOfWeek)))
                                    .font(.caption.weight(.bold))
                                    .frame(width: 48, alignment: .leading)
                                Text("\(slot.startTime)-\(slot.endTime)")
                                    .font(.callout)
                                    .monospacedDigit()
                                    .frame(width: 120, alignment: .leading)
                                Text(vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)")
                                    .frame(width: 180, alignment: .leading)
                                Text(slot.unitLabel ?? slot.subjectLabel)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            if slot.id != filteredScheduleSlots.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Forecast por evaluación")
                        .font(MacAppStyle.sectionTitle)

                    if filteredForecastRows.isEmpty {
                        Text("Todavía no hay previsiones calculadas para la agenda actual.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            MacPlannerForecastHeaderRow()
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                            ForEach(Array(filteredForecastRows.enumerated()), id: \.offset) { index, row in
                                MacPlannerForecastDataRow(row: row)

                                if index < filteredForecastRows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            }
            .padding(.bottom, 12)
        }
    }
}

private struct MacPlannerForecastHeaderRow: View {
    var body: some View {
        HStack {
            Text("Evaluación").frame(maxWidth: .infinity, alignment: .leading)
            Text("Grupo").frame(maxWidth: .infinity, alignment: .leading)
            Text("Sesiones").frame(width: 80, alignment: .trailing)
            Text("Completadas").frame(width: 100, alignment: .trailing)
            Text("Pendientes").frame(width: 90, alignment: .trailing)
        }
    }
}

private struct MacPlannerForecastDataRow: View {
    let row: PlannerSessionForecast

    var body: some View {
        HStack {
            Text(row.periodName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.className)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.expectedSessions)")
                .frame(width: 80, alignment: .trailing)
            Text("\(row.plannedSessions)")
                .frame(width: 100, alignment: .trailing)
            Text("\(row.remainingSessions)")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}
