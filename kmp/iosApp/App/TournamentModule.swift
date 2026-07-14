import SwiftUI
import MiGestorKit

struct TournamentStudentProfile: Identifiable, Codable {
    let id: Int64
    var level: TournamentStudentLevel
    var incompatibleStudentIds: [Int64]
}

struct TournamentTeam: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorHex: String
    var studentIds: [Int64]
}

struct TournamentMatch: Identifiable, Codable {
    let id: UUID
    var phase: String
    var round: Int
    var homeLabel: String
    var awayLabel: String
    var homeTeamId: UUID?
    var awayTeamId: UUID?
    var homeScore: Int
    var awayScore: Int
    var court: String
    var linkedSessionId: Int64?
}

struct TournamentViewState: Identifiable, Codable {
    let id: UUID
    let classId: Int64
    var name: String
    var sport: String
    var template: TournamentTemplate
    var status: TournamentStatus
    var pointsWin: Int
    var pointsDraw: Int
    var pointsLoss: Int
    var tieBreaker: String
    var teams: [TournamentTeam]
    var matches: [TournamentMatch]
    var studentProfiles: [TournamentStudentProfile]?
    var createdAt: Date
}

enum TournamentBoardSection: String, CaseIterable, Identifiable {
    case overview = "Resumen"
    case groups = "Grupos"
    case bracket = "Cuadro"
    case teams = "Equipos"

    var id: String { rawValue }
}

