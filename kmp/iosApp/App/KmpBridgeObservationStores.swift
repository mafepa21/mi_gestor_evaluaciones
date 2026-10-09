import Combine
import Foundation
import SwiftUI
import MiGestorKit

extension ObservableObject where Self: AnyObject {
    /// Reenvía un @Published del bridge al store solo cuando el valor cambia de verdad
    /// (los tipos Kotlin comparan con `isEqual`/`equals`). Usa `weak self` para no crear ciclos de retención.
    @MainActor
    fileprivate func bridgeSink<Value>(
        _ publisher: Published<Value>.Publisher,
        _ keyPath: ReferenceWritableKeyPath<Self, Value>,
        into cancellables: inout Set<AnyCancellable>,
        isEqual: @escaping (Value, Value) -> Bool
    ) {
        publisher
            .removeDuplicates(by: isEqual)
            .sink { [weak self] value in self?[keyPath: keyPath] = value }
            .store(in: &cancellables)
    }

    @MainActor
    fileprivate func bridgeSink<Value: Equatable>(
        _ publisher: Published<Value>.Publisher,
        _ keyPath: ReferenceWritableKeyPath<Self, Value>,
        into cancellables: inout Set<AnyCancellable>
    ) {
        bridgeSink(publisher, keyPath, into: &cancellables, isEqual: ==)
    }
}

@MainActor
final class NotebookBridgeStore: ObservableObject {
    @Published private(set) var classes: [SchoolClass] = []
    @Published private(set) var notebookState: NotebookUiState = NotebookUiStateLoading()
    @Published private(set) var notebookStructureState = NotebookStructureState(
        classId: nil,
        tabs: [],
        columns: [],
        categories: [],
        workGroups: [],
        workGroupMembers: [],
        isLoading: true,
        errorMessage: nil
    )
    @Published private(set) var notebookRowsState = NotebookRowsState(
        classId: nil,
        rows: [],
        numericDrafts: [:],
        textDrafts: [:],
        checkDrafts: [:],
        isLoading: true,
        errorMessage: nil
    )
    @Published private(set) var notebookSelectionState = NotebookSelectionState(
        selectedColumnIds: [],
        isColumnSelectionMode: false,
        activeCell: nil,
        activeCellEditor: nil,
        isLoading: true,
        errorMessage: nil
    )
    @Published private(set) var notebookSaveState: NotebookViewModelSaveState = NotebookViewModelSaveState.saved
    @Published private(set) var notebookSplitSaveState = NotebookSaveState(
        state: NotebookViewModelSaveState.saved,
        isDirty: false,
        isSaving: false,
        isSaved: true
    )
    @Published private(set) var notebookInspectorState = NotebookInspectorState(
        rubricEvaluationTarget: nil,
        activeCellEditor: nil,
        activeCell: nil,
        isLoading: true,
        errorMessage: nil
    )
    @Published private(set) var notebookAverageState = NotebookAverageState(
        classId: nil,
        averagesByStudentId: [:],
        explanationsByStudentId: [:],
        isLoading: true,
        errorMessage: nil
    )
    @Published private(set) var rubricEvaluationState: RubricEvaluationUiState = RubricEvaluationUiState.companion.default()
    @Published private(set) var isNotebookRubricAutoAdvanceActive = false
    @Published private(set) var showingBulkRubricEvaluation = false
    @Published private(set) var syncPendingChanges = 0

    private weak var bridge: KmpBridge?
    private var cancellables = Set<AnyCancellable>()

    func bind(to bridge: KmpBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
        cancellables.removeAll()

        classes = bridge.classes
        notebookState = bridge.notebookState
        notebookStructureState = bridge.notebookStructureState
        notebookRowsState = bridge.notebookRowsState
        notebookSelectionState = bridge.notebookSelectionState
        notebookSaveState = bridge.notebookSaveState
        notebookSplitSaveState = bridge.notebookSplitSaveState
        notebookInspectorState = bridge.notebookInspectorState
        notebookAverageState = bridge.notebookAverageState
        rubricEvaluationState = bridge.rubricEvaluationState
        isNotebookRubricAutoAdvanceActive = bridge.isNotebookRubricAutoAdvanceActive
        showingBulkRubricEvaluation = bridge.showingBulkRubricEvaluation
        syncPendingChanges = bridge.syncPendingChanges

        bridgeSink(bridge.$classes, \.classes, into: &cancellables)
        bridgeSink(bridge.$notebookState, \.notebookState, into: &cancellables) {
            ($0 as AnyObject).isEqual($1 as AnyObject)
        }
        bridgeSink(bridge.$notebookStructureState, \.notebookStructureState, into: &cancellables)
        bridgeSink(bridge.$notebookRowsState, \.notebookRowsState, into: &cancellables)
        bridgeSink(bridge.$notebookSelectionState, \.notebookSelectionState, into: &cancellables)
        bridgeSink(bridge.$notebookSaveState, \.notebookSaveState, into: &cancellables)
        bridgeSink(bridge.$notebookSplitSaveState, \.notebookSplitSaveState, into: &cancellables)
        bridgeSink(bridge.$notebookInspectorState, \.notebookInspectorState, into: &cancellables)
        bridgeSink(bridge.$notebookAverageState, \.notebookAverageState, into: &cancellables)
        bridgeSink(bridge.$rubricEvaluationState, \.rubricEvaluationState, into: &cancellables)
        bridgeSink(bridge.$isNotebookRubricAutoAdvanceActive, \.isNotebookRubricAutoAdvanceActive, into: &cancellables)
        bridgeSink(bridge.$showingBulkRubricEvaluation, \.showingBulkRubricEvaluation, into: &cancellables)
        bridgeSink(bridge.$syncPendingChanges, \.syncPendingChanges, into: &cancellables)
    }
}

