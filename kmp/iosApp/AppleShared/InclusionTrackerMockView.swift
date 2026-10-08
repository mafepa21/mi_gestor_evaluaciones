import SwiftUI

// MAQUETA de la pantalla «Inclusión»: seguimiento de plazos de las tareas del
// manual para el alumnado con medidas de Nivel III y IV.
//
// Es solo interfaz: datos de ejemplo en memoria, sin persistencia ni KMP.
// Reutiliza `SupportMeasureLevelUI` (SupportMeasureShared.swift) para el nivel.
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

// MARK: - Modelo de la maqueta

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

/// Cómo se calcula la fecha del manual de una tarea.
enum InclusionDueRule: Hashable {
    case fixed
    /// N días después de la fecha de evaluación inicial del grupo.
    case afterInitialEvaluation(days: Int)
}

struct InclusionStudent: Identifiable, Hashable {
    let id: UUID
    let name: String
    let level: SupportMeasureLevelUI
    let measuresSummary: String
}

struct InclusionTask: Identifiable, Hashable {
    let id: UUID
    let studentID: UUID
    var phase: InclusionPhase
    var title: String
    var rule: InclusionDueRule
    /// Fecha que dice el manual (se recalcula si depende de la evaluación inicial).
    var manualDue: Date
    /// Fecha vigente (la que ha dejado el docente).
    var due: Date
    var doneOn: Date?

    var isDone: Bool { doneOn != nil }
    var isEdited: Bool { !InclusionDate.calendar.isDate(due, inSameDayAs: manualDue) }
}

enum InclusionDeadlineStatus {
    case done, overdue, soon, normal

    /// "Esta semana" = los próximos 7 días a partir de hoy (incluido hoy).
    static func of(_ task: InclusionTask, today: Date) -> InclusionDeadlineStatus {
        if task.isDone { return .done }
        let delta = InclusionDate.days(from: today, to: task.due)
        if delta < 0 { return .overdue }
        if delta <= 7 { return .soon }
        return .normal
    }

    var color: Color {
        switch self {
        case .overdue: return .red
        case .soon: return .orange
        case .done, .normal: return .secondary
        }
    }
}

enum InclusionMockState: String, CaseIterable, Identifiable {
    case data = "Con datos"
    case loading = "Cargando"
    case empty = "Vacío"
    case saveError = "Error al guardar"

    var id: String { rawValue }
}

@MainActor
final class InclusionMockStore: ObservableObject {
    static let saveErrorMessage = "No se pudo guardar el cambio. No se ha aplicado nada. Inténtalo de nuevo."

    let today: Date
    let groupName = "2º ESO B"

    @Published private(set) var students: [InclusionStudent] = []
    @Published private(set) var tasks: [InclusionTask] = []
    @Published private(set) var initialEvaluationDate: Date
    @Published var errorMessage: String?
    @Published var state: InclusionMockState {
        didSet { applyState() }
    }

    init(state: InclusionMockState = .data, today: Date = InclusionDate.make(2026, 10, 8)) {
        self.today = today
        self.state = state
        self.initialEvaluationDate = InclusionDate.make(2026, 10, 22)
        applyState()
    }

    private func applyState() {
        errorMessage = (state == .saveError) ? Self.saveErrorMessage : nil
        switch state {
        case .data, .saveError:
            loadSamples()
        case .loading:
            loadSamples()
        case .empty:
            students = []
            tasks = []
        }
    }

    // MARK: Consultas

    var isLoading: Bool { state == .loading }

    func tasks(for studentID: UUID) -> [InclusionTask] {
        tasks.filter { $0.studentID == studentID }
    }

    func tasks(for studentID: UUID, in phase: InclusionPhase) -> [InclusionTask] {
        tasks(for: studentID)
            .filter { $0.phase == phase }
            .sorted { $0.due < $1.due }
    }

    func progress(for studentID: UUID) -> (done: Int, total: Int) {
        let list = tasks(for: studentID)
        return (list.filter(\.isDone).count, list.count)
    }

