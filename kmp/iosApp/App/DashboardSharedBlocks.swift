import SwiftUI
import MiGestorKit

// MARK: - Capa de bloques compartida entre el Dashboard de iPad (DashboardView)
// y el de macOS (MacDashboardView).
//
// Antes de esto, macOS no tenía Resumen por grupo, Agenda docente, Educación
// Física ni Auditoría LOMLOE — esos bloques solo existían en iPad, duplicados
// a mano cada vez que se querían llevar a macOS. Este archivo los saca de
// DashboardView a funciones libres para que ambas plataformas rendericen
// exactamente la misma vista sobre el mismo `DashboardSnapshot` del backend,
// cada una con su propia forma de navegar (onOpenModule) y su propio
// `colorScheme`.
//
// El "Ahora" de macOS (franja horaria activa/próxima) y el System/Sistema de
// cada plataforma se quedan fuera a propósito: dependen de datos que no
// tienen equivalente en el otro lado (horario fijo del profesor en macOS,
// almacén de backups en macOS) y forzar una única vista ahí habría sido
// una regresión, no una unificación.

struct DashboardGroupRow: Identifiable {
    let id: Int64
    let groupName: String
    let attendancePct: Int
    let evaluationCompletedPct: Int
    let averageScore: Double
    let studentsInFollowUp: Int
}

// MARK: - Modo operativo (Clase / Despacho)

/// Lo que el usuario elige. `auto` es el valor por defecto: el modo se deduce
/// del horario, así que al entrar en el aula el dashboard ya está en Clase sin
/// tocar nada. Las otras dos opciones son una anulación manual.
enum DashboardModePreference: String, CaseIterable, Identifiable {
    case auto
    case classroom
    case office

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .classroom: return "Clase"
        case .office: return "Despacho"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .classroom: return "figure.run"
        case .office: return "tray.full"
        }
    }

    /// Con `auto`, hay clase en curso -> Clase; cualquier otra cosa ->
    /// Despacho. Si el horario no da contexto, se cae a Despacho en vez de
    /// dejar una pantalla vacía.
    func resolved(for context: DashboardSessionContext?) -> DashboardMode {
        switch self {
        case .classroom: return .classroom
        case .office: return .office
        case .auto:
            guard let context else { return .office }
            return context.status == .active ? .classroom : .office
        }
    }

    /// Etiqueta que explica qué ha decidido el automático, para que el usuario
    /// no tenga que adivinar por qué ve una cosa u otra.
    func resolvedHint(for context: DashboardSessionContext?) -> String? {
        guard self == .auto else { return nil }
        return resolved(for: context) == .classroom ? "Auto · Clase en curso" : "Auto · Despacho"
    }
}

// MARK: - Contexto "Ahora"

func dashboardContextStatusLabel(_ status: DashboardSessionContextStatus) -> String {
    switch status {
    case .active: return "En curso"
    case .nextToday: return "Hoy"
    case .nextOtherDay: return "Próxima"
    case .noSchedule: return "Sin horario"
    case .outsideSchoolYear: return "Fuera de curso"
    default: return "Sin horario"
    }
}

func dashboardContextStatusTint(_ status: DashboardSessionContextStatus) -> Color {
    switch status {
    case .active: return EvaluationDesign.success
    case .nextToday, .nextOtherDay: return EvaluationDesign.accent
    default: return IOSAppStyle.warning
    }
}

func dashboardContextDayLabel(_ day: Int?) -> String {
    switch day {
    case 1: return "Lunes"
    case 2: return "Martes"
    case 3: return "Miércoles"
    case 4: return "Jueves"
    case 5: return "Viernes"
    case 6: return "Sábado"
    case 7: return "Domingo"
    default: return "Día"
    }
}

func dashboardContextTitle(_ context: DashboardSessionContext) -> String {
    switch context.status {
    case .active: return context.className.isEmpty ? "Clase actual" : context.className
    case .nextToday, .nextOtherDay: return "Próxima clase"
    case .outsideSchoolYear: return "Fuera de curso"
    default: return "Sin horario"
    }
}

