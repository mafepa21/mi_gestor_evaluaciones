import Foundation
import ServiceManagement

/// Sync LAN con la app del Mac cerrada.
///
/// El helper (`MiGestorCommandCenter`) es un proceso propio que lee y escribe la misma
/// base que la app. Antes moría al cerrar la app, así que lo que se editaba en el iPad
/// con el Mac «apagado» no llegaba hasta volver a abrirla, y entretanto los dos
/// dispositivos se separaban. Ahora:
/// - al cerrar la app, el helper se queda vivo si hay un iPad enlazado;
/// - al iniciar sesión en el Mac, lo arranca un agente de `launchd` (`SMAppService`);
/// - al abrir la app, se cierra ese helper antes de abrir la base (la adopción de un
///   dataset sustituye el fichero en el arranque) y la app arranca el suyo.
enum MacSyncBackgroundService {
    static let keepRunningDefaultsKey = "sync.mac.keepRunningWhenClosed"
    static let agentPlistName = "com.migestor.mac.sync-helper.plist"

    /// Activado por defecto: es lo que evita que los dos dispositivos se separen.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: keepRunningDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keepRunningDefaultsKey) }
    }

    /// El helper guarda la contraseña del enlace en el llavero desktop.
    static var hasPairedDevice: Bool {
        IosKeychainStore(service: "com.migestor.sync.desktop").loadString(key: "paired-token") != nil
    }

    /// El helper deja aquí la base del iPad pendiente de adoptar (ver `LocalSyncServer`).
    static var hasStagedAdoption: Bool {
        guard let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MiGestor", isDirectory: true) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending_adopt.json").path)
    }

    /// Decide si el helper sigue vivo al cerrar la app.
    ///
    /// No se queda si hay una restauración o un borrado pendientes de reinicio, ni con
    /// una adopción preparada: recibiría cambios del iPad en una base que el próximo
    /// arranque va a sustituir.
    static func keepsHelperRunningAfterQuit(
        isEnabled: Bool,
        isHelperRunning: Bool,
        hasPairedDevice: Bool,
        needsRestart: Bool,
        hasStagedAdoption: Bool
    ) -> Bool {
        isEnabled && isHelperRunning && hasPairedDevice && !needsRestart && !hasStagedAdoption
    }

    // MARK: - Arranque al iniciar sesión

    enum LoginItemStatus: Equatable {
        case enabled
        case requiresApproval
        case disabled
        case failed(String)
    }

    private static var agent: SMAppService { SMAppService.agent(plistName: agentPlistName) }

    static var loginItemStatus: LoginItemStatus {
        switch agent.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }

    /// Registra o retira el agente según el ajuste y si hay un iPad enlazado.
    ///
    /// Registrar lo arranca al momento (`RunAtLoad`). Por eso solo se registra al
    /// cerrar la app con el helper vivo (`allowRegister`): el del agente no consigue el
    /// puerto, termina solo y queda listo para el próximo inicio de sesión. Con la app
    /// abierta, dos helpers se pelearían por el puerto. Retirarlo se puede siempre.
    @discardableResult
    static func syncLoginItem(allowRegister: Bool) -> LoginItemStatus {
        let shouldBeRegistered = isEnabled && hasPairedDevice
        do {
            switch (shouldBeRegistered, agent.status) {
            case (true, .notRegistered), (true, .notFound):
                guard allowRegister else { break }
                try agent.register()
            case (false, .enabled), (false, .requiresApproval):
                try agent.unregister()
            default:
                break
            }
            return loginItemStatus
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
