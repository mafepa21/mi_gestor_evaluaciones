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
