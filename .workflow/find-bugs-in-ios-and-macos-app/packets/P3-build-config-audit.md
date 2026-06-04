# P3 Build Config Audit

Objective: read-only Apple project/build configuration audit.

Scope: `kmp/iosApp/project.yml`, generated Xcode project, Apple build scripts.

Accepted findings:
- KMP framework output paths are shared across platform/config variants and can reuse stale framework outputs.

Downgraded:
- Search-path drift between `project.yml` and `project.pbxproj` is a maintenance risk, not a confirmed current build failure.

Verification:
- iOS simulator Debug build passed.
- macOS Debug build passed.
