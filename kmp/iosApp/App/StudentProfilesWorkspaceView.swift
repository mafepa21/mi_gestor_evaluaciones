import SwiftUI
import MiGestorKit

// MARK: - Filtro de seguimiento
private enum StudentTrackingFilter: String, CaseIterable {
    case todos = "Todos"
    case seguimiento = "Seguimiento"
    case lesionados = "Lesionados"
}

struct StudentProfilesWorkspaceView: View {
    let bridge: KmpBridge
    @ObservedObject var studentsBridgeStore: StudentsBridgeStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    init(
        bridge: KmpBridge,
        studentsBridgeStore: StudentsBridgeStore,
        selectedClassId: Binding<Int64?>,
        selectedStudentId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void
    ) {
        self.bridge = bridge
        self.studentsBridgeStore = studentsBridgeStore
        self._selectedClassId = selectedClassId
        self._selectedStudentId = selectedStudentId
        self.onOpenModule = onOpenModule
    }

    @State private var searchText = ""
    @State private var trackingFilter: StudentTrackingFilter = .todos
    @State private var profile: KmpBridge.StudentProfileSnapshot?
    @State private var isLoadingProfile = false
    @State private var showFollowUpConfirm = false
    @State private var showIncidentsSheet = false
    @State private var updatingStudentIds: Set<Int64> = []
    @State private var supportMeasures: [SupportMeasureRow] = []
    @State private var showSupportMeasureSheet = false
    @State private var showBulkImportSheet = false
    @State private var showGroupOverviewSheet = false
    @State private var pendingDeleteStudent: Student?
    @State private var pendingDeleteSupportMeasure: SupportMeasureRow?
    @State private var editingStudent: Student?
    @State private var editingSupportMeasure: SupportMeasureRow?

    // MARK: - Computed

    private var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = studentsBridgeStore.studentsInClass.isEmpty ? studentsBridgeStore.allStudents : studentsBridgeStore.studentsInClass

        let tracked: [Student]
        switch trackingFilter {
        case .todos:
            tracked = base
        case .seguimiento:
            tracked = base.filter { _ in true } // isFollowUp not on Student model — show all for now
        case .lesionados:
            tracked = base.filter { $0.isInjured }
        }

