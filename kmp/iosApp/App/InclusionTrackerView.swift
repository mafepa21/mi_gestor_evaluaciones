import SwiftUI
import MiGestorKit

/// Pantalla «Inclusión»: seguimiento de plazos del Manual de Inclusión del grupo
/// seleccionado. La lógica (plantillas, fechas, estados) vive en KMP; aquí solo
/// se carga, se pinta y se reenvían las acciones del docente.
///
/// Layout adaptativo: ancho regular (iPad, Mac) = lista de alumnos + detalle;
/// compacto (iPhone, iPad estrecho) = lista que empuja el detalle.
/// Las piezas visuales están en `AppleShared/InclusionTrackerComponents.swift`.

// MARK: - Estado

@MainActor
final class InclusionTrackerStore: ObservableObject {
    static let saveErrorMessage = "No se pudo guardar el cambio. No se ha aplicado nada. Inténtalo de nuevo."
    static let loadErrorMessage = "No se pudo cargar el seguimiento de inclusión."
    static let refreshErrorMessage = "El cambio se guardó, pero no se pudo actualizar la lista. Vuelve a abrir la pantalla."

    @Published private(set) var board: InclusionBoardSnapshot?
    @Published private(set) var isLoading = false
    /// Fallo al cargar sin nada que mostrar: pantalla de error con «Reintentar».
    @Published private(set) var loadFailed = false
    /// Aviso en banner (fallo al guardar o al refrescar).
    @Published var errorMessage: String?
    private(set) var today = Date()

    /// Responde si la respuesta de una carga es todavía válida (cambio de grupo).
    private let gate = InclusionLoadGate()

    /// El store sobrevive a la pantalla: al salir se olvidan avisos y fallos para no
    /// enseñarlos al volver.
    func resetTransientState() {
        errorMessage = nil
        loadFailed = false
    }

    func load(bridge: KmpBridge, classId: Int64?) async {
        guard let classId else {
            board = nil
            loadFailed = false
            isLoading = false
            return
        }
        if board?.classId != classId { board = nil }
        loadFailed = false
        isLoading = board == nil
        let now = Date()
        do {
            let loaded = try await bridge.loadInclusionBoard(classId: classId, today: now, gate: gate)
            guard let loaded else { return } // llegó otro grupo mientras cargaba
            today = now
            board = loaded
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard gate.currentClassId == classId else { return }
            isLoading = false
            if board == nil {
                loadFailed = true
            } else {
                errorMessage = Self.refreshErrorMessage
            }
        }
    }

    /// Ejecuta un cambio y refresca. Si falla, no se toca nada y se avisa.
    @discardableResult
    func perform(bridge: KmpBridge, classId: Int64, _ change: () async throws -> Void) async -> Bool {
        do {
            try await change()
        } catch {
            errorMessage = Self.saveErrorMessage
            return false
        }
        errorMessage = nil
        await load(bridge: bridge, classId: classId)
        return true
    }

    /// Fase actual según hoy y la evaluación inicial del grupo.
    var currentPhase: InclusionPhase {
        guard let board else { return .septiembre }
        let startYear = Int(board.schoolYear.prefix(4)) ?? InclusionDate.calendar.component(.year, from: today)
        let sep16 = InclusionDate.make(startYear, 9, 16)
        let nov1 = InclusionDate.make(startYear, 11, 1)
        let dec1 = InclusionDate.make(startYear, 12, 1)
        if today < sep16 { return .septiembre }
        if today < board.initialEvaluationDate { return .observar }
        if today < nov1 { return .evaluacionInicial }
        if today < dec1 { return .noviembre }
        return .diciembre
    }
}

private extension InclusionPhaseUI {
    var display: InclusionPhase {
        switch self {
        case .septiembre: return .septiembre
        case .observar: return .observar
        case .evaluacionInicial: return .evaluacionInicial
        case .noviembre: return .noviembre
        case .diciembre: return .diciembre
        }
    }
}

private extension InclusionPhase {
    var ui: InclusionPhaseUI {
        switch self {
        case .septiembre: return .septiembre
        case .observar: return .observar
        case .evaluacionInicial: return .evaluacionInicial
        case .noviembre: return .noviembre
        case .diciembre: return .diciembre
        }
    }
}

