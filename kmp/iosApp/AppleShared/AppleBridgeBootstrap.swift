import Foundation
import MiGestorKit

struct AppleBridgeBootstrap {
    let container: KmpContainer
    let platformName: String
    let databasePath: String

    static func current() -> AppleBridgeBootstrap {
        // La ruta se pide siempre al mismo módulo que abre el driver. No escribas el
        // nombre del fichero a mano aquí: hasta 2026-07 macOS apuntaba al nombre legacy
        // "mi_gestor_kmp.db" mientras el driver abría "desktop_mi_gestor_kmp.db", así que
        // las copias de seguridad salían vacías y la restauración no hacía nada.
        #if os(macOS)
        return AppleBridgeBootstrap(
            container: KmpContainer(driver: MacosDriverKt.createMacosDriver()),
            platformName: "macOS",
            databasePath: MacosDriverKt.getMacosDatabasePath()
        )
        #else
        return AppleBridgeBootstrap(
            container: KmpContainer(driver: IosDriverKt.createIosDriver()),
            platformName: "iOS",
            databasePath: IosDriverKt.getIosDatabasePath()
        )
        #endif
    }

    var connectedStatusText: String {
        "KMP conectado en \(platformName)"
    }
}
