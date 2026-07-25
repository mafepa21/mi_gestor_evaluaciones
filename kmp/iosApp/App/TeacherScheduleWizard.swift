import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit
#if os(macOS)
import AppKit
#endif

enum TeacherScheduleWizardStep: Int, CaseIterable, Identifiable {
    case course
    case slots
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .course: return "Curso"
        case .slots: return "Horario"
        case .finish: return "Terminado"
        }
    }

    var systemImage: String {
        switch self {
        case .course: return "calendar"
        case .slots: return "clock"
        case .finish: return "checkmark.circle"
        }
    }
}

private enum TeacherScheduleWizardExtra: String, Identifiable {
    case evaluations
    case units
    case colors
    case nonTeaching

    var id: String { rawValue }

    var title: String {
        switch self {
        case .evaluations: return "Evaluaciones"
        case .units: return "Unidades didácticas"
        case .colors: return "Colores"
        case .nonTeaching: return "No lectivos"
        }
    }

    var subtitle: String {
        switch self {
        case .evaluations: return "Periodos evaluativos y cómputo de sesiones."
        case .units: return "Renombra o elimina las unidades creadas al planificar."
        case .colors: return "Un color por curso para reconocerlo de un vistazo."
        case .nonTeaching: return "Festivos y días no lectivos detectados en el calendario."
        }
    }

    var systemImage: String {
        switch self {
        case .evaluations: return "chart.bar.doc.horizontal"
        case .units: return "folder"
        case .colors: return "paintpalette"
        case .nonTeaching: return "calendar.badge.minus"
        }
    }
}

