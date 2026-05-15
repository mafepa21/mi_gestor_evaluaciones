import SwiftUI
import MiGestorKit

@MainActor
final class TeacherScheduleSettingsViewModel: ObservableObject {
    @Published var groups: [SchoolClass] = []
    @Published var classColorHexById: [Int64: String] = [:]
    @Published var weeklySlots: [WeeklySlotTemplate] = []
    @Published var teacherSchedule: TeacherSchedule?
    @Published var teacherScheduleSlots: [TeacherScheduleSlot] = []
    @Published var evaluationPeriods: [PlannerEvaluationPeriod] = []
    @Published var forecastRows: [PlannerSessionForecast] = []
    @Published var nonTeachingEvents: [CalendarEvent] = []

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
    @Published var editingScheduleSlotId: Int64?
    @Published var editingScheduleSlotWeeklyTemplateId: Int64?
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
        if !teacherScheduleSlots.isEmpty {
            return teacherScheduleSlots.sorted(by: { ($0.dayOfWeek, $0.startTime) < ($1.dayOfWeek, $1.startTime) })
        }

        return weeklySlots.map {
            TeacherScheduleSlot(
                id: $0.id,
                teacherScheduleId: teacherSchedule?.id ?? 0,
                schoolClassId: $0.schoolClassId,
                subjectLabel: "",
                unitLabel: nil,
                dayOfWeek: Int32($0.dayOfWeek),
                startTime: $0.startTime,
                endTime: $0.endTime,
                weeklyTemplateId: KotlinLong(value: $0.id)
            )
        }
        .sorted(by: { ($0.dayOfWeek, $0.startTime) < ($1.dayOfWeek, $1.startTime) })
    }

    var usingLegacyWeeklySlots: Bool {
        teacherScheduleSlots.isEmpty && !weeklySlots.isEmpty
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
            nonTeachingEvents = try await bridge.plannerNonTeachingCalendarEvents(classId: selectedClassId)
            await refreshForecastForSelection()
            scheduleError = ""
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func saveTeacherSchedule() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        syncScheduleDatesFromPicker()
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
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func addScheduleSlot() async {
        guard let bridge, let schedule = teacherSchedule, let groupId = scheduleFormGroupId else { return }
        syncScheduleSlotTimesFromPicker()
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
        } catch {
            scheduleError = error.localizedDescription
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
        do {
            try await bridge.plannerDeleteTeacherScheduleSlot(slotId: slotId)
            await reload()
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func addEvaluationPeriod() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        let normalizedName = evaluationFormName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            scheduleError = "Añade un nombre para la evaluación."
            return
        }
        syncEvaluationDatesFromPicker()
        do {
            _ = try await bridge.plannerSaveEvaluationPeriod(
                periodId: 0,
                scheduleId: schedule.id,
                name: normalizedName,
                startDateIso: evaluationFormStart,
                endDateIso: evaluationFormEnd,
                sortOrder: evaluationPeriods.count + 1
            )
            evaluationFormName = ""
            evaluationFormStart = ""
            evaluationFormEnd = ""
            evaluationFormStartDateValue = .now
            evaluationFormEndDateValue = .now
            scheduleError = ""
            await reload()
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func deleteEvaluationPeriod(_ periodId: Int64) async {
        guard let bridge else { return }
        do {
            try await bridge.plannerDeleteEvaluationPeriod(periodId: periodId)
            await reload()
        } catch {
            scheduleError = error.localizedDescription
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
}

#if os(macOS)
struct MacTeacherScheduleSettingsPanel: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @StateObject private var vm = TeacherScheduleSettingsViewModel()

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if !vm.scheduleError.isEmpty {
                Text(vm.scheduleError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EvaluationDesign.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            summaryCard
            courseCard
            slotsCard

            macCard {
                DisclosureGroup("Evaluaciones") {
                    evaluationsContent
                        .padding(.top, 12)
                }
            }

            macCard {
                DisclosureGroup("Colores") {
                    colorsContent
                        .padding(.top, 12)
                }
            }

            macCard {
                DisclosureGroup("No lectivos") {
                    nonTeachingContent
                        .padding(.top, 12)
                }
            }
        }
        .controlSize(.regular)
        .task {
            await vm.bind(bridge: bridge, selectedClassId: selectedClassId)
        }
        .appOnChange(of: selectedClassId) { newValue in
            Task { await vm.updateSelectedClass(newValue) }
        }
    }

    private var summaryCard: some View {
        macCard {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resumen")
                        .font(MacAppStyle.sectionTitle)
                    Text(vm.scheduleName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                metric("Curso", "\(vm.scheduleStartDate) - \(vm.scheduleEndDate)")
                metric("Franjas", "\(vm.effectiveScheduleSlots.count)")
                metric("Evaluaciones", "\(vm.evaluationPeriods.count)")
                metric("No lectivos", "\(vm.nonTeachingEvents.count)")
            }
        }
    }

    private var courseCard: some View {
        macCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Curso")
                        .font(MacAppStyle.sectionTitle)
                    Spacer()
                    Picker(
                        "Grupo",
                        selection: Binding(
                            get: { selectedClassId ?? -1 },
                            set: { selectedClassId = $0 > 0 ? $0 : nil }
                        )
                    ) {
                        Text("Todos").tag(Int64(-1))
                        ForEach(vm.groups, id: \.id) { group in
                            Text(group.name).tag(group.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Nombre de agenda", text: $vm.scheduleName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)

                    labeledDatePicker("Inicio", selection: $vm.scheduleStartDateValue)
                    labeledDatePicker("Fin", selection: $vm.scheduleEndDateValue)

                    Button("Guardar") {
                        Task { await vm.saveTeacherSchedule() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 8) {
                    Text("Días")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                        if vm.activeWeekdays.contains(day) {
                            Button {
                                vm.toggleActiveWeekday(day)
                            } label: {
                                Text(vm.dayLabel(for: day))
                                    .font(.caption.weight(.bold))
                                    .frame(width: 36)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                vm.toggleActiveWeekday(day)
                            } label: {
                                Text(vm.dayLabel(for: day))
                                    .font(.caption.weight(.bold))
                                    .frame(width: 36)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text(vm.activeWeekdaySummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    Spacer()
                }
            }
        }
    }

    private var slotsCard: some View {
        macCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Franjas")
                        .font(MacAppStyle.sectionTitle)
                    Spacer()
                    if vm.editingScheduleSlotId != nil {
                        Button("Cancelar edición") {
                            vm.cancelEditingScheduleSlot()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                slotEditorRow

                if vm.usingLegacyWeeklySlots {
                    Text("Mostrando franjas heredadas del horario original.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if vm.effectiveScheduleSlots.isEmpty {
                    Text("Todavía no hay franjas definidas.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.effectiveScheduleSlots, id: \.id) { slot in
                            slotRow(slot)
                            if slot.id != vm.effectiveScheduleSlots.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var slotEditorRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Picker(
                "Grupo",
                selection: Binding(
                    get: { vm.scheduleFormGroupId ?? -1 },
                    set: { vm.scheduleFormGroupId = $0 > 0 ? $0 : nil }
                )
            ) {
                ForEach(vm.groups, id: \.id) { group in
                    Text(group.name).tag(group.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Picker("Día", selection: $vm.scheduleFormDay) {
                ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                    Text(vm.dayLabel(for: day)).tag(day)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 84)

            compactTimePicker("Inicio", selection: $vm.scheduleFormStartTimeValue)
            compactTimePicker("Fin", selection: $vm.scheduleFormEndTimeValue)

            TextField("Materia", text: $vm.scheduleFormSubject)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)

            TextField("Unidad", text: $vm.scheduleFormUnit)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)

            Button(vm.editingScheduleSlotId == nil ? "Añadir" : "Guardar") {
                Task { await vm.addScheduleSlot() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.scheduleFormGroupId == nil)
        }
    }

    private var evaluationsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Nombre", text: $vm.evaluationFormName)
                    .textFieldStyle(.roundedBorder)
                labeledDatePicker("Inicio", selection: $vm.evaluationFormStartDateValue)
                labeledDatePicker("Fin", selection: $vm.evaluationFormEndDateValue)
                Button("Añadir") {
                    Task { await vm.addEvaluationPeriod() }
                }
                .buttonStyle(.borderedProminent)
            }

            if vm.evaluationPeriods.isEmpty {
                Text("Aún no hay periodos evaluativos.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.evaluationPeriods.sorted(by: { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }), id: \.id) { period in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(period.name)
                                .font(.callout.weight(.semibold))
                            Text("\(period.startDateIso) - \(period.endDateIso)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await vm.deleteEvaluationPeriod(period.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        let rows = vm.filteredForecastRows.filter { $0.periodId == period.id }
                        if rows.isEmpty {
                            Text("Sin sesiones previstas para este periodo.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                ScheduleForecastRowView(row: row)
                            }
                        }
                    }
                    .padding(10)
                    .background(MacAppStyle.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var colorsContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(vm.groups, id: \.id) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: vm.colorHex(for: group.id)))
                            .frame(width: 10, height: 10)
                        Text(group.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        ForEach(EvaluationDesign.plannerCoursePalette, id: \.self) { hex in
                            Button {
                                vm.saveColor(hex, for: group.id)
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle()
                                            .stroke(vm.colorHex(for: group.id) == hex ? Color.primary : Color.clear, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var nonTeachingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.nonTeachingEvents.isEmpty {
                Text("No hay eventos no lectivos detectados.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.nonTeachingEvents, id: \.id) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.title)
                            .font(.callout.weight(.semibold))
                        Text(nonTeachingSubtitle(event))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let classId = event.classId?.int64Value,
                           let group = vm.groups.first(where: { $0.id == classId }) {
                            Text(group.name)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(MacAppStyle.cardBackground, in: Capsule(style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func slotRow(_ slot: TeacherScheduleSlot) -> some View {
        HStack(spacing: 12) {
            Text("\(vm.dayLabel(for: Int(slot.dayOfWeek))) · \(slot.startTime)-\(slot.endTime)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 150, alignment: .leading)
            Text(vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)")
                .font(.callout)
                .frame(width: 170, alignment: .leading)
            Text(slot.subjectLabel.isEmpty ? "Sin materia" : slot.subjectLabel)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(slot.unitLabel ?? "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Editar") {
                vm.beginEditingScheduleSlot(slot)
            }
            .buttonStyle(.borderless)
            .disabled(vm.usingLegacyWeeklySlots)

            Button("Duplicar") {
                vm.duplicateScheduleSlot(slot)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                Task { await vm.deleteScheduleSlot(slot.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(vm.usingLegacyWeeklySlots)
        }
        .padding(.vertical, 8)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold))
                .monospacedDigit()
        }
    }

    private func macCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private func labeledDatePicker(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DatePicker(label, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    private func compactTimePicker(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DatePicker(label, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(width: 82)
    }

    private func nonTeachingSubtitle(_ event: CalendarEvent) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(event.startAt.toEpochMilliseconds()) / 1000)
        let end = Date(timeIntervalSince1970: TimeInterval(event.endAt.toEpochMilliseconds()) / 1000)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
    }
}
#endif

struct TeacherScheduleSettingsPanel: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @StateObject private var vm = TeacherScheduleSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: EvaluationDesign.cardSpacing) {
            EvaluationGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    EvaluationSectionTitle(
                        eyebrow: "Planificación docente",
                        title: "Horario, curso y calendario lectivo",
                        subtitle: "Aquí se define la agenda fija que consume Planner: rango del curso, franjas semanales, no lectivos detectados y previsión por evaluación."
                    )

                    if !vm.scheduleError.isEmpty {
                        Text(vm.scheduleError)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EvaluationDesign.danger)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Grupo en foco")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Picker(
                                "Grupo en foco",
                                selection: Binding(
                                    get: { selectedClassId ?? -1 },
                                    set: { selectedClassId = $0 > 0 ? $0 : nil }
                                )
                            ) {
                                Text("Todos").tag(Int64(-1) as Int64?)
                                ForEach(vm.groups, id: \.id) { group in
                                    Text(group.name).tag(group.id as Int64?)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("No lectivos detectados")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("\(vm.nonTeachingEvents.count)")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                        }
                    }
                }
            }

            EvaluationGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    EvaluationSectionTitle(
                        eyebrow: "Marco del curso",
                        title: "Curso, agenda y días lectivos",
                        subtitle: "La agenda docente persiste en KMP y sirve como fuente única para el planner semanal."
                    )

                    TextField("Nombre de agenda", text: $vm.scheduleName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Text("Marca aquí el inicio y el fin reales del curso. Planner usará este rango para calcular semanas, no lectivos y previsiones por evaluación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Inicio de curso")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "Inicio de curso",
                                selection: $vm.scheduleStartDateValue,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fin de curso")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "Fin de curso",
                                selection: $vm.scheduleEndDateValue,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        Button("Guardar curso") {
                            Task { await vm.saveTeacherSchedule() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Días lectivos")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                                if vm.activeWeekdays.contains(day) {
                                    Button {
                                        vm.toggleActiveWeekday(day)
                                    } label: {
                                        Text(vm.dayLabel(for: day))
                                            .font(.caption.weight(.bold))
                                            .frame(minWidth: 44)
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else {
                                    Button {
                                        vm.toggleActiveWeekday(day)
                                    } label: {
                                        Text(vm.dayLabel(for: day))
                                            .font(.caption.weight(.bold))
                                            .frame(minWidth: 44)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        Text(vm.activeWeekdaySummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            EvaluationGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    EvaluationSectionTitle(
                        eyebrow: "Horario fijo",
                        title: "Franjas semanales del docente",
                        subtitle: "Cada franja alimenta el tablero semanal y sirve de base para el cómputo de sesiones lectivas por evaluación."
                    )

                    HStack(spacing: 12) {
                        Picker(
                            "Grupo",
                            selection: Binding(
                                get: { vm.scheduleFormGroupId ?? -1 },
                                set: { vm.scheduleFormGroupId = $0 > 0 ? $0 : nil }
                            )
                        ) {
                            ForEach(vm.groups, id: \.id) { group in
                                Text(group.name).tag(group.id as Int64?)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Día", selection: $vm.scheduleFormDay) {
                            ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                                Text(vm.dayLabel(for: day)).tag(day)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 12) {
                        TextField("Materia o bloque", text: $vm.scheduleFormSubject)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Unidad de referencia", text: $vm.scheduleFormUnit)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    Text("Define una franja tal y como ocurre en el centro. Si eliges una hora distinta a las franjas clásicas, el planner la mostrará igualmente en su hueco real.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Inicio")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "Inicio",
                                selection: $vm.scheduleFormStartTimeValue,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fin")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "Fin",
                                selection: $vm.scheduleFormEndTimeValue,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        Button("Añadir franja") {
                            Task { await vm.addScheduleSlot() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if vm.teacherScheduleSlots.isEmpty {
                    Text("Todavía no hay franjas definidas.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        if vm.usingLegacyWeeklySlots {
                            Text("Mostrando franjas heredadas del horario original de KMP Desktop. Puedes seguir viéndolas aquí aunque todavía no se hayan guardado en la agenda persistente.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(vm.effectiveScheduleSlots, id: \.id) { slot in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(vm.dayLabel(for: Int(slot.dayOfWeek))) · \(slot.startTime)-\(slot.endTime)")
                                        .font(.body.weight(.semibold))
                                    let slotLines: [String?] = [
                                        vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                                        slot.subjectLabel,
                                        slot.unitLabel
                                    ]
                                    Text(
                                        slotLines
                                            .compactMap { value in
                                                guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
                                                return raw
                                            }
                                            .joined(separator: " · ")
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !vm.usingLegacyWeeklySlots {
                                    Button(role: .destructive) {
                                        Task { await vm.deleteScheduleSlot(slot.id) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            EvaluationGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    EvaluationSectionTitle(
                        eyebrow: "Identidad visual",
                        title: "Color por curso",
                        subtitle: "Cada curso puede tener un color fijo para reconocerlo de un vistazo en planner."
                    )

                    Text("Elige un color estable para cada curso. El color identificará el curso en las franjas y no sustituirá al estado de la sesión.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(vm.groups, id: \.id) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: vm.colorHex(for: group.id)))
                                    .frame(width: 12, height: 12)
                                Text(group.name)
                                    .font(.subheadline.weight(.semibold))
                            }

                            HStack(spacing: 10) {
                                ForEach(EvaluationDesign.plannerCoursePalette, id: \.self) { hex in
                                    Button {
                                        vm.saveColor(hex, for: group.id)
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 28, height: 28)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        vm.colorHex(for: group.id) == hex ? Color.primary : Color.clear,
                                                        lineWidth: 3
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            EvaluationGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    EvaluationSectionTitle(
                        eyebrow: "Calendario",
                        title: "No lectivos detectados",
                        subtitle: "Se leen del calendario y afectan al contador de sesiones previstas si contienen etiquetas como festivo, no lectivo, vacaciones o puente."
                    )

                    if vm.nonTeachingEvents.isEmpty {
                        Text("No hay eventos no lectivos detectados para el contexto actual.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.nonTeachingEvents, id: \.id) { event in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title)
                                        .font(.body.weight(.semibold))
                                    Text(nonTeachingSubtitle(event))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let classId = event.classId?.int64Value,
                                   let group = vm.groups.first(where: { $0.id == classId }) {
                                    Text(group.name)
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule(style: .continuous).fill(EvaluationDesign.surfaceSoft))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            EvaluationGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    EvaluationSectionTitle(
                        eyebrow: "Evaluaciones",
                        title: "Periodos y cómputo lectivo",
                        subtitle: "El contador cruza agenda fija, curso, festivos detectados y sesiones ya creadas en planner."
                    )

                    HStack(spacing: 12) {
                        TextField("Nombre de la evaluación", text: $vm.evaluationFormName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Inicio")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "Inicio de evaluación",
                                selection: $vm.evaluationFormStartDateValue,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fin")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "Fin de evaluación",
                                selection: $vm.evaluationFormEndDateValue,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        Button("Añadir periodo") {
                            Task { await vm.addEvaluationPeriod() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text("Cada evaluación necesita un rango claro. El sistema lo cruzará con las franjas semanales y los días no lectivos para calcular cuántas sesiones tocan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if vm.evaluationPeriods.isEmpty {
                        Text("Aún no hay periodos evaluativos configurados.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.evaluationPeriods.sorted(by: { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }), id: \.id) { period in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(period.name)
                                            .font(.headline)
                                        Text("\(period.startDateIso) · \(period.endDateIso)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await vm.deleteEvaluationPeriod(period.id) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }

                                let rows = vm.filteredForecastRows.filter { $0.periodId == period.id }
                                if rows.isEmpty {
                                    Text("Sin sesiones previstas para este periodo con el contexto actual.")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                        ScheduleForecastRowView(row: row)
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(EvaluationDesign.surfaceSoft)
                            )
                        }
                    }
                }
            }
        }
        .task {
            await vm.bind(bridge: bridge, selectedClassId: selectedClassId)
        }
        .appOnChange(of: selectedClassId) { newValue in
            Task { await vm.updateSelectedClass(newValue) }
        }
    }

    private func nonTeachingSubtitle(_ event: CalendarEvent) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(event.startAt.toEpochMilliseconds()) / 1000)
        let end = Date(timeIntervalSince1970: TimeInterval(event.endAt.toEpochMilliseconds()) / 1000)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) · \(end.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Local helpers (avoid fileprivate/private access level issues)

private extension String {
    var _nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ScheduleForecastRowView: View {
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
