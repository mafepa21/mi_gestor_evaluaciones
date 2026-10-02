import SwiftUI
import MiGestorKit

/// Hoja interactiva para previsualizar y aplicar el preset de calendario oficial
/// del claustro 2026-2027 al horario docente.
struct SchoolCalendarPresetSheet: View {
    @ObservedObject var bridge: KmpBridge
    let scheduleId: Int64
    let groups: [SchoolClass]
    let onApplied: (SchoolCalendarPreset2026_2027.ApplyResult) -> Void
    let onDismiss: () -> Void

    @State private var selectedStage: SchoolCalendarPreset2026_2027.Stage = .eso
    @State private var applyEvaluations = true
    @State private var applyTrips = true
    @State private var selectedTripIds: Set<String> = []
    @State private var applySchoolEvents = true
    @State private var applyMilestones = true
    @State private var isApplying = false
    @State private var errorMessage = ""

    private var resolvedTrips: [(trip: SchoolCalendarPreset2026_2027.TripPreset, matchingClasses: [SchoolClass])] {
        SchoolCalendarPreset2026_2027.resolveTripsForTeacher(groups: groups)
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !errorMessage.isEmpty {
                        errorBanner
                    }

                    evaluationsSection
                    tripsSection
                    schoolEventsSection
                    milestonesSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()
            sheetFooter
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 640)
        .task {
            selectedStage = SchoolCalendarPreset2026_2027.detectSuggestedStage(for: groups)
            selectedTripIds = Set(resolvedTrips.map(\.trip.id))
        }
    }

    // MARK: - Cabecera

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(EvaluationDesign.accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(EvaluationDesign.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendario oficial 2026–2027")
                        .font(.title3.weight(.bold))
                    Text("Fechas de evaluación, salidas e hitos acordados en claustro")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Label("Cerrar", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - Banner de error

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(EvaluationDesign.danger)
            Text(errorMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(EvaluationDesign.danger)
            Spacer()
        }
        .padding(12)
        .background(EvaluationDesign.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 1. Periodos de evaluación

    private var evaluationsSection: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1. Periodos de evaluación")
                            .font(.callout.weight(.bold))
                        Text("Genera los 3 trimestres oficiales con cómputo de sesiones")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $applyEvaluations)
                        .labelsHidden()
                }

                if applyEvaluations {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Etapa educativa", selection: $selectedStage) {
                            ForEach(SchoolCalendarPreset2026_2027.Stage.allCases) { stage in
                                Text(stage.title).tag(stage)
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 8) {
                            ForEach(selectedStage.periods) { period in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(period.name)
                                            .font(.caption.weight(.bold))
                                        Text(period.notes)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(period.startDateIso) al \(period.endDateIso)")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(EvaluationDesign.accent)
                                }
                                .padding(10)
                                .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. Salidas y viajes de curso

    private var tripsSection: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2. Salidas y viajes por curso")
                            .font(.callout.weight(.bold))
                        Text("Se asocian solo a sus grupos; no bloquean clases en otros cursos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $applyTrips)
                        .labelsHidden()
                }

                if applyTrips {
                    if resolvedTrips.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("Tus grupos actuales no tienen viajes de varios días asignados en el claustro (ej. Toledo es para 2º ESO y Pirineos para 4º ESO).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(resolvedTrips, id: \.trip.id) { item in
                                let isSelected = selectedTripIds.contains(item.trip.id)
                                Button {
                                    if isSelected {
                                        selectedTripIds.remove(item.trip.id)
                                    } else {
                                        selectedTripIds.insert(item.trip.id)
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(isSelected ? EvaluationDesign.accent : .secondary)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.trip.title)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.primary)
                                            Text(item.trip.dateRangeSummary)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                            HStack(spacing: 4) {
                                                Text("Afecta a:")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                ForEach(item.matchingClasses, id: \.id) { group in
                                                    Text(group.name)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(EvaluationDesign.accent.opacity(0.12), in: Capsule(style: .continuous))
                                                        .foregroundStyle(EvaluationDesign.accent)
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. Hitos colegiales y festivos

    private var schoolEventsSection: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3. Festivos e hitos colegiales")
                            .font(.callout.weight(.bold))
                        Text("Convivencias de inicio, Día HHDC, festival de Navidad, Día de la Paz y Fallas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $applySchoolEvents)
                        .labelsHidden()
                }

                if applySchoolEvents {
                    VStack(spacing: 6) {
                        ForEach(SchoolCalendarPreset2026_2027.schoolWideEvents) { event in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.caption.weight(.semibold))
                                    Text(event.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(event.dateSummary)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(event.isNonTeaching ? Color.orange : .secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. Hitos de claustro e informativos

    private var milestonesSection: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("4. Reuniones y límites de notas Educamos")
                            .font(.callout.weight(.bold))
                        Text("Hitos informativos para el docente (no anulan clases lectivas)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $applyMilestones)
                        .labelsHidden()
                }

                if applyMilestones {
                    VStack(spacing: 6) {
                        ForEach(SchoolCalendarPreset2026_2027.teacherMilestones) { milestone in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(milestone.title)
                                        .font(.caption.weight(.semibold))
                                    Text(milestone.description)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(milestone.dateSummary)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pie con acción

    private var sheetFooter: some View {
        HStack {
            Button("Cancelar") {
                onDismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button {
                apply()
            } label: {
                if isApplying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Aplicando…")
                    }
                } else {
                    Text("Aplicar al horario")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isApplying || (!applyEvaluations && selectedTripIds.isEmpty && !applySchoolEvents && !applyMilestones))
        }
        .padding(20)
    }

    private func apply() {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = ""

        Task {
            do {
                let result = try await SchoolCalendarPreset2026_2027.applyPreset(
                    bridge: bridge,
                    scheduleId: scheduleId,
                    stage: selectedStage,
                    applyEvaluations: applyEvaluations,
                    selectedTripIds: applyTrips ? selectedTripIds : [],
                    groups: groups,
                    applySchoolEvents: applySchoolEvents,
                    applyMilestones: applyMilestones
                )
                await MainActor.run {
                    isApplying = false
                    onApplied(result)
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    errorMessage = "Error al aplicar preset: \(error.localizedDescription)"
                }
            }
        }
    }
}
