import Foundation
import MiGestorKit
import Combine
import Security
import CryptoKit

typealias KmpSubject = MiGestorKit.Subject
typealias WipeCategory = MiGestorKit.WipeCategory

@MainActor
final class KmpBridge: ObservableObject {
    static let plannerCoursePalette: [String] = [
        "#2563EB",
        "#0F766E",
        "#DC2626",
        "#7C3AED",
        "#EA580C",
        "#0891B2",
        "#65A30D",
        "#BE185D",
        "#4F46E5",
        "#B45309"
    ]

    @Published var status: String = "Inicializando..."
    /// Se pone a `true` al final de `bootstrap()`, tanto si termina bien como si
    /// falla. Permite a quien necesite saber si la carga inicial —incluido el
    /// primer *pull* de Sync LAN— ya ha terminado, esperarlo en vez de leer
    /// `classes`/`allStudents` mientras aún pueden estar vacíos de forma
    /// transitoria (p. ej. `OnboardingStore`, que decidiría "base vacía" en un
    /// iPad recién emparejado si mirara antes de que llegue el primer *pull*).
    @Published private(set) var hasCompletedBootstrap = false
    @Published var statsText: String = "-"
    @Published var classes: [SchoolClass] = []
    @Published var academicYears: [AcademicYearSnapshot] = []
    @Published var activeAcademicYear: AcademicYearSnapshot?
    @Published var archivedAcademicYears: [AcademicYearSnapshot] = []
    @Published var subjects: [KmpSubject] = []
    @Published var studentsInClass: [Student] = []
    @Published var evaluationsInClass: [Evaluation] = []
    @Published var rubrics: [RubricDetail] = []
    @Published var planning: [PlanPeriod] = []
    @Published var rubricsUiState: RubricUiState? = nil
    @Published var rubricClassLinks: [Int64: Set<Int64>] = [:]
    @Published var rubricBuilderTeachingUnits: [TeachingUnit] = []
    @Published var selectedRubricTeachingUnitId: Int64? = nil
    @Published var editingRubricBuilderId: Int64? = nil
    
    // Notebook State (Bridged from NotebookViewModel)
    @Published var notebookState: NotebookUiState = NotebookUiStateLoading()
    @Published var notebookStructureState = KmpBridge.emptyNotebookStructureState()
    @Published var notebookRowsState = KmpBridge.emptyNotebookRowsState()
    @Published var notebookSelectionState = KmpBridge.emptyNotebookSelectionState()
    @Published var notebookSaveState: NotebookViewModelSaveState = NotebookViewModelSaveState.saved
    @Published var notebookSplitSaveState = KmpBridge.emptyNotebookSaveState()
    @Published var notebookInspectorState = KmpBridge.emptyNotebookInspectorState()
    @Published var notebookAverageState = KmpBridge.emptyNotebookAverageState()
    
    // Rubric Evaluation State (Bridged from RubricEvaluationViewModel)
    @Published var rubricEvaluationState: RubricEvaluationUiState = RubricEvaluationUiState.companion.default()
    @Published var isNotebookRubricAutoAdvanceActive: Bool = false
    @Published var rubricEvaluationCoordinator = RubricEvaluationCoordinator()
    
    // Bulk Rubric Evaluation State
    @Published var bulkRubricEvaluationState: BulkRubricEvaluationUiState? = nil
    @Published var showingBulkRubricEvaluation: Bool = false
    
    // Detailed Dashboard Data
    @Published var upcomingClasses: [CalendarEvent] = []
    @Published var pendingTasks: [Incident] = []
    @Published var esoPercentage: Int = 0
    @Published var bachPercentage: Int = 0
    @Published var activityGroups: [ActivityGroup] = []
    @Published var dashboardSnapshot: DashboardSnapshot? = nil
    @Published var dashboardFilters: DashboardFilters = DashboardFilters(classId: nil, severity: nil, priority: nil, sessionStatus: nil)
    @Published var allStudents: [Student] = []
    @Published var selectedStudentsClassId: Int64? = nil
    @Published var studentImportPreview: AppleStudentImportPreview? = nil
    @Published var isImportingStudents = false

