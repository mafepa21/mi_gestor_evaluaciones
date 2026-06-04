# P3 Motion and Transitions

## Scope

Files inspected through targeted search: `kmp/iosApp/MacApp/*.swift`, `NotebookMacLayout.swift`, `PlannerMacLayout.swift` where present.

## Findings

1. Motion is sparse. The root banner uses `uiFeatureFlags.bannerTransition` and `uiFeatureFlags.interactionAnimation` (`MacRootView.swift:96-104`), but major state changes have little or no transition.
2. Attendance row swipe affordances use explicit `easeOut(duration: 0.16)` for reveal/close (`MacAttendanceDayRow.swift:183-211`). This is a good microinteraction pattern and should be normalized rather than replaced.
3. Module state changes usually update synchronously via `.appOnChange` and tasks. Examples: dashboard loading/ready/error (`MacDashboardView.swift:43-56`), attendance mode/selection changes (`MacAttendanceView.swift:198-210`), rubric filter/selection changes (`MacRubricsView.swift:135-175`). These changes can visually “snap”.
4. Sheets and confirmation dialogs rely on system modal transitions. That is acceptable for macOS, but large sheets like rubric builder and bulk evaluation feel like full workspace swaps (`MacRubricsView.swift:196-249`).
5. Inspector visibility uses native `.inspector`, which is appropriate (`MacRootView.swift:89-93`). The missing piece is not custom animation but continuity of selected context when the inspector appears/disappears.

## Recommended Improvements

- Define one shared macOS motion token, likely `Animation.spring(response: 0.35, dampingFraction: 0.75)` or the existing feature-flag animation, and apply it only to low-risk state: banners, filter chips, operation pills, inspector context changes.
- Add `.transition(.opacity.combined(with: .scale(scale: 0.98)))` to small state badges and empty/loading overlays, not to large tables.
- Animate dashboard load-state swaps with a small opacity transition so “loading -> today content” reads as completion, not a full redraw.
- For Attendance/Rubrics segmented mode and filter changes, animate only summary chips and detail panels. Do not animate table rows wholesale; that would hurt perceived speed.
- Respect reduced motion through existing `uiFeatureFlags` where available before adding new transitions.

## Risk

Avoid decorative motion. macOS should feel fast and stable; the goal is orientation, not spectacle.
