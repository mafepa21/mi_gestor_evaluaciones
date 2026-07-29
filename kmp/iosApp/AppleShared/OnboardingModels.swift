import Foundation
import SwiftUI
import MiGestorKit

/// Pasos de la configuración inicial, en el orden que tiene sentido docente:
/// primero las fechas del curso, luego el horario (que crea los grupos solo),
/// después el alumnado y por último las situaciones de aprendizaje.
///
/// Los instrumentos de evaluación quedan deliberadamente fuera de esta primera
/// tanda: no hacen falta para empezar a dar clase y alargarían el recorrido
/// justo donde el docente ya quiere cerrar el asistente.
enum OnboardingStep: String, CaseIterable, Identifiable {
    case course
    case schedule
    case groups
    case students
    case learningSituations

    var id: String { rawValue }

    var number: Int { (OnboardingStep.allCases.firstIndex(of: self) ?? 0) + 1 }

    var title: String {
        switch self {
        case .course: return "Fechas del curso"
        case .schedule: return "Tu horario semanal"
        case .groups: return "Tus grupos"
        case .students: return "El alumnado de cada grupo"
        case .learningSituations: return "Situaciones de aprendizaje"
        }
    }

    /// Una línea, en lenguaje de profesor, explicando por qué este paso importa.
    /// Sin esto la lista es una checklist muda y el docente no sabe qué gana.
    var whyItMatters: String {
        switch self {
        case .course:
            return "Marca cuándo empieza y acaba el curso. Todo lo demás cuelga de estas dos fechas."
        case .schedule:
            return "Las franjas de cada semana. Con ellas el Planner ya sabe qué toca cada día."
        case .groups:
            return "Un grupo por cada clase que das. Se crean solos al meter el horario."
        case .students:
            return "Sin alumnado no hay cuaderno ni asistencia. Es el paso que desbloquea el día a día."
        case .learningSituations:
            return "Lo que vas a trabajar y con qué lo evalúas. Puedes dejarlo para más adelante."
        }
    }

    var systemImage: String {
        switch self {
        case .course: return "calendar"
        case .schedule: return "clock"
        case .groups: return "person.2"
        case .students: return "person.3"
        case .learningSituations: return "doc.text.magnifyingglass"
        }
    }

    /// Etiqueta del camino de importación. `nil` cuando el paso no admite importar
    /// (los grupos no se importan: salen del horario).
    var importActionTitle: String? {
        switch self {
        case .course: return nil
        case .schedule: return "Importar horario"
        case .groups: return nil
        case .students: return "Importar Excel"
        case .learningSituations: return "Importar documento"
        }
    }

    var manualActionTitle: String {
        switch self {
        case .course: return "Poner fechas"
        case .schedule: return "Crear franjas a mano"
        case .groups: return "Ver mis grupos"
        case .students: return "Escribir nombres"
        case .learningSituations: return "Crearla a mano"
        }
    }

    /// Qué se necesita antes de poder hacer este paso. Se escribe en la fila
    /// cuando está bloqueado, en vez de dejarlo en gris sin explicación.
    var requirement: OnboardingStep? {
        switch self {
        case .course: return nil
        case .schedule: return .course
        case .groups: return .schedule
        case .students: return .groups
        case .learningSituations: return .groups
        }
    }
}

/// Pantalla del onboarding que está abierta ahora mismo.
enum OnboardingRoute: Identifiable, Equatable {
    case welcome
    case checklist
    /// Asistente de horario. `startOnSlots` lo abre directamente en el paso de
    /// franjas; `autoPresentImporter` además dispara el selector de archivo.
    case scheduleWizard(startOnSlots: Bool, autoPresentImporter: Bool)
    case students(startWithImport: Bool)

    var id: String {
        switch self {
        case .welcome: return "welcome"
        case .checklist: return "checklist"
        case .scheduleWizard(let slots, let importer): return "wizard-\(slots)-\(importer)"
        case .students(let importer): return "students-\(importer)"
        }
    }
}

