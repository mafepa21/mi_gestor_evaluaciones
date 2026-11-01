import SwiftUI
import MiGestorKit

// Catálogo de pruebas físicas y tipos de medida compartidos por iPad y Mac.

enum PhysicalTestCapacity: String, CaseIterable, Identifiable {
    case resistance = "Resistencia"
    case strength = "Fuerza"
    case speed = "Velocidad"
    case flexibility = "Movilidad"

    var id: String { rawValue }
}

enum PhysicalTestMeasurement: String, CaseIterable, Identifiable {
    case time = "Tiempo"
    case distance = "Distancia"
    case repetitions = "Repeticiones"
    case level = "Nivel"

    var id: String { rawValue }

    var inputKind: NotebookCellInputKind {
        switch self {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .numeric010
        }
    }

    var scaleKind: NotebookScaleKind {
        switch self {
        case .time: return .time
        case .distance: return .distance
        case .repetitions: return .repetitions
        case .level: return .tenPoint
        }
    }
}

enum PhysicalTestResultMode: String, CaseIterable, Identifiable {
    case best = "Mejor intento"
    case average = "Media de intentos"
    case last = "Último intento"

    var id: String { rawValue }
}

struct PhysicalTestTemplate: Identifiable, Hashable {
    let id: String
    var name: String
    var capacity: PhysicalTestCapacity
    var measurement: PhysicalTestMeasurement
    var unit: String
    var direction: PhysicalTestScaleDirection
    var attempts: Int
    var resultMode: PhysicalTestResultMode
    var protocolText: String

    static let defaults: [PhysicalTestTemplate] = [
        .init(id: "course_navette", name: "Course Navette", capacity: .resistance, measurement: .level, unit: "periodo", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Test progresivo por periodos con señal acústica."),
        .init(id: "cooper", name: "Test Cooper", capacity: .resistance, measurement: .distance, unit: "m", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Distancia recorrida en 12 minutos."),
        .init(id: "horizontal_jump", name: "Salto horizontal", capacity: .strength, measurement: .distance, unit: "m", direction: .higherIsBetter, attempts: 3, resultMode: .best, protocolText: "Salto a pies juntos desde parado. Se registra la mejor marca."),
        .init(id: "push_ups", name: "Flexiones", capacity: .strength, measurement: .repetitions, unit: "rep", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Repeticiones técnicamente válidas."),
        .init(id: "sit_ups", name: "Abdominales 30\"", capacity: .strength, measurement: .repetitions, unit: "rep", direction: .higherIsBetter, attempts: 1, resultMode: .last, protocolText: "Repeticiones válidas durante 30 segundos."),
        .init(id: "speed_30m", name: "Velocidad 30 m", capacity: .speed, measurement: .time, unit: "s", direction: .lowerIsBetter, attempts: 2, resultMode: .best, protocolText: "Sprint de 30 metros con salida alta."),
        .init(id: "sit_and_reach", name: "Sit and reach", capacity: .flexibility, measurement: .distance, unit: "cm", direction: .higherIsBetter, attempts: 2, resultMode: .best, protocolText: "Flexión de tronco sentado con piernas extendidas.")
    ]
}
