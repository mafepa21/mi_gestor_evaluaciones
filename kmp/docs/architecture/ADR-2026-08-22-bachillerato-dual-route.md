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

## Narrative ledger extension

Teacher-authored documents may use a readable ledger instead of the QUICK VIEW /
ACTIVITY DETAILS shape. The importer detects the same two route markers before
the generic weekly parser, then treats each `BLOQUE CORTO` or `BLOQUE LARGO` as
one plan and each `U##` heading as structured operational content. The importer
compacts each narrative block into at most four operational moments — explanation,
activation, main activity and optional reflection — while keeping adaptations
inside the main activity. A
`LONG_PART_1` block is a single 35–74 minute opportunity: it is not expanded to
two timetable periods and it is not treated as a 30-minute `SHORT`.

The payload keeps image references as DOCX relationship IDs plus the Word
`title`, `descr` and nearby paragraph context. The source DOCX remains the
binary source of truth; the detail renderer resolves those IDs locally, avoids
duplicating images already rendered in the selected route, and supplements the
selected route when the source document anchors a shared or unit image only in
the other route. References are retained both at plan level for the full Annex
and at activity level so related images are visible in the Activity tab.

## Consequences

- One DOCX supports both mirror timetables and any valid midweek start.
- Route-aware fiche documents preserve different curricular orderings without
  losing the route-specific pedagogical development.
- The UI distinguishes imported canonical blocks from classes to schedule.
- Scheduling stores only the plans selected by the actual chronological route.
- Imported legacy sequences preserve their previous behavior.
- Narrative ledgers preserve teacher wording, operational content and embedded
  visuals without requiring authors to reformat their existing DOCX; the planner
  shows a compact four-moment activity script and keeps the full source in Annex.

## Verification

Automated coverage includes short-first and long-first starts, midweek starts,
holiday-like gaps, 15/20/21-minute break boundaries, odd three-class sequences,
legacy fallback, backward-compatible payload decoding, narrative ledgers,
partial long blocks and DOCX image relationship metadata.
