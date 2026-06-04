# macOS UI improvement audit

## Goal
Find concrete improvement opportunities in the macOS version of Mi Gestor Evaluaciones, focused on design elements, animations, and transitions.

## Success Criteria
- Identify recommendations grounded in current SwiftUI files.
- Keep the run read-only and avoid protected app logic.
- Separate findings by design elements, animations, and transitions.
- Prioritize changes that preserve daily teacher workflows and reduce visual noise.
- Produce an integrated report with actionable, file-scoped recommendations.

## Current Context
- macOS-specific UI lives in `kmp/iosApp/MacApp/`.
- Shared Apple UI lives in `kmp/iosApp/AppleShared/`.
- Some notebook/mac toolbar integration lives in `kmp/iosApp/App/`.
- AGENTS.md requires small, safe, reviewable changes and protects KMP, SQLDelight, `KmpBridge.swift`, `EvaluationDesign.swift`, and `desktopApp/`.

## Constraints
- No code changes in this run unless the user explicitly asks for implementation.
- Prefer one future implementation slice at a time.
- Respect Jobs-style simplicity: one obvious primary task, generous whitespace, 8pt grid, clear hierarchy, minimal visual noise.

## Risks
- Visual recommendations can drift into broad redesign; keep each proposal file-scoped.
- Motion can harm perceived speed; prefer subtle spring or opacity transitions only where state changes need orientation.

## Approval Required
None for this read-only audit. Approval is required before any later code edits.

## Work Packets
1. `P1-shell-design`: macOS shell, sidebar, root layout, and dashboard hierarchy.
2. `P2-component-design`: reusable macOS components, cards, buttons, lists, inspector surfaces.
3. `P3-motion-transitions`: existing animations, transitions, state changes, and missing motion cues.
4. `P4-integration-priorities`: synthesize packet results into a practical roadmap.

## Integration Policy
Accept recommendations that are grounded in current files, preserve KMP logic boundaries, and can be implemented in small slices. Reject broad redesigns, business logic changes, or visual additions that increase daily teacher workload.

## Verification
- Static code inspection with file references.
- Workflow artifact completeness check.
- No build required because this is a read-only audit.

## Reusable Artifacts
Keep this workflow directory as a reusable template for future macOS UI audits if the final report proves useful.
