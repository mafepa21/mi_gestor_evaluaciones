import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit
#if os(macOS)
import AppKit
#endif

@MainActor
final class TeacherScheduleSettingsViewModel: ObservableObject {
    @Published var groups: [SchoolClass] = []
    @Published var classColorHexById: [Int64: String] = [:]
    @Published var weeklySlots: [WeeklySlotTemplate] = []
    @Published var teacherSchedule: TeacherSchedule?
    @Published var teacherScheduleSlots: [TeacherScheduleSlot] = []
    @Published var evaluationPeriods: [PlannerEvaluationPeriod] = []
    @Published var teachingUnits: [TeachingUnit] = []
    @Published var pendingRenameTeachingUnit: TeachingUnit?
    @Published var renameTeachingUnitDraft = ""
    @Published var pendingDeleteTeachingUnitId: Int64?
    @Published var forecastRows: [PlannerSessionForecast] = []
    @Published var nonTeachingEvents: [CalendarEvent] = []
    @Published var scheduleImportPreview: ScheduleImportPreview?
    @Published var isImportingSchedule = false

    @Published var scheduleName = "Agenda docente"
    @Published var scheduleStartDate = "2026-09-01"
    @Published var scheduleEndDate = "2027-06-30"
    @Published var activeWeekdays: Set<Int> = [1, 2, 3, 4, 5]
    @Published var scheduleFormGroupId: Int64?
    @Published var scheduleFormDay = 1
    @Published var scheduleFormStart = "08:05"
    @Published var scheduleFormEnd = "09:00"
    @Published var scheduleFormSubject = ""
    @Published var scheduleFormUnit = ""
    @Published var scheduleError = ""
    @Published var scheduleImportStatusMessage = ""
    @Published var scheduleSaveState: PlannerSaveState = .idle
    @Published var editingScheduleSlotId: Int64?
    @Published var editingScheduleSlotWeeklyTemplateId: Int64?
    @Published var editingEvaluationPeriodId: Int64?
    @Published var evaluationFormName = ""
    @Published var evaluationFormStart = ""
    @Published var evaluationFormEnd = ""
    @Published var scheduleStartDateValue: Date = AppDateTimeSupport.date(fromISO: "2026-09-01")
    @Published var scheduleEndDateValue: Date = AppDateTimeSupport.date(fromISO: "2027-06-30")
    @Published var scheduleFormStartTimeValue: Date = AppDateTimeSupport.time(from: "08:05")
    @Published var scheduleFormEndTimeValue: Date = AppDateTimeSupport.time(from: "09:00")
    @Published var evaluationFormStartDateValue: Date = .now
    @Published var evaluationFormEndDateValue: Date = .now

    private weak var bridge: KmpBridge?
    private var selectedClassId: Int64?
    private var isBound = false

    var activeWeekdaySummary: String {
        let labels = activeWeekdays.sorted().map(dayLabel(for:))
        return labels.isEmpty ? "Sin días lectivos" : labels.joined(separator: " · ")
    }

    var filteredForecastRows: [PlannerSessionForecast] {
        guard let selectedClassId else {
            return forecastRows.sorted { lhs, rhs in
                if lhs.periodName == rhs.periodName {
                    return lhs.className < rhs.className
                }
                return lhs.periodName < rhs.periodName
            }
        }
        return forecastRows
            .filter { $0.schoolClassId?.int64Value == selectedClassId }
            .sorted { lhs, rhs in
                if lhs.periodName == rhs.periodName {
                    return lhs.className < rhs.className
                }
                return lhs.periodName < rhs.periodName
            }
    }

    var effectiveScheduleSlots: [TeacherScheduleSlot] {
        teacherScheduleSlots.sorted(by: { ($0.dayOfWeek, $0.startTime) < ($1.dayOfWeek, $1.startTime) })
    }

    var usingLegacyWeeklySlots: Bool {
        false
    }

