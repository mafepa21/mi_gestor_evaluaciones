import Foundation
import MiGestorKit
import Combine

@MainActor
protocol AppleSharedBridge: ObservableObject {
    var status: String { get }
    var statsText: String { get }
    var classes: [SchoolClass] { get }
    var syncStatusMessage: String { get }
    var syncPendingChanges: Int { get }
    var syncLastRunAt: Date? { get }
    var pairedSyncHost: String? { get }
    var discoveredSyncHosts: [String] { get }
    func bootstrap() async
    func onAppDidBecomeActive()
    func onAppDidEnterBackground()
}

extension KmpBridge: AppleSharedBridge {}

@MainActor
final class AppleLifecycleBridgeObserver {
    private weak var bridge: (any AppleSharedBridge)?
    private var cancellables: Set<AnyCancellable> = []

    init(bridge: any AppleSharedBridge) {
        self.bridge = bridge

        NotificationCenter.default.publisher(for: .appleAppDidBecomeActive)
            .sink { [weak self] _ in
                self?.bridge?.onAppDidBecomeActive()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appleAppDidEnterBackground)
            .sink { [weak self] _ in
                self?.bridge?.onAppDidEnterBackground()
            }
            .store(in: &cancellables)
    }
}
