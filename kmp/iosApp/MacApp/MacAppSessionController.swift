import SwiftUI

@MainActor
final class MacAppSessionController: ObservableObject {
    private enum Defaults {
        static let selectedFeature = "mac.selectedFeature"
        static let inspectorVisible = "mac.inspectorVisible"
    }

    enum BootstrapState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published var selectedFeature: MacFeatureDescriptor.Feature {
        didSet {
            UserDefaults.standard.set(selectedFeature.rawValue, forKey: Defaults.selectedFeature)
        }
    }
    @Published var bootstrapState: BootstrapState = .idle
    @Published var inspectorVisible: Bool {
        didSet {
            UserDefaults.standard.set(inspectorVisible, forKey: Defaults.inspectorVisible)
        }
    }

    let bridge = KmpBridge()
    let bootstrap = AppleBridgeBootstrap.current()
    let commandCenter = MacCommandCenterCoordinator()
    let backupStore: MacBackupStore

    init() {
        backupStore = MacBackupStore(bridge: bridge)

        let defaults = UserDefaults.standard
        let storedFeature = defaults.string(forKey: Defaults.selectedFeature)
            .flatMap(MacFeatureDescriptor.Feature.init(rawValue:))
        selectedFeature = storedFeature ?? .dashboard

        if defaults.object(forKey: Defaults.inspectorVisible) == nil {
            inspectorVisible = true
        } else {
            inspectorVisible = defaults.bool(forKey: Defaults.inspectorVisible)
        }
    }

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

    func retry() {
        guard case .failed = bootstrapState else { return }
        bootstrapState = .idle
        start()
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
