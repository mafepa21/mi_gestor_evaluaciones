import SwiftUI
import AppKit
import MiGestorKit

/// Estado/acciones que `MacAttendanceView` publica hacia `MacRootView` para pintar
/// una toolbar nativa de macOS con los controles que antes vivían en el strip
/// bajo la cabecera (mismo patrón que Planner/Notebook/Dashboard).
struct MacAttendanceToolbarActions {
    var mode: Binding<AttendanceBoardMode>
    var selectedDate: Binding<Date>
    let classes: [SchoolClass]
    let selectedClassId: Int64?
    let selectClass: (Int64) -> Void
    let sessions: [KmpBridge.AttendanceSessionSnapshot]
    let selectedSessionId: Int64?
    let sessionLabel: (KmpBridge.AttendanceSessionSnapshot) -> String
    let selectSession: (Int64) -> Void
    var searchText: Binding<String>
    var selectedStatusFilter: Binding<String>
    let filterLabel: String
    let filterIcon: String
    let clearFilters: () -> Void
    let canCloseSelection: Bool
    let canMarkAllPresent: Bool
    let canRepeatPattern: Bool
    let markAllPresent: () -> Void
    let repeatPattern: () -> Void
    let refresh: () -> Void
    let clearSelection: () -> Void
}


struct MacAttendanceView: View {
    let bridge: KmpBridge
    @ObservedObject var attendanceStore: AttendanceBridgeStore
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onToolbarActionsChange: (MacAttendanceToolbarActions?) -> Void

    @State private var selectedDate = Date()
    @State private var mode: AttendanceBoardMode = .day
    @State private var searchText = ""
    @State private var selectedStatusFilter = "TODOS"
    @State private var recordsByStudentId: [Int64: KmpBridge.AttendanceRecordSnapshot] = [:]
    @State private var history: [KmpBridge.AttendanceRecordSnapshot] = []
    @State private var classOverviews: [KmpBridge.AttendanceClassOverview] = []
    @State private var incidents: [Incident] = []
    @State private var sessions: [KmpBridge.AttendanceSessionSnapshot] = []
    @State private var selectedAttendanceSessionId: Int64?
    @State private var savingStudentIds: Set<Int64> = []
    @State private var savingInjuryStudentIds: Set<Int64> = []
    @State private var localInjuryStatuses: [Int64: Bool] = [:]
    @State private var saveRevisionByStudentId: [Int64: Int] = [:]
    @State private var overviewRefreshTask: Task<Void, Never>?
    @State private var historySelection: AttendanceHistorySelection?
    @State private var isAttendanceInspectorVisible = false
    @State private var noteDraft = ""
    @State private var isLoading = false
    @State private var showAllPresent = false

    private var selectedClass: SchoolClass? {
        selectedClassId.flatMap { id in attendanceStore.classes.first(where: { $0.id == id }) }
    }

    private var selectedStudent: Student? {
        guard let selectedStudentId else { return nil }
        return attendanceStore.studentsInClass.first(where: { $0.id == selectedStudentId })
    }

    private var selectedAttendance: KmpBridge.AttendanceRecordSnapshot? {
        guard let selectedStudentId else { return nil }
        return recordsByStudentId[selectedStudentId]
    }

    private var selectedInspectionAttendance: KmpBridge.AttendanceRecordSnapshot? {
        historySelection?.record ?? selectedAttendance
    }

    private var inspectorDate: Date {
        historySelection?.date ?? selectedDate
    }

    private var filteredRows: [AttendanceEntryRow] {
        attendanceStore.studentsInClass
            .map { student in
                AttendanceEntryRow(
                    id: student.id,
                    student: student,
                    isInjured: isStudentInjured(student),
                    record: recordsByStudentId[student.id]
                )
            }
            .filter { row in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesSearch = query.isEmpty || row.student.fullName.localizedCaseInsensitiveContains(query)
                let matchesStatus = selectedStatusFilter == "TODOS" || row.record?.status == selectedStatusFilter
                return matchesSearch && matchesStatus
            }
    }

    private var exceptionRows: [AttendanceEntryRow] {
        filteredRows.filter(AttendanceLogic.isRowUnresolved)
            .sorted { AttendanceLogic.exceptionPriority($0) < AttendanceLogic.exceptionPriority($1) }
    }

    private var presentRows: [AttendanceEntryRow] {
        filteredRows.filter { !AttendanceLogic.isRowUnresolved($0) }
    }

