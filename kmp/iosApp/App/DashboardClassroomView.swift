import SwiftUI
import MiGestorKit

/// Modo Clase: lo que hace falta con el grupo delante y nada más.
/// Minutos restantes en grande, grupo, barra de progreso, tres fichas
/// (asistencia, pendientes, alumnos con alerta) y tres acciones. Una sola
/// acción principal (Pasar lista); el resto, de cristal.
///
/// La usan iPad y Mac con el mismo inicializador; `studentNames` es opcional
/// (solo afina el detalle de la ficha de alerta).
struct DashboardClassroomView: View {
    let snapshot: DashboardSnapshot
    let colorScheme: ColorScheme
    let isCompact: Bool
    let onAction: (DashboardNowAction) -> Void
    let onExitClassroomMode: () -> Void
    var studentNames: [Int64: String] = [:]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var hugeSize: CGFloat = 128
#if os(iOS)
    @State private var previousIdleTimerDisabled: Bool?
#endif

    private var context: DashboardSessionContext? { snapshot.currentContext }

    private var singleColumn: Bool { isCompact || dynamicTypeSize.isAccessibilitySize }

    private var clock: DashboardSessionClock? {
        DashboardSessionClock(start: context?.startTime, end: context?.endTime)
    }

    private var hasClass: Bool {
        guard let context else { return false }
        return !dashboardContextHasNoClass(context.status)
    }

    private var groupTitle: String {
        guard let context, !context.className.isEmpty else { return "Clase actual" }
        return context.className
    }

    /// Materia y unidad del horario; sin ellas, un texto neutro. (Antes caía a
    /// "Educación Física" para cualquier docente.)
    private var groupSubtitle: String {
        guard let context else { return "Sesión en curso" }
        var parts = [context.subjectLabel, context.unitLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if let end = context.endTime, context.status == .active { parts.append("hasta las \(end)") }
        return parts.isEmpty ? "Sesión en curso" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: DashboardStyle.Spacing.s3) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onExitClassroomMode) {
                    Label("Salir de modo Clase", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(DashboardStyle.Typography.footnoteStrong)
                }
                .dashboardButtonStyle()
                .keyboardShortcut(.cancelAction)
            }

            if hasClass {
                classContent
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: 704)
        .frame(maxWidth: .infinity)
#if os(iOS)
        .onAppear {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled ?? false
        }
#endif
    }

    // MARK: Con clase

    private var classContent: some View {
        let facts = DashboardPresentation.classroomFacts(snapshot: snapshot, studentNames: studentNames)
        return VStack(spacing: DashboardStyle.Spacing.s4) {
            timeBlock
                .dashboardReveal(1)

            VStack(spacing: DashboardStyle.Spacing.micro) {
                Text(groupTitle)
                    .font(DashboardStyle.Typography.largeTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(groupSubtitle)
                    .font(DashboardStyle.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .dashboardReveal(2)

            if context?.status == .active, let clock {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    let state = clock.state(at: timeline.date)
                    DashboardProgressBar(
                        progress: state.progress,
                        elapsedMinutes: state.elapsed,
                        totalMinutes: state.total
                    )
                }
                .frame(maxWidth: 448)
                .dashboardReveal(3)
            }

            tiles(facts)
                .dashboardReveal(4)

            actions
                .dashboardReveal(5)
        }
        .padding(.vertical, DashboardStyle.Spacing.s2)
    }

    @ViewBuilder
    private var timeBlock: some View {
        if let clock {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let state = clock.state(at: timeline.date)
                if context?.status == .active {
                    minutes(
                        caption: "Quedan",
                        value: state.remaining,
                        spoken: state.remaining == 1 ? "Queda 1 minuto" : "Quedan \(state.remaining) minutos"
                    )
                } else {
                    minutes(
                        caption: "Empieza en",
                        value: state.minutesToStart,
                        spoken: state.minutesToStart == 1
                            ? "Falta 1 minuto para empezar"
                            : "Faltan \(state.minutesToStart) minutos para empezar"
                    )
                }
            }
        }
    }

    private func minutes(caption: String, value: Int, spoken: String) -> some View {
        VStack(spacing: 0) {
            Text(caption)
                .font(DashboardStyle.Typography.footnoteStrong)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: hugeSize, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)
            Text("minutos")
                .font(DashboardStyle.Typography.title)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Fichas

    private func tiles(_ facts: DashboardClassroomFacts) -> some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(spacing: DashboardStyle.Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DashboardStyle.Spacing.s2))
        return layout {
            DashboardClassroomTile(
                title: "Asistencia del grupo",
                value: facts.attendanceValue,
                detail: facts.attendanceDetail,
                singleColumn: singleColumn
            )
            DashboardClassroomTile(
                title: "Pendientes de evaluar",
                value: "\(facts.pendingCount)",
                detail: facts.pendingDetail,
                singleColumn: singleColumn
            )
            DashboardClassroomTile(
                title: "Alumnos con alerta",
                value: "\(facts.alertStudentsCount)",
                detail: facts.alertDetail,
                singleColumn: singleColumn
            )
        }
    }

    // MARK: Acciones

    private var actions: some View {
        let layout = (singleColumn || dynamicTypeSize >= .xxLarge)
            ? AnyLayout(VStackLayout(spacing: DashboardStyle.Spacing.s2))
            : AnyLayout(HStackLayout(spacing: DashboardStyle.Spacing.s2))
        return DashboardGlassGroup {
            layout {
                Button {
                    onAction(.passList)
                } label: {
                    Label("Pasar lista", systemImage: DashboardNowAction.passList.systemImage)
                        .font(DashboardStyle.Typography.headline)
                        .frame(maxWidth: singleColumn ? .infinity : nil)
                }
                .dashboardButtonStyle(prominent: true, large: true)
                .disabled(context?.classId == nil)

                Button {
                    onAction(.observation)
                } label: {
                    Label("Nueva observación", systemImage: DashboardNowAction.observation.systemImage)
                        .font(DashboardStyle.Typography.headline)
                        .frame(maxWidth: singleColumn ? .infinity : nil)
                }
                .dashboardButtonStyle(large: true)

                Button {
                    onAction(.quickEvaluation)
                } label: {
                    Label("Evaluación rápida", systemImage: DashboardNowAction.quickEvaluation.systemImage)
                        .font(DashboardStyle.Typography.headline)
                        .frame(maxWidth: singleColumn ? .infinity : nil)
                }
                .dashboardButtonStyle(large: true)
            }
        }
    }

    // MARK: Sin clase

    private var emptyContent: some View {
        VStack(spacing: DashboardStyle.Spacing.s2) {
            Text("No hay clase ahora")
                .font(DashboardStyle.Typography.title)
            Text("Hoy no tienes sesiones en curso.")
                .font(DashboardStyle.Typography.subheadline)
                .foregroundStyle(.secondary)
            Button("Volver a Auto", action: onExitClassroomMode)
                .dashboardButtonStyle(prominent: true, large: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashboardStyle.Spacing.s5)
    }
}

private struct DashboardClassroomTile: View {
    let title: String
    let value: String
    let detail: String
    let singleColumn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = singleColumn
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DashboardStyle.Spacing.s1))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.micro))
        layout {
            Text(title)
                .font(DashboardStyle.Typography.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: singleColumn ? .infinity : nil, alignment: .leading)
            Text(value)
                .font(DashboardStyle.Typography.title)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)
            if !singleColumn {
                Text(detail)
                    .font(DashboardStyle.Typography.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(padding: DashboardStyle.Spacing.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}
