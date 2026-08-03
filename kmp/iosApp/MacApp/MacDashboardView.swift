import SwiftUI
import MiGestorKit
import UniformTypeIdentifiers

struct MacDashboardToolbarActions {
    let canRunActions: Bool
    let refresh: () -> Void
    let passList: () -> Void
    let observation: () -> Void
}

enum MacDashboardDestination {
    case attendance(classId: Int64?)
    case notebook(classId: Int64?)
    case rubrics(classId: Int64?)
    case plannerAgenda
    case plannerSession(sessionId: Int64?)
    case students(classId: Int64?)
    case reports(classId: Int64?)
}

struct MacDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let bridge: KmpBridge
    @ObservedObject var dashboardStore: DashboardBridgeStore
    @ObservedObject var backupStore: MacBackupStore
    let bootstrap: AppleBridgeBootstrap
    var onNavigate: (MacDashboardDestination) -> Void = { _ in }
    var onToolbarActionsChange: (MacDashboardToolbarActions?) -> Void = { _ in }
    var onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void = { _, _, _ in }

    @State private var loadState: MacDashboardLoadState = .loading
    @State private var reloadTask: Task<Void, Never>?
    @State private var activeSheet: DashboardSheet?
    @State private var proactiveInsights: [DashboardProactiveInsight] = []
    @State private var aiBriefing: TeachingAssistantDraft? = nil
    @State private var aiBriefingState: DashboardAIBriefingState = .deterministic
    @State private var activeAIBriefingKey: DashboardAIBriefingCacheKey?

    // Bloques compartidos con iPad (Resumen por grupo/Agenda/EF/LOMLOE/KPIs):
    // se apoyan en el `DashboardSnapshot` real del backend, el mismo que usa
    // iPad, en vez del modelo ad-hoc (`MacDashboardSnapshot`) que hasta ahora
    // era la única fuente de datos de este dashboard.
    @State private var operationalSnapshot: DashboardSnapshot?
    @State private var classTrends: KmpBridge.AITrendsSnapshot?
    @State private var isLoadingClassTrends = false
    @State private var classTrendsLoadFailed = false

    @State private var teachingAssistantService = AppleFoundationTeachingAssistantService()

    /// Misma clave de preferencia que iPad: el modo elegido en una plataforma
    /// no se pisa con el de la otra porque `@AppStorage` es local, pero el
    /// comportamiento y las opciones son idénticos.
    @AppStorage("dashboard_mode_preference") private var modePreferenceRaw: String = DashboardModePreference.auto.rawValue

    private var modePreference: DashboardModePreference {
        DashboardModePreference(rawValue: modePreferenceRaw) ?? .auto
    }

    private var activeContext: DashboardSessionContext? {
        guard case .ready(let snapshot) = loadState else { return nil }
        return snapshot.context
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    dashboardHeader

                    switch loadState {
                    case .loading:
                        DashboardLoadingView()
                    case .ready(let snapshot):
                        readyContent(snapshot: snapshot, isWide: proxy.size.width >= 1040)
                    case .empty(let reason):
                        DashboardEmptyStateView(reason: reason) { destination in
                            onNavigate(destination)
                        }
                    case .error(let message):
                        DashboardErrorStateView(message: message) {
                            scheduleReload()
                        }
                    }
                }
                .padding(MacAppStyle.pagePadding)
                .macLiquidGlassGroup(spacing: 18)
            }
        }
        .background(MacAppStyle.pageBackground)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quickEvaluation(let classId):
                QuickEvaluationSheet(bridge: bridge, initialClassId: classId) {
                    activeSheet = nil
                } onOpenNotebook: { classId in
                    activeSheet = nil
                    onNavigate(.notebook(classId: classId))
                }
                .frame(minWidth: 760, minHeight: 680)
            case .observation(let classId):
                ObservationComposerSheet(bridge: bridge, initialClassId: classId) {
                    activeSheet = nil
                } onOpenStudents: { classId in
                    activeSheet = nil
                    onNavigate(.students(classId: classId))
                }
                .frame(minWidth: 560, minHeight: 520)
            }
        }
        .task {
            scheduleReload()
            await backupStore.loadBackups()
        }
        .onAppear {
            scheduleToolbarActionsSync()
        }
        .onDisappear {
            reloadTask?.cancel()
            onToolbarActionsChange(nil)
        }
        .appOnChange(of: toolbarKey) { _ in
            scheduleToolbarActionsSync()
        }
        .appOnChange(of: dashboardStore.syncPendingChanges) { _ in
            scheduleReload()
        }
        .appOnChange(of: dashboardStore.pairedSyncHost) { _ in
            scheduleReload()
        }
        .appOnChange(of: modePreferenceRaw) { _ in
            scheduleReload()
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hoy")
                    .font(MacAppStyle.pageTitle)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            dashboardModePicker
            SyncStatusCompactView(summary: DashboardSyncSummary(bridge: bridge))
        }
    }

    private var headerSubtitle: String {
        modePreference.resolvedHint(for: operationalSnapshot?.currentContext)
            ?? (modePreference == .classroom ? "Solo el grupo que tengo delante" : "Qué tengo ahora, qué falta y qué hago")
    }

    /// macOS no tenía selector de modo: el dashboard estaba fijado a Despacho.
    /// Ahora ofrece las mismas tres opciones que iPad.
    private var dashboardModePicker: some View {
        Picker("Contexto", selection: $modePreferenceRaw) {
            ForEach(DashboardModePreference.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 260)
    }

    @ViewBuilder
    private func readyContent(snapshot: MacDashboardSnapshot, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if isWide {
                HStack(alignment: .top, spacing: 24) {
                    DashboardHeroNowCard(
                        context: snapshot.context,
                        tintHex: snapshot.context?.classId.flatMap { bridge.plannerCourseColor(for: $0.int64Value) },
                        onAction: handleQuickAction,
                        onOpenSheet: { activeSheet = $0 }
                    )
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 24) {
                        DashboardProactiveInsightCard(
                            insights: proactiveInsights,
                            aiBriefing: aiBriefing,
                            aiBriefingState: aiBriefingState,
                            actionAvailability: proactiveActionAvailable,
                            onAction: handleProactiveAction
                        )
                        DashboardPendingCard(items: snapshot.pendingItems, onNavigate: onNavigate)
                        DashboardRiskCard(snapshot: snapshot, insights: proactiveInsights, onNavigate: onNavigate)
                        DashboardStatusCard(summary: snapshot.syncStatus, backupStore: backupStore, platformName: bootstrap.platformName)
                    }
                    .frame(width: 380)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    DashboardProactiveInsightCard(
                        insights: proactiveInsights,
                        aiBriefing: aiBriefing,
                        aiBriefingState: aiBriefingState,
                        actionAvailability: proactiveActionAvailable,
                        onAction: handleProactiveAction
                    )
                    DashboardHeroNowCard(
                        context: snapshot.context,
                        tintHex: snapshot.context?.classId.flatMap { bridge.plannerCourseColor(for: $0.int64Value) },
                        onAction: handleQuickAction,
                        onOpenSheet: { activeSheet = $0 }
                    )
                    DashboardPendingCard(items: snapshot.pendingItems, onNavigate: onNavigate)
                    DashboardRiskCard(snapshot: snapshot, insights: proactiveInsights, onNavigate: onNavigate)
                    DashboardStatusCard(summary: snapshot.syncStatus, backupStore: backupStore, platformName: bootstrap.platformName)
                }
            }

            if let operationalSnapshot {
                sharedOperationalBlocks(snapshot: operationalSnapshot, isWide: isWide)
            }
        }
    }

    /// Resumen por grupo, Agenda docente, Educación Física y Auditoría
    /// LOMLOE, sobre el mismo `DashboardSnapshot` del backend que usa iPad
    /// (capa compartida en DashboardSharedBlocks.swift). El `MacDashboardSnapshot`
    /// que queda ya solo lleva pendientes, sync y acciones: el contexto de
    /// "Ahora" también viene del snapshot compartido.
    @ViewBuilder
    private func sharedOperationalBlocks(snapshot: DashboardSnapshot, isWide: Bool) -> some View {
        // En modo Clase estos bloques no se pintan: comparan grupos entre sí o
        // miran la semana entera, y el backend ya los devuelve vacíos. Se
        // omiten en vez de dibujar cuatro tarjetas diciendo "sin datos".
        let isClassroom = modePreference.resolved(for: snapshot.currentContext) == .classroom
        VStack(alignment: .leading, spacing: 16) {
            if !isClassroom {
                dashboardKpiRow(snapshot: snapshot, colorScheme: colorScheme)
            }
            if isClassroom {
                EmptyView()
            } else if isWide {
                HStack(alignment: .top, spacing: 16) {
                    dashboardGroupSummaryBlock(snapshot: snapshot, isWide: true)
                    dashboardAgendaBlock(snapshot: snapshot, colorScheme: colorScheme, onOpenModule: onOpenModule)
                }
                HStack(alignment: .top, spacing: 16) {
                    dashboardPEBlock(snapshot: snapshot, colorScheme: colorScheme, onSelectItem: handleSelectPEItem)
                    dashboardLomloeAuditBlock(
                        trends: classTrends,
                        isLoading: isLoadingClassTrends,
                        loadFailed: classTrendsLoadFailed,
                        onRetry: { Task { await rebuildProactiveRadarForCurrentState() } }
                    )
                }
            } else {
                dashboardGroupSummaryBlock(snapshot: snapshot, isWide: false)
                dashboardAgendaBlock(snapshot: snapshot, colorScheme: colorScheme, onOpenModule: onOpenModule)
                dashboardPEBlock(snapshot: snapshot, colorScheme: colorScheme, onSelectItem: handleSelectPEItem)
                dashboardLomloeAuditBlock(
                    trends: classTrends,
                    isLoading: isLoadingClassTrends,
                    loadFailed: classTrendsLoadFailed,
                    onRetry: { Task { await rebuildProactiveRadarForCurrentState() } }
                )
            }
        }
    }

    private func handleSelectPEItem(_ item: PEOperationalItem) {
        if let destination = peDestination(for: item) {
            onOpenModule(destination, item.classId?.int64Value, nil)
        }
    }

    private var toolbarKey: String {
        let context = activeContext
        return "\(context?.classId?.int64Value ?? -1)|\(context.map { dashboardContextStatusLabel($0.status) } ?? "none")|\(dashboardStore.syncPendingChanges)|\(dashboardStore.pairedSyncHost ?? "")"
    }

    private func syncToolbarActions() {
        onToolbarActionsChange(
            MacDashboardToolbarActions(
                canRunActions: activeContext?.classId != nil,
                refresh: { scheduleReload() },
                passList: { handleQuickAction(.attendance(classId: activeContext?.classId?.int64Value)) },
                observation: { activeSheet = .observation(classId: activeContext?.classId?.int64Value) }
            )
        )
    }

    private func scheduleToolbarActionsSync() {
        Task { @MainActor in
            syncToolbarActions()
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await loadDashboard()
        }
    }

    @MainActor
    private func loadDashboard() async {
        loadState = .loading
        do {
            await bridge.ensureClassesLoaded()
            // El modo ya no está fijado a `.office`: se resuelve desde la
            // preferencia del usuario y del contexto del horario, igual que en
            // iPad. Se pide primero con el modo vigente y, si el automático
            // cambia de opinión al ver el contexto, se recarga una sola vez.
            let requestedMode = modePreference.resolved(for: operationalSnapshot?.currentContext)
            await bridge.refreshDashboard(mode: requestedMode)
            var snapshot = dashboardStore.dashboardSnapshot
            let settledMode = modePreference.resolved(for: snapshot?.currentContext)
            if settledMode != requestedMode {
                await bridge.refreshDashboard(mode: settledMode)
                snapshot = dashboardStore.dashboardSnapshot
            }
            operationalSnapshot = snapshot

            guard !dashboardStore.classes.isEmpty else {
                loadState = .empty(.noClasses)
                return
            }

            // Sin horario o fuera del rango del curso ya NO vacían la página.
            // Antes sí, y por eso el mismo estado se veía radicalmente distinto
            // en las dos plataformas: macOS sustituía todo el dashboard por una
            // tarjeta de aviso mientras iPad seguía enseñando alertas,
            // pendientes y riesgo. Ese aviso lo da ahora la propia tarjeta
            // "Ahora", igual que en iPad, y el resto del dashboard sigue ahí:
            // el trabajo pendiente no deja de existir porque sea julio.
            loadState = .ready(try await buildSnapshot(context: snapshot?.currentContext))
        } catch {
            loadState = .error("No se pudo cargar el dashboard: \(error.localizedDescription)")
        }
        await rebuildProactiveRadarForCurrentState()
        syncToolbarActions()
    }

    private func rebuildProactiveRadarForCurrentState() async {
        guard case .ready(let snapshot) = loadState else {
            proactiveInsights = []
            aiBriefing = nil
            aiBriefingState = .deterministic
            classTrends = nil
            classTrendsLoadFailed = false
            return
        }
        let context = snapshot.context
        isLoadingClassTrends = context?.classId != nil
        let trends: KmpBridge.AITrendsSnapshot?
        if let classId = context?.classId?.int64Value {
            trends = try? await bridge.getAITrendsAndMetrics(classId: classId, studentId: nil)
        } else {
            trends = nil
        }
        classTrends = trends
        classTrendsLoadFailed = context?.classId != nil && trends == nil
        isLoadingClassTrends = false
        proactiveInsights = DashboardProactiveInsightEngine.build(
            snapshot: snapshot.proactiveSnapshot,
            trends: trends,
            context: DashboardProactiveContext(
                className: context.map { $0.className.isEmpty ? nil : $0.className } ?? nil,
                modeLabel: "macOS",
                syncPendingChanges: snapshot.syncStatus.pendingChanges,
                pairedSyncHost: snapshot.syncStatus.pairedHost,
                latestBackupDate: backupStore.latestBackup?.createdAt,
                platformName: "macOS"
            ),
            limit: 5
        )
        loadAIBriefingIfNeeded(snapshot: snapshot)
    }

    private func loadAIBriefingIfNeeded(snapshot: MacDashboardSnapshot) {
        let key = aiBriefingKey(snapshot: snapshot)
        activeAIBriefingKey = key
        if let cached = DashboardAIBriefingCache.shared.cachedDraft(for: key) {
            aiBriefing = cached
            aiBriefingState = .cached
            return
        }
        let context = snapshot.context
        aiBriefing = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: context.map { $0.className.isEmpty ? nil : $0.className } ?? nil)
        aiBriefingState = .updating
        guard DashboardAIBriefingCache.shared.beginRefresh(for: key) else { return }
        let classId = context?.classId?.int64Value
        Task { @MainActor in
            defer { DashboardAIBriefingCache.shared.finishRefresh(for: key) }
            do {
                let draft = try await teachingAssistantService.generateDailyBriefingDraft(
                    bridge: bridge,
                    classId: classId,
                    audience: .docente,
                    tone: .breve,
                    customPrompt: nil
                )
                guard activeAIBriefingKey == key else { return }
                DashboardAIBriefingCache.shared.store(draft, for: key)
                aiBriefing = draft
                aiBriefingState = .fresh
            } catch {
                guard activeAIBriefingKey == key else { return }
                let fallback = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: context.map { $0.className.isEmpty ? nil : $0.className } ?? nil)
                if let fallback {
                    aiBriefing = fallback
                }
                aiBriefingState = .failed
            }
        }
    }

    private func aiBriefingKey(snapshot: MacDashboardSnapshot) -> DashboardAIBriefingCacheKey {
        let context = snapshot.context
        return DashboardAIBriefingCacheKey(classId: context?.classId?.int64Value, scope: "macOS")
    }

    private func proactiveActionAvailable(_ action: DashboardProactiveAction) -> Bool {
        let classId = activeContext?.classId?.int64Value
        switch action {
        case .passList, .openNotebook, .evaluatePending, .quickEvaluation, .openReports:
            return classId != nil
        case .openPlanner:
            return true
        case .reviewPhysicalEducation:
            return classId != nil
        case .reviewSystem, .openInspector:
            return false
        }
    }

    private func handleProactiveAction(_ action: DashboardProactiveAction) {
        let classId = activeContext?.classId?.int64Value
        switch action {
        case .passList:
            handleQuickAction(.attendance(classId: classId))
        case .openNotebook:
            handleQuickAction(.notebook(classId: classId))
        case .evaluatePending:
            handleQuickAction(.rubrics(classId: classId))
        case .quickEvaluation:
            activeSheet = .quickEvaluation(classId: classId)
        case .openPlanner:
            handleQuickAction(.plannerAgenda)
        case .openReports:
            handleQuickAction(.reports(classId: classId))
        case .reviewPhysicalEducation:
            handleQuickAction(.notebook(classId: classId))
        case .reviewSystem, .openInspector:
            break
        }
    }

    private func buildSnapshot(context: DashboardSessionContext?) async throws -> MacDashboardSnapshot {
        let pending = try await pendingItems(for: context)
        return MacDashboardSnapshot(
            context: context,
            pendingItems: pending,
            syncStatus: DashboardSyncSummary(bridge: bridge),
            quickActions: DashboardQuickAction.defaults(for: context)
        )
    }


    private func pendingItems(for context: DashboardSessionContext?) async throws -> [DashboardPendingItem] {
        var items: [DashboardPendingItem] = []

        if let context, context.classId != nil, context.sessionId == nil {
            items.append(
                DashboardPendingItem(
                    title: context.status == .active ? "Crear diario de sesión" : "Próxima clase sin sesión creada",
                    subtitle: "Hay clase en el horario fijo, pero no hay sesión planificada asociada.",
                    priority: context.status == .active ? .high : .medium,
                    destination: .plannerAgenda
                )
            )
        }

        if let context, let classId = context.classId?.int64Value {
            let records = try await bridge.attendanceRecords(for: classId, on: Date())
            if records.isEmpty {
                items.append(
                    DashboardPendingItem(
                        title: "Asistencia pendiente de hoy",
                        subtitle: "Abre Asistencia para pasar lista; el dashboard no marcará nada automáticamente.",
                        priority: context.status == .active ? .high : .medium,
                        destination: .attendance(classId: classId)
                    )
                )
            }
        }

        if dashboardStore.syncPendingChanges > 0 {
            items.append(
                DashboardPendingItem(
                    title: "\(dashboardStore.syncPendingChanges) cambios pendientes de sync",
                    subtitle: dashboardStore.pairedSyncHost.map { "Conectado a \($0)" } ?? "Sync local inactivo o desconectado.",
                    priority: .medium,
                    destination: nil
                )
            )
        }

        return items
    }

    private func handleQuickAction(_ destination: MacDashboardDestination) {
        switch destination {
        case .plannerSession(let sessionId):
            onNavigate(.plannerSession(sessionId: sessionId))
        case .rubrics(let classId):
            onNavigate(.rubrics(classId: classId))
        default:
            onNavigate(destination)
        }
    }
}

