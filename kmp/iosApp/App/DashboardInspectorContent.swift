import SwiftUI
import MiGestorKit

/// Contenido del inspector nativo (`.inspector(isPresented:)`): panel lateral
/// en iPad ancho y Mac, hoja en ancho compacto. Solo enseña detalle y las
/// acciones de navegación del elemento elegido.
struct DashboardInspectorContent: View {
    let snapshot: DashboardSnapshot?
    let selection: DashboardInspectorSelection?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onNewObservation: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
                HStack {
                    Text("Detalle")
                        .font(DashboardStyle.Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: onClose) {
                        Label("Cerrar detalle", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: DashboardStyle.minTapSize, minHeight: DashboardStyle.minTapSize)
                    }
                    .dashboardButtonStyle()
                }

                detail
            }
            .padding(DashboardStyle.Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    @ViewBuilder
    private var detail: some View {
        if let snapshot {
            switch selection {
            case .session(let id):
                if let item = snapshot.todaySessions.first(where: { $0.id == id }) {
                    sessionDetail(item)
                } else {
                    unavailable("Sesión no encontrada")
                }
            case .alert(let id):
                if let alert = snapshot.alerts.first(where: { $0.id == id }) {
                    alertDetail(alert, snapshot: snapshot)
                } else {
                    unavailable("Alerta no encontrada")
                }
            case .pe(let id):
                if let item = snapshot.peItems.first(where: { $0.id == id }) {
                    peDetail(item)
                } else {
                    unavailable("Elemento de Educación Física no encontrado")
                }
            case .attendance(let classId):
                VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
                    Text("Asistencia pendiente de hoy").font(DashboardStyle.Typography.headline)
                    Text("Abre Asistencia para pasar lista; el Dashboard no marca nada automáticamente.")
                        .font(DashboardStyle.Typography.subheadline)
                        .foregroundStyle(.secondary)
                    actions {
                        navigationButton("Pasar lista", "checkmark.circle", prominent: true) {
                            onOpenModule(.attendance, classId, nil)
                        }
                    }
                }
            case .none:
                unavailable("Elige una fila para ver su detalle.")
            }
        } else {
            unavailable("Sin datos")
        }
    }

    private func unavailable(_ text: String) -> some View {
        Text(text)
            .font(DashboardStyle.Typography.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: Sesión

    private func sessionDetail(_ item: TodaySessionItem) -> some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            Text(item.groupName).font(DashboardStyle.Typography.headline)
            if !item.didacticUnit.isEmpty {
                Text(item.didacticUnit).font(DashboardStyle.Typography.subheadline)
            }
            field("Horario", item.timeLabel)
            field("Espacio", item.space)
            field("Estado", sessionStatusLabel(item.sessionStatus))

            let classId = item.classId?.int64Value
            actions {
                navigationButton("Pasar lista", "checkmark.circle", prominent: true) {
                    onOpenModule(.attendance, classId, nil)
                }
                navigationButton("Abrir cuaderno", "book.closed") {
                    onOpenModule(.notebook, classId, nil)
                }
            }
        }
    }

    // MARK: Alerta

    private func alertDetail(_ alert: AlertItem, snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            Text(alert.title).font(DashboardStyle.Typography.headline)
            Text(alert.detail)
                .font(DashboardStyle.Typography.subheadline)
                .foregroundStyle(.secondary)
            field("Severidad", dashboardFilterLabel(alert.severity))
            field("Prioridad", dashboardFilterLabel(alert.priority))

            if let recommendation = DashboardRecommendations.action(
                type: alert.type, title: alert.title, detail: alert.detail
            ) {
                Label(recommendation, systemImage: "lightbulb")
                    .font(DashboardStyle.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            actions {
                let targets = agendaNavigationTargets(for: alert, snapshot: snapshot)
                if targets.isEmpty {
                    if let studentId = alert.studentId?.int64Value {
                        navigationButton("Ver ficha del alumno", "person.crop.circle", prominent: true) {
                            onOpenModule(.students, alert.classId?.int64Value, studentId)
                        }
                        navigationButton("Abrir cuaderno", "book.closed") {
                            onOpenModule(.notebook, alert.classId?.int64Value, studentId)
                        }
                    } else if let classId = alert.classId?.int64Value {
                        navigationButton("Abrir cuaderno", "book.closed", prominent: true) {
                            onOpenModule(.notebook, classId, nil)
                        }
                    }
                } else {
                    ForEach(targets, id: \.id) { target in
                        navigationButton("Evaluar: \(target.label)", "checklist", prominent: true) {
                            onOpenModule(.rubrics, target.classId?.int64Value, target.studentId?.int64Value)
                        }
                    }
                }
                navigationButton("Nueva observación", "note.text.badge.plus", action: onNewObservation)
            }
        }
    }

    // MARK: Educación Física

    private func peDetail(_ item: PEOperationalItem) -> some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            Text(item.title).font(DashboardStyle.Typography.headline)
            Text(item.detail)
                .font(DashboardStyle.Typography.subheadline)
                .foregroundStyle(.secondary)
            field("Severidad", dashboardFilterLabel(item.severity))
            if let destination = peDestination(for: item) {
                actions {
                    navigationButton("Ir a Educación Física", "figure.run", prominent: true) {
                        onOpenModule(destination, item.classId?.int64Value, nil)
                    }
                }
            }
        }
    }

    // MARK: Piezas

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: DashboardStyle.Spacing.s1)
                Text(value.isEmpty ? "Sin dato" : value)
                    .multilineTextAlignment(.trailing)
            }
            .font(DashboardStyle.Typography.subheadline)
            .frame(minHeight: DashboardStyle.minTapSize)
        }
        .accessibilityElement(children: .combine)
    }

    private func actions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        DashboardGlassGroup(spacing: DashboardStyle.Spacing.s1) {
            VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
                content()
            }
        }
        .padding(.top, DashboardStyle.Spacing.s1)
    }

    private func navigationButton(
        _ title: String,
        _ systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(DashboardStyle.Typography.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .dashboardButtonStyle(prominent: prominent)
    }

    private func sessionStatusLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "planned": return "Planificada"
        case "in_progress": return "En curso"
        case "completed": return "Completada"
        default: return raw.isEmpty ? "Sin estado" : raw
        }
    }
}
