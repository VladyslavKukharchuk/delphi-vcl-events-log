# 0018. The events table is paged, and the status bar is gone

- **Status:** accepted
- **Date:** 2026-08-24
- **Partially supersedes:** [0008](0008-listview-for-the-events-table.md) (the status line),
  [0010](0010-search-and-severity-filter.md) (the match count as a sentence under the table)

## Context

The table was unbounded in one direction and over-explained in the other. `Query` returned every
matching row and `TEventTable` held all of them, so `RowToEvent` parsed three values per row on every
refresh — a hundred thousand matches is several hundred thousand string parses on the UI thread, four
times a second while the generator runs. Meanwhile the window carried a status bar reporting matches
against the total, which ADR 0008 had asked for on the grounds that without it "the window silently
implies that what is visible is everything".

Read against the statement, neither is required. The assignment asks for a table showing every
attribute, robust JSON import, search by text, filtering by severity, and a background generator. It
does not ask for a status bar, a row count, or a cap on what the table shows.

Three things shape the answer. **The control is already virtual** — ADR 0008 chose `OwnerData` mode,
so what costs is everything before the control is asked, which puts the problem in the repository and
in `TEventTable`. **A cap is only dishonest if it hides something**, so a bounded design that states
what it is showing answers ADR 0008's objection without a status line. **The generator moves every
index** — new events sort to the top of `order by time desc`, so any design that gives the user a
position inside a large result has to answer what happens to that position a second later.

## Options

### Option 1 — fetch everything, every refresh

- Pro: no change, and the simplest possible `TEventTable`.
- Con: memory and parse cost scale with the table, on the UI thread.

### Option 2 — pages, with navigation controls

`Previous` / `Next` and a "page 3 of 214" label. `TEventTable` holds one page.

- Pro: the smallest bounded design — `ProvideItem` stays a plain array read with nothing to
  coordinate with the paint cycle, and every navigation is one query of a known size.
- Pro: the page number states the size of the result, which is the information the status line
  existed to carry.
- Pro: stable while the table grows — a refresh keeps the user on page N, and the content shifts by
  at most a page boundary.
- Con: new controls the statement does not ask for, and a log is more naturally scrolled than paged —
  rows either side of a boundary cannot be seen together.

### Option 3 — windowed fetch behind the existing scrollbar

`Items.Count` is the total, and a window of rows around the visible range is cached in `OnDataHint`.

- Pro: no new controls, the interaction is unchanged, and there are no boundaries.
- Con: `OnData` can be asked for an item the hint did not cover, and it runs during painting, so that
  path needs a fallback that cannot raise — an edge case that shows as a blank row.
- Con: dragging deep issues `OFFSET` queries that re-evaluate the filter for every skipped row, and
  keyset paging fixes the cost but not the shape a scrollbar needs — "the next N after this row".
- Con: worst under a growing table — every index shifts underneath a scrolled reader on each refresh,
  with no page number to make that comprehensible.

## Decision

Option 2, and the status bar goes with it. `IEventRepository` trades `Query` for two methods:

```pascal
function Count(const AFilter: TEventFilter): Int64;
function Page(const AFilter: TEventFilter; AOffset, ALimit: Integer): TArray<TLogEvent>;
```

`Page` adds `limit :limit offset :offset` to the statement `Query` already built, and one key to its
ordering: `order by time desc, id desc`. Each page is its own query, free to sequence equal
timestamps differently from the last one, so without a unique final key an event stored in the same
millisecond as its neighbour shows up on two pages or on neither — and a JSON import, whose records
often share a timestamp, is where that happens rather than in theory. No index covers the pair, since
ADR 0006 indexed `time` alone, so SQLite sorts the ties itself, free at this size. `Count` is one
method rather than a filtered-and-unfiltered pair: `WhereClause` returns an empty string for an
unfiltered filter, so the two cases need no separate entry point.

`TEventTable` gains `FPage`, `FPageCount` and `FTotal`, and owns the controls that show them — the
same shape as `TFilterBar` (ADR 0012). The page size is the user's, chosen from 50, 100, 200 and 500
and defaulting to 200, because the right number depends on the screen and on whether the reader is
scanning or looking for one event; changing it keeps the reader in place rather than returning to the
first page. Changing the filter resets to page one; a refresh clamps the current page to the last one
that still exists.

Why option 2 won over option 1: it makes the ceiling explicit, and the page number states it rather
than hiding it. Why it won over option 3: option 3 is the better interaction for a static log and the
worse one for a growing one. The generator is not an edge case here — it is a required feature and it
shifts every index on every insert. A page number survives that; a scroll position inside a very long
virtual list does not, and option 3 has to fetch from inside the paint cycle to keep it.

**The status bar is removed rather than rewired.** Paging already says what it was asked to say, and
"page 3 of 214 · 4318 events" belongs with the controls that change it, not in a strip at the bottom.
Counting was not its only job, though: `EnterDegradedMode` also wrote the database-unavailable message
there, and a control whose one remaining purpose is an error string — empty every other second the
application runs — trades one kind of clutter for another. That message joins the modal dialog
`EnterDegradedMode` already raises. What is lost is persistence, since the reason leaves the screen
with the dialog; what remains is that import, clear, generate and the filters are all disabled, so
the window reads as unusable rather than as empty (ADR 0013). The `Clear` confirmation stops naming a
count for the same reason and simply asks.

The cost accepted is the visible one: two buttons and a label the statement does not ask for, and
paging is not how one usually reads a log. That is the price of a bounded query with no hidden state.

## Consequences

**`Count` is the new hot path.** It runs on every refresh, and under a text filter it is a full scan
with `LIKE` on every row (ADR 0006 explains why no index can serve it). The generator's refreshes are
throttled, so this is about one count per second while generating — still the most expensive thing
the application does per refresh. **`OFFSET` is linear**, so page 1500 of a filtered result
re-evaluates the filter for every skipped row; navigation is sequential, so keyset paging is the
answer if that is ever felt. And **a page boundary is a real boundary** — two events a second apart
can land on different pages.

`ListView_EnsureVisible` scrolls a new page back to the top; it is called instead of
`Items[0].MakeVisible` because `TListItems.GetItem` returns `nil` in `OwnerData` mode when the
control has no handle yet, and `Refresh` can run before the form is shown.
