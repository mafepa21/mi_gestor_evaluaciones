# P2 macOS SwiftUI Fixes

Objective: fix the blank macOS Settings scene and restore persisted sidebar visibility.

Files:
- `kmp/iosApp/MacApp/MiGestorKMPMacApp.swift`
- `kmp/iosApp/MacApp/MacRootView.swift`

Do:
- Reuse the existing `MacSettingsView` from the native Settings scene.
- Restore `NavigationSplitViewVisibility` from `SceneStorage` on appearance.

Do not:
- Redesign settings.
- Change KMP bridge, persistence, or business logic.

Verification:
- Swift build must compile the new settings scene wrapper.
- The sidebar initialization must no longer hard-code `.all`.