/// Estado de la configuración inicial.
///
/// Ojo con el recuento de grupos y alumnado: la clase de ejemplo que siembra
/// `seedDemoDataIfEmpty` en la primera ejecución se descuenta siempre. Ni marca
/// pasos como hechos ni hace que la base parezca "con datos".
///
/// El progreso se calcula mirando los datos reales (¿hay franjas? ¿hay grupos?
/// ¿hay alumnado?), no con un contador propio: si el docente hace una tarea por
/// su cuenta, restaura un backup o le llega por Sync LAN, la lista se entera.
///
/// Única excepción: las fechas del curso. El curso escolar y la agenda se crean
/// solos con valores por defecto (`getOrCreatePrimarySchedule`), así que su mera
/// existencia no prueba que nadie las haya revisado. Ahí sí hace falta una marca
/// explícita, que también se da por buena en cuanto existe alguna franja: no se
/// llega a tener horario sin haber pasado por las fechas.
///
/// La bienvenida no es un "solo una vez en la vida del dispositivo": se
/// replantea en cada arranque del proceso mientras la base siga realmente
/// vacía. Eso cubre a propósito el borrado total y el modular de Ajustes →
/// Zona de Riesgo sin necesitar ningún gancho especial en esas pantallas —
/// las dos fuerzan el reinicio de la app (aviso manual en iOS, relanzamiento
/// automático en macOS), así que el siguiente arranque ya encuentra la base
/// vacía y decide solo. También cubre a un docente que ha ido borrando grupos
/// y alumnado a mano hasta vaciarla. Lo único que no se repite es la propia
/// tarjeta de bienvenida: a partir de la primera vez que se ha visto, una
/// base vacía salta directa a la lista de pasos, no a la presentación.
@MainActor
final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()

    private enum Keys {
        static let welcomeSeen = "onboarding.welcomeSeen.v1"
        static let courseConfirmed = "onboarding.courseConfirmed.v1"
    }

    @Published private(set) var completedSteps: Set<OnboardingStep> = []
    @Published private(set) var groupCount = 0
    @Published private(set) var studentCount = 0
    @Published private(set) var slotCount = 0
    @Published private(set) var hasLoadedState = false

    /// Una sola ruta activa en vez de un booleano por pantalla: encadenar varios
    /// `.sheet` sobre la misma vista es frágil en SwiftUI (el último gana), y
    /// aquí hay cuatro hojas que se abren unas desde otras.
    @Published var route: OnboardingRoute?

    /// En memoria, no persistido: evita repreguntar dos veces dentro del mismo
    /// arranque del proceso (p.ej. si `bootstrap(bridge:)` se dispara más de
    /// una vez por un cambio de estado). Cada arranque nuevo lo reinicia solo.
    private var hasPromptedThisLaunch = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Flags persistidos

    var hasSeenWelcome: Bool { defaults.bool(forKey: Keys.welcomeSeen) }
    var isCourseConfirmed: Bool { defaults.bool(forKey: Keys.courseConfirmed) }

    // MARK: - Derivados

    var isDone: Bool { completedSteps.count == OnboardingStep.allCases.count }

    var nextStep: OnboardingStep? {
        OnboardingStep.allCases.first { !completedSteps.contains($0) }
    }

    var completedCount: Int { completedSteps.count }
    var totalCount: Int { OnboardingStep.allCases.count }

    func isCompleted(_ step: OnboardingStep) -> Bool { completedSteps.contains(step) }

    /// Un paso está disponible cuando su requisito ya está cubierto. El propio
    /// paso, aunque esté hecho, sigue disponible: se puede volver a él.
    func isAvailable(_ step: OnboardingStep) -> Bool {
        guard let requirement = step.requirement else { return true }
        return completedSteps.contains(requirement)
    }

    func blockedReason(for step: OnboardingStep) -> String? {
        guard let requirement = step.requirement, !completedSteps.contains(requirement) else { return nil }
        switch requirement {
        case .course: return "Antes pon las fechas del curso."
        case .schedule: return "Antes crea tu horario."
        case .groups: return "Antes necesitas al menos un grupo."
        case .students: return "Antes añade alumnado."
        case .learningSituations: return "Antes crea una situación de aprendizaje."
        }
    }

    // MARK: - Acciones

    func markCourseConfirmed() {
        defaults.set(true, forKey: Keys.courseConfirmed)
        completedSteps.insert(.course)
    }

    func markWelcomeSeen() {
        defaults.set(true, forKey: Keys.welcomeSeen)
    }

    /// "Ahora no" y "Terminar": no se vuelve a abrir solo dentro de este mismo
    /// arranque. Sigue accesible a mano desde Ajustes → General → Primeros
    /// pasos, y volverá a saltar solo si la base sigue vacía en un arranque
    /// posterior (ver el aviso de la clase, arriba).
    func dismiss() {
        markWelcomeSeen()
        hasPromptedThisLaunch = true
        route = nil
    }

    func openChecklist() {
        route = .checklist
    }

    // MARK: - Arranque

    /// Se llama en cada arranque del proceso, no solo la primera vez.
    /// Reevalúa si la base está realmente vacía (grupos y alumnado reales,
    /// descontando la clase de demo) y, si lo está, presenta el onboarding —
    /// la bienvenida completa la primera vez que se ve en este dispositivo,
    /// y directamente la lista de pasos las siguientes, para no repetir la
    /// misma presentación a quien ya la conoce.
    ///
    /// Espera primero a que `bridge.bootstrap()` haya terminado del todo,
    /// primer *pull* de Sync LAN incluido. Sin esa espera, un iPad recién
    /// emparejado vería su base local vacía por un instante y podría marcarla
    /// como "sin datos" antes de que llegue lo que ya tiene el otro
    /// dispositivo — con la bienvenida repitiéndose en cada arranque (ver
    /// más abajo), ese falso vacío podría no ser un caso puntual sino
    /// reaparecer una y otra vez si el *pull* tarda.
    func bootstrap(bridge: KmpBridge) async {
        await waitUntilBridgeBootstrapped(bridge)
        await refresh(bridge: bridge)
        guard !hasPromptedThisLaunch, groupCount == 0, studentCount == 0 else { return }
        hasPromptedThisLaunch = true
        route = hasSeenWelcome ? .checklist : .welcome
    }

    /// Espera a `bridge.hasCompletedBootstrap`, con un límite de tiempo por si
    /// `bootstrap()` se quedara colgado: mejor una decisión sobre datos
    /// parciales que bloquear el onboarding para siempre. Sondeo simple en vez
    /// de suscribirse al publisher: ambos, `OnboardingStore` y `KmpBridge`,
    /// están aislados al actor principal, así que leer la propiedad aquí ya es
    /// una lectura directa y segura, sin cruzar de actor.
    private func waitUntilBridgeBootstrapped(_ bridge: KmpBridge, timeoutSeconds: Double = 8) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !bridge.hasCompletedBootstrap, Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    /// Marca que pone `KmpContainer.seedDemoDataIfEmpty` a la clase de ejemplo
    /// que crea en la primera ejecución ("3 ESO A", con Ana López y Pablo
    /// García). Sin filtrarla, una instalación recién estrenada nunca parecería
    /// vacía y la bienvenida no llegaría a salir nunca.
    private static let demoClassMarker = "Clase demo"

    func refresh(bridge: KmpBridge) async {
        await bridge.ensureClassesLoaded()
        try? await bridge.refreshStudentsDirectory()

        var done: Set<OnboardingStep> = []

        let demoClassIds = bridge.classes
            .filter { $0.description_ == Self.demoClassMarker }
            .map(\.id)
        var demoStudentIds: Set<Int64> = []
        for classId in demoClassIds {
            let students = (try? await bridge.students(forClassId: classId)) ?? []
            demoStudentIds.formUnion(students.map(\.id))
        }

        groupCount = bridge.classes.count - demoClassIds.count
        studentCount = bridge.allStudents.filter { !demoStudentIds.contains($0.id) }.count

        if let schedule = try? await bridge.plannerTeacherSchedule() {
            let slots = (try? await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id)) ?? []
            slotCount = slots.count
        } else {
            slotCount = 0
        }

        if isCourseConfirmed || slotCount > 0 { done.insert(.course) }
        if slotCount > 0 { done.insert(.schedule) }
        if groupCount > 0 { done.insert(.groups) }
        if studentCount > 0 { done.insert(.students) }
        let situations = (try? await bridge.learningSituations()) ?? []
        if !situations.isEmpty { done.insert(.learningSituations) }

        completedSteps = done
        hasLoadedState = true
    }
}
