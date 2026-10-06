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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return AppleBridgeBootstrap(
                container: KmpContainer(driver: MacosDriverKt.createMacosTestDriver()),
                platformName: "macOS Tests",
                databasePath: MacosDriverKt.getMacosTestDatabasePath()
            )
        }
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

    /// Ruta de la base de datos sin abrirla. `current()` abre un driver completo
    /// (validación, migraciones de rescate, contenedor KMP) y el driver se queda
    /// abierto: usarlo solo para leer la ruta abría la base hasta 4 veces al
    /// arrancar y las conexiones extra competían por el fichero.
    static var databasePath: String {
        #if os(macOS)
        if isRunningTests {
            return MacosDriverKt.getMacosTestDatabasePath()
        }
        return MacosDriverKt.getMacosDatabasePath()
        #else
        return IosDriverKt.getIosDatabasePath()
        #endif
    }

    static var platformName: String {
        #if os(macOS)
        return isRunningTests ? "macOS Tests" : "macOS"
        #else
        return "iOS"
        #endif
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var connectedStatusText: String {
        "KMP conectado en \(platformName)"
    }
}
