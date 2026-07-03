import SwiftUI
import MiGestorKit

struct CreateCourseSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    @State var name = ""
    @State var course = "3"
    let onDismiss: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Int32(course) != nil
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nueva clase",
            subtitle: "Crea el grupo donde trabajarás asistencia, cuaderno y planificación.",
            systemImage: "person.3.sequence.fill",
            canSave: canSave,
            onCancel: close,
            onSave: save
        ) {
            IOSSectionCard(title: "Datos esenciales", systemImage: "rectangle.and.pencil.and.ellipsis") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Nombre del curso", placeholder: "1º ESO A", text: $name)

                    WorkspaceCreateTextField(title: "Nivel", placeholder: "3", text: $course)
                        .appKeyboardType(.numberPad)
                }
            }
        }
    }

    private func close() {
        onDismiss()
        dismiss()
    }

    private func save() {
        Task {
            guard let numericCourse = Int32(course),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            _ = try? await bridge.createClass(name: name, course: numericCourse)
            close()
        }
    }
}

struct CreateStudentSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void
    @State var firstName = ""
    @State var lastName = ""
    @State var isInjured = false
    @State var studentSex: StudentSex = .unspecified
    @State var hasBirthDate = false
    @State var birthDate = Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nuevo alumno",
            subtitle: "Añade solo lo necesario ahora. Los datos de seguimiento se completan desde la ficha.",
            systemImage: "person.crop.circle.badge.plus",
            canSave: canSave,
            onCancel: close,
            onSave: save
        ) {
            IOSSectionCard(title: "Identidad", systemImage: "person.text.rectangle") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Nombre", placeholder: "Nombre", text: $firstName)
                    WorkspaceCreateTextField(title: "Apellidos", placeholder: "Apellidos", text: $lastName)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sexo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Sexo", selection: $studentSex) {
                            Text("No especificado").tag(StudentSex.unspecified)
                            Text("Masculino").tag(StudentSex.male)
                            Text("Femenino").tag(StudentSex.female)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

            IOSSectionCard(title: "Seguimiento", systemImage: "heart.text.square") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Fecha de nacimiento", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Nacimiento", selection: $birthDate, displayedComponents: .date)
                    }
                    Toggle("Seguimiento físico activo", isOn: $isInjured)
                }
            }
        }
    }

    func localDate(from date: Date) -> LocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return LocalDate(
            year: Int32(components.year ?? 2010),
            monthNumber: Int32(components.month ?? 1),
            dayOfMonth: Int32(components.day ?? 1)
        )
    }

    private func close() {
        onDismiss()
        dismiss()
    }

    private func save() {
        Task {
            guard canSave else { return }
            if bridge.selectedStudentsClassId != defaultClassId {
                await bridge.selectStudentsClass(classId: defaultClassId)
            }
            try? await bridge.createStudentInSelectedClass(
                firstName: firstName,
                lastName: lastName,
                isInjured: isInjured,
                sex: studentSex,
                sexSource: studentSex == .unspecified ? nil : .manual,
                birthDate: hasBirthDate ? localDate(from: birthDate) : nil
            )
            close()
        }
    }
}

struct CreateEvaluationSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void
    @State var code = ""
    @State var name = ""
    @State var type = "Rúbrica"
    @State var weight = "1.0"

    private var canSave: Bool {
        defaultClassId != nil &&
        Double(weight) != nil &&
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nueva evaluación",
            subtitle: "Define el instrumento mínimo para que aparezca en el Cuaderno.",
            systemImage: "checklist.checked",
            canSave: canSave,
            onCancel: close,
            onSave: save
        ) {
            IOSSectionCard(title: "Instrumento", systemImage: "doc.badge.plus") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Código", placeholder: "UD1-R1", text: $code)
                    WorkspaceCreateTextField(title: "Nombre", placeholder: "Rúbrica de técnica", text: $name)
                    WorkspaceCreateTextField(title: "Tipo", placeholder: "Rúbrica", text: $type)
                    WorkspaceCreateTextField(title: "Peso", placeholder: "1.0", text: $weight)
                        .appKeyboardType(.decimalPad)
                }
            }
        }
    }

    private func close() {
        onDismiss()
        dismiss()
    }

    private func save() {
        Task {
            guard let defaultClassId,
                  let numericWeight = Double(weight),
                  !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await bridge.createEvaluation(classId: defaultClassId, code: code, name: name, type: type, weight: numericWeight)
            close()
        }
    }
}

struct WorkspaceCreateSheetScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        canSave: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.canSave = canSave
        self.onCancel = onCancel
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WorkspaceCreateSheetHero(
                        title: title,
                        subtitle: subtitle,
                        systemImage: systemImage
                    )
                    content
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(EvaluationDesign.surface.opacity(0.4))
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: onSave)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 720, minHeight: 520, idealHeight: 620)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

struct WorkspaceCreateSheetHero: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(EvaluationDesign.accent)
                .frame(width: 48, height: 48)
                .background(EvaluationDesign.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        }
    }
}

struct WorkspaceCreateTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct WorkspaceCreateMultilineField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct CreatePESessionSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void

    @State var title = ""
    @State var objectives = ""
    @State var activities = ""
    @State var scheduledSpace = ""
    @State var usedSpace = ""
    @State var materialToPrepare = ""
    @State var sessionDate = Date()
    @State var period = 1
    @State var status: SessionStatus = .planned

    private var canSave: Bool {
        defaultClassId != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nueva sesión EF",
            subtitle: "Planifica la próxima clase con lo imprescindible para ejecutarla en pista.",
            systemImage: "figure.run.circle.fill",
            canSave: canSave,
            onCancel: close,
            onSave: save
        ) {
            IOSSectionCard(title: "Sesión", systemImage: "calendar.badge.plus") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Nombre", placeholder: "Circuito de coordinación", text: $title)
                    WorkspaceCreateMultilineField(title: "Objetivos", placeholder: "Objetivo docente principal", text: $objectives)
                    WorkspaceCreateMultilineField(title: "Actividades", placeholder: "Calentamiento, parte principal y cierre", text: $activities)
                }
            }

            IOSSectionCard(title: "Clase y logística", systemImage: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Fecha", selection: $sessionDate, displayedComponents: .date)
                    Stepper("Periodo \(period)", value: $period, in: 1...8)
                    WorkspaceCreateTextField(title: "Espacio previsto", placeholder: "Pabellón", text: $scheduledSpace)
                    WorkspaceCreateTextField(title: "Espacio usado", placeholder: "Pista exterior", text: $usedSpace)
                    WorkspaceCreateMultilineField(title: "Material a preparar", placeholder: "Conos, petos, cronómetro", text: $materialToPrepare)
                }
            }

            IOSSectionCard(title: "Estado", systemImage: "checkmark.seal") {
                Picker("Estado", selection: $status) {
                    Text("Planificada").tag(SessionStatus.planned)
                    Text("Activa").tag(SessionStatus.inProgress)
                    Text("Cerrada").tag(SessionStatus.completed)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func close() {
        onDismiss()
        dismiss()
    }

    private func save() {
        Task {
            guard let defaultClassId,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let isoCalendar = Calendar(identifier: .iso8601)
            let isoWeekday = ((isoCalendar.component(.weekday, from: sessionDate) + 5) % 7) + 1
            _ = try? await bridge.createPESession(
                classId: defaultClassId,
                title: title,
                dayOfWeek: isoWeekday,
                period: period,
                weekNumber: isoCalendar.component(.weekOfYear, from: sessionDate),
                year: isoCalendar.component(.yearForWeekOfYear, from: sessionDate),
                objectives: objectives,
                activities: activities,
                status: status,
                scheduledSpace: scheduledSpace,
                usedSpace: usedSpace,
                materialToPrepare: materialToPrepare
            )
            close()
        }
    }
}

struct CreatePhysicalTestSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void

    @State var code = ""
    @State var name = ""
    @State var kind = "Tiempo"
    @State var weight = "1.0"
    @State var description = ""

    let templates = ["Tiempo", "Distancia", "Repeticiones", "Resistencia", "Flexibilidad"]

    private var canSave: Bool {
        defaultClassId != nil &&
        Double(weight) != nil &&
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nueva prueba física",
            subtitle: "Define la prueba para registrar resultados y baremos desde el iPad.",
            systemImage: "figure.run.square.stack",
            canSave: canSave,
            onCancel: close,
            onSave: save
        ) {
            IOSSectionCard(title: "Prueba", systemImage: "stopwatch") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tipo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Tipo", selection: $kind) {
                            ForEach(templates, id: \.self) { template in
                                Text(template).tag(template)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    WorkspaceCreateTextField(title: "Código", placeholder: "CF-01", text: $code)
                    WorkspaceCreateTextField(title: "Nombre", placeholder: "Course navette", text: $name)
                    WorkspaceCreateTextField(title: "Peso", placeholder: "1.0", text: $weight)
                        .appKeyboardType(.decimalPad)
                    WorkspaceCreateMultilineField(title: "Descripción", placeholder: "Criterios o protocolo de medición", text: $description)
                }
            }
        }
    }

    private func close() {
        onDismiss()
        dismiss()
    }

    private func save() {
        Task {
            guard let defaultClassId,
                  let numericWeight = Double(weight),
                  !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await bridge.createPhysicalTest(
                classId: defaultClassId,
                code: code,
                name: name,
                kind: kind,
                weight: numericWeight,
                description: description.nilIfBlank
            )
            close()
        }
    }
}

