import Foundation

// Todos los textos VISIBLES de la proyección del Mac, en inglés. El resto de la app (y el iPad)
// sigue en español: este enum es la única puerta de los textos de la proyección.
//
// Parte de lo que genera la app son cadenas en español (títulos de fase del `TournamentPhaseTimeline`,
// columnas y huecos del `BracketTreeLayout`, «Gana P5»…). Aquí se traducen en la capa de proyección
// sin tocar esas capas: `isSlotPlaceholder` sigue reconociendo las formas españolas y la proyección
// las muestra en inglés. Un texto desconocido se deja tal cual (la prueba de palabras españolas lo delata).
//
// No se traducen el nombre del torneo ni los nombres de equipos (con el interruptor encendido).

enum ProjectionStrings {
    // MARK: Equipos, pistas y rondas

    static let unknownTeam = "Team"
    static let teamHeader = "Team"
    static let versus = "vs"
    static let champions = "Champions"

    static func team(_ number: Int) -> String { "Team \(number)" }
    static func court(_ number: Int) -> String { "Court \(number)" }
    static func round(_ number: Int, of count: Int) -> String { "Round \(number) of \(count)" }

    // MARK: Cabeceras de escena

    static let nowPlaying = "Now playing"
    static let breakGetReady = "Break · Get ready"
    static let getReady = "Get ready"
    static let tournamentStarts = "The tournament starts"
    static let phaseComplete = "Phase complete"
    static let tournamentComplete = "Tournament complete"
    static let tournament = "Tournament"
    static let podium = "Podium"
    static let bracket = "Bracket"

    static func startNote(phase: String) -> String {
        "\(phase). Standings will appear after the first round."
    }

    static func phaseFinished(isPlacement: Bool) -> String {
        "\(isPlacement ? "Group stage" : "Groups") complete. The bracket begins."
    }

    static let placementNote = "Nobody is eliminated: winners play on for the top places, losers for the bottom places."
    static let groupsNote = "The best teams of each group move on to the bracket."

    // MARK: Clasificación

    static let standings = "Standings"
    static let finalStandings = "Final standings"
    static let groupStandings = "Group standings"
    static let recordHeader = "W-D-L"
    static let diffHeader = "Diff"
    static let pointsHeader = "Pts"
    static func points(_ value: Int) -> String { "\(value) pts" }

    /// «Grupo A» → «Group A».
    static func groupName(_ name: String) -> String {
        name.hasPrefix("Grupo ") ? "Group " + name.dropFirst("Grupo ".count) : name
    }

    // MARK: Descansos

    static func resting(_ teams: [String]) -> String? {
        switch teams.count {
        case 0: return nil
        case 1...6: return "Resting: \(teams.joined(separator: ", "))"
        default: return "\(teams.count) teams resting"
        }
    }

    // MARK: Cuadro

    static func bracketTitle(part: ProjectionBracket.Part, isPlacement: Bool, half: Int, teamCount: Int) -> String {
        switch part {
        case .whole: return bracket
        case .first: return isPlacement ? "Bracket · places 1 to \(half)" : "Bracket · top half"
        case .second: return isPlacement ? "Bracket · places \(half + 1) to \(teamCount)" : "Bracket · bottom half"
        }
    }

    /// «Places 1–4» (o «1st place» si es uno solo).
    static func placesCaption(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "\(ordinal(range.lowerBound)) place"
            : "Places \(range.lowerBound)–\(range.upperBound)"
    }

    /// «1st», «1st–2nd», «5–6».
    static func positionsText(_ range: ClosedRange<Int>) -> String {
        if range.lowerBound == range.upperBound { return ordinal(range.lowerBound) }
        if range.count == 2 { return "\(ordinal(range.lowerBound))–\(ordinal(range.upperBound))" }
        return "\(range.lowerBound)–\(range.upperBound)"
    }

    /// «Win: places 1–4 · Lose: places 5–8», a partir de los destinos en español del árbol.
    static func destination(winner: String, loser: String) -> String {
        "Win: \(destinationPart(winner)) · Lose: \(destinationPart(loser))"
    }