    // LAN Sync State
    @Published var discoveredSyncHosts: [String] = []
    @Published var syncStatusMessage: String = "Sync local inactivo"
    @Published var syncPendingChanges: Int = 0
    @Published var syncLastRunAt: Date? = nil
    @Published var pairedSyncHost: String? = nil
    @Published var syncDivergence: SyncDivergenceReport? = nil
    var lastDivergenceCheckAt: Date = .distantPast

    var hasPersistedLanPairing: Bool {
        !(syncToken?.isEmpty ?? true) && !((pairedServerId?.isEmpty ?? true) && (pairedServerFingerprint?.isEmpty ?? true))
    }
    
    // UI State for Sheets
    @Published var showingAddColumn = false
    @Published var editingWeightColumn: NotebookColumnDefinition? = nil
    @Published var selectedNotebookTabId: String? = nil


    let container: KmpContainer
    let appleBootstrap: AppleBridgeBootstrap
    let appleImportFacade = AppleImportFacade()
    let notebookViewModel: NotebookViewModel
    let plannerViewModel: PlannerViewModel
    let rubricEvaluationViewModel: RubricEvaluationViewModel
    let rubricBulkEvaluationViewModel: RubricBulkEvaluationViewModel
    let rubricsViewModel: RubricsViewModel
    let lanSyncClient = LanSyncClient()
    let syncEventListener = SyncEventListener()
    let lanSyncDiscovery = LanSyncDiscovery()
    let syncSecureStore = IosKeychainStore(service: "com.migestor.sync.ios")
    var syncToken: String? = nil
    var pairedServerId: String? = nil
    var pairedServerFingerprint: String? = nil
    /// Canonical JSON por SHA y número de sesión. Evita volver a parsear el mismo DOCX una vez
    /// por plan al abrir el Planner o al reparar una planificación histórica.
    var sessionPlanJSONCacheBySource: [String: [Int: String]] = [:]
    var discoveredPeersByHost: [String: LanDiscoveredPeer] = [:]
    var manualSyncTask: Task<Void, Never>? = nil
    var autoSyncLoopTask: Task<Void, Never>? = nil
    var autoSyncDebounceTask: Task<Void, Never>? = nil
    var localChangesNotifyTask: Task<Void, Never>? = nil
    var pendingChangesPersistenceTask: Task<Void, Never>? = nil
    var notebookSnapshotDebounceTask: Task<Void, Never>? = nil
    var pendingGradeSnapshotTask: Task<Void, Never>? = nil
    /// Espera corta al teclear una nota: no escribe SQL en cada tecla.
    var columnGradeSaveDebounceTask: Task<Void, Never>? = nil
    var pendingDebouncedColumnGrade: (studentId: Int64, column: NotebookColumnDefinition, value: String)? = nil
    var postSyncRefreshTask: Task<Void, Never>? = nil
    var isPairingInFlight = false
    var isSyncInFlight = false
    var syncNeedsAnotherPass = false
    var isAppInForeground = true
    var lastLocalMutationAt: Date = .distantPast
    var lastCheckedDbModificationDate: Date = .distantPast
    var lastSuccessfulSyncAt: Date = .distantPast
    var lastFullPullAt: Date = .distantPast
    var lastSilentSyncAttemptAt: Date = .distantPast
    var lastSyncCursorEpochMs: Int64 = UserDefaults.standard.object(forKey: "sync.last.cursor") as? Int64 ?? 0
    var selectedNotebookTabByClassId: [String: String] = {
        guard let raw = UserDefaults.standard.dictionary(forKey: "notebook.selected.tab.by.class.v1") as? [String: String] else {
            return [:]
        }
        return raw
    }()
    var plannerCourseColorByClassId: [String: String] = {
        guard let raw = UserDefaults.standard.dictionary(forKey: "planner.class.colors.v1") as? [String: String] else {
            return [:]
        }
        return raw
    }()
    /// Cola de cambios pendientes – persiste en UserDefaults para sobrevivir reinicios.
    var pendingOutboundChanges: [LanSyncChange] = {
        guard let data = UserDefaults.standard.data(forKey: "sync.pending.changes.v2"),
              let decoded = try? JSONDecoder().decode([LanSyncChange].self, from: data)
        else { return [] }
        return decoded
    }()
    var pendingLocalSseChanges: [LanSyncChange] = []
    var notebookSyncCache: NotebookSyncCache = {
        guard let data = UserDefaults.standard.data(forKey: "sync.notebook.cache.v1"),
              let decoded = try? JSONDecoder().decode(NotebookSyncCache.self, from: data)
        else { return NotebookSyncCache() }
        return decoded
    }()
    lazy var localDeviceId: String = loadOrCreateLocalDeviceId()
    private var didBootstrap = false
    private var cancellables = Set<AnyCancellable>()
    private let notebookStateSubject = CurrentValueSubject<NotebookUiState, Never>(NotebookUiStateLoading())
    var cachedNotebookStateIdentity: ObjectIdentifier? = nil
    var cachedNotebookCellValueIndex: NotebookCellValueIndex? = nil
    var lastNotebookAggregateSignature: String? = nil
    var gradeOnTenFormatCache: [String: String] = [:]
    struct OptimisticAnnotation {
        let note: String?
        let icon: String?
        let attachmentUris: [String]
    }
    var optimisticGradeDrafts: [String: String] = [:]
    var optimisticTextDrafts: [String: String] = [:]
    var optimisticAnnotations: [String: OptimisticAnnotation] = [:]