struct CreatePEIncidentSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let onSaved: (Int64, String, PEIncidentWorkflowState, Int64?, String) -> Void

    @State var title = ""
    @State var detail = ""
    @State var category = "Lesión"
    @State var severity = "medium"
    @State var workflowState: PEIncidentWorkflowState = .open
    @State var selectedStudentId: Int64?
    @State var selectedSessionId: Int64?
    @State var followUpNote = ""
    @State var sessions: [KmpBridge.PESessionSnapshot] = []

    let categories = ["Lesión", "Seguridad", "Conducta", "Material", "Equipación"]

    private var canSave: Bool {
        defaultClassId != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nueva incidencia EF",
            subtitle: "Registra lo importante ahora y deja el seguimiento preparado.",
            systemImage: "exclamationmark.triangle.fill",
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: save
        ) {
            IOSSectionCard(title: "Incidencia", systemImage: "waveform.path.ecg.rectangle") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Categoría")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Categoría", selection: $category) {
                            ForEach(categories, id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    WorkspaceCreateTextField(title: "Título", placeholder: "Golpe en tobillo", text: $title)
                    WorkspaceCreateMultilineField(title: "Detalle", placeholder: "Qué ha pasado y contexto inmediato", text: $detail)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Severidad")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Severidad", selection: $severity) {
                            Text("Baja").tag("low")
                            Text("Media").tag("medium")
                            Text("Alta").tag("high")
                            Text("Crítica").tag("critical")
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

            IOSSectionCard(title: "Contexto", systemImage: "person.crop.rectangle.stack") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Estado", selection: $workflowState) {
                        ForEach(PEIncidentWorkflowState.allCases) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }
                    Picker("Alumno", selection: $selectedStudentId) {
                        Text("Sin alumno").tag(Int64?.none)
                        ForEach(bridge.studentsInClass, id: \.id) { student in
                            Text("\(student.firstName) \(student.lastName)").tag(Optional(student.id))
                        }
                    }
                    Picker("Sesión", selection: $selectedSessionId) {
                        Text("Sin sesión").tag(Int64?.none)
                        ForEach(sessions, id: \.id) { session in
                            Text(session.session.teachingUnitName).tag(Optional(session.id))
                        }
                    }
                    WorkspaceCreateMultilineField(title: "Nota de seguimiento", placeholder: "Primer seguimiento o próxima acción", text: $followUpNote)
                }
            }
        }
        .task {
            await bridge.selectStudentsClass(classId: defaultClassId)
            let calendar = Calendar(identifier: .iso8601)
            sessions = (try? await bridge.loadPESessions(
                weekNumber: calendar.component(.weekOfYear, from: Date()),
                year: calendar.component(.yearForWeekOfYear, from: Date()),
                classId: defaultClassId
            )) ?? []
        }
    }

    private func save() {
        Task {
            guard let defaultClassId, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let finalTitle = "\(category) · \(title)"
            let finalDetail = [
                detail,
                selectedSessionId == nil ? nil : "Sesión vinculada #\(selectedSessionId!)",
                followUpNote.nilIfBlank.map { "Seguimiento inicial: \($0)" }
            ].compactMap { $0?.nilIfBlank }.joined(separator: "\n")
            if let incidentId = try? await bridge.createIncident(
                classId: defaultClassId,
                studentId: selectedStudentId,
                title: finalTitle,
                detail: finalDetail,
                severity: severity
            ) {
                onSaved(incidentId, category, workflowState, selectedSessionId, followUpNote)
                dismiss()
            }
        }
    }
}

struct CreatePEMaterialRecordSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let sessions: [KmpBridge.PESessionSnapshot]
    let onSaved: (PEMaterialRecord) -> Void

    @State var itemName = ""
    @State var quantity = 1
    @State var status: PEMaterialStatus = .prepared
    @State var note = ""
    @State var selectedSessionId: Int64?

    private var canSave: Bool {
        defaultClassId != nil && !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nuevo material",
            subtitle: "Registra material preparado o usado y vincúlalo a una sesión si procede.",
            systemImage: "shippingbox.fill",
            canSave: canSave,
            onCancel: { dismiss() },
            onSave: save
        ) {
            IOSSectionCard(title: "Material", systemImage: "list.bullet.clipboard") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Material", placeholder: "Petos azules", text: $itemName)
                    Stepper("Cantidad \(quantity)", value: $quantity, in: 1...100)
                    Picker("Estado", selection: $status) {
                        ForEach(PEMaterialStatus.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Sesión", selection: $selectedSessionId) {
                        Text("Sin sesión").tag(Int64?.none)
                        ForEach(sessions, id: \.id) { session in
                            Text(session.session.teachingUnitName).tag(Optional(session.id))
                        }
                    }
                    WorkspaceCreateMultilineField(title: "Nota", placeholder: "Detalle útil para preparar o revisar", text: $note)
                }
            }
        }
    }

    private func save() {
        Task {
            guard let defaultClassId, !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let record = PEMaterialRecord(
                id: UUID(),
                classId: defaultClassId,
                sessionId: selectedSessionId,
                itemName: itemName,
                quantity: quantity,
                status: status,
                note: note,
                createdAt: Date()
            )
            if let session = sessions.first(where: { $0.id == selectedSessionId }) {
                let materialLine = "\(itemName) x\(quantity)" + (note.nilIfBlank.map { " (\($0))" } ?? "")
                let prepared = status == .prepared ? materialLine : session.materialToPrepareText
                let used = status == .used ? materialLine : session.materialUsedText
                try? await bridge.savePESessionOperationalData(
                    sessionId: session.id,
                    scheduledSpace: "",
                    usedSpace: "",
                    materialToPrepare: prepared,
                    materialUsed: used,
                    injuries: session.injuriesText,
                    unequippedStudents: session.unequippedStudentsText,
                    intensityScore: session.intensityScore,
                    stationObservations: session.stationObservationsText,
                    physicalIncidents: session.physicalIncidentsText,
                    journalStatus: session.summary?.status ?? .draft
                )
            }
            onSaved(record)
            dismiss()
        }
    }
}