func dashboardContextSubtitle(_ context: DashboardSessionContext) -> String {
    let parts = [
        context.className.isEmpty ? nil : context.className,
        context.subjectLabel,
        context.unitLabel,
    ].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? "Sin detalle de grupo" : parts.joined(separator: " · ")
}

// MARK: - Cromado

/// Nivel "contexto, no acción": `.thinMaterial`, sin sombra de color, para
/// que se lea un escalón por debajo de los bloques "hay que actuar".
struct DashboardSecondaryCardChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(EvaluationDesign.cardSpacing)
            .background(.thinMaterial)
            .cornerRadius(EvaluationDesign.innerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05), lineWidth: 1)
            )
    }
}

@ViewBuilder
func dashboardSecondaryCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content().modifier(DashboardSecondaryCardChrome())
}

func dashboardSecondaryTitle(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
}

// MARK: - Helpers de alerta/severidad compartidos

func dashboardFilterLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case "high": return "Alta"
    case "medium": return "Media"
    case "low": return "Baja"
    default: return raw.isEmpty ? "Sin clasificar" : raw
    }
}

func riskTint(_ raw: String) -> Color {
    switch raw.lowercased() {
    case "high": return .red
    case "medium": return .orange
    default: return .yellow
    }
}

/// Empareja una alerta con el `AgendaItem` ("recordatorio") que el backend
/// genera a partir de ella para transportar sus `navigationTargets` (rúbrica
/// + alumno pendientes de evaluar). El backend no enlaza ambos por id, así
/// que el emparejamiento se hace por contenido (mismo grupo, título y
/// detalle), suficiente porque el `AgendaItem` "recordatorio" siempre se
/// construye 1:1 desde la alerta.
func agendaNavigationTargets(for alert: AlertItem, snapshot: DashboardSnapshot) -> [AgendaNavigationTarget] {
    snapshot.agendaItems.first {
        $0.type == "recordatorio"
            && $0.title == alert.title
            && $0.subtitle == alert.detail
            && $0.classId?.int64Value == alert.classId?.int64Value
    }?.navigationTargets ?? []
}

func navigateAlert(
    _ alert: AlertItem,
    snapshot: DashboardSnapshot,
    onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
) {
    let targets = agendaNavigationTargets(for: alert, snapshot: snapshot)
    if let target = targets.first {
        onOpenModule(.rubrics, target.classId?.int64Value, target.studentId?.int64Value)
        return
    }
    if let studentId = alert.studentId?.int64Value {
        onOpenModule(.students, alert.classId?.int64Value, studentId)
        return
    }
    if let classId = alert.classId?.int64Value {
        onOpenModule(.notebook, classId, nil)
    }
}

func navigateAgendaItem(_ item: AgendaItem, onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void) {
    if let target = item.navigationTargets.first {
        onOpenModule(.rubrics, target.classId?.int64Value, target.studentId?.int64Value)
        return
    }
    let classId = item.classId?.int64Value
    switch item.type {
    case "sesion":
        onOpenModule(.attendance, classId, nil)
    case "revision":
        onOpenModule(.planner, classId, nil)
    default:
        guard let classId else { return }
        onOpenModule(.notebook, classId, nil)
    }
}

/// Los `PEOperationalItem` del backend nunca llevan `classId` (se agregan a
/// nivel de todas las clases de EF), así que la navegación solo puede llevar
/// al módulo relevante, no a un grupo o alumno concretos.
func peDestination(for item: PEOperationalItem) -> AppWorkspaceModule? {
    switch item.type {
    case "incidencias_fisicas":
        return .peIncidents
    case "exentos_adaptacion":
        return .students
    case "prueba_rubrica_activa":
        return .peRubrics
    case "material_hoy":
        return .peMaterial
    default:
        return nil
    }
}

