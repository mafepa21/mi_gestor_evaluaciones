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
