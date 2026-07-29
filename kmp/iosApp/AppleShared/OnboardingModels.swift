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
@MainActor
final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()

    private enum Keys {
        static let dismissed = "onboarding.dismissed.v1"
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Flags persistidos

    var isDismissed: Bool { defaults.bool(forKey: Keys.dismissed) }
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

    /// "Ahora no" y "Terminar": no se vuelve a abrir solo. Sigue accesible a
    /// mano desde Ajustes → General → Primeros pasos.
    func dismiss() {
        defaults.set(true, forKey: Keys.dismissed)
        markWelcomeSeen()
        route = nil
    }

    func openChecklist() {
        route = .checklist
    }

    // MARK: - Arranque

    /// Decide si hay que enseñar la bienvenida. Tres condiciones a la vez (nunca
    /// una sola): que no se haya visto ya, que no haya grupos ni alumnado reales
    /// (la clase de ejemplo sembrada no cuenta) y que no haya horario. Así una
    /// actualización de la app no le lanza un tutorial en la cara a un docente
    /// con el curso empezado.
    func bootstrap(bridge: KmpBridge) async {
        await refresh(bridge: bridge)
        guard !isDismissed, !hasSeenWelcome else { return }
        guard groupCount == 0, studentCount == 0 else {
            // Base con datos: el onboarding no aplica. Se marca como visto para
            // no volver a preguntarlo en cada arranque.
            markWelcomeSeen()
            return
        }
        route = .welcome
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
