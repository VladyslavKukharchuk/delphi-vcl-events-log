# 0017. No row counts and no query limit

- **Status:** accepted; the count and the unbounded query are superseded by
  [0018](0018-paged-events-table.md), which restores both in a bounded form. The
  status bar stays removed.
- **Date:** 2026-08-24
- **Partially supersedes:** [0008](0008-listview-for-the-events-table.md) (the status line),
  [0010](0010-search-and-severity-filter.md) (the match count)

## Context

`IEventRepository` carried two `Count` overloads — one over the whole table, one over the same
`WhereClause` the view uses — and `Query` capped its result at `DefaultQueryLimit`, a thousand rows.
The three fed each other: ADR 0004 replaced an in-memory list with SQLite and lifted the ceiling on
how many events can exist; the limit kept an unbounded table from being copied into the view; and the
counts existed so the window could say what the limit hid. ADR 0008 put it plainly — without a status
line "the window silently implies that what is visible is everything".

Read against the statement, none of the three is required. The assignment asks for a table showing
every attribute, JSON import robust to bad data, search by text, filtering by severity, and a
background generator producing one event a second. It does not ask for a status bar, a row count, or
a cap on what the table shows. It does not ask for persistence at all — it says events are added to
the general list, and SQLite is this project's own decision (ADR 0004).

What the counts cost is uneven, and worth stating precisely rather than as a general worry:

- `Count` over the whole table is `select count(*) from events`. SQLite keeps no row counter, so this
  is a scan, but with no `where` clause it walks the smallest index rather than the table.
- `Count(AFilter)` with search text is `count(*) ... where text like '%…%'`. A leading wildcard rules
  out any index (ADR 0006 says so and declines to add one), so this is a full scan evaluating `LIKE`
  on every row.
- Both run inside `TEventTable.Refresh`, which fires on every filter keystroke and on a 250 ms timer
  while the generator runs — eight to twelve statements a second.

Against the volume the statement itself defines, one event per second, that is microseconds of work,
and ADR 0010 already recorded "a log large enough that counting hurts" as the condition for
revisiting. So the argument for removal is not performance. It is that three coupled mechanisms —
limit, count, status line — exist to manage a problem the assignment never poses, and the simplest
honest version of this application does not have them.

The three cannot be separated. Removing the counts while keeping the limit is the one combination
that must not ship: the table would show a thousand rows out of any number and say nothing about it.

## Options

### Option 1 — keep all three

- Pro: the status line states exactly what is shown against what is stored, which is real information.
- Pro: no change, and two ADRs stay as written.
- Con: three mechanisms, one repository method pair, one status-bar formatter with four cases and a
  scan-with-`LIKE` on a timer, all serving a requirement that does not exist.

### Option 2 — drop the filtered count only, keep `Count` and the limit

Ask for `LIMIT + 1` rows, show the first `LIMIT`, and treat the extra row as the truncation flag.

- Pro: removes the only expensive query at no cost in honesty.
- Pro: ADR 0010 already named this as the fallback.
- Con: keeps the limit and the status line, so the machinery survives in a slightly cheaper form.
- Con: the status line loses the exact number of matches while still needing four cases.

### Option 3 — drop the counts and the limit together

`Query` returns every matching row ordered by time, `IEventRepository` loses both `Count` overloads
and `DefaultQueryLimit`, and the table stops summarising itself.

- Pro: the view can no longer be out of step with the store, because it is the store — nothing is
  hidden, so nothing has to be reported.
- Pro: `IEventRepository` drops to four methods, and `TEventTable` drops to holding an array and
  filling list items.
- Pro: closest to the statement, which asks for a table of events and not for a report about it.
- Con: `Query` now copies the whole matching set on every refresh, including every 250 ms tick while
  the generator runs. At the rate the statement specifies this stays small for hours, but it is
  unbounded by construction where it used to be capped at a thousand rows.
- Con: the `Clear` confirmation loses its count, and the button can no longer disable itself when
  nothing is stored.

## Decision

Option 3. Both `Count` overloads, `DefaultQueryLimit` and the `ALimit` parameter are gone; `Query`
runs `select … order by time desc` with no cap; `TEventTable` keeps only the array and the list view.

Why it won over option 1: the statement is the source of truth for scope, and CLAUDE.md forbids
adding features "just in case". A status line reporting counts is a feature, and the limit and the
counts exist only to support it. Removing the three together removes a whole axis of the design
rather than trimming it.

Why it won over option 2: option 2 is the better answer to "make this cheaper", which turned out not
to be the question. It keeps the limit, and therefore keeps the obligation to explain the limit; it
just explains it less precisely. If the limit is not required, the cheapest correct version of it is
no limit.

Two consequences of removing the count had to be settled rather than inherited:

- **The `Clear` confirmation.** It read "Delete all 4318 stored events?" and the action returned early
  when the count was zero. It now reads "Delete all stored events?", the button is enabled once the
  repository is attached, and `DeleteAll` on an empty table is a no-op. The cost is a confirmation
  dialog that can appear when there is nothing to delete.
- **The status bar.** Counting was not its only job: `EnterDegradedMode` also wrote the
  database-unavailable message there. Keeping a control whose only remaining purpose is one error
  string — and which is empty every other second the application runs — trades one kind of clutter
  for another, so the bar goes too. The message joins the modal dialog that `EnterDegradedMode`
  already raises: the dialog now states that the database is unavailable *and* why, where before the
  two halves were split between a dialog and a strip at the bottom of the window. What is lost is
  persistence — after the dialog is dismissed, the reason is gone from the screen. The window is not
  silent about the failure, though: import, clear, generate and the filters are all disabled, so it
  reads as unusable rather than as empty (ADR 0013).

## Consequences

Easier: the repository interface, which is now four methods with no optional parameter and no
overload; the table, which no longer formats four variants of a sentence about itself; and reasoning
about what the view shows, because it shows everything that matches.

Harder: memory and refresh cost now scale with the number of stored events rather than being capped.
One event per second is roughly 29,000 rows across an eight-hour run, and each refresh copies all of
them into a fresh array — four times a second while generating. Nothing in the assignment's scenario
gets near a problem, but the ceiling that used to be explicit is now implicit.

To revisit if the assumptions change: a log large enough that a full refresh is visible in the UI.
The answer then is not to restore the limit alone but to stop refreshing the whole view on a timer —
the generator already knows which event it produced, and appending one row is cheaper than re-reading
every row. That would be a new ADR.

The statement requires `README.md` to list what could be improved given more time. That section does
not exist yet; when it is written, the unbounded refresh belongs in it.
