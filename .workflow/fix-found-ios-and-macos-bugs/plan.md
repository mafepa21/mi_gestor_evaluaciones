# Fix found iOS and macOS bugs

## Goal
Apply the accepted fixes from the previous iOS/macOS bug audit without broad refactors.

## Success Criteria
- The macOS Command Center helper is bundled inside the built macOS app resources where `MacCommandCenterCoordinator` already looks for it.
- The native macOS Settings scene no longer opens a blank window and reuses the existing `MacSettingsView`.
- macOS sidebar visibility restores from `SceneStorage` on launch instead of being overwritten to `.all`.
- KMP framework run-script phases are not skipped because of stale shared framework output paths.
- Workflow artifacts record scope, integration, and verification.

## Current Context
- Accepted findings came from `.workflow/find-bugs-in-ios-and-macos-app/final-report.md`.
- The working tree already contains many unrelated user changes; this run must not revert or normalize them.
- Project rules prefer small iOS/macOS SwiftUI changes and protect KMP, SQLDelight, `KmpBridge.swift`, `EvaluationDesign.swift`, and `desktopApp/`.

## Constraints
- Keep edits to macOS app entry/root files and XcodeGen project configuration.
- Do not touch business logic, persistence schema, or the Swift-KMP bridge.
- Use existing macOS settings and command center types.

## Risks
- Regenerating `MiGestorKMPiOS.xcodeproj` may include unrelated generated drift because the project file is already dirty.
- Embedding a nested helper app affects macOS signing/package behavior and needs build verification.

## Approval Required
No external, destructive, credential, production, or force-push action is planned. Escalation is only needed if local build tooling is blocked by sandboxing.

## Work Packets
- P1 Project/build integration: update XcodeGen scripts for stale framework phases and helper embedding.
- P2 macOS SwiftUI fixes: connect Settings scene and restore sidebar visibility.
- P3 Verification: regenerate project if needed, inspect diffs, and build the macOS target.

## Integration Policy
Accept only changes that directly satisfy an accepted finding. Leave unrelated dirty files untouched.

## Verification
- Verify workflow artifact completeness.
- Inspect focused diffs for touched files.
- Regenerate Xcode project from `project.yml` if `project.yml` changes.
- Build the macOS target enough to prove the helper is embedded and Swift compiles.

## Reusable Artifacts
This run directory documents the fix recipe for future audit-remediation passes.
