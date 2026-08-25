# 0017. No row counts and no query limit

- **Status:** accepted; the count and the unbounded query are superseded by
  [0018](0018-paged-events-table.md), which restores both in a bounded form. The status bar stays
  removed.
- **Date:** 2026-08-24
- **Partially supersedes:** [0008](0008-listview-for-the-events-table.md) (the status line),
  [0010](0010-search-and-severity-filter.md) (the match count)

## Context

`IEventRepository` carried two `Count` overloads and `Query` capped its result at
`DefaultQueryLimit`, a thousand rows. The three fed each other: SQLite lifted the ceiling on how many
events can exist, the limit kept an unbounded table from being copied into the view, and the counts
existed so the window could say what the limit hid. ADR 0008 put it plainly — without a status line
"the window silently implies that what is visible is everything".

Read against the statement, none of the three is required. The assignment asks for a table showing
every attribute, robust JSON import, search by text, filtering by severity, and a background
generator. It does not ask for a status bar, a row count, or a cap on what the table shows — nor for
persistence at all, which is this project's own decision (ADR 0004).

The argument for removal is not performance. `Count(AFilter)` with search text is a full scan
evaluating `LIKE` on every row, and it runs inside `TEventTable.Refresh` — on every keystroke and on
a 250 ms timer while the generator runs. Against the volume the statement defines, that is
microseconds. The argument is that three coupled mechanisms exist to manage a problem the assignment
never poses.

The three cannot be separated. Removing the counts while keeping the limit is the one combination
that must not ship: the table would show a thousand rows out of any number and say nothing about it.

## Options

### Option 1 — keep all three

- Pro: the status line states exactly what is shown against what is stored, which is real information.
- Con: three mechanisms, one repository method pair, one status-bar formatter with four cases and a
  scan-with-`LIKE` on a timer, all serving a requirement that does not exist.

### Option 2 — drop the filtered count only

Ask for `LIMIT + 1` rows and treat the extra row as the truncation flag.

- Pro: removes the only expensive query at no cost in honesty; ADR 0010 already named it as the
  fallback.
- Con: keeps the limit and the status line, so the machinery survives in a slightly cheaper form.

### Option 3 — drop the counts and the limit together

- Pro: the view can no longer be out of step with the store, because it is the store — nothing is
  hidden, so nothing has to be reported.
- Pro: `IEventRepository` drops to four methods, and `TEventTable` to holding an array.
- Pro: closest to the statement, which asks for a table of events and not a report about it.
- Con: `Query` now copies the whole matching set on every refresh, unbounded by construction where it
  used to be capped.
- Con: the `Clear` confirmation loses its count, and the button can no longer disable itself.

## Decision

Option 3. Both `Count` overloads, `DefaultQueryLimit` and the `ALimit` parameter are gone; `Query`
runs `select … order by time desc` with no cap.

Why it won over option 1: the statement is the source of truth for scope, and `CLAUDE.md` forbids
adding features "just in case". A status line reporting counts is a feature, and the limit and the
counts exist only to support it. Removing the three together removes a whole axis of the design
rather than trimming it.

Why it won over option 2: option 2 is the better answer to "make this cheaper", which turned out not
to be the question. It keeps the limit, and therefore the obligation to explain the limit; it just
explains it less precisely. If the limit is not required, the cheapest correct version of it is no
limit.

Two consequences had to be settled rather than inherited:

- **The `Clear` confirmation** now reads "Delete all stored events?" instead of naming a count, the
  button is enabled once the repository is attached, and `DeleteAll` on an empty table is a no-op.
  The cost is a confirmation that can appear when there is nothing to delete.
- **The status bar goes too.** Counting was not its only job — `EnterDegradedMode` also wrote the
  database-unavailable message there. Keeping a control whose only remaining purpose is one error
  string, and which is empty every other second, trades one kind of clutter for another. The message
  joins the modal dialog `EnterDegradedMode` already raises. What is lost is persistence: after the
  dialog is dismissed, the reason is gone from the screen. The window is not silent about the failure
  though — import, clear, generate and the filters are all disabled, so it reads as unusable rather
  than as empty.

## Consequences

Memory and refresh cost now scale with the number of stored events rather than being capped. One
event per second is roughly 29,000 rows across an eight-hour run, and each refresh copies all of them
into a fresh array, four times a second while generating. Nothing in the assignment's scenario gets
near a problem, but the ceiling that used to be explicit is now implicit — which is what
[ADR 0018](0018-paged-events-table.md) goes on to address.