private extension InclusionDeadlineStatusUI {
    var display: InclusionDeadlineStatus {
        switch self {
        case .done: return .done
        case .overdue: return .overdue
        case .soon: return .soon
        case .normal: return .normal
        }
    }
}

// MARK: - Pantalla

struct InclusionTrackerView: View {
    let bridge: KmpBridge
    @Binding var selectedClassId: Int64?

    init(bridge: KmpBridge, selectedClassId: Binding<Int64?>) {
        self.bridge = bridge
        self._selectedClassId = selectedClassId
        self._store = ObservedObject(wrappedValue: WorkspaceScreenMemory.shared.inclusion(bridge: bridge))
    }

    /// Vive en `WorkspaceScreenMemory`: al volver se ve el tablero anterior al instante.
    @ObservedObject private var store: InclusionTrackerStore
    @State private var selection: Int64?
    @State private var showingAddTask = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// El tablero solo vale si es del grupo elegido: al volver tras cambiar de grupo
    /// en otra pantalla no se enseña, ni un fotograma, el del grupo anterior.
    private var currentBoard: InclusionBoardSnapshot? {
        guard let board = store.board, board.classId == selectedClassId else { return nil }
        return board
    }

    private var isLoadingCurrent: Bool {
        store.isLoading || (selectedClassId != nil && currentBoard == nil && !store.loadFailed)
    }

