import SwiftUI
import MiGestorKit

struct PlannerTermBoardView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var availableSituations: [LearningSituation] = []
    @State private var isLoadingSituations = false
    @State private var showingApplyConfirmation = false

    private var selectedPeriod: PlannerEvaluationPeriod? {
        if let id = vm.selectedTermPeriodId {
            return vm.evaluationPeriods.first(where: { $0.id == id })
        }
        return sortedEvaluationPeriods.first
    }

    private var sortedEvaluationPeriods: [PlannerEvaluationPeriod] {
        vm.evaluationPeriods.sorted { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topControlBar
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if let metrics = vm.termCapacityMetrics {
                metricsStrip(metrics)
                    .padding(.horizontal, EvaluationDesign.screenPadding)
                    .padding(.bottom, 12)
            }

            if vm.isTermBoardLoading && vm.termBoardSlots.isEmpty {
                loadingView
            } else if let error = vm.termBoardErrorMessage {
                errorView(error)
            } else if vm.termBoardSlots.isEmpty {
                emptyStateView
            } else {
                slotsTimeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            if vm.simulatedSituationId != nil {
                floatingSimulationBar
                    .padding(.horizontal, EvaluationDesign.screenPadding)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: vm.selectedGroupId) {
            await reloadData()
        }
        .appOnChange(of: vm.selectedTermPeriodId) { _ in
            Task { await vm.loadTermBoard() }
        }
        .appOnChange(of: vm.evaluationPeriods.map(\.id)) { _ in
            Task { await reloadData() }
        }
    }

    // MARK: - Top Controls

    private var topControlBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Evaluación · Tablero de Encaje")
                    .font(.title2.weight(.bold))
                Text("Capacidad lectiva real, festivos y previsión de encaje de SAs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            // Period Selector
            if !sortedEvaluationPeriods.isEmpty {
                Picker("Evaluación", selection: Binding(
                    get: { vm.selectedTermPeriodId ?? sortedEvaluationPeriods.first?.id },
                    set: { newId in
                        vm.selectedTermPeriodId = newId
                        Task { await vm.loadTermBoard(classId: vm.selectedGroupId, periodId: newId) }
                    }
                )) {
                    ForEach(sortedEvaluationPeriods, id: \.id) { period in
                        Text(period.name).tag(Optional(period.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            // Group Selector
            if !vm.groups.isEmpty {
                Picker("Grupo", selection: Binding(
                    get: { vm.selectedGroupId ?? vm.groups.first?.id },
                    set: { newId in
                        vm.selectGroup(newId)
                        Task { await vm.loadTermBoard(classId: newId, periodId: vm.selectedTermPeriodId) }
                    }
                )) {
                    ForEach(vm.groups, id: \.id) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            // SA Simulation Menu
            Menu {
                if vm.simulatedSituationId != nil {
                    Button(role: .destructive) {
                        Task { await vm.clearSimulation() }
                    } label: {
                        Label("Descartar simulación actual", systemImage: "xmark.circle")
                    }
                    Divider()
                }

                Text("Probar encaje de SA:")
                    .font(.caption)

                ForEach(availableSituations, id: \.id) { situation in
                    Button {
                        Task { await vm.simulateSituation(situation.id) }
                    } label: {
                        HStack {
                            Text(situation.title)
                            if vm.simulatedSituationId == situation.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.simulatedSituationId != nil ? "sparkles" : "plus.viewfinder")
                    Text(vm.simulatedSituationId != nil ? "Simulando SA" : "Simular SA…")
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.simulatedSituationId != nil ? EvaluationDesign.accent : Color.secondary.opacity(0.3))
        }
    }

    // MARK: - Metrics Strip

    private func metricsStrip(_ metrics: TermCapacityMetrics) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                metricCard(
                    title: "Clases lectivas",
                    value: "\(metrics.totalLectivas)",
                    caption: "Reales en tu horario",
                    icon: "figure.run",
                    tint: EvaluationDesign.accent
                )

                metricCard(
                    title: "Festivos / Inhábiles",
                    value: "\(metrics.totalFestivos)",
                    caption: "Detectados y saltados",
                    icon: "calendar.badge.minus",
                    tint: metrics.totalFestivos > 0 ? Color.orange : Color.secondary
                )

                metricCard(
                    title: "Ocupadas por SAs",
                    value: "\(metrics.totalOcupadas)",
                    caption: "Programadas",
                    icon: "checkmark.circle.fill",
                    tint: EvaluationDesign.success
                )

                metricCard(
                    title: metrics.simulationActive ? "Huecos tras SA" : "Huecos libres",
                    value: "\(metrics.simulationActive ? metrics.simulationRemainingFreeCount : metrics.totalLibres)",
                    caption: metrics.simulationActive ? "Disponibles libres" : "Para planificar",
                    icon: "plus.circle.dashed",
                    tint: (metrics.simulationActive ? metrics.simulationRemainingFreeCount : metrics.totalLibres) > 0 ? Color.blue : Color.secondary
                )
            }

            // Diagnostic feedback banner
            if metrics.simulationActive {
                simulationFeedbackBanner(metrics)
            }
        }
    }

    private func metricCard(title: String, value: String, caption: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plannerGlassPanel(.content, cornerRadius: 14)
    }

    private func simulationFeedbackBanner(_ metrics: TermCapacityMetrics) -> some View {
        HStack(spacing: 10) {
            if metrics.simulationOverflowCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alerta de calendario: \(metrics.simulationOverflowCount) sesiones caen fuera de plazo")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("La SA tiene \(metrics.simulationSessionCount) sesiones y sobrepasa la fecha límite. Compacta sesiones o adelanta el inicio.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            } else if metrics.simulationRemainingFreeCount > 0 {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.yellow)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encaje holgado: te quedan \(metrics.simulationRemainingFreeCount) clases libres antes de la evaluación")
                        .font(.subheadline.weight(.semibold))
                    Text("Puedes crear sesiones extra de refuerzo, coevaluación o torneos comodín en los huecos libres.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(EvaluationDesign.success)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encaje óptimo: la SA ocupa exactamente los huecos disponibles")
                        .font(.subheadline.weight(.semibold))
                    Text("Las \(metrics.simulationSessionCount) sesiones finalizan dentro del periodo de evaluación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            metrics.simulationOverflowCount > 0
                ? Color.orange.opacity(0.9)
                : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Slots Timeline

    private var slotsTimeline: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 16) {
                // Group slots by week
                ForEach(groupedSlotsByWeek, id: \.weekKey) { weekGroup in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(weekGroup.weekTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(weekGroup.dateRange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(weekGroup.slots) { slot in
                                slotRow(slot)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, EvaluationDesign.screenPadding)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Slot Row Card

    private func slotRow(_ slot: TermClassSlot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Day and time badge
            VStack(alignment: .center, spacing: 2) {
                Text(dayAbbreviation(slot.dayOfWeek))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(dayOfMonth(slot.date))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(monthAbbreviation(slot.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(slot.startTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 54)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Main Content by Kind
            switch slot.kind {
            case .holiday(let name):
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.title3)
                        .foregroundStyle(Color.red.opacity(0.8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(Color.red.opacity(0.9))
                        Text("Día no lectivo / Festivo · No gasta clase lectiva")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

            case .schoolEvent(let title):
                HStack(spacing: 12) {
                    Image(systemName: "flag.badge.ellipsis")
                        .font(.title3)
                        .foregroundStyle(Color.orange.opacity(0.8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Color.orange.opacity(0.9))
                        Text("Actividad complementaria / Centro · No lectivo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

            case .occupied(let session):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let index = slot.lessonIndex {
                            Text("Clase #\(index)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EvaluationDesign.accentSoft, in: Capsule())
                                .foregroundStyle(EvaluationDesign.accent)
                        }

                        Text(session.teachingUnitName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer()

                        if !session.linkedAssessmentIdsCsv.isEmpty {
                            Label("Hito de evaluación", systemImage: "medal.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.orange)
                        }
                    }

                    if !session.objectives.isEmpty {
                        Text(session.objectives)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenSession(session)
                }

            case .preview(let sessionNumber, let title, let objective, let hasEval, _):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let index = slot.lessonIndex {
                            Text("Clase #\(index)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.purple)
                        }

                        Text("Previsión: Sesión \(sessionNumber) · \(title)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.purple)
                            .lineLimit(1)

                        Spacer()

                        if slot.isAfterEvaluationDeadline {
                            Text("Fuera de plazo")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.red)
                        } else if hasEval {
                            Label("Evaluación prevista", systemImage: "pencil.and.ruler.fill")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.orange)
                        }
                    }

                    if !objective.isEmpty {
                        Text(objective)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

            case .free:
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let index = slot.lessonIndex {
                            Text("Clase #\(index) · Hueco disponible")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.success)
                        } else {
                            Text("Hueco disponible")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(EvaluationDesign.success)
                        }
                        Text("Horario lectivo sin contenido asignado")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        vm.addExtraSession(at: slot)
                    } label: {
                        Label("Crear sesión extra", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(EvaluationDesign.success)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plannerGlassPanel(
            .content,
            cornerRadius: 14,
            tint: slotRowTint(slot),
            isInteractive: slotIsPreview(slot)
        )
        .overlay {
            if slotIsFree(slot) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(EvaluationDesign.success.opacity(0.4))
            } else if slotIsPreview(slot) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Floating Simulation Bar

    private var floatingSimulationBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.purple)
                    Text(vm.termCapacityMetrics?.simulationSituationTitle ?? "Simulación de SA")
                        .font(.headline)
                }
                Text("\(vm.termCapacityMetrics?.simulationSessionCount ?? 0) sesiones proyectadas en los huecos libres")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .cancel) {
                Task { await vm.clearSimulation() }
            } label: {
                Text("Descartar")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Button {
                showingApplyConfirmation = true
            } label: {
                if vm.isApplyingSimulation {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Aplicar al Calendario")
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.purple)
            .disabled(vm.isApplyingSimulation)
        }
        .padding(16)
        .plannerGlassPanel(.content, cornerRadius: 18, isInteractive: true)
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        .confirmationDialog(
            "¿Fijar sesiones en el calendario?",
            isPresented: $showingApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Aplicar y guardar en calendario") {
                Task {
                    _ = await vm.applySimulatedSituation()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Las sesiones simuladas se guardarán en la agenda del grupo en las fechas proyectadas.")
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Calculando disponibilidad y encaje de la evaluación…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.orange)
            Text("No se pudo cargar el tablero")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Reintentar") {
                Task { await reloadData() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sin clases detectadas en este periodo")
                .font(.headline)
            Text("Asegúrate de haber configurado las franjas horarias de este grupo en Ajustes de agenda.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func reloadData() async {
        if let bridge = vm.bridge {
            availableSituations = (try? await bridge.learningSituations()) ?? []
        }
        await vm.loadTermBoard()
    }

    private struct WeekSlotGroup: Identifiable {
        var id: String { weekKey }
        let weekKey: String
        let weekTitle: String
        let dateRange: String
        let slots: [TermClassSlot]
    }

    private var groupedSlotsByWeek: [WeekSlotGroup] {
        let calendar = Calendar(identifier: .iso8601)
        let grouped = Dictionary(grouping: vm.termBoardSlots) { slot in
            let week = calendar.component(.weekOfYear, from: slot.date)
            let year = calendar.component(.yearForWeekOfYear, from: slot.date)
            return "\(year)-W\(week)"
        }

        let sortedKeys = grouped.keys.sorted()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        dateFormatter.calendar = calendar

        return sortedKeys.compactMap { key -> WeekSlotGroup? in
            guard let slots = grouped[key]?.sorted(by: { $0.date < $1.date }), let first = slots.first, let last = slots.last else { return nil }
            let weekNum = calendar.component(.weekOfYear, from: first.date)
            let weekTitle = "Semana \(weekNum)"
            let range = "\(dateFormatter.string(from: first.date)) – \(dateFormatter.string(from: last.date))"
            return WeekSlotGroup(weekKey: key, weekTitle: weekTitle, dateRange: range, slots: slots)
        }
    }

    private func dayAbbreviation(_ day: Int) -> String {
        switch day {
        case 1: return "LUN"
        case 2: return "MAR"
        case 3: return "MIÉ"
        case 4: return "JUE"
        case 5: return "VIE"
        case 6: return "SÁB"
        default: return "DOM"
        }
    }

    private func dayOfMonth(_ date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        return "\(calendar.component(.day, from: date))"
    }

    private func monthAbbreviation(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.calendar = Calendar(identifier: .iso8601)
        return formatter.string(from: date).uppercased()
    }

    private func slotIsFree(_ slot: TermClassSlot) -> Bool {
        if case .free = slot.kind { return true }
        return false
    }

    private func slotIsPreview(_ slot: TermClassSlot) -> Bool {
        if case .preview = slot.kind { return true }
        return false
    }

    private func slotRowTint(_ slot: TermClassSlot) -> Color? {
        switch slot.kind {
        case .holiday: return Color.red.opacity(0.04)
        case .preview: return Color.purple.opacity(0.06)
        case .occupied: return nil
        case .free: return EvaluationDesign.success.opacity(0.03)
        case .schoolEvent: return Color.orange.opacity(0.04)
        }
    }
}