struct CreateTournamentSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let defaultClassId: Int64?
    let onSaved: (TournamentViewState) -> Void

    @State var name = ""
    @State var sport = "Baloncesto"
    @State var template: TournamentTemplate = .roundRobin
    @State var teamCount = 4
    @State var pointsWin = 3
    @State var pointsDraw = 1
    @State var pointsLoss = 0
    @State var tieBreaker = "Diferencia de tantos"
    @State var sportOptions: [String] = []
    @State var tieBreakerOptions: [String] = []
    @State var showingNewSportAlert = false
    @State var showingNewTieBreakerAlert = false
    @State var newSport = ""
    @State var newTieBreaker = ""

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Nuevo torneo EF",
            subtitle: "Crea el cuadro base y los equipos iniciales para empezar a jugar.",
            systemImage: "trophy.fill",
            canSave: defaultClassId != nil,
            onCancel: { dismiss() },
            onSave: save
        ) {
            IOSSectionCard(title: "Identidad", systemImage: "trophy") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Nombre del torneo", placeholder: "Torneo de \(sport)", text: $name)
                    Menu {
                        ForEach(sportOptions, id: \.self) { option in
                            Button(option) { sport = option }
                        }
                        Divider()
                        Button("Añadir nueva opción…") {
                            showingNewSportAlert = true
                        }
                    } label: {
                        tournamentOptionRow(title: "Deporte / modalidad", value: sport)
                    }
                    .buttonStyle(.bordered)

                    Picker("Plantilla", selection: $template) {
                        ForEach(TournamentTemplate.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
            }

            IOSSectionCard(title: "Equipos y puntuación", systemImage: "person.3.fill") {
                VStack(alignment: .leading, spacing: 16) {
                    Stepper("Equipos \(teamCount)", value: $teamCount, in: 2...8)
                    Stepper("Puntos victoria \(pointsWin)", value: $pointsWin, in: 0...10)
                    Stepper("Puntos empate \(pointsDraw)", value: $pointsDraw, in: 0...10)
                    Stepper("Puntos derrota \(pointsLoss)", value: $pointsLoss, in: 0...10)
                    Menu {
                        ForEach(tieBreakerOptions, id: \.self) { option in
                            Button(option) { tieBreaker = option }
                        }
                        Divider()
                        Button("Añadir nueva opción…") {
                            showingNewTieBreakerAlert = true
                        }
                    } label: {
                        tournamentOptionRow(title: "Desempate", value: tieBreaker)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .task {
            sportOptions = storedItems(forKey: peTournamentSportsStorageKey, as: String.self)
            if sportOptions.isEmpty {
                sportOptions = ["Baloncesto", "Fútbol sala", "Balonmano", "Voleibol", "Bádminton"]
            }
            tieBreakerOptions = storedItems(forKey: peTournamentTieBreakersStorageKey, as: String.self)
            if tieBreakerOptions.isEmpty {
                tieBreakerOptions = ["Diferencia de tantos", "Enfrentamiento directo", "Fair play", "Tantos a favor"]
            }
            if !sportOptions.contains(sport) { sportOptions.append(sport) }
            if !tieBreakerOptions.contains(tieBreaker) { tieBreakerOptions.append(tieBreaker) }
        }
        .alert("Añadir deporte", isPresented: $showingNewSportAlert) {
            TextField("Nuevo deporte", text: $newSport)
            Button("Cancelar", role: .cancel) { newSport = "" }
            Button("Guardar") {
                guard let option = newSport.nilIfBlank else { return }
                if !sportOptions.contains(option) {
                    sportOptions.append(option)
                    persistItems(sportOptions, forKey: peTournamentSportsStorageKey)
                }
                sport = option
                newSport = ""
            }
        }
        .alert("Añadir desempate", isPresented: $showingNewTieBreakerAlert) {
            TextField("Nuevo criterio", text: $newTieBreaker)
            Button("Cancelar", role: .cancel) { newTieBreaker = "" }
            Button("Guardar") {
                guard let option = newTieBreaker.nilIfBlank else { return }
                if !tieBreakerOptions.contains(option) {
                    tieBreakerOptions.append(option)
                    persistItems(tieBreakerOptions, forKey: peTournamentTieBreakersStorageKey)
                }
                tieBreaker = option
                newTieBreaker = ""
            }
        }
    }

    func tournamentOptionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Color.accentColor)
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        Task {
            guard let defaultClassId else { return }
            await bridge.selectStudentsClass(classId: defaultClassId)
            let teams = generateTeams(students: bridge.studentsInClass, count: teamCount)
            let tournament = TournamentViewState(
                id: UUID(),
                classId: defaultClassId,
                name: name.nilIfBlank ?? "Torneo \(sport)",
                sport: sport,
                template: template,
                status: .draft,
                pointsWin: pointsWin,
                pointsDraw: pointsDraw,
                pointsLoss: pointsLoss,
                tieBreaker: tieBreaker.nilIfBlank ?? "Diferencia de tantos",
                teams: teams,
                matches: generateTournamentMatches(template: template, teams: teams),
                studentProfiles: normalizedProfiles(students: bridge.studentsInClass, existingProfiles: nil),
                createdAt: Date()
            )
            onSaved(tournament)
            dismiss()
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
