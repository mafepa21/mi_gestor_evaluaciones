# apply macOS UI recommendations

## Goal
Apply the first safe slice of the macOS UI recommendations: lighter control surfaces and restrained motion for small state changes.

## Success Criteria
- Add reusable macOS UI polish without changing business logic.
- Apply the new lighter control surface to one real macOS module.
- Keep edits within 1-3 production files.
- Avoid protected files: `KmpBridge.swift`, KMP shared/data, SQLDelight, `EvaluationDesign.swift`, and `desktopApp/`.
- Verify workflow artifacts and compile the touched Swift surface if practical.

## Current Context
- Previous audit recommends: quiet control surfaces, shared motion token, dashboard focus pass, notebook toolbar simplification, inspector continuity.
- Current worktree already has unrelated/user changes in `MacAttendanceView.swift` and `MacRootView.swift`.
- This run will not revert or overwrite unrelated changes.

## Constraints
- Use `swiftui-polish` rules: 8pt grid, native SwiftUI, minimal diff, no business logic changes.
- Maximum production edit scope for this slice: `MacAppStyle.swift`, `MacPremiumComponents.swift`, `MacAttendanceView.swift`.

## Risks
- `MacAttendanceView.swift` is already modified; edits must avoid the existing injury-status changes.
- UI-only compile verification may require full Xcode/KMP setup.

## Approval Required
None. This is a local, non-destructive code edit. No destructive, external, or publishing action is planned.

## Work Packets
1. `P1-motion-tokens`: add restrained macOS animation/transition tokens.
2. `P2-control-strip`: add lighter reusable macOS control strip and small state transitions.
3. `P3-attendance-application`: apply lighter strip to Attendance controls.
4. `P4-verify-integrate`: verify workflow and compile/build where feasible.

## Integration Policy
Accept only changes that reduce visual noise, improve orientation, and preserve existing workflows. Defer dashboard focus and notebook toolbar simplification to later slices.

## Verification
- Static diff review.
- Workflow verification script.
- Swift/Xcode build check if available and scoped enough.

## Reusable Artifacts
Keep packet/result notes in this workflow for future macOS UI implementation slices.