    struct NotebookCellValueIndex {
        var textByKey: [String: String] = [:]
        var displayByKey: [String: String] = [:]
        var checkByKey: [String: Bool] = [:]
        var numericByKey: [String: String] = [:]
        var numericByEvalKey: [String: String] = [:]
        var numericDraftByKey: [String: String] = [:]
        var checkDraftByKey: [String: Bool] = [:]
        var textDraftByKey: [String: String] = [:]
    }

    init() {
        self.appleBootstrap = AppleBridgeBootstrap.current()
        self.container = appleBootstrap.container
        
        // Initialize Shared ViewModels
        self.notebookViewModel = NotebookViewModel(
            notebookRepository: container.notebookRepository,
            evaluationsRepository: container.evaluationsRepository,
            rubricsRepository: container.rubricsRepository,
            studentImporter: StudentImporter(),
            scope: MainScope()
        )

        self.plannerViewModel = PlannerViewModel(
            plannerRepo: container.plannerRepository,
            classRepo: container.classesRepository,
            weeklyTemplateRepo: container.weeklyTemplateRepository,
            plannedSessionRepo: container.plannedSessionRepository,
            generateSessionsFromUD: container.generateSessionsFromUD,
            scope: MainScope()
        )
        
        self.rubricEvaluationViewModel = RubricEvaluationViewModel(
            rubricsRepository: container.rubricsRepository,
            studentsRepository: container.studentsRepository,
            evaluationsRepository: container.evaluationsRepository,
            gradesRepository: container.gradesRepository,
            notebookRepository: container.notebookRepository,
            scope: MainScope()
        )
        
        self.rubricBulkEvaluationViewModel = RubricBulkEvaluationViewModel(
            rubricsRepository: container.rubricsRepository,
            studentsRepository: container.studentsRepository,
            notebookRepository: container.notebookRepository,
            gradesRepository: container.gradesRepository,
            scope: MainScope()
        )
        
        self.rubricsViewModel = RubricsViewModel(
            rubricsRepository: container.rubricsRepository,
            classesRepository: container.classesRepository,
            evaluationsRepository: container.evaluationsRepository,
            notebookRepository: container.notebookRepository,
            scope: MainScope()
        )
        
        migrateLegacySyncSecretsFromUserDefaults()
        self.syncToken = syncSecureStore.loadString(key: "sync.token")
        self.pairedSyncHost = syncSecureStore.loadString(key: "sync.host")
        self.pairedServerId = syncSecureStore.loadString(key: "sync.server.id")
        self.pairedServerFingerprint = syncSecureStore.loadString(key: "sync.server.fingerprint")
        
        #if os(macOS)
        // On macOS the sync endpoint is the helper process, which is NOT running yet at
        // init time. We intentionally leave pairedSyncHost as nil here so that
        // startSyncEventListenerIfPaired() and syncNow() are no-ops until
        // MacCommandCenterCoordinator calls notifyHelperReady(host:port:) once the
        // helper has published a valid LAN IP address.
        self.syncToken = "loopback-token"
        self.pairedSyncHost = nil
        self.pairedServerFingerprint = nil
        #endif

        self.lanSyncDiscovery.onPeersChanged = { [weak self] peers in
            Task { @MainActor in
                guard let self else { return }
                let uniquePeers = Self.deduplicateDiscoveredPeers(peers)
                self.discoveredPeersByHost = Dictionary(
                    uniquePeers.map { ($0.host, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                self.discoveredSyncHosts = uniquePeers.map(\.host).sorted()
                self.rebindPairedHostIfNeeded()
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lanSyncDiscovery.start()
            self.startAutoSyncLoop()
            self.startSyncEventListenerIfPaired()
            #if os(iOS)
            // On iOS the persisted host/token come from a real pairing; rehydrate on launch.
            if self.hasPersistedLanPairing {
                await self.syncNow(reason: "rehydrate", forceFullPull: false, silent: true)
            }
            #endif
        }

        setupObservers()
    }

    deinit {
        autoSyncLoopTask?.cancel()
        autoSyncDebounceTask?.cancel()
        pendingChangesPersistenceTask?.cancel()
        syncEventListener.stop()
        notebookSnapshotDebounceTask?.cancel()
        pendingGradeSnapshotTask?.cancel()
        columnGradeSaveDebounceTask?.cancel()
        postSyncRefreshTask?.cancel()
    }

    private static func emptyNotebookStructureState() -> NotebookStructureState {
        NotebookStructureState(
            classId: nil,
            tabs: [],
            columns: [],
            categories: [],
            workGroups: [],
            workGroupMembers: [],
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookRowsState() -> NotebookRowsState {
        NotebookRowsState(
            classId: nil,
            rows: [],
            numericDrafts: [:],
            textDrafts: [:],
            checkDrafts: [:],
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookSelectionState() -> NotebookSelectionState {
        NotebookSelectionState(
            selectedColumnIds: [],
            isColumnSelectionMode: false,
            activeCell: nil,
            activeCellEditor: nil,
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookSaveState() -> NotebookSaveState {
        NotebookSaveState(
            state: NotebookViewModelSaveState.saved,
            isDirty: false,
            isSaving: false,
            isSaved: true
        )
    }

    private static func emptyNotebookInspectorState() -> NotebookInspectorState {
        NotebookInspectorState(
            rubricEvaluationTarget: nil,
            activeCellEditor: nil,
            activeCell: nil,
            isLoading: true,
            errorMessage: nil
        )
    }

    private static func emptyNotebookAverageState() -> NotebookAverageState {
        NotebookAverageState(
            classId: nil,
            averagesByStudentId: [:],
            explanationsByStudentId: [:],
            isLoading: true,
            errorMessage: nil
        )
    }

    private func notebookAggregateSignature(for state: NotebookUiState) -> String? {
        guard let data = state as? NotebookUiStateData else {
            return String(describing: type(of: state))
        }

        let sheet = data.sheet
        let columnsSignature = sheet.columns.map { column in
            [
                column.id,
                column.title,
                "\(column.order)",
                "\(column.widthDp)",
                "\(column.visibility)",
                "\(column.isHidden)",
                column.categoryId ?? "",
                column.tabIds.joined(separator: ","),
                "\(column.weight)",
                "\(column.countsTowardAverage)"
            ].joined(separator: ":")
        }.joined(separator: "|")

        let categoriesSignature = sheet.columnCategories.map { category in
            "\(category.id):\(category.tabId):\(category.name):\(category.order):\(category.isCollapsed)"
        }.joined(separator: "|")

        let rowsSignature = sheet.rows.map { row in
            let cells = row.cells.map { cell in
                "\(String(describing: cell.evaluationId)):\(String(describing: cell.value))"
            }.joined(separator: ",")
            let persistedCells = row.persistedCells.map { cell in
                [
                    cell.columnId,
                    cell.textValue ?? "",
                    String(describing: cell.boolValue),
                    cell.iconValue ?? "",
                    cell.annotation?.icon ?? "",
                    cell.annotation?.note ?? "",
                    "\(cell.annotation?.attachmentUris.count ?? 0)",
                    cell.ordinalValue ?? "",
                    cell.displayValue ?? ""
                ].joined(separator: ":")
            }.joined(separator: ",")
            let grades = row.persistedGrades.map { grade in
                "\(grade.columnId):\(String(describing: grade.value)):\(String(describing: grade.evaluationId))"
            }.joined(separator: ",")
            return "\(row.student.id):\(String(describing: row.weightedAverage)):\(cells):\(persistedCells):\(grades)"
        }.joined(separator: "|")

        return [
            "class:\(sheet.classId)",
            "tabs:\(sheet.tabs.map { "\($0.id):\($0.title):\($0.order)" }.joined(separator: "|"))",
            "columns:\(columnsSignature)",
            "categories:\(categoriesSignature)",
            "rows:\(rowsSignature)",
            "numeric:\(data.numericDrafts.description)",
            "text:\(data.textDrafts.description)",
            "check:\(data.checkDrafts.description)",
            "groups:\(sheet.workGroups.map { "\($0.id):\($0.tabId):\($0.name):\($0.order):\($0.learningSituationId?.int64Value ?? -1)" }.joined(separator: ";"))",
            "groupMembers:\(sheet.workGroupMembers.map { "\($0.tabId):\($0.groupId):\($0.studentId)" }.joined(separator: ";"))"
        ].joined(separator: "¬")
    }

    private func setupObservers() {
        #if os(macOS)
        // macOS: react to the helper process lifecycle via NotificationCenter so the
        // SSE listener and auto-sync loop start only when the server is actually ready.
        NotificationCenter.default.addObserver(
            forName: .syncHelperBecameReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let host = notification.userInfo?["host"] as? String,
                  let port = notification.userInfo?["port"] as? Int else { return }
            Task { @MainActor in
                self.notifyHelperReady(host: host, port: port)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .syncHelperStopped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.notifyHelperStopped()
            }
        }
        #endif

        // Observe Notebook State with Debounce (to stabilize UI during typing)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.state.asAsyncSequence(type: NotebookUiState.self)
            for await state in sequence {
                if state is NotebookUiStateLoading {
                    // Solo propagar Loading si aún no tenemos datos previos (primera carga).
                    // Si ya había datos, ignoramos la transición a Loading para no destruir
                    // la jerarquía SwiftUI ni los @State/@FocusState de las celdas en edición.
                    if self.notebookState is NotebookUiStateLoading {
                        self.notebookState = state
                        self.invalidateNotebookCellValueIndexCache()
                    }
                    // Si ya teníamos datos, ignoramos el Loading: el ViewModel
                    // emitirá Data de vuelta cuando termine la recarga silenciosa.
                } else {
                    let signature = self.notebookAggregateSignature(for: state)
                    if signature == nil || signature != self.lastNotebookAggregateSignature {
                        self.lastNotebookAggregateSignature = signature
                        notebookStateSubject.send(state)
                    }
                }
            }
        }
        
        notebookStateSubject
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.notebookState = state
                self.invalidateNotebookCellValueIndexCache()
            }
            .store(in: &cancellables)
        
        // Observe Notebook Save State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.saveState.asAsyncSequence(type: NotebookViewModelSaveState.self)
            for await saveState in sequence {
                self.notebookSaveState = saveState
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.structureState.asAsyncSequence(type: NotebookStructureState.self)
            for await state in sequence {
                self.notebookStructureState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.rowsState.asAsyncSequence(type: NotebookRowsState.self)
            for await state in sequence {
                self.notebookRowsState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.selectionState.asAsyncSequence(type: NotebookSelectionState.self)
            for await state in sequence {
                self.notebookSelectionState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.notebookSaveState.asAsyncSequence(type: NotebookSaveState.self)
            for await state in sequence {
                self.notebookSplitSaveState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.inspectorState.asAsyncSequence(type: NotebookInspectorState.self)
            for await state in sequence {
                self.notebookInspectorState = state
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = notebookViewModel.averageState.asAsyncSequence(type: NotebookAverageState.self)
            for await state in sequence {
                self.notebookAverageState = state
            }
        }
        
        // Observe Rubric Evaluation State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = rubricEvaluationViewModel.uiState.asAsyncSequence(type: RubricEvaluationUiState.self)
            for await state in sequence {
                let wasSaveSuccessful = self.rubricEvaluationState.isSaveSuccessful
                self.rubricEvaluationState = state
                if state.isSaveSuccessful && !wasSaveSuccessful && !self.isNotebookRubricAutoAdvanceActive {
                    self.refreshCurrentNotebook()
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
            }
        }
        
        // Observe Rubric Bulk Evaluation State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = rubricBulkEvaluationViewModel.uiState.asAsyncSequence(type: BulkRubricEvaluationUiState.self)
            for await state in sequence {
                let wasSaveSuccessful = self.bulkRubricEvaluationState?.isSaveSuccessful ?? false
                self.bulkRubricEvaluationState = state
                if state.isSaveSuccessful && !wasSaveSuccessful {
                    if let classId = self.notebookViewModel.currentClassId?.int64Value {
                        self.scheduleNotebookSnapshotSync(forClassId: classId)
                    }
                }
            }
        }

        // Observe Rubrics Builder/Bank State
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sequence = rubricsViewModel.uiState.asAsyncSequence(type: RubricUiState.self)
            for await state in sequence {
                self.rubricsUiState = state
                self.rubrics = state.savedRubrics
            }
        }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            if !UserDefaults.standard.bool(forKey: Self.hasCompletedInitialSeedKey) {
                try await seedIfNeeded()
                UserDefaults.standard.set(true, forKey: Self.hasCompletedInitialSeedKey)
            }
            try await refreshDashboard()
            try await loadDashboard(mode: .office)
            try await refreshClasses()
            try await refreshSubjects()
            try await refreshRubrics()
            try await refreshRubricClassLinks()
            try await refreshPlanning()
            try await refreshStudentsDirectory()
            await syncNow(reason: "bootstrap", forceFullPull: true, silent: true)
            status = appleBootstrap.connectedStatusText
        } catch {
            didBootstrap = false
            status = "Error: \(error.localizedDescription)"
        }
        hasCompletedBootstrap = true
    }

    var appDatabasePath: String {
        appleBootstrap.databasePath
    }

    /// Fuera del SQLite a propósito: `wipeAllData()` (Ajustes → Zona de Riesgo)
    /// borra el fichero de base de datos entero, así que cualquier marca que
    /// viviera dentro de una tabla desaparecería con él y la siembra de
    /// datos de demo (`seedDemoDataIfEmpty`, que solo mira si hay alumnos)
    /// volvería a dispararse en el siguiente arranque, deshaciendo el
    /// borrado. `UserDefaults` sobrevive al borrado del SQLite, así que una
    /// vez sembrado no se vuelve a sembrar nunca más, ni siquiera tras un
    /// borrado deliberado.
    private static let hasCompletedInitialSeedKey = "demo.seed.completed.v1"

    private func seedIfNeeded() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.seedDemoDataIfEmpty { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }


    // Proxy Methods for NotebookViewModel

    func enqueueRosterSnapshot(forClassId classId: Int64, updatedAtEpochMs: Int64) {
        let studentIds = studentsInClass.map { $0.id }.sorted()
        enqueueLocalChange(
            entity: "class_roster",
            id: "\(classId)",
            updatedAtEpochMs: updatedAtEpochMs,
            payload: [
                "classId": classId,
                "studentIds": studentIds
            ]
        )
    }

    func enqueueLocalChange(
        entity: String,
        id: String,
        updatedAtEpochMs: Int64,
        payload: [String: Any],
        op: String = "upsert",
        shouldPersist: Bool = true,
        shouldScheduleAutoSync: Bool = true,
        autoSyncDelayNanoseconds: UInt64 = 250_000_000
    ) {
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            return
        }
        let newChange = LanSyncChange(
            entity: entity,
            id: id,
            updatedAtEpochMs: updatedAtEpochMs,
            deviceId: localDeviceId,
            payload: payloadString,
            op: op
        )
        if let idx = pendingOutboundChanges.firstIndex(where: { $0.entity == entity && $0.id == id }) {
            pendingOutboundChanges[idx] = newChange
        } else {
            pendingOutboundChanges.append(newChange)
        }
        lastLocalMutationAt = Date()
        let pendingChangesCount = pendingOutboundChanges.count
        publishSyncState {
            $0.syncPendingChanges = pendingChangesCount
        }
        
        if shouldPersist {
            persistPendingChanges()
        }
        enqueueLocalSseNotification(newChange)
        if shouldScheduleAutoSync {
            triggerAutoSyncSoon(delayNanoseconds: autoSyncDelayNanoseconds)
        }
    }

    private func enqueueLocalSseNotification(_ change: LanSyncChange) {
        #if os(macOS)
        guard pairedSyncHost != nil else { return }
        if let idx = pendingLocalSseChanges.firstIndex(where: { $0.entity == change.entity && $0.id == change.id }) {
            pendingLocalSseChanges[idx] = change
        } else {
            pendingLocalSseChanges.append(change)
        }
        localChangesNotifyTask?.cancel()
        localChangesNotifyTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                let changes = self.pendingLocalSseChanges
                self.pendingLocalSseChanges.removeAll()
                guard !changes.isEmpty else { return }
                // El helper guarda la contraseña del enlace en el llavero desktop.
                // syncToken del Mac es un marcador local ("loopback-token") y no vale aquí.
                let desktopStore = IosKeychainStore(service: "com.migestor.sync.desktop")
                guard let token = desktopStore.loadString(key: "paired-token"),
                      LanLocalNotifyPolicy.shouldAttachBearer(token: token) else {
                    // Sin iPad emparejado no hay a quién avisar; no fingimos éxito.
                    return
                }
                try await self.lanSyncClient.notifyLocalChanges(
                    host: self.pairedSyncHost ?? "127.0.0.1",
                    token: token,
                    changes: changes,
                    pinnedFingerprint: self.pairedServerFingerprint
                )
            } catch is CancellationError {
                return
            } catch {
                self.publishSyncState {
                    $0.syncStatusMessage = LanLocalNotifyPolicy.failureStatusMessage
                }
            }
        }
        #endif
    }


}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