private enum MacDashboardLoadState {
    case loading
    case ready(MacDashboardSnapshot)
    case empty(MacDashboardEmptyReason)
    case error(String)
}

/// Única razón que justifica vaciar la página entera: sin clases no hay nada
/// que enseñar. Sin horario o fuera de curso sí hay dashboard, y lo avisa la
/// tarjeta "Ahora".
private enum MacDashboardEmptyReason {
    case noClasses
}

private struct MacDashboardSnapshot {
    /// Antes había dos contextos (`currentClassContext` y `nextClassContext`)
    /// resueltos aquí en Swift. Ahora es uno solo y viene del backend, dentro
    /// del `DashboardSnapshot` compartido con iPad: su `status` ya distingue si
    /// la clase está en curso o es la siguiente.
    let context: DashboardSessionContext?
    let pendingItems: [DashboardPendingItem]
    let syncStatus: DashboardSyncSummary
    let quickActions: [DashboardQuickAction]

    var proactiveSnapshot: DashboardProactiveSnapshot {
        DashboardProactiveSnapshot(
            todayCount: context?.status == .active ? 1 : 0,
            alertsCount: pendingItems.filter { $0.priority == .high }.count,
            pendingCount: pendingItems.count,
            nextSessionLabel: context.map { $0.className.isEmpty ? "Sin próxima sesión" : $0.className } ?? "Sin próxima sesión",
            todaySessions: [context].compactMap { context in
                guard let context else { return nil }
                return DashboardProactiveSession(
                    id: "\(context.scheduleSlotId?.int64Value ?? context.classId?.int64Value ?? -1)",
                    groupName: context.className.isEmpty ? "Grupo" : context.className,
                    timeLabel: [context.startTime, context.endTime].compactMap { $0 }.joined(separator: "-"),
                    didacticUnit: context.sessionTitle ?? context.unitLabel ?? "Sin sesión planificada",
                    sessionStatus: dashboardContextStatusLabel(context.status)
                )
            },
            alerts: pendingItems.map { item in
                DashboardProactiveSignal(
                    id: item.id.uuidString,
                    type: "pending",
                    title: item.title,
                    detail: item.subtitle,
                    severity: item.priority.proactiveSeverity,
                    count: 1
                )
            }
        )
    }
}

