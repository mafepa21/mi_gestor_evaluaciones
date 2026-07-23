import SwiftUI
import MiGestorKit

/// Módulo de reuniones de centro para iPad. Ámbito centro (claustro, equipo
/// docente, departamento…), no de un grupo: por eso es un módulo propio y no
/// cuelga de la ficha del alumno. Vista separada de `MacMeetingsView`; lo que
/// comparten es `MeetingsShared` (modelos, estados de revisión y hojas).
struct MeetingsWorkspaceView: View {
    let bridge: KmpBridge

    @State private var meetings: [MeetingRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var showMeetingSheet = false
    @State private var editingMeeting: MeetingRow?
    @State private var pendingDeleteMeeting: MeetingRow?

    var body: some View {
        NavigationStack {
            Group {
                if meetings.isEmpty && !isLoading {
                    emptyState
                } else {
                    meetingsList
                }
            }
            .navigationTitle("Reuniones")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showMeetingSheet = true
                    } label: {
                        Label("Nueva reunión", systemImage: "plus")
                    }
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showMeetingSheet) {
            MeetingFormSheet(existingMeeting: nil) { _ in Task { await reload() } }
                .environmentObject(bridge)
        }
        .sheet(item: $editingMeeting) { meeting in
            MeetingFormSheet(existingMeeting: meeting) { _ in Task { await reload() } }
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sin reuniones registradas")
                .font(.headline)
            Text("Registra el acta de un claustro, un equipo docente o una CCP.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showMeetingSheet = true
            } label: {
                Label("Nueva reunión", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meetingsList: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(IOSAppStyle.danger)
            }
            ForEach(meetings) { meeting in
                NavigationLink {
                    MeetingDetailScreen(
                        bridge: bridge,
                        meetingId: meeting.id,
                        onEdit: { editingMeeting = meeting },
                        onDeleted: { Task { await reload() } }
                    )
                } label: {
                    meetingRow(meeting)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDeleteMeeting = meeting
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                    Button {
                        editingMeeting = meeting
                    } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                    .tint(IOSAppStyle.info)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private func meetingRow(_ meeting: MeetingRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: meeting.type.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.displayTitle)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(meeting.type.displayName)
                    Text("·")
                    Text(meeting.dateDisplay)
                    if meeting.isClosed {
                        Text("· Cerrada")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                reviewBadge(for: meeting.mostUrgentReviewStatus, openCount: meeting.openAgreementsCount)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func reviewBadge(for status: TutoringReviewStatus, openCount: Int) -> some View {
        switch status {
        case .overdue:
            Text("Acuerdos vencidos")
                .font(.caption2.weight(.bold))
                .foregroundStyle(IOSAppStyle.danger)
        case .dueSoon:
            Text("Acuerdos próximos")
                .font(.caption2.weight(.bold))
                .foregroundStyle(IOSAppStyle.warning)
        case .none:
            if openCount > 0 {
                Text("\(openCount) acuerdo\(openCount == 1 ? "" : "s") por cerrar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meetings = try await bridge.meetings().map { $0.asRow }
            errorMessage = nil
        } catch {
            errorMessage = "No se pudieron cargar las reuniones: \(error.localizedDescription)"
        }
    }

    private func deleteMeeting(_ meeting: MeetingRow) async {
        pendingDeleteMeeting = nil
        do {
            try await bridge.deleteMeeting(id: meeting.id)
            await reload()
        } catch {
            errorMessage = "No se pudo borrar la reunión: \(error.localizedDescription)"
        }
    }
}

/// Detalle de una reunión: recarga por id para reflejar los cambios en acuerdos
/// sin depender de que la lista se haya refrescado.
private struct MeetingDetailScreen: View {
    let bridge: KmpBridge
    let meetingId: Int64
    let onEdit: () -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var meeting: MeetingRow?
    @State private var errorMessage: String?

    @State private var showAgreementSheet = false
    @State private var editingAgreement: MeetingAgreementRow?
    @State private var pendingDeleteAgreement: MeetingAgreementRow?
    @State private var pendingDeleteMeeting = false

    var body: some View {
        ScrollView {
            if let meeting {
                VStack(alignment: .leading, spacing: 20) {
                    header(meeting)

                    if !meeting.summary.isEmpty {
                        section("Acta") {
                            Text(meeting.summary)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    agreementsSection(meeting)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(40)
            }
        }
        .navigationTitle(meeting?.displayTitle ?? "Reunión")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { onEdit() } label: { Image(systemName: "pencil") }
                Button(role: .destructive) { pendingDeleteMeeting = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showAgreementSheet) {
            MeetingAgreementFormSheet(meetingId: meetingId, existingAgreement: nil) {
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .sheet(item: $editingAgreement) { agreement in
            MeetingAgreementFormSheet(meetingId: meetingId, existingAgreement: agreement) {
                Task { await reload() }
            }
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
        .confirmationDialog(
            "¿Borrar esta reunión?",
            isPresented: $pendingDeleteMeeting
        ) {
            Button("Borrar reunión y sus acuerdos", role: .destructive) {
                Task { await deleteMeeting() }
            }
            Button("Cancelar", role: .cancel) { pendingDeleteMeeting = false }
        }
    }

    private func header(_ meeting: MeetingRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(meeting.type.displayName, systemImage: meeting.type.systemImage)
                Text("·")
                Text(meeting.dateDisplay)
                if meeting.isClosed {
                    Text("· Cerrada")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

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
                    .font(.footnote)
                    .foregroundStyle(IOSAppStyle.danger)
            }
        }
    }

    private func agreementsSection(_ meeting: MeetingRow) -> some View {
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
            }
        }
    }

    private func agreementRow(_ agreement: MeetingAgreementRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await toggleDone(agreement) }
            } label: {
                Image(systemName: agreement.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(agreement.isDone ? IOSAppStyle.success : Color.secondary)
            }
            .buttonStyle(.plain)

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
            Spacer(minLength: 0)
            Menu {
                Button { editingAgreement = agreement } label: {
                    Label("Editar", systemImage: "pencil")
                }
                Button(role: .destructive) { pendingDeleteAgreement = agreement } label: {
                    Label("Borrar", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
    }

    @ViewBuilder
    private func agreementBadge(_ status: TutoringReviewStatus) -> some View {
        switch status {
        case .overdue:
            Text("Vencido")
                .font(.caption.weight(.bold))
                .foregroundStyle(IOSAppStyle.danger)
        case .dueSoon:
            Text("Próximo a vencer")
                .font(.caption.weight(.bold))
                .foregroundStyle(IOSAppStyle.warning)
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

    private func reload() async {
        do {
            meeting = try await bridge.meeting(id: meetingId)?.asRow
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo cargar la reunión: \(error.localizedDescription)"
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
            await reload()
        } catch {
            errorMessage = "No se pudo actualizar el acuerdo: \(error.localizedDescription)"
        }
    }

    private func deleteAgreement(_ agreement: MeetingAgreementRow) async {
        pendingDeleteAgreement = nil
        do {
            try await bridge.deleteMeetingAgreement(id: agreement.id)
            await reload()
        } catch {
            errorMessage = "No se pudo borrar el acuerdo: \(error.localizedDescription)"
        }
    }

    private func deleteMeeting() async {
        do {
            try await bridge.deleteMeeting(id: meetingId)
            onDeleted()
            dismiss()
        } catch {
            errorMessage = "No se pudo borrar la reunión: \(error.localizedDescription)"
        }
    }
}