    private var visibleHistoryStudents: [Student] {
        attendanceStore.studentsInClass.filter { student in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || student.fullName.localizedCaseInsensitiveContains(query)
            let matchesStatus = selectedStatusFilter == "TODOS" || history.contains {
                $0.studentId == student.id && $0.status == selectedStatusFilter
            }
            return matchesSearch && matchesStatus
        }
    }

    private var monthDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return [calendar.startOfDay(for: selectedDate)]
        }
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var boardSummary: (present: Int, absent: Int, late: Int, pending: Int) {
        let present = recordsByStudentId.values.filter { AttendanceLogic.isPresentStatus($0.status) }.count
        let absent = recordsByStudentId.values.filter { AttendanceLogic.isAbsentStatus($0.status) }.count
        let late = recordsByStudentId.values.filter { AttendanceLogic.isLateStatus($0.status) }.count
        let pending = max(attendanceStore.studentsInClass.count - recordsByStudentId.count, 0)
        return (present, absent, late, pending)
    }

    private func isStudentInjured(_ student: Student) -> Bool {
        localInjuryStatuses[student.id] ?? student.isInjured
    }

    private var averageOverviewRate: Int {
        guard !classOverviews.isEmpty else { return 0 }
        return classOverviews.map(\.attendanceRate).reduce(0, +) / classOverviews.count
    }

    private var criticalAlerts: [AttendanceAlert] {
        guard mode == .day else { return [] }
        let today = Calendar.current.startOfDay(for: selectedDate)
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -6, to: today) else { return [] }
        var alerts: [AttendanceAlert] = []
        for student in attendanceStore.studentsInClass {
            let recentAbsences = history.filter {
                $0.studentId == student.id
                    && Calendar.current.startOfDay(for: $0.date) >= windowStart
                    && Calendar.current.startOfDay(for: $0.date) <= today
                    && AttendanceLogic.isAbsentStatus($0.status)
            }.count
            if recentAbsences >= 3 {
                alerts.append(AttendanceAlert(
                    id: "\(student.id)-absences",
                    student: student,
                    message: "\(recentAbsences) ausencias en 7 días",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: MacAppStyle.dangerTint
                ))
            }
            if isStudentInjured(student) {
                alerts.append(AttendanceAlert(
                    id: "\(student.id)-injury",
                    student: student,
                    message: "Lesión activa",
                    systemImage: "cross.case.fill",
                    tint: MacAppStyle.warningTint
                ))
            }
        }
        return alerts
    }

    private var toolbarStateKey: String {
        // La anotación explícita de tipo es necesaria: sin ella el type-checker de
        // Swift agota el tiempo al inferir este literal heterogéneo.
        let components: [String] = [
            selectedClassId.map(String.init) ?? "all",
            selectedStudentId.map(String.init) ?? "none",
            selectedStatusFilter,
            searchText,
            mode.rawValue,
            String(Int(selectedDate.timeIntervalSince1970)),
            selectedAttendanceSessionId.map(String.init) ?? "none",
            String(sessions.count)
        ]
        return components.joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            header
            metricsStrip
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MacAppStyle.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppStyle.pageBackground)
        // Native .inspector() (rather than a manual HSplitView pane) lets the enclosing
        // NavigationSplitView negotiate space correctly. Starts closed (no student
        // selected yet) and opens itself when a student is picked, below.
        .inspector(isPresented: $isAttendanceInspectorVisible) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 360, max: 430)
        }
        .background(
            Button("") { Task { await markAllPresent() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .hidden()
        )
        .task {
            await bootstrap()
        }
        .task(id: selectedClassId) {
            await syncClassSelection()
        }
        .task(id: selectedDate) {
            await reloadClassOverviews()
            await reloadAttendance()
        }
        .appOnChange(of: selectedStudentId) { _, newValue in
            noteDraft = selectedInspectionAttendance?.note ?? ""
            if newValue != nil {
                isAttendanceInspectorVisible = true
            }
            publishToolbarActions()
        }
        .appOnChange(of: mode) { _, newValue in
            if newValue == .courses {
                selectedStudentId = nil
                historySelection = nil
            }
            publishToolbarActions()
        }
        .appOnChange(of: toolbarStateKey) { _, _ in
            publishToolbarActions()
        }
        .onDisappear {
            overviewRefreshTask?.cancel()
            onToolbarActionsChange(nil)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
            MacPremiumModuleHeader(
                title: "Asistencia",
                subtitle: selectedClass?.name ?? "Todos los cursos",
                state: attendanceOperationState
            )

            if !criticalAlerts.isEmpty {
                criticalAlertsRow
            }
        }
    }

    private var criticalAlertsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(criticalAlerts) { alert in
                    Button {
                        historySelection = nil
                        selectedStudentId = alert.student.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: alert.systemImage)
                            Text(alert.student.fullName)
                                .fontWeight(.semibold)
                            Text(alert.message)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(alert.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(alert.tint.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var attendanceOperationState: MacPremiumOperationStateKind? {
        if !savingStudentIds.isEmpty || !savingInjuryStudentIds.isEmpty {
            return .saving("Guardando...")
        }
        if isLoading {
            return .loading("Actualizando...")
        }
        return nil
    }

    private func selectClass(_ classId: Int64) {
        selectedClassId = classId
        if mode == .courses {
            mode = .day
        }
    }

    private func selectSession(_ sessionId: Int64) {
        selectedAttendanceSessionId = sessionId
    }

    private func clearAttendanceFilters() {
        searchText = ""
        selectedStatusFilter = "TODOS"
    }

    private var attendanceFilterLabel: String {
        var active = 0
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            active += 1
        }
        if selectedStatusFilter != "TODOS" {
            active += 1
        }
        return active == 0 ? "Filtrar" : "Filtros \(active)"
    }

    private var attendanceFilterIcon: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedStatusFilter == "TODOS"
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    @ViewBuilder
    private var metricsStrip: some View {
        if mode == .courses {
            HStack(spacing: MacAppStyle.cardSpacing) {
                MacMetricCard(label: "Cursos", value: "\(classOverviews.count)", tint: .blue, systemImage: "rectangle.3.group")
                MacMetricCard(label: "Alumnado", value: "\(classOverviews.map(\.studentCount).reduce(0, +))", tint: .green, systemImage: "person.3")
                MacMetricCard(label: "Pendientes hoy", value: "\(classOverviews.map(\.pendingTodayCount).reduce(0, +))", tint: .orange, systemImage: "clock")
                MacMetricCard(label: "Media periodo", value: "\(averageOverviewRate)%", tint: .indigo, systemImage: "chart.line.uptrend.xyaxis")
            }
        } else {
            HStack(spacing: MacAppStyle.cardSpacing) {
                MacMetricCard(label: "Presentes", value: "\(boardSummary.present)", tint: MacAppStyle.successTint, systemImage: "checkmark.circle")
                MacMetricCard(label: "Ausencias", value: "\(boardSummary.absent)", tint: MacAppStyle.dangerTint, systemImage: "xmark.circle")
                MacMetricCard(label: "Retrasos", value: "\(boardSummary.late)", tint: MacAppStyle.warningTint, systemImage: "clock.badge.exclamationmark")
                MacMetricCard(label: "Pendientes", value: "\(boardSummary.pending)", tint: .gray, systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch mode {
        case .courses:
            coursesContent
        case .day:
            dayContent
        case .history:
            historyContent
        }
    }

    private var coursesContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(classOverviews) { overview in
                    Button {
                        selectedClassId = overview.id
                        mode = .day
                    } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(overview.schoolClass.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(overview.studentCount) alumnos")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(overview.attendanceRate)%")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundStyle(MacAppStyle.successTint)
                            }

                            HStack(spacing: 8) {
                                overviewChip("P", overview.presentCount, MacAppStyle.successTint)
                                overviewChip("A", overview.absentCount, MacAppStyle.dangerTint)
                                overviewChip("R", overview.lateCount, MacAppStyle.warningTint)
                                overviewChip("Pend.", overview.pendingTodayCount, .gray)
                            }
                        }
                        .padding(MacAppStyle.innerPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MacAppStyle.cardBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(MacHoverableButtonStyle(cornerRadius: MacAppStyle.cardRadius))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var dayContent: some View {
        Group {
            if filteredRows.isEmpty {
                ContentUnavailableView(
                    "Sin alumnos visibles",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Ajusta el curso, la búsqueda o el filtro de estado.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
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
                    .padding(.vertical, 8)
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress { press in
                    switch press.key {
                    case .upArrow:
                        moveRosterSelection(by: -1)
                        return .handled
                    case .downArrow:
                        moveRosterSelection(by: 1)
                        return .handled
                    default:
                        guard let char = press.characters.first,
                              let status = Self.statusShortcut(for: char) else { return .ignored }
                        applyStatusShortcut(status)
                        return .handled
                    }
                }
            }
        }
    }

    private func dayRow(for row: AttendanceEntryRow) -> some View {
        MacAttendanceDayRow(
            row: row,
            isSelected: selectedStudentId == row.student.id,
            isSaving: savingStudentIds.contains(row.student.id) || savingInjuryStudentIds.contains(row.student.id),
            onSelect: {
                historySelection = nil
                selectedStudentId = row.student.id
            },
            onPickStatus: { status in
                Task { await updateAttendance(for: row.student, status: status.id) }
            },
            onMarkInjury: {
                Task { await markInjuryStatus(for: row.student) }
            }
        )
        .contextMenu {
            Button {
                Task { await toggleInjuryStatus(for: row.student) }
            } label: {
                Label(
                    row.isInjured ? "Quitar lesión" : "Marcar lesión",
                    systemImage: row.isInjured ? "heart.slash" : "bandage"
                )
            }
        }
    }

    private var allPresentBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(MacAppStyle.successTint)
            Text("Todos presentes")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var presentSummaryDisclosure: some View {
        DisclosureGroup(isExpanded: $showAllPresent) {
            LazyVStack(spacing: 8) {
                ForEach(presentRows) { row in
                    dayRow(for: row)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(MacAppStyle.successTint)
                Text("\(presentRows.count) presentes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 4)
        .animation(.snappy(duration: 0.22), value: showAllPresent)
    }

    private var historyContent: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    historyHeaderCell("Alumno", width: 220)
                    ForEach(monthDates, id: \.self) { date in
                        historyHeaderCell(Self.dayHeaderString(date), width: 44)
                    }
                }

                ForEach(visibleHistoryStudents, id: \.id) { student in
                    HStack(spacing: 0) {
                        Button {
                            historySelection = nil
                            selectedStudentId = student.id
                        } label: {
                            Text(student.fullName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .frame(width: 220, height: 42, alignment: .leading)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(MacHoverableButtonStyle(cornerRadius: 0))
                        .background(MacAppStyle.cardBackground)
                        .overlay(Rectangle().stroke(MacAppStyle.cardBorder, lineWidth: 0.5))

                        ForEach(monthDates, id: \.self) { date in
                            historyCell(record: historyRecord(for: student.id, date: date), studentId: student.id, date: date)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let student = selectedStudent {
            let recentRecords = history
                .filter { $0.studentId == student.id }
                .sorted { $0.date > $1.date }
            let studentIncidents = incidents.filter { $0.studentId?.int64Value == student.id }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MacPremiumInspectorHeader(
                        title: student.fullName,
                        subtitle: inspectorDate.formatted(date: .abbreviated, time: .omitted),
                        onClose: {
                            selectedStudentId = nil
                            historySelection = nil
                        }
                    ) {
                        inspectorStatusContent(record: selectedInspectionAttendance ?? recentRecords.first)
                    }

                    inspectorSection("Condición física") {
                        MacStatusPill(
                            label: isStudentInjured(student) ? "Lesión activa" : "Sin lesión",
                            isActive: isStudentInjured(student),
                            tint: isStudentInjured(student) ? MacAppStyle.warningTint : MacAppStyle.successTint
                        )
                        Button {
                            Task { await toggleInjuryStatus(for: student) }
                        } label: {
                            Label(
                                isStudentInjured(student) ? "Quitar lesión" : "Marcar lesión",
                                systemImage: isStudentInjured(student) ? "heart.slash" : "bandage"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(savingInjuryStudentIds.contains(student.id))
                    }

                    inspectorSection("Histórico reciente") {
                        if recentRecords.isEmpty {
                            Text("Sin registros en el mes.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(recentRecords.prefix(8)), id: \.id) { record in
                                HStack {
                                    Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    MacStatusPill(
                                        label: statusLabel(record.status),
                                        isActive: true,
                                        tint: AttendanceStatusOption.option(for: record.status)?.color ?? .secondary
                                    )
                                }
                            }
                        }
                    }

                    inspectorSection("Nota") {
                        TextEditor(text: $noteDraft)
                            .font(.callout)
                            .frame(minHeight: 70)
                            .padding(6)
                            .background(MacAppStyle.subtleFill)
                            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous)
                                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
                            }

                        Button {
                            Task { await saveAttendanceNote(for: student.id) }
                        } label: {
                            Label("Guardar nota", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    inspectorSection("Sesiones vinculadas") {
                        if sessions.isEmpty {
                            Text("No hay sesiones planificadas para este día.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sessions) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.session.teachingUnitName)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Text("Periodo \(entry.session.period)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(MacAppStyle.subtleFill)
                                .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
                            }
                        }
                    }

                    inspectorSection("Incidencias") {
                        if studentIncidents.isEmpty {
                            Text("Sin incidencias asociadas.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(studentIncidents.prefix(4)), id: \.id) { incident in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(incident.title)
                                        .font(.callout.weight(.semibold))
                                    Text(incident.detail ?? "Sin detalle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }

                    inspectorSection("Accesos") {
                        MacPremiumInspectorActionGroup {
                            Button {
                                onOpenModule(.students, selectedClassId, student.id)
                            } label: {
                                Label("Abrir ficha", systemImage: "person.text.rectangle")
                            }
                            Button {
                                onOpenModule(.diary, selectedClassId, student.id)
                            } label: {
                                Label("Abrir diario", systemImage: "book.closed")
                            }
                            Button {
                                onOpenModule(.notebook, selectedClassId, student.id)
                            } label: {
                                Label("Abrir cuaderno", systemImage: "tablecells")
                            }
                            if let selectedClassId {
                                Button {
                                    Task { await createAttendanceIncident(for: student.id, classId: selectedClassId) }
                                } label: {
                                    Label("Registrar incidencia", systemImage: "exclamationmark.bubble")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(MacAppStyle.pagePadding)
            }
            .background(MacAppStyle.cardBackground)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                Text("Selecciona un alumno")
                    .font(.headline)
                Text("Aquí aparecerán notas, histórico, sesiones e incidencias.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(MacAppStyle.pagePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacAppStyle.cardBackground)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        MacPremiumInspectorSection(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func inspectorStatusContent(record: KmpBridge.AttendanceRecordSnapshot?) -> some View {
        HStack(spacing: 8) {
            MacStatusPill(
                label: record.map { statusLabel($0.status) } ?? "Sin registro",
                isActive: record != nil,
                tint: AttendanceStatusOption.option(for: record?.status)?.color ?? .secondary
            )
            if record?.followUpRequired == true {
                MacStatusPill(label: "Seguimiento", isActive: true, tint: MacAppStyle.warningTint)
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        isLoading = true
        await bridge.ensureClassesLoaded()
        if selectedClassId == nil {
            selectedClassId = attendanceStore.selectedStudentsClassId ?? attendanceStore.classes.first?.id
        }
        await reloadClassOverviews()
        await syncClassSelection()
        isLoading = false
        publishToolbarActions()
    }

    @MainActor
    private func syncClassSelection() async {
        guard selectedClassId != nil else {
            recordsByStudentId = [:]
            history = []
            return
        }
        await bridge.selectStudentsClass(classId: selectedClassId)
        await reloadAttendance()
    }

    @MainActor
    private func reloadAttendance() async {
        guard let selectedClassId else { return }
        isLoading = true
        let records = (try? await bridge.attendanceRecords(for: selectedClassId, on: selectedDate)) ?? []
        recordsByStudentId = Dictionary(
            uniqueKeysWithValues: normalizedAttendanceRecords(records).map { ($0.studentId, $0) }
        )
        let range = monthRange(for: selectedDate)
        history = (try? await bridge.attendanceHistory(for: selectedClassId, from: range.start, to: range.end)) ?? []
        if let selection = historySelection {
            historySelection = AttendanceHistorySelection(
                studentId: selection.studentId,
                date: selection.date,
                record: historyRecord(for: selection.studentId, date: selection.date)
            )
        }
        incidents = (try? await bridge.incidents(for: selectedClassId)) ?? []
        sessions = (try? await bridge.attendanceSessions(for: selectedClassId, on: selectedDate)) ?? []
        reconcileSelectedAttendanceSession()
        noteDraft = selectedInspectionAttendance?.note ?? ""
        isLoading = false
        publishToolbarActions()
    }

    @MainActor
    private func reloadClassOverviews() async {
        await bridge.ensureClassesLoaded()
        let range = monthRange(for: selectedDate)
        classOverviews = (try? await bridge.attendanceOverview(
            for: attendanceStore.classes.map(\.id),
            from: range.start,
            to: range.end
        )) ?? []
    }

    @MainActor
    private func updateAttendance(for student: Student, status: String) async {
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
                note: previousRecord?.note ?? "",
                hasIncident: previousRecord?.hasIncident ?? false,
                followUpRequired: previousRecord?.followUpRequired,
                sessionId: attendanceSessionId(for: selectedDate, existingRecord: previousRecord)
            )
            selectedStudentId = student.id
            if saveRevisionByStudentId[student.id] == revision {
                savingStudentIds.remove(student.id)
                bridge.status = "Asistencia actualizada."
            }
            scheduleClassOverviewRefresh()
        } catch {
            if saveRevisionByStudentId[student.id] == revision {
                recordsByStudentId[student.id] = previousRecord
                savingStudentIds.remove(student.id)
            }
            bridge.status = "No se pudo guardar la asistencia: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func toggleInjuryStatus(for student: Student) async {
        guard let selectedClassId else { return }
        let previousValue = isStudentInjured(student)
        let newValue = !previousValue
        localInjuryStatuses[student.id] = newValue
        selectedStudentId = student.id
        savingInjuryStudentIds.insert(student.id)
        defer { savingInjuryStudentIds.remove(student.id) }

        do {
            try await bridge.updateStudentInjuryStatus(
                studentId: student.id,
                isInjured: newValue,
                classId: selectedClassId
            )
            bridge.status = newValue ? "Alumno marcado con lesión." : "Lesión retirada."
        } catch {
            localInjuryStatuses[student.id] = previousValue
            bridge.status = "No se pudo actualizar la lesión: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func markInjuryStatus(for student: Student) async {
        guard !isStudentInjured(student) else {
            selectedStudentId = student.id
            bridge.status = "La lesión de \(student.fullName) ya está activa."
            return
        }
        await toggleInjuryStatus(for: student)
    }

    @MainActor
    private func markAllPresent() async {
        guard let selectedClassId else { return }
        let students = filteredRows.map(\.student)
        guard !students.isEmpty else { return }
        let previousRecords = recordsByStudentId
        savingStudentIds.formUnion(students.map(\.id))
        let drafts = students.map { student in
            let previousRecord = previousRecords[student.id]
            applyLocalAttendanceStatus("PRESENTE", for: student, classId: selectedClassId)
            return KmpBridge.AttendanceDraft(
                studentId: student.id,
                classId: selectedClassId,
                date: selectedDate,
                status: "PRESENTE",
                note: previousRecord?.note ?? "",
                hasIncident: previousRecord?.hasIncident ?? false,
                followUpRequired: previousRecord?.followUpRequired,
                sessionId: attendanceSessionId(for: selectedDate, existingRecord: previousRecord)
            )
        }

        do {
            try await bridge.saveAttendanceBatch(records: drafts)
            savingStudentIds.subtract(students.map(\.id))
            scheduleClassOverviewRefresh()
            bridge.status = "Todos los alumnos filtrados marcados como presentes."
        } catch {
            recordsByStudentId = previousRecords
            savingStudentIds.subtract(students.map(\.id))
            bridge.status = "No se pudo marcar el grupo: \(error.localizedDescription)"
        }
    }

    private static func statusShortcut(for char: Character) -> String? {
        let mapping: [Character: String] = [
            "p": "PRESENTE",
            "a": "AUSENTE",
            "r": "TARDE",
            "j": "JUSTIFICADO",
            "m": "SIN_MATERIAL",
            "e": "EXENTO"
        ]
        return mapping[Character(char.lowercased())]
    }

    private func moveRosterSelection(by delta: Int) {
        guard !filteredRows.isEmpty else { return }
        historySelection = nil
        guard let currentId = selectedStudentId,
              let index = filteredRows.firstIndex(where: { $0.student.id == currentId }) else {
            selectedStudentId = filteredRows.first?.student.id
            expandPresentSummaryIfNeeded(for: filteredRows.first?.student.id)
            return
        }
        let newIndex = min(max(index + delta, 0), filteredRows.count - 1)
        let newStudentId = filteredRows[newIndex].student.id
        selectedStudentId = newStudentId
        expandPresentSummaryIfNeeded(for: newStudentId)
    }

    private func expandPresentSummaryIfNeeded(for studentId: Int64?) {
        guard let studentId, presentRows.contains(where: { $0.student.id == studentId }) else { return }
        showAllPresent = true
    }

    private func applyStatusShortcut(_ status: String) {
        guard let studentId = selectedStudentId ?? filteredRows.first?.student.id,
              let student = filteredRows.first(where: { $0.student.id == studentId })?.student else { return }
        historySelection = nil
        selectedStudentId = studentId
        Task { await updateAttendance(for: student, status: status) }
        moveRosterSelection(by: 1)
    }

    @MainActor
    private func repeatPattern() async {
        guard let selectedClassId else { return }
        let applied = (try? await bridge.repeatLatestAttendancePattern(classId: selectedClassId, targetDate: selectedDate)) ?? 0
        bridge.status = applied > 0 ? "Patrón anterior aplicado a \(applied) registros." : "No había patrón anterior reutilizable."
        await reloadAttendance()
        await reloadClassOverviews()
    }

    @MainActor
    private func saveAttendanceNote(for studentId: Int64) async {
        guard let selectedClassId else { return }
        let current = selectedInspectionAttendance
        do {
            try await bridge.saveAttendance(
                studentId: studentId,
                classId: selectedClassId,
                on: inspectorDate,
                status: current?.status ?? "PRESENTE",
                note: noteDraft,
                hasIncident: current?.hasIncident ?? false,
                followUpRequired: current?.followUpRequired,
                sessionId: attendanceSessionId(for: inspectorDate, existingRecord: current)
            )
            bridge.status = "Nota de asistencia guardada."
            applyLocalAttendanceNote(studentId: studentId, classId: selectedClassId, record: current)
        } catch {
            bridge.status = "No se pudo guardar la nota: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func createAttendanceIncident(for studentId: Int64, classId: Int64) async {
        let statusText = selectedInspectionAttendance?.status ?? "sin registro previo"
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
                followUpRequired: true,
                sessionId: attendanceSessionId(for: inspectorDate, existingRecord: selectedInspectionAttendance)
            )
            bridge.status = "Incidencia registrada desde asistencia."
            applyLocalAttendanceIncident(studentId: studentId, classId: classId, record: selectedInspectionAttendance)
            scheduleClassOverviewRefresh()
        } catch {
            bridge.status = "No se pudo crear la incidencia: \(error.localizedDescription)"
        }
    }

    private func applyLocalAttendanceStatus(_ status: String, for student: Student, classId: Int64) {
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
            noteDraft = updated.note
        }
    }

    private func upsertHistoryRecord(_ record: KmpBridge.AttendanceRecordSnapshot) {
        if let index = history.firstIndex(where: { $0.studentId == record.studentId && Calendar.current.isDate($0.date, inSameDayAs: record.date) }) {
            history[index] = record
        } else {
            history.append(record)
        }
    }

    private func applyLocalAttendanceNote(
        studentId: Int64,
        classId: Int64,
        record: KmpBridge.AttendanceRecordSnapshot?
    ) {
        let updated = KmpBridge.AttendanceRecordSnapshot(
            id: record?.id ?? -studentId,
            studentId: studentId,
            classId: classId,
            date: inspectorDate,
            status: record?.status ?? "PRESENTE",
            note: noteDraft,
            hasIncident: record?.hasIncident ?? false,
            followUpRequired: record?.followUpRequired ?? false,
            sessionId: attendanceSessionId(for: inspectorDate, existingRecord: record)
        )
        if Calendar.current.isDate(inspectorDate, inSameDayAs: selectedDate) {
            recordsByStudentId[studentId] = updated
        }
        upsertHistoryRecord(updated)
        if let selection = historySelection, selection.studentId == studentId {
            historySelection = AttendanceHistorySelection(
                studentId: selection.studentId,
                date: selection.date,
                record: updated
            )
        }
    }

    private func applyLocalAttendanceIncident(
        studentId: Int64,
        classId: Int64,
        record: KmpBridge.AttendanceRecordSnapshot?
    ) {
        let updated = KmpBridge.AttendanceRecordSnapshot(
            id: record?.id ?? -studentId,
            studentId: studentId,
            classId: classId,
            date: inspectorDate,
            status: record?.status ?? "OBSERVACION",
            note: record?.note ?? noteDraft,
            hasIncident: true,
            followUpRequired: true,
            sessionId: attendanceSessionId(for: inspectorDate, existingRecord: record)
        )
        if Calendar.current.isDate(inspectorDate, inSameDayAs: selectedDate) {
            recordsByStudentId[studentId] = updated
        }
        upsertHistoryRecord(updated)
        if let selection = historySelection, selection.studentId == studentId {
            historySelection = AttendanceHistorySelection(
                studentId: selection.studentId,
                date: selection.date,
                record: updated
            )
        }
    }

    private func scheduleClassOverviewRefresh() {
        overviewRefreshTask?.cancel()
        overviewRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await reloadClassOverviews()
        }
    }

    private func normalizedAttendanceRecords(_ records: [KmpBridge.AttendanceRecordSnapshot]) -> [KmpBridge.AttendanceRecordSnapshot] {
        Dictionary(grouping: records, by: \.studentId)
            .values
            .compactMap { duplicates in
                duplicates.max { lhs, rhs in
                    attendanceRecordPriority(lhs) < attendanceRecordPriority(rhs)
                }
            }
    }

    private func attendanceRecordPriority(_ record: KmpBridge.AttendanceRecordSnapshot) -> (Int, Int64) {
        (record.sessionId == nil ? 0 : 1, record.id)
    }

    private func reconcileSelectedAttendanceSession() {
        if let selectedAttendanceSessionId, sessions.contains(where: { $0.session.id == selectedAttendanceSessionId }) {
            return
        }
        selectedAttendanceSessionId = sessions.count == 1 ? sessions.first?.session.id : nil
    }

    private func attendanceSessionId(for date: Date, existingRecord: KmpBridge.AttendanceRecordSnapshot?) -> Int64? {
        if let existingSessionId = existingRecord?.sessionId {
            return existingSessionId
        }
        guard Calendar.current.isDate(date, inSameDayAs: selectedDate) else {
            return nil
        }
        return selectedAttendanceSessionId
    }


    private func historyRecord(for studentId: Int64, date: Date) -> KmpBridge.AttendanceRecordSnapshot? {
        history.first {
            $0.studentId == studentId && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    private func monthRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            let day = calendar.startOfDay(for: date)
            return (day, day)
        }
        let end = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        return (interval.start, end)
    }

    private func publishToolbarActions() {
        onToolbarActionsChange(
            MacAttendanceToolbarActions(
                mode: $mode,
                selectedDate: $selectedDate,
                classes: attendanceStore.classes,
                selectedClassId: selectedClassId,
                selectClass: { classId in selectClass(classId) },
                sessions: sessions,
                selectedSessionId: selectedAttendanceSessionId,
                sessionLabel: { entry in AttendanceLogic.sessionLabel(for: entry) },
                selectSession: { sessionId in selectSession(sessionId) },
                searchText: $searchText,
                selectedStatusFilter: $selectedStatusFilter,
                filterLabel: attendanceFilterLabel,
                filterIcon: attendanceFilterIcon,
                clearFilters: { clearAttendanceFilters() },
                canCloseSelection: selectedStudentId != nil || historySelection != nil,
                canMarkAllPresent: mode == .day && selectedClassId != nil && !filteredRows.isEmpty,
                canRepeatPattern: mode == .day && selectedClassId != nil,
                markAllPresent: { Task { await markAllPresent() } },
                repeatPattern: { Task { await repeatPattern() } },
                refresh: {
                    Task {
                        await reloadClassOverviews()
                        await reloadAttendance()
                    }
                },
                clearSelection: {
                    selectedStudentId = nil
                    historySelection = nil
                }
            )
        )
    }

    private func historyCell(record: KmpBridge.AttendanceRecordSnapshot?, studentId: Int64, date: Date) -> some View {
        let option = AttendanceStatusOption.option(for: record?.status)
        let isSelected = historySelection?.studentId == studentId && Calendar.current.isDate(historySelection?.date ?? .distantPast, inSameDayAs: date)
        return Button {
            selectedStudentId = studentId
            historySelection = AttendanceHistorySelection(studentId: studentId, date: date, record: record)
            noteDraft = record?.note ?? ""
        } label: {
            Text(option?.shortLabel ?? "·")
                .font(.caption.weight(.bold))
                .foregroundStyle(option?.color ?? .secondary)
                .frame(width: 44, height: 42)
                .background((option?.color ?? Color.secondary).opacity(record == nil ? 0.04 : 0.16))
                .overlay {
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor : MacAppStyle.cardBorder, lineWidth: isSelected ? 1.4 : 0.5)
                }
        }
        .buttonStyle(.plain)
    }

    private func historyHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, height: 36)
            .background(MacAppStyle.subtleFill)
            .overlay(Rectangle().stroke(MacAppStyle.cardBorder, lineWidth: 0.5))
    }

    private func overviewChip(_ label: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
                .foregroundStyle(tint)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
    }

    private func statusLabel(_ status: String) -> String {
        AttendanceStatusOption.option(for: status)?.label ?? status
    }

    private static func dayHeaderString(_ date: Date) -> String {
        date.formatted(.dateTime.day())
    }

}
