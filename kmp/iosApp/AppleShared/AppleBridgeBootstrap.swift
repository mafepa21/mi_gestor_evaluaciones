import Foundation
import MiGestorKit

struct AppleBridgeBootstrap {
    let container: KmpContainer
    let platformName: String
    let databasePath: String

    static func current() -> AppleBridgeBootstrap {
        #if os(macOS)
        return AppleBridgeBootstrap(
            container: KmpContainer(driver: MacosDriverKt.createMacosDriver()),
            platformName: "macOS",
            databasePath: MacosDriverKt.getMacosAppDataPath(fileName: "mi_gestor_kmp.db")
        )
        #else
        return AppleBridgeBootstrap(
            container: KmpContainer(driver: IosDriverKt.createIosDriver()),
            platformName: "iOS",
            databasePath: IosDriverKt.getIosAppDataPath(fileName: "mi_gestor_kmp.db")
        )
        #endif
    }

    var connectedStatusText: String {
        "KMP conectado en \(platformName)"
    }
}