private struct DashboardPendingItem: Identifiable {
    enum Priority: Equatable {
        case low
        case medium
        case high

        var tint: Color {
            switch self {
            case .low: return MacAppStyle.successTint
            case .medium: return MacAppStyle.warningTint
            case .high: return MacAppStyle.dangerTint
            }
        }

        var proactiveSeverity: String {
            switch self {
            case .low: return "low"
            case .medium: return "medium"
            case .high: return "high"
            }
        }
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let priority: Priority
    let destination: MacDashboardDestination?
}

private struct DashboardSyncSummary {
    let message: String
    let pendingChanges: Int
    let lastRunAt: Date?
    let pairedHost: String?
    let state: State

    enum State {
        case synced
        case pending
        case disconnected
        case inactive

        var tint: Color {
            switch self {
            case .synced: return MacAppStyle.successTint
            case .pending: return MacAppStyle.warningTint
            case .disconnected: return MacAppStyle.dangerTint
            case .inactive: return .secondary
            }
        }
    }

    @MainActor init(bridge: KmpBridge) {
        message = bridge.syncStatusMessage
        pendingChanges = bridge.syncPendingChanges
        lastRunAt = bridge.syncLastRunAt
        pairedHost = bridge.pairedSyncHost
        if bridge.syncPendingChanges > 0 {
            state = .pending
        } else if bridge.pairedSyncHost != nil {
            state = .synced
        } else if bridge.syncStatusMessage.lowercased().contains("error") {
            state = .disconnected
        } else {
            state = .inactive
        }
    }
}

private struct DashboardQuickAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let destination: MacDashboardDestination?
    let sheet: DashboardSheet?

