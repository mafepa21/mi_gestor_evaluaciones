import Combine
import Foundation
import MiGestorKit

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

        bridge.$classes.assign(to: \.classes, on: self).store(in: &cancellables)
        bridge.$notebookState.assign(to: \.notebookState, on: self).store(in: &cancellables)
        bridge.$notebookStructureState.assign(to: \.notebookStructureState, on: self).store(in: &cancellables)
        bridge.$notebookRowsState.assign(to: \.notebookRowsState, on: self).store(in: &cancellables)
        bridge.$notebookSelectionState.assign(to: \.notebookSelectionState, on: self).store(in: &cancellables)
        bridge.$notebookSaveState.assign(to: \.notebookSaveState, on: self).store(in: &cancellables)
        bridge.$notebookSplitSaveState.assign(to: \.notebookSplitSaveState, on: self).store(in: &cancellables)
        bridge.$notebookInspectorState.assign(to: \.notebookInspectorState, on: self).store(in: &cancellables)
        bridge.$notebookAverageState.assign(to: \.notebookAverageState, on: self).store(in: &cancellables)
        bridge.$rubricEvaluationState.assign(to: \.rubricEvaluationState, on: self).store(in: &cancellables)
        bridge.$isNotebookRubricAutoAdvanceActive.assign(to: \.isNotebookRubricAutoAdvanceActive, on: self).store(in: &cancellables)
        bridge.$showingBulkRubricEvaluation.assign(to: \.showingBulkRubricEvaluation, on: self).store(in: &cancellables)
        bridge.$syncPendingChanges.assign(to: \.syncPendingChanges, on: self).store(in: &cancellables)
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

        bridge.$classes.assign(to: \.classes, on: self).store(in: &cancellables)
        bridge.$studentsInClass.assign(to: \.studentsInClass, on: self).store(in: &cancellables)
        bridge.$dashboardSnapshot.assign(to: \.dashboardSnapshot, on: self).store(in: &cancellables)
        bridge.$syncStatusMessage.assign(to: \.syncStatusMessage, on: self).store(in: &cancellables)
        bridge.$syncPendingChanges.assign(to: \.syncPendingChanges, on: self).store(in: &cancellables)
        bridge.$syncLastRunAt.assign(to: \.syncLastRunAt, on: self).store(in: &cancellables)
        bridge.$pairedSyncHost.assign(to: \.pairedSyncHost, on: self).store(in: &cancellables)
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

        bridge.$classes.assign(to: \.classes, on: self).store(in: &cancellables)
        bridge.$studentsInClass.assign(to: \.studentsInClass, on: self).store(in: &cancellables)
        bridge.$allStudents.assign(to: \.allStudents, on: self).store(in: &cancellables)
        bridge.$selectedStudentsClassId.assign(to: \.selectedStudentsClassId, on: self).store(in: &cancellables)
        bridge.$studentImportPreview.assign(to: \.studentImportPreview, on: self).store(in: &cancellables)
        bridge.$isImportingStudents.assign(to: \.isImportingStudents, on: self).store(in: &cancellables)
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

        bridge.$classes.assign(to: \.classes, on: self).store(in: &cancellables)
        bridge.$studentsInClass.assign(to: \.studentsInClass, on: self).store(in: &cancellables)
        bridge.$allStudents.assign(to: \.allStudents, on: self).store(in: &cancellables)
        bridge.$selectedStudentsClassId.assign(to: \.selectedStudentsClassId, on: self).store(in: &cancellables)
    }
}