@MainActor
final class DashboardBridgeStore: ObservableObject {
    @Published private(set) var classes: [SchoolClass] = []
    @Published private(set) var studentsInClass: [Student] = []
    @Published private(set) var dashboardSnapshot: DashboardSnapshot?
    @Published private(set) var syncStatusMessage = "Sync local inactivo"
    @Published private(set) var syncPendingChanges = 0
    @Published private(set) var syncLastRunAt: Date?
    @Published private(set) var pairedSyncHost: String?

    private weak var bridge: KmpBridge?
    private var cancellables = Set<AnyCancellable>()

    func bind(to bridge: KmpBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
        cancellables.removeAll()

        classes = bridge.classes
        studentsInClass = bridge.studentsInClass
        dashboardSnapshot = bridge.dashboardSnapshot
        syncStatusMessage = bridge.syncStatusMessage
        syncPendingChanges = bridge.syncPendingChanges
        syncLastRunAt = bridge.syncLastRunAt
        pairedSyncHost = bridge.pairedSyncHost

        bridgeSink(bridge.$classes, \.classes, into: &cancellables)
        bridgeSink(bridge.$studentsInClass, \.studentsInClass, into: &cancellables)
        bridgeSink(bridge.$dashboardSnapshot, \.dashboardSnapshot, into: &cancellables)
        bridgeSink(bridge.$syncStatusMessage, \.syncStatusMessage, into: &cancellables)
        bridgeSink(bridge.$syncPendingChanges, \.syncPendingChanges, into: &cancellables)
        bridgeSink(bridge.$syncLastRunAt, \.syncLastRunAt, into: &cancellables)
        bridgeSink(bridge.$pairedSyncHost, \.pairedSyncHost, into: &cancellables)
    }
}

@MainActor
final class StudentsBridgeStore: ObservableObject {
    @Published private(set) var classes: [SchoolClass] = []
    @Published private(set) var studentsInClass: [Student] = []
    @Published private(set) var allStudents: [Student] = []
    @Published private(set) var selectedStudentsClassId: Int64?
    @Published private(set) var studentImportPreview: AppleStudentImportPreview?
    @Published private(set) var isImportingStudents = false

    private weak var bridge: KmpBridge?
    private var cancellables = Set<AnyCancellable>()

    func bind(to bridge: KmpBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
        cancellables.removeAll()

        classes = bridge.classes
        studentsInClass = bridge.studentsInClass
        allStudents = bridge.allStudents
        selectedStudentsClassId = bridge.selectedStudentsClassId
        studentImportPreview = bridge.studentImportPreview
        isImportingStudents = bridge.isImportingStudents

        bridgeSink(bridge.$classes, \.classes, into: &cancellables)
        bridgeSink(bridge.$studentsInClass, \.studentsInClass, into: &cancellables)
        bridgeSink(bridge.$allStudents, \.allStudents, into: &cancellables)
        bridgeSink(bridge.$selectedStudentsClassId, \.selectedStudentsClassId, into: &cancellables)
        bridgeSink(bridge.$studentImportPreview, \.studentImportPreview, into: &cancellables) { _, _ in false }
        bridgeSink(bridge.$isImportingStudents, \.isImportingStudents, into: &cancellables)
    }
}

@MainActor
final class AttendanceBridgeStore: ObservableObject {
    @Published private(set) var classes: [SchoolClass] = []
    @Published private(set) var studentsInClass: [Student] = []
    @Published private(set) var allStudents: [Student] = []
    @Published private(set) var selectedStudentsClassId: Int64?

    private weak var bridge: KmpBridge?
    private var cancellables = Set<AnyCancellable>()

    func bind(to bridge: KmpBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
        cancellables.removeAll()

        classes = bridge.classes
        studentsInClass = bridge.studentsInClass
        allStudents = bridge.allStudents
        selectedStudentsClassId = bridge.selectedStudentsClassId

        bridgeSink(bridge.$classes, \.classes, into: &cancellables)
        bridgeSink(bridge.$studentsInClass, \.studentsInClass, into: &cancellables)
        bridgeSink(bridge.$allStudents, \.allStudents, into: &cancellables)
        bridgeSink(bridge.$selectedStudentsClassId, \.selectedStudentsClassId, into: &cancellables)
    }
}