    static func defaults(for context: DashboardSessionContext?) -> [DashboardQuickAction] {
        let classId = context?.classId?.int64Value
        return [
            .init(id: "attendance", title: "Pasar lista", systemImage: "checkmark.circle", destination: .attendance(classId: classId), sheet: nil),
            .init(id: "notebook", title: "Abrir cuaderno", systemImage: "tablecells", destination: .notebook(classId: classId), sheet: nil),
            .init(id: "rubrics", title: "Evaluar rúbrica", systemImage: "checklist.checked", destination: .rubrics(classId: classId), sheet: nil),
            .init(id: "observation", title: "Preparar observación", systemImage: "note.text.badge.plus", destination: nil, sheet: .observation(classId: classId)),
            .init(id: "quick-evaluation", title: "Preparar evaluación", systemImage: "sparkles", destination: nil, sheet: .quickEvaluation(classId: classId))
        ]
    }
}

private enum DashboardSheet: Identifiable, Hashable {
    case quickEvaluation(classId: Int64?)
    case observation(classId: Int64?)

    var id: String {
        switch self {
        case .quickEvaluation(let classId): return "quick-\(classId ?? -1)"
        case .observation(let classId): return "observation-\(classId ?? -1)"
        }
    }
}

private struct MacPanel<Content: View>: View {
    let title: String
    var role: MacLiquidGlassSurfaceRole = .primaryPanel
    var tint: Color? = nil
    let content: Content