    private var isWide: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        content
            .overlay(alignment: .bottom) {
                if let message = store.errorMessage {
                    InclusionErrorBanner(message: message) { store.errorMessage = nil }
                }
            }
            .animation(.snappy, value: store.errorMessage)
            .onDisappear { store.resetTransientState() }
            .task(id: selectedClassId) {
                selection = nil
                await store.load(bridge: bridge, classId: selectedClassId)
                selectFirstIfWide()
            }
            .sheet(isPresented: $showingAddTask) {
                if let board = currentBoard, let classId = selectedClassId {
                    InclusionAddTaskSheet(
                        recipients: board.students.map { InclusionTaskRecipient(id: $0.id, name: $0.name) },
                        initialID: selection,
                        today: store.today
                    ) { title, phase, due, studentIds in
                        Task {
                            // Una sola transacción; al terminar el store recarga el tablero.
                            await store.perform(bridge: bridge, classId: classId) {
                                try await bridge.addInclusionTasks(
                                    studentIds: studentIds, title: title, phase: phase.ui, due: due
                                )
                            }
                        }
                    }
                }
            }
    }

    private var selectedStudent: InclusionStudentSnapshot? {
        currentBoard?.students.first { $0.id == selection }
    }

    /// En pantallas anchas se abre con el primer alumno. En compacto no se fuerza,
    /// para no saltarse la lista.
    private func selectFirstIfWide() {
        guard isWide, selection == nil else { return }
        selection = currentBoard?.students.first?.id
    }

    // MARK: Estructura

    @ViewBuilder
    private var content: some View {
        if selectedClassId == nil {
            ContentUnavailableView(
                "Elige un grupo",
                systemImage: "person.2.badge.gearshape",
                description: Text("Selecciona un grupo para ver el seguimiento de inclusión de su alumnado.")
            )
        } else if store.loadFailed {
            ContentUnavailableView {
                Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(InclusionTrackerStore.loadErrorMessage)
            } actions: {
                Button("Reintentar") {
                    Task { await store.load(bridge: bridge, classId: selectedClassId) }
                }
                .frame(minHeight: 44)
            }
        } else if isWide {
            HStack(spacing: 0) {
                NavigationStack { listPane }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
                Divider()
                NavigationStack { detailPane }
                    .frame(maxWidth: .infinity)
            }
        } else {
            NavigationStack {
                listPane
                    .navigationDestination(for: Int64.self) { studentId in
                        if let student = currentBoard?.students.first(where: { $0.id == studentId }) {
                            detailView(for: student)
                        }
                    }
            }
        }
    }

    // MARK: Lista

    private var groupName: String {
        bridge.classes.first { $0.id == selectedClassId }?.name ?? "Grupo"
    }

    private var listPane: some View {
        let board = currentBoard
        return Group {
            if isLoadingCurrent {
                List {
                    ForEach(0..<4, id: \.self) { _ in
                        InclusionStudentRowView(name: "Nombre Apellido", level: .iii, done: 0, total: 8, overdue: 0)
                    }
                }
                .redacted(reason: .placeholder)
                .disabled(true)
                .overlay { ProgressView().controlSize(.large) }
            } else if let board, board.students.isEmpty {
                ContentUnavailableView(
                    "Ningún alumno con medidas de nivel III o IV",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("Cuando registres medidas en la ficha de un alumno, aparecerá aquí con sus plazos.")
                )
            } else if let board {
                studentList(board)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("Inclusión")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func studentList(_ board: InclusionBoardSnapshot) -> some View {
        if isWide {
            List(selection: $selection) {
                ForEach(board.students) { student in
                    row(student).tag(student.id)
                }
            }
        } else {
            List {
                ForEach(board.students) { student in
                    NavigationLink(value: student.id) { row(student) }
                }
            }
        }
    }

    private func row(_ student: InclusionStudentSnapshot) -> some View {
        InclusionStudentRowView(
            name: student.name,
            level: student.level,
            done: student.doneCount,
            total: student.tasks.count,
            overdue: student.overdueCount
        )
    }

    private var header: some View {
        let board = currentBoard
        return InclusionHeaderCard(
            subtitle: "\(groupName) · curso \(board?.schoolYear ?? "")",
            overdueCount: board?.overdueCount ?? 0,
            dueThisWeekCount: board?.dueThisWeekCount ?? 0,
            initialEvaluationDate: board?.initialEvaluationDate ?? Date(),
            isLoading: isLoadingCurrent,
            canEditEvaluation: !(board?.students.isEmpty ?? true),
            applyEvaluation: { date in
                guard let classId = selectedClassId else { return nil }
                var moved: Int?
                let ok = await store.perform(bridge: bridge, classId: classId) {
                    moved = try await bridge.setInclusionInitialEvaluation(classId: classId, date: date)
                }
                return ok ? moved : nil
            }
        )
    }

    // MARK: Detalle

    @ViewBuilder
    private var detailPane: some View {
        if let student = selectedStudent {
            detailView(for: student)
        } else if currentBoard?.students.isEmpty == true {
            ContentUnavailableView(
                "Ningún alumno con medidas de nivel III o IV",
                systemImage: "person.crop.circle.badge.checkmark"
            )
        } else {
            ContentUnavailableView("Elige un alumno", systemImage: "person.text.rectangle",
                                   description: Text("Verás sus tareas agrupadas por fase."))
        }
    }

    private func detailView(for student: InclusionStudentSnapshot) -> some View {
        InclusionStudentDetailView(
            name: student.name,
            level: student.level,
            measuresSummary: student.measuresSummary,
            done: student.doneCount,
            total: student.tasks.count,
            groups: groups(for: student),
            currentPhase: store.currentPhase,
            isLoading: isLoadingCurrent,
            showingAddTask: $showingAddTask
        )
        .onAppear { selection = student.id }
    }

    private func groups(for student: InclusionStudentSnapshot) -> [InclusionPhaseGroup] {
        guard let classId = selectedClassId else { return [] }
        return InclusionPhase.allCases.compactMap { phase in
            let tasks = student.tasks
                .filter { $0.phase.display == phase }
                .sorted { $0.due < $1.due }
            guard !tasks.isEmpty else { return nil }
            return InclusionPhaseGroup(phase: phase, tasks: tasks.map { task in
                InclusionTaskDisplay(
                    id: task.id,
                    title: task.title,
                    due: task.due,
                    manualDue: task.manualDue,
                    doneOn: task.doneOn,
                    isEdited: task.isEdited,
                    canReset: task.canReset,
                    status: task.status.display,
                    onToggle: {
                        Task { await store.perform(bridge: bridge, classId: classId) {
                            try await bridge.toggleInclusionTask(id: task.id)
                        } }
                    },
                    onSetDue: { date in
                        Task { await store.perform(bridge: bridge, classId: classId) {
                            try await bridge.setInclusionTaskDue(id: task.id, classId: classId, to: date)
                        } }
                    },
                    onReset: {
                        Task { await store.perform(bridge: bridge, classId: classId) {
                            try await bridge.resetInclusionTaskDue(id: task.id, classId: classId)
                        } }
                    }
                )
            })
        }
    }
}
