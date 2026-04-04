# Findings

- Root cause for the broken rubric content copy: `duplicateConfigToClass(...)` was duplicating notebook columns without carrying over the linked evaluation in the target course, which left rubric-backed columns detached from their content.
- The iOS notebook flow did not expose any structure-duplicate action, so the feature had to be surfaced in the notebook toolbar and backed by the shared repository method.
- The bulk rubric evaluation flow already existed in shared code, but Swift export renamed `copyAssessment(...)` to `doCopyAssessment(...)`, so the iOS bridge needed to call the exported symbol directly.
- Work-group creation was vulnerable to silent replacement because the persistence layer still enforces `UNIQUE(class_id, tab_id, name)` and uses `INSERT OR REPLACE`; creating a group with a name that already exists in the same tab would replace the prior row.
- Notebook column resizing had drift between header and body because desktop and iOS were rendering the header width from `widthDp` while the cells still used a fixed width; both platforms now resolve width from the same column state.
- Long-press color selection needed to be separated from the drag gesture path, so the header now reserves a dedicated drag handle and keeps the long-press menu for color/actions.
