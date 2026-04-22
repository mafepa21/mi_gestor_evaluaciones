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
    @Published var editingScheduleSlotId: Int64?
    @Published var editingScheduleSlotWeeklyTemplateId: Int64?
    @Published var scheduleError = ""
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

    var isEditingScheduleSlot: Bool {
        editingScheduleSlotId != nil || editingScheduleSlotWeeklyTemplateId != nil
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

    func editScheduleSlot(_ slot: TeacherScheduleSlot) {
        scheduleFormGroupId = slot.schoolClassId
        scheduleFormDay = Int(slot.dayOfWeek)
        scheduleFormSubject = slot.subjectLabel
        scheduleFormUnit = slot.unitLabel ?? ""
        scheduleFormStart = slot.startTime
        scheduleFormEnd = slot.endTime
        scheduleFormStartTimeValue = AppDateTimeSupport.time(from: slot.startTime, fallback: scheduleFormStartTimeValue)
        scheduleFormEndTimeValue = AppDateTimeSupport.time(from: slot.endTime, fallback: scheduleFormEndTimeValue)
        editingScheduleSlotId = usingLegacyWeeklySlots ? nil : slot.id
        editingScheduleSlotWeeklyTemplateId = slot.weeklyTemplateId?.int64Value
        scheduleError = ""
    }

    func duplicateScheduleSlot(_ slot: TeacherScheduleSlot) {
        scheduleFormGroupId = slot.schoolClassId
        scheduleFormDay = Int(slot.dayOfWeek)
        scheduleFormSubject = slot.subjectLabel
        scheduleFormUnit = slot.unitLabel ?? ""
        scheduleFormStart = slot.startTime
        scheduleFormEnd = slot.endTime
        scheduleFormStartTimeValue = AppDateTimeSupport.time(from: slot.startTime, fallback: scheduleFormStartTimeValue)
        scheduleFormEndTimeValue = AppDateTimeSupport.time(from: slot.endTime, fallback: scheduleFormEndTimeValue)
        editingScheduleSlotId = nil
        editingScheduleSlotWeeklyTemplateId = nil
        scheduleError = ""
    }

    func cancelScheduleSlotEditing() {
        editingScheduleSlotId = nil
        editingScheduleSlotWeeklyTemplateId = nil
        scheduleFormSubject = ""
        scheduleFormUnit = ""
        scheduleError = ""
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
                                selection: Binding<Int64?>(
                                    get: { selectedClassId },
                                    set: { selectedClassId = $0 }
                                )
                            ) {
                                Text("Todos").tag(nil as Int64?)
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
                            selection: Binding<Int64?>(
                                get: { vm.scheduleFormGroupId },
                                set: { vm.scheduleFormGroupId = $0 }
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
        .onChange(of: selectedClassId) { newValue in
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

#if os(macOS)
struct MacTeacherScheduleSettingsPanel: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @StateObject private var vm = TeacherScheduleSettingsViewModel()

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            summaryCard
            courseCard
            slotsCard

            MacAgendaCard {
                DisclosureGroup {
                    evaluationsContent
                        .padding(.top, 12)
                } label: {
                    MacAgendaDisclosureLabel(
                        title: "Periodos de evaluación",
                        subtitle: "\(vm.evaluationPeriods.count) periodos configurados"
                    )
                }
            }

            MacAgendaCard {
                DisclosureGroup {
                    courseColorsContent
                        .padding(.top, 12)
                } label: {
                    MacAgendaDisclosureLabel(
                        title: "Colores de cursos",
                        subtitle: "\(vm.groups.count) cursos disponibles"
                    )
                }
            }

            MacAgendaCard {
                DisclosureGroup {
                    nonTeachingContent
                        .padding(.top, 12)
                } label: {
                    MacAgendaDisclosureLabel(
                        title: "No lectivos detectados",
                        subtitle: "\(vm.nonTeachingEvents.count) eventos afectan al forecast"
                    )
                }
            }
        }
        .task {
            await vm.bind(bridge: bridge, selectedClassId: selectedClassId)
        }
        .onChange(of: selectedClassId) { _, newValue in
            Task { await vm.updateSelectedClass(newValue) }
        }
    }

    private var summaryCard: some View {
        MacAgendaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planificación docente")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("Horario, curso y calendario lectivo")
                            .font(.title3.weight(.semibold))
                        Text("La vista principal del planner consume esta agenda; aquí quedan las decisiones estructurales.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    MacClassPicker(
                        title: "Grupo en foco",
                        groups: vm.groups,
                        selection: $selectedClassId,
                        includesAll: true
                    )
                    .frame(width: 260)
                }

                if !vm.scheduleError.isEmpty {
                    Text(vm.scheduleError)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MacAppStyle.dangerTint)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    MacAgendaMetric(title: "Curso", value: "\(vm.scheduleStartDate) - \(vm.scheduleEndDate)")
                    MacAgendaMetric(title: "Días", value: "\(vm.activeWeekdays.count)")
                    MacAgendaMetric(title: "Franjas", value: "\(vm.effectiveScheduleSlots.count)")
                    MacAgendaMetric(title: "Evaluaciones", value: "\(vm.evaluationPeriods.count)")
                }
            }
        }
    }

    private var courseCard: some View {
        MacAgendaCard(title: "Curso", subtitle: "Nombre, rango y días lectivos que usará Planner.") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Nombre de agenda", text: $vm.scheduleName)
                    .textFieldStyle(.roundedBorder)

                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inicio")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        DatePicker("Inicio de curso", selection: $vm.scheduleStartDateValue, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fin")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        DatePicker("Fin de curso", selection: $vm.scheduleEndDateValue, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    Spacer()

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
    }

    private var slotsCard: some View {
        MacAgendaCard(title: "Franjas", subtitle: "Alta rápida arriba y listado persistente con acciones abajo.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    MacClassPicker(
                        title: "Grupo",
                        groups: vm.groups,
                        selection: $vm.scheduleFormGroupId,
                        includesAll: false
                    )
                    .frame(width: 240)

                    Picker("Día", selection: $vm.scheduleFormDay) {
                        ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                            Text(vm.dayLabel(for: day)).tag(day)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 12) {
                    TextField("Materia o bloque", text: $vm.scheduleFormSubject)
                        .textFieldStyle(.roundedBorder)
                    TextField("Unidad de referencia", text: $vm.scheduleFormUnit)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inicio")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        DatePicker("Inicio", selection: $vm.scheduleFormStartTimeValue, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fin")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        DatePicker("Fin", selection: $vm.scheduleFormEndTimeValue, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    Spacer()

                    if vm.isEditingScheduleSlot {
                        Button("Cancelar") {
                            vm.cancelScheduleSlotEditing()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(vm.isEditingScheduleSlot ? "Guardar franja" : "Añadir franja") {
                        Task { await vm.addScheduleSlot() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Franjas creadas")
                            .font(.headline)
                        Spacer()
                        Text(vm.usingLegacyWeeklySlots ? "Heredadas" : "\(vm.effectiveScheduleSlots.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    if vm.usingLegacyWeeklySlots {
                        Text("Estas franjas vienen del horario original. Al editar una se guardará como franja persistente de agenda.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if vm.effectiveScheduleSlots.isEmpty {
                        ContentUnavailableView(
                            "Sin franjas",
                            systemImage: "calendar.badge.clock",
                            description: Text("Añade la primera franja semanal para alimentar el planner.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 8) {
                                ForEach(vm.effectiveScheduleSlots, id: \.id) { slot in
                                    MacScheduleSlotRow(
                                        slot: slot,
                                        groupName: groupName(for: slot.schoolClassId),
                                        dayLabel: vm.dayLabel(for: Int(slot.dayOfWeek)),
                                        canDelete: !vm.usingLegacyWeeklySlots,
                                        onEdit: { vm.editScheduleSlot(slot) },
                                        onDuplicate: { vm.duplicateScheduleSlot(slot) },
                                        onDelete: {
                                            Task { await vm.deleteScheduleSlot(slot.id) }
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 140, maxHeight: 280)
                    }
                }
            }
        }
    }

    private var evaluationsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TextField("Nombre de la evaluación", text: $vm.evaluationFormName)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Inicio", selection: $vm.evaluationFormStartDateValue, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                DatePicker("Fin", selection: $vm.evaluationFormEndDateValue, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Button("Añadir periodo") {
                    Task { await vm.addEvaluationPeriod() }
                }
                .buttonStyle(.borderedProminent)
            }

            if vm.evaluationPeriods.isEmpty {
                ContentUnavailableView(
                    "Sin periodos",
                    systemImage: "flag.checkered",
                    description: Text("Crea evaluaciones para que el forecast calcule sesiones previstas.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.evaluationPeriods.sorted(by: { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }), id: \.id) { period in
                            MacEvaluationPeriodCard(
                                period: period,
                                rows: vm.filteredForecastRows.filter { $0.periodId == period.id },
                                onDelete: {
                                    Task { await vm.deleteEvaluationPeriod(period.id) }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 160, maxHeight: 320)
            }
        }
    }

    private var courseColorsContent: some View {
        Group {
            if vm.groups.isEmpty {
                ContentUnavailableView(
                    "Sin cursos",
                    systemImage: "paintpalette",
                    description: Text("Cuando haya grupos, podrás asignarles un color estable.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.groups, id: \.id) { group in
                            MacCourseColorRow(
                                groupName: group.name,
                                selectedHex: vm.colorHex(for: group.id),
                                onSelect: { hex in vm.saveColor(hex, for: group.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 120, maxHeight: 260)
            }
        }
    }

    private var nonTeachingContent: some View {
        Group {
            if vm.nonTeachingEvents.isEmpty {
                ContentUnavailableView(
                    "Sin no lectivos",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("No hay eventos detectados para el contexto actual.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.nonTeachingEvents, id: \.id) { event in
                            MacNonTeachingEventRow(
                                title: event.title,
                                dateText: nonTeachingSubtitle(event),
                                groupName: event.classId.flatMap { classId in
                                    vm.groups.first(where: { $0.id == classId.int64Value })?.name
                                } ?? "Todos"
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 120, maxHeight: 260)
            }
        }
    }

    private func groupName(for classId: Int64) -> String {
        vm.groups.first(where: { $0.id == classId })?.name ?? "Grupo \(classId)"
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

private struct MacAgendaCard<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacAgendaMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacAppStyle.subtleFill)
        )
    }
}

private struct MacAgendaDisclosureLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacClassPicker: View {
    let title: String
    let groups: [SchoolClass]
    @Binding var selection: Int64?
    var includesAll: Bool
    @State private var isPresented = false
    @State private var query = ""

    private var selectedLabel: String {
        if includesAll, selection == nil {
            return "Todos"
        }
        guard let selection,
              let group = groups.first(where: { $0.id == selection }) else {
            return title
        }
        return group.name
    }

    private var filteredGroups: [SchoolClass] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedLabel)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MacAppStyle.subtleFill)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Buscar...", text: $query)
                        .textFieldStyle(.roundedBorder)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if includesAll {
                                optionRow(title: "Todos", isSelected: selection == nil) {
                                    selection = nil
                                    isPresented = false
                                }
                            }

                            ForEach(filteredGroups, id: \.id) { group in
                                optionRow(title: group.name, isSelected: selection == group.id) {
                                    selection = group.id
                                    isPresented = false
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(width: 320, height: 280)
                }
                .padding(16)

                MacPopupActionBar(
                    title: nil,
                    onClose: { isPresented = false }
                )
            }
        }
    }

    private func optionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MacScheduleSlotRow: View {
    let slot: TeacherScheduleSlot
    let groupName: String
    let dayLabel: String
    let canDelete: Bool
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dayLabel) · \(slot.startTime)-\(slot.endTime)")
                    .font(.callout.weight(.semibold))
                Text(slotDetail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Editar", action: onEdit)
                .buttonStyle(.borderless)
            Button("Duplicar", action: onDuplicate)
                .buttonStyle(.borderless)
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Borrar franja")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacAppStyle.subtleFill)
        )
    }

    private var slotDetail: String {
        [groupName, slot.subjectLabel, slot.unitLabel]
            .compactMap { value in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
                return trimmed
            }
            .joined(separator: " · ")
    }
}

private struct MacEvaluationPeriodCard: View {
    let period: PlannerEvaluationPeriod
    let rows: [PlannerSessionForecast]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(period.name)
                        .font(.callout.weight(.semibold))
                    Text("\(period.startDateIso) - \(period.endDateIso)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Borrar periodo")
            }

            if rows.isEmpty {
                Text("Sin sesiones previstas para el contexto actual.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    MacCompactForecastRow(row: row)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacAppStyle.subtleFill)
        )
    }
}

private struct MacCompactForecastRow: View {
    let row: PlannerSessionForecast

    var body: some View {
        HStack {
            Text(row.className)
                .font(.caption.weight(.semibold))
            Spacer()
            Text("Prev. \(row.expectedSessions)")
            Text("Creadas \(row.plannedSessions)")
            Text("Delta \(row.remainingSessions)")
                .foregroundStyle(row.remainingSessions > 0 ? MacAppStyle.dangerTint : MacAppStyle.successTint)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
    }
}

private struct MacCourseColorRow: View {
    let groupName: String
    let selectedHex: String
    let onSelect: (String) -> Void
    @State private var showPalette = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: selectedHex))
                .frame(width: 14, height: 14)
            Text(groupName)
                .font(.callout.weight(.semibold))
            Spacer()
            Button("Cambiar") {
                showPalette.toggle()
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showPalette) {
                VStack(spacing: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 10), count: 4), spacing: 10) {
                        ForEach(EvaluationDesign.plannerCoursePalette, id: \.self) { hex in
                            Button {
                                onSelect(hex)
                                showPalette = false
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle()
                                            .stroke(selectedHex == hex ? Color.primary : Color.clear, lineWidth: 3)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .frame(width: 184)

                    MacPopupActionBar(
                        title: nil,
                        onClose: { showPalette = false }
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacAppStyle.subtleFill)
        )
    }
}

private struct MacNonTeachingEventRow: View {
    let title: String
    let dateText: String
    let groupName: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(dateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(groupName)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(MacAppStyle.subtleFill))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacAppStyle.subtleFill)
        )
    }
}
#endif
