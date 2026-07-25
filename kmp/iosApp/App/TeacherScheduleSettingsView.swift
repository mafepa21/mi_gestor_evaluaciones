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
    @Published var scheduleImportPlan: ScheduleImportCatalogPlan?
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
    private let catalogResolver = ScheduleImportCatalogResolver()

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
            let withConflicts = previewWithExistingConflicts(parsed)
            scheduleImportPreview = withConflicts
            scheduleImportPlan = buildCatalogPlan(for: withConflicts)
            scheduleError = ""
            scheduleImportStatusMessage = ""
            scheduleSaveState = .idle
        } catch {
            scheduleError = error.localizedDescription
            scheduleImportPlan = nil
            scheduleImportStatusMessage = ""
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func importSchedulePreview(_ preview: ScheduleImportPreview, emptySlotMode: ScheduleEmptySlotImportMode, createSubjects: Bool = true) async {
        guard let bridge, teacherSchedule != nil else { return }
        isImportingSchedule = true
        scheduleSaveState = .saving
        defer { isImportingSchedule = false }

        do {
            let catalog = try await ensureImportedCatalog(preview, createSubjects: createSubjects)
            guard let schedule = teacherSchedule else { return }

            var importedCount = 0
            var skippedCount = 0
            for slot in preview.persistableSlots {
                for groupCode in slot.groupCodes {
                    guard let classId = catalog.groupIdByCode[groupCode] else { continue }
                    let subjectLabel = resolvedSubjectLabel(for: slot, groupCode: groupCode, subjectNameByCode: catalog.subjectNameByCode)

                    let alreadyExists = effectiveScheduleSlots.contains { existing in
                        existing.schoolClassId == classId
                            && Int(existing.dayOfWeek) == slot.weekday
                            && existing.startTime == slot.startTime
                            && existing.endTime == slot.endTime
                            && existing.subjectLabel == subjectLabel
                    }
                    if alreadyExists {
                        skippedCount += 1
                        continue
                    }

                    _ = try await bridge.plannerSaveTeacherScheduleSlot(
                        scheduleId: schedule.id,
                        classId: classId,
                        subjectLabel: subjectLabel,
                        unitLabel: slot.kind == .tutoring ? "Tutoría multigrupo" : nil,
                        dayOfWeek: slot.weekday,
                        startTime: slot.startTime,
                        endTime: slot.endTime
                    )
                    importedCount += 1
                }
            }

            scheduleImportPreview = nil
            scheduleImportPlan = nil
            await reload()
            scheduleSaveState = .saved(Date())
            scheduleError = ""

            var message = "Horario importado correctamente (\(importedCount) franjas)."
            if skippedCount > 0 {
                message += " \(skippedCount) ya existían y se omitieron."
            }
            if emptySlotMode != .skip {
                message += " Los huecos vacíos quedan clasificados en la previsualización, pero esta versión no los persiste sin grupo."
            }
            scheduleImportStatusMessage = message
        } catch {
            scheduleError = error.localizedDescription
            scheduleImportStatusMessage = ""
            scheduleSaveState = .failed(scheduleError)
        }
    }

    private func resolvedSubjectLabel(for slot: ImportedScheduleSlot, groupCode: String, subjectNameByCode: [String: String]) -> String {
        if let code = slot.subjectCode(forGroup: groupCode), let name = subjectNameByCode[code] {
            return name
        }
        return slot.subjectName ?? slot.displayTitle
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
        guard let preview = scheduleImportPreview else { return [:] }
        let groupResolution = catalogResolver.resolveGroups(preview: preview, existingGroups: groups)
        return Dictionary(
            groupResolution.matchedIdByCode.compactMap { code, classId in
                groups.first(where: { $0.id == classId }).map { (code, $0.name) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func buildCatalogPlan(for preview: ScheduleImportPreview) -> ScheduleImportCatalogPlan {
        guard let bridge else { return .empty }
        let groupResolution = catalogResolver.resolveGroups(preview: preview, existingGroups: groups)
        let subjectResolution = catalogResolver.resolveSubjects(preview: preview, existingSubjects: bridge.subjects)
        let plan = ScheduleImportCatalogPlan.build(groupResolution: groupResolution, subjectResolution: subjectResolution)

        let ambiguousWarnings = catalogResolver.subjectCodesByGroup(preview: preview)
            .filter { $0.value.count > 1 }
            .map { groupCode, subjectCodes -> String in
                let name = groupResolution.matchedIdByCode[groupCode]
                    .flatMap { classId in groups.first(where: { $0.id == classId })?.name }
                    ?? groupDisplayName(for: groupCode)
                return "\(name) imparte \(subjectCodes.count) materias (\(subjectCodes.sorted().joined(separator: ", "))): se deja sin asignatura fija. Duplica el grupo desde Cursos si quieres cuadernos separados."
            }
            .sorted()

        guard !ambiguousWarnings.isEmpty else { return plan }
        return ScheduleImportCatalogPlan(
            groupsToCreate: plan.groupsToCreate,
            groupsReusedCount: plan.groupsReusedCount,
            subjectsToCreate: plan.subjectsToCreate,
            subjectsReusedCount: plan.subjectsReusedCount,
            warnings: plan.warnings + ambiguousWarnings
        )
    }

    /// Crea en el catálogo los grupos y asignaturas que detecta el Excel y
    /// no existen todavía, y hace backfill de `subjectId` en grupos ya
    /// existentes que imparten una única asignatura y aún no lo tenían. Los
    /// grupos con `subjectId` puesto a mano nunca se tocan.
    private func ensureImportedCatalog(
        _ preview: ScheduleImportPreview,
        createSubjects: Bool
    ) async throws -> (groupIdByCode: [String: Int64], subjectNameByCode: [String: String]) {
        guard let bridge else { return ([:], [:]) }

        let subjectResolution = catalogResolver.resolveSubjects(preview: preview, existingSubjects: bridge.subjects)
        var subjectIdByCode = subjectResolution.matchedIdByCode
        let subjectNames = subjectNameByCode(from: subjectResolution, existingSubjects: bridge.subjects)
        if createSubjects {
            for item in subjectResolution.toCreate {
                let subjectId = try await bridge.saveSubject(code: item.code, name: item.name)
                subjectIdByCode[item.code] = subjectId
            }
        }

        let groupResolution = catalogResolver.resolveGroups(preview: preview, existingGroups: groups)
        let subjectCodesByGroup = catalogResolver.subjectCodesByGroup(preview: preview)
        var groupIdByCode = groupResolution.matchedIdByCode

        for item in groupResolution.toCreate {
            let singleSubjectCode = subjectCodesByGroup[item.code]?.count == 1 ? subjectCodesByGroup[item.code]?.first : nil
            let classId = try await bridge.createClass(
                name: item.name,
                course: item.course,
                subjectId: singleSubjectCode.flatMap { subjectIdByCode[$0] }
            )
            groupIdByCode[item.code] = classId
        }

        for (groupCode, classId) in groupResolution.matchedIdByCode {
            guard let existingGroup = groups.first(where: { $0.id == classId }), existingGroup.subjectId == nil else { continue }
            guard let subjectCodes = subjectCodesByGroup[groupCode], subjectCodes.count == 1, let onlyCode = subjectCodes.first else { continue }
            guard let subjectId = subjectIdByCode[onlyCode] else { continue }
            try await bridge.updateClass(
                id: classId,
                name: existingGroup.name,
                course: existingGroup.course,
                description: existingGroup.description_,
                centerId: existingGroup.centerId?.int64Value,
                academicYearId: existingGroup.academicYearId?.int64Value,
                stageCycleId: existingGroup.stageCycleId?.int64Value,
                subjectId: subjectId
            )
        }

        await bridge.ensureClassesLoaded()
        groups = bridge.classes.sorted { $0.name < $1.name }

        return (groupIdByCode, subjectNames)
    }

    /// Nombre a mostrar por código de asignatura: el del catálogo cuando ya
    /// existe (nunca se sobrescribe), o el que se le asignará al crearla.
    /// Compartido entre la comprobación de idempotencia y el guardado real
    /// para que ambos calculen exactamente el mismo `subjectLabel`.
    private func subjectNameByCode(
        from resolution: ScheduleImportCatalogResolver.SubjectResolution,
        existingSubjects: [KmpSubject]
    ) -> [String: String] {
        var result = Dictionary(
            uniqueKeysWithValues: resolution.matchedIdByCode.compactMap { code, subjectId in
                existingSubjects.first(where: { $0.id == subjectId }).map { (code, $0.name) }
            }
        )
        for item in resolution.toCreate {
            result[item.code] = item.name
        }
        return result
    }

    private func previewWithExistingConflicts(_ preview: ScheduleImportPreview) -> ScheduleImportPreview {
        guard let bridge else { return preview }
        let groupResolution = catalogResolver.resolveGroups(preview: preview, existingGroups: groups)
        let subjectResolution = catalogResolver.resolveSubjects(preview: preview, existingSubjects: bridge.subjects)
        let subjectNames = subjectNameByCode(from: subjectResolution, existingSubjects: bridge.subjects)
        var conflicts = preview.conflicts
        var warnings = preview.warnings
        var alreadyImportedCount = 0

        for imported in preview.persistableSlots {
            for groupCode in imported.groupCodes {
                guard let classId = groupResolution.matchedIdByCode[groupCode] else { continue }
                let subjectLabel = resolvedSubjectLabel(for: imported, groupCode: groupCode, subjectNameByCode: subjectNames)
                let groupName = groups.first(where: { $0.id == classId })?.name ?? groupDisplayName(for: groupCode)

                for existing in effectiveScheduleSlots where existing.schoolClassId == classId && Int(existing.dayOfWeek) == imported.weekday {
                    guard rangesOverlap(startA: existing.startTime, endA: existing.endTime, startB: imported.startTime, endB: imported.endTime) else { continue }

                    let isIdenticalSlot = existing.startTime == imported.startTime
                        && existing.endTime == imported.endTime
                        && existing.subjectLabel == subjectLabel
                    if isIdenticalSlot {
                        alreadyImportedCount += 1
                    } else {
                        conflicts.append("\(dayLabel(for: imported.weekday)) \(imported.startTime)-\(imported.endTime) se solapa con una franja existente de \(groupName).")
                    }
                }
            }
        }

        if alreadyImportedCount > 0 {
            warnings.append("\(alreadyImportedCount) franja(s) ya existen igual en el horario y se omitirán al importar.")
        }

        return ScheduleImportPreview(
            sourceName: preview.sourceName,
            slots: preview.slots,
            subjectLegend: preview.subjectLegend,
            conflicts: Array(Set(conflicts)).sorted(),
            warnings: warnings
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
        ScheduleGroupNaming.displayName(forCode: code)
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
