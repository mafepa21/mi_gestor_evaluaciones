import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

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

    private let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEE"
        return df
    }()

    private var students: [Student] {
        attendanceStore.studentsInClass.filter { student in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return student.fullName.localizedCaseInsensitiveContains(query)
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
                .frame(maxWidth: 200)

            Spacer()

            Button {
                Task { await markTodayAllPresent() }
            } label: {
                Label("Marcar todos hoy (P)", systemImage: "bolt.badge.checkmark.fill")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppleDesignSystem.success)
            .controlSize(.small)

            Button {
                copySummaryToClipboard()
            } label: {
                Label(isCopiedAlertPresented ? "¡Copiado!" : "Copiar resumen", systemImage: isCopiedAlertPresented ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
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
                        .font(.system(size: 10, weight: .bold, design: .rounded))
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
    private var matrixContent: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Cabecera de columnas
                HStack(spacing: 0) {
                    studentColumnHeader
                        .frame(width: 220, alignment: .leading)
                        .background(appCardBackground(for: colorScheme))

                    ForEach(uniqueDates, id: \.self) { date in
                        dateColumnHeader(for: date)
                            .frame(width: 50)
                            .background(appCardBackground(for: colorScheme))
                    }

                    statsColumnsHeader
                        .background(appCardBackground(for: colorScheme))
                }
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.15)), alignment: .bottom)

                // Filas de alumnos
                ForEach(Array(students.enumerated()), id: \.element.id) { index, student in
                    let stats = computeStats(for: student)
                    let isEven = index.isMultiple(of: 2)

                    HStack(spacing: 0) {
                        studentRowCell(student: student)
                            .frame(width: 220, height: 44, alignment: .leading)
                            .background(isEven ? Color.secondary.opacity(0.02) : Color.clear)

                        ForEach(uniqueDates, id: \.self) { date in
                            let record = recordFor(studentId: student.id, date: date)
                            attendanceCell(student: student, date: date, record: record)
                                .frame(width: 50, height: 44)
                                .background(isEven ? Color.secondary.opacity(0.02) : Color.clear)
                        }

                        statsRowCells(stats: stats)
                            .frame(height: 44)
                            .background(isEven ? Color.secondary.opacity(0.02) : Color.clear)
                    }
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.08)), alignment: .bottom)
                }

                // Fila de resumen de fecha al pie
                HStack(spacing: 0) {
                    Text("Presentes / Total")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(width: 220, height: 40, alignment: .leading)

                    ForEach(uniqueDates, id: \.self) { date in
                        let summary = dateSummary(for: date)
                        VStack(spacing: 1) {
                            Text("\(summary.present)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppleDesignSystem.success)
                            Text("/\(summary.total)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 50, height: 40)
                    }

                    classGlobalStatsCell
                        .frame(height: 40)
                }
                .background(EvaluationDesign.surfaceSoft.opacity(0.6))
            }
        }
    }

    // MARK: - Column Headers
    private var studentColumnHeader: some View {
        HStack {
            Text("Alumnado (\(students.count))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private func dateColumnHeader(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return VStack(spacing: 2) {
            Text(weekdayFormatter.string(from: date).uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isToday ? EvaluationDesign.accent : .secondary)

            Text(dayFormatter.string(from: date))
                .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isToday ? .white : .primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    isToday ? Capsule().fill(EvaluationDesign.accent) : Capsule().fill(Color.clear)
                )
        }
        .frame(height: 48)
    }

    private var statsColumnsHeader: some View {
        HStack(spacing: 0) {
            Text("% Asist.")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 48)

            Text("Faltas")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppleDesignSystem.danger)
                .frame(width: 50, height: 48)

            Text("Retr.")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppleDesignSystem.warning)
                .frame(width: 50, height: 48)

            Text("Just.")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 48)
        }
    }

    // MARK: - Student Cell
    private func studentRowCell(student: Student) -> some View {
        Button {
            onSelectStudent?(student)
        } label: {
            HStack(spacing: 8) {
                Text(student.initials)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
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
                                .font(.system(size: 9))
                            Text("Lesión")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.orange)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
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
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(option.color)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(option.color.opacity(0.16))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(option.color.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    Text("·")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                }

                if record?.hasIncident == true {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .offset(x: 10, y: -10)
                } else if !(record?.note.isEmpty ?? true) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                        .offset(x: 10, y: -10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Cells
    private func statsRowCells(stats: AttendanceMatrixStudentStats) -> some View {
        HStack(spacing: 0) {
            Text("\(stats.attendanceRate)%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(stats.attendanceRateColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(stats.attendanceRateColor.opacity(0.12), in: Capsule())
                .frame(width: 64)

            Text("\(stats.absentCount)")
                .font(.system(size: 12, weight: stats.absentCount > 0 ? .black : .regular, design: .rounded))
                .foregroundStyle(stats.absentCount > 0 ? AppleDesignSystem.danger : .secondary)
                .frame(width: 50)

            Text("\(stats.lateCount)")
                .font(.system(size: 12, weight: stats.lateCount > 0 ? .bold : .regular, design: .rounded))
                .foregroundStyle(stats.lateCount > 0 ? AppleDesignSystem.warning : .secondary)
                .frame(width: 50)

            Text("\(stats.justifiedCount)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 50)
        }
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
            AppleInteractionFeedback.play(.error)
        }
    }

    private func clearAttendance(for student: Student, on date: Date) async {
        let key = dateKey(for: date)
        matrixRecords[student.id]?.removeValue(forKey: key)
        AppleInteractionFeedback.play(.lightImpact)
    }

    private func markTodayAllPresent() async {
        let today = Date()
        let key = dateKey(for: today)

        var drafts: [KmpBridge.AttendanceDraft] = []
        for student in students {
            let current = matrixRecords[student.id]?[key]
            guard current?.status != "JUSTIFICADO" && current?.status != "EXENTO" else { continue }

            drafts.append(
                KmpBridge.AttendanceDraft(
                    studentId: student.id,
                    classId: selectedClassId,
                    date: today,
                    status: "PRESENTE",
                    note: current?.note ?? "",
                    hasIncident: current?.hasIncident ?? false,
                    followUpRequired: current?.followUpRequired,
                    sessionId: current?.sessionId
                )
            )

            let opt = KmpBridge.AttendanceRecordSnapshot(
                id: current?.id ?? 0,
                studentId: student.id,
                classId: selectedClassId,
                date: today,
                status: "PRESENTE",
                note: current?.note ?? "",
                hasIncident: current?.hasIncident ?? false,
                followUpRequired: current?.followUpRequired ?? false,
                sessionId: current?.sessionId
            )
            if matrixRecords[student.id] == nil {
                matrixRecords[student.id] = [:]
            }
            matrixRecords[student.id]?[key] = opt
        }

        AppleInteractionFeedback.play(.success)

        do {
            try await bridge.saveAttendanceBatch(records: drafts)
            bridge.status = "Todos los alumnos marcados como presentes hoy."
        } catch {
            bridge.status = "Error al marcar todos presentes: \(error.localizedDescription)"
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
                                .font(.system(size: 11, weight: .bold, design: .rounded))
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
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(target.currentRecord?.status == option.id ? EvaluationDesign.accent.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if target.currentRecord != nil {
                Divider()

                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Limpiar registro", systemImage: "trash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 220)
    }
}