    func overdueCount(for studentID: UUID) -> Int {
        tasks(for: studentID).filter { InclusionDeadlineStatus.of($0, today: today) == .overdue }.count
    }

    var overdueCount: Int {
        tasks.filter { InclusionDeadlineStatus.of($0, today: today) == .overdue }.count
    }

    var dueThisWeekCount: Int {
        tasks.filter { InclusionDeadlineStatus.of($0, today: today) == .soon }.count
    }

    /// Fase actual según la fecha de hoy y la evaluación inicial del grupo.
    var currentPhase: InclusionPhase {
        let sep16 = InclusionDate.make(2026, 9, 16)
        let nov1 = InclusionDate.make(2026, 11, 1)
        let dec1 = InclusionDate.make(2026, 12, 1)
        if today < sep16 { return .septiembre }
        if today < initialEvaluationDate { return .observar }
        if today < nov1 { return .evaluacionInicial }
        if today < dec1 { return .noviembre }
        return .diciembre
    }

    // MARK: Acciones (todas pasan por `commit` para simular el fallo al guardar)

    private func commit(_ change: () -> Void) {
        guard state != .saveError else {
            errorMessage = Self.saveErrorMessage
            return
        }
        errorMessage = nil
        change()
    }

    func toggleDone(_ taskID: UUID) {
        commit {
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            tasks[index].doneOn = tasks[index].isDone ? nil : today
        }
    }

    func setDue(_ taskID: UUID, to date: Date) {
        commit {
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            tasks[index].due = date
        }
    }

    func resetDue(_ taskID: UUID) {
        commit {
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            tasks[index].due = tasks[index].manualDue
        }
    }

    func addTask(studentID: UUID, title: String, phase: InclusionPhase, due: Date) {
        commit {
            tasks.append(InclusionTask(
                id: UUID(), studentID: studentID, phase: phase, title: title,
                rule: .fixed, manualDue: due, due: due, doneOn: nil
            ))
        }
    }

    /// Cambia la evaluación inicial y recalcula las tareas que dependen de ella.
    /// Las que el docente ya editó conservan su fecha; solo cambia la del manual.
    /// Devuelve cuántas fechas vigentes se movieron.
    @discardableResult
    func setInitialEvaluationDate(_ date: Date) -> Int {
        var moved = 0
        commit {
            initialEvaluationDate = date
            for index in tasks.indices {
                guard case let .afterInitialEvaluation(days) = tasks[index].rule else { continue }
                let wasEdited = tasks[index].isEdited
                let newManual = InclusionDate.adding(days: days, to: date)
                tasks[index].manualDue = newManual
                if !wasEdited {
                    tasks[index].due = newManual
                    moved += 1
                }
            }
        }
        return moved
    }

    // MARK: Datos de ejemplo

