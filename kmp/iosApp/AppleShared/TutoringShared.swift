import SwiftUI

/// Espejo Swift de `TutoringChannel` (KMP). El `rawValue` debe coincidir con el
/// nombre del enum Kotlin: el puente convierte por nombre, y una fila con un
/// canal desconocido se descarta en vez de forzar un valor.
enum TutoringChannelUI: String, CaseIterable, Identifiable {
    case inPerson = "IN_PERSON"
    case phone = "PHONE"
    case videoCall = "VIDEO_CALL"
    case written = "WRITTEN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inPerson: return "Presencial"
        case .phone: return "Teléfono"
        case .videoCall: return "Videollamada"
        case .written: return "Por escrito"
        }
    }

    var systemImage: String {
        switch self {
        case .inPerson: return "person.2.fill"
        case .phone: return "phone.fill"
        case .videoCall: return "video.fill"
        case .written: return "envelope.fill"
        }
    }
}

/// Estado de la revisión de seguimiento acordada, para poder destacar en la
/// ficha lo que ya vence. Mismo criterio que `SupportMeasureRow.reviewStatus`.
enum TutoringReviewStatus {
    case none
    case dueSoon
    case overdue
}

struct TutoringSessionRow: Identifiable, Hashable {
    let id: Int64
    let studentId: Int64
    let dateIso: String
    let channel: TutoringChannelUI
    let attendees: String
    let topics: String
    let agreements: String
    let reviewDueIso: String?
    let isClosed: Bool

    var dateDisplay: String {
        TutoringDateFormatting.display(from: dateIso)
    }

    var reviewDueDisplay: String? {
        reviewDueIso.map(TutoringDateFormatting.display(from:))
    }

    var reviewStatus: TutoringReviewStatus {
        guard !isClosed, let reviewDueIso, let due = TutoringDateFormatting.date(from: reviewDueIso) else {
            return .none
        }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: due)
        if dueDay < today { return .overdue }
        guard let limit = Calendar.current.date(byAdding: .day, value: 15, to: today) else { return .none }
        return dueDay <= limit ? .dueSoon : .none
    }
}

enum TutoringDateFormatting {
    /// ISO fijo (`en_US_POSIX`) para parsear: las fechas se guardan en ISO y no
    /// deben depender de la configuración regional del dispositivo.
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func date(from iso: String) -> Date? {
        isoFormatter.date(from: iso)
    }

    static func iso(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func display(from iso: String) -> String {
        guard let date = date(from: iso) else { return iso }
        return displayFormatter.string(from: date)
    }
}

extension KmpBridge.TutoringSessionSnapshot {
    var asRow: TutoringSessionRow {
        TutoringSessionRow(
            id: id,
            studentId: studentId,
            dateIso: dateIso,
            channel: channel,
            attendees: attendees,
            topics: topics,
            agreements: agreements,
            reviewDueIso: reviewDueIso,
            isClosed: isClosed
        )
    }
}

/// Alta y edición del acta de una entrevista con la familia.
struct TutoringSessionFormSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    let studentId: Int64
    var existingSession: TutoringSessionRow?
    let onSaved: () -> Void

    @State private var date = Date()
    @State private var channel: TutoringChannelUI = .inPerson
    @State private var attendees = ""
    @State private var topics = ""
    @State private var agreements = ""
    @State private var hasReviewDue = false
    @State private var reviewDue = Date()
    @State private var isClosed = false
    @State private var isSaving = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingSession == nil ? "Nueva tutoría" : "Editar tutoría")
                    .font(.title3.weight(.bold))
                Text("Acta de la entrevista con la familia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.danger)
            }

            Form {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)

                Picker("Canal", selection: $channel) {
                    ForEach(TutoringChannelUI.allCases) { option in
                        Label(option.displayName, systemImage: option.systemImage).tag(option)
                    }
                }

                TextField("Asistentes", text: $attendees, prompt: Text("Madre, padre, tutor legal…"))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Temas tratados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $topics)
                        .frame(minHeight: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Acuerdos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $agreements)
                        .frame(minHeight: 60)
                }

                Toggle("Fijar revisión de seguimiento", isOn: $hasReviewDue)
                if hasReviewDue {
                    DatePicker("Revisar el", selection: $reviewDue, displayedComponents: .date)
                }

                Toggle("Seguimiento cerrado", isOn: $isClosed)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                Button(existingSession == nil ? "Registrar" : "Guardar") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existingSession else { return }
        date = TutoringDateFormatting.date(from: existingSession.dateIso) ?? Date()
        channel = existingSession.channel
        attendees = existingSession.attendees
        topics = existingSession.topics
        agreements = existingSession.agreements
        if let reviewDueIso = existingSession.reviewDueIso,
           let parsed = TutoringDateFormatting.date(from: reviewDueIso) {
            hasReviewDue = true
            reviewDue = parsed
        }
        isClosed = existingSession.isClosed
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = KmpBridge.TutoringSessionDraft(
            studentId: studentId,
            dateIso: TutoringDateFormatting.iso(from: date),
            channel: channel,
            attendees: attendees.trimmingCharacters(in: .whitespacesAndNewlines),
            topics: topics.trimmingCharacters(in: .whitespacesAndNewlines),
            agreements: agreements.trimmingCharacters(in: .whitespacesAndNewlines),
            reviewDueIso: hasReviewDue ? TutoringDateFormatting.iso(from: reviewDue) : nil,
            isClosed: isClosed
        )
        do {
            try await bridge.saveTutoringSession(id: existingSession?.id, draft: draft)
            onSaved()
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la tutoría: \(error.localizedDescription)"
        }
    }
}
