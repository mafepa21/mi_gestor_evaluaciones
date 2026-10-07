import SwiftUI
import MiGestorKit
#if canImport(VisionKit)
import VisionKit
#endif

// MARK: - Main Container
struct ContentView: View {
    @Environment(\.kmpBridgeReference) private var bridgeReference
    private var bridge: KmpBridge { bridgeReference! }
    @StateObject private var shellStore = ShellBridgeStore()
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    
    var body: some View {
        AppWorkspaceShell()
            .environmentObject(shellStore)
            .onAppear { shellStore.bind(to: bridge) }
            .tint(.accentColor)
            .appFullScreenCover(isPresented: rubricEvaluationPresentation) {
                RubricEvaluationView()
                    .environmentObject(bridge)
                    #if os(macOS)
                    .frame(minWidth: 1180, minHeight: 700)
                    #endif
            }
            .animation(
                uiFeatureFlags.reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82),
                value: shellStore.isRubricEvaluationPresented
            )
    }

    private var rubricEvaluationPresentation: Binding<Bool> {
        Binding(
            get: {
                shellStore.isRubricEvaluationPresented
            },
            set: { isPresented in
                if !isPresented {
                    bridge.closeRubricEvaluation()
                }
            }
        )
    }
}
