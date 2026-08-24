# ADR: Canonical dual-route Bachillerato session sequences

Date: 2026-08-22

## Decision

Bachillerato learning situations are authored as one canonical document made of
weekly `LONG`/`SHORT` pairs. For the canonical weekly format, the document does
not duplicate its curriculum for groups whose timetable begins with a different
block. At scheduling time, the planner selects one of two chronological routes
from the real group timetable:

- `shortFirst`: `SHORT 1, LONG 1, SHORT 2, LONG 2, ...`
- `longFirst`: `LONG 1, SHORT 1, LONG 2, SHORT 2, ...`

The earliest compatible opportunity on or after the selected start date chooses
the route. Long opportunities may contain a legal break of up to 20 minutes.
Partial start weeks, holidays and missing opportunities are skipped without
changing the pedagogical order.

## Import contract

The weekly importer records additive, optional metadata on each draft plan:

- `cycleIndex`
- `weekKey`
- `blockRole` (`long` or `short`)
- `sequenceFormat`
- `sequenceRoute` when a route-aware fiche document is used

Older payloads remain decodable because every field is optional. Legacy
individual-session documents continue to use their existing linear projection.

## Annual counts and terminal alternatives

The annual programme is authoritative for the number of classes. A canonical
document contains `ceil(N / 2) * 2` block definitions, but the scheduler creates
exactly `N` classes. For an odd annual count, the final pair contains equivalent
`LONG` and `SHORT` terminal alternatives and schedules only the chronologically
required one. For example, SA4 contains four canonical block definitions but
creates three classes.

## Route-aware fiche exception

Some situations do not have the same curricular units in the two chronological
shapes. In that case the importer accepts a `selectable-route-fiches-v1` DOCX
with exactly two marked containers:

- `ROUTE OPTION: shortFirst`
- `ROUTE OPTION: longFirst`

Each container contains complete, independent `Session N` fiches and its own
physical-block sequence. The importer keeps both variants in the preview, but
the planner selects and persists only one route. A long route must be authored as
its own development; it is not a short route with an extension activity appended.
The selected route is inferred from the first compatible timetable block, with a
manual picker when the first opportunity is ambiguous.

## Consequences

- One DOCX supports both mirror timetables and any valid midweek start.
- Route-aware fiche documents preserve different curricular orderings without
  losing the route-specific pedagogical development.
- The UI distinguishes imported canonical blocks from classes to schedule.
- Scheduling stores only the plans selected by the actual chronological route.
- Imported legacy sequences preserve their previous behavior.

## Verification

Automated coverage includes short-first and long-first starts, midweek starts,
holiday-like gaps, 15/20/21-minute break boundaries, odd three-class sequences,
legacy fallback and backward-compatible payload decoding.
