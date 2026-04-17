import SwiftUI

@MainActor
final class MacAppSessionController: ObservableObject {
    enum BootstrapState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published var selectedFeature: MacFeatureDescriptor.Feature = .dashboard
    @Published var bootstrapState: BootstrapState = .idle
    @Published var inspectorVisible = true

    let bridge = KmpBridge()
    let bootstrap = AppleBridgeBootstrap.current()

    func start() {
        guard bootstrapState == .idle else { return }
        bootstrapState = .loading
        Task {
            await bridge.bootstrap()
            bridge.onAppDidBecomeActive()
            if bridge.status.lowercased().hasPrefix("error") {
                bootstrapState = .failed(bridge.status)
            } else {
                bootstrapState = .ready
            }
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            bridge.onAppDidBecomeActive()
        case .background:
            bridge.onAppDidEnterBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
