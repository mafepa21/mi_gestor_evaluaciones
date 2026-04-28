import Foundation

enum MacFeatureSource: String {
    case parityIOS = "Paridad iOS"
    case inheritedDesktop = "Legado desktop"
    case applePlatform = "Servicios Apple"
}

struct MacFeatureDescriptor: Identifiable, Hashable {
    enum Feature: String, CaseIterable, Identifiable {
        case dashboard
        case notebook
        case attendance
        case planner
        case students
        case rubrics
        case physicalTests
        case sync
        case backups
        case reports
        case settings

        var id: String { rawValue }
    }

    let feature: Feature
    let title: String
    let subtitle: String
    let systemImage: String
    let source: MacFeatureSource
    let enabledInV1: Bool

    var id: Feature { feature }
}

enum MacFeatureRegistry {
    static let all: [MacFeatureDescriptor] = [
        .init(feature: .dashboard, title: "Dashboard", subtitle: "KPIs, agenda y pulso operativo", systemImage: "rectangle.3.group.bubble.left.fill", source: .parityIOS, enabledInV1: true),
        .init(feature: .notebook, title: "Cuaderno", subtitle: "Vista de clase, edición y guardado", systemImage: "tablecells.fill", source: .parityIOS, enabledInV1: true),
        .init(feature: .attendance, title: "Asistencia", subtitle: "Pase e historial", systemImage: "checklist.checked", source: .parityIOS, enabledInV1: true),
        .init(feature: .planner, title: "Planificación", subtitle: "Sesiones, unidades y agenda docente", systemImage: "calendar.badge.clock", source: .parityIOS, enabledInV1: true),
        .init(feature: .students, title: "Alumnado", subtitle: "Directorio y seguimiento rápido", systemImage: "person.3.sequence.fill", source: .parityIOS, enabledInV1: true),
        .init(feature: .rubrics, title: "Rúbricas", subtitle: "Banco de evaluación y edición", systemImage: "checklist.checked", source: .parityIOS, enabledInV1: true),
        .init(feature: .physicalTests, title: "EF · Condición física", subtitle: "Baremos, marcas e históricos", systemImage: "stopwatch.fill", source: .parityIOS, enabledInV1: true),
        .init(feature: .sync, title: "Sync LAN", subtitle: "Emparejado, pull y observabilidad", systemImage: "arrow.triangle.2.circlepath.circle.fill", source: .inheritedDesktop, enabledInV1: true),
        .init(feature: .backups, title: "Backups", subtitle: "Copias locales y restauración", systemImage: "externaldrive.badge.timemachine", source: .inheritedDesktop, enabledInV1: true),
        .init(feature: .reports, title: "Informes", subtitle: "Exportaciones y contexto IA", systemImage: "doc.text.image", source: .parityIOS, enabledInV1: true),
        .init(feature: .settings, title: "Ajustes", subtitle: "Preferencias, shell y feature flags", systemImage: "gearshape.2.fill", source: .applePlatform, enabledInV1: true),
    ]

    static func descriptor(for feature: MacFeatureDescriptor.Feature) -> MacFeatureDescriptor {
        all.first(where: { $0.feature == feature }) ?? all[0]
    }
}