        guard !query.isEmpty else { return tracked }
        return tracked.filter {
            "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Body

    var body: some View {
        studentWorkspaceContent
            .task {
                await bridge.ensureClassesLoaded()
                await bridge.selectStudentsClass(classId: selectedClassId)
                if selectedStudentId == nil {
                    selectedStudentId = studentsBridgeStore.studentsInClass.first?.id ?? studentsBridgeStore.allStudents.first?.id
                }
                await reloadProfile()
            }
            .appOnChange(of: selectedClassId) { _ in
                Task {
                    await bridge.selectStudentsClass(classId: selectedClassId)
                    if selectedStudentId == nil {
                        selectedStudentId = studentsBridgeStore.studentsInClass.first?.id
                    }
                    await reloadProfile()
                }
            }
            .appOnChange(of: selectedStudentId) { _ in
                Task { await reloadProfile() }
            }
            .sheet(isPresented: $showSupportMeasureSheet) {
                if let studentId = selectedStudentId {
                    SupportMeasureFormSheet(studentId: studentId) {
                        Task { await reloadProfile() }
                    }
                    .environmentObject(bridge)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { editingSupportMeasure != nil },
                    set: { if !$0 { editingSupportMeasure = nil } }
                )
            ) {
                if let studentId = selectedStudentId, let editingSupportMeasure {
                    SupportMeasureFormSheet(studentId: studentId, existingMeasure: editingSupportMeasure) {
                        Task { await reloadProfile() }
                    }
                    .environmentObject(bridge)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { editingStudent != nil },
                    set: { if !$0 { editingStudent = nil } }
                )
            ) {
                if let student = editingStudent {
                    StudentEditorSheet(student: student) { firstName, lastName, email in
                        Task { await updateStudent(student, firstName: firstName, lastName: lastName, email: email) }
                    }
                }
            }
            .confirmationDialog(
                "Eliminar alumno",
                isPresented: Binding(
                    get: { pendingDeleteStudent != nil },
                    set: { if !$0 { pendingDeleteStudent = nil } }
                ),
                presenting: pendingDeleteStudent
            ) { student in
                if selectedClassId != nil {
                    Button("Quitar del grupo", role: .destructive) {
                        Task { await removeStudentFromClass(student) }
                    }
                }
                Button("Eliminar de toda la app", role: .destructive) {
                    Task { await deleteStudentEverywhere(student) }
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteStudent = nil
                }
            } message: { student in
                Text("\(student.firstName) \(student.lastName) tiene evaluaciones, asistencia y medidas vinculadas. Elige si quieres quitarlo solo de este grupo o eliminarlo por completo.")
            }
            .confirmationDialog(
                "Eliminar medida de apoyo",
                isPresented: Binding(
                    get: { pendingDeleteSupportMeasure != nil },
                    set: { if !$0 { pendingDeleteSupportMeasure = nil } }
                ),
                presenting: pendingDeleteSupportMeasure
            ) { measure in
                Button("Eliminar \(measure.level.displayName) · \(measure.measureType.displayName)", role: .destructive) {
                    Task { await deleteSupportMeasure(measure) }
                }
                Button("Cancelar", role: .cancel) {
                    pendingDeleteSupportMeasure = nil
                }
            } message: { _ in
                Text("Se eliminará este registro por completo. Si solo quieres cerrarla, usa \"Retirar\".")
            }
    }

    @ViewBuilder
    private var studentWorkspaceContent: some View {
        ViewThatFits(in: .horizontal) {
            regularStudentWorkspace
            compactStudentWorkspace
        }
    }

    private var regularStudentWorkspace: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(minWidth: 290, maxWidth: 330)

            Divider().opacity(0.2)

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760)
    }

    private var compactStudentWorkspace: some View {
        VStack(spacing: 16) {
            leftColumn
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360, maxHeight: 520)

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .background(appPageBackground(for: colorScheme))
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Class picker
            classPickerHeader

            Divider().opacity(0.15)

            // Filters
            VStack(spacing: 10) {
                IOSSearchField(text: $searchText, placeholder: "Buscar alumno…")

                Picker("Filtro", selection: $trackingFilter) {
                    ForEach(StudentTrackingFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.15)

            // Student list
            if filteredStudents.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "person.slash")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Sin alumnos")
                        .font(IOSAppStyle.captionText)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(filteredStudents, id: \.id) { student in
                    StudentListRow(
                        student: student,
                        isSelected: selectedStudentId == student.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(uiFeatureFlags.interactionAnimation) {
                            selectedStudentId = student.id
                        }
                        AppleInteractionFeedback.play(.selection)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Eliminar", role: .destructive) {
                            pendingDeleteStudent = student
                        }
                        .tint(IOSAppStyle.danger)

                        Button(student.isInjured ? "Quitar lesión" : "Lesión") {
                            Task { await toggleInjuryStatus(for: student) }
                        }
                        .tint(.orange)

                        Button("Incidencia") {
                            Task { await registerIncident(for: student) }
                        }
                        .tint(IOSAppStyle.danger)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Editar") {
                            editingStudent = student
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editingStudent = student
                        } label: {
                            Label("Editar alumno", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDeleteStudent = student
                        } label: {
                            Label("Eliminar alumno", systemImage: "trash")
                        }
                    }
                    .disabled(updatingStudentIds.contains(student.id))
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous)
                            .fill(selectedStudentId == student.id
                                  ? IOSAppStyle.info.opacity(0.10)
                                  : Color.clear)
                            .padding(.horizontal, 4)
                    )
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }

            Divider().opacity(0.15)

            // Footer count
            Text("\(filteredStudents.count) alumno\(filteredStudents.count == 1 ? "" : "s")")
                .font(IOSAppStyle.captionText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .background(IOSAppStyle.cardBackground)
    }

    private var classPickerHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GRUPO")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("Grupo", selection: $selectedClassId) {
                    Text("Todos los grupos").tag(Optional<Int64>.none)
                    ForEach(studentsBridgeStore.classes, id: \.id) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(IOSAppStyle.info)

                if selectedClassId != nil {
                    Button {
                        showBulkImportSheet = true
                    } label: {
                        Image(systemName: "tablecells.badge.ellipsis")
                    }
                    .help("Importar medidas Nivel III desde Excel")

                    Button {
                        showGroupOverviewSheet = true
                    } label: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                    .help("Ver medidas del grupo")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .sheet(isPresented: $showBulkImportSheet) {
            if let selectedClassId {
                SupportMeasureBulkImportSheet(
                    classId: selectedClassId,
                    roster: studentsBridgeStore.studentsInClass
                ) {
                    Task { await reloadProfile() }
                }
                .environmentObject(bridge)
            }
        }
        .sheet(isPresented: $showGroupOverviewSheet) {
            SupportMeasureGroupOverviewSheet(
                className: studentsBridgeStore.classes.first(where: { $0.id == selectedClassId })?.name ?? "",
                roster: studentsBridgeStore.studentsInClass
            )
            .environmentObject(bridge)
        }
    }

    // MARK: - Right Column

    @ViewBuilder
    private var rightColumn: some View {
        if let profile {
            VStack(spacing: 0) {
                // Quick action bar — fijo arriba
                quickActionBar(for: profile)
                    .padding(.horizontal, IOSAppStyle.pagePadding)
                    .padding(.vertical, 12)
                    .background(IOSAppStyle.cardBackground.opacity(0.9))
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(IOSAppStyle.cardBorder).frame(height: 1)
                    }

                // Scrollable detail
                profileDetail(profile)
            }
        } else if isLoadingProfile {
            loadingState
        } else {
            emptyState
        }
    }

    // MARK: - Quick Action Bar

    private func quickActionBar(for profile: KmpBridge.StudentProfileSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                PrimaryActionButton(
                    label: "Cuaderno",
                    systemImage: "book.closed.fill",
                    tint: IOSAppStyle.info,
                    fullWidth: false
                ) {
                    onOpenModule(.notebook, selectedClassId, profile.student.id)
                }

                quickActionChip(label: "Asistencia", systemImage: "checklist.checked", tint: IOSAppStyle.success) {
                    onOpenModule(.attendance, selectedClassId, profile.student.id)
                }

                quickActionChip(label: "Diario", systemImage: "doc.text.fill", tint: .indigo) {
                    onOpenModule(.diary, selectedClassId, profile.student.id)
                }

                quickActionChip(label: "Informes", systemImage: "doc.richtext.fill", tint: .purple) {
                    onOpenModule(.reports, selectedClassId, profile.student.id)
                }

                Divider()
                    .frame(height: 28)
                    .padding(.horizontal, 2)

                quickActionChip(
                    label: profile.student.isInjured ? "Lesión activa" : "Seguimiento",
                    systemImage: profile.student.isInjured ? "bandage.fill" : "arrow.triangle.branch",
                    tint: profile.student.isInjured ? IOSAppStyle.warning : .secondary,
                    filled: false
                ) {
                    showFollowUpConfirm = true
                }

                if profile.incidentCount > 0 {
                    quickActionChip(
                        label: "\(profile.incidentCount) incidencia\(profile.incidentCount == 1 ? "" : "s")",
                        systemImage: "exclamationmark.bubble.fill",
                        tint: IOSAppStyle.danger,
                        filled: false
                    ) { }
                }
            }
        }
    }

    private func quickActionChip(
        label: String,
        systemImage: String,
        tint: Color,
        filled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(filled ? tint : tint.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous)
                    .fill(filled ? tint.opacity(0.12) : IOSAppStyle.subtleFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous)
                            .stroke(tint.opacity(filled ? 0.22 : 0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Profile Detail

    private func profileDetail(_ profile: KmpBridge.StudentProfileSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                // Hero
                WorkspaceInspectorHero(
                    title: "\(profile.student.firstName) \(profile.student.lastName)",
                    subtitle: profile.schoolClass?.name ?? "Sin grupo activo"
                )

                // Status chips row
                HStack(spacing: 8) {
                    IOSStatusPill(
                        label: profile.student.isInjured ? "Lesionado" : "Disponible",
                        isActive: profile.student.isInjured,
                        tint: profile.student.isInjured ? IOSAppStyle.warning : IOSAppStyle.success
                    )
                    IOSStatusPill(
                        label: profile.latestAttendanceStatus ?? "Sin registros",
                        isActive: !(profile.latestAttendanceStatus?.uppercased().contains("AUS") ?? false),
                        tint: profile.latestAttendanceStatus?.uppercased().contains("AUS") == true
                            ? IOSAppStyle.danger : IOSAppStyle.success
                    )
                    IOSStatusPill(
                        label: "\(profile.incidentCount) incid.",
                        isActive: profile.incidentCount > 0,
                        tint: IOSAppStyle.danger
                    )
                    if let activeLevel = supportMeasures.first(where: \.isActive)?.level {
                        IOSStatusPill(
                            label: "Medida \(activeLevel.shortLabel)",
                            isActive: true,
                            tint: .indigo
                        )
                    }
                    Spacer()
                }

                // Metric grid
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    IOSMetricCard(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked", tint: IOSAppStyle.success)
                    IOSMetricCard(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum", tint: IOSAppStyle.info)
                    IOSMetricCard(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill", tint: IOSAppStyle.danger)
                    IOSMetricCard(title: "Seguimiento", value: "\(profile.followUpCount)", systemImage: "arrow.triangle.branch", tint: IOSAppStyle.warning)
                    IOSMetricCard(title: "Instrumentos", value: "\(profile.instrumentsCount)", systemImage: "chart.bar.doc.horizontal")
                    IOSMetricCard(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                    IOSMetricCard(title: "Sesiones diario", value: "\(profile.journalSessionCount)", systemImage: "doc.text.fill")
                    IOSMetricCard(title: "Familias", value: "\(profile.familyCommunicationCount)", systemImage: "person.2.fill", tint: .indigo)
                }

                // Asistencia reciente
                if !profile.recentAttendance.isEmpty {
                    let recent = Array(profile.recentAttendance.prefix(4))
                    PremiumCard.section(title: "Asistencia reciente", systemImage: "checklist.checked") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recent, id: \.id) { attendance in
                                recentAttendanceRow(attendance)
                            }
                        }
                    }
                }

                // Incidencias
                if !profile.incidents.isEmpty {
                    PremiumCard.section(title: "Incidencias destacadas", systemImage: "exclamationmark.bubble.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(profile.incidents.prefix(3), id: \.id) { incident in
                                incidentRow(incident)
                            }
                        }
                    }
                }

                // Instrumentos vinculados
                if !profile.evaluationTitles.isEmpty {
                    PremiumCard.section(title: "Instrumentos vinculados", systemImage: "checklist") {
                        WorkspaceFlowLayout(spacing: 8) {
                            ForEach(Array(profile.evaluationTitles.enumerated()), id: \.offset) { _, title in
                                WorkspaceTag(text: title, systemImage: "checklist")
                            }
                        }
                    }
                }

                // Resumen docente
                PremiumCard.section(title: "Resumen docente", systemImage: "doc.text.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProfileSummaryLine(title: "Grupo activo", value: profile.schoolClass?.name ?? "Sin grupo filtrado")
                        ProfileSummaryLine(title: "Seguimientos abiertos", value: "\(profile.followUpCount)")
                        ProfileSummaryLine(title: "Registros con evidencia", value: "\(profile.evidenceCount)")
                        ProfileSummaryLine(title: "Instrumentos evaluativos", value: "\(profile.instrumentsCount)")
                        ProfileSummaryLine(title: "Sesiones con seguimiento", value: "\(profile.journalSessionCount)")
                    }
                }

                // Medidas de apoyo (Nivel III/IV, Decreto 104/2018 + Orden 20/2019 CV)
                PremiumCard.section(title: "Medidas de apoyo", systemImage: "person.text.rectangle.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        if supportMeasures.isEmpty {
                            Text("Sin medidas registradas.")
                                .font(IOSAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(supportMeasures) { measure in
                                supportMeasureRow(measure)
                            }
                        }
                        Button {
                            showSupportMeasureSheet = true
                        } label: {
                            Label("Añadir medida", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // Contexto pedagógico
                if profile.adaptationsSummary != nil || profile.familyCommunicationSummary != nil {
                    PremiumCard.section(title: "Contexto pedagógico", systemImage: "person.text.rectangle") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let adaptations = profile.adaptationsSummary {
                                WorkspaceDetailBlock(title: "Adaptaciones recientes", content: adaptations)
                            }
                            if let comms = profile.familyCommunicationSummary {
                                WorkspaceDetailBlock(title: "Comunicación con familias", content: comms)
                            }
                        }
                    }
                }

                // Timeline
                PremiumCard.section(title: "Timeline docente", systemImage: "clock.arrow.circlepath") {
                    VStack(alignment: .leading, spacing: 8) {
                        if profile.timeline.isEmpty {
                            Text("Todavía no hay registros vinculados.")
                                .font(IOSAppStyle.bodyText)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(profile.timeline) { entry in
                                timelineRow(entry)
                            }
                        }
                    }
                }
            }
            .padding(IOSAppStyle.pagePadding)
        }
        .background(IOSAppStyle.pageBackground)
    }

    // MARK: - Sub-rows

    private func recentAttendanceRow(_ att: KmpBridge.AttendanceRecordSnapshot) -> some View {
        let note = att.note.isEmpty ? "Registro diario" : att.note
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(att.status)
                    .font(.subheadline.weight(.bold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(att.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
    }

    private func supportMeasureRow(_ measure: SupportMeasureRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(measure.level.displayName) · \(measure.measureType.displayName)")
                        .font(.subheadline.weight(.bold))
                    if !measure.isActive {
                        Text("Retirada")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let responsible = measure.responsible, !responsible.isEmpty {
                    Text(responsible)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                switch measure.reviewStatus {
                case .overdue:
                    Text("Revisión vencida")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(IOSAppStyle.danger)
                case .dueSoon:
                    Text("Revisión próxima")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(IOSAppStyle.warning)
                case .none:
                    EmptyView()
                }
            }
            Spacer()
            if measure.isActive {
                Button("Editar") {
                    editingSupportMeasure = measure
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderless)

                Button("Retirar") {
                    Task { await retireSupportMeasure(measure) }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
        .contextMenu {
            if measure.isActive {
                Button {
                    editingSupportMeasure = measure
                } label: {
                    Label("Editar medida", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                pendingDeleteSupportMeasure = measure
            } label: {
                Label("Eliminar medida", systemImage: "trash")
            }
        }
    }

    private func incidentRow(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(incident.title)
                    .font(.subheadline.weight(.bold))
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
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
    }

    private func timelineRow(_ entry: KmpBridge.StudentTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.subheadline.weight(.bold))
            Text(entry.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(IOSAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Cargando ficha…")
                .font(IOSAppStyle.bodyText)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IOSAppStyle.pageBackground)
    }

    private var emptyState: some View {
        IOSEmptyState(
            title: "Selecciona un alumno",
            subtitle: "La ficha reúne asistencia, evolución, incidencias y evidencias en un mismo flujo.",
            systemImage: "person.text.rectangle"
        )
        .background(IOSAppStyle.pageBackground)
    }

    // MARK: - Data

    @MainActor
    private func reloadProfile() async {
        guard let studentId = selectedStudentId else {
            profile = nil
            supportMeasures = []
            return
        }
        isLoadingProfile = true
        profile = try? await bridge.loadStudentProfile(studentId: studentId, classId: selectedClassId)
        supportMeasures = ((try? await bridge.supportMeasures(for: studentId)) ?? []).map(\.asRow)
        isLoadingProfile = false
    }

    @MainActor
    private func toggleInjuryStatus(for student: Student) async {
        guard !updatingStudentIds.contains(student.id) else { return }
        updatingStudentIds.insert(student.id)
        defer { updatingStudentIds.remove(student.id) }

        do {
            try await bridge.updateStudentInjuryStatus(
                studentId: student.id,
                isInjured: !student.isInjured,
                classId: selectedClassId
            )
            await bridge.selectStudentsClass(classId: selectedClassId)
            selectedStudentId = student.id
            await reloadProfile()
            bridge.status = student.isInjured ? "Lesión retirada." : "Alumno marcado con lesión."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo actualizar la lesión: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    private func retireSupportMeasure(_ measure: SupportMeasureRow) async {
        do {
            try await bridge.retireSupportMeasure(
                id: measure.id,
                endDateIso: AppDateTimeSupport.isoDateFormatter.string(from: Date())
            )
            await reloadProfile()
            bridge.status = "Medida retirada."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo retirar la medida: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    private func deleteSupportMeasure(_ measure: SupportMeasureRow) async {
        pendingDeleteSupportMeasure = nil
        do {
            try await bridge.deleteSupportMeasure(id: measure.id)
            await reloadProfile()
            bridge.status = "Medida eliminada."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo eliminar la medida: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    private func removeStudentFromClass(_ student: Student) async {
        pendingDeleteStudent = nil
        guard !updatingStudentIds.contains(student.id) else { return }
        updatingStudentIds.insert(student.id)
        defer { updatingStudentIds.remove(student.id) }

        do {
            try await bridge.removeStudentFromSelectedClass(studentId: student.id)
            if selectedStudentId == student.id {
                selectedStudentId = studentsBridgeStore.studentsInClass.first?.id
            }
            await reloadProfile()
            bridge.status = "\(student.firstName) \(student.lastName) se ha quitado del grupo."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo quitar al alumno del grupo: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    private func deleteStudentEverywhere(_ student: Student) async {
        pendingDeleteStudent = nil
        guard !updatingStudentIds.contains(student.id) else { return }
        updatingStudentIds.insert(student.id)
        defer { updatingStudentIds.remove(student.id) }

        do {
            try await bridge.deleteStudentEverywhere(studentId: student.id)
            if selectedStudentId == student.id {
                selectedStudentId = studentsBridgeStore.studentsInClass.first?.id ?? studentsBridgeStore.allStudents.first?.id
            }
            await reloadProfile()
            bridge.status = "\(student.firstName) \(student.lastName) se ha eliminado."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo eliminar al alumno: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    private func updateStudent(_ student: Student, firstName: String, lastName: String, email: String) async {
        editingStudent = nil
        do {
            try await bridge.updateMacStudent(
                student: student,
                firstName: firstName,
                lastName: lastName,
                email: email,
                isInjured: student.isInjured
            )
            await reloadProfile()
            bridge.status = "Alumno actualizado."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo actualizar el alumno: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    private func registerIncident(for student: Student) async {
        guard let selectedClassId, !updatingStudentIds.contains(student.id) else { return }
        updatingStudentIds.insert(student.id)
        defer { updatingStudentIds.remove(student.id) }

        do {
            _ = try await bridge.createIncident(
                classId: selectedClassId,
                studentId: student.id,
                title: "Incidencia desde alumnado",
                detail: "Registrada mediante acción rápida en la ficha del alumno."
            )
            selectedStudentId = student.id
            await reloadProfile()
            bridge.status = "Incidencia registrada."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo registrar la incidencia: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }
}

// MARK: - StudentListRow

private struct StudentListRow: View {
    let student: Student
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Text(initials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(avatarColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(student.firstName) \(student.lastName)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? IOSAppStyle.info : .primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if student.isInjured {
                        Label("Lesión", systemImage: "bandage.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IOSAppStyle.warning)
                    } else {
                        Text("Alumno")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IOSAppStyle.info.opacity(0.7))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var initials: String {
        let f = student.firstName.first.map(String.init) ?? ""
        let l = student.lastName.first.map(String.init) ?? ""
        return "\(f)\(l)"
    }

    private var avatarColor: Color {
        student.isInjured ? IOSAppStyle.warning : IOSAppStyle.info
    }
}

// MARK: - StudentEditorSheet

private struct StudentEditorSheet: View {
    let student: Student
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String

    init(student: Student, onSave: @escaping (String, String, String) -> Void) {
        self.student = student
        self.onSave = onSave
        _firstName = State(initialValue: student.firstName)
        _lastName = State(initialValue: student.lastName)
        _email = State(initialValue: student.email ?? "")
    }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos del alumno") {
                    TextField("Nombre", text: $firstName)
                    TextField("Apellidos", text: $lastName)
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .navigationTitle("Editar alumno")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(
                            firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                            lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                            email.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
