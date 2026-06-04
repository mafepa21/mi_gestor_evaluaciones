# Monolithic services to mini services

## Goal
Review service-like code for monolithic responsibilities and split one high-value, low-risk candidate into smaller mini services without changing business behavior.

## Success Criteria
- Identify monolithic service candidates with file paths and reasons.
- Select one scoped candidate suitable for a surgical refactor.
- Extract cohesive mini services while preserving public behavior and call sites where possible.
- Avoid protected files unless explicitly needed and justified.
- Run relevant compile or test checks, or report why they could not run.

## Current Context
- Repo: KMP + SwiftUI educational app.
- User explicitly requested a supervised multi-agent workflow.
- AGENTS.md favors small safe changes, protected KMP/shared/data files, and Apple UI work in SwiftUI files by default.
- Initial hotspot scan shows larger service files in Swift Apple code, especially `AppleFoundationContextualAIService.swift`, plus backup/report services.

## Constraints
- Default scope is 1 flow, 1-3 files, 1 deliverable.
- Do not touch `KmpBridge.swift`, `EvaluationDesign.swift`, `kmp/shared/domain`, SQLDelight schema, or `desktopApp` unless explicitly required.
- Prefer behavior-preserving extraction over feature changes.
- No destructive operations.

## Risks
- Service splitting can create dependency churn and subtle call-site regressions.
- AI/report/backup services may depend on OS availability gates and async behavior.
- KMP/data service refactors may affect multiple platforms.

## Approval Required
- No approval required for read-only audit or small local edits.
- Approval required before broad codemods, mass renames, SQLDelight migrations, or touching protected files.

## Work Packets
- Packet A: KMP/data service audit. Read-only; identify monoliths and low-risk split candidates.
- Packet B: Swift Apple service audit. Read-only; identify monoliths and best surgical extraction target.
- Packet C: Verification/risk audit. Read-only; propose compile/test commands and regression risks.
- Local integration: choose one candidate, implement bounded extraction, verify.

## Integration Policy
- Prefer candidates with clear internal helper clusters and few external call sites.
- Reject splits that require public API redesign or protected-file changes.
- Keep new mini services private/internal unless broader reuse is already present.

## Verification
- Run narrow Swift or Gradle checks matching touched files when available.
- Run workflow artifact verification.
- Summarize skipped checks honestly.

## Reusable Artifacts
- Keep `.workflow/monolithic-services-to-mini-services/` as the run artifact.
- Save final candidate list and split rationale in `final-report.md`.
