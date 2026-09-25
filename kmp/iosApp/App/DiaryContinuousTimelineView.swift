import SwiftUI
import MiGestorKit

struct DiaryContinuousTimelineView: View {
    let bridge: KmpBridge
    let selectedClassId: Int64?
    let onSelectSession: (PlanningSession) -> Void
    let onOpenAttendance: (Int64?) -> Void
    let onOpenNotebook: (Int64?) -> Void

    @State private var allClassSessions: [PlanningSession] = []
    @State private var journalSummaries: [Int64: SessionJournalSummary] = [:]
    @State private var journalAggregates: [Int64: SessionJournalAggregate] = [:]
    @State private var selectedQuarter: DiaryTimelineQuarter = .all
    @State private var selectedStatus: DiaryStatusFilter = .all
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var isExportSheetPresented: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var className: String {
        guard let selectedClassId else { return "Todas las clases" }
        return bridge.classes.first(where: { $0.id == selectedClassId })?.name ?? "Clase"
    }

    private var allTimelineEntries: [DiaryTimelineEntry] {
        let sorted = allClassSessions.sorted { s1, s2 in
            let d1 = DiaryTimelineEntry.dateFor(session: s1)
            let d2 = DiaryTimelineEntry.dateFor(session: s2)
            if d1 != d2 { return d1 < d2 }
            return s1.period < s2.period
        }

        return sorted.enumerated().map { index, session in
            DiaryTimelineEntry(
                id: session.id,
                session: session,
                date: DiaryTimelineEntry.dateFor(session: session),
                sessionIndex: index + 1,
                summary: journalSummaries[session.id]
            )
        }
    }

    private var filteredEntries: [DiaryTimelineEntry] {
        allTimelineEntries.filter { entry in
            let matchesQuarter = selectedQuarter.matches(date: entry.date)

            let matchesStatus: Bool = {
                switch selectedStatus {
                case .all: return true
                case .completed: return entry.isCompleted
                case .drafts: return entry.summary?.status == .draft
                case .incomplete: return !entry.isCompleted
                case .incidents: return entry.hasIncidents
                case .empty: return !entry.hasJournal
                }
            }()

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch: Bool = {
                guard !query.isEmpty else { return true }
                let s = entry.session
                let matchUnit = s.teachingUnitName.localizedCaseInsensitiveContains(query)
                let matchObj = s.objectives.localizedCaseInsensitiveContains(query)
                let matchAct = s.activities.localizedCaseInsensitiveContains(query)
                let matchNote = journalAggregates[s.id]?.journal.actualText.localizedCaseInsensitiveContains(query) ?? false
                return matchUnit || matchObj || matchAct || matchNote
            }()

            return matchesQuarter && matchesStatus && matchesSearch
        }
    }