    func bind(bridge: KmpBridge, selectedClassId: Int64?) async {
        self.bridge = bridge
        self.selectedClassId = selectedClassId
        if !isBound {
            await reload()
            isBound = true
        } else {
            await refreshForecastForSelection()
        }
    }

    func updateSelectedClass(_ classId: Int64?) async {
        selectedClassId = classId
        if scheduleFormGroupId == nil {
            scheduleFormGroupId = classId ?? groups.first?.id
        }
        await refreshForecastForSelection()
    }

    func reload() async {
        guard let bridge else { return }
        await bridge.ensureClassesLoaded()
        groups = bridge.classes.sorted { $0.name < $1.name }
        classColorHexById = bridge.plannerCourseColors(for: groups.map(\.id))
        weeklySlots = bridge.plannerWeeklySlots(classId: nil)
        if scheduleFormGroupId == nil {
            scheduleFormGroupId = selectedClassId ?? groups.first?.id
        }

        do {
            let schedule = try await bridge.plannerTeacherSchedule()
            teacherSchedule = schedule
            scheduleName = schedule.name
            scheduleStartDate = schedule.startDateIso
            scheduleEndDate = schedule.endDateIso
            scheduleStartDateValue = AppDateTimeSupport.date(fromISO: schedule.startDateIso, fallback: scheduleStartDateValue)
            scheduleEndDateValue = AppDateTimeSupport.date(fromISO: schedule.endDateIso, fallback: scheduleEndDateValue)
            activeWeekdays = Set(
                schedule.activeWeekdaysCsv
                    .split(separator: ",")
                    .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            )
            teacherScheduleSlots = try await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)
            evaluationPeriods = try await bridge.plannerEvaluationPeriods(scheduleId: schedule.id)
            teachingUnits = (try? await bridge.plannerTeachingUnits(for: nil)) ?? []
            nonTeachingEvents = try await bridge.plannerNonTeachingCalendarEvents(classId: selectedClassId)
            await refreshForecastForSelection()
            scheduleError = ""
            scheduleImportStatusMessage = ""
            scheduleSaveState = .idle
        } catch {
            scheduleError = error.localizedDescription
            scheduleImportStatusMessage = ""
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func saveTeacherSchedule() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        syncScheduleDatesFromPicker()
        scheduleSaveState = .saving
        do {
            let savedId = try await bridge.plannerSaveTeacherSchedule(
                scheduleId: schedule.id,
                ownerUserId: schedule.ownerUserId,
                academicYearId: schedule.academicYearId,
                name: scheduleName,
                startDateIso: scheduleStartDate,
                endDateIso: scheduleEndDate,
                activeWeekdaysCsv: activeWeekdays.sorted().map(String.init).joined(separator: ","),
                trace: schedule.trace
            )
            teacherSchedule = TeacherSchedule(
                id: savedId,
                ownerUserId: schedule.ownerUserId,
                academicYearId: schedule.academicYearId,
                name: scheduleName,
                startDateIso: scheduleStartDate,
                endDateIso: scheduleEndDate,
                activeWeekdaysCsv: activeWeekdays.sorted().map(String.init).joined(separator: ","),
                trace: schedule.trace
            )
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func addScheduleSlot() async {
        guard let bridge, let schedule = teacherSchedule, let groupId = scheduleFormGroupId else { return }
        syncScheduleSlotTimesFromPicker()
        scheduleSaveState = .saving
        do {
            _ = try await bridge.plannerSaveTeacherScheduleSlot(
                scheduleId: schedule.id,
                classId: groupId,
                subjectLabel: scheduleFormSubject,
                unitLabel: scheduleFormUnit._nilIfBlank,
                dayOfWeek: scheduleFormDay,
                startTime: scheduleFormStart,
                endTime: scheduleFormEnd,
                editingSlotId: editingScheduleSlotId,
                existingWeeklyTemplateId: editingScheduleSlotWeeklyTemplateId
            )
            scheduleFormSubject = ""
            scheduleFormUnit = ""
            editingScheduleSlotId = nil
            editingScheduleSlotWeeklyTemplateId = nil
            scheduleError = ""
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func beginEditingScheduleSlot(_ slot: TeacherScheduleSlot) {
        scheduleFormGroupId = slot.schoolClassId
        scheduleFormDay = Int(slot.dayOfWeek)
        scheduleFormStart = slot.startTime
        scheduleFormEnd = slot.endTime
        scheduleFormStartTimeValue = AppDateTimeSupport.time(from: slot.startTime, fallback: scheduleFormStartTimeValue)
        scheduleFormEndTimeValue = AppDateTimeSupport.time(from: slot.endTime, fallback: scheduleFormEndTimeValue)
        scheduleFormSubject = slot.subjectLabel
        scheduleFormUnit = slot.unitLabel ?? ""
        editingScheduleSlotId = slot.id
        editingScheduleSlotWeeklyTemplateId = slot.weeklyTemplateId?.int64Value
    }

    func duplicateScheduleSlot(_ slot: TeacherScheduleSlot) {
        scheduleFormGroupId = slot.schoolClassId
        scheduleFormDay = Int(slot.dayOfWeek)
        scheduleFormStart = slot.startTime
        scheduleFormEnd = slot.endTime
        scheduleFormStartTimeValue = AppDateTimeSupport.time(from: slot.startTime, fallback: scheduleFormStartTimeValue)
        scheduleFormEndTimeValue = AppDateTimeSupport.time(from: slot.endTime, fallback: scheduleFormEndTimeValue)
        scheduleFormSubject = slot.subjectLabel
        scheduleFormUnit = slot.unitLabel ?? ""
        editingScheduleSlotId = nil
        editingScheduleSlotWeeklyTemplateId = nil
    }

    func cancelEditingScheduleSlot() {
        scheduleFormSubject = ""
        scheduleFormUnit = ""
        editingScheduleSlotId = nil
        editingScheduleSlotWeeklyTemplateId = nil
    }

    func deleteScheduleSlot(_ slotId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteTeacherScheduleSlot(slotId: slotId)
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func previewScheduleImport(_ result: Result<URL, Error>) async {
        scheduleSaveState = .saving
        do {
            let url = try result.get()
            let parsed = try ScheduleExcelImportService().preview(from: url)
            scheduleImportPreview = previewWithExistingConflicts(parsed)
            scheduleError = ""
            scheduleImportStatusMessage = ""
            scheduleSaveState = .idle
        } catch {
            scheduleError = error.localizedDescription
            scheduleImportStatusMessage = ""
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func importSchedulePreview(_ preview: ScheduleImportPreview, emptySlotMode: ScheduleEmptySlotImportMode) async {
        guard let bridge, teacherSchedule != nil else { return }
        isImportingSchedule = true
        scheduleSaveState = .saving
        defer { isImportingSchedule = false }

        do {
            var groupIdByCode = try await ensureImportedGroups(preview.groupCodes)
            guard let schedule = teacherSchedule else { return }

            var importedCount = 0
            for slot in preview.persistableSlots {
                for groupCode in slot.groupCodes {
                    guard let classId = groupIdByCode[groupCode] else { continue }
                    _ = try await bridge.plannerSaveTeacherScheduleSlot(
                        scheduleId: schedule.id,
                        classId: classId,
                        subjectLabel: slot.subjectName ?? slot.subjectCode ?? slot.displayTitle,
                        unitLabel: slot.kind == .tutoring ? "Tutoría multigrupo" : nil,
                        dayOfWeek: slot.weekday,
                        startTime: slot.startTime,
                        endTime: slot.endTime
                    )
                    importedCount += 1
                }
            }

            groupIdByCode.removeAll(keepingCapacity: true)
            scheduleImportPreview = nil
            await reload()
            scheduleSaveState = .saved(Date())
            scheduleError = ""
            scheduleImportStatusMessage = emptySlotMode == .skip
                ? "Horario importado correctamente (\(importedCount) franjas)."
                : "Horario importado correctamente (\(importedCount) franjas). Los huecos vacíos quedan clasificados en la previsualización, pero esta versión no los persiste sin grupo."
        } catch {
            scheduleError = error.localizedDescription
            scheduleImportStatusMessage = ""
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func addEvaluationPeriod() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        let normalizedName = evaluationFormName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            scheduleError = "Añade un nombre para la evaluación."
            scheduleSaveState = .failed(scheduleError)
            return
        }
        syncEvaluationDatesFromPicker()
        scheduleSaveState = .saving
        let editingId = editingEvaluationPeriodId
        let sortOrder = editingId.flatMap { id in evaluationPeriods.first(where: { $0.id == id })?.sortOrder }
            .map(Int.init) ?? evaluationPeriods.count + 1
        do {
            _ = try await bridge.plannerSaveEvaluationPeriod(
                periodId: editingId ?? 0,
                scheduleId: schedule.id,
                name: normalizedName,
                startDateIso: evaluationFormStart,
                endDateIso: evaluationFormEnd,
                sortOrder: sortOrder
            )
            evaluationFormName = ""
            evaluationFormStart = ""
            evaluationFormEnd = ""
            evaluationFormStartDateValue = .now
            evaluationFormEndDateValue = .now
            editingEvaluationPeriodId = nil
            scheduleError = ""
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func beginEditingEvaluationPeriod(_ period: PlannerEvaluationPeriod) {
        evaluationFormName = period.name
        evaluationFormStart = period.startDateIso
        evaluationFormEnd = period.endDateIso
        evaluationFormStartDateValue = AppDateTimeSupport.date(fromISO: period.startDateIso)
        evaluationFormEndDateValue = AppDateTimeSupport.date(fromISO: period.endDateIso)
        editingEvaluationPeriodId = period.id
    }

    func cancelEditingEvaluationPeriod() {
        evaluationFormName = ""
        evaluationFormStart = ""
        evaluationFormEnd = ""
        editingEvaluationPeriodId = nil
    }

    func deleteEvaluationPeriod(_ periodId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteEvaluationPeriod(periodId: periodId)
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func renameTeachingUnit(_ unit: TeachingUnit, newName: String) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerRenameTeachingUnit(unit, newName: newName)
            scheduleError = ""
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func deleteTeachingUnit(_ unitId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteTeachingUnit(unitId)
            scheduleError = ""
            await reload()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func toggleActiveWeekday(_ day: Int) {
        if activeWeekdays.contains(day) {
            activeWeekdays.remove(day)
        } else {
            activeWeekdays.insert(day)
        }
    }

    func dayLabel(for day: Int) -> String {
        switch day {
        case 1: return "Lun"
        case 2: return "Mar"
        case 3: return "Mié"
        case 4: return "Jue"
        case 5: return "Vie"
        case 6: return "Sáb"
        case 7: return "Dom"
        default: return "D\(day)"
        }
    }

    private func refreshForecastForSelection() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        forecastRows = (try? await bridge.plannerForecast(scheduleId: schedule.id, classId: selectedClassId)) ?? []
    }

    func syncScheduleDatesFromPicker() {
        scheduleStartDate = AppDateTimeSupport.isoDateString(from: scheduleStartDateValue)
        scheduleEndDate = AppDateTimeSupport.isoDateString(from: scheduleEndDateValue)
    }

    func syncScheduleSlotTimesFromPicker() {
        scheduleFormStart = AppDateTimeSupport.timeString(from: scheduleFormStartTimeValue)
        scheduleFormEnd = AppDateTimeSupport.timeString(from: scheduleFormEndTimeValue)
    }

    func syncEvaluationDatesFromPicker() {
        evaluationFormStart = AppDateTimeSupport.isoDateString(from: evaluationFormStartDateValue)
        evaluationFormEnd = AppDateTimeSupport.isoDateString(from: evaluationFormEndDateValue)
    }

    func colorHex(for classId: Int64) -> String {
        classColorHexById[classId] ?? EvaluationDesign.plannerCoursePalette[0]
    }

    func saveColor(_ colorHex: String, for classId: Int64) {
        guard let bridge else { return }
        bridge.plannerSetCourseColor(colorHex, for: classId)
        classColorHexById[classId] = bridge.plannerCourseColor(for: classId)
    }

    func knownGroupNamesByCode() -> [String: String] {
        Dictionary(
            groups.compactMap { group in
                guard let code = groupCode(from: group.name) else { return nil }
                return (code, group.name)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func ensureImportedGroups(_ groupCodes: [String]) async throws -> [String: Int64] {
        guard let bridge else { return [:] }
        var idByCode = Dictionary(
            groups.compactMap { group in
                groupCode(from: group.name).map { ($0, group.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        for code in groupCodes where idByCode[code] == nil {
            let className = groupDisplayName(for: code)
            let course = Int32(Int(code.prefix(1)) ?? 0)
            let classId = try await bridge.createClass(name: className, course: course)
            idByCode[code] = classId
            await bridge.ensureClassesLoaded()
            groups = bridge.classes.sorted { $0.name < $1.name }
        }
        return idByCode
    }

    private func previewWithExistingConflicts(_ preview: ScheduleImportPreview) -> ScheduleImportPreview {
        let idByCode = Dictionary(
            groups.compactMap { group in
                groupCode(from: group.name).map { ($0, group.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var conflicts = preview.conflicts

        for imported in preview.persistableSlots {
            for groupCode in imported.groupCodes {
                guard let classId = idByCode[groupCode] else { continue }
                for existing in effectiveScheduleSlots where existing.schoolClassId == classId && Int(existing.dayOfWeek) == imported.weekday {
                    if rangesOverlap(startA: existing.startTime, endA: existing.endTime, startB: imported.startTime, endB: imported.endTime) {
                        conflicts.append("\(dayLabel(for: imported.weekday)) \(imported.startTime)-\(imported.endTime) se solapa con una franja existente de \(groupDisplayName(for: groupCode)).")
                    }
                }
            }
        }

        return ScheduleImportPreview(
            sourceName: preview.sourceName,
            slots: preview.slots,
            subjectLegend: preview.subjectLegend,
            conflicts: Array(Set(conflicts)).sorted(),
            warnings: preview.warnings
        )
    }

    private func rangesOverlap(startA: String, endA: String, startB: String, endB: String) -> Bool {
        guard let a0 = minutes(startA), let a1 = minutes(endA), let b0 = minutes(startB), let b1 = minutes(endB) else {
            return false
        }
        return max(a0, b0) < min(a1, b1)
    }

    private func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    private func groupDisplayName(for code: String) -> String {
        guard code.count >= 5 else { return code }
        return "\(code.prefix(1))º ESO \(code.suffix(1))"
    }

    private func groupCode(from name: String) -> String? {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .replacingOccurrences(of: "º", with: "")
            .replacingOccurrences(of: "°", with: "")
        guard normalized.contains("ESO") else { return nil }
        let digits = normalized.filter(\.isNumber)
        let letters = normalized.filter(\.isLetter)
        guard let course = digits.first, let group = letters.last else { return nil }
        return "\(course)ESO\(group)"
    }
}

// MARK: - Local helpers (avoid fileprivate/private access level issues)

private extension String {
    var _nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ScheduleForecastRowView: View {
    let row: PlannerSessionForecast

    private var deltaColor: Color {
        row.remainingSessions > 0 ? EvaluationDesign.danger : EvaluationDesign.success
    }

    var body: some View {
        HStack {
            Text(row.className)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Previstas \(row.expectedSessions)")
                .font(.caption.weight(.bold))
            Text("Creadas \(row.plannedSessions)")
                .font(.caption.weight(.bold))
            Text("Δ \(row.remainingSessions)")
                .font(.caption.weight(.bold))
                .foregroundStyle(deltaColor)
        }
    }
}
