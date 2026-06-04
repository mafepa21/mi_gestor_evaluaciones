# Orchestration: apply macOS UI recommendations

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules
- If touching `MacRootView.swift` risks merging into unrelated existing changes, defer toolbar simplification.
- If compile verification is too broad or blocked by local project state, report it honestly and keep diff review as minimum evidence.
- If the control strip creates layout regressions in Attendance, revert only our new usage and keep reusable component if independently valid.

## Packet Prompts
### P1-motion-tokens
Ownership: `kmp/iosApp/MacApp/MacAppStyle.swift`.
Add restrained motion constants for small macOS UI state transitions.

### P2-control-strip
Ownership: `kmp/iosApp/MacApp/MacPremiumComponents.swift`.
Add a lighter reusable control-strip component and transitions for small status/loading overlays.

### P3-attendance-application
Ownership: `kmp/iosApp/MacApp/MacAttendanceView.swift`.
Use the lighter strip for Attendance controls without changing attendance logic.

### P4-verify-integrate
Ownership: workflow artifacts and verification commands.
Collect results, verify workflow, and attempt relevant compile/build checks.

## Completion Audit
- Production diff is limited to expected files.
- Packet results exist.
- Workflow verification passes.
- Final report names skipped/deferred recommendations.
