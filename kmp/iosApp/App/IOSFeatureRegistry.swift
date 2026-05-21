enum IOSFeaturePriority {
    case daily
    case teaching
    case tools
    case settings
}

struct IOSFeatureDescriptor: Identifiable, Hashable {
    let module: AppWorkspaceModule
    let title: String
    let subtitle: String
    let systemImage: String
    let priority: IOSFeaturePriority
    let visibleInDailyMode: Bool

    var id: AppWorkspaceModule { module }
}

enum IOSFeatureRegistry {
    static let daily: [IOSFeatureDescriptor] = [
        .init(module: .dashboard, title: "Hoy", subtitle: "Resumen operativo", systemImage: "rectangle.3.group", priority: .daily, visibleInDailyMode: true),
        .init(module: .teacherRadar, title: "Radar", subtitle: "Alertas docentes", systemImage: "scope", priority: .daily, visibleInDailyMode: true),
        .init(module: .notebook, title: "Cuaderno", subtitle: "Evaluación diaria", systemImage: "tablecells", priority: .daily, visibleInDailyMode: true),
        .init(module: .attendance, title: "Asistencia", subtitle: "Pase y seguimiento", systemImage: "checklist.checked", priority: .daily, visibleInDailyMode: true),
        .init(module: .planner, title: "Planificación", subtitle: "Sesiones y agenda", systemImage: "calendar", priority: .daily, visibleInDailyMode: true)
    ]

    static let secondary: [IOSFeatureDescriptor] = [
        .init(module: .courses, title: "Cursos", subtitle: "Grupos y configuración", systemImage: "rectangle.3.group.bubble.left", priority: .teaching, visibleInDailyMode: false),
        .init(module: .students, title: "Alumnado", subtitle: "Perfiles y seguimiento", systemImage: "person.3", priority: .teaching, visibleInDailyMode: false),
        .init(module: .diary, title: "Diario de aula", subtitle: "Trazabilidad de sesión", systemImage: "doc.text", priority: .teaching, visibleInDailyMode: false),
        .init(module: .evaluationHub, title: "Evaluación", subtitle: "Instrumentos y calendario", systemImage: "chart.bar.doc.horizontal", priority: .teaching, visibleInDailyMode: false),
        .init(module: .rubrics, title: "Rúbricas", subtitle: "Banco de evaluación", systemImage: "checklist", priority: .teaching, visibleInDailyMode: false),
        .init(module: .reports, title: "Informes", subtitle: "Salida docente", systemImage: "doc.richtext", priority: .teaching, visibleInDailyMode: false),
        .init(module: .library, title: "Biblioteca", subtitle: "Plantillas reutilizables", systemImage: "books.vertical", priority: .tools, visibleInDailyMode: false),
        .init(module: .peSessions, title: "EF · Sesiones", subtitle: "Operativa en pista", systemImage: "figure.run", priority: .tools, visibleInDailyMode: false),
        .init(module: .peTests, title: "EF · Condición física", subtitle: "Baremos e históricos", systemImage: "stopwatch", priority: .tools, visibleInDailyMode: false),
        .init(module: .peRubrics, title: "EF · Rúbricas", subtitle: "Rúbricas motrices", systemImage: "figure.cooldown", priority: .tools, visibleInDailyMode: false),
        .init(module: .peIncidents, title: "EF · Incidencias", subtitle: "Seguridad y seguimiento", systemImage: "cross.case", priority: .tools, visibleInDailyMode: false),
        .init(module: .peMaterial, title: "EF · Material", subtitle: "Inventario rápido", systemImage: "shippingbox", priority: .tools, visibleInDailyMode: false),
        .init(module: .peTournaments, title: "EF · Torneos", subtitle: "Competición y resultados", systemImage: "trophy", priority: .tools, visibleInDailyMode: false),
        .init(module: .settings, title: "Ajustes", subtitle: "Configuración", systemImage: "gearshape", priority: .settings, visibleInDailyMode: false),
        .init(module: .backups, title: "Seguridad", subtitle: "Copias y restauración", systemImage: "lock.shield", priority: .settings, visibleInDailyMode: false)
    ]

    static let all: [IOSFeatureDescriptor] = daily + secondary

    static func descriptor(for module: AppWorkspaceModule) -> IOSFeatureDescriptor {
        all.first(where: { $0.module == module })
            ?? .init(
                module: module,
                title: module.title,
                subtitle: module.subtitle,
                systemImage: module.systemImage,
                priority: .tools,
                visibleInDailyMode: false
            )
    }
}
