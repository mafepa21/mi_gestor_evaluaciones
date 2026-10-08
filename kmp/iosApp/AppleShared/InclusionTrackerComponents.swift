import SwiftUI

// Componentes visuales compartidos de la pantalla «Inclusión».
//
// Los usan la pantalla real (`InclusionTrackerView`, datos del puente KMP) y la
// maqueta (`InclusionTrackerMockView`, datos en memoria, solo para #Preview).
// Son solo interfaz: reciben valores simples y devuelven acciones por closures,
// así que no conocen ni KMP ni la maqueta.
// Liquid Glass solo en el "chrome" (cabecera, franja de fases, avisos); las
// filas de tareas quedan sobre fondos sólidos del sistema.

// MARK: - Fechas

enum InclusionDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    static func short(_ date: Date) -> String {
        shortFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func days(from: Date, to: Date) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

// MARK: - Modelo de presentación

enum InclusionPhase: Int, CaseIterable, Identifiable {
    case septiembre, observar, evaluacionInicial, noviembre, diciembre

    var id: Int { rawValue }

    /// Cuándo ocurre, tal y como lo dice el manual.
    var whenLabel: String {
        switch self {
        case .septiembre: return "Septiembre"
        case .observar: return "Sep-Oct"
        case .evaluacionInicial: return "Evaluación inicial"
        case .noviembre: return "Noviembre"
        case .diciembre: return "Diciembre"
        }
    }

    /// Qué hay que hacer en esa fase.
    var actionLabel: String {
        switch self {
        case .septiembre: return "Recopilar"
        case .observar: return "Observar"
        case .evaluacionInicial: return "Decidir medidas"
        case .noviembre: return "Revisar + ITACA"
        case .diciembre: return "Cerrar antes de Navidad"
        }
    }

    var symbol: String {
        switch self {
        case .septiembre: return "tray.full"
        case .observar: return "eye"
        case .evaluacionInicial: return "checklist"
        case .noviembre: return "arrow.triangle.2.circlepath"
        case .diciembre: return "flag.checkered"
        }
    }

    var accessibleName: String { "\(whenLabel), \(actionLabel)" }
}

enum InclusionDeadlineStatus {
    case done, overdue, soon, normal

    var color: Color {
        switch self {
        case .overdue: return .red
        case .soon: return .orange
        case .done, .normal: return .secondary
        }
    }
}

/// Una tarea lista para pintar. Las acciones llegan ya cableadas.
struct InclusionTaskDisplay: Identifiable {
    let id: AnyHashable
    let title: String
    let due: Date
    let manualDue: Date
    let doneOn: Date?
    let isEdited: Bool
    let canReset: Bool
    let status: InclusionDeadlineStatus
    let onToggle: () -> Void
    let onSetDue: (Date) -> Void
    let onReset: () -> Void

    var isDone: Bool { doneOn != nil }
}

struct InclusionPhaseGroup: Identifiable {
    let phase: InclusionPhase
    let tasks: [InclusionTaskDisplay]

    var id: Int { phase.id }
}

// MARK: - Estilo: Liquid Glass con fallback

extension SupportMeasureLevelUI {
    /// Mismo criterio que la vista de grupo: Nivel IV índigo; Nivel III verde azulado.
    var inclusionColor: Color {
        switch self {
        case .iii: return .teal
        case .iv: return .indigo
        }
    }
}

private struct InclusionGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, macOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0.opacity(0.28)) } ?? Glass.regular
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    if let tint { shape.fill(tint.opacity(0.14)) }
                }
        }
    }
}

