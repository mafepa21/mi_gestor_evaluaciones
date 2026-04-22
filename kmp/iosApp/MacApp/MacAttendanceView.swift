import SwiftUI
import AppKit
import MiGestorKit

struct MacAttendanceToolbarActions {
    let canCloseSelection: Bool
    let markAllPresent: () -> Void
    let repeatPattern: () -> Void
    let refresh: () -> Void
    let clearSelection: () -> Void
}

private enum MacAttendanceMode: String, CaseIterable, Identifiable {
    case day = "Día"
    case history = "Historial"
    case courses = "Cursos"

    var id: String { rawValue }
}

private struct MacAttendanceStatusOption: Identifiable, Hashable {
    let id: String
    let label: String
    let shortLabel: String
    let color: Color

    static let all: [MacAttendanceStatusOption] = [
        .init(id: "PRESENTE", label: "Presente", shortLabel: "P", color: MacAppStyle.successTint),
        .init(id: "AUSENTE", label: "Ausente", shortLabel: "A", color: MacAppStyle.dangerTint),
        .init(id: "TARDE", label: "Retraso", shortLabel: "R", color: MacAppStyle.warningTint),
        .init(id: "JUSTIFICADO", label: "Justificada", shortLabel: "J", color: .gray),
        .init(id: "SIN_MATERIAL", label: "Sin material", shortLabel: "M", color: .brown),
        .init(id: "EXENTO", label: "Exento", shortLabel: "E", color: .indigo)
    ]

    static func option(for status: String?) -> MacAttendanceStatusOption? {
        all.first { $0.id == status }
    }
}

private struct MacAttendanceEntryRow: Identifiable {
    let id: Int64
    let student: Student
    let record: KmpBridge.AttendanceRecordSnapshot?
}

private struct MacAttendanceHistorySelection: Identifiable {
    let studentId: Int64
    let date: Date
    let record: KmpBridge.AttendanceRecordSnapshot?

    var id: String {
        "\(studentId)-\(Int(date.timeIntervalSince1970))"
    }
}

