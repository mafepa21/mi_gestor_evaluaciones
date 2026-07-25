import Foundation

public enum NotebookDensity: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case spacious
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .compact: return "Compacta (80dp)"
        case .standard: return "Estándar (100dp)"
        case .spacious: return "Espaciosa (120dp)"
        }
    }
    
    public var rowHeight: Double {
        switch self {
        case .compact: return 80.0
        case .standard: return 100.0
        case .spacious: return 120.0
        }
    }
}

public enum AverageRoundingMode: String, Codable, CaseIterable, Identifiable {
    case roundHalfUp
    case ceil
    case floor
    case trunc
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .roundHalfUp: return "Redondeo estándar (0.5+ arriba)"
        case .ceil: return "Hacia arriba (Techo)"
        case .floor: return "Hacia abajo (Suelo)"
        case .trunc: return "Truncamiento"
        }
    }
}

public enum BackupFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case manual
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .daily: return "Diaria (Al cerrar la app)"
        case .weekly: return "Semanal"
        case .manual: return "Solo manual"
        }
    }
}

public enum TeacherSubjectProfile: String, Codable, CaseIterable, Identifiable {
    case general
    case physicalEducation
    case languages
    case sciences
    case math
    case music
    case technology
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .physicalEducation: return "Educación Física"
        case .languages: return "Lenguas"
        case .sciences: return "Ciencias"
        case .math: return "Matemáticas"
        case .music: return "Música"
        case .technology: return "Tecnología"
        case .custom: return "Personalizado"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: return "Core docente sin módulos específicos."
        case .physicalEducation: return "Sesiones, mediciones, material, incidencias y torneos."
        case .languages: return "Plantillas de lectura, escritura y oralidad."
        case .sciences: return "Plantillas de prácticas, informes y laboratorio."
        case .math: return "Plantillas de resolución, cálculo y competencias."
        case .music: return "Plantillas de interpretación, ritmo y escucha."
        case .technology: return "Plantillas de proyectos, prototipos e hitos."
        case .custom: return "Base flexible para materias propias."
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "rectangle.3.group"
        case .physicalEducation: return "figure.run"
        case .languages: return "text.book.closed"
        case .sciences: return "flask"
        case .math: return "function"
        case .music: return "music.note"
        case .technology: return "hammer"
        case .custom: return "slider.horizontal.3"
        }
    }

    public static func decodeSet(_ rawValue: String) -> Set<TeacherSubjectProfile> {
        let values = rawValue
            .split(separator: ",")
            .compactMap { TeacherSubjectProfile(rawValue: String($0)) }
        let decoded = Set(values)
        return decoded.isEmpty ? [.general] : decoded
    }

    public static func encodeSet(_ profiles: Set<TeacherSubjectProfile>) -> String {
        let normalized = profiles.isEmpty ? Set([TeacherSubjectProfile.general]) : profiles
        return normalized
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

public struct SubjectNotebookColumnPreset: Hashable {
    public let blueprintId: String
    public let defaultTitle: String
    public let weight: Double
    public let countsTowardAverage: Bool
    public let unitOrSituation: String?
    public let categoryName: String?
    public let isPinned: Bool
    public let isLocked: Bool
    public let isTemplate: Bool

    public init(
        blueprintId: String,
        defaultTitle: String,
        weight: Double,
        countsTowardAverage: Bool,
        unitOrSituation: String? = nil,
        categoryName: String? = nil,
        isPinned: Bool = false,
        isLocked: Bool = false,
        isTemplate: Bool = true
    ) {
        self.blueprintId = blueprintId
        self.defaultTitle = defaultTitle
        self.weight = weight
        self.countsTowardAverage = countsTowardAverage
        self.unitOrSituation = unitOrSituation
        self.categoryName = categoryName
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.isTemplate = isTemplate
    }
}

public struct SubjectTemplateDescriptor: Identifiable, Hashable {
    public let id: String
    public let profile: TeacherSubjectProfile
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let notebookBlueprintId: String
    public let columnPreset: SubjectNotebookColumnPreset

    public init(
        id: String,
        profile: TeacherSubjectProfile,
        title: String,
        subtitle: String,
        systemImage: String,
        notebookBlueprintId: String,
        columnPreset: SubjectNotebookColumnPreset? = nil
    ) {
        self.id = id
        self.profile = profile
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.notebookBlueprintId = notebookBlueprintId
        self.columnPreset = columnPreset ?? SubjectNotebookColumnPreset(
            blueprintId: notebookBlueprintId,
            defaultTitle: title,
            weight: notebookBlueprintId == "rubric" ? 15 : (notebookBlueprintId == "written_test" ? 10 : 0),
            countsTowardAverage: ["written_test", "rubric", "checklist"].contains(notebookBlueprintId),
            categoryName: nil
        )
    }
}

public enum SubjectTemplateRegistry {
    public static let all: [SubjectTemplateDescriptor] = [
        .init(id: "general_numeric", profile: .general, title: "Nota numérica", subtitle: "Calificación evaluable 0-10.", systemImage: "number.circle", notebookBlueprintId: "written_test", columnPreset: .init(blueprintId: "written_test", defaultTitle: "Nota numérica", weight: 10, countsTowardAverage: true, categoryName: "Evaluación")),
        .init(id: "general_rubric", profile: .general, title: "Rúbrica", subtitle: "Criterios con niveles.", systemImage: "checklist", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Rúbrica", weight: 15, countsTowardAverage: true, categoryName: "Evaluación")),
        .init(id: "general_checklist", profile: .general, title: "Lista de control", subtitle: "Seguimiento sí/no rápido.", systemImage: "checkmark.square", notebookBlueprintId: "checklist", columnPreset: .init(blueprintId: "checklist", defaultTitle: "Lista de control", weight: 5, countsTowardAverage: true, categoryName: "Seguimiento")),
        .init(id: "general_observation", profile: .general, title: "Observación", subtitle: "Evidencia cualitativa breve.", systemImage: "note.text", notebookBlueprintId: "observation", columnPreset: .init(blueprintId: "observation", defaultTitle: "Observación", weight: 0, countsTowardAverage: false, categoryName: "Seguimiento")),
        .init(id: "general_evidence", profile: .general, title: "Evidencia", subtitle: "Adjunto o referencia desde inspector.", systemImage: "paperclip.circle", notebookBlueprintId: "evidence", columnPreset: .init(blueprintId: "evidence", defaultTitle: "Evidencia", weight: 0, countsTowardAverage: false, categoryName: "Extras")),
        .init(id: "languages_reading", profile: .languages, title: "Comprensión lectora", subtitle: "Registro evaluable de lectura.", systemImage: "text.book.closed", notebookBlueprintId: "written_test", columnPreset: .init(blueprintId: "written_test", defaultTitle: "Comprensión lectora", weight: 10, countsTowardAverage: true, unitOrSituation: "Lenguas · Lectura", categoryName: "Lenguas")),
        .init(id: "languages_writing", profile: .languages, title: "Expresión escrita", subtitle: "Rúbrica o nota de producción escrita.", systemImage: "pencil.and.scribble", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Expresión escrita", weight: 15, countsTowardAverage: true, unitOrSituation: "Lenguas · Escritura", categoryName: "Lenguas")),
        .init(id: "languages_oral", profile: .languages, title: "Oralidad", subtitle: "Presentación, fluidez o interacción.", systemImage: "person.wave.2", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Oralidad", weight: 15, countsTowardAverage: true, unitOrSituation: "Lenguas · Oralidad", categoryName: "Lenguas")),
        .init(id: "languages_fluency", profile: .languages, title: "Fluidez lectora", subtitle: "Medición de progreso lector.", systemImage: "timer", notebookBlueprintId: "observation", columnPreset: .init(blueprintId: "observation", defaultTitle: "Fluidez lectora", weight: 0, countsTowardAverage: false, unitOrSituation: "Medición · Fluidez lectora", categoryName: "Lenguas")),
        .init(id: "sciences_lab", profile: .sciences, title: "Práctica de laboratorio", subtitle: "Proceso, seguridad y resultado.", systemImage: "flask", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Práctica de laboratorio", weight: 15, countsTowardAverage: true, unitOrSituation: "Ciencias · Laboratorio", categoryName: "Ciencias")),
        .init(id: "sciences_report", profile: .sciences, title: "Informe científico", subtitle: "Evidencia escrita o multimedia.", systemImage: "doc.text.magnifyingglass", notebookBlueprintId: "evidence", columnPreset: .init(blueprintId: "evidence", defaultTitle: "Informe científico", weight: 0, countsTowardAverage: false, unitOrSituation: "Ciencias · Informe", categoryName: "Ciencias")),
        .init(id: "sciences_notebook", profile: .sciences, title: "Cuaderno de laboratorio", subtitle: "Observación de trabajo continuo.", systemImage: "book.closed", notebookBlueprintId: "observation", columnPreset: .init(blueprintId: "observation", defaultTitle: "Cuaderno de laboratorio", weight: 0, countsTowardAverage: false, unitOrSituation: "Ciencias · Cuaderno", categoryName: "Ciencias")),
        .init(id: "math_problem_solving", profile: .math, title: "Resolución de problemas", subtitle: "Rúbrica competencial.", systemImage: "function", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Resolución de problemas", weight: 15, countsTowardAverage: true, unitOrSituation: "Matemáticas · Problemas", categoryName: "Matemáticas")),
        .init(id: "math_calculation", profile: .math, title: "Cálculo", subtitle: "Resultado numérico evaluable.", systemImage: "number", notebookBlueprintId: "written_test", columnPreset: .init(blueprintId: "written_test", defaultTitle: "Cálculo", weight: 10, countsTowardAverage: true, unitOrSituation: "Matemáticas · Cálculo", categoryName: "Matemáticas")),
        .init(id: "math_competency", profile: .math, title: "Prueba competencial", subtitle: "Evidencia con peso en media.", systemImage: "chart.bar.doc.horizontal", notebookBlueprintId: "written_test", columnPreset: .init(blueprintId: "written_test", defaultTitle: "Prueba competencial", weight: 15, countsTowardAverage: true, unitOrSituation: "Matemáticas · Competencial", categoryName: "Matemáticas")),
        .init(id: "music_performance", profile: .music, title: "Interpretación", subtitle: "Rúbrica de práctica musical.", systemImage: "music.note", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Interpretación", weight: 15, countsTowardAverage: true, unitOrSituation: "Música · Interpretación", categoryName: "Música")),
        .init(id: "music_rhythm", profile: .music, title: "Ritmo", subtitle: "Lista de control o logro.", systemImage: "metronome", notebookBlueprintId: "checklist", columnPreset: .init(blueprintId: "checklist", defaultTitle: "Ritmo", weight: 5, countsTowardAverage: true, unitOrSituation: "Música · Ritmo", categoryName: "Música")),
        .init(id: "music_pitch", profile: .music, title: "Afinación", subtitle: "Observación de progreso.", systemImage: "waveform", notebookBlueprintId: "observation", columnPreset: .init(blueprintId: "observation", defaultTitle: "Afinación", weight: 0, countsTowardAverage: false, unitOrSituation: "Música · Afinación", categoryName: "Música")),
        .init(id: "music_listening", profile: .music, title: "Escucha activa", subtitle: "Observación cualitativa.", systemImage: "ear", notebookBlueprintId: "observation", columnPreset: .init(blueprintId: "observation", defaultTitle: "Escucha activa", weight: 0, countsTowardAverage: false, unitOrSituation: "Música · Escucha", categoryName: "Música")),
        .init(id: "technology_project", profile: .technology, title: "Proyecto técnico", subtitle: "Hitos y producto final.", systemImage: "hammer", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Proyecto técnico", weight: 15, countsTowardAverage: true, unitOrSituation: "Tecnología · Proyecto", categoryName: "Tecnología")),
        .init(id: "technology_prototype", profile: .technology, title: "Prototipo", subtitle: "Evidencia del proceso.", systemImage: "wrench.and.screwdriver", notebookBlueprintId: "evidence", columnPreset: .init(blueprintId: "evidence", defaultTitle: "Prototipo", weight: 0, countsTowardAverage: false, unitOrSituation: "Tecnología · Prototipo", categoryName: "Tecnología")),
        .init(id: "pe_measurement", profile: .physicalEducation, title: "Medición física", subtitle: "Marca, baremo o progreso.", systemImage: "stopwatch", notebookBlueprintId: "observation", columnPreset: .init(blueprintId: "observation", defaultTitle: "Medición física", weight: 0, countsTowardAverage: false, unitOrSituation: "EF · Condición física", categoryName: "EF")),
        .init(id: "pe_scale", profile: .physicalEducation, title: "Baremo", subtitle: "Referencia para mediciones.", systemImage: "chart.xyaxis.line", notebookBlueprintId: "written_test", columnPreset: .init(blueprintId: "written_test", defaultTitle: "Baremo", weight: 10, countsTowardAverage: true, unitOrSituation: "EF · Baremo", categoryName: "EF")),
        .init(id: "pe_session", profile: .physicalEducation, title: "Sesión práctica", subtitle: "Seguimiento operativo.", systemImage: "figure.run", notebookBlueprintId: "checklist", columnPreset: .init(blueprintId: "checklist", defaultTitle: "Sesión práctica", weight: 5, countsTowardAverage: true, unitOrSituation: "EF · Sesión práctica", categoryName: "EF")),
        .init(id: "pe_rubric", profile: .physicalEducation, title: "Rúbrica motriz", subtitle: "Criterios específicos de área.", systemImage: "figure.cooldown", notebookBlueprintId: "rubric", columnPreset: .init(blueprintId: "rubric", defaultTitle: "Rúbrica motriz", weight: 15, countsTowardAverage: true, unitOrSituation: "EF · Rúbrica motriz", categoryName: "EF")),
    ]

    public static func templates(for profiles: Set<TeacherSubjectProfile>) -> [SubjectTemplateDescriptor] {
        let normalized = profiles.isEmpty ? Set([TeacherSubjectProfile.general]) : profiles
        return all.filter { normalized.contains($0.profile) }
    }
}

public enum SettingsRoute: Hashable, Identifiable {
    case general
    case schedule
    case evaluation
    case notebook
    case dataSecurity
    case dataManagement
    case sync
    case appleAI
    case appearance
    case diagnostics

    public var id: String {
        switch self {
        case .general: return "general"
        case .schedule: return "schedule"
        case .evaluation: return "evaluation"
        case .notebook: return "notebook"
        case .dataSecurity: return "dataSecurity"
        case .dataManagement: return "dataManagement"
        case .sync: return "sync"
        case .appleAI: return "appleAI"
        case .appearance: return "appearance"
        case .diagnostics: return "diagnostics"
        }
    }
}
