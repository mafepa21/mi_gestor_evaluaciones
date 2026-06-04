# Orchestration: Find bugs in iOS and macOS app

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules

## Packet Prompts

## Completion Audit
# Orchestration

## Sequence
1. Create workflow artifacts and freeze production code as read-only for this audit.
2. Run `P0-discovery` locally to identify targets, commands, and high-risk changed areas.
3. Delegate `P1`, `P2`, and `P3` to parallel explorer subagents with read-only scopes.
4. Continue local discovery and safe verification while subagents run.
5. Collect packet results into `results/`.
6. Integrate findings, resolve conflicts by source inspection, and write `final-report.md`.
7. Verify workflow artifact completeness.

## Branching Rules
- If a finding needs production edits, record it only; do not patch without explicit approval.
- If a build command fails because dependencies or network are missing, record the blocker and continue with static verification.
- If a subagent reports a vague issue without file/line evidence, downgrade to unaccepted risk until locally confirmed.

## Packet Prompts

### P1 iOS SwiftUI Audit
Read-only audit of `kmp/iosApp/App` and `kmp/iosApp/AppleShared`. Focus on concrete bugs: compile errors, invalid state assumptions, broken actions, force unwraps, platform API misuse, task/threading issues visible in SwiftUI code, navigation dead ends, and regressions introduced by the current dirty tree. Do not edit files. Return prioritized findings with file/line references, reproduction rationale, and any recommended narrow fix.

### P2 macOS SwiftUI Audit
Read-only audit of `kmp/iosApp/MacApp` plus shared Apple files when directly referenced by Mac code. Focus on concrete macOS bugs: missing target membership, menu/window/root wiring problems, platform availability misuse, broken settings/actions, compile errors, and feature registry inconsistencies. Do not edit files. Return prioritized findings with file/line references, reproduction rationale, and recommended narrow fix.

### P3 Build/Config Audit
Read-only audit of `kmp/iosApp/project.yml`, generated Xcode project references, target source membership, scripts, and known build commands. Focus on bugs that would prevent iOS/macOS build or cause files to be excluded from targets. Do not edit files. Return prioritized findings with exact references and verification commands.
