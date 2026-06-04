# Integration Results

## Accepted

### P1: Command Center helper is not bundled in the macOS app
- Evidence:
  - `MacCommandCenterCoordinator.resolveHelperExecutableURL()` first checks `Bundle.main.resourceURL` for `MiGestorCommandCenter.app/Contents/MacOS/MiGestorCommandCenter`, then falls back to a source-tree path derived from `#filePath`: `kmp/iosApp/MacApp/MacCommandCenterCoordinator.swift:445`.
  - Local verification after successful macOS build: `find /private/tmp/migestor_mac_audit_derived2/Build/Products/Debug/MiGestorKMPMac.app -name 'MiGestorCommandCenter*' -print` returned no output.
- Impact: packaged or relocated macOS builds can fail Sync LAN / `Conectar iPad` because the helper exists only in the development checkout.
- Narrow fix: add a macOS build/copy phase that embeds `../commandCenterHelper/build/compose/binaries/main/app/MiGestorCommandCenter.app` into `MiGestorKMPMac.app/Contents/Resources`.

### P2: Standard macOS Settings scene is empty
- Evidence: `kmp/iosApp/MacApp/MiGestorKMPMacApp.swift:78` declares `Settings { EmptyView() }`.
- Impact: `MiGestorKMPMac > Settings...` opens a blank settings window even though the sidebar settings module exists.
- Narrow fix: remove the `Settings` scene if unsupported, or render real settings content with the required session dependencies.

### P3: macOS sidebar visibility persistence is ignored on launch
- Evidence:
  - `storedColumnVisibility` is declared and updated at `kmp/iosApp/MacApp/MacRootView.swift:17` and `kmp/iosApp/MacApp/MacRootView.swift:63`.
  - `onAppear` resets `columnVisibility = .all` at `kmp/iosApp/MacApp/MacRootView.swift:54`.
- Impact: users who hide the sidebar lose that preference after reopening the window/app.
- Narrow fix: initialize `columnVisibility` from the stored value rather than always forcing `.all`.

### P4: KMP framework output path can reuse stale variants
- Evidence:
  - iOS prebuild output is a single stable path in `kmp/iosApp/project.yml:72`: `$(SRCROOT)/Frameworks/ios/MiGestorKit.framework/MiGestorKit`.
  - `build_apple_framework.sh` selects platform/configuration from build environment but copies into shared `Frameworks/ios` or `Frameworks/macos` destinations.
- Impact: switching simulator/device or Debug/Release can reuse an already-present framework path and produce stale or wrong-platform framework embeds.
- Narrow fix: make the script phase unambiguously rerun for platform/config changes, or use platform/config-specific output paths.

## Rejected / Downgraded

- No confirmed iOS SwiftUI bug from static audit or build. iOS simulator Debug build succeeded locally.
- `pbxproj` search-path drift from `project.yml` is tracked as risk, not a confirmed bug; current Debug iOS/macOS builds both succeeded.

## Verification

- `xcodebuild -list -project kmp/iosApp/MiGestorKMPiOS.xcodeproj`: passed.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -sdk iphonesimulator -derivedDataPath /private/tmp/migestor_ios_audit_derived2 CODE_SIGNING_ALLOWED=NO build`: passed.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac -configuration Debug -sdk macosx -derivedDataPath /private/tmp/migestor_mac_audit_derived2 CODE_SIGNING_ALLOWED=NO build`: passed.