struct MacAttendanceView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onToolbarActionsChange: (MacAttendanceToolbarActions?) -> Void

    @State private var selectedDate = Date()
    @State private var mode: MacAttendanceMode = .day
    @State private var searchText = ""
    @State private var selectedStatusFilter = "TODOS"
    @State private var recordsByStudentId: [Int64: KmpBridge.AttendanceRecordSnapshot] = [:]
    @State private var history: [KmpBridge.AttendanceRecordSnapshot] = []
    @State private var classOverviews: [KmpBridge.AttendanceClassOverview] = []
    @State private var incidents: [Incident] = []
    @State private var sessions: [KmpBridge.AttendanceSessionSnapshot] = []
    @State private var savingStudentIds: Set<Int64> = []
    @State private var saveRevisionByStudentId: [Int64: Int] = [:]
    @State private var historySelection: MacAttendanceHistorySelection?
    @State private var noteDraft = ""
    @State private var isLoading = false

    private var selectedClass: SchoolClass? {
        selectedClassId.flatMap { id in bridge.classes.first(where: { $0.id == id }) }
    }

    private var selectedStudent: Student? {
        guard let selectedStudentId else { return nil }
        return bridge.studentsInClass.first(where: { $0.id == selectedStudentId })
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

    private var filteredRows: [MacAttendanceEntryRow] {
        bridge.studentsInClass
            .map { student in
                MacAttendanceEntryRow(id: student.id, student: student, record: recordsByStudentId[student.id])
            }
            .filter { row in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesSearch = query.isEmpty || row.student.fullName.localizedCaseInsensitiveContains(query)
                let matchesStatus = selectedStatusFilter == "TODOS" || row.record?.status == selectedStatusFilter
                return matchesSearch && matchesStatus
            }
    }

    private var visibleHistoryStudents: [Student] {
        bridge.studentsInClass.filter { student in
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
        let present = recordsByStudentId.values.filter { Self.isPresentStatus($0.status) }.count
        let absent = recordsByStudentId.values.filter { Self.isAbsentStatus($0.status) }.count
        let late = recordsByStudentId.values.filter { Self.isLateStatus($0.status) }.count
        let pending = max(bridge.studentsInClass.count - recordsByStudentId.count, 0)
        return (present, absent, late, pending)
    }

    private var averageOverviewRate: Int {
        guard !classOverviews.isEmpty else { return 0 }
        return classOverviews.map(\.attendanceRate).reduce(0, +) / classOverviews.count
    }

    private var toolbarStateKey: String {
        [
            selectedClassId.map(String.init) ?? "all",
            selectedStudentId.map(String.init) ?? "none",
            selectedStatusFilter,
            searchText,
            mode.rawValue,
            String(Int(selectedDate.timeIntervalSince1970))
        ].joined(separator: "|")
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: MacAppStyle.sectionSpacing) {
                header
                metricsStrip
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(MacAppStyle.pagePadding)
            .frame(minWidth: 760)

            inspector
                .frame(minWidth: 330, idealWidth: 360, maxWidth: 430)
        }
        .background(MacAppStyle.pageBackground)
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
        .onChange(of: selectedStudentId) { _, _ in
            noteDraft = selectedInspectionAttendance?.note ?? ""
            publishToolbarActions()
        }
        .onChange(of: mode) { _, newValue in
            if newValue == .courses {
                selectedStudentId = nil
                historySelection = nil
            }
            publishToolbarActions()
        }
        .onChange(of: toolbarStateKey) { _, _ in
            publishToolbarActions()
        }
        .onDisappear {
            onToolbarActionsChange(nil)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Asistencia")
                        .font(MacAppStyle.pageTitle)
                    Text(selectedClass?.name ?? "Todos los cursos")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }

            HStack(spacing: 10) {
                Picker("Vista", selection: $mode) {
                    ForEach(MacAttendanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Menu {
                    Button("Todos los cursos") {
                        mode = .courses
                    }
                    Divider()
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Button {
                            selectedClassId = schoolClass.id
                            if mode == .courses {
                                mode = .day
                            }
                        } label: {
                            if schoolClass.id == selectedClassId {
                                Label(schoolClass.name, systemImage: "checkmark")
                            } else {
                                Text(schoolClass.name)
                            }
                        }
                    }
                } label: {
                    Label(selectedClass?.name ?? "Curso", systemImage: "rectangle.3.group")
                        .frame(minWidth: 170, alignment: .leading)
                }
                .menuStyle(.button)

                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(mode == .courses)

                TextField("Buscar alumno", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
                    .disabled(mode == .courses)

                Picker("Estado", selection: $selectedStatusFilter) {
                    Text("Todos").tag("TODOS")
                    ForEach(MacAttendanceStatusOption.all) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .frame(width: 150)
                .disabled(mode == .courses)
            }
        }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(classOverviews) { overview in
                    Button {
                        selectedClassId = overview.id
                        mode = .day
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
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
                        ForEach(filteredRows) { row in
                            MacAttendanceDayRow(
                                row: row,
                                isSelected: selectedStudentId == row.student.id,
                                isSaving: savingStudentIds.contains(row.student.id),
                                onSelect: {
                                    historySelection = nil
                                    selectedStudentId = row.student.id
                                },
                                onPickStatus: { status in
                                    Task { await updateAttendance(for: row.student, status: status.id) }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
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
                        .buttonStyle(.plain)
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
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(student.fullName)
                                .font(.title3.weight(.semibold))
                            Text(inspectorDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            selectedStudentId = nil
                            historySelection = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Cerrar ficha")
                    }

                    inspectorStatusCard(record: selectedInspectionAttendance ?? recentRecords.first)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Histórico reciente")
                            .font(.headline)
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
                                        tint: MacAttendanceStatusOption.option(for: record.status)?.color ?? .secondary
                                    )
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nota")
                            .font(.headline)
                        TextEditor(text: $noteDraft)
                            .font(.callout)
                            .frame(minHeight: 70)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sesiones vinculadas")
                            .font(.headline)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Incidencias")
                            .font(.headline)
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

                    VStack(alignment: .leading, spacing: 8) {
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

    private func inspectorStatusCard(record: KmpBridge.AttendanceRecordSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estado")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                MacStatusPill(
                    label: record.map { statusLabel($0.status) } ?? "Sin registro",
                    isActive: record != nil,
                    tint: MacAttendanceStatusOption.option(for: record?.status)?.color ?? .secondary
                )
                Spacer()
                if record?.followUpRequired == true {
                    Label("Seguimiento", systemImage: "flag.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MacAppStyle.warningTint)
                }
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    @MainActor
    private func bootstrap() async {
        isLoading = true
        await bridge.ensureClassesLoaded()
        if selectedClassId == nil {
            selectedClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
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
            historySelection = MacAttendanceHistorySelection(
                studentId: selection.studentId,
                date: selection.date,
                record: historyRecord(for: selection.studentId, date: selection.date)
            )
        }
        incidents = (try? await bridge.incidents(for: selectedClassId)) ?? []
        sessions = (try? await bridge.attendanceSessions(for: selectedClassId, on: selectedDate)) ?? []
        noteDraft = selectedInspectionAttendance?.note ?? ""
        isLoading = false
        publishToolbarActions()
    }

    @MainActor
    private func reloadClassOverviews() async {
        await bridge.ensureClassesLoaded()
        let range = monthRange(for: selectedDate)
        classOverviews = (try? await bridge.attendanceOverview(
            for: bridge.classes.map(\.id),
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
                followUpRequired: previousRecord?.followUpRequired
            )
            selectedStudentId = student.id
            if saveRevisionByStudentId[student.id] == revision {
                savingStudentIds.remove(student.id)
                bridge.status = "Asistencia actualizada."
            }
            await reloadClassOverviews()
        } catch {
            if saveRevisionByStudentId[student.id] == revision {
                recordsByStudentId[student.id] = previousRecord
                savingStudentIds.remove(student.id)
            }
            bridge.status = "No se pudo guardar la asistencia: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func markAllPresent() async {
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
                note: recordsByStudentId[student.id]?.note ?? "",
                hasIncident: recordsByStudentId[student.id]?.hasIncident ?? false,
                followUpRequired: recordsByStudentId[student.id]?.followUpRequired
            )
        }
        savingStudentIds.removeAll()
        await reloadAttendance()
        await reloadClassOverviews()
        bridge.status = "Todos los alumnos filtrados marcados como presentes."
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
                followUpRequired: current?.followUpRequired
            )
            bridge.status = "Nota de asistencia guardada."
            await reloadAttendance()
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
                followUpRequired: true
            )
            bridge.status = "Incidencia registrada desde asistencia."
            await reloadAttendance()
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
            sessionId: baseRecord?.sessionId
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
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return (interval.start, end)
    }

    private func publishToolbarActions() {
        onToolbarActionsChange(
            MacAttendanceToolbarActions(
                canCloseSelection: selectedStudentId != nil || historySelection != nil,
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
        let option = MacAttendanceStatusOption.option(for: record?.status)
        let isSelected = historySelection?.studentId == studentId && Calendar.current.isDate(historySelection?.date ?? .distantPast, inSameDayAs: date)
        return Button {
            selectedStudentId = studentId
            historySelection = MacAttendanceHistorySelection(studentId: studentId, date: date, record: record)
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
        MacAttendanceStatusOption.option(for: status)?.label ?? status
    }

    private static func dayHeaderString(_ date: Date) -> String {
        date.formatted(.dateTime.day())
    }

    private static func isPresentStatus(_ status: String?) -> Bool {
        status?.uppercased().contains("PRESENT") == true
    }

    private static func isAbsentStatus(_ status: String?) -> Bool {
        status?.uppercased().contains("AUS") == true
    }

    private static func isLateStatus(_ status: String?) -> Bool {
        guard let status = status?.uppercased() else { return false }
        return status.contains("TARD") || status.contains("RETR")
    }
}

private struct MacAttendanceDayRow: View {
    let row: MacAttendanceEntryRow
    let isSelected: Bool
    let isSaving: Bool
    let onSelect: () -> Void
    let onPickStatus: (MacAttendanceStatusOption) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(currentOption?.color.opacity(0.18) ?? Color.secondary.opacity(0.10))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Text(currentOption?.shortLabel ?? "·")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(currentOption?.color ?? .secondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(row.record.map { statusLabel($0.status) } ?? "Sin pasar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isSaving {
                ProgressView()
                    .scaleEffect(0.7)
            }

            HStack(spacing: 6) {
                ForEach(MacAttendanceStatusOption.all) { option in
                    Button {
                        onPickStatus(option)
                    } label: {
                        Text(option.shortLabel)
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .background(option.color.opacity(row.record?.status == option.id ? 0.22 : 0.08))
                    .foregroundStyle(option.color)
                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.chipRadius, style: .continuous))
                    .help(option.label)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.08) : MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : MacAppStyle.cardBorder, lineWidth: isSelected ? 1 : 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var currentOption: MacAttendanceStatusOption? {
        MacAttendanceStatusOption.option(for: row.record?.status)
    }

    private func statusLabel(_ status: String) -> String {
        MacAttendanceStatusOption.option(for: status)?.label ?? status
    }
}