    private func loadSamples() {
        let ana = InclusionStudent(id: UUID(), name: "Ana R.", level: .iv, measuresSummary: "ACIS Matemáticas + AyL")
        let luis = InclusionStudent(id: UUID(), name: "Luis M.", level: .iii, measuresSummary: "Acceso: mesa adaptada")
        let sara = InclusionStudent(id: UUID(), name: "Sara P.", level: .iv, measuresSummary: "Flexibilización")
        students = [ana, luis, sara]
        initialEvaluationDate = InclusionDate.make(2026, 10, 22)
        let evalDate = initialEvaluationDate

        func fixed(_ student: InclusionStudent, _ phase: InclusionPhase, _ title: String,
                   _ month: Int, _ day: Int, doneOn: Date? = nil) -> InclusionTask {
            let due = InclusionDate.make(2026, month, day)
            return InclusionTask(id: UUID(), studentID: student.id, phase: phase, title: title,
                                 rule: .fixed, manualDue: due, due: due, doneOn: doneOn)
        }
        func afterEval(_ student: InclusionStudent, _ title: String, days: Int) -> InclusionTask {
            let due = InclusionDate.adding(days: days, to: evalDate)
            return InclusionTask(id: UUID(), studentID: student.id, phase: .evaluacionInicial, title: title,
                                 rule: .afterInitialEvaluation(days: days), manualDue: due, due: due, doneOn: nil)
        }
        let d = InclusionDate.make

        var list: [InclusionTask] = []
        // Ana R.
        list += [
            fixed(ana, .septiembre, "Carpeta roja preparada", 9, 15, doneOn: d(2026, 9, 11)),
            fixed(ana, .septiembre, "Doc1 firmado (de otro curso)", 9, 15, doneOn: d(2026, 9, 14)),
            fixed(ana, .observar, "Doc7 PAP", 10, 6),
            fixed(ana, .observar, "PAPACIS Matemáticas", 10, 12),
            fixed(ana, .observar, "PAPAyL", 10, 12),
            afterEval(ana, "Doc4 tras la evaluación inicial", days: 3),
            fixed(ana, .noviembre, "Registrar medidas en ITACA", 11, 20),
            fixed(ana, .diciembre, "Subir documentos firmados", 12, 18)
        ]
        // Luis M.
        list += [
            fixed(luis, .septiembre, "Carpeta roja preparada", 9, 15, doneOn: d(2026, 9, 12)),
            fixed(luis, .observar, "Doc2", 10, 3),
            fixed(luis, .observar, "Observar uso de la mesa adaptada", 10, 16),
            afterEval(luis, "Doc4 tras la evaluación inicial", days: 3),
            fixed(luis, .noviembre, "Registrar medidas en ITACA", 11, 20),
            fixed(luis, .diciembre, "Subir documentos firmados", 12, 18)
        ]
        // Sara P.
        list += [
            fixed(sara, .septiembre, "Carpeta roja preparada", 9, 15, doneOn: d(2026, 9, 10)),
            fixed(sara, .septiembre, "Doc1 firmado", 9, 15, doneOn: d(2026, 9, 13)),
            fixed(sara, .observar, "Doc7 PAP", 10, 14),
            afterEval(sara, "Doc4 tras la evaluación inicial", days: 3),
            fixed(sara, .noviembre, "Registrar medidas en ITACA", 11, 20),
            fixed(sara, .diciembre, "Subir documentos firmados", 12, 18)
        ]
        tasks = list
    }
}

// MARK: - Estilo: Liquid Glass con fallback

