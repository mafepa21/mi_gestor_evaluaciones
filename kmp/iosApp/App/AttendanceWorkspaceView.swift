import SwiftUI
import MiGestorKit


struct AttendanceWorkspaceView: View {
    let bridge: KmpBridge
    @ObservedObject var attendanceStore: AttendanceBridgeStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @EnvironmentObject var layoutState: WorkspaceLayoutState
    @Binding var selectedClassId: Int64?
    @Binding var preselectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    init(
        bridge: KmpBridge,
        attendanceStore: AttendanceBridgeStore,
        selectedClassId: Binding<Int64?>,
        preselectedStudentId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void
    ) {
        self.bridge = bridge
        self.attendanceStore = attendanceStore
        self._selectedClassId = selectedClassId
        self._preselectedStudentId = preselectedStudentId
        self.onOpenModule = onOpenModule
    }

    @State var selectedDate = Date()
    @State var boardMode: AttendanceBoardMode = .day
    @State var selectedStatusFilter = AttendanceStatusOption.allFilterId
    @State var searchText = ""
    @State var selectedStudentId: Int64?
    @State var historySelection: AttendanceHistorySelection?
    @State var recordsByStudentId: [Int64: KmpBridge.AttendanceRecordSnapshot] = [:]
    @State var classOverviews: [KmpBridge.AttendanceClassOverview] = []
    @State var savingStudentIds: Set<Int64> = []
    @State var savingInjuryStudentIds: Set<Int64> = []
    @State var localInjuryStatuses: [Int64: Bool] = [:]
    @State var saveRevisionByStudentId: [Int64: Int] = [:]
    @State var history: [KmpBridge.AttendanceRecordSnapshot] = []
    @State var incidents: [Incident] = []
    @State var sessions: [KmpBridge.AttendanceSessionSnapshot] = []
    @State var selectedAttendanceSessionId: Int64?
    @State var noteDraft = ""
    @State var isAttendanceInspectorPresented = false
    @State var showAllPresent = false
    @State var classSelectionTask: Task<Void, Never>?
    @State var dateReloadTask: Task<Void, Never>?

    var boardSummary: (present: Int, absent: Int, late: Int, untracked: Int) {
        let rows = attendanceStore.studentsInClass.map { recordsByStudentId[$0.id] }
        let present = rows.filter { AttendanceLogic.isPresentStatus($0?.status) }.count
        let absent = rows.filter { AttendanceLogic.isAbsentStatus($0?.status) }.count
        let late = rows.filter { AttendanceLogic.isLateStatus($0?.status) }.count
        let untracked = max(attendanceStore.studentsInClass.count - present - absent - late, 0)
        return (present, absent, late, untracked)
    }

    var filteredRows: [AttendanceEntryRow] {
        attendanceStore.studentsInClass
            .map { student in
                AttendanceEntryRow(
                    id: student.id,
                    student: student,
                    isInjured: isStudentInjured(student),
                    record: recordsByStudentId[student.id]
                )
            }
            .filter {
                let matchesStatus = selectedStatusFilter == AttendanceStatusOption.allFilterId || $0.record?.status == selectedStatusFilter
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullName = "\($0.student.firstName) \($0.student.lastName)"
                let matchesSearch = query.isEmpty || fullName.localizedCaseInsensitiveContains(query)
                return matchesStatus && matchesSearch
            }
    }

    func isStudentInjured(_ student: Student) -> Bool {
        localInjuryStatuses[student.id] ?? student.isInjured
    }

    var exceptionRows: [AttendanceEntryRow] {
        filteredRows.filter(AttendanceLogic.isRowUnresolved)
            .sorted { AttendanceLogic.exceptionPriority($0) < AttendanceLogic.exceptionPriority($1) }
    }

    var presentRows: [AttendanceEntryRow] {
        filteredRows.filter { !AttendanceLogic.isRowUnresolved($0) }
    }

    var selectedStudent: Student? {
        attendanceStore.studentsInClass.first(where: { $0.id == selectedStudentId })
    }

