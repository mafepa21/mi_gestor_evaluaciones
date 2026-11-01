import SwiftUI

/// Una clase de Mi Gestor, tal como la ve la Libreta: solo número y nombre.
/// La libreta guarda únicamente el número (`Notebook.linkedClassId`); el nombre se
/// lee cada vez de aquí, así un cambio de nombre en Mi Gestor se ve al momento.
struct LibretaClassOption: Identifiable, Hashable {
    let id: Int64
    let name: String
}

private struct LibretaClassesKey: EnvironmentKey {
    static let defaultValue: [LibretaClassOption] = []
}

extension EnvironmentValues {
    /// Clases de Mi Gestor disponibles para ligar libretas. Las pone `IOSRootView`.
    var libretaClasses: [LibretaClassOption] {
        get { self[LibretaClassesKey.self] }
        set { self[LibretaClassesKey.self] = newValue }
    }
}

extension Array where Element == LibretaClassOption {
    /// Nombre de la clase, o `nil` si no hay clase o ya no existe (se trata como «sin clase»).
    func name(for id: Int64?) -> String? {
        guard let id else { return nil }
        return first { $0.id == id }?.name
    }
}