func trendDirectionInfo(_ direction: String, delta: Double) -> (icon: String, label: String, color: Color) {
    switch direction {
    case "UPWARD":
        return ("arrow.up.right", "Al alza (+ \(IosFormatting.decimal(from: delta)))", .green)
    case "DOWNWARD":
        return ("arrow.down.right", "A la baja (- \(IosFormatting.decimal(from: abs(delta))))", .red)
    case "STABLE":
        return ("arrow.right", "Estable", .blue)
    default:
        return ("questionmark.circle", "Datos insuficientes", .gray)
    }
}

func trendBgColor(_ direction: String) -> Color {
    switch direction {
    case "UPWARD": return .green
    case "DOWNWARD": return .red
    case "STABLE": return .blue
    default: return .gray
    }
}

// MARK: - Tarjeta "Ahora"

/// Acciones que ofrece la tarjeta "Ahora". Se declaran aquí, sin destinos de
/// plataforma, para que iPad y Mac ofrezcan las mismas y cada uno las resuelva
/// con su propia navegación.
enum DashboardNowAction: String, Identifiable {
    case passList
    case openNotebook
    case evaluate
    case observation
    case quickEvaluation
    case openPlanner
    case openJournal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passList: return "Pasar lista"
        case .openNotebook: return "Abrir cuaderno"
        case .evaluate: return "Evaluar"
        case .observation: return "Observación"
        case .quickEvaluation: return "Evaluación rápida"
        case .openPlanner: return "Abrir Planner"
        case .openJournal: return "Diario"
        }
    }

    var systemImage: String {
        switch self {
        case .passList: return "checkmark.circle"
        case .openNotebook: return "tablecells"
        case .evaluate: return "checklist.checked"
        case .observation: return "note.text.badge.plus"
        case .quickEvaluation: return "sparkles"
        case .openPlanner: return "calendar"
        case .openJournal: return "doc.text"
        }
    }
}

