# 0018. The events table is paged

- **Status:** accepted
- **Date:** 2026-08-24
- **Partially supersedes:** [0017](0017-no-row-counts-and-no-query-limit.md) (the count and the
  unbounded query; the status bar stays removed)

## Context

ADR 0017 removed both `Count` overloads and the thousand-row query limit, on the argument that the
limit, the counts and the status line were one mechanism serving a requirement the statement never
made. `Query` returns every matching row, and `TEventTable` holds all of them.

The cost that decision accepted is now the subject:

> memory and refresh cost now scale with the number of stored events rather than being capped

Concretely, `Query` materialises the whole result set on every refresh. `RowToEvent` parses three
values per row — a UUID, an ISO timestamp and a severity name — so a hundred thousand matches is
several hundred thousand string parses, on the UI thread, followed by a `TList` that is copied again
by `ToArray`. The statement's own rate of one event per second keeps this far away, but the ceiling
is implicit rather than absent.

Two things about the existing design shape the answer.

**The control is already virtual.** ADR 0008 chose `OwnerData` mode: `TListView` holds no items, it
asks for the ones it is about to paint through `OnData`. Rendering was never the bottleneck. What
costs is everything that happens before the control is asked — the query, the parsing, the array. So
the problem to solve is in the repository and in `TEventTable`, not in the control.

**A cap is only dishonest if it hides something.** ADR 0008's objection to a silent limit was that
"the window silently implies that what is visible is everything", and ADR 0017 removed the limit
rather than keep explaining it. Both of the bounded designs below avoid that objection in the same
way: they state what they are showing and let the user reach the rest. That is what makes a bounded
query possible again without bringing the status line back with it.

There is also a force that only appears once the generator is running. New events sort to the top of
`order by time desc`, so every stored index shifts on every insert. Any design that gives the user a
position inside a large result has to answer what happens to that position a second later.

## Options

### Option 1 — keep ADR 0017: fetch everything, every refresh

- Pro: no change, and the simplest possible `TEventTable`.
- Con: memory and parse cost scale with the table; the UI thread does the work.

### Option 2 — pages, with navigation controls

`Previous` / `Next` and a "page 3 of 214" label. `TEventTable` holds one page.

- Pro: the smallest bounded design. `ProvideItem` stays a plain array read, and nothing has to
  coordinate with the paint cycle.
- Pro: every navigation is exactly one query of a known size — no sequence of deep-offset queries
  behind a dragged scrollbar.
- Pro: the page number answers "how much is there" without a separate count display, which is the
  information ADR 0008 wanted the status line to carry.
- Pro: stable while the table grows. A refresh keeps the user on page N, and the content shifts by at
  most a page boundary.
- Pro: sequential navigation leaves keyset paging (`where time < :last`) available later, which is
  indifferent to depth.
- Con: new controls the statement does not ask for, which is what CLAUDE.md's rule against features
  "just in case" is about.
- Con: a log is more naturally scrolled than paged, and rows either side of a page boundary cannot be
  seen together.

### Option 3 — windowed fetch behind the existing scrollbar

`Items.Count` is the total number of matches, so the scrollbar spans the whole result. A window of
rows around the visible range is cached, loaded in `OnDataHint`, and `OnData` reads from it.

- Pro: no new controls, and the interaction is unchanged.
- Pro: rows either side of any boundary are visible together, because there are no boundaries.
- Con: `OnData` can be asked for an item the hint did not cover, and it runs during painting, so that
  path needs a fallback that cannot raise — an edge case that shows as a blank row.
- Con: dragging the scrollbar deep into a filtered result issues `OFFSET` queries that re-evaluate
  the filter for every skipped row.
- Con: worst under a growing table. A user scrolled into the middle of three hundred thousand rows
  has every index shift underneath them on each refresh, and there is no page number to make that
  comprehensible.

### Option 4 — keyset paging behind the scrollbar

Replace `OFFSET` with `where time < :last_seen`.

- Pro: constant cost at any depth.
- Con: it answers "the next N after this row", not "N rows starting at index 40 000", which is what a
  scrollbar asks. It fits option 2, not option 3.

## Decision

Option 2. `IEventRepository` trades `Query` for two methods:

```pascal
function Count(const AFilter: TEventFilter): Int64;
function Page(const AFilter: TEventFilter; AOffset, ALimit: Integer): TArray<TLogEvent>;
```

`Page` adds `limit :limit offset :offset` to the statement `Query` already built. `Count` is a single
method rather than the overloaded pair ADR 0017 removed: `WhereClause` returns an empty string for an
unfiltered filter, so `Count(TEventFilter.Unfiltered)` is `select count(*) from events` and the two
cases need no separate entry point.

`TEventTable` gains `FPage`, `FPageCount` and `FTotal`, and owns the three controls that show them —
the same shape as `TFilterBar`, which owns its edit and its combo (ADR 0012). The page size is the
user's, chosen from a drop-down of 50, 100, 200 and 500 and defaulting to 200 — a fixed size would
have been one less control, but the right number depends on the screen and on whether the reader is
scanning or looking for one event, which is not something this application can guess. Changing it
keeps the reader in place rather than returning to the first page: the row at the top of the current
page is located again under the new size, so the boundaries move and the reading position does not.
Changing the filter resets to the first page; a refresh clamps the current page to the last one that
still exists, so deleting or filtering cannot leave the view past the end.

Why option 2 won over option 1: the ceiling ADR 0017 made implicit becomes explicit again, and the
page number states it rather than hiding it.

Why it won over option 3: option 3 is the better interaction for a static log and the worse one for a
growing one. The generator is not an edge case here — it is a required feature, it runs for as long
as the user leaves it on, and it shifts every index on every insert. A page number survives that; a
scroll position inside a very long virtual list does not. Option 3 also has to run its query from
inside the paint cycle's cache hint, with a fallback for the items the hint misses, and that
fallback can only degrade to a blank row. Option 2 has no such path: `OnData` reads an array that was
already loaded.

The cost accepted is the visible one. Two buttons and a label are controls the statement does not
ask for, and paging is not how one usually reads a log. That is the price of a bounded query with no
hidden state, and it is paid once, in one panel at the bottom of the window.

## Consequences

Easier: memory and refresh cost, both now fixed at a page regardless of how many events match.
`TEventTable` stayed simple — one array, one index into it, no cache to invalidate.

Harder, and worth watching:

- **`Count` is the new hot path.** It runs on every refresh, and under a text filter it is a full scan
  with `LIKE` on every row (ADR 0006 explains why no index can serve it). The generator's refreshes
  are already throttled — `TEventActions.Poll` only signals a change when `TakeStale` says events
  arrived — so this is about one count per second while generating, not one per timer tick. It is
  still the most expensive thing the application does per refresh.
- **`OFFSET` is linear.** Page 1500 of a filtered result re-evaluates the filter for every skipped
  row. Navigation is sequential, so keyset paging is the answer if that is ever felt — it needs the
  timestamp of the last row on the current page and no other state.
- **A page boundary is a real boundary.** Two events a second apart can land on different pages, and
  nothing shows them together.

`ListView_EnsureVisible` scrolls a new page back to the top; without it page 2 opens at whatever
offset page 1 was left at. It is called instead of `Items[0].MakeVisible` because `TListItems.GetItem`
returns `nil` in `OwnerData` mode when the control has no handle yet, and `Refresh` can run before the
form is shown.

To revisit if the assumptions change: a filtered result large enough that the count itself is felt.
The answer then is to stop recounting on every refresh — the count only changes when events are
inserted or deleted, and both paths already run through `TEventActions`.