extension View {
    func inclusionGlass(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(InclusionGlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

/// Agrupa superficies glass relacionadas (iOS/macOS 26) o las deja tal cual.
struct InclusionGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

struct InclusionLevelChip: View {
    let level: SupportMeasureLevelUI

    var body: some View {
        Text(level.shortLabel)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(level.inclusionColor, in: Capsule())
            .accessibilityLabel(level.displayName)
    }
}

struct InclusionCountBadge: View {
    let count: Int
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label("\(count) \(text)", systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(count > 0 ? color : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .inclusionGlass(cornerRadius: 14, tint: count > 0 ? color : nil)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Cabecera del lateral

struct InclusionHeaderCard: View {
    let subtitle: String
    let overdueCount: Int
    let dueThisWeekCount: Int
    let initialEvaluationDate: Date
    let isLoading: Bool
    let canEditEvaluation: Bool
    /// Devuelve cuántas fechas se movieron, o `nil` si no se pudo guardar.
    let applyEvaluation: (Date) async -> Int?

    @State private var showingEvaluationDate = false

    var body: some View {
        InclusionGlassGroup(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inclusión")
                            .font(.title2.weight(.bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    InclusionCountBadge(count: overdueCount, text: overdueCount == 1 ? "vencida" : "vencidas",
                                        symbol: "exclamationmark.circle.fill", color: .red)
                    InclusionCountBadge(count: dueThisWeekCount, text: "esta semana",
                                        symbol: "clock.fill", color: .orange)
                }
                .redacted(reason: isLoading ? .placeholder : [])
                evaluationDateButton
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inclusionGlass(cornerRadius: 22)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var evaluationDateButton: some View {
        Button {
            showingEvaluationDate = true
        } label: {
            HStack {
                Label("Evaluación inicial", systemImage: "calendar.badge.clock")
                Spacer(minLength: 8)
                Text(InclusionDate.short(initialEvaluationDate))
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !canEditEvaluation)
        .accessibilityLabel("Fecha de evaluación inicial del grupo")
        .accessibilityValue(InclusionDate.short(initialEvaluationDate))
        .accessibilityHint("Abre un selector de fecha. Recalcula las tareas que dependen de ella.")
        .popover(isPresented: $showingEvaluationDate) {
            InclusionEvaluationDatePopover(initial: initialEvaluationDate, apply: applyEvaluation)
        }
    }
}

// MARK: - Fila de alumno (lateral)

struct InclusionStudentRowView: View {
    let name: String
    let level: SupportMeasureLevelUI?
    let done: Int
    let total: Int
    let overdue: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.headline)
                if let level { InclusionLevelChip(level: level) }
                Spacer(minLength: 0)
                if overdue > 0 {
                    Label("\(overdue)", systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                        .accessibilityLabel("\(overdue) \(overdue == 1 ? "tarea vencida" : "tareas vencidas")")
                }
            }
            HStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint((level ?? .iv).inclusionColor)
                    .frame(maxWidth: 90)
                Text("\(done) de \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "\(name), \($0.displayName)" } ?? name)
        .accessibilityValue("\(done) de \(total) tareas hechas" + (overdue > 0 ? ", \(overdue) vencidas" : ""))
    }
}

// MARK: - Detalle del alumno

struct InclusionStudentDetailView: View {
    let name: String
    let level: SupportMeasureLevelUI?
    let measuresSummary: String
    let done: Int
    let total: Int
    let groups: [InclusionPhaseGroup]
    let currentPhase: InclusionPhase
    let isLoading: Bool
    @Binding var showingAddTask: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let level { InclusionLevelChip(level: level) }
                        Text(measuresSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(done) de \(total) tareas hechas")
                        .font(.callout.weight(.semibold))
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.tasks) { task in
                        InclusionTaskRowView(task: task)
                    }
                } header: {
                    phaseHeader(group)
                }
            }
        }
        .redacted(reason: isLoading ? .placeholder : [])
        .disabled(isLoading)
        .safeAreaInset(edge: .top, spacing: 0) {
            InclusionPhaseStrip(current: currentPhase)
        }
        .navigationTitle(name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddTask = true
                } label: {
                    Label("Añadir tarea", systemImage: "plus")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Abre un formulario para crear una tarea para \(name)")
            }
        }
    }

    private func phaseHeader(_ group: InclusionPhaseGroup) -> some View {
        let doneCount = group.tasks.filter(\.isDone).count
        let isCurrent = group.phase == currentPhase
        return HStack(alignment: .firstTextBaseline) {
            Text("\(group.phase.whenLabel) · \(group.phase.actionLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if isCurrent {
                Text("Ahora")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 8)
            Text("\(doneCount) de \(group.tasks.count) hechas")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Franja de fases

struct InclusionPhaseStrip: View {
    let current: InclusionPhase

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            InclusionGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(InclusionPhase.allCases) { phase in
                        chip(for: phase)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fases del curso")
    }

    private func chip(for phase: InclusionPhase) -> some View {
        let isCurrent = phase == current
        let isPast = phase.rawValue < current.rawValue
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: isPast ? "checkmark.circle.fill" : phase.symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(phase.whenLabel)
                    .font(.caption.weight(.bold))
            }
            Text(phase.actionLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isPast ? Color.secondary : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 112, minHeight: 44, alignment: .leading)
        .inclusionGlass(cornerRadius: 14, tint: isCurrent ? .orange : nil)
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.accessibleName)
        .accessibilityValue(isCurrent ? "Fase actual" : (isPast ? "Pasada" : "Pendiente"))
    }
}

// MARK: - Fila de tarea

struct InclusionTaskRowView: View {
    let task: InclusionTaskDisplay
    @State private var showingDueEditor = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                task.onToggle()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(task.doneOn.map { "Hecha el \(InclusionDate.short($0))" } ?? "Pendiente")
            .accessibilityHint(task.isDone ? "Toca dos veces para desmarcarla" : "Toca dos veces para marcarla como hecha")
            .accessibilityAddTraits(.isToggle)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                    .frame(minHeight: 44, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let doneOn = task.doneOn {
                    Label("Hecha el \(InclusionDate.short(doneOn))", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                dueControl
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var dueControl: some View {
        let status = task.status
        return HStack(spacing: 8) {
            Button {
                showingDueEditor = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: status == .overdue ? "exclamationmark.circle.fill" : "calendar")
                        .imageScale(.small)
                    Text(dueText(status: status))
                        .fontWeight(status == .overdue || status == .soon ? .semibold : .regular)
                }
                .font(.subheadline)
                .foregroundStyle(status.color)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fecha de vencimiento: \(InclusionDate.short(task.due))")
            .accessibilityValue(accessibleStatus(status))
            .accessibilityHint("Abre un selector para cambiar la fecha")
            .popover(isPresented: $showingDueEditor) {
                InclusionDueDateEditor(task: task)
            }

            if task.isEdited {
                Text("editada")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private func dueText(status: InclusionDeadlineStatus) -> String {
        let date = InclusionDate.short(task.due)
        switch status {
        case .overdue: return "Venció el \(date)"
        case .soon, .normal: return "Vence el \(date)"
        case .done: return "Vencía el \(date)"
        }
    }

    private func accessibleStatus(_ status: InclusionDeadlineStatus) -> String {
        switch status {
        case .overdue: return "Vencida"
        case .soon: return "Vence esta semana"
        case .done: return "Tarea hecha"
        case .normal: return task.isEdited ? "Fecha editada" : "En plazo"
        }
    }
}

// MARK: - Editor de fecha de una tarea

struct InclusionDueDateEditor: View {
    let task: InclusionTaskDisplay
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    init(task: InclusionTaskDisplay) {
        self.task = task
        _draft = State(initialValue: task.due)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fecha de vencimiento")
                .font(.headline)
            Text(task.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DatePicker("Fecha", selection: $draft, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "es_ES"))
                .labelsHidden()

            Button {
                task.onReset()
                dismiss()
            } label: {
                Label("Restablecer al \(InclusionDate.short(task.manualDue)) (manual)", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!task.canReset)

            HStack {
                Button("Cancelar", role: .cancel) { dismiss() }
                    .frame(minHeight: 44)
                Spacer()
                Button("Guardar") {
                    task.onSetDue(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 360)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Fecha de la evaluación inicial

struct InclusionEvaluationDatePopover: View {
    let initial: Date
    let apply: (Date) async -> Int?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date
    @State private var movedCount: Int?

    init(initial: Date, apply: @escaping (Date) async -> Int?) {
        self.initial = initial
        self.apply = apply
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evaluación inicial del grupo")
                .font(.headline)
            Text("Al cambiarla se recalculan las tareas que dependen de ella. Las que ya editaste a mano no se mueven.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Fecha", selection: $draft, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "es_ES"))
                .labelsHidden()
            if let movedCount {
                Label("\(movedCount) \(movedCount == 1 ? "fecha recalculada" : "fechas recalculadas")",
                      systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cerrar", role: .cancel) { dismiss() }
                    .frame(minHeight: 44)
                Spacer()
                Button("Aplicar") {
                    Task { movedCount = await apply(draft) }
                }
                .keyboardShortcut(.defaultAction)
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 360)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Añadir tarea

struct InclusionAddTaskSheet: View {
    let studentName: String
    let onAdd: (String, InclusionPhase, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var phase: InclusionPhase = .observar
    @State private var due: Date

    init(studentName: String, today: Date, onAdd: @escaping (String, InclusionPhase, Date) -> Void) {
        self.studentName = studentName
        self.onAdd = onAdd
        _due = State(initialValue: InclusionDate.adding(days: 7, to: today))
    }

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarea para \(studentName)") {
                    TextField("Título", text: $title)
                    Picker("Fase", selection: $phase) {
                        ForEach(InclusionPhase.allCases) { Text("\($0.whenLabel) · \($0.actionLabel)").tag($0) }
                    }
                    DatePicker("Vence el", selection: $due, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_ES"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Añadir tarea")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        onAdd(title.trimmingCharacters(in: .whitespacesAndNewlines), phase, due)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

// MARK: - Banner de error

struct InclusionErrorBanner: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar aviso")
        }
        .padding(.leading, 14)
        .padding(.vertical, 2)
        .inclusionGlass(cornerRadius: 18, tint: .red)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error al guardar")
    }
}