private extension SupportMeasureLevelUI {
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

private extension View {
    func inclusionGlass(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(InclusionGlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

/// Agrupa superficies glass relacionadas (iOS/macOS 26) o las deja tal cual.
private struct InclusionGlassGroup<Content: View>: View {
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

private struct InclusionLevelChip: View {
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

private struct InclusionCountBadge: View {
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

// MARK: - Pantalla

struct InclusionTrackerMockView: View {
    @StateObject private var store: InclusionMockStore
    @State private var selection: UUID?
    @State private var showingAddTask = false
    @State private var showingEvaluationDate = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(state: InclusionMockState = .data) {
        _store = StateObject(wrappedValue: InclusionMockStore(state: state))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .overlay(alignment: .bottom) { errorBanner }
        .animation(.snappy, value: store.errorMessage)
        .sheet(isPresented: $showingAddTask) {
            if let student = selectedStudent {
                InclusionAddTaskSheet(student: student, today: store.today) { title, phase, due in
                    store.addTask(studentID: student.id, title: title, phase: phase, due: due)
                }
            }
        }
        .onAppear(perform: selectFirstIfWide)
        .onChange(of: store.state) { _, _ in
            selection = nil
            selectFirstIfWide()
        }
    }

    private var selectedStudent: InclusionStudent? {
        store.students.first { $0.id == selection }
    }

    /// En pantallas anchas se abre con el primer alumno. En iPhone no se fuerza,
    /// para no saltarse la lista (navegación en dos pasos).
    private func selectFirstIfWide() {
        #if os(macOS)
        if selection == nil { selection = store.students.first?.id }
        #else
        if selection == nil, horizontalSizeClass == .regular { selection = store.students.first?.id }
        #endif
    }

    // MARK: Lateral

    private var sidebar: some View {
        Group {
            if store.state == .empty {
                ContentUnavailableView(
                    "Ningún alumno con medidas de nivel III o IV",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("Cuando registres medidas en la ficha de un alumno, aparecerá aquí con sus plazos.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(store.students) { student in
                        InclusionStudentRow(student: student, store: store)
                            .tag(student.id)
                    }
                }
                .redacted(reason: store.isLoading ? .placeholder : [])
                .disabled(store.isLoading)
                .overlay {
                    if store.isLoading { ProgressView().controlSize(.large) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("Inclusión")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) { debugMenu }
        }
    }

    private var header: some View {
        InclusionGlassGroup(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inclusión")
                            .font(.title2.weight(.bold))
                        Text("\(store.groupName) · curso 2026-2027")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    InclusionCountBadge(count: store.overdueCount, text: store.overdueCount == 1 ? "vencida" : "vencidas",
                                        symbol: "exclamationmark.circle.fill", color: .red)
                    InclusionCountBadge(count: store.dueThisWeekCount, text: "esta semana",
                                        symbol: "clock.fill", color: .orange)
                }
                .redacted(reason: store.isLoading ? .placeholder : [])
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
                Text(InclusionDate.short(store.initialEvaluationDate))
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
        .disabled(store.isLoading || store.state == .empty)
        .accessibilityLabel("Fecha de evaluación inicial del grupo")
        .accessibilityValue(InclusionDate.short(store.initialEvaluationDate))
        .accessibilityHint("Abre un selector de fecha. Recalcula las tareas que dependen de ella.")
        .popover(isPresented: $showingEvaluationDate) {
            InclusionEvaluationDatePopover(store: store)
        }
    }

    private var debugMenu: some View {
        Menu {
            Picker("Estado de la maqueta", selection: $store.state) {
                ForEach(InclusionMockState.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label("Estado (depuración)", systemImage: "ladybug")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Estado de la maqueta, solo depuración")
    }

    // MARK: Detalle

    @ViewBuilder
    private var detail: some View {
        if let student = selectedStudent {
            InclusionStudentDetail(student: student, store: store, showingAddTask: $showingAddTask)
        } else if store.state == .empty {
            ContentUnavailableView(
                "Ningún alumno con medidas de nivel III o IV",
                systemImage: "person.crop.circle.badge.checkmark"
            )
        } else {
            ContentUnavailableView("Elige un alumno", systemImage: "person.text.rectangle",
                                   description: Text("Verás sus tareas agrupadas por fase."))
        }
    }

    // MARK: Banner de error

    @ViewBuilder
    private var errorBanner: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    store.errorMessage = nil
                } label: {
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
}

// MARK: - Fila de alumno (lateral)

private struct InclusionStudentRow: View {
    let student: InclusionStudent
    @ObservedObject var store: InclusionMockStore

    var body: some View {
        let progress = store.progress(for: student.id)
        let overdue = store.overdueCount(for: student.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(student.name)
                    .font(.headline)
                InclusionLevelChip(level: student.level)
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
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(student.level.inclusionColor)
                    .frame(maxWidth: 90)
                Text("\(progress.done) de \(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(student.name), \(student.level.displayName)")
        .accessibilityValue("\(progress.done) de \(progress.total) tareas hechas" + (overdue > 0 ? ", \(overdue) vencidas" : ""))
    }
}

// MARK: - Detalle del alumno

private struct InclusionStudentDetail: View {
    let student: InclusionStudent
    @ObservedObject var store: InclusionMockStore
    @Binding var showingAddTask: Bool

    var body: some View {
        let progress = store.progress(for: student.id)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        InclusionLevelChip(level: student.level)
                        Text(student.measuresSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(progress.done) de \(progress.total) tareas hechas")
                        .font(.callout.weight(.semibold))
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            ForEach(InclusionPhase.allCases) { phase in
                let phaseTasks = store.tasks(for: student.id, in: phase)
                if !phaseTasks.isEmpty {
                    Section {
                        ForEach(phaseTasks) { task in
                            InclusionTaskRow(task: task, store: store)
                        }
                    } header: {
                        phaseHeader(phase, tasks: phaseTasks)
                    }
                }
            }
        }
        .redacted(reason: store.isLoading ? .placeholder : [])
        .disabled(store.isLoading)
        .safeAreaInset(edge: .top, spacing: 0) {
            InclusionPhaseStrip(current: store.currentPhase)
        }
        .navigationTitle(student.name)
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
                .accessibilityHint("Abre un formulario para crear una tarea para \(student.name)")
            }
        }
    }

    private func phaseHeader(_ phase: InclusionPhase, tasks: [InclusionTask]) -> some View {
        let done = tasks.filter(\.isDone).count
        let isCurrent = phase == store.currentPhase
        return HStack(alignment: .firstTextBaseline) {
            Text("\(phase.whenLabel) · \(phase.actionLabel)")
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
            Text("\(done) de \(tasks.count) hechas")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Franja de fases

private struct InclusionPhaseStrip: View {
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

private struct InclusionTaskRow: View {
    let task: InclusionTask
    @ObservedObject var store: InclusionMockStore
    @State private var showingDueEditor = false

    var body: some View {
        let status = InclusionDeadlineStatus.of(task, today: store.today)
        HStack(alignment: .top, spacing: 4) {
            Button {
                store.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(task.isDone ? "Hecha el \(InclusionDate.short(task.doneOn ?? store.today))" : "Pendiente")
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
                dueControl(status: status)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func dueControl(status: InclusionDeadlineStatus) -> some View {
        HStack(spacing: 8) {
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
                InclusionDueDateEditor(task: task, store: store)
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

private struct InclusionDueDateEditor: View {
    let task: InclusionTask
    @ObservedObject var store: InclusionMockStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    init(task: InclusionTask, store: InclusionMockStore) {
        self.task = task
        self.store = store
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
                store.resetDue(task.id)
                dismiss()
            } label: {
                Label("Restablecer al \(InclusionDate.short(task.manualDue)) (manual)", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!task.isEdited)

            HStack {
                Button("Cancelar", role: .cancel) { dismiss() }
                    .frame(minHeight: 44)
                Spacer()
                Button("Guardar") {
                    store.setDue(task.id, to: draft)
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

private struct InclusionEvaluationDatePopover: View {
    @ObservedObject var store: InclusionMockStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date = Date()
    @State private var movedCount: Int?

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
                    movedCount = store.setInitialEvaluationDate(draft)
                }
                .keyboardShortcut(.defaultAction)
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 360)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
        .onAppear { draft = store.initialEvaluationDate }
    }
}

// MARK: - Añadir tarea

private struct InclusionAddTaskSheet: View {
    let student: InclusionStudent
    let today: Date
    let onAdd: (String, InclusionPhase, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var phase: InclusionPhase = .observar
    @State private var due: Date

    init(student: InclusionStudent, today: Date, onAdd: @escaping (String, InclusionPhase, Date) -> Void) {
        self.student = student
        self.today = today
        self.onAdd = onAdd
        _due = State(initialValue: InclusionDate.adding(days: 7, to: today))
    }

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarea para \(student.name)") {
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

// MARK: - Previews

#Preview("iPhone · con datos") {
    InclusionTrackerMockView()
        .environment(\.horizontalSizeClass, .compact)
        .frame(width: 393, height: 852)
}

#Preview("iPad · con datos") {
    InclusionTrackerMockView()
        .environment(\.horizontalSizeClass, .regular)
        .frame(width: 1024, height: 768)
}

#Preview("Mac · con datos") {
    InclusionTrackerMockView()
        .frame(width: 960, height: 640)
}

#Preview("iPad · cargando") {
    InclusionTrackerMockView(state: .loading)
        .frame(width: 1024, height: 768)
}

#Preview("iPhone · vacío") {
    InclusionTrackerMockView(state: .empty)
        .environment(\.horizontalSizeClass, .compact)
        .frame(width: 393, height: 852)
}

#Preview("iPad · error al guardar") {
    InclusionTrackerMockView(state: .saveError)
        .environment(\.horizontalSizeClass, .regular)
        .frame(width: 1024, height: 768)
}
