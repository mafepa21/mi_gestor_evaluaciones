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

public struct SubjectTemplateDescriptor: Identifiable, Hashable {
    public let id: String
    public let profile: TeacherSubjectProfile
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let notebookBlueprintId: String

    public init(
        id: String,
        profile: TeacherSubjectProfile,
        title: String,
        subtitle: String,
        systemImage: String,
        notebookBlueprintId: String
    ) {
        self.id = id
        self.profile = profile
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.notebookBlueprintId = notebookBlueprintId
    }
}

public enum SubjectTemplateRegistry {
    public static let all: [SubjectTemplateDescriptor] = [
        .init(id: "general_numeric", profile: .general, title: "Nota numérica", subtitle: "Calificación evaluable 0-10.", systemImage: "number.circle", notebookBlueprintId: "written_test"),
        .init(id: "general_rubric", profile: .general, title: "Rúbrica", subtitle: "Criterios con niveles.", systemImage: "checklist", notebookBlueprintId: "rubric"),
        .init(id: "general_checklist", profile: .general, title: "Lista de control", subtitle: "Seguimiento sí/no rápido.", systemImage: "checkmark.square", notebookBlueprintId: "checklist"),
        .init(id: "general_observation", profile: .general, title: "Observación", subtitle: "Evidencia cualitativa breve.", systemImage: "note.text", notebookBlueprintId: "observation"),
        .init(id: "general_evidence", profile: .general, title: "Evidencia", subtitle: "Adjunto o referencia desde inspector.", systemImage: "paperclip.circle", notebookBlueprintId: "evidence"),
        .init(id: "languages_reading", profile: .languages, title: "Comprensión lectora", subtitle: "Registro evaluable de lectura.", systemImage: "text.book.closed", notebookBlueprintId: "written_test"),
        .init(id: "languages_writing", profile: .languages, title: "Expresión escrita", subtitle: "Rúbrica o nota de producción escrita.", systemImage: "pencil.and.scribble", notebookBlueprintId: "rubric"),
        .init(id: "languages_oral", profile: .languages, title: "Oralidad", subtitle: "Presentación, fluidez o interacción.", systemImage: "person.wave.2", notebookBlueprintId: "rubric"),
        .init(id: "languages_fluency", profile: .languages, title: "Fluidez lectora", subtitle: "Medición de progreso lector.", systemImage: "timer", notebookBlueprintId: "observation"),
        .init(id: "sciences_lab", profile: .sciences, title: "Práctica de laboratorio", subtitle: "Proceso, seguridad y resultado.", systemImage: "flask", notebookBlueprintId: "rubric"),
        .init(id: "sciences_report", profile: .sciences, title: "Informe científico", subtitle: "Evidencia escrita o multimedia.", systemImage: "doc.text.magnifyingglass", notebookBlueprintId: "evidence"),
        .init(id: "sciences_notebook", profile: .sciences, title: "Cuaderno de laboratorio", subtitle: "Observación de trabajo continuo.", systemImage: "book.closed", notebookBlueprintId: "observation"),
        .init(id: "math_problem_solving", profile: .math, title: "Resolución de problemas", subtitle: "Rúbrica competencial.", systemImage: "function", notebookBlueprintId: "rubric"),
        .init(id: "math_calculation", profile: .math, title: "Cálculo", subtitle: "Resultado numérico evaluable.", systemImage: "number", notebookBlueprintId: "written_test"),
        .init(id: "math_competency", profile: .math, title: "Prueba competencial", subtitle: "Evidencia con peso en media.", systemImage: "chart.bar.doc.horizontal", notebookBlueprintId: "written_test"),
        .init(id: "music_performance", profile: .music, title: "Interpretación", subtitle: "Rúbrica de práctica musical.", systemImage: "music.note", notebookBlueprintId: "rubric"),
        .init(id: "music_rhythm", profile: .music, title: "Ritmo", subtitle: "Lista de control o logro.", systemImage: "metronome", notebookBlueprintId: "checklist"),
        .init(id: "music_listening", profile: .music, title: "Escucha activa", subtitle: "Observación cualitativa.", systemImage: "ear", notebookBlueprintId: "observation"),
        .init(id: "technology_project", profile: .technology, title: "Proyecto técnico", subtitle: "Hitos y producto final.", systemImage: "hammer", notebookBlueprintId: "rubric"),
        .init(id: "technology_prototype", profile: .technology, title: "Prototipo", subtitle: "Evidencia del proceso.", systemImage: "wrench.and.screwdriver", notebookBlueprintId: "evidence"),
        .init(id: "pe_measurement", profile: .physicalEducation, title: "Medición física", subtitle: "Marca, baremo o progreso.", systemImage: "stopwatch", notebookBlueprintId: "observation"),
        .init(id: "pe_scale", profile: .physicalEducation, title: "Baremo", subtitle: "Referencia para mediciones.", systemImage: "chart.xyaxis.line", notebookBlueprintId: "written_test"),
        .init(id: "pe_session", profile: .physicalEducation, title: "Sesión práctica", subtitle: "Seguimiento operativo.", systemImage: "figure.run", notebookBlueprintId: "checklist"),
        .init(id: "pe_rubric", profile: .physicalEducation, title: "Rúbrica motriz", subtitle: "Criterios específicos de área.", systemImage: "figure.cooldown", notebookBlueprintId: "rubric"),
    ]

    public static func templates(for profiles: Set<TeacherSubjectProfile>) -> [SubjectTemplateDescriptor] {
        let normalized = profiles.isEmpty ? Set([TeacherSubjectProfile.general]) : profiles
        return all.filter { normalized.contains($0.profile) }
    }
}

public enum SettingsRoute: Hashable, Identifiable {
    case general
    case evaluation
    case notebook
    case dataSecurity
    case sync
    case appleAI
    case appearance
    case diagnostics
    
    public var id: String {
        switch self {
        case .general: return "general"
        case .evaluation: return "evaluation"
        case .notebook: return "notebook"
        case .dataSecurity: return "dataSecurity"
        case .sync: return "sync"
        case .appleAI: return "appleAI"
        case .appearance: return "appearance"
        case .diagnostics: return "diagnostics"
        }
    }
}
