# Final Report: macOS UI improvement audit

## Outcome
Supervised read-only workflow completed. The macOS UI is structurally sound, but the best improvement opportunities are hierarchy, chrome reduction, and restrained motion for orientation.

## Accepted Results
1. Keep the current macOS foundation: `NavigationSplitView`, native `.inspector`, `HSplitView`, module headers, and toolbar ownership are directionally correct.
2. Reduce visual chrome density before adding new visuals. The most valuable design improvement is making cards/filter bars/status panels quieter so the primary task is obvious.
3. Add motion only where it improves orientation: module swaps, dashboard load-state completion, operation-state pills, transient banners, inspector context changes, and small filter/status updates.
4. Preserve the Attendance swipe microinteraction; it is a good example of focused motion and should inform other microinteractions.

## Rejected Results
- Broad redesign of the macOS shell.
- Business logic, KMP, SQLDelight, `KmpBridge.swift`, `EvaluationDesign.swift`, or desktop Compose changes.
- Animating large data grids or table reloads wholesale.
- New decorative visual systems, gradients, or non-native chrome.

## Conflicts Resolved
No hard conflicts found. The main tradeoff is density versus clarity: the app is already functionally dense, so polish should remove chrome and improve hierarchy before adding controls.

## Priority Recommendations

### P1: Quiet the Mac Control Surfaces

Files likely involved: `kmp/iosApp/MacApp/MacPremiumComponents.swift`, one module view.

Create a lighter filter/control strip variant for dense macOS screens. Use it first in Attendance or Rubrics. This reduces card-on-card noise without changing workflows.

### P2: Dashboard Focus Pass

Files likely involved: `kmp/iosApp/MacApp/MacDashboardView.swift`.

Make “Ahora” the dominant visual focus on wide displays, reduce passive right-column card emphasis, and add a subtle loading-to-content opacity transition. This improves the first screen teachers see daily.

### P3: Notebook Toolbar Simplification

Files likely involved: `kmp/iosApp/MacApp/MacRootView.swift`, possibly `kmp/iosApp/App/NotebookMacToolbarBinding.swift`.

Group notebook toolbar actions by task and move less frequent actions into `Más`. Keep class, view mode, add column, search, and inspector highly discoverable.

### P4: Shared Motion Token

Files likely involved: `kmp/iosApp/MacApp/MacAppStyle.swift`, `MacPremiumComponents.swift`, selected module.

Use one restrained animation token for operation states, badges, and small transitions. Prefer existing `uiFeatureFlags` where available and respect reduced motion.

### P5: Inspector Context Continuity

Files likely involved: `MacStudentsView.swift`, `MacAttendanceView.swift`, `MacPhysicalTestsInspectorView.swift`.

When selection changes, animate only the inspector header/badges or use content transitions so the user sees context changed without making the main table unstable.

## Verification Evidence
- Static inspection completed for macOS shell, dashboard, components, students, attendance, rubrics, notebook mac layout, and targeted motion search.
- No build run: no production code was changed.

## Remaining Risks
- Without screenshots/runtime inspection, recommendations are grounded in code structure rather than visual capture.
- Some UI states depend on real data; final implementation should be verified with a seeded database or existing local app state.

## Reusable Follow-up
Use this workflow directory as the template for future macOS UI audits: plan first, inspect shell/components/motion separately, then integrate into small implementation slices.
