# P1 Project/Build Integration

Objective: make the macOS build bundle the Command Center helper and avoid stale KMP framework script outputs.

Files:
- `kmp/iosApp/project.yml`
- `kmp/iosApp/MiGestorKMPiOS.xcodeproj/project.pbxproj`

Do:
- Mark KMP framework scripts as always out of date in XcodeGen.
- Add a macOS post-build script that embeds `MiGestorCommandCenter.app` into the built app resources.
- Regenerate the Xcode project from `project.yml`.

Do not:
- Change KMP sources, SQLDelight schema, or helper implementation.

Verification:
- macOS Xcode build must run the framework/helper scripts.
- Built app must contain an executable helper at the resource path used by `MacCommandCenterCoordinator`.
