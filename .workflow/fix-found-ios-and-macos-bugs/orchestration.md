# Orchestration: Fix found iOS and macOS bugs

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules
- If `project.yml` changes, regenerate the Xcode project and inspect the generated diff before building.
- If the generated project diff is broader than the XcodeGen source changes explain, stop and report the risk instead of hand-editing blindly.
- If build verification fails from a pre-existing unrelated compile error, report the blocker with the first actionable error.

## Packet Prompts
- P1: Patch `kmp/iosApp/project.yml` so KMP framework scripts always run despite shared output paths, build the Command Center helper, and embed the helper app into the macOS bundle resources.
- P2: Patch `MiGestorKMPMacApp.swift` and `MacRootView.swift` only. Reuse existing settings dependencies and restore `columnVisibility` from `storedColumnVisibility`.
- P3: Run workflow verification, regenerate the Xcode project as needed, run focused build checks, and summarize diff scope.

## Completion Audit
- All accepted findings have an implementation decision.
- Verification evidence is recorded.
- Protected files remain untouched by this run.
