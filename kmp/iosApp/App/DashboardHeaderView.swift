import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

// MARK: - Cabecera del Dashboard: fecha + saludo

/// Único título de la pantalla. El selector de modo, Exportar y el estado de
/// sync viven en la barra de herramientas del shell (iOS: `IOSContextualToolbar`,
/// macOS: `MacRootView`), así no se van al desplazar.
struct DashboardHeaderView: View {
    let greeting: String
    let dateLine: String
    let modeHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.micro) {
            Text(modeHint.map { "\(dateLine) · \($0)" } ?? dateLine)
                .font(DashboardStyle.Typography.footnote)
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(DashboardStyle.Typography.largeTitle)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardReveal(0)
    }
}

// MARK: - Selector Auto / Clase / Despacho

struct DashboardModeSelector: View {
    @Binding var selection: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Con texto enorme un segmentado no cabe: menú nativo.
            Picker("Modo del Dashboard", selection: $selection) {
                ForEach(DashboardModePreference.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: DashboardStyle.minTapSize)
        } else {
            segmented
        }
    }

    /// Los segmentos nunca se comprimen: una línea, ancho mínimo y 44 pt de alto.
    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(DashboardModePreference.allCases) { option in
                let isSelected = selection == option.rawValue
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        selection = option.rawValue
                    }
                } label: {
                    Text(option.title)
                        .font(DashboardStyle.Typography.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, DashboardStyle.Spacing.s2)
                        .frame(minWidth: 80, minHeight: DashboardStyle.minTapSize)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(DashboardStyle.cardFill)
                                    .matchedGeometryEffect(id: "modo-seleccionado", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(DashboardStyle.Spacing.micro)
        .fixedSize(horizontal: true, vertical: false)
        .dashboardGlass(in: Capsule(), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modo del Dashboard")
    }
}

// MARK: - Píldora de sincronización

struct DashboardSyncPillView: View {
    let state: DashboardSyncPill

    var body: some View {
        HStack(spacing: DashboardStyle.Spacing.s1) {
            if state == .syncing {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(state.tint).frame(width: 8, height: 8)
            }
            Text(state.title)
                .font(DashboardStyle.Typography.footnoteStrong)
                .lineLimit(1)
        }
        .padding(.horizontal, DashboardStyle.Spacing.s2)
        .frame(minHeight: DashboardStyle.minTapSize)
        .dashboardGlass(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estado de sincronización: \(state.title)")
    }
}

// MARK: - Exportar

/// Un CSV que solo se genera cuando el usuario elige compartirlo: el
/// `Transferable` guarda el snapshot y construye el texto al exportar, no al
/// pintar el menú.
struct DashboardCSVExport: Transferable {
    enum Kind {
        case today
        case alerts
        case groups
        case agenda

        var title: String {
            switch self {
            case .today: return "Hoy"
            case .alerts: return "Alertas"
            case .groups: return "Grupos"
            case .agenda: return "Agenda"
            }
        }
    }

    let kind: Kind
    let snapshot: DashboardSnapshot

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.makeCSV().utf8)
        }
    }

    func makeCSV() -> String {
        switch kind {
        case .today:
            return Self.csv("group,time,didactic_unit,space,status", snapshot.todaySessions.map {
                [$0.groupName, $0.timeLabel, $0.didacticUnit, $0.space, $0.sessionStatus]
            })
        case .alerts:
            return Self.csv("type,title,detail,severity,priority,count", snapshot.alerts.map {
                [$0.type, $0.title, $0.detail, $0.severity, $0.priority, "\($0.count)"]
            })
        case .groups:
            return Self.csv("group,attendance,evaluation,average,follow_up", snapshot.groupSummaries.map {
                [$0.groupName, "\($0.attendancePct)", "\($0.evaluationCompletedPct)", "\($0.averageScore)", "\($0.studentsInFollowUp)"]
            })
        case .agenda:
            return Self.csv("type,title,subtitle,time,status", snapshot.agendaItems.map {
                [$0.type, $0.title, $0.subtitle, $0.timeLabel, $0.status]
            })
        }
    }

    /// Escapa comas, comillas y saltos de línea para que el CSV abra bien.
    private static func csv(_ header: String, _ rows: [[String]]) -> String {
        func field(_ value: String) -> String {
            guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return ([header] + rows.map { $0.map(field).joined(separator: ",") }).joined(separator: "\n")
    }
}

struct DashboardExportMenu: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        Menu {
            ForEach([DashboardCSVExport.Kind.today, .alerts, .groups, .agenda], id: \.title) { kind in
                ShareLink(
                    item: DashboardCSVExport(kind: kind, snapshot: snapshot),
                    preview: SharePreview("\(kind.title).csv")
                ) {
                    Text(kind.title)
                }
            }
        } label: {
            Label("Exportar", systemImage: "square.and.arrow.up")
                .font(DashboardStyle.Typography.footnoteStrong)
                .lineLimit(1)
        }
        .dashboardButtonStyle()
    }
}
