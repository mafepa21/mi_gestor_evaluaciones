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
    /// Aviso de que al salir de un torneo no se guardaron los últimos cambios. Vive aquí (y no en la
    /// pantalla) para no perderse si se cambia de módulo; se muestra en Torneos y en la SdA hasta que se descarta.
    @Published private(set) var saveWarning: String?
    /// `true` mientras el modo directo ocupa la pantalla (el Mac oculta su barra lateral).
    @Published private(set) var isLiveModeActive = false

    private init() {}

    func request(tournamentId: String, classId: Int64?) {
        pending = SdaTournamentOpenRequest(tournamentId: tournamentId, classId: classId)
    }

    func consume() {
        pending = nil
    }

    func reportSaveFailure(tournamentName: String) {
        saveWarning = "No se guardaron los últimos cambios de «\(tournamentName)». Ábrelo de nuevo y revisa los resultados."
    }

    func dismissSaveWarning() {
        saveWarning = nil
    }

    func setLiveModeActive(_ active: Bool) {
        guard isLiveModeActive != active else { return }
        isLiveModeActive = active
    }
}
