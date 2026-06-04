# P2 Component Design

## Scope

Files inspected: `MacPremiumComponents.swift`, `MacStudentsView.swift`, `MacAttendanceView.swift`, `MacRubricsView.swift`, related macOS module patterns.

## Findings

1. Reusable module headers are consistent and restrained, with clear primary/secondary action slots (`MacPremiumComponents.swift:84-151`). This should remain the core pattern.
2. Filter bars are visually heavy because every filter group becomes a full card with border (`MacPremiumComponents.swift:172-187`). In dense macOS screens, this can overstate controls relative to content.
3. Table containers include a useful loading overlay, but the overlay appears/disappears abruptly and may feel like a badge rather than a progress affordance (`MacPremiumComponents.swift:190-220`).
4. Students uses `HSplitView` with filters, list, and optional inspector (`MacStudentsView.swift:91-115`). The layout is powerful, but the filter rail can become a competing sidebar inside the app sidebar.
5. Attendance has a strong operational header and filter bar (`MacAttendanceView.swift:218-315`), but filters mix mode, class, date, session, and advanced filtering in one horizontal strip. The primary daily task is “mark attendance”; controls can be grouped more clearly around that.
6. Rubrics uses a familiar master-detail layout (`MacRubricsView.swift:118-123`), but several sheets are large modal workspaces (`MacRubricsView.swift:196-249`). The transition from browsing to building/evaluating can feel like a hard mode switch.

## Recommended Improvements

- Introduce a lighter `MacPremiumControlStrip` variant for filters: same spacing and token use, less border/chrome than content cards.
- Add consistent operation-state motion for `MacPremiumOperationState`: short opacity/scale transition for loading/saved/failed pills, respecting reduced motion.
- For Students, make the filter rail collapsible or visually quieter in content presentation; keep the inspector as the dominant secondary column.
- For Attendance, separate “daily mode controls” from “filtering” visually: mode/date/class stay visible, search/status filters remain in the popover button.
- For Rubrics, prefer inspector/detail expansion for preview and assignment context when possible; reserve full sheets for builder and bulk evaluation.

## Risk

Do not replace native `HSplitView`/`NavigationSplitView` patterns. The issue is hierarchy and chrome density, not structural correctness.
