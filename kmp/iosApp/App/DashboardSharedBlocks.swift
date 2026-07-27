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