    init(
        title: String,
        role: MacLiquidGlassSurfaceRole = .primaryPanel,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.role = role
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacSectionHeader(title: title)
            content
        }
        .padding(MacAppStyle.innerPadding)
        .macLiquidGlassPanel(role, isActive: true, tint: tint)
    }
}

private struct DashboardHeroNowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let context: DashboardSessionContext?
    /// El color del grupo se sigue resolviendo en Swift (`plannerCourseColor`),
    /// porque es cromado de la app y no dato del snapshot.
    let tintHex: String?
    let onAction: (MacDashboardDestination) -> Void
    let onOpenSheet: (DashboardSheet) -> Void

    var body: some View {
        MacPanel(title: "Ahora", tint: panelTint) {
            // El cuerpo de la tarjeta es exactamente el mismo que en iPad
            // (`dashboardNowCard`): antes eran dos implementaciones distintas
            // sobre dos modelos distintos. Aquí solo queda el marco de macOS.
            dashboardNowCard(
                context: context,
                colorScheme: colorScheme,
                isCompact: false,
                onAction: handle
            )
        }
    }

    private var panelTint: Color {
        guard let tintHex else { return MacAppStyle.infoTint }
        return Color(hex: tintHex)
    }

    private func handle(_ action: DashboardNowAction) {
        let classId = context?.classId?.int64Value
        switch action {
        case .passList:
            onAction(.attendance(classId: classId))
        case .openNotebook:
            onAction(.notebook(classId: classId))
        case .evaluate:
            onAction(.rubrics(classId: classId))
        case .observation:
            onOpenSheet(.observation(classId: classId))
        case .quickEvaluation:
            onOpenSheet(.quickEvaluation(classId: classId))
        case .openPlanner:
            onAction(.plannerAgenda)
        case .openJournal:
            onAction(.plannerSession(sessionId: context?.sessionId?.int64Value))
        }
    }
}


private struct DashboardQuickActionButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .macLiquidGlassPanel(.secondaryPanel, cornerRadius: 12, isInteractive: true)
    }
}

private struct DashboardPendingCard: View {
    let items: [DashboardPendingItem]
    let onNavigate: (MacDashboardDestination) -> Void