struct TournamentBoardScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Binding var tournament: TournamentViewState
    let classLabel: String
    let students: [Student]

    @State var section: TournamentBoardSection = .overview
    @State var showingAutoBalance = false

    var standings: [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        computeStandings(matches: tournament.matches, teams: tournament.teams)
    }

    var groupedStandings: [(String, [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)])] {
        let grouped = Dictionary(grouping: tournament.matches.filter { $0.phase.hasPrefix("Grupo") }) { $0.phase }
        return grouped.keys.sorted().map { key in
            (key, computeStandings(matches: grouped[key] ?? [], teams: tournament.teams))
        }
    }

    var bracketColumns: [(String, [TournamentMatch])] {
        let eliminationMatches = tournament.matches.filter { !$0.phase.hasPrefix("Grupo") && $0.phase != "Liga" }
        let grouped = Dictionary(grouping: eliminationMatches) { $0.phase }
        return grouped.keys.sorted().map { ($0, (grouped[$0] ?? []).sorted { $0.round < $1.round }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WorkspaceInspectorHero(title: tournament.name, subtitle: classLabel)

                    Picker("Vista", selection: $section) {
                        ForEach(TournamentBoardSection.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .overview:
                        overviewSection
                    case .groups:
                        groupsSection
                    case .bracket:
                        bracketSection
                    case .teams:
                        teamsSection
                    }
                }
                .padding(24)
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Progreso del torneo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Autoequilibrar") { showingAutoBalance = true }
                    Button("Equipos") { section = .teams }
                }
            }
        }
        .sheet(isPresented: $showingAutoBalance) {
            TournamentAutoBalanceSheet(tournament: $tournament, students: students)
        }
    }

    var overviewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                WorkspaceMetricCard(title: "Clasificación general", value: "\(standings.count)", systemImage: "list.number")
                WorkspaceMetricCard(title: "Plantilla", value: tournament.template.rawValue, systemImage: "square.grid.3x3.fill")
                WorkspaceMetricCard(title: "Equipos", value: "\(tournament.teams.count)", systemImage: "person.3.fill")
                WorkspaceMetricCard(title: "Partidos", value: "\(tournament.matches.count)", systemImage: "sportscourt.fill")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Clasificación general")
                    .font(.headline)
                ForEach(Array(standings.enumerated()), id: \.offset) { index, row in
                    tournamentStandingCard(rank: index + 1, row: row)
                }
            }
        }
    }

    var groupsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if groupedStandings.isEmpty {
                WorkspaceEmptyState(title: "Sin fase de grupos", subtitle: "Este torneo no usa clasificación por grupos.")
            } else {
                ForEach(groupedStandings, id: \.0) { group, rows in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group)
                            .font(.title3.weight(.bold))
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            tournamentStandingCard(rank: index + 1, row: row)
                        }
                    }
                }
            }
        }
    }

    var bracketSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if bracketColumns.isEmpty {
                WorkspaceEmptyState(title: "Sin cuadro eliminatorio", subtitle: "Este torneo no tiene fase eliminatoria todavía.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(bracketColumns, id: \.0) { phase, matches in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(phase)
                                    .font(.headline)
                                ForEach(matches, id: \.id) { match in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ronda \(match.round)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                        tournamentMatchLine(match.homeLabel, score: match.homeScore)
                                        tournamentMatchLine(match.awayLabel, score: match.awayScore)
                                    }
                                    .padding(14)
                                    .frame(width: 220, alignment: .leading)
                                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    var teamsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button("Autoequilibrar equipos") {
                    showingAutoBalance = true
                }
                .buttonStyle(.borderedProminent)
                Button("Regenerar partidos") {
                    tournament.matches = generateTournamentMatches(template: tournament.template, teams: tournament.teams)
                    syncTournamentMatchLabels(&tournament)
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array($tournament.teams.enumerated()), id: \.element.id) { index, $team in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Nombre del equipo", text: $team.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .appOnChange(of: team.name) { _ in
                                syncTournamentMatchLabels(&tournament)
                            }
                        Text("Miembros: \(team.studentIds.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if team.studentIds.isEmpty {
                        Text("Sin alumnado asignado.")
                            .foregroundStyle(.secondary)
                    } else {
                        WorkspaceFlowLayout(spacing: 8) {
                            ForEach(team.studentIds, id: \.self) { studentId in
                                let name = studentName(studentId)
                                Button {
                                    remove(studentId: studentId, fromTeamAt: index)
                                } label: {
                                    Label(name, systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    Menu {
                        ForEach(unassignedOrCurrentStudents(for: team), id: \.id) { student in
                            Button("\(student.firstName) \(student.lastName)") {
                                assign(studentId: student.id, toTeamAt: index)
                            }
                        }
                    } label: {
                        Label("Asignar alumnado", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    func tournamentStandingCard(rank: Int, row: (team: TournamentTeam, points: Int, scored: Int, conceded: Int)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(rank) · \(row.team.name)")
                .font(.headline)
            Text("\(row.points) pts · \(row.scored) a favor · \(row.conceded) en contra")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func tournamentMatchLine(_ title: String, score: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(score)")
                .font(.headline.monospacedDigit())
        }
    }

    func computeStandings(
        matches: [TournamentMatch],
        teams: [TournamentTeam]
    ) -> [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        teams.map { team in
            let related = matches.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }
            let points = related.reduce(0) { total, match in
                let isHome = match.homeTeamId == team.id
                let scored = isHome ? match.homeScore : match.awayScore
                let conceded = isHome ? match.awayScore : match.homeScore
                if scored > conceded { return total + tournament.pointsWin }
                if scored == conceded { return total + tournament.pointsDraw }
                return total + tournament.pointsLoss
            }
            let scored = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.homeScore : match.awayTeamId == team.id ? match.awayScore : 0)
            }
            let conceded = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.awayScore : match.awayTeamId == team.id ? match.homeScore : 0)
            }
            return (team, points, scored, conceded)
        }
        .sorted { lhs, rhs in
            if lhs.points == rhs.points { return lhs.scored > rhs.scored }
            return lhs.points > rhs.points
        }
    }

    func studentName(_ studentId: Int64) -> String {
        guard let student = students.first(where: { $0.id == studentId }) else { return "Alumno \(studentId)" }
        return "\(student.firstName) \(student.lastName)"
    }

    func unassignedOrCurrentStudents(for team: TournamentTeam) -> [Student] {
        let assigned = Set(tournament.teams.flatMap(\.studentIds))
        return students.filter { !assigned.contains($0.id) || team.studentIds.contains($0.id) }
    }

    func assign(studentId: Int64, toTeamAt index: Int) {
        for teamIndex in tournament.teams.indices {
            tournament.teams[teamIndex].studentIds.removeAll { $0 == studentId }
        }
        tournament.teams[index].studentIds.append(studentId)
    }

    func remove(studentId: Int64, fromTeamAt index: Int) {
        tournament.teams[index].studentIds.removeAll { $0 == studentId }
    }
}

struct TournamentAutoBalanceSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var tournament: TournamentViewState
    let students: [Student]

    @State var profiles: [TournamentStudentProfile] = []
    @State var teamCount = 4
    @State var studentA: Int64?
    @State var studentB: Int64?

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Configurar equipos",
            subtitle: "Equilibra el torneo por nivel y evita emparejamientos conflictivos.",
            systemImage: "scale.3d",
            canSave: !students.isEmpty,
            onCancel: { dismiss() },
            onSave: generateBalancedTournament
        ) {
            PremiumCard.section(title: "Configuración", systemImage: "person.3.fill") {
                VStack(alignment: .leading, spacing: 16) {
                    Stepper("Equipos \(teamCount)", value: $teamCount, in: 2...8)
                    Text("\(students.count) alumnos disponibles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            PremiumCard.section(title: "Nivel del alumnado", systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($profiles) { $profile in
                        HStack(spacing: 12) {
                            Text(studentName(profile.id))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Picker("Nivel", selection: $profile.level) {
                                ForEach(TournamentStudentLevel.allCases) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            PremiumCard.section(title: "Incompatibilidades", systemImage: "person.2.slash") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Alumno A", selection: $studentA) {
                        Text("Selecciona").tag(Int64?.none)
                        ForEach(students, id: \.id) { student in
                            Text("\(student.firstName) \(student.lastName)").tag(Optional(student.id))
                        }
                    }
                    Picker("Alumno B", selection: $studentB) {
                        Text("Selecciona").tag(Int64?.none)
                        ForEach(students, id: \.id) { student in
                            Text("\(student.firstName) \(student.lastName)").tag(Optional(student.id))
                        }
                    }

                    Button {
                        addIncompatibility()
                    } label: {
                        Label("Añadir incompatibilidad", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(studentA == nil || studentB == nil || studentA == studentB)

                    if incompatibilityPairs.isEmpty {
                        Text("Sin incompatibilidades definidas.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(incompatibilityPairs, id: \.id) { pair in
                            HStack(spacing: 12) {
                                Text(pair.label)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button(role: .destructive) {
                                    removeIncompatibility(a: pair.a, b: pair.b)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .task {
            profiles = normalizedProfiles(students: students, existingProfiles: tournament.studentProfiles)
            teamCount = max(2, tournament.teams.count)
        }
    }

    var incompatibilityPairs: [(id: String, a: Int64, b: Int64, label: String)] {
        var seen = Set<String>()
        var result: [(id: String, a: Int64, b: Int64, label: String)] = []
        for profile in profiles {
            for incompatible in profile.incompatibleStudentIds {
                let sorted = [profile.id, incompatible].sorted()
                let key = "\(sorted[0])-\(sorted[1])"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append((key, sorted[0], sorted[1], "\(studentName(sorted[0])) / \(studentName(sorted[1]))"))
            }
        }
        return result.sorted { $0.label < $1.label }
    }

    func addIncompatibility() {
        guard let studentA, let studentB, studentA != studentB else { return }
        updateProfile(studentA) { profile in
            if !profile.incompatibleStudentIds.contains(studentB) {
                profile.incompatibleStudentIds.append(studentB)
            }
        }
        updateProfile(studentB) { profile in
            if !profile.incompatibleStudentIds.contains(studentA) {
                profile.incompatibleStudentIds.append(studentA)
            }
        }
        self.studentA = nil
        self.studentB = nil
    }

    func removeIncompatibility(a: Int64, b: Int64) {
        updateProfile(a) { profile in
            profile.incompatibleStudentIds.removeAll { $0 == b }
        }
        updateProfile(b) { profile in
            profile.incompatibleStudentIds.removeAll { $0 == a }
        }
    }

    func updateProfile(_ id: Int64, mutate: (inout TournamentStudentProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&profiles[index])
    }

    func studentName(_ id: Int64) -> String {
        guard let student = students.first(where: { $0.id == id }) else { return "Alumno \(id)" }
        return "\(student.firstName) \(student.lastName)"
    }

    private func generateBalancedTournament() {
        tournament.studentProfiles = profiles
        tournament.teams = generateBalancedTeams(
            students: students,
            count: teamCount,
            profiles: profiles,
            existingTeams: tournament.teams
        )
        tournament.matches = generateTournamentMatches(template: tournament.template, teams: tournament.teams)
        syncTournamentMatchLabels(&tournament)
        dismiss()
    }
}
