#if os(iOS)
import BackgroundTasks
import Foundation

/// Sync LAN con la app del iPad cerrada.
///
/// iOS no deja una conexión abierta en segundo plano, pero sí despierta la app de vez
/// en cuando (`BGAppRefreshTask`) para un envío y una descarga cortos. iOS decide
/// cuándo: pueden pasar minutos u horas, según el uso y la batería. No sustituye al
/// envío al irse a segundo plano ni a ponerse al día al volver; solo acorta el tiempo
/// en que el iPad y el Mac están separados.
enum LanSyncBackgroundRefresh {
    /// También en `BGTaskSchedulerPermittedIdentifiers` (`Config/iOS-Info.plist`).
    static let identifier = "com.migestor.ios.sync-refresh"
    static let minimumInterval: TimeInterval = 15 * 60

    /// El bridge vive en la vista raíz. Si iOS arranca la app en frío solo para esta
    /// tarea, aún no existe y no se abre otra base por detrás: se espera al siguiente
    /// despertar.
    @MainActor static weak var bridge: KmpBridge?

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule()
        guard let bridge else { return }
        await bridge.runBackgroundRefreshSync()
    }
}
#endif