    private var monthSections: [DiaryTimelineMonthSection] {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "es_ES")
        monthFormatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.year, .month], from: entry.date)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }

        return grouped.keys.sorted().compactMap { key in
            guard let entries = grouped[key], let firstDate = entries.first?.date else { return nil }
            let monthName = monthFormatter.string(from: firstDate).capitalized
            return DiaryTimelineMonthSection(
                id: key,
                monthName: monthName,
                entries: entries
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            metricsStrip
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            if isLoading && allClassSessions.isEmpty {
                Spacer()
                ProgressView("Cargando bitácora continua de aula…")
                Spacer()
            } else if allClassSessions.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("Sin sesiones planificadas", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("No se han encontrado sesiones agendadas para \(className).")
                }
                Spacer()
            } else if filteredEntries.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("Sin resultados", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No hay sesiones que coincidan con el periodo o los filtros seleccionados.")
                }
                Spacer()
            } else {
                timelineFeed
            }
        }
        .background(appPageBackground(for: colorScheme))
        .task(id: selectedClassId) {
            await reloadClassSessions()
        }
        .sheet(isPresented: $isExportSheetPresented) {
            DiaryExportPDFSheet(
                className: className,
                entries: allTimelineEntries,
                aggregatesBySessionId: journalAggregates
            )
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bitácora Continua · \(className)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("\(filteredEntries.count) sesiones registradas en el periodo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Periodo", selection: $selectedQuarter) {
                ForEach(DiaryTimelineQuarter.allCases) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)

            IOSSearchField(text: $searchText, placeholder: "Buscar en bitácora…")
                .frame(maxWidth: 200)

            Button {
                isExportSheetPresented = true
            } label: {
                Label("Exportar PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    // MARK: - Metrics Strip
    private var metricsStrip: some View {
        HStack(spacing: 12) {
            metricBadge(
                title: "Total",
                count: filteredEntries.count,
                tint: EvaluationDesign.accent,
                systemImage: "calendar"
            )

            let completed = filteredEntries.filter(\.isCompleted).count
            metricBadge(
                title: "Completadas",
                count: completed,
                tint: AppleDesignSystem.success,
                systemImage: "checkmark.circle.fill"
            )

            let pending = filteredEntries.filter { !$0.isCompleted }.count
            metricBadge(
                title: "Pendientes",
                count: pending,
                tint: AppleDesignSystem.warning,
                systemImage: "clock.fill"
            )

            let incidents = filteredEntries.filter(\.hasIncidents).count
            metricBadge(
                title: "Incidencias",
                count: incidents,
                tint: AppleDesignSystem.danger,
                systemImage: "exclamationmark.triangle.fill"
            )

            Spacer()

            Menu {
                Picker("Filtro de estado", selection: $selectedStatus) {
                    ForEach(DiaryStatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            } label: {
                Label(selectedStatus == .all ? "Filtrar estado" : selectedStatus.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    private func metricBadge(title: String, count: Int, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
            Text("\(title): \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Timeline Feed
    private var timelineFeed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(monthSections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        // Separador de Mes
                        HStack(spacing: 8) {
                            Text(section.monthName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)

                            Text("(\(section.entries.count) sesiones)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                        }
                        .padding(.top, 8)

                        // Tarjetas de Sesión
                        ForEach(section.entries) { entry in
                            DiaryTimelineCard(
                                entry: entry,
                                aggregate: journalAggregates[entry.id],
                                onSelect: {
                                    onSelectSession(entry.session)
                                },
                                onOpenAttendance: {
                                    onOpenAttendance(entry.session.groupId)
                                },
                                onOpenNotebook: {
                                    onOpenNotebook(entry.session.groupId)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Data Loading
    private func reloadClassSessions() async {
        isLoading = true
        do {
            let all = try await bridge.plannerListAllSessions()
            if let selectedClassId {
                self.allClassSessions = all.filter { $0.groupId == selectedClassId }
            } else {
                self.allClassSessions = all
            }

            let sessionIds = allClassSessions.map(\.id)
            let summaries = try await bridge.plannerJournalSummaries(sessionIds: sessionIds)
            self.journalSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.planningSessionId, $0) })

            // Cargar agregados para notas completas
            var aggregates: [Int64: SessionJournalAggregate] = [:]
            for session in allClassSessions {
                if let agg = try? await bridge.plannerJournal(for: session) {
                    aggregates[session.id] = agg
                }
            }
            self.journalAggregates = aggregates
        } catch {
            print("Error cargando sesiones de la clase: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Timeline Card Component
private struct DiaryTimelineCard: View {
    let entry: DiaryTimelineEntry
    let aggregate: SessionJournalAggregate?
    let onSelect: () -> Void
    let onOpenAttendance: () -> Void
    let onOpenNotebook: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "EEEE, d 'de' MMMM"
        return df
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Carril izquierdo: número de sesión y nodo
            VStack(spacing: 4) {
                Text("#\(entry.sessionIndex)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(entry.statusColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))

                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 2)
            }
            .frame(width: 32)

            // Contenedor principal de la tarjeta
            VStack(alignment: .leading, spacing: 10) {
                // Cabecera de la tarjeta
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(dateFormatter.string(from: entry.date).capitalized)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)

                            if let start = entry.session.startTime, let end = entry.session.endTime {
                                Text("\(start) - \(end)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.08), in: Capsule())
                            }
                        }

                        // Unidad didáctica
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)

                            Text(entry.session.teachingUnitName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Estado de diario
                    if entry.isCompleted {
                        Label("Completado", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppleDesignSystem.success)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppleDesignSystem.success.opacity(0.12), in: Capsule())
                    } else if entry.summary?.status == .draft {
                        Label("Borrador", systemImage: "pencil.circle")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppleDesignSystem.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppleDesignSystem.warning.opacity(0.12), in: Capsule())
                    }
                }

                // Objetivos y Actividades
                if !entry.session.objectives.isEmpty || !entry.session.activities.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !entry.session.objectives.isEmpty {
                            Text("Objetivos: \(entry.session.objectives)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if !entry.session.activities.isEmpty {
                            Text("Actividades: \(entry.session.activities)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                // Fragmento del diario / Desarrollo real
                if let journal = aggregate?.journal, !journal.actualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(EvaluationDesign.accent)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Desarrollo en clase:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(EvaluationDesign.accent)

                            Text(journal.actualText)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                    }
                    .padding(8)
                    .background(EvaluationDesign.surfaceSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }

                // Insignias de incidencias o decisiones pedagógicas
                let decisionLabel = aggregate?.journal.pedagogicalDecision.label ?? ""
                HStack(spacing: 8) {
                    if entry.hasIncidents {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Incidencias")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppleDesignSystem.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppleDesignSystem.danger.opacity(0.12), in: Capsule())
                    }

                    if !decisionLabel.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text(decisionLabel)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    // Acciones de la tarjeta
                    Button {
                        onSelect()
                    } label: {
                        Label("Editar diario", systemImage: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onOpenAttendance()
                    } label: {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Ver asistencia de este grupo")

                    Button {
                        onOpenNotebook()
                    } label: {
                        Image(systemName: "book.pages")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Ver cuaderno de este grupo")
                }
            }
            .padding(14)
            .background(appCardBackground(for: colorScheme))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
