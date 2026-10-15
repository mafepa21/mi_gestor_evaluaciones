import Foundation
import SwiftUI

/// Petición de «abre el módulo Torneos con este torneo seleccionado».
struct SdaTournamentOpenRequest: Equatable {
    let tournamentId: String
    /// Curso del torneo. La pantalla cambia a él si hace falta.
    let classId: Int64?
}

/// Pasa el torneo a seleccionar desde la sección de la Situación a la pantalla Torneos.
/// Mismo patrón que `SettingsNavigationStore`: quien navega deja la petición y `onOpenModule`
/// cambia de módulo; la pantalla Torneos la consume cuando ya tiene los datos cargados.
@MainActor
final class SdaTournamentNavigationStore: ObservableObject {
    static let shared = SdaTournamentNavigationStore()

    @Published private(set) var pending: SdaTournamentOpenRequest?

    private init() {}

    func request(tournamentId: String, classId: Int64?) {
        pending = SdaTournamentOpenRequest(tournamentId: tournamentId, classId: classId)
    }

    func consume() {
        pending = nil
    }
}
