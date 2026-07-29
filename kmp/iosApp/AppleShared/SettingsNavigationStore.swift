import Foundation
import SwiftUI

/// Secciones de Ajustes a las que se puede saltar desde fuera.
enum SettingsSectionRequest: String {
    case general
    case courses
    case schedule
}

/// Permite pedir "abre Ajustes por esta sección" sin que cada shell tenga que
/// conocer el enum interno de su propia pantalla de Ajustes.
///
/// Hace falta desde que `Cursos` dejó de ser un módulo de la barra lateral: los
/// accesos que antes navegaban al módulo (el menú "Gestión de grupos" del
/// Cuaderno, la lista de primeros pasos) ahora tienen que aterrizar dentro de
/// Ajustes, y hay tres shells distintos que resolver.
@MainActor
final class SettingsNavigationStore: ObservableObject {
    static let shared = SettingsNavigationStore()

    /// La consume la pantalla de Ajustes al aparecer o al cambiar, y la limpia.
    @Published var pendingSection: SettingsSectionRequest?

    private init() {}

    func request(_ section: SettingsSectionRequest) {
        pendingSection = section
    }

    func consume() -> SettingsSectionRequest? {
        let section = pendingSection
        pendingSection = nil
        return section
    }
}
