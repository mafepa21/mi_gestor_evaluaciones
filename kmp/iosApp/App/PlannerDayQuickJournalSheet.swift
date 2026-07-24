import SwiftUI
import MiGestorKit

/// Cierre rápido del diario de todas las sesiones de un día en una sola pantalla:
/// pensado para velocidad (marcar impartida, nota corta), no para redacción extensa.
/// La edición completa del diario sigue viviendo en `PlannerJournalDetailPane`.
struct PlannerDayQuickJournalSheet: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let sessions: [PlanningSession]
    let onOpenSession: (PlanningSession) -> Void
    let onClose: () -> Void

    @State private var noteText: [Int64: String] = [:]
    @State private var savedNoteSessionIds: Set<Int64> = []

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    PlannerEmptyState(
                        title: "Sin sesiones este día",
                        systemImage: "bolt.badge.clock",
                        message: "No hay sesiones planificadas para cerrar el diario."
                    )
                } else {
                    List {
                        ForEach(sessions, id: \.id) { session in
                            PlannerDayQuickJournalRow(
                                vm: vm,
                                session: session,
                                noteText: Binding(
                                    get: { noteText[session.id, default: ""] },
                                    set: { noteText[session.id] = $0 }
                                ),
                                isNoteSaved: savedNoteSessionIds.contains(session.id),
                                onToggleImpartida: {
                                    let nextStatus: SessionStatus = session.status == .completed ? .planned : .completed
                                    Task { await vm.setSessionStatus(session, status: nextStatus) }
                                },
                                onSaveNote: {
                                    let text = noteText[session.id, default: ""]
                                    Task {
                                        await vm.quickAddObservation(to: session, text: text)
                                        noteText[session.id] = ""
                                        savedNoteSessionIds.insert(session.id)
                                    }
                                },
                                onOpenFull: { onOpenSession(session) }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Diario rápido del día")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private struct PlannerDayQuickJournalRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    @Binding var noteText: String
    let isNoteSaved: Bool
    let onToggleImpartida: () -> Void
    let onSaveNote: () -> Void
    let onOpenFull: () -> Void

    private var tint: Color { Color(hex: session.teachingUnitColor) }

    private var title: String {
        let trimmed = session.teachingUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Sesión sin título" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(timeRange) · \(session.groupName)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                PlannerStatusBadge(
                    label: vm.sessionStateLabel(for: session),
                    systemImage: vm.sessionStateIcon(for: session),
                    tint: vm.sessionStateTint(for: session)
                )
                Button {
                    onOpenFull()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Abrir ficha completa")
            }

            Button {
                onToggleImpartida()
            } label: {
                Label(
                    session.status == .completed ? "Impartida" : "Marcar impartida",
                    systemImage: session.status == .completed ? "checkmark.circle.fill" : "circle"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(session.status == .completed ? EvaluationDesign.success : .secondary)

            pulseRow
            participationRow

            HStack(spacing: 8) {
                TextField("Nota rápida de seguimiento…", text: $noteText)
                    .textFieldStyle(.roundedBorder)
                Button("Guardar", action: onSaveNote)
                    .buttonStyle(.bordered)
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if isNoteSaved {
                Label("Nota guardada", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.success)
            }
        }
        .padding(.vertical, 8)
    }

    private var timeRange: String {
        if let start = session.startTime, let end = session.endTime {
            return "\(start)-\(end)"
        }
        return vm.timeLabel(for: Int(session.period))
    }

    private var summary: SessionJournalSummary? { vm.summary(for: session.id) }

    private var pulseRow: some View {
        HStack(spacing: 8) {
            pulseButton("Muy bien", icon: "checkmark.circle.fill", climate: 5, usefulTime: 5, difficulty: 1, tint: EvaluationDesign.success)
            pulseButton("Normal", icon: "circle.lefthalf.filled", climate: 3, usefulTime: 3, difficulty: 3, tint: EvaluationDesign.accent)
            pulseButton("Revisar", icon: "exclamationmark.triangle.fill", climate: 2, usefulTime: 2, difficulty: 5, tint: IOSAppStyle.warning)
        }
    }

    private var participationRow: some View {
        HStack(spacing: 8) {
            participationButton("Baja", value: 2)
            participationButton("Media", value: 3)
            participationButton("Alta", value: 5)
        }
    }

    private func pulseButton(_ title: String, icon: String, climate: Int, usefulTime: Int, difficulty: Int, tint: Color) -> some View {
        let isSelected = summary?.climateScore == Int32(climate) && summary?.usefulTimeScore == Int32(usefulTime)
        return Button {
            Task { await vm.quickSetPulse(to: session, climate: climate, usefulTime: usefulTime, difficulty: difficulty) }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : tint)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? tint : tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tint.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
    }

    private func participationButton(_ title: String, value: Int) -> some View {
        let isSelected = summary?.participationScore == Int32(value)
        return Button {
            Task { await vm.quickSetParticipation(to: session, value: value) }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : EvaluationDesign.accent)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? EvaluationDesign.accent : EvaluationDesign.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(EvaluationDesign.accent.opacity(isSelected ? 0 : 0.22), lineWidth: 1))
    }
}
