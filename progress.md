# Progress

- Implemented duplication of notebook structure in shared data code, including evaluations, rubric links, and column evaluation mappings.
- Added iOS notebook toolbar action and sheet to duplicate a course structure into another course.
- Added copy/paste evaluation actions inside the iOS bulk rubric evaluation view.
- Fixed several Swift interop mismatches in `KmpBridge.swift` during validation.
- Verified successful iOS simulator build after the changes.
- Hardened notebook work-group creation so duplicate names in the same tab are auto-disambiguated instead of replacing the previous group.
- Added shared test coverage for unique work-group naming in the same tab and verified the desktop Kotlin compilation.
- Improved notebook column interactions across desktop and iOS: drag-and-drop reordering, corner resize handles, long-press color menus, and synchronized header/cell widths.
- Verified `:shared:compileKotlinMetadata` and `:desktopApp:compileKotlin` after the notebook UI changes.
- Integrated localized database analysis and aggregation on Kotlin side (KMP) to deliver compressed academic trends (`AITrendsSnapshot`) to the Apple Intelligence localized prompt runner.
- Exposed trends data from KMP to Swift in `KmpBridge.swift`, updated contextual AI builders and generated report structures.
- Integrated visual AI trends inspector cards in `NotebookStudentInspector.swift`, LOMLOE Audit Widget in `DashboardView.swift`, and parameters detail in `RubricsReportsWorkspaceViews.swift`.
- Verified successful iOS Simulator and macOS compilation via `verify_apple_builds.sh` after fixing usecase long/int comparison and styling type mismatch.