/// Configurador de la agenda docente, rediseñado como asistente progresivo:
/// una tarea por pantalla (Curso → Horario → Terminado) en vez de un único
/// scroll con siete secciones encima a la vez. Sustituye a los antiguos
/// `MacTeacherScheduleSettingsPanel`/`TeacherScheduleSettingsPanel`: el
/// primero amontonaba las mismas siete secciones en tarjetas apiladas
/// (algunas colapsadas en `DisclosureGroup`, la mayoría no); el segundo
/// las mostraba TODAS siempre expandidas y, además, no estaba conectado a
/// ningún punto de entrada real en la app — código muerto.
///
/// Curso y Horario son los dos pasos obligatorios (lo mínimo para que
/// Planner tenga algo que mostrar). Evaluaciones, Unidades didácticas,
/// Colores y No lectivos son refinamientos opcionales: viven detrás de
/// tarjetas en el paso "Terminado", nunca forzados en el camino principal.
struct TeacherScheduleWizard: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    /// `nil` cuando el asistente vive embebido en Ajustes; presente cuando
    /// se presenta como sheet rápido desde Planner (añade el botón "Cerrar").
    var onClose: (() -> Void)? = nil

    @StateObject private var vm = TeacherScheduleSettingsViewModel()
    @State private var step: TeacherScheduleWizardStep = .course
    @State private var isScheduleImporterPresented = false
    @State private var pendingScheduleSlotDeletionId: Int64?
    @State private var activeExtra: TeacherScheduleWizardExtra?
    @State private var scheduleExportError = ""

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusMessages
                    stepContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            wizardFooter
        }
        .task {
            await vm.bind(bridge: bridge, selectedClassId: selectedClassId)
        }
        .appOnChange(of: selectedClassId) { newValue in
            Task { await vm.updateSelectedClass(newValue) }
        }
        .fileImporter(
            isPresented: $isScheduleImporterPresented,
            allowedContentTypes: [.xlsx],
            allowsMultipleSelection: false
        ) { result in
            Task {
                switch result {
                case .success(let urls):
                    await vm.previewScheduleImport(urls.first.map(Result.success) ?? .failure(AppleSpreadsheetReaderError.unreadableFile))
                case .failure(let error):
                    await vm.previewScheduleImport(.failure(error))
                }
            }
        }
        .sheet(item: $vm.scheduleImportPreview) { preview in
            ScheduleImportPreviewSheet(
                preview: preview,
                knownGroupNames: vm.knownGroupNamesByCode(),
                isImporting: vm.isImportingSchedule
            ) { mode in
                Task { await vm.importSchedulePreview(preview, emptySlotMode: mode) }
            }
        }
        .sheet(item: $activeExtra) { extra in
            extraSheet(extra)
        }
        .alert(
            "Eliminar franja",
            isPresented: Binding(
                get: { pendingScheduleSlotDeletionId != nil },
                set: { if !$0 { pendingScheduleSlotDeletionId = nil } }
            )
        ) {
            Button("Cancelar", role: .cancel) { pendingScheduleSlotDeletionId = nil }
            Button("Eliminar franja y sesiones futuras", role: .destructive) {
                guard let slotId = pendingScheduleSlotDeletionId else { return }
                pendingScheduleSlotDeletionId = nil
                Task { await vm.deleteScheduleSlot(slotId) }
            }
        } message: {
            Text("Eliminar esta franja también quitará del Planner semanal las sesiones futuras generadas desde ella.")
        }
    }

    // MARK: - Chrome del asistente

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurar mi horario")
                        .font(.title2.weight(.bold))
                    Text(stepSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Label("Cerrar", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(TeacherScheduleWizardStep.allCases) { candidate in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { step = candidate }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: candidate.systemImage)
                            Text(candidate.title)
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(candidate == step ? EvaluationDesign.accent : EvaluationDesign.surfaceSoft)
                        )
                        .foregroundStyle(candidate == step ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(24)
    }

    private var stepSubtitle: String {
        switch step {
        case .course: return "Paso 1 de 3 · Nombre, fechas y días lectivos del curso"
        case .slots: return "Paso 2 de 3 · Las franjas que consume el Planner semanal"
        case .finish: return "Paso 3 de 3 · Listo. Afina evaluaciones, unidades, colores o no lectivos si quieres"
        }
    }

    @ViewBuilder
    private var wizardFooter: some View {
        HStack {
            if step != .course {
                Button("Atrás") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = TeacherScheduleWizardStep(rawValue: step.rawValue - 1) ?? .course
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            TeacherScheduleSaveStateLine(state: vm.scheduleSaveState)

            Spacer()

            switch step {
            case .course:
                Button("Continuar a Horario") {
                    withAnimation(.easeInOut(duration: 0.2)) { step = .slots }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .slots:
                Button("Continuar a Terminado") {
                    withAnimation(.easeInOut(duration: 0.2)) { step = .finish }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .finish:
                if let onClose {
                    Button("Terminar") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if !scheduleExportError.isEmpty {
            Text(scheduleExportError)
                .font(.caption.weight(.semibold))
                .foregroundStyle(EvaluationDesign.danger)
        }
        if !vm.scheduleError.isEmpty {
            Text(vm.scheduleError)
                .font(.caption.weight(.semibold))
                .foregroundStyle(EvaluationDesign.danger)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EvaluationDesign.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        if !vm.scheduleImportStatusMessage.isEmpty {
            Text(vm.scheduleImportStatusMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(EvaluationDesign.success)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EvaluationDesign.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .course: courseStep
        case .slots: slotsStep
        case .finish: finishStep
        }
    }

    // MARK: - Paso 1 · Curso

    private var courseStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            courseHeroCard
            courseFineTuneCard

            if vm.groups.count > 1 {
                PremiumCard.glass {
                    VStack(alignment: .leading, spacing: 12) {
                        EvaluationSectionTitle(
                            eyebrow: "Contexto",
                            title: "Grupo en foco",
                            subtitle: "Filtra el asistente a un grupo concreto, o déjalo en \"Todos\" para verlos todos a la vez."
                        )
                        Picker(
                            "Grupo en foco",
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
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }
        }
    }

    /// El rango de fechas es el único dato que de verdad importa en este
    /// paso (todo lo demás son ajustes finos), así que es lo único que
    /// recibe peso visual pesado: una cifra grande + una línea de tiempo,
    /// en vez de competir con el campo de nombre y los date picker dentro
    /// de la misma tarjeta plana. Los presets resuelven directamente el
    /// caso común (curso natural, 1 sept - 30 jun): un toque en vez de
    /// manipular dos selectores de fecha.
    private var courseHeroCard: some View {
        PremiumCard.glass {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("CURSO ESCOLAR")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Text(courseYearLabel)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(EvaluationDesign.accent)
                        .monospacedDigit()
                }

                VStack(spacing: 6) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [EvaluationDesign.accent.opacity(0.35), EvaluationDesign.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 10)
                    HStack {
                        Text("SEPTIEMBRE")
                        Spacer()
                        Text("JUNIO")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    presetChip(academicYearBounds(offsetYears: 0))
                    presetChip(academicYearBounds(offsetYears: 1))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func presetChip(_ bounds: AcademicYearBounds) -> some View {
        let isSelected = isMatchingPreset(bounds)
        return Button {
            vm.scheduleStartDateValue = bounds.start
            vm.scheduleEndDateValue = bounds.end
        } label: {
            VStack(spacing: 2) {
                Text(bounds.label)
                    .font(.callout.weight(.bold))
                Text("1 sept – 30 jun")
                    .font(.caption2)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? EvaluationDesign.accent : EvaluationDesign.surfaceSoft)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    /// Selectores finos + días lectivos + nombre: el ajuste, no la decisión
    /// principal. Deliberadamente más pequeño y por debajo del hero.
    private var courseFineTuneCard: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 16) {
                    labeledDatePicker("Inicio de curso", selection: $vm.scheduleStartDateValue)
                    labeledDatePicker("Fin de curso", selection: $vm.scheduleEndDateValue)
                    Spacer()
                    Button("Guardar") {
                        Task { await vm.saveTeacherSchedule() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.scheduleSaveState == .saving)
                }

                Divider()

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

                Divider()

                HStack(spacing: 10) {
                    Text("Nombre")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Nombre de agenda", text: $vm.scheduleName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private struct AcademicYearBounds {
        let start: Date
        let end: Date
        let label: String
    }

    /// `startYear` es septiembre→junio: si hoy es antes de agosto, el curso
    /// "actual" empezó el septiembre anterior. `offsetYears` mueve el preset
    /// al curso siguiente sin repetir el cálculo.
    private func academicYearBounds(offsetYears: Int) -> AcademicYearBounds {
        let calendar = Calendar(identifier: .iso8601)
        let today = Date()
        let currentYear = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)
        let baseStartYear = currentMonth >= 8 ? currentYear : currentYear - 1
        let startYear = baseStartYear + offsetYears
        let endYear = startYear + 1
        let start = calendar.date(from: DateComponents(year: startYear, month: 9, day: 1)) ?? today
        let end = calendar.date(from: DateComponents(year: endYear, month: 6, day: 30)) ?? today
        return AcademicYearBounds(start: start, end: end, label: "\(startYear)–\(endYear)")
    }

    private func isMatchingPreset(_ bounds: AcademicYearBounds) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(vm.scheduleStartDateValue, inSameDayAs: bounds.start)
            && calendar.isDate(vm.scheduleEndDateValue, inSameDayAs: bounds.end)
    }

    private var courseYearLabel: String {
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: vm.scheduleStartDateValue)
        let endYear = calendar.component(.year, from: vm.scheduleEndDateValue)
        return startYear == endYear ? "\(startYear)" : "\(startYear)–\(endYear)"
    }

    // MARK: - Paso 2 · Franjas

    private var slotsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            PremiumCard.glass {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        EvaluationSectionTitle(
                            eyebrow: "Horario fijo",
                            title: "Franjas semanales",
                            subtitle: "Cada franja alimenta el tablero semanal del Planner y el cómputo de sesiones por evaluación."
                        )
                        Spacer()
                        Button {
                            isScheduleImporterPresented = true
                        } label: {
                            Label("Importar", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        exportButton
                    }

                    if !vm.effectiveScheduleSlots.isEmpty {
                        ScheduleWeekGridView(
                            entries: scheduleGridEntries,
                            activeWeekdays: Array(vm.activeWeekdays),
                            dayLabel: vm.dayLabel(for:),
                            compact: true
                        )
                    }

                    slotEditorForm

                    if vm.effectiveScheduleSlots.isEmpty {
                        Text("Todavía no hay franjas definidas.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Divider()
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
    }

    private var slotEditorForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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
                .frame(minWidth: 140)

                Picker("Día", selection: $vm.scheduleFormDay) {
                    ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { day in
                        Text(vm.dayLabel(for: day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 90)
            }

            HStack(spacing: 12) {
                TextField("Materia o bloque", text: $vm.scheduleFormSubject)
                    .textFieldStyle(.roundedBorder)
                TextField("Unidad de referencia", text: $vm.scheduleFormUnit)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .bottom, spacing: 12) {
                labeledTimePicker("Inicio", selection: $vm.scheduleFormStartTimeValue)
                labeledTimePicker("Fin", selection: $vm.scheduleFormEndTimeValue)

                Button(vm.editingScheduleSlotId == nil ? "Añadir franja" : "Guardar franja") {
                    Task { await vm.addScheduleSlot() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.scheduleFormGroupId == nil || vm.scheduleSaveState == .saving)

                if vm.editingScheduleSlotId != nil {
                    Button("Cancelar edición") {
                        vm.cancelEditingScheduleSlot()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func slotRow(_ slot: TeacherScheduleSlot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(vm.dayLabel(for: Int(slot.dayOfWeek))) · \(slot.startTime)-\(slot.endTime)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                let slotLines: [String] = [
                    vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                    slot.subjectLabel,
                    slot.unitLabel
                ]
                .compactMap { value in
                    let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value
                    guard let raw, !raw.isEmpty else { return nil }
                    return raw
                }
                Text(slotLines.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.usingLegacyWeeklySlots {
                Button {
                    vm.beginEditingScheduleSlot(slot)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    pendingScheduleSlotDeletionId = slot.id
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 8)
    }

    private var scheduleGridEntries: [ScheduleWeekGridView.Entry] {
        vm.effectiveScheduleSlots.map { slot in
            ScheduleWeekGridView.Entry(
                id: slot.id,
                dayOfWeek: Int(slot.dayOfWeek),
                startTime: slot.startTime,
                endTime: slot.endTime,
                subject: slot.subjectLabel,
                groupName: vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                unit: slot.unitLabel
            )
        }
    }

    private var schedulePDFPage: some View {
        ScheduleWeekGridPage(
            title: vm.scheduleName.isEmpty ? "Horario" : vm.scheduleName,
            subtitle: selectedClassId
                .flatMap { id in vm.groups.first(where: { $0.id == id })?.name }
                .map { "Grupo: \($0)" } ?? "Todos los grupos",
            entries: scheduleGridEntries,
            activeWeekdays: Array(vm.activeWeekdays),
            dayLabel: vm.dayLabel(for:)
        )
    }

    @ViewBuilder
    private var exportButton: some View {
        #if os(macOS)
        Button {
            exportSchedulePDFMac()
        } label: {
            Label("Exportar", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .disabled(vm.effectiveScheduleSlots.isEmpty)
        #else
        if !vm.effectiveScheduleSlots.isEmpty, let url = exportedScheduleURL {
            ShareLink(item: url) {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        } else {
            Label("Exportar", systemImage: "square.and.arrow.up")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        #endif
    }

    #if os(macOS)
    /// Genera el PDF y lo abre con la app por omisión (Vista Previa): el
    /// gesto que espera un profesor en septiembre, horario en papel en un
    /// clic.
    private func exportSchedulePDFMac() {
        scheduleExportError = ""
        guard let url = ScheduleGridPDFRenderer.writeToTemporaryFile(
            page: schedulePDFPage,
            suggestedName: vm.scheduleName.isEmpty ? "horario" : vm.scheduleName
        ) else {
            scheduleExportError = "No se pudo generar el PDF del horario."
            return
        }
        NSWorkspace.shared.open(url)
    }
    #else
    private var exportedScheduleURL: URL? {
        ScheduleGridPDFRenderer.writeToTemporaryFile(
            page: schedulePDFPage,
            suggestedName: vm.scheduleName.isEmpty ? "horario" : vm.scheduleName
        )
    }
    #endif

    // MARK: - Paso 3 · Terminado

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            PremiumCard.glass {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(EvaluationDesign.success)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tu horario está listo")
                                .font(.title3.weight(.bold))
                            Text("Planner ya puede planificar sesiones sobre esta agenda.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 18) {
                        finishMetric("Curso", "\(vm.scheduleStartDate) – \(vm.scheduleEndDate)")
                        finishMetric("Franjas", "\(vm.effectiveScheduleSlots.count)")
                        finishMetric("Evaluaciones", "\(vm.evaluationPeriods.count)")
                        finishMetric("No lectivos", "\(vm.nonTeachingEvents.count)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Afinar más (opcional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach([
                        TeacherScheduleWizardExtra.evaluations,
                        .units,
                        .colors,
                        .nonTeaching
                    ]) { extra in
                        Button {
                            activeExtra = extra
                        } label: {
                            extraCard(extra)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func finishMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold))
                .monospacedDigit()
        }
    }

    private func extraCard(_ extra: TeacherScheduleWizardExtra) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: extra.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EvaluationDesign.accent)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(extra.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(extra.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func extraSheet(_ extra: TeacherScheduleWizardExtra) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(extra.title).font(.title3.weight(.bold))
                    Text(extra.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    activeExtra = nil
                } label: {
                    Label("Cerrar", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                extraContent(extra)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private func extraContent(_ extra: TeacherScheduleWizardExtra) -> some View {
        switch extra {
        case .evaluations: evaluationsContent
        case .units: teachingUnitsContent
        case .colors: colorsContent
        case .nonTeaching: nonTeachingContent
        }
    }

    private var evaluationsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Nombre de la evaluación", text: $vm.evaluationFormName)
                    .textFieldStyle(.roundedBorder)
                labeledDatePicker("Inicio", selection: $vm.evaluationFormStartDateValue)
                labeledDatePicker("Fin", selection: $vm.evaluationFormEndDateValue)
                Button(vm.editingEvaluationPeriodId == nil ? "Añadir" : "Guardar") {
                    Task { await vm.addEvaluationPeriod() }
                }
                .buttonStyle(.borderedProminent)
                if vm.editingEvaluationPeriodId != nil {
                    Button("Cancelar") {
                        vm.cancelEditingEvaluationPeriod()
                    }
                    .buttonStyle(.bordered)
                }
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
                            Button {
                                vm.beginEditingEvaluationPeriod(period)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
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
                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var teachingUnitsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Se crean automáticamente al planificar una sesión. Aquí puedes renombrarlas o eliminarlas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if vm.teachingUnits.isEmpty {
                Text("Aún no hay unidades didácticas creadas.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.teachingUnits, id: \.id) { unit in
                    HStack {
                        Text(unit.name)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button {
                            vm.pendingRenameTeachingUnit = unit
                            vm.renameTeachingUnitDraft = unit.name
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            vm.pendingDeleteTeachingUnitId = unit.id
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .alert(
            "Renombrar unidad",
            isPresented: Binding(
                get: { vm.pendingRenameTeachingUnit != nil },
                set: { if !$0 { vm.pendingRenameTeachingUnit = nil } }
            )
        ) {
            TextField("Nombre", text: Binding(
                get: { vm.renameTeachingUnitDraft },
                set: { vm.renameTeachingUnitDraft = $0 }
            ))
            Button("Guardar") {
                if let unit = vm.pendingRenameTeachingUnit {
                    Task { await vm.renameTeachingUnit(unit, newName: vm.renameTeachingUnitDraft) }
                }
                vm.pendingRenameTeachingUnit = nil
            }
            Button("Cancelar", role: .cancel) {
                vm.pendingRenameTeachingUnit = nil
            }
        }
        .confirmationDialog(
            "Eliminar unidad didáctica",
            isPresented: Binding(
                get: { vm.pendingDeleteTeachingUnitId != nil },
                set: { if !$0 { vm.pendingDeleteTeachingUnitId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let unitId = vm.pendingDeleteTeachingUnitId {
                    Task { await vm.deleteTeachingUnit(unitId) }
                }
                vm.pendingDeleteTeachingUnitId = nil
            }
            Button("Cancelar", role: .cancel) {
                vm.pendingDeleteTeachingUnitId = nil
            }
        } message: {
            Text("Si hay sesiones planificadas usando esta unidad, no se podrá eliminar hasta que las reasignes o borres.")
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
                                .background(EvaluationDesign.surfaceSoft, in: Capsule(style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func nonTeachingSubtitle(_ event: CalendarEvent) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(event.startAt.toEpochMilliseconds()) / 1000)
        let end = Date(timeIntervalSince1970: TimeInterval(event.endAt.toEpochMilliseconds()) / 1000)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Helpers de formulario

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

    private func labeledTimePicker(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DatePicker(label, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }
}

private struct TeacherScheduleSaveStateLine: View {
    let state: PlannerSaveState

    var body: some View {
        if !message.isEmpty {
            HStack(spacing: 8) {
                if state == .saving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: iconName)
                        .foregroundStyle(tint)
                }
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    private var message: String {
        switch state {
        case .idle: return ""
        case .saving: return "Guardando…"
        case .saved: return "Guardado"
        case .failed(let text): return text
        }
    }

    private var iconName: String {
        switch state {
        case .failed: return "exclamationmark.triangle.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .failed: return EvaluationDesign.danger
        case .saving: return EvaluationDesign.accent
        default: return EvaluationDesign.success
        }
    }
}