    private static func destinationPart(_ spanish: String) -> String {
        if let groups = captures(#"^puesto (\d+)º$"#, in: spanish), let n = Int(groups[0]) { return "\(ordinal(n)) place" }
        if let groups = captures(#"^sigue por (\d+)–(\d+)$"#, in: spanish) { return "places \(groups[0])–\(groups[1])" }
        if let groups = captures(#"^pasa a (.+)$"#, in: spanish) { return "advances to \(stage(groups[0]))" }
        switch spanish {
        case "campeón": return "champion"
        case "subcampeón": return "runner-up"
        case "queda eliminado": return "eliminated"
        default: return spanish
        }
    }

    // MARK: Fases (títulos que genera `TournamentPhaseTimeline`)

    /// «Fase 1 · Liguilla» → «Phase 1 · Group stage»; «Liga» → «League».
    static func phaseTitle(_ spanish: String) -> String {
        if let groups = captures(#"^Fase (\d+) · (.+)$"#, in: spanish) {
            return "Phase \(groups[0]) · \(phasePart(groups[1]))"
        }
        return phasePart(spanish)
    }

    /// Para el pie: «Fase 1 · Liguilla» → «1 · Group stage».
    static func footerTitle(_ spanish: String) -> String {
        if let groups = captures(#"^Fase (\d+) · (.+)$"#, in: spanish) {
            return "\(groups[0]) · \(phasePart(groups[1]))"
        }
        return phasePart(spanish)
    }

    static func footerBracket(number: Int, isPlacement: Bool) -> String {
        "\(number) · \(isPlacement ? bracket : "Knockout")"
    }

    private static func phasePart(_ spanish: String) -> String {
        switch spanish {
        case "Grupos": return "Groups"
        case "Liguilla": return "Group stage"
        case "Cuadro de puestos": return "Placement bracket"
        case "Eliminatorias": return "Knockout"
        case "Rotaciones": return "Rotations"
        case "Liga": return "League"
        case "Podio": return podium
        case "Cuadro": return bracket
        case "Clasificación final": return finalStandings
        default: return stage(spanish)
        }
    }

    /// Rondas de eliminatoria: «Cuartos de final» → «Quarterfinals»; «Ronda 3» → «Round 3».
    static func stage(_ spanish: String) -> String {
        switch spanish {
        case "Final": return "Final"
        case "Semifinales": return "Semifinals"
        case "Cuartos de final": return "Quarterfinals"
        case "Octavos de final": return "Round of 16"
        case "Dieciseisavos": return "Round of 32"
        default:
            if let groups = captures(#"^Ronda (\d+)$"#, in: spanish) { return "Round \(groups[0])" }
            return spanish
        }
    }

    /// Subtítulo de columna del cuadro de puestos: «2 grupos de 4 puestos» → «2 groups of 4 places».
    static func columnSubtitle(_ spanish: String) -> String {
        if let groups = captures(#"^(\d+) grupos? de (\d+) puestos$"#, in: spanish), let count = Int(groups[0]) {
            return "\(count) \(count == 1 ? "group" : "groups") of \(groups[1]) places"
        }
        if let groups = captures(#"^(\d+) grupos? de puestos$"#, in: spanish), let count = Int(groups[0]) {
            return "\(count) \(count == 1 ? "group" : "groups") of places"
        }
        if spanish == "Nadie queda eliminado" { return "Nobody is eliminated" }
        return spanish
    }

    // MARK: Huecos del cuadro

    /// Traduce un hueco que genera la app («Gana P5», «Clasificado 2 Grupo B», «3º liguilla»…).
    /// Lo que no es un hueco conocido se devuelve igual.
    static func placeholder(_ spanish: String) -> String {
        let value = spanish.trimmingCharacters(in: .whitespacesAndNewlines)
        if let groups = captures(#"^(?:Gana|Ganador) P(\d+)$"#, in: value) { return "Winner M\(groups[0])" }
        if let groups = captures(#"^(?:Pierde|Perdedor) P(\d+)$"#, in: value) { return "Loser M\(groups[0])" }
        if let groups = captures(#"^Clasificado (\d+) Grupo ([A-Z0-9]+)$"#, in: value), let n = Int(groups[0]) {
            return "\(ordinal(n)) Group \(groups[1])"
        }
        if let groups = captures(#"^Clasificado (\d+)$"#, in: value), let n = Int(groups[0]) {
            return "\(ordinal(n)) group stage"
        }
        if let groups = captures(#"^(\d+)º liguilla$"#, in: value), let n = Int(groups[0]) { return "\(ordinal(n)) group stage" }
        if let groups = captures(#"^(\d+)º Grupo ([A-Z0-9]+)$"#, in: value), let n = Int(groups[0]) {
            return "\(ordinal(n)) Group \(groups[1])"
        }
        return spanish
    }

    // MARK: Mac: mensajes de la ventana

    static let loading = "Loading the tournament…"
    static let tournamentNotFound = "The tournament can't be found. Close this window and project again from the tournament."

    // MARK: Accesibilidad

    static func placeLabel(_ position: Int) -> String { "Place \(position)" }
    static func matchLabel(_ number: Int) -> String { "Match \(number)" }

    // MARK: Utilidades

    /// «1st», «2nd», «3rd», «4th», «11th», «12th», «13th», «21st»…
    static func ordinal(_ number: Int) -> String {
        let lastTwo = number % 100
        if (11...13).contains(lastTwo) { return "\(number)th" }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }

    /// Grupos de captura de la primera coincidencia de `pattern` (que debe cubrir todo el texto).
    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<max(match.numberOfRanges, 1)).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
