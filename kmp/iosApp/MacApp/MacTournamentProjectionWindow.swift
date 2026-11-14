import SwiftUI
import AppKit

/// Identificador de la ventana de proyección (se abre con `openWindow(id:value:)` y el id del torneo).
enum MacTournamentProjectionWindowID {
    static let value = "tournament-projection"
}

/// Ventana de proyección de un torneo. Se abre a mano desde el detalle del torneo («Proyectar»).
/// Carga el plan por su id, lo recarga cuando llegan resultados por la sync o se anotan en este
/// Mac, y pinta `SdaProjectionView` (sin nombres, fondo claro). Al abrirse se va al proyector si
/// hay segunda pantalla, entra en pantalla completa y mantiene el Mac despierto. Esc sale de la
/// pantalla completa y, ya en ventana, la cierra.
struct MacTournamentProjectionWindow: View {
    let tournamentId: String?
    @ObservedObject var session: MacAppSessionController
    @AppStorage("mac_reduce_motion") private var prefersReducedMotion = false

    private enum Phase {
        case loading
        case missing
        case ready(TournamentPlan)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        content
            .frame(minWidth: 640, minHeight: 360)
            .background(MacProjectionWindowConfigurator())
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
            .task(id: session.bootstrapState) {
                session.start()
                await load()
            }
            .reloadOnLanSync(.learningSituations) { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .tournamentPlanSaved)) { notification in
                guard notification.userInfo?["id"] as? String == tournamentId else { return }
                Task { await load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .ready(let plan):
            SdaProjectionView(plan: plan, forceReduceMotion: prefersReducedMotion)
        case .loading:
            message("Cargando el torneo…")
        case .missing:
            message("No se encuentra el torneo. Ciérrala y vuelve a proyectar desde el torneo.")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
    }

    private func load() async {
        guard let tournamentId, session.bootstrapState == .ready else { return }
        do {
            guard let record = try await session.bridge.tournament(id: tournamentId) else {
                phase = .missing
                return
            }
            let plan = try record.plan()
            // Solo se cambia si hay algo nuevo: así la rotación no se reinicia en balde.
            if case .ready(let current) = phase, current == plan { return }
            phase = .ready(plan)
        } catch {
            // Un fallo al recargar deja a la vista lo último bueno; si no hay nada, se avisa.
            if case .loading = phase { phase = .missing }
        }
    }
}

// MARK: - Ventana (AppKit)

/// Prepara la ventana: aspecto claro, proyector, pantalla completa, Esc y sin dormir.
private struct MacProjectionWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HostView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var keyMonitor: Any?
        private var closeObserver: NSObjectProtocol?
        private var activity: NSObjectProtocol?

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            window.appearance = NSAppearance(named: .aqua)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .white

            // El Mac no se duerme mientras se proyecta.
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
                reason: "Proyectando un torneo"
            )

            // Esc: sale de la pantalla completa; ya en ventana, la cierra.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let window = self?.window, window.isKeyWindow else { return event }
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                } else {
                    window.close()
                }
                return nil
            }

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.tearDown() }
            }

            moveToProjector(window)
            // Un instante después, para que la ventana ya esté en su pantalla antes de ampliarse.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
                guard let window, !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }

        /// Con segunda pantalla o proyector, la ventana se va allí; si no, se queda en la principal.
        private func moveToProjector(_ window: NSWindow) {
            let home = NSApp.windows.first { $0 !== window && $0.isVisible && !($0 is NSPanel) }?.screen
                ?? NSScreen.screens.first
            guard let projector = NSScreen.screens.first(where: { $0 != home }) else { return }
            window.setFrame(projector.frame, display: true)
        }

        func tearDown() {
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }
        }

        deinit {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        }
    }
}
