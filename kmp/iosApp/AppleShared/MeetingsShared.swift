import SwiftUI

/// Espejo Swift de `MeetingType` (KMP). El `rawValue` debe coincidir con el
/// nombre del enum Kotlin: el puente convierte por nombre y una fila con un tipo
/// desconocido se descarta en vez de forzar un valor.
enum MeetingTypeUI: String, CaseIterable, Identifiable {
    case claustro = "CLAUSTRO"
    case equipoDocente = "EQUIPO_DOCENTE"
    case departamento = "DEPARTAMENTO"
    case ccp = "CCP"
    case coordinacion = "COORDINACION"
    case otra = "OTRA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claustro: return "Claustro"
        case .equipoDocente: return "Equipo docente"
        case .departamento: return "Departamento"
        case .ccp: return "CCP"
        case .coordinacion: return "Coordinación"
        case .otra: return "Otra"
        }
    }

    var systemImage: String {
        switch self {
        case .claustro: return "person.3.fill"
        case .equipoDocente: return "person.2.badge.gearshape.fill"
        case .departamento: return "books.vertical.fill"
        case .ccp: return "person.crop.rectangle.stack.fill"
        case .coordinacion: return "point.3.connected.trianglepath.dotted"
        case .otra: return "calendar"
        }
    }
}

struct MeetingAgreementRow: Identifiable, Hashable {
    let id: Int64
    let meetingId: Int64
    let description: String
    let responsible: String
    let dueIso: String?
    let isDone: Bool

    var dueDisplay: String? {
        dueIso.map(TutoringDateFormatting.display(from:))
    }

    /// Reutiliza el criterio de las tutorías: `dueSoon` a 15 días o menos,
    /// `overdue` si ya pasó. Un acuerdo cumplido no genera aviso.
    var reviewStatus: TutoringReviewStatus {
        guard !isDone, let dueIso, let due = TutoringDateFormatting.date(from: dueIso) else {
            return .none
        }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: due)
        if dueDay < today { return .overdue }
        guard let limit = Calendar.current.date(byAdding: .day, value: 15, to: today) else { return .none }
        return dueDay <= limit ? .dueSoon : .none
    }
}

struct MeetingRow: Identifiable, Hashable {
    let id: Int64
    let title: String
    let dateIso: String
    let type: MeetingTypeUI
    let location: String
    let attendees: String
    let summary: String
    let isClosed: Bool
    let agreements: [MeetingAgreementRow]

    var dateDisplay: String {
        TutoringDateFormatting.display(from: dateIso)
    }

    var displayTitle: String {
        title.isEmpty ? type.displayName : title
    }

    var openAgreementsCount: Int {
        agreements.filter { !$0.isDone }.count
    }

    /// El estado más urgente entre los acuerdos abiertos, para el aviso de la fila.
    var mostUrgentReviewStatus: TutoringReviewStatus {
        if agreements.contains(where: { $0.reviewStatus == .overdue }) { return .overdue }
        if agreements.contains(where: { $0.reviewStatus == .dueSoon }) { return .dueSoon }
        return .none
    }
}

extension KmpBridge.MeetingAgreementSnapshot {
    var asRow: MeetingAgreementRow {
        MeetingAgreementRow(
            id: id,
            meetingId: meetingId,
            description: description,
            responsible: responsible,
            dueIso: dueIso,
            isDone: isDone
        )
    }
}

extension KmpBridge.MeetingSnapshot {
    var asRow: MeetingRow {
        MeetingRow(
            id: id,
            title: title,
            dateIso: dateIso,
            type: type,
            location: location,
            attendees: attendees,
            summary: summary,
            isClosed: isClosed,
            agreements: agreements.map { $0.asRow }
        )
    }
}

/// Alta y edición de la cabecera de una reunión (título, fecha, tipo, lugar,
/// asistentes y cuerpo del acta). Los acuerdos se gestionan aparte, en el detalle.
struct MeetingFormSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    var existingMeeting: MeetingRow?
    let onSaved: (Int64) -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var type: MeetingTypeUI = .claustro
    @State private var location = ""
    @State private var attendees = ""
    @State private var summary = ""
    @State private var isClosed = false
    @State private var isSaving = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingMeeting == nil ? "Nueva reunión" : "Editar reunión")
                    .font(.title3.weight(.bold))
                Text("Acta de la reunión de centro")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.danger)
            }

            Form {
                TextField("Título", text: $title, prompt: Text("Claustro de inicio de curso…"))

                DatePicker("Fecha", selection: $date, displayedComponents: .date)

                Picker("Tipo", selection: $type) {
                    ForEach(MeetingTypeUI.allCases) { option in
                        Label(option.displayName, systemImage: option.systemImage).tag(option)
                    }
                }

                TextField("Lugar", text: $location, prompt: Text("Salón de actos, sala de profesores…"))

                TextField("Asistentes", text: $attendees, prompt: Text("Todo el profesorado, equipo docente de 3.º…"))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Acta")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $summary)
                        .frame(minHeight: 100)
                }

                Toggle("Reunión cerrada", isOn: $isClosed)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                Button(existingMeeting == nil ? "Crear" : "Guardar") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 560)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existingMeeting else { return }
        title = existingMeeting.title
        date = TutoringDateFormatting.date(from: existingMeeting.dateIso) ?? Date()
        type = existingMeeting.type
        location = existingMeeting.location
        attendees = existingMeeting.attendees
        summary = existingMeeting.summary
        isClosed = existingMeeting.isClosed
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = KmpBridge.MeetingDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dateIso: TutoringDateFormatting.iso(from: date),
            type: type,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            attendees: attendees.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            isClosed: isClosed
        )
        do {
            let savedId = try await bridge.saveMeeting(id: existingMeeting?.id, draft: draft)
            onSaved(savedId)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la reunión: \(error.localizedDescription)"
        }
    }
}

/// Alta y edición de un acuerdo: descripción, responsable, fecha límite y estado.
struct MeetingAgreementFormSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    let meetingId: Int64
    var existingAgreement: MeetingAgreementRow?
    let onSaved: () -> Void

    @State private var description = ""
    @State private var responsible = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var isDone = false
    @State private var isSaving = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingAgreement == nil ? "Nuevo acuerdo" : "Editar acuerdo")
                .font(.title3.weight(.bold))

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.danger)
            }

            Form {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Acuerdo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .frame(minHeight: 60)
                }

                TextField("Responsable", text: $responsible, prompt: Text("Jefatura de estudios, tutores…"))

                Toggle("Fijar fecha límite", isOn: $hasDue)
                if hasDue {
                    DatePicker("Para el", selection: $due, displayedComponents: .date)
                }

                Toggle("Cumplido", isOn: $isDone)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                Button(existingAgreement == nil ? "Añadir" : "Guardar") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 420)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existingAgreement else { return }
        description = existingAgreement.description
        responsible = existingAgreement.responsible
        if let dueIso = existingAgreement.dueIso,
           let parsed = TutoringDateFormatting.date(from: dueIso) {
            hasDue = true
            due = parsed
        }
        isDone = existingAgreement.isDone
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = KmpBridge.MeetingAgreementDraft(
            meetingId: meetingId,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            responsible: responsible.trimmingCharacters(in: .whitespacesAndNewlines),
            dueIso: hasDue ? TutoringDateFormatting.iso(from: due) : nil,
            isDone: isDone
        )
        do {
            try await bridge.saveMeetingAgreement(id: existingAgreement?.id, draft: draft)
            onSaved()
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar el acuerdo: \(error.localizedDescription)"
        }
    }
}
