import SwiftUI
import AppKit
import MiGestorKit

enum MacStudentsPresentation {
    case full
    case content
    case inspector
}

struct MacStudentsView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    var presentation: MacStudentsPresentation = .full
    var reloadToken: Int = 0

    @State private var rows: [KmpBridge.MacStudentRowSnapshot] = []
    @State private var profile: KmpBridge.StudentProfileSnapshot?
    @State private var localSelectedStudentId: Int64?
    @State private var searchText = ""
    @State private var trackingFilter = "todos"
    @State private var workGroupFilter = "Todos"
    @State private var quickNoteText = ""
    @State private var isLoadingRows = false
    @State private var isLoadingProfile = false
    @State private var isSavingNote = false
    @State private var errorMessage: String?
    @State private var profileErrorMessage: String?
    @State private var riskPack: TeachingEvidencePack?
    @State private var isInspectorPresented = true
    @State private var didBootstrap = false
    @State private var profileLoadTask: Task<Void, Never>?
    @State private var studentEditorMode: MacStudentEditorMode?
    @FocusState private var isSearchFocused: Bool

    private var filteredRows: [KmpBridge.MacStudentRowSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            let matchesQuery = query.isEmpty ||
                row.student.fullName.localizedCaseInsensitiveContains(query) ||
                row.className.localizedCaseInsensitiveContains(query)
            let matchesTracking: Bool = {
                switch trackingFilter {
                case "seguimiento":
                    return row.isFollowUp
                case "lesionados":
                    return row.isInjured
                default:
                    return true
                }
            }()
            let matchesGroup = workGroupFilter == "Todos" || row.workGroupName == workGroupFilter
            return matchesQuery && matchesTracking && matchesGroup
        }
    }

    private var selectedRow: KmpBridge.MacStudentRowSnapshot? {
        guard let localSelectedStudentId else { return filteredRows.first }
        return rows.first(where: { $0.id == localSelectedStudentId }) ?? filteredRows.first
    }

    private var workGroupOptions: [String] {
        ["Todos"] + Array(Set(rows.map(\.workGroupName))).sorted()
    }

    private var selectedRowClassId: Int64? {
        selectedClassId ?? selectedRow?.classId
    }

    private var canSaveQuickNote: Bool {
        selectedRowClassId != nil && !quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSavingNote
    }

    var body: some View {
        Group {
            switch presentation {
            case .full:
                HSplitView {
                    studentsFilters
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                    studentsList
                        .frame(minWidth: 640)
                    if isInspectorPresented {
                        studentInspector
                            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                    }
                }
            case .content:
                HSplitView {
                    studentsFilters
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                    studentsList
                        .frame(minWidth: 560)
                }
            case .inspector:
                studentInspector
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430, maxHeight: .infinity)
            }
        }
        .background(MacAppStyle.pageBackground)
        .task {
            await bootstrapStudents()
        }
        .task(id: reloadToken) {
            guard reloadToken > 0 else { return }
            await reloadRows()
        }
        .appOnChange(of: selectedClassId) { _, newClassId in
            guard didBootstrap else { return }
            Task {
                await bridge.selectStudentsClass(classId: newClassId)
                await reloadRows()
            }
        }
        .appOnChange(of: localSelectedStudentId) { _, _ in
            scheduleProfileReload()
        }
        .appOnChange(of: filteredRows.map(\.id)) { _, visibleIds in
            guard !visibleIds.isEmpty else {
                localSelectedStudentId = nil
                profileLoadTask?.cancel()
                isLoadingProfile = false
                profile = nil
                riskPack = nil
                profileErrorMessage = nil
                return
            }
            if localSelectedStudentId == nil || !visibleIds.contains(localSelectedStudentId ?? -1) {
                localSelectedStudentId = visibleIds.first
            }
        }
        .onExitCommand {
            if !searchText.isEmpty {
                searchText = ""
            }
        }
        .background {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)

            Button("") {
                openSelectedInNotebook()
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)
        }
        .onDisappear {
            profileLoadTask?.cancel()
        }
        .sheet(item: $studentEditorMode) { mode in
            MacStudentEditorSheet(mode: mode) { draft in
                Task { await saveStudentDraft(draft, mode: mode) }
            }
        }
    }

    private var studentsList: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            studentsHeader
            studentsTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MacAppStyle.pagePadding)
    }

    private var studentsFilters: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Filtros")
                    .font(.title3.weight(.semibold))
                Text("\(filteredRows.count) de \(rows.count) alumnos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Clase", selection: $selectedClassId) {
                    Text("Todas").tag(Optional<Int64>.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Búsqueda")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Nombre o clase", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Seguimiento")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Seguimiento", selection: $trackingFilter) {
                    Text("Todos").tag("todos")
                    Text("Seguimiento").tag("seguimiento")
                    Text("Lesionados").tag("lesionados")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Grupo de trabajo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Grupo de trabajo", selection: $workGroupFilter) {
                    ForEach(workGroupOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(MacAppStyle.pagePadding)
        .background(MacAppStyle.cardBackground)
    }

    private var studentsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Alumnado")
                    .font(MacAppStyle.pageTitle)
                Text("Tabla densa con seguimiento, asistencia, media e incidencias.")
                    .font(MacAppStyle.bodyText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingRows {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await reloadRows() }
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            Button {
                guard let classId = selectedRowClassId else { return }
                studentEditorMode = .create(classId: classId)
            } label: {
                Label("Alumno", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRowClassId == nil)
            if presentation == .full {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label(isInspectorPresented ? "Ocultar ficha" : "Mostrar ficha", systemImage: "sidebar.trailing")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var studentsTable: some View {
        if rows.isEmpty && !isLoadingRows {
            ContentUnavailableView(
                "Sin alumnado",
                systemImage: "person.3",
                description: Text("No hay alumnos disponibles para la clase seleccionada.")
            )
        } else if filteredRows.isEmpty {
            ContentUnavailableView(
                "Sin coincidencias",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Ajusta la búsqueda o los filtros de seguimiento.")
            )
        } else {
            Table(filteredRows, selection: $localSelectedStudentId) {
                TableColumn("Nombre") { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.system(size: 13, weight: .semibold))
                        if row.student.email?.isEmpty == false {
                            Text(row.student.email ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Clase") { row in
                    Text(row.className)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                TableColumn("Seguimiento") { row in
                    MacStatusPill(
                        label: row.followUpLabel,
                        isActive: row.isFollowUp,
                        tint: row.isInjured ? MacAppStyle.warningTint : (row.isFollowUp ? MacAppStyle.infoTint : MacAppStyle.successTint)
                    )
                }
                .width(min: 112, ideal: 130)
                TableColumn("Asistencia reciente") { row in
                    Text(row.recentAttendanceLabel)
                        .font(.system(size: 12, weight: .medium))
                }
                .width(min: 130, ideal: 150)
                TableColumn("Media") { row in
                    Text(row.averageText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 82)
                TableColumn("Incidencias") { row in
                    Text("\(row.incidentCount)")
                        .font(.system(size: 12, weight: row.incidentCount > 0 ? .bold : .regular))
                        .foregroundStyle(row.incidentCount > 0 ? .red : .secondary)
                        .monospacedDigit()
                }
                .width(min: 82, ideal: 96)
                TableColumn("Última observación") { row in
                    Text(row.lastObservationText)
                        .font(.system(size: 12))
                        .foregroundStyle(row.lastObservationText == "Sin observaciones" ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private var studentInspector: some View {
        if let selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ficha del alumno")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedRow.student.fullName)
                            .font(.title2.weight(.semibold))
                        Text(selectedRow.className)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        MacStatusPill(
                            label: selectedRow.followUpLabel,
                            isActive: selectedRow.isFollowUp,
                            tint: selectedRow.isInjured ? MacAppStyle.warningTint : MacAppStyle.infoTint
                        )
                        MacStatusPill(
                            label: selectedRow.workGroupName,
                            isActive: selectedRow.workGroupName != "Sin grupo",
                            tint: MacAppStyle.successTint
                        )
                    }

                    inspectorSection("Datos del alumno") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let email = selectedRow.student.email, !email.isEmpty {
                                Label(email, systemImage: "envelope")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                studentEditorMode = .edit(row: selectedRow)
                            } label: {
                                Label("Editar datos", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if isLoadingProfile {
                        ProgressView("Cargando ficha…")
                    } else if let profileErrorMessage {
                        ContentUnavailableView(
                            "No se pudo cargar la ficha",
                            systemImage: "exclamationmark.triangle",
                            description: Text(profileErrorMessage)
                        )
                    } else if let profile {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            MacMetricCard(label: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                            MacMetricCard(label: "Media", value: IosFormatting.decimal(profile.averageScore), systemImage: "sum")
                            MacMetricCard(label: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble")
                            MacMetricCard(label: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                        }

                        if let riskPack, let level = riskPack.riskLevel {
                            inspectorSection("Radar de riesgo") {
                                VStack(alignment: .leading, spacing: 10) {
                                    MacStatusPill(
                                        label: level.title,
                                        isActive: level != .seguimientoNormal,
                                        tint: level == .atencionPrioritaria ? MacAppStyle.dangerTint : (level == .atencionPuntual ? MacAppStyle.warningTint : MacAppStyle.successTint)
                                    )
                                    Text(riskPack.summary)
                                        .font(.system(size: 13, weight: .medium))
                                    ForEach(Array(riskPack.warningTexts.prefix(3)), id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(riskPack.recommendedActionTexts.prefix(2)), id: \.self) { action in
                                        Label(action, systemImage: "arrowshape.right.circle")
                                            .font(.caption)
                                    }
                                }
                            }
                        }

                        inspectorSection("Notas rápidas") {
                            if selectedRowClassId == nil {
                                Text("Selecciona una clase para guardar notas rápidas.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                TextEditor(text: $quickNoteText)
                                    .frame(minHeight: 86)
                                    .font(.system(size: 13))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                HStack {
                                    Button {
                                        Task { await saveQuickNote() }
                                    } label: {
                                        Label(isSavingNote ? "Guardando…" : "Guardar nota", systemImage: "square.and.arrow.down")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!canSaveQuickNote)
                                    Spacer()
                                }
                            }
                        }

                        inspectorSection("Historial de incidencias") {
                            if profile.incidents.isEmpty {
                                Text("Sin incidencias registradas.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(profile.incidents.prefix(5), id: \.id) { incident in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(incident.title)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(incident.severity.capitalized)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(incident.detail ?? "Sin detalle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }

                        inspectorSection("Accesos") {
                            VStack(spacing: 8) {
                                Button {
                                    openSelectedInNotebook()
                                } label: {
                                    Label("Abrir en cuaderno", systemImage: "tablecells")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    openSelected(.attendance)
                                } label: {
                                    Label("Abrir asistencia", systemImage: "checklist.checked")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    openSelected(.reports)
                                } label: {
                                    Label("Abrir informes", systemImage: "doc.text")
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ProgressView("Cargando ficha…")
                    }
                }
                .padding(MacAppStyle.pagePadding)
            }
            .background(MacAppStyle.cardBackground)
        } else {
            VStack {
                ContentUnavailableView(
                    "Selecciona un alumno",
                    systemImage: "person.3",
                    description: Text("La ficha reunirá notas, incidencias y accesos cruzados.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(MacAppStyle.cardBackground)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            content()
        }
    }

    @MainActor
    private func bootstrapStudents() async {
        if selectedClassId == nil {
            selectedClassId = bridge.selectedStudentsClassId
        }
        await bridge.selectStudentsClass(classId: selectedClassId)
        await reloadRows(preferredStudentId: selectedStudentId)
        didBootstrap = true
    }

    @MainActor
    private func reloadRows(preferredStudentId: Int64? = nil) async {
        isLoadingRows = true
        errorMessage = nil
        defer { isLoadingRows = false }
        do {
            rows = try await bridge.loadMacStudentRows(classId: selectedClassId)
            let visibleIds = filteredRows.map(\.id)
            if let preferredStudentId, visibleIds.contains(preferredStudentId) {
                localSelectedStudentId = preferredStudentId
            } else if let localSelectedStudentId, visibleIds.contains(localSelectedStudentId) {
                self.localSelectedStudentId = localSelectedStudentId
            } else {
                localSelectedStudentId = visibleIds.first
            }
            scheduleProfileReload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleProfileReload() {
        profileLoadTask?.cancel()
        guard let studentId = localSelectedStudentId else {
            isLoadingProfile = false
            profile = nil
            riskPack = nil
            profileErrorMessage = nil
            return
        }

        let requestedClassId = selectedRowClassId
        profile = nil
        riskPack = nil
        profileErrorMessage = nil
        isLoadingProfile = true

        profileLoadTask = Task { @MainActor in
            do {
                let loadedProfile = try await bridge.loadStudentProfile(studentId: studentId, classId: requestedClassId)
                guard !Task.isCancelled,
                      localSelectedStudentId == studentId,
                      selectedRowClassId == requestedClassId else { return }
                profile = loadedProfile
                riskPack = try? await StudentRiskEvidenceBuilder.build(bridge: bridge, classId: requestedClassId, studentId: studentId)
                isLoadingProfile = false
            } catch {
                guard !Task.isCancelled,
                      localSelectedStudentId == studentId,
                      selectedRowClassId == requestedClassId else { return }
                profile = nil
                riskPack = nil
                profileErrorMessage = error.localizedDescription
                isLoadingProfile = false
            }
        }
    }

    @MainActor
    private func saveQuickNote() async {
        guard let studentId = localSelectedStudentId, let classId = selectedRowClassId else { return }
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            try await bridge.saveQuickStudentNote(studentId: studentId, classId: classId, note: quickNoteText)
            quickNoteText = ""
            await reloadRows(preferredStudentId: studentId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSelectedInNotebook() {
        openSelected(.notebook)
    }

    private func openSelected(_ module: AppWorkspaceModule) {
        guard let studentId = localSelectedStudentId else { return }
        selectedStudentId = studentId
        onOpenModule(module, selectedRowClassId, studentId)
    }

    @MainActor
    private func saveStudentDraft(_ draft: MacStudentDraft, mode: MacStudentEditorMode) async {
        errorMessage = nil
        do {
            switch mode {
            case .create(let classId):
                let studentId = try await bridge.createMacStudent(
                    firstName: draft.firstName,
                    lastName: draft.lastName,
                    email: draft.email,
                    isInjured: draft.isInjured,
                    classId: classId
                )
                studentEditorMode = nil
                await reloadRows(preferredStudentId: studentId)
            case .edit(let row):
                try await bridge.updateMacStudent(
                    student: row.student,
                    firstName: draft.firstName,
                    lastName: draft.lastName,
                    email: draft.email,
                    isInjured: draft.isInjured
                )
                studentEditorMode = nil
                await reloadRows(preferredStudentId: row.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum MacStudentEditorMode: Identifiable {
    case create(classId: Int64)
    case edit(row: KmpBridge.MacStudentRowSnapshot)

    var id: String {
        switch self {
        case .create(let classId):
            return "create-\(classId)"
        case .edit(let row):
            return "edit-\(row.id)"
        }
    }
}

private struct MacStudentDraft {
    var firstName: String
    var lastName: String
    var email: String
    var isInjured: Bool
}

private struct MacStudentEditorSheet: View {
    let mode: MacStudentEditorMode
    let onSave: (MacStudentDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var isInjured: Bool

    init(mode: MacStudentEditorMode, onSave: @escaping (MacStudentDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _firstName = State(initialValue: "")
            _lastName = State(initialValue: "")
            _email = State(initialValue: "")
            _isInjured = State(initialValue: false)
        case .edit(let row):
            _firstName = State(initialValue: row.student.firstName)
            _lastName = State(initialValue: row.student.lastName)
            _email = State(initialValue: row.student.email ?? "")
            _isInjured = State(initialValue: row.student.isInjured)
        }
    }

    private var title: String {
        switch mode {
        case .create: return "Nuevo alumno"
        case .edit: return "Editar alumno"
        }
    }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Nombre")
                        .foregroundStyle(.secondary)
                    TextField("Nombre", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Apellidos")
                        .foregroundStyle(.secondary)
                    TextField("Apellidos", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Email")
                        .foregroundStyle(.secondary)
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Lesión")
                        .foregroundStyle(.secondary)
                    Toggle("Alumno lesionado", isOn: $isInjured)
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") {
                    dismiss()
                }
                Button("Guardar") {
                    onSave(
                        MacStudentDraft(
                            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            isInjured: isInjured
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
