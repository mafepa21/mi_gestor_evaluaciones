import SwiftUI
import MiGestorKit

@MainActor
final class MacMeetingsStore: ObservableObject {
    @Published var meetings: [MeetingRow] = []
    @Published var selectedMeetingId: Int64?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var selectedMeeting: MeetingRow? {
        guard let selectedMeetingId else { return nil }
        return meetings.first { $0.id == selectedMeetingId }
    }
}

/// Módulo autónomo de reuniones de centro. Ámbito centro, no de un grupo: por eso
/// vive en su propia entrada de la barra lateral y no cuelga de ningún alumnado.
struct MacMeetingsView: View {
    let bridge: KmpBridge
    @StateObject private var store = MacMeetingsStore()

    @State private var showMeetingSheet = false
    @State private var editingMeeting: MeetingRow?
    @State private var pendingDeleteMeeting: MeetingRow?

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reuniones")
                        .font(.title2.weight(.bold))
                    Text("Actas de centro y acuerdos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showMeetingSheet = true
                } label: {
                    Label("Nueva reunión", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HSplitView {
                meetingsList
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                detail
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(MacAppStyle.pagePadding)
        .task { await reload() }
        .sheet(isPresented: $showMeetingSheet) {
            MeetingFormSheet(existingMeeting: nil) { newId in
                Task {
                    await reload()
                    store.selectedMeetingId = newId
                }
            }
            .environmentObject(bridge)
        }
        .sheet(item: $editingMeeting) { meeting in
            MeetingFormSheet(existingMeeting: meeting) { _ in
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .confirmationDialog(
            "¿Borrar esta reunión?",
            isPresented: Binding(
                get: { pendingDeleteMeeting != nil },
                set: { if !$0 { pendingDeleteMeeting = nil } }
            ),
            presenting: pendingDeleteMeeting
        ) { meeting in
            Button("Borrar reunión y sus acuerdos", role: .destructive) {
                Task { await deleteMeeting(meeting) }
            }
            Button("Cancelar", role: .cancel) { pendingDeleteMeeting = nil }
        } message: { meeting in
            Text("Se eliminará «\(meeting.displayTitle)» y todos sus acuerdos. No se puede deshacer.")
        }
    }

    // MARK: - Lista

    private var meetingsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(MacAppStyle.dangerTint)
                        .padding(.bottom, 4)
                }

                if store.meetings.isEmpty && !store.isLoading {
                    VStack(spacing: 8) {
                        Image(systemName: "person.3")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Sin reuniones registradas")
                            .font(.callout.weight(.semibold))
                        Text("Registra el acta de un claustro, un equipo docente o una CCP.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(store.meetings) { meeting in
                        Button {
                            store.selectedMeetingId = meeting.id
                        } label: {
                            meetingListRow(meeting)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
        }
    }

    private func meetingListRow(_ meeting: MeetingRow) -> some View {
        let isSelected = store.selectedMeetingId == meeting.id
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: meeting.type.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(meeting.dateDisplay)
                    if meeting.isClosed {
                        Text("· Cerrada")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                reviewBadge(for: meeting.mostUrgentReviewStatus, openCount: meeting.openAgreementsCount)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? MacAppStyle.infoTint.opacity(0.15) : Color.clear)
        )
    }

    @ViewBuilder
    private func reviewBadge(for status: TutoringReviewStatus, openCount: Int) -> some View {
        switch status {
        case .overdue:
            Text("Acuerdos vencidos")
                .font(.caption2.weight(.bold))
                .foregroundStyle(MacAppStyle.dangerTint)
        case .dueSoon:
            Text("Acuerdos próximos")
                .font(.caption2.weight(.bold))
                .foregroundStyle(MacAppStyle.warningTint)
        case .none:
            if openCount > 0 {
                Text("\(openCount) acuerdo\(openCount == 1 ? "" : "s") por cerrar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detalle

    @ViewBuilder
    private var detail: some View {
        if let meeting = store.selectedMeeting {
            MacMeetingDetailView(
                bridge: bridge,
                meeting: meeting,
                onEdit: { editingMeeting = meeting },
                onDelete: { pendingDeleteMeeting = meeting },
                onChanged: { Task { await reload() } }
            )
            .id(meeting.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Selecciona una reunión")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Datos

    private func reload() async {
        store.isLoading = true
        defer { store.isLoading = false }
        do {
            let snapshots = try await bridge.meetings()
            store.meetings = snapshots.map { $0.asRow }
            store.errorMessage = nil
            // Conserva la selección si sigue existiendo; si no, cae a la primera.
            if let selected = store.selectedMeetingId,
               !store.meetings.contains(where: { $0.id == selected }) {
                store.selectedMeetingId = store.meetings.first?.id
            } else if store.selectedMeetingId == nil {
                store.selectedMeetingId = store.meetings.first?.id
            }
        } catch {
            store.errorMessage = "No se pudieron cargar las reuniones: \(error.localizedDescription)"
        }
    }

    private func deleteMeeting(_ meeting: MeetingRow) async {
        pendingDeleteMeeting = nil
        do {
            try await bridge.deleteMeeting(id: meeting.id)
            if store.selectedMeetingId == meeting.id {
                store.selectedMeetingId = nil
            }
            await reload()
        } catch {
            store.errorMessage = "No se pudo borrar la reunión: \(error.localizedDescription)"
        }
    }
}

/// Detalle de una reunión: cabecera del acta, cuerpo y checklist de acuerdos.
private struct MacMeetingDetailView: View {
    let bridge: KmpBridge
    let meeting: MeetingRow
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onChanged: () -> Void

    @State private var showAgreementSheet = false
    @State private var editingAgreement: MeetingAgreementRow?
    @State private var pendingDeleteAgreement: MeetingAgreementRow?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !meeting.summary.isEmpty {
                    section("Acta") {
                        Text(meeting.summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                agreementsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showAgreementSheet) {
            MeetingAgreementFormSheet(meetingId: meeting.id, existingAgreement: nil) { onChanged() }
                .environmentObject(bridge)
        }
        .sheet(item: $editingAgreement) { agreement in
            MeetingAgreementFormSheet(meetingId: meeting.id, existingAgreement: agreement) { onChanged() }
                .environmentObject(bridge)
        }
        .confirmationDialog(
            "¿Borrar este acuerdo?",
            isPresented: Binding(
                get: { pendingDeleteAgreement != nil },
                set: { if !$0 { pendingDeleteAgreement = nil } }
            ),
            presenting: pendingDeleteAgreement
        ) { agreement in
            Button("Borrar acuerdo", role: .destructive) {
                Task { await deleteAgreement(agreement) }
            }
            Button("Cancelar", role: .cancel) { pendingDeleteAgreement = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(.largeTitle.weight(.bold))
                    HStack(spacing: 8) {
                        Label(meeting.type.displayName, systemImage: meeting.type.systemImage)
                        Text(meeting.dateDisplay)
                        if meeting.isClosed {
                            Text("· Cerrada")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }

            if !meeting.location.isEmpty {
                Label(meeting.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !meeting.attendees.isEmpty {
                Label(meeting.attendees, systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(MacAppStyle.dangerTint)
            }
        }
    }

    private var agreementsSection: some View {
        section("Acuerdos") {
            VStack(alignment: .leading, spacing: 10) {
                if meeting.agreements.isEmpty {
                    Text("Sin acuerdos registrados.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(meeting.agreements) { agreement in
                        agreementRow(agreement)
                    }
                }
                Button {
                    showAgreementSheet = true
                } label: {
                    Label("Añadir acuerdo", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func agreementRow(_ agreement: MeetingAgreementRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await toggleDone(agreement) }
            } label: {
                Image(systemName: agreement.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(agreement.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(agreement.description)
                    .font(.body)
                    .strikethrough(agreement.isDone, color: .secondary)
                    .foregroundStyle(agreement.isDone ? .secondary : .primary)
                HStack(spacing: 8) {
                    if !agreement.responsible.isEmpty {
                        Label(agreement.responsible, systemImage: "person")
                    }
                    if let dueDisplay = agreement.dueDisplay {
                        Label(dueDisplay, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                agreementBadge(agreement.reviewStatus)
            }
            Spacer()
            Button {
                editingAgreement = agreement
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                pendingDeleteAgreement = agreement
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func agreementBadge(_ status: TutoringReviewStatus) -> some View {
        switch status {
        case .overdue:
            Text("Vencido")
                .font(.caption.weight(.bold))
                .foregroundStyle(MacAppStyle.dangerTint)
        case .dueSoon:
            Text("Próximo a vencer")
                .font(.caption.weight(.bold))
                .foregroundStyle(MacAppStyle.warningTint)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func toggleDone(_ agreement: MeetingAgreementRow) async {
        let draft = KmpBridge.MeetingAgreementDraft(
            meetingId: agreement.meetingId,
            description: agreement.description,
            responsible: agreement.responsible,
            dueIso: agreement.dueIso,
            isDone: !agreement.isDone
        )
        do {
            try await bridge.saveMeetingAgreement(id: agreement.id, draft: draft)
            onChanged()
        } catch {
            errorMessage = "No se pudo actualizar el acuerdo: \(error.localizedDescription)"
        }
    }

    private func deleteAgreement(_ agreement: MeetingAgreementRow) async {
        pendingDeleteAgreement = nil
        do {
            try await bridge.deleteMeetingAgreement(id: agreement.id)
            onChanged()
        } catch {
            errorMessage = "No se pudo borrar el acuerdo: \(error.localizedDescription)"
        }
    }
}
