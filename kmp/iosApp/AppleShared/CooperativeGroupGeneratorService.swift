import Foundation

/// Perfil de un alumno como candidato para la formación de grupos cooperativos.
public struct CooperativeCandidateStudent: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let average: Double?
    public let gender: String?
    public let fitnessScore: Double?
    public let tags: [String]

    public init(
        id: Int64,
        name: String,
        average: Double? = nil,
        gender: String? = nil,
        fitnessScore: Double? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.average = average
        self.gender = gender
        self.fitnessScore = fitnessScore
        self.tags = tags
    }

    /// Puntuación compuesta de referencia (media académica o aptitud física) para la ordenación.
    public var compositeScore: Double {
        if let avg = average { return avg }
        if let fit = fitnessScore { return fit }
        return 5.0
    }
}

/// Estrategia pedagógica para la formación de equipos.
public enum CooperativeGroupingStrategy: String, CaseIterable, Identifiable, Sendable {
    case heterogeneous = "heterogeneous"
    case homogeneous = "homogeneous"
    case balancedRandom = "balancedRandom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heterogeneous: return "Heterogéneo (Equilibrado)"
        case .homogeneous: return "Homogéneo (Por Niveles)"
        case .balancedRandom: return "Aleatorio Balanceado"
        }
    }

    public var description: String {
        switch self {
        case .heterogeneous:
            return "Modelo Kagan / Cooperativo: reparte alumnos de alto, medio y bajo rendimiento equitativamente en cada equipo."
        case .homogeneous:
            return "Agrupa alumnos de nivel similar. Ideal para tareas por estaciones multinivel o adaptadas."
        case .balancedRandom:
            return "Distribución aleatoria manteniendo tamaños de equipo estrictamente homogéneos."
        }
    }

    public var systemImage: String {
        switch self {
        case .heterogeneous: return "person.3.sequence.fill"
        case .homogeneous: return "equal.square.fill"
        case .balancedRandom: return "shuffle"
        }
    }
}

/// Configuración para el algoritmo de generación de grupos.
public struct CooperativeGroupingConfiguration: Sendable {
    public var strategy: CooperativeGroupingStrategy
    public var targetGroupCount: Int?
    public var targetGroupSize: Int?
    public var balanceGender: Bool
    public var groupNamePrefix: String

    public init(
        strategy: CooperativeGroupingStrategy = .heterogeneous,
        targetGroupCount: Int? = 4,
        targetGroupSize: Int? = nil,
        balanceGender: Bool = false,
        groupNamePrefix: String = "Equipo"
    ) {
        self.strategy = strategy
        self.targetGroupCount = targetGroupCount
        self.targetGroupSize = targetGroupSize
        self.balanceGender = balanceGender
        self.groupNamePrefix = groupNamePrefix
    }
}

/// Equipo cooperativo resultante.
public struct CooperativeGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var members: [CooperativeCandidateStudent]

    public init(id: UUID = UUID(), name: String, members: [CooperativeCandidateStudent] = []) {
        self.id = id
        self.name = name
        self.members = members
    }

    /// Media académica del equipo.
    public var averageScore: Double? {
        let scores = members.compactMap(\.average)
        guard !scores.isEmpty else { return nil }
        return (scores.reduce(0.0, +) / Double(scores.count) * 10).rounded() / 10.0
    }

    /// Dispersión o varianza interna del equipo.
    public var internalDiversity: Double {
        let scores = members.map(\.compositeScore)
        guard scores.count > 1 else { return 0.0 }
        let avg = scores.reduce(0.0, +) / Double(scores.count)
        let variance = scores.map { pow($0 - avg, 2) }.reduce(0.0, +) / Double(scores.count)
        return sqrt(variance)
    }

    /// Desglose de género si consta.
    public var genderSummary: String? {
        let genders = members.compactMap(\.gender).filter { !$0.isEmpty }
        guard !genders.isEmpty else { return nil }
        let counts = Dictionary(grouping: genders, by: { $0.uppercased().prefix(1) })
        return counts.map { "\($0.value.count)\($0.key)" }.joined(separator: " / ")
    }
}

/// Resultado global de la generación de grupos cooperativos.
public struct CooperativeGroupingResult: Sendable {
    public let groups: [CooperativeGroup]
    public let unassigned: [CooperativeCandidateStudent]
    public let strategy: CooperativeGroupingStrategy

    public init(
        groups: [CooperativeGroup],
        unassigned: [CooperativeCandidateStudent] = [],
        strategy: CooperativeGroupingStrategy
    ) {
        self.groups = groups
        self.unassigned = unassigned
        self.strategy = strategy
    }

    /// Desviación estándar entre las medias de los grupos (cuanto más cercana a 0, más equilibrados).
    public var betweenGroupVariance: Double {
        let avgs = groups.compactMap(\.averageScore)
        guard avgs.count > 1 else { return 0.0 }
        let mean = avgs.reduce(0.0, +) / Double(avgs.count)
        let sumSquaredDiffs = avgs.map { pow($0 - mean, 2) }.reduce(0.0, +)
        return sqrt(sumSquaredDiffs / Double(avgs.count))
    }
}

/// Servicio determinista on-device para generar agrupamientos cooperativos pedagógicos.
public struct CooperativeGroupGeneratorService: Sendable {
    public init() {}

