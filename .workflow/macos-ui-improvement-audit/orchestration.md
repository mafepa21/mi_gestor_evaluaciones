# Orchestration: macOS UI improvement audit

## Execution Rules

- Keep the original objective intact.
- Ask for approval before risky, expensive, external, or destructive actions.
- Keep immediate blocking work local.
- Delegate only bounded, disjoint, materially useful packets.
- Integrate packet results before final verification.

## Branching Rules
- If a finding requires KMP, SQLDelight, `KmpBridge.swift`, `EvaluationDesign.swift`, or `desktopApp/`, mark it as out of scope unless the user explicitly approves.
- If a recommendation touches more than three files, split it into a future phased implementation.
- If existing code already implements the pattern, record it as a consistency target rather than a new feature.

## Packet Prompts
### P1-shell-design
Objective: inspect the macOS root, navigation shell, and dashboard for hierarchy, density, focus, and platform fit.
Sources: `MacRootView.swift`, `MacDashboardView.swift`, `MacAppStyle.swift`, `MacFeatureRegistry.swift`.
Output: `results/P1-shell-design.md`.

### P2-component-design
Objective: inspect reusable macOS components and module surfaces for repeated visual patterns, cards, lists, inspectors, and toolbars.
Sources: `MacPremiumComponents.swift`, `MacStudentsView.swift`, `MacAttendanceView.swift`, `MacRubricsView.swift`, `MacPhysicalTestsView.swift`, `MacBackupInspectorView.swift`.
Output: `results/P2-component-design.md`.

### P3-motion-transitions
Objective: inspect animations/transitions and identify where state changes need clearer, calmer macOS motion.
Sources: `kmp/iosApp/MacApp/*.swift`, `NotebookMacLayout.swift`, `PlannerMacLayout.swift`.
Output: `results/P3-motion-transitions.md`.

### P4-integration-priorities
Objective: integrate the packet results into prioritized recommendations and future implementation slices.
Sources: all packet outputs.
Output: `final-report.md`.

## Completion Audit
- All packet result files exist.
- Final report contains accepted, rejected/out-of-scope, risks, and verification.
- Workflow verification script passes.
