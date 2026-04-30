import SwiftUI
import MiGestorKit

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
    @ObservedObject var bridge: KmpBridge
    let bootstrap: AppleBridgeBootstrap
    var onNavigate: (MacDashboardDestination) -> Void = { _ in }
    var onToolbarActionsChange: (MacDashboardToolbarActions?) -> Void = { _ in }

    @State private var loadState: MacDashboardLoadState = .loading
    @State private var reloadTask: Task<Void, Never>?
    @State private var activeSheet: DashboardSheet?

    private var activeContext: CurrentClassDashboardContext? {
        guard case .ready(let snapshot) = loadState else { return nil }
        return snapshot.currentClassContext ?? snapshot.nextClassContext
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
                .frame(minWidth: 560, minHeight: 520)
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
        }
        .onAppear {
            syncToolbarActions()
        }
        .onDisappear {
            reloadTask?.cancel()
            onToolbarActionsChange(nil)
        }
        .onChange(of: toolbarKey) { _ in
            syncToolbarActions()
        }
        .onChange(of: bridge.syncPendingChanges) { _ in
            scheduleReload()
        }
        .onChange(of: bridge.pairedSyncHost) { _ in
            scheduleReload()
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dashboard")
                    .font(MacAppStyle.pageTitle)
                Text("Tu centro de mando diario")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SyncStatusCompactView(summary: DashboardSyncSummary(bridge: bridge))
        }
    }

    @ViewBuilder
    private func readyContent(snapshot: MacDashboardSnapshot, isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                DashboardHeroNowCard(
                    context: snapshot.currentClassContext ?? snapshot.nextClassContext,
                    onAction: handleQuickAction,
                    onOpenSheet: { activeSheet = $0 }
                )
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 24) {
                    DashboardPendingCard(items: snapshot.pendingItems, onNavigate: onNavigate)
                    DashboardStatusCard(summary: snapshot.syncStatus, platformName: bootstrap.platformName)
                }
                .frame(width: 380)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeroNowCard(
                    context: snapshot.currentClassContext ?? snapshot.nextClassContext,
                    onAction: handleQuickAction,
                    onOpenSheet: { activeSheet = $0 }
                )
                DashboardPendingCard(items: snapshot.pendingItems, onNavigate: onNavigate)
                DashboardStatusCard(summary: snapshot.syncStatus, platformName: bootstrap.platformName)
            }
        }
    }

    private var toolbarKey: String {
        let context = activeContext
        return "\(context?.classId ?? -1)|\(context?.status.rawValue ?? "none")|\(bridge.syncPendingChanges)|\(bridge.pairedSyncHost ?? "")"
    }

    private func syncToolbarActions() {
        onToolbarActionsChange(
            MacDashboardToolbarActions(
                canRunActions: activeContext?.classId != nil,
                refresh: { scheduleReload() },
                passList: { handleQuickAction(.attendance(classId: activeContext?.classId)) },
                observation: { activeSheet = .observation(classId: activeContext?.classId) }
            )
        )
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
            guard !bridge.classes.isEmpty else {
                loadState = .empty(.noClasses)
                return
            }

            let schedule = try await bridge.plannerTeacherSchedule()
            let slots = try await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)
            guard !slots.isEmpty else {
                loadState = .empty(.noScheduleConfigured)
                return
            }

            let now = Date()
            guard Self.date(now, isInside: schedule.startDateIso, and: schedule.endDateIso) else {
                loadState = .empty(.outsideSchoolYear(startDate: schedule.startDateIso, endDate: schedule.endDateIso))
                return
            }

            let activeWeekdays = Self.weekdays(from: schedule.activeWeekdaysCsv)
            let today = Self.plannerWeekday(for: now)
            guard activeWeekdays.isEmpty || activeWeekdays.contains(today) else {
                loadState = .ready(
                    try await buildSnapshot(
                        current: nil,
                        next: nextContext(from: slots, schedule: schedule, now: now, statusForToday: false)
                    )
                )
                return
            }

            let sortedSlots = slots.sorted(by: Self.slotOrder)
            if let activeSlot = sortedSlots.first(where: { slot in
                Int(slot.dayOfWeek) == today && Self.time(now, isBetween: slot.startTime, and: slot.endTime)
            }) {
                let context = try await context(
                    for: activeSlot,
                    status: .active,
                    schedule: schedule,
                    now: now,
                    includeSession: true
                )
                loadState = .ready(try await buildSnapshot(current: context, next: nil))
            } else if let next = try await nextContext(from: sortedSlots, schedule: schedule, now: now, statusForToday: true) {
                loadState = .ready(try await buildSnapshot(current: nil, next: next))
            } else {
                loadState = .empty(.noScheduleConfigured)
            }
        } catch {
            loadState = .error("No se pudo cargar el dashboard: \(error.localizedDescription)")
        }
        syncToolbarActions()
    }

    private func buildSnapshot(
        current: CurrentClassDashboardContext?,
        next: CurrentClassDashboardContext?
    ) async throws -> MacDashboardSnapshot {
        let pending = try await pendingItems(for: current ?? next)
        return MacDashboardSnapshot(
            currentClassContext: current,
            nextClassContext: next,
            pendingItems: pending,
            syncStatus: DashboardSyncSummary(bridge: bridge),
            quickActions: DashboardQuickAction.defaults(for: current ?? next)
        )
    }

    private func nextContext(
        from slots: [TeacherScheduleSlot],
        schedule: TeacherSchedule,
        now: Date,
        statusForToday: Bool
    ) async throws -> CurrentClassDashboardContext? {
        let today = Self.plannerWeekday(for: now)
        if statusForToday,
           let todaySlot = slots
            .filter({ Int($0.dayOfWeek) == today && Self.time($0.startTime, isAfter: now) })
            .sorted(by: Self.slotOrder)
            .first {
            return try await context(for: todaySlot, status: .nextToday, schedule: schedule, now: now, includeSession: true)
        }

        for offset in 1...7 {
            guard let candidateDate = Calendar.current.date(byAdding: .day, value: offset, to: now) else { continue }
            let day = Self.plannerWeekday(for: candidateDate)
            let activeWeekdays = Self.weekdays(from: schedule.activeWeekdaysCsv)
            guard activeWeekdays.isEmpty || activeWeekdays.contains(day) else { continue }
            if let slot = slots.filter({ Int($0.dayOfWeek) == day }).sorted(by: Self.slotOrder).first {
                return try await context(for: slot, status: .nextOtherDay, schedule: schedule, now: candidateDate, includeSession: false)
            }
        }
        return nil
    }

    private func context(
        for slot: TeacherScheduleSlot,
        status: CurrentClassDashboardContext.Status,
        schedule: TeacherSchedule,
        now: Date,
        includeSession: Bool
    ) async throws -> CurrentClassDashboardContext {
        let classId = slot.schoolClassId
        let schoolClass = bridge.classes.first(where: { $0.id == classId })
        let session = includeSession ? try await plannedSession(for: slot, date: now) : nil
        let journalSummary: SessionJournalSummary?
        if let session {
            journalSummary = try await bridge.plannerJournalSummaries(sessionIds: [session.id]).first
        } else {
            journalSummary = nil
        }
        let journalLabel = Self.journalStatusLabel(journalSummary)
        let subjectLabel = schoolClass.map { "\($0.course)º" }
        let subtitle = [session?.objectives.nilIfBlank, session?.activities.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " · ")

        return CurrentClassDashboardContext(
            status: status,
            classId: classId,
            className: schoolClass?.name ?? session?.groupName ?? "Grupo \(classId)",
            classColorHex: bridge.plannerCourseColor(for: classId),
            subjectLabel: subjectLabel,
            unitLabel: session?.teachingUnitName.nilIfBlank,
            startTime: slot.startTime,
            endTime: slot.endTime,
            dayOfWeek: Int(slot.dayOfWeek),
            scheduleSlotId: slot.id,
            sessionId: session?.id,
            sessionTitle: session?.teachingUnitName.nilIfBlank,
            sessionSubtitle: subtitle.nilIfBlank,
            sessionStatusLabel: session.map { $0.status == .completed ? "Impartida" : "Planificada" } ?? journalLabel,
            isFromPlannedSession: session != nil
        )
    }

    private func plannedSession(for slot: TeacherScheduleSlot, date: Date) async throws -> PlanningSession? {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let sessions = try await bridge.plannerListSessions(weekNumber: week, year: year, classId: slot.schoolClassId)
        let dayOfWeek = Int(slot.dayOfWeek)
        return sessions.first { session in
            Int(session.dayOfWeek) == dayOfWeek
        }
    }

    private func pendingItems(for context: CurrentClassDashboardContext?) async throws -> [DashboardPendingItem] {
        var items: [DashboardPendingItem] = []

        if let context, context.classId != nil, context.status == .active, context.sessionId == nil {
            items.append(
                DashboardPendingItem(
                    title: "Sesión de Planner sin crear",
                    subtitle: "Hay clase en el horario fijo, pero no hay sesión planificada asociada.",
                    priority: .medium,
                    destination: .plannerAgenda
                )
            )
        }

        if let context, let classId = context.classId {
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

        if bridge.syncPendingChanges > 0 {
            items.append(
                DashboardPendingItem(
                    title: "\(bridge.syncPendingChanges) cambios pendientes de sync",
                    subtitle: bridge.pairedSyncHost.map { "Conectado a \($0)" } ?? "Sync local inactivo o desconectado.",
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

    private static func plannerWeekday(for date: Date) -> Int {
        let appleWeekday = Calendar.current.component(.weekday, from: date)
        return appleWeekday == 1 ? 7 : appleWeekday - 1
    }

    private static func weekdays(from csv: String) -> Set<Int> {
        Set(csv.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
    }

    private static func date(_ date: Date, isInside startIso: String, and endIso: String) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let start = AppDateTimeSupport.date(fromISO: startIso, fallback: .distantPast)
        let end = AppDateTimeSupport.date(fromISO: endIso, fallback: .distantFuture)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    private static func time(_ date: Date, isBetween start: String, and end: String) -> Bool {
        guard let current = minutes(from: date), let startMinutes = minutes(from: start), let endMinutes = minutes(from: end) else {
            return false
        }
        return current >= startMinutes && current <= endMinutes
    }

    private static func time(_ start: String, isAfter date: Date) -> Bool {
        guard let current = minutes(from: date), let startMinutes = minutes(from: start) else { return false }
        return startMinutes > current
    }

    private static func minutes(from date: Date) -> Int? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }

    private static func minutes(from time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    private static func slotOrder(lhs: TeacherScheduleSlot, rhs: TeacherScheduleSlot) -> Bool {
        if lhs.dayOfWeek == rhs.dayOfWeek {
            return lhs.startTime == rhs.startTime ? lhs.endTime < rhs.endTime : lhs.startTime < rhs.startTime
        }
        return lhs.dayOfWeek < rhs.dayOfWeek
    }

    private static func journalStatusLabel(_ summary: SessionJournalSummary?) -> String? {
        switch summary?.status {
        case .completed:
            return "Diario cerrado"
        case .draft:
            return "Diario en borrador"
        case .empty, .none:
            return nil
        default:
            return nil
        }
    }
}

private enum MacDashboardLoadState {
    case loading
    case ready(MacDashboardSnapshot)
    case empty(MacDashboardEmptyReason)
    case error(String)
}

private enum MacDashboardEmptyReason {
    case noScheduleConfigured
    case noClasses
    case outsideSchoolYear(startDate: String, endDate: String)
}

private struct MacDashboardSnapshot {
    let currentClassContext: CurrentClassDashboardContext?
    let nextClassContext: CurrentClassDashboardContext?
    let pendingItems: [DashboardPendingItem]
    let syncStatus: DashboardSyncSummary
    let quickActions: [DashboardQuickAction]
}

private struct CurrentClassDashboardContext {
    enum Status: String {
        case active
        case nextToday
        case nextOtherDay
        case noScheduleConfigured
        case outsideSchoolYear
    }

    let status: Status
    let classId: Int64?
    let className: String?
    let classColorHex: String?
    let subjectLabel: String?
    let unitLabel: String?
    let startTime: String?
    let endTime: String?
    let dayOfWeek: Int?
    let scheduleSlotId: Int64?
    let sessionId: Int64?
    let sessionTitle: String?
    let sessionSubtitle: String?
    let sessionStatusLabel: String?
    let isFromPlannedSession: Bool
}

private struct DashboardPendingItem: Identifiable {
    enum Priority {
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

    static func defaults(for context: CurrentClassDashboardContext?) -> [DashboardQuickAction] {
        let classId = context?.classId
        return [
            .init(id: "attendance", title: "Pasar lista", systemImage: "checkmark.circle", destination: .attendance(classId: classId), sheet: nil),
            .init(id: "notebook", title: "Abrir cuaderno", systemImage: "tablecells", destination: .notebook(classId: classId), sheet: nil),
            .init(id: "rubrics", title: "Evaluar rúbrica", systemImage: "checklist.checked", destination: .rubrics(classId: classId), sheet: nil),
            .init(id: "observation", title: "Registrar observación", systemImage: "note.text.badge.plus", destination: nil, sheet: .observation(classId: classId)),
            .init(id: "quick-evaluation", title: "Evaluación rápida", systemImage: "sparkles", destination: nil, sheet: .quickEvaluation(classId: classId))
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
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacSectionHeader(title: title)
            content
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

private struct DashboardHeroNowCard: View {
    let context: CurrentClassDashboardContext?
    let onAction: (MacDashboardDestination) -> Void
    let onOpenSheet: (DashboardSheet) -> Void

    var body: some View {
        MacPanel(title: "Ahora") {
            VStack(alignment: .leading, spacing: 24) {
                if let context {
                    contextHeader(context)
                    if context.isFromPlannedSession {
                        plannedSessionBlock(context)
                    } else if context.status == .active {
                        missingSessionBlock
                    }
                    quickActions(context)
                } else {
                    ContentUnavailableView(
                        "Sin clase activa",
                        systemImage: "calendar",
                        description: Text("No hay una franja lectiva próxima en la agenda docente.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
        }
    }

    private func contextHeader(_ context: CurrentClassDashboardContext) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(Color(hex: context.classColorHex ?? "#2563EB"))
                .frame(width: 14, height: 14)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(title(for: context))
                    .font(.title2.weight(.semibold))
                Text(subtitle(for: context))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let start = context.startTime, let end = context.endTime {
                    Label("\(dayLabel(context.dayOfWeek)) · \(start)-\(end)", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            MacStatusPill(label: statusLabel(context.status), isActive: context.status == .active, tint: statusTint(context.status))
        }
    }

    private func plannedSessionBlock(_ context: CurrentClassDashboardContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sesión planificada", systemImage: "calendar.badge.checkmark")
                .font(.headline)
            Text(context.sessionTitle ?? context.unitLabel ?? "Sesión")
                .font(.callout.weight(.semibold))
            if let subtitle = context.sessionSubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status = context.sessionStatusLabel {
                MacStatusPill(label: status, isActive: true, tint: MacAppStyle.infoTint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var missingSessionBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .foregroundStyle(MacAppStyle.warningTint)
            VStack(alignment: .leading, spacing: 8) {
                Text("No hay sesión planificada para esta franja.")
                    .font(.callout.weight(.semibold))
                Text("Puedes seguir trabajando desde el horario fijo o crear la sesión en Planner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Crear sesión en Planner") {
                onAction(.plannerAgenda)
            }
        }
        .padding(16)
        .background(MacAppStyle.warningTint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func quickActions(_ context: CurrentClassDashboardContext) -> some View {
        let classId = context.classId
        let active = context.status == .active
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
            if active {
                dashboardAction("Pasar lista", "checkmark.circle", .attendance(classId: classId))
                dashboardAction("Abrir cuaderno", "tablecells", .notebook(classId: classId))
                dashboardAction("Evaluar rúbrica", "checklist.checked", .rubrics(classId: classId))
                Button {
                    onOpenSheet(.observation(classId: classId))
                } label: {
                    DashboardQuickActionButton(title: "Registrar observación", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.plain)
                Button {
                    onOpenSheet(.quickEvaluation(classId: classId))
                } label: {
                    DashboardQuickActionButton(title: "Evaluación rápida", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                if let sessionId = context.sessionId {
                    dashboardAction("Abrir diario", "doc.text", .plannerSession(sessionId: sessionId))
                }
            } else {
                dashboardAction("Preparar sesión", "calendar.badge.plus", .plannerAgenda)
                dashboardAction("Abrir planner", "calendar", .plannerAgenda)
                dashboardAction("Abrir cuaderno", "tablecells", .notebook(classId: classId))
            }
        }
    }

    private func dashboardAction(_ title: String, _ systemImage: String, _ destination: MacDashboardDestination) -> some View {
        Button {
            onAction(destination)
        } label: {
            DashboardQuickActionButton(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func title(for context: CurrentClassDashboardContext) -> String {
        switch context.status {
        case .active:
            return context.className ?? "Clase actual"
        case .nextToday, .nextOtherDay:
            return "Próxima clase"
        case .noScheduleConfigured:
            return "Sin horario"
        case .outsideSchoolYear:
            return "Fuera de curso"
        }
    }

    private func subtitle(for context: CurrentClassDashboardContext) -> String {
        let parts = [context.className, context.subjectLabel, context.unitLabel].compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? "Sin detalle de grupo" : parts.joined(separator: " · ")
    }

    private func statusLabel(_ status: CurrentClassDashboardContext.Status) -> String {
        switch status {
        case .active: return "En curso"
        case .nextToday: return "Hoy"
        case .nextOtherDay: return "Próxima"
        case .noScheduleConfigured: return "Sin horario"
        case .outsideSchoolYear: return "Fuera de curso"
        }
    }

    private func statusTint(_ status: CurrentClassDashboardContext.Status) -> Color {
        switch status {
        case .active: return MacAppStyle.successTint
        case .nextToday, .nextOtherDay: return MacAppStyle.infoTint
        case .noScheduleConfigured, .outsideSchoolYear: return MacAppStyle.warningTint
        }
    }

    private func dayLabel(_ day: Int?) -> String {
        switch day {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        case 6: return "Sábado"
        case 7: return "Domingo"
        default: return "Día"
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
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardPendingCard: View {
    let items: [DashboardPendingItem]
    let onNavigate: (MacDashboardDestination) -> Void

    var body: some View {
        MacPanel(title: "Pendiente") {
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct DashboardStatusCard: View {
    let summary: DashboardSyncSummary
    let platformName: String

    var body: some View {
        MacPanel(title: "Estado") {
            VStack(alignment: .leading, spacing: 12) {
                statusRow("Sync", value: summaryLine, tint: summary.state.tint)
                statusRow("Cambios pendientes", value: "\(summary.pendingChanges)", tint: summary.pendingChanges > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint)
                statusRow("Última sync", value: summary.lastRunAt.map(Self.relativeTime) ?? "Sin registro", tint: .secondary)
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
        MacPanel(title: "Ahora") {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: systemImage)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if case .outsideSchoolYear(let startDate, let endDate) = reason {
                    Text("Curso configurado: \(startDate) - \(endDate)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button(buttonTitle) {
                    onNavigate(destination)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        }
    }

    private var title: String {
        switch reason {
        case .noScheduleConfigured: return "Agenda docente pendiente"
        case .noClasses: return "Sin clases"
        case .outsideSchoolYear: return "Fuera del rango del curso"
        }
    }

    private var message: String {
        switch reason {
        case .noScheduleConfigured:
            return "Configura tu horario docente para mostrar la clase activa."
        case .noClasses:
            return "Todavía no hay clases creadas."
        case .outsideSchoolYear:
            return "Estás fuera del rango del curso configurado."
        }
    }

    private var buttonTitle: String {
        switch reason {
        case .noScheduleConfigured: return "Configurar horario"
        case .noClasses: return "Crear clase"
        case .outsideSchoolYear: return "Editar agenda docente"
        }
    }

    private var destination: MacDashboardDestination {
        switch reason {
        case .noScheduleConfigured, .outsideSchoolYear:
            return .plannerAgenda
        case .noClasses:
            return .students(classId: nil)
        }
    }

    private var systemImage: String {
        switch reason {
        case .noScheduleConfigured, .outsideSchoolYear: return "calendar.badge.exclamationmark"
        case .noClasses: return "person.3.sequence"
        }
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
    @State private var selectedStudentId: Int64?
    @State private var selectedEvaluationId: Int64?
    @State private var scoreText = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Evaluación rápida")
                .font(.title2.weight(.semibold))
            Form {
                Picker("Clase", selection: $selectedClassId) {
                    Text("Seleccionar").tag(Int64?.none)
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
                    }
                }
                Picker("Alumno", selection: $selectedStudentId) {
                    Text("Seleccionar").tag(Int64?.none)
                    ForEach(Array(bridge.studentsInClass), id: \.id) { student in
                        Text(student.fullName).tag(Optional(student.id))
                    }
                }
                Picker("Columna / evaluación", selection: $selectedEvaluationId) {
                    Text("Seleccionar").tag(Int64?.none)
                    ForEach(bridge.evaluationsInClass, id: \.id) { evaluation in
                        Text(evaluation.name).tag(Optional(evaluation.id))
                    }
                }
                TextField("Nota", text: $scoreText)
                TextField("Observación opcional", text: $note, axis: .vertical)
            }
            Text("No se guarda ninguna nota desde el dashboard. Completa los datos y abre el cuaderno para confirmar allí el registro.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Cancelar", action: onCancel)
                Spacer()
                Button("Abrir cuaderno") {
                    onOpenNotebook(selectedClassId)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedClassId == nil)
            }
        }
        .padding(24)
        .onAppear {
            selectedClassId = initialClassId
            loadSelection()
        }
        .onChange(of: selectedClassId) { _ in
            loadSelection()
        }
    }

    private func loadSelection() {
        Task {
            guard let selectedClassId else { return }
            bridge.selectClass(id: selectedClassId)
            await bridge.selectStudentsClass(classId: selectedClassId)
        }
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
        .onChange(of: selectedClassId) { _ in
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
