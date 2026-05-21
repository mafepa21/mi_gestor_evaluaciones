import SwiftUI
import MiGestorKit

// MARK: - Filtro de seguimiento
private enum StudentTrackingFilter: String, CaseIterable {
    case todos = "Todos"
    case seguimiento = "Seguimiento"
    case lesionados = "Lesionados"
}

struct StudentProfilesWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var searchText = ""
    @State private var trackingFilter: StudentTrackingFilter = .todos
    @State private var profile: KmpBridge.StudentProfileSnapshot?
    @State private var isLoadingProfile = false
    @State private var showFollowUpConfirm = false
    @State private var showIncidentsSheet = false

    // MARK: - Computed

    private var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass

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
        HStack(spacing: 0) {
            leftColumn
                .frame(minWidth: 290, maxWidth: 330)

            Divider().opacity(0.2)

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await bridge.ensureClassesLoaded()
            await bridge.selectStudentsClass(classId: selectedClassId)
            if selectedStudentId == nil {
                selectedStudentId = bridge.studentsInClass.first?.id ?? bridge.allStudents.first?.id
            }
            await reloadProfile()
        }
        .appOnChange(of: selectedClassId) { _ in
            Task {
                await bridge.selectStudentsClass(classId: selectedClassId)
                if selectedStudentId == nil {
                    selectedStudentId = bridge.studentsInClass.first?.id
                }
                await reloadProfile()
            }
        }
        .appOnChange(of: selectedStudentId) { _ in
            Task { await reloadProfile() }
        }
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
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedStudentId = student.id
                        }
                    }
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

            Picker("Grupo", selection: $selectedClassId) {
                Text("Todos los grupos").tag(Optional<Int64>.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text(schoolClass.name).tag(Optional(schoolClass.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(IOSAppStyle.info)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
                IOSPrimaryActionButton(
                    label: "Cuaderno",
                    systemImage: "book.closed.fill",
                    tint: IOSAppStyle.info
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
                    IOSSectionCard(title: "Asistencia reciente", systemImage: "checklist.checked") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recent, id: \.id) { attendance in
                                recentAttendanceRow(attendance)
                            }
                        }
                    }
                }

                // Incidencias
                if !profile.incidents.isEmpty {
                    IOSSectionCard(title: "Incidencias destacadas", systemImage: "exclamationmark.bubble.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(profile.incidents.prefix(3), id: \.id) { incident in
                                incidentRow(incident)
                            }
                        }
                    }
                }

                // Instrumentos vinculados
                if !profile.evaluationTitles.isEmpty {
                    IOSSectionCard(title: "Instrumentos vinculados", systemImage: "checklist") {
                        WorkspaceFlowLayout(spacing: 8) {
                            ForEach(Array(profile.evaluationTitles.enumerated()), id: \.offset) { _, title in
                                WorkspaceTag(text: title, systemImage: "checklist")
                            }
                        }
                    }
                }

                // Resumen docente
                IOSSectionCard(title: "Resumen docente", systemImage: "doc.text.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProfileSummaryLine(title: "Grupo activo", value: profile.schoolClass?.name ?? "Sin grupo filtrado")
                        ProfileSummaryLine(title: "Seguimientos abiertos", value: "\(profile.followUpCount)")
                        ProfileSummaryLine(title: "Registros con evidencia", value: "\(profile.evidenceCount)")
                        ProfileSummaryLine(title: "Instrumentos evaluativos", value: "\(profile.instrumentsCount)")
                        ProfileSummaryLine(title: "Sesiones con seguimiento", value: "\(profile.journalSessionCount)")
                    }
                }

                // Contexto pedagógico
                if profile.adaptationsSummary != nil || profile.familyCommunicationSummary != nil {
                    IOSSectionCard(title: "Contexto pedagógico", systemImage: "person.text.rectangle") {
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
                IOSSectionCard(title: "Timeline docente", systemImage: "clock.arrow.circlepath") {
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
            return
        }
        isLoadingProfile = true
        profile = try? await bridge.loadStudentProfile(studentId: studentId, classId: selectedClassId)
        isLoadingProfile = false
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