/// Lo poco que leen las pantallas base (shell iOS/iPad/Mac y `ContentView`).
/// Las pantallas base ya no observan `KmpBridge` entero: con ~50 valores
/// publicados, cualquier cambio (una nota guardándose, la hora del último
/// sync cada 15-30 s) las obligaba a recalcularse enteras.
@MainActor
final class ShellBridgeStore: ObservableObject {
    @Published private(set) var classes: [SchoolClass] = []
    @Published private(set) var studentsInClass: [Student] = []
    @Published private(set) var allStudents: [Student] = []
    @Published private(set) var selectedStudentsClassId: Int64?
    @Published private(set) var syncPendingChanges = 0
    @Published private(set) var showingBulkRubricEvaluation = false
    @Published private(set) var isRubricEvaluationPresented = false

    private weak var bridge: KmpBridge?
    private var cancellables = Set<AnyCancellable>()

    func bind(to bridge: KmpBridge) {
        guard self.bridge !== bridge else { return }
        self.bridge = bridge
        cancellables.removeAll()

        classes = bridge.classes
        studentsInClass = bridge.studentsInClass
        allStudents = bridge.allStudents
        selectedStudentsClassId = bridge.selectedStudentsClassId
        syncPendingChanges = bridge.syncPendingChanges
        showingBulkRubricEvaluation = bridge.showingBulkRubricEvaluation
        isRubricEvaluationPresented = Self.isPresented(bridge.rubricEvaluationState)

        bridgeSink(bridge.$classes, \.classes, into: &cancellables)
        bridgeSink(bridge.$studentsInClass, \.studentsInClass, into: &cancellables)
        bridgeSink(bridge.$allStudents, \.allStudents, into: &cancellables)
        bridgeSink(bridge.$selectedStudentsClassId, \.selectedStudentsClassId, into: &cancellables)
        bridgeSink(bridge.$syncPendingChanges, \.syncPendingChanges, into: &cancellables)
        bridgeSink(bridge.$showingBulkRubricEvaluation, \.showingBulkRubricEvaluation, into: &cancellables)
        bridge.$rubricEvaluationState
            .map(Self.isPresented)
            .removeDuplicates()
            .sink { [weak self] value in self?.isRubricEvaluationPresented = value }
            .store(in: &cancellables)
    }

    private static func isPresented(_ state: RubricEvaluationUiState) -> Bool {
        state.isLoading || state.rubricDetail != nil || state.error != nil
    }
}

/// Contenedor de los stores por módulo. No publica nada a propósito: así la
/// pantalla base que lo posee no se redibuja cuando cambia uno de ellos; solo
/// lo hacen las vistas hijas que observan cada store.
@MainActor
final class WorkspaceBridgeStores: ObservableObject {
    let notebook = NotebookBridgeStore()
    let dashboard = DashboardBridgeStore()
    let students = StudentsBridgeStore()
    let attendance = AttendanceBridgeStore()
    /// El Planner vive aquí y no en su vista: al salir y volver conserva la semana
    /// cargada y solo se refresca por detrás (`refreshOnReappear`). Se enlaza al
    /// bridge en su primer `bind`, no en `bind(to:)`.
    let planner = PlannerWorkspaceViewModel()

    func bind(to bridge: KmpBridge) {
        notebook.bind(to: bridge)
        dashboard.bind(to: bridge)
        students.bind(to: bridge)
        attendance.bind(to: bridge)
    }
}

/// Referencia a `KmpBridge` sin suscribirse a sus cambios. Para vistas que
/// solo llaman a acciones del bridge; los datos que pintan llegan por un store.
private struct KmpBridgeReferenceKey: EnvironmentKey {
    static let defaultValue: KmpBridge? = nil
}

extension EnvironmentValues {
    var kmpBridgeReference: KmpBridge? {
        get { self[KmpBridgeReferenceKey.self] }
        set { self[KmpBridgeReferenceKey.self] = newValue }
    }
}

/// Lo último que enseñó cada pantalla que guarda sus datos en `@State`. Al cambiar
/// de pantalla, la vista se destruye (`.id(activeModule)`); al volver arranca con
/// esto y refresca por detrás, sin pantalla vacía ni ruedita. Va ligada al bridge:
/// si este se recrea (restaurar una copia, borrar datos) se vacía.
@MainActor
final class WorkspaceScreenMemory {
    static let shared = WorkspaceScreenMemory()

    private var ownerId: ObjectIdentifier?
    private var values: [String: Any] = [:]
    private var inclusionStore: InclusionTrackerStore?

    private func adopt(_ bridge: KmpBridge) {
        let id = ObjectIdentifier(bridge)
        guard ownerId != id else { return }
        ownerId = id
        values = [:]
        inclusionStore = nil
    }

    func value<T>(_ key: String, bridge: KmpBridge) -> T? {
        adopt(bridge)
        return values[key] as? T
    }

    func store<T>(_ value: T, _ key: String, bridge: KmpBridge) {
        adopt(bridge)
        values[key] = value
    }

    /// El store de Inclusión ya conserva su tablero si el grupo no cambia.
    func inclusion(bridge: KmpBridge) -> InclusionTrackerStore {
        adopt(bridge)
        if let inclusionStore { return inclusionStore }
        let created = InclusionTrackerStore()
        inclusionStore = created
        return created
    }
}