    var selectedAttendance: KmpBridge.AttendanceRecordSnapshot? {
        guard let selectedStudentId else { return nil }
        return recordsByStudentId[selectedStudentId]
    }

    var selectedInspectionAttendance: KmpBridge.AttendanceRecordSnapshot? {
        historySelection?.record ?? selectedAttendance
    }

    var inspectorDate: Date {
        historySelection?.date ?? selectedDate
    }

    var selectedClass: SchoolClass? {
        selectedClassId.flatMap { classId in attendanceStore.classes.first(where: { $0.id == classId }) }
    }

    var monthDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return [selectedDate.stripTime]
        }
        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var visibleHistoryRows: [Student] {
        attendanceStore.studentsInClass.filter { student in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || student.fullName.localizedCaseInsensitiveContains(query)
            let matchesStatus = selectedStatusFilter == AttendanceStatusOption.allFilterId || history.contains {
                $0.studentId == student.id && $0.status == selectedStatusFilter
            }
            return matchesSearch && matchesStatus
        }
    }

    var isInspectorPresented: Bool {
        (selectedStudentId != nil || historySelection != nil) && !layoutState.isFocusModeEnabled
    }

    var averageOverviewRate: Int {
        guard !classOverviews.isEmpty else { return 0 }
        return classOverviews.map(\.attendanceRate).reduce(0, +) / classOverviews.count
    }

    var criticalAlerts: [AttendanceAlert] {
        guard boardMode == .day else { return [] }
        let today = selectedDate.stripTime
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -6, to: today) else { return [] }
        var alerts: [AttendanceAlert] = []
        for student in attendanceStore.studentsInClass {
            let recentAbsences = history.filter {
                $0.studentId == student.id
                    && $0.date.stripTime >= windowStart
                    && $0.date.stripTime <= today
                    && AttendanceLogic.isAbsentStatus($0.status)
            }.count
            if recentAbsences >= 3 {
                alerts.append(AttendanceAlert(
                    id: "\(student.id)-absences",
                    student: student,
                    message: "\(recentAbsences) ausencias en 7 días",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: EvaluationDesign.danger
                ))
            }
            if localInjuryStatuses[student.id] ?? student.isInjured {
                alerts.append(AttendanceAlert(
                    id: "\(student.id)-injury",
                    student: student,
                    message: "Lesión activa",
                    systemImage: "cross.case.fill",
                    tint: .orange
                ))
            }
        }
        return alerts
    }


    var body: some View {
        attendanceWorkspacePrimaryPane
            .inspector(isPresented: $isAttendanceInspectorPresented) {
                attendanceInspector
                    .inspectorColumnWidth(min: 300, ideal: 336, max: 420)
            }
            .task {
                await bridge.ensureClassesLoaded()
                if selectedClassId == nil {
                    selectedClassId = attendanceStore.classes.first?.id
                }
                await reloadClassOverviews()
                await syncClassSelection()
                if let preselectedStudentId {
                    selectedStudentId = preselectedStudentId
                    self.preselectedStudentId = nil
                }
            }
            .appOnChange(of: selectedClassId) { _ in
                classSelectionTask?.cancel()
                classSelectionTask = Task { await syncClassSelection() }
            }
            .appOnChange(of: selectedDate) { _ in
                dateReloadTask?.cancel()
                dateReloadTask = Task {
                    await reloadClassOverviews()
                    guard !Task.isCancelled else { return }
                    await reloadAttendance()
                }
            }
            .appOnChange(of: boardMode) { _ in
                if boardMode == .courses {
                    selectedStudentId = nil
                    historySelection = nil
                }
            }
            .appOnChange(of: selectedStudentId) { _ in
                noteDraft = selectedInspectionAttendance?.note ?? ""
                isAttendanceInspectorPresented = isInspectorPresented
            }
            .appOnChange(of: historySelection?.id) { _ in
                isAttendanceInspectorPresented = isInspectorPresented
            }
            .appOnChange(of: layoutState.isFocusModeEnabled) { _ in
                isAttendanceInspectorPresented = isInspectorPresented
            }
            .appOnChange(of: isAttendanceInspectorPresented) { presented in
                // Si el usuario cierra el inspector con el gesto del sistema (arrastrar
                // el borde) en vez de "Cerrar ficha", `selectedStudentId`/`historySelection`
                // seguían activos y volver a tocar el mismo alumno no disparaba el
                // appOnChange correspondiente, así que la ficha no reabría. Al detectar
                // ese cierre externo, limpiamos la selección para que quede consistente
                // con el inspector oculto.
                guard !presented, isInspectorPresented else { return }
                selectedStudentId = nil
                historySelection = nil
            }
            .onAppear(perform: syncAttendanceToolbar)
            .appOnChange(of: toolbarStateKey) { _ in
                syncAttendanceToolbar()
            }
            .onDisappear {
                layoutState.clearAttendanceToolbar()
            }
            .animation(uiFeatureFlags.inspectorAnimation(presented: isInspectorPresented), value: isInspectorPresented)
    }

    var attendanceWorkspacePrimaryPane: some View {
        VStack(spacing: 0) {
            attendanceHeader
            if !criticalAlerts.isEmpty {
                criticalAlertsRow
            }
            attendanceToolbar
            attendanceMainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appPageBackground(for: colorScheme))
    }

    var criticalAlertsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(criticalAlerts) { alert in
                    Button {
                        historySelection = nil
                        selectedStudentId = alert.student.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: alert.systemImage)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alert.student.fullName)
                                    .font(.caption.weight(.bold))
                                Text(alert.message)
                                    .font(.caption2)
                            }
                        }
                        .foregroundStyle(alert.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(alert.tint.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
    }

    var attendanceHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asistencia")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text(attendanceContextSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(appPageBackground(for: colorScheme))
    }

    var attendanceContextSummary: String {
        let className = selectedClass?.name ?? "Todos los cursos"
        let filter = selectedStatusFilter == AttendanceStatusOption.allFilterId
            ? nil
            : AttendanceStatusOption.all.first(where: { $0.id == selectedStatusFilter })?.label
        return [className, boardMode.rawValue, filter].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    var attendanceMainContent: some View {
        switch boardMode {
        case .courses:
            coursesOverviewContent
        case .day:
            dayRollCallContent
        case .history:
            monthlyHistoryContent
        }
    }

    var coursesOverviewContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                ForEach(classOverviews) { overview in
                    Button {
                        selectedClassId = overview.id
                        boardMode = .day
                    } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(overview.schoolClass.name)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text("\(overview.studentCount) alumnos")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(overview.attendanceRate)%")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundStyle(EvaluationDesign.success)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                overviewMiniStat("Presentes", overview.presentCount, EvaluationDesign.success)
                                overviewMiniStat("Ausencias", overview.absentCount, EvaluationDesign.danger)
                                overviewMiniStat("Retrasos", overview.lateCount, AppleDesignSystem.warning)
                                overviewMiniStat("Pendientes", overview.pendingTodayCount, .gray)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    var dayRollCallContent: some View {
        Group {
            if filteredRows.isEmpty {
                WorkspaceEmptyState(title: "Sin alumnos visibles", subtitle: "Ajusta el curso, búsqueda o filtro de estado.")
            } else {
                List {
                    if exceptionRows.isEmpty {
                        allPresentBanner
                    } else {
                        ForEach(exceptionRows) { row in
                            dayRow(for: row)
                        }
                    }

                    if !presentRows.isEmpty {
                        presentSummaryDisclosure
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    func dayRow(for row: AttendanceEntryRow) -> some View {
        AttendanceRowCard(
            row: row,
            isInjured: row.isInjured,
            onPickStatus: { status in
                Task { await updateAttendance(for: row.student, status: status.id) }
            },
            onSelect: {
                historySelection = nil
                selectedStudentId = row.student.id
                AppleInteractionFeedback.play(.selection)
            },
            isSaving: savingStudentIds.contains(row.student.id)
                || savingInjuryStudentIds.contains(row.student.id)
        )
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Presente") {
                Task { await updateAttendance(for: row.student, status: "PRESENTE") }
            }
            .tint(AppleDesignSystem.success)
            Button("Ausente") {
                Task { await updateAttendance(for: row.student, status: "AUSENTE") }
            }
            .tint(AppleDesignSystem.danger)
            Button("Retraso") {
                Task { await updateAttendance(for: row.student, status: "TARDE") }
            }
            .tint(AppleDesignSystem.warning)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Sin material") {
                Task { await updateAttendance(for: row.student, status: "SIN_MATERIAL") }
            }
            .tint(.brown)
            Button("Justificada") {
                Task { await updateAttendance(for: row.student, status: "JUSTIFICADO") }
            }
            .tint(.gray)
            Button("Lesión") {
                Task { await markStudentInjured(row.student) }
            }
            .tint(.orange)
        }
        #endif
    }

    var allPresentBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(EvaluationDesign.success)
            Text("Todos presentes")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var presentSummaryDisclosure: some View {
        DisclosureGroup(isExpanded: $showAllPresent) {
            ForEach(presentRows) { row in
                dayRow(for: row)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(EvaluationDesign.success)
                Text("\(presentRows.count) presentes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var monthlyHistoryContent: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    weekCellHeader("Alumno", width: 220)
                    ForEach(monthDates, id: \.self) { date in
                        weekCellHeader(Self.dayHeaderString(date), width: 48)
                    }
                }

                ForEach(visibleHistoryRows, id: \.id) { student in
                    HStack(spacing: 0) {
                        Button {
                            historySelection = nil
                            selectedStudentId = student.id
                        } label: {
                            HStack {
                                Text(student.fullName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(width: 220, height: 48)
                        }
                        .buttonStyle(.plain)
                        .background(appCardBackground(for: colorScheme))

                        ForEach(monthDates, id: \.self) { date in
                            let record = historyRecord(for: student.id, date: date)
                            historyStatusCell(record: record, studentId: student.id, date: date)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(appPageBackground(for: colorScheme))
    }

    var attendanceToolbar: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedStudent {
                Button {
                    selectedStudentId = nil
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(selectedStudent.firstName) \(selectedStudent.lastName)")
                                .font(.headline)
                            Text(selectedInspectionAttendance?.status ?? "Sin registro")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Ocultar ficha")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(16)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                if boardMode == .courses {
                    WorkspaceCompactStat(title: "Cursos", value: "\(classOverviews.count)", tint: .blue)
                    WorkspaceCompactStat(title: "Alumnado", value: "\(classOverviews.map(\.studentCount).reduce(0, +))", tint: EvaluationDesign.success)
                    WorkspaceCompactStat(title: "Pendientes hoy", value: "\(classOverviews.map(\.pendingTodayCount).reduce(0, +))", tint: AppleDesignSystem.warning)
                    WorkspaceCompactStat(title: "Media", value: "\(averageOverviewRate)%", tint: .indigo)
                } else {
                    WorkspaceCompactStat(title: "Presentes", value: "\(boardSummary.present)", tint: EvaluationDesign.success)
                    WorkspaceCompactStat(title: "Ausencias", value: "\(boardSummary.absent)", tint: EvaluationDesign.danger)
                    WorkspaceCompactStat(title: "Retrasos", value: "\(boardSummary.late)", tint: AppleDesignSystem.warning)
                    WorkspaceCompactStat(title: "Pendientes", value: "\(boardSummary.untracked)", tint: .gray)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(appPageBackground(for: colorScheme))
    }

    @ViewBuilder
    var attendanceInspector: some View {
        if let student = selectedStudent {
            let studentIncidents = incidents.filter { $0.studentId?.int64Value == student.id }
            let recentStatuses = history.filter { $0.studentId == student.id }.sorted { $0.date > $1.date }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        WorkspaceInspectorHero(
                            title: "\(student.firstName) \(student.lastName)",
                            subtitle: "Histórico de asistencia e incidencias"
                        )
                        Spacer()
                        Button {
                            selectedStudentId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(appCardBackground(for: colorScheme), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    WorkspaceMetricCard(
                        title: "Último estado",
                        value: selectedInspectionAttendance?.status ?? recentStatuses.first?.status ?? "Sin registros",
                        systemImage: "clock.badge.checkmark"
                    )

                    if let latest = selectedInspectionAttendance ?? recentStatuses.first {
                        WorkspaceMetricCard(
                            title: "Seguimiento",
                            value: latest.followUpRequired ? "Requiere revisión" : "Sin seguimiento",
                            systemImage: latest.followUpRequired ? "arrow.triangle.branch" : "checkmark.circle"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Histórico reciente")
                            .font(.headline)
                        ForEach(Array(recentStatuses.prefix(6)), id: \.id) { attendance in
                            HStack {
                                Text(dateLabel(from: attendance.date))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(attendance.status)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }

                    if !sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sesiones del día")
                                .font(.headline)
                            ForEach(sessions) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(entry.session.teachingUnitName)
                                            .font(.subheadline.weight(.bold))
                                        Spacer()
                                        Text("P\(entry.session.period)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.session.status.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if let journalSummary = entry.journalSummary {
                                        Text("Diario: \(journalSummary.status.name.capitalized) · clima \(journalSummary.climateScore)/5")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Sin diario registrado todavía")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(16)
                                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Incidencias")
                            .font(.headline)
                        if studentIncidents.isEmpty {
                            Text("Sin incidencias asociadas")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(studentIncidents.prefix(4)), id: \.id) { incident in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(incident.title)
                                        .font(.subheadline.weight(.bold))
                                    Text(incident.detail ?? "Sin detalle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nota de asistencia")
                            .font(.headline)
                        TextField("Observación rápida de la sesión…", text: $noteDraft, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(3, reservesSpace: true)

                        Button("Guardar nota") {
                            Task { await saveAttendanceNote(for: student.id) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedInspectionAttendance == nil)
                    }

                    HStack(spacing: 16) {
                        Button("Abrir ficha de alumno") {
                            onOpenModule(.students, selectedClassId, student.id)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Abrir diario") {
                            onOpenModule(.diary, selectedClassId, student.id)
                        }
                        .buttonStyle(.bordered)

                        Button("Abrir cuaderno") {
                            onOpenModule(.notebook, selectedClassId, student.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let selectedClassId {
                        Button("Registrar incidencia desde asistencia") {
                            Task { await createAttendanceIncident(for: student.id, classId: selectedClassId, latestStatus: recentStatuses.first?.status) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(24)
            }
        } else {
            WorkspaceEmptyState(
                title: "Selecciona un alumno",
                subtitle: "El inspector muestra histórico, patrón reciente e incidencias de asistencia."
            )
        }
    }

    @MainActor
    func syncClassSelection() async {
        selectedStudentId = nil
        historySelection = nil
        localInjuryStatuses = [:]
        noteDraft = ""
        searchText = ""
        selectedStatusFilter = "TODOS"
        if selectedClassId == nil {
            recordsByStudentId = [:]
            history = []
            incidents = []
            sessions = []
        }
        await bridge.selectStudentsClass(classId: selectedClassId)
        guard !Task.isCancelled else { return }
        await reloadAttendance()
        guard !Task.isCancelled else { return }
        syncAttendanceToolbar()
    }

    @MainActor
    func reloadAttendance() async {
        guard let selectedClassId else { return }
        let records = (try? await bridge.attendanceRecords(for: selectedClassId, on: selectedDate)) ?? []
        guard !Task.isCancelled else { return }
        recordsByStudentId = Dictionary(
            uniqueKeysWithValues: normalizedAttendanceRecords(records).map { ($0.studentId, $0) }
        )
        let range = monthRange(for: selectedDate)
        history = (try? await bridge.attendanceHistory(for: selectedClassId, from: range.start, to: range.end)) ?? []
        guard !Task.isCancelled else { return }
        if let selection = historySelection {
            historySelection = AttendanceHistorySelection(
                studentId: selection.studentId,
                date: selection.date,
                record: historyRecord(for: selection.studentId, date: selection.date)
            )
        }
        incidents = (try? await bridge.incidents(for: selectedClassId)) ?? []
        sessions = (try? await bridge.attendanceSessions(for: selectedClassId, on: selectedDate)) ?? []
        guard !Task.isCancelled else { return }
        reconcileSelectedAttendanceSession()
        noteDraft = selectedInspectionAttendance?.note ?? ""
        syncAttendanceToolbar()
    }

    @MainActor
    func reloadClassOverviews() async {
        await bridge.ensureClassesLoaded()
        guard !Task.isCancelled else { return }
        let range = monthRange(for: selectedDate)
        let overviews = (try? await bridge.attendanceOverview(
            for: attendanceStore.classes.map(\.id),
            from: range.start,
            to: range.end
        )) ?? []
        guard !Task.isCancelled else { return }
        classOverviews = overviews
    }

    func normalizedAttendanceRecords(
        _ records: [KmpBridge.AttendanceRecordSnapshot]
    ) -> [KmpBridge.AttendanceRecordSnapshot] {
        Dictionary(grouping: records, by: \.studentId)
            .values
            .compactMap { duplicates in
                duplicates.max { lhs, rhs in
                    attendanceRecordPriority(lhs) < attendanceRecordPriority(rhs)
                }
            }
    }

    func attendanceRecordPriority(_ record: KmpBridge.AttendanceRecordSnapshot) -> (Int, Int64) {
        let sessionPriority = record.sessionId == nil ? 0 : 1
        return (sessionPriority, record.id)
    }

    func monthRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            let day = calendar.startOfDay(for: date)
            return (day, day)
        }
        let end = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        return (interval.start, end)
    }

    func reconcileSelectedAttendanceSession() {
        if let selectedAttendanceSessionId, sessions.contains(where: { $0.session.id == selectedAttendanceSessionId }) {
            return
        }
        selectedAttendanceSessionId = sessions.count == 1 ? sessions.first?.session.id : nil
    }

    func attendanceSessionId(for date: Date, existingRecord: KmpBridge.AttendanceRecordSnapshot?) -> Int64? {
        if let existingSessionId = existingRecord?.sessionId {
            return existingSessionId
        }
        guard Calendar.current.isDate(date, inSameDayAs: selectedDate) else {
            return nil
        }
        return selectedAttendanceSessionId
    }

    var toolbarStateKey: String {
        [
            searchText,
            selectedStatusFilter,
            boardMode.rawValue,
            String(Int(selectedDate.timeIntervalSince1970)),
            selectedStudentId.map(String.init) ?? "none",
            selectedAttendanceSessionId.map(String.init) ?? "none",
            String(sessions.count)
        ].joined(separator: "|")
    }

    func syncAttendanceToolbar() {
        if layoutState.attendanceToolbarAvailable {
            layoutState.updateAttendanceToolbar(
                searchText: searchText,
                selectedDate: selectedDate,
                boardMode: boardMode.rawValue,
                selectedStatusFilter: selectedStatusFilter,
                hasSelection: selectedStudentId != nil,
                sessions: sessions,
                selectedSessionId: selectedAttendanceSessionId
            )
        } else {
            layoutState.configureAttendanceToolbar(
                searchText: searchText,
                selectedDate: selectedDate,
                boardMode: boardMode.rawValue,
                selectedStatusFilter: selectedStatusFilter,
                hasSelection: selectedStudentId != nil,
                sessions: sessions,
                selectedSessionId: selectedAttendanceSessionId,
                onSearchTextChange: { searchText = $0 },
                onDateChange: { selectedDate = $0 },
                onBoardModeChange: { rawValue in
                    if let mode = AttendanceBoardMode(rawValue: rawValue) {
                        boardMode = mode
                    }
                },
                onStatusFilterChange: { selectedStatusFilter = $0 },
                onMarkAllPresent: {
                    Task { await markAllPresent() }
                },
                onRepeatPattern: {
                    Task { await repeatPattern() }
                },
                onClearSelection: {
                    selectedStudentId = nil
                    historySelection = nil
                },
                onSessionChange: { selectedAttendanceSessionId = $0 }
            )
        }
    }

    func updateAttendance(for student: Student, status: String) async {
        guard let selectedClassId else { return }
        let previousRecord = recordsByStudentId[student.id]
        let revision = (saveRevisionByStudentId[student.id] ?? 0) + 1
        saveRevisionByStudentId[student.id] = revision
        savingStudentIds.insert(student.id)
        applyLocalAttendanceStatus(status, for: student, classId: selectedClassId)

        do {
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: selectedClassId,
                on: selectedDate,
                status: status,
                sessionId: attendanceSessionId(for: selectedDate, existingRecord: previousRecord)
            )
            selectedStudentId = student.id
            if saveRevisionByStudentId[student.id] == revision {
                savingStudentIds.remove(student.id)
                bridge.status = "Asistencia actualizada."
                AppleInteractionFeedback.play(.success)
            }
        } catch {
            if saveRevisionByStudentId[student.id] == revision {
                recordsByStudentId[student.id] = previousRecord
                savingStudentIds.remove(student.id)
            }
            bridge.status = "No se pudo guardar la asistencia: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    @MainActor
    func markStudentInjured(_ student: Student) async {
        guard let selectedClassId else { return }
        guard !(localInjuryStatuses[student.id] ?? student.isInjured) else {
            selectedStudentId = student.id
            bridge.status = "La lesión de \(student.fullName) ya está activa."
            return
        }

        localInjuryStatuses[student.id] = true
        savingInjuryStudentIds.insert(student.id)
        selectedStudentId = student.id
        defer { savingInjuryStudentIds.remove(student.id) }

        do {
            try await bridge.updateStudentInjuryStatus(
                studentId: student.id,
                isInjured: true,
                classId: selectedClassId
            )
            bridge.status = "Lesión activa para \(student.fullName)."
            AppleInteractionFeedback.play(.success)
        } catch {
            localInjuryStatuses[student.id] = student.isInjured
            bridge.status = "No se pudo marcar la lesión: \(error.localizedDescription)"
            AppleInteractionFeedback.play(.error)
        }
    }

    func applyLocalAttendanceStatus(_ status: String, for student: Student, classId: Int64) {
        let baseRecord = recordsByStudentId[student.id]
        let updated = KmpBridge.AttendanceRecordSnapshot(
            id: baseRecord?.id ?? -student.id,
            studentId: student.id,
            classId: classId,
            date: selectedDate,
            status: status,
            note: baseRecord?.note ?? "",
            hasIncident: baseRecord?.hasIncident ?? false,
            followUpRequired: baseRecord?.followUpRequired ?? false,
            sessionId: attendanceSessionId(for: selectedDate, existingRecord: baseRecord)
        )
        recordsByStudentId[student.id] = updated
        upsertHistoryRecord(updated)
        if selectedStudentId == student.id {
            noteDraft = recordsByStudentId[student.id]?.note ?? ""
        }
    }

    func upsertHistoryRecord(_ record: KmpBridge.AttendanceRecordSnapshot) {
        if let index = history.firstIndex(where: { $0.studentId == record.studentId && Calendar.current.isDate($0.date, inSameDayAs: record.date) }) {
            history[index] = record
        } else {
            history.append(record)
        }
    }

    func markAllPresent() async {
        guard let selectedClassId else { return }
        let students = filteredRows.map(\.student)
        guard !students.isEmpty else { return }
        for student in students {
            applyLocalAttendanceStatus("PRESENTE", for: student, classId: selectedClassId)
            try? await bridge.saveAttendance(
                studentId: student.id,
                classId: selectedClassId,
                on: selectedDate,
                status: "PRESENTE",
                sessionId: recordsByStudentId[student.id]?.sessionId
            )
        }
        savingStudentIds.removeAll()
        await reloadAttendance()
        await reloadClassOverviews()
        bridge.status = "Todos los alumnos filtrados marcados como presentes."
    }

    func repeatPattern() async {
        guard let selectedClassId else { return }
        let applied = (try? await bridge.repeatLatestAttendancePattern(classId: selectedClassId, targetDate: selectedDate)) ?? 0
        bridge.status = applied > 0 ? "Patrón anterior aplicado a \(applied) registros" : "No había patrón anterior reutilizable"
        await reloadAttendance()
    }

    func weekStatus(for studentId: Int64, date: Date) -> AttendanceStatusOption {
        let dayEpoch = Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let record = history.first {
            $0.studentId == studentId &&
            Int64($0.date.stripTime.timeIntervalSince1970) == dayEpoch
        }
        return AttendanceStatusOption.all.first(where: { $0.id == record?.status }) ?? .init(id: "--", label: "Sin dato", shortLabel: "-", color: .clear)
    }

    func attendanceWeekStatusCell(_ status: AttendanceStatusOption) -> some View {
        let borderColor = Color.primary.opacity(0.08)
        return Text(status.shortLabel)
            .font(.caption.bold())
            .frame(width: 120, height: 54)
            .background(status.color.opacity(0.18))
            .overlay(Rectangle().stroke(borderColor, lineWidth: 0.5))
    }

    func historyStatusCell(record: KmpBridge.AttendanceRecordSnapshot?, studentId: Int64, date: Date) -> some View {
        let option = AttendanceStatusOption.all.first(where: { $0.id == record?.status })
        let isSelected = historySelection?.studentId == studentId && Calendar.current.isDate(historySelection?.date ?? .distantPast, inSameDayAs: date)
        return Button {
            selectedStudentId = studentId
            historySelection = AttendanceHistorySelection(studentId: studentId, date: date, record: record)
            noteDraft = record?.note ?? ""
        } label: {
            Text(option?.shortLabel ?? "·")
                .font(.caption.weight(.black))
                .foregroundStyle(option?.color ?? .secondary)
                .frame(width: 48, height: 48)
                .background((option?.color ?? Color.secondary).opacity(record == nil ? 0.04 : 0.16))
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: isSelected ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    func weekCellHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.bold())
            .frame(width: width, height: 44)
            .background(appMutedCardBackground(for: colorScheme))
    }

    func overviewMiniStat(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline.weight(.black))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func historyRecord(for studentId: Int64, date: Date) -> KmpBridge.AttendanceRecordSnapshot? {
        history.first {
            $0.studentId == studentId && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    func dateLabel(from date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func dayHeaderString(_ date: Date) -> String {
        date.formatted(.dateTime.day())
    }

    func createAttendanceIncident(for studentId: Int64, classId: Int64, latestStatus: String?) async {
        let statusText = latestStatus ?? "sin registro previo"
        let detail = "Incidencia creada desde asistencia el \(inspectorDate.formatted(date: .abbreviated, time: .omitted)). Estado observado: \(statusText)."
        do {
            _ = try await bridge.createIncident(
                classId: classId,
                studentId: studentId,
                title: "Seguimiento de asistencia",
                detail: detail,
                severity: "medium"
            )
            try await bridge.saveAttendance(
                studentId: studentId,
                classId: classId,
                on: inspectorDate,
                status: selectedInspectionAttendance?.status ?? "OBSERVACION",
                note: selectedInspectionAttendance?.note ?? noteDraft,
                hasIncident: true,
                followUpRequired: true
            )
            incidents = (try? await bridge.incidents(for: classId)) ?? incidents
            await reloadAttendance()
            bridge.status = "Incidencia registrada desde asistencia."
        } catch {
            bridge.status = "No se pudo crear la incidencia: \(error.localizedDescription)"
        }
    }

    func saveAttendanceNote(for studentId: Int64) async {
        guard let selectedClassId else { return }
        let current = selectedInspectionAttendance
        let currentStatus = current?.status ?? "PRESENTE"
        do {
            try await bridge.saveAttendance(
                studentId: studentId,
                classId: selectedClassId,
                on: inspectorDate,
                status: currentStatus,
                note: noteDraft,
                hasIncident: current?.hasIncident ?? false,
                followUpRequired: current?.followUpRequired
            )
            bridge.status = "Nota de asistencia guardada."
            await reloadAttendance()
        } catch {
            bridge.status = "No se pudo guardar la nota: \(error.localizedDescription)"
        }
    }
}
