import Combine
import Foundation
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