    /// Genera la distribución de grupos cooperativos según la configuración deseada.
    public func generateGroups(
        students: [CooperativeCandidateStudent],
        configuration: CooperativeGroupingConfiguration
    ) -> CooperativeGroupingResult {
        guard !students.isEmpty else {
            return CooperativeGroupingResult(groups: [], strategy: configuration.strategy)
        }

        let totalStudents = students.count

        // 1. Determinar número final de grupos (K)
        let groupCount: Int
        if let explicitCount = configuration.targetGroupCount, explicitCount > 0 {
            groupCount = min(explicitCount, totalStudents)
        } else if let targetSize = configuration.targetGroupSize, targetSize > 0 {
            groupCount = max(1, Int(ceil(Double(totalStudents) / Double(targetSize))))
        } else {
            groupCount = max(1, totalStudents / 4) // Tamaño por defecto: ~4 alumnos
        }

        guard groupCount > 0 else {
            return CooperativeGroupingResult(groups: [], strategy: configuration.strategy)
        }

        // Inicializar K grupos vacíos
        var groupBuckets = (0..<groupCount).map { i in
            CooperativeGroup(
                name: "\(configuration.groupNamePrefix) \(i + 1)",
                members: []
            )
        }

        switch configuration.strategy {
        case .heterogeneous:
            groupBuckets = distributeHeterogeneous(
                students: students,
                groupCount: groupCount,
                balanceGender: configuration.balanceGender,
                prefix: configuration.groupNamePrefix
            )

        case .homogeneous:
            groupBuckets = distributeHomogeneous(
                students: students,
                groupCount: groupCount,
                prefix: configuration.groupNamePrefix
            )

        case .balancedRandom:
            groupBuckets = distributeBalancedRandom(
                students: students,
                groupCount: groupCount,
                prefix: configuration.groupNamePrefix
            )
        }

        return CooperativeGroupingResult(
            groups: groupBuckets,
            strategy: configuration.strategy
        )
    }

    // MARK: - Algoritmo Heterogéneo (Snake Draft / Serpenteante Kagan)

    private func distributeHeterogeneous(
        students: [CooperativeCandidateStudent],
        groupCount: Int,
        balanceGender: Bool,
        prefix: String
    ) -> [CooperativeGroup] {
        var groups = (0..<groupCount).map { i in
            CooperativeGroup(name: "\(prefix) \(i + 1)", members: [])
        }

        if balanceGender {
            // Dividir por género para equilibrar ambos subgrupos de forma serpenteante
            let females = students.filter { ($0.gender ?? "").lowercased().hasPrefix("f") || ($0.gender ?? "").lowercased().hasPrefix("m") && ($0.gender ?? "").lowercased().contains("muj") }
            let males = students.filter { !females.contains($0) }

            assignSnake(to: &groups, students: females.sorted { $0.compositeScore > $1.compositeScore })
            // Invertir orden inicial en el segundo bloque para compensar
            assignSnake(to: &groups, students: males.sorted { $0.compositeScore > $1.compositeScore }, reverseStart: true)
        } else {
            let sorted = students.sorted { $0.compositeScore > $1.compositeScore }
            assignSnake(to: &groups, students: sorted)
        }

        return groups
    }

    private func assignSnake(
        to groups: inout [CooperativeGroup],
        students: [CooperativeCandidateStudent],
        reverseStart: Bool = false
    ) {
        guard !groups.isEmpty, !students.isEmpty else { return }
        let k = groups.count
        var ascending = !reverseStart

        var i = 0
        while i < students.count {
            let chunk = Array(students[i..<min(i + k, students.count)])
            let indices = ascending ? Array(0..<chunk.count) : Array((0..<chunk.count).reversed())

            for (chunkIdx, groupIdx) in indices.enumerated() {
                groups[groupIdx].members.append(chunk[chunkIdx])
            }

            ascending.toggle()
            i += k
        }
    }

    // MARK: - Algoritmo Homogéneo (Por bloques de nivel)

    private func distributeHomogeneous(
        students: [CooperativeCandidateStudent],
        groupCount: Int,
        prefix: String
    ) -> [CooperativeGroup] {
        var groups = (0..<groupCount).map { i in
            CooperativeGroup(name: "\(prefix) \(i + 1)", members: [])
        }

        let sorted = students.sorted { $0.compositeScore > $1.compositeScore }
        let chunkSize = Double(sorted.count) / Double(groupCount)

        for (idx, student) in sorted.enumerated() {
            let targetGroup = min(groupCount - 1, Int(floor(Double(idx) / chunkSize)))
            groups[targetGroup].members.append(student)
        }

        return groups
    }

    // MARK: - Algoritmo Aleatorio Equilibrado

    private func distributeBalancedRandom(
        students: [CooperativeCandidateStudent],
        groupCount: Int,
        prefix: String
    ) -> [CooperativeGroup] {
        var groups = (0..<groupCount).map { i in
            CooperativeGroup(name: "\(prefix) \(i + 1)", members: [])
        }

        let shuffled = students.shuffled()
        for (idx, student) in shuffled.enumerated() {
            let targetGroup = idx % groupCount
            groups[targetGroup].members.append(student)
        }

        return groups
    }

    // MARK: - Adaptador a ImportedNotebookGroup

    /// Convierte los equipos generados en la estructura nativa del Cuaderno de Notas para su importación directa.
    public func toImportedNotebookGroups(result: CooperativeGroupingResult) -> [ImportedNotebookGroup] {
        result.groups.map { group in
            ImportedNotebookGroup(
                name: group.name,
                members: group.members.map { member in
                    ImportedNotebookGroupMember(
                        rawName: member.name,
                        matchedStudentId: member.id,
                        matchedStudentName: member.name
                    )
                }
            )
        }
    }
}