/// La tarjeta "Ahora": qué clase tengo delante, qué sesión toca y los tres
/// botones que se usan de verdad con el grupo en el aula. Hasta ahora solo
/// existía en macOS, escrita contra un modelo Swift propio; ahora lee el
/// `DashboardSessionContext` del snapshot compartido y la pintan las dos
/// plataformas.
@ViewBuilder
func dashboardNowCard(
    context: DashboardSessionContext?,
    colorScheme: ColorScheme,
    isCompact: Bool,
    onAction: @escaping (DashboardNowAction) -> Void
) -> some View {
    let tint = context.map { dashboardContextStatusTint($0.status) } ?? IOSAppStyle.warning

    VStack(alignment: .leading, spacing: 16) {
        if let context {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(dashboardContextTitle(context))
                        .font(.system(size: isCompact ? 22 : 26, weight: .bold, design: .rounded))
                    Text(dashboardContextSubtitle(context))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let start = context.startTime, let end = context.endTime {
                        Label(
                            "\(dashboardContextDayLabel(context.dayOfWeek?.intValue)) · \(start)-\(end)",
                            systemImage: "clock"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(dashboardContextStatusLabel(context.status))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }

            if dashboardContextHasNoClass(context.status) {
                // Sin horario o fuera del rango del curso no hay grupo al que
                // apuntar: ofrecer "Pasar lista" o "Evaluar" en gris es un
                // callejón sin salida. Se enseña la salida real.
                dashboardNowScheduleGap(status: context.status, onAction: onAction)
            } else {
                if context.isFromPlannedSession {
                    dashboardNowPlannedSession(context: context, colorScheme: colorScheme)
                } else if context.status == .active {
                    dashboardNowMissingSession(onAction: onAction)
                }

                dashboardNowActions(context: context, onAction: onAction)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sin clase activa", systemImage: "calendar")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("No hay franja lectiva en el horario docente para este momento.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Configurar horario") { onAction(.openPlanner) }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding(EvaluationDesign.cardSpacing)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(appCardBackground(for: colorScheme))
    .cornerRadius(EvaluationDesign.innerRadius)
    .overlay(
        RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
            .stroke(tint.opacity(0.25), lineWidth: 1)
    )
}

/// Estados en los que el horario no señala ninguna clase concreta.
func dashboardContextHasNoClass(_ status: DashboardSessionContextStatus) -> Bool {
    switch status {
    case .active, .nextToday, .nextOtherDay: return false
    default: return true
    }
}

@ViewBuilder
private func dashboardNowScheduleGap(
    status: DashboardSessionContextStatus,
    onAction: @escaping (DashboardNowAction) -> Void
) -> some View {
    let outsideYear = status == .outsideSchoolYear
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: "calendar.badge.exclamationmark")
            .foregroundStyle(IOSAppStyle.warning)
        VStack(alignment: .leading, spacing: 4) {
            Text(outsideYear
                 ? "Hoy queda fuera de las fechas del curso configurado."
                 : "Todavía no hay horario docente configurado.")
                .font(.callout.weight(.semibold))
            Text(outsideYear
                 ? "El resto del dashboard sigue disponible: el trabajo pendiente no desaparece."
                 : "Crea tus franjas para que el dashboard sepa qué clase tienes en cada momento.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Button(outsideYear ? "Editar agenda docente" : "Configurar horario") {
            onAction(.openPlanner)
        }
        .buttonStyle(.borderedProminent)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(IOSAppStyle.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

@ViewBuilder
private func dashboardNowPlannedSession(context: DashboardSessionContext, colorScheme: ColorScheme) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Label("Sesión planificada", systemImage: "calendar.badge.checkmark")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        Text(context.sessionTitle ?? context.unitLabel ?? "Sesión")
            .font(.callout.weight(.semibold))
        if let subtitle = context.sessionSubtitle {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let status = context.sessionStatusLabel {
            Text(status)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(EvaluationDesign.accent.opacity(0.14), in: Capsule())
        }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

@ViewBuilder
private func dashboardNowMissingSession(onAction: @escaping (DashboardNowAction) -> Void) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: "calendar.badge.plus")
            .foregroundStyle(IOSAppStyle.warning)
        VStack(alignment: .leading, spacing: 4) {
            Text("No hay sesión planificada para esta franja.")
                .font(.callout.weight(.semibold))
            Text("Puedes seguir con el horario fijo o crearla en el Planner.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Button("Crear sesión") { onAction(.openPlanner) }
            .buttonStyle(.bordered)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(IOSAppStyle.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

@ViewBuilder
private func dashboardNowActions(
    context: DashboardSessionContext,
    onAction: @escaping (DashboardNowAction) -> Void
) -> some View {
    // La tarjeta Ahora debe responder una sola pregunta: "¿qué hago ahora?".
    // El resto de acciones siguen disponibles, pero no compiten con la acción
    // que corresponde al estado de la franja lectiva.
    let primaryAction: DashboardNowAction = context.status == .active
        ? .passList
        : .openNotebook
    let secondaryActions: [DashboardNowAction] = context.status == .active
        ? [.observation, .evaluate, .openNotebook]
        : [.openPlanner]

    VStack(alignment: .leading, spacing: 8) {
        Text(dashboardNowPrimaryHint(for: context))
            .font(.caption)
            .foregroundStyle(.secondary)

        Button {
            onAction(primaryAction)
        } label: {
            HStack(spacing: 12) {
                Label(
                    dashboardNowPrimaryTitle(for: primaryAction, context: context),
                    systemImage: primaryAction.systemImage
                )
                .font(.headline)

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(EvaluationDesign.accent)
        .disabled(context.classId == nil)
        .accessibilityHint(dashboardNowPrimaryHint(for: context))

        Menu {
            ForEach(secondaryActions) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
                .disabled(context.classId == nil)
            }

            if let sessionId = context.sessionId, context.status == .active {
                Divider()
                Button {
                    onAction(.openJournal)
                } label: {
                    Label(
                        DashboardNowAction.openJournal.title,
                        systemImage: DashboardNowAction.openJournal.systemImage
                    )
                }
                .accessibilityLabel("Abrir diario de la sesión \(sessionId)")
            }
        } label: {
            Label("Más acciones", systemImage: "ellipsis.circle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
    }
}

private func dashboardNowPrimaryTitle(
    for action: DashboardNowAction,
    context: DashboardSessionContext
) -> String {
    if action == .openNotebook && context.status != .active {
        return "Preparar cuaderno"
    }
    return action.title
}

private func dashboardNowPrimaryHint(for context: DashboardSessionContext) -> String {
    switch context.status {
    case .active:
        return "Empieza por registrar la asistencia del grupo."
    case .nextToday:
        return "Deja preparado el grupo para la próxima clase de hoy."
    case .nextOtherDay:
        return "Deja preparado el grupo para la próxima clase."
    default:
        return "Elige la siguiente acción para continuar."
    }
}

// MARK: - KPI row

@ViewBuilder
func dashboardKpiRow(snapshot: DashboardSnapshot, colorScheme: ColorScheme) -> some View {
    HStack(spacing: 12) {
        dashboardKpiCard(title: "Hoy", value: "\(snapshot.todayCount)", isNumeric: true, colorScheme: colorScheme)
        dashboardKpiCard(title: "Alertas", value: "\(snapshot.alertsCount)", isNumeric: true, colorScheme: colorScheme)
        dashboardKpiCard(title: "Pendientes", value: "\(snapshot.pendingCount)", isNumeric: true, colorScheme: colorScheme)
        dashboardKpiCard(title: "Próxima sesión", value: snapshot.nextSessionLabel, isNumeric: false, colorScheme: colorScheme)
    }
}

@ViewBuilder
private func dashboardKpiCard(title: String, value: String, isNumeric: Bool, colorScheme: ColorScheme) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.footnote).foregroundStyle(.secondary)
        if isNumeric {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
        } else {
            Text(value).font(.headline).lineLimit(2)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(appCardBackground(for: colorScheme))
    .cornerRadius(12)
}

// MARK: - Resumen por grupo

@ViewBuilder
func dashboardGroupSummaryBlock(snapshot: DashboardSnapshot, isWide: Bool) -> some View {
    let rows = snapshot.groupSummaries.map {
        DashboardGroupRow(
            id: $0.classId,
            groupName: $0.groupName,
            attendancePct: Int($0.attendancePct),
            evaluationCompletedPct: Int($0.evaluationCompletedPct),
            averageScore: $0.averageScore,
            studentsInFollowUp: Int($0.studentsInFollowUp)
        )
    }
    dashboardSecondaryCard {
        VStack(alignment: .leading, spacing: 12) {
            dashboardSecondaryTitle("Resumen por grupo", systemImage: "person.3")
            if isWide {
                Table(rows) {
                    TableColumn("Grupo") { Text($0.groupName) }
                    TableColumn("Asist") { Text("\($0.attendancePct)%") }
                    TableColumn("Eval") { Text("\($0.evaluationCompletedPct)%") }
                    TableColumn("Media") { Text(IosFormatting.decimal(from: $0.averageScore)) }
                    TableColumn("Seguim.") { Text("\($0.studentsInFollowUp)") }
                }
                .frame(minHeight: 180)
            } else {
                ForEach(rows) { summary in
                    HStack {
                        Text(summary.groupName).bold()
                        Spacer()
                        Text("As \(summary.attendancePct)% · Ev \(summary.evaluationCompletedPct)%")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
            if snapshot.groupSummaries.isEmpty {
                Text("Sin datos de grupos")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Agenda docente

@ViewBuilder
func dashboardAgendaBlock(
    snapshot: DashboardSnapshot,
    colorScheme: ColorScheme,
    onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void
) -> some View {
    dashboardSecondaryCard {
        VStack(alignment: .leading, spacing: 12) {
            dashboardSecondaryTitle("Agenda docente", systemImage: "list.bullet.clipboard")
            ForEach(snapshot.agendaItems, id: \.id) { item in
                let isNavigable = !item.navigationTargets.isEmpty || item.classId != nil
                Button {
                    navigateAgendaItem(item, onOpenModule: onOpenModule)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(item.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.timeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        if isNavigable {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        appMutedCardBackground(for: colorScheme)
                            .overlay(
                                RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                            )
                    )
                    .cornerRadius(EvaluationDesign.pillRadius)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!isNavigable)
            }
            if snapshot.agendaItems.isEmpty {
                Text("Sin agenda para hoy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Educación Física

@ViewBuilder
func dashboardPEBlock(
    snapshot: DashboardSnapshot,
    colorScheme: ColorScheme,
    onSelectItem: @escaping (PEOperationalItem) -> Void
) -> some View {
    dashboardSecondaryCard {
        VStack(alignment: .leading, spacing: 12) {
            dashboardSecondaryTitle("Educación Física", systemImage: "figure.run")
            ForEach(snapshot.peItems, id: \.id) { item in
                Button {
                    onSelectItem(item)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(item.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dashboardFilterLabel(item.severity))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(riskTint(item.severity).opacity(0.12), in: Capsule())
                            .foregroundStyle(riskTint(item.severity))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        appMutedCardBackground(for: colorScheme)
                            .overlay(
                                RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                            )
                    )
                    .cornerRadius(EvaluationDesign.pillRadius)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            if snapshot.peItems.isEmpty {
                Text("Sin incidencias EF hoy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Auditoría LOMLOE

@ViewBuilder
func dashboardLomloeAuditBlock(
    trends: KmpBridge.AITrendsSnapshot?,
    isLoading: Bool,
    loadFailed: Bool,
    onRetry: @escaping () -> Void
) -> some View {
    dashboardSecondaryCard {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dashboardSecondaryTitle("Auditoría LOMLOE y Alertas del Grupo", systemImage: "text.badge.checkmark")
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(NotebookStyle.primaryTint)
                }
            }

            if let trends {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        let directionInfo = trendDirectionInfo(trends.trendDirection, delta: trends.averageGradeDelta)
                        Image(systemName: directionInfo.icon)
                            .foregroundStyle(directionInfo.color)
                        Text("Trayectoria: \(directionInfo.label)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(directionInfo.color)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(trendBgColor(trends.trendDirection).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cobertura Curricular del Grupo")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(IosFormatting.decimal(from: trends.curriculumCoveragePct))%")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(NotebookStyle.primaryTint)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Asistencia Media")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(IosFormatting.decimal(from: trends.attendanceRate))%")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(trends.attendanceRate >= 85 ? Color.primary : Color.orange)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(NotebookStyle.softBorder)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(NotebookStyle.primaryTint)
                                .frame(width: geo.size.width * CGFloat(trends.curriculumCoveragePct / 100.0), height: 8)
                        }
                    }
                    .frame(height: 8)

                    if !trends.attendanceCorrelationNote.isEmpty {
                        Text(trends.attendanceCorrelationNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if !trends.behaviorIncidentSummary.isEmpty {
                        Text(trends.behaviorIncidentSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if !trends.missingCompetencyLabels.isEmpty {
                        Divider()
                            .background(NotebookStyle.softBorder)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Competencias clave sin evidencias en el grupo:")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            FlexibleTagRow(
                                items: trends.missingCompetencyLabels,
                                selected: ""
                            ) { _ in }
                            .disabled(true)
                        }
                    }
                }
            } else if loadFailed {
                HStack(spacing: 10) {
                    Label("No se pudo cargar la auditoría de este grupo.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IOSAppStyle.warning)
                    Spacer()
                    Button("Reintentar") {
                        onRetry()
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
            } else if !isLoading {
                Text("No hay datos suficientes para generar la auditoría de cobertura curricular y tendencias de este grupo.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
