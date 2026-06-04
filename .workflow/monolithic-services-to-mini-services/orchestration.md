# Orchestration: Monolithic services to mini services

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules
- If KMP/data candidates require repository or SQLDelight changes, treat them as audit-only unless the user approves a broader backend refactor.
- If a Swift service has clear internal clusters and no public call-site churn, implement that split first.
- If all candidates are high-risk, stop after the audit and propose a staged plan.

## Packet Prompts
- A: Audit `kmp/data/src/commonMain/kotlin/com/migestor/data/service`, `kmp/data/src/commonMain/kotlin/com/migestor/data/di`, and service contracts for monolithic service responsibilities. Output candidates, risks, and recommended split boundaries. Read-only.
- B: Audit Swift service files under `kmp/iosApp/App` and `kmp/iosApp/AppleShared`, especially Apple Foundation and backup/report services. Output candidates, call-site risks, and one best low-risk extraction target. Read-only.
- C: Audit verification options for likely touched Swift/KMP service files. Output exact commands already present/credible in repo context and what each validates. Read-only.

## Completion Audit
- Workflow artifacts populated.
- Packet outputs integrated.
- Implementation scoped and behavior-preserving.
- Relevant checks attempted.
