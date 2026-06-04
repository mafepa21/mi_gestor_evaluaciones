# P2 macOS SwiftUI Audit

Objective: read-only macOS SwiftUI/product bug audit.

Scope: `kmp/iosApp/MacApp` and Apple shared/source files used by the macOS target.

Accepted findings:
- Command Center helper is built but not bundled in `MiGestorKMPMac.app`.
- Standard macOS `Settings` scene is `EmptyView`.
- Sidebar visibility persistence is overwritten on launch.

Verification:
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac -configuration Debug -sdk macosx -derivedDataPath /private/tmp/migestor_mac_audit_derived2 CODE_SIGNING_ALLOWED=NO build`
- `find /private/tmp/migestor_mac_audit_derived2/Build/Products/Debug/MiGestorKMPMac.app -name 'MiGestorCommandCenter*' -print`
