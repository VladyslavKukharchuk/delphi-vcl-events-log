# 0008. A virtual TListView for the events table

- **Status:** accepted
- **Date:** 2026-08-21

## Context

The statement requires a main window that shows the events in a table with every attribute visible.
What that table is built from has to be decided once, because the control's model decides how the rest
of the UI is written.

Forces at play:

- The row count changes constantly. The generator appends an event every second, and every filter
  change replaces the whole result set (decision D8).
- What the table shows is a `TArray<TLogEvent>` produced by a query — already ordered, already
  filtered, already capped. The control does not need to sort, filter or store anything.
- ADR 0001 keeps controls inside `src/UI`, and ADR 0004 forbids a `TDataSet` from leaving
  `src/Repository`. Anything that binds a control directly to a dataset is out by construction.
- The identifier is a full UUID, 36 characters, and the statement asks for every attribute to be
  displayed.

## Options

### Option 1 — `TListView` in `vsReport` with `OwnerData = True`

Virtual mode: the control holds no items and asks for the contents of a row when it needs to paint it.

- Pro: the array stays the single copy of the data. Replacing it and setting `Items.Count` is the whole
  refresh; nothing is added, removed or synchronised item by item.
- Pro: repainting costs the visible rows, not the result set, so a thousand rows behave like ten.
- Pro: native report-style columns, header, row selection — the look users expect from a log window,
  free.
- Con: `OnData` runs during painting, so it has to be cheap and must never raise.
- Con: no cell-level formatting without owner drawing.

### Option 2 — `TListView` with real items

The same control, filling `Items` on every refresh.

- Pro: no virtual-mode rules to respect.
- Con: every refresh builds and frees a thousand `TListItem` objects, and a refresh happens once a
  second. That is churn bought for nothing.
- Con: the data then exists twice — in the array and in the control — and the two can disagree.

### Option 3 — `TStringGrid`

- Pro: full control over cells and drawing.
- Con: stores its contents as strings, so the data exists twice and everything becomes text early.
- Con: no column header behaviour, no row selection, no sizing — all of it hand-built.

### Option 4 — `TDrawGrid`

- Pro: draws only visible cells, like virtual mode, with complete freedom.
- Con: every cell is painted by hand. Freedom nothing here needs, paid for in code.

### Option 5 — `TDBGrid` bound to a `TDataSource`

- Pro: the classic Delphi answer; almost no code.
- Con: requires a live dataset in front of the control, which ADR 0001 rejected and ADR 0004 forbids.
  It would put the query in the form and make the layering decorative.

## Decision

Option 1 — `TListView`, `ViewStyle = vsReport`, `OwnerData = True`, with `OnData` reading the array the
last query produced.

Why it won: the control's model matches what the application already has. The array is ordered,
filtered and capped before it arrives, so a control that stores and manages its own items would be
duplicating a job already done — and duplicating the data along with it. Virtual mode makes the array
the single source of truth, and a refresh becomes two statements: assign the array, set the count.

Option 2 loses on churn that happens once a second for no benefit. Options 3 and 4 buy drawing freedom
that a four-column log window does not need, and pay for it in code that has to be maintained. Option
5 is the shape this project has twice decided against.

**The identifier is shown in full** (decision D7). A truncated UUID would be shorter but it would also
be a value the user cannot copy, compare or paste into a query, and the statement asks for the
attributes to be displayed rather than hinted at. The cost is a 250-pixel column and a window wide
enough to hold it, which is why the form is 1000 pixels rather than the default 624.

**The window states when the view is capped.** D8 limits the query, so the table can show fewer rows
than the database holds. A status line reading "showing the 1000 most recent of 4318 events" is not a
convenience — without it the window silently implies that what is visible is everything.

## Consequences

Easier: refreshing, because there is nothing to keep in step; and growing the table, because a new
column is a column definition plus one line in `OnData`.

Harder: `OnData` is called during painting, so it must stay cheap and must not raise. It reads an array
by index and formats four values, and it guards its index rather than trusting it.

To revisit if the assumptions change: sorting by clicking a column header, which in virtual mode means
re-querying with a different `order by` rather than sorting the control; or per-row colouring by
severity, which would need `OwnerDraw` and is the first thing this decision makes awkward.

The consequence to watch: `Items.Count` and `Length(FVisible)` have to move together. They are assigned
on adjacent lines in `RefreshView` for exactly that reason, and any future path that replaces the array
elsewhere would be a way to make the control ask for a row that no longer exists.