    var body: some View {
        MacPanel(title: "Pendientes", tint: items.first?.priority.tint ?? MacAppStyle.infoTint) {
            VStack(spacing: 12) {
                if items.isEmpty {
                    Text("Sin pendientes fiables con los datos disponibles.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(MacAppStyle.subtleFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    pendingGroup("Resolver ahora", items: items.filter { $0.priority == .high })
                    pendingGroup("Preparar", items: items.filter { $0.priority == .medium })
                    pendingGroup("Revisar", items: items.filter { $0.priority == .low })
                    let groupedCount = items.filter { $0.priority == .high || $0.priority == .medium || $0.priority == .low }.count
                    if groupedCount == 0 {
                        Text("Sin pendientes categorizados.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pendingGroup(_ title: String, items: [DashboardPendingItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    Button {
                        if let destination = item.destination {
                            onNavigate(destination)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(item.priority.tint)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.callout.weight(.semibold))
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.destination != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(16)
                        .background(MacAppStyle.subtleFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(MacHoverableButtonStyle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct DashboardRiskCard: View {
    let snapshot: MacDashboardSnapshot
    let insights: [DashboardProactiveInsight]
    let onNavigate: (MacDashboardDestination) -> Void

    private var riskItems: [DashboardPendingItem] {
        snapshot.pendingItems.filter { $0.priority == .high }
    }

    private var proactiveRiskItems: [DashboardProactiveInsight] {
        insights.filter { $0.priority >= .high && $0.kind != .system }
    }

    var body: some View {
        MacPanel(title: "Riesgo", tint: riskItems.isEmpty && proactiveRiskItems.isEmpty ? MacAppStyle.successTint : MacAppStyle.warningTint) {
            VStack(spacing: 12) {
                if riskItems.isEmpty {
                    if proactiveRiskItems.isEmpty {
                        Text("Sin alumnado o sesiones en riesgo inmediato con los datos cargados.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(MacAppStyle.subtleFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        ForEach(proactiveRiskItems.prefix(2)) { insight in
                            proactiveRiskRow(insight)
                        }
                    }
                } else {
                    ForEach(riskItems) { item in
                        Button {
                            if let destination = item.destination {
                                onNavigate(destination)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(item.priority.tint)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title)
                                        .font(.callout.weight(.semibold))
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let recommendation = DashboardRecommendations.action(
                                        type: "", title: item.title, detail: item.subtitle
                                    ) {
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "lightbulb.fill")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.yellow)
                                            Text(recommendation)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(MacAppStyle.subtleFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(MacHoverableButtonStyle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func proactiveRiskRow(_ insight: DashboardProactiveInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.kind.systemImage)
                .foregroundStyle(insight.priority.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(.callout.weight(.semibold))
                Text(insight.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardStatusCard: View {
    let summary: DashboardSyncSummary
    @ObservedObject var backupStore: MacBackupStore
    let platformName: String

    var body: some View {
        MacPanel(title: "Sistema", tint: summary.state.tint) {
            VStack(alignment: .leading, spacing: 12) {
                statusRow("Sync LAN", value: summaryLine, tint: summary.state.tint)
                statusRow("Cambios pendientes", value: "\(summary.pendingChanges)", tint: summary.pendingChanges > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint)
                statusRow("Última sync", value: summary.lastRunAt.map(Self.relativeTime) ?? "Sin registro", tint: .secondary)
                statusRow("Último backup", value: backupLine, tint: backupStore.latestBackup == nil ? MacAppStyle.warningTint : MacAppStyle.successTint)
                statusRow("Host", value: summary.pairedHost ?? "Sync local inactivo", tint: summary.pairedHost == nil ? .secondary : MacAppStyle.infoTint)
                statusRow("Plataforma", value: platformName, tint: .secondary)
            }
        }
    }

    private var summaryLine: String {
        if summary.pendingChanges > 0 {
            return "\(summary.pendingChanges) cambios pendientes"
        }
        if let lastRunAt = summary.lastRunAt {
            return "Sincronizado · \(Self.relativeTime(lastRunAt))"
        }
        return summary.message.isEmpty ? "Sync local inactivo" : summary.message
    }

    private var backupLine: String {
        guard let latestBackup = backupStore.latestBackup else {
            return "Sin backup registrado"
        }
        return "\(Self.relativeTime(latestBackup.createdAt)) · \(latestBackup.sizeBytes.macBackupFileSizeText)"
    }

    private func statusRow(_ title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func absoluteTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SyncStatusCompactView: View {
    let summary: DashboardSyncSummary

    var body: some View {
        MacStatusPill(
            label: label,
            isActive: summary.state == .synced || summary.state == .pending,
            tint: summary.state.tint
        )
    }

    private var label: String {
        if summary.pendingChanges > 0 {
            return "\(summary.pendingChanges) pendientes"
        }
        if summary.pairedHost != nil {
            return "Sincronizado"
        }
        return "Sync local inactivo"
    }
}

private struct DashboardLoadingView: View {
    var body: some View {
        MacPanel(title: "Ahora") {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView("Cargando dashboard…")
                    .controlSize(.large)
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MacAppStyle.subtleFill)
                        .frame(height: 44)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        }
    }
}

private struct DashboardEmptyStateView: View {
    let reason: MacDashboardEmptyReason
    let onNavigate: (MacDashboardDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacPanel(title: "Ahora", tint: tint) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.title2.weight(.semibold))
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 24)

                    Button(buttonTitle) {
                        onNavigate(destination)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(actions) { action in
                    Button {
                        onNavigate(action.destination)
                    } label: {
                        DashboardEmptyActionCard(action: action)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var title: String {
        switch reason {
        case .noClasses: return "Sin clases"
        }
    }

    private var message: String {
        switch reason {
        case .noClasses: return "Todavía no hay clases creadas."
        }
    }

    private var buttonTitle: String {
        switch reason {
        case .noClasses: return "Crear clase"
        }
    }

    private var destination: MacDashboardDestination {
        switch reason {
        case .noClasses: return .students(classId: nil)
        }
    }

    private var systemImage: String {
        switch reason {
        case .noClasses: return "person.3.sequence"
        }
    }

    private var tint: Color {
        switch reason {
        case .noClasses: return MacAppStyle.infoTint
        }
    }

    private var actions: [DashboardEmptyAction] {
        switch reason {
        case .noClasses:
            return [
                .init(title: "Crear grupo", subtitle: "Empieza por el alumnado y sus clases.", systemImage: "person.3.sequence", destination: .students(classId: nil), tint: MacAppStyle.infoTint),
                .init(title: "Preparar agenda", subtitle: "Define el marco del curso.", systemImage: "calendar", destination: .plannerAgenda, tint: MacAppStyle.warningTint)
            ]
        }
    }
}

private struct DashboardEmptyAction: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let destination: MacDashboardDestination
    let tint: Color

    var id: String { title }
}

private struct DashboardEmptyActionCard: View {
    let action: DashboardEmptyAction

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: action.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(action.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(action.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(action.subtitle)
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
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .macLiquidGlassPanel(.secondaryPanel, cornerRadius: 14, tint: action.tint.opacity(0.5), isInteractive: true)
    }
}

private struct DashboardErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        MacPanel(title: "Error") {
            VStack(alignment: .leading, spacing: 16) {
                Label("No se pudo preparar el dashboard", systemImage: "exclamationmark.triangle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MacAppStyle.dangerTint)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reintentar", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        }
    }
}

private struct QuickEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    let initialClassId: Int64?
    let onCancel: () -> Void
    let onOpenNotebook: (Int64?) -> Void

    @State private var selectedClassId: Int64?
    @State private var instruments: [PreparedEvaluationInstrument] = PreparedEvaluationInstrument.defaults
    @State private var activeInstrumentId: UUID?
    @State private var showingRubricImporter = false
    @State private var showingRubricBuilder = false
    @State private var importPreview: AppleRubricImportPreview?
    @State private var errorMessage: String?
    @State private var isCreatingColumns = false

    private var selectedInstruments: [PreparedEvaluationInstrument] {
        instruments.filter(\.isSelected)
    }

    private var canCreateColumns: Bool {
        selectedClassId != nil &&
        !selectedInstruments.isEmpty &&
        selectedInstruments.allSatisfy { $0.rubricId != nil && parsedWeight(for: $0) != nil } &&
        !isCreatingColumns
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    classSelector
                    instrumentsSection
                    statusBlock
                }
                .padding(MacAppStyle.pagePadding)
            }

            Divider()
            footer
        }
        .background(MacAppStyle.pageBackground)
        .onAppear {
            selectedClassId = initialClassId ?? bridge.classes.first?.id
            loadSelection()
        }
        .appOnChange(of: selectedClassId) { _ in
            loadSelection()
        }
        .fileImporter(
            isPresented: $showingRubricImporter,
            allowedContentTypes: [.xlsx, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleRubricImportFile(result) }
        }
        .sheet(item: $importPreview) { preview in
            DashboardRubricImportPreviewSheet(preview: preview) {
                importPreview = nil
            } confirm: {
                Task { await confirmRubricImport(preview) }
            }
        }
        .sheet(isPresented: $showingRubricBuilder) {
            RubricsBuilderScreen(onSaved: { rubricId in
                attachRubric(rubricId)
                showingRubricBuilder = false
            })
            .environmentObject(bridge)
            .frame(minWidth: 1_120, idealWidth: 1_280, maxWidth: 1_600, minHeight: 720, idealHeight: 900)
        }
        .alert("No se pudo preparar la evaluación", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(MacAppStyle.infoTint)
                .frame(width: 48, height: 48)
                .background(MacAppStyle.infoTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Preparar evaluación")
                    .font(.title2.weight(.semibold))
                Text("Crea columnas de rúbrica vinculadas al cuaderno de la clase.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, MacAppStyle.pagePadding)
        .padding(.vertical, 20)
    }

    private var classSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grupo")
                .font(MacAppStyle.sectionTitle)

            Picker("Grupo", selection: $selectedClassId) {
                Text("Seleccionar").tag(Int64?.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var instrumentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instrumentos")
                    .font(MacAppStyle.sectionTitle)
                Spacer()
                Button {
                    instruments.append(PreparedEvaluationInstrument(title: "Nueva rúbrica", weightText: "10"))
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 12) {
                ForEach($instruments) { $instrument in
                    instrumentRow($instrument)
                }
            }
        }
    }

    private func instrumentRow(_ instrument: Binding<PreparedEvaluationInstrument>) -> some View {
        let value = instrument.wrappedValue
        let selectedRubric = bridge.rubrics.first { $0.rubric.id == value.rubricId }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: instrument.isSelected)
                    .labelsHidden()

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Nombre del instrumento", text: instrument.title)
                        .font(.headline)
                        .textFieldStyle(.plain)

                    HStack(spacing: 12) {
                        TextField("Peso", text: instrument.weightText)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        Text("%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MacStatusPill(
                            label: selectedRubric == nil ? "Sin rúbrica" : "Rúbrica vinculada",
                            isActive: selectedRubric != nil,
                            tint: selectedRubric == nil ? MacAppStyle.warningTint : MacAppStyle.successTint
                        )
                    }
                }

                Spacer(minLength: 16)

                Menu {
                    if availableRubrics.isEmpty {
                        Text("No hay rúbricas disponibles")
                    } else {
                        ForEach(availableRubrics, id: \.rubric.id) { rubric in
                            Button {
                                instrument.wrappedValue.rubricId = rubric.rubric.id
                                instrument.wrappedValue.rubricName = rubric.rubric.name
                            } label: {
                                Label(rubric.rubric.name, systemImage: "checklist")
                            }
                        }
                    }

                    Divider()

                    Button {
                        startRubricBuilder(for: value.id)
                    } label: {
                        Label("Crear rúbrica", systemImage: "plus.square")
                    }

                    Button {
                        activeInstrumentId = value.id
                        showingRubricImporter = true
                    } label: {
                        Label("Importar desde Excel", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Rúbrica", systemImage: "ellipsis.circle")
                }
                .menuStyle(.button)
            }

            if let selectedRubric {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedRubric.rubric.name)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        Label("\(selectedRubric.criteria.count) criterios", systemImage: "list.bullet.rectangle")
                        if isCurrentClassRubric(selectedRubric) {
                            Label("Grupo actual", systemImage: "person.2.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var statusBlock: some View {
        if selectedInstruments.isEmpty {
            Label("Selecciona al menos un instrumento.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !canCreateColumns {
            Label("Cada instrumento seleccionado necesita peso válido y rúbrica.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(MacAppStyle.warningTint)
        } else {
            Label("Se crearán \(selectedInstruments.count) columna(s) de rúbrica en el cuaderno.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(MacAppStyle.successTint)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Cancelar", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button {
                onOpenNotebook(selectedClassId)
            } label: {
                Label("Abrir cuaderno", systemImage: "tablecells")
            }
            .disabled(selectedClassId == nil)

            Spacer()

            Button {
                Task { await createColumns() }
            } label: {
                Label(isCreatingColumns ? "Creando..." : "Crear columnas", systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreateColumns)
        }
        .padding(.horizontal, MacAppStyle.pagePadding)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var availableRubrics: [RubricDetail] {
        bridge.rubrics
            .filter { rubric in
                guard let selectedClassId else { return true }
                let directClassId = rubric.rubric.classId?.int64Value
                return directClassId == nil || directClassId == selectedClassId || bridge.rubricClassLinks[rubric.rubric.id]?.contains(selectedClassId) == true
            }
            .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    private func loadSelection() {
        Task {
            guard let selectedClassId else { return }
            bridge.selectClass(id: selectedClassId)
            await bridge.selectStudentsClass(classId: selectedClassId)
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
        }
    }

    private func startRubricBuilder(for instrumentId: UUID) {
        activeInstrumentId = instrumentId
        bridge.resetRubricBuilder()
        if let selectedClassId {
            bridge.selectRubricClass(selectedClassId)
        }
        if let instrument = instruments.first(where: { $0.id == instrumentId }) {
            bridge.updateRubricName(instrument.title)
        }
        showingRubricBuilder = true
    }

    @MainActor
    private func handleRubricImportFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            importPreview = makeRubricImportPreview(from: rows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmRubricImport(_ preview: AppleRubricImportPreview) async {
        do {
            try await bridge.importRubricDraft(tsv: preview.tsv)
            if let selectedClassId {
                bridge.selectRubricClass(selectedClassId)
            }
            importPreview = nil
            showingRubricBuilder = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachRubric(_ rubricId: Int64) {
        guard let activeInstrumentId,
              let index = instruments.firstIndex(where: { $0.id == activeInstrumentId }) else { return }
        instruments[index].rubricId = rubricId
        instruments[index].rubricName = bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? instruments[index].title
    }

    @MainActor
    private func createColumns() async {
        guard let selectedClassId else { return }
        isCreatingColumns = true
        defer { isCreatingColumns = false }
        bridge.selectClass(id: selectedClassId)

        do {
            for instrument in selectedInstruments {
                guard let rubricId = instrument.rubricId,
                      let weight = parsedWeight(for: instrument) else { continue }
                _ = try await bridge.addColumnWithOptionalCategory(
                    name: instrument.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rúbrica" : instrument.title,
                    type: NotebookColumnType.rubric.name,
                    weight: weight,
                    formula: nil,
                    rubricId: rubricId,
                    categoryKind: .evaluation,
                    instrumentKind: .rubric,
                    inputKind: .rubric,
                    scaleKind: .tenPoint,
                    iconName: "checklist",
                    countsTowardAverage: true
                )
            }
            onOpenNotebook(selectedClassId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedWeight(for instrument: PreparedEvaluationInstrument) -> Double? {
        let normalized = instrument.weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private func isCurrentClassRubric(_ rubric: RubricDetail) -> Bool {
        guard let selectedClassId else { return false }
        return rubric.rubric.classId?.int64Value == selectedClassId ||
            bridge.rubricClassLinks[rubric.rubric.id]?.contains(selectedClassId) == true
    }

    private func makeRubricImportPreview(from rows: [[String]]) -> AppleRubricImportPreview {
        let tsv = rows.tsvText
        let nonEmptyRows = rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let header = nonEmptyRows.first ?? []
        let levels = header.dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let criteriaRows = nonEmptyRows.dropFirst().filter { row in
            row.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        var warnings: [String] = []
        if levels.isEmpty {
            warnings.append("No se han detectado niveles en la primera fila.")
        }
        if criteriaRows.isEmpty {
            warnings.append("No se han detectado criterios con descripción.")
        }
        for (index, row) in criteriaRows.enumerated() {
            let filledDescriptions = row.dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            let missingDescriptions = max(0, levels.count - filledDescriptions)
            if missingDescriptions > 0 {
                warnings.append("Criterio \(index + 1) tiene \(missingDescriptions) nivel(es) sin descripción.")
            }
        }
        let numericLevelCount = levels.filter { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil }.count
        if numericLevelCount > 0 {
            warnings.append("\(numericLevelCount) nivel(es) parecen numéricos; revisa la escala antes de guardar.")
        }
        return AppleRubricImportPreview(
            title: "Rúbrica importada",
            levelCount: levels.count,
            criterionCount: criteriaRows.count,
            warnings: warnings,
            tsv: tsv
        )
    }
}

private struct PreparedEvaluationInstrument: Identifiable {
    let id = UUID()
    var title: String
    var weightText: String
    var isSelected = true
    var rubricId: Int64?
    var rubricName: String?

    static let defaults: [PreparedEvaluationInstrument] = [
        PreparedEvaluationInstrument(title: "Diseño del Plan de Entrenamiento", weightText: "40"),
        PreparedEvaluationInstrument(title: "Ejecución y Autorregulación", weightText: "40"),
        PreparedEvaluationInstrument(title: "Desempeño del Rol de Coach y Cooperación", weightText: "20")
    ]
}

private struct DashboardRubricImportPreviewSheet: View {
    let preview: AppleRubricImportPreview
    let cancel: () -> Void
    let confirm: () -> Void

    private var canConfirm: Bool {
        preview.levelCount > 0 && preview.criterionCount > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "checklist")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MacAppStyle.infoTint)
                    .frame(width: 48, height: 48)
                    .background(MacAppStyle.infoTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Importar rúbrica")
                        .font(.title2.weight(.semibold))
                    Text(preview.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, MacAppStyle.pagePadding)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        previewMetric(title: "Niveles", value: "\(preview.levelCount)", icon: "slider.horizontal.below.square")
                        previewMetric(title: "Criterios", value: "\(preview.criterionCount)", icon: "list.bullet.rectangle")
                        previewMetric(title: "Advertencias", value: "\(preview.warnings.count)", icon: "exclamationmark.triangle")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Validación")
                            .font(.headline)
                        if preview.warnings.isEmpty {
                            Label("Estructura lista para revisar en el editor.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(MacAppStyle.successTint)
                        } else {
                            ForEach(preview.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout)
                                    .foregroundStyle(MacAppStyle.warningTint)
                            }
                        }
                    }
                    .padding(MacAppStyle.innerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                }
                .padding(MacAppStyle.pagePadding)
            }

            Divider()

            HStack(spacing: 16) {
                Text(canConfirm ? "Se abrirá en el editor para revisión final." : "La rúbrica necesita niveles y criterios.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancelar", action: cancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button {
                    confirm()
                } label: {
                    Label("Abrir en editor", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
            .padding(.horizontal, MacAppStyle.pagePadding)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 600, height: 430)
        .background(MacAppStyle.pageBackground)
    }

    private func previewMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct ObservationComposerSheet: View {
    @ObservedObject var bridge: KmpBridge
    let initialClassId: Int64?
    let onCancel: () -> Void
    let onOpenStudents: (Int64?) -> Void

    @State private var selectedClassId: Int64?
    @State private var selectedStudentId: Int64?
    @State private var type = "Seguimiento"
    @State private var text = ""
    @State private var requiresFollowUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Registrar observación")
                .font(.title2.weight(.semibold))
            Form {
                Picker("Clase", selection: $selectedClassId) {
                    Text("Seleccionar").tag(Int64?.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
                    }
                }
                Picker("Alumno opcional", selection: $selectedStudentId) {
                    Text("Sin alumno").tag(Int64?.none)
                    ForEach(Array(bridge.studentsInClass), id: \.id) { student in
                        Text(student.fullName).tag(Optional(student.id))
                    }
                }
                Picker("Tipo", selection: $type) {
                    Text("Seguimiento").tag("Seguimiento")
                    Text("Convivencia").tag("Convivencia")
                    Text("Académica").tag("Académica")
                    Text("Familia").tag("Familia")
                }
                TextField("Texto", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                Toggle("Requiere seguimiento", isOn: $requiresFollowUp)
            }
            Text("El dashboard no crea observaciones automáticamente. Esta sheet prepara el contexto; el guardado queda pendiente de un método seguro específico.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Cancelar", action: onCancel)
                Spacer()
                Button("Abrir alumnado") {
                    onOpenStudents(selectedClassId)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedClassId == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .onAppear {
            selectedClassId = initialClassId
            loadStudents()
        }
        .appOnChange(of: selectedClassId) { _ in
            loadStudents()
        }
    }

    private func loadStudents() {
        Task {
            guard let selectedClassId else { return }
            bridge.selectClass(id: selectedClassId)
            await bridge.selectStudentsClass(classId: selectedClassId)
        }
    }
}
