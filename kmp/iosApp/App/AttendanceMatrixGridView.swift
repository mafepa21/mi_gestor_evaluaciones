import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Si falla marcar presente/ausente en la sábana, el cambio se revierte y el aviso
/// debe quedar visible en español (sin fingir que se guardó).
enum AttendanceMatrixSaveGate {
    static let saveFailureMessage =
        "No se pudo guardar la asistencia. Pulsa otra vez para reintentar."

    static func failureMessage(detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return saveFailureMessage }
        return "\(saveFailureMessage) \(trimmed)"
    }
}

struct AttendanceMatrixGridView: View {
    let bridge: KmpBridge
    @ObservedObject var attendanceStore: AttendanceBridgeStore
    let selectedClassId: Int64
    var onSelectStudent: ((Student) -> Void)? = nil

    @State private var selectedRange: AttendanceMatrixRange = .month
    @State private var searchText: String = ""
    @State private var matrixRecords: [Int64: [String: KmpBridge.AttendanceRecordSnapshot]] = [:]
    @State private var uniqueDates: [Date] = []
    @State private var isLoading: Bool = false
    @State private var activeCellPopover: MatrixCellTarget? = nil
    @State private var isCopiedAlertPresented: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.undoManager) private var undoManager
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var pendingUndo: MatrixBulkUndo?
    @State private var undoDismissTask: Task<Void, Never>?

    /// Estados previos de «Todos presentes hoy», guardados para poder deshacer.
    struct MatrixBulkUndo {
        let id = UUID()
        let date: Date
        let previousDrafts: [KmpBridge.AttendanceDraft]
    }
    // Medidas que crecen con el tamaño de letra del sistema (Dynamic Type).
    @ScaledMetric(relativeTo: .subheadline) private var studentColumnWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .caption) private var dateColumnWidth: CGFloat = 50
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var statusBadgeSize: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .caption) private var footerHeight: CGFloat = 40
    @State private var horizontalOffset: CGFloat = 0

    struct MatrixCellTarget: Identifiable {
        let student: Student
        let date: Date
        let currentRecord: KmpBridge.AttendanceRecordSnapshot?

        var id: String {
            "\(student.id)_\(date.timeIntervalSince1970)"
        }
    }

    private let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "dd/MM"
        return df
    }()

    private let accessibilityDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEEE d 'de' MMMM"
        return df
    }()

    private let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEE"
        return df
    }()

    private var students: [Student] {
        attendanceStore.studentsInClass.filter {
            AttendanceMatrixSearch.nameMatches($0.fullName, query: searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topControlBar
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.vertical, 10)

            legendBar
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.bottom, 8)

            Divider()

            if isLoading && uniqueDates.isEmpty {
                Spacer()
                ProgressView("Cargando sábana de asistencia…")
                Spacer()
            } else if students.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("Sin alumnado", systemImage: "person.3.sequence")
                } description: {
                    Text("No hay alumnos en este grupo o no coinciden con la búsqueda.")
                }
                Spacer()
            } else {
                matrixContent
            }
        }
        .background(appPageBackground(for: colorScheme))
        .overlay(alignment: .bottom) {
            if let pendingUndo {
                AttendanceUndoBanner(
                    message: "\(pendingUndo.previousDrafts.count) marcados como presentes",
                    onUndo: { Task { await undoMarkTodayAllPresent() } }
                )
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(uiFeatureFlags.animation(.easeInOut(duration: 0.2)), value: pendingUndo?.id)
        .task(id: "\(selectedClassId)_\(selectedRange.rawValue)") {
            await reloadMatrixData()
        }
        .popover(item: $activeCellPopover) { target in
            AttendanceMatrixStatusPicker(
                target: target,
                onSelectStatus: { status in
                    activeCellPopover = nil
                    Task {
                        await setAttendance(status: status, for: target.student, on: target.date)
                    }
                },
                onClear: {
                    activeCellPopover = nil
                    Task {
                        await clearAttendance(for: target.student, on: target.date)
                    }
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Top Controls
    private var topControlBar: some View {
        HStack(spacing: 12) {
            Picker("Rango", selection: $selectedRange) {
                ForEach(AttendanceMatrixRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            IOSSearchField(text: $searchText, placeholder: "Buscar alumno…")
                .frame(minWidth: 160, maxWidth: 260)

            Spacer()

            Button {
                Task { await markTodayAllPresent() }
            } label: {
                Label("Todos presentes hoy", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppleDesignSystem.success)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(todayMarkableDrafts().isEmpty)

            ViewThatFits(in: .horizontal) {
                copySummaryButton(iconOnly: false)
                copySummaryButton(iconOnly: true)
            }
        }
    }

    private func copySummaryButton(iconOnly: Bool) -> some View {
        let title = isCopiedAlertPresented ? "¡Copiado!" : "Copiar resumen"
        let icon = isCopiedAlertPresented ? "checkmark" : "doc.on.doc"
        return Button {
            copySummaryToClipboard()
        } label: {
            if iconOnly {
                Label(title, systemImage: icon).labelStyle(.iconOnly)
            } else {
                Label(title, systemImage: icon)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(title)
    }

    // MARK: - Legend Bar
    private var legendBar: some View {
        HStack(spacing: 8) {
            Text("Leyenda:")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            ForEach(AttendanceStatusOption.all) { option in
                HStack(spacing: 4) {
                    Text(option.shortLabel)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(option.color))
                    Text(option.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(uniqueDates.count) sesiones registradas")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Matrix Grid Content
    /// Columna de nombres fija a la izquierda y fila de fechas fija arriba (iOS 18+ / macOS):
    /// un único scroll vertical con dos columnas; el horizontal solo mueve fechas y totales.
    private var matrixContent: some View {
        VStack(spacing: 0) {
            if pinsDateHeader {
                HStack(spacing: 0) {
                    studentColumnHeader
                        .frame(width: studentColumnWidth, height: headerHeight, alignment: .leading)
                        .background(appCardBackground(for: colorScheme))
                        .shadow(color: .black.opacity(horizontalOffset > 1 ? 0.10 : 0), radius: 4, x: 2)
                        .zIndex(1)
                    dateHeaderStrip
                        .offset(x: -horizontalOffset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.15)), alignment: .bottom)
            }

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    pinnedNamesColumn
                        .frame(width: studentColumnWidth)
                        .background(appPageBackground(for: colorScheme))
                        .shadow(color: .black.opacity(horizontalOffset > 1 ? 0.10 : 0), radius: 4, x: 2)
                        .zIndex(1)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                // Anclas invisibles por fecha para saltar a hoy al abrir.
                                HStack(spacing: 0) {
                                    ForEach(uniqueDates, id: \.self) { date in
                                        Color.clear.frame(width: dateColumnWidth, height: 0).id(date)
                                    }
                                }
                                if !pinsDateHeader {
                                    dateHeaderStrip
                                        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.15)), alignment: .bottom)
                                }
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(students.enumerated()), id: \.element.id) { index, student in
                                        dataRow(student: student, isEven: index.isMultiple(of: 2))
                                    }
                                }
                                footerDataRow
                            }
                        }
                        .modifier(HorizontalOffsetReader(offset: $horizontalOffset))
                        .onAppear { scrollToToday(proxy) }
                        .onChange(of: uniqueDates) { _, _ in scrollToToday(proxy) }
                    }
                }
            }
        }
    }

    private var pinsDateHeader: Bool {
        if #available(iOS 18.0, macOS 15.0, *) { return true }
        return false
    }

    private func scrollToToday(_ proxy: ScrollViewProxy) {
        let today = Calendar.current.startOfDay(for: Date())
        let target = uniqueDates.last(where: { Calendar.current.startOfDay(for: $0) <= today }) ?? uniqueDates.last
        guard let target else { return }
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .trailing) }
    }

    private var pinnedNamesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !pinsDateHeader {
                studentColumnHeader
                    .frame(height: headerHeight, alignment: .leading)
                    .background(appCardBackground(for: colorScheme))
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.15)), alignment: .bottom)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(students.enumerated()), id: \.element.id) { index, student in
                    studentRowCell(student: student)
                        .frame(width: studentColumnWidth, height: rowHeight, alignment: .leading)
                        .background(index.isMultiple(of: 2) ? Color.secondary.opacity(0.02) : Color.clear)
                        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.08)), alignment: .bottom)
                }
            }
            Text("Presentes / Total")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(width: studentColumnWidth, height: footerHeight, alignment: .leading)
                .background(EvaluationDesign.surfaceSoft.opacity(0.6))
        }
    }

    private var dateHeaderStrip: some View {
        HStack(spacing: 0) {
            ForEach(uniqueDates, id: \.self) { date in
                dateColumnHeader(for: date)
                    .frame(width: dateColumnWidth, height: headerHeight)
            }
            statsColumnsHeader
                .frame(height: headerHeight)
        }
        .background(appCardBackground(for: colorScheme))
        .fixedSize()
    }

    private func dataRow(student: Student, isEven: Bool) -> some View {
        let stats = computeStats(for: student)
        return HStack(spacing: 0) {
            ForEach(uniqueDates, id: \.self) { date in
                let record = recordFor(studentId: student.id, date: date)
                attendanceCell(student: student, date: date, record: record)
                    .frame(width: dateColumnWidth, height: rowHeight)
            }
            statsRowCells(stats: stats)
                .frame(height: rowHeight)
        }
        .background(isEven ? Color.secondary.opacity(0.02) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.08)), alignment: .bottom)
    }

    private var footerDataRow: some View {
        HStack(spacing: 0) {
            ForEach(uniqueDates, id: \.self) { date in
                let summary = dateSummary(for: date)
                VStack(spacing: 1) {
                    Text("\(summary.present)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(AppleDesignSystem.success)
                    Text("/\(summary.total)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: dateColumnWidth, height: footerHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(accessibilityDateFormatter.string(from: date)): \(summary.present) presentes de \(summary.total)")
            }
            classGlobalStatsCell
                .frame(height: footerHeight)
        }
        .background(EvaluationDesign.surfaceSoft.opacity(0.6))
    }

    // MARK: - Column Headers
    private var studentColumnHeader: some View {
        HStack {
            Text("Alumnado (\(students.count))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight)
    }

    private func dateColumnHeader(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return VStack(spacing: 2) {
            Text(weekdayFormatter.string(from: date).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? EvaluationDesign.accent : .secondary)

            Text(dayFormatter.string(from: date))
                .font(.system(.caption2, design: .rounded).weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? .white : .primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    isToday ? Capsule().fill(EvaluationDesign.accent) : Capsule().fill(Color.clear)
                )
        }
        .frame(minHeight: headerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDateFormatter.string(from: date) + (isToday ? ", hoy" : ""))
        .accessibilityAddTraits(.isHeader)
    }

    private var statsColumnsHeader: some View {
        HStack(spacing: 0) {
            Text("% Asist.")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: headerHeight)

            Text("Faltas")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppleDesignSystem.danger)
                .frame(width: 50, height: headerHeight)

            Text("Retr.")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppleDesignSystem.warning)
                .frame(width: 50, height: headerHeight)

            Text("Just.")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 50, height: headerHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Student Cell
    private func studentRowCell(student: Student) -> some View {
        Button {
            onSelectStudent?(student)
        } label: {
            HStack(spacing: 8) {
                Text(student.initials)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor))

                VStack(alignment: .leading, spacing: 1) {
                    Text(student.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if student.isInjured {
                        HStack(spacing: 2) {
                            Image(systemName: "bandage.fill")
                                .font(.caption2)
                            Text("Lesión")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Color.orange)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(student.fullName + (student.isInjured ? ", lesión activa" : ""))
        .accessibilityHint("Abre la ficha del alumno")
    }

    // MARK: - Attendance Status Cell
    private func attendanceCell(student: Student, date: Date, record: KmpBridge.AttendanceRecordSnapshot?) -> some View {
        let option = AttendanceStatusOption.option(for: record?.status)

        return Button {
            activeCellPopover = MatrixCellTarget(student: student, date: date, currentRecord: record)
        } label: {
            ZStack {
                if let option {
                    Text(option.shortLabel)
                        .font(.system(.caption2, design: .rounded).weight(.black))
                        .foregroundStyle(option.color)
                        .frame(width: statusBadgeSize, height: statusBadgeSize)
                        .background(
                            Circle()
                                .fill(option.color.opacity(0.16))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(option.color.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    // Guion visible para "sin dato": no depender de un punto casi invisible.
                    Text("–")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: statusBadgeSize, height: statusBadgeSize)
                }

                if record?.hasIncident == true {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .offset(x: 10, y: -10)
                } else if !(record?.note.isEmpty ?? true) {
                    // Anillo (no punto relleno) para distinguir nota de incidencia sin depender del color.
                    Circle()
                        .strokeBorder(Color.blue, lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                        .offset(x: 10, y: -10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(student.fullName), \(accessibilityDateFormatter.string(from: date))")
        .accessibilityValue(attendanceCellAccessibilityValue(option: option, record: record))
        .accessibilityHint("Cambia el estado de asistencia")
    }

    private func attendanceCellAccessibilityValue(option: AttendanceStatusOption?, record: KmpBridge.AttendanceRecordSnapshot?) -> String {
        var parts = [option?.label ?? "Sin registrar"]
        if record?.hasIncident == true { parts.append("con incidencia") }
        if !(record?.note.isEmpty ?? true) { parts.append("con nota") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Stats Cells
    private func statsRowCells(stats: AttendanceMatrixStudentStats) -> some View {
        HStack(spacing: 0) {
            Text("\(stats.attendanceRate)%")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(stats.attendanceRateColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(stats.attendanceRateColor.opacity(0.12), in: Capsule())
                .frame(width: 64)

            Text("\(stats.absentCount)")
                .font(.system(.caption, design: .rounded).weight(stats.absentCount > 0 ? .black : .regular))
                .foregroundStyle(stats.absentCount > 0 ? AppleDesignSystem.danger : .secondary)
                .frame(width: 50)

            Text("\(stats.lateCount)")
                .font(.system(.caption, design: .rounded).weight(stats.lateCount > 0 ? .bold : .regular))
                .foregroundStyle(stats.lateCount > 0 ? AppleDesignSystem.warning : .secondary)
                .frame(width: 50)

            Text("\(stats.justifiedCount)")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 50)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.attendanceRate)% de asistencia, \(stats.absentCount) faltas, \(stats.lateCount) retrasos, \(stats.justifiedCount) justificadas")
    }

    private var classGlobalStatsCell: some View {
        let allStats = students.map { computeStats(for: $0) }
        let totalSessions = allStats.reduce(0) { $0 + $1.totalSessions }
        let totalAttended = allStats.reduce(0) { $0 + $1.presentCount + $1.lateCount + $1.exemptCount }
        let globalRate = totalSessions > 0 ? Int(round(Double(totalAttended) / Double(totalSessions) * 100.0)) : 100
        let totalAbsences = allStats.reduce(0) { $0 + $1.absentCount }

        return HStack(spacing: 0) {
            Text("\(globalRate)% med.")
                .font(.caption.weight(.bold))
                .foregroundStyle(EvaluationDesign.accent)
                .frame(width: 64)

            Text("\(totalAbsences) tot.")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppleDesignSystem.danger)
                .frame(width: 50)

            Spacer()
        }
        .frame(width: 214)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Media de la clase \(globalRate)%, \(totalAbsences) faltas en total")
    }

    // MARK: - Data Logic & Persistence
    private func dateKey(for date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private func recordFor(studentId: Int64, date: Date) -> KmpBridge.AttendanceRecordSnapshot? {
        let key = dateKey(for: date)
        return matrixRecords[studentId]?[key]
    }

    private func computeStats(for student: Student) -> AttendanceMatrixStudentStats {
        guard let recordsForStudent = matrixRecords[student.id] else {
            return AttendanceMatrixStudentStats(
                student: student,
                presentCount: 0,
                absentCount: 0,
                lateCount: 0,
                justifiedCount: 0,
                noMaterialCount: 0,
                exemptCount: 0,
                totalSessions: 0
            )
        }

        var present = 0
        var absent = 0
        var late = 0
        var justified = 0
        var noMaterial = 0
        var exempt = 0

        for date in uniqueDates {
            let key = dateKey(for: date)
            guard let record = recordsForStudent[key] else { continue }
            switch record.status {
            case "PRESENTE": present += 1
            case "AUSENTE": absent += 1
            case "TARDE": late += 1
            case "JUSTIFICADO": justified += 1
            case "SIN_MATERIAL": noMaterial += 1
            case "EXENTO": exempt += 1
            default: break
            }
        }

        let total = present + absent + late + justified + noMaterial + exempt

        return AttendanceMatrixStudentStats(
            student: student,
            presentCount: present,
            absentCount: absent,
            lateCount: late,
            justifiedCount: justified,
            noMaterialCount: noMaterial,
            exemptCount: exempt,
            totalSessions: total
        )
    }

    private func dateSummary(for date: Date) -> (present: Int, total: Int) {
        let key = dateKey(for: date)
        var present = 0
        var tracked = 0
        for student in students {
            if let record = matrixRecords[student.id]?[key] {
                tracked += 1
                if record.status == "PRESENTE" || record.status == "TARDE" || record.status == "EXENTO" {
                    present += 1
                }
            }
        }
        return (present, tracked)
    }

    private func reloadMatrixData() async {
        isLoading = true
        let range = selectedRange.dateRange()
        do {
            let history = try await bridge.attendanceHistory(for: selectedClassId, from: range.start, to: range.end)

            var recordsByStudent: [Int64: [String: KmpBridge.AttendanceRecordSnapshot]] = [:]
            var dateMap: [String: Date] = [:]

            for record in history {
                let key = dateKey(for: record.date)
                if recordsByStudent[record.studentId] == nil {
                    recordsByStudent[record.studentId] = [:]
                }
                recordsByStudent[record.studentId]?[key] = record
                if dateMap[key] == nil {
                    dateMap[key] = record.date
                }
            }

            let todayKey = dateKey(for: Date())
            if dateMap[todayKey] == nil {
                dateMap[todayKey] = Date()
            }

            self.uniqueDates = dateMap.values.sorted()
            self.matrixRecords = recordsByStudent
        } catch {
            print("Error cargando sábana de asistencia: \(error)")
        }
        isLoading = false
    }

    private func setAttendance(status: String, for student: Student, on date: Date) async {
        let key = dateKey(for: date)
        let previous = matrixRecords[student.id]?[key]

        // Actualización optimista
        let optimisticRecord = KmpBridge.AttendanceRecordSnapshot(
            id: previous?.id ?? 0,
            studentId: student.id,
            classId: selectedClassId,
            date: date,
            status: status,
            note: previous?.note ?? "",
            hasIncident: previous?.hasIncident ?? false,
            followUpRequired: previous?.followUpRequired ?? false,
            sessionId: previous?.sessionId
        )

        if matrixRecords[student.id] == nil {
            matrixRecords[student.id] = [:]
        }
        matrixRecords[student.id]?[key] = optimisticRecord
        AppleInteractionFeedback.play(.selection)

        do {
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: selectedClassId,
                on: date,
                status: status,
                note: previous?.note,
                sessionId: previous?.sessionId
            )
        } catch {
            matrixRecords[student.id]?[key] = previous
            bridge.status = AttendanceMatrixSaveGate.failureMessage(
                detail: error.localizedDescription
            )
            AppleInteractionFeedback.play(.error)
        }
    }

    /// Desmarca y lo guarda (antes solo se borraba en pantalla y reaparecía al recargar).
    private func clearAttendance(for student: Student, on date: Date) async {
        let key = dateKey(for: date)
        let previous = matrixRecords[student.id]?[key]
        matrixRecords[student.id]?.removeValue(forKey: key)
        AppleInteractionFeedback.play(.lightImpact)
        do {
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: selectedClassId,
                on: date,
                status: "",
                note: previous?.note,
                sessionId: previous?.sessionId
            )
        } catch {
            matrixRecords[student.id]?[key] = previous
            bridge.status = AttendanceMatrixSaveGate.failureMessage(detail: error.localizedDescription)
            AppleInteractionFeedback.play(.error)
        }
    }

    /// Alumnos que «Todos presentes hoy» cambiaría (no toca justificados, exentos ni ya presentes).
    private func todayMarkableDrafts() -> [KmpBridge.AttendanceDraft] {
        let today = Date()
        let key = dateKey(for: today)
        return students.compactMap { student in
            let current = matrixRecords[student.id]?[key]
            guard !["JUSTIFICADO", "EXENTO", "PRESENTE"].contains(current?.status ?? "") else { return nil }
            return KmpBridge.AttendanceDraft(
                studentId: student.id,
                classId: selectedClassId,
                date: today,
                status: current?.status ?? "",
                note: current?.note ?? "",
                hasIncident: current?.hasIncident ?? false,
                followUpRequired: current?.followUpRequired,
                sessionId: current?.sessionId
            )
        }
    }

    private func applyLocal(_ drafts: [KmpBridge.AttendanceDraft]) {
        for draft in drafts {
            let key = dateKey(for: draft.date)
            let current = matrixRecords[draft.studentId]?[key]
            if matrixRecords[draft.studentId] == nil { matrixRecords[draft.studentId] = [:] }
            if draft.status.isEmpty {
                matrixRecords[draft.studentId]?.removeValue(forKey: key)
            } else {
                matrixRecords[draft.studentId]?[key] = KmpBridge.AttendanceRecordSnapshot(
                    id: current?.id ?? 0,
                    studentId: draft.studentId,
                    classId: draft.classId,
                    date: draft.date,
                    status: draft.status,
                    note: draft.note,
                    hasIncident: draft.hasIncident,
                    followUpRequired: draft.followUpRequired ?? false,
                    sessionId: draft.sessionId
                )
            }
        }
    }

    private func undoMarkTodayAllPresent() async {
        guard let undo = pendingUndo else { return }
        pendingUndo = nil
        undoDismissTask?.cancel()
        applyLocal(undo.previousDrafts)
        do {
            try await bridge.saveAttendanceBatch(records: undo.previousDrafts)
            bridge.status = "Asistencia de hoy restaurada."
            AppleInteractionFeedback.play(.success)
        } catch {
            bridge.status = "No se pudo deshacer del todo: \(error.localizedDescription). Revisa la columna de hoy."
            AppleInteractionFeedback.play(.error)
            await reloadMatrixData()
        }
    }

    private func markTodayAllPresent() async {
        let previousDrafts = todayMarkableDrafts()
        guard !previousDrafts.isEmpty else { return }
        let presentDrafts = previousDrafts.map { draft in
            KmpBridge.AttendanceDraft(
                studentId: draft.studentId,
                classId: draft.classId,
                date: draft.date,
                status: "PRESENTE",
                note: draft.note,
                hasIncident: draft.hasIncident,
                followUpRequired: draft.followUpRequired,
                sessionId: draft.sessionId
            )
        }
        applyLocal(presentDrafts)

        do {
            try await bridge.saveAttendanceBatch(records: presentDrafts)
            AppleInteractionFeedback.play(.success)
            bridge.status = "\(presentDrafts.count) alumnos marcados como presentes hoy."
            let undo = MatrixBulkUndo(date: Date(), previousDrafts: previousDrafts)
            pendingUndo = undo
            undoManager?.registerUndo(withTarget: bridge) { _ in
                Task { @MainActor in await undoMarkTodayAllPresent() }
            }
            undoManager?.setActionName("Todos presentes hoy")
            undoDismissTask?.cancel()
            undoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                if pendingUndo?.id == undo.id { pendingUndo = nil }
            }
        } catch {
            // El lote no es atómico: recargar desde la base para mostrar lo que de verdad quedó guardado.
            bridge.status = AttendanceMatrixSaveGate.failureMessage(detail: error.localizedDescription)
            AppleInteractionFeedback.play(.error)
            await reloadMatrixData()
        }
    }

    private func copySummaryToClipboard() {
        var lines: [String] = []
        lines.append("Resumen de Asistencia - \(selectedRange.rawValue)")
        lines.append("Alumno\t% Asistencia\tFaltas (A)\tRetrasos (R)\tJustificadas (J)")

        for student in students {
            let stats = computeStats(for: student)
            lines.append("\(student.fullName)\t\(stats.attendanceRate)%\t\(stats.absentCount)\t\(stats.lateCount)\t\(stats.justifiedCount)")
        }

        let resultText = lines.joined(separator: "\n")

        #if canImport(UIKit)
        UIPasteboard.general.string = resultText
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        #endif

        AppleInteractionFeedback.play(.success)
        isCopiedAlertPresented = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopiedAlertPresented = false
        }
    }
}

// MARK: - Status Picker Popover
private struct AttendanceMatrixStatusPicker: View {
    @ScaledMetric(relativeTo: .subheadline) private var pickerWidth: CGFloat = 220
    let target: AttendanceMatrixGridView.MatrixCellTarget
    let onSelectStatus: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.student.fullName)
                    .font(.subheadline.weight(.bold))
                Text(target.date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Divider()

            VStack(spacing: 4) {
                ForEach(AttendanceStatusOption.all) { option in
                    Button {
                        onSelectStatus(option.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.shortLabel)
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(option.color))

                            Text(option.label)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if target.currentRecord?.status == option.id {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(EvaluationDesign.accent)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(target.currentRecord?.status == option.id ? EvaluationDesign.accent.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(target.currentRecord?.status == option.id ? .isSelected : [])
                }
            }

            if target.currentRecord != nil {
                Divider()

                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Desmarcar", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(minWidth: pickerWidth)
    }
}

/// Lee el desplazamiento horizontal para que la fila de fechas fija lo siga (iOS 18 / macOS 15).
private struct HorizontalOffsetReader: ViewModifier {
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x + geometry.contentInsets.leading
            } action: { _, newValue in
                offset = max(0, newValue)
            }
        } else {
            content
        }
    }
}
