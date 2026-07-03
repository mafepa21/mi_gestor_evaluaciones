# Notebook Manual Verification

Run this checklist on iPad and macOS after changes to the notebook grid layout.

1. Add a normal column.
   - The new column appears in the scrollable area with the expected width.
   - The student column remains fixed while horizontal scrolling.

2. Add a column while creating a category.
   - The category band appears above exactly the columns it owns.
   - The band title toggles the category open or closed.

3. Collapse a category.
   - The category becomes a wide folder-style chip with the column count.
   - Row cells show the collapsed progress without changing row height.

4. Scroll horizontally.
   - The student column remains fixed.
   - The Media column remains visible as the right fixed column.
   - Category bands stay aligned with their columns.

5. Scroll vertically.
   - Fixed student rows, scrollable cells, and Media rows stay aligned.
   - There is no gap between the header and the first row.
   - Fast scrolling up and down does not cause stuttering or visual jumps.
   - Tested with a large group (30-40 students) to ensure smooth performance.

6. Check Media.
   - Media is visible with all column configurations.
   - Opening the Media header still opens average configuration.

7. Change Tabs.
   - The fixed student column width persists uniquely for each tab.
   - Navigating between tabs applies the correct saved column sizes.

8. Debug Grid Alignment (Temporary).
   - Activate `isDebugGridModeEnabled` in code.
   - Verify that all rows and cells have exactly matching heights and boundaries.
   - Verify there is no alignment deviation > 1px.

9. Row Virtualization Check (Temporary, Phase 0 baseline).
   - Set `NotebookRowVirtualizationDebug.enabled = true` in `NotebookGridContainer.swift`, run on a real iPad and on Mac.
   - Open a class with 30+ students and 20+ columns across 2-3 categories.
   - Watch the Xcode console for lines like `NotebookPerf virtualization pane=scroll materialized=X totalRows=Y`.
   - Scroll to the bottom and back to the top slowly, then do a fast flick.
   - Expected if virtualization works: `materialized` stays roughly bounded to the number of rows that fit on screen plus a small buffer (e.g. ~10-15 for a typical viewport), regardless of `totalRows`.
   - If `materialized` keeps growing until it equals `totalRows` and never shrinks back down while scrolling, the `LazyVStack` inside the hosted `UIScrollView`/`NSScrollView` is not virtualizing — treat plan item 2.3 (manual visible-range windowing) as high priority instead of optional.
   - Revert `enabled` to `false` before shipping; this instrumentation is for profiling only.

10. Undo / Redo (Fase 1.1).
    - macOS: with a cell selected/edited, press ⌘Z — the "Cuaderno" menu bar item shows "Deshacer cambio"; verify the value reverts and a toast confirms it. Press ⇧⌘Z to redo.
    - macOS: repeat while the focus is inside the notebook search field — the shortcut should still reach the notebook (not get swallowed by the text field's own undo).
    - macOS: switch to a different module (e.g. Asistencia) and press ⌘Z — a banner should say undo is only available in Cuaderno, and nothing in the notebook should change.
    - iPad with a hardware keyboard: same ⌘Z/⇧⌘Z checks, plus the "Más" overflow menu should show enabled "Deshacer"/"Rehacer" buttons reflecting stack state.
    - Make a new edit right after an undo: the redo stack should clear (redo button disables again).

11. Numeric cell text selection vs. drag-to-adjust (Fase 1.3).
    - macOS only: click-drag across the text of a free-typed numeric cell (the `TextField` variant, not the popover-keyboard one) and confirm it selects text instead of changing the value.
    - iPad/iPhone: confirm the vertical drag-to-adjust gesture on numeric010/time/distance/repetition cells still works as before.

12. Resize divider cursor (Fase 1.4).
    - macOS: hover the fixed-column divider, then quickly switch modules or classes while still hovering. The pointer should return to the default arrow, never stay stuck as a resize cursor.

13. Filtered empty state (Fase 1.6).
    - With a class that has students, type a search term that matches nobody: headers and Media column stay visible, and a "Sin resultados con los filtros actuales" card appears with a "Limpiar filtros" button that restores the full roster in one tap.
    - Select a work group with a search term active that returns zero students: same inline card.
    - Open a class with literally no students enrolled: the original full-screen "Sin alumnado en esta clase" state still appears (no card, no header row).

14. Cell save feedback (Fase 1.2).
    - Type in a free-text/numeric cell and stop typing without navigating away: the cell shows "Guardando" for about half a second (matching the 500ms debounce in `NotebookViewModel.saveColumnGrade`), then "Sincronizado" briefly, then returns to idle.
    - Tap a check/ordinal/attendance cell (always-immediate saves): it should go straight to "Sincronizado" with no visible "Guardando" flash.

15. Filter/view menu consistency (Fase 1.7).
    - On iPhone/compact width, open the compact command bar's "Filtros" menu and note the "Situación de aprendizaje" clear-filter label, then tap the navigation title to open the title menu and check the same label under "Situación de aprendizaje" — both should read "Sin filtrar".
    - Same check for "Grupo completo" in both places.
    - Open the compact command bar's "Vista" menu and the title menu's "Vista" section — both should show "Rejilla"/"Plano" with matching icons, and switching to "Plano" while in review/reading focus mode should stay disabled in both.

16. Row hover cost (Fase 2.1, macOS).
    - Add `Self._printChanges()` (temporary) to `NotebookGridContainer.body`, or watch Instruments' SwiftUI view-body-count. Move the mouse across ~40 rows.
    - Expected: `NotebookGridContainer.body` does not re-run on hover at all; only the two affected `NotebookHoverableRow` leaves (previous + new) update, across all 3 panes (≤6 row evaluations per hover transition, not 3× the full row count).
    - Hover should still visually highlight the same row across the fixed, scroll, and trailing panes simultaneously.

17. Frozen-pane elasticity (Fase 2.2).
    - iPad: fling the center grid past the top/bottom of the list. The fixed (student) and trailing (Media) columns should hard-stop at the same offset as the center pane, without an independent rubber-band bounce of their own.
    - macOS: same check with a two-finger scroll past content bounds on a trackpad.
    - Confirm you can still scroll vertically by dragging/scrolling directly on the fixed student column and the Media column (this was intentionally preserved, not disabled).
