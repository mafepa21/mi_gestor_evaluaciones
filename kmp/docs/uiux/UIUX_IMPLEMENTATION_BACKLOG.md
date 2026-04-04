# UI/UX Implementation Backlog (P0-P2)

## P0 - Clarity and Noise Reduction
- [x] Introduce `UiFeatureFlags` for incremental rollout (`newShell`, `notebookToolbarSimplified`, `accessibilitySurfaceFallback`).
- [x] Add semantic desktop shell contract (`AppShellScaffold`) with sidebar + toolbar + optional inspector.
- [x] Simplify notebook action density with progressive disclosure (visible primary actions + overflow menu).
- [x] Increase key touch/click targets to 44dp in shell and notebook toolbars.
- [x] Define cross-screen design tokens (`DesignTokens`) for spacing/radius/touch/elevation.
- [x] Limit visible actions to 3-5 in the remaining modules (Rubrics, Planning, Reports, Backups) via overflow menus.

## P1 - Apple-like Consistency and Accessibility
- [x] Add dark mode color scheme for desktop Material theme.
- [x] Add transparency fallback path for desktop glass surfaces.
- [x] Add iOS transparency fallback helpers and wire them in notebook/evaluation surfaces.
- [x] Add explicit a11y labels on notebook icon-only actions (desktop/iOS priority surfaces).
- [x] Add Reduce Motion behavior for shell/sidebar/planner transitions and iOS overlay animation.
- [x] Add cross-module search entry flow in shell toolbar (module + quick actions).

## P2 - Polish and Optimization
- [ ] Refine contextual inspector content by module.
- [ ] Tune inline edit vs overlay edit behavior for notebook cells by type.
- [ ] Add motion polish pass (state transitions only where interaction clarity improves).
- [ ] Ship final visual regression baseline snapshots for desktop + iOS.
