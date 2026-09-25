import SwiftUI
import MiGestorKit

/// Hoja para consultar todos los hitos oficiales del curso (evaluaciones, salidas,
/// festivos y claustro) importados en el calendario escolar.
struct SchoolCalendarEventsOverviewSheet: View {
    @ObservedObject var bridge: KmpBridge
    let onClose: () -> Void

    @State private var allEvents: [CalendarEvent] = []
    @State private var evaluationPeriods: [PlannerEvaluationPeriod] = []
    @State private var classes: [SchoolClass] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedFilter: EventFilter = .all

    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case evaluations = "Evaluaciones"
        case trips = "Salidas y viajes"
        case schoolWide = "Centro y festivos"
        case teacher = "Claustro y familias"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selector de categoría
                Picker("Filtro", selection: $selectedFilter) {
                    ForEach(EventFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if isLoading {
                    Spacer()
                    ProgressView("Cargando hitos del curso…")
                    Spacer()
                } else {
                    List {
                        // 1. Periodos de evaluación
                        if (selectedFilter == .all || selectedFilter == .evaluations) && !filteredEvaluations.isEmpty {
                            Section {
                                ForEach(filteredEvaluations, id: \.id) { period in
                                    evaluationRow(period)
                                }
                            } header: {
                                Label("Periodos de Evaluación", systemImage: "chart.bar.doc.horizontal.fill")
                                    .foregroundStyle(Color.purple)
                            }
                        }

                        // 2. Salidas y viajes
                        if (selectedFilter == .all || selectedFilter == .trips) && !filteredTrips.isEmpty {
                            Section {
                                ForEach(filteredTrips, id: \.id) { event in
                                    eventRow(event, category: .trip)
                                }
                            } header: {
                                Label("Salidas y viajes de curso", systemImage: "bus.fill")
                                    .foregroundStyle(Color.blue)
                            }
                        }

                        // 3. Festivos y eventos de centro
                        if (selectedFilter == .all || selectedFilter == .schoolWide) && !filteredSchoolWide.isEmpty {
                            Section {
                                ForEach(filteredSchoolWide, id: \.id) { event in
                                    eventRow(event, category: .holiday)
                                }
                            } header: {
                                Label("Festivos y eventos de centro", systemImage: "flag.fill")
                                    .foregroundStyle(Color.red)
                            }
                        }

                        // 4. Claustro, reuniones y Educamos
                        if (selectedFilter == .all || selectedFilter == .teacher) && !filteredTeacherEvents.isEmpty {
                            Section {
                                ForEach(filteredTeacherEvents, id: \.id) { event in
                                    eventRow(event, category: .milestone)
                                }
                            } header: {
                                Label("Hitos docentes, reuniones y notas", systemImage: "calendar.badge.clock")
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        if filteredEvaluations.isEmpty && filteredTrips.isEmpty && filteredSchoolWide.isEmpty && filteredTeacherEvents.isEmpty {
                            ContentUnavailableView(
                                "No se encontraron hitos",
                                systemImage: "magnifyingglass",
                                description: Text("No hay eventos que coincidan con «\(searchText)»")
                            )
                        }
                    }
                    #if os(macOS)
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    #else
                    .listStyle(.insetGrouped)
                    #endif
                }

            }
            .navigationTitle("Hitos del curso 2026–2027")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Buscar evento, viaje o hito…")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        onClose()
                    }
                }
            }
            .task {
                await loadData()
            }
        }
        .frame(minWidth: 500, minHeight: 520)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allEvents = try await bridge.plannerAllCalendarEvents()
            classes = bridge.classes
            let schedule = try? await bridge.plannerTeacherSchedule()
            if let scheduleId = schedule?.id {
                evaluationPeriods = (try? await bridge.plannerEvaluationPeriods(scheduleId: scheduleId)) ?? []
            }
        } catch {
            print("Error cargando hitos: \(error)")
        }
    }

    private var classNameById: [Int64: String] {
        Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0.name) })
    }

    private var filteredEvaluations: [PlannerEvaluationPeriod] {
        if searchText.isEmpty { return evaluationPeriods }
        return evaluationPeriods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.startDateIso.localizedCaseInsensitiveContains(searchText) ||
            $0.endDateIso.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var categorizedEvents: (trips: [CalendarEvent], schoolWide: [CalendarEvent], teacher: [CalendarEvent]) {
        var trips: [CalendarEvent] = []
        var schoolWide: [CalendarEvent] = []
        var teacher: [CalendarEvent] = []

        for event in allEvents {
            let titleLower = event.title.lowercased()
            let descLower = (event.description_ ?? "").lowercased()
            let haystack = "\(titleLower) \(descLower)"

            if event.classId != nil || haystack.contains("viaje") || haystack.contains("salida") || haystack.contains("toledo") || haystack.contains("pirineos") || haystack.contains("agullent") {
                trips.append(event)
            } else if haystack.contains("reunión") || haystack.contains("notas") || haystack.contains("graduación") || haystack.contains("claustro") || haystack.contains("educamos") {
                teacher.append(event)
            } else {
                schoolWide.append(event)
            }
        }

        return (trips, schoolWide, teacher)
    }

    private var filteredTrips: [CalendarEvent] {
        filterEvents(categorizedEvents.trips)
    }

    private var filteredSchoolWide: [CalendarEvent] {
        filterEvents(categorizedEvents.schoolWide)
    }

    private var filteredTeacherEvents: [CalendarEvent] {
        filterEvents(categorizedEvents.teacher)
    }

    private func filterEvents(_ list: [CalendarEvent]) -> [CalendarEvent] {
        if searchText.isEmpty { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.description_ ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.classId.flatMap { classNameById[$0.int64Value] } ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private func evaluationRow(_ period: PlannerEvaluationPeriod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.title3)
                .foregroundStyle(Color.purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(period.name)
                    .font(.subheadline.weight(.semibold))

                Text("\(formatIsoDate(period.startDateIso)) — \(formatIsoDate(period.endDateIso))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Evaluación")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.purple)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private func eventRow(_ event: CalendarEvent, category: PlannerMilestoneCategory) -> some View {
        let dateStr = formatDateFromEpoch(event.startAt.toEpochMilliseconds())
        let classLabel = event.classId.flatMap { classNameById[$0.int64Value] }
        let isBlocking = (event.description_ ?? "").localizedCaseInsensitiveContains("no lectivo") ||
                         event.title.localizedCaseInsensitiveContains("festivo") ||
                         event.title.localizedCaseInsensitiveContains("vacaciones")

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: category.iconName)
                .font(.title3)
                .foregroundStyle(category.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))

                    if isBlocking {
                        Text("No lectivo")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }

                if let desc = event.description_, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Label(dateStr, systemImage: "calendar")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let classLabel {
                        Label(classLabel, systemImage: "person.2.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func formatIsoDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2])/\(parts[1])/\(parts[0])"
    }

    private func formatDateFromEpoch(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: date)
    }
}
