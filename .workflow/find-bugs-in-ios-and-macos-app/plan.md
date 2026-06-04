# Find bugs in iOS and macOS app

## Goal
Find concrete bugs and high-risk regressions in the current iOS and macOS SwiftUI app state, without changing production code during the audit.

## Success Criteria
- Produce isolated iOS, macOS, and build/config audit findings.
- Prioritize findings by severity with file/line references and reproducible rationale.
- Distinguish confirmed bugs from risks, missing verification, and likely user-work-in-progress.
- Run safe, relevant verification where possible.
- Save an integrated final report under this workflow directory.

## Current Context
- Repository: `/Users/mariofernandez/Projects/mi_gestor_evaluaciones`.
- App: KMP + SwiftUI educational management app.
- Target audit scope: `kmp/iosApp/App`, `kmp/iosApp/MacApp`, `kmp/iosApp/AppleShared`, and Apple project configuration.
- The working tree is already dirty with many user changes, including protected/sensitive areas. Production code edits are out of scope unless explicitly approved after findings are reviewed.

## Constraints
- Apply AGENTS.md: small, safe, reviewable changes; Apple-native premium UX; do not touch `KmpBridge.swift`, `EvaluationDesign.swift`, `kmp/shared`, `kmp/data`, or `desktopApp` unless explicitly requested.
- For this workflow, production code remains read-only. Only `.workflow/find-bugs-in-ios-and-macos-app/` may be edited.
- Use disjoint packets and integrate rather than dumping raw notes.

## Risks
- Dirty working tree may contain intentional in-progress changes.
- Build commands can be slow and may fail due to existing environment/config issues rather than app bugs.
- macOS target may require generated Xcode project state or signing/configuration not available from static inspection.

## Approval Required
- Required before production code edits, destructive git operations, deleting files, migrations, force pushes, or broad codemods.
- Not required for read-only inspection, workflow artifact writes, static searches, or non-destructive build/list commands.

## Work Packets
- `P0-discovery`: local repository orientation, dirty tree triage, build targets, available checks.
- `P1-ios-swiftui-audit`: subagent read-only audit of iOS SwiftUI views and shared components for crashes, state bugs, invalid assumptions, navigation/action regressions.
- `P2-macos-swiftui-audit`: subagent read-only audit of macOS SwiftUI views and Mac-specific registry/root/settings for crashes and feature wiring bugs.
- `P3-build-config-audit`: subagent read-only audit of XcodeGen/project files, target membership, missing source inclusion, platform conditionals, and obvious build blockers.
- `P4-verification`: local compilation/project checks where safe.
- `P5-integration`: accepted/rejected findings, severity, final report.

## Integration Policy
- Accept only findings with concrete source evidence or verification output.
- If packets disagree, inspect the referenced source directly before accepting.
- Do not classify design preferences as bugs unless they cause broken behavior, inaccessible interaction, or inconsistent platform behavior.
- Separate confirmed bugs from risks and follow-up suggestions.

## Verification
- Verify workflow artifact completeness with `verify_workflow.py`.
- Prefer Xcode/XcodeGen or approved Gradle commands only where commands are discoverable and non-destructive.
- If builds are skipped or fail for environmental reasons, report that explicitly.

## Reusable Artifacts
- Keep this run as a reusable audit template if it proves useful.
