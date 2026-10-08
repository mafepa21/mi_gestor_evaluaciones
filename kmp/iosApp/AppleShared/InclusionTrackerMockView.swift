import SwiftUI

// MAQUETA de la pantalla «Inclusión»: seguimiento de plazos de las tareas del
// manual para el alumnado con medidas de Nivel III y IV.
//
// Es solo interfaz: datos de ejemplo en memoria, sin persistencia ni KMP. Se
// conserva para los #Preview; la pantalla real es `InclusionTrackerView` y las
// piezas visuales viven en `InclusionTrackerComponents.swift`.

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

extension InclusionDeadlineStatus {
    /// "Esta semana" = los próximos 7 días a partir de hoy (incluido hoy).
    static func of(_ task: InclusionTask, today: Date) -> InclusionDeadlineStatus {
        if task.isDone { return .done }
        let delta = InclusionDate.days(from: today, to: task.due)
        if delta < 0 { return .overdue }
        if delta <= 7 { return .soon }
        return .normal
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

// MARK: - Pantalla de la maqueta

struct InclusionTrackerMockView: View {
    @StateObject private var store: InclusionMockStore
    @State private var selection: UUID?
    @State private var showingAddTask = false
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
        .overlay(alignment: .bottom) {
            if let message = store.errorMessage {
                InclusionErrorBanner(message: message) { store.errorMessage = nil }
            }
        }
        .animation(.snappy, value: store.errorMessage)
        .sheet(isPresented: $showingAddTask) {
            if let student = selectedStudent {
                InclusionAddTaskSheet(studentName: student.name, today: store.today) { title, phase, due in
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
                        let progress = store.progress(for: student.id)
                        InclusionStudentRowView(name: student.name, level: student.level,
                                                done: progress.done, total: progress.total,
                                                overdue: store.overdueCount(for: student.id))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            InclusionHeaderCard(
                subtitle: "\(store.groupName) · curso 2026-2027",
                overdueCount: store.overdueCount,
                dueThisWeekCount: store.dueThisWeekCount,
                initialEvaluationDate: store.initialEvaluationDate,
                isLoading: store.isLoading,
                canEditEvaluation: store.state != .empty,
                applyEvaluation: { store.setInitialEvaluationDate($0) }
            )
        }
        .navigationTitle("Inclusión")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) { debugMenu }
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

    @ViewBuilder
    private var detail: some View {
        if let student = selectedStudent {
            let progress = store.progress(for: student.id)
            InclusionStudentDetailView(
                name: student.name,
                level: student.level,
                measuresSummary: student.measuresSummary,
                done: progress.done,
                total: progress.total,
                groups: groups(for: student),
                currentPhase: store.currentPhase,
                isLoading: store.isLoading,
                showingAddTask: $showingAddTask
            )
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

    private func groups(for student: InclusionStudent) -> [InclusionPhaseGroup] {
        InclusionPhase.allCases.compactMap { phase in
            let tasks = store.tasks(for: student.id, in: phase)
            guard !tasks.isEmpty else { return nil }
            return InclusionPhaseGroup(phase: phase, tasks: tasks.map { task in
                InclusionTaskDisplay(
                    id: task.id,
                    title: task.title,
                    due: task.due,
                    manualDue: task.manualDue,
                    doneOn: task.doneOn,
                    isEdited: task.isEdited,
                    canReset: task.isEdited,
                    status: InclusionDeadlineStatus.of(task, today: store.today),
                    onToggle: { store.toggleDone(task.id) },
                    onSetDue: { store.setDue(task.id, to: $0) },
                    onReset: { store.resetDue(task.id) }
                )
            })
        }
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
