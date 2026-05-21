import SwiftUI
import MiGestorKit
#if canImport(VisionKit)
import VisionKit
#endif

// MARK: - Main Container
struct ContentView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    
    var body: some View {
        AppWorkspaceShell()
            .tint(.accentColor)
            .sheet(isPresented: rubricEvaluationPresentation) {
                RubricEvaluationView()
                    .environmentObject(bridge)
                    #if os(macOS)
                    .frame(minWidth: 980, minHeight: 700)
                    #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(bridge.rubricEvaluationState.isLoading)
                    #endif
            }
            .animation(
                uiFeatureFlags.reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.82),
                value: bridge.rubricEvaluationState.isLoading ||
                    bridge.rubricEvaluationState.rubricDetail != nil ||
                    bridge.rubricEvaluationState.error != nil
            )
    }

    private var rubricEvaluationPresentation: Binding<Bool> {
        Binding(
            get: {
                bridge.rubricEvaluationState.isLoading ||
                    bridge.rubricEvaluationState.rubricDetail != nil ||
                    bridge.rubricEvaluationState.error != nil
            },
            set: { isPresented in
                if !isPresented {
                    bridge.closeRubricEvaluation()
                }
            }
        )
    }
}
