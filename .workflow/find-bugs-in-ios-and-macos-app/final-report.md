# Final Report: Find Bugs in iOS and macOS App

## Outcome

Completed supervised read-only audit. No production code was edited.

Confirmed issues are macOS/product-config focused. Current Debug builds for iOS simulator and macOS both compile successfully.

## Accepted Findings

### 1. Command Center helper is built but not bundled in the macOS app

Evidence:
- `MacCommandCenterCoordinator.resolveHelperExecutableURL()` checks `Bundle.main.resourceURL` for `MiGestorCommandCenter.app/Contents/MacOS/MiGestorCommandCenter`, then falls back to a source-tree path: `kmp/iosApp/MacApp/MacCommandCenterCoordinator.swift:445`.
- Local verification after successful macOS build returned no helper in the app bundle:
  `find /private/tmp/migestor_mac_audit_derived2/Build/Products/Debug/MiGestorKMPMac.app -name 'MiGestorCommandCenter*' -print`
- The macOS build script builds the helper, but the app resources do not embed it.

Impact:
- Sync LAN / `Conectar iPad` can work on the dev machine but fail in packaged or relocated app builds.

Narrow fix:
- Add a macOS copy resources/build phase that embeds `../commandCenterHelper/build/compose/binaries/main/app/MiGestorCommandCenter.app` into `MiGestorKMPMac.app/Contents/Resources`.

### 2. Standard macOS Settings menu opens a blank window

Evidence:
- `kmp/iosApp/MacApp/MiGestorKMPMacApp.swift:78` declares `Settings { EmptyView() }`.
- The real settings experience exists elsewhere (`MacSettingsView`), so the sidebar route works but the standard app menu does not.

Impact:
- `MiGestorKMPMac > Settings...` presents an empty settings window.

Narrow fix:
- Remove the `Settings` scene if unsupported, or render real settings content with the needed session dependencies.

### 3. macOS sidebar visibility persistence is overwritten on launch

Evidence:
- `storedColumnVisibility` is declared at `kmp/iosApp/MacApp/MacRootView.swift:17`.
- It is updated from `columnVisibility` at `kmp/iosApp/MacApp/MacRootView.swift:63`.
- `onAppear` always resets `columnVisibility = .all` at `kmp/iosApp/MacApp/MacRootView.swift:54`.

Impact:
- A user who hides the sidebar loses that preference when reopening the window/app.

Narrow fix:
- Initialize `columnVisibility` from `storedColumnVisibility` instead of forcing `.all`.

### 4. KMP framework output paths can reuse stale variants

Evidence:
- iOS prebuild output is a single stable path in `kmp/iosApp/project.yml:72`.
- `build_apple_framework.sh` chooses platform/configuration from environment but copies into shared `Frameworks/ios` or `Frameworks/macos` destinations.

Impact:
- Switching simulator/device or Debug/Release can leave Xcode reusing a stale framework at the same output path.

Narrow fix:
- Make the script phase reliably rerun for platform/config changes, or use platform/config-specific output paths.

## Rejected Results

- No confirmed iOS SwiftUI bug. The iOS audit found no confirmed routing/state/platform misuse issue, and the local iOS simulator Debug build succeeded.
- Project search-path drift between `project.yml` and `project.pbxproj` is a maintenance risk, not a current compile breaker.

## Verification Evidence

- `xcodebuild -list -project kmp/iosApp/MiGestorKMPiOS.xcodeproj`: passed.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -sdk iphonesimulator -derivedDataPath /private/tmp/migestor_ios_audit_derived2 CODE_SIGNING_ALLOWED=NO build`: passed.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac -configuration Debug -sdk macosx -derivedDataPath /private/tmp/migestor_mac_audit_derived2 CODE_SIGNING_ALLOWED=NO build`: passed.
- `find /private/tmp/migestor_mac_audit_derived2/Build/Products/Debug/MiGestorKMPMac.app -name 'MiGestorCommandCenter*' -print`: returned no files.

## Remaining Risks

- No UI smoke test was run; findings are source/build based.
- Release, archive, and physical device builds were not run.
- The working tree had many pre-existing changes, including protected KMP/data files. This audit treated production code as read-only.

## Recommended Next Fix Order

1. Embed the Command Center helper into the macOS app bundle.
2. Fix or remove the blank `Settings` scene.
3. Restore sidebar visibility from `SceneStorage`.
4. Harden KMP framework script outputs for platform/config switches.
