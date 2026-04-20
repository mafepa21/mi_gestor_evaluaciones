import SwiftUI
import MiGestorKit

struct MacDashboardView: View {
    @ObservedObject var bridge: KmpBridge
    let bootstrap: AppleBridgeBootstrap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                pageHeader

                metricsRow
                    .padding(.top, 4)

                if !bridge.classes.isEmpty {
                    classesSection
                }

                if let snapshot = bridge.dashboardSnapshot {
                    operationalSection(snapshot: snapshot)
                }

                systemSection
            }
            .padding(MacAppStyle.pagePadding)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(MacAppStyle.pageTitle)
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MacStatusPill(
                label: bridge.pairedSyncHost != nil ? "LAN activa" : "Sin sync",
                isActive: bridge.pairedSyncHost != nil,
                tint: bridge.pairedSyncHost != nil ? MacAppStyle.successTint : .secondary
            )
        }
    }

    private var metricsRow: some View {
        let values = bridge.statsText.components(separatedBy: " · ")
        let students = extractNumber(from: values, keyword: "Alumnos") ?? "--"
        let classes = extractNumber(from: values, keyword: "Clases") ?? "--"
        let evals = extractNumber(from: values, keyword: "Eval") ?? "--"

        return HStack(spacing: MacAppStyle.cardSpacing) {
            MacMetricCard(label: "Alumnado", value: students, systemImage: "person.3.fill")
            MacMetricCard(label: "Grupos", value: classes, systemImage: "rectangle.3.group")
            MacMetricCard(label: "Evaluaciones", value: evals, systemImage: "chart.bar.doc.horizontal")
            MacMetricCard(
                label: "Pendientes",
                value: "\(bridge.pendingTasks.count)",
                tint: bridge.pendingTasks.isEmpty ? MacAppStyle.successTint : MacAppStyle.warningTint,
                systemImage: "clock.badge.exclamationmark"
            )
        }
    }

    private var classesSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Grupos activos")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: MacAppStyle.cardSpacing)]) {
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    classCard(for: schoolClass)
                }
            }
        }
    }

    private func classCard(for schoolClass: SchoolClass) -> some View {
        HStack(spacing: 10) {
            Text("\(schoolClass.course)º")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(schoolClass.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                let avg = bridge.activityGroups.first(where: { $0.name == schoolClass.name })?.average ?? 0
                Text(avg > 0 ? String(format: "Media %.1f", avg) : "Sin media")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private func operationalSection(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Operativa hoy")
            HStack(spacing: MacAppStyle.cardSpacing) {
                MacMetricCard(label: "Sesiones hoy", value: "\(snapshot.todayCount)", systemImage: "calendar")
                MacMetricCard(
                    label: "Alertas",
                    value: "\(snapshot.alertsCount)",
                    tint: snapshot.alertsCount > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint,
                    systemImage: "exclamationmark.bubble"
                )
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.cardSpacing) {
            MacSectionHeader(title: "Sistema")
            HStack(spacing: MacAppStyle.cardSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    labeledRow("Plataforma", value: bootstrap.platformName)
                    Divider()
                    labeledRow("Base de datos", value: URL(fileURLWithPath: bootstrap.databasePath).lastPathComponent)
                    Divider()
                    labeledRow("Bridge", value: bridge.status)
                }
                .padding(MacAppStyle.innerPadding)
                .background(MacAppStyle.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                        .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func extractNumber(from parts: [String], keyword: String) -> String? {
        parts.first(where: { $0.contains(keyword) })?
            .components(separatedBy: " ")
            .last
    }
}
