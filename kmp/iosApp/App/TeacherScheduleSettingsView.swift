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
                endTime: scheduleFormEnd
            )
            scheduleFormSubject = ""
            scheduleFormUnit = ""
            scheduleError = ""
            await reload()
        } catch {
            scheduleError = error.localizedDescription
        }
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
        .onChange(of: selectedClassId) { _, newValue in
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
