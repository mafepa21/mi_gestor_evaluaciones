import SwiftUI
import MiGestorKit

struct PlannerWeekDetailPane: View {
    @ObservedObject var weekBoard: PlannerWeekBoardStore
    let vm: PlannerWorkspaceViewModel
    @Binding var selectedCell: PlannerCellKey?
    @Binding var selectedDay: Int?
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedCell {
                cellDetail(for: selectedCell)
            } else if let selectedDay {
                dayDetail(for: selectedDay)
            } else {
                emptyState
            }
        }
        .padding(EvaluationDesign.screenPadding)
    }

    @ViewBuilder
    private func cellDetail(for key: PlannerCellKey) -> some View {
        let entries = weekBoard.weekRenderModel.entriesByCell[key] ?? []
        if entries.isEmpty {
            emptyCellDetail(for: key)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(
                    title: "\(vm.dayHeaderLabel(for: key.day)) · \(vm.timeLabel(for: key.period))",
                    subtitle: entries.count == 1 ? "Detalle de sesión" : "\(entries.count) sesiones en esta franja"
                )

                ForEach(entries) { entry in
                    PlannerWeekDetailEntryCard(
                        vm: vm,
                        entry: entry,
                        onPrimaryAction: {
                            open(entry: entry, key: key)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func dayDetail(for day: Int) -> some View {
        let entries = entriesForDay(day)
        VStack(alignment: .leading, spacing: 16) {
            detailHeader(
                title: vm.dayHeaderLabel(for: day),
                subtitle: entries.isEmpty ? "Sin sesiones planificadas" : "\(entries.count) sesiones planificadas"
            )

            if entries.isEmpty {
                PlannerEmptyState(
                    title: "Día sin sesiones",
                    systemImage: "calendar.badge.plus",
                    message: "Selecciona una franja de la miniatura para crear una sesión."
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        PlannerWeekDayEntryRow(
                            vm: vm,
                            entry: entry,
                            onSelect: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedCell = PlannerCellKey(day: entry.dayOfWeek, period: entry.period)
                                    selectedDay = nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        PlannerEmptyState(
            title: "Selecciona una franja",
            systemImage: "calendar.day.timeline.left",
            message: "Toca una celda para revisar la sesión o la cabecera de un día para ver su agenda."
        )
    }

    private func emptyCellDetail(for key: PlannerCellKey) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            detailHeader(
                title: "\(vm.dayHeaderLabel(for: key.day)) · \(vm.timeLabel(for: key.period))",
                subtitle: "Franja disponible"
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Sin sesión asignada")
                    .font(.headline.weight(.semibold))
                Text("Puedes crear una sesión en esta franja sin salir de Semana.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    vm.openComposer(day: key.day, period: key.period)
                } label: {
                    Label("Crear sesión", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EvaluationDesign.border, lineWidth: 1)
            )
        }
    }

    private func detailHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func entriesForDay(_ day: Int) -> [PlannerWeekCellEntry] {
        weekBoard.weekRenderModel.visibleSlots.flatMap { slot in
            weekBoard.weekRenderModel.entriesByCell[PlannerCellKey(day: day, period: slot.period)] ?? []
        }
    }

    private func open(entry: PlannerWeekCellEntry, key: PlannerCellKey) {
        if let sessionId = entry.sessionId,
           let session = vm.sessions.first(where: { $0.id == sessionId }) {
            onOpenSession(session)
        } else {
            vm.selectGroup(entry.classId)
            vm.openComposer(day: key.day, period: key.period)
            vm.composerDraft.groupId = entry.classId
        }
    }
}

private struct PlannerWeekDetailEntryCard: View {
    let vm: PlannerWorkspaceViewModel
    let entry: PlannerWeekCellEntry
    let onPrimaryAction: () -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }
    private var statusTint: Color {
        vm.sessionStateTint(sessionStatus: entry.sessionStatus, journalStatus: entry.journalStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.className)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                    Text(entryTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(entry.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.12), in: Capsule(style: .continuous))
            }

            Button {
                onPrimaryAction()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var statusLabel: String {
        if entry.kind == .scheduledSlot { return "Pendiente" }
        return vm.sessionStateLabel(sessionStatus: entry.sessionStatus, journalStatus: entry.journalStatus)
    }

    private var statusIcon: String {
        if entry.kind == .scheduledSlot { return "plus.circle.fill" }
        return vm.sessionStateIcon(sessionStatus: entry.sessionStatus, journalStatus: entry.journalStatus)
    }

    private var primaryActionTitle: String {
        entry.kind == .scheduledSlot ? "Crear sesión" : "Abrir ficha completa"
    }

    private var primaryActionIcon: String {
        entry.kind == .scheduledSlot ? "plus" : "arrow.up.right"
    }

    private var entryTitle: String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Sesión sin título" : title
    }
}

private struct PlannerWeekDayEntryRow: View {
    let vm: PlannerWorkspaceViewModel
    let entry: PlannerWeekCellEntry
    let onSelect: () -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Text(vm.timeLabel(for: entry.period))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 112, alignment: .leading)

                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.className) · \(entry.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(statusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statusLabel: String {
        if entry.kind == .scheduledSlot { return "Pendiente de concretar" }
        return vm.sessionStateLabel(sessionStatus: entry.sessionStatus, journalStatus: entry.journalStatus)
    }
}
