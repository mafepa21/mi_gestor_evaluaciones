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
                TermBoardMetricsStrip(metrics: metrics)
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
                TermBoardTimelineView(
                    slots: vm.termBoardSlots,
                    onOpenSession: onOpenSession,
                    onAddExtraSession: { vm.addExtraSession(at: $0) }
                )
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
}
